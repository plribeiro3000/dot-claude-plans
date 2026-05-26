# SPIKE — Migration from Sequel gem to ActiveRecord in the integrator project

**Conducted by:** Engineering
**Date:** 2026-03-26
**Status:** Research complete — pending decisions

---

## Goal

Assess the scope and complexity of replacing the Sequel gem with ActiveRecord in the `integrator` Rails application. The migration strategy is: switch to ActiveRecord, keep the adapter classes initially (only changing internals), then drop the adapter classes in a later step.

Questions this spike answers:

1. Where exactly is Sequel used today?
2. What Sequel-specific features are in play?
3. How is the database connection currently managed?
4. Are there any Sequel models?
5. What is the migration complexity per component?
6. What are the risk areas?

---

## Method

- Full codebase search for `Sequel` references in all Ruby files
- Read all adapter classes and their sub-classes
- Read connection pool initializer, Sidekiq middleware, and `ApplicationWorker`
- Read `Database` model (the façade over adapters)
- Read all `DatabaseExtractor` and `DatabaseTransformerConsumer` workers that use the connection
- Read migration files
- Checked `Gemfile`, `Gemfile.lock`, and `.rubocop.yml` for gem versions and lint rules

---

## Evidence

### 1. Sequel usage inventory

All files containing `Sequel` references (6 total):

| File | Usage |
|------|-------|
| `app/models/database.rb` | `require 'sequel'`; `Sequel::DatabaseDisconnectError`, `Sequel::DatabaseConnectionError` in `CONNECTION_EXCEPTIONS` constant |
| `app/adapters/microsoft_sql_adapter.rb` | `Sequel.connect(@connection_params)` — creates the raw connection |
| `app/adapters/postgres_sql_adapter.rb` | `Sequel.connect(@connection_params)` — creates the raw connection |
| `app/adapters/postgres_sql_adapter/permissions.rb` | `rescue Sequel::DatabaseError` |
| `app/workers/database_integrator.rb` | `rescue Sequel::DatabaseConnectionError`, `rescue Sequel::DatabaseError` |
| `app/workers/database_warmer.rb` | `rescue Sequel::DatabaseConnectionError` |

### 2. Adapter classes — structure and Sequel API usage

There are two adapter classes, one per supported database engine:

**`MicrosoftSqlAdapter`** (SQL Server via `tiny_tds`):
- `connect!`: calls `Sequel.connect(params)`, then runs 8–11 `SET` statements via `connection.execute('...')`
- `insert(collection, fields)`: uses Sequel dataset syntax `connection[collection].insert(keys, values)`
- `fetch(collection, conditions)`: raw SQL via `connection["select ..."].to_a`
- `select_ids(collection, conditions)`: raw SQL via `connection["select ..."].to_a`
- `page(collection, condition, last_id)`: raw SQL with `SELECT TOP N` pagination via `connection[query].to_a`
- `count(collection, conditions)`: raw SQL via `connection["select count..."].to_a.first[:count]`
- `delete(collection, conditions)`: raw SQL via `connection["delete from ..."].to_a.empty?`
- `sample(collection, conditions)`: raw SQL with `ORDER BY NEWID()` via `connection["select top 1 ..."].to_a.first`
- `first(collection, conditions)`: raw SQL via `connection["select top 1 ..."].to_a.first`
- `maximum_identifier_for(table)`: uses `ident_current()` (SQL Server function)
- `execute_procedure(name, params)`: raw stored procedure call via `connection.execute(...).to_a`
- `database_version`: `connection['SELECT @@version as version'].first[:version]`
- `close`: `connection.disconnect if connection.test_connection`
- `valid?`: `connection&.test_connection`

