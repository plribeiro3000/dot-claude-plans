# SPIKE — Unified extraction architecture across the three integration flows

**Conducted by:** Paulo Ribeiro
**Date:** 2026-04-01
**Status:** Research complete — pending decisions

---

## Goal

Map the three integration flows (Self-Service, API, Managed) end-to-end and propose a unified
architecture that addresses the engineer's four design questions:

1. **Extraction storage** — what should the managed flow use for raw response storage?
2. **Collection.raw as S3** — is it viable to move the `raw` field to S3 without breaking
   self-service aggregation?
3. **Separation of concerns** — should `collection_source_keys` and `sensitive_keys` move from
   the extractor to the transformer?
4. **Self-service vs managed transformer** — can the aggregation-based and iteration-based
   approaches be unified?

This spike synthesises prior research from two completed spikes
(`managed-extraction-storage` and `raw-response-storage`) with a full codebase reading of every
relevant worker, model, and configuration file.

---

## Method

- Read all three prior planning documents: KNOWLEDGE.md, PROCESS.md, DOMAIN.md
- Read both prior spikes in full
- Read every worker file for all three flows (Subsidiary as representative resource)
- Read every model involved: `Collection`, `SubsidiaryCollection`, `ApiRequest`, `ApiResponse`,
  `Job`, `Import`, `Connector`, `Source`, `ApiSource`, `DatabaseSource`, `Stream`, `S3`
- Read all uploader files and the CarrierWave initializer
- Read the entry-point workers: `ApiIntegrator`, `ManagedIntegrator`

---

## Evidence

### 1. Flow maps — exact method calls per phase

#### Flow 1: Self-Service (database workers)

Entry: `DatabaseIntegrator` (not read — out of scope)

**Extract — `Subsidiary::DatabaseExtractor#perform(job_id, collection_last_id)`**

```
Database.connect!
connection.page(:subsidiaries, conditions, collection_last_id)
  → SQL: SELECT * FROM fsk_subsidiaries WHERE updated_at >= ? AND id > ? LIMIT page_size
job.subsidiary_collections.create(raw: raw_collection)
  → SubsidiaryCollection { raw: Array<Hash> }
collection_last_id = raw_collection.last[:id]
Subsidiary::DatabaseExtractor.perform_async(job_id, collection_last_id)  # recurse pages
  OR
Hierarchy::DatabaseExtractor.perform_async(job_id)  # advance pipeline
```

Storage written: `SubsidiaryCollection.raw` (MongoDB Array field)
Pagination: cursor-based on `id` column

**Transform Producer — `Subsidiary::DatabaseTransformerProducer#perform(job_id)`**

```
job.subsidiary_collections.first.job_resource_quantity
  → MongoDB aggregation: $match job_id, $unwind $raw, $group count
job.computation.increment_queue(by: job_resource_quantity)
SubsidiaryCollection.pair_ids_for(job_id:)
  → MongoDB aggregation: $match job_id, $unwind $raw, $project collection_id + raw.id
Sidekiq::Client.push_bulk(Subsidiary::DatabaseTransformerConsumer, [[collection_id, raw_object_id], ...])
```

**Transform Consumer — `Subsidiary::DatabaseTransformerConsumer#perform(collection_id, raw_object_id)`**

```
SubsidiaryCollection.without(:raw).find(collection_id)
collection.find_raw_object(raw_object_id)
  → MongoDB aggregation: $match _id, $filter raw where raw.id == raw_object_id, $unwind, $replaceRoot
Subsidiary.get(raw_object[:id])
resource.imports.find_or_create_by(job_id: job.id.to_s)
import.update(data: raw_object)         # raw_object is the entire row hash, no mapping
job.computation.increment_executions
  → if done? → Hierarchy::DatabaseTransformerProducer.perform_async
```

Key observations:
- No attribute mapping in self-service transform: `import.update(data: raw_object)` — uses the
  row as-is because the `fsk_*` schema IS the canonical format
- No `collection_source_keys` — the SQL query returns a flat array of rows directly
- No `sensitive_keys` redaction — assumed clean by schema contract
- One Sidekiq job per `(collection_id, raw_object_id)` pair — fine-grained parallelism
- `find_raw_object` uses MongoDB aggregation to avoid loading the full `raw` array into Ruby memory

**Load — `Subsidiary::LoaderProducer` + `Subsidiary::LoaderConsumer`** (shared with all flows)

---

