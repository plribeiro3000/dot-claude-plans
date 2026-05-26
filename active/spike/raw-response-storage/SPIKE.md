# SPIKE — Raw extraction response storage strategy for audit trail

**Conducted by:** Paulo Ribeiro
**Date:** 2026-04-01
**Status:** Research complete — pending decisions

---

## Goal

Define a unified strategy for storing raw extraction responses as an immutable audit trail in the integrator project.

The requirement is compliance-driven: if a source system has a bug or sends incorrect data, we must be able to prove exactly what they sent us, per extraction page, per job. This storage is separate from the processing pipeline — the pipeline uses `job.{resource}_collections` (the `Collection` model with `raw:` field). Raw response storage is exclusively for audit and debugging.

Questions to answer:
1. What storage backend is best suited for this use case across all source types (API, database, future FTP/files)?
2. Does the current API implementation (CarrierWave + fog-aws → S3) already solve the problem, or does it have gaps?
3. Is the database extractor flow missing raw response storage entirely?
4. What is the scalability, cost, and operational trade-off of each option?

---

## Method

- Codebase analysis of current `ApiRequest`, `ApiResponse`, `ApiResponseUploader`, and `ApplicationUploader` models
- Analysis of `Client::ApiExtractor`, `Client::DatabaseExtractor`, and `Client::ManagedExtractorConsumer` workers to understand what is stored and what is missing
- Analysis of the `Collection` model and its `raw:` field to understand the pipeline boundary
- Analysis of the `Resource`/`S3` cold storage flow to understand the existing S3 pattern
- Inspection of `ApplicationConfiguration` for all AWS/S3 settings and the `HOT_DATA_WINDOW` concept
- Inspection of Terraform configurations (`integrator-almaviva`, modules) to understand deployed infrastructure
- Review of `config/initializers/carrierwave.rb` and `config/initializers/fog.rb` to understand current storage setup

---

## Evidence

### 1. Current API flow — what exists

**Models:**
- `ApiRequest` (MongoDB doc): stores `connector_id`, `job_id`, `page`, `uri`
- `ApiResponse` (embedded in `ApiRequest`): stores `status_code`, `job_id`, plus two CarrierWave-mounted uploaders: `raw_body` and `raw_headers`
- `ApiResponseUploader < ApplicationUploader`: sets `store_dir` to `jobs/{job_id}/{resource_name_underscore}`
- `ApplicationUploader < CarrierWave::Uploader::Base`: uses `storage :fog`

**Initializer (`config/initializers/carrierwave.rb`):**
```ruby
config.fog_credentials = { provider: 'AWS', ... }
config.fog_directory = ApplicationConfiguration.aws_bucket  # "4shark-integrator-{client_name}"
config.fog_public = false
```

**Worker (`Client::ApiExtractor`):**
```ruby
local_raw_body_file = File.new(api_request.response.raw_body_path, 'w+', encoding: 'UTF-8')
local_raw_body_file.write(parsed_response.to_json)  # NOTE: writes parsed JSON, not raw HTTP body
api_response.raw_body = local_raw_body_file
```

**Critical finding:** The API extractor writes `parsed_response.to_json` (already parsed from HTTP body), not `http_response.body`. This means the stored file is a re-serialized JSON, not the original raw bytes as received. Headers are stored as `http_response.to_hash.to_json`.

**Storage path pattern:** `jobs/{job_id}/{resource_name}/raw_body_{id}_page_{page}.json`

**Where files go:** S3 bucket `4shark-integrator-{client_name}` via fog-aws. Confirmed by CarrierWave initializer and the `ApplicationUploader` using `storage :fog`. ECS containers are ephemeral (Fargate) — files written to `tmp/` are transient. CarrierWave immediately uploads to S3 on `save!`.

**Temporary file lifecycle:** The worker creates a file in `Rails.root.join('tmp', ...)`, assigns it to CarrierWave, calls `save!` (which uploads to S3), then calls `close`. The tmp file lives only for the duration of the worker execution.

---

### 2. Current database flow — what is MISSING

**`Client::DatabaseExtractor`:**
```ruby
raw_collection = connection.page(:clients, conditions, collection_last_id)
if raw_collection.size.positive?
  job.client_collections.create(raw: raw_collection)  # stored in Collection, not as raw response
```