**`PostgresSqlAdapter`**:
- Identical public interface to `MicrosoftSqlAdapter`
- `connect!`: calls `Sequel.connect(params)`, no `SET` statements needed
- `insert`: same Sequel dataset syntax `connection[collection].insert(keys, values)`
- `page`: uses `LIMIT` instead of `SELECT TOP`
- `sample`: uses `WHERE RANDOM() < 0.01 LIMIT 1` instead of `ORDER BY NEWID()`
- `maximum_identifier_for`: uses `currval('table_id_seq')` instead of `ident_current()`
- `execute_procedure`: same as MSSQL
- `database_version`: `connection['select version()'].first[:version]`
- `close`/`valid?`: same as MSSQL (Sequel methods)

**Sub-classes (4 files):**

| File | Sequel usage |
|------|-------------|
| `microsoft_sql_adapter/locks.rb` | `@connection.connection["SELECT * FROM sys.dm_tran_locks ..."].to_a` — raw Sequel query |
| `microsoft_sql_adapter/permissions.rb` | `@connection.connection["SELECT HAS_PERMS_BY_NAME(...)"]` — raw Sequel query, returns hash with `:untitled` key (Sequel-specific unnamed column naming) |
| `postgres_sql_adapter/locks.rb` | `@connection.connection[query].to_a` — raw Sequel query; also calls `table_locks.save_changes` (see bug note below) |
| `postgres_sql_adapter/permissions.rb` | `@connection.connection["select count(*) as count from #{table}"]`; `rescue Sequel::DatabaseError` |

### 3. Sequel-specific features identified

| Feature | Location | Notes |
|---------|----------|-------|
| `Sequel.connect(params)` | Both adapters `connect!` | Main entry point — must be replaced |
| `connection["raw sql"].to_a` | All query methods | Sequel dataset string syntax; AR equivalent is `ActiveRecord::Base.connection.execute(sql)` returning array |
| `connection[collection].insert(keys, values)` | Both adapters `insert` | Sequel dataset insert; AR equivalent is `execute` or `connection.insert` |
| `connection.execute("SET ...")` | `MicrosoftSqlAdapter#connect!` | Used for 8 SQL Server session settings; AR has `execute` too |
| `connection.disconnect` | Both adapters `close` | Sequel disconnects; AR uses `connection.close` |
| `connection.test_connection` | Both adapters `close`/`valid?` | Sequel-specific; AR equivalent is `connection.active?` |
| `Sequel::DatabaseError` | 3 files | Error class; AR equivalent is `ActiveRecord::StatementInvalid` |
| `Sequel::DatabaseConnectionError` | 3 files | Error class; AR equivalent is `ActiveRecord::ConnectionNotEstablished` |
| `Sequel::DatabaseDisconnectError` | `database.rb` | Error class; AR equivalent is `ActiveRecord::ConnectionNotEstablished` |
| `[:untitled][:untitled]` result key | `microsoft_sql_adapter/permissions.rb` | Sequel names anonymous columns `:untitled`; AR returns `Hash` with string keys — needs verification |
| `result[:count]` / `result[:version]` | Multiple locations | Sequel returns symbol-keyed hashes; AR returns string-keyed hashes |

### 4. Database connection architecture

The connection to the **source database** (SQL Server or PostgreSQL) goes through a completely separate stack from Rails' own ActiveRecord connection:

```
config/initializers/database_pool.rb
  → ConnectionPool (connection_pool gem)
    → MicrosoftSqlAdapter.connect! OR PostgresSqlAdapter.connect!
      → Sequel.connect(params)  ← Sequel entry point
```

The `Database` model (`app/models/database.rb`) is a façade:
- Holds the `ConnectionPool` instance in a class-level accessor
- `connect!` creates a `Database` instance that delegates via `method_missing` to an adapter from the pool
- `with_connection` yields a connection from the pool directly

Connections are distributed to Sidekiq workers via `DatabaseConnectionMiddleware`:
- Runs only for queues: `database_transformer`, `database_extractor`, `api_extractor`, `api_transformer`, `statistics`
- Sets `Thread.current[:database_connection]` before job execution, clears it after
- `ApplicationWorker#connection` reads `Thread.current[:database_connection]`

