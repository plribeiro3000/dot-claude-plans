# SPIKE — Storage strategy for managed extraction: Collections vs ApiRequest/ApiResponse files

**Conducted by:** Paulo Ribeiro
**Date:** 2026-04-01
**Status:** Research complete — pending decisions

---

## Goal

Which storage pattern should the unified managed extractors use for API-sourced data: MongoDB Collections (Pattern A), ApiRequest/ApiResponse files (Pattern B), or a hybrid?

The investigation is needed because the managed flow currently contains a structural inconsistency: the extractor branches on source type and uses two different storage mechanisms, but the transformer always reads from collections — meaning any API-sourced data written to ApiRequest/ApiResponse files in the managed path is silently ignored by the transformer.

---

## Method

- Static analysis of all relevant models and workers in the integrator codebase
- Traced the full data flow for both extraction paths: database source and API source
- Examined storage infrastructure configuration (CarrierWave, Fog/S3)
- Reviewed the Job model relationships and cleanup dependencies
- Examined the Collection base class for MongoDB document structure
- Reviewed ApplicationConfiguration for page size settings

---

## Evidence

### 1. Current managed flow has a silent data loss bug

Every `ManagedExtractorConsumer` (24 workers, all resources including User sub-roles) branches on source type:

```
if connector.source.is_a?(DatabaseSource)
  # saves to job.{resource}_collections.create(raw: raw_collection)
else  # ApiSource
  # saves to ApiRequest + ApiResponse files on disk/S3
end
```

Every `ManagedTransformerConsumer` reads exclusively from collections:

```
job.subsidiary_collections.each do |collection|
  collection.raw.each do |raw_object|
    # transform raw_object
  end
end
```

There is no branching in any transformer. When the source is an API, the extractor writes to ApiRequest/files, but the transformer reads from collections — which are empty. The result is that API-sourced data is silently skipped in the managed path.

**This is the primary constraint that shapes the answer.** Whichever storage pattern is chosen, the transformer must be consistent with what the extractor writes.

### 2. Pattern A — MongoDB Collections (SubsidiaryCollection, DealCollection, etc.)

**Source:** `app/models/collection.rb`, `app/models/subsidiary_collection.rb`

- Base class `Collection` uses `field :raw, type: Array` — stores the entire page as a single MongoDB document.
- The `Collection` class has optimized aggregation methods: `pair_ids_for`, `find_raw_object`, `job_resource_quantity` — these exist specifically to avoid loading entire arrays into Ruby memory.
- Page size is controlled by `ApplicationConfiguration.sql_page_size` (default 500 rows).
- Job owns all collections with `dependent: :destroy` — automatic cleanup on job destruction.
- 15 collection types declared in `Collection::TYPES`, each mapped 1:1 to a resource.
- The `SubsidiaryCollection` has zero business logic — it is a pure data container.

**Memory concern:** With 500 rows per page, and typical CRM records containing ~20-50 fields each, a single collection document is roughly 50KB–250KB. Well within the 16MB MongoDB document limit. The limit only becomes a concern if `sql_page_size` is set above ~5000 rows with large records.

**Retry safety:** `find_or_create` is not used — each page creates a new collection document. On worker retry, duplicate collection documents accumulate. The transformer iterates all collections for the job, so duplicates cause duplicate imports. This is a pre-existing issue in the database path, not introduced by unification.

### 3. Pattern B — ApiRequest/ApiResponse files (Fog/S3)

**Source:** `app/models/api_request.rb`, `app/models/api_response.rb`, `app/uploaders/api_response_uploader.rb`, `config/initializers/carrierwave.rb`

- `ApiRequest` stores: `connector_id`, `job_id`, `page`, `uri`
- `ApiResponse` is embedded in `ApiRequest` and stores: `status_code`, `job_id`, file references for `raw_body` and `raw_headers`
- Files are written to `Rails.root/tmp/` locally and then uploaded to S3 via CarrierWave + Fog
- Storage path: `jobs/{job_id}/{resource_name}/raw_body_{id}_page_{page}.json`
- The uploader is configured as `storage :fog` with no local fallback — requires AWS credentials to be present. The CarrierWave initializer only configures Fog if `aws_access_key_id` is present; otherwise the uploader silently uses local disk.
- Job owns api_requests with `dependent: :nullify` — files are NOT deleted when job is destroyed. ApiRequests are deleted when the Connector is deleted (`dependent: :destroy` on Connector).
- `Import` has `belongs_to :api_request, optional: true` — a cross-reference from the transformation result back to the API request, enabling traceability.

**File lifecycle gap:** The `tmp/` files created during extraction are never explicitly deleted. They are uploaded to S3 and closed, but the local file is not removed. Over time, `tmp/` fills with JSON files. There is no cleanup job for these files.

**Transformer read pattern:** `api_response.raw_body.read` — CarrierWave downloads the file from S3 and reads the entire JSON body into memory. The body contains the _full_ parsed API response (not just the extracted collection), meaning the transformer re-parses and re-applies `collection_source_keys` again — the same work done in the extractor.

