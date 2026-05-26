# TASKS - Adapter Layer Evolution

> Single-project feature: `integrator`
> Based on: PLAN.md
> Status: Ready for execution

## Overview

Task breakdown for three-phase adapter layer evolution:
- **Phase 1**: Sequel DSL migration (SQL injection fix) — 7 tasks
- **Phase 2**: Open query support — 5 tasks
- **Phase 3**: CDC support for SQL Server — 6 tasks

All tasks follow strict success criteria defined in PLAN.md. Phases must be executed sequentially; no task in Phase 2 begins until Phase 1 is complete.

---

## Phase 1: Sequel DSL Migration

### Task 1.1: Migrate MicrosoftSqlAdapter query methods to Sequel DSL

**Description**

Refactor `MicrosoftSqlAdapter` query methods (`fetch`, `select_ids`, `count`, `delete`, `sample`, `first`) to use Sequel DSL instead of string interpolation.

**Acceptance Criteria**

- `fetch(collection, conditions)` uses `connection[Sequel.identifier(collection)]` DSL
- `conditions` parameter accepts both String (deprecated, via `Sequel.lit`) and Hash/`Sequel::SQL::BooleanExpression` (preferred)
- String form is marked with deprecation warning in code
- `select_ids`, `count`, `delete`, `sample`, `first` follow the same pattern as `fetch`
- All methods produce identical SQL to their original versions (verify via Sequel's `.sql` method in tests)
- No string interpolation (`#{}`) remains in any of these methods
- All existing tests pass; behavior is unchanged
- Linter passes with no new violations

**Dependencies**

- None (first task in Phase 1)

**Blocks**

- Task 1.2
- Task 1.3
- Task 1.4

---

### Task 1.2: Migrate MicrosoftSqlAdapter `page` method to Sequel DSL

**Description**

Refactor the `page` method in `MicrosoftSqlAdapter` to use Sequel DSL for table reference, WHERE clause, and cursor-based pagination.

**Acceptance Criteria**

- Table reference uses `Sequel.identifier(collection)`
- Timestamp WHERE clause is parameterized (no string interpolation)
- Cursor comparison (`id > collection_last_id`) uses `Sequel.lit('? > ?', ...)` with bound parameter for `collection_last_id` (eliminates numeric injection)
- Uses `TOP N` for result limiting
- `collection_last_id` is never interpolated into SQL
- All existing tests pass; pagination behavior is unchanged
- Linter passes with no new violations

**Dependencies**

- Task 1.1 (need `Sequel.identifier` pattern established)

**Blocks**

- Task 1.5
- Task 2.3 (Phase 2 needs safe pagination)

---

### Task 1.3: Migrate MicrosoftSqlAdapter `maximum_identifier_for` to Sequel DSL

**Description**

Refactor `maximum_identifier_for` to use `Sequel.lit` with bound parameters for table name and identifier functions.

**Acceptance Criteria**

- Table name string passed to `ident_current` is bound via `Sequel.lit`, not interpolated
- Identical results as original method (same identity value returned)
- All existing tests pass
- Linter passes with no new violations

**Dependencies**

- Task 1.1

**Blocks**

- None (independent for Phase 1 completion)

---

### Task 1.4: Migrate MicrosoftSqlAdapter submodules (Permissions and Locks)

**Description**

Refactor `MicrosoftSqlAdapter::Permissions#access_allowed_for` and `MicrosoftSqlAdapter::Locks#locks_for` to use Sequel DSL.

**Acceptance Criteria**

- `Permissions#access_allowed_for`: replaces raw string interpolation with `Sequel.lit("HAS_PERMS_BY_NAME(?, 'OBJECT', 'SELECT')", table)`
- `Permissions#access_allowed_for`: adds `AS has_permission` alias to result column
- `Permissions#access_allowed_for`: accesses result as `result.first[:has_permission]` (not anonymous column)
- `Locks#locks_for`: replaces `object_id('#{collection}')` with `Sequel.lit('object_id(?)', collection)`
- Both methods produce identical SQL to original versions
- All existing tests pass
- Linter passes with no new violations

**Dependencies**

- Task 1.1

**Blocks**

- None (independent for Phase 1 completion)

---

### Task 1.5: Migrate PostgresSqlAdapter to Sequel DSL

**Description**

Refactor PostgreSQL adapter with same Sequel DSL changes as Microsoft SQL adapter. Identical strategy with PostgreSQL-specific syntax (`LIMIT` instead of `TOP`, `currval` instead of `ident_current`).

**Acceptance Criteria**

- All methods (`fetch`, `select_ids`, `count`, `delete`, `sample`, `first`, `page`, `maximum_identifier_for`) use Sequel DSL
- `page` method uses `LIMIT` for result limiting (not `TOP`)
- `maximum_identifier_for` uses `currval` with bound parameters
- Cursor pagination (`WHERE {collection}.id > ?`) identical to Microsoft SQL adapter pattern
- No string interpolation (`#{}`) in any method
- All existing tests pass; behavior is unchanged
- Linter passes with no new violations

**Dependencies**

- Task 1.2 (must see Microsoft SQL `page` pattern first)

**Blocks**

- Task 1.6
- Task 1.7

---

### Task 1.6: Migrate PostgresSqlAdapter submodules (Permissions and Locks)

**Description**

Refactor `PostgresSqlAdapter::Permissions#access_allowed_for` and `PostgresSqlAdapter::Locks#database_locks` to use Sequel DSL and fix the `save_changes` bug.

**Acceptance Criteria**

- `Permissions#access_allowed_for`: replaces COUNT query interpolation with `Sequel.lit('select count(*) as count from ?', Sequel.identifier(table))`
- `Locks#database_locks`: replaces `ApplicationConfiguration.database` and `.username` interpolation with bound parameters via `Sequel.lit`
- `Locks#database_locks`: fixes pre-existing `save_changes` bug by changing to `save`
- Both methods produce identical results as original versions
- All existing tests pass
- Linter passes with no new violations

**Dependencies**

- Task 1.5 (follow same pattern as PostgreSQL main adapter)

**Blocks**

- None (final Phase 1 task)

---

### Task 1.7: Handle `execute_procedure` and document residual risk

**Description**

Review and document the `execute_procedure` method in both adapters. No parameterization exists for EXEC statements in Sequel, so this method remains at-risk. Document the risk clearly and ensure callers are aware.

**Acceptance Criteria**

- `execute_procedure` in both `MicrosoftSqlAdapter` and `PostgresSqlAdapter` has a clear code comment documenting the SQL injection risk
- Comment explains that callers must ensure `params` are safe (no Sequel parameterization available for EXEC statements)
- Comment points callers to the public interface documentation or a relevant rubocop rule if one exists
- No code changes to the method itself
- Linter passes with no new violations
- Success criteria met: "execute_procedure is the only method with a documented residual risk; comment present"

**Dependencies**

- Task 1.1 (Phase 1 context)

**Blocks**

- Phase 1 completion gate (needed for Phase 2)

---

## Phase 2: Open Query Support

### Task 2.1: Add `ApplicationConfiguration.open_queries` parser

**Description**

Extend `ApplicationConfiguration` to parse and return query definitions from environment variables. Each definition includes name, SQL, resource, cursor_field, and cursor_type.

**Acceptance Criteria**

- `ApplicationConfiguration.open_queries` returns an array of parsed query definition hashes
- Each definition has keys: `name` (string), `sql` (string), `resource` (string), `cursor_field` (optional, string), `cursor_type` (optional, `:timestamp` or `:id`, defaults to `:timestamp`)
- Parser reads from a JSON string env var (exact env var name to be decided; suggest `DATABASE_OPEN_QUERIES`)
- Returns empty array if env var is not set or empty
- Returns empty array if env var is valid JSON but contains no queries
- Raises a clear error if env var is set but not valid JSON
- All configuration tests pass
- Linter passes with no new violations

**Dependencies**

- Phase 1 complete (adapters are safe)

**Blocks**

- Task 2.2
- Task 2.4

---

### Task 2.2: Implement `QueryRunner` class with pagination strategy

**Description**

Create a new `QueryRunner` class that executes client-provided SQL with cursor-based pagination. Pagination strategy is delegated to a strategy object keyed on the database adapter type.

**Acceptance Criteria**

- `QueryRunner` accepts a Sequel connection and a query definition hash
- Executes the SQL as-is (no DSL transformation)
- If `cursor_field` is present and `cursor_value` is provided, appends `WHERE {cursor_field} >= {cursor_value}` using `Sequel.lit` with bound parameters
- Applies page size limit from `ApplicationConfiguration.sql_page_size`
- Returns an array of hashes (same shape as `connection.page` results)
- Pagination strategy is abstracted: `QueryRunner::PaginationStrategy::MicrosoftSql` (uses `TOP N`) and `QueryRunner::PaginationStrategy::PostgreSql` (uses `LIMIT N`)
- `QueryRunner` instantiates the correct strategy based on `ApplicationConfiguration.database_adapter`
- No string interpolation for cursor filtering or pagination — all bound via `Sequel.lit`
- All `QueryRunner` tests pass covering: basic execution, cursor filtering, pagination, both database engines
- Linter passes with no new violations

**Dependencies**

- Task 2.1 (`open_queries` config exists)

**Blocks**

- Task 2.3
- Task 2.4

---

### Task 2.3: Implement `OpenQuery::DatabaseExtractor` worker

**Description**

Create a new Sidekiq worker that iterates over configured open queries and extracts results using `QueryRunner`, storing each page as a raw collection. On completion, chains to the first `DatabaseTransformerProducer` in the standard pipeline.

**Acceptance Criteria**

- New Sidekiq worker class `OpenQuery::DatabaseExtractor` with `queue: :database_extractor`
- Accepts a Job object as parameter
- Iterates over all `ApplicationConfiguration.open_queries`
- For each query: instantiates `QueryRunner`, paginates through all results, stores each page as a raw collection on the Job
- Uses the `resource` field from the query definition to determine which collection to populate
- After all queries and all pages are exhausted, calls `perform_async` on the first `DatabaseTransformerProducer` in the standard transformer pipeline
- Chains correctly to existing transformer pipeline (same entry point as current `Subsidiary::DatabaseExtractor` or similar)
- All tests pass
- Linter passes with no new violations

**Dependencies**

- Task 2.2 (`QueryRunner` exists)
- Task 2.1 (configuration exists)

**Blocks**

- Task 2.5

---

### Task 2.4: Integrate `OpenQuery::DatabaseExtractor` into `DatabaseIntegrator` worker

**Description**

Update the `DatabaseIntegrator` worker to enqueue `OpenQuery::DatabaseExtractor` when open queries are configured.

**Acceptance Criteria**

- After the existing extraction chain completes, `DatabaseIntegrator` checks `ApplicationConfiguration.open_queries.any?`
- If true: enqueues `OpenQuery::DatabaseExtractor` with the same Job object
- If false: proceeds as today (no behavior change)
- Both extraction paths coexist: fsk_* tables continue to be extracted AND open queries are extracted (when configured)
- When no open queries are configured, integrator behaves exactly as before
- All tests pass
- Linter passes with no new violations

**Dependencies**

- Task 2.3 (`OpenQuery::DatabaseExtractor` exists)
- Task 2.1 (configuration check works)

**Blocks**

- None (Phase 2 completion gate)

---

### Task 2.5: Acceptance testing and documentation for Phase 2

**Description**

Verify end-to-end Phase 2 functionality and document the open query configuration format for operators.

**Acceptance Criteria**

- Integration test: when `open_queries` is configured, both fsk_* tables and open queries are extracted
- Integration test: when `open_queries` is empty, only fsk_* tables are extracted (behavior unchanged)
- Integration test: `QueryRunner` correctly paginates and filters by cursor across both database types
- Configuration documentation: example JSON for `DATABASE_OPEN_QUERIES` env var
- Configuration documentation: example of `cursor_field` and `cursor_type` values
- All tests pass
- Linter passes with no new violations

**Dependencies**

- Task 2.4 (integration complete)

**Blocks**

- None (Phase 2 complete)

---

## Phase 3: CDC Support for SQL Server

### Task 3.1: Create `CdcPosition` Mongoid model

**Description**

Add a MongoDB model to persist the last processed LSN (Log Sequence Number) per table per job.

**Acceptance Criteria**

- New Mongoid model `CdcPosition` with fields: `table_name` (string), `last_lsn` (string or binary), `updated_at` (timestamp)
- Unique index on `table_name` (one LSN per table across all jobs)
- Can be upserted: `CdcPosition.where(table_name: 'foo').find_or_create_by(table_name: 'foo').update(last_lsn: new_lsn)`
- All model tests pass
- Linter passes with no new violations

**Dependencies**

- Phase 2 complete (Phase 3 is future/optional)

**Blocks**

- Task 3.2
- Task 3.3

---

### Task 3.2: Add CDC methods to `MicrosoftSqlAdapter`

**Description**

Add three new methods to `MicrosoftSqlAdapter` for CDC operations: `cdc_changes`, `current_lsn`, and `min_valid_lsn`.

**Acceptance Criteria**

- `cdc_changes(table_name, from_lsn, to_lsn)`: executes `SELECT * FROM cdc.fn_cdc_get_net_changes_{capture_instance}(@from_lsn, @to_lsn, 'all')` using `Sequel.lit` with bound parameters
  - Returns array of hashes with CDC metadata columns (`__$operation`, `__$start_lsn`, etc.) and data columns
  - Capture instance name uses configurable prefix (env var `CDC_CAPTURE_INSTANCE_PREFIX`, defaults to `dbo_`)
  - Both `from_lsn` and `to_lsn` are bound parameters, not interpolated
- `current_lsn`: executes `SELECT sys.fn_cdc_get_max_lsn()` and returns the LSN value
- `min_valid_lsn(table_name)`: executes `SELECT sys.fn_cdc_get_min_lsn(capture_instance)` with bound parameters and returns the minimum valid LSN
- All methods produce expected SQL (verify via `.sql` method in tests)
- No string interpolation for table names, LSN values, or capture instance names
- All adapter tests pass
- Linter passes with no new violations

**Dependencies**

- Task 3.1 (CDC feature context)
- Phase 1 complete (adapters use Sequel DSL)

**Blocks**

- Task 3.3
- Task 3.4

---

### Task 3.3: Implement `Cdc::DatabaseExtractor` worker

**Description**

Create a new Sidekiq worker that extracts from CDC tables instead of timestamp-based queries. Implements full-load on first run, incremental load on subsequent runs, and fallback to full load when LSN is stale.

**Acceptance Criteria**

- New Sidekiq worker `Cdc::DatabaseExtractor` with `queue: :database_extractor`
- Accepts a Job object as parameter
- For each table in `DATABASE::DATA_SOURCE_TABLES`:
  1. Load `CdcPosition` record for the table
  2. If no position exists (first run): perform full SELECT of the table, store results as a raw collection
  3. If position exists: call `adapter.cdc_changes(table, from_lsn, to_lsn)` with stored LSN as `from_lsn` and `adapter.current_lsn` as `to_lsn`, store delta collection
  4. Upsert `CdcPosition` with the new LSN after successful extraction
  5. Falls back to timestamp-based extraction (full SELECT) if stored LSN is below `adapter.min_valid_lsn(table)` (retention window expiry)
- After all tables are processed, chains to the first `DatabaseTransformerProducer` in the standard pipeline
- All tests pass covering: first run (full load), incremental load, retention window expiry
- Linter passes with no new violations

**Dependencies**

- Task 3.2 (CDC methods exist)
- Task 3.1 (CDC position model exists)

**Blocks**

- Task 3.4
- Task 3.5

---

### Task 3.4: Add CDC configuration flag to `ApplicationConfiguration`

**Description**

Extend `ApplicationConfiguration` with CDC enablement flag and validation.

**Acceptance Criteria**

- `ApplicationConfiguration.cdc_enabled?` returns `true` when `CDC_ENABLED=true` env var is set
- Returns `false` otherwise (CDC is opt-in; no existing client deployments affected)
- Startup validation: if CDC is enabled but the adapter is not Microsoft SQL, raises a clear error
  - Error message: "CDC is supported only on SQL Server. Current adapter: {adapter_name}"
- Startup error prevents the application from starting (fail-fast)
- All configuration tests pass
- Linter passes with no new violations

**Dependencies**

- Task 3.3 (need to know what calls this flag)

**Blocks**

- Task 3.5

---

### Task 3.5: Integrate `Cdc::DatabaseExtractor` into `DatabaseIntegrator` worker

**Description**

Update `DatabaseIntegrator` to enqueue the correct extraction worker based on CDC enablement.

**Acceptance Criteria**

- When `ApplicationConfiguration.cdc_enabled?` is true: enqueue `Cdc::DatabaseExtractor` as the extraction entry point
- When CDC is disabled: enqueue the standard timestamp-based extractor (e.g., `Subsidiary::DatabaseExtractor`) as before
- The choice is made at job enqueue time (not extracted from Job state)
- When CDC is disabled, behavior is unchanged (backward compatible)
- All integration tests pass
- Linter passes with no new violations

**Dependencies**

- Task 3.4 (CDC enabled flag exists)
- Task 3.3 (`Cdc::DatabaseExtractor` exists)

**Blocks**

- Task 3.6

---

### Task 3.6: CDC acceptance testing and documentation for Phase 3

**Description**

Verify end-to-end CDC functionality and document CDC configuration and LSN management for operators.

**Acceptance Criteria**

- Integration test: CDC extractor performs full load on first run (no stored LSN)
- Integration test: CDC extractor performs incremental load on subsequent runs (uses stored LSN)
- Integration test: CDC extractor falls back to full load when stored LSN is below `min_valid_lsn` (retention window expiry)
- Integration test: LSN position is updated only after successful extraction (no partial advances)
- Integration test: Configuration error raised at startup when CDC is enabled on PostgreSQL
- Documentation: Operator guide for enabling CDC on source database (DBA responsibility)
- Documentation: Capture instance naming convention default (`dbo_{table_name}`)
- Documentation: How to set `CDC_CAPTURE_INSTANCE_PREFIX` if client DBA used a different naming convention
- Documentation: CDC retention window implications (default 3 days; suggest running integrator at least daily)
- All tests pass
- Linter passes with no new violations

**Dependencies**

- Task 3.5 (integration complete)

**Blocks**

- None (Phase 3 complete)

---

## Task Sequencing and Execution

### Phase 1 Sequential Flow

1. Task 1.1 (MicrosoftSqlAdapter main methods)
2. Task 1.2 (MicrosoftSqlAdapter `page`)
3. Task 1.3 (MicrosoftSqlAdapter `maximum_identifier_for`)
4. Task 1.4 (MicrosoftSqlAdapter submodules)
5. Task 1.5 (PostgresSqlAdapter main methods) — can overlap with 1.3, 1.4
6. Task 1.6 (PostgresSqlAdapter submodules)
7. Task 1.7 (`execute_procedure` risk documentation)

**Parallel opportunities**: Tasks 1.3, 1.4 can run in parallel with 1.2 (no dependencies). Task 1.5 can start as soon as 1.2 completes.

### Phase 2 Sequential Flow

1. Task 2.1 (Configuration parser)
2. Task 2.2 (QueryRunner with pagination)
3. Task 2.3 (OpenQuery::DatabaseExtractor worker)
4. Task 2.4 (DatabaseIntegrator integration)
5. Task 2.5 (Acceptance testing and documentation)

**No parallel opportunities**: Each task depends on the previous one.

### Phase 3 Sequential Flow

1. Task 3.1 (CdcPosition model)
2. Task 3.2 (MicrosoftSqlAdapter CDC methods)
3. Task 3.3 (Cdc::DatabaseExtractor worker)
4. Task 3.4 (CDC configuration flag)
5. Task 3.5 (DatabaseIntegrator integration)
6. Task 3.6 (Acceptance testing and documentation)

**Parallel opportunities**: Task 3.2 can overlap with 3.1 after initial model design is clear.

---

## Success Gate

**All tasks complete when**:

- Phase 1: All SQL in adapters uses Sequel DSL; no string interpolation; all tests pass
- Phase 2: Open queries execute safely via `QueryRunner`; both fsk_* and open queries coexist; all tests pass
- Phase 3 (optional, future): CDC extraction works for first run and incremental updates; LSN positions tracked; all tests pass
- Linter: Zero violations across all phases
- Changelog: Updated with Phase 1 and Phase 2 changes (Phase 3 is future, skip for now)

---

**Created**: 2026-03-30
**For**: integrator adapter layer evolution
**Status**: Ready for execution via `/execute`
