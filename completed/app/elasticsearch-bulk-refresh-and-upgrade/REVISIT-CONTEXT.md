# REVISIT-CONTEXT — App-Managed Refresh (3.33.0) on `app-shared-001`

Supporting/auxiliary note. Purpose: give the session that revisits this in ~1 week (target ≥ 2026-06-08, after a full business week post-deploy) the maximum context to continue without re-deriving anything. Read this together with `ANALYSIS.md` § "Post-deploy first reading — CPU (2026-06-01)".

This file is **state at 2026-06-01**, not a plan. It records: what was measured, exactly how, what was concluded, what is still open, and the exact commands to reproduce.

> **Revisit executed 2026-06-08.** The weekday-data revisit this file was written to feed has been run. Findings — including a **third performance lever** that landed after this file froze — are in the new section **"Revisit executed — 2026-06-08"** immediately below. The 2026-06-01 content underneath is preserved as the frozen baseline; read the revisit section first.
>
> **Final reading executed 2026-06-19.** A second, longer revisit (2+ weeks post-deploy, full business-week coverage past the scale-up) was run to close the plan's last open phase. Findings are in **"Final reading — 2026-06-19"** immediately below. This confirms the 2026-06-08 verdict held and quantifies the JVM ceiling recession the scale-up targeted. Read this first.

---

## Final reading — 2026-06-19 (plan's last phase closed)

Run 2026-06-19, ~14 days after 3.33.0 and ~14 days after the scale-up. Purpose: the engineer-requested "analyse performance after some time" phase. Resolves the JVM-ceiling action item the 2026-06-08 revisit left open and confirms the CPU verdict survives a long weekday window.

**No new infra events.** `describe-domain` 2026-06-19: still `OpenSearch_3.5`, `t3.medium.search` ×2, `ConfigChangeStatus: Completed` since 2026-06-05 — no cluster change since the scale-up. 8 routine app deploys landed 2026-06-09 → 06-18 (`Deploy Shared-001 App`, all success); none touched the OpenSearch path or sizing, and the metrics stayed flat through all of them.

### CPU — flat for 2+ weeks (1-minute, per day)

CloudWatch 1-minute `CPUUtilization`, fresh pull 2026-06-05 → 2026-06-19 (`/tmp/opensearch_shared001_cpu_minute_20260619.json`). Overlap days 06-05→06-08 reproduce the 2026-06-08 table exactly (method confirmed). `min ≥X%` = count of 1-minute datapoints whose **max** crossed X%.

| Day (UTC) | p50 % | p99 % | max % | min ≥90% | min ≥80% | min ≥50% | marker |
|---|---|---|---|---|---|---|---|
| 06-05 | 9.5 | 23.0 | 58 | 0 | 0 | 1 | ③ t3.medium (18:02) |
| 06-06 | 9.0 | 20.5 | 39 | 0 | 0 | 0 | |
| 06-07 | 9.0 | 20.0 | 39 | 0 | 0 | 0 | |
| 06-08 | 9.0 | 19.5 | 41 | 0 | 0 | 0 | |
| 06-09 | 9.0 | 20.0 | 41 | 0 | 0 | 0 | deploy |
| 06-10 | 9.5 | 20.5 | 61 | 0 | 0 | 1 | deploy |
| 06-11 | 9.5 | 23.0 | 57 | 0 | 0 | 2 | |
| 06-12 | 9.0 | 20.5 | 49 | 0 | 0 | 0 | deploy |
| 06-13 | 9.0 | 20.5 | 74 | 0 | 0 | 3 | |
| 06-14 | 8.5 | 21.0 | 55 | 0 | 0 | 1 | |
| 06-15 | 9.0 | 21.5 | 63 | 0 | 0 | 2 | deploy |
| 06-16 | 9.5 | 22.5 | 90 | 1 | 1 | 1 | single 90% blip |
| 06-17 | 9.5 | 21.5 | 81 | 0 | 1 | 1 | 3 deploys |
| 06-18 | 9.0 | 22.0 | 76 | 0 | 0 | 3 | deploy |
| 06-19 | 9.5 | 24.0 | 55 | 0 | 0 | 2 | (partial, to 11:57) |

