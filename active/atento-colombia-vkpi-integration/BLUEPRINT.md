# BLUEPRINT — Building the Colombia VKPI indicator integration

## Objective

Deliver the VKPI indicators as a second, non-normalized source on the existing Atento Colombia integrator, feeding a `Modifier` stream, starting 2026-09-17. This document answers three questions the effort estimate turns on: what has to be **built**, what is only **configured**, and what has to be **proven** because it has never run.

Scope premise: Atento applies the agreed structure — the `llave` column on `tb_dim_indicadores` (unique, not null) and the score-table changes already proposed. `PLAN.md` in this folder holds the agreement and the gate; this document holds the construction.

Language classification: internal engineering doc → English (`LANGUAGE-POLICY.md`, category 1).

## The headline: almost nothing is code

The integration's whole contract with the platform is four fields:

```ruby
# app/models/modifier.rb:6-15
def request_body_for(import)
  {
    indicator: {
      compiled_at: import.data[:compiled_at],
      user_id: import.stream.source.user_id_from(import.data[:user_id]),
      value: import.data[:value],
      variable: import.data[:variable]
    }
  }.to_json
end
```

Everything upstream of that — reading the VKPI table, shaping each row into those four keys — is expressed in two Mongoid documents, not in Ruby. `Stream` carries the SQL as a Liquid template (`app/models/stream.rb:23`, `:74-78`) and the field-by-field shaping as embedded `AttributeMapping` documents, whose four kinds cover every transformation this integration needs:

```ruby
# app/models/attribute_mapping.rb:8,19
KINDS = %w[dynamic fixed formula template].freeze
...
enumerize :kind, in: { dynamic: 0, fixed: 1, template: 2, formula: 3 }, default: :dynamic
```

`dynamic` reads a column from the row, `fixed` writes a constant, `template` renders Liquid over the already-mapped attributes, `formula` evaluates Dentaku over them, and any of the four may pass its result through a `transformer`.

## The configuration, in full

### The source

One `DatabaseSource` — `adapter: 'microsoft_sql_server'`, the VKPI host, port and database, `normalized: false`, `resources: ['Modifier']`, `timezone: 'America/Bogota'`, plus its `authentication`.

Two model-level facts make this shape the intended one rather than a workaround. `Source` carries a unique index on `normalized: true` (`app/models/source.rb:31`), so a second source **must** be non-normalized — the schema encodes "one normalized base, N others". And `user_resource_uniqueness` (`:55-63`) reserves the `User` resource for a single source; this one carries only `Modifier`, so it does not collide with the normalized source that owns users.

### The stream

One `Stream` on the `Modifier` resource type, carrying the query and the mapping.

**The query** joins the score table to the catalogue so that the 4Shark variable key travels with the value: `score.NR_INDICADOR = catalogue.NR_ID`, selecting `llave` as a column. The incremental predicate is written against `DT_MODIFIED` using the Liquid vocabulary `Variables#to_h` exposes (`app/models/variables.rb:13-47`) — `fetch_since` and `starts_at`, both rendered `'%Y-%m-%d %H:%M:%S'` in the source's own timezone.

**The five mappings** produce exactly what the payload and the transformer need:

| Target | Kind | Source | Note |
|---|---|---|---|
| `user_id` | dynamic | `NR_RE` | The Simplex code. `user_id_from` returns it unprefixed for a non-normalized source (`app/models/source.rb:41-47`), which is why it must match what the platform already holds |
| `value` | dynamic | `RESULTADO` | The final figure. `HC` / `HC_Total` are informational and are not read |
| `variable` | dynamic | `llave` | Carried in by the catalogue join |
| `compiled_at` | dynamic | `DT_DATA` | Delivered `yyyymmdd`; `BeginningOfMonthTransformer` (`app/transformers/beginning_of_month_transformer.rb:4-8`) calls `value.to_date`, which parses that form |
| `external_id` | template | composite | Period + person + programa + indicator — the agreed unique key. Consumed at `app/workers/modifier/transformer_consumer.rb:61`, `Modifier.get(attributes['external_id'])` |

Exactly one mapping carries `primary: true`; the model rejects any other count (`app/models/stream.rb:106-114`).

**The availability probe** is the piece worth deliberately not skipping. A non-normalized source gets **no** authorization check at all:

```ruby
# app/workers/authorization/database_consumer.rb:12-37
if source.normalized?
  connection = source.connect!
  missing_permissions = connection.permissions.missing
  ...
else
  source_check.update(authentication: :skipped)
end
```

That branch is correct — `Permissions#missing` demands SELECT on the fifteen normalized-base tables, none of which exist on the VKPI server — but it means a wrong credential or a missing grant surfaces only when the extract query runs. `Stream#availability_probe` is the substitute, and it is a SQL string rather than code: `AvailabilityCheck::DatabaseConsumer` runs it and marks the stream check passed or failed before the job proceeds (`app/workers/availability_check/database_consumer.rb:11-15`).

