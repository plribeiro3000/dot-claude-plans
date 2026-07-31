# BLUEPRINT — Auxiliary (output) variables

**Status**: validated against vendor documentation and gem source; ready to estimate
**Date**: 2026-07-30
**Feature**: an incentive rule may publish its per-user result into an auxiliary variable, which any incentive in a later calculation stage reads by name.

## What this document is, and what it is not

`PLAN.md` states the approach and the fifteen technical decisions. `TASKS.md` states the fourteen PR-sized units with their dependencies and acceptance criteria. **This blueprint sits between them**: it records what four validation spikes established by going to the actual documentation and gem source, the decisions that research forced, and the resulting size picture.

**Per-step detail is not duplicated here.** Each spike carries its own micro-step table — step, code shape, what breaks if skipped, how to verify, size — and those tables are the working reference at implementation time:

| Layer | Tasks | Spike |
|---|---|---|
| Schema and migrations | BE-1 (M1–M3), BE-9 (M4) | `../../spike/auxvar-migrations/SPIKE.md` |
| Model and validation | BE-3, BE-4, BE-5 | `../../spike/auxvar-validation/SPIKE.md` |
| Materialization and read path | BE-2, BE-6, BE-7 | `../../spike/auxvar-materialization/SPIKE.md` |
| API and front-end | BE-8, FE-1–FE-4 | `../../spike/auxvar-graphql-frontend/SPIKE.md` |

Each spike directory also holds the fetched sources and code excerpts it rests on.

---

## 1. What the validation round changed

Five things the plan asserted turned out to be wrong or incomplete. Each was verified directly — the gem source or the file, not a summary.

### 1.1 The upsert does not close BE-6's race — this is the finding that changes what gets built

`TASKS.md` said the unique index plus an upsert made the write safe, because the aggregate re-reads at the moment of write. That covers the row mutation and not the read-then-write cycle. Two consumer jobs — one per rule bound to the same auxiliary variable, a fan-out shape `IndicatorIncentive::Producer` already produces — each compute a `SUM` from a separate `SELECT`. Under Read Committed the later write overwrites the earlier with a lower number, silently, on a payroll figure.

**Decided: the `Reward` precedent.** `Reward#increment_budget` wraps exactly this read-modify-write in `transaction do lock! … end` (`app/models/reward.rb:65-71`), inside a method the file's own comments frame as a financial operation. BE-6 takes the same shape: `transaction { lock; recompute the sum; write }`. Source 2 on the ladder — 4Shark's own code, for the same class of problem. It stays in plain ActiveRecord, so Query Discipline Rule 1 needs no raw-SQL authorization, and unlike an upsert it fires the model's validations and cache callbacks.

Two consequences to carry into implementation rather than discover:

- **The unique index is still required and does different work.** `aggregated_modifiers_unique_index` on `(user_commission_id, variable_id)` (`db/schema.rb:86`) protects the insert race; the lock protects the recompute race. They are jointly necessary, not alternatives.
- **The first-ever-row race still raises `RecordNotUnique` on the loser**, because the lock can only serialize a row that exists. `AggregatedIndicator` declares no `rescue_unique_constraint`, so the loser fails and Sidekiq retries it — at which point the row exists and the lock path applies. That is tolerable behaviour, not an oversight, and it should be stated in the code rather than left to look like a bug.

### 1.2 `aggregated_modifiers.value` is a string column

`db/schema.rb:84` declares `t.string "value", limit: 8000`, while the sum being written comes from `commissionings.value`, `decimal(28, 6)` (`db/schema.rb:454`). Reads go back out through `variable.format(value)` (`app/models/aggregated_indicator.rb:49-51`).

So the recompute casts on the way in — and, more consequentially, **no SQL-side accumulation is available at all**: `SET value = value + x` is not valid arithmetic on a string column. Every shape that looked cheaper than the lock was never on the table.

### 1.3 M2 would fail on the first `db:migrate`

The reference is named `output_variable` for its role; its target table is `variables`. Rails pluralizes the reference name when `to_table:` is absent, so the migration as planned asked for a foreign key to a nonexistent `output_variables` table. The convention already covers this (`RAILS-MIGRATIONS.md:64` shows the same role-differs-from-table shape); the tasks simply omitted it. Corrected in `TASKS.md`.

### 1.4 The `statement_timeout` convention is inert in this codebase

