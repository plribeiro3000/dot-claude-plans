# PLAN - Migrate Sequel to ActiveRecord

> Reference: SPIKE.md at `~/.claude/plans/completed/spike/sequel-to-activerecord/SPIKE.md`

> **STATUS: CANCELLED (2026-03-30)**
>
> This plan was cancelled after further analysis concluded that Sequel is the better tool for the
> integrator's use case. See [Decision Record](#decision-record) at the end of this document.

## Original Objective

Replace the Sequel gem with ActiveRecord as the raw SQL client for connecting to customer databases
(SQL Server and PostgreSQL). The adapter public interface remains unchanged — workers are not
touched. The final state uses ActiveRecord's native connection pool, eliminating the `connection_pool`
gem, `DatabaseConnectionMiddleware`, and `Thread.current[:database_connection]`.

## Scope

### In Scope
- Replace `Sequel.connect()` with ActiveRecord connection establishment in both adapters
- Replace all Sequel dataset API calls with `ActiveRecord::Base.connection.exec_query` equivalents
- Replace Sequel exception classes with ActiveRecord equivalents in all rescue clauses
- Replace `connection.test_connection` / `connection.disconnect` with AR equivalents
- Fix symbol-keyed result access (`result[:key]`) to string-keyed access (`result["key"]`)
- Fix anonymous column naming issue in `MicrosoftSqlAdapter::Permissions#access_allowed_for`
- Fix pre-existing `save_changes` bug in `postgres_sql_adapter/locks.rb`
- Migrate from custom `connection_pool` gem + `Thread.current` stack to ActiveRecord's native pool
- Add `activerecord-sqlserver-adapter` gem to Gemfile
- Remove `sequel`, `rubocop-sequel`, and explicit `tiny_tds` declarations from Gemfile

### Out of Scope
- Dropping the adapter classes themselves (separate future effort)
- Changing the public interface of any adapter method
- Modifying any worker (`DatabaseExtractor`, `DatabaseTransformerConsumer`, `DatabaseWarmer`,
  `DatabaseIntegrator`, `ApplicationWorker`)
- Changing the `Database` model's public interface
- Migrating MongoDB/Mongoid models

## Execution Phases

### Phase 1: Swap Sequel internals in adapters for ActiveRecord

**Objective**: Both adapter classes (`MicrosoftSqlAdapter` and `PostgresSqlAdapter`) and all four
sub-classes (`locks.rb`, `permissions.rb` for each) use ActiveRecord for all SQL operations. The
`connection_pool` gem and `DatabaseConnectionMiddleware` remain in place — only the internals of
each adapter change.

**Components**:

- `Gemfile`: Add `activerecord-sqlserver-adapter`. Keep `connection_pool`, `sequel`, `tiny_tds`
  (sequel and tiny_tds removed in Phase 3).

- `MicrosoftSqlAdapter#initialize`: Change `@connection_params` to ActiveRecord/SQL Server adapter
  format (`adapter: "sqlserver"`, `host:`, `port:`, `database:`, `username:`, `password:`,
  `timeout:`). Remove `azure:` and `max_connections:` keys (not used by AR adapter).

- `MicrosoftSqlAdapter#connect!`: Replace `Sequel.connect(@connection_params)` with
  `ActiveRecord::Base.establish_connection(@connection_params)` on a dedicated subclass (see
  technical decisions). Run the same 8-11 `SET` statements via `@connection.execute(sql)`.

- `MicrosoftSqlAdapter` query methods (`fetch`, `select_ids`, `page`, `count`, `delete`, `sample`,
  `first`, `maximum_identifier_for`, `database_version`): Replace
  `connection["select ..."].to_a` with `connection.exec_query("select ...").to_a`. Change all
  `result[:symbol_key]` accesses to `result["string_key"]`.

- `MicrosoftSqlAdapter#insert`: Replace `connection[collection].insert(keys, values)` with a
  manually constructed `INSERT INTO ... VALUES (...)` statement via `connection.execute`.

- `MicrosoftSqlAdapter#execute_procedure`: Replace `connection.execute(sql).to_a` with
  `connection.exec_query(sql).to_a`.