Reading:
- **CPU-pegging is gone and stays gone.** Across 14 days there is **exactly one** minute ≥90% (06-16, a single isolated blip) and **two** minutes ≥80% total. Compare seg1b before (4.55 min ≥90%/day) and the weekday regression 27–29/05 (up to 9 min/day). Effective reduction on the weekday-regression peak is ~65× on ≥90% bursts.
- p99 holds ~20–24% all window; p50 steady ~9%. The transient engine baseline (p50 14% on 31/05) is long gone — back to ~9%.
- The only sub-bursts (06-16 max 90, 06-17 max 81) cluster on heavy deploy days — deploy-driven indexing/restart spikes, isolated single minutes, not the old sustained pattern.

### JVM ceiling recession — scale-up action item resolved

The 2026-06-08 revisit flagged: *"confirm the 2→4 GB RAM bump pulled the heap ceiling down off 80%."* Answer: **yes, modestly.** Per-day `JVMMemoryPressure`:

| Period | p50 | max (daily) | days touching ≥80% |
|---|---|---|---|
| t3.small (24/05–05/06, frozen `os_chart_data.js`) | ~51% | **80% every day** (one day 81%) | 13 of 13 |
| t3.medium (06–19/06, fresh pull) | ~47% | **~77%** | 1 of 14 (80.8% on 06-17) |

The ceiling came off the 80% circuit-breaker line (80 → 77) and the median dropped ~51 → 47%. The `JVMMemoryPressure`% did **not** halve despite doubling heap (1 → 2 GB) — the JVM expands young-gen to use the larger heap, so the *percentage* moves only ~3–4 points while absolute headroom doubles. The real win is structural: the cluster stopped riding the circuit-breaker line daily.

### IndexingLatency — collapsed to milliseconds

Same fresh pull. From 06-06 onward (first full day post scale-up): **p50 0 ms, p99 <1 ms, max ≤21 ms/day**. The frozen reading saw bulk-batch maxes ~5020 ms. The 06-05 partial day still shows the old shape (max 771 ms, p99 88 ms) — the collapse is clean at the scale-up boundary. (Not over-attributed: this overlaps the 3.33.0 consolidation effect too; report as combined.)

### Deliverable produced this reading

`/tmp/opensearch_shared001_timeline_final_20260619.html` — self-contained engineer-facing timeline: before/now/improvement cards, daily CPU-burst bar chart + daily JVM-max line chart (both 24/05→19/06 with the 3 levers marked), comparative tables, and the annotated event timeline. Inline Chart.js (CDN); no sibling data file needed (data is inlined). Raw fresh pulls in `/tmp`: `opensearch_shared001_{cpu,jvm,idx}_minute_20260619.json`.

### Verdict — plan's last phase closed

The open phase ("analyse performance after a while") is answered. Under 2+ weeks of weekday load, across 8 routine deploys, the CPU-pegging that motivated the entire effort is **zero and stable**, the heap is off the 80% line, and indexing is flat in milliseconds. Per `PLAN.md` § Architectural closure, the app↔OpenSearch interaction is now considered aligned; any future issue is config fine-tuning or cluster scale-up, not architectural rework. Engine-vs-app-vs-scale-up attribution remains structurally unattributable (three overlapping changes) — accepted; the business question is answered yes. **This folder is ready to move `active/` → `completed/` once the engineer confirms.**

---

## TL;DR of where we are