A correction round earlier in this planning added `def self.statement_timeout` to all four migrations, on the strength of `RAILS-MIGRATIONS.md` stating that `strong_migrations` detects the method automatically. **It does not, at the installed version.** `strong_migrations` 2.7.0 touches a timeout in one place, `lib/strong_migrations/checker.rb:193-194`, and reads the global `StrongMigrations.statement_timeout`; nothing reads a method on the migration class. `app/config/initializers/strong_migrations.rb` sets only `auto_analyze = true`, so the global is never assigned, and no `MIGRATION_<timestamp>` variable exists in the repo or the deploy workflows.

The criteria were removed and replaced by a note recording why, so the dead method is not re-added. A separate task is open to correct the doc.

### 1.5 Two tasks named the wrong pattern to copy

Both were "follow the pattern at X" where nobody had checked that X was the right analogue — the failure mode that passes review because it looks idiomatic.

**BE-4** pointed at `indicator_variables_options`, which emits three keys per variable: the key plus a `_goal`/`meta_` pair that exists only for variables carrying a goal. An auxiliary variable carries none — `calculation`, `frequency` and `override_calculation` are each validated `if: :indicator?` (`app/models/variable.rb:32,36,39`). **Decided: the `easy_variables_options` shape** (`app/models/rule.rb:221-225`), one key per variable. Copying the indicator builder would have bound keys that never exist at runtime, so a formula would validate and then return zero in production — the exact failure class this feature exists to remove.

**FE-1** assumed the generic `variable/create` screen without noting that `EasyVariable` sets the opposite precedent, with its own mutation and module. **Decided: the generic screen, following Deal.** The generic form builder already carries `require = false` on `variableCalculation`, `variableFrequency` and `variableOverrideCalculation` (`app-webclient/src/app/variable/create/variable-create-form-builder.service.ts:36,46,56`) — precisely the mechanism a type without the indicator-only attributes needs. `EasyVariable` does not transfer: its mutation hardcodes `type` because Easy is scoped to a company mode rather than chosen among peers, which Auxiliary is.

---

## 2. What the validation round confirmed

Worth recording, because each was a premise something else rested on.

**The BE-4 blocker is real and structural.** Dentaku's parser wraps an identifier into an AST node with no binding check (`dentaku-3.5.7/lib/dentaku/parser.rb:118-124`); `UnboundVariableError` is raised later, inside `Calculator#evaluate!`'s separate dependency-resolution step (`calculator.rb:73-77`). `Formula#error` rescues only `ParseError` and `TokenizerError` (`app/models/formula.rb:14-21`), so it structurally cannot intercept it. Release 3.60.0's reasoned-error branch does not resolve the blocker — extending the synthetic options hash is the only path.

**The deploy ordering rests on something firmer than we had.** Apollo's documentation states a query selecting a field the schema does not define never executes, so there is no partial result for `errorPolicy: 'none'` to discard — it is total failure. Frontend-last is therefore necessary, not merely prudent. And the fourth `Variable` type stays additive for an un-updated client because `type` is exposed as a plain `String`, confirmed at `app/graphql_types/variable_graphql_type.rb:33`.

**Reusing `AggregatedIndicator#calculate!` would be actively wrong**, not merely redundant: an auxiliary variable never populates `indicator_aggregations`, so it would always fall through to `variable.format_default`. This is what the Calculator re-entry guard in BE-2 exists to prevent.

**The migration shapes hold.** M1's database-level default is metadata-only on Postgres 11+ and all four stacks qualify (16.13–18.4, from the terraform `rds.tf` files); the `CONCURRENTLY` + `disable_ddl_transaction!` shape matches Postgres's documented constraints and recovery path; and M2 needs no follow-up `validate_foreign_key`, because Postgres never checks NULL foreign key values and every pre-existing row is NULL.

**Rails semantics BE-5 depends on hold.** A custom `validate` callback can neither halt nor be halted by another (`activemodel-8.1.3.1/lib/active_model/validations.rb:135-136`), and `accepts_nested_attributes_for` assigns children before `valid?` runs — so the plan validation sees current rules, not a stale set.

---

## 3. Decisions taken during validation

Each resolved under the ladder, with the source that resolved it. None was escalated.