#### Flow 2: API workers

Entry: `ApiIntegrator` → `HealthCheck::Processor` → `ConnectionCheck::Processor`

**Extract — `Subsidiary::ApiExtractor#perform(job_id)` (loop per connector)**

```
Stream.where(resource_name: 'Subsidiary').enabled.first
stream.connectors.pluck(:id)
connector = Connector.find(connector_id)
primary_attribute_mapping = connector.attribute_mappings.find_by(primary: true)
sensitive_keys = connector.sensitive_keys
source = connector.source   # ApiSource
source.authenticated_headers  # → Authentication#authenticated_headers
URI(connector.uri)

loop:
  Variables.new(job, source).to_h  # job-level variables (fetch_since, timezone, etc.)
  variables.merge({ 'page' => page, 'previous_record_id' => previous_record_id })
  connector.query(variables)  # Liquid template rendering → URI query string
  http_client.get(uri.request_uri, headers)
  connector.unexpected_response?(http_response.code)  # raises UnexpectedResponseStatusCodeException

  ApiRequest.find_or_initialize_by(connector_id:, job_id:, page:)
  api_request.save!
  api_response = api_request.build_response
  api_response.status_code = http_response.code

  parsed_response = JSON.parse(http_response.body.force_encoding('UTF-8'))

  # --- collection_source_keys applied IN EXTRACTOR ---
  collection = parsed_response.dig(*connector.collection_source_keys)

  # --- sensitive_keys redaction applied IN EXTRACTOR ---
  collection.each { |item| sensitive_key.path.inject(item, :fetch)[key] = nil }

  previous_record_id = collection.last[primary_attribute_mapping.source]

  # Writes parsed_response (NOT http_response.body) to S3 via CarrierWave
  File.new(api_request.response.raw_body_path, 'w+')  # tmp/raw_body_{id}_page_{page}.json
  local_raw_body_file.write(parsed_response.to_json)   # NOTE: re-serialised parsed JSON
  api_response.raw_body = local_raw_body_file
  # Also writes headers to S3
  api_response.save!  # → CarrierWave uploads to S3

  break if source.last_page?(page_collection_size)
```

Storage written:
- `ApiRequest` (MongoDB): `connector_id`, `job_id`, `page`, `uri`
- `ApiResponse` (embedded): `status_code`, `raw_body` file in S3, `raw_headers` file in S3
- S3 path: `jobs/{job_id}/{resource_name}/raw_body_{id}_page_{page}.json`
- **No `SubsidiaryCollection` written — the transformer reads from S3, not collections**

Critical gap: `collection` (the extracted records after `collection_source_keys`) is computed in
the extractor but NOT saved anywhere accessible. The transformer re-reads `parsed_response` from
S3 and re-applies `collection_source_keys` again. This is duplicated work.

**Transform — `Subsidiary::ApiTransformer#perform(job_id)` (loop per connector, per api_request)**

```
stream.connectors.pluck(:id)
connector = Connector.find(connector_id)
api_request_ids = connector.api_requests.where(job_id: job_id).pluck(:id)

api_request_ids.each do |api_request_id|
  api_request = ApiRequest.find(api_request_id)
  raw_body = api_response.raw_body.read    # S3 download → full JSON body into memory
  parsed_body = JSON.parse(raw_body.force_encoding('UTF-8'))

  # --- collection_source_keys applied AGAIN IN TRANSFORMER ---
  raw_collection = parsed_body.dig(*connector.collection_source_keys)

  raw_collection.each do |raw_object|
    # simple attribute mappings (kind 0,1): static traversal/fixed values
    # compound attribute mappings (kind 2,3): Liquid template / Dentaku formula
    attributes = { ... }

    subsidiary = Subsidiary.get(attributes['external_id'])
    import = subsidiary.imports.find_or_initialize_by(job_id: job_id)
    import.data = attributes
    import.api_request_id = api_request.id   # traceability link
    import.save!
  end
end
Hierarchy::ApiTransformer.perform_async(job_id)
```

Key observations:
- Transformer downloads entire S3 file into Ruby memory for each page (one file = one API response)
- `collection_source_keys` is applied twice: once in extractor, once in transformer
- `sensitive_keys` redaction was done in extractor — transformer does NOT redact again
- Attribute mappings ARE applied in transformer (not extractor) — correct separation
- `import.api_request_id` links import to the source ApiRequest — audit traceability

---

#### Flow 3: Managed workers

