# PLAN — Unified Integration Flow

> Reference: SPIKE.md, KNOWLEDGE.md, PROCESS.md, DOMAIN.md

## Domain Refinement (2026-04-10)

This plan was updated after a late-stage domain review. See the matching section in
KNOWLEDGE.md and DOMAIN.md for the full rationale. Key decisions that reshape Phases 4 and 5:

1. **`Connector` is deleted.** All its fields migrate to `Stream` (query_template,
   paginated_query_template, primary_key, fetch_since_column, page_size, collection_source,
   success_response_status_code, embedded attribute_mappings and sensitive_keys). `Connector.headers`
   is dead code — deleted outright, not migrated.
2. **`ResourceType` is a new first-class model.** Replaces `Stream.resource_name` String field.
   Holds `identifier_prefix` (moved from Source). `NORMALIZED_REGISTRY` constant lists the 14
   resource types needed for normalized bootstrap.
3. **`Stream.position` removed.** Execution order remains hardcoded in worker chain.
4. **Liquid render unified.** DB extractor reworked to consume Liquid-rendered SQL via
   `Stream#render_query(variables)`. The extended `Variables` class injects `page`,
   `previous_record_id`, `page_size` alongside its existing 32 date-derived keys.
5. **Rake task renamed** to `rake integration:normalized:bootstrap`. Creates ResourceTypes,
   Source, Authentication, HealthCheck, and Streams with pre-filled query templates.
6. **`Import.belongs_to :stream`** (not `:source`). Prefix resolution via
   `ResourceType.find_by(name: 'User').identifier_prefix` — not via `stream.resource_type`.
   Eliminates the `attr_writer` pattern and Sidekiq arg threading in loader consumers.
7. **`Resource.streams`** class method on each Resource STI subclass replaces
   `Stream.for_resource` scope. Producers use `Subsidiary.streams.enabled.pluck(:id)`.

## Objective

Unify all integration paths into a single managed flow. Three source types coexist in one
pipeline: normalized DB (bypass), custom query DB (mappings), API (mappings). Self-service
becomes a configuration of managed — a `DatabaseSource` with `normalized: true`. After the
work is complete, there is only ONE flow. The 44 self-service-specific workers are deleted.

## Current Situation

- Two parallel pipelines controlled by `INTEGRATION_MODE` env var: self-service (hardcoded
  `fsk_*` tables) and managed (config-driven via Source/Stream/Connector).
- Both follow the same 14-resource order and converge at the shared loading phase (25 steps).
- The managed flow already handles database and API sources via Source STI (ApiSource,
  DatabaseSource) after PRs #2087, #2088, #2090.
- Self-service still has 44 dedicated workers that will be deleted when absorbed.

## Scope

### In Scope

- Complete the unified managed worker tree (API + database consumers separated)
- **Delete `Connector` model and migrate all its fields to `Stream`** (2026-04-10)
- **Introduce `ResourceType` model** with `NORMALIZED_REGISTRY` constant (2026-04-10)
- **Rework DB extractor to use Liquid template render** (unified with API path) (2026-04-10)
- **Extend `Variables` class** with `page`, `previous_record_id`, `page_size` (2026-04-10)
- **Resource.streams class method** on each Resource STI subclass (2026-04-10)
- Bootstrap task (`rake integration:normalized:bootstrap`) to auto-generate ResourceTypes,
  DatabaseSource, DatabaseAuthentication, HealthCheck, and Streams (with query templates
  pre-filled) from existing env vars for self-service clients
- Add `normalized` flag to DatabaseSource, `identifier_prefix` to ResourceType (not Source),
  `table_prefix` to DatabaseSource
- Transformer bypass for normalized sources (no attribute mappings)
- Refactor `Import#user_identifier_prefix` to read from `ResourceType.find_by(name: 'User')`
  (no `attr_writer`, no Sidekiq arg threading)
- Absorb self-service pre-flight checks into ManagedIntegrator
- Delete all 44 self-service workers and related infrastructure
- Remove `INTEGRATION_MODE` env var and related methods
- Update rake tasks to work with sources

### Out of Scope

- Management interface updates (separate project)
- AI-assisted data discovery workflow
- Execution order UI (beyond hardcoded chain)
- Connection pool optimizations (future PR)

---

## Completed Phases

### Phase 1: Domain Model Restructure (PR #2087 — merged)

- Renamed `ExternalApplication` → `Source` (STI: `ApiSource`, `DatabaseSource`)
- Renamed `ExternalResource` → `Stream` (with `position` field)
- Renamed `ApplicationProgrammingInterface` → `Connector` (single class, no STI)
- `Authentication` STI: `DatabaseAuthentication`, `SalesForceAuthentication`, `TrackmobAuthentication`
- `HealthCheck` belongs to Source with unified `reachable?` (HTTP for API, TCP for database)
- Credentials moved from DatabaseSource to `DatabaseAuthentication` (encrypted via symmetric-encryption)
- Connector conditional validations via `api_source?`/`database_source?`
- All 48 worker files updated, views, controllers, routes, locales (3 languages), specs
- Source type selection via `?type=` query param, submenu buttons, `form_for` with `as: :source`
- 600 tests passing, rubocop clean, brakeman clean

### Phase 2: Adapter Refactoring + Stream Simplification + Managed Extraction (PR #2088 — merged)

- `ApplicationConfiguration.connection_params` — centralized hash based on adapter type
- `MicrosoftSqlAdapter` and `PostgresSqlAdapter` accept params override via `.merge(params)`
- `DatabaseSource#connect!` — returns adapter instance using `configuration` as override
- Existing self-service flow unchanged (adapters default to ApplicationConfiguration values)
- Removed `role` field from Stream — `resource_name` now unified (e.g., `User::Admin`)
- Updated 20 API workers from `Stream.where(role: 'Admin')` to `Stream.where(resource_name: 'User::Admin')`
- 24 `ManagedDatabaseExtractorProducer` + 24 `ManagedDatabaseExtractorConsumer` workers created
- `ManagedIntegrator` entry point with health check for all DatabaseSources

### Phase 3: Managed Transformation (PR #2090 — merged)

- 24 `ManagedDatabaseTransformerProducer` — same producer pattern as extraction
- 24 `ManagedDatabaseTransformerConsumer` — applies attribute mappings from SQL collections

### Phase 4: Unified Managed Workers (PRs #2087/#2088/#2090 verified 2026-04-07)

