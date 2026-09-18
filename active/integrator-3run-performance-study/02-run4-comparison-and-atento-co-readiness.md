# Run 4 comparison and Atento CO production readiness

Extends the 3-run study with a 4th run (2026-09-17) executed on `atento-co-staging`
after PR #2433 (skip the per-record S3 cold-storage restore on a clean/first load).

## The four runs

All four are the `atento-co-staging` integration. Run END is exact (the worker's
`ShutDownWorker` marker, UTC). Run START is the first ElastiCache write (±5 min,
metric resolution). Workload volume is the total Redis SET commands over the run
(`integrator-atento-redis001-001`, `AWS/ElastiCache`), used as a proxy for records
loaded because the authoritative per-run counts live in the integrator `Job`
collection, not in CloudWatch.

| Run | Start (UTC) | End (UTC) | Duration | Workload (SET) | GET | EngineCPU max | CPU max | Conns max |
|-----|-------------|-----------|----------|----------------|-----|---------------|---------|-----------|
| 1 | 2026-09-16 19:10 | 2026-09-16 21:05 | ~1h55m | 287,320 | 142,134 | 2.42% | 4.69% | 38 |
| 2 | 2026-09-16 21:35 | 2026-09-16 23:29 | ~1h54m | 272,988 | 86,694 | 2.18% | 4.17% | 40 |
| 3 | 2026-09-17 01:35 | 2026-09-17 02:30 | ~55m | 291,746 | 189,123 | 5.76% | 7.59% | 75 |
| 4 | 2026-09-17 17:05 | 2026-09-17 17:56 | ~52m | 276,695 | 106,049 | 5.30% | 7.18% | 97 |

## Findings

Workload is comparable across all four runs — SET totals cluster in 273k–292k
(±3.5%). The duration difference is therefore a real speedup, not a smaller batch.

The speedup lands between run 2 and run 3, and runs 3 and 4 confirm the fast tier:
runs 1–2 took ~1h55m for ~280k SETs; runs 3–4 did the same ~280k SETs in ~55m and
~52m — about 2.2x faster for the same work. This is the #2433 payoff: removing the
per-record S3 restore made each record cheaper, so the same volume finishes sooner.
Run 4 is the fastest of the four and carries the highest peak throughput
(91,952 SET / 5-min window vs run 3's 81,522) — denser and shorter, the signature of
the optimization.

The integrator ElastiCache node stayed idle in every run: EngineCPU (the saturation
metric on a single-threaded Redis) never above 5.76%, CPU never above 7.6%, database
memory never above 1.25%, zero evictions, ~3.35 GB freeable throughout. Runs 3–4 show
a higher EngineCPU peak than runs 1–2 only because the same work is compressed into a
shorter window (higher ops/sec), still trivial. The node is over-provisioned for this
workload and is shared across the atento environments (prod BR/MX/CO/CL + staging
MX/CO/CL), so its `cache.t3.medium` sizing is intentional headroom, not waste.

The only integrator-side log anomaly in run 4 was a single benign Sidekiq RTT WARN at
17:23:57 (cold-start of the worker tasks), non-recurring, with the ElastiCache metrics
proving the server was idle. Not an error.

## Atento CO production readiness

This integrator version, with the current MongoDB replica-set configuration on
`integrator-atento`, is considered ready to run the production integration against the
Atento Colombia base. The 4-run study shows the load completing in ~50 min for a
production-scale volume with no resource pressure on the integrator's own
infrastructure (MongoDB nodes, ElastiCache).

## Open item — NOT integrator-side

During run 4, the **demo app backend** (`app`, us-east-1) threw `Redis::OutOfMemoryError`
(`bigredis-max-ram`) on its Redis Cloud instance `redis-16939...redis-cloud.com` —
a DIFFERENT system from the integrator ElastiCache analyzed here. Cause: the demo's
cache (`RedisCacheStore`) and Sidekiq share one Redis Cloud database with `noeviction`;
a write burst during the load crossed the database memory limit (peak 291 MB against a
sub-1GB per-database limit — the node's 1 GB is not the enforced ceiling), so cache
writes and job enqueues failed together and some `Indicator` saves aborted. Fix options
(engineer's call, infra): raise the demo database memory limit (stopgap) or give the
cache its own database with `allkeys-lru` (definitive; the code already supports it via
`REDIS_CACHE_URL` in `app/lib/application_configuration.rb:311`). Decision pending.