Entry: `ManagedIntegrator` → health checks `DatabaseSource.all`

**Extract Producer — `Subsidiary::ManagedExtractorProducer#perform(job_id)`**

```
stream_ids = Stream.where(resource_name: 'Subsidiary').enabled.pluck(:id)
connector_ids per stream
arguments = [[job_id, stream_id, connector_id], ...]
total_connectors = Connector.where(stream_id: stream_ids).count
job.computation.increment_queue(by: total_connectors)
Sidekiq::Client.push_bulk(Subsidiary::ManagedExtractorConsumer, arguments)
```

**Extract Consumer — `Subsidiary::ManagedExtractorConsumer#perform(job_id, stream_id, connector_id, collection_last_id)`**

The consumer branches on source type:

```
if connector.source.is_a?(DatabaseSource)
  # --- DATABASE BRANCH ---
  connection = stream.source.connect!   # Sequel connection via DatabaseSource
  dataset = connection.fetch(Sequel.lit(query))
  dataset = dataset.where(fetch_since_column >= fetch_since)
  dataset = dataset.where(primary_key > collection_last_id.to_i)  if collection_last_id
  dataset = dataset.order(primary_key).limit(page_size || sql_page_size)
  raw_collection = dataset.to_a

  if raw_collection.size.positive?
    job.subsidiary_collections.create(raw: raw_collection)
    collection_last_id = raw_collection.last[primary_key]
    Subsidiary::ManagedExtractorConsumer.perform_async(job_id, stream_id, connector_id, collection_last_id)
  else
    job.computation.increment_executions
    Hierarchy::ManagedExtractorProducer.perform_async(job_id) if job.computation.done?
  end

else  # --- API BRANCH (BUG — writes to ApiRequest/S3, but transformer reads collections) ---
  # ... identical HTTP logic to ApiExtractor ...
  # Writes to ApiRequest + S3 files
  # Does NOT write to job.subsidiary_collections
  job.computation.increment_executions
  Hierarchy::ManagedExtractorProducer.perform_async(job_id) if job.computation.done?
end
```

**Transform Producer — `Subsidiary::ManagedTransformerProducer#perform(job_id)`**

```
stream_ids = Stream.where(resource_name: 'Subsidiary').enabled.pluck(:id)
connector_ids per stream
arguments = [[job_id, stream_id, connector_id], ...]
total_connectors = Connector.where(stream_id: stream_ids).count
job.computation.increment_queue(by: total_connectors)
Sidekiq::Client.push_bulk(Subsidiary::ManagedTransformerConsumer, arguments)
```

Note: the producer issues one consumer per connector — not per raw object. Fundamental difference
from self-service (which issues one consumer per raw_object_id via pair_ids_for).

**Transform Consumer — `Subsidiary::ManagedTransformerConsumer#perform(job_id, stream_id, connector_id)`**

```
job = Job.find(job_id)
connector = Connector.find(connector_id)
variables = Variables.new(job, connector.source)

# --- Reads ALL collections for this job (no filter by stream or connector) ---
job.subsidiary_collections.each do |collection|
  collection.raw.each do |raw_object|
    # simple + compound attribute mappings applied
    attributes = { ... }
    resource = resource_class.get(attributes['external_id'])
    import = resource.imports.find_or_initialize_by(job_id: job_id)
    import.data = attributes
    import.save!           # NO api_request_id — no traceability
  end
end

job.computation.increment_executions
Hierarchy::ManagedTransformerProducer.perform_async(job_id) if job.computation.done?
```

Key observations:
- Loops `job.subsidiary_collections.each` — loads ALL collection documents (and their `raw`
  arrays) into Ruby memory, one document at a time. No aggregation-based optimisation.
- Does NOT filter collections by `stream_id` or `connector_id` — if there are multiple connectors
  for the same resource, the same collections are iterated by every consumer. This is a data
  multiplication bug.
- `sensitive_keys` NOT applied in managed transformer — raw_object goes through attribute mappings
  directly. Sensitive key redaction must have happened in the extractor (database branch never
  does it; API branch of extractor does it before saving).

---

### 2. Differences between the three flows

