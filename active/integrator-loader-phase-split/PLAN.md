# PLAN — Integrator loader phase split (UserField + UserIdentifier)

## Goal

Eliminate the race condition in the integrator's `UserField` and `UserIdentifier` loader chains by splitting the single producer→consumer pair per resource into **N sequential phases**, where each phase only handles one operation type and the next phase only starts after the previous one has fully drained.

## Why

The current loader chain processes all operations of a resource (delete + create for UserField; create + promote + delete for UserIdentifier) in a single Sidekiq consumer that fans out jobs across 30+ threads per worker, with no ordering guarantee between operation types. This produces deterministic failures when the app's API enforces a state machine that requires a specific order:

- **UserField**: `(user_id, key)` is unique on the app side. When the source changes a key's value, the .NET writes a `type='delete'` row (for the old value) + a `type='create'` row (for the new value) in `ME_4Shark_DB.fsk_user_fields`. The integrator pushes both to the app concurrently. If `CREATE` races ahead of `DELETE`, the app rejects with `key: ya ha sido tomado` (HTTP 422).
- **UserIdentifier**: only one identifier per user can be `primary`. Operations are CREATE, PROMOTE (mark as primary, demote all others), DELETE (only allowed if not primary). With parallel processing, PROMOTE can fire before the identifier was CREATED, and DELETE can fire on something that's still primary — both fail.

## Evidence

End-to-end test cycles run against `atento-cl-staging` over 4 rounds (see `~/.claude/plans/active/simplex-harvester/PLAN.md` § "Cycle execution log"):

| Cycle | Requests | Success | Fail | % | Dominant failure |
|---|---|---|---|---|---|
| 1 (baseline, mostly creates) | 82.126 | 81.592 | 534 | 99.35% | mixed (low rate) |
| 2 (first incremental) | 601 | 543 | 58 | 90.35% | UserField key collision: 54 of 58 |
| 3 (second incremental) | 921 | 735 | 186 | 79.80% | UserField key collision: 72 of 186 + Phase 13 cascade: 110 of 186 |
| 4 (third incremental, small) | 24 | 18 | 6 | 75.00% | UserField key collision: 3 of 6 |

UserField key collision is the dominant **real bug** across cycles 2-4 (3 + 72 + 54 = 129 failures, 53% of all 244 failures). The integrator code was confirmed against the source — `app/workers/user_field/loader_consumer.rb:14-25` dispatches on `import.delete?` per job, and `loader_producer.rb:41` push_bulks all IDs to a single queue with 30 threads.

UserIdentifier has not failed in these cycles because the source has not produced identifier promotions/deletions yet, but the code structure (`app/workers/user_identifier/loader_consumer.rb:14-35`) has the same race shape and will fail the moment a promotion or deletion enters the stream.

## Solution

### UserField — 2-phase pipeline

```
LoaderProducer (delete phase) → LoaderConsumer (delete only)
                                       ↓ when phase done
                              LoaderProducer (create phase) → LoaderConsumer (create only)
                                                                     ↓ when phase done
                                                            UserActivity::LoaderProducer (next resource)
```

The producer plucks IDs filtered by `imports.data.type == 'delete'` first. When the delete phase reaches `job.computation.done?`, it triggers the create-phase producer. Same data flow, second filter.

### UserIdentifier — 3-phase pipeline

```
LoaderProducer (create phase) → LoaderConsumer (create only)
                                       ↓ when phase done
                              LoaderProducer (promote phase) → LoaderConsumer (select_primary only)
                                                                     ↓ when phase done
                                                            LoaderProducer (delete phase) → LoaderConsumer (delete only)
                                                                                                   ↓ when phase done
                                                                                          Client::LoaderProducer (next resource)
```

Order chosen by domain rules:

1. **CREATE first** — `select_primary` and `delete` both need the identifier to exist.
2. **PROMOTE second** — flipping `primary=true` automatically demotes the previous primary; this needs to settle before any deletes.
3. **DELETE last** — the app rejects delete of a `primary` identifier; deletes must run after the promote phase ensures the to-be-deleted ones are no longer primary.

### Phase identification

Two options for how each producer-consumer pair knows which phase it represents:

- **Option A — parameter on producer.** Existing producer class gains a `phase` argument (`:delete` / `:create` / `:promote`). The producer's pluck query filters by that phase. The consumer reads the phase from the job arg too and runs only the matching branch.
- **Option B — separate worker classes.** Three explicit classes per resource (`LoaderDeleteProducer`, `LoaderDeleteConsumer`, etc). More files, clearer logs, easier to scale a phase independently if needed.

