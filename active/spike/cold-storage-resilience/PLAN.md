# PLAN — Cold Storage resilience

Derived from `SPIKE.md` (same folder). Two independent changes in the integrator,
ship in order: prong 2 first, then prong 3.

## Prong 2 — Bounded-retry archival with S3 revert on give-up

**File:** `app/workers/resource/consumer.rb` (+ new `S3.delete` in `app/models/s3.rb`).

**Behavior.** The Consumer keeps its current shape (find → store → destroy if 200).
The change is only the failure handling of the `destroy`:

1. `S3.store` succeeds (status 200) → archival is in the S3.
2. `resource.destroy` raises a transient Mongo error → **do not retry inline.**
   Let the job be re-enqueued by Sidekiq with exponential backoff, base ~5s.
3. Cap the attempts (target 3–5 — confirm exact number). The attempt count comes
   from `retry_count` (already exposed on the worker via
   `SidekiqRetryCountMiddleware`).
4. On giving up (cap reached, destroy still failing): **`S3.delete` the object
   (revert), leave the record in Mongo, and continue** (`increment_executions`
   runs, the record is picked up and re-archived by the next cold storage run).
   No stuck job, no permanent S3+Mongo duplication.

While the record is in Mongo, `find` always succeeds, so a re-enqueued attempt
re-runs find → store (idempotent overwrite) → destroy.

**Open implementation params (resolve at /execute with Pattern Priming):**
- Exact cap (3 vs 5) and the backoff formula (e.g. `5 * 2**count`, capped).
- Which exception(s) to treat as the transient-destroy case (Mongo connection /
  `OperationFailure` family) — keep it cirurgical, don't swallow unrelated errors.
- Mechanism: native `sidekiq_options retry: N` + `sidekiq_retry_in` +
  `sidekiq_retries_exhausted`, **or** a manual `rescue` keyed on `retry_count`
  that re-`raise`s below the cap and reverts at the cap. The manual form scopes
  the revert to the *destroy* failure only (a find/store failure must not trigger
  a revert) — likely the cleaner fit; confirm during Pattern Priming.

**New `S3.delete`** — mirror `store`/`fetch` shape in `app/models/s3.rb`:
`storage/#{type.name.underscore}/#{id}.json` → `adapter.delete_object(bucket, file_path)`.

**Note (residual, not a blocker).** The revert assumes "destroy failed ⇒ record
still in Mongo". A stepdown *during* the delete (error 189) is the one ambiguous
case where the delete may have applied. Using **writeConcern `majority`** on the
destroy makes an error mean "not majority-committed", tightening that assumption —
worth considering as part of this change, engineer's call.

## Prong 3 — Shutdown aborts if other cold_storage work exists

**File:** the shutdown trigger path — `app/workers/shut_down_worker.rb` and/or its
callers (`resource/consumer.rb:23-25`, `resource/producer.rb:8,22`).

**Behavior.** Before `Ec2.stop_machine` / `Ecs.scale_down`, check whether there is
ANY cold_storage job besides the current one (`Sidekiq::Queue.new('cold_storage').size`
plus the busy set / scheduled-retries for that queue). If so, **abort the shutdown**
(do not power off). This only happens in the rare two-concurrent-runs case; both
runs finish and the last one finds the queue empty and shuts down correctly. The
codebase does not inspect `Sidekiq::Queue` today — this is new.

Depends on prong 2: with the Consumer no longer able to get stuck, a leftover job
can never pin the infra on permanently.

## Order, tests, rollout

1. Prong 2 (with `S3.delete`) → unit tests: destroy fails N times then gives up
   (S3 reverted, record kept, execution counted); destroy succeeds on a retry
   (archived, no revert).
2. Prong 3 → test: shutdown aborts when the cold_storage queue is non-empty,
   proceeds when empty.
3. Schema/key scheme unchanged. Deploy is a normal single deploy (no in-flight
   contract change).