- `MicrosoftSqlAdapter#close` and `#valid?`: Replace `connection.disconnect` with
  `connection.close` (or disconnect via the AR handler) and `connection.test_connection` with
  `connection.active?`.

- `PostgresSqlAdapter`: Same changes as MSSQL adapter. `@connection_params` uses
  `adapter: "postgresql"` (standard AR format). No `SET` statements needed. `page` uses `LIMIT`.
  `sample` uses `random()`. `maximum_identifier_for` uses `currval`.

- `microsoft_sql_adapter/locks.rb`: Replace `@connection.connection[query].to_a` with
  `@connection.connection.exec_query(query).to_a`.

- `microsoft_sql_adapter/permissions.rb`: Rewrite `access_allowed_for` to add a named alias
  (`HAS_PERMS_BY_NAME(...) AS has_permission`). Replace `response[:untitled][:untitled]` with
  `response.first["has_permission"]`. Replace `connection[sql]` with `exec_query`.

- `postgres_sql_adapter/locks.rb`: Replace `@connection.connection[query].to_a` with
  `@connection.connection.exec_query(query).to_a`. Fix pre-existing bug:
  `table_locks.save_changes` → `table_locks.save`.

- `postgres_sql_adapter/permissions.rb`: Replace `connection[sql].to_a` with
  `connection.exec_query(sql).to_a`. Replace `rescue Sequel::DatabaseError` with
  `rescue ActiveRecord::StatementInvalid`.

- `app/models/database.rb`: Replace Sequel exception classes in `CONNECTION_EXCEPTIONS`
  (`Sequel::DatabaseDisconnectError`, `Sequel::DatabaseConnectionError`) with
  `ActiveRecord::ConnectionNotEstablished`. Remove `require 'sequel'`.

- `app/workers/database_integrator.rb`: Replace `rescue Sequel::DatabaseConnectionError` and
  `rescue Sequel::DatabaseError` with AR equivalents.

- `app/workers/database_warmer.rb`: Replace `rescue Sequel::DatabaseConnectionError` with AR
  equivalent.

**Dependencies**: None — this is the first phase.

**Success Criteria**:
- [ ] Both adapters connect to their respective databases using ActiveRecord
- [ ] All query methods return the same data structure they returned with Sequel (array of hashes)
- [ ] `insert` returns `true` on success
- [ ] `execute_procedure` returns an array of hashes
- [ ] `close` and `valid?` behave correctly with ActiveRecord semantics
- [ ] `MicrosoftSqlAdapter::Permissions#access_allowed_for` works with a named column alias
- [ ] `postgres_sql_adapter/locks.rb` bug fixed (`save` instead of `save_changes`)
- [ ] No `Sequel` references remain in any adapter or worker file
- [ ] `connection_pool` initializer still works (pool still wraps adapter objects)
- [ ] `DatabaseConnectionMiddleware` still assigns to `Thread.current[:database_connection]`
- [ ] Workers continue to call adapter methods without any changes
- [ ] Linter passes with no new violations

### Phase 2: Migrate to ActiveRecord's native connection pool

**Objective**: Remove the `connection_pool` gem, `DatabaseConnectionMiddleware`, and
`Thread.current[:database_connection]`. The `Database` model and `ApplicationWorker` are updated
to use ActiveRecord's connection pool. The final architecture no longer has a custom pool.

**Components**:

- `config/initializers/database_pool.rb`: Replace `ConnectionPool.new(...)` block with AR
  connection handler registration. Each customer database gets its own AR connection spec registered
  under a named key. Remove `connection_pool` gem require. Remove reap thread and `at_exit` shutdown
  (AR manages its own lifecycle).

- `app/models/database.rb`: Remove `ConnectionPool` usage. Change `connect!` and `with_connection`
  to use AR connection pool directly. Remove `CONNECTION_EXCEPTIONS` entry for
  `ConnectionPool::TimeoutError`.

- `app/middlewares/database_connection_middleware.rb`: Remove entirely. AR manages connections per
  thread automatically via connection checkout/checkin.

- `app/workers/application_worker.rb`: Remove `Thread.current[:database_connection]` accessor.
  Workers call adapters via `Database.connect!` which checks out a connection from AR pool.