Recommendation: **Option B** — file count grows but every Sidekiq dashboard entry, every CloudWatch log filter, and every retry path becomes immediately attributable to one phase. The runtime per phase is short, and queue/worker contention is already at thread granularity.

### Synchronization between phases

Reuse the existing `job.computation.done?` mechanism. The current consumer already triggers the next resource's producer when the phase's counter reaches zero:

```ruby
return unless job.computation.done?
UserActivity::LoaderProducer.perform_async(job_id)
```

For the phase-split version, the last consumer of phase N triggers the producer of phase N+1 instead of the next resource. Only the last phase of the resource triggers the next resource's producer.

The `job.computation` counter needs to be re-incremented at the start of each phase by the new total expected for that phase. This requires either (a) extending `Job::Computation` to support per-phase counters or (b) resetting the existing counter when each phase starts and using a separate flag/state to track "which phase am I in for this resource".

Choice between (a) and (b) is a design call to make in implementation, not in this plan.

## Code changes inventory (master, hotfix)

### UserField (master)

| File | Change |
|---|---|
| `app/workers/user_field/loader_producer.rb` | Split into `loader_delete_producer.rb` + `loader_create_producer.rb`. Each filters by operation type. Delete-producer triggers when extractor/transformer phase completes; create-producer is triggered by the delete-phase consumer when done. |
| `app/workers/user_field/loader_consumer.rb` | Split into `loader_delete_consumer.rb` + `loader_create_consumer.rb`. Each handles only its phase. Delete-consumer triggers `LoaderCreateProducer` when phase done; create-consumer triggers `UserActivity::LoaderProducer`. |
| `config/sidekiq.yml` | New queues `api_loader_user_field_delete` and `api_loader_user_field_create` (or stay on existing `api_loader_consumer` queue — design call). |
| `app/loaders/user_field_loader.rb` | No change — already has `delete` and `create` methods. |
| Call sites that perform_async `UserField::LoaderProducer` | Redirect to `UserField::LoaderDeleteProducer` (the new entry point). Likely 1-2 call sites. |

### UserIdentifier (master)

| File | Change |
|---|---|
| `app/workers/user_identifier/loader_producer.rb` | Split into `loader_create_producer.rb` + `loader_promote_producer.rb` + `loader_delete_producer.rb`. |
| `app/workers/user_identifier/loader_consumer.rb` | Split into 3 consumers, one per phase. Each triggers the next phase's producer when `job.computation.done?`. Last phase (delete) triggers `Client::LoaderProducer`. |
| `config/sidekiq.yml` | New queues per phase (or stay on existing — same call as UserField). |
| `app/loaders/user_identifier_loader.rb` | No change — already has `create`, `select_primary`, `delete` methods. |
| Call sites that perform_async `UserIdentifier::LoaderProducer` | Redirect to `UserIdentifier::LoaderCreateProducer`. |

### Job::Computation extension

Either extend to support per-phase counters or document the reset-and-reuse pattern. Need to read `app/models/job.rb` and `app/models/computation.rb` (if separate) before settling on this.

### Tests

For each new producer/consumer pair, mirror the existing rspec structure under `spec/workers/user_field/` and `spec/workers/user_identifier/`. Test the phase ordering explicitly: a test that enqueues a mix of delete+create user_fields for the same `(user_id, key)` and asserts that the create-phase consumer is not invoked until all delete-phase consumers have finished.

### CHANGELOG

`CHANGELOG.md` gets a new entry under `[8.4.9] - <release date>` describing the fix.

## Branch & release strategy

### Hotfix from master (primary path)

All integrator clients are running master (currently 8.4.8). Develop has a major-bump WIP that breaks compatibility and is not deployable. The fix must ship via hotfix:

1. `git hf hotfix start 8.4.9`
2. Implement all changes above on `hotfix/8.4.9`
3. Update `CHANGELOG.md` with `[8.4.9] - <date>` entry
4. Open PR `hotfix/8.4.9` → `master`
5. Run tests/CI
6. Merge PR (HubFlow finish takes care of master + develop back-merge + tag `v8.4.9`)
7. Trigger GHA deploy for all integrator clients

Per the 4Shark hotfix workflow (canonical: `~/.claude/docs/HUBFLOW.md`), the `git hf hotfix finish` command does the back-merge and tag. **Never** manually merge or tag — the `validate-bash-command.sh` hook blocks `git checkout -b hotfix/*`.

### Forward-merge to develop (follow-up work)

The HubFlow back-merge from `hotfix/8.4.9` into `develop` will produce conflicts because develop's `app/workers/user_field/` and `app/workers/user_identifier/` already diverged (`managed_*` workers exist in develop for the new architecture).

