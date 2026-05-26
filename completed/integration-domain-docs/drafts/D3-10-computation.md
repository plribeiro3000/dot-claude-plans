# Multi-stream coordination via Computation

The pipeline fans out at every stage: a single `<Resource>::TransformerProducer` dispatches one Sidekiq job per Stream feeding that ResourceType, and the next ResourceType's producer should fire only when **all** of those Sidekiq jobs have finished. Sidekiq itself does not provide a "wait for N jobs" primitive — each job is independent. The integrator builds the coordination on top of Redis with a small primitive: `Computation`.

## What Computation does

`Computation` is a thin wrapper around two Redis counters and one Redis lock, all keyed by a string the caller provides:

- **`queue`** — a counter representing "how many jobs are expected to do this work". Incremented by the Producer when it pushes the fan-out.
- **`executions`** — a counter representing "how many jobs have finished". Incremented by each Consumer when it completes.
- **`lock`** — a Redis SETNX-based exclusive lock. Used in two patterns: gating a single Producer per Job, and serializing the report-emission step.

The completion check is `Computation#done?` — it returns true when `queue == executions`. The next stage runs when `done?` returns true, which means every Consumer has acknowledged completion.

```ruby
def done?
  queue.value ==
    if defined?(@execution_quantity)
      @execution_quantity
    else
      executions.value
    end
end
```

The `@execution_quantity` cache is a per-instance optimization — the Consumer that just incremented `executions` already has the post-increment value locally, so it can compare against `queue` without a second Redis round-trip.

## How a Producer/Consumer pair uses it

The pattern is identical across every fan-out in the pipeline. From `<Resource>::ExtractorProducer`:

```ruby
arguments = stream_ids.map { |stream_id| [job_id, stream_id.to_s] }
total_streams = database_arguments.size + api_arguments.size
job.computation.increment_queue(by: total_streams)
Sidekiq::Client.push_bulk('class' => Subsidiary::DatabaseExtractorConsumer, 'args' => database_arguments)
Sidekiq::Client.push_bulk('class' => Subsidiary::ApiExtractorConsumer, 'args' => api_arguments)
```

The Producer:

1. Computes the work — the list of (job_id, stream_id) pairs to dispatch
2. Increments `queue` by the size of that list — declaring how many Consumers are expected
3. Pushes the Consumer jobs in bulk

Each Consumer, on completion:

```ruby
job.computation.increment_executions
Hierarchy::ExtractorProducer.perform_async(job_id) if job.computation.done?
```

The Consumer:

1. Does its work (extract one Stream, transform one Stream, etc.)
2. Increments `executions` — declaring its own completion
3. Checks `done?` — if true, **this Consumer** is the one that closes the count, and it kicks off the next ResourceType's Producer

The "last Consumer triggers the next stage" pattern is deliberate. Sidekiq does not preserve job order across a fan-out, so the Consumer that finishes last is unpredictable — but exactly one Consumer will see `queue == executions` first (Redis `INCRBY` is atomic), and that Consumer is responsible for advancing the pipeline. The other Consumers see a still-counting state and exit cleanly.

## Why one counter and not two

A naive design would track `queue` as the expected count and decrement it as Consumers finish — the Computation would be done when `queue == 0`. This works but loses information: after completion, the Computation has no record of how much work was done, only that it is done. The two-counter approach (`queue` + `executions`) preserves the totals, which matters for the report stage and for debugging.

The two-counter shape also separates concerns cleanly. `queue` is set once by the Producer and never modified; `executions` grows monotonically as Consumers finish. There is no "race to zero" failure mode where a buggy Consumer over-decrements and the Computation never reaches `done?`.

## The Counter primitive

Underneath, `Counter` is a Redis primitive with three operations: `increment`, `reset`, `value`. Each operation is wrapped in a Redis MULTI to atomically set the key and refresh its TTL (24 hours by default). The TTL exists as a self-cleanup measure: a Job that crashes mid-way leaves dangling counters in Redis, but they expire automatically after a day rather than accumulating forever.

