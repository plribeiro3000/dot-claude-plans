# SPIKE — Aurora PostgreSQL versus plain RDS PostgreSQL for the app stacks

## Question

Three of the four app stacks run Aurora PostgreSQL; `app-beta-001` already runs plain RDS PostgreSQL. If we moved everything to plain RDS: how much would we save, what Aurora features would we lose, and does our measured utilization actually use any of them?

## Answer up front

Across the three Aurora stacks the saving is **about USD 72/month**, and it is not distributed the way intuition suggests: it is **inversely proportional to how much data the stack holds**. `demo-001` (1.3 GB) would save a third of its bill; `shared-001` (343 GB) would save 1.8%.

The reason is the single most important fact in this spike: **an Aurora replica adds no storage cost, an RDS replica pays for a full second copy.** That is what eats the instance-price advantage on the large stack.

And the comparison above is **not between equivalent things**, which is the finding that should decide this. Aurora's two-instance cluster fails over automatically. RDS Single-AZ plus a read replica does not — promotion is manual. Buying automatic failover back on RDS means Multi-AZ, whose storage alone is USD 0.23/GB-month against Aurora's 0.10, and that erases the saving and then some.

Separately, the measurement turned up something that costs more than this whole question: **the writer's CPU reaches 99–100% every single day** on a burstable instance class.

## Prices used

All from the AWS Price List API, `us-east-1`, publication date 2026-07-29. Not estimates and not from memory — the API is the same source the console bills from.

| Item | Aurora PostgreSQL | RDS PostgreSQL | Delta |
|---|---|---|---|
| `db.t4g.large` Single-AZ, on-demand | USD 0.146/hr | USD 0.129/hr | −11.6% |
| `db.t3.medium` Single-AZ, on-demand | USD 0.107/hr | USD 0.072/hr | −32.7% |
| Storage | USD 0.10 /GB-month | USD 0.115 /GB-month (gp3) | +15% |
| Storage, Multi-AZ | — | USD 0.23 /GB-month | — |
| I/O | USD 0.20 per 1M requests | included in gp3 baseline | — |
| I/O-Optimized instance (`t4g.large`) | USD 0.19/hr | — | — |
| I/O-Optimized storage | USD 0.225 /GB-month | — | — |

Two things to read off this table before any arithmetic. Aurora's **instance** is dearer and its **storage** is cheaper per GB — so which engine wins depends entirely on the storage-to-compute ratio. And Aurora charges for I/O while gp3 does not, which sounds decisive until the I/O volume is measured.

## What the stacks actually do

Measured over seven days, 2026-07-21 to 2026-07-27, from CloudWatch.

| Stack | Instances | Engine | Volume | Write I/O / week | Read I/O / week |
|---|---|---|---|---|---|
| `app-shared-001` | 2 × `db.t4g.large` | Aurora PG 16.13 | 343 GB | 29.0M | 0.25M |
| `app-atento-001` | 2 × `db.t4g.large` | Aurora PG 16.13 | 36.5 GB | 25.2M | not sampled |
| `app-demo-001` | 1 × `db.t3.medium` | Aurora PG 17.9 | 1.3 GB | not sampled | not sampled |
| `app-beta-001` | 1 × `db.t3.micro` | **RDS PG 18.4** | 20 GB provisioned | — | — |

Two observations that matter more than the totals.

**Reads are almost free of I/O.** `shared-001` billed 245 thousand read I/Os in a week against 29 million writes — reads are being served from the buffer cache, so Aurora's per-I/O charge is essentially a write charge for us.

**Data size and write volume are uncorrelated across our stacks.** `atento-001` holds a tenth of `shared-001`'s data and does comparable write I/O. So neither metric alone predicts the bill.

## The arithmetic, per stack

730 hours per month. RDS figures assume the same instance count, each instance Single-AZ with its own gp3 volume sized at the current data volume.

### `app-shared-001` — saves 1.8%

| | Aurora today | RDS |
|---|---|---|
| Instances | 2 × 0.146 × 730 = **213.16** | 2 × 0.129 × 730 = **188.34** |
| Storage | 343 × 0.10 = **34.30** | 343 × **2** × 0.115 = **78.89** |
| I/O | ~124M × 0.20/M = **24.80** | **0** |
| **Total** | **272.26** | **267.23** |

The replica's second full copy of 343 GB costs USD 44.59/month, which almost exactly cancels the USD 24.82 saved on instances plus the USD 24.80 saved on I/O. Average write rate is roughly 48 IOPS, far inside gp3's 3000 baseline, so the I/O line genuinely goes to zero.

### `app-atento-001` — saves 17.5%

| | Aurora today | RDS |
|---|---|---|
| Instances | **213.16** | **188.34** |
| Storage | 36.5 × 0.10 = **3.65** | 36.5 × 2 × 0.115 = **8.40** |
| I/O | ~108M × 0.20/M = **21.60** | **0** |
| **Total** | **238.41** | **196.74** |

Same instance saving, but only USD 4.75 of extra storage to pay for it, because the dataset is small. USD 41.67/month.

### `app-demo-001` — saves about a third

| | Aurora today | RDS |
|---|---|---|
| Instance | 0.107 × 730 = **78.11** | 0.072 × 730 = **52.56** |
| Storage | 1.3 × 0.10 = **0.13** | 1.3 × 0.115 = **0.15** |
| **Total** | **~78.3** | **~52.7** |

