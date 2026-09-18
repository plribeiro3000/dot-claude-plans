# Integrator 3-run performance study — windows and data sources

## The three runs (all times UTC)

Windows pinned from New Relic `Transaction` min/max timestamps on app `Integrator Atento CO (Staging)` (account 1469332); the New Relic envelope is slightly wider than the Job's own reported total because it includes warmup and the cold-storage/shutdown tail.

| Run | Config | Start (UTC) | End (UTC) | NR envelope | Job total | NR txns |
|---|---|---|---|---|---|---|
| Run 1 | 30 threads × 1 task (0.5 vCPU) | 2026-09-16 19:13:44 | 2026-09-16 21:05:56 | 112.2 min | 1 h 48 min 18 s | 43,979 |
| Run 2 | 30 threads × 1 task (0.5 vCPU) | 2026-09-16 21:40:01 | 2026-09-16 23:29:25 | 109.4 min | ~1 h 47 min | 48,641 |
| Run 3 | 10 threads × 3 tasks (0.5 vCPU each) | 2026-09-17 01:44:01 | 2026-09-17 02:30:50 | 46.8 min | 45 min 38 s | 52,424 |

Run 1 rejected every send with a fast HTTP 400 (subsidiary-mode mismatch); Run 2 did the real 2xx load on the same infrastructure; Run 3 moved two levers at once (10 vs 30 threads AND 3 vs 1 task). The per-run query windows for every source below are these exact UTC start/end.

## What each source actually holds (verified 2026-09-17)

**New Relic (APM) — the primary source, rich.** App `Integrator Atento CO (Staging)`, account 1469332. Per-transaction data for every worker class: count, duration percentiles, and the self-time split into Ruby/CPU vs `databaseDuration` (Mongo) vs `externalDuration` (S3/HTTP). Queried via NerdGraph NRQL with a User API key (`op://Employee/Terraform ENV/NEW_RELIC_KEY`, fetched at runtime, never printed).

**CloudWatch — infrastructure metrics.** ECS service `integrator-atento-co-staging-worker-service` (cluster `integrator-atento-co-staging-cluster`, sa-east-1): `CPUUtilization` / `MemoryUtilization`. ElastiCache `integrator-atento-redis001-001`: `EngineCPUUtilization` / `CPUUtilization` / `CurrConnections`.

**CloudWatch Logs — Sidekiq logs.** Log group `/ecs/integrator-atento-co-staging-worker` (also `-web`, `-runner`). The worker task ships stdout via the awslogs driver, so the Sidekiq output is here, not in Datadog.

**Datadog — effectively empty for these runs.** The integrator emits exactly one custom metric, `integrator.process.count`, incremented once per run start in `Job::Starter` via `DataDog.increment` → `Dogapi::Client.emit_point` (`app/workers/metric_incrementor.rb`, tag `client_name`). It is a run-start marker, not throughput or resource data. Queried over the study window it returns **no datapoints** for the three runs. There is no Datadog agent sidecar on the worker task and no `ddtrace`, so no ECS CPU/mem and no APM traces reach Datadog for the integrator worker — a metric-name search returns only `integrator.process.count`, and a tag search for the integrator cluster/service matches nothing. The APM instrumentation is New Relic's. Datadog therefore contributes nothing measurable to this study; the cross-source comparison is New Relic + CloudWatch + Sidekiq logs.
