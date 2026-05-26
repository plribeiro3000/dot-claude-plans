# PLAN - Adapter Layer Evolution

> Single-project feature: `integrator`
> Supersedes: `~/.claude/plans/completed/integrator/sequel-to-activerecord/PLAN.md` (cancelled)

## Objective

Evolve the integrator's adapter layer in three sequential steps: eliminate SQL injection
vulnerabilities by migrating to Sequel DSL, generalize extractors to support client-provided open
queries, and lay the groundwork for CDC-based incremental sync on SQL Server.

The adapter public interface (`fetch`, `page`, `count`, `insert`, `delete`, `select_ids`,
`sample`, `first`, `maximum_identifier_for`, `execute_procedure`) must remain unchanged throughout.
Workers are not touched unless the contract they depend on needs to change for open queries.

## Scope

### In Scope

- Replace string-interpolated SQL with Sequel DSL and parameterized literals in both adapters and
  all four submodules (`locks.rb`, `permissions.rb` for each engine)
- Fix the pre-existing `save_changes` bug in `postgres_sql_adapter/locks.rb`
- Add a `QueryRunner` component that executes arbitrary client-provided SQL and pages through
  results with a configurable cursor strategy
- Add `open_query` configuration to `ApplicationConfiguration` (one or more named queries with
  their collection binding and cursor field)
- Add an `OpenQuery::DatabaseExtractor` worker that uses `QueryRunner` instead of the hardcoded
  `connection.page` pattern
- Add CDC extraction support for SQL Server: initial load + incremental mode via
  `cdc.fn_cdc_get_net_changes_*`, LSN position tracking per table per client

### Out of Scope

- Changing the public interface of any existing adapter method
- Modifying any existing `DatabaseExtractor` worker (they continue using `connection.page` as today)
- The Integration Validation Portal (separate project — query onboarding and validation happen there;
  this plan is about the integrator *executing* those queries)
- PostgreSQL CDC (no `pg_logical` or `wal2json` support planned; CDC is SQL Server only)
- Schema introspection or automatic column mapping
- Multi-tenant connection pooling changes (pool already correct for the use case)

## Current State Analysis

### SQL injection surface

Every string-building method in both adapters uses Ruby string interpolation directly into SQL:

- `fetch`, `select_ids`, `page`, `count`, `delete`, `sample`, `first` — `conditions` parameter
  is appended as a raw string with no escaping
- `page` — `collection_last_id` is interpolated into a numeric comparison (`id > #{collection_last_id}`)
- `maximum_identifier_for` — table name is interpolated into `ident_current('#{collection}')` and
  `currval('#{collection}_id_seq')`
- `execute_procedure` — `params` is interpolated directly into the stored procedure call
- `MicrosoftSqlAdapter::Permissions#access_allowed_for` — table name interpolated into
  `HAS_PERMS_BY_NAME`
- `MicrosoftSqlAdapter::Locks#locks_for` — `collection` interpolated into `object_id('#{collection}')`
- `PostgresSqlAdapter::Locks#database_locks` — `ApplicationConfiguration.database` and `.username`
  interpolated directly
- `PostgresSqlAdapter::Permissions#access_allowed_for` — table name interpolated into a COUNT query

The `conditions` parameter in `page` is an entire SQL fragment (e.g.
`"where fsk_users.updated_at >= '2025-01-01'"`) — this is the highest-risk injection surface because
it is constructed by callers (the extractor workers) from job-derived values.

### Hardcoded extraction model

`Database::DATA_SOURCE_TABLES` lists 15 fixed `fsk_*` tables. Every `DatabaseExtractor` constructs
the same timestamp-based `WHERE updated_at >= '#{fetch_since}'` condition as a raw string. The chain
of extractors is hardcoded in the worker classes themselves (each extractor chains to the next via
`perform_async`). There is no runtime-configurable query mapping.

### Change detection

All extractors use `job.fetch_since` (a timestamp from the previous successful job) as the lower
bound for `updated_at`. This works for normalized `fsk_*` schemas where all tables have
`updated_at`. For open queries against arbitrary client schemas, neither the column name nor
the change detection strategy can be assumed.

## Execution Phases

### Phase 1: Sequel DSL migration (SQL injection fix)

**Objective**: Replace all string-interpolated SQL in both adapters and their submodules with Sequel
DSL, parameterized literals (`Sequel.lit`), or identifier quoting (`Sequel.identifier`). The public
interface of every method remains unchanged. No behavior changes — this is a safety refactor.

**Components**:

- `MicrosoftSqlAdapter` — query methods:
  - `fetch(collection, conditions)`: migrate to `connection[Sequel.identifier(collection)]` DSL with
    a parameterized WHERE clause. The `conditions` parameter is a raw fragment today; it must become
    a hash of column-to-value pairs or a `Sequel::SQL::BooleanExpression` so callers can be updated
    in Phase 2. For now, accept both forms: if `conditions` is a String, wrap it with `Sequel.lit`
    (still unsafe but contained); if it is a Hash or expression, use DSL. Mark the string form as
    deprecated.
  - `select_ids`, `count`, `delete`, `sample`, `first`: same approach as `fetch`.
  - `page`: use `Sequel.identifier(collection)` for table reference; use parameterized `WHERE` for
    timestamp; use `Sequel.lit('? > ?', Sequel.identifier("#{collection}.id"), collection_last_id)`
    for the id cursor — eliminates numeric injection.
  - `maximum_identifier_for`: use `Sequel.lit` with a bound parameter for the table name string
    passed to `ident_current`.
  - `execute_procedure`: this method passes raw stored procedure calls — keep as-is but add a
    comment documenting the risk. Callers must ensure params are safe. No clean parameterization
    exists for EXEC statements in Sequel.
  - `insert`: already uses Sequel dataset `insert(keys, values)` — no change needed.

- `PostgresSqlAdapter` — same changes as above. `page` uses `LIMIT` instead of `TOP`.
  `maximum_identifier_for` uses `currval` with a bound string parameter.

- `MicrosoftSqlAdapter::Permissions#access_allowed_for`: replace raw string interpolation with
  `Sequel.lit("HAS_PERMS_BY_NAME(?, 'OBJECT', 'SELECT')", table)`. Fix anonymous column access:
  add `AS has_permission` alias and access result as `result.first[:has_permission]`.

- `MicrosoftSqlAdapter::Locks#locks_for`: replace `object_id('#{collection}')` with
  `Sequel.lit('object_id(?)', collection)`.

- `PostgresSqlAdapter::Permissions#access_allowed_for`: replace COUNT query interpolation with
  `Sequel.lit('select count(*) as count from ?', Sequel.identifier(table))`.

- `PostgresSqlAdapter::Locks#database_locks`: replace `ApplicationConfiguration.database` and
  `.username` interpolation with bound parameters via `Sequel.lit`.

- `postgres_sql_adapter/locks.rb`: fix pre-existing `save_changes` bug → `save`.

**Dependencies**: None — this is the first phase and touches only adapter internals.

**Success Criteria**:
- [ ] No string interpolation (`#{}`) inside any SQL string in both adapters and all four submodules
- [ ] `execute_procedure` is the only method with a documented residual risk; comment present
- [ ] `page` method: `collection_last_id` is passed as a bound parameter, not interpolated
- [ ] `maximum_identifier_for` uses bound parameters for table name strings
- [ ] `MicrosoftSqlAdapter::Permissions#access_allowed_for` returns correct result with `AS has_permission` alias
- [ ] `postgres_sql_adapter/locks.rb` uses `save` instead of `save_changes`
- [ ] Linter passes with no new violations
- [ ] All existing tests pass; no behavioral change

---

### Phase 2: Open query support

**Objective**: The integrator can execute client-provided arbitrary SQL queries (configured at
deploy time via environment variables or a config file) instead of — or in addition to — the fixed
`fsk_*` table queries. The result of each open query is stored as a raw collection and fed into the
existing transformer pipeline.

**Components**:

- `ApplicationConfiguration.open_queries`: returns a parsed array of query definitions from the
  environment. Each definition has: `name` (string identifier), `sql` (the query text), `resource`
  (which API resource the result maps to, e.g. `"users"`), `cursor_field` (optional column name for
  incremental filtering, e.g. `"updated_at"`), `cursor_type` (`:timestamp` or `:id`, defaults to
  `:timestamp`). Format to be defined (JSON string in an env var is sufficient for MVP).

- `QueryRunner`: a new class (not an adapter method) that accepts a Sequel connection and a query
  definition. Responsibilities:
  - Execute the SQL as written (no DSL transformation — these are client-provided strings)
  - Apply cursor-based pagination: if `cursor_field` is present and a `cursor_value` is provided,
    append `WHERE {cursor_field} >= {cursor_value}` using `Sequel.lit` with bound parameters
  - Apply page size limit consistent with `ApplicationConfiguration.sql_page_size`
  - Return an array of hashes (same shape as existing `connection.page` results)
  - SQL Server and PostgreSQL use different pagination syntax (`TOP N` vs `LIMIT N`) — `QueryRunner`
    delegates pagination wrapping to a strategy object keyed on `ApplicationConfiguration.database_adapter`

