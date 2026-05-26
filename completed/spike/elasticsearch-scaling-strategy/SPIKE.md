# SPIKE — Elasticsearch scaling strategy (deal indexation)

**Status**: closed — implementation running in production, observation in progress
**Author**: Paulo Ribeiro
**Date**: 2026-05-26
**Time-box**: 1 day of investigation (spent)
**Question**: given that PR #5057 (bulk indexing) already lowered OpenSearch CPU peak, what is the next lowest-cost / highest-value step — **dedicated Sidekiq process for indexation** or **OpenSearch instance upgrade**?

---

## Context

The `app-shared-001` OpenSearch domain (t3.small.search × 2) had been suffering from `Faraday::TimeoutError` during the nightly commission processing window. PR #5057 introduced bulk indexing (100 docs per request) and lowered CPU peak from 90% to 77%, but JVM Memory Pressure was reported as sustained at ~78% (nightly average) and job p99 of 34s still exceeded the `ELASTICSEARCH_READ_TIMEOUT=30s`.

PR #5041 (Sidekiq Capsule) was proposed to limit `deal_indexation` queue concurrency to 2 threads per pod. Analysis showed that **capsule does relieve OpenSearch saturation but does not correct the Hirefire autoscaling distortion** — the `worker_commission` autoscaler sums 20 queues and cannot distinguish indexation load from commission processing load.

Two non-exclusive alternatives surfaced:

- **Option A**: create a dedicated Sidekiq process for `deal_indexation` (+ tier variants), with its own autoscaling. Resolves the root cause of the distortion.
- **Option B**: upgrade the OpenSearch instance in production environments (atento, shared). Adds CPU/memory headroom without touching queue architecture.

This spike compared both on cost, value delivered, risk, and execution speed.

## Initial state (factual)

### Infrastructure

| Component | shared-001 | atento-001 | beta-001 | demo-001 |
|---|---|---|---|---|
| OpenSearch | t3.small.search × 2 | t3.small.search × 2 | none | none |
| Commission workers (ECS services) | 3 tiers | 3 tiers | 3 tiers | 3 tiers |
| Commission ASG min/max | 1 / 8 | 1 / 8 | (unverified) | (unverified) |
| Worker task size | 2 vCPU / 2 GiB RAM | 2 vCPU / 2 GiB RAM | (unverified) | (unverified) |
| JOBS_PER_PROCESS (autoscaler) | 500 | 500 | 500 | 500 |
| SIDEKIQ_THREADS | 10 | 10 | (unverified) | (unverified) |

### Metrics observed (shared-001, 14 nights, 03:00–09:00 UTC)

| Metric | Pre-bulk (avg) | Post-bulk (1 night) | Notes |
|---|---|---|---|
| JVM Memory Pressure (sustained avg) | ~52% | 51.5% | nightly work in normal state |
| JVM Memory Pressure (peak) | 79–82% | 79.7% | GC spikes, no structural change |
| CPU peak | 84–100% range | 77% | best night in the observed period |
| IndexingRate (nightly sum) | 318K–414K docs | 428K docs | +3% throughput, new peak |
| Sidekiq jobs per night | 156K–207K (singles) | 4.4K (bulks of 100) | as expected |
| Job p99 nightly | 4–18s | 34.4s | above the `ELASTICSEARCH_READ_TIMEOUT=30s` |
| Faraday::TimeoutError (daily) | 211–1254 | 329 (partial) | high night-to-night variance |

### Comparison with atento-001 (same window)

| Metric | shared-001 | atento-001 | Delta |
|---|---|---|---|
| JVM sustained avg | ~52% | ~52% | equal |
| JVM peak | 79–82% | 79–80% | equal |
| CPU avg | 12–16% | 15% | equal |
| **CPU nightly peak** | **77–100%** | **40–61%** | **shared saturates, atento does not** |
| IndexingLatency peak | 209–5020 ms | 210–1022 ms | shared 5× worse |
| Faraday::TimeoutError (7 days) | 3,782 | **7** | shared has **540×** more |
| ThreadpoolWriteQueue peak | 7–96 | always 0 | shared queues writes; atento does not |

