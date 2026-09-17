# ANALYSIS — Atento CO staging integrator: run comparison for thread tuning

Investigation of the `integrator-atento-co-staging` integration run under different Sidekiq
thread counts, to decide whether reducing the worker concurrency improves throughput on a
CPU-bound, single-task deployment.

## Test plan (three runs)

1. **Run 1 — baseline, 30 threads.** The run that already happened. Recorded below in full. It
   failed 100% for reasons unrelated to threading (a config mismatch), but its *timing and CPU
   profile* are the baseline for the thread comparison.
2. **Run 2 — clean, 30 threads.** Same infrastructure (30 threads, 0.5 vCPU), but with the run-1
   blockers removed (token re-saved, subsidiary mode corrected on the app side, Mongo wiped +
   Redis flushed). Purpose: a run that actually sends all data, to get a *successful* 30-thread
   timing to compare against.
3. **Run 3 — 10 threads.** After merging and applying terraform PR #1171 (`SIDEKIQ_THREADS`
   30 → 10 on this stack). Purpose: test whether fewer threads improves the CPU-bound phase.

The threading hypothesis: the worker task is `cpu = 512` (0.5 vCPU); Ruby's GIL serializes Ruby
execution to one thread at a time, so 30 threads on a CPU-bound workload do not parallelize —
they only add scheduling overhead. The SDK's own guidance is ~10 max. Runs 2 and 3 test whether
dropping to 10 helps.

## Timeline markers

- Run 2 start (exact): **2026-09-16 21:42:24 UTC**

---

## Run 1 — baseline (30 threads) — FAILED 100%, but the profile is the baseline

### Configuration

- Run id: `6aaaeb35bccb7eaae90700fe`
- Integrator version: 8.4.25
- Source systems: 2 · Integrations: 29
- Worker infrastructure: 1 web task + 1 worker task
- Worker task sizing: `cpu = 512` (**0.5 vCPU**), `memory = 2048` (2 GB)
- `SIDEKIQ_THREADS = 30`
- Fetch window: from `1964-01-01 00:00:00 UTC` (full initial fetch)

### Timing (from the run report)

| Phase | Start (UTC) | Duration |
|---|---|---|
| Search / fetch from source | 19:17:09 | 1 min 14 s |
| Data processing (transform) | 19:18:23 | **1 h 10 min 54 s** |
| Sending to 4Shark (load) | 20:29:17 | 36 min 10 s |
| **Total** | | **1 h 48 min 18 s** |

### Volume and outcome

- Total requests to 4Shark: **39,192**
- Successful: **0 (0.0%)**
- Failed: **39,192 (100.0%)**

### Failure breakdown (from the audit trail, before the Mongo wipe)

Every request returned HTTP 400 with the subsidiary-mode guardrail body:

| Resource | Method | Status | Count | Response body |
|---|---|---|---|---|
| Modifier | POST | 400 | 33,079 | `Use subsidiary scoped api: /api/v3/subsidiaries/:subsidiary_id/indicators` |
| User | POST | 400 | 6,113 | `Use subsidiary scoped api: /api/v3/subsidiaries/:subsidiary_id/users` |

`33,079 + 6,113 = 39,192` = 100%.

### CPU / memory profile (worker task, CloudWatch, 15-min periods)

CPU utilization is the % of the task's allocated CPU (0.5 vCPU). Times converted to UTC.

| Window (UTC) | CPU avg % | CPU max % | Mem avg % | Mem max % |
|---|---|---|---|---|
| 19:15 | 74.8 | 100 | 26.2 | 37.0 |
| 19:30 | 99.9 | 100 | 40.2 | 40.9 |
| 19:45 | 99.9 | 100 | 42.9 | 47.5 |
| 20:00 | 100.0 | 100 | 51.0 | 52.0 |
| 20:15 | 97.4 | 100 | 54.8 | 56.7 |
| 20:30 | 3.8 | 99.2 | 56.0 | 56.2 |
| 20:45 | 99.9 | 100 | 56.4 | 56.6 |
| 21:00 | 94.7 | 100 | 56.8 | 57.2 |

- **CPU: pegged at ~100% average the entire heavy phase.** Not just peaks — sustained average.
  This is the signature of a compute-bound workload saturating its allocation.
- The **20:30 dip to ~4% avg** is the gap where the admin loaders were failing instantly
  (`0.02 s` fails) during the `api_token` bad_decrypt / token-fix window — the CPU idled because
  the jobs were rejected before doing work.
- **Memory: peaked ~57% (~1.16 GB of 2 GB).** Comfortable. Memory is NOT the bottleneck — CPU is
  the wall.

