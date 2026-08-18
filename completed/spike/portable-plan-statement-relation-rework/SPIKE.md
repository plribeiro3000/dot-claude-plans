# SPIKE — Portable Exportation: correct the plan_statement↔batch relation (drop the FK, join through the portable)

**Date:** 2026-08-07
**Feature:** portable exportation coordinator (PR #5289, branch `feature/portable-exportation-coordinator`)
**Question:** the rule side (`PlanStatement`) relates to its batch through a foreign key `plan_statements.plan_statement_portable_batch_id` that the batch *claims* on creation. The result side (`Statement`) has no such FK — it relates to its batch only through the join record (`StatementPortable`). The rule side must be reworked to match the result side. What exactly changes, and what has to be decided before writing code?

**Prerequisite — DONE (2026-08-07):** the only production data on this FK (RedeBrasil, cancelled client, feature never exposed via UI) was purged in a Rails console session — 2 `PlanStatementPortableBatch`, 121 live + 66 orphan `PlanStatementPortableAttachment` (with their S3 PDFs), 121 `PlanStatementPortable`, and the FK on 121 `PlanStatement` all removed. Verified: `PlanStatement.where.not(plan_statement_portable_batch_id: nil).count == 0` globally. The column is now entirely null in production, so dropping it is safe.

---

## Why the FK is wrong (the domain rule)

A declaration must be exportable in **every** export whose rule matches it — not claimed once and skipped thereafter. The FK `plan_statements.plan_statement_portable_batch_id` encodes a one-to-one "this declaration belongs to that one batch", which is false: the same declaration participates in many exports over time. The correct model is the one the result side already uses — the batch↔declaration link lives in the join record (`PlanStatementPortable`, which also carries the generated PDF), created fresh per export, so a declaration can appear in unlimited batches.

## Current state — the exact divergence

The two sides are identical at **consume** time and differ only at **produce/dispatch** time.

**Consume (already correct on both sides):** both consumers create the join record from batch + declaration.
- `app/workers/statement_portable_batch/consumer.rb:14` — `statement_portable_batch.portables.find_or_create_by(statement: statement)`
- `app/workers/plan_statement_portable_batch/consumer.rb:16` — `plan_statement_portable_batch.portables.find_or_create_by(statement: plan_statement)`

So the join-through-portable relation **already exists** on the rule side at consume time. Nothing here changes.

**Produce (result side — the correct reference):** the producer pulls declaration ids straight from the domain, then dispatches `[batch_id, statement_id]`.
- `app/workers/statement_portable_batch/producer.rb:18` — `statement_ids = company.statements.pluck(:id)` (all of them, re-exportable)
- `app/workers/portable_exportation/result_producer.rb:45-55` — `statement_ids_for` pulls from `company.statements.for_user(...)` + period filter, no claim.
- `StatementPortableBatch` has **no** `has_many :statements`, no claim callback, no presence-via-claim validation. `Statement` has **no** `belongs_to :statement_portable_batch` — only `has_one :portable`.

**Produce (rule side — what is wrong):** the batch *claims* declarations by writing the FK, then reads them back.
- `app/models/plan_statement_portable_batch.rb:49` — `before_validation :add_plan_statements, on: :create`
- `app/models/plan_statement_portable_batch.rb:63-71` — `add_plan_statements` sets `self.plan_statement_ids = PlanStatement.where(...).without_batch.for_export_user(...).pluck(:id)` (writes the FK on each matched row).
- `app/models/plan_statement_portable_batch.rb:73-77` — `plan_statements_presence` validation (fails creation when the claim found nothing).
- `app/models/plan_statement_portable_batch.rb:10` — `has_many :plan_statements, dependent: :nullify`.
- Standalone `app/workers/plan_statement_portable_batch/producer.rb:22,25` — `return if new_record?` (relies on the claim + presence validation), then `plan_statement_portable_batch.plan_statements.pluck(:id)` (reads the claimed FK).
- Coordinator `app/workers/portable_exportation/processor.rb:62,75` — `next if new_record?` per calendar, then `dispatch_batches` reads `plan_statement_portable_batch.plan_statements.pluck(:id)`.
- `app/models/plan_statement.rb:7` — `belongs_to :plan_statement_portable_batch` (the FK), `:23` `scope :for_export_user`, `:27` `scope :without_batch`.

## Target — mirror the result side exactly

Delete the FK and the claim; the producer pulls declaration ids from the domain and dispatches; the consumer (unchanged) creates the join record.

### Change list

**Migration**
- Drop `plan_statements.plan_statement_portable_batch_id` (and its index `index_plan_statement_portables_on_batch_id`? no — that index is on `plan_statement_portables`, unaffected; the FK index is `db/schema.rb` line ~1613 on `plan_statements`). Generate via `bin/rails generate migration`, not hand-written. Zero-downtime handling is an open decision below.

**`app/models/plan_statement.rb`**
- Remove `belongs_to :plan_statement_portable_batch` (line 7).
- Remove `scope :for_export_user` (line 23) and `scope :without_batch` (line 27).
- Keep `has_one :portable` (line 13) — this is the correct relation.

**`app/models/plan_statement_portable_batch.rb`**
- Remove `has_many :plan_statements, dependent: :nullify` (line 10).
- Remove `before_validation :add_plan_statements` (line 49), the `add_plan_statements` method (63-71), and the `plan_statements_presence` validation (line 18 + method 73-77).
- Keep `has_many :portables` (line 11) and everything else.

**`app/workers/plan_statement_portable_batch/producer.rb` (standalone)**
- After creating the batch, pull the declaration ids from the domain directly (mirror `StatementPortableBatch::Producer`), then `push_bulk`. Remove `return if new_record?` (no claim to fail) and the `batch.plan_statements.pluck(:id)` read.

**`app/workers/portable_exportation/processor.rb` (coordinator)**
- `create_batches` (46-68) no longer relies on the claim to populate the batch. `dispatch_batches` (70-81) pulls declaration ids from the domain per calendar instead of `batch.plan_statements.pluck(:id)`.

---

## Decisions (resolved, implemented in this PR)

### D1 — the domain query for the rule side

Mirror the result side, applied at the entry point that owns the filter:
- **Standalone Producer** (takes a `plan_id`) pulls `plan.statements` (all declarations of that plan, re-exportable), no user/period filter — mirrors `StatementPortableBatch::Producer` pulling `company.statements` whole.
- **Coordinator** applies `for_user(portable_exportation.user_id)` directly at the call site (mirrors `result_producer.rb:46`), inside a private `plan_statement_ids_for(calendar_id, portable_exportation)`. The period filter stays at the calendar level (`calendar_ids_for`) — rule declarations carry no date of their own.

`for_export_user` was removed because it was a scope calling a scope, not because the user filter was wrong; the filter now lives at the call site directly.

### D2 — empty calendar handling after removing the claim

Skip a calendar with zero declarations before creating its batch (`next if plan_statement_ids_for(...).empty?` in `create_batches`). An empty batch would pollute the delivery tree (one folder per plano) and cost coordination for nothing.

### D3 — FK column drop, zero-downtime

`plan_statements` is a core table written on every declaration acceptance, so an old pod during a rolling deploy would `INSERT` naming the dropped column (`partial_inserts = false`) and hit `PG::UndefinedColumn` — a production incident. The unshipped-feature argument does not save a core table. So:
- **This PR** removes every code reference to the FK and leaves the column in place. A live instance writes `nil` to the unused column — harmless, fully backward-compatible.
- **Follow-up PR** does the whole strong_migrations two-step in its own deploy sequence: `self.ignored_columns += %w[plan_statement_portable_batch_id]` in one deploy, then `remove_column` with `safety_assured` in the next. Keeping both steps together in the follow-up is what makes the drop safe — `ignored_columns` a PR early buys nothing.

---

## The PortableExportation endpoint + fail-fast validation

The old `PlanStatementPortableBatch#plan_statements_presence` gave the user an immediate error when there was nothing to export — a user who just joined and generated nothing, or who has rule declarations but no result declarations yet, was told at request time instead of creating a record that processes to nothing. Removing the claim removed that guard, and it is a genuine, common case (a user "just wants to test the feature" on an empty account). It comes back on `PortableExportation`, the single object the whole export is triggered through — whoever needs the declarations needs all of them (rule + result), so there is one endpoint, not one per nature.

**Fail-fast validation on `PortableExportation` (implemented).** `statements_presence` checks, by the record's own filters (`user_id`, `starts_at`, `ends_at`), whether there is at least one **rule** statement OR one **result** statement. If neither exists it adds an error on `:base` (`:missing_statements`, translated in every locale) — the error is about the filter combination, not any single column — so the user is told "no statements match these specs" and never creates an empty export. It passes when either nature has anything. Code uses the domain term **statement** (`PlanStatement`/`Statement`) throughout; the client-facing message and the delivery folders keep the pt/es **declaração/declaración**.

**Creation at request time; the worker consumes the record (implemented).** `PortableExportation::Processor.perform(portable_exportation_id)` finds an already-created record and works on it; it no longer creates the record or looks up a SuperAdmin owner (company and owner come off the record). This mirrors `PaymentExportation` — its create mutation does `build` → set `company_id`/`owner_id` → `authorize` → `Processor.perform_async(id) if save` → `respond_with`, so a failed validation returns the record with its errors and never enqueues the worker. The **create mutation is the one remaining piece**, deferred deliberately; until it exists the coordinated flow is dormant (nothing enqueues `Processor`). The standalone per-plan/per-company producers still create-inside, unchanged.

**Single source of truth for the filter semantics (implemented).** The selection lives on `PortableExportation` — `matching_calendars`, `matching_plan_statements(calendar_id)`, `matching_statements` (relations, so the workers pluck under `with_uncached_connection` and the validation uses `exists?`/`empty?`). Both the validation and the two workers (`Processor`, `ResultProducer`) consume them, so "do I have anything?" and "what exactly?" can never diverge. The filters live on the record; the record answers both.

**Scope note:** the standalone `PlanStatementPortableBatch::Producer` (per-plan) is a separate, older entry point and keeps pulling `plan.statements`; this validation is `PortableExportation`-only, matching the single-endpoint decision.

## References
- Purge session: this conversation (2026-08-07), delete + verify console scripts.
- Scale-limits research: `../signature-pdf-audit-trail/PLAN.md` § Scale ceilings.
- Delivery/scale decisions: `../signature-pdf-audit-trail/PLAN.md` § "2026-07-22 — Scale & delivery decisions".
- Result-side reference implementation: `statement_portable_batch/producer.rb`, `portable_exportation/result_producer.rb`.
