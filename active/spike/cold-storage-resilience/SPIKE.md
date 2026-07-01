# SPIKE — Cold Storage resilience to MongoDB transient failure

## Question

When a MongoDB connection/failover interrupts a `Resource::Consumer` mid-flight,
how do we keep the job from either exploding or hanging forever — and how do we
keep the auto-shutdown from cutting the database out from under in-flight work?

## What happened (recap, evidence)

- `Resource::Consumer#perform` order (`app/workers/resource/consumer.rb:7-26`):
  `Resource.find` (9) → `S3.store` (18) → `resource.destroy if status==200` (19)
  → `increment_executions` (21) → `done?` (23) → `ShutDownWorker` (25).
- On 2026-06-17 23:20:53 the `ShutDownWorker` ran `Ec2.stop_machine` on the 3 Mongo
  nodes **while the cold storage was still running**. The replica set lost its
  primary; 62 Consumers hit the failover in the same second.
- 59 got `NoServerAvailable` (never touched the doc) → retried fine.
- 3 got `[189] Demoted from primary while removing` — they were **inside the
  `destroy` (line 19), after `S3.store` already returned 200**. The delete was
  applied server-side (the doc is gone today) but the client got the error, so
  Sidekiq marked failure and retried. Every retry now hits `DocumentNotFound`
  at line 9 → stuck for 12 days.

Root insight: the S3-before-Mongo guarantee held (the `removing` error proves the
store returned 200). No data loss. The bug is **the job, not the data**: it
re-attempts work that is already done.

## Prong 1 — MongoDB write resilience (the "retry the command" idea)