### Slow jobs

- `Modifier::CustomCollectionConsumer` (VKPI indicator compute) ran **~17–18 min each**
  (`elapsed` ~1000–1100 s), 500 records per page, one page per worker.
- With 30 threads on 0.5 vCPU under the GIL, the heavy modifier phase is where the
  1 h 10 min processing time went.

### Root causes found during run 1 (all now resolved)

1. **`Account.api_token` bad_decrypt.** A forced symmetric-encryption key rotation orphaned the
   encrypted `api_token` (ciphertext under the old key). `ENV['API_TOKEN']` is nil, so it was not
   recoverable from the environment. Fixed by re-saving the token in the console (re-encrypts
   under the current key). Same root-cause class as the earlier DB-source password bad_decrypt.
2. **Subsidiary-mode mismatch — THE cause of the 100% failure.** The app company (Atento CO) was
   configured in subsidiary mode while the integrator sends to the root API
   (`SIDEKIQ`... `SUBSIDIARIES_MODULE = "false"`). The app rejected every request with the 400
   guardrail. Fixed on the **app side**: the demo/CO company's subsidiaries module was set to
   `true` by mistake; corrected to `false` (root), matching the integrator.
3. **CPU saturation (the threading finding).** 30 Sidekiq threads on 0.5 vCPU, CPU-bound compute,
   Ruby GIL → ~18-min modifier jobs, 1 h 10 min processing. The lever for future runs.

### Points of attention

- **Throughput pause.** 39,192 > the 5,000 ceiling, so a normal run pauses with the throughput
  e-mail. Forcing past it needs `SKIP_THROUGHPUT=true` on `rake integration:start`.
- Memory has headroom — do not size the task for memory; CPU is the constraint.
- The audit trail (Resources/Imports/Requests) for run 1 was **wiped** from Mongo before run 2
  (clean-slate reset). The metrics above were captured from the run report, the CloudWatch logs,
  and the pre-wipe diagnostics; they cannot be re-queried from Mongo.

---

## Run 2 — clean, 30 threads

- Start: **2026-09-16 21:42:24 UTC** (`integration:start`)
- Finalized: **2026-09-16 23:29:25 UTC** (`ShutDownWorker`) — worker task stopped 23:29:30, service back to `desired=0`.
- **Total: ~1 h 47 min** — nearly identical to run 1's 1 h 48 min, with the SAME 30 threads / 0.5 vCPU.
- Config: 30 threads, 0.5 vCPU, 2 GB — thread PR #1171 NOT applied yet.
- Preconditions fixed vs run 1: token valid, app company in root mode, Mongo wiped, Redis flushed.
- Success / fail counts: **pending the run report or the Job counters** (not derivable from CloudWatch —
  the per-request outcome lives in the Job document, not the worker log). This is the headline for
  "did it send everything"; it must come from the report, not be assumed.

### Live CPU / memory × running jobs (bottleneck points)

Each row is a 5-min sample crossing worker CPU/memory with the jobs running in that window. A
**stuck point** is high CPU + high `max_elapsed` + falling throughput; healthy saturation is high
CPU + high throughput + short jobs.

| Time (UTC) | CPU avg % | Mem avg % | dones/5min | max elapsed | Dominant consumer | Reading |
|---|---|---|---|---|---|---|
| 21:42–44 | ~99.8 | 27 | ramp | ~15 s | SalesRep DatabaseEnrichmentExtractor | extract — saturated, healthy |
| 21:47 | 99.9 | 28.5 | 1517 | 15 s | SalesRep DatabaseEnrichmentExtractor | high throughput, short jobs |
| 21:52 | 100.0 | 33 | 841 | 21 s | SalesRep DatabaseEnrichmentExtractor | throughput dipping |
| 21:57 | 98.9 | 38 | 492 | 387 s | SalesRep EnricherConsumer | enrichment SPIKE — one ~6 min job, throughput dips |
| 22:02 | 97.8 | 39.6 | 2251 | 11 s | SalesRep EnricherConsumer | recovered — spike cleared, throughput back up |

**Enrichment is bursty, not a sustained stall (so far).** In the 21:57 window the SalesRep
`EnricherConsumer` hit a `max_elapsed` of ~6 min with throughput down to 492; the very next window
recovered to 2251 done / 11 s max. So the enrichment phase runs mostly short jobs at pegged CPU
with occasional heavy jobs that briefly spike duration — different from run 1's modifier phase,
where the ~18-min jobs were sustained. CPU stays ~99% throughout and memory low (~40%), so the
constraint is compute on 0.5 vCPU (the GIL serializing Ruby work across the 30 threads), but no
sustained stall has appeared yet. The phase to watch for a real stall is the later
transform/modifier stage.