**Key point**: The Rails application itself has no ActiveRecord connection to any relational database. All models are Mongoid (MongoDB). The `puma.rb` file has `ActiveRecord::Base.establish_connection` in `on_worker_boot`, but this appears to be a leftover default — there is no `config/database.yml` file in the project.

### 5. Models — are there Sequel models?

No. There are 33 Mongoid models (`include Mongoid::Document`). None inherit from Sequel::Model or use Sequel's model layer. Sequel is used exclusively at the **raw connection/dataset level** to query the *source database* (the customer's SQL Server or PostgreSQL instance being integrated).

### 6. Migrations

There are 5 migration files in `db/migrate/`. All use `Mongoid::Migration` — they operate on MongoDB, not on the Sequel-connected SQL database. The source database schema is never managed by this application.

### 7. Bug found

`app/adapters/postgres_sql_adapter/locks.rb:32` calls `table_locks.save_changes` on a `TableLocks` object. `TableLocks` is a Mongoid model. `save_changes` is a Sequel model method that does not exist on Mongoid — the correct method is `save`. The rubocop-sequel rule `Sequel/SaveChanges` is **disabled** in `.rubocop.yml`, which explains why this was never flagged. This is a pre-existing bug, not introduced by the migration.

### 8. Gem versions

| Gem | Version |
|-----|---------|
| `sequel` | 5.102.0 |
| `tiny_tds` | 3.1.0 |
| `pg` | 1.6.3 |
| `rubocop-sequel` | 0.4.1 |

### 9. Workers using the connection

The following workers call adapter methods through `Database.connect!` or `connection` (from Thread):

**`DatabaseExtractor` workers** (one per entity — 12 workers): Call `connection.page(table, conditions, last_id)` only.

Entities: `Subsidiary`, `Hierarchy`, `User`, `Client`, `Product`, `Goal`, `Deal`, `DealExtraField`, `Groupification`, `Group`, `UserField`, `UserIdentifier`, `UserActivity`, `Modifier`

**`DatabaseTransformerConsumer` workers** (9 workers): Call `connection.fetch(:users, "where users.id = #{id}")` to fetch related user rows.

Entities: `Deal`, `Groupification`, `UserField`, `Hierarchy`, `UserIdentifier`, `Modifier`, `Goal`, `UserActivity`, `User`

**`DatabaseWarmer`**: Calls `connection.database_version`, `connection.integration_version`

**`DatabaseIntegrator`**: Calls `connection.database_version`, `connection.integration_version`, `connection.permissions.missing`, `connection.locks.check(job)`

---

## Conclusions

### Migration surface

Sequel usage is **entirely contained within 6 files**, all within the adapter layer and the workers that handle connection exceptions. The migration does not touch models, migrations, or business logic.

### Migration steps per file

**Phase 1: Replace Sequel in adapters (keeping adapter interface intact)**

| File | Change needed | Complexity |
|------|--------------|-----------|
| `microsoft_sql_adapter.rb` | Replace `Sequel.connect()` with AR connection factory; replace `connection[sql].to_a` with `connection.exec_query(sql).to_a`; replace `connection[collection].insert()` with raw SQL insert; replace `connection.execute(sql)` with `connection.execute(sql)` (same name, different object); replace `connection.disconnect` → `connection.close`; replace `connection.test_connection` → `connection.active?` | Medium |
| `postgres_sql_adapter.rb` | Same as above minus the `SET` statements | Medium |
| `microsoft_sql_adapter/locks.rb` | Replace `connection[sql].to_a` with AR equivalent | Low |
| `microsoft_sql_adapter/permissions.rb` | Replace `connection[sql]` with AR; the `:untitled` symbol key access for anonymous columns needs verification against AR behavior | Medium-High |
| `postgres_sql_adapter/locks.rb` | Replace `connection[sql].to_a` with AR; fix pre-existing `save_changes` → `save` bug | Low |
| `postgres_sql_adapter/permissions.rb` | Replace `connection[sql].to_a`; replace `rescue Sequel::DatabaseError` with AR equivalent | Low |

