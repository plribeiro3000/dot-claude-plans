# Integrator performance — execution plan (measured levers)

Derived from the 3-run study (§ 00, § 01). Every size below is `sum(duration)` measured in New Relic across a run, so it is the real wall-time the work holds, not an estimate. Attack order is most-value-first, adjusted for dependency: a lever the integrator can deliver alone outranks one gated on another service, when the certain value is comparable.

## The three levers, ranked by measured value

### Lever 1 — Batch the outbound sends (largest measured cost; gated on the app API)

The send phase is the biggest total cost of a run: `User::SalesRep::LoaderConsumer` ~21,000 s (5,743 sends at ~3.7 s each, ~97% external) and `Modifier::LoaderConsumer` ~12,000–16,000 s, each send a single HTTP round-trip. This is the "100k individual round-trips → do it in fewer" archetype applied to the network.

The caveat that decides its size: a user send's 3.6 s is almost entirely the app CREATING the user server-side (`externalDuration` is the far side's time), not handshake or the integrator's own work. So the integrator cannot shrink the per-request cost; its only lever is **sending many per request**, which requires the app endpoints (`/api/v3/indicators` and the user endpoint) to accept a batch body. Whether they do is the open question that sets this lever's value, and it is the first thing to settle.

- Value: highest by raw measure (~33,000 s of the run in sends).
- Integrator-side: only the batching; the per-record server cost stays with the app.
- Dependency resolved — this lever is **app-side, not the integrator's**. Both `Api::V3::IndicatorsController` and `Api::V3::UsersController` are single-record (`resource :indicators`, `resources :users`, each `params.require(:indicator|:user)`); no endpoint accepts a batch body, so batching needs a new app-side endpoint. And the user send's 3.6 s is the app creating the user **synchronously** in the request: `current_company.users.new(...).save` inside a transaction, which hashes the password (bcrypt, deliberately slow) and cascades nested `identifiers_attributes` + `seat_attributes` (with a `UserIdentifier.get(...).user.seat.id` parent lookup). The indicator endpoint already offloads its heavy part (`Indicator::Processor.perform_async`) and returns fast — the user endpoint does not. So the two app-side moves are: add batch endpoints, and make user creation return before the heavy work (as the indicator endpoint does). Tracked as an **app** effort, separate from the integrator work below.

### Lever 2 — Eliminate the S3 cold-storage restore on a clean run (largest certain, integrator-only) — DELIVERED (integrator PR #2433, merged)

Shipped as `Integrator.hot_data_expired?` gating `Resource.get`'s S3 restore: on a load whose oldest run is still inside the hot-data window, nothing has aged into cold storage, so the per-record S3 GET is skipped. The remaining follow-up is mechanical — the restore-skip currently reaches the transform through `Resource.get`, which every transform consumer already calls, so no per-consumer wiring is outstanding.


In the transform, `Modifier.get(external_id)` on a wiped/first-load base does `find_by` miss → S3 GET → guaranteed 404 → `create!`, once per record. Measured at **66% of the transform** (~192 s of the 294 s per Modifier job in Run 3), ~14,000 s across the run counting the user transform too. On a first load the restore cannot succeed — the record was never archived — so every one of those S3 GETs is pure waste.

- Value: ~14,000 s, measured, certain.
- Integrator-side: fully. Gate the restore so it only runs once cold-storage has actually archived records (a first/clean load skips it).
- Dependency: none. **This is the one to start now.**

### Lever 3 — Collapse the per-record queries in the enrichment/transform — INVESTIGATED, NOT WORTH PURSUING

The "redundant per-record queries → collapse them" premise does not survive measurement. Every per-record Mongo op in the transform is an INDEXED, NECESSARY operation, not a redundant one:

- The transform's Mongo time is dominated by `Modifier::CustomCollectionConsumer` (Run 3: 61.3 s db/job × 67 = ~4,108 s db). That db is the per-record `Modifier.get` — `find_by(external_id)` (indexed: `Resource` carries `{ external_id: 1 }` and `{ _type: 1, external_id: 1 }`) — plus `import.save` (the write that persists the record). Both are necessary: the `find_by` deduplicates a record against ones already created earlier IN THE SAME RUN (a second collection can carry the same `external_id`), so it cannot be skipped even on a clean load — unlike the S3 GET, which was safe to skip because S3 is provably empty on a clean load while Mongo fills during it.
- The enricher's second read+write per record — the `Modifier::EnricherConsumer` that re-reads (`Modifier.find`) and re-saves each record — is measured at only **462 s total** (Run 3: 7,174 txns, 0.05 s db each). Folding it into the collection consumer would save that ~462 s at real architectural risk (enrichment-data ordering), so it is not worth it.
- `Enrichment.find_by(job_id, downstream_id, external_id)` is backed by a unique compound index on exactly those keys (`enrichment.rb`), so it is an index probe, not a COLLSCAN.
- The `Job.find(job_id)` in `EnricherConsumer` is genuinely redundant (the arg already carries the id) but it is one indexed `_id` lookup per record — sub-second aggregate, not a lever.
- The `User::SalesRep::EnricherConsumer` cost (Run 3: ~5,980 s) is ~65% `externalDuration` — reading each record's extracted enrichment file — which is inherent I/O of enrichment, not a redundant query.

Measured verdict: after Lever 2 removed the S3 restore, the transform is already lean; its remaining Mongo cost is necessary indexed work. There is no safe, meaningful integrator-only optimization here.

## Not worth doing (measured too small)

The Ruby/CPU hoists (the closed PR #2432) are ~13% of the transform; HTTP keep-alive removes only the handshake (~tens of ms) against a 3.6 s app-side send. Both deprioritized.

## Attack order

1. **Lever 2 (S3 restore) — DELIVERED** in integrator PR #2433 (merged). ~14,000 s, certain, integrator-only.
2. **Lever 3 (query collapse) — next integrator-side item:** per-record `Job.find` / `Modifier.find` / `import.stream` / `Enrichment.find_by` on the enrichment hot path, ~4,000 s, no dependency. The remaining integrator-only lever.
3. **Lever 1 (batch sends) — app-side, cross-repo:** the app-API answer is in (both endpoints are single-record and the user endpoint creates synchronously), so this is an **app** effort — add batch endpoints and make user creation return before the heavy work. Largest raw measure (~33,000 s), but it lives in the `app` repo, not the integrator.
