# Auxiliary — Integrator worker → queue → stage map

Source: `grep -rn "sidekiq_options queue:" ~/Projects/4Shark/integrator/app/workers/` (387 matches, one per worker class), read in full and deduplicated by shape. Referenced from `SPIKE.md` Finding 1 and Finding 8.

## The repeating per-resource-type pattern

Every one of the 25 streams (`Subsidiary`, `Hierarchy`, `User::Admin`, `User::President`, `User::VicePresident`, `User::Director`, `User::Superintendent`, `User::GeneralManager`, `User::Manager`, `User::Coordinator`, `User::Supervisor`, `User::SalesRepresentative`, `User::Unknown`, `ParentUpdate`, `UserIdentifier`, `Client`, `Product`, `Group`, `Groupification`, `UserField`, `UserActivity`, `Deal`, `DealExtraField`, `Modifier`, `Goal`) declares the same worker-class shape, only the resource namespace changes. Confirmed identical across `Client`, `Deal`, `DealExtraField`, `Goal`, `Group`, `Groupification`, `Hierarchy`, `Modifier`, `ParentUpdate`, `Product`, `Subsidiary`, `UserActivity`, `UserField`, `UserIdentifier`, `User::Admin`, `User::Coordinator`, `User::Director`, `User::GeneralManager`, `User::Manager`, `User::President`, `User::SalesRepresentative`, `User::Superintendent`, `User::Supervisor`, `User::Unknown`, `User::VicePresident` (25 namespaces).

| Worker (per `<Resource>::`) | Queue | Stage |
|---|---|---|
| `CollectionExtractorProducer` | `database_extractor` | Extract |
| `ApiCollectionExtractorConsumer` | `database_extractor` | Extract |
| `DatabaseCollectionExtractorConsumer` | `database_extractor` | Extract |
| `EnrichmentExtractorProducer` | `database_extractor` | Extract |
| `ApiEnrichmentExtractorConsumer` | `database_extractor` | Extract |
| `DatabaseEnrichmentExtractorConsumer` | `database_extractor` | Extract |
| `TransformerProducer` | `database_transformer` | Transform |
| `TransformerConsumer` | `database_transformer` | Transform |
| `NormalizedCollectionConsumer` | `database_transformer` | Transform |
| `CustomCollectionConsumer` | `database_transformer` | Transform |
| `EnricherProducer` | `database_transformer` | Transform |
| `EnricherConsumer` | `database_transformer` | Transform |
| `LoaderProducer` | `api_loader_producer` | Load |
| `LoaderConsumer` | `api_loader_consumer` | Load |

`UserField` and `UserIdentifier` additionally split `LoaderConsumer`/`LoaderProducer` into `CreateLoaderConsumer`/`CreateLoaderProducer` and `DeleteLoaderConsumer`/`DeleteLoaderProducer` (and `UserIdentifier` adds `PrimaryLoaderConsumer`/`PrimaryLoaderProducer`) — same two queues (`api_loader_producer` / `api_loader_consumer`), just more entry points into the Load stage for that one resource.

## Ancillary (non-stream) workers