- `OpenQuery::DatabaseExtractor`: a new Sidekiq worker (`queue: :database_extractor`) that iterates
  over `ApplicationConfiguration.open_queries` and, for each query definition, paginates through
  results using `QueryRunner`. Stores each page as a raw collection on the Job using the `resource`
  field to determine which collection to populate. When all pages for all queries are exhausted,
  chains to the first `DatabaseTransformerProducer` in the standard pipeline.

- No changes to existing `DatabaseExtractor` workers — they continue extracting `fsk_*` tables as
  before. `OpenQuery::DatabaseExtractor` is an independent extraction path, triggered when
  `ApplicationConfiguration.open_queries` is present and non-empty.

- `DatabaseIntegrator` worker: after the existing extraction chain completes, check whether open
  queries are configured. If yes, enqueue `OpenQuery::DatabaseExtractor`. If no, proceed as today.
  The condition is `ApplicationConfiguration.open_queries.any?`.

**Dependencies**: Phase 1 complete (adapters are safe before we add new query execution paths).

**Success Criteria**:
- [ ] `ApplicationConfiguration.open_queries` parses query definitions from environment
- [ ] `QueryRunner` executes a provided SQL string and returns paginated results as an array of hashes
- [ ] `QueryRunner` applies cursor-based filtering via bound parameters (no string interpolation)
- [ ] `QueryRunner` handles SQL Server (`TOP N`) and PostgreSQL (`LIMIT N`) pagination differences
- [ ] `OpenQuery::DatabaseExtractor` iterates all configured queries and stores raw collections
- [ ] `OpenQuery::DatabaseExtractor` chains to the transformer pipeline on completion
- [ ] When no open queries are configured, the integrator behaves exactly as before
- [ ] When open queries are configured, the `fsk_*` extraction also still runs (both paths active)
- [ ] Linter passes with no new violations
- [ ] Unit tests for `QueryRunner` covering: basic execution, cursor filtering, pagination, both DB engines

---

### Phase 3: CDC support for SQL Server (future)

**Objective**: Add SQL Server CDC as an alternative extraction mode. Instead of
`WHERE updated_at >= last_run`, the extractor reads from `cdc.fn_cdc_get_net_changes_*` change
tables using LSN positions. An initial full-load pass precedes incremental CDC reads.

**Components**:

- `ApplicationConfiguration.cdc_enabled?`: returns `true` when `CDC_ENABLED=true` env var is set.
  CDC mode is opt-in per deployment.

- `CdcPosition` (MongoDB model via Mongoid): stores the last processed LSN per table per job. Fields:
  `table_name`, `last_lsn` (binary or hex string), `updated_at`. One record per table, upserted
  after each successful extraction cycle.

- `MicrosoftSqlAdapter#cdc_changes(table_name, from_lsn, to_lsn)`: executes
  `SELECT * FROM cdc.fn_cdc_get_net_changes_{capture_instance}(@from_lsn, @to_lsn, 'all')`
  using `Sequel.lit` with bound parameters. Returns array of hashes with CDC metadata columns
  (`__$operation`, `__$start_lsn`, etc.) alongside data columns.

- `MicrosoftSqlAdapter#current_lsn`: executes `SELECT sys.fn_cdc_get_max_lsn()` to retrieve the
  current maximum LSN. Used as the upper bound for each extraction cycle.

- `MicrosoftSqlAdapter#min_valid_lsn(table_name)`: executes
  `SELECT sys.fn_cdc_get_min_lsn(capture_instance)` to determine whether stored LSN is still
  within the CDC retention window. If stored LSN is below min valid LSN, fall back to full reload.

- `Cdc::DatabaseExtractor`: a new Sidekiq worker that, per table in `DATA_SOURCE_TABLES`:
  1. Loads `CdcPosition` for the table
  2. If no position exists (first run), performs a full SELECT of the table and stores results as
     a raw collection (same as current extractors)
  3. If position exists, calls `adapter.cdc_changes(table, from_lsn, to_lsn)` and stores the
     delta collection
  4. Upserts `CdcPosition` with the new LSN after successful extraction
  Falls back to timestamp-based extraction if `from_lsn` is below `min_valid_lsn`.

- `DatabaseIntegrator` worker: when `ApplicationConfiguration.cdc_enabled?` is true, enqueue
  `Cdc::DatabaseExtractor` instead of `Subsidiary::DatabaseExtractor` as the extraction entry point.
  The timestamp-based chain remains untouched and is used when CDC is not enabled.