| Dimension | Self-Service | API | Managed |
|---|---|---|---|
| **Entry point** | `DatabaseIntegrator` | `ApiIntegrator` | `ManagedIntegrator` |
| **Health check** | telnet + DB permissions | `HealthCheck::Processor` + `ConnectionCheck::Processor` | `source.health_check.reachable?` per `DatabaseSource` |
| **Extraction unit** | One worker per page | One worker for all pages (inner loop) | One consumer per connector (inner loop for DB, recursive for API) |
| **DB connection** | `Database.connect!` (global singleton, fsk_* schema) | n/a | `stream.source.connect!` (per-source Sequel) |
| **API connection** | n/a | `Net::HTTP` in ApiExtractor | `Net::HTTP` in ManagedExtractorConsumer |
| **Pagination (DB)** | Cursor on `id` (recursive workers) | n/a | Cursor on `primary_key` (recursive workers) |
| **Pagination (API)** | n/a | `source.last_page?(page_size)` + integer `page` counter | Same as API flow |
| **collection_source_keys** | Not applicable | Applied in **extractor AND transformer** (duplicate) | Applied in **extractor only** (API branch) |
| **sensitive_keys** | Not applicable | Applied in **extractor** | Applied in extractor (API branch only) |
| **attribute_mappings** | NOT applied — row used as-is | Applied in transformer | Applied in transformer |
| **Raw storage** | `SubsidiaryCollection.raw` (MongoDB Array) | `ApiRequest` + `ApiResponse` S3 files | DB branch: `SubsidiaryCollection.raw`; API branch: `ApiRequest` + S3 (bug — transformer ignores) |
| **Transformer unit** | One Sidekiq job per `(collection_id, raw_object_id)` | One job for all pages per connector | One job per connector (iterates all collections) |
| **Transformer reads** | `collection.find_raw_object` (MongoDB aggregation) | S3 file download + JSON parse | `collection.raw.each` (loads full array into Ruby) |
| **Memory profile** | Low — aggregation returns one object | Medium — one full S3 file per job | High — all collections × raw.each loaded per connector |
| **Import traceability** | No `api_request_id` | `import.api_request_id` set | No `api_request_id` |
| **Concurrent transformers safe?** | Yes — one worker per distinct raw_object | Yes — one worker per api_request | No — multiple connectors iterate same collections |

---

### 3. The managed transformer multi-connector bug

In `ManagedTransformerConsumer`, when there are multiple connectors for the same stream:

- Producer dispatches N consumers, one per connector
- Each consumer calls `job.subsidiary_collections.each` — iterating ALL collections
- If there are 2 connectors, each record is processed twice → 2 imports per resource per job

This is a data correctness bug, separate from the API branch storage bug.

---

### 4. Separation of concerns analysis

The engineer's principle: extractor = fetch + paginate + save raw; transformer = interpret + map + save.

Current violations:

| Responsibility | Should be in | Currently in | Flow |
|---|---|---|---|
| `collection_source_keys` extraction | Transformer | Extractor | API, Managed API |
| `collection_source_keys` extraction | Transformer | Transformer | API (also duplicated here) |
| `sensitive_keys` redaction | Transformer | Extractor | API, Managed API |
| Attribute mappings | Transformer | Transformer | All — correct |
| Pagination | Extractor | Extractor | All — correct |
| HTTP auth headers | Extractor | Extractor | All — correct |

The API extractor (`Subsidiary::ApiExtractor`) applies `collection_source_keys` and
`sensitive_keys` before writing to S3. The transformer then re-reads from S3 and applies
`collection_source_keys` again. This means:
- The extractor stores the FULL parsed response (including non-collection data)
- The transformer re-parses and re-extracts the collection portion
- `sensitive_keys` redaction happens once in the extractor — the transformer never redacts

If the extractor stored only the extracted collection (after `collection_source_keys`) and without
sensitive fields (after `sensitive_keys` redaction), the transformer's job would be simpler.
But this would compromise the audit trail's fidelity — you'd be storing already-processed data
rather than the raw response from the source system.

**The audit trail requirement and the separation-of-concerns principle are in tension here.**

The raw response (for audit) must include the full API body before any processing. The transformer
needs only the extracted, redacted collection. These are two different storage artefacts:

1. **Audit storage** — full raw response, exactly as received, write-once, S3
2. **Pipeline storage** — extracted + redacted collection, used by transformer, MongoDB Collection

Keeping both is the only way to satisfy both requirements simultaneously.

---

### 5. Collection.raw as S3 viability

The engineer considered replacing `Collection.raw` (MongoDB Array field) with a method that reads
from S3, so all raw storage is unified.

This breaks self-service:

