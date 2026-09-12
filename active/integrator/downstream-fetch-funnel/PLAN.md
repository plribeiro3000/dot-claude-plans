# PLAN — Deduplicated downstream fetch funnel (integrator)

> Repo: `integrator` (Mongoid). Spike: `../../spike/integrator-downstream-fetch-funnel/SPIKE.md`.
> Status: **merged to `develop` in PR #2403** (single commit `c2def57d`). Ships to production in the 8.5.0 line — `../integrator-develop-release-validation/PLAN.md` carries the rollout and the drained-window constraint.
> Pre-production: the normalized/unified flow this touches runs at no client yet, so there is no data to migrate and no in-flight job to straddle.

## Objective

Every distinct downstream request is fetched **once per job**, deduplicated across pages *and* across streams, from a persisted set in Mongo. Eliminates the redundant source fetch when the same rendered request is asked for by multiple pages of one stream or by multiple streams.

## Where this sits in the whole flow

The integrator now has the three layers controlled end to end, which is what makes the release coherent:

- **Upstream** — collection extraction: paginated fetch of each stream's source into `Collection` pages (`*/api_collection_extractor_consumer.rb`, `*/database_collection_extractor_consumer.rb`), carrying the pagination cursor.
- **Downstream** — enrichment extraction: per record, fetch the downstream detail the collection referenced (`*/api_enrichment_extractor_consumer.rb`, `*/database_enrichment_extractor_consumer.rb`), writing one `Enrichment` per `{job, downstream, external_id}`.
- **Cache** — the fetch funnel this plan delivers: `RequestCache`, consulted inside every enrichment consumer so a repeated rendered request hits the store instead of the source.

## The design (single path) — as shipped

A `RequestCache` collection is the persisted funnel. Each enrichment consumer routes its fetch through `RequestCache.fetch`. The `Enrichment` per-downstream record and the `Computation` counter contract are **unchanged** — the change is contained in the consumers.

### The dedup key — the rendered request, via a value object

Two fetches return the same bytes iff they are the same request: same `source` + same rendered request. `external_id` is only an input to `Stream#render_query`, so the signature is the **rendered request**, not the `external_id`.

The key is a plain value object, `app/models/request_cache_key.rb` (`RequestCacheKey`), built per the project `Variables` pattern — plain `initialize`, one public `fingerprint`:

```ruby
class RequestCacheKey
  def initialize(protocol:, verb: nil, url: nil, body: nil, query: nil)
    @protocol = protocol
    @verb = verb
    @url = url
    @body = body
    @query = query
  end

  def fingerprint
    attributes = {
      'protocol' => @protocol, 'verb' => @verb, 'url' => @url,
      'body' => @body, 'query' => @query
    }

    Digest::SHA256.hexdigest(attributes.sort.to_h.to_json)
  end
end
```

**Headers are deliberately NOT in the key** — an auth token rotates within a job, so keying on it would poison the cache (the same resource under two tokens would be two entries). The API consumer passes `protocol: :http, verb: :get, url:`; the database consumer passes `protocol: :database, query:`. The `protocol` segment keeps an HTTP url and a DB query that happen to be the same string apart.

### The model — `app/models/request_cache.rb`

Mirrors `Enrichment` (same Mongoid shape, same uploader mechanics), and owns the funnel as a class method:

```ruby
class RequestCache
  include Mongoid::Document
  include Mongoid::Timestamps

  belongs_to :job, optional: true, inverse_of: nil
  belongs_to :source, optional: true, inverse_of: nil

  mount_uploader :raw_body, RequestCacheRawBodyUploader

  field :fingerprint, type: String

  validates :fingerprint, presence: true
  validates :job_id, presence: true
  validates :source_id, presence: true

  index({ job_id: 1, source_id: 1, fingerprint: 1 }, unique: true, background: true)
  index({ created_at: 1 }, background: true)

  def self.fetch(job:, source:, key:)
    cache = find_or_initialize_by(job_id: job.id, source_id: source.id, fingerprint: key.fingerprint)
    cached_file = cache.raw_body.file

    return cache.raw_body.read.force_encoding('UTF-8') if cached_file.present? && cached_file.exists?

    response_body = yield
    local_file = File.new(cache.raw_body_path, 'w+', encoding: 'UTF-8')
    local_file.write(response_body)
    cache.raw_body = local_file
    cache.save!
    response_body
  ensure
    local_file.close if local_file
  end

  def raw_body_path
    Rails.root.join('tmp', "request_cache_raw_body_#{id}.json")
  end
end
```

Plus `app/uploaders/request_cache_raw_body_uploader.rb` mirroring `EnrichmentRawBodyUploader` (`store_dir` → `request_caches/#{model.job_id}`).

Two correctness points settled at review:

- **A failed response is never cached.** The block raises before `cache.save!`, so an `UnexpectedResponseStatusCodeException` propagates out of `fetch` (only an `ensure` closes the temp file) exactly as before the funnel existed — Sidekiq retries.
- **The duplicate-key (E11000) on `save!` is NOT rescued** — it propagates so Sidekiq retries the consumer straight into a cache hit. A concurrent racer that lost the unique-index race is redundant, not wrong.

### The consumer change (the ~50 files, api + database variants)

Each enrichment consumer builds the key and wraps its existing fetch in `RequestCache.fetch { … }`; the block body is the untouched old fetch, returning the body. The `Enrichment` write and the `increment_executions` + `done?` tail stay exactly as they are — so the count is unchanged (one increment per enqueued consumer, every path), and the transform (`enricher_consumer`) is untouched.

The api variant (the shape the ~25 api consumers follow):