| Worker | Queue | When it runs |
|---|---|---|
| `Job::Starter` | (no `sidekiq_options`, default queue) | Cron entry point — creates the `Job` record |
| `HealthCheck::Producer`/`Consumer`/`Finalizer` | `checkup` | Immediately after `Job::Starter`, before any stream |
| `Authorization::Producer`/`ApiConsumer`/`DatabaseConsumer`/`Finalizer` | `authorization` | After `HealthCheck`, before any stream |
| `AvailabilityCheck::Producer`/`ApiConsumer`/`DatabaseConsumer`/`Finalizer` | `checkup` | After `Authorization`, before any stream |
| `ThroughputProcessor` | `authorization` | After `AvailabilityCheck`; hands off to `Subsidiary::CollectionExtractorProducer` (Extract stage, stream 1) unless throughput exceeds ceiling |
| `HighThroughputReport::Producer`/`Consumer` | `report` | Only when `ThroughputProcessor` finds the job's throughput above `job.metric.ceiling` — replaces the normal Extract-stage start |
| `SourceCheckReport::Producer`/`Consumer` | `report` | Only on a DB connection failure inside `Job::Starter`'s rescue |
| `MissingStreamsReport::Producer`/`Consumer` | `report` | Only when `Stream.count == 0` |
| `InactiveStreamsReport::Producer`/`Consumer` | `report` | Only when `Stream.enabled.count == 0` |
| `StreamCheckReport::Producer`/`Consumer` | `report` | Only when `AvailabilityCheck::Finalizer` finds unsuccessful stream checks |
| `IntegrationReport::Producer`/`Consumer` | `report` | Fired by `Job::Finisher`, i.e. strictly AFTER the Load stage's last stream (`Goal::LoaderConsumer`) completes — the normal end-of-run report/email |
| `Resource::Producer`/`Consumer` | `cold_storage` | Fired by `IntegrationReport::Consumer` after the mail send and after `job.computation.release_lock` — strictly after Load + report |
| `Job::Finisher` | (no `sidekiq_options`, default queue) | Closes the `Job` record, then fires `IntegrationReport::Producer` |
| `Job::Migration::Producer`/`Consumer`, `JobMetric::Migration::Producer`/`Consumer` | `migration` | Deploy-time data migrations (see `integrator/CLAUDE.md` § Normalized Database Schema Lifecycle) — unrelated to the per-run pipeline |

## `config/sidekiq.yml` queue list (source: `~/Projects/4Shark/integrator/config/sidekiq.yml`)

```
concurrency: <%= ApplicationConfiguration.sidekiq_threads %>
:queues:
  - [api_extractor, 1]
  - [api_loader_producer, 10]
  - [api_loader_consumer, 1]
  - [authorization, 1]
  - [checkup, 1]
  - [cold_storage, 1]
  - [database_extractor, 1]
  - [database_transformer, 1]
  - [default, 1]
  - [migration, 1]
  - [report, 1]
```

`api_extractor` is declared here with weight 1 but **no worker class in `app/workers/` sets `sidekiq_options queue: :api_extractor`** (confirmed by a repo-wide grep) — it is a dead queue entry in this config file today.

## Verified pipeline chain (stage boundaries)

Traced by reading the actual `perform_async` call at the tail of each worker, not inferred:

```
Job::Starter
  → HealthCheck::Producer → HealthCheck::Consumer(N) → HealthCheck::Finalizer
  → Authorization::Producer → Authorization::{Api,Database}Consumer(N) → Authorization::Finalizer
  → AvailabilityCheck::Producer → AvailabilityCheck::{Api,Database}Consumer(N) → AvailabilityCheck::Finalizer
  → ThroughputProcessor
  → Subsidiary::CollectionExtractorProducer            [EXTRACT stage, stream 1 of 25]
  → ... (all 25 streams, Extract stage, in CLAUDE.md's fixed order) ...
  → Goal::{Api,Database}EnrichmentExtractorConsumer     [EXTRACT stage, stream 25 — LAST]
  → Subsidiary::TransformerProducer                     [TRANSFORM stage, stream 1 of 25]
  → ... (all 25 streams, Transform stage) ...
  → Goal::TransformerConsumer → Goal::EnricherProducer → Goal::EnricherConsumer  [TRANSFORM stage, stream 25 — LAST]
  → Subsidiary::LoaderProducer                          [LOAD stage, stream 1 of 25]
  → ... (all 25 streams, Load stage) ...
  → Goal::LoaderConsumer                                [LOAD stage, stream 25 — LAST]
  → Job::Finisher
  → IntegrationReport::Producer → IntegrationReport::Consumer (mail send + job.computation.release_lock)
  → Resource::Producer → Resource::Consumer(N)          [cold_storage archival]
```

Each `→` above was confirmed by reading the calling worker's `perform` method and finding the literal `SomeClass.perform_async(...)` call at its `computation.done?` branch — not assumed from the stream-order list in `CLAUDE.md` alone.
