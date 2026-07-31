# SPIKE — The productive app writer saturates CPU daily

## Status

**Open, not started.** This document currently holds the evidence that opened the question and nothing more. It was carved out of the Aurora-versus-RDS spike, where the saturation was found incidentally while measuring utilization for a cost comparison.

Deliberately deferred until the KMS key-per-environment migration finishes, so that any resize decision is made against a settled database rather than one mid-migration.

## Question

`app-shared-001`'s writer instance averages 18–22% CPU and reaches 99–100% every single day. Why, and does it need a different instance class?

Three sub-questions, in the order they should be answered:

1. **What runs during the peaks?** A daily peak on a database whose workload includes nightly chained processing suggests a scheduled job rather than user traffic, but nothing here establishes that.
2. **Is the peak harmful or is it the instance working as intended?** A burstable class is designed to burst. Reaching 100% is only a problem if CPU credits are being exhausted, or if latency during the peak affects anything a user or a job waits on.
3. **Is a burstable class the right choice for a productive writer at all?** This is the design question behind the other two.

## The evidence that opened it

Measured over seven days, 2026-07-21 to 2026-07-27, from CloudWatch, on `app-shared-001-db-1` (the writer).

| Day | Average CPU | Maximum CPU |
|---|---|---|
| 2026-07-21 | 20.01% | 99.08% |
| 2026-07-22 | 19.92% | **100.00%** |
| 2026-07-23 | 18.24% | **100.00%** |
| 2026-07-24 | 17.47% | 98.93% |
| 2026-07-25 | 17.24% | 99.08% |
| 2026-07-26 | 18.01% | 99.05% |
| 2026-07-27 | 22.16% | 99.13% |

Seven days out of seven above 98.9%, two of them at exactly 100%. The average sitting at a fifth of capacity is what makes it a shape worth explaining rather than a straightforward under-provisioning: the instance is idle most of the time and pinned briefly, every day.

Supporting context from the same measurement window:

- The instance class is `db.t4g.large` — burstable, 2 vCPU, 8 GiB.
- Write I/O on the cluster is 29.0M requests per week, roughly 4.15M/day, or about 48 IOPS averaged. That is a low sustained rate, consistent with the CPU profile: bursty rather than saturated.
- Reads are almost entirely served from the buffer cache — 245 thousand billed read I/Os in the week against those 29 million writes.
- The reader instance holds a steady 10 connections, maximum 12, so read traffic is present but small.

## What has NOT been established

Everything that matters. Named explicitly so the next session does not mistake the evidence above for a diagnosis:

- **What the peaks are.** No query, job, or time-of-day correlation has been looked at.
- **Whether CPU credits are being exhausted.** `CPUCreditBalance` / `CPUSurplusCreditBalance` were not sampled. Without them, "reaches 100%" does not distinguish healthy bursting from credit starvation, and that distinction is the whole question.
- **Whether latency suffers during the peaks.** Not measured on either the database or the application side.
- **Whether `atento-001` shows the same shape.** Only `shared-001` was sampled. If the pattern is common to both, it points at the application; if it is unique to one, it points at that environment's data or tenants.

## Where the data is, and a deadline on it

Performance Insights is enabled on every productive instance with a 31-day retention, so the peaks of the sampled week are still queryable and the top SQL during them is recoverable.

**Performance Insights reaches end of life on 2026-07-31.** AWS states that clusters using it default to the Standard mode of CloudWatch Database Insights with the existing retention preserved, and that Terraform configuration and API parameters continue to work unchanged — so the data is not lost. But the console experience redirects after that date, so anyone picking this up should expect to be in Database Insights rather than the Performance Insights console, and should not read the difference as the data having gone.

## Why this is not an engine question

The Aurora-versus-RDS spike is what surfaced this, and the conclusion there was that the engine does not change: the workload produces these peaks on whichever engine runs it. One caveat is worth carrying forward rather than dropping — Aurora offloads some storage-layer work that a plain instance performs itself, which is widely stated and was not verified. On an instance already touching 100%, that difference would matter. It is recorded here only so that a future engine discussion does not restart from zero, not as a reason to reopen the decision.