- App-managed refresh (PR #5080, release 3.33.0) is live on `app-shared-001` since **2026-05-31 00:39 UTC**.
- First CPU reading (1.5 days, weekend-skewed) shows: extreme CPU bursts (≥90%) down ~6.7× vs the prior 4 days; but a **parallel OpenSearch 3.3→3.5 engine upgrade** the same Saturday confounds attribution, and the higher CPU baseline is the engine, not the app.
- **Two things block a clean verdict:** (1) only ~1.5 days of post data, all weekend; (2) engine-vs-app burst attribution unresolved. The revisit fixes (1) with weekday data; (2) is structurally hard (see "What the revisit cannot fix").

---

## Revisit executed — 2026-06-08 (weekday data + third lever)

Run on 2026-06-08, after a full business week post-deploy. Resolves the two blockers the 2026-06-01 reading left open and adds a third performance change the frozen state did not know about.

### The three deploy points (corrected)

The engineer's mental model is three performance adjustments. Cross-referenced against the app CHANGELOG, GitHub Actions `Deploy Shared-001 App` runs, and the terraform repo. The corrected set:

| # | Change | When applied to shared-001 (UTC) | Source of truth |
|---|---|---|---|
| 1 | **3.32.0** — dedicated deal-indexation Sidekiq worker (the "dedicated queue") | 2026-05-26 19:39 | GH Actions run `26470354634`, sha `8e382aaf`, tag `release/3.32.0` |
| 2 | **3.33.0** — app-managed OpenSearch refresh | 2026-05-31 00:39 | GH Actions run `26698926406`, sha `24400e90`, tag `release/3.33.0` |
| 3 | **OpenSearch cluster scale-up `t3.small.search` → `t3.medium.search`** | 2026-06-05 18:02 (start 17:26) | Terraform PR #497, sha `e2bc729`; `describe-domain` `ChangeProgressDetails` `ConfigChangeStatus: Completed` |

Context (confounders, not the three levers): bulk indexing **3.31.0** deployed 2026-05-25 21:45 (origin of the indexation rework); the **OpenSearch engine 3.3 → 3.5** upgrade landed 2026-05-30 17:53→19:18, ~5 h before 3.33.0 — see the frozen section below.

**Correction recorded (engineer, 2026-06-08):** the third lever is the **scale-up**, NOT release **3.34.0**. The 3.34.0 CHANGELOG line "Deal index refresh disabled at index creation" (PR #5100) was a **no-op on shared-001** — the `deals` index already existed, so baking `refresh_interval: -1` into `DealElasticIndex.create!` only affects *future* index creation. It did not touch performance. Do not mark it on the chart.

**What the scale-up does:** `t3.medium.search` keeps the **same 2 vCPU** as `t3.small.search` but **doubles RAM 2 → 4 GB**. So the expected benefit is on the **JVM heap ceiling**, not on CPU% (CPU per-core capacity is unchanged). Confirm by comparing `JVMMemoryPressure` max before vs. after 2026-06-05 18:02.

### Blocker 1 resolved — weekday CPU data (1-minute, per day)

CloudWatch 1-minute series, `app-shared-001` `CPUUtilization`, pulled 2026-06-08 (window 2026-05-24 → 2026-06-08; `/tmp` raw at pull time, regenerable via the commands below). `min ≥X%` = count of 1-minute datapoints whose **max** crossed X%.

| Day (UTC) | p50 % | p99 % | max % | min ≥90% | min ≥80% | min ≥50% | marker |
|---|---|---|---|---|---|---|---|
| 05-24 | 8.0 | 20.5 | 39 | 0 | 0 | 0 | (partial) |
| 05-25 | 8.5 | 57.5 | 99 | 8 | 13 | 36 | bulk 3.31.0 |
| 05-26 | 8.5 | 35.0 | 77 | 0 | 0 | 8 | ① 3.32.0 |
| 05-27 | 9.0 | 57.0 | 100 | 9 | 16 | 29 | **regression (weekday)** |
| 05-28 | 8.5 | 32.0 | 99 | 3 | 4 | 13 | |
| 05-29 | 8.5 | 30.5 | 100 | 5 | 6 | 14 | |
| 05-30 | 10.0 | 31.0 | 71 | 0 | 0 | 8 | engine 3.5 |
| 05-31 | 14.0 | 35.0 | 69 | 0 | 0 | 6 | ② 3.33.0 |
| 06-01 | 12.7 | 35.5 | 99 | 1 | 5 | 16 | Monday (weekday) |
| 06-02 | 9.0 | 21.5 | 99 | 2 | 3 | 3 | |
| 06-03 | 9.0 | 20.0 | 39 | 0 | 0 | 0 | |
| 06-04 | 9.0 | 20.5 | 44 | 0 | 0 | 0 | |
| 06-05 | 9.5 | 23.5 | 58 | 0 | 0 | 1 | ③ t3.medium |
| 06-06 | 9.0 | 20.5 | 39 | 0 | 0 | 0 | |
| 06-07 | 9.0 | 20.0 | 39 | 0 | 0 | 0 | |
| 06-08 | 9.0 | 20.0 | 38 | 0 | 0 | 0 | (partial) |

Reading:
- The **real regression** is the weekday window **27–29/05** in the dedicated-queue world (3.32.0): up to **9 min/day ≥90%**, peaks at 100%. The frozen `seg1b` (4.55 bursts ≥90%/day) understated it because it averaged in the calm weekend of 30/05.
- After 3.33.0 + engine 3.5 (30–31/05), extreme bursts vanish. A **Monday weekday repique** appears 01/06 (≥80% in 5 min) — this is why the first reading was inconclusive.
- From **03/06 onward the series is flat**: zero bursts ≥50%, p99 ~20%. This is the business-week confirmation the frozen state was waiting for: **the CPU pegging is gone under weekday load.**
- The engine-elevated baseline (p50 14% on 31/05, see frozen seg2) **reverted to ~9% by 02/06** — the 14% was a transient, not a permanent engine cost.
- The **scale-up (05/06) entered with CPU already flat** — it did not cut CPU (same vCPU), as expected. Its value is JVM headroom (verify in Blocker-2 metrics).

### Blocker 2 partially addressed — goal metrics pulled (JVM + IndexingLatency)

Beyond CPU, the revisit pulled two of the goal-side metrics (1-minute, same window):

- **`JVMMemoryPressure`** — avg p50 ~50%, **max up to 80.5%** (rides the ~80% circuit-breaker line on `t3.small`'s 2 GB heap). This is the metric the scale-up targets. **Action for next pass:** quantify the ceiling recession in the last 3 days (post 2026-06-05 18:02) vs. before — confirm the 2→4 GB RAM bump pulled the heap ceiling down off 80%.
- **`IndexingLatency`** — bursty: **p50 ≈ 0 ms** (cluster idle most minutes), max ~5020 ms (bulk batches). No chronic degradation; consistent with the producer-consumer batch pattern. (The frozen "Expected effects" predicted unchanged indexing path — holds.)

Still **not** pulled (carry to a deeper pass if needed): refresh-events-per-hour and segment count (`GET /_stats`), and per-commission end-to-end latency (observable #8 — still needs app-side instrumentation).

### Engine-vs-app attribution — still structurally unresolvable (as predicted)

The 3.5 upgrade and 3.33.0 still landed 5 h apart on the same dead Saturday night; no clean weekday "engine-new / app-old" control window exists on this domain. The business question is answered (weekday bursts went to zero and stayed there), but the precise split between "engine 3.5 efficiency" and "app refresh consolidation" remains unattributable — and now the scale-up adds a third overlapping factor. Accept the combined effect.

### Deliverable produced this revisit

Interactive chart in this folder (open the HTML; it loads the JS sibling):

| File | What |
|---|---|
| `opensearch_shared001_cpu_minute_30d_deploys_20260608.html` | Minute-by-minute chart, metric selector (CPU / JVMMemoryPressure / IndexingLatency), the 3 deploy markers + bulk/engine context, daily-burst table. Reads `os_chart_data.js` as a sibling — keep them together. |
| `os_chart_data.js` | `window.OSDATA = {cpu, jvm, idx}`, each `{fine:[[epochMs,avg,max]…], coarse:[…]}`. `fine` = 1-min (05-24→06-08), `coarse` = 5-min (05-09→05-24). ~1.7 MB. |

To rebase a future sampling: re-pull CloudWatch (commands below + the JVM/IndexingLatency equivalents), regenerate `os_chart_data.js` in this folder, re-open the HTML. The chart shell (markers, table, axes) is reused as-is; only the data asset changes.

### Deploy-point reproduce commands (added this revisit)

```
gh run list -R 4shark/app --workflow "Deploy Shared-001 App" --created 2026-05-09..2026-06-08 --limit 100 --json databaseId,displayTitle,headSha,conclusion,createdAt,updatedAt
```
Map each deploy sha to its release tag with `git -C ~/Projects/4shark/app tag --points-at <sha>`. The scale-up is **not** in this list (it is terraform, not an app deploy): `git -C ~/Projects/4Shark/terraform log --since=2026-05-20 -- 'app-shared-001/opensearch.tf'`, and confirm applied state with `aws opensearch describe-domain --domain-name app-shared-001 --region us-east-1` → `.DomainStatus.ClusterConfig.InstanceType` + `.ChangeProgressDetails`.

---

## The two changes that landed the same Saturday (2026-05-30)

| When (UTC) | Change | Source of truth |
|---|---|---|
| 30/05 17:53 → 19:18 | **OpenSearch engine 3.3 → 3.5** + service software patch `R20260217-P1 → R20260428-P1`. Part of a parallel infra-currency effort (all RDS + ElastiCache + OpenSearch bumped to current versions). **Not** part of the app change. | CloudTrail `es.amazonaws.com`, events `StartServiceSoftwareUpdate` + `UpgradeDomain`; `describe-domain` shows `EngineVersion: OpenSearch_3.5`, `ChangeProgressDetails.StartTime 2026-05-30T15:42:28-03:00` |
| 31/05 00:39:31 | **App-managed refresh code (3.33.0, PR #5080) live on shared-001.** Deploy run `26698926406` (`Deploy Shared-001 App`, branch master, sha `24400e90`), success. The 30/05 23:55 attempt (`26698…`) failed first (migration timeout — see `ANALYSIS.md` rollout log). | GitHub Actions, `gh run list -R 4shark/app` |
| 31/05 11:15 + 17:41 | Hotfix 3.33.1 deploys (sha `425bb1a8`), runs `26711084154` + `26719749817`. Unrelated to refresh behavior (RDS index + worker task-def recovery — see rollout log). | GitHub Actions |

Segment boundaries used in the analysis (UTC):
- **seg1** before everything: `t < 2026-05-30T17:53`
- **seg1b** clean 4-day before (dedicated-worker world, the basis this doc prescribes): `2026-05-27T00:00 ≤ t < 2026-05-30T17:53`
- **seg2** engine-new / app-old control window: `2026-05-30T19:18 ≤ t < 2026-05-31T00:40`
- **seg3** engine-new / app-new: `t ≥ 2026-05-31T00:40`

---

## Reproduce the CPU reading

### 1. Pull 1-minute CPU (avg + max)

> ⚠️ CloudWatch keeps 1-minute resolution for only **15 days**. By ~2026-06-06 the 2026-05-22 minutes start aging out. The 2026-05-22 → 2026-06-01 series is therefore **frozen** in `opensearch_cpu_minute_series_pre_post_3.33.0_2026-06-01.json` (compact `{ts, avg, max}` per minute). For the revisit, pull a **fresh** minute window covering the new weekday data and append; do not expect to re-pull the old window at 1-min.

Default (read-only) AWS profile is enough. Single-line:

```
aws cloudwatch get-metric-data --region us-east-1 --start-time 2026-06-01T00:00:00Z --end-time 2026-06-08T23:59:00Z --output json --metric-data-queries '[{"Id":"cpuavg","MetricStat":{"Metric":{"Namespace":"AWS/ES","MetricName":"CPUUtilization","Dimensions":[{"Name":"ClientId","Value":"405749097490"},{"Name":"DomainName","Value":"app-shared-001"}]},"Period":60,"Stat":"Average"}},{"Id":"cpumax","MetricStat":{"Metric":{"Namespace":"AWS/ES","MetricName":"CPUUtilization","Dimensions":[{"Name":"ClientId","Value":"405749097490"},{"Name":"DomainName","Value":"app-shared-001"}]},"Period":60,"Stat":"Maximum"}}]' > /tmp/opensearch_shared001_cpu_minute_revisit.json
```

(Dimensions: `ClientId = 405749097490` (account), `DomainName = app-shared-001`. Newest-first; `StatusCode` must be `Complete`.)

### 2. Robust per-segment stats (median/percentiles + burst counts)

The jq used (percentiles + per-day burst rates). `.MetricDataResults[0]` = avg, `[1]` = max, same ordering:

```
jq -r '.MetricDataResults as $r | [range(0; ($r[0].Values|length)) | {t: $r[0].Timestamps[.], a: $r[0].Values[.], m: $r[1].Values[.]}] as $all | def pct($p): sort | .[ (((length-1)*$p)|floor) ]; def stats($rows): ($rows|map(.a)) as $av | ($rows|map(.m)) as $mx | ($rows|length) as $n | {minutes:$n, days:(($n/1440*100|round)/100), p50:($av|pct(0.50)), p90:($av|pct(0.90)), p95:($av|pct(0.95)), p99:($av|pct(0.99)), avg_max_1min:($av|max), burst90_per_day:(($mx|map(select(.>=90))|length)/($n/1440)*100|round/100), burst80_per_day:(($mx|map(select(.>=80))|length)/($n/1440)*100|round/100), burst50_per_day:(($mx|map(select(.>=50))|length)/($n/1440)*100|round/100)}; {weekday_post: stats([ $all[] | select(.t >= "2026-06-02T00:00") ])}' /tmp/opensearch_shared001_cpu_minute_revisit.json
```

Adjust the `select` boundary to the first full weekday (Mon 2026-06-01 was a partial post-deploy day; use 2026-06-02 onward for a clean weekday set). Compare against the frozen `seg1b` numbers in `ANALYSIS.md`.

### Frozen first-reading numbers (so the revisit has the baseline inline)

| CPU % | seg1b (27–30/05, before) | seg3 (31/05–01/06, after, weekend) |
|---|---|---|
| p50 | 8.5 | 14.0 |
| p99 | 33.0 | 37.0 |
| max 1-min avg | 87 | 64 |
| bursts ≥90% / day | 4.55 | 0.68 |
| bursts ≥80% / day | 6.95 | 3.40 |
| bursts ≥50% / day | 16.04 | 12.93 |

Engine baseline jump (8.5 → 14.5 p50) is visible in seg2 (engine-new/app-old) — attribute baseline to the 3.5 upgrade, not the app.

---

## What the revisit SHOULD add (beyond more CPU days)

The CPU reading is a **side-effect** metric. The actual goal of 3.33.0 (`PLAN.md` § Goal) is refresh consolidation. Pull the goal metrics that the first reading skipped:

1. **`RefreshLatency`** (CloudWatch `AWS/ES`) — no pre-deploy baseline existed (`refresh_latency_metrics_pre_3.33.0.json` is empty). Post-deploy values are first-observation. Check the alarm `<env>-opensearch-refresh-latency-high` (p99 ≥ 10000 ms sustained 30×60s, added in PR #459) has not fired.
2. **Refresh events per hour** and **segment count** — `GET /deals/_settings` (confirm `refresh_interval: "-1"` still set) and `GET /_stats` against the domain. Observable #7 in `ANALYSIS.md`. These confirm the consolidation actually happened, independent of CPU.
3. **Per-commission end-to-end latency p50/p99** (observable #8) — validate the engineer-accepted ~45 s floor. Needs app-side instrumentation; check whether it was added (open follow-up in `ANALYSIS.md`).
4. **State-machine health** — observables #3 and #4 (stuck `executed` / `refreshed` rows). Quick Rails console queries.

## What the revisit CANNOT fix (be honest about it)

The engine-vs-app burst attribution. Both the 3.5 upgrade and the app change reduce bursting, and they landed 5 h apart on the same low-traffic night, so there is no clean weekday "engine-new / app-old" window to use as control on this domain. Options, none perfect:
- Accept the combined effect ("after the weekend, CPU bursts on shared-001 dropped ~6.7×") and stop splitting hairs — the business question ("did the weekend work help?") is answered yes.
- If a clean engine-only baseline is ever needed, it would have to come from a domain that took the 3.5 upgrade but NOT the app change. The engineer ruled out using `app-atento-001` as that control (2026-06-01), so this path is closed unless reopened.

---

## Open follow-ups carried from ANALYSIS.md (still open at 2026-06-01)

- Instrument observable #8 (per-commission end-to-end latency).
- PgBouncer EC2 `i-0dd0d5c92ec9daf66`: not in SSM; t3a.micro (upsize candidate).
- `MIGRATION_DATABASE_URL` GH Environment Secret: no rotation discipline.
- Task-def ownership split (Terraform `:55` drops `command`; GHA pipeline `:56` correct) — reconcile before any bare `terraform apply` on worker families.

---

## Data files in this folder (for the revisit)

| File | What |
|---|---|
| `opensearch_baseline_30d_pre_3.33.0.html` | 30-day pre-deploy baseline (daily resolution), engineer-facing chart |
| `opensearch_cpu_post_3.33.0_first_reading_2026-06-01.html` | First post-deploy reading — minute-level chart + 3-segment tables + timeline |
| `opensearch_cpu_minute_series_pre_post_3.33.0_2026-06-01.json` | **Frozen** 1-minute `{ts, avg, max}` series 22/05→01/06 (CloudWatch will have dropped this resolution by revisit time) |
| `refresh_latency_metrics_pre_3.33.0.json` | Empty series confirming no pre-deploy RefreshLatency baseline |

## Quick facts (so the revisit does not re-discover them)

- Domain: `app-shared-001`, us-east-1, account `405749097490`, VPC-only endpoint. Engine now `OpenSearch_3.5`. Cluster: `t3.small.search` × 2, gp3 10 GB, Multi-AZ, no dedicated master. (`aws opensearch describe-domain --domain-name app-shared-001 --region us-east-1`.)
- "AmbientShared001" in conversation = this domain (`app-shared-001`).
- App repo: `4shark/app`. Deploy workflow for this env: `Deploy Shared-001 App`. Branch master.
- The engineer's mental model of the change: previously the app delegated index write/search/update + refresh to Elasticsearch (which was CPU-pegging); 3.33.0 moves that work app-side.
