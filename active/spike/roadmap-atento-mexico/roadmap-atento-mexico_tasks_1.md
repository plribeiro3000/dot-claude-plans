# Atento México Backlog — PR-Sized Task Breakdown

Companion to `SPIKE.md`. Covers every June-11 item this spike found NOT delivered, plus the two items flagged uncertain. Delivered items (Findings 1-4) carry no task — they are closed. Each task below cites the same file:line evidence as the parent Finding; nothing here introduces a new claim not already sourced in `SPIKE.md`.

## Task 1 — "Remuneración variable" naming override (Finding 6)

**Estimate: 1 day.** Unchanged from June — the override mechanism already exists and is in production for three other models.

**Steps:**
1. Confirm with the engineer which term Atento México wants ("Remuneración variable" vs the current "Retribución variable") and whether the `atento` (Brazil-serving, non-MX) front needs the same change or should keep the current string.
2. Create `app-webclient/src/environments/atento-mx/translations/es/models/deal.json` with the single key `variable_remuneration_achieved`, following the shape of the three existing override files (e.g. `app-webclient/src/environments/atento-mx/translations/es/models/seat.json`).
3. If step 1 confirms the `atento` front also needs it, repeat for `app-webclient/src/environments/atento/translations/es/models/deal.json`.
4. Build locally with the `atento-mx` override selector (`node build.js app-webclient atento-mx` per the usage comment at `app-webclient/build.js:4`) and confirm the four render sites (`app-webclient/src/app/statement/statement-show/statement-show.component.html:166,315,390,436`) show the new string.

**Files touched:** new file `app-webclient/src/environments/atento-mx/translations/es/models/deal.json` (and optionally the `atento` sibling). No core file changes.

**Dependencies:** none.

**Acceptance criteria:**
- The `atento-mx` build renders the client-requested term on all four `statement-show` locations.
- The base `es` locale (`app-webclient/src/translations/es/models/deal.json:56`) is untouched — no other Spanish-speaking client's copy changes.

## Task 2 — Results declaration broken down by payment type (Finding 7)

**Estimate: 2 days** (down from the June 2-3 day estimate now that the backend is confirmed complete).

**Steps:**
1. Add `userPaymentTypeCommissions { id money points dealMoney limiterMoney rankingMoney redemptionMoney paymentType { name externalId } }` to the existing `ShowStatement` query in `app-webclient/src/app/statement/statement-show/statement-show.component.ts` (the query starts at line 147; the `userCommission` block needing the addition is lines 160-205).
2. Add a breakdown table/section to `app-webclient/src/app/statement/statement-show/statement-show.component.html` rendering one row per `paymentType`, with the money/points columns already available on `UserPaymentTypeCommissionGraphqlType` (`app/app/graphql_types/user_payment_type_commission_graphql_type.rb:4-18`).
3. Confirm with the engineer whether the breakdown should also show a "total" row (sum across payment types) — the existing top-of-page totals (`dealMoney`, `limiterMoney`, etc. on `UserCommission` itself) already provide this sum; clarify whether they are meant to be shown alongside or instead of the new table.

**Files touched:** `app-webclient/src/app/statement/statement-show/statement-show.component.ts`, `app-webclient/src/app/statement/statement-show/statement-show.component.html`. No backend files — the GraphQL field and type already exist (`app/app/graphql_types/user_commission_graphql_type.rb:34`, `app/app/graphql_types/user_payment_type_commission_graphql_type.rb`).

**Dependencies:** none.

**Acceptance criteria:**
- Opening a result declaration (`statement-show`) shows a per-payment-type breakdown of the values already computed at commission-calculation time.
- No change to any backend file (the task is provably frontend-only, since the GraphQL surface pre-exists).

## Task 3 — Deactivation flow with group management (Finding 8)

**Estimate: 4 days**, matching both the June estimate and the independent "Pedidos Clientes" spreadsheet figure (`PLAN.md:61`, "P3, 4d").

