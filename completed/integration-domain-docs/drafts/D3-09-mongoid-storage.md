# Mongoid storage of resources, imports, and requests

The integrator's MongoDB holds three layers of state: configuration (covered in Chapter 5), the per-job Collections of raw extracted data (covered in Chapter 3), and the long-term audit trail of every record the integrator has ever pushed through. This chapter is about that audit trail — Resources, Imports, and Requests — and the storage decisions that make it queryable years after the fact.

## Three nested documents

The audit trail is one document tree per record:

```
Resource (top-level)
└── Imports (embedded array, one per Job that touched this Resource)
    └── Requests (embedded array, one per HTTP call in that Import)
```

A `Resource` represents a stable platform-side entity — a User, a Subsidiary, a Deal — identified by its `external_id` (the customer-side identifier the integrator emits). A new Resource is created the first time the integrator sees that external_id; subsequent appearances reuse the same document.

An `Import` is what happened to that Resource during one Job — the snapshot of the data that came in, plus references to the originating Stream and Job. Each Job adds one Import to each Resource it touches.

A `Request` is one HTTP call to the 4Shark API made on behalf of one Import — the request body, response status, response body, timestamp. Most Imports have exactly one Request (the create or update call); some have several when retries fired or when the resource type involves multiple API calls (a User registration followed by a separate identifier_promotions call).

The nesting is deliberate. A query for "what happened to user EMP-001 in the last six months" is one MongoDB lookup by `external_id` plus a filter on the embedded `imports` array — no joins. A query for "show me every API call we made for job_id=42" is a different shape (covered below) but still tractable.

## The Resource document

`Resource` is the spine. It carries:

- `external_id` — the customer-side identifier
- `_type` — the Resource subclass (`User`, `Deal`, `Subsidiary`, etc.). One of 15 types.
- `integration_status` — the state machine (Chapter 13): `pending`, `integrated`, `disabled`, `erased`, `unknown`. Default `pending`
- `model_version` — schema version of the data carried in Imports. Defaults to `'1.0'`; `User` overrides to `'3.0'`
- `imports` — embedded array of Import documents

Resources are indexed on `external_id` (for lookup), `(_type, external_id)` (for typed lookup), and on several embedded paths into Imports — `(imports.job_id, _type)`, `(imports.job_id, imports.data.type, _type)`, `(imports.requests.job_id, imports.requests.url, imports.requests.http_method)`. The indexes target the queries the integrator actually runs: per-job aggregations during the report stage, per-job retransmission lookups during retry, per-resource history during debugging.

## `Resource.get(external_id)` — find or restore

A Loader trying to push an Import for a Resource needs the Resource to exist on the integrator side first. `Resource.get(external_id)` does the lookup with a fallback:

1. Query MongoDB for a Resource with that external_id
2. If not found, attempt to **restore from S3** — the integrator periodically archives Resource documents to S3 as a long-term store, freeing MongoDB space on customers with millions of records. The S3 path is keyed by external_id; if a copy exists, it is parsed and re-inserted into MongoDB
3. If S3 has no copy either, create a stub Resource with just the external_id (the rest of the fields populate during the current run)

The S3-as-long-term-store is a real path. The integrator's MongoDB is sized for the active working set — the resources touched in recent jobs — not for the customer's entire history. A query about a Deal from three years ago triggers an S3 restore on demand. The customer never sees the difference; the platform cares because the alternative would be a MongoDB sized for unbounded growth.

## The Import document

`Import` is embedded under Resource and carries the per-Job snapshot:

- `data` — the post-mapping, post-JOIN body of the record. A Hash. This is what the integrator believes the record looks like at the moment of this Job.
- `model_version` — schema version of the Import's `data` field. Default `'2.0'`. Lets the codebase migrate the in-memory shape over time without breaking historical Imports
- `job_id`, `stream_id`, `api_request_id` — back-references to the originating Job and Stream, plus the API request the Import generated
- `requests` — embedded array of Request documents

`Import#request_body` delegates to `resource.request_body_for(self)` — the Resource subclass owns the logic that turns `data` into the JSON body the API receives. This indirection lets the Resource class control which fields of `data` go where, which fields go through `Source#user_id_from`, which are dropped, which are renamed.

A handful of helpers expose properties of the data without making the caller dig into the Hash:

- `upstream_id` — `data[:id]`, the raw id from the source
- `active?`, `inactive?` — `data[:active]` shortcut
- `primary?` — `data[:primary]` shortcut, used for UserIdentifier and similar
- `external_id?` — whether `data` carries an external_id
- `finish?`, `promotion?`, `demotion?`, `update_parent?`, `delete?`, `enable?` — type predicates for Resources whose data carries a `type` field discriminating the operation

## `Import#find_request` and `request_exists?`

Two helpers do MongoDB aggregation against the embedded `requests` to find a previous HTTP call in the audit trail. `request_exists?(job_id:, url:, http_method:)` returns true if the integrator has already made that exact request in the given Job. `find_request` returns the matching Request when it exists.

The combination acts as an idempotency net at the integrator side: if the same Import gets retried (Sidekiq redelivery, manual replay), the integrator can detect that the request was already sent and skip it, avoiding duplicate side effects on the API. The same mechanism is what powers the `X-Idempotency-Key` header the integrator emits on every state-changing call — the key is derived from the Request identity, and the API's idempotency cache handles the second copy gracefully even if the integrator-side check misses.