The TTL refresh on every operation is deliberate — a Job that takes longer than 24 hours (rare but possible for large customers' first runs) should not see its counters expire mid-run. As long as the Computation is being touched, the TTL stays alive.

## The lock — gating a single Producer per Job

`acquire_lock` uses Redis SETNX (`SET ... NX`) on `"lock:#{@key}"`. The key is set if it doesn't exist; the operation returns `'OK'` on success and `nil` on failure (already held). The integrator code reads the result:

```ruby
def acquire_lock
  result = redis_pool.with { |connection| connection.set(lock_key, 'true', nx: true) }
  result == 'OK'
end
```

The lock is used in two contexts:

- **`Job::Starter` itself** — uses the global `Lock.acquire('integrator')` (a slightly different primitive in `app/models/lock.rb`, also Redis SETNX) to guarantee at most one Job runs at a time.
- **Report emission** — `IntegrationReport::Producer` calls `job.computation.acquire_lock` before emitting the report email. This guarantees that even if the report producer is enqueued twice (Sidekiq redelivery, manual replay), the email is sent once. The lock is **not** released; it lives in Redis under the Job's TTL until it expires naturally. This is intentional — once the report is sent, the lock's job is done; a second acquisition attempt would be a sign of a duplicate trigger, which is exactly what should be blocked.

## When does Computation get reset

Each Job has a fresh Computation, keyed by the Job's id. The producers that start a stage call `reset_queue` and `reset_executions` defensively before incrementing — a Job that gets retried mid-flight (rare but possible) starts the counter from zero rather than carrying over a half-counted state from the failed attempt.

The pre-#2120 codebase had the Computation key the connector level, not the stream level. After PR #2120, `Computation` is per-Job (`j_<job_id>`) and the fan-out happens at the per-Resource Producer/Consumer level. The shape is the same; the granularity changed.

## A worked example: Subsidiary stage

A customer with two Streams supplying Subsidiary (one normalized DB, one ApiSource bridging to a SaaS):

1. **Job::Starter completes**, fires `HealthCheck::Producer`. After health checks pass, the chain advances and eventually fires `Subsidiary::ExtractorProducer`.
2. **Subsidiary::ExtractorProducer** runs:
   - Finds 2 enabled Streams of ResourceType=Subsidiary, both `ready_for?(job) == true`
   - Partitions: 1 to the DatabaseExtractorConsumer queue, 1 to the ApiExtractorConsumer queue
   - Increments `job.computation.queue` by 2 (the total work)
   - Pushes the 2 Consumer jobs via `Sidekiq::Client.push_bulk`
3. **Subsidiary::DatabaseExtractorConsumer** runs (one of two parallel jobs):
   - Connects to the normalized DB
   - Extracts 100 rows of Subsidiary data, persists them into a SubsidiaryCollection
   - Self-reschedules with `collection_last_id` to fetch the next page (this is recursion within the same Stream's pagination, not a separate fan-out — the Computation is not incremented for it)
   - Eventually the page is empty, ending the per-Stream pagination
   - Increments `job.computation.executions` to 1
   - Checks `done?`: `queue (2) == executions (1)` is false; exits
4. **Subsidiary::ApiExtractorConsumer** runs (the other parallel job, possibly later):
   - Hits the SaaS endpoint
   - Extracts the data, persists it
   - Increments `job.computation.executions` to 2
   - Checks `done?`: `queue (2) == executions (2)` is true
   - Fires `Hierarchy::ExtractorProducer.perform_async(job_id)` — the next stage of the pipeline

The order in which the two Consumers complete is unpredictable — DB might be slower than the API, or the other way around. The Computation guarantees that exactly one of them advances the pipeline.

## Trade-offs

The pattern is simple to read and simple to operate. It also has known costs:

- **Each Consumer touches Redis on every completion.** Two counter increments and one `done?` check per Consumer. Negligible at the integrator's scale, but worth noting.
- **A Consumer crash before `increment_executions` will stall the pipeline.** The Computation never reaches `done?`; the next ResourceType never fires. Sidekiq retry will replay the failed Consumer, and on retry it will eventually increment the counter and unstall. Sustained Consumer failure would block the Job indefinitely until the operator intervenes — but a Consumer failing every retry is a deeper failure that needs manual attention anyway.
- **There is no global view of the pipeline state.** A monitoring dashboard cannot show "the integrator is at stage 7 of 25" without scraping Sidekiq queues and consulting the Job document — the Computation is per-stage, not per-pipeline. In practice the customer-facing email and the Mongo audit trail provide the post-hoc view; the live view exists only for engineers reading Sidekiq directly.

## Why this primitive instead of Sidekiq Pro / Sidekiq Batches

Sidekiq Pro's `Batch` feature does almost exactly what `Computation` does: declare a set of jobs, get a callback when they all complete. The integrator does not use it for two reasons:

- **Pro is a paid product.** The integrator's pre-Pro code already had this primitive built; switching to Pro would buy the team approximately the same primitive at a recurring cost.
- **The custom primitive integrates with the rest of the integrator's Redis usage.** The same Redis instance hosts Sidekiq queues, the integrator-wide Lock, and the Computation counters. Adding another Redis-backed primitive on the same connection pool is operationally cheaper than introducing a new Sidekiq Pro extension.

## Summary

`Computation` is a per-Job, per-stage coordination primitive built on two Redis counters and one Redis lock. Producers declare expected work; Consumers acknowledge completion; the last Consumer to acknowledge advances the pipeline. The shape is what makes the no-central-coordinator architecture (Chapter 3) viable.