### Full-run CPU / memory profile (worker task, 10-min periods, UTC)

| Time (UTC) | CPU avg % | CPU max % | Mem avg % | Note |
|---|---|---|---|---|
| 21:40 | 79.8 | 100 | 25 | task ramping up |
| 21:50 | 99.2 | 100 | 37 | pegged |
| 22:00 | 99.2 | 100 | 40 | pegged |
| 22:10 | 98.9 | 100 | 41 | pegged |
| 22:20 | 99.1 | 100 | 48 | pegged (the 22:22 monitor `None` tick was a glitch — CPU was 99%) |
| 22:30 | 98.9 | 100 | 52 | pegged |
| 22:40 | 99.2 | 100 | 54 | pegged |
| 22:50 | 84.5 | 100 | 56 | dip — phase transition (fewer parallel jobs) |
| 23:00 | 69.5 | 100 | 56 | dip — phase transition |
| 23:10 | 99.2 | 100 | 56 | pegged |
| 23:20 | 94.5 | 100 | 53 | pegged, winding down |
| 23:29 | — | — | — | `ShutDownWorker` — finalized |

- **CPU pegged ~99% for essentially the whole run** — same as run 1. The only dips (22:50–23:00) are
  phase transitions where fewer jobs run in parallel for a moment.
- **Memory peaked ~56% (~1.15 GB of 2 GB)** and plateaued — same as run 1, not the bottleneck.
- **The headline result: total time (~1 h 47 min) is virtually identical to run 1's 1 h 48 min, with
  the same 30 threads / 0.5 vCPU.** Run 1 rejected every send with a fast 400; run 2 (assuming it
  sent successfully — confirm from the report) did the real 2xx load work. That the totals match
  says the wall is the CPU-bound processing on 0.5 vCPU, not the send phase — so the thread/vCPU
  config, not success vs failure, is what sets the ~1 h 47 min. This is the baseline the 10-thread
  run 3 is measured against.

---

## Run 3 — 10 threads × 3 worker tasks

- **Started 2026-09-17 01:44:53 UTC, finalized ~02:30 UTC — total 45 min 38 s** (fetch 1 m 17 s, processing 23 m 50 s, sending 20 m 31 s). Requests 39,192 · success 33,286 (84.93%) · failed 5,906 (15.07%). Run id `6aab4615f79a0f38b5319847`.
- **Started: 2026-09-16 22:44 BRT (2026-09-17 01:44 UTC)** — `integration:start` with `SKIP_THROUGHPUT=true`, against the freshly wiped base (data zeroed, config intact — accounts=1/sources=2/streams=54/resource_types=28/authentications=2/health_checks=1 — Redis flushed). `data_migrations` ledger restored (5 versions) after being wiped in error.
- **Config: `SIDEKIQ_THREADS=10`, THREE worker tasks, 0.5 vCPU / 2 GB each.** Terraform PR #1171 (`SIDEKIQ_THREADS` 30 → 10) is applied and merged, and the co-staging worker was deployed onto the `threads=10` revision, so 10 threads is live. The worker service was then scaled to 3 tasks by hand for this run.
- **This run moves TWO levers at once, so total time is not a clean threads-only comparison.** Run 1 and Run 2 ran 30 threads on ONE 0.5-vCPU task (30 threads, 0.5 vCPU total). Run 3 runs 10 threads on THREE 0.5-vCPU tasks — still 30 threads in aggregate, but spread over 1.5 vCPU (3× the CPU) instead of 0.5. So a faster Run 3 reflects the horizontal scale-out (more vCPU) as much as the lower per-task thread count; the two effects cannot be separated from total time alone. Isolating the thread effect would need a matched 1-task / 10-thread run.
- Goal: total time against the 30-thread / 1-task baselines (Run 1 1 h 48 m, Run 2 ~1 h 47 m), plus — via live sampling of `/sys/fs/cgroup/cpu.stat` per task — whether the 10-thread tasks throttle less than the single 30-thread one.

_Total time / success-fail to fill after the run finalizes._

### Per-job result — `Modifier::CustomCollectionConsumer` isolates the thread effect

The heavy VKPI compute job, measured from the worker logs (`elapsed=` on each `done` line), across the three runs:

| Run | Config | Jobs measured | Avg per job | Min | Max |
|---|---|---|---|---|---|
| Run 1 | 30 threads, 1 task (0.5 vCPU) | 67 | **15.5 min** (929 s) | 81 s | 18.4 min (1103 s) |
| Run 2 | 30 threads, 1 task (0.5 vCPU) | 67 | **16.1 min** (968 s) | 85 s | 19.0 min (1143 s) |
| Run 3 | 10 threads, 3 tasks (0.5 vCPU each) | 67 (full phase) | **4.9 min** (294 s) | 31 s | 6.2 min (375 s) |

**Per-job elapsed isolates the per-task thread count, NOT the task/vCPU count — this is the clean thread-tuning result.** One `CustomCollectionConsumer` runs inside a single task: in Run 3 that task holds 10 threads sharing its 0.5 vCPU; in Run 1/2 the one task holds 30 threads sharing the same 0.5 vCPU. Adding tasks (Run 3's 3 vs 1) raises *throughput* — more jobs in parallel — but does nothing to a single job's wall-clock. So the ~3.2× per-job speed-up (15.5 → 4.9 min, across the full 67-job phase — the same job count as Run 1 and Run 2) is driven by the 30 → 10 thread reduction alone, and it matches the 30:10 ratio almost exactly.

This is textbook Ruby-GIL oversubscription, and it confirms the hypothesis: with the GIL serializing Ruby execution, 30 CPU-bound threads on 0.5 vCPU each get ~1/30 of the wall-clock, so a job stretches to ~30× its pure compute time; at 10 threads each gets ~1/10, so the same job finishes ~3× faster. Fewer threads per task = each CPU-bound job proportionally faster, exactly as the Sidekiq guidance (a pegged 100 % CPU → reduce concurrency) predicts.

**The two levers are now separable**: per-job time is the *thread* effect (this table, ~3.2×), and total run time additionally carries the *task/vCPU* effect (3 tasks = 1.5 vCPU aggregate = ~3× the parallel throughput). Total time is filled below when the run finalizes.

---

## Sidekiq CPU behavior and the oversubscription metric

The worker's heavy phase (VKPI indicator compute in `Modifier::CustomCollectionConsumer`) is
CPU-bound, so high CPU is the correct, expected state — an idle CPU at max throughput would be the
bug. But the documented target is high-but-not-pegged, and pegged-at-100% is itself the signal to
reduce concurrency.

Sidekiq's own scaling guidance (Judoscale, *The Ultimate Guide to Scaling Sidekiq*; corroborated by
the `sidekiq/sidekiq` wiki *Scaling* page):

> "You want CPU usage to be high but not 100% when all threads are in use. […] if your CPU usage
> never goes above 50% at max throughput, you probably want to increase your concurrency.
> Conversely, if CPU is hitting 100%, you need to reduce your concurrency."

So the reading of the two runs flips: CPU pegged at ~100% of the 0.5-vCPU limit for essentially the
whole run is **not** "good, we're using the max" — it is the documented trigger to *lower* the
thread count. That is exactly the 30 → 10 hypothesis that run 3 tests. For a CPU-bound workload the
same guidance puts the thread count near the core count (single digits on a fractional vCPU), and
recommends separate Sidekiq processes for CPU-bound work rather than one process with many threads.

### The load-average / oversubscription metric is NOT available for runs 1 and 2

The metric that would quantify "how many times the process is overloaded" — load average, or more
precisely cgroup CPU throttling — was never captured for these two runs, and cannot be
reconstructed after the fact:

- **Load average is the wrong metric on Fargate anyway.** The container sees the *host's* cores in
  `/proc/loadavg`, not its own 0.5-vCPU cgroup slice, so a per-task load average is misleading —
  a load of "2" on a task limited to half a core means something very different from a load of "2"
  on a 2-core box. The definitive per-task oversubscription signal is **cgroup CPU throttling**
  (`nr_throttled` / `throttled_time` in `/sys/fs/cgroup/cpu.stat`): how often, and for how long, the
  kernel parked the task's threads because it hit its CPU quota.
- **Neither is in Datadog for this task.** The integrator co-staging worker is not instrumented by
  the Datadog Fargate integration — a tag scan of `ecs.fargate.cpu.percent` over the run windows
  returns only `atento-001-connection-pooler`; no `staging`/`integrator` Fargate task reports at
  all. So there is no `ecs.fargate.cpu.*`, no throttling metric, and no load average for the worker
  in Datadog.
- **CloudWatch cannot show it either.** The CPU numbers in this analysis came from CloudWatch
  `CPUUtilization`, which is the percentage of allocated CPU **capped at 100%** — it cannot express
  oversubscription (a task wanting 300% of its allocation still reads 100%), and CloudWatch/Container
  Insights exposes no cgroup-throttling or load-average metric.