| # | Decision | Resolved as | Decided by |
|---|---|---|---|
| 16 | BE-6 write shape | `transaction { lock; recompute; write }` | `Reward#increment_budget` (`app/models/reward.rb:65-71`) — in-repo precedent for the same financial read-modify-write |
| 17 | BE-4 builder shape | The `easy_variables_options` form, one key per variable | The indicator-only validations at `app/models/variable.rb:32,36,39` mean the `_goal`/`meta_` pair has nothing to attach to |
| 18 | FE-1 creation screen | The generic `variable/create` screen, following Deal | The `require = false` controls already in `variable-create-form-builder.service.ts:36,46,56` |
| 19 | Auxiliary key reserved words | The type's key validation excludes `case`, `end`, `then`, `when`, `else` | Dentaku's `case_statement` scanner matches those words case-insensitively (`dentaku-3.5.7/lib/dentaku/token_scanner.rb:150-152`), and `Variable#key`'s format (`variable.rb:37`) permits them |
| 20 | `CalendarAudit` exclusion path | Through `joins(:variable)` | `plan_variables` carries only `goal_type`, `plan_id`, `variable_id` (`db/schema.rb:1617-1624`) — no type column to filter on directly |
| 21 | BE-6 cache-callback gap | Accepted as-is | The cost is a cache miss forcing a live query on read — performance, not correctness. Fixing it is not in the requested scope |

On decision 19: the failure is loud rather than silent, which is why it is cheap to guard. A reserved word in a formula produces malformed syntax, which **is** a `ParseError`, so `Formula#error` catches it and the author gets the reasoned message rather than the bare `:invalid`. The guard removes an authoring dead-end; it does not prevent a wrong calculation. Existing variables of other types are untouched — checking whether any already collide needs the production database and is only relevant if someone wants to rename them.

---

## 4. Size picture for estimation

Signals are the spikes' own, per task. They are relative to each other within this feature, not absolute.

| Task | Repo | Size | What drives it |
|---|---|---|---|
| BE-1 | `app` | M | Three migrations; the concurrent index builds are the unquantified part (see §5) |
| BE-2 | `app` | S–M | Mechanical exclusions across a known call-site list, plus the Calculator re-entry guard |
| BE-3 | `app` | S–M | Four of five steps are a few lines each; the registration rebuild carries the weight |
| BE-4 | `app` | S | One new builder method plus three call-site additions |
| BE-5 | `app` | M | The ordered constant and the validation method, plus the spec that keeps the constant honest against the enqueue graph |
| BE-6 | `app` | **L** | The highest-risk task: the locked recompute, the string-column cast, the partial-commission path, and the concurrency assertion |
| BE-7 | `app` | M | A new options processor plus the merge in three consumers |
| BE-8 | `app` | S in lines (~6–10 across 5 files), M in care | Both mutation allow-lists must be updated or bindings drop silently |
| BE-9 | `app` | S | One migration plus its `MODULE_KEYS` entry, shipped together |
| FE-1 | `app-webclient` | S | A list-and-locale change; confirm the locale file count before committing to S |
| FE-2 | `app-webclient` | M | Fifteen sites, mechanically small each once the shared builder is fixed |
| FE-3 | `app-webclient` | S–M | Steps 1–3 are S; the compatible-incentive filter is M with no in-repo precedent |
| FE-4 | `app-webclient` | S–M | Four ordered steps: query field, form control, template guard, picker filter |
| ROLLOUT-1 | — | S | Produces a checklist; triggers nothing |

**The shape of the estimate**: one L, five M, the rest S or S–M, across two repositories. BE-1 unblocks four independent starts; after BE-3 merges, two lanes run without touching each other's files.

---

## 5. What is still unquantified, and why

Three things could not be settled from the repository, and each is named rather than guessed.

**Row counts for `incentive_variables` and `rules`.** No schema or committed data reference carries them, and the production database is behind an access boundary. A concurrent index build on a small table is minutes; on a large one it is the dominant cost of BE-1. This is the single largest source of variance in the estimate, and one query answers it.

**Whether a genuine concurrent-writers test is achievable here.** No existing spec in this repository tests a cross-connection race. If none is practical, BE-6's concurrency claim rests on code inspection plus Postgres's documented `FOR UPDATE` semantics — which is defensible, but it should be a conscious choice rather than a silent gap.

**The `app-webclient` locale file count** behind FE-1's S signal was not fully audited.

---

## 6. Sources

The four spikes named in the table at the top, each with its own auxiliary evidence files. Vendor and gem sources consulted during validation: Dentaku 3.5.7 source, `strong_migrations` 2.7.0 source, Rails 8.1.3.1 source (`active_model/validations.rb`, `active_record/nested_attributes.rb`), PostgreSQL documentation on `ON CONFLICT DO UPDATE`, Read Committed isolation and `CREATE INDEX CONCURRENTLY`, Apollo Client error-policy documentation, graphql-ruby schema-evolution documentation, and Netlify build documentation.

Versions were read from `Gemfile.lock`, `package.json` and the terraform `rds.tf` files rather than assumed.
