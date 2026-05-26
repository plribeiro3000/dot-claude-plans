# Source data access

A worker that needs to read from a customer's database calls `stream.source.connect!` and gets back an adapter — `MicrosoftSqlAdapter` or `PostgresSqlAdapter` — that exposes a small read API: `fetch`, `page`, `count`, `first`, `sample`, `select_ids`. Underneath, the adapter wraps a `Sequel::Database` whose internal connection pool is the only pooling layer in the integrator. This chapter covers the shape, why it ended up that way, and the historical context that explains a wrong path the codebase took for a few months.

## The adapter is cached per Source

`DatabaseSource#connect!` does not open a new connection per call. It returns an adapter from a class-level cache keyed by Source id:

```ruby
def connect!
  self.class.adapters.compute_if_absent(id.to_s) do
    case adapter
    when 'microsoft_sql_server' then MicrosoftSqlAdapter.connect!(configuration)
    when 'postgres_sql_server' then PostgresSqlAdapter.connect!(configuration)
    end
  end
end

def self.adapters
  @adapters ||= Concurrent::Map.new
end
```

The first call instantiates the adapter (and its underlying `Sequel::Database`); every subsequent call from any worker, on any thread, on the same Source returns the same instance. The cache is a `Concurrent::Map` for thread-safety; `compute_if_absent` is atomic, so two workers calling `connect!` on the same Source at the same instant won't race to create two adapters.

The adapter lives for the lifetime of the Sidekiq process. There is no per-job teardown — the connection state survives across jobs, which is desirable: opening a SQL connection costs milliseconds, and a busy integrator processes hundreds of queries per minute.

## Sequel's pool is the connection pool

Each adapter holds a `Sequel::Database`. That object internally manages a pool of TCP connections to the customer's database (`Sequel::ThreadedConnectionPool` by default, sized by `max_connections`). When the adapter is asked to run a query, Sequel checks out one connection from the pool, executes, and checks it back in. Multiple worker threads using the same adapter share the pool: a Sidekiq concurrency of 10 means up to 10 simultaneous queries against one customer's database, each on its own connection, without explicit coordination from the integrator code.

The pool's size defaults to `ApplicationConfiguration.sql_pool_size` — `(sidekiq_threads * 1.2).ceil`, so the pool has a small buffer above the expected concurrent demand. A Source can override this with its own `max_connections` field when the customer's database has a tight connection limit (rare but real).

The worker-side code is simple: get an adapter, call a query method, ignore connection lifecycle. There is no `connection.close` after a query; the Sequel pool releases the connection automatically when the query completes. There is no `with_connection { ... }` block; the entire pool dance is hidden inside Sequel.

## Shutdown

The integrator registers an `at_exit` hook in `config/initializers/database_pool.rb`:

```ruby
at_exit do
  DatabaseSource.adapters.each_value(&:disconnect!)
end
```

On process termination, every adapter that was instantiated during the process's lifetime gets `disconnect!` called, which forces the underlying `Sequel::Database` to close every TCP connection in its pool. This is the only place the integrator code explicitly tears connections down — during normal operation, the pool maintains them.

The initializer creates no adapters. A misconfigured Source (wrong host, wrong credentials) does not prevent the application from booting because the adapter is only instantiated on the first `connect!` call, well after boot.

## The read API

Both adapters expose the same surface, called by the workers without caring which database technology is underneath:

- **`fetch(table, conditions = {})`** — returns an array of rows matching the given filter. Used by the Transformer JOIN steps for normalized Sources (e.g. `connection.fetch(:users, { id: 42 })`)
- **`page(table, condition, last_id)`** — keyset-paginated scan. Used by the Extractor for legacy single-table reads (now mostly superseded by per-Stream Liquid templates that the adapter executes via `connection.fetch(Sequel.lit(query))`)
- **`count(table, conditions = {})`** — row count. Used by the ThroughputCalculator
- **`first`/`sample`** — single-row helpers, used in dev seed scripts and rare sanity-check paths
- **`select_ids(table, conditions = {})`** — projects only the primary-key column. Used when the worker needs a list of identifiers to fan out, not the full rows
- **`delete(collection, conditions = '')`** — the only write method; used by dev seed task to drop test data
- **`execute_procedure(name:, params:)`** — invoke a stored procedure. Used by the dev seed and by integrations that pull data through stored procs rather than queries
- **`database_version`** / **`integration_version`** — version probes. `database_version` runs `SELECT @@version` (MSSQL) or `SELECT version()` (Postgres) and returns the server's version string; `integration_version` reads the most recent row of a `versions` table that the normalized schema bootstrap creates

The MSSQL adapter additionally issues a sequence of `SET` statements on connection start (`SET QUOTED_IDENTIFIER ON`, `SET ANSI_DEFAULTS ON`, etc.) to put the connection in a state compatible with the integrator's queries. The Postgres adapter has no such ceremony.

