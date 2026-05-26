# The normalized database contract and the bootstrap task

For customers using the normalized integration path, the customer's commitment is to populate a fixed set of tables with their data. The integrator commits to reading those tables in a known shape, transforming the rows into 4Shark API payloads, and managing the lifecycle of the records on the platform side. This contract is one of the integrator's oldest features — it is how the project started and remains the most common path for new customers.

The bootstrap task is the operational binding between the contract and the per-customer configuration. Running it once per customer creates the entire stack of MongoDB documents the integrator needs to operate against the normalized schema.

## The schema

The normalized schema is a fixed set of tables (the names are documented in `docs/mssql-prefixed/` and `docs/postgres/` of the integrator repo, with the exact column shapes for each supported database). The customer's MIS team is responsible for populating these tables from whatever upstream systems they have — typically through ETL scripts or direct SQL extracts that already exist for internal reporting.

The 24 tables and views the integrator reads from are listed in `config/normalized_schema.rb` as a Ruby constant:

```ruby
NORMALIZED_SCHEMA = [
  { name: 'Subsidiary', resource: 'Subsidiary', table: 'subsidiaries' },
  { name: 'Hierarchy', resource: 'Hierarchy', table: 'hierarchy', fetch_since_column: 'created_at' },
  { name: 'Admin', resource: 'User', table: 'users', condition: "type = 'Admin'" },
  ...
  { name: 'Goal', resource: 'Goal', table: 'goals' }
].freeze
```

Each entry declares:

- **`name`** — the logical sequence step (becomes the ResourceType's `name`)
- **`resource`** — the underlying Resource subclass
- **`table`** — the source table to extract from (the bootstrap prepends the customer's `table_prefix`)
- **`condition`** — optional WHERE clause, used for the 10 user-level entries that filter the same `users` table by `type`
- **`fetch_since_column`** — optional override of the default `'updated_at'` filter column, used for 5 append-only entries (Hierarchy, ParentUpdate, Groupification, UserField, UserActivity)

The 25-entry stream sequence in Chapter 4 maps onto this schema with the addition of `User::Unknown` (which is structural, not configured — Chapter 4 covers why).

## The `table_prefix` decision

The schema names are agreed at onboarding but the actual table names in the customer's database carry a per-customer prefix — typically `'fsk_'` (e.g. `fsk_subsidiaries`, `fsk_users`). The prefix lets the customer host the integrator's tables in the same database as their own internal tables without name collisions. A customer who already has a `users` table for their own purposes can run the integrator's `fsk_users` alongside it.

The prefix is set once during onboarding and stored on the `DatabaseSource#table_prefix` field. The bootstrap task interpolates it into every Stream's `query_template` — the rendered SQL is a fully-formed `SELECT * FROM fsk_subsidiaries WHERE updated_at >= '{{ fetch_since }}' LIMIT {{ page_size }}`, with the prefix already in place.

The legacy default of `'fsk_'` no longer lives in the model — `DatabaseSource#table_prefix` has no field-level default. Bootstrap reads from `ApplicationConfiguration.table_prefix` (the env var the customer's deploy carries) and stamps the value onto the Source. This keeps the prefix decision out of the codebase and into the per-customer environment.

## What the bootstrap task creates

`rake integration:normalized:bootstrap` creates, in order:

1. **24 ResourceType documents** — one per `NORMALIZED_SCHEMA` entry. The same task is idempotent (`find_or_initialize_by(name:)`) — running it twice doesn't duplicate.
2. **One DatabaseSource document** — `find_or_initialize_by(normalized: true)`. Fields are populated from `ApplicationConfiguration` (host, port, database, adapter, table_prefix, timezone, max_connections), with `||=` so existing values from a partial previous bootstrap survive. `warm_up` is seeded `if source.warm_up.nil?` (so a deliberately-set `false` is not overwritten on re-runs).
3. **One DatabaseAuthentication document** — `find_or_initialize_by(source: source)`. Username and password from `ApplicationConfiguration`.
4. **One HealthCheck document** — `find_or_create_by(source: source)`. Default state.
5. **24 Stream documents** — one per ResourceType. For each Stream:
   - `disabled` set to `false` if currently `nil` (preserves explicit-disable across re-runs)
   - `name`, `primary_key`, `fetch_since_column`, `page_size` from the schema entry (with sensible defaults)
   - `query_template` rendered as `SELECT * FROM <prefix><table> WHERE <fetch_since_column> >= '{{ fetch_since }}' <condition?> ORDER BY id LIMIT {{ page_size }}`
   - `paginated_query_template` rendered as the same query plus `AND id > {{ previous_record_id }}`
   - `availability_probe` rendered as `SELECT 1 FROM <prefix><table> WHERE 1 = 0` — the no-data probe used by AvailabilityCheck

The full task fires once per customer per environment at onboarding time. The customer's MIS team's only direct interaction with the integrator's MongoDB is the bootstrap — after it runs, they go back to populating tables on their side and never log into the integrator again.

## Idempotency

Re-running the bootstrap on an existing customer is safe and intended. The use cases:

- **A new ResourceType is added to `NORMALIZED_SCHEMA`** — running the bootstrap creates the new ResourceType + its Stream on existing customers without disturbing the rest.
- **A `fetch_since_column` correction** — the four `created_at` overrides for Hierarchy, Groupification, UserField, UserActivity were added in PR #2174 to match legacy behavior the post-#2120 pipeline had silently lost. Existing customers picked up the corrected column on their next bootstrap re-run.
- **A query template adjustment** — if the bootstrap-generated SQL needs a tweak (a new condition, a different ORDER BY), updating the bootstrap and re-running rolls it out to every existing customer that still uses the bootstrap-generated template.

The idempotency is built on `find_or_initialize_by` everywhere; only fields that should be re-seeded on every run are reassigned, and fields that may have been hand-edited (a customer with a custom `query_template` for one Stream) are preserved. The exception is `query_template` and `paginated_query_template` themselves — the bootstrap re-generates these unconditionally, on the assumption that hand-edits to bootstrap-generated templates are a code smell. If a customer truly needs a divergent template, the right path is a custom Source instead of a fork of the normalized one.

## What the bootstrap does **not** create

- **`DatabaseWarmer` configuration** — the `warm_up` field on the Source is seeded from env, but the actual scheduling of `DatabaseWarmer::Producer` ahead of `Job::Starter` lives in the integration cron task, not in the bootstrap.
- **Cron schedule** — when and how often the integration runs is configured in the customer's deploy via `ApplicationConfiguration` and the `integration:cron` rake task. The bootstrap is silent on scheduling.
- **API credentials** — the integrator's credentials for the 4Shark API are deploy-level configuration (env vars, secrets), not Source documents.
- **Sensitive keys masking** — there is no entry per Stream in the bootstrap output. Sensitive keys are configured per-customer based on a security review of the customer's data shape, after the bootstrap. (For most normalized customers, the MIS team writes the data with sensitive fields already separated into specific columns the integrator can mask; for others, the security review identifies which columns of which tables need masking and the SensitiveKey embedded list is added to the Stream.)

## The cron entrypoint

The `integration:cron` task is the wrapper that the deploy schedules. It checks whether any `DatabaseSource.where(warm_up: true)` exists; if yes, dispatches `DatabaseWarmer::Producer.perform_async` (which fans out to one Consumer per warm-up Source); if no, dispatches `Job::Starter.perform_async` directly.

This shape lets the warm-up step be optional per Source and free of operational overhead when no Source needs it. A customer on always-on infrastructure has zero warm-up overhead; a customer on Azure SQL serverless has one extra round-trip per Source per Job, which is exactly enough to wake the auto-paused database.

## The `DatabaseWarmer` chain

For customers with `warm_up: true` Sources, the chain is:

1. **`DatabaseWarmer::Producer`** — picks up the schedule kick. Plucks `DatabaseSource.where(warm_up: true).pluck(:id)`. If the result is empty, fires `Job::Starter` directly. Otherwise, resets a Computation counter, increments by the number of warm-up Sources, and bulk-pushes one Consumer per Source.
2. **`DatabaseWarmer::Consumer`** — runs once per Source. Calls `source.connect!.database_version` — a real round-trip that wakes an auto-paused database (the connection alone is not enough; some hosting providers only wake on a query). Increments the Computation counter; the last one to acknowledge fires `Job::Starter`.

The Consumer carries a retry policy: connection errors during warm-up are expected (Azure SQL serverless takes seconds to wake), so they trigger a 5-minute reschedule rather than a hard failure. The retry counter propagates through the Sidekiq job payload (via `Sidekiq::Client.push` with `retry_count` set explicitly, read by `SidekiqRetryCountMiddleware`) so that sustained failure (more than 2 retries) raises `UnreachableDatabaseException` and surfaces the source as truly unreachable.

The pre-#2174 codebase had a single `DatabaseWarmer` worker class that combined both phases. PR #2174 split it into the Producer/Consumer pair to support multiple warm-up Sources independently — a hybrid customer with two normalized Sources, both on auto-pause infra, would have needed serial warm-up under the old shape; the new shape parallelizes.

## Why the schema is fixed (and why that's right)

A customer might ask "can we add a custom column to the normalized schema?". The answer is no — the schema is fixed across all normalized customers. Changes to the schema require a code change to `NORMALIZED_SCHEMA` plus a coordinated re-bootstrap of every customer using the schema. This is intentional:

- **The fixed shape is what makes the bootstrap one task, not 50 per-customer tasks.** A normalized customer's onboarding is "configure the env, run the bootstrap, populate the tables" — three steps that take an afternoon. A per-customer schema would push the integration design back into the customer's lap, which is exactly what the persona cannot do (Chapter 1).
- **Custom needs go through a custom Source.** A customer who needs to integrate a column or a table outside the normalized schema can add a custom-shaped Stream alongside the normalized Source — same integrator, different Source. The normalized contract is the default; the custom path is the escape hatch.

Schema changes have happened — they happen as new ResourceTypes get added (ParentUpdate was a relatively recent addition) or new columns get added to existing tables. The change is rolled out across all normalized customers via a coordinated re-bootstrap, with the customer's MIS team alerted to populate the new column in their next ETL run.

## Schema versioning across customers

The `versions` table in the normalized schema records the version of the schema currently deployed at the customer. The integrator reads it via `connection.integration_version` and stamps the value onto the Job document — so every Job carries a record of which schema version produced its data. This lets 4Shark trace backward from "this data looks wrong" to "the customer's MIS team has not migrated their schema to the version we expect".

The integrator tolerates schema-version drift across customers — different customers can run different schema versions concurrently, as long as each customer's Streams match their installed version. The bootstrap-generated `query_template`s assume the latest schema; customers behind a version may need to manually adjust the templates until they catch up.

## Summary

The normalized contract is a fixed schema (24 logical streams + the structural User::Unknown), bootstrapped once per customer via an idempotent rake task that creates ResourceTypes + Source + Authentication + HealthCheck + Streams. The customer's MIS team populates the schema; the integrator reads it. The DatabaseWarmer chain is optional, opt-in per Source, and exists to support hosting providers that auto-pause idle databases. Schema changes roll out across all normalized customers via coordinated re-bootstrap; customer-specific divergences live in custom Sources, not in modifications to the normalized one.