- `config/initializers/database_pool.rb`: Rewritten to register AR connection spec for the
  customer database at startup.

**Dependencies**: Phase 1 must be complete. All adapter internals must use ActiveRecord connections
before the pool can be migrated.

**Success Criteria**:
- [ ] No references to `connection_pool` gem remain in application code
- [ ] No references to `Thread.current[:database_connection]` remain
- [ ] `DatabaseConnectionMiddleware` removed from the middleware stack
- [ ] Workers obtain connections from AR pool without any `Thread.current` pattern
- [ ] Multiple concurrent Sidekiq workers can hold simultaneous connections to the same or different
      customer databases without contention
- [ ] Pool size is configurable (equivalent to current `ApplicationConfiguration.sql_pool_size`)
- [ ] Connections are properly returned to the pool after each job
- [ ] Linter passes with no new violations

### Phase 3: Remove Sequel and clean up Gemfile

**Objective**: Remove all gem references that are no longer needed once the migration is complete.

**Components**:

- `Gemfile`: Remove `gem 'sequel'`, `gem 'rubocop-sequel'`, and explicit `gem 'tiny_tds'`
  declaration (`tiny_tds` remains as a transitive dependency of `activerecord-sqlserver-adapter`).
- `Gemfile.lock`: Updated by running `bundle install`.
- `.rubocop.yml`: Remove the `Sequel/SaveChanges` disable entry (the bug it was hiding is fixed).

**Dependencies**: Phases 1 and 2 must be complete. No Sequel references must exist anywhere.

**Success Criteria**:
- [ ] `bundle install` succeeds after gem removals
- [ ] `require 'sequel'` and `require 'tiny_tds'` do not appear anywhere in the codebase
- [ ] `rubocop-sequel` no longer in `Gemfile`
- [ ] `Sequel/SaveChanges` disable entry removed from `.rubocop.yml`
- [ ] Full test suite passes
- [ ] Linter passes with no violations

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| AR connection per adapter | Dedicated `AbstractAdapter` AR subclass per engine | AR requires a class to `establish_connection` against; using subclasses (`MicrosoftSqlAdapterBase < ActiveRecord::Base`, `PostgresSqlAdapterBase < ActiveRecord::Base`) keeps connections isolated per engine and avoids polluting `ActiveRecord::Base` |
| SQL Server AR adapter | `activerecord-sqlserver-adapter` | The only maintained AR adapter for SQL Server; manages `tiny_tds` as a transitive dependency |
| Query execution | `exec_query(sql).to_a` | Returns an `ActiveRecord::Result` that responds to `to_a`, yielding an array of string-keyed hashes — same shape as Sequel minus the symbol keys |
| `execute` for DDL/DML | `connection.execute(sql)` | Used only for `SET` statements in `MicrosoftSqlAdapter#connect!` and for `insert` — returns adapter-specific result, but return value is not used |
| `insert` implementation | Raw SQL `INSERT INTO ... (cols) VALUES (vals)` via `execute` | Replaces Sequel's dataset `insert`; no AR model available since the target is the customer's schema |
| Anonymous column fix | Add `AS has_permission` alias in the SQL query | Sequel named anonymous columns `:untitled`; AR returns them with empty string keys or raises — adding an alias is the safest and most explicit fix |
| AR native pool (Phase 2) | `ActiveRecord::Base.connection_handler` with named specs | Supports multiple simultaneous connections to different databases; each named spec gets its own pool |
| `connection_pool` gem removal | Phase 2, after adapter internals are stable | Reduces risk: Phase 1 validates AR connections work correctly before dismantling the pool layer |

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| `exec_query` result format differences | High | Audit every `result[:key]` access and change to `result["key"]`; covered by success criteria |
| Anonymous column naming in Permissions | High | Add explicit `AS has_permission` alias before migrating; verify output |
| SQL Server `SET` statements via AR | Medium | `connection.execute` works for non-SELECT in the sqlserver adapter; test `connect!` against a real or stubbed SQL Server connection |
| AR connection pool behavior under Sidekiq concurrency | Medium | Test with multiple workers active simultaneously; ensure `pool_size` matches Sidekiq concurrency config |
| `connection.active?` semantics differ from `test_connection` | Medium | `active?` does a lightweight ping; if it raises, `valid?` must rescue `StandardError` — same rescue already exists |
| Missing `config/database.yml` | Low | AR connection specs are registered programmatically via `establish_connection` — no YAML file needed |
| `at_exit` / reap thread removal in Phase 2 | Low | AR manages connection lifecycle automatically; no custom shutdown needed |