Beyond resolving the file-level conflicts, **develop needs additional work** to fit the phase-split into its own architecture:

- Develop's `managed_*` worker chain populates intermediate states in `ME_4Shark_DB`. In the current single-phase architecture, the managed code generates one state per resource (e.g., one `user_identifier` row per operation regardless of whether it's a create/promote/delete).
- After the phase split, the managed code must emit three distinct phase markers for UserIdentifier (`pending_create` / `pending_promote` / `pending_delete`) and two for UserField (`pending_delete` / `pending_create`), so the new producers know which IDs belong to which phase.
- The exact code change in develop depends on the not-yet-shipped managed-architecture design — to be detailed in a follow-up plan when develop's design lands.

Document the follow-up as a known item in the PR description and in develop's planning doc, but do not block the hotfix on it.

## Test plan

### Unit tests

- New rspec files for each producer/consumer pair, asserting the phase-only filter and the trigger of the next phase.
- A regression test that enqueues a mixed delete+create batch for the same `(user_id, key)` and asserts via Sidekiq inline mode that the CREATE is enqueued only after the DELETE has run.

### End-to-end against `atento-cl-staging` — replay the 4 historic cycles using SQL backups

After the hotfix is deployed to `atento-cl-staging`, replay the 4 cycles already recorded in `~/.claude/plans/active/simplex-harvester/PLAN.md` § "Cycle execution log" against the new integrator code. This gives a direct before/after comparison per failure type.

#### Why we don't need to re-run `.NET` or change any clock