## What actually has to be built or proven

**Nothing in the happy path is new code.** The producer already routes each stream by its own source's type (`app/workers/modifier/extractor_producer.rb:23-33`), so several `Modifier` streams from different databases coexist by construction; the transformer's non-normalized branch (`transformer_consumer.rb:31-67`) is the one every `ApiSource` in production already exercises. What has never run is the **pairing** of a database source with that branch — the extract half.

Four items carry the real work:

**1. The extract path, first run.** `Modifier::DatabaseExtractorConsumer` rendering a Liquid template against a customer schema and writing a raw collection is untested in production. This is where small fixes land, and it is one worker rather than a pipeline — which is what bounds the risk.

**2. Pagination.** The consumer walks by keyset:

```ruby
# app/workers/modifier/database_extractor_consumer.rb:31-37
if stream.paginated?
  collection_last_id = raw_collection.last[stream.primary_key.to_sym]
  Modifier::DatabaseExtractorConsumer.perform_async(job_id, stream_id, collection_last_id)
else
  job.computation.increment_executions
  Goal::ExtractorProducer.perform_async(job_id) if job.computation.done?
end
```

`Stream#primary_key` defaults to `'id'`, and the walk is correct only against a unique, ordered column. The agreed row identity is the composite period + person + programa + indicator, with no surrogate key named anywhere. Either the stream runs unpaginated — one query per run, viable at this volume but holding a connection and a JSON blob — or Atento adds an identity column. **This has not been raised with them.**

**3. The historical backload, and the reload that precedes it.** The structure script leaves the score table empty, so how much history exists at all is Atento's decision when they repopulate — a fact to obtain from them rather than measure here. Whatever they load, `Modifier::LoaderConsumer` then pushes one API request per record (`app/workers/modifier/loader_consumer.rb:15,23`), so the first run's window is that row count times one request. A first run bounded to the current period, with history loaded afterwards in controlled batches, keeps the go-live short and is the recommended shape.

**4. Two connection pools in one task.** `DatabaseSource.adapters` is a `Concurrent::Map` keyed by source id (`app/models/database_source.rb:40,48-50`), so each source gets its own pool sized by `max_connections || ApplicationConfiguration.sql_pool_size`. Two pools against two servers from one ECS task has never run; the task's memory ceiling under that shape is unmeasured.

## Phases from 2026-09-17

**Phase 0 — pre-conditions, before any configuration.** Verify against the live database that the agreed changes landed, using the acceptance checks `PLAN.md` already specifies (the `llave` column present, unique, non-null; `RESULTADO` present and the numerator/denominator pair gone; `DT_CREATED` / `DT_MODIFIED` populated; zero score rows whose indicator is absent from the catalogue). In parallel, confirm the integrator's ECS tasks can reach the VKPI host — a server they have never touched, and the only item here with an unbounded upper end.

**Phase 1 — connectivity and configuration.** Create the source and the stream with the mapping table above, and set the availability probe. Ends when the probe passes on a real job.

**Phase 2 — extract.** First real run of the database + non-normalized extract. Ends when a raw collection is written with the expected row count for one period.

**Phase 3 — transform and load, end to end.** Ends when indicators land in the platform for a known set of people and reconcile against the source for one period.

**Phase 4 — historical backload.** Scope decided by the measurement from item 3 above; run in controlled batches.

**Phase 5 — release and daily running.** HubFlow release of the integrator, deploy per `INTEGRATORS` deployment key, then the stream on the daily schedule.

## Calendar and estimate

**Development runs Thursday 2026-09-17 to Thursday 2026-10-08 — three calendar weeks — and both dates are committed to Atento in the roadmap they hold.** The floor is well inside that window because the code work is close to zero: this is two documents and a SQL query, not a feature. What consumes the rest is the environment — getting `develop` green, rehearsing the normalized-customer migration on a homologation base, and releasing it to the other clients — which is roughly two thirds of the calendar and is not VKPI work at all.

**Two items can still move the ceiling, and neither can be sized yet**: whether the integrator's tasks reach `COLBOGSQL58`, and how many rows the first load carries.

**The 08-oct date assumes the base is in the script's structure by 17-sep.** Atento's own time to run the script and populate `llave` is excluded from the three weeks; each week of delay there moves delivery by the same amount, which is the term the roadmap states.

## Open items

- **The supervisor path has never been exercised against data.** `PLAN.md` records why one `llave` per catalogue row is sufficient — the per-operation split already lives inside `NR_ID`, so `calidad` in two operations is two catalogue records with two keys. The sample Atento delivered carries no supervisor rows, so that reasoning has not been confirmed against a real row. The first load including supervisors is the check.
- **A monotonic column for pagination** (item 2 above), also unraised.
- **Whether `DT_CREATED` / `DT_MODIFIED` will be populated for historical rows** or only for rows written after the change. An incremental read against a column that is null on existing rows returns nothing, silently.