## The Request document

`Request` is embedded under Import. Fields:

- `url` — the API endpoint hit (full URL, not just the path)
- `http_method` — `POST`, `PUT`, `PATCH`, `DELETE`, `GET`
- `body` — the JSON request body, as sent
- `timestamp` — when the call was made
- `response` — embedded sub-document with `status` (HTTP code) and `body` (the response payload)
- `job_id` — back-reference to the Job

Every API call is preserved here. There is no log file to consult instead — this is the log. A customer asking "what request did the integrator send for user EMP-001 on January 15?" is answered by a single MongoDB query into the embedded array.

The choice to embed Requests under Imports rather than store them as a separate top-level collection is what makes the per-resource audit query fast. The trade-off is that high-traffic resources accumulate large embedded arrays — a Deal that gets retransmitted many times because of intermittent API errors carries every retry. In practice this is bounded because retries cap out quickly and most resources are touched once per Job.

## Per-job Collections — the Extract → Transform handoff

`Collection` is a top-level Mongoid document, separate from the Resource tree. There are 14 concrete subclasses (`UserCollection`, `DealCollection`, etc., one per Resource type that gets extracted). Each Collection is per-Job + per-Stream + per-page — one Collection document per page of extraction.

Fields:

- `job_id`, `stream_id` — what produced the page
- `source_type` — `'database'` or `'api'`
- `page` — the page index within the Stream's run
- `query` — the rendered Liquid query that produced the page (for DB Streams) or the URL (for API Streams)
- `status_code` — the API response code (for API Streams)
- `raw_body` — CarrierWave-attached file containing the page payload as JSON
- `raw_headers` — CarrierWave-attached file containing the response headers (for API Streams)
- `raw` — legacy inline Array field, no longer the primary path; kept for backward compatibility with older Collection documents that pre-date the file-based storage

The choice to store the raw payload as an attached **file** rather than as an inline Array in MongoDB is operational: payloads can be tens of MBs (a customer with hundreds of thousands of deals per page), and MongoDB does not handle large embedded arrays gracefully. The Carrierwave file lands in `tmp/raw_body_<id>.json` on the integrator's local filesystem during the Job; after the Job finishes, the report process can clean these up or archive them to S3 alongside the Resource archive.

The Transform stage reads from these files (`collection.raw_body.read`) rather than from the database, which is why the database stays small even when Job-volume is large. The Collections are the bridge between Extract and Transform; they are short-lived; they are not the audit trail.

## Why three layers of indirection

A simpler design would skip Collection entirely — extract directly into Imports, transform in place. The integrator does not do this for two reasons:

- **Collections preserve the raw upstream shape.** If a transformation bug corrupts an Import, the original page is still in the Collection and can be re-transformed without re-extracting from the customer's source. The customer database has been touched once per Job; everything else is operations on data already pulled.
- **Collections are per-page and per-Stream.** When N Streams feed the same ResourceType (the multi-Stream fan-out), the Collections keep the per-Stream raw bodies separate. A bug specific to one Stream can be debugged by reading that one Stream's Collections without disturbing the others.

The cost is one extra Mongoid document per page per Job. The benefit is a clean rewind point for any post-Extract operation.

## The audit query patterns

Three common queries motivate the index choices:

- **Per-Resource history.** "What happened to user EMP-001?" is `User.where(external_id: 'EMP-001').first.imports`. One lookup, no joins. The `(_type, external_id)` index serves this directly.
- **Per-Job aggregation.** "What did Job 42 push?" is the report query. Indexed paths: `imports.job_id`, `imports.job_id × _type`, `imports.job_id × imports.data.type × _type` (for the per-resource-type-per-error-type breakdown the customer-facing email assembles).
- **Per-request lookup.** "Did we already send POST /api/v3/deals for Job 42?" is `imports.requests.job_id × imports.requests.url × imports.requests.http_method`. Used by the idempotency check.

All three queries hit indexes by design. The integrator's MongoDB is read-heavy on these patterns and write-heavy on the Imports/Requests append paths; the indexes cover both sides.

## The README debug queries — direct examples

The integrator's `README.md` lists a handful of canonical Mongo queries that map onto the indexes:

- `User.where('imports.job_id': 23, 'imports.requests.response.status': 422).pluck('imports.requests.response.body').uniq` — every distinct 422 response body for Job 23 across all Users. Useful for spotting the pattern of validation failures.
- `User.where('imports.job_id': 23, 'imports.requests.response.status': 422, 'imports.requests.response.body.cpf': "já está em uso").count` — count of one specific validation error for one Job. The error body text matches because the API returns Portuguese error messages with stable wording.
- `Groupification.not_in('imports.job_id': 23, 'imports.requests.response.status': 422).count` — successful (non-422) Groupifications for Job 23.

These shapes are not officially documented as a public API; they are operational queries the on-call engineer runs by hand. The fact that they are short — one line each — is the payoff for the embedded-document choice. A normalized schema with foreign keys would require multiple joins to answer the same question.

## Summary

Resources, Imports, and Requests form a three-level nested document tree, indexed for per-resource history and per-job aggregation. Collections sit alongside as the raw-data buffer between Extract and Transform, with payloads in attached files rather than embedded arrays. S3 backs the long-term archive for resources that fall out of the active window. The whole thing is designed to be queried by hand from the Mongo console, because that's where the on-call engineer ends up when a customer asks "did this run?".
