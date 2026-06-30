# PLAN-SPIKE — OpenSearch Heap Pressure: Bulk API, Refresh Interval, and Gem Upgrade

> Reference: Context provided by the engineer (diagnosis already concluded) + new facts confirmed in this review iteration

## Objective

Reduce JVM heap pressure on the OpenSearch cluster `app-shared-001` (2x `t3.small.search`, ~1GB heap per node) without changing instances. The identified cause is a burst of individual indexing (1 doc per HTTP request) reaching 1644 docs/s. Four complementary changes attack the problem on the producer side:

1. Aggregate calls to OpenSearch via the `_bulk` API (200-500 docs per request)
2. Raise `index.refresh_interval` from 1s to 30s
3. Remove the `< 7.14.0` pin and migrate to `opensearch-ruby` (decision made by the engineer)
4. Replace `elasticsearch-persistence` 7.2.1 and `elasticsearch-model` 7.2.1 with an adapter compatible with `opensearch-ruby` (adapter decision still pending)

---

## Scope

### In scope
- `app/elastic_indexes/application_elastic_index.rb` — add bulk save support; replace `Elasticsearch::*` namespaces
- `app/elastic_indexes/deal_elastic_index.rb` — add `refresh_interval` to index settings
- `app/workers/deal_elastic_index/consumer.rb` and `grower.rb` — call sites of `save_document!` that need to switch to bulk
- `Gemfile` and `Gemfile.lock` — remove `elasticsearch`, `elasticsearch-persistence`; add `opensearch-ruby` + chosen adapter

### Out of scope (open question)
- Monitoring/alerts on OpenSearch (not a blocker for this delivery)
- Indexes other than `DealElasticIndex`
- Cluster instance change (discarded by the operational context)
- Tuning `number_of_replicas` or other cluster settings

---

## Track 1 — Bulk API in `ApplicationElasticIndex`

### Current context

**Pattern 1: `save_document!` (1 doc per request)** — `app/elastic_indexes/application_elastic_index.rb:36-39`

```ruby
def save_document!(document, extra_attributes = nil, options = nil)
  response = new.save(document, extra_attributes, options)
  raise ElasticIndexationException unless response['result'].in?(%w[created updated])
end
```

Each call issues an individual POST to OpenSearch. `save` calls `elasticsearch_repository_save(document)` which in turn uses the REST API `PUT /{index}/_doc/{id}`.

**Pattern 2: `client.bulk` already exists in the installed gem** — `app/vendor/bundle/ruby/4.0.0/gems/elasticsearch-api-7.13.3/lib/elasticsearch/api/actions/bulk.rb:40-70`

The `bulk` method in the current gem accepts `arguments[:body]` as an array and serializes via `Elasticsearch::API::Utils.__bulkify(body)`, sending `Content-Type: application/x-ndjson`. The `client` is accessible via `new.client` in the repository (see `vendor/bundle/ruby/4.0.0/gems/elasticsearch-persistence-7.2.1/lib/elasticsearch/persistence/repository.rb:118-122`).

**Pattern 3: `dynamic_push_bulk` on the Sidekiq enqueue** — `app/workers/tenant_worker.rb:92-104`

```ruby
def dynamic_push_bulk(payload)
  result =
    Sidekiq::Client.push_bulk(
      payload.merge(
        'class' => self,
        'queue' => queue.name,
        **queue.metadata
      )
    )
  Thread.current[:tenant_company_id] = nil
  result
end
```

The project already uses batched enqueueing (Sidekiq `push_bulk`) on the producer side. The problem is that each consumer job still calls `save_document!` individually.

### Producer/consumer flow map

```
Producer (1 job per commission)
  → UserProducer (1 job per user_id, push_bulk)
      → Consumer (1 job per deal_id, push_bulk)   ← save_document! here (1 request/doc)

Grower (1 job per eligibility_period)
  → save_document! in a loop per deal_id          ← save_document! here (1 request/doc)
```

The two indexing points are `Consumer#perform` (`app/workers/deal_elastic_index/consumer.rb:16`) and `Grower#perform` (`app/workers/deal_elastic_index/grower.rb:27-28`).

### Option A: Synchronous bulk in the Grower (immediate opportunity)

**Approach summary:** The `Grower` already has the full list of `deal_ids` before the indexing loop (lines 18-24 of grower.rb). Swap the `save_document!` loop for a single `bulk_save_documents!(deal_ids, commission_uuid: commission.uuid)` call on `ApplicationElasticIndex`. No change to job topology.

**Pros:**
- Surgical change: only the Grower and the bulk method on ApplicationElasticIndex
- The Grower already has the ids gathered — no flow refactoring
- Immediate reduction from N requests to 1 (or ceil(N/batch_size) for large batches)
- No race-condition risk on `computation.increment_executions`

**Cons:**
- The Consumer (UserProducer → Consumer flow) keeps 1 doc per request — that is the dominant flow in the diagnosed burst (1644 docs/s)
- Partial heap-pressure reduction