**Phase 2: Replace Sequel exception classes**

| File | Change needed | Complexity |
|------|--------------|-----------|
| `app/models/database.rb` | Replace 3 Sequel exception classes in `CONNECTION_EXCEPTIONS`; remove `require 'sequel'` | Low |
| `app/workers/database_integrator.rb` | Replace 2 Sequel exception classes in `rescue` clauses | Low |
| `app/workers/database_warmer.rb` | Replace 1 Sequel exception class in `rescue` clause | Low |

### Risk areas

1. **Anonymous column naming**: Sequel names anonymous SQL columns `:untitled` (symbol). `MicrosoftSqlAdapter::Permissions#access_allowed_for` accesses `response[:untitled][:untitled]`. ActiveRecord's `exec_query` returns a `Result` object with string-keyed hashes. The query must be rewritten to use a named alias (`HAS_PERMS_BY_NAME(...) AS has_permission`) and the accessor updated accordingly.

2. **Result key format**: Sequel returns symbol-keyed hashes (`:count`, `:version`, `:lastidentityvalue`). ActiveRecord returns string-keyed hashes (`"count"`, `"version"`, `"lastidentityvalue"`). Every place that reads `result[:key]` must change to `result["key"]` or `result.first["key"]`. This appears in all query methods of both adapters.

3. **SQL Server adapter support in ActiveRecord**: ActiveRecord supports SQL Server via the `activerecord-sqlserver-adapter` gem (which requires `tiny_tds`). This gem must be added to the Gemfile. The connection parameters format differs from Sequel's.

4. **`connection.execute` on ActiveRecord for non-SELECT**: In Sequel, `connection.execute(sql)` works for both DDL and DML. In ActiveRecord, `connection.execute(sql)` behaves differently per adapter — for SQL Server via `tiny_tds`, this needs testing. The `MicrosoftSqlAdapter#connect!` runs 8–11 `SET` statements on connection open; this pattern must be preserved.

5. **Connection pool ownership**: The current design uses the `connection_pool` gem to manage a pool of adapter objects, each wrapping a Sequel connection. If migrating to ActiveRecord's built-in connection pool, the entire `Database.connection_pool` / `DatabaseConnectionMiddleware` / `Thread.current[:database_connection]` stack may need to be redesigned. If keeping the custom pool (wrapping AR connections), the adapter internal changes are isolated.

6. **`connection.test_connection` / `valid?`**: Used in the pool `reap` callback and in `close`. ActiveRecord's equivalent (`connection.active?`) has different semantics depending on the adapter.

7. **Pre-existing bug**: `postgres_sql_adapter/locks.rb` calls `save_changes` (Sequel API) on a Mongoid object. This must be fixed to `save` as part of the migration, but is not itself a migration risk — it is a separate bug.

---

## Decisions (2026-03-26)

1. **Connection pool**: Migrate to ActiveRecord's native connection pool. May start with the custom pool as an intermediate step, but the final state must use AR's pool (replacing `connection_pool` gem + `DatabaseConnectionMiddleware` + `Thread.current[:database_connection]` stack).
2. **`activerecord-sqlserver-adapter`**: Will be added to the Gemfile. `tiny_tds` explicit declaration will be removed (it's a transitive dependency of the adapter, `~> 3.0`).
3. **`sequel` gem**: Will be removed from Gemfile after migration is complete.
4. **`rubocop-sequel` gem**: Will be removed from Gemfile after migration is complete.

## Next Steps

- **Prototype recommended**: Before implementing, test `exec_query` behavior for the anonymous column issue in `MicrosoftSqlAdapter::Permissions` against a SQL Server instance. The fix is straightforward (add a column alias), but the behavior must be confirmed.
- **Immediate fix (independent of migration)**: The `save_changes` bug in `postgres_sql_adapter/locks.rb` can be fixed now without touching the Sequel migration.
- Proceed to `@agent-planner` to create a PLAN.md for the migration.

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