- `SubsidiaryCollection.pair_ids_for(job_id:)` uses `$unwind: '$raw'` in MongoDB aggregation
- `collection.find_raw_object(raw_object_id)` uses `$filter` and `$replaceRoot` on `$raw`
- `collection.job_resource_quantity` uses `$unwind: '$raw'` + `$group: $sum`

All three rely on `raw` being a native MongoDB Array field. If `raw` is moved to S3:
- These aggregations cannot execute — MongoDB cannot aggregate a field that lives in S3
- The self-service transformer producer (`pair_ids_for`) would have to download all pages from S3
  and enumerate objects in Ruby to build the dispatch arguments
- This destroys the memory-efficient, single-aggregation design of the self-service transformer

**Verdict: Collection.raw must remain a MongoDB Array field for the self-service flow.**

If the engineer wants S3 storage for database-sourced raw responses, that must be a separate
storage artefact alongside the Collection, not a replacement for it.

---

### 6. Self-service vs managed transformer — unification analysis

Self-service transformer:
- Dispatches one Sidekiq job per `(collection_id, raw_object_id)` pair
- Each job uses MongoDB aggregation to fetch exactly one raw object — minimal memory
- Fine-grained parallelism — 1000 records = 1000 parallel Sidekiq jobs
- No attribute mapping — raw object IS the canonical data

Managed transformer:
- Dispatches one Sidekiq job per connector
- Each job iterates all collections (`job.subsidiary_collections.each`) — loads full arrays
- Coarser parallelism — N connectors = N Sidekiq jobs, each doing all the work
- Attribute mapping applied per object — transformation logic

These cannot be unified without changing the managed transformer's dispatch unit from
"per connector" to "per (collection_id, raw_object_id)". This is feasible but non-trivial:

- Managed transformer producer would call `SubsidiaryCollection.pair_ids_for(job_id:)` just like
  the self-service producer
- Managed transformer consumer would receive `(collection_id, raw_object_id, connector_id)` and
  apply attribute mappings from the given connector
- Problem: which connector maps to which raw_object? Multiple connectors can exist per stream,
  each potentially extracting different fields. The pairing of `(raw_object, connector)` is not
  straightforward unless there is a 1:1 relationship between the collection page and the connector
  that produced it.

Currently, `SubsidiaryCollection` has no field indicating which connector produced it. Unifying
the dispatch model would require adding a `connector_id` field to `Collection` so the transformer
knows which attribute mappings to apply for each object.

---

### 7. Future source types (FTP, CSV, Excel)

The current storage options and their compatibility:

| Source type | MongoDB Collection | S3 (CarrierWave) | S3 (direct) |
|---|---|---|---|
| Database (SQL) | Yes — rows as Array<Hash> | Yes — JSON serialisation of rows | Yes |
| API (HTTP JSON) | Yes — parsed JSON as Array<Hash> | Yes — raw HTTP body or parsed JSON | Yes |
| FTP/CSV | Yes — parsed rows as Array<Hash> | Yes — raw file bytes | Yes |
| Excel | Yes — parsed rows as Array<Hash> | Yes — raw .xlsx bytes | Yes |
| XML API | Yes — parsed nodes as Array<Hash> | Yes — raw XML bytes | Yes |

MongoDB Collection is viable for all source types as pipeline storage (after parsing into
Array<Hash>). S3 is the correct backend for audit storage of any binary or text format.

---

### 8. The `Import.identifier` mode check

`Import#identifier` contains:
```ruby
if ApplicationConfiguration.managed_integration?
  data[:id]
else
  "4sk_#{data[:id]}"
end
```

This branching exists because self-service data comes pre-prefixed with `4sk_` in the `fsk_*`
schema, while managed data uses the source system's native ID. This is a model-layer coupling to
integration mode that should be eliminated as part of the DOMAIN.md plan.

---

## Conclusions

### Finding 1 — The managed API branch has two bugs

**Bug A (data loss):** The managed extractor API branch writes to `ApiRequest`/S3. The managed
transformer reads from `job.subsidiary_collections`. These never connect. API-sourced data in the
managed flow is silently discarded during transformation. This is confirmed by prior spike
`managed-extraction-storage`.

**Bug B (data multiplication):** The managed transformer dispatches one consumer per connector,
but each consumer iterates ALL collections for the job regardless of which connector produced them.
With N connectors, each record is processed N times.

### Finding 2 — collection_source_keys is applied twice in the API flow