- Per-source consumers separated (`ManagedApiExtractorConsumer` for HTTP, `ManagedDatabaseExtractorConsumer` for Sequel)
- Producer dispatches by `connector.source.is_a?(DatabaseSource)`
- Source-agnostic transformer consumer (single class)
- `ManagedIntegrator` with health checks + inline API auth
- `Collection` model carries managed fields (connector_id, stream_id, source_type, raw_body, raw_headers)
- All legacy `ApiExtractor`, `ApiTransformer`, `ApiIntegrator` workers removed

### Phase 5: Self-Service Absorption — Steps 1–5 (PRs #2108, #2109, #2110, #2111, #2115, #2116 — merged)

- PR #2108: model fields (`normalized`, `identifier_prefix`, `table_prefix`)
- PR #2109: structural fix — Connector navigates via `stream.source`
- PR #2110: Import identifier prefix wiring (later partially superseded by #2120)
- PR #2111: transformer bypass for normalized sources (no mappings, parent lookup preserved)
- PR #2115: pre-flight pipeline (HealthCheck/Authorization producers/consumers/finalizers; `Preflight` model)
- PR #2116: rake tasks unified, `skip_throughput` flag

### Phase 5: Domain Refinement + Bootstrap (PR #2120 — merged 2026-05-05)

Implements the 2026-04-10 domain refinement together with the bootstrap rake task.

- `Connector` model deleted; all fields absorbed into `Stream`
- `ResourceType` introduced with `Integrator::NORMALIZED_SCHEMA` constant
- `identifier_prefix` lives on ResourceType (not Source)
- `Stream.position` and `Stream.resource_name` removed
- `Stream#render_query(variables)` unifies Liquid render for DB and API extractors
- `Variables` extended with `page`, `previous_record_id`, `page_size`
- `Resource.streams` class method replaces `Stream.for_resource` scope
- `Import.belongs_to :stream`; `user_identifier_prefix` resolves via `ResourceType.find_by(name: 'User')`
- Loader producer/consumer arg threading reverted (no `attr_writer`, no Sidekiq arg payload growth)
- `rake integration:normalized:bootstrap` — creates ResourceTypes, DatabaseSource, DatabaseAuthentication, HealthCheck, and 14 Streams (idempotent)
- Worker tree collapsed: `ManagedDatabase*`/`ManagedApi*`/`Managed*` renamed to `{api,database}_extractor_consumer`, `extractor_producer`, `transformer_{consumer,producer}` — no Managed prefix, only one flow
- New `SourceCheck`, `StreamCheck` supporting models; `health_check_report_mailer` replaced by `source_check_report_mailer`

### Phase 5: Source-Driven Database Config + Final Cleanup (PR #2174 — merged 2026-05-06)

Drove all database connection config from `DatabaseSource`; removed the
last remnants of the self-service flow.

- Adapters (`MicrosoftSqlAdapter`, `PostgresSqlAdapter`) accept params from any caller
- `DatabaseSource#connect!` returns adapter instance configured from its own fields
- Deleted: `DatabaseIntegrator`, `Database` (singleton), `DatabaseConnectionMiddleware`, 14 `DatabaseExtractor`, 14 `DatabaseTransformerProducer`, 14 `DatabaseTransformerConsumer` workers
- Deleted: `connection_check/processor.rb`, `connection_check_report/*` workers
- `DatabaseWarmer` rewritten as producer/consumer pair
- `INTEGRATION_MODE`, `integration_mode`, `self_service_integration?`, `managed_integration?`, `api_integration?`, `database_integration?` removed from `ApplicationConfiguration`
- `ThroughputCalculator` reads via `source.connect!`
- Obsolete env vars (`CLIENT_HOST`, `CLIENT_PORT`, `CLIENT_DATABASE`, `CLIENT_USERNAME`, `CLIENT_PASSWORD`, `DATABASE_ADAPTER`, `CLIENT_AZURE`, `CLIENT_TIMEOUT`) no longer read by app code — kept in env only by clients pre-bootstrap

---

## Migration Status: Code Complete, Staging Gate Pending

The unified integration flow is fully delivered for the data path AND
the operational path. There is now ONE flow. A normalized DB client is
just a `DatabaseSource` with `normalized: true`, configured by
`rake integration:normalized:bootstrap` from existing env vars.