- Retryable writes are **already on** (driver default). Error 189 is on the
  retryable list; the driver retries the write **exactly once** against the new
  primary, then surfaces the error (confirmed: spec + the log's `attempt 1,
  later retry failed`).
- It did not save us because the second attempt found **no primary at all** —
  the nodes were being *stopped*, not re-electing in seconds. `server_selection_timeout`
  is `10s` (mongoid.yml:10); raising it would not help when the RS never recovers.
- Conclusion: **prong 1 alone cannot fix this.** Driver-level retry covers a
  seconds-long election, not a shutdown. The real fixes are prongs 2 and 3.
  (A modest `server_selection_timeout` bump only buys resilience against *brief*
  elections — worth considering, but not the fix.)

## Prong 2 — Consumer idempotency (don't hang forever)

The Consumer must treat "the resource is already gone" as **success, not failure**,
because the only path that removes a Resource is line 19, *after* a 200 from S3.

### Option 2A — rescue `DocumentNotFound` at line 9, treat as already-archived
Catch `Mongoid::Errors::DocumentNotFound`, count the execution, return.
- Pro: tiny change, directly clears the stuck-forever case.
- Con / subtlety: **double-count risk in `Computation`.** If the original run had
  failed *after* `increment_executions` (line 21) instead of before, the
  idempotent retry would increment a second time → `executions` could overshoot
  `queue` and trip `done?` early. For the 3 observed jobs this is safe (they died
  at the `destroy`, *before* the increment), but a general fix must not assume that.

### Option 2B — verify against S3 before deciding
On `DocumentNotFound` (or on a transient `destroy` error), `S3.fetch` the object;
if present, the archival is complete → count + return; if absent, it is a true
anomaly → log/alert (do not silently swallow).
- Pro: closes both "delete applied + ack lost" and "doc gone for some other
  reason"; S3 becomes the source of truth for "already archived".
- Con: one extra S3 GET on the failure path; still needs the dedup guard below.

### Cross-cutting: make the execution count idempotent per resource_id
The robust version of either option needs `increment_executions` to be
**counted at most once per `resource_id`** (e.g. a Redis Set / SETNX keyed by
`job_id:resource_id`, checked before incrementing), so a retry of an
already-counted resource never inflates `executions`. Without this, prong 2 fixes
the hang but can introduce the early-`done?` race.

**Recommendation for prong 2:** 2A as the behavior, hardened with the per-resource
dedup guard on the increment. 2B (S3 verify) is the stricter variant if we want
positive confirmation before declaring success — decide based on how much we
trust "DocumentNotFound ⇒ already archived" as an invariant.

## Prong 3 — Shutdown must not cut the DB out of in-flight work

Today the shutdown trigger looks only at its own job's `Computation`
(`Consumer#done?`, consumer.rb:23) or `total_ids.zero?` (producer.rb:22). Neither
looks at the Sidekiq queue, so it can stop the Mongo nodes while Consumers (its
own or another run's) are still draining. The codebase **never** inspects
`Sidekiq::Queue` today — this would be new.

### Option 3A — gate the shutdown on the cold_storage queue being empty
Before `Ec2.stop_machine` / `Ecs.scale_down`, check
`Sidekiq::Queue.new('cold_storage').size`, the busy set (`Sidekiq::WorkSet`), and
the cold_storage entries in `RetrySet`/`ScheduledSet`. If anything is pending,
**do not shut down** — re-enqueue the shutdown check for later (or abort and let
the next `done?` decide).
- Pro: directly prevents "stop the DB while work is in flight".
- Con: `RetrySet` is global; a single stuck retry (exactly our 3 orphans) would
  keep the machine up **forever**. So **prong 3A only works if prong 2 is in
  place** — with an idempotent Consumer the orphans self-clear and the queue
  actually drains. The two are interdependent.

### Option 3B — drain pattern (quiet → wait empty → stop)
Quiesce the queue (stop enqueuing), wait for in-flight to finish, then stop the
nodes. More robust, more moving parts; mirrors the phased-Sidekiq deploy machinery.

**Recommendation for prong 3:** 3A (queue-empty gate), explicitly **after** prong 2
lands, so a stuck job can never pin the infra on. Order matters: ship idempotency
first, then the shutdown gate.

## Bottom line

- Prong 1: nothing to "fix" — retryable writes already on; not the lever.
- Prong 2 (idempotency) is the load-bearing fix: it turns a transient failover
  into a self-healing retry instead of an eternal job. Ship first.
- Prong 3 (shutdown gate) prevents the trigger itself; ship after prong 2, since
  it depends on the queue being able to drain.
- No migration of the S3 key scheme (`external_id`) is needed or in scope.

## Decisions (engineer, 2026-06-30)

1. **Prong 2 = 2B (S3-verified).** On `DocumentNotFound` at line 9, `S3.fetch` the
   object: present → count + return (archival already complete); absent →
   log/alert (true anomaly). For transient Mongo errors, follow the loader
   pattern (`client/loader_consumer.rb:32-33`: `rescue → perform_in(5.seconds)`).
2. **No dedup guard.** The other Consumers increment directly with no guard
   (`client/loader_consumer.rb:27`). The double-count I raised is the pre-existing
   "die between `increment_executions` and the Sidekiq ack" window — already
   tolerated system-wide. 2B introduces nothing new; increment directly, follow
   the existing pattern. (Recommendation withdrawn.)
3. **Prong 3 = abort-if-others.** Before shutting down, if there is ANY
   cold_storage job besides itself, abort the shutdown (don't power off). Covers
   the rare 2-concurrent-runs case; both finish and the last one finds the queue
   empty and shuts down correctly. Simpler than an elaborate gate.
4. **Do NOT bump `server_selection_timeout` (already 10s).** It is margin, not
   speed. See the new section below — the slow first connection has a concrete
   cause worth fixing instead.

## Side finding — slow first MongoDB connection (>5s)

Maqnelson envs: `MONGO_CONNECT_TIMEOUT=5`, `MONGO_SERVER_SELECTION_TIMEOUT=10`,
`MONGO_SOCKET_TIMEOUT=300`, `SIDEKIQ_THREADS=30`; URI
`mongodb://...003,...004,...005/maqnelson`.

- The ">5s first connection" matches `connect_timeout=5s`: the Mongo nodes are
  on-demand (started lazily, stopped by `ShutDownWorker`), so the first connect
  can hit a cold node and wait the full 5s before moving on.
- The connection string has **no `?replicaSet=maqnelson`** (the `/maqnelson` is
  the database). Without the RS name, the driver discovers topology blindly by
  probing all three seeds — slower at boot and more fragile during failover
  (the driver takes longer to find the new primary — relevant to the incident).
- `MONGO_SOCKET_TIMEOUT=300s` is very high (a stuck query pins a thread for 5
  min) — worth reviewing, separate topic.
- Fix direction (not the timeout): add `?replicaSet=maqnelson` to the URI (Mongo
  best practice, low risk) and profile the first connection to confirm where the
  5s go. Tied to the same Mongo-lifecycle fragility as the incident.

### Item-2 investigation conclusion (2026-06-30)

- **Likely primary cause (solid):** `connect_timeout=5s` + on-demand nodes. The
  ">5s first connection" matches the 5s connect timeout against a node still
  warming up (mongod boot + recovery + primary election) right after the lazy
  start. Inherent to the idle/auto-shutdown Mongo lifecycle.
- **Contributing (hypotheses, need profiling):**
  - URI without `?replicaSet=`: the driver still discovers the RS (incident log:
    `topology=ReplicaSetNoPrimary name=maqnelson`), so it is NOT treated as
    standalone with multiple seeds — correction to an earlier claim. Latency
    impact of the missing name is unconfirmed without measurement; adding it is
    still low-risk best practice.
  - `min_pool_size == max_pool_size == 30` (`mongoid.yml:6-7`): 30 connection
    handshakes populated at boot against cold nodes.
- **Recommended order:** (1) profile the first connection (driver logging) to see
  where the 5s actually go — confirms the rest; (2) add `?replicaSet=maqnelson`
  to `MONGODB`; (3) evaluate `min_pool_size < max_pool_size`.
- Not the lever: bumping `server_selection_timeout` (already 10s) — it is margin,
  it does not speed up the connect.

## Next step

Pending engineer go: turn prongs 2 + 3 into an implementation PLAN; investigate
the slow-connection side finding separately.