**Steps:**
1. **Blocker to resolve with the engineer before estimating further** — the only specification found is the one-line spreadsheet entry "popup p/ retirar de grupos" (popup to remove from groups). Confirm the exact behavior wanted: does disabling a user prompt to (a) remove them from every group they belong to, (b) reassign groups they manage/coordinate to a successor, or (c) both? This changes whether the work touches `Group` membership only or also `Seat`/`SeatAction` succession (`app/app/models/seat_action.rb:18` already has a distinct `promote`/`change_manager`/`demote` mechanism for seat succession that may or may not be the intended reuse point).
2. Once scoped, add a confirmation step to the frontend disable action (today a single confirm-and-execute at `app-webclient/src/app/user/user.component.html:277-316`) surfacing the groups affected.
3. Add the corresponding backend mutation/parameter so the disable call can carry the operator's group decision, extending `app/app/models/application_record.rb:135-151` (`disable(by:)`) or building a dedicated flow alongside it — `disable` today only sets `disabled_at`/`disabler_id` and has no hook point for a side effect like this.
4. Cover both the single-user disable path (`user.component.ts`) and the bulk path (`app/app/workers/user_activity_document/consumer.rb:27-43`, Finding 1) — the bulk upload also calls `user.disable`, so the group step needs to be either applied there too or explicitly scoped out.

**Files touched:** `app/app/models/application_record.rb` or a new dedicated class; `app-webclient/src/app/user/user.component.ts` and `.html`; potentially `app/app/workers/user_activity_document/consumer.rb` if the bulk path is in scope.

**Dependencies:** Step 1 (scope clarification) blocks every other step — this is the item's real risk, not its size.

**Acceptance criteria:** cannot be written precisely until step 1 resolves; provisionally, "disabling a user surfaces the groups they belong to/manage and lets the operator choose an action before the disable completes."

## Task 4 — Goal audit (Finding 9)

**Estimate: cannot be responsibly given without a scope conversation.** The June figure (8 days) may be pricing a real gap on top of `PlanGoalAudit`, or may be a stale estimate against a feature that has since shipped in some form.

**Steps:**
1. **Blocker** — ask whoever wrote the June-11 list what "auditoria de metas" is meant to cover, specifically relative to the existing `PlanGoalAudit` (`app/app/models/plan_goal_audit.rb:1-13`, shipped 2025-12-05, checks for missing user goals per plan — frontend at `app-webclient/src/app/plan-goal-audit/`).
2. If the answer is "a history of goal value changes over time" — check `UserGoalHistory` (`db/schema.rb:2269`, `create_table "user_goal_histories"`) as a possible existing foundation before scoping new work.
3. If the answer is "an audit of goal-document uploads, parallel to UserHistory" — the nearest sibling pattern is `app/app/models/user_history.rb` plus its work_book at `app/app/work_books/user_history_work_book/`, shipped `3.48.0`/`3.49.0` (per `app/CHANGELOG.md:173,163`) — a plausible template to scope hours against once step 1 answers what is being asked.

**Files touched:** unknown until scoped.

**Dependencies:** step 1 blocks everything.

**Acceptance criteria:** none written — this task cannot be estimated responsibly until the specification gap is closed.

## Task 5 — Filter persistence (Finding 10)

**Estimate: 15 days IF scoped to a bounded list of screens; larger if "every listing" is meant literally** (121 files use `Filter` today).

**Steps:**
1. **Blocker to resolve first** — get the engineer to name the specific screens Atento México actually re-visits and complains about (the request likely originated from a handful of frequently-used listings, not all 121). Candidates to propose, given what this spike already touched: `partial`/`compensation` listings (subject of the already-delivered item 5, SOW 2.4, so likely the same audience), `statement`/`plan-statement` listings, `user` listing.
2. Design the persistence mechanism once the screen list is bounded — options include a shared Angular service wrapping `localStorage` keyed by route, or extending the existing per-screen `Filter` class (`app-webclient/src/app/shared/filter.model.ts:62-119`) with a save/restore pair. No existing pattern to copy: `grep -rln "localStorage" .../app-webclient/src/app/shared` found nothing.
3. Implement per scoped screen, following whichever pattern step 2 settles on.
4. Confirm the already-shipped "Shared and override filter defaults in the plans list" fix (`app-webclient/CHANGELOG.md:65`, `1.281.0`) is compatible with (not superseded by) the new persistence mechanism, since both touch filter defaults on the same screen family.