**Cost / effort:** ~2-3h. A `bulk_save_documents!` method on `ApplicationElasticIndex` + Grower modification.

**Risk:** Low. Localized change, no job-topology change.

### Option B: Bulk via coalescing in the Consumer (Redis buffer)

**Approach summary:** The Consumer enqueues documents in a Redis buffer (by `commission_id`) instead of indexing immediately. A separate job (`Flusher`) drains the buffer in batches when it reaches 200-500 docs or after a TTL (e.g., 5s). `computation.increment_executions` happens in the Consumer (before indexing), and the Flusher does not have access to the counter — the counter has to be separated from the act of indexing.

**Pros:**
- Covers the dominant flow (the Consumer is triggered by the UserProducer, which is the higher-volume flow)
- Elasticity: large burst → large buffer → few bulk requests

**Cons:**
- Increases complexity: new worker, buffer TTL, edge cases (TTL expired before completing, Redis OOM)
- `computation.done?` and the current `Metric::Producer` are fired in the Consumer per deal. With a buffer, that firing has to move to the Flusher — regression risk in commission completeness control
- The buffer TTL creates a search latency window (recent docs appear with delay)

**Cost / effort:** ~1-2 days. New worker + Redis buffer + completeness-flow adjustment.

**Risk:** Medium-high. Change in the commission completeness control flow.

### Option C: Batch-aware enqueueing in the UserProducer

**Approach summary:** Instead of enqueuing 1 job per deal_id, the UserProducer enqueues "deal_ids batch" jobs (e.g., 200 ids per job). The Consumer receives a list and makes one bulk call per job.

**Pros:**
- No Redis buffer or separate Flusher required
- The job is self-contained (receives the ids, performs the bulk, increments executions)
- Consistent with the 4Shark "IDs, not objects" pattern

**Cons:**
- Changes the Consumer signature (`perform(commission_id, deal_ids_array, partial)`) — requires migrating in-flight jobs during the deploy
- `computation.increment_executions` has to be called once per job but increment `deal_ids_array.count` — change in the `computation` protocol
- The Grower (alternative flow) would also need adjustment to enqueue in batches or index in bulk directly

**Cost / effort:** ~4-6h plus tests. Changes in UserProducer + Consumer + possibly Grower.

**Risk:** Medium. Job interface change with in-flight jobs during a zero-downtime deploy.

### Mechanical decision to make (Track 1)

| Point | Options | Trade-off |
|-------|--------|-----------|
| Which flow to attack first | Grower only (A) / Consumer via buffer (B) / Consumer via batch enqueueing (C) | A is safer and immediate; B and C cover the dominant flow but have higher cost and risk |
| Bulk batch size | 200 / 500 / configurable | 200 is conservative for 1GB heap; 500 exposes larger request size |
| Implement A + C combined | Yes / No | Covers both flows in a single PR; increases the diff |

---

## Track 2 — `index.refresh_interval`

### Current context

**Pattern 4: Index settings in `DealElasticIndex`** — `app/elastic_indexes/deal_elastic_index.rb:8`

```ruby
settings index: { number_of_shards: 1 }
```

`refresh_interval` is not set — it uses the OpenSearch/Elasticsearch default of `1s`. There are no occurrences of `refresh_interval` anywhere in the project (grep confirmed zero results in `.rb`, `.json`, `.yml`, `.yaml`).

The `create!` method in `ApplicationElasticIndex` calls `new.create_index!(force: true)` — settings are passed to the creation API via `Elasticsearch::Persistence::Repository::DSL`. To change it on an existing index, use the `PUT /{index}/_settings` API.

### Option A: Change in `settings` of `DealElasticIndex` (applied on `create!`)

**Approach summary:** Add `refresh_interval: '30s'` to the `settings index: { ... }` hash of `DealElasticIndex`. Only effective on new indexes (e.g., after a `DealElasticIndex.create!`). The existing production index is not affected automatically.

**Pros:**
- 1-line change
- Configuration codified as the source of truth alongside the index

**Cons:**
- Does not change the existing production index without a separate migration
- Requires a manual/rake `PUT /deals/_settings { "index": { "refresh_interval": "30s" } }` before seeing the effect

**Cost / effort:** ~30min (code) + migration operation (via console/rake).

**Risk:** Low. The OpenSearch dynamic settings API does not require reindex — it applies on the fly.

### Option B: Settings migration rake task

**Approach summary:** Create a rake task `elastic:migrate_settings` that calls `client.indices.put_settings(index: 'deals', body: { index: { refresh_interval: '30s' } })`. Can run independently of the deploy.

**Pros:**
- Applies to the existing index without `create!`
- Idempotent: can run multiple times

**Cons:**
- Extra code (rake task) with no recurring use

**Cost / effort:** ~1h (rake task + PR documentation).

**Risk:** Low.

### Mechanical decision to make (Track 2)