```ruby
source = downstream.source
variables = Variables.new(job, source, page_size: downstream.page_size, external_id: external_id).to_h
url = Addressable::URI.encode(downstream.render_query(variables))
key = RequestCacheKey.new(protocol: :http, verb: :get, url: url)

body =
  RequestCache.fetch(job: job, source: source, key: key) do
    uri = URI(url)
    http_client = Net::HTTP.new(uri.host, uri.port)
    http_client.use_ssl = true
    http_response = http_client.get(uri.request_uri, source.authentication.authenticated_headers)

    if downstream.unexpected_response?(http_response.code)
      exception = UnexpectedResponseStatusCodeException.new(
        downstream.name, downstream_id, http_response.code, downstream.success_response_status_code
      )
      exception.response_body = http_response.body
      raise exception
    end

    http_response.body
  end
```

The database variant is the same shape with `protocol: :database, query:` and the `connect! → execute → .to_a.first.to_json` inside the block.

**On a cache hit the block never runs**, so the HTTP GET / `authenticated_headers` (api) and the `connect!` + query (database) are skipped. That skip is intended: those are producers of the fetch, not side effects other code depends on, and the first unique request of each source is always a miss, so headers/connection are still exercised there.

## The cleanup subsystem (as shipped)

The persisted funnel needs eviction. A Mongo TTL index was rejected: a TTL deletion does **not** fire the CarrierWave `after_destroy` callback, so it would drop the Mongo document and orphan the S3 blob. Instead the `created_at` index is plain, and an explicit producer/consumer fanout evicts old entries with `destroy`, so the blob is removed by the callback.

- `app/workers/request_cache/producer.rb` — pages the oldest entries past the retention window (`created_at < 1.week.ago`, `limit(10_000)`), fans out one consumer per id via `push_bulk`, re-enqueues itself, and hands off to `Resource::Producer` (cold storage) only when it finds nothing.
- `app/workers/request_cache/consumer.rb` — `RequestCache.find(id)` then `request_cache.with(write: { w: :majority }, &:destroy)`; the CarrierWave `after_destroy` deletes the S3 blob. Matches the sibling `Resource::Consumer` exactly (topology, `CONNECTION_ERRORS` rescue, `increment_executions` → `done?` → enqueue-next).
- Wiring: `IntegrationReport::Consumer` enqueues `RequestCache::Producer` (was `Resource::Producer`) after the email + `release_lock`, so cleanup runs as a stage **before** cold storage and always advances to it.
- Queue: both workers run on the `:request_cache` Sidekiq queue (registered in `config/sidekiq.yml`), not `:cold_storage` — the cache eviction is its own concern.

**Accepted trade-off (engineer's call, PR #2403):** the consumer is destroy-only and uses `.find`, matching the sibling. If a fog/S3 error fires inside the `after_destroy` blob removal, the Mongo row is already gone, so that blob orphans and the retry (`.find` raises `DocumentNotFound`) stalls that job's cleanup stage. This is the same S3-failure risk the rest of the codebase already accepts (`Resource::Consumer` propagates S3 errors the same way), on a rare transient error over week-old records. A guard was considered and declined to keep the sibling pattern; revisit only if orphaned blobs are observed.

## What is deliberately NOT done — producer-side manifest

The alternative is deduplicating the whole request set at the producer (build the unique rendered-request set first, enqueue once per unique entry). Rejected: it re-shapes the `Computation` accounting (queue no longer counts one-per-downstream) and forces the transform to read by request signature instead of by `downstream_id` — a far larger blast radius for the same fetch-dedup outcome the consumer-side funnel already delivers. The consumer-side funnel keeps both contracts intact.

## Invariants preserved (the correctness argument)

- **Computation** — every enqueued consumer still calls `increment_executions` exactly once, on both the hit and the miss branch. `done?` balance is identical to before.
- **Transform** — `enricher_consumer` still finds its per-downstream `Enrichment`; nothing about its read changes.
- **Concurrent race** — two consumers with the same signature racing: both miss, both fetch, both upsert the `RequestCache` (loser E11000 → propagates → Sidekiq retry → hit), each writes its own `Enrichment`. No stall, no double count. The unique index is the backstop; the funnel cuts the sequential (cross-page / cross-stream) case, which is the common one.
- **Storage** — the `Enrichment` body is still written per downstream (kept so the transform is untouched); the funnel saves the *fetch*, not the storage. Storage duplication is cheap S3; the fetch (client API call / customer DB query) is the expensive thing removed.

## Scope — delivered in PR #2403

- 1 model (`RequestCache`) + 1 key value object (`RequestCacheKey`) + 1 uploader.
- 1 cleanup producer + 1 cleanup consumer on the `:request_cache` queue; the queue registered in `config/sidekiq.yml`; `IntegrationReport::Consumer` rewired to enqueue it before cold storage.
- ~50 enrichment extractor consumers routed through `RequestCache.fetch`, per sibling pattern.
- `RequestCache` model spec + `RequestCacheKey` spec. Consumers are chained-pipeline workers → not unit-tested per Testing Philosophy; the funnel behavior is proven by the model spec + the staging run.
- CHANGELOG `[Unreleased]` → Changed: "Downstream data fetched once per job".

## Rollout

Merged to `develop` (PR #2403); ships to production in the 8.5.0 line alongside the ParentUpdate store fix and the S3 store-prefix rename. It changes what a resumed job reads, so it carries the same "no job straddles the deploy" constraint the release plan already enforces (drained window, per-integrator, outside the processing window) — not a hot deploy. Pre-prod, so no data migration. Validation rides on the `atento-mx-staging` run in `../integrator-develop-release-validation/PLAN.md` (the consistency study there already proves `Resource == Collection + Enrichment`, which the funnel does not alter).