The API extractor applies `collection_source_keys` to extract the relevant array, then writes
`parsed_response.to_json` (the FULL response, not just the extracted collection) to S3. The
transformer reads from S3 and applies `collection_source_keys` again. This is redundant and
confirms that the extractor and transformer are not clearly separated: the extractor does
interpretation work (extracting the collection) that belongs to the transformer.

### Finding 3 — The audit trail and the pipeline storage serve different masters

These are distinct artefacts:
- **Audit storage**: full raw response, before any processing, for compliance proof. Lives in S3.
  Write-once. Never mutated. Scope: what did the source system send?
- **Pipeline storage**: extracted, redacted collection in `Collection.raw`. MongoDB Array. Used
  by transformers. Scope: what data flows through the pipeline?

The current API flow stores audit data only (S3) and has no pipeline storage. The current database
flows store pipeline data only (Collection.raw) and have no audit storage. A unified architecture
needs both, separated by purpose, for all source types.

### Finding 4 — Collection.raw must remain a MongoDB Array field

The self-service transformer's aggregation-based design (`pair_ids_for`, `find_raw_object`,
`job_resource_quantity`) is tightly coupled to `raw` being a MongoDB native Array. Moving it to
S3 would force a full rewrite of the self-service transformer to load data into Ruby memory —
losing the memory-efficiency benefit that motivated the aggregation approach. This is not
recommended.

### Finding 5 — Unified architecture: S3 audit + Collection.raw pipeline for all flows

The correct unified architecture separates audit storage from pipeline storage for every flow:

```
EXTRACTOR:
  1. Fetch raw data from source (HTTP, SQL, FTP, etc.)
  2. Write raw response to S3 (audit trail — one object per page)
  3. Parse raw response into Array<Hash>
  4. Write parsed array to Collection.raw (pipeline storage)
  5. Paginate

TRANSFORMER:
  1. Read from Collection.raw (pipeline storage)
  2. Apply collection_source_keys to extract the relevant array (API sources only)
  3. Apply sensitive_keys redaction
  4. Apply attribute_mappings
  5. Save Import
```

Under this model:
- The extractor is responsible ONLY for: fetch + save raw to S3 + save parsed to Collection
- The transformer is responsible ONLY for: read from Collection + interpret + map + save Import
- `collection_source_keys` moves entirely to the transformer (removed from extractor)
- `sensitive_keys` moves entirely to the transformer (removed from extractor)
- S3 stores the true raw response before any processing — audit fidelity is maximised
- Collection.raw stores the parsed rows/objects — transformer reads without S3 I/O
- All source types (API, database, FTP, CSV) follow the same two-store pattern

### Finding 6 — The managed transformer dispatch unit must change

The current "one consumer per connector" dispatch has the data-multiplication bug. The fix requires:
1. Adding `connector_id` to `Collection` (or to a new `CollectionPage` model) so the transformer
   knows which connector produced each page
2. Dispatching transformer consumers per `(collection_id, raw_object_id, connector_id)` — the
   same granularity as self-service, extended with connector context
3. This allows the managed transformer to use `find_raw_object` (aggregation-based, memory-safe)
   exactly like self-service, plus apply the attribute mappings from the specified connector

This change unifies the dispatch model between self-service and managed transformers. The only
difference would be: self-service consumer does no attribute mapping; managed consumer applies
attribute mappings from the connector.

### Finding 7 — The API extractor stores parsed JSON, not raw bytes

`ApiExtractor` calls `local_raw_body_file.write(parsed_response.to_json)` — this is a
re-serialisation of the already-parsed JSON, not the original HTTP response body. For JSON APIs
this is functionally equivalent. For XML or other encodings, this loses fidelity. True audit
storage should write `http_response.body` directly. This is a minor correction identified in
prior spike `raw-response-storage`.

---

## Proposed unified architecture

### What changes per layer

#### Models

| Model | Change | Reason |
|---|---|---|
| `Collection` | Add `connector_id` field (optional — nil for self-service) | Enables transformer to know which connector produced each page; required for per-object dispatch in managed flow |
| `Collection` | Add `source_type` field (`:database`, `:api`, `:ftp`, etc.) | Enables observability and potential routing logic without inspecting connector |
| `ApiRequest` | Retain as audit record — no change to structure | Purpose is audit, not pipeline; lifecycle stays as-is |
| `ApiResponse` | Fix: write `http_response.body` instead of `parsed_response.to_json` | True audit fidelity; one-line change in extractors |
| `Import` | Remove `ApplicationConfiguration.managed_integration?` check from `identifier` | Part of DOMAIN.md migration plan; replace with explicit mode on IntegratorConfiguration |