**`Client::ManagedExtractorConsumer` (DatabaseSource branch):**
```ruby
raw_collection = dataset.to_a
if raw_collection.size.positive?
  job.client_collections.create(raw: raw_collection)  # same — only in Collection
```

**Finding:** Database extractors store data exclusively in `{Resource}Collection` models with a `raw:` field (type `Array`). There is NO equivalent to `ApiRequest`/`ApiResponse` for database sources. No audit trail exists for the original SQL query result pages.

---

### 3. The `Collection` model — pipeline intermediary, NOT audit storage

```ruby
class Collection
  field :raw, type: Array
  belongs_to :job
end
```

The `raw` field stores an array of row hashes. This is the pipeline's working copy used by transformers. It is not an audit trail because:
- It can be mutated or deleted
- It does not capture the query that produced it
- It does not capture the database connection state (version, integration version)
- It has no equivalent metadata like status codes or headers

---

### 4. Cold storage flow (Resource → S3)

The project already has a producer/consumer pattern for archiving `Resource` model documents (processed entities, not raw responses) to S3:

- `Resource::Producer`: pages through old `Resource` documents (older than `HOT_DATA_WINDOW`, default 90 days, set to 365 for Almaviva)
- `Resource::Consumer`: calls `S3.store(id, resource.class, resource.to_json)` → `storage/{type_underscore}/{id}.json`
- On restoration: `Resource.restore_from_s3(id)` — re-inserts the document into MongoDB

This cold storage flow is for processed `Resource` entities, not for raw extraction pages. The patterns are separate.

---

### 5. Infrastructure — what is already deployed

**AWS S3:** The bucket `4shark-integrator-{client_name}` already exists per client (confirmed by `AWS_BUCKET = "4shark-integrator-almaviva"` in Terraform). The IAM user `integrator-{client_name}` has S3 permissions to this bucket.

**No S3 lifecycle policies:** Searched all Terraform configs — no `lifecycle_rule`, `transition`, or `intelligent_tiering` configurations found in any S3 module or per-client config. The bucket has no automated tiering.

**ECS Fargate (ephemeral):** All integrators run on Fargate. There is no persistent disk. Files written to `tmp/` are lost when the container stops.

**MongoDB:** Per-client replica set (PSA topology) on EC2 `t3.small` instances with 60GB EBS volumes. Already at capacity for the data they need to serve — adding unbounded audit data here would require EBS resizing.

**fog-aws gem:** Already in Gemfile — used by CarrierWave for API response uploads. The `S3` model also uses it directly for cold storage.

---

### 6. Option analysis

#### Option A — Extend current CarrierWave/S3 pattern to all source types

The API flow already works: CarrierWave + fog-aws uploads to the existing per-client S3 bucket. Extending to database sources means creating a `DatabaseRequest`/`DatabaseResponse` model pair similar to `ApiRequest`/`ApiResponse`, with CarrierWave uploaders.

**What needs to change:**
- New models: `DatabaseRequest` (query, job, connector, page) and `DatabaseResponse` (row_count, raw body as JSON file)
- New uploader: `DatabaseResponseUploader` following the same `store_dir` pattern
- `{Resource}::DatabaseExtractor` and `ManagedExtractorConsumer` must create `DatabaseRequest`/`DatabaseResponse` records before/after each page query

**Scalability:** Files in S3 with metadata in MongoDB. S3 scales to any volume. MongoDB only stores the metadata document (small).

**Cost:** S3 Standard Storage (sa-east-1) ~$0.025/GB/month. A page of 500 rows of SQL data serialized to JSON is roughly 50–200KB. At 1,000 pages/job × 2 jobs/day × 365 days = 730,000 files/year. At 100KB average = ~73GB/year per client. Cost: ~$1.80/month or ~$21.6/year per client. Negligible.

**Hot/Cold tiering:** Not configured today. Can be added as S3 Intelligent-Tiering or lifecycle policies (Standard → Standard-IA after 30 days → Glacier after 90 days) in Terraform with zero code changes in the application.

**Unified format:** Yes. S3 stores bytes — content type is irrelevant. JSON for API/DB responses, raw bytes for future FTP/CSV files. CarrierWave handles binary uploads natively.

**Query/retrieval:** Metadata in MongoDB (`DatabaseRequest` + `DatabaseResponse`) with `job_id`, `connector_id`, `page` indexed. Retrieve the S3 key from the MongoDB doc, call `fog_directory.files.get(key)`.