A release-readiness review (2026-05-08) confirmed that all 24 streams
preserve extraction + transformation behavior and that the bootstrap
populates every required field. **No data-loss risk.** The review found
operational regressions which were addressed in Phase 6 (PRs #2181-#2185).

A second review (2026-05-08, after Phase 6) caught additional
release-readiness items — restored detail in `SourceCheckReport`, a
modeling fix in `Authorization::DatabaseConsumer`, mobile rendering of
all mailer views, and minor dead-code cleanup. These were addressed in
PRs #2186, #2187, #2188 (Phase 7 below).

**Only remaining item:** 6.6 staging validation of `fetch_since`
timezone semantics + visual verification of the mobile-card mailers
against a real client. No code work pending — runbook gate before the
release cut for the customer migration.

## Phase 6: Operational Hardening (CODE COMPLETE)

### Goal

Restore the operator-visibility behaviors of the legacy flow that were
not carried into the unified pipeline. Each scope shipped as its own
PR for incremental review.

### 6.1 — Job::Starter DB connection error reporting (PR #2182 — merged)

Wrapped `Job::Starter#perform`'s `normalized_source.connect!` in a
**method-level** rescue (per 4Shark style — no inline begin/rescue):

```ruby
rescue TinyTds::Error, Sequel::DatabaseConnectionError, Sequel::DatabaseError => e
  job.update(job_attributes)
  job.source_checks.find_by(source: normalized_source).update(reachability: :failed, failure: :connection_error, detail: e.message)
  SourceCheckReport::Producer.perform_async(job.id.to_s)
ensure
  Lock.delete(LOCK_KEY)
```

Routed via the new `SourceCheckReport` umbrella (chosen over restoring
the legacy `DatabaseConnectionReport`). Job aborts — same semantics as
legacy.

### 6.2 — DatabaseWarmer give-up + unblock (PR #2183 — merged)

Replaced `UnreachableDatabaseException` (deleted) with **silent give-up
after one retry**:

```ruby
if retry_count > 1
  computation.increment_executions
  Job::Starter.perform_async if computation.done?
  return
end
```

The warmer now acks the Computation counter and lets the chain advance
to `Job::Starter`. Connectivity failure is re-detected downstream:
`Job::Starter` rescues against the normalized source; `HealthCheck::Consumer`
runs an independent reachability probe against every other source. Both
feed into `SourceCheckReport`.

### 6.3 — StreamCheckReport umbrella (PR #2185 — merged)

Engineer chose **mode (a)** — skip-and-aggregate-email — preserving the
legacy "graceful degradation" semantic.

- Added `AvailabilityCheck::Finalizer` (new dispatch hop after the
  per-stream consumers) — fires `StreamCheckReport::Producer` if any
  `stream_checks.unsuccessful.any?`, then always fires `ThroughputProcessor`
- Added `StreamCheckReport::Producer/Consumer` + mailer + view +
  i18n (en, pt-BR, es)
- Fire-and-forget pattern (no `ShutDownWorker` — pipeline continues)
- **Cleanup as part of this PR:** deleted 6 dead per-failure-type
  reporters (`MissingAccessReport`, `MissingPermissionReport`,
  `UnreachableHostReport`, `DatabaseConnectionReport`,
  `OpenTransactionsReport`, `ApiConnectionReport`) and consolidated
  their concerns into the existing `SourceCheckReport` umbrella

### 6.4 — User::Unknown surfacing (PR #2184 — merged)

Added `User::Unknown` to `Integrator::NORMALIZED_SCHEMA` between
`SalesRepresentative` (position 11) and `ParentUpdate` (position 13)
with negative-filter:

```ruby
condition: "type NOT IN ('Admin', 'President', 'VicePresident', 'Director', 'GeneralManager', " \
           "'Superintendent', 'Manager', 'Coordinator', 'Supervisor', 'SalesRepresentative')"
```

`OR type IS NULL` removed because the schema declares `type varchar(20) NOT NULL`.

Created 5 workers in `app/workers/user/unknown/` mirroring the
`User::SalesRepresentative` pattern. Updated all 5 SalesRepresentative
workers to hand off to `User::Unknown::*` instead of directly to
`ParentUpdate::*`.

**Trade-off accepted:** users now extracted via 11 per-type queries
instead of 1 — the normalized schema is per-role by design (per CLAUDE.md
stream order). Composite index `idx_users_updated_at (updated_at, type)`
verified present in both MSSQL and PG schemas.

### 6.5 — Latent bugs cleanup (PR #2181 — merged)

- Added explicit `DatabaseSource::DATA_SOURCE_TABLES` constant
  (alphabetical, no derive — per "no premature DRY" rule)
- Restored `app/adapters/microsoft_sql_adapter/permissions.rb`,
  `microsoft_sql_adapter/locks.rb`, `postgres_sql_adapter/permissions.rb`
  references to the new constant
- Fixed `app/views/integration_report_mailer/create.html.erb` —
  replaced removed `@job.total_api_requests` with semantically
  equivalent `total_requests_quantity`

### 6.6 — Staging validation: `fetch_since` timezone semantics (PENDING — release gate)

Not a code change — runbook step before the production cut.

Legacy self-service used `job.fetch_since.strftime('%Y-%m-%d %H:%M:%S')`
literal UTC. New flow applies `@source.timezone` via
`Variables#fetch_since` (`app/models/variables.rb:53`). For
`America/Sao_Paulo` that's a 3h shift on the boundary.

- [ ] Deploy current `develop` to staging with a clone of the customer's source DB
- [ ] Run `rake integration:normalized:bootstrap` on staging
- [ ] Run one full incremental cycle and compare `Job#fetch_since`
      boundary against the legacy job's boundary
- [ ] Confirm no records duplicated or skipped at the cutover point
- [ ] Decide between accepting the 3h shift (one-time anomaly) or
      configuring `source.timezone = 'UTC'` in the bootstrap
- [ ] Document the decision in the customer's runbook entry

### Phase 6 PR Map

| # | Scope | PR | Branch | Status |
|---|-------|----|----|---|
| 6.1 | Job::Starter connection error reporting | #2182 | `feature/starter-connection-error-report` | merged |
| 6.2 | DatabaseWarmer give-up + unblock | #2183 | `feature/warmer-unreachable-report` | merged |
| 6.3 | StreamCheckReport + dead reporter cleanup | #2185 | `feature/stream-check-report` | merged |
| 6.4 | User::Unknown surfacing | #2184 | `feature/normalized-user-unknown` | merged |
| 6.5 | Latent bugs cleanup | #2181 | `fix/latent-database-references` | merged |
| 6.6 | Staging validation runbook | n/a | n/a | PENDING |

Execution order followed: 6.5 → 6.1 → 6.2 → 6.4 → 6.3 → (6.6 pending).

### Open regression — RESOLVED (PR #2180)

`lib/tasks/integration_audit.rake` (added by hotfix `8.4.6`,
commit `5a119f10`, 2026-05-08) referenced dead methods after the
hotfix back-merge from `master 8.4.4`. Fixed in PR #2180:

```ruby
source = DatabaseSource.find_by(normalized: true)
if source.nil?
  puts '[integration_audit:normalized:user] SKIPPED: no normalized DatabaseSource configured'
  next
end
connection = source.connect!
```

## Phase 7: Post-Phase-6 Release-Readiness (PRs #2186-#2188 — merged)

A second review after Phase 6 caught items that were exposed by the new
shape. Three PRs to address them.

### PR #2186 — Restored detail + modeling fix + 3 misc

**Bug fix — operator email loses tables for `missing_permissions` and `open_transactions`:**

- Added `affected_resources: Array, default: []` field to `SourceCheck`
- `Authorization::DatabaseConsumer` populates it from
  `connection.permissions.missing` and `job.table_locks.pluck(:table)`
- `SourceCheckReportMailer` view renders affected_resources per failure
  with i18n labels in en/pt-BR/es
  ("Tables without read permission" / "Tables with pending operations")

**Modeling fix — Authorization scope:**

The conditional in `Authorization::DatabaseConsumer` was inverted —
running permission/lock checks on managed-flow sources (which have
arbitrary custom tables, NOT the normalized schema's `DATA_SOURCE_TABLES`)
and skipping the normalized source. Inverted to match the domain rule
"there is at most one normalized source per integrator, and the schema
check belongs to it":

```ruby
if source.normalized?
  # run permission + lock check
else
  source_check.update(authentication: :skipped)
end
```

With at most one normalized source, the lock-attribution diff that an
earlier draft used (snapshotting `external_id` before/after) became
unnecessary — `job.table_locks.pluck(:table)` after the check is
unambiguously this single source's contribution.

`INTEGRATOR_DOMAIN.md` § Authorization updated to anchor the rule.

**Other misc fixes:**

- `AvailabilityCheck::Producer` total==0 guard — when no stream has a
  probe, dispatch `Finalizer` directly so `ThroughputProcessor` still
  fires (pipeline no longer stalls)
- Comment in `database_warmer/consumer.rb` rewritten to accurately
  describe the give-up + downstream re-detection path (was misleading)
- Refreshed `INTEGRATOR_DOMAIN.md` references to deleted reporter
  classes and `UnreachableDatabaseException`

### PR #2187 — Deleted orphan `TableLocksReportWorkBook`

`app/work_books/table_locks_report_work_book.rb` generated the xlsx
attachment for the legacy `OpenTransactionsReport` (deleted in PR #2185).
Zero callers, zero specs, zero brakeman.ignore entries — straight
deletion. Missed by the dead-code sweep at the time because we searched
by reporter class name, not by the workbook the reporters called.

### PR #2188 — Release-readiness cleanup batch

**PostgreSQL lock check defensive fix:**
`postgres_sql_adapter/locks.rb:20` — `CharlockHolmes::EncodingDetector.detect(...)[:encoding]`
returns nil for empty/binary payloads, `nil.downcase` raised
`NoMethodError`. The MSSQL adapter had the `encoding.nil?` guard
already, copied it.

**Unreachable email shows failure + detail:**
`SourceCheckReport` rendered unreachable sources with only the source
name. For sources marked unreachable from `Job::Starter`'s rescue
(which sets `failure: :connection_error, detail: e.message`), operator
saw the source name but not the actual error. Now mirrors the
unauthenticated card layout.

**All four operator-facing mailers migrated to mobile-friendly cards:**

The `<div min-width:500px>` + `<table display:inline-table>` pattern
forced any mobile viewport into horizontal scroll the moment more than
one column needed to fit. Replaced with `<div max-width:500px>`
"cards" — on desktop the card sits at 500px (same look); on mobile it
shrinks to fit the viewport, long error text wraps instead of clipping.

Affected views:
- `source_check_report_mailer/create.html.erb` — both blocks
  (unreachable + unauthenticated) → 1 card per source with name +
  labeled paragraphs for failure/detail/affected_resources
- `stream_check_report_mailer/create.html.erb` → 1 card per stream
  (Source + Stream)
- `high_throughput_report_mailer/create.html.erb` → single card with
  labeled paragraphs per metric (zebra preserved via alternating
  `background-color:#f2f2f2` on `<p>`)
- `integration_report_mailer/create.html.erb` → top metrics card
  (zebra preserved) + 1 card per unsuccessful integration

**Dropped operational dead code:**

- `ApplicationConfiguration.warm_up?` — superseded by
  `DatabaseSource.where(warm_up: true)` query
- Sidekiq queues `api_transformer` and `statistics` from
  `config/sidekiq.yml` — zero workers populated them. **Note:** the
  `default` queue stays — used implicitly by workers without explicit
  `sidekiq_options queue:` (`Job::Starter`, `Job::Finisher`,
  `ShutDownWorker`, `MetricIncrementor`, `DatabaseWarmer` producer/consumer)
- Write-only `external_id` assignments in both lock adapters — the
  field is inherited from `Resource` base class (kept on the model
  itself — out of scope to touch the Resource hierarchy) but nothing
  reads it for `TableLocks` specifically

### Phase 7 PR Map

| # | Scope | PR | Status |
|---|-------|----|----|
| 7.1 | affected_resources + Authorization modeling fix + misc | #2186 | merged |
| 7.2 | Delete orphan TableLocksReportWorkBook | #2187 | merged |
| 7.3 | Release-readiness cleanup (postgres encoding, unreachable email, mobile mailers, dead code) | #2188 | merged |

---

## Historical Reference (Phases as Originally Planned)

The phase descriptions below are kept for historical context. They describe the
intent at planning time; for the actual implementation see the merged PRs above.

### Phase 4 (as planned): Unified Managed Workers

### Goal

Complete the unified managed flow: separate the single mixed-source consumers into dedicated
per-source-type consumers, update producers to dispatch by source type, and delete all legacy
API workers and models. After this phase there are only two integration flows: `self_service`
and `managed`.

Key architectural rule: the producer is the ONLY place that knows about source types. No
source type conditionals inside any consumer.

The 96-file rename (`ManagedDatabase*` → `Managed*`) is already done on the branch.
`Collection` fields, `CollectionUploader`, `ManagedIntegrator`, and deleted legacy API files
are already correct on the branch.

### Architecture

**Single storage per flow — no dual storage:**

- `Collection.raw` (MongoDB Array) — used ONLY by self-service. Nil for managed.
- `Collection.raw_body` (CarrierWave → S3) — used ONLY by managed. Nil for self-service.
- `Collection.raw_headers` (CarrierWave → S3) — HTTP headers for API sources only.

**New fields on `Collection`** (all optional — nil for self-service):

- `connector_id` (BSON::ObjectId) — which connector produced this page
- `stream_id` (BSON::ObjectId) — which stream this page belongs to
- `source_type` (String) — `'database'` or `'api'`
- `page` (Integer) — page number
- `query` (String) — SQL query or HTTP URI
- `status_code` (String) — HTTP status code (nil for database)
- `raw_body` (CarrierWave uploader → S3) — full raw response (managed only)
- `raw_headers` (CarrierWave uploader → S3) — HTTP headers (API managed only)

**Consumer separation — extraction:**

`ManagedDatabaseExtractorConsumer`:
- `perform(job_id, stream_id, connector_id, collection_last_id = nil)`
- Sequel pagination loop, saves `raw_collection.to_json` to `raw_body` (S3)
- No HTTP code, no source type check
- On empty page: `increment_executions`, calls next producer if `done?`
- On disconnect: retries self

`ManagedApiExtractorConsumer`:
- `perform(job_id, stream_id, connector_id)`
- HTTP GET pagination loop, saves `http_response.body` to `raw_body` and headers to `raw_headers`
- Does NOT apply `collection_source_keys` (moves to transformer)
- Does NOT apply `sensitive_keys` (moves to transformer)
- No Sequel code, no source type check

**Extractor Producer — dispatch by source type:**

```ruby
def perform(job_id)
  stream_ids = Stream.where(resource_name: 'Subsidiary').enabled.pluck(:id)

  if stream_ids.any?
    job = Job.find(job_id)

    database_arguments = []
    api_arguments      = []

    stream_ids.each do |stream_id|
      stream = Stream.find(stream_id)
      stream.connectors.order(id: :asc).each do |connector|
        args = [job_id, stream_id.to_s, connector.id.to_s]
        if connector.source.is_a?(DatabaseSource)
          database_arguments << args
        else
          api_arguments << args
        end
      end
    end

    total_connectors = database_arguments.size + api_arguments.size
    job.computation.increment_queue(by: total_connectors)

    Sidekiq::Client.push_bulk('class' => Subsidiary::ManagedDatabaseExtractorConsumer, 'args' => database_arguments) if database_arguments.any?
    Sidekiq::Client.push_bulk('class' => Subsidiary::ManagedApiExtractorConsumer, 'args' => api_arguments) if api_arguments.any?
  else
    Hierarchy::ManagedExtractorProducer.perform_async(job_id)
  end
end
```

**Transformer — source-agnostic:**

`ManagedTransformerConsumer`:
- Downloads `raw_body` from S3, parses JSON
- Applies `collection_source_keys` (if present) — no-op for database connectors
- Applies `sensitive_keys` redaction (if present) — no-op for database connectors
- Applies `attribute_mappings`
- No `collection.source_type` check, no `connector.source.is_a?` check

`ManagedTransformerProducer` dispatches ALL connectors to the single `ManagedTransformerConsumer`.
No source type dispatch needed — transformer is source-agnostic.

**ManagedIntegrator:**
- Checks health for `Source.all` (ApiSource) + `DatabaseSource.all`
- Performs inline authentication for each ApiSource
- Dispatches `Subsidiary::ManagedExtractorProducer`

**Workers to delete:**
- `ApiRequest`, `ApiResponse`, `ApiResponseUploader`
- 24 `{Resource}::ApiExtractor` + 24 `{Resource}::ApiTransformer`
- `ApiIntegrator`

**Worker naming and signatures:**

| File | Class | Signature |
|------|-------|-----------|
| `managed_extractor_producer.rb` | `ManagedExtractorProducer` | `perform(job_id)` |
| `managed_database_extractor_consumer.rb` | `ManagedDatabaseExtractorConsumer` | `perform(job_id, stream_id, connector_id, collection_last_id = nil)` |
| `managed_api_extractor_consumer.rb` | `ManagedApiExtractorConsumer` | `perform(job_id, stream_id, connector_id)` |
| `managed_transformer_producer.rb` | `ManagedTransformerProducer` | `perform(job_id)` |
| `managed_transformer_consumer.rb` | `ManagedTransformerConsumer` | `perform(job_id, stream_id, connector_id)` |

**24-resource fixed execution order:**

```
Subsidiary → Hierarchy → User::Admin → User::President → User::VicePresident →
User::Director → User::GeneralManager → User::Superintendent → User::Manager →
User::Supervisor → User::Coordinator → User::SalesRepresentative → User::Unknown →
Client → Product → Group → Groupification → Deal → DealExtraField → Modifier →
UserField → UserIdentifier → UserActivity → ParentUpdate → Goal
```

---

## Phase 5: Self-Service Absorption (FINAL)

### Goal

Absorb the self-service flow into the managed flow. After this phase, there is only ONE
integration flow. Self-service clients run through the managed pipeline with a DatabaseSource
configured as `normalized: true`. All 44 self-service workers are deleted.

### Step 1: Bootstrap Task (`rake integration:normalized:bootstrap`)

Creates all configuration for a normalized DB client from existing env vars. Idempotent —
uses `find_or_initialize_by` with `||=` for all fields.

**ResourceTypes (14, from `NORMALIZED_REGISTRY` constant):**
- For each entry: `ResourceType.find_or_initialize_by(name: entry[:name])`, set
  `identifier_prefix` from entry (only `User` has `'4sk_'`), save.
- `User` ResourceType carries the prefix used by `Import#user_identifier_prefix` to resolve
  cross-resource user references.

**Source:**
- Creates a `DatabaseSource` with: `adapter` (from `DATABASE_ADAPTER`), `host` (from `CLIENT_HOST`),
  `port` (from `CLIENT_PORT`), `database_name` (from `CLIENT_DATABASE`), `azure` (from `CLIENT_AZURE`),
  `timeout` (from `CLIENT_TIMEOUT`)
- Creates a `DatabaseAuthentication` with: `username` (from `CLIENT_USERNAME`), `password` (from `CLIENT_PASSWORD`)
- Creates a `HealthCheck` (Socket-based, host:port)
- Sets `table_prefix` from `TABLE_PREFIX` env var on the DatabaseSource
- Sets `normalized: true` on the DatabaseSource
- **No `identifier_prefix` on Source** (it lives on ResourceType now)

**Env var → model field mapping:**

| Env Var | Model | Field |
|---------|-------|-------|
| `DATABASE_ADAPTER` | DatabaseSource | `adapter` |
| `CLIENT_HOST` | DatabaseSource | `host` |
| `CLIENT_PORT` | DatabaseSource | `port` |
| `CLIENT_DATABASE` | DatabaseSource | `database_name` |
| `CLIENT_AZURE` | DatabaseSource | `azure` |
| `CLIENT_TIMEOUT` | DatabaseSource | `timeout` |
| `TABLE_PREFIX` | DatabaseSource | `table_prefix` |
| `CLIENT_USERNAME` | DatabaseAuthentication | `username` |
| `CLIENT_PASSWORD` | DatabaseAuthentication | `password` |
| `SQL_PAGE_SIZE` | Connector | `page_size` |

**Streams (14, one per resource, in chain order):**

| # | Resource | Table Name |
|---|----------|------------|
| 1 | Subsidiary | subsidiaries |
| 2 | Hierarchy | hierarchy |
| 3 | User | users |
| 4 | UserIdentifier | user_identifiers |
| 5 | Client | clients |
| 6 | Product | products |
| 7 | Group | groups |
| 8 | Groupification | groupifications |
| 9 | UserField | user_fields |
| 10 | UserActivity | user_activity |
| 11 | Deal | deals |
| 12 | DealExtraField | deal_extra_fields |
| 13 | Modifier | modifiers |
| 14 | Goal | goals |

In normalized mode, User is a single ResourceType — the code guarantees extraction and
transformation order. In managed (query/API), User has separate ResourceTypes per role
(`User::Admin`, `User::Manager`, …) because custom data has no guaranteed order.

**Each stream carries its own extraction config (fields absorbed from Connector):**

- `query_template` (Liquid) — used when `previous_record_id` is nil:
  ```sql
  SELECT * FROM {table_prefix}{table_name}
  WHERE updated_at >= '{{ fetch_since }}'
  ORDER BY id
  LIMIT {{ page_size }}
  ```
- `paginated_query_template` (Liquid) — used when `previous_record_id` is present:
  ```sql
  SELECT * FROM {table_prefix}{table_name}
  WHERE updated_at >= '{{ fetch_since }}' AND id > {{ previous_record_id }}
  ORDER BY id
  LIMIT {{ page_size }}
  ```
  The `{table_prefix}{table_name}` is substituted at bootstrap time (Ruby string interpolation).
  The `{{ }}` Liquid tags are preserved for runtime render by `Stream#render_query`.
- `primary_key`: `'id'`
- `fetch_since_column`: `'updated_at'`
- `page_size`: from `SQL_PAGE_SIZE` env var (falls back to `ApplicationConfiguration.sql_page_size`)

**No AttributeMappings (normalized database):**
- Streams on a `DatabaseSource` with `normalized: true` have NO AttributeMappings
- The transformer detects `stream.source.normalized?` → saves the raw record directly
- For User streams in normalized source, the transformer also performs the parent lookup query
- This avoids maintenance: any new column in the normalized schema is automatically integrated

The task is idempotent — if config already exists, it does not duplicate.

### Step 2: Model Fields + Structural Fix (PARTIAL — must be revised per 2026-04-10 refinement)

**Already merged (PRs #2108, #2109, #2110, #2120)** — but some of this work is superseded by
the 2026-04-10 refinement and must be revised in the Phase 4 PR:

**Model fields (PR #2108):**
- `normalized` field (Boolean, default: false) on `Source` (STI — all subclasses inherit)
- ~~`identifier_prefix` field (String, default: nil) on `Source`~~ **SUPERSEDED 2026-04-10**: move to `ResourceType`
- `table_prefix` field (String, default: 'fsk_') on `DatabaseSource`
- Connector validation: `primary_mapping_presence` skipped when `normalized_source?` — **will move to Stream** when Connector is deleted

**Structural fix (PR #2109):**
- Removed redundant `belongs_to :source` from Connector — navigates via `stream.source`
- Removed `has_many :connectors` from Source
- Added `validates :source_id, presence: true` on Stream
- 72 workers updated (`connector.source` → `stream.source`)

**Identifier prefix (PR #2110) — SUPERSEDED by 2026-04-10 refinement:**
- `Import` had `belongs_to :source, optional: true` → **changed to `belongs_to :stream`**
- `Import#identifier/user_identifier/parent_identifier` used `source.identifier_prefix` →
  **rewritten to resolve via `ResourceType.find_by(name: 'User').identifier_prefix`**
- 24 transformers set `import.source_id = stream.source_id` → **changed to `import.stream_id = stream.id`**
- FactoryBot factory `:source` with sub-factories `:api_source`, `:database_source` — unchanged

**PR #2120 (open)** — first cut of ResourceType, bootstrap task, and Stream position removal.
Needs adjustment: Connector deletion, Import prefix refactor, Stream.for_resource scope removal,
Variables extension, and Liquid unification are NOT in #2120 and must be added before merge.

### Step 2.5: Domain Refinement (NEW — 2026-04-10)

This step captures the refactoring work identified during the late-stage domain review. It must
land in the same PR that absorbs Connector into Stream.

**Connector deletion:**
- Delete `app/models/connector.rb`, `app/controllers/streams/connectors_controller.rb`, views
- Move all Connector fields to Stream: `query_template`, `paginated_query_template`,
  `primary_key`, `fetch_since_column`, `page_size`, `collection_source`, `success_response_status_code`
- Move `embeds_many :attribute_mappings` from Connector to Stream
- Move `embeds_many :sensitive_keys` from Connector to Stream
- Delete `embeds_many :headers` from Connector — dead code (never read; all extractors use
  `source.authenticated_headers`)
- Delete `connectors` MongoDB collection
- `Stream#render_query(variables)` replaces `Connector#query(attributes)` — picks
  `paginated_query_template` when `previous_record_id` is present, otherwise `query_template`

**ResourceType introduction:**
- `app/models/resource_type.rb` with `NORMALIZED_REGISTRY` constant
- `has_many :streams`, `belongs_to :resource_type` on Stream
- Remove `Stream.resource_name` (String field), remove `Stream#user?`
- `Stream#resource` delegates to `resource_type.resource`
- `ResourceType.find_by(name: 'User').identifier_prefix = '4sk_'` in NORMALIZED_REGISTRY

**Source.identifier_prefix removal:**
- Delete `identifier_prefix` field from `Source`
- Delete `normalized` field from `Source` (keep only on `DatabaseSource`)
- Update `spec/models/api_source_spec.rb`, `spec/models/database_source_spec.rb`,
  `spec/models/source_spec.rb` to remove `identifier_prefix` expectations

**Import refactor:**
- `belongs_to :stream, optional: true` (replaces `belongs_to :source`)
- Delete `attr_writer :user_identifier_prefix`
- Rewrite `user_identifier_prefix` method:
  ```ruby
  def user_identifier_prefix
    return '4sk_' if ApplicationConfiguration.self_service_integration?

    user_resource_type = ResourceType.find_by(name: 'User')
    user_resource_type.identifier_prefix if user_resource_type
  end
  ```
- `identifier`, `user_identifier`, `parent_identifier` consume `user_identifier_prefix` directly,
  no memoization/defined? check
- 24 transformers: `import.stream_id = stream.id` (already done in PR #2120 — keep)
- 14 loader_producers: **revert** the `user_identifier_prefix` arg addition from PR #2120
- 14 loader_consumers: **revert** the 3rd arg and attr assignment
- `spec/models/import_spec.rb`: stub `ApplicationConfiguration.self_service_integration?` to
  false in "with user resource type" contexts (otherwise test passes for wrong reason via
  fallback)

**Stream.for_resource scope → Resource.streams:**
- Delete `scope :for_resource` from Stream
- Add class method to `Resource` base class:
  ```ruby
  class Resource
    def self.streams
      resource_type = ResourceType.find_by(name: name)
      return Stream.none unless resource_type

      Stream.where(resource_type: resource_type)
    end
  end
  ```
- Update all 48 producers: `Subsidiary.streams.enabled.pluck(:id)`, `Deal.streams.enabled.pluck(:id)`, etc.

**Liquid render unification in DB extractor:**
- Rework `app/workers/*/managed_database_extractor_consumer.rb` (24 files) to consume
  `Stream#render_query(variables)` output instead of Sequel `.where` chaining
- Before:
  ```ruby
  query = connector.read_attribute(:query)
  dataset = connection.fetch(Sequel.lit(query))
  dataset = dataset.where(Sequel.lit("#{fetch_since_column} >= ?", fetch_since))
  dataset = dataset.where(primary_key > collection_last_id.to_i) if collection_last_id.present?
  dataset = dataset.order(primary_key).limit(connector.page_size || ApplicationConfiguration.sql_page_size)
  ```
- After:
  ```ruby
  variables = Variables.new(
    job,
    stream.source,
    page: nil,
    previous_record_id: collection_last_id,
    page_size: stream.page_size || ApplicationConfiguration.sql_page_size
  ).to_h
  rendered_query = stream.render_query(variables)
  dataset = connection.fetch(Sequel.lit(rendered_query))
  ```
- The API extractor (24 files) also migrates to the unified `Variables` constructor, removing
  the inline `.merge({ 'page' => page, 'previous_record_id' => previous_record_id })`

**Variables extension:**
- `Variables.new(job, source, page: nil, previous_record_id: nil, page_size: nil)`
- Inject three new keys alongside the existing 32. If a template doesn't reference a variable,
  Liquid silently ignores it. Same Variables class used by both DB and API extractors.

**Stream.position + resource_name removal:**
- Delete `position` field and `resource_name` field from Stream
- Delete `Stream#user?` (delegates to ResourceType if needed)
- Delete position-related locales, form fields, views
- Update `spec/models/stream_spec.rb`

**ResourceType#user? removal (dead code from PR #2120):**
- Delete `def user?` from `app/models/resource_type.rb:37-39`
- Delete the two `expect(resource_type.user?).to be(...)` lines from
  `spec/models/resource_type_spec.rb:21,27`
- Verified with grep: no production code calls `resource_type.user?`; the spec tested the
  method for its own sake. Clean deletion, nothing else to update.

**table_prefix default bug (PR #2120 regression):**
- Problem: `app/models/database_source.rb:11` declares
  `field :table_prefix, type: String, default: 'fsk_'`. When
  `DatabaseSource.find_or_initialize_by(normalized: true)` runs in the bootstrap rake, Mongoid
  pre-fills `source.table_prefix = 'fsk_'` via the default. The next line
  (`source.table_prefix ||= table_prefix.present? ? table_prefix : 'fsk_'` at
  `lib/tasks/integration/normalized/bootstrap.rake:28`) is a no-op because `||=` only fires on
  nil/false. Result: the `TABLE_PREFIX` env var is **never read**; all bootstrapped sources end
  up with `'fsk_'` regardless of env, breaking any client whose tables don't use that prefix.
- Correction:
  1. Remove the default from the model: change to `field :table_prefix, type: String` (no
     default, no fallback value — leave undefined for now; adjust during test runs if a default
     becomes necessary)
  2. Simplify the bootstrap line to `source.table_prefix ||= ApplicationConfiguration.table_prefix`
     (same `||=` idiom as the rest of the rake task, no ternary, no hardcoded fallback)
  3. Update `spec/models/database_source_spec.rb:20` — remove the
     `.with_default_value_of('fsk_')` expectation
- Why this works across cases:
  - New record → `table_prefix` is nil → `||=` writes `ApplicationConfiguration.table_prefix`
    (which is `ENV.fetch('TABLE_PREFIX', '')`, so empty string if the env var is unset — valid
    for clients without a prefix)
  - Existing record with value → `||=` no-op, preserves
  - Existing record with `""` → `""` is truthy in Ruby → `||=` no-op, preserves "explicitly
    empty" intent
- Note: the legacy `app/adapters/*.rb` sites (10 total) continue reading
  `ApplicationConfiguration.table_prefix` directly and are unaffected. They are deleted in
  Phase 5 along with the `Database` class.

### Step 3: Transformer Bypass for Normalized (DONE — PR #2111)

- 14 non-user transformers: `stream.source.normalized?` → save raw record directly (no mappings)
- 10 user transformers: normalized bypass with parent lookup via `stream.source.connect!`
- User transformers: `begin/ensure` for `connection.disconnect` (no connection leak)
- Connection opened once before collections loop, closed in ensure
- All 24 transformers: `import.save` without bang (no exception on validation failure)
- Mapping variables outside `collections.each` in else branch

### Step 4: Absorb Pre-flight Checks

- Absorb from DatabaseIntegrator into ManagedIntegrator:
  - Throughput validation (`ThroughputCalculator`) — triggered when DatabaseSource present
  - Permission check (`connection.permissions.missing`) — for DatabaseSource
  - Lock check (`connection.locks.check`) — for DatabaseSource
  - Host reachability (already handled by HealthCheck)
- Absorb `DatabaseWarmer` as optional retry step for DatabaseSource with warm-up
- ManagedIntegrator sets `database_version` and `integration_version` on Job when normalized
  DatabaseSource is present

### Step 5: Update Rake Tasks

- Rake tasks `cron`, `start`, `force_start` in `integration.rake`:
  - Remove branching by integration mode
  - Always call `ManagedIntegrator`
  - `start` and `force_start`: read contagens via `source.connect!` instead of `Database.connect!`

### Step 6: Cleanup

Delete:
- `DatabaseIntegrator` worker
- `DatabaseWarmer` worker
- 14 `{Resource}::DatabaseExtractor` workers
- 14 `{Resource}::DatabaseTransformerProducer` workers
- 14 `{Resource}::DatabaseTransformerConsumer` workers
- `Database` class (singleton Sequel pool wrapper)
- `DatabaseConnectionMiddleware` (Sidekiq middleware)
- All specs for removed workers

Remove from `ApplicationConfiguration`:
- `self_service_integration?`, `managed_integration?`, `api_integration?`, `database_integration?`
- `INTEGRATION_MODE` env var handling

Remove obsolete env vars (migrated to DatabaseSource/DatabaseAuthentication):
- `CLIENT_HOST`, `CLIENT_PORT`, `CLIENT_DATABASE`, `CLIENT_USERNAME`, `CLIENT_PASSWORD`
- `DATABASE_ADAPTER`, `CLIENT_AZURE`, `CLIENT_TIMEOUT`, `TABLE_PREFIX`

**Zero-downtime deployment:**
1. Deploy seed task code (no behavior change)
2. Run `rake integration:seed_normalized` on each self-service client
3. Deploy unified flow code (self-service workers removed)
4. Clients run through managed flow using seeded config

---

## Phase Dependency Graph

```
Phase 1: Domain Model Restructure (PR #2087) ✓
        │
        └──► Phase 2: Adapter + Stream + Managed Extraction (PR #2088) ✓
                │
                └──► Phase 3: Managed Transformation (PR #2090) ✓
                        │
                        └──► Phase 4: Unified Managed Workers ✓
                                │
                                └──► Phase 5: Self-Service Absorption ✓
                                        │
                                        ├──► Steps 1–5 (PRs #2108, #2109, #2110, #2111, #2115, #2116) ✓
                                        ├──► Refinement + Bootstrap (PR #2120) ✓
                                        └──► Source-Driven Config + Cleanup (PR #2174) ✓
```

---

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| MongoDB collection names | `sources`, `streams`, `resource_types` (`connectors` dropped) | No production data exists — no backwards compatibility needed |
| Source STI (ApiSource, DatabaseSource) | Single inheritance on Source | Type-specific fields and behavior co-located |
| **No Connector model** (2026-04-10) | Fields folded into Stream | Industry research (Airbyte, Fivetran, Singer) confirmed no platform uses Connector as an entity between Source and Stream. Removes unnecessary indirection |
| **`ResourceType` as model** (2026-04-10) | Replaces `Stream.resource_name` String | Proper catalog with metadata (identifier_prefix). Enables per-type config without repeating String keys |
| **`identifier_prefix` on ResourceType** (2026-04-10) | Was planned on Source | Prefix is a property of the resource type, not the source. Only User has it (`4sk_`) |
| **Liquid render unified** (2026-04-10) | DB and API both via Stream#render_query | Single code path; single Variables class; simpler extractors |
| **Stream.position removed** (2026-04-10) | Execution order hardcoded in worker chain | Position field was never used; gave false impression of configurability |
| `normalized` flag on DatabaseSource | Boolean field | Explicit control; bypass detection is by flag, not by absence of mappings |
| Bootstrap task for migration | `rake integration:normalized:bootstrap` | Idempotent; generates ResourceTypes, Source, Auth, HealthCheck, and Streams with Liquid templates pre-filled from env vars |
| Zero-downtime deployment | Bootstrap task before code deploy | Clients never have a gap in config |
| Extractor consumer separation | Separate classes per source type | No mixed flows in extraction — each consumer does one thing |
| Transformer source-agnostic | Single consumer for all types | Both extractors save to `raw_body` (S3); absent config is a no-op |
| **Import prefix via ResourceType lookup** (2026-04-10) | Was via `source.identifier_prefix` | `Import.belongs_to :stream` but prefix always comes from User ResourceType (because non-User resources reference User IDs) |
| **No attr_writer on Import** (2026-04-10) | Was passed via Sidekiq args in loader consumers | Eliminates silent fallback bug and Sidekiq payload growth |
| **Resource.streams class method** (2026-04-10) | Was `Stream.for_resource` scope | Scope returned nil silently on missing ResourceType — `Stream.none` is safer. Resource-owned lookup is clearer |
| Self-service workers deleted | Not preserved for fallback | Clean break; bootstrap task ensures equivalent config exists |
| `Collection.raw` frozen | Self-service only, never touched by managed | Prevents self-service aggregations from being triggered by managed data |
| `sensitive_keys` in transformer | Removed from extractor | Extractor only fetches + saves; transformer interprets + redacts + maps |
| `ApiRequest`/`ApiResponse` deleted | Not used in production | Bugs in original design; `Collection.raw_body` replaces both |
| **Connector.headers deleted, not migrated** (2026-04-10) | Dead code | Verified in `managed_api_extractor_consumer.rb:19` — all API extractors use `source.authenticated_headers` |

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Self-service clients break during migration | High | Seed task generates exact equivalent config; run in staging first |
| `"4sk_"` prefix change breaks existing resources | High | `identifier_prefix` preserves existing behavior for seeded sources |
| Normalized DB special cases (User parent lookup) | Medium | Preserved as transformer behavior for `source.normalized?` |
| Performance regression (extra DB lookups for config) | Medium | Stream/Connector reads cached in memory during job |
| Mongoid STI `_type` absent on existing documents | Medium | Verified in PR #2087; default resolution works |
| Seed task not run before deploy | High | Documented deployment procedure; task is idempotent and can run multiple times |

## Internal References

- Entry points: `app/workers/database_integrator.rb`, `app/workers/managed_integrator.rb`
- Mode config: `lib/application_configuration.rb`
- Rake tasks: `lib/tasks/integration.rake`, `lib/tasks/integration/normalized/bootstrap.rake`
- Source models: `app/models/source.rb`, `app/models/api_source.rb`, `app/models/database_source.rb`
- Stream: `app/models/stream.rb` (absorbs Connector fields in 2026-04-10 refinement)
- ResourceType: `app/models/resource_type.rb` (new in 2026-04-10 refinement)
- Connector (to be deleted): `app/models/connector.rb`, `app/controllers/streams/connectors_controller.rb`
- Import: `app/models/import.rb` (rewrite `user_identifier_prefix` via ResourceType lookup)
- Variables: `app/models/variables.rb` (extended with page/previous_record_id/page_size)
- DB extractor (rework for Liquid render): `app/workers/*/managed_database_extractor_consumer.rb` (24 files)
- API extractor (migrate to unified Variables): `app/workers/*/managed_api_extractor_consumer.rb` (24 files)
- Loader producers (revert PR #2120 arg threading): `app/workers/*/loader_producer.rb` (14 files)
- Loader consumers (revert PR #2120 3rd arg): `app/workers/*/loader_consumer.rb` (14 files)
- Resource base class: `app/models/resource.rb` (add `self.streams` class method)
- DB connection: `app/models/database.rb`
- Table list: `Database::DATA_SOURCE_TABLES` in `app/models/database.rb:9`
- User parent lookup: `app/workers/user/database_transformer_consumer.rb:12-15`
- Env vars: `lib/application_configuration.rb` (CLIENT_HOST, CLIENT_PORT, CLIENT_DATABASE, etc.)
- SPIKE: `SPIKE.md` in this directory