## Assumptions

- The `activerecord-sqlserver-adapter` gem is compatible with the current Ruby and Rails version in
  the project.
- Customer databases are always SQL Server or PostgreSQL — no other engines are in use.
- `ApplicationConfiguration` provides all connection parameters needed (host, port, database,
  username, password, timeout, azure flag).
- The `connection_pool` gem's `size:` and `timeout:` semantics map directly to AR pool's `pool:` and
  `checkout_timeout:` options.
- Tests exist or will be written to validate adapter behavior after the migration.
- No worker reads `Thread.current[:database_connection]` directly other than `ApplicationWorker#connection`.

---

## Decision Record

**Date:** 2026-03-30
**Decision:** Do not migrate from Sequel to ActiveRecord. Keep Sequel as the database client.

### Context

The integrator is evolving toward a new phase where it will support **open queries** (arbitrary SQL
provided by clients) instead of only the normalized `fsk_*` schema. Additionally, **CDC (Change Data
Capture)** support from SQL Server is being evaluated as a future feature for incremental sync.

A comparative analysis of data movement tools (Fivetran, Hevo Data, Airbyte) concluded that these
tools solve connectivity but not data discovery — and since 4Shark is building its own discovery
tooling with AI, the value of adopting a data movement tool is diminished. This shifts the strategy
toward evolving the integrator itself.

### Why Sequel is the better choice

1. **Performance**: Sequel is 7.5x faster than ActiveRecord for simple SELECT queries (2,777 i/s vs
   372 i/s in benchmarks). For an ETL pipeline that executes thousands of queries per integration
   cycle, this difference is material.

2. **Memory**: Sequel uses 2.8x less memory for large result sets (45 MB vs 125 MB). The integrator
   processes large volumes of data from client databases — lower memory footprint means fewer
   infrastructure constraints.

3. **Connection pool efficiency**: Sequel reserves connections only during query execution and returns
   them immediately. ActiveRecord holds connections per thread until the thread dies. Under Sidekiq
   concurrency (25 threads), Sequel's model is significantly more efficient and avoids pool exhaustion.

4. **Multi-database simplicity**: Each `Sequel.connect()` returns an independent database object.
   ActiveRecord requires dedicated base classes per connection and `connects_to` configuration —
   more ceremony for a system that connects to different client databases.

5. **ORM features are irrelevant**: The integrator connects to **external client databases** with
   unknown schemas. ActiveRecord's value proposition (models, associations, validations, scopes) does
   not apply. Both tools end up executing raw SQL via `exec_query` or `connection[sql]` — but Sequel
   does it faster with less overhead.

6. **CDC support**: Neither ActiveRecord nor Sequel has native CDC support. Both require raw SQL to
   query CDC change tables (`cdc.fn_cdc_get_net_changes_*`). No advantage either way.

7. **Open queries**: For arbitrary client-provided SQL, the execution path is raw SQL in both cases.
   Sequel's DSL and `Arel::Table` (from ActiveRecord) can both build dynamic queries, but the
   integrator's actual need is to execute SQL strings — Sequel's bracket syntax (`connection[sql]`)
   is simpler and faster.

### What to do instead

The adapter layer's real problems are not about Sequel vs ActiveRecord:

1. **SQL injection risk**: Current adapters use string interpolation for query building. This must be
   fixed using Sequel's native parameterization or DSL — not by switching ORMs.

2. **Open query support**: Generalize the adapter to accept configurable queries instead of
   hardcoded `fsk_*` table references.

3. **CDC support (future)**: When needed, add CDC change table reading as a new extraction mode
   alongside the existing timestamp-based approach.

### Superseded by

This plan is superseded by a new planning effort to evolve the integrator's adapter layer for open
queries and CDC support while keeping Sequel as the database client.