**Conclusion from comparison**: JVM and average CPU are the same on both environments (same hardware). **CPU peak** and **timeout frequency** diverge dramatically — shared has the problem, atento does not. Atento processes the workload within the limits of the current t3.small.

### Constraints

- ASG max=8 already caps the commission worker pod count. The theoretical "200 pods" catastrophic scenario does not happen — real cap is 80 simultaneous threads against OpenSearch.
- `t3.small.search` and `t3.medium.search` have **the same vCPU count (2)**. The upgrade only doubles RAM (2 GiB → 4 GiB). JVM heap doubles (~1 GiB → 2 GiB).
- Beta and demo do not have OpenSearch — no indexation traffic. No change needed.

## Options evaluated

### Option A — Dedicated Sidekiq process for indexation

**Required changes:**

1. App (`config/initializers/hire_fire.rb`):
   - Remove `:deal_indexation`, `:deal_indexation_tiger_shark`, `:deal_indexation_white_shark` from `:worker_commission*` dynos
   - Add 3 new dynos: `:worker_indexation`, `:worker_indexation_tiger_shark`, `:worker_indexation_white_shark`

2. Terraform (production scope: atento + shared = 2 envs × 3 tiers = **6 new services**):
   - 6 new `module "ecs_service"` (1 per tier × env)
   - 6 new `module "capacity_worker_indexation*"` (ASGs with own min/max)
   - 6 new entries in `autoscaling_lambdas` map in `lambda.tf`
   - 6 new task definitions with `SIDEKIQ_THREADS=10` (or customized)
   - 6 new log groups

**Proposed ASG configuration for worker_indexation:**

| Tier | Min | Max | JOBS_PER_PROCESS |
|---|---|---|---|
| worker_indexation (atento + shared) | 1 | 3 | 1000 |
| worker_indexation_tiger_shark | 1 | 2 | 1000 |
| worker_indexation_white_shark | 1 | 2 | 1000 |

Low max because each pod (10 threads × bulks of 100 docs) generates ~1000 docs/s — 3 pods give ~3K docs/s sustained, enough to drain 428K docs in ~2h30 (fits the nightly window).

**Natural cap on OpenSearch pressure**: 3 pods × 10 threads = **30 parallel bulks max**. Adjustable via ASG `max_size` without code deploy.

### Option B — OpenSearch instance upgrade

**Required changes:**

- Terraform (`app-shared-001/opensearch.tf` **only**):
  - `instance_type` variable from `t3.small.search` to `t3.medium.search` (or higher)
- **Scope revised**: `app-shared-001` only. Atento processes its workload within current t3.small limits (7 timeouts in 7 days vs 3,782 for shared; CPU peak 40–61% vs 77–100%).

**Comparison of OpenSearch instance types (us-east-1):**

| Instance type | vCPU | RAM | JVM heap | Burstable? | $/h (1 node) | $/month (2 nodes) | Delta vs t3.small × 2 |
|---|---|---|---|---|---|---|---|
| t3.small.search (current) | 2 | 2 GiB | ~1 GiB | yes (burst, 20% baseline) | $0.036 | $52.56 | — |
| t3.medium.search | 2 | 4 GiB | ~2 GiB | yes (burst, 20% baseline) | $0.073 | $106.58 | +$54/mo per env |
| m6g.large.search | 2 | 8 GiB | ~4 GiB | **no** (sustained 100%) | $0.121 | $176.66 | +$124/mo per env |
| r6g.large.search | 2 | 16 GiB | ~8 GiB | **no** (sustained 100%) | $0.157 | $229.22 | +$176/mo per env |