**Files touched:** a new shared service (likely under `app-webclient/src/app/shared/`), plus one component pair (`.ts`/`.html`) per scoped screen.

**Dependencies:** step 1 (scope) blocks step 2 (design) blocks step 3 (implementation).

**Acceptance criteria:** provisional, pending step 1 — "the filter selections on [named screens] survive a page reload and a return visit within the same browser."

## Task 6 — Sábana / consolidated calendar report (Finding 11)

**Estimate: 20 days for the report alone; +10 days if the salary column ships in the same release (field encryption, currently untracked as its own item).** See `SPIKE.md` § Trade-offs for the two readings.

**Steps (report engineering, assuming the salary column is deferred — Option in `SPIKE.md` Trade-offs table, row 1):**
1. Design the consolidation query: for a company + period, enumerate every non-disabled plan on the calendar, then every `UserCommission` under each, grouped by `user_id` (an employee in more than one plan needs one row, not one row per plan) — no existing code performs this grouping; the closest analog, `CommissionReportCreationBatch` (`app/app/models/commission_report_creation_batch.rb:1-16`), is `belongs_to :period` but produces per-plan reports, not a per-user rollup.
2. Build a new work_book (following the `app/app/work_books/<name>_work_book/` pattern already used by `statement_audit_work_book`, `user_history_work_book`, etc.) with columns per the SOW's Category A mapping (`STATEMENT-OF-WORK-v2.md:144-164`): hierarchy (Coordinador/Supervisor identifiers and names, via `Seat`), employee identifiers, group name, points/percentage/limiter results, final monetary value, per-payment-type commission values (reuse Task 2's `UserPaymentTypeCommission` exposure), operational indicators (`AggregatedIndicator`), and payment-approval status.
3. Wire Category B columns fed via `Field` (Centro, Login/AC, Fecha de Ingreso — `STATEMENT-OF-WORK-v2.md:170-176`) — these need no new development per the SOW's own text ("the extra-fields feature already exists").
4. Build the producer/consumer/finalizer worker set and frontend trigger + download UI, following the pattern of the most recently shipped batch export (`statement_audit_work_book` / `StatementAudit`, `3.48.0`).
5. Explicitly exclude the salary column and the two Category C columns (Observaciones, Aclaraciones — `STATEMENT-OF-WORK-v2.md:179-184`) from this iteration; document the exclusion in the PR description per the client-communication caution already recorded in `DELIVERY-TRACKING.md:86` (a partial delivery must be labeled as such, not announced as the complete feature).

**Steps (if salary is in scope for the same release — add before step 2 above):**
1. Add `encrypts :value, deterministic: true` (or equivalent, following `app/app/models/user.rb:258`'s pattern) to `Field` (`app/app/models/field.rb`), migrate `fields.value` (`db/schema.rb:822-830`) and `user_field_snapshots.value` (`db/schema.rb:2257-2267`) across every environment, and adjust every process that reads/writes `Field` values.
2. Confirm with the engineer whether Validation Rules (SOW 2.7, 120h, recommended-not-mandatory per `STATEMENT-OF-WORK-v2.md:136-138`) should land first to guarantee data quality before the encrypted salary is exported at scale.

**Files touched:** new `app/app/work_books/<sabana>_work_book/`, a new model/producer/consumer/finalizer set under `app/app/models/` and `app/app/workers/`, a new frontend module under `app-webclient/src/app/`; if salary is included, also `app/app/models/field.rb`, a new encryption migration, and every call site that reads/writes `Field.value`.

**Dependencies:** the salary column depends on field encryption (currently untracked as its own backlog item); the SOW recommends but does not require Validation Rules (2.7) first.

**Acceptance criteria:**
- One row per employee, spanning every active plan in the selected period, with columns matching SOW Category A + B (minus salary if deferred).
- Available before final payment approval, with a payment-approval status column, per `STATEMENT-OF-WORK-v2.md:134` ("Available at any point in the process ... with payment-approval status flagged").
- The PR description states explicitly whether the salary column is included, so the delivery is not misrepresented to the client (per the `DELIVERY-TRACKING.md:86` caution).