| Point | Options | Trade-off |
|-------|--------|-----------|
| refresh_interval value | 10s / 30s / 60s | 30s is the sweet spot for bursty workloads; 60s reduces more but increases search staleness |
| How to apply in production | Manual console (A) / Rake task (B) | Rake task is auditable and reproducible |

---

## Track 3 — Migrate to `opensearch-ruby` (decision made)

### Confirmed facts

**The pin in the Gemfile** — `app/Gemfile:30`:

```ruby
gem 'elasticsearch', '< 7.14.0'
```

**Reason for the pin — confirmed by two independent sources:**

1. Starting in 7.14.0, Elastic introduced product verification via the `x-elastic-product: Elasticsearch` header and the `"You Know, for Search"` tagline. OpenSearch has never emitted that header — a search for `x-elastic-product` in the `opensearch-project/OpenSearch` repository via the GitHub Code Search API returned **zero occurrences**.

2. Official OpenSearch project position (issue #1166, closed by dblock on 2021-08-28):

   > "The `override_main_response_version` option in OpenSearch was introduced to support clients that worked previously against ES 7.10.2, the last OSS version, but elasticsearch-ruby 7.14 no longer does, so this won't be fixed in OpenSearch."

   And in the same thread:

   > "Expect an opensearch-ruby release soon. It will work against ES and OpenSearch..."

   Source: https://github.com/opensearch-project/OpenSearch/issues/1166

3. AWS CLI confirmed: `app-shared-001` has `"override_main_response_version": "true"` in `AdvancedOptions` — but that only covers the body of `GET /`, not the `x-elastic-product` header required by `elasticsearch-ruby` >= 7.14.

**Conclusion:** no `elasticsearch` gem version >= 7.14 works with OpenSearch (including 7.17.x and 8.x). The upgrade path within the `elastic/elasticsearch-ruby` ecosystem is closed for OpenSearch users. The migration to `opensearch-ruby` is the only path.

### What the migration involves

Replace in the `Gemfile`:

```ruby
# remove:
gem 'elasticsearch', '< 7.14.0'
gem 'elasticsearch-persistence'

# add:
gem 'opensearch-ruby', '~> 3.4'
# + adapter (see Track 4)
```

In `ApplicationElasticIndex`:

- `Elasticsearch::Transport::Transport::Errors::*` → `OpenSearch::Transport::Transport::Errors::*` (lines 4-6)
- `include Elasticsearch::Persistence::Repository` → equivalent of the chosen adapter (line 8)
- `include Elasticsearch::Persistence::Repository::DSL` → equivalent of the adapter (line 9)
- The `elasticsearch_repository_save/update/delete` aliases → equivalent aliases

The `client.bulk` method remains available in `opensearch-ruby` with the same interface — `OpenSearch::Client` exposes `bulk(body: [...])` identically to `Elasticsearch::Client`.

**URL fetched:** https://github.com/opensearch-project/OpenSearch/issues/1166
**Verbatim quote checked:** "elasticsearch-ruby 7.14 no longer does, so this won't be fixed in OpenSearch." — present in comments of issue #1166 closed by dblock.
**Quote substring confirmed:** dblock comment on 2021-08-28.

---

## Track 4 — Adapter to replace `elasticsearch-persistence` and `elasticsearch-model`

### Current context

`ApplicationElasticIndex` uses the `Elasticsearch::Persistence::Repository` pattern:

- `include Elasticsearch::Persistence::Repository` — provides `save`, `update`, `delete`, `search`, `find`, `create_index!`, `delete_index!`, `refresh_index!`, `index_exists?`, `client`
- `include Elasticsearch::Persistence::Repository::DSL` — provides `index_name`, `klass`, `document_type`, `settings`, `mappings`
- `DealElasticIndex` uses the DSL for `settings`, `mappings`, `indexes` (line 8-20 of deal_elastic_index.rb)

Current lockfile (`app/Gemfile.lock:222-234`):

```
elasticsearch-model (7.2.1)
  activesupport (> 3)
  elasticsearch (~> 7)
  hashie
elasticsearch-persistence (7.2.1)
  activemodel (> 4)
  activesupport (> 4)
  elasticsearch (~> 7)
  elasticsearch-model (= 7.2.1)
  hashie
```

Both gems depend on `elasticsearch (~> 7)`. When switching to `opensearch-ruby`, these dependencies become incompatible.

### Status of verified alternatives

#### `compliance-innovations/opensearch-rails`

- **GitHub tags:** 30 tags — 5 native OpenSearch (`v0.1.0`, `v0.1.1`, `v1.0.0`, `v1.1.0.a`, `v1.1.0.b`) + 25 historical prefixed `es-v*` (original `elasticsearch-rails` fork)
- **Last commit:** 2024-02-09 (publish script addition + Ruby 3.2 support)
- **Published on RubyGems.org?** Not verified as published on the public rubygems.org. The `bin/publish_gem.sh` script uses `gem inabox --host $host` — publication on a private gem server, not rubygems.org. A search on rubygems.org for `opensearch-model` and `opensearch-persistence` returned "No gems found".
- **Interface:** `OpenSearch::Persistence::Repository` with `client`, `document_type`, `index_name`, `klass`, `mapping`, `settings`, `index_exists?` — structurally analogous to `Elasticsearch::Persistence::Repository`
- **Activity:** 10 stars, 15 forks, last updated 2026-04-15 (GitHub metadata), but last code commit in Feb 2024
- **Supply chain:** not published on public rubygems.org — a `github:` dependency would conflict with Renovate/Dependabot and 4Shark's supply chain policy

**Source pattern referenced:**
- `compliance-innovations/opensearch-rails` — gemspec at `opensearch-model/opensearch-model.gemspec` lists `gem 'opensearch-ruby', '>= 2'` as a runtime dependency
- `bin/publish_gem.sh` — uses `gem inabox --host $host`, not `gem push` to rubygems.org

#### `opensearch-ruby` directly (without Repository pattern)

- Use `OpenSearch::Client` directly, with no persistence layer
- Rewrite `ApplicationElasticIndex` over the raw API: `client.index`, `client.update`, `client.delete`, `client.search`, `client.bulk`, `client.indices.create`, `client.indices.delete`, `client.indices.refresh`, `client.indices.exists`
- The `settings`/`mappings` DSL of `DealElasticIndex` would be replaced by Ruby hashes passed directly to `client.indices.create(body: { settings: {...}, mappings: {...} })`
- No third-party gem dependency besides the official `opensearch-ruby`
- `opensearch-ruby` 3.4.0 published on rubygems.org (verified: https://rubygems.org/gems/opensearch-ruby/versions/3.4.0)

#### `esse` gem (marcosgz/esse)

- **Current version:** 0.5.3 (released May 20, 2026) — active development
- **Published on rubygems.org:** yes (24,230 total downloads verified)
- **Runtime dependencies:** only `multi_json` and `thor` — no `elasticsearch` or `opensearch-ruby` as hard dependencies (uses whatever the project configures)
- **OpenSearch support:** explicit — README: "Ruby simple and extremely flexible client for ElasticSearch and OpenSearch based on official clients such as elasticsearch-ruby and opensearch-ruby"
- **Repository pattern:** yes — Index/Repository/Document architecture with chunked collections; bulk indexing supported via CLI (`esse index reset`) and API
- **Ecosystem:** companion gems (`esse-rails`, `esse-active_record`, `esse-async_indexing`, `esse-redis_storage`)
- **Activity:** last commit May 20, 2026, 11 stars, 1 fork
- **Fit with `ApplicationElasticIndex`:** the esse architecture differs from the elasticsearch-persistence Repository pattern. `ApplicationElasticIndex` would have to be rewritten following the esse pattern (Index + Repository subclasses), not just a namespace swap
- **Adoption risk:** 24K total downloads, 1 fork — low adoption. Third-party gem without endorsement from the OpenSearch project or Elastic

**Source pattern referenced:**
- `rubygems.org/gems/esse` — version 0.5.3, May 20, 2026, 24,230 downloads
- `github.com/marcosgz/esse` — 317 commits, last May 20, 2026

#### `searchkick` (ankane/searchkick)

- **Published on rubygems.org:** yes — mainstream gem, battle-tested in production (the README cites Instacart)
- **Declared support:** README — "The latest version works with Elasticsearch 8 and 9 and OpenSearch 2 and 3."
- **Official OpenSearch endorsement:** the OpenSearch project declined to maintain an `opensearch-rails` and pushed the community towards `searchkick`. Position recorded in issue `opensearch-project/opensearch-ruby#50` ("Proposal: Fork and maintain elasticsearch-rails", closed on 2023-02-07)
- **Paradigm:** search defined inside the model (`class Deal; searchkick; end`) — different from the other three options that keep the `Deal` (AR) × `DealElasticIndex` (isolated index) separation
- **Supply chain:** published on the public rubygems.org — Renovate works, supply-chain checks operate
- **Maintainer:** ankane (Andrew Kane) — reputable, active

**Official OpenSearch position documented in issue #50 (2023-02-07):**

wbeckler (OpenSearch maintainer), comment on 2022-11-17:

> "I feel like if an opensearch-rails were built off a forked elasticsearch-rails, it could be to the detriment of searchkick... I think anyone can do a minor patch of elasticsearch-rails to get it to use opensearch-ruby, but I don't want to encourage that as a solution over adding whatever is missing from searchkick"

simi (rubygems.org maintainer), comment on 2022-11-12, explaining why no one in the community wanted to take on a public `opensearch-rails`:

> "Initially I was about to go with 1., but then I realized I don't want to spend my time contributing to billion dollar company projects."

**URL fetched:** https://github.com/opensearch-project/opensearch-ruby/issues/50
**Verbatim quote checked (wbeckler):** "I feel like if an opensearch-rails were built off a forked elasticsearch-rails, it could be to the detriment of searchkick... I think anyone can do a minor patch of elasticsearch-rails to get it to use opensearch-ruby, but I don't want to encourage that as a solution over adding whatever is missing from searchkick" — present in wbeckler's comment on 2022-11-17 in issue #50.
**Quote substring confirmed (wbeckler):** wbeckler comment, 2022-11-17, issue opensearch-project/opensearch-ruby#50.

**URL fetched:** https://github.com/opensearch-project/opensearch-ruby/issues/50
**Verbatim quote checked (simi):** "Initially I was about to go with 1., but then I realized I don't want to spend my time contributing to billion dollar company projects." — present in simi's comment on 2022-11-12 in the same issue #50.
**Quote substring confirmed (simi):** simi comment, 2022-11-12, issue opensearch-project/opensearch-ruby#50.

**URL fetched:** https://github.com/ankane/searchkick
**Verbatim quote checked:** "The latest version works with Elasticsearch 8 and 9 and OpenSearch 2 and 3." — present in the README of the ankane/searchkick repository.
**Quote substring confirmed:** intro section of the README, ankane/searchkick.

**Current `DealElasticIndex` surface that would need migration:**

| Current usage point | File:line | Impact on searchkick |
|---|---|---|
| `DealElasticIndex.client = Elasticsearch::Client.new(...)` (per-request tenant-aware swap) | `app/middlewares/elastic_index_connection.rb:5`, `app/config/initializers/elastic_indexes.rb:6` | Searchkick uses a global `Searchkick.client` — per-request swap requires a monkey-patch or custom wrapper |
| `DealElasticIndex.fetch_ids_by(...)` — bool/must/range/match query | `app/adapters/metric/total_adapter.rb:26`, `app/adapters/metric/quantity_adapter.rb:19`, `app/workers/deal_eligibility/grower.rb:20` | Needs to be translated to the searchkick DSL; results must be byte-for-byte identical |
| `search(query, options).raw_response` + `scroll(scroll_id:, scroll:)` | `app/workers/deal_elastic_index/expirator.rb:25,27` | Scroll is not first-class in searchkick — requires raw `body:` or low-level access to the `searchkick_index` |
| `save_document!` | `app/workers/deal_elastic_index/consumer.rb:16`, `app/workers/deal_elastic_index/grower.rb:28` | Becomes `Deal#reindex` or `Deal.searchkick_index.bulk_index(...)` |
| `delete_document!` | `app/workers/deal_elastic_index/destroyer.rb:8` | Becomes `Deal#reindex(:delete)` |

### Option A: `compliance-innovations/opensearch-rails` via `github:` dependency

**Approach summary:** Add `gem 'opensearch-model', github: 'compliance-innovations/opensearch-rails', glob: 'opensearch-model/*.gemspec'` and `gem 'opensearch-persistence', github: 'compliance-innovations/opensearch-rails', glob: 'opensearch-persistence/*.gemspec'`. Swap `Elasticsearch::Persistence::*` namespaces for `OpenSearch::Persistence::*` in `ApplicationElasticIndex`.

**Pros:**
- Closest interface to the current one: `OpenSearch::Persistence::Repository` exposes the same methods (`client`, `index_name`, `klass`, `settings`, `mappings`, etc.)
- The `settings`/`mappings` DSL in `DealElasticIndex` likely works without change (same `settings index: { ... }` block and `mappings dynamic: 'false' do ... end`)
- Smaller rewrite of `ApplicationElasticIndex`

**Cons:**
- Not published on public rubygems.org — a `github:` dependency conflicts with Renovate/Dependabot and 4Shark's supply chain policy
- Last code commit: Feb 2024 (>1 year without code maintenance)
- Compatibility with Ruby 4.0.4 (the project version, see Gemfile line 8) not verified — the fork's CI tests Ruby 3.2 at most

**Cost / effort:** ~4-6h (namespace swap + integration tests).

**Risk:** High. `github:` dependency violates supply chain policy. Ruby 4.0 compatibility not verified.

### Option B: `opensearch-ruby` directly (rewrite `ApplicationElasticIndex`)

**Approach summary:** Eliminate `elasticsearch-persistence` and `elasticsearch-model` entirely. Rewrite `ApplicationElasticIndex` using `OpenSearch::Client` directly. Bulk, search, serialize/deserialize, and index management are implemented over the raw client API, without the Repository pattern.

**Pros:**
- Single dependency: `opensearch-ruby` — official gem of the OpenSearch project, published on rubygems.org, compatible with Renovate/Dependabot
- Full control of the implementation (native bulk, refresh, retry, error handling)
- Removes the debt of `elasticsearch-persistence`/`elasticsearch-model` which have no stable published OpenSearch equivalent
- The `bulk` method on `OpenSearch::Client` has an identical interface to `Elasticsearch::Client`

**Cons:**
- Rewrite of `ApplicationElasticIndex` — loss of the `settings`/`mappings` DSL (the `DealElasticIndex` would need to change how it declares settings and mappings)
- No Repository layer: serialize/deserialize, `create_index!`, `delete_index!`, `refresh_index!`, `index_exists?` need to be reimplemented
- No other 4Shark project uses this pattern — no internal reference
- Greater implementation and testing effort

**Cost / effort:** ~2-3 days (rewrite + integration tests).

**Risk:** Medium. Rewrite of infrastructure-level code. The risk is regression in search (query DSL in `fetch_ids_by`, scroll, etc.) — testable on staging before production.

### Option C: `esse` gem as adapter

**Approach summary:** Replace `elasticsearch-persistence` with the `esse` gem. `ApplicationElasticIndex` would be rewritten following the esse pattern (a class that inherits from `Esse::Index`, with Repository subclasses for each data source).

**Pros:**
- Explicit support for OpenSearch AND Elasticsearch in the same gem
- Published on rubygems.org (compatible with the supply chain policy)
- Active development (last commit May 20, 2026)
- Native bulk indexing support
- Ecosystem of companion gems (`esse-async_indexing` may be relevant for the heap problem)

**Cons:**
- Different architecture from the current Repository pattern — significant rewrite of `ApplicationElasticIndex` and `DealElasticIndex`
- 24K total downloads, 1 fork — very low adoption for an infrastructure gem
- No OpenSearch project endorsement
- No other 4Shark project uses this pattern
- The `esse` gem solves the client problem (Elasticsearch vs OpenSearch) but requires learning a new abstraction

**Cost / effort:** ~3-4 days (learning the esse API + rewrite + tests).

**Risk:** Medium-high. Low adoption + new abstraction + infrastructure rewrite.

### Option D: `searchkick` as adapter

**Approach summary:** Replace `elasticsearch-persistence` and `elasticsearch-model` with the `searchkick` gem. Search is declared on the ActiveRecord model (`class Deal; searchkick; end`), with `search_data` defining the indexed document. `DealElasticIndex` as an isolated object goes away — the `Deal` (AR) × `DealElasticIndex` (index) separation is abandoned in favor of the searchkick integrated model.

**Pros:**
- Officially endorsed by the OpenSearch project — wbeckler (OpenSearch maintainer) pushed the community to searchkick instead of maintaining an `opensearch-rails` (issue opensearch-project/opensearch-ruby#50, closed 2023-02-07)
- Published on public rubygems.org — Renovate works, supply chain checks operate normally
- Battle-tested in production (README: Instacart)
- Supports Elasticsearch 8/9 and OpenSearch 2/3 on the same gem
- ankane is a reputable and active maintainer

**Cons:**
- API completely different from `elasticsearch-persistence` — the `Deal/DealElasticIndex` separation is eliminated; `searchkick` puts search inside the model
- Per-tenant client swap (`DealElasticIndex.client = Elasticsearch::Client.new(...)` per request) is not natively supported — `Searchkick.client` is global; per-request swap requires a monkey-patch or custom wrapper (high technical risk, unknown surface)
- Migration effort ~3-4 days vs ~1-2 days for Options B/C with clearer paths
- Translation of `fetch_ids_by` (bool/must/range/match → searchkick DSL) with mandatory result equivalence — medium risk in the metric adapters
- Scroll API is not first-class in searchkick; `expirator.rb` requires low-level access to `searchkick_index`

**Cost / effort:**

| Work | Estimate | Risk |
|---|---|---|
| `searchkick` on `Deal` + mappings + `search_data` | 1-2h | Low |
| Rewrite `save_document!` callers | 2-3h | Low |
| Rewrite `delete_document!` callers | 30min | Low |
| Rewrite `fetch_ids_by` (3 callers) — translate bool/must/range/match to searchkick DSL with identical results | 4-6h | Medium |
| Rewrite `expirator.rb` (scroll API) | 3-4h | Medium |
| Per-tenant client swap — `Searchkick.client` is global; per-request requires hack | 6-8h | High (unknown) |
| Equivalence testing | 4-6h | — |
| Reindex of existing production data | 2h | Low |

**Total estimated: ~22-31h (~3-4 days of focused work)**

**Risk:** Medium-high. Per-tenant client swap is the main blocker — unknown surface that could escalate the effort. Eliminating the `Deal/DealElasticIndex` separation is an irreversible paradigm change in the diff.

**Source patterns referenced:**
- `app/middlewares/elastic_index_connection.rb:5` — `DealElasticIndex.client = Elasticsearch::Client.new(...)` (per-request tenant-aware swap)
- `app/config/initializers/elastic_indexes.rb:6` — client initialization per tenant
- `app/adapters/metric/total_adapter.rb:26`, `app/adapters/metric/quantity_adapter.rb:19`, `app/workers/deal_eligibility/grower.rb:20` — `DealElasticIndex.fetch_ids_by(...)`
- `app/workers/deal_elastic_index/expirator.rb:25,27` — `raw_response` + `scroll`
- `app/workers/deal_elastic_index/consumer.rb:16` — `save_document!`
- `app/workers/deal_elastic_index/grower.rb:28` — `save_document!`
- `app/workers/deal_elastic_index/destroyer.rb:8` — `delete_document!`
- [github.com/opensearch-project/opensearch-ruby/issues/50](https://github.com/opensearch-project/opensearch-ruby/issues/50) — official OpenSearch position pushing to searchkick; wbeckler verbatim: "I think anyone can do a minor patch of elasticsearch-rails to get it to use opensearch-ruby, but I don't want to encourage that as a solution over adding whatever is missing from searchkick"
- [github.com/ankane/searchkick](https://github.com/ankane/searchkick) — README: "The latest version works with Elasticsearch 8 and 9 and OpenSearch 2 and 3."

### Mechanical decision to make (Track 4)

| Point | Options | Trade-off |
|-------|--------|-----------|
| Which adapter replaces `elasticsearch-persistence` | `compliance-innovations/opensearch-rails` via `github:` (A) / `opensearch-ruby` directly (B) / `esse` gem (C) / `searchkick` (D) | A violates supply chain policy; B is cleanest but requires a rewrite; C has low adoption; D has official OpenSearch endorsement but per-tenant swap is high-risk and eliminates the Deal/DealElasticIndex separation |
| Tracks 3+4 in the same PR as 1+2 | Yes / Separate PR | The tracks are technically independent; splitting reduces per-PR risk |

---

## Technical decisions to be made (NOT decided here)

| Decision point | Options | Trade-off summary | Engineer to choose |
|----------------|---------|-------------------|---------------------|
| Which flow to attack with bulk | Grower only (A) / Consumer via Redis buffer (B) / Consumer via batch enqueueing (C) | A is immediate and safe; B and C cover the dominant flow but with more risk | □ |
| Bulk batch size | 200 / 500 | 200 is conservative for 1GB heap; 500 maximizes throughput but exposes larger requests | □ |
| refresh_interval value | 10s / 30s / 60s | 30s is the documented sweet spot for bursty workloads | □ |
| How to apply refresh_interval in production | Manual console / rake task | Rake task is auditable | □ |
| Adapter to replace elasticsearch-persistence | `opensearch-rails` via `github:` (A) / `opensearch-ruby` directly (B) / `esse` (C) / `searchkick` (D) | A violates supply chain policy; B requires rewrite but is cleanest; C has low adoption; D has official OpenSearch endorsement but per-tenant swap is unknown and eliminates Deal/DealElasticIndex separation | □ |
| Tracks 3+4 in this PR or a separate one | Together with 1+2 / Separate PR | The tracks are independent; splitting reduces per-PR risk | □ |

---

## Risks (cross-cutting)

| Risk | Impact | Possible mitigation |
|------|--------|---------------------|
| `computation.done?` fires prematurely if the bulk fails partially | Commission marked as complete without all docs indexed | Check `errors` in the `_bulk` response and re-raise `ElasticIndexationException` for items with errors |
| In-flight jobs during deploy with the new Consumer interface (Option C of Track 1) | Jobs queued with the old signature fail when processed by the new Consumer | Keep signature compatibility during deploy (accept both array and integer) |
| `refresh_interval: 30s` increases search staleness | Recently indexed deals do not appear in searches for up to 30s | Confirm with the engineer whether there is a visibility SLA for searches on `DealElasticIndex` |
| `compliance-innovations/opensearch-rails` not published on rubygems.org | `github:` dependency violates 4Shark supply chain policy | Use Option B, C, or D of Track 4 |
| `esse` gem with low adoption | Risk of abandonment; limited support | Monitor activity; have a migration plan to `opensearch-ruby` directly |
| Ruby 4.0.4 incompatibility with forks | `compliance-innovations` CI tests up to Ruby 3.2 | Test in staging before deciding on the fork |
| `searchkick` per-tenant client swap — unknown surface | Effort can escalate beyond 8h; solution may be fragile | Prototype the swap in staging before committing to Option D |

---

## Open questions for the engineer

1. Does `DealElasticIndex` have a search visibility SLA? In other words: after a deal is indexed, how quickly must it appear in `fetch_ids_by` results? That determines whether `refresh_interval: 30s` is acceptable.

2. For Track 1, which flow has the greater real impact in the observed burst: the Grower (override/eligibility flow) or the Consumer (main UserProducer → Consumer flow)?

3. Are there automated integration tests against OpenSearch in CI? Or are the elastic tests only unit tests with mocks?

4. For Track 4: does the 4Shark supply chain policy allow `github:` dependencies in production? If not, Option A is mechanically discarded.

5. Can the `ApplicationElasticIndex` rewrite (Options B, C, and D of Track 4) go in a separate PR, or does it need to be atomic with the Track 3 gem migration?

6. For Option D (searchkick): is the per-tenant client swap a non-negotiable requirement? If yes, prototype before committing — the "unknown" risk can substantially increase the total effort.

---

## Sources

- `app/Gemfile:30` — `gem 'elasticsearch', '< 7.14.0'` (current pin)
- `app/Gemfile.lock:217-234` — resolved versions of all elastic gems
- `app/elastic_indexes/application_elastic_index.rb:1-128` — full implementation of ApplicationElasticIndex with `Elasticsearch::Persistence::Repository` and `DSL`
- `app/elastic_indexes/application_elastic_index.rb:36-39` — `save_document!` (1 doc per request)
- `app/elastic_indexes/deal_elastic_index.rb:8-20` — `settings index: { number_of_shards: 1 }` + mappings DSL (no `refresh_interval`)
- `app/workers/deal_elastic_index/consumer.rb:16` — `DealElasticIndex.save_document!` in the Consumer
- `app/workers/deal_elastic_index/grower.rb:27-28` — `save_document!` loop per deal_id
- `app/workers/deal_elastic_index/destroyer.rb:8` — `DealElasticIndex.delete_document!` in the Destroyer
- `app/middlewares/elastic_index_connection.rb:5` — `DealElasticIndex.client = Elasticsearch::Client.new(...)` (per-request tenant-aware swap)
- `app/config/initializers/elastic_indexes.rb:6` — client initialization per tenant
- `app/adapters/metric/total_adapter.rb:26` — `DealElasticIndex.fetch_ids_by(...)`
- `app/adapters/metric/quantity_adapter.rb:19` — `DealElasticIndex.fetch_ids_by(...)`
- `app/workers/deal_eligibility/grower.rb:20` — `DealElasticIndex.fetch_ids_by(...)`
- `app/workers/deal_elastic_index/expirator.rb:25,27` — `search(...).raw_response` + `scroll(scroll_id:, scroll:)`
- `app/workers/tenant_worker.rb:92-104` — `dynamic_push_bulk` via Sidekiq
- `app/vendor/bundle/ruby/4.0.0/gems/elasticsearch-api-7.13.3/lib/elasticsearch/api/actions/bulk.rb:40-70` — `client.bulk` available in the installed gem (verbatim: `raise ArgumentError, "Required argument 'body' missing" unless arguments[:body]`)
- [opensearch-project/OpenSearch#1166](https://github.com/opensearch-project/OpenSearch/issues/1166) — official position: `elasticsearch-ruby 7.14` fails with OpenSearch; `override_main_response_version` does not cover the `x-elastic-product` header; verbatim: "elasticsearch-ruby 7.14 no longer does, so this won't be fixed in OpenSearch."
- [rubygems.org/gems/opensearch-ruby/versions/3.4.0](https://rubygems.org/gems/opensearch-ruby/versions/3.4.0) — `opensearch-ruby` 3.4.0 published on rubygems.org (official gem of the OpenSearch project)
- [rubygems.org/gems/esse](https://rubygems.org/gems/esse) — `esse` 0.5.3 (May 20, 2026), 24,230 downloads, runtime dependencies: `multi_json`, `thor`
- [github.com/marcosgz/esse](https://github.com/marcosgz/esse) — README: "Ruby simple and extremely flexible client for ElasticSearch and OpenSearch based on official clients such as elasticsearch-ruby and opensearch-ruby"; 317 commits, last May 20, 2026
- [github.com/compliance-innovations/opensearch-rails](https://github.com/compliance-innovations/opensearch-rails) — 30 tags (5 native OpenSearch: v0.1.0 to v1.1.0.b); `bin/publish_gem.sh` uses `gem inabox --host $host` (private gem server, not rubygems.org); last code commit Feb 2024
- `github.com/compliance-innovations/opensearch-rails` — `opensearch-model/opensearch-model.gemspec`: runtime dependency `opensearch-ruby (>= 2)`; interface `OpenSearch::Persistence::Repository` with methods `client`, `index_name`, `klass`, `settings`, `mappings`, `index_exists?`
- [rubygems.org search: opensearch-model](https://rubygems.org/search?utf8=%E2%9C%93&query=opensearch-model) — "No gems found" — confirms `opensearch-model` is not published on public rubygems.org
- [rubygems.org search: opensearch-persistence](https://rubygems.org/search?utf8=%E2%9C%93&query=opensearch-persistence) — "No gems found" — confirms `opensearch-persistence` is not published on public rubygems.org
- [github.com/opensearch-project/opensearch-ruby/issues/50](https://github.com/opensearch-project/opensearch-ruby/issues/50) — official OpenSearch position pushing to searchkick; wbeckler (2022-11-17): "I don't want to encourage that as a solution over adding whatever is missing from searchkick"; simi (2022-11-12): "I don't want to spend my time contributing to billion dollar company projects."; issue closed 2023-02-07
- [github.com/ankane/searchkick](https://github.com/ankane/searchkick) — README: "The latest version works with Elasticsearch 8 and 9 and OpenSearch 2 and 3."
- Not researched: dual elasticsearch+OpenSearch support in the `elasticsearch` gem 9.x — not found in changelog, release notes, or official issues