New model needed: `DatabaseRequest` (if database audit trail is required — see open questions)

#### Extractors (all flows)

| Worker | Change | Reason |
|---|---|---|
| `Subsidiary::ApiExtractor` | Remove `collection_source_keys` extraction | Moves to transformer |
| `Subsidiary::ApiExtractor` | Remove `sensitive_keys` redaction | Moves to transformer |
| `Subsidiary::ApiExtractor` | Write `http_response.body` to S3 instead of `parsed_response.to_json` | Audit fidelity |
| `Subsidiary::ApiExtractor` | After writing to S3, parse response and save to `SubsidiaryCollection.raw` | Pipeline storage so transformer can read from Collection |
| `Subsidiary::ApiExtractor` | Set `collection.connector_id` on create | Traceability for transformer dispatch |
| `Subsidiary::ManagedExtractorConsumer` (API branch) | Same 4 changes as ApiExtractor | Bug fix + alignment |
| `Subsidiary::ManagedExtractorConsumer` (DB branch) | Set `collection.connector_id` on create | Traceability for transformer dispatch |
| `Subsidiary::DatabaseExtractor` | Set `collection.connector_id = nil` (self-service has no connector) | Explicit null — no functional change |
| All extractors | Optionally: add `DatabaseRequest`/`DatabaseResponse` for DB audit trail | See open question 1 |

#### Transformers (all flows)

| Worker | Change | Reason |
|---|---|---|
| `Subsidiary::ApiTransformer` | Remove S3 download + JSON re-parse | Reads from Collection.raw instead |
| `Subsidiary::ApiTransformer` | Apply `collection_source_keys` extraction | Moved from extractor |
| `Subsidiary::ApiTransformer` | Apply `sensitive_keys` redaction | Moved from extractor |
| `Subsidiary::ApiTransformer` | Reads from `Collection` instead of `ApiRequest` | Unified read path |
| `Subsidiary::ApiTransformer` | Retain `import.api_request_id` link | Audit traceability preserved |
| `Subsidiary::ManagedTransformerConsumer` | Change dispatch from per-connector to per-(collection_id, raw_object_id, connector_id) | Fix data multiplication bug |
| `Subsidiary::ManagedTransformerConsumer` | Use `find_raw_object` aggregation | Memory safety |
| `Subsidiary::ManagedTransformerConsumer` | Apply `collection_source_keys` (API sources) | Moved from extractor |
| `Subsidiary::ManagedTransformerConsumer` | Apply `sensitive_keys` | Moved from extractor |
| `Subsidiary::ManagedTransformerProducer` | Dispatch using `SubsidiaryCollection.pair_ids_for(job_id:)` + connector_id | Match new consumer signature |
| `Subsidiary::DatabaseTransformerConsumer` | No change — already correct | Self-service flow is the reference implementation |

#### Loaders

No changes. The loader is already source-agnostic and operates on `Resource`/`Import`. This is
the architectural pattern the extractor and transformer layers should aspire to.

---

## Open questions for the engineer to decide

### Question 1 — Is a database audit trail required?

The `raw-response-storage` spike found that database extractors have NO audit trail — only
`Collection.raw` (pipeline storage). Adding database audit storage would require:
- New `DatabaseRequest` + `DatabaseResponse` models (or equivalent)
- Storing the SQL query, page parameters, and raw result set to S3
- Additional writes per extraction page

**Trade-off:** Compliance value vs implementation cost. The engineer must decide if database
sources need the same audit trail as API sources, or if the lack of HTTP semantics (no status
code, no headers) makes the audit case weaker for database sources.

If YES: design a `DatabaseRequest`/`DatabaseResponse` pattern (simpler: use `S3.store` directly
without CarrierWave — less code, same infrastructure).
If NO: database extractors continue writing only to `Collection.raw`. No audit trail for database
sources.

### Question 2 — Should collection_source_keys move to the transformer for the API flow?

The proposed architecture moves `collection_source_keys` from the extractor to the transformer.
This means:
- The extractor saves the FULL parsed API response to Collection.raw (including non-collection wrapper)
- The transformer extracts the relevant array using `collection_source_keys`