## Liquid-rendered queries

The actual query text the adapter executes for an Extract is rendered from the Stream's `query_template` (or `paginated_query_template`) via Liquid. The Variables helper provides values like `fetch_since`, `page_size`, `previous_record_id`, plus a set of derived timestamps (beginning-of-month, end-of-year, etc., timezone-converted to the Source's `timezone`).

The rendered query reaches the adapter as a fully-formed SQL string and is executed via `connection.fetch(Sequel.lit(query))`. The adapter does **not** apply a `table_prefix` at the adapter level — the prefix is interpolated into the template by the bootstrap when it generates the Stream documents. This is a deliberate choice: keeping the prefix out of the adapter means the same adapter works identically for normalized and custom-shaped Streams. The query the adapter sees is the query that runs.

## What changed in PR #2174 (and why)

Up through October 2025, the integrator carried a global `Database` model that held a single class-level `connection_pool` (using the `connection_pool` gem). Every worker called `Database.connect!` to get the global adapter. This was added in commit `f19c7b1a` ("fix(*): Connection Pool") to address a real production problem: customers were seeing the integrator open hundreds of database connections under concurrent load and leave them open. The connection_pool gem fixed the symptom.

It fixed the symptom by accident. The actual problem was that `MicrosoftSqlAdapter.new` was being called on every `Database.connect!` — each call instantiated a new `Sequel::Database`, which in turn created its own internal pool. Sequel's pool was already there; what was missing was caching the **adapter** so the same `Sequel::Database` could be reused across calls. The connection_pool gem cached the adapter, which incidentally also gave it the pool semantics it appeared to be solving — but the real fix should have been "cache the adapter" without adding a second pooling layer on top of Sequel's existing one.

PR #2174 corrected the design:

- The global `Database` model is deleted
- `DatabaseSource.adapters` (a `Concurrent::Map`) caches the adapter per Source
- The `connection_pool` gem is dropped from the Gemfile (still present transitively because Sidekiq and Mongoid pull it in)
- Sequel's internal pool is the single layer

The behavior the production fix was after — bounded connection count, no leaks — is preserved. The mechanism is now Sequel's, which it always was; the integrator just stops stacking a second mechanism on top.

## Why this matters for someone reading the code

A worker that opens a database connection looks like this today:

```ruby
connection = stream.source.connect!
records = connection.fetch(:users, { id: record['user_id'] })
```

There is no `ensure` block to close the connection, no block-style `with_connection`, no `release` call. A reader new to the codebase reasonably expects "I opened, I have to close". The answer is no — the cached adapter is meant to be open, and the Sequel pool releases each per-query connection automatically. The shape is the way it is because **Sequel already does the work**, and the integrator's job is to not interfere.

The ~50 `connection.close` calls that used to pepper the worker code (one per Sidekiq job that opened a connection) were removed in PR #2174 along with the global `Database` model. They were no-ops in the new design — at best harmless, at worst (if a future change made the cached adapter think it had been closed) source of subtle bugs.

## Source data access from places that aren't workers

A few non-worker call sites need a database adapter:

- **`Job::Starter`** — calls `Source.find_by(normalized: true).connect!.database_version` to stamp the Job with the customer's database version and (as a side effect) wake an idle database
- **`ThroughputCalculator`** — pre-flight throughput estimation, reads row counts from the normalized Source
- **`db:sql:seed` rake task** — dev-only, populates a local SQL Server with fake data via the adapter's `execute_procedure` method; not used in production

Each of these calls `Source.normalized.first.connect!` (when there's a normalized Source). The same caching applies — they get the same adapter the workers use.

## Why the customer database connection lives in the integrator's process, not in Mongoid

A reasonable alternative architecture would push the database read out of the Ruby process and into a separate service (a Sidekiq worker dedicated to SQL extraction, or a Lambda function, or a sidecar). The integrator does not do this. The reason is operational simplicity: the per-Stream Extractor is already a Sidekiq job, and giving it direct access to the SQL adapter inside the same Ruby process keeps the call stack short and the failure modes obvious. A separate service would add network hops, serialization costs, and one more thing to monitor.

The trade-off is that the Sidekiq process holds open SQL connections for the customer's entire deploy lifetime. With the per-Source adapter cache, that means N Sequel pools live in memory (one per Source). For typical customers (1-2 Sources), this is unobservable; for hypothetical customers with dozens of Sources, the integrator process memory would grow. The current customer base is well under any limit where this matters.

## Summary

One adapter per Source, cached at class level on `DatabaseSource`, holding a `Sequel::Database` whose internal pool is the only pool. Workers open and use; they do not close. Sequel handles concurrency; the integrator's code does not. Shutdown calls `disconnect!` on every cached adapter via `at_exit`. The pre-2174 connection-pool-gem layer was a fix for the wrong half of the problem and is gone.