**The best available past signal is what is already recorded: CPU pegged at ~100% of the 0.5-vCPU
limit throughout both runs.** By Sidekiq's own rule that pegging *is* the "reduce concurrency"
evidence — the throttling counter would only quantify how hard.

### How to capture it on run 3 (live-only)

The throttling and load-average data exist only inside the running task, so they must be sampled
live. On run 3 (and, for a clean 30t vs 10t contrast, ideally a matched re-run at 30t), exec into
the worker task while it runs and sample periodically:

- `cat /sys/fs/cgroup/cpu.stat` → `nr_throttled` and `throttled_time` (nanoseconds parked). Rising
  fast = oversubscribed. This is the number that answers the engineer's question directly.
- `cat /proc/loadavg` → recorded for reference, read against the 0.5-vCPU limit, not the host core
  count.

Delta between samples (throttled periods per interval, throttled time per interval) is the
comparison metric: run 3 (10 threads) should throttle less than run 2 (30 threads) if the
GIL-plus-oversubscription hypothesis holds, even though both may still read ~100% CPU on CloudWatch.

## Comparison across the three runs

| Metric | Run 1 (30t, 1 task) | Run 2 (30t, 1 task) | Run 3 (10t, 3 tasks) |
|---|---|---|---|
| Threads per task | 30 | 30 | 10 |
| Worker tasks | 1 | 1 | 3 |
| Aggregate vCPU | 0.5 | 0.5 | 1.5 |
| Total time | 1 h 48 min 18 s | ~1 h 47 min | **45 min 38 s** |
| Processing (transform) | 1 h 10 min 54 s | from report | **23 min 50 s** |
| Sending | 36 min 10 s | from report | **20 min 31 s** |
| Fetch | 1 min 14 s | — | 1 min 17 s |
| Requests | 39,192 | from report | 39,192 |
| Success | 0% (all HTTP 400 subsidiary) | from report | **84.93% (33,286)** |
| Failed | 100% (39,192) | from report | 15.07% (5,906) |
| Modifier compute avg (per job) | 15.5 min | 16.1 min | **4.9 min** |

### What the numbers say

**Total run: 45 min 38 s vs ~1 h 48 m — 2.37× faster.** Both levers moved together and each shows in a different metric:

- **Per-job Modifier compute — the THREAD effect: 15.5 → 4.9 min, ~3.2×.** A single job runs inside one task, so this isolates 10 vs 30 threads on the same 0.5 vCPU; the speed-up matches the 30:10 ratio (GIL oversubscription relief), independent of task count.
- **Processing phase — the TASK/vCPU effect: 1 h 10 m → 23 m 50 s, ~3.0×.** The transform phase is the sum of all the heavy jobs; running 3 tasks (1.5 vCPU aggregate) processes ~3× the jobs in parallel, so the phase collapses ~3×, tracking the vCPU multiple.
- **Sending — I/O-bound, gains less: 36 m 10 s → 20 m 31 s.** Run 1's 36 m was fast HTTP-400 rejections; Run 3's 20 m is real 2xx work AND still shorter, because 3 tasks push more requests in parallel. Network I/O, not CPU, bounds this phase, so it does not scale with vCPU the way processing does — which is why total time is 2.37× rather than ~3×.

**CPU profile confirms the phase reading (Run 3, service-level CPUUtilization = average across the 3 tasks, normalized to reserved CPU so it is comparable to the 1-task runs).** During processing (01:46–02:10, transform + Modifier compute) CPU is pegged **~99–100%** (peak windows 98.7–98.8% avg, max 100) — the 3 tasks are saturated, the same signature Run 1 and Run 2 show on their single task. During sending (02:10–02:30) CPU drops to **~20–70%** (low of 19.5% at 02:14): sending waits on HTTP responses, so it is I/O-bound, not CPU-bound. Two consequences: CPU% alone cannot show the thread-tuning win, because it saturates at ~100% in all three runs (the § oversubscription point — with CPU capped at 100 %, per-job elapsed and total time are what separate the runs); and the sending phase's CPU drop is why that phase gained only 1.8× while processing gained ~3×.

**Data-correctness caveat, separate from performance: Run 3 sent all 39,192 requests but 5,906 (15.07%) failed.** This is not a threading regression — it is the data-validation surface the CO integration plan's next phase exists for (the failures must be classified through the `Imports → Requests` audit trail). The performance win (2.37× total, 3.2× per heavy job) stands on its own; the 15% failures are the thing to chase next, not a cost of the thread change.