**Unique audit data:** `ApiResponse` preserves `status_code` and `raw_headers` — data that Collections do not capture. This is the only information in Pattern B that is not available in Pattern A.

### 4. S3 infrastructure is already configured and in use

`config/initializers/fog.rb` and `config/initializers/carrierwave.rb` both exist and configure S3 via Fog. CarrierWave is already used in production for API-path (non-managed) extraction. S3 is available as infrastructure.

However, S3 is not used by the collection path at all. Collections are stored in MongoDB only.

### 5. Page size and MongoDB document limits

- `sql_page_size`: default 500 rows (ENV `SQL_PAGE_SIZE`)
- `mongo_page_size`: default 500 rows (ENV `MONGO_PAGE_SIZE`)
- MongoDB document limit: 16MB
- At 500 rows and typical CRM record sizes (~1–5KB per row), a collection document is 500KB–2.5MB. Safe.
- At the extreme (5000 rows × 5KB = 25MB), it would exceed the limit. But the defaults are conservative and the system has operated with collections for the self-service path without hitting this limit.

### 6. The 24 ManagedTransformerConsumers all read from collections

Every single `ManagedTransformerConsumer` in the codebase — including all User sub-roles (Admin, Coordinator, Director, GeneralManager, Manager, President, SalesRepresentative, Superintendent, Supervisor, VicePresident) — reads from `job.{resource}_collections`. None of them branch on source type or read from ApiRequests.

This means: if the decision is to keep Pattern B for API sources, all 24 transformer consumers would need to be rewritten with branching logic, doubling their complexity.

### 7. ApiRequest carries an important cross-reference: Import.api_request_id

`app/models/import.rb` has `belongs_to :api_request, optional: true`. The API-path transformer sets `import.api_request_id = api_request.id`. This provides traceability from the final import record back to the raw HTTP request that produced it.

The managed path transformer does NOT set `api_request_id` — this field is always nil for managed-path imports.

---

## Conclusions

### The current managed flow has a bug, not just a design inconsistency

The managed extractor writes API-sourced data to ApiRequest/files. The managed transformer reads from collections. These two paths are never reconciled. API-sourced data in the managed flow is silently discarded during transformation. This must be fixed regardless of which option is chosen.

### Option 1 (Collections for both) is the correct choice

The evidence points clearly to Option 1 for these reasons:

**1. All 24 transformers already implement the collection interface.** No transformer changes are required. Option 2 would require rewriting all 24 transformers with source-type branching, adding complexity without benefit.

**2. The managed path never needs the full HTTP response payload.** The managed extractor already parses the response and applies `collection_source_keys` and `sensitive_key` redaction before saving. The collection stores only the processed data. Pattern B stores the raw HTTP body and re-applies `collection_source_keys` in the transformer — duplicate parsing that adds no value in the managed flow.

**3. File lifecycle is unmanaged.** `tmp/` files accumulate without cleanup. S3 objects from managed extractions would never be deleted (Job uses `dependent: :nullify` for api_requests, not destroy). Collections are destroyed with their job.

**4. The only thing Pattern B adds over Pattern A is `status_code` and `raw_headers`.** In the managed flow, these are already handled: HTTP errors raise `UnexpectedResponseStatusCodeException` before any storage occurs. Successful responses always have the expected status code. Storing it in the collection adds nothing actionable.

**5. Memory profile is equivalent.** Both patterns load a page of data per worker execution. Pattern A loads data directly from MongoDB. Pattern B downloads a file from S3 then parses JSON — two I/O operations instead of one.

### Option 3 (Hybrid) is not justified

Saving to both collections AND ApiRequest/files doubles the write cost per page with no benefit to the transformer path. The only beneficiary would be post-hoc debugging of API call details (headers, raw body), but this information is already available during extraction when the exception is raised. The audit trail argument does not hold for the managed flow because: (a) errors abort immediately, and (b) successful responses always have the same status code.

### What needs to change

The API branch in all 24 `ManagedExtractorConsumer` files must be rewritten to:
1. Perform the HTTP request as today
2. Apply `collection_source_keys` and `sensitive_key` redaction as today
3. Save the processed collection via `job.{resource}_collections.create(raw: collection)` instead of writing to ApiRequest/files
4. Paginate with `collection_last_id` (cursor-based, as the database branch does) rather than the current `page` counter

This aligns the API branch with the database branch structurally, and makes the transformer agnostic to source type — which it already is by design.

---

## Next Steps

Investigation is complete. The findings identify a clear implementation path with no remaining technical unknowns.

Use `@agent-planner` to create a PLAN.md for rewriting the API branch in all `ManagedExtractorConsumer` workers to use the collection storage pattern.

Key implementation notes for planning:
- 24 worker files need the API branch rewritten
- Pagination cursor changes from `page` (integer counter) to `collection_last_id` (primary key value) — the `primary_attribute_mapping` is already fetched for cursor tracking
- `ApiRequest` and `ApiResponse` should NOT be created in the managed flow for API sources
- The managed transformer consumers require no changes
- No new models or infrastructure required

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
>
> **Further reading:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/technical-spike/)