- CDC is SQL Server only. If `cdc_enabled?` is true but the adapter is `postgres_sql_server`, raise
  a configuration error at startup.

**Dependencies**: Phase 2 complete. SQL Server CDC must be enabled on the source database
(this is a DBA responsibility, not managed by the integrator). The capture instance name convention
must be established (`dbo_{table_name}` is the default SQL Server convention).

**Success Criteria**:
- [ ] `cdc_enabled?` defaults to `false`; no behavior change when disabled
- [ ] `CdcPosition` model persists and retrieves LSN per table
- [ ] `MicrosoftSqlAdapter#cdc_changes` returns change rows with CDC metadata columns
- [ ] `MicrosoftSqlAdapter#current_lsn` and `#min_valid_lsn` return correct values
- [ ] `Cdc::DatabaseExtractor` performs full load on first run (no stored LSN)
- [ ] `Cdc::DatabaseExtractor` performs incremental load on subsequent runs using stored LSN
- [ ] `Cdc::DatabaseExtractor` falls back to full load when stored LSN is below `min_valid_lsn`
- [ ] LSN position is updated only after successful extraction (no partial advances)
- [ ] Configuration error raised at startup when CDC is enabled on a PostgreSQL deployment
- [ ] Linter passes with no new violations
- [ ] Unit tests for LSN boundary conditions: first run, incremental, retention window expiry

---

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Sequel remains as DB client | Keep Sequel | Confirmed in cancelled AR migration plan: 7.5x faster, 2.8x less memory, simpler multi-DB model |
| `conditions` migration strategy | Accept String (deprecated) + Hash/expression | Breaking all callers in Phase 1 is too large a blast radius; deprecate String form, migrate callers in Phase 2 |
| `execute_procedure` SQL risk | Document, do not fix | No clean Sequel parameterization for EXEC statements; callers must own safety |
| Open query config format | JSON env var | Minimal new infrastructure; one env var covers multiple queries; consistent with how existing config works |
| `QueryRunner` as a standalone class | Yes, not an adapter method | Open queries are a different execution model (raw SQL + cursor strategy) — they do not belong on the adapter's DSL surface |
| CDC position storage | Mongoid (`CdcPosition`) | MongoDB is already the integrator's own data store; no new infrastructure; LSN is binary data that fits BSON well |
| CDC fallback strategy | Full reload when LSN invalid | Conservative: better to re-extract all rows than to silently miss changes |
| CDC scope | SQL Server only | PostgreSQL CDC requires `pg_logical` or `wal2json` which are not in scope for this phase |
| Phase 3 priority | Low / future | CDC is the most complex piece with external dependencies (DBA, CDC enabled on source); Phases 1 and 2 deliver value independently |

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Sequel DSL behavior differences from raw string SQL | Medium | Each refactored method must produce identical SQL output — verify with Sequel's `sql` debugging method before shipping |
| `conditions` callers still pass raw strings after Phase 1 | High | The deprecated String path still works via `Sequel.lit`; fix callers incrementally in Phase 2 when adding open query support |
| Open query SQL is client-controlled | High | `QueryRunner` executes SQL as-is — the Integration Validation Portal is the validation gate; the integrator trusts pre-approved queries only |
| CDC retention window too short | Medium | `min_valid_lsn` check triggers full reload; default SQL Server retention is 3 days — ensure deployments run at least daily |
| CDC capture instance naming convention mismatch | Medium | Default is `dbo_{table_name}`; if client DBA used a different name, CDC calls will fail; add a configurable `CDC_CAPTURE_INSTANCE_PREFIX` env var |
| Phase 3 PostgreSQL deployment misconfiguration | Low | Startup guard raises error immediately; no silent failure |

## Assumptions

- Sequel is and remains the database client (confirmed by the cancelled AR migration decision record)
- `ApplicationConfiguration.open_queries` will be populated by the Integration Validation Portal
  deployment process (the portal validates queries; the integrator receives them as configuration)
- CDC is optional and opt-in; no existing client deployments are affected by Phase 3
- SQL Server CDC is enabled on source databases by the client's DBA before the integrator is
  configured with `CDC_ENABLED=true`
- The existing transformer and loader pipeline can consume open query raw collections without
  changes, as long as the `resource` field maps to an existing transformer
- Each integrator instance serves a single client database (no multi-tenant connection changes needed)

---

**Status:** READY FOR TASK CREATION