> **Pending verification**: prices validated against training knowledge base. Confirm against [AWS OpenSearch pricing](https://aws.amazon.com/opensearch-service/pricing/) before go/no-go.

**Technical question answered**: the engineer asked whether "t3.medium does not add CPU, only RAM". **Correct** — both have 2 vCPU. But the RAM effect on effective CPU is relevant:

- JVM heap doubles (1 GiB → 2 GiB)
- GC pressure drops → fewer stop-the-world pauses
- Less CPU spent on GC → more CPU available for indexing
- In a memory-bound workload (which was the false reading — JVM at 78% sustained — corrected later), the upgrade *would* translate to effective CPU gain.

Practical translation: t3.medium **likely solves** the JVM problem on its own (78% → ~39%) and frees CPU for the read timeout to stop being exceeded.

**Caveat: `t3.*` instances are burstable.** If the bottleneck is CPU credit exhaustion during long peaks, t3.medium does not solve it (same 20% baseline × 2 vCPU). For sustained high workload, m6g.large would be safer.

## Comparative analysis

### Monthly incremental cost

| Scenario | Additional cost/month | Additional cost/year |
|---|---|---|
| A (dedicated Sidekiq, 6 prod services) | ~$100 (engineer estimate, to verify) | ~$1,200 |
| **B1 (upgrade t3.medium in shared only)** | **$54** | **$648** |
| B2 (upgrade m6g.large in shared only) | $124 | $1,488 |
| A + B1 (dedicated Sidekiq + upgrade shared) | ~$154 | ~$1,848 |

> Atento removed from upgrade scope — comparative analysis showed current t3.small handles atento's workload (7 Faraday::TimeoutError in 7 days vs 3,782 in shared; nightly CPU peak 40–61% vs 77–100%).

### Value delivered

| Item | A (dedicated Sidekiq) | B1 (t3.medium) | B2 (m6g.large) |
|---|---|---|---|
| Reduces JVM Memory Pressure | ❌ (does not change the cluster) | ✅ (78% → ~39%) (under buggy reading) | ✅ (78% → ~20%) (under buggy reading) |
| Reduces nightly timeouts | ⚠️ via thread concurrency cap | ✅ via heap relief (under buggy reading) | ✅ via sustained CPU + heap |
| Autoscaling fidelity to real backlog | ✅ resolves distortion | ❌ unchanged | ❌ unchanged |
| Enables batch >100 | ⚠️ depends on ASG cap | ✅ heap survives | ✅ heap + sustained CPU |
| Cost proportional to use | ✅ scales only when needed | ❌ fixed 24/7 | ❌ fixed 24/7 |
| Time to effect in prod | days | hours | hours |
| Risk on rollout | medium (6 new services) | low (native OS blue-green) | low (same as B1) |
| Reversibility | hard (refactor + deploy) | trivial (1 TF apply back) | trivial (same as B1) |

### Operational risk

**Option A — main risk**: introduces 6 new failure points (3 services × 2 prod envs) with new autoscaling Lambdas. Cold start on the first night could delay processing by 1–3 min until the autoscaler scales up.

**Option B — main risk**: production upgrade uses native OpenSearch blue-green, but **rolling reindex** can take up to 1 hour during the upgrade. Possible degraded window (prior testing in beta NOT possible because beta has no OpenSearch).

## Initial recommendation (later superseded)

**Start with Option B1 (upgrade to t3.medium in shared + atento).**

Justification at the time:

1. Cost similar to A (+$108 vs ~$100/mo) with **much lower complexity** (1 TF PR vs 1 app PR + 1 TF PR with 6 new services).
2. **Resolves the most worrying metric** (JVM Memory Pressure at 78% sustained — buggy reading) which A does not touch.
3. **Reversible in minutes** — 1 TF apply to roll back. Option A is a structural refactor that is not easily undone.
4. **Does not foreclose Option A** — after the upgrade, if the autoscaling distortion still causes perceptible waste, evaluate A with post-upgrade data.
5. **t3.medium directly addresses the engineer's question** — he asked whether RAM helps when vCPU does not change. Under the (buggy) JVM reading, yes — sustained 78% heap meant frequent GC; doubling heap frees effective CPU even without changing vCPU count.

### Recommended sequence (later abandoned)

1. **Day 0**: TF apply in shared to `t3.medium.search × 2`. Native blue-green from OpenSearch (no downtime).
2. **Day 1–3**: monitor JVM Memory Pressure, CPU peak, nightly Faraday::TimeoutError.
3. **If successful**: raise `DEAL_INDEXATION_BATCH_SIZE` to 250 and re-monitor. Apply same upgrade in atento.
4. **If failure**: evaluate upgrade to m6g.large (sustained CPU) OR implement Option A with new data.
5. **Regardless of outcome**: close PR #5041 (capsule).

### What not to do (under the initial recommendation)

- **Do not merge PR #5041 (capsule)** — capsule is a stopgap and introduces architectural debt (autoscaling distortion + idle threads) that is not justified if B1 solves it.
- **Do not implement A without testing B1 first** — A costs the same as B1 with 6× more moving parts.
- **Do not upgrade directly to m6g.large** — overkill if t3.medium suffices; 2.3× higher cost.

## Open questions / pending verification (at time of recommendation)

1. **Cost estimate for Option A** ($100/mo) needed validation — depended on the EC2 instance type used by the indexation worker ASG.
2. **`JOBS_PER_PROCESS=1000` for `worker_indexation`** was an estimate — to be calibrated with real post-implementation data (if reached).
3. **Atento OpenSearch metrics**: JVM avg = 52% (vs shared 78% — buggy reading). Could indicate atento did not need an upgrade.
4. **t3.medium under load test**: ideally validate in staging with synthetic workload, but no staging environment has dedicated OpenSearch. Alternative: roll out in shared and observe one full commission cycle.
5. **Updated AWS pricing**: validate against https://aws.amazon.com/opensearch-service/pricing/ before TF apply.
6. **PR #5041 status**: decide with Emerson whether to close it or convert to draft for later.

## References

- PR #5057 — bulk deal indexing via persisted batches: https://github.com/4shark/app/pull/5057
- PR #5041 — Sidekiq Capsule (open): https://github.com/4shark/app/pull/5041
- `config/initializers/hire_fire.rb:36-60` — `worker_commission` dyno watch list (20 queues)
- `lambda/worker-autoscaling/lambda_function.rb:74-82` — per-dyno scaling logic
- `app/elastic_indexes/application_elastic_index.rb:41-49` — `save_documents!` implementation
- `lib/application_configuration.rb:207-219` — `DEAL_INDEXATION_BATCH_SIZE` config
- AWS OpenSearch instance types: https://docs.aws.amazon.com/opensearch-service/latest/developerguide/supported-instance-types.html
- AWS OpenSearch pricing: https://aws.amazon.com/opensearch-service/pricing/

---

## Outcome — what was actually implemented (2026-05-26)

The initial recommendation (Option B1 — t3.medium upgrade in shared) was **discarded** after reviewing the statistic that supported the JVM-relief argument. A calculation bug (averaging per-bucket maximums instead of averaging per-bucket averages) inflated sustained JVM avg from 52% (real) to 78% (reported), which falsely suggested that more RAM would relieve CPU via reduced GC. With sustained JVM avg at 52%, the cluster has memory headroom — t3.medium would only double heap (1 GiB → 2 GiB) without addressing the real bottleneck (CPU peaks during short bursts).

The chosen path was a **reduced-scope version of Option A** (dedicated Sidekiq process), with 4 important refinements vs. the original spike design:

1. **Only shared-001**, not all 4 environments. Atento, beta, and demo continue using the original `sidekiq_commission.yml` (which still includes `deal_indexation`).
2. **Only the `commission` tier** in shared, leaving tiger_shark / white_shark alone. Tier-specific processing in shared has low volume and the tier YAMLs already consume the corresponding tier queue.
3. **No autoscaling Lambda**. ASG min=1, max=1, desired=1 — a single fixed task draining the queue. Predictable cost (~$20/mo of EC2 + log group) and no aggregate-autoscaling distortion.
4. **All ES-touching workers unified** into two queues: `deal_indexation` (Producer, UserProducer, Consumer, Sower, Grower — main pipeline) and `deal_indexation_cleanup` (Destroyer, Expirator — TTL cleanup). The old `:elastic_index` queue was renamed to `:deal_indexation_cleanup`. Sower/Grower previously on `:commission_processing` (a queue with no consumer in any YAML — historical drift) now use `base_queue_name :deal_indexation` via TenantWorker, with dynamic routing for the tier suffix.

### Merged PRs

| PR | Content |
|---|---|
| [app#5070](https://github.com/4shark/app/pull/5070) | New YAMLs (`sidekiq_commission_without_deal_indexation.yml`, `sidekiq_deal_indexation.yml`) + migration of Sower/Grower/Destroyer/Expirator + Hirefire dyno declarations + Procfile entries |
| [terraform#446](https://github.com/4shark/terraform/pull/446) | `shared-001-worker-deal-indexation-service` ECS service + fixed ASG min=1/max=1 + log group `/ecs/shared-001-worker-deal-indexation` (apply-before-merge) |
| [app#5071](https://github.com/4shark/app/pull/5071) | `.github/workflows/deploy-shared-001.yaml`: add the new worker to `SIDEKIQ_SERVICES` and switch the `configuration_file` of `worker_commission` to the YAML without `deal_indexation` |
| Release 3.32.0 (app#5072) | Tag `3.32.0` on master, version bump in `config/version.rb` |

### Deploy result (2026-05-26 19:29 UTC)

- Deploy run [#26470354634](https://github.com/4shark/app/actions/runs/26470354634): success
- ECS service `shared-001-worker-deal-indexation-service`: ACTIVE, running=1, desired=1, taskDef `:2`
- Sidekiq logs in `/ecs/shared-001-worker-deal-indexation` confirm active processing of `DealElasticIndex::Producer` (~20ms) and `DealElasticIndex::UserProducer` (~60-90ms) jobs
- Worker commission in shared now consumes the YAML without `deal_indexation`, fully isolating the indexation pipeline

### What was NOT done (intentionally)

- **PR #5041 (Sidekiq Capsule, from Emerson)** remains open. Analysis showed that capsule does not resolve the Hirefire autoscaling distortion and would be a stopgap. Since Option A was implemented, capsule becomes obsolete — should be closed after alignment with Emerson.
- **OpenSearch upgrade (t3.medium or m6g.large)**: discarded. Not justifiable given the real JVM avg at ~52% sustained. Reconsider only if the new architecture does not solve the problem on the next night.
- **Replicate split in atento/beta/demo**: discarded. Atento has 7 Faraday::TimeoutError in 7 days (vs 3,782 in shared) and nightly CPU peak 40-61% — within limits. Beta/demo have no OpenSearch.

### Pending — observation only

Validation criteria for the first night after deploy (03:00–09:00 UTC on 2026-05-27):

- **Sustained JVM avg**: stay around ~52% (must not increase)
- **OpenSearch CPU peak**: target ≤65% (was 77-100%)
- **Nightly Faraday::TimeoutError**: target ≤50 (was 232-1024)
- **Throughput**: equal to or greater than 428K docs/night (last measured peak)
- **Logs from the `worker-deal-indexation` pod**: `Consumer` jobs (bulk of 100) with p99 below the `ELASTICSEARCH_READ_TIMEOUT=30s`

If all 5 criteria are met, the spike is closed for good. If 1+ fails, reopen with new data to evaluate the next action (raise batch to 200, scale OpenSearch, etc.).

### Retrospective correction

The calculation bug was acknowledged and corrected during the session. The 6 statistics affected (JVM avg, CPU avg in all previous reports) were overstated. Numbers for **peaks** (max-of-max) were correct, so conclusions about throughput, CPU peak, and timeout count remained valid. Only the argument "JVM at 78% sustained needs heap relief" was invalidated.
