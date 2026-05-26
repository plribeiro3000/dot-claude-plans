# PLAN — Integration Audit Expansion

## Objective

Expand the integration audit rake tasks from the original 5 (user-only) to cover every Resource the integrator handles, plus the corresponding app entities (including auxiliary `*_history` tables relevant to integration). Reorganize the existing single-file structure into one rake file per task to keep the surface small as it grows.

## Scope (confirmed 2026-05-25)

### The 14 Resources audited on the integrator side

`TableLocks` and `Password` are out of scope. The 14:

```
Client            Deal              DealExtraField    Goal
Group             Groupification    Hierarchy         Modifier
Product           Subsidiary        User              UserActivity
UserField         UserIdentifier
```

### Three sides per Resource (integrator side) + 1 (app side)

- **Mongo** (integrator) — Mongoid documents under each Resource subclass
- **Normalized** (integrator) — customer-controlled SQL base extracted via `DatabaseSource` (develop) or `Database.connect!` (master, hotfix 8.4.11). No-op when no normalized source is configured (`DatabaseSource.find_by(normalized: true)` nil on develop, `ApplicationConfiguration.non_database_integration?` on master)
- **App** (RDS) — destination tables. Names do not always match the Resource name (mapping resolved during iteration 4 by reading models + controllers + loaders)

### Resource → app table mapping (resolved during iteration 4)

| Integrator | App table | How |
|---|---|---|
| Client, Deal, Goal, Group, Groupification, Product, Subsidiary, User, UserIdentifier | same name | direct |
| Modifier | `Indicator` | endpoint `POST /api/v3/indicators`; columns match (company_id, user_id, compiled_at, value, variable_id) |
| UserField | `Field` | engineer-confirmed |
| DealExtraField | `DealField` | engineer-confirmed |
| UserActivity | — (no separate table) | `POST/DELETE /users/:id/activity` only flips `disabled_at`/`disabler_id` on `User` — already in `audit:user` |
| Hierarchy | — (no separate table) | loader updates `Seat` and produces `SeatHistory` rows — `seat` (current state, added in iteration 5) + `seat_history` (changes) cover it |

### Auxiliary history tables on the app side

12 `*_history.rb` models exist in the app; only 2 are integration-relevant:

- `seat_history` (already in `audit:seat_history`)
- `groupification_history` (engineer-flagged; added in iteration 4)

The other 10 belong to the internal `UserHistory` snapshot system (`user_*_history` junction tables) or to non-integration domains (`voucher_catalogation_history`) — excluded.

### Folder structure

- Integrator: `lib/tasks/integration_audit/mongo/<resource>.rake` + `lib/tasks/integration_audit/normalized/<resource>.rake`
- App: `lib/tasks/integration_audit/<table>.rake`

Rake auto-discovers files under `lib/tasks/**/*.rake`, so task names (`integration_audit:mongo:user`, `integration_audit:user`, etc.) stay identical to the original single-file shape.

## Iterations

### Iteration 1 — Reorganize the existing structure (COMPLETED)

Moved the existing single-file rake into one file per task, no behavior changes.

- **App PR #5060** — split `integration_audit.rake` into `integration_audit/{user,user_identifier,seat_history}.rake`
- **Integrator PR #2223** — split `integration_audit.rake` into `integration_audit/{mongo,normalized}/user.rake`

### Iteration 2 — Mongo audits for the remaining 13 Resources (COMPLETED)

- **Integrator PR #2224** — added `integration_audit:mongo:{client,deal,deal_extra_field,goal,group,groupification,hierarchy,modifier,product,subsidiary,user_activity,user_field,user_identifier}`. Each follows the same template as `mongo/user.rake` (cursor-paginated dump of `_id`, `external_id`, `integration_status`, `created_at`, `updated_at`, `imports_count`).

### Iteration 3 — Normalized audits (COMPLETED)

Originally listed as blocked on "how to discover the normalized table name per Resource". Resolved at engineering time: table names follow snake_case plural (`clients`, `deals`, `hierarchies`, `subsidiaries`, etc.). The SQL adapter (`PostgresSqlAdapter#page:45`, `MicrosoftSqlAdapter#page`) applies `ApplicationConfiguration.table_prefix` internally, so the rake passes the logical name and the adapter resolves the physical name.

- **Integrator PR #2225** — added `integration_audit:normalized:{client,deal,deal_extra_field,goal,group,groupification,hierarchy,modifier,product,subsidiary,user_activity,user_field,user_identifier}`. Each follows the same template as `normalized/user.rake` and no-ops when `DatabaseSource.find_by(normalized: true)` is nil.

### Iteration 4 — App audits (COMPLETED)

Originally listed as "on-demand, no upfront list". Engineer-clarified during execution that all entities corresponding to the 14 integrator Resources should be audited up front on the app side too. Resolved via the Resource→app table mapping above.

- **App PR #5061** — added `integration_audit:{client,deal,goal,group,product,subsidiary,indicator,groupification,field,deal_field,groupification_history}`. Each follows the `user_identifier.rake` template (auto-discovered columns via `Model.column_names`, cursor pagination).
- 7 direct entities paginate via `company.<assoc>`. 4 nested entities (`groupification`, `field`, `deal_field`, `groupification_history`) walk the company hierarchy via nested loops to avoid multi-table joins, matching the convention set by `seat_history.rake`.

