# ANALYSIS — app-atento-001 OpenSearch (2026-06-19)

Parallel analysis to the shared-001 work, run on the second in-scope domain (`ANALYSIS.md` § "OpenSearch domains in scope: shared-001 and atento-001"). Triggered by the `atento-001-opensearch-yellow` CloudWatch alarm that fired 2026-06-19 ~02:43 BRT.

**One-line conclusion:** atento-001 is the **counterfactual** to shared-001 — it received the app-side work (3.33.0 app-managed refresh + engine 3.5) but **not** the scale-up. The app work helped (baseline CPU halved), but the cluster is still undersized: JVM heap rides the 80% circuit-breaker every day and nodes periodically drop → recurring YELLOW. The fix that stabilized shared-001 (t3.small → t3.medium) is the direct remedy.

> **APPLIED 2026-06-19.** The recommended scale-up was executed the same day. Terraform PR **[#527](https://github.com/4shark/terraform/pull/527)** (merged) changed `app-atento-001/opensearch.tf` `instance_type` `t3.small.search` → `t3.medium.search`; `terraform apply` completed `0 added, 1 changed, 0 destroyed` (in-place blue/green, no downtime). `describe-domain` post-apply confirms `t3.medium.search` ×2, `processing: false`. **Pending verification (needs ~1 day of data):** JVM heap max should recede from ~80% toward ~77% (as on shared-001), and the `Nodes=1` drops / `ClusterStatus.yellow` events should stop. Re-pull `JVMMemoryPressure` + `Nodes` after 2026-06-20 to confirm.

## Cluster state (2026-06-19)

`describe-domain app-atento-001`: `OpenSearch_3.5`, **`t3.small.search` ×2**, Multi-AZ, no dedicated master, gp3 10 GB. Last config change `Completed` 2026-05-30 (the engine 3.3→3.5 upgrade). **No scale-up was ever applied** — unlike shared-001, which went to `t3.medium.search` on 2026-06-05.

## The YELLOW alarm — root cause

`atento-001-opensearch-yellow` fired for `ClusterStatus.yellow ≥ 1` (5 datapoints, 05:36–05:41 UTC), back to OK by 05:47.

Correlated metrics (1-min, us-east-1, account 405749097490):
- `Nodes` dropped 2 → **1** from 05:36 to 05:46 (~10 min). When one of the two data nodes leaves, its replica shards become unassigned → `ClusterStatus.yellow`.
- `JVMMemoryPressure` was riding 72–75% on the surviving readings just before the drop; daily max sits at 79.7–80% every day.
- Not RED, no data loss, no disk issue — just replicas temporarily unassigned during the node's absence.

**This is not a new failure mode.** `ClusterStatus.yellow` (5-min buckets) recurs across the entire 05-15→06-19 window, including a ~5h event on **2026-05-19** (63 buckets) — long before the refresh work. The instability is structural (undersized cluster), not a regression from any deploy.

## CPU — the app work helped, but bursts and a load step remain

CPU daily (5-min `period=300`, 05-15→06-19) and 1-min for the recent fortnight:

| Period | CPU p50 | CPU max | Bursts ≥90% |
|---|---|---|---|
| 05-15 → 05-30 (pre app-managed refresh) | **~15%** | ~45% | none (1 day) |
| 05-31 → 06-14 (post 3.33.0 + engine 3.5) | **~9%** | periodic 97–100% | sporadic (consolidated-refresh spikes) |
| 06-15 → 06-19 (after a load step) | **~14,7%** | up to 98% | sporadic |

Readings:
- **31/05: baseline CPU halves 15% → 9%.** The app-managed refresh + engine 3.5 landed 2026-05-30 ~21:00 / refresh_interval:-1 2026-05-31 00:55 (per `ANALYSIS.md` rollout log); the baseline drop on 31/05 corroborates it exactly. The architectural change works on atento too.
- **New burst pattern from 03/06:** sharp spikes to 97–100% that did not exist before — consistent with the design (refresh work consolidated into fewer, larger events). On shared-001 the scale-up's extra headroom smoothed these; atento without it still spikes.
- **15/06: baseline steps back up to ~14,7% and stays flat** — consistent with a sustained load increase that consumed the headroom the refresh change had freed. (Cause not investigated this pass — candidate: new client traffic / indexing volume on atento.)

## JVM — the ceiling that never moved

Daily `JVMMemoryPressure` max is **79.7–80% every single day for all 36 days** (p50 ~52%), ~170–200 min/day above 75%. This is identical to pre-scale-up shared-001. After the scale-up, shared-001's max receded to ~77% and p50 to ~47%; atento never received it, so its heap never moved. The t3.small heap (1 GB) pinned at the circuit-breaker is what periodically pushes a node out under GC pressure.

## atento-001 vs shared-001 (current state)

| Metric | atento-001 (t3.small) | shared-001 (t3.medium) |
|---|---|---|
| JVM heap max daily | ~79.7–80% (daily) | ~77% |
| JVM p50 | ~52% | ~47% |
| Node drops / YELLOW | recurring (alarm today) | none |
| CPU bursts ≥90% | several min on busy days | ~0 (1 min in 14 days) |
| app-managed refresh | yes | yes |
| engine 3.5 | yes | yes |
| scale-up | **no** | yes (2026-06-05) |

## Recommendation

**Apply the same scale-up to atento-001: `t3.small.search` → `t3.medium.search`** (same 2 vCPU, RAM 2→4 GB, heap 1→2 GB). On shared-001 this pulled the heap off the 80% line and the cluster has had zero node-drops/yellow since. The symptom on atento is identical, so this is the strong-candidate fix — though it has not been tested on atento. Urgency rose with the 06-15 load step.

Caveats / before applying:
- It is a candidate by symptom-symmetry, not a proven fix on atento. Watch JVM max and `Nodes` after the change.
- The CPU bursts to 100% are a separate (app-side / refresh-consolidation) phenomenon; the scale-up gives headroom but the bulk-size / thread levers in `PLAN.md` § "Capacity path" remain the orthogonal knobs if bursts persist.
- Reprovisioning recreates nodes (blue/green) — coordinate as a cluster change; confirm Sidekiq queue depth is not heavy at the time.

## Reproduce

Raw pulls in `/tmp` (regenerable): `opensearch_atento001_cpu_minute_20260619.json` (1-min 06-04→06-19), `opensearch_atento001_cpu_5min_20260619.json` (5-min 05-15→06-19), `opensearch_atento001_jvm_minute_20260619.json`, `opensearch_atento001_jvm_5min_20260619.json`, `atento_nodes.json`, `atento_yellow_long.json`. Dimensions: `ClientId=405749097490`, `DomainName=app-atento-001`, `Namespace=AWS/ES`, region us-east-1. Deliverable: `/tmp/opensearch_atento001_timeline_final_20260619.html`.
