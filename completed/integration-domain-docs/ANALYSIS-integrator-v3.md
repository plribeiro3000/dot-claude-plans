# Integrator Domain Analysis — v3 (post-source-driven refresh)

**Date:** 2026-05-07
**Phase:** Phase 4 (D3 — Integrator Domain) — survey refreshed
**Base:** `develop` @ `d3dbc67d` (merge commit of PR [#2174](https://github.com/4shark/integrator/pull/2174) `feature/source-driven-database-config`, squashed into `5c0aee45`).
**Status:** Source of truth for D3 drafting from here on. v2 stays as the historical record of the post-PR-#2120 / pre-PR-#2174 state. v1 stays as the historical record of the pre-PR-#2120 state.

## Why v3 was needed

PR #2174 was originally scoped as Phase 4.1 — a small "replace `managed_integration?` flag" cleanup before drafting D3. It grew during code review into a structural refactor that touches the same chapters v2 was anchored on (3, 5, 6, 8, 12). Drafting against v2 would produce documentation that is correct in shape but wrong on details that matter to anyone debugging the post-merge code.

The shape of the v2 outline survives — the 13 chapters still describe the integrator faithfully. The deltas are narrow but concrete and sit inside chapters that need to be precise (the configuration surface, the data-access layer, the transformer pipeline, the bootstrap).

## What PR #2174 did, in domain terms

Five concrete changes, all consequences of one decision: "the source is the unit of database configuration, and Sequel's built-in connection pool is the single layer of pooling."

1. **`ApplicationConfiguration.managed_integration?` and friends were deleted** — the flag and the four siblings (`self_service_integration?`, `api_integration?`, `database_integration?`, `integration_mode`) plus the `INTEGRATION_MODE` env var. The view branch in `integration_report_mailer/create.html.erb` and the symmetric encryption initializer now use `Integrator.fully_normalized?` (defined in `lib/integrator.rb`, returning `Source.size == 1 && Source.normalized.size == 1`). The encryption initializer became unconditional in production (raises if keys are missing) and a no-op elsewhere.

2. **Database configuration moved off `ApplicationConfiguration` and onto `DatabaseSource`.** The model gained `warm_up` (Boolean) and `max_connections` (Integer) fields. The connection params hash is built by `DatabaseSource#configuration` and passed directly to `Sequel.connect` — `ApplicationConfiguration.connection_params` is gone. `max_connections` defaults to `ApplicationConfiguration.sql_pool_size` when the source does not set it explicitly.

3. **The global `Database` model and the external `connection_pool` gem layer were removed.** `app/models/database.rb` is deleted. `app/middlewares/database_connection_middleware.rb` is deleted. `def connection` on `ApplicationWorker` is gone. The `connection_pool` gem is dropped from `Gemfile` (still present as a transitive dep). One adapter is cached per source in `DatabaseSource.adapters` (`Concurrent::Map`); `connect!` returns the cached adapter directly. Sequel's built-in `ThreadedConnectionPool` (sized by `max_connections`) is the single layer of pooling. `connection.close` was removed from ~50 call sites across workers, services and rake tasks; Sequel releases each connection back to its internal pool automatically after every query. The adapters expose `disconnect!` for shutdown only — invoked by `config/initializers/database_pool.rb` in an `at_exit` hook that iterates `DatabaseSource.adapters`.

4. **The legacy duplicate worker chain was deleted (42 files).** 14 `*::DatabaseExtractor` (the pre-PR-#2120 normalized-DB extractor that read from fixed table names via the global `Database` adapter), 14 `*::DatabaseTransformerProducer`, and 14 `*::DatabaseTransformerConsumer` (the matching transformer that did per-record load with `users`/`parents` JOINs). All 42 had zero external callers post PR #2120 — they were orphaned but kept the code carrying two parallel transform implementations. The `Managed` prefix was dropped from every per-resource worker file/class. The dead worker chain that survived from a separate older pipeline (`HealthCheck::Processor`, `ConnectionCheck::Processor`, `*_report/{producer,consumer}`, the mailer + view + locales) was deleted in the same PR.

5. **The normalized JOIN logic moved from the deleted legacy `*::DatabaseTransformerConsumer` workers into the live `*::TransformerConsumer` workers' `if stream.source.normalized?` branch.** Eight resources need the JOIN: Hierarchy (user + parent conditional), UserIdentifier, Groupification, UserField, UserActivity, Deal, Modifier (user always), and Goal (user conditional). The 10 `User::*::TransformerConsumer` variants already had the parent JOIN before this PR — only the prefix was removed. The 5 unrelated transformers (Subsidiary, Client, Product, Group, DealExtraField) had no JOIN in either version. The `connection = stream.source.connect!` opens at the start of the normalized branch and is implicit-released at the end of the worker (Sequel pool checkin is automatic).

Two ancillary fixes:

- **`fetch_since_column: 'created_at'` was added to four entries of `NORMALIZED_SCHEMA`** (Hierarchy, Groupification, UserField, UserActivity). The legacy `*::DatabaseExtractor` workers filtered these by `created_at`, but the streams created by the bootstrap defaulted the column to `updated_at` because `NORMALIZED_SCHEMA` did not declare a `fetch_since_column` for them. The post-PR-#2120 pipeline silently captured a different set of rows than the pre-PR-#2120 pipeline did. v3 acknowledges this as a fix; v2 had not noticed.
- **`DatabaseWarmer` became a Producer/Consumer pair.** The pre-PR-#2174 single class (`app/workers/database_warmer.rb`) was deleted. `DatabaseWarmer::Producer` plucks `DatabaseSource.where(warm_up: true).pluck(:id)`, resets a `Computation` counter, and bulk-pushes one Consumer per source. `DatabaseWarmer::Consumer` calls `source.connect!.database_version` (a real round-trip the database has to wake up to answer) and increments the counter; the last one to close the count chains to `Job::Starter`. Retries propagate `retry_count` through the Sidekiq job payload (via `Sidekiq::Client.push` with explicit `retry_count`) so `UnreachableDatabaseException` can fire after sustained failure — `perform_in` would have reset the counter on every reschedule.

## Method

- Read `app/models/database_source.rb`, `lib/integrator.rb`, `app/workers/job/starter.rb`, `app/workers/database_warmer/{producer,consumer}.rb`, `config/initializers/database_pool.rb`, `config/initializers/symmetric_encryption.rb`, `config/normalized_schema.rb`, `app/workers/hierarchy/transformer_consumer.rb` (representative `*::TransformerConsumer` with both user and parent JOINs)
- Cross-checked `git log --oneline d3dbc67d ^06b5721a` (`develop` advance from end of PR #2120 to end of PR #2174) — single commit `5c0aee45`
- Confirmed the historical context of the external pool against `git show f19c7b1a` (the original "fix(*): Connection Pool" commit from October 2025) — Sequel pool was already active; the external `connection_pool` gem was added on top without removing the inner one. v3 records this as a clarified design rationale, not a recent change.

## Updated inventory (deltas from v2)

The inventory headings below mirror v2. Sections marked **(unchanged)** are still accurate as written in v2 — refer to v2 for the full inventory.

### Pipeline orchestration — *(EDITED)*

- **`Job::Starter` worker** — entrypoint, **renamed** from `ManagedIntegrator`. Same role and shape. Now reads the integration version + database version from `Source.find_by(normalized: true).connect!` directly (no global `Database` adapter); the conditional block runs only `if Source.normalized.any?`.
- **`Job::Finisher` worker** — *(unchanged)*.
- **No central pipeline coordinator** — *(unchanged; worker chaining only).* The `Managed` prefix is gone from every per-resource worker class name; what v2 called "a legacy artifact" is no longer a description anyone needs to understand the codebase.
- **`Computation` (Redis) primitive** — *(unchanged).*

### Source configuration — *(EDITED)*

- **Source / ApiSource / Stream / ResourceType / AttributeMapping / Authentication** — *(unchanged from v2).*
- **DatabaseSource** — *gained two fields:*
  - `warm_up` (Boolean, no default) — flag that opts a source into the `DatabaseWarmer` chain. Hosting providers that auto-pause idle databases (Azure SQL serverless) need a wake-up round-trip before the integration job starts; sources without auto-pause leave this `nil`. The bootstrap seeds `warm_up` from `ApplicationConfiguration.warm_up?` only when the field is `nil` (lets a deliberate `false` survive a re-run).
  - `max_connections` (Integer, no default) — sizes the per-source Sequel pool. `DatabaseSource#configuration` falls back to `ApplicationConfiguration.sql_pool_size` (`(sidekiq_threads * 1.2).ceil`) when the field is unset.

  `connect!` now caches one adapter per source via `DatabaseSource.adapters` (a class-level `Concurrent::Map`), with `compute_if_absent` for atomic insertion. The cached adapter wraps a `Sequel::Database` whose internal `ThreadedConnectionPool` is the only pooling layer. `disconnect!` on the adapter (added in this PR; replaces `close`) forcibly disconnects the Sequel pool — invoked at process shutdown.

- **Connector — REMOVED** *(unchanged from v2).*
- **Header — REMOVED** *(unchanged from v2).*

### Source data access — *(REWRITTEN)*

The pre-PR-#2174 stack carried two pools: an external `ConnectionPool` (gem) of N adapters, with each adapter wrapping a `Sequel::Database` that *also* exposed an internal pool. Removed.

The current model is one adapter per source — cached at the class level on `DatabaseSource` — wrapping a `Sequel::Database` with a single pool sized by `max_connections`. Workers obtain the adapter via `stream.source.connect!`; query methods on the adapter (`fetch`, `insert`, `page`, `count`, etc.) delegate to the Sequel database, which acquires a connection from its internal pool, executes, and releases it back synchronously. Workers do **not** call `close` or `disconnect` — the Sequel pool checkin is implicit. The adapter is alive for the lifetime of the process and reused across jobs and threads. Connection breakage during a job propagates as `Sequel::DatabaseDisconnectError` / `Sequel::DatabaseConnectionError`; Sidekiq retry handles transient cases. At process shutdown, `at_exit` walks `DatabaseSource.adapters` and calls `disconnect!` on each, draining the Sequel pools cleanly.

The Liquid-rendered query path — `Stream#render_query(variables)` rendered before reaching the adapter — is unchanged from v2.

### Identifier handling at Load time — *(unchanged from v2).*

`Source#user_id_from(id)` is the single entrypoint; two modes (normalized → `4sk_{id}`, otherwise pass-through). PR #2174 did not touch this layer.

### Pre-flight checks — *(unchanged from v2).*

`SourceCheck` + `StreamCheck` + `AvailabilityCheck` workers; `Stream#ready_for?(job)` gating. PR #2174 did not touch this layer.

### Per-job collection model — *(unchanged from v2).*

### Resource model — *(unchanged from v2).*

### Audit trail — *(unchanged from v2).*

### Stream sequence — *(EDITED — for accuracy)*

The 25-stream fixed sequence is unchanged. Four entries gained `fetch_since_column: 'created_at'` in `NORMALIZED_SCHEMA`: Hierarchy, Groupification, UserField, UserActivity. ParentUpdate had it already. The remaining 19 entries default to `'updated_at'` via `Stream`'s field default. The reason for the asymmetry is domain — the four `created_at`-keyed streams record append-only events (a hierarchy promotion, a groupification entry, a user-field assignment, a user activation/deactivation) whose business identity is "when this happened", not "when the row was last edited"; the legacy extractors were written that way, and the stream-driven pipeline now matches. This is now the correct configuration; before PR #2174, the bootstrap was creating the four streams with the wrong column.

### Worker shape — *(EDITED)*

The worker class names dropped the `Managed` prefix across the board. The shape that v2 documented — `*::ExtractorProducer`, `*::DatabaseExtractorConsumer`, `*::ApiExtractorConsumer`, `*::TransformerProducer`, `*::TransformerConsumer`, `*::LoaderProducer`, `*::LoaderConsumer` — is the live shape. The pre-PR-#2120 parallel chain (`*::DatabaseExtractor`, `*::DatabaseTransformerProducer`, `*::DatabaseTransformerConsumer`) was orphaned by the unification and is now deleted (42 files).

The 8 `*::TransformerConsumer` workers that operate on User-bearing resources (Hierarchy, UserIdentifier, Groupification, UserField, UserActivity, Deal, Modifier, Goal) carry an `if stream.source.normalized?` branch that opens `connection = stream.source.connect!` and runs the `users` (and `parent`, when applicable) JOIN before saving the import. This logic moved here from the deleted legacy `*::DatabaseTransformerConsumer` workers, where it lived per record. Domain intent: a normalized-DB record references its user by a foreign-key id; the API consumer downstream wants the resolved user document to apply policy decisions, so the integrator denormalizes at transform time. The 10 `User::*::TransformerConsumer` workers already carried the parent JOIN before this PR — what changed there was only the prefix.

### Per-client configuration is data, not code — *(unchanged from v2).*

The 14 `*::DatabaseExtractor` files that v2 listed as dead-code candidates ("would be the one-source-of-truth in a single-flow world") were confirmed orphaned and deleted in PR #2174.

## Cross-cutting findings (vs v2 and vs v1)

1. **The "managed flow" is gone, full stop.** v2 wrote that the worker prefix was a "legacy artifact"; v3 records that the artifact is gone. `Integrator.fully_normalized?` is the only flag that distinguishes a fully-bootstrapped client from a hybrid one, and only two callers consult it (the report mailer view and now nothing else — the encryption initializer became unconditional).
2. **The configuration surface is one layer.** `ApplicationConfiguration` is the env-var bridge (used by the bootstrap, by Sidekiq, by Mongoid, by Symmetric Encryption); `DatabaseSource` is the per-source configuration (used by `connect!`, by every worker that opens a connection). v2 still showed `ApplicationConfiguration.connection_params` as a code path; v3 has it deleted.
3. **The pooling story is one layer.** Sequel's `ThreadedConnectionPool` does the work; the integrator does not stack a second pool on top. The "connection_pool gem" episode (Oct 2025) was a misdiagnosis — Sequel pool was already configured but the adapter was being re-instantiated per call, so the underlying issue was missing caching, not missing pooling. The current design (cache + Sequel pool) is the correct shape from first principles.
4. **The transform stage now denormalizes for normalized DBs.** Pre-PR-#2120 the per-record DB transformer denormalized inline. v2's interpretation (the unified pipeline lost the JOIN) was wrong on a technicality — the JOIN existed in the legacy `*::DatabaseTransformerConsumer` workers that v2 had labelled "dead code candidates"; PR #2174 deleted those workers but ported the JOIN into the live `*::TransformerConsumer` first.
5. **Bootstrap parity.** Four streams (Hierarchy, Groupification, UserField, UserActivity) now extract by `created_at`, matching the legacy behavior. v2 did not catch this drift; PR #2174 fixed it by inspection during the pre-merge review.

## Implications for the documentation plan

The v2 13-chapter outline survives. **Caps 1, 2, 4, 7, 9, 10, 11, 13 are unchanged from v2's intent.** Caps 3, 5, 6, 8, 12 need the v3 details to be accurate. The chapter-level revision flags below replace the ones in v2:

1. **What the integrator is and why it exists** — *(unchanged from v2 outline).*
2. **Topology and isolation** — *(unchanged from v2 outline).*
3. **The unified integration pipeline** — *(REWRITE on top of v2's rewrite)* — drop the "the worker class names retain the `Managed` prefix as a legacy artifact" line; the prefix is gone. State plainly: one Job, three stages (E → T → L), one set of workers per resource, no parallel chain.
4. **The 25-stream fixed sequence and the role of ResourceType** — *(unchanged from v2 outline)*; mention that 4 of the 25 streams extract by `created_at` and the rest by `updated_at`, with the domain reason in one line each.
5. **Sources and Streams** — *(EDITED on top of v2's rewrite)* — add `warm_up` and `max_connections` to the DatabaseSource description; add the `Source.adapters` cache as the runtime side of `connect!`; keep the v2 framing of Source/Stream as the configuration surface.
6. **Source data access** — *(REWRITE on top of v2's light edit)* — describe one pool (Sequel internal), one adapter per source cached at class level, no `connection.close` on the worker side, `at_exit` cleanup. Frame the historical context briefly: the integrator used to stack two pools; the redundant outer layer was removed in PR #2174 once the internal Sequel pool was understood.
7. **Identifier handling on records** — *(unchanged from v2 outline).*
8. **AttributeMapping and the transformer pipeline** — *(EDITED on top of v2's light edit)* — add the normalized-branch JOIN as a domain step ("denormalize user/parent before save") in the transformer chapter, since it is part of the transform stage even though it sits in `TransformerConsumer` rather than in a Transformer subclass. List the 8 resources that participate.
9. **Mongoid storage of resources, imports, and requests** — *(unchanged from v2 outline).*
10. **Multi-stream coordination via Computation** — *(unchanged from v2 outline).*
11. **Pre-flight: SourceCheck, StreamCheck, AvailabilityCheck** — *(unchanged from v2 outline).*
12. **The normalized database contract and the bootstrap task** — *(EDITED on top of v2's rewrite)* — add `warm_up` and `max_connections` as fields the bootstrap seeds; mention the four `created_at` streams; describe `DatabaseWarmer::Producer/Consumer` as the warm-up chain that runs before `Job::Starter` when any source has `warm_up=true`.
13. **Resource integration_status lifecycle** — *(unchanged from v2 outline).*

## Findings

### Header model — *(unchanged from v2)*

### `ApplicationConfiguration.managed_integration?` — REMOVED

The flag and its siblings (`self_service_integration?`, `api_integration?`, `database_integration?`, `integration_mode`) were deleted in PR #2174 along with the `INTEGRATION_MODE` env var. The replacement is `Integrator.fully_normalized?` in `lib/integrator.rb`:

```ruby
def self.fully_normalized?
  Source.size == 1 && Source.normalized.size == 1
end
```

(`Source.one?` is not defined on Mongoid criteria, hence `.size == 1`. The two clauses are equivalent in practice — the partial unique index ensures at most one Source carries `normalized=true` — but writing both makes the intent explicit and survives a hypothetical change to the index.)

The view branch in `integration_report_mailer/create.html.erb` and the symmetric encryption initializer (now unconditional in production) are the two callers. v2 scheduled this as a separate PR; v3 records it as done.

### `IdentifierPrefixerTransformer` — *(unchanged from v2)*

### User::Unknown — *(unchanged from v2; structural and unconditional)*

### `Database` global model and `DatabaseConnectionMiddleware` — REMOVED

`app/models/database.rb` and `app/middlewares/database_connection_middleware.rb` are deleted. The `def connection` helper on `ApplicationWorker` (which read `Thread.current[:database_connection]` populated by the middleware) is gone. No worker reads from a thread-local connection anymore — every worker that needs a database adapter calls `stream.source.connect!` (or `Source.normalized.first.connect!` for the few non-stream consumers: `ThroughputCalculator`, `db:sql` rake task, `Job::Starter`'s version probe).

### `DatabaseWarmer` — Producer/Consumer pair

The pre-PR-#2174 single worker (`app/workers/database_warmer.rb`) is deleted. The new pair lives at `app/workers/database_warmer/{producer,consumer}.rb`. The Consumer's reschedule path uses `Sidekiq::Client.push` with an explicit `retry_count` in the payload (read by `SidekiqRetryCountMiddleware`) — `perform_in` would have lost the counter and made `UnreachableDatabaseException` unreachable.

### `connection_pool` gem usage — REMOVED

The gem stays present as a transitive dependency (Sidekiq + Mongoid pull it in). The integrator's own use of it is deleted — the `Database.connection_pool` global, the `database_pool.rb` initializer's `ConnectionPool.new`, the `DatabaseSource::Connection` wrapper that briefly existed during the PR review iteration. Sequel's internal pool is the only pooling layer.

### Database adapter console syntax — *(unchanged from v2 — done in PR #2174)*

`README.md §2.5.1` was updated in PR #2174 to use `connection.fetch(:table_name, id: 34)` and to drop the older string-form filter.

### Other findings (no correction required)

- *(carried over from v2)*: `resource_inclusion` validation; `paginated_query_template` optional; `User#model_version = '3.0'` predates these PRs.
- **Re-running the bootstrap is safe across PR #2174.** The bootstrap is idempotent (`find_or_initialize_by` per stream); existing clients on `develop` will pick up the four new `fetch_since_column: 'created_at'` entries on next bootstrap run, and the `warm_up` / `max_connections` fields will land as `nil` (the bootstrap seeds them only when env vars are set).

## Diff against v2 — quick reference

| v2 claim | v3 status |
|---|---|
| `Managed*` prefix is a legacy artifact in worker class names | **Prefix removed; class names are clean.** |
| `ApplicationConfiguration.managed_integration?` is "scheduled for removal" | **Removed.** |
| `INTEGRATION_MODE` env var | **Removed.** |
| Symmetric encryption initializer "becomes unconditional" | **Done.** Raises in production if keys are missing. |
| `Database` global wrapper class | **Deleted.** No global adapter; one adapter cached per source on `DatabaseSource.adapters`. |
| `DatabaseConnectionMiddleware` populates `Thread.current[:database_connection]` | **Deleted.** No worker reads from Thread.current. |
| `def connection` on ApplicationWorker | **Removed.** |
| External `ConnectionPool` of N adapters per global pool | **Removed.** Sequel's internal `ThreadedConnectionPool` is the single pooling layer. |
| `DatabaseSource` carries `adapter`, `host`, `port`, `database_name`, `azure`, `table_prefix`, `timeout` | **Adds `warm_up` and `max_connections`.** |
| `ApplicationConfiguration.connection_params` is a runtime helper | **Deleted.** Connection params now built per-source in `DatabaseSource#configuration`. |
| 14 `<Resource>::DatabaseExtractor` workers exist | **Deleted (orphaned by the unification).** |
| 14 `<Resource>::DatabaseTransformerProducer` workers exist | **Deleted (orphaned).** |
| 14 `<Resource>::DatabaseTransformerConsumer` workers exist (with users/parents JOIN) | **Deleted; JOIN ported into the live `<Resource>::TransformerConsumer` `if stream.source.normalized?` branch in 8 resources.** |
| `HealthCheck::Processor`, `ConnectionCheck::Processor`, `*_report/{producer,consumer}`, mailer + view + locales (legacy reporting chain) | **Deleted.** |
| `DatabaseWarmer` is a single worker class | **Now a Producer/Consumer pair under `app/workers/database_warmer/`.** |
| README §2.5.1 uses outdated `"where id=34"` string-form filter | **Updated to keyword-arg syntax.** |
| `NORMALIZED_SCHEMA` declares `fetch_since_column` only on `ParentUpdate` | **Now declares it on Hierarchy, ParentUpdate, Groupification, UserField, UserActivity (5 entries).** Restores legacy `created_at` filtering for the four append-only streams. |
| `ManagedIntegrator` is the entrypoint | **Renamed to `Job::Starter`.** Same role. |

v3 supersedes v2 for D3 drafting from here on. v2 stays as the historical record of the post-#2120 / pre-#2174 state. v1 stays as the historical record of the pre-#2120 state.