### Iteration 5 — Production rollout via hotfix 8.4.11 + follow-ups (COMPLETED)

Develop integrator was held back from release due to unrelated in-flight refactors (Source-driven connection model). To get the new audit tasks into production for the 12 clients currently running on master, the work from iterations 1–3 was backported into a single hotfix.

- **Integrator PR #2226** (hotfix `8.4.11`, base `master`) — bundled iterations 1–3 in a single release: split single-file rake into folders, 14 mongo audits (with cursor pagination fix), 14 normalized audits adapted to master's connection model. The mongo tasks are identical to develop. The normalized tasks were rewritten for master because master still uses `Database.connect!` directly (`Source`-driven model exists in code but no client uses it yet), so the guard is `ApplicationConfiguration.non_database_integration?` instead of `DatabaseSource.find_by(normalized: true).nil?`.
- After merge, `git hf hotfix finish 8.4.11` tagged master with `v8.4.11` and back-merged into develop. The back-merge produced expected conflicts on the 14 normalized rakes (master vs develop diverge on connection model); resolved by accepting develop's version (`DatabaseSource` / `source.connect!`) so the next develop release ships the up-to-date implementation, and on the CHANGELOG by keeping develop's `[Unreleased]` intact and inserting `[8.4.11] - 2026-05-25` between `[Unreleased]` and `[8.4.10]`.
- Production rollout: `start-instance.sh` brought up the 9 Mongo EC2 instances for almaviva, maqnelson, redebrasil; GitHub Actions deploy workflow triggered for all 12 integrators on `master` ref; `stop-instance.sh` brought the 9 Mongo EC2 instances back down after deploys completed.

Follow-up PRs on develop, both COMPLETED:

- **App PR #5063** — added `integration_audit:seat` (current state of `Seat`, companion to `seat_history`). Same nested-loop pattern as `seat_history`; when `user.seat` is nil, emits a row with only `user_id` filled.
- **Integrator PR #2227** — removed from `[Unreleased]` the 4 entries duplicated after the 8.4.11 back-merge (Mongo audit tasks, Normalized audit tasks, Integration audit tasks reorganized, Memory pressure on integration audit tasks). These already appear under `[8.4.11]`; the cleanup avoids them surfacing twice when the next develop release is cut.

## Pending / follow-up

None — feature fully closed.

Earlier open items, all resolved:

- ~~`integration_audit:seat`~~ — added in iteration 5 (App PR #5063).
- ~~`DealExtraField` handling~~ — maps to `DealField` on the app side.
- ~~CHANGELOG duplication on develop integrator~~ — cleaned up in iteration 5 (Integrator PR #2227).

## Final state — what's live in production after this feature

**Integrator master (deployed to all 12 clients, tag `v8.4.11`):**
- `integration_audit:mongo:*` — 14 tasks (User + 13 added)
- `integration_audit:normalized:*` — 14 tasks (User + 13 added; all no-op when integrator is not in database mode). Uses `Database.connect!` on master

**Integrator develop (awaiting next release; will overwrite master at release time):**
- Same task surface, but normalized uses `DatabaseSource.find_by(normalized: true)` + `source.connect!` (Source-driven model)

**App develop (awaiting next release):**
- 15 tasks: `user`, `user_identifier`, `seat_history` (originals) + `client`, `deal`, `goal`, `group`, `product`, `subsidiary`, `indicator`, `groupification`, `field`, `deal_field`, `groupification_history` (iteration 4) + `seat` (iteration 5)

## PR ledger

| Iteration | Repo | PR | Title |
|---|---|---|---|
| 1 | app | [#5060](https://github.com/4shark/app/pull/5060) | refactor(integration-audit): split rake tasks into one file per task |
| 1 | integrator | [#2223](https://github.com/4shark/integrator/pull/2223) | refactor(integration-audit): split rake tasks into one file per task |
| 2 | integrator | [#2224](https://github.com/4shark/integrator/pull/2224) | feat(integration-audit): add mongo audit tasks for the remaining 13 resources |
| 3 | integrator | [#2225](https://github.com/4shark/integrator/pull/2225) | feat(integration-audit): add normalized audit tasks for the remaining 13 resources |
| 4 | app | [#5061](https://github.com/4shark/app/pull/5061) | feat(integration-audit): add audit tasks for the remaining integration entities |
| 5 | integrator | [#2226](https://github.com/4shark/integrator/pull/2226) | [8.4.11] - 2026-05-25 (hotfix bundling iterations 1–3 into master) |
| 5 | app | [#5063](https://github.com/4shark/app/pull/5063) | feat(integration-audit): add seat audit task for current state |
| 5 | integrator | [#2227](https://github.com/4shark/integrator/pull/2227) | docs(changelog): remove entries from [Unreleased] already shipped in 8.4.11 |

## Status

All 5 iterations COMPLETED and merged. Production rollout to all 12 integrator clients done. Feature fully closed.
