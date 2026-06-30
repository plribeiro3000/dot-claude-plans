# PLAN — App-Managed Refresh with DispatchChecker State Machine

> Successor planning doc to `SPIKE.md`, `SPIKE-INGEST-READ-PATTERNS.md`, and `SPIKE-APP-MANAGED-REFRESH.md` in this directory.
>
> This is the **locked** architectural design after a long iteration that rejected: per-commission forced refresh (segment explosion), `?refresh=wait_for` (per-commission thread hold, max_refresh_listeners ceiling under burst), dual-index alias swap (storage cost + batch-end detection unavailable), Postgres multi-column filtering of the Deal table (12+ indexes required), inline metric aggregation in Consumer (averages cannot be decomposed), single Sweeper-with-Postgres-coordination tables (rejected as over-engineered duplication), and self-scheduling Consumer-side Producer enqueue with fixed buffer (non-deterministic under Sidekiq backlog, would require 5min+ buffer).

## Goal

Eliminate the OpenSearch cluster's auto-refresh load from the 4Shark app's perspective and replace it with an app-managed refresh schedule that aligns with the producer-consumer pipeline's actual demand. Preserve the producer-consumer pattern, preserve ES as the multi-column search index, preserve the per-commission completion semantics for the next pipeline stage. Resolve the conflict between 4Shark's per-commission synchronization and OpenSearch's window-based refresh model by inverting the dispatch responsibility: the Refresh job triggers the next stage, not the Consumer.

## Core architectural decisions (locked)

| Decision | Choice | Why |
|---|---|---|
| ES auto-refresh | **Disabled** (`refresh_interval: -1`) | App owns the refresh schedule end-to-end; no concurrency between auto and manual; deterministic timestamp of every refresh; SPIKE-APP-MANAGED-REFRESH.md Finding A endorses this for batch-managed scenarios |
| Refresh trigger | **First Consumer to finish a batch in an empty window** opens a Redis lock, enqueues Refresh job for +`MIN_REFRESH_INTERVAL` (e.g., 45s) | On-demand: zero refreshes when idle; ~120/h during nightly batch; no fixed-interval polling job |
| Dispatch responsibility | **Refresh job → enqueues DispatchChecker per entity → DispatchChecker enqueues Metric::Producer** | Deterministic: Producer fires only after refresh actually completed; no fixed buffer guessing; survives Sidekiq backlog |
| State tracking | **State machine on existing `deal_indexation_batches` table** (`pending → executed → refreshed → completed`) | No new table per engineer requirement; reuses the table created by v3.31.0 bulk commit; canonical source of "which batches passed each phase" |
| Audit retention | **No automatic cleanup**; only the existing process-start cleanup remains | `completed` rows kept for audit and historical analysis of commission processing behavior |
| Capacity topology | **Keep current state (bulk size 100, dedicated queue with 10 fixed threads)** for the initial deploy; revisit only after measurement | One variable at a time — measure the architectural change alone before touching capacity knobs |

## Capacity path post-deploy

Sequence of changes already applied to production (chronological):
1. **v3.31.0 (2026-05-25):** introduced bulk indexing (`DealIndexationBatch` + `client.bulk`, batch size 100)
2. **v3.32.0 (2026-05-26):** dedicated Sidekiq queue (`worker-deal-indexation`, 10 fixed threads, no autoscaling) — caused the regression
3. **This plan:** app-managed refresh with DispatchChecker state machine

After this plan ships, the working hypothesis is: the cluster-side relief (no more 3.600 refreshes/h competing for the 2 vCPUs) lets the existing 10 dedicated threads be enough. Each Consumer's bulk request likely completes faster than the observed 155ms degraded latency, because the merge thread no longer competes continuously for CPU. **Hypothesis to verify by measurement, not by prediction.**