Each existing SQL backup already captures the post-`.NET` state of its cycle, with the original `created_at` timestamps that the SQL Server EC2 stamped at write time (the `create_*` / `delete_*` / `disable_*` / `update_user_parent` SPs use `GETUTCDATE()` for `created_at`, not the .NET caller's clock). Restoring a backup brings the SQL state back exactly as the integrator saw it the first time.

Clock manipulation on the integrator host is also **not needed**. The integrator filters incoming work by `created_at > finished_at_of_previous_execution`. The variable we control is `finished_at` in Mongo, not the wall clock.

#### Why we need to overwrite `finished_at` in Mongo between cycles

The integrator writes its own `finished_at` as real-now when each execution ends. If we replay 4 cycles back-to-back today, each run will record a `finished_at` somewhere on today's date. The backup rows from May 14–17 have `created_at` BEFORE today's date, so the filter `created_at > finished_at` would return zero rows on every cycle past the first — the integrator would see nothing to process.

Fix: between cycles, update the execution record's `finished_at` on Mongo to a value **just before** the next backup's earliest `created_at`. This lets the filter pick up exactly that cycle's deltas.

#### Replay sequence

Reset before starting:

1. **Clean the app side** (`demo-001` RDS) — drop the test users created during cycles 1-4 so the app starts from zero. Same procedure used by the engineer at the start of this campaign.
2. **Clean the integrator Mongo** for `atento-cl-staging` — drop the `executions` (or equivalent) collection so no `finished_at` is set, the next run pulls everything from the restored backup.

Then for each cycle in order:

| Step | Cycle | `ME_4Shark_DB` to restore | Mongo `finished_at` to write | Expected requests | Expected failures (post-fix) | Reference baseline (pre-fix) |
|---|---|---|---|---|---|---|
| 1 | 1 (full baseline) | `ME_4Shark_DB_2026-05-13.bak` | (none — drop executions, `finished_at` is null) | ~82.126 | mostly 0 (some Phase 13 cases may remain) | 534 failures, 99.35% success |
| 2 | 2 (incremental) | `ME_4Shark_DB_2026-05-15.bak` | `2026-05-16 03:00:00 UTC` (just before cycle 2's earliest `created_at`) | ~601 | ~4 (54 UserField fixes + 4 legitimate remain) | 58 failures, 90.35% success |
| 3 | 3 (incremental) | `ME_4Shark_DB_2026-05-16.bak` | `2026-05-17 03:00:00 UTC` (just before cycle 3's earliest `created_at`) | ~921 | ~114 (72 UserField fixes drop; 55+55 Phase 13 cascade remains; 4 misc) | 186 failures, 79.80% success |
| 4 | 4 (incremental) | `ME_4Shark_DB_2026-05-17.bak` | `2026-05-17 22:00:00 UTC` (just before cycle 4's earliest `created_at`) | ~24 | ~3 (3 UserField fixes drop; 3 hierarchy-date artifacts remain) | 6 failures, 75% success |

#### Concrete procedure for one cycle

For each row in the table above:

1. **Stop the integrator**: scale `integrator-atento-cl-staging-worker-service` to 0 and `integrator-atento-cl-staging-web-service` to 0 (avoid stray work between steps).
2. **Restore the SQL backup**: `BACKUP/RESTORE DATABASE [ME_4Shark_DB] FROM DISK = N'/var/opt/mssql/data/ME_4Shark_DB_<DATE>.bak' WITH REPLACE, RECOVERY`.
3. **Update Mongo `finished_at`** for the relevant execution record on the integrator's Mongo (collection name TBD during implementation — likely `integrator_atento_cl_staging.executions` or similar; verify by inspecting Mongo before the first replay). If multiple execution records exist, target the latest. For cycle 1, alternatively drop the collection so the filter starts from null.
4. **Scale services back up**: worker to 1 task, web to 1 task.
5. **Trigger integrator**: `bin/rails integration:start` via `aws ecs execute-command` against the worker container.
6. **Wait for completion**: monitor Sidekiq queue + Mongo execution record. Final report arrives via email.
7. **Compare report** to the baseline failure count above. The success criterion is `actual_failures ≤ expected_failures`.

#### What the comparison tells us

- **If cycle 2 drops from 58 → ~4**: the UserField fix is confirmed in isolation.
- **If cycle 3 drops from 186 → ~114** (and the ~114 remaining are concentrated in `Users.seat.parent_id: no puede estar en blanco` + `Hierarchies.user_id: no se ha encontrado`): the UserField fix is confirmed AND Phase 13 (positional Mando) is correctly isolated as the remaining root cause to track separately.
- **If cycle 4 drops from 6 → ~3** (the 3 hierarchy date validation failures remain, since those were testing artifact): confirms.
- **If any cycle still shows `UserFields.key: ya ha sido tomado`**: the fix is incomplete and needs to be revisited before merging.

#### Cleanup after replay

Restore `ME_4Shark_DB_2026-05-17.bak` (the latest snapshot) so the staging environment ends in the state the team last left it. Drop the cleanup-only data on Mongo. Document the result of each cycle's replay in this PLAN.md (a new "Replay results" subsection under Test plan).

#### Risks

- The Mongo `finished_at` overwrite is a state-mutation operation; if the wrong record is targeted (multiple executions in the collection), the next run picks up unrelated data. Verify the targeted record by `_id` or `created_at` before update.
- If the app-side cleanup at the start is incomplete, leftover users from previous campaigns inflate the success rate (because the integrator's deltas land on already-existing users). Validate the app DB row count before cycle 1 starts.

### Acceptance criteria

- 0 failures of type `UserFields.key: ya ha sido tomado` in a cycle that previously produced them.
- 0 failures of type `UserIdentifiers.*: identifier already exists / not primary / not found` (the equivalent set) when an UserIdentifier promote/delete delta is exercised.
- Overall success rate of incremental cycles back to >99% (matching cycle 1 baseline) after fix is in.

## Rollout

1. Hotfix shipped and deployed to one client first (atento-cl-staging) — observe one incremental cycle.
2. After verification, deploy the same image to the remaining 11 integrator clients.
3. No data migration needed — the fix changes only the integrator's runtime behavior, no schema changes in ME_4Shark_DB or Mongo.
4. Rollback strategy: revert the hotfix commits, ship `8.4.10` reverting to old behavior. Old behavior had ~10pp failure rate per cycle on key changes — acceptable as a temporary fallback while a different fix is designed.

## Open questions

- Phase identification: Option A (parameter on existing class) vs Option B (separate worker classes per phase). Recommendation in this plan is Option B, but final call is in implementation when reading the existing worker structure end to end.
- `Job::Computation` extension shape: per-phase counters vs reset-and-reuse with a state flag. Read `app/models/job.rb` and `app/models/computation.rb` before deciding.
- Whether the new queues should be separate Sidekiq queues with their own priorities (cleaner observability, separate scaling) or stay on `api_loader_consumer` (less config churn).
- Whether the UserIdentifier phase split should also be applied to the API path (today UserIdentifier promotion via API uses the same flow as the database path — needs verification).

## References

- Bug evidence: `~/.claude/plans/active/simplex-harvester/PLAN.md` § "Cycle execution log" (cycles 2-4)
- Failure breakdown analysis: same doc, § "Failure analysis (244 failures across cycle 2 + cycle 3)"
- 4Shark hotfix workflow: `~/.claude/docs/HUBFLOW.md`
- Current loader code (master): `app/workers/user_field/loader_consumer.rb`, `app/workers/user_identifier/loader_consumer.rb`, both producers