**Infrastructure:** Fully available today — S3 bucket, IAM, fog-aws, CarrierWave already in place.

**Simplicity:** Medium. Requires new models and uploader, but follows an identical pattern already in the codebase. No new gems or infrastructure.

**Reliability:** S3 has 99.999999999% (11 nines) durability. AES256 server-side encryption already configured in the Terraform S3 module.

**Content-type agnostic:** Yes. S3 stores any bytes. Future CSV/Excel files need no special handling.

**Gap identified in current API implementation:** The API extractor stores `parsed_response.to_json` instead of `http_response.body`. This means non-JSON responses (XML, for example) would be silently converted — or would fail the `JSON.parse` call. True raw storage would preserve the original bytes.

---

#### Option B — MongoDB documents

Store raw page responses as MongoDB documents in a dedicated collection.

**Scalability:** MongoDB document size limit is 16MB. A single SQL page of 500 rows easily fits, but API responses with large embedded objects could approach this limit. More critically, MongoDB is sized per-client (60GB EBS, t3.small) and is already serving the integration pipeline. Adding unbounded audit data would exhaust disk quickly.

**Cost:** EC2 t3.small + 60GB EBS = ~$20/month. Adding audit data to an existing instance is not an option without EBS resize.

**Hot/Cold tiering:** Not available in MongoDB without external tooling (MongoDB TTL indexes can expire documents, but that's deletion not archival).

**Unified format:** No. MongoDB BSON has strict limits. Binary blobs over 16MB require GridFS.

**Verdict:** Not recommended. The project already uses MongoDB for transient pipeline data (Collections). Mixing audit data into the same store creates pressure on a size-constrained resource.

---

#### Option C — MongoDB GridFS

GridFS chunks files into 255KB pieces in MongoDB itself, bypassing the 16MB document limit.

**Scalability:** Still stored in MongoDB — same EC2 instances. The chunk collection grows alongside the application data.

**Cost:** Same as MongoDB above — requires EBS resizing over time.

**Hot/Cold tiering:** No native tiering.

**Infrastructure:** Mongoid has GridFS support, but CarrierWave's mongoid adapter has historically had issues with GridFS in newer versions. Not used anywhere in this codebase.

**Verdict:** Not recommended. No advantage over Option A (S3) and introduces complexity without benefit.

---

#### Option D — Direct S3 (without CarrierWave)

Use the existing `S3` model directly (as done in the cold storage flow) instead of CarrierWave.

```ruby
S3.store(request_id, RawResponse, body)
```

**Difference from Option A:** No CarrierWave — direct `fog.put_object`. No tmp file creation and upload. Simpler for binary payloads that don't need an ActiveRecord-style uploader.

**Trade-off:** The `S3` model currently hardcodes `.json` extension and a `storage/{type}/{id}.json` path. This would need to be extended for different content types.

**Scalability, Cost, Tiering:** Identical to Option A.

**Verdict:** Viable as a simpler alternative to CarrierWave for this use case, especially since raw responses are write-once/read-rarely (no update callbacks needed).

---

#### Option E — Hybrid tiering

S3 Standard for recent responses (last N days) + automatic transition to S3 Glacier for older responses.

This is not a separate storage implementation — it is a lifecycle policy added to Option A or D. The application writes to S3 Standard. An S3 Lifecycle Rule transitions objects to a cheaper tier automatically.

**AWS S3 Intelligent-Tiering:** Automatically moves objects between access tiers based on usage patterns. No retrieval fee. Monitoring fee: $0.0025 per 1,000 objects/month. For 730,000 objects/year per client: ~$1.80/month monitoring fee. Retrieval is instant.

**S3 Glacier Instant Retrieval:** $0.004/GB/month (vs. $0.025 for Standard). For 73GB/year: $0.29/month after transition. Retrieval: milliseconds, small fee per GB.

**Configuration:** Zero application code changes. One Terraform resource (`aws_s3_bucket_lifecycle_configuration`) per bucket.

**Verdict:** Recommended as an add-on to Option A or D, not as a standalone option.

---

### 7. Summary comparison table

| Dimension | Option A (CarrierWave+S3) | Option B (MongoDB) | Option C (GridFS) | Option D (Direct S3) | Option E (tiering add-on) |
|---|---|---|---|---|---|
| Scalability | High | Low | Low | High | High |
| Cost/year (est.) | ~$22/client | Requires EBS resize | Requires EBS resize | ~$22/client | ~$3.50/client with Glacier |
| Hot/Cold tiering | Via lifecycle policy | No | No | Via lifecycle policy | Native |
| Unified format | Yes | Partial | Yes | Yes | Yes |
| Query/retrieval | MongoDB metadata + S3 fetch | MongoDB query | MongoDB query | MongoDB metadata + S3 fetch | MongoDB metadata + S3 fetch |
| Infrastructure change | None (already deployed) | None | None | None | Add lifecycle rule in Terraform |
| Simplicity | Medium (new models) | Low (same store, wrong reason) | High complexity | Low (extend existing S3 model) | Low (Terraform only) |
| Durability | 11 nines | EC2/EBS dependent | EC2/EBS dependent | 11 nines | 11 nines |
| Content-type agnostic | Yes | No (16MB limit) | Yes | Yes | Yes |

---

## Conclusions

**Finding 1 — API flow is 90% solved, with one gap.**
The API flow already stores raw responses in S3 via CarrierWave + fog-aws. The infrastructure (bucket, IAM, gems) is in place and working. The gap: `parsed_response.to_json` is stored instead of `http_response.body`. For JSON APIs this makes no practical difference, but for XML or other encodings, this loses fidelity. True audit storage should preserve the original bytes.

**Finding 2 — Database flow has NO raw response storage.**
`DatabaseExtractor` and `ManagedExtractorConsumer` (database branch) write only to `{Resource}Collection` with a `raw:` Array field. This is pipeline data, not audit data. No `DatabaseRequest` or equivalent model exists. This is the primary gap.

**Finding 3 — S3 is the correct backend for all source types.**
MongoDB is the wrong store for audit data: it's size-constrained (EC2/EBS), has no native tiering, and the `Collection` model already serves a distinct pipeline role. S3 is already deployed per-client, has 11-nines durability, AES256 encryption, handles any content type, and costs ~$22/year per client at current volumes.

**Finding 4 — CarrierWave vs. direct S3 is an implementation detail.**
Both options use fog-aws and the same S3 bucket. CarrierWave provides a Rails-idiomatic uploader with callbacks and ActiveRecord integration. Direct S3 (via the `S3` model) is simpler for write-once binary payloads with no update lifecycle. The decision affects only the implementation approach, not the storage backend.

**Finding 5 — Tiering is free in terms of application code.**
Adding S3 Intelligent-Tiering or lifecycle transitions (Standard → Glacier Instant Retrieval) requires only a Terraform change to the S3 bucket — zero application code changes. This would reduce storage cost by ~85% for data older than 30–90 days.

**Finding 6 — The `HOT_DATA_WINDOW` concept already exists.**
`ApplicationConfiguration.hot_data_window` (default 90 days, 365 for Almaviva) is used to decide when `Resource` entities move to cold storage. The same concept can inform lifecycle policies for raw audit storage.

---

## Next Steps

The investigation reveals a clear gap (no database raw response storage) and a partial implementation (API raw response storage with a fidelity issue). Two decisions need to be made before implementation:

**Decision 1 — Implementation approach for database raw storage:**
- **Option A-extended:** New `DatabaseRequest`/`DatabaseResponse` models following the `ApiRequest`/`ApiResponse` pattern, with CarrierWave uploader. Consistent with existing API pattern. More code, more models.
- **Option D-direct:** Store database page responses directly via the `S3` model (as `S3.store(request_id, ...)`) without CarrierWave. Less code, no new models. Simpler for write-once data.

**Decision 2 — Fix the API raw body fidelity issue:**
The current API extractor stores `parsed_response.to_json` instead of `http_response.body`. For a true audit trail, `http_response.body` should be stored. This is a one-line fix but changes existing behavior. Engineer must decide if this correction is in scope.

**Decision 3 — Add S3 lifecycle tiering:**
Apply `aws_s3_bucket_lifecycle_configuration` in Terraform to transition raw audit objects older than 30 days to S3 Standard-IA and older than 90 days to S3 Glacier Instant Retrieval. Zero application code changes. Engineer must confirm if cost optimization is desired.

**If all three decisions are "yes":**
This generates a PLAN.md with implementation work across the integrator application and Terraform repository.

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
>
> **Further reading:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/technical-spike/)