Order of fine-tuning levers, applied only if measurement shows persistent bottleneck:
- **Bulk size:** raise `DEAL_INDEXATION_BATCH_SIZE` from 100 toward AWS's recommended 3-5 MiB target (~2000-3000 docs at 1 KiB/doc). Single env var change. Track 1 of `PLAN-SPIKE.md`.
- **Thread count on dedicated queue:** raise `SIDEKIQ_THREADS` on `worker-deal-indexation` from 10 to 20 or 30. Single line of Terraform. No autoscaling of tasks (engineer's standing preference to control cost).
- **Last resort — cluster scale-up:** `t3.small.search` → `r6g.large` (AWS-recommended for small production). Only after all app-side levers are exhausted.

Each lever is an independent knob; the measurement-driven sequence ensures we never scale up the cluster to mask an app-side inefficiency.

## Architectural closure

**After this plan ships, the app's interaction with OpenSearch is considered architecturally aligned.** Any future performance issue is one of:

- **Configuration fine-tuning** (refresh interval value, bulk size, thread count, retry policy) — engineering knobs without architectural change
- **Cluster scale-up** (instance type, shard count, replica count) — infrastructure investment

What this plan **closes**: the open question "is our producer-consumer pattern compatible with OpenSearch's refresh/merge model?". Before this plan, the answer was "no — we were synchronizing per-commission while ES wants to synchronize per-window". After this plan, the answer is "yes — the DispatchChecker pattern translates 4Shark's per-commission semantics into ES's per-window semantics deterministically".

This commitment matters because the alternative is paying for cluster scale-up while still running an architecturally incompatible workload — which would mask the problem temporarily, cost ongoing money, and leave the underlying mismatch unresolved.

## Domain model

### State machine on `deal_indexation_batches`

```mermaid
stateDiagram-v2
    [*] --> pending: UserProducer creates batch
    pending --> executed: Consumer completes client.bulk
    executed --> refreshed: DispatchChecker confirms executed_at <= T_refresh
    refreshed --> completed: DispatchChecker dispatches Metric::Producer for this entity
    completed --> [*]: terminal; ignored by future refresh cycles
```

Initial state `pending` is set explicitly on insert, following the platform's existing convention (engineer chose this over implicit nil).

### Sequence diagram — end-to-end flow

```mermaid
sequenceDiagram
    participant UP as UserProducer
    participant C as Consumer
    participant DB as Postgres
    participant R as Redis (lock)
    participant RJ as Refresh Job
    participant ES as OpenSearch
    participant DC as DispatchChecker
    participant MP as Metric::Producer

    UP->>DB: INSERT deal_indexation_batches (status=pending)
    UP->>C: enqueue Consumer per batch
    C->>ES: POST /_bulk (index docs)
    C->>DB: UPDATE status=executed, executed_at=NOW
    C->>R: SETNX refresh_window:<entity_type> (with NO TTL)
    alt key did not exist
        C->>RJ: enqueue RefreshJob in +45s
    end
    Note over C: Consumer ends — does NOT enqueue Metric::Producer

    Note over RJ: 45 seconds later
    RJ->>RJ: T = Time.current
    RJ->>ES: POST /_refresh
    RJ->>R: DEL refresh_window:<entity_type>
    RJ->>DB: SELECT DISTINCT commission_id, partial_commission_id FROM deal_indexation_batches WHERE status != 'completed'
    loop for each entity (commission_id or partial_commission_id)
        RJ->>DC: enqueue DispatchChecker(entity_type, entity_id, T)
    end

    DC->>DB: UPDATE status=refreshed, refreshed_at=T WHERE entity matches AND status=executed AND executed_at <= T
    DC->>DB: check commission.computation.done? AND all batches refreshed for this entity
    alt gate passes
        DC->>MP: enqueue Metric::Producer(entity_id, partial)
        DC->>DB: UPDATE all batches for this entity SET status=completed, completed_at=NOW
    else gate fails
        Note over DC: do nothing; next refresh cycle will try again
    end
```

### Entities and prefixes

The state machine is polymorphic over Commission and PartialCommission. The same `deal_indexation_batches` row carries either `commission_id` (with `partial_commission_id IS NULL`) or vice-versa. The Refresh job's `SELECT DISTINCT` query covers both columns. The DispatchChecker is parametrized by `(entity_type, entity_id, T)`, runs independently per entity.

Redis lock keys carry the entity prefix:

- `refresh_window:commission` — global lock for the commission-side refresh window
- `refresh_window:partial_commission` — global lock for the partial commission-side window

(These are global per entity type, NOT per-entity-id. The lock is what gates "should a Refresh job be scheduled for the next window?". With per-entity-id locks the design would degenerate into per-commission refresh, which is rejected.)

## Components — implementation summary

### 1. Cluster setting (cluster-side, no code)

```
PUT /deals/_settings
{ "index": { "refresh_interval": "-1" } }
```

Single API call. Disables ES auto-refresh permanently. The app's Refresh job becomes the sole source of refresh events.

Pre-requisite confirmed: the app codebase has **zero** uses of `?refresh=wait_for` in `app/`, `lib/`, `config/`, and the `elasticsearch-persistence-7.2.1` gem (grep run during planning). Setting `-1` will not cause any hanging request because no client code uses `wait_for`.

### 2. Schema migration on `deal_indexation_batches`

Add four columns:

```ruby
add_column :deal_indexation_batches, :status, :string, null: false, default: 'pending'
add_column :deal_indexation_batches, :executed_at, :datetime, null: true
add_column :deal_indexation_batches, :refreshed_at, :datetime, null: true
add_column :deal_indexation_batches, :completed_at, :datetime, null: true
add_index :deal_indexation_batches, [:status, :commission_id]
add_index :deal_indexation_batches, [:status, :partial_commission_id]
```

The `status` enum tracks the four states. The three timestamps record when each transition happened (useful for audit and for the `executed_at <= T` cutoff query in DispatchChecker).

### 3. Consumer change (`app/workers/deal_elastic_index/consumer.rb`)

Current lines 18-23:

```ruby
DealElasticIndex.save_documents!(deals, commission_uuid: commission.uuid)
commission.computation.increment_executions

return unless commission.computation.done?

Metric::Producer.with_company_id(commission.company_id).dynamic_perform_async(commission.id, partial)
```

Becomes (conceptually):

```ruby
DealElasticIndex.save_documents!(deals, commission_uuid: commission.uuid)
deal_indexation_batch.update!(status: 'executed', executed_at: Time.current)
commission.computation.increment_executions

# Open refresh window if this is the first Consumer to finish in the current cycle
entity_type = partial ? 'partial_commission' : 'commission'
if Redis.set("refresh_window:#{entity_type}", '1', nx: true)
  DealElasticIndex::RefreshWorker.with_company_id(commission.company_id).perform_in(45.seconds, entity_type)
end
```

The `Metric::Producer.dynamic_perform_async` call is removed. Metric::Producer dispatch is now the DispatchChecker's responsibility.

### 4. RefreshWorker (new)

```ruby
class DealElasticIndex::RefreshWorker < TenantWorker
  def perform(entity_type)
    refresh_at = Time.current
    DealElasticIndex.refresh!
    Redis.del("refresh_window:#{entity_type}")

    entity_id_column = entity_type == 'partial_commission' ? :partial_commission_id : :commission_id

    entity_ids = DealIndexationBatch
      .where.not(status: 'completed')
      .where.not(entity_id_column => nil)
      .distinct
      .pluck(entity_id_column)

    entity_ids.each do |entity_id|
      DealElasticIndex::DispatchChecker
        .perform_async(entity_type, entity_id, refresh_at.to_f)
    end
  end
end
```

### 5. DispatchChecker (new)

```ruby
class DealElasticIndex::DispatchChecker < TenantWorker
  def perform(entity_type, entity_id, refresh_at_float)
    refresh_at = Time.at(refresh_at_float)
    entity_id_column = entity_type == 'partial_commission' ? :partial_commission_id : :commission_id

    DealIndexationBatch
      .where(entity_id_column => entity_id, status: 'executed')
      .where('executed_at <= ?', refresh_at)
      .update_all(status: 'refreshed', refreshed_at: refresh_at)

    commission = entity_type == 'partial_commission' ? PartialCommission.find(entity_id) : Commission.find(entity_id)
    all_refreshed = DealIndexationBatch
      .where(entity_id_column => entity_id)
      .where.not(status: ['refreshed', 'completed'])
      .none?

    return unless commission.computation.done? && all_refreshed

    Metric::Producer.with_company_id(commission.company_id).dynamic_perform_async(entity_id, entity_type == 'partial_commission')

    DealIndexationBatch
      .where(entity_id_column => entity_id)
      .update_all(status: 'completed', completed_at: Time.current)
  end
end
```

## Open question for the code-writing phase

The internal ordering inside DispatchChecker (mark refreshed first, then check gate, then dispatch, then mark completed) has potential concurrency edge cases when two DispatchCheckers for the same entity run in parallel. The Refresh job enqueues at most one DispatchChecker per entity per cycle, but Sidekiq retries could overlap. Engineer's decision: **defer this question; revisit when writing the actual code**. Possible mitigations to evaluate at that point: pessimistic lock on the commission row, advisory lock in Postgres, Sidekiq unique-job key on `entity_type:entity_id`.

## Rollout phases

1. **Schema migration.** Add the four columns and two indexes on `deal_indexation_batches`. Safe — no app changes yet, no code reads the columns.

2. **Code change (atomic deploy):** Consumer modification + RefreshWorker + DispatchChecker, all in one release. Until the cluster setting changes, ES auto-refresh keeps firing in parallel with the new Refresh job (no harm — both refresh the same index; brief overlap window during transition).

3. **Cluster setting change:** `PUT /deals/_settings { "index": { "refresh_interval": "-1" } }`. Disables auto-refresh. From this moment, the new Refresh job is the sole source of refresh events. Monitor: per-commission end-to-end latency, refresh count per hour, segment count per hour (via `GET /_stats`).

4. **Observability:** confirm metric_dispatched_at and completed_at timestamps populate as expected. Confirm that `commission.computation.done? = true` commissions eventually reach `completed` status on all their batches.

5. **Documentation (ADR in the app repo).** Add an Architecture Decision Record at `~/Projects/4Shark/app/docs/adr/ADR-NNN-app-managed-opensearch-refresh.md` (or the conventional path the app repo uses). Content:
   - **Context:** the 4Shark producer-consumer pipeline + OpenSearch refresh/merge model — why the per-commission synchronization clashes with ES's window-based refresh.
   - **The performance problem:** May 2026, batch indexing degradation; the dedicated queue + bulk changes that did not fully resolve it.
   - **The investigation:** instead of scaling the cluster (treating the symptom), we paused and researched how OpenSearch actually works internally — `refresh_interval`, segment merge thread pool, `wait_for` mechanics, AWS BP for instance sizing. References to the three SPIKE.md documents that produced this plan.
   - **The architectural finding:** the producer-consumer pattern (per-commission "indexed → read") is incompatible with the ES native refresh model (window-based). Not a bug — a structural mismatch.
   - **The decision:** disable ES auto-refresh (`refresh_interval: -1`), manage refresh from the app via the DispatchChecker state machine, deterministically dispatch downstream stages after refresh completion.
   - **The consequence and commitment:** the app is now aligned with the ES workload model. Future ES performance issues fall in two categories — configuration fine-tuning OR cluster scale-up — never architectural rework. The cluster can now be scaled with confidence that we are not paying to mask an app-side inefficiency.
   - **References:** PLAN-SPIKE.md, SPIKE.md, SPIKE-INGEST-READ-PATTERNS.md, SPIKE-APP-MANAGED-REFRESH.md in this directory (copied or linked into the app repo's docs).

Rollback at any phase:
- Phase 3 rollback: `PUT /deals/_settings { "index": { "refresh_interval": "30s" } }` — re-enables auto-refresh, system runs hybrid until next code rollback
- Phase 2 rollback: revert the deploy; Consumer goes back to direct Metric::Producer enqueue
- Phase 1 rollback: columns stay but are unused; can be dropped in a later migration

## What this plan does NOT cover

- **Cluster sizing** (`t3.small.search` → larger). Engineer's standing constraint: solve at the code level first. Revisit only if monitoring shows post-rollout pressure is still excessive.
- **Bulk size tuning** (`DEAL_INDEXATION_BATCH_SIZE` currently 100). Track 1 of `PLAN-SPIKE.md`. AWS recommends 3-5 MiB per bulk; at ~1 KiB/doc, the calibrated target is ~2000-3000 docs. Orthogonal to this plan; addressed as separate work after the refresh redesign stabilizes.
- **OpenSearch gem migration** (`elasticsearch-ruby` < 7.14.0 → `opensearch-ruby`). Track 3 of `PLAN-SPIKE.md`. Independent technical debt.
- **Adapter replacement** for `elasticsearch-persistence` 7.2.1. Track 4 of `PLAN-SPIKE.md`. Independent technical debt.
- **`DealEligibility::Grower` flow.** Also calls `DealElasticIndex.fetch_ids_by`. If this plan proves effective, the same DispatchChecker pattern can be extended to the Grower flow — but not in this plan's scope.
- **Cleanup of `completed` batches.** Engineer decision: no automatic cleanup. Audit retention is the value. Future cleanup, if ever needed, would be a separate worker driven by an explicit retention policy.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| First Consumer crashes between marking `executed` and opening the Redis lock | The batch is executed in ES but no Refresh job scheduled. Next Consumer to finish will open the lock and schedule. Worst case: this commission's batch waits one extra cycle (~45s). | Acceptable; bounded by next refresh window |
| Refresh job crashes after `POST /_refresh` but before enqueuing DispatchCheckers | The refresh happened in ES, but DispatchCheckers were not enqueued. Sidekiq retries the Refresh job. Re-running re-refreshes (redundant but harmless) and re-enqueues DispatchCheckers. | Acceptable; Refresh job is idempotent-safe |
| DispatchChecker crashes between dispatching Metric::Producer and marking batches `completed` | Metric::Producer was enqueued (or runs) but batches stay in `refreshed`. Next refresh cycle re-runs DispatchChecker which re-dispatches Metric::Producer. Per engineer: lean on existing Sidekiq patterns and Metric::Producer idempotency. | Accepted per #2 in design conversation |
| Redis lock leaked (set but never deleted because Refresh job never runs) | New windows do not open; commissions accumulate in `executed` state. | Lock has no TTL by design (engineer choice). Mitigation: monitor "oldest executed_at without refresh" metric; alert if > N minutes. Fallback recovery: manual `DEL refresh_window:*` |
| Sidekiq backlog delays Refresh job arbitrarily | All downstream commissions stall waiting for refresh. Producer pipeline (which feeds the next stage) grinds. | Monitor RefreshWorker queue latency; isolate RefreshWorker on a dedicated queue with high priority |
| `deal_indexation_batches` table grows large with `completed` rows | Storage cost; index performance over time | Engineer accepts as audit value. If cost becomes prohibitive, add retention later as separate work |
| Per-commission latency floor rises to ~45s (was ~0s pre-bulk) | Fast commissions that previously completed in 2s now take 47s. | Engineer-accepted trade-off; documented as "the cost of operating ES on `t3.small` without scaling the cluster" |