**Implication for Collection.raw size:** Instead of storing only the extracted records array,
`Collection.raw` would store the full parsed API response. For most APIs, the wrapper is a small
metadata object (status, pagination info, data array). The data array is what matters. But the
overhead is real.

**Implication for aggregation:** The self-service aggregations (`pair_ids_for`, `find_raw_object`)
assume that every element of `raw` IS a record. If `raw` stores `{"data": [...], "meta": {...}}`,
the aggregation logic breaks. This means `collection_source_keys` must be applied BEFORE storing
to Collection.raw — which puts it back in the extractor.

**Resolution:** The extractor MUST apply `collection_source_keys` before saving to `Collection.raw`
if the Collection is to remain compatible with the aggregation methods. The extractor should save
only the extracted records array. The audit storage (S3) should save the full raw response BEFORE
`collection_source_keys` is applied. `sensitive_keys` can then move to the transformer (since
Collection.raw holds only extracted records, sensitive fields are still present until the
transformer redacts them).

This means the correct separation of concerns is:
- Extractor: fetch → write full raw to S3 → apply collection_source_keys → write records to Collection → paginate
- Transformer: read from Collection → apply sensitive_keys → apply attribute_mappings → save Import

### Question 3 — Should Collection gain a connector_id field?

Adding `connector_id` to `Collection` enables the managed transformer to use the same
per-(collection_id, raw_object_id) dispatch as self-service while knowing which connector
produced each record. However:
- Self-service collections have no connector (they come from `Database.connect!` with hardcoded
  `fsk_*` queries)
- A nil `connector_id` is valid for self-service
- The `pair_ids_for` aggregation would need to be extended to return connector_id for managed flow

**Alternative:** Instead of adding `connector_id` to Collection, create a new model
`CollectionPage` that records the connector_id and links to the collection document. This avoids
changing the Collection schema but adds a join.

The engineer must decide which approach is acceptable.

### Question 4 — Migration path for self-service flow

The self-service flow (`DatabaseExtractor`, `DatabaseTransformerProducer/Consumer`) is used by
production clients. Any change to the Collection schema or the transformer dispatch model could
affect running jobs.

The proposed architecture does NOT require changes to the self-service transformer logic — it
continues to work as-is. Changes are limited to: optionally adding `connector_id: nil` on
collection create (backward compatible), and the API/managed paths.

The engineer should confirm that the self-service flow is treated as frozen during this migration,
with API and managed flows being aligned independently.

### Question 5 — Fix the ApiResponse fidelity issue now or later?

The API extractor stores `parsed_response.to_json` instead of `http_response.body`. For all
current clients (JSON APIs) this makes no functional difference. Fixing it (write `http_response.body`)
changes the content of existing S3 audit files for future jobs — past audit files are unaffected.

This is a small one-line fix but must be scheduled to avoid confusion about what is stored in S3.
The engineer should decide if this is in scope for the current work or deferred.

---

## Risks

| Risk | Severity | Note |
|---|---|---|
| Managed transformer data multiplication bug is in production | High | Any managed client with multiple connectors per stream is importing duplicate records today |
| API branch of managed extractor discards data silently | High | Any managed client with API source sees zero records imported from API connectors |
| Collection schema change requires all workers redeployed atomically | Medium | Adding `connector_id` field to Collection in a running system requires deploying extractors and transformers together |
| Collection.raw size increase if full API response is stored pre-collection_source_keys | Low | Most APIs have small wrappers; conservative page sizes keep documents within MongoDB limits |
| S3 write cost increase (two writes per page instead of one) | Low | ~$22/year per client estimated in raw-response-storage spike |

---

## Next Steps

Investigation is complete. The findings present a clear unified architecture with four open
questions the engineer must decide before implementation can be planned.

After decisions are made, use `@agent-planner` to create a PLAN.md covering:
- Fix to managed API branch (Bug A — data loss)
- Fix to managed transformer dispatch (Bug B — data multiplication)
- Move `collection_source_keys` to extractor (pre-Collection storage) and `sensitive_keys` to
  transformer
- Addition of `connector_id` to Collection (if Question 3 is yes)
- Addition of database audit trail (if Question 1 is yes)
- Fix to `ApiResponse` fidelity (if Question 5 is in scope)

All 24 resource workers (including all User sub-roles) will need updates to any worker class
that changes its contract. The Subsidiary worker is the reference implementation — all others
follow the same pattern.

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
>
> **Further reading:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-responses/recipes/technical-spike/)