The cleanest win, for two compounding reasons: a single instance means no duplicated storage at all, and the `t3.medium` price gap is 32.7% rather than 11.6%. Its I/O was not sampled, which would only widen the gap.

**Total across the three: roughly USD 72/month.**

## What we would lose

### Automatic failover — the one that invalidates the comparison

Aurora's two-instance cluster promotes the reader automatically and the writer endpoint follows it. RDS Single-AZ with a read replica has no such mechanism: promotion is an operator action.

This is not a feature we chose to buy — it is included in the Aurora price, and the RDS columns above quietly drop it. Restoring it means Multi-AZ, where the price table shows storage at USD 0.23/GB-month against Aurora's 0.10 — for `shared-001` that is 343 GB at 0.23, which alone exceeds the entire monthly saving before the higher Multi-AZ instance rate is counted.

So the honest framing is not "Aurora costs 1.8% more". It is **"Aurora costs 1.8% more and includes automatic failover plus a storage-free replica"**.

### Free replica storage

Already quantified above. Worth naming separately because it is the mechanism behind the inverse relationship: the more data a stack holds, the worse RDS looks, and the effect is linear in GB.

### The reader endpoint, which we do use

The pooler's follower connection points at `cluster_reader_endpoint` (`app-shared-001/main.tf:113`). Measured, that reader holds a steady 10 connections with a maximum of 12 — it is in use, not idle, which matches the pooler's configured `min_pool_size = 5` on that database.

RDS has an equivalent (point at the replica's own endpoint), so nothing breaks. What is lost is the indirection: the reader endpoint load-balances across multiple readers and re-points itself after a failover, whereas a replica endpoint is one fixed host.

### What Aurora offers that we demonstrably do not use

Global Database, Serverless v2, cloning, Backtrack (MySQL-only regardless), the 15-replica ceiling, and the 128 TB volume. None appear anywhere in the four stacks. If the decision were only about unused features, it would be easy — the cost table is what makes it not easy.

## The finding that is worth more than this question

`app-shared-001`'s writer instance averages 18–22% CPU and reaches **99–100% every single day** across the whole sampled week (maximum 100.0% on two of seven days).

That is a burstable instance class saturating daily. It is not an Aurora-versus-RDS matter — it follows the workload to whichever engine it runs on — and it plausibly costs more in latency than USD 72/month buys back. Whether the writer belongs on a non-burstable class, or whether a specific query is responsible for the peaks, is a separate and probably more valuable investigation.

Nothing here establishes what the peaks are, only that they happen daily. That is the next thing to measure, and Performance Insights already has the data — with the caveat that it becomes CloudWatch Database Insights on 2026-07-31.

## Open questions

1. **Is 1.8% worth a migration on `shared-001`?** The engine change is a full data migration with a cutover, and the spike on the KMS key work already established what that costs in risk and process. Spending it for USD 5/month is not obviously rational; spending it for USD 41 or USD 25 on the smaller stacks might be.
2. **Do we accept losing automatic failover on the productive stacks?** That is a availability decision, not a cost one, and it is the real content of this choice.
3. **Would the writer's daily CPU saturation get worse on RDS?** Aurora offloads some storage-layer work that a plain instance performs itself. This is widely stated but was not verified here, and on an instance already touching 100% it is the difference between a saving and a regression.
4. **What is `demo-001`'s and `atento-001`'s read I/O?** Not sampled. Both would only improve the RDS case, so the savings above are conservative rather than optimistic.
5. **`beta-001` is already the answer to "can we run plain RDS?"** — it does. What it does not tell us is anything about the productive workload, because it is a `t3.micro` with 20 GB.

## Decision — 2026-07-29

**Nothing changes engine.** `beta-001` stays on plain RDS PostgreSQL, which it already is; the three Aurora stacks stay on Aurora. No `demo-001` migration and no `atento-001` downgrade.

The reasoning is the numbers, not the features: roughly USD 72/month across three stacks does not pay for three data migrations with cutovers, and the two individually-largest savings are the two smallest stacks — USD 25/month on a non-productive visualization tool and USD 41/month on a productive one whose migration carries the full cutover risk. The engineer's own summary of it: the calculations do not make sense at this scale.

Worth recording because it will come up again: the availability question that would have been the hard part — whether to give up automatic failover on the productive stacks — never had to be answered. The cost side closed the question first.

This decision is about the **engine**. It does not touch the KMS key-per-environment migration, which continues on both engines and is the work resuming after this spike.

## Follow-up carried out of this spike

The writer CPU saturation found while measuring utilization is **not** part of this decision and is not closed by it. It has its own spike — `~/Projects/4Shark/dot-claude-plans/active/spike/app-writer-cpu-saturation/` — because it follows the workload regardless of engine and plausibly costs more in latency than this whole question was worth in dollars.

Whether the productive clusters need a larger instance class is deliberately deferred until the key migration finishes, so that a resize decision is made against a settled database rather than one mid-migration.

## What is settled

Plain RDS is cheaper per instance and dearer per GB, and our stacks sit on both sides of that line, so there is no single answer for all four. The saving is real but modest, and concentrated where the data is small. The Aurora feature we actually depend on is automatic failover, and no RDS configuration provides it at a lower price than Aurora already charges.
