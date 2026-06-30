# ANALYSIS — App-Managed Refresh Rollout (3.33.0)

## Context

The app-managed OpenSearch refresh implemented in `PLAN.md` shipped on release `3.33.0`, currently being deployed to `app-shared-001` (us-east-1). This document captures the pre-deploy baseline against which the post-deploy behavior will be measured.

- **Deploy date**: 2026-05-30
- **Release**: 3.33.0 (PR #5098 merged; HubFlow finish ran by engineer; release branch deleted)
- **Cluster under observation**: `app-shared-001` (us-east-1, OpenSearch)
- **Baseline window**: 2026-04-30 → 2026-05-30 (30 daily samples, CloudWatch period 86400s, avg + max)
- **Code change effective**: at deploy completion the new `DealIndexationBatch` state machine, Refresher, Consumer lock check, RefreshWorker and DispatchChecker are live; the cluster setting `index.refresh_interval: -1` is applied as a separate cluster-side step (see `PLAN.md` § Rollout phases, phase 3)

## Pre-deploy baseline (last 30 days)

Source: `opensearch_baseline_30d_pre_3.33.0.html` (interactive Chart.js view) and the underlying CloudWatch series embedded in it. A second deploy on 2026-05-26 (PR #5070 + #5071 — dedicated Sidekiq worker for deal indexation) is marked with a dashed vertical line and constitutes a confounder that must be controlled for when reading post-3.33.0 effects.

| Metric | Avg over window | Max over window | Observation |
|---|---|---|---|
| `IndexingLatency` (ms) | 6–10 | 396–19834 spikes | Average stable; max very volatile, indicating sporadic heavy bulk events but no chronic degradation |
| `IndexingRate` (ops/min) | oscillating, contains negative values | 17–22k pre-26-mai; 37–51k post-26-mai | Negative averages are CloudWatch artifact when the counter resets on worker restart — informative of restart frequency, not throughput. Max throughput more than doubled after the dedicated-worker split |
| `SearchLatency` (ms) | 4–8 | 363–9385 spikes | Stable; the refresh redesign should not affect this metric |
| `SearchRate` (ops/min) | oscillating, contains negative values | 5556–12583 | Same artifact pattern; max steady |
| `CPUUtilization` (%) | 10–17 | 100% on multiple days | Cluster CPU-saturated at peaks. Pre-existing pressure; the rollout is expected to consolidate refresh work into fewer, larger events — net effect on CPU is an open question |
| `JVMMemoryPressure` (%) | ~51 | ~79.7 (one outlier at 82.4 on 2026-05-05) | Heap pressure caps at the circuit-breaker line. Structural ceiling unchanged by recent deploys |
| `ConcurrentSearchLatency` (ms) | 0.07–7 | 175–18754 | High volatility on max. Pre-existing pattern, no correlation with the 2026-05-26 deploys |
| `WriteLatency` (ms) | 0 | 0–0.01 | Negligible; EBS-side writes are not the bottleneck |
| `RefreshLatency` | no datapoints | no datapoints | Metric is not currently emitted. There is **no pre-deploy baseline for refresh latency** — post-deploy values are first-observation, not deltas |

### Confounder: 2026-05-26 dedicated-worker deploy

The 30-day window includes the May 26 split of deal indexation into its own Sidekiq worker (PRs #5070 and #5071). Effects already attributed to that deploy:

- `IndexingRate` max more than doubled (~17–22k → 37–51k)
- `IndexingLatency` avg unchanged — throughput gain came from parallelism, not per-op speed
- `SearchLatency` unchanged — search and index share resources without measurable cross-impact in this regime
- `CPUUtilization` and `JVMMemoryPressure` unchanged — the split redistributed work; it did not reduce total cost
- New negative averages in `IndexingRate` and `SearchRate` reflect more frequent Sidekiq restarts during the post-deploy tuning window — these should stabilize over the coming days regardless of 3.33.0

Post-3.33.0 readings must be compared against the **last four days (2026-05-27 → 2026-05-30)** of the baseline window, not the full 30 days — those four days reflect the dedicated-worker world that 3.33.0 inherits.

## Expected effects of 3.33.0

Derived from the design in `PLAN.md` (§ Goal, § Core architectural decisions, § Rollout phases) and the spike findings in `SPIKE-APP-MANAGED-REFRESH.md`:

| Metric | Expected direction | Reasoning |
|---|---|---|
| `RefreshLatency` (first emission) | Single sample per refresh window; per-event latency dominated by segment count at refresh time | OpenSearch native auto-refresh was firing every 30s; the new app-managed refresh fires once per Refresher cycle (variable cadence, governed by `deal_indexation_refresh_max_duration` and the Redis lock). Fewer refresh events, each touching more segments |
| Number of refresh events per hour | Drops substantially (target: one per app-driven window vs. ~120/hour from native auto-refresh) | This is the central goal of the change |
| Segment count per `GET /_stats` cycle | Drops or stabilizes | Fewer refreshes → larger, fewer segments → less merge work |
| `CPUUtilization` peaks | Net direction unclear; lean toward reduction | Refresh + merge are CPU-heavy; consolidating them should reduce total CPU time but concentrate it at refresh moments |
| `JVMMemoryPressure` ceiling | Should not regress; may slightly improve | Heap pressure is driven by indexing buffers and segment metadata; fewer segments means less metadata in heap |
| `IndexingLatency` avg | Unchanged | Indexing path is unchanged by this release |
| `IndexingRate` avg/max | Unchanged baseline; negative-rate artifacts continue while Sidekiq restarts settle | Throughput is governed by the dedicated-worker capacity from 2026-05-26 |
| `SearchLatency` avg | Unchanged | Search-side behavior is unchanged |
| Per-commission end-to-end latency floor | Rises from ~0s to ~45s | Engineer-accepted trade-off documented in `PLAN.md` § Risks |
| Sidekiq queue depth on the new `deal_indexation_refresh` queue | Bounded; should rarely accumulate | Refresher dispatch is throttled by the Redis lock; one Refresh job per window |

## Post-deploy first reading — CPU (2026-06-01)

First post-deploy measurement, taken 2026-06-01 (~1.5 days of post-app data). Scope: `CPUUtilization` only — the metric the engineer flagged as the pre-existing pain (`SPIKE-INGEST-READ-PATTERNS.md`: native auto-refresh + merge work was CPU-pegging the cluster). Supporting files: `opensearch_cpu_post_3.33.0_first_reading_2026-06-01.html` (interactive minute-level chart + tables) and `opensearch_cpu_minute_series_pre_post_3.33.0_2026-06-01.json` (raw 1-minute series, preserved because CloudWatch drops 1-minute resolution after 15 days).

### New confounder — OpenSearch engine upgrade 3.3 → 3.5 (parallel work)

Not previously recorded in this doc. On the **same Saturday (2026-05-30)**, as part of an unrelated infra-currency effort (engineer upgraded all RDS + ElastiCache + OpenSearch to current versions, to avoid running on soon-deprecated versions), `app-shared-001` was upgraded **OpenSearch 3.3 → 3.5**. CloudTrail (`es.amazonaws.com`, account 405749097490):

| Time (UTC) | Event | Detail |
|---|---|---|
| 2026-05-30 17:53 | `StartServiceSoftwareUpdate` | `OpenSearch_3_3_R20260217-P1` → `R20260428-P1` |
| 2026-05-30 18:42 | `UpgradeDomain` | engine `OpenSearch 3.3 → 3.5` |
| 2026-05-30 19:18 | config change `Completed` | `ChangeProgressDetails` |

This matters because the engine upgrade completed **~5 h before** the app-managed-refresh code went live on shared-001 (deploy success 2026-05-31 00:39 UTC, run `26698926406`, sha `24400e90`). That gap creates a control window ("engine new, app still old") that lets us partially separate the two effects.

### Methodology — minute-level, robust statistics

Daily/hourly aggregates are misleading here: the workload produces ~40-second CPU bursts. At hourly resolution a 40 s burst either inflates the whole-hour `Maximum` to 100% (reads as sustained saturation) or is diluted into the `Average` (reads as no event). The reading was redone at **1-minute resolution** (`period=60`) with **median/percentiles** instead of mean — percentiles are not distorted by short bursts. Window: 2026-05-22 00:00 → 2026-06-01 12:01 UTC, 15,097 datapoints, `StatusCode: Complete`.

### Three-segment attribution

| CPU % | seg1 · engine old + app old | seg1b · last-4-days (27–30/05) engine old + app old | seg2 · engine new + app old | seg3 · engine new + app new |
|---|---|---|---|---|
| window | 22/05 → 30/05 17:53 (8.73 d) | 27/05 → 30/05 17:53 (3.74 d) | 30/05 19:18 → 31/05 00:40 (~5 h, Sat night) | 31/05 00:40 → 01/06 12:01 (1.47 d) |
| p50 (baseline) | 8.5 | 8.5 | **14.5** | 14.0 |
| p90 | 16.0 | 15.5 | 23.5 | 23.5 |
| p95 | 20.0 | 19.5 | 26.0 | 28.0 |
| p99 | 45.5 | 33.0 | 32.0 | 37.0 |
| max 1-min average | 89 | 87 | 36 | 64 |
| bursts ≥90% / day | 3.32 | 4.55 | 0 | 0.68 |
| bursts ≥80% / day | 5.84 | 6.95 | 0 | 3.40 |
| bursts ≥50% / day | 18.44 | 16.04 | 0 | 12.93 |

(`seg1b` is the comparison basis this doc prescribes — the dedicated-worker world from 2026-05-26. Its p50 is identical to the 30-day p50, confirming the May-26 worker split left CPU baseline unchanged, as recorded above.)

### Conclusions (first reading)

1. **Higher CPU baseline is the engine upgrade, not the app change.** The median jumps 8.5% → 14.5% in **seg2** — engine already on 3.5 while the app was still the old code. When 3.33.0 went live (seg3), the baseline did not move (14.0%). The app-managed refresh did **not** raise the baseline. This is consistent with `PLAN.md` § Risks (the refresh change was never expected to move idle CPU).
2. **Extreme CPU-pegging bursts dropped sharply, but attribution is confounded.** Comparing seg1b → seg3, bursts ≥90%/day fell 4.55 → 0.68 (~6.7×) and the longest sustained minute fell from 87% to 64%; meanwhile p99 stayed roughly flat (33 → 37, baseline-shifted). But both the engine upgrade (3.5 may handle the same load more efficiently) and the app change (refresh work consolidated/moved app-side) reduce bursting, and the only isolating window (seg2) is ~5 h of dead Saturday-night traffic — its zero bursts prove nothing. **Cannot yet quantify how much of the burst reduction is the app change vs. the 3.5 upgrade.**
3. **Sample is short and weekend-skewed.** seg3 is 1.47 days, mostly Sunday + Monday morning. Needs a full business week to confirm bursts stay low under weekday load.

Supporting weak signals over the same period (confounded by the same two factors): daily `5xx` fell (2026-05-27 = 7583 → 05-31 = 39, 06-01 = 34); `JVMGCYoungCollectionTime` max trended down (peak 1.57M → ~457–616k). `JVMMemoryPressure` unchanged (~51% avg / ~80% max), as expected.

### What this does NOT cover yet

`RefreshLatency`, refresh-events-per-hour, and segment count — the central goal metrics from the "Expected effects" table — are not in this reading. This first pass is CPU-only. The 1-week revisit (see `REVISIT-CONTEXT.md`) must pull those to validate the actual refresh-consolidation goal, beyond the CPU side-effect.

## Post-deploy observability checklist

For each item: who watches, what to look at, what condition signals a problem.

| # | Signal | Source | Watch condition (problem) | Owner action if triggered |
|---|---|---|---|---|
| 1 | RefreshWorker queue latency | Sidekiq web UI or CloudWatch worker queue depth | Latency consistently > 60s | Verify worker concurrency; check Sidekiq logs for errors |
| 2 | RefreshLatency (CloudWatch) | OpenSearch metric | First observation establishes baseline; subsequent samples > 10s sustained | Investigate segment count and merge backlog |
| 3 | Number of `deal_indexation_batches` in `executed` state with `executed_at` older than 2× `deal_indexation_refresh_max_duration` | Rails console / monitoring query | Any row | Lock leak or Refresher crash — inspect Redis lock + Sidekiq logs |
| 4 | Number of `deal_indexation_batches` in `refreshed` state with `metric_dispatched_at` null and `refreshed_at` older than 5 minutes | Rails console / monitoring query | Any row | DispatchChecker crash — inspect Sidekiq retries |
| 5 | OpenSearch `CPUUtilization` max | CloudWatch | Sustained > 90% for > 30 minutes | Capture cluster `_nodes/stats` snapshot, decide between cluster scale-up and further app-side tuning |
| 6 | OpenSearch `JVMMemoryPressure` max | CloudWatch | Sustained > 80% for > 1 hour | Same as #5 — heap is closer to circuit-breaker than CPU was |
| 7 | OpenSearch refresh count per hour (`GET /_stats`) | Direct OpenSearch API | Higher than pre-deploy after `refresh_interval: -1` is applied | Verify the cluster setting actually took effect (`GET /deals/_settings`) |
| 8 | Per-commission end-to-end latency p50 / p99 | App-side metric (whichever the app already exposes) | p99 > 90s sustained | Confirm against the engineer-accepted ~45s floor; if exceeded, investigate Refresher cadence |
| 9 | Sidekiq dead set / retry set growth on the new queue | Sidekiq web UI | Sustained growth | Inspect failure reason; the design assumes idempotent retries |

## Rollback triggers

Per `PLAN.md` § Rollout phases:

1. **Phase 3 rollback** (cluster setting only): `PUT /deals/_settings { "index": { "refresh_interval": "30s" } }` — re-enables native auto-refresh, system runs hybrid until a code rollback. Reach for this if observables 5, 6, or 7 trigger and the cause maps to the new refresh model.
2. **Phase 2 rollback** (revert deploy): rolls back the consumer change, Refresher, and DispatchChecker. Reach for this if observables 3, 4, or 9 reveal a structural bug in the state machine.
3. **Phase 1 rollback** (schema): the four new columns and two indexes stay; they are unused without the code. No rush; drop later as separate work.

## Rollout execution log

| Date (UTC) | Step | Environment | Result |
|---|---|---|---|
| 2026-05-30 ~21:00 | Phase 2 (code deploy 3.33.0) | atento-001, demo-001, beta-001 | success |
| 2026-05-30 23:59 | Phase 2 (code deploy 3.33.0) | shared-001 | **failure** — migration `20260529120547` ANALYZE post-step timed out at `statement_timeout = 250ms` (strong_migrations on `deal_indexation_batches`). Index created out-of-band; `schema_migrations` row missing |
| 2026-05-31 ~00:25 | Recovery | shared-001 | terraform PR #455 raised `MIGRATION_20260529120547` and `MIGRATION_20260529121413` to `30000`. RDS: orphan index `index_deal_indexation_batches_on_status_and_commission_id` dropped via `DROP INDEX CONCURRENTLY`. Apply + DROP completed |
| 2026-05-31 ~00:50 | Phase 2 retry | shared-001 | success |
| 2026-05-31 ~00:55 | Phase 3 (`PUT /deals/_settings refresh_interval: -1`) | atento-001 | applied (server-side PUT completed despite Faraday::TimeoutError client side; re-read confirmed `"-1"`) |
| 2026-05-31 ~01:00 | Phase 3 | shared-001 | already `"-1"` on first GET (likely applied during recovery flow); PUT idempotent re-confirmed |
| 2026-05-31 ~02:25 | **Parallel incident** — RDS db-1 saturation | shared-001 | integrator maqnelson nightly burst on `PUT /api/v3/subsidiaries/:id/deals/:id` saturated db.t4g.large (2 vCPUs) at 99.5% CPU for ~70 min. Root cause: 3.33.0 commit `ad54ec6bc` added `UserIdentifier.get(company_id, value)` lookup in `Deal#resolve_user_identifier_value` (and Goal/Indicator equivalents); query missed partial index because `subsidiary_id` predicate absent. Compounded by missing composite index on `deals(company_id, external_id)` for the existing `Deal.get` call in `Api::V3::Subsidiaries::DealsController#update:228`. 93% of web requests returned 5xx |
| 2026-05-31 ~03:30 | Mitigation | shared-001 | TSTP sent to maqnelson integrator workers via `aws ecs execute-command`; cluster recovered to 1-2 AAS within ~3 min |
| 2026-05-31 ~04:00 | Hotfix preparation | shared-001 | PR #5099 (app) — `subsidiary_id: nil` added to `UserIdentifier.get` callsites in `deal.rb`, `goal.rb`, `indicator.rb`; new migration `20260531100514` adds `add_index :deals, [:company_id, :external_id], algorithm: :concurrently`; index created manually in shared-001 via `aws ecs run-task` (migration TD with master `postgres` user, MD5 auth incompatible with scram-sha-256) before hotfix deploy |
| 2026-05-31 ~05:30 | Hotfix 3.33.1 release | all 4 envs | release branch + hotfix flow; PR #5099 merged + `git hf hotfix finish 3.33.1` ran |
| 2026-05-31 ~10:00 | Deploy 3.33.1 attempt 1 | shared-001 | **failure** — migration `20260531100514` ANALYZE post-step timed out at 250ms on `deals` (same root cause as 3.33.0 incident, on a different migration) |
| 2026-05-31 ~10:30 | Recovery | shared-001 | terraform PR #456 added `MIGRATION_20260531100514 = "30000"` to `app-shared-001/compute.tf` |
| 2026-05-31 ~10:55 | Deploy 3.33.1 attempt 2 | shared-001 | success — migration became no-op (`if_not_exists: true` skipped the existing index); ANALYZE completed under the raised timeout |
| 2026-05-31 ~11:05 | Deploy 3.33.1 | demo-001 | **failure** — same ANALYZE timeout; CREATE INDEX CONCURRENTLY left the index in `INVALID` state (PgHero confirmed) |
| 2026-05-31 ~11:15 | Recovery + redeploy | demo-001 | terraform PR #457 added `MIGRATION_20260531100514 = "30000"` to `app-demo-001/compute.tf`; redeploy succeeded |
| 2026-05-31 ~11:35 | Index integrity fix | demo-001 | `bin/rails db:migrate:down VERSION=20260531100514` (drops invalid index via `def down` `remove_index ... if_exists: true`) followed by `db:migrate` (re-creates index clean). Execution via `aws ecs run-task` with override DATABASE_URL pointing direct to Aurora (psql unavailable in container; pgbouncer transaction pooling breaks CREATE INDEX CONCURRENTLY) |
| 2026-05-31 ~11:45 | SSM cleanup | 4 app stacks + outbound | terraform PR #458 removed stale `MIGRATION_DATABASE_URL` from `app-shared-001/compute.tf`, `app-demo-001/compute.tf`, `app-beta-001/compute.tf`, the 4 `ssm.tf` files, and `modules/atento_001_task_config/main.tf` (shared between atento-001 and outbound-atento-br). Applied in order outbound → atento to avoid orphan ARN reference. Workflow `secrets.MIGRATION_DATABASE_URL` (GH Environment Secret) confirmed as the actual source of truth; SSM params were Heroku-era artifacts, never read by app or workflow |
| 2026-05-31 ~11:54 | Latent defect introduced by PR #458 | shared-001 | The same apply that deleted SSM param `/shared-001/MIGRATION_DATABASE_URL` also re-registered the worker task defs (`:55`) **without `command`** — the terraform-generated TD omits the Sidekiq `command` the GHA pipeline normally sets. No deploy followed (the change was deemed "removing an unused env var"), so the running services stayed on `:54`, which still references the now-deleted SSM param |
| 2026-05-31 ~15:25 | **Follow-on incident** — ECS worker services down | shared-001 | `worker-system` (0/2) and `worker-commission` (0/1) tasks recycled on `:54`, failed the SSM secret fetch (`invalid parameters: /shared-001/MIGRATION_DATABASE_URL`), and crash-looped. CloudWatch alarm `shared-001-ecs-service-down-shared-001-worker-system-service` fired (`RunningTaskCount=0`). `worker-user` (`:54`) and `web` (`:65`) stayed up only because their tasks had not recycled yet — latent time-bombs. The OpenSearch domain itself was healthy throughout (the alarm namespace is `ECS/ContainerInsights`, not OpenSearch) |
| 2026-05-31 ~17:28 | Manual mitigation attempt (failed) | shared-001 | `update-service` to `:55` rejected by the deployment circuit breaker — `:55` boots the container but `tini` has no program to run (missing `command`) → exit 1 → automatic rollback to `:54`. Confirmed the terraform-generated TD is itself broken, independent of the secret |
| 2026-05-31 ~17:41 | Resolution — full GHA deploy | shared-001 | Deploy `Deploy Shared-001 App` (run `26719749817`, branch `master`) re-registered all worker/web task defs (`:56`/`:67`) **with `command` restored and without the dead secret** — the GHA pipeline generates the TD correctly, unlike the bare `terraform apply`. All services recovered: worker-system `:56` 2/2, worker-commission `:56` 1/1, worker-user `:56` 1/1, web `:67` 4/4 |

**Incident closure:** all 4 app envs on 3.33.1 with correct indexes, RDS db-1 healthy, no app-side residue. Integrator maqnelson worker restored to desired count 2 after the TSTP mitigation.

OpenSearch domains in scope: shared-001 and atento-001 only. Demo-001 and beta-001 do not run their own OpenSearch domain — no Phase 3 action applies there.

### Follow-on incident — worker services down (2026-05-31, post-cleanup)

The SSM `MIGRATION_DATABASE_URL` cleanup (PR #458, marked Done below) triggered a second incident the same day. The Amazon Q CloudWatch alarm in `#dev_operations` read as "OpenSearch down" but was in fact `ECS/ContainerInsights` `RunningTaskCount=0` — the OpenSearch domain was healthy the whole time. Two independent defects, both introduced by the bare `terraform apply` that ran the cleanup **without an accompanying deploy**:

1. **Deleting the SSM parameter broke the still-running revision.** The apply destroyed `/shared-001/MIGRATION_DATABASE_URL`, but the live services were still on task def `:54`, which references it. ECS does not re-fetch secrets for running tasks, so nothing broke until ~12:25 BRT, when `worker-system` and `worker-commission` tasks recycled, failed the secret fetch, and crash-looped to 0 running. `worker-user` (`:54`) and `web` (`:65`) were latent time-bombs for the same reason.
2. **The terraform-generated task def lost the `command`.** Revision `:55` (terraform) has `command: null`; `:52`/`:54` and the pipeline-generated `:56` all carry `bundle exec sidekiq -C config/sidekiq_system.yml`. A manual `update-service` to `:55` therefore could not recover the service — the container booted, `tini` had no program, exited 1, and the deployment circuit breaker rolled back to the broken `:54`.

**Resolution:** a full deploy via GitHub Actions (run `26719749817`, "Deploy Shared-001 App") re-registered every task def (`:56`/`:67`) with the `command` restored and the dead secret gone. All services recovered (worker-system 2/2, worker-commission 1/1, worker-user 1/1, web 4/4). Lesson: removing the SSM param required a deploy in the same window so the in-use task defs stopped referencing it — and the canonical task def comes from the GHA pipeline, not from `terraform apply`, which omits the `command`.

## Follow-up actions

**Open:**
- **Instrument observable #8 (per-commission end-to-end latency p50/p99)** if not already exposed — needed to validate the ~45s floor the engineer accepted.
- **PgBouncer EC2 (`i-0dd0d5c92ec9daf66`) is not registered in SSM.** Surfaced during the 2026-05-31 incident as a constraint on emergency troubleshooting (forced SSH-via-1Password to read `userlist.txt`). Enable SSM Agent so the host is reachable via Session Manager / Run Command.
- **PgBouncer EC2 is t3a.micro.** Worked through the 2026-05-31 incident because the bottleneck was RDS-side, not PgBouncer-side (CPU stayed at 1-2% on the EC2). Under different shape — many small connections instead of few CPU-heavy queries — t3a.micro becomes the gargalo. Upsize to at least t3.small (2 vCPU non-burstable) and ideally split read/write pools.
- **GitHub Environment Secret `MIGRATION_DATABASE_URL` has no rotation discipline.** Last updated 2026-03; manually maintained via GitHub repo Settings UI. Should be sourced from a single canonical place (SSM or Secrets Manager) and consumed by the workflow via a script that reads at runtime. Otherwise drift between the secret and the actual RDS credential is invisible until a deploy fails.
- **Task-def ownership is split between Terraform and the GHA pipeline.** Revision `:55` proves a bare `terraform apply` re-registers the worker task defs without `command`, while the GHA pipeline registers them correctly (`:56`). A future `terraform apply` on these worker families will re-arm the same exit-1 failure for anyone who deploys outside the pipeline. Reconcile ownership: either Terraform stops managing the `command`/container shape (pipeline owns it) or Terraform sets the full `command`.

**Done:**

- ✅ SSM `MIGRATION_DATABASE_URL` cleanup — removed from terraform (5 stacks) and the 4 SSM params destroyed. App container no longer carries the dead env var (PR #458, applied).
- ✅ Statement-timeout override added for migrations on `deal_indexation_batches` and `deals` in app-shared-001 and app-demo-001 (PRs #455, #456, #457).
- ✅ Bake `refresh_interval: '-1'` into `DealElasticIndex` settings (PR #5100, merged). Any future `DealElasticIndex.create!` now starts with auto-refresh disabled.
- ✅ CloudWatch alarm `<env>-opensearch-refresh-latency-high` (RefreshLatency p99 ≥ 10000ms sustained 30×60s) added to `cloudwatch_app_monitoring` module; applied automatically in shared-001 and atento-001 via existing module usage (PR #459).

## Open data gaps

## Open data gaps

- **No pre-deploy RefreshLatency baseline.** Decide whether to instrument it pre-rollout-of-cluster-setting (phase 3) so the first sample is not the only data point.
- **No segment count timeseries.** `GET /_stats` is point-in-time; sustained observation needs a sampler. Consider adding a scheduled CloudWatch custom metric if observable #7 needs trend data.
- **Per-commission end-to-end latency** (observable #8) — whichever app-side metric the team has today; if none exists, this is an instrumentation follow-up.

## References

- `PLAN.md` — design and rollout phases
- `SPIKE-APP-MANAGED-REFRESH.md` — refresh model spike that produced the design
- `SPIKE-INGEST-READ-PATTERNS.md` — read/write pattern spike that motivated the redesign
- `opensearch_baseline_30d_pre_3.33.0.html` — interactive baseline view (supporting file in this folder)
- `refresh_latency_metrics_pre_3.33.0.json` — empty RefreshLatency series confirming the metric gap (supporting file in this folder)
- ADR `docs/adr/0001-app-managed-opensearch-refresh.md` in the `app` repo — long-form decision record
- Architecture doc `docs/architecture/DEAL_INDEXATION_REFRESH.md` in the `app` repo — flow diagrams and component contracts
