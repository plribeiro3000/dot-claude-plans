# SPIKE — Atento México Backlog Revalidation

## Investigation question

Revalidate the Atento México backlog (the 2026-06-11 meeting list, with day estimates) against the current state of `app` and `app-webclient` (`develop`, verified against `origin/develop` on 2026-07-30, the day `3.60.0` shipped), and turn it into PR-sized tasks with a day estimate per task. For each item: is it already delivered, is the June estimate still accurate, or has the code moved enough to change it? For "sabana" (20 days, deprioritized), establish what it actually requires instead of carrying the round number forward.

## Sources consulted

- `app/CHANGELOG.md` — every entry from `3.20.4` (2026-03-31) through `3.60.0` (2026-07-30), read in full.
- `app-webclient/CHANGELOG.md` — every entry from `1.271.1` (2026-06-18) through `1.282.0` (2026-07-30), read in full.
- `git -C ~/Projects/4Shark/app fetch origin develop` / `git -C ~/Projects/4Shark/app-webclient fetch origin develop`, then `rev-list --left-right --count origin/develop...HEAD` on both repos — `0	0` on both, confirming the local checkout is exactly current with the remote before any code claim was made.
- `~/Projects/4Shark/dot-claude-plans/active/content/atento-mexico-development-list/DELIVERY-TRACKING.md` — a prior internal tracking document (2026-07-28) reconciling a 9-item numbered client list against both changelogs and a 2026-07-28 engineer call. Used as a corroborating source, re-verified independently against code below rather than cited as ground truth on its own.
- `~/Projects/4Shark/dot-claude-plans/active/content/atento-mexico-development-list/PLAN.md` — references a "Pedidos Clientes" spreadsheet with a distinct Atento slice, including the exact wording "Atento BR — Desativação de usuários, popup p/ retirar de grupos (P3, 4d)".
- `~/Projects/4Shark/dot-claude-plans/active/spike/atento-mexico-improvements/STATEMENT-OF-WORK-v2.md` — the formal, 17-request SOW dated 2026-02-27, with hour estimates per item. Read in full; used to cross-check scope and dependencies for Sábana and the payment-type item.
- Direct code reads and `git log`/`git show` on both repos, cited per finding below.
- See auxiliary: `roadmap-atento-mexico_tasks_1.md` — PR-sized task breakdowns (steps, dependencies, acceptance criteria) for every item not yet delivered.

**Two backlogs exist and do not fully overlap.** The engineer's 2026-06-11 list (13 items as given, matching the "~12" recollection closely) is a more granular internal breakdown than the formal SOW's 9 client-numbered requests. Six of the thirteen items map cleanly onto SOW requests or onto entries the SOW explicitly marks as "no-cost adjustments." The remaining items (goal audit, filter persistence, the deactivation/group popup, the transaction state filter) do not appear anywhere in the SOW text — they trace to the separate "Pedidos Clientes" spreadsheet referenced in `PLAN.md` or to conversations not captured in either internal document. This split is noted per item below rather than assumed away.

## Findings

### Finding 1: Bulk user deactivation via upload — DELIVERED

**Evidence:**

```ruby
# app/app/workers/user_activity_document/consumer.rb:27-43
if user
  if user_activity_document_row.action == 'deactivate'
    if user.id == owner.id
      DocumentError.with_uncached_connection do
        @user_activity_document
          .document_errors
          .create(error_key: 'cannot_disable_self', line: user_activity_document_row.document_line, resource: 'User')
      end
    elsif User.with_uncached_connection { user.disable(by: owner.id) }
      UserActivityDocumentEnrollment.with_uncached_connection do
        @user_activity_document
          .enrollments
          .create(action: :deactivate, user_id: user.id, document_line: user_activity_document_row.document_line)
      end
```

`app/CHANGELOG.md:286` — `- Bulk user deactivation by spreadsheet` under `## [3.40.1] - 2026-06-18` (`app/CHANGELOG.md:272`). `app/CHANGELOG.md:259` — `- Bulk user activation by spreadsheet` under `## [3.41.0] - 2026-06-22` (`app/CHANGELOG.md:255`). `app-webclient/CHANGELOG.md:181` — `- Bulk user activation and deactivation by spreadsheet` under `## [1.272.0] - 2026-06-25` (`app-webclient/CHANGELOG.md:177`).

**Significance:** Both backend versions and the frontend release predate the 2026-06-11 meeting's own reference point only slightly (3.40.1 shipped six days after 2026-06-11) — this item was already in flight or just-shipped when the June estimate (2-3 days) was recorded, and is fully in production now. No remaining work.

### Finding 2: Bulk group creation via upload — DELIVERED

**Evidence:**

```
$ git -C ~/Projects/4Shark/app show --stat faafb97f5
Tue Jun 30 10:16:37 2026 -0300 faafb97f5 feat(group-document): add bulk group creation  [Emerson Silva]
 app/workers/group_document/consumer.rb                    |  49 ++++
 app/workers/group_document/finalizer.rb                    |  25 ++
 app/workers/group_document/producer.rb                     |  55 ++++
 ...
 36 files changed, 1053 insertions(+), 6 deletions(-)
```

`app/app/models/group_document.rb:1-6` defines `GroupDocument < Document` with a Producer/Consumer/Finalizer worker set at `app/app/workers/group_document/`. `app/CHANGELOG.md:200` — `- Bulk group creation` under `## [3.45.0] - 2026-06-30` (`app/CHANGELOG.md:196`). `app-webclient/CHANGELOG.md:140` — `- Bulk group creation` under `## [1.274.0] - 2026-06-30` (`app-webclient/CHANGELOG.md:136`).

**Significance:** Delivered by the same engineer (Emerson Silva) who, per the 2026-07-29 alignment, was "finishing a user-update task" — consistent with Emerson working the upload-family items in sequence (deactivation → group creation → user update). Frontend UI exists at `app-webclient/src/app/group-document/`. No remaining work.

### Finding 3: Upload error ordering, error list export, plan listing by creation date — ALL THREE DELIVERED

**Evidence:** `app/CHANGELOG.md:49-58` (`## [3.59.0] - 2026-07-28`):

```
### Added
- Document error report download
- Newest-first plan listing order

### Fixed
- Document error listing order
```

`app-webclient/CHANGELOG.md:48-60` (`## [1.281.0] - 2026-07-28`) carries the frontend halves: `- Document error report download` (Added, line 56) and `- Plan listing order` (Changed, line 60).

**Significance:** These three June-11 items ("ordenação de erros de upload", "exportação da lista de erros", "listagem de planos por data de criação") are the same three items the prior `DELIVERY-TRACKING.md` (§ "Outside the numbered list") documented as shipped and, in the error-report-download case, already announced to the client on 2026-07-28. This spike independently confirms the changelog citations above rather than trusting that document's claim. No remaining work.

### Finding 4: Statement audit — pending and canceled plan states — DELIVERED

**Evidence:**

```ruby
# app/app/work_books/statement_audit_work_book/statements_work_sheet.rb — diff from commit bc05cafb2
+            row << I18n.with_locale(@company.locale) { plan.status_text }
+
+            row << if plan.disabled?
+                     I18n.with_locale(@company.locale) { I18n.t('boolean.yes') }
+                   else
+                     '-'
+                   end
```

`git -C ~/Projects/4Shark/app show --stat bc05cafb2` — commit titled `feat(statement-audit): add time window filter and fix canceled plan status`, dated `Mon Jul 6 11:48:10 2026 -0300` (author leandroalmeida27). Also filters plans by `Plan.where(...).where(status: %i[final canceled])` when a time window is applied (same diff, line `plan_ids = ...`). `app/CHANGELOG.md:178` — `- Statement audit report status for canceled plans` under `## [3.48.0] - 2026-07-07` (`app/CHANGELOG.md:169`). The statement's own pending/accepted state is already a column: `row << I18n.with_locale(@company.locale) { statement.accepted?.humanize }` (same file), backed by `Statement#pending?` at `app/app/models/statement.rb:37-39` (`acceptment.nil?`).

**Significance:** The audit worksheet now surfaces both dimensions the June item names — the statement's own pending/accepted status (pre-existing column) and the plan's canceled status (added by this commit, plus a `disabled_plan` flag). No remaining work.

### Finding 5: State filter on transactions — ALREADY EXISTED, predates the backlog

**Evidence:**

```html
<!-- app-webclient/src/app/trade/reward-transaction/reward-transaction.component.html:56-60 -->
<select [(value)]="filter.status" (change)="selectStatus($event)">
  <option value="">{{ 'filter.status' | translate }}</option>
  <option value="pending">{{ '4s_incentive.status.pending' | translate }}</option>
  <option value="processing">{{ '4s_incentive.status.processing' | translate }}</option>
  <option value="final">{{ '4s_incentive.status.final' | translate }}</option>
</select>
```

Backed by `scope :for_status, ->(status) { where(status: status) if status.present? }` (`app/app/models/reward_transaction.rb:28`) and exposed via `option(:status, type: String) { |scope, status| scope.for_status(status) }` (`app/app/graphql_resolvers/reward_transactions_graphql_resolver.rb:16`). `git -C ~/Projects/4Shark/app-webclient log --oneline -3 -- src/app/trade/reward-transaction/reward-transaction.component.html` shows the two most recent touches are `41fffeae4` (2026-02-09, "replace legacy transaction type references") and `1216f2dfa` (2026-01-30, "rename incentive campaign domain to reward/voucher") — neither commit introduced the status select, they only renamed it in place.

**Significance:** If "transações" in the June backlog means reward/voucher transactions (`RewardTransaction`), a status filter has existed since at least January 2026 — before the backlog was written. Two readings follow: either this item is stale (already satisfied, the estimator was unaware) or "transações" refers to a different listing this spike did not identify (a candidate checked and ruled out: `UserPayment` carries `for_integration_status` and `for_payment_type` scopes at `app/app/models/user_payment.rb:35,37` but no generic `for_status`; no UI search for a `UserPayment` status filter turned up a match). This is flagged under "What remains uncertain" rather than resolved.

### Finding 6: "Remuneración variable" naming — NOT DELIVERED, mechanism already exists

**Evidence:**

```json
// app-webclient/src/translations/es/models/deal.json:56
"variable_remuneration_achieved": "Retribución variable alcanzada",
```

Rendered at `app-webclient/src/app/statement/statement-show/statement-show.component.html:166,315,390,436` via `{{ 'deal.variable_remuneration_achieved' | translate }}`. There is no `es-MX`-specific locale folder (`find .../src/translations -maxdepth 1 -type d` returns only `pt-BR`, `es`, `en`) — every Spanish-speaking client shares this one string.

A client-specific override mechanism already exists and is in production for other strings: `git -C ~/Projects/4Shark/app-webclient show --stat 4d07805ff` (`feat(i18n): layer client translation overrides at build time`, author Paulo Ribeiro, merged as PR #6580) added `src/environments/atento-mx/translations/{en,es,pt-BR}/models/{seat,user,user_document}.json`, layered at build time per `build.js:6-15` (`[overrideSelector] Translation override folder under src/environments/<selector>/translations, layered on top of the base translations`). `find ~/Projects/4Shark/app-webclient/src/environments/atento-mx -type f` shows the three existing override files but no `deal.json` — the override for this specific string does not exist yet.

**Significance:** The June estimate (1 day) is still accurate, and arguably conservative — the existing override mechanism means this is a single new JSON file (`src/environments/atento-mx/translations/es/models/deal.json`, and the `atento` sibling if it needs the same fix) with one key, no core-file change, and no risk to other Spanish-locale clients.

### Finding 7: Results declaration broken down by payment type — NOT DELIVERED, but the backend is already fully wired

**Evidence:**

```ruby
# app/app/models/user_payment_type_commission.rb:1-27
class UserPaymentTypeCommission < ApplicationRecord
  belongs_to :payment_type, optional: true, inverse_of: :user_payment_type_commissions
  belongs_to :user_commission, optional: true, inverse_of: :user_payment_type_commissions
  has_many :commissionings, dependent: :destroy, inverse_of: :user_payment_type_commission
  ...
  def reset_attributes!
    update(deal_money: 0, deal_points: 0, limiter_money: 0, limiter_points: 0, modifier_money: 0, modifier_points: 0,
           money: 0, points: 0, ranking_money: 0, ranking_points: 0, redemption_money: 0)
  end
end
```

`app/app/models/user_commission.rb:12` — `has_many :user_payment_type_commissions, dependent: :destroy, inverse_of: :user_commission` — the association exists. The GraphQL surface is further along than a first pass suggested: `app/app/graphql_types/user_commission_graphql_type.rb:34` already declares `field :user_payment_type_commissions, [UserPaymentTypeCommissionGraphqlType], null: true`, and the type it points to, `app/app/graphql_types/user_payment_type_commission_graphql_type.rb:1-21`, exposes `deal_money`, `limiter_money`, `ranking_money`, `redemption_money`, `money`, `points`, and `payment_type` (`PaymentTypeGraphqlType`) per row — the backend is complete and in production. What is missing is the frontend: `grep -rln "userPaymentTypeCommission" .../app-webclient/src/app` returns nothing, and the result-declaration screen's own query (`app-webclient/src/app/statement/statement-show/statement-show.component.ts:160-205`) asks `userCommission { dealMoney limiterMoney indicatorMoney ... }` — broken down by commission TYPE (deal/limiter/indicator/ranking/redemption), never requesting `userPaymentTypeCommissions` at all.

**Significance:** This is narrower than a name-only reading suggests — the model, association, GraphQL type, and field are already shipped; the entire remaining scope is adding `userPaymentTypeCommissions { ... }` to one existing query and rendering a breakdown table on the statement-show page. The June estimate (2-3 days) is generous for what is now a frontend-only task, unless the display requirements (grouping, totals, formatting per payment type) need more design than a straight table.

### Finding 8: Deactivation flow with group management — NOT DELIVERED

**Evidence:** The generic disable path is `app/app/models/application_record.rb:135-151`:

```ruby
def disable(by: nil)
  if disabled?
    errors.add(:id, :already_inactive)
    return false
  end

  result =
    if respond_to?(:disabler_id)
      update(disabled_at: Time.zone.now, disabler_id: by)
    else
      update(disabled_at: Time.zone.now)
    end

  delete_external_id_cache if result
  result
end
```

Nothing here touches group membership or group management (no cascade to `Group`, `Seat`, or any successor concept). `app/app/models/group.rb:5` carries only `belongs_to :disabler, class_name: 'User', ...` — a group can itself be disabled by a user, but nothing runs the other direction. The frontend disable action (`app-webclient/src/app/user/user.component.html:277-316`) is a single confirm-and-execute control with no group-related step; `grep -n "disable\|confirm\|group" .../user.component.html` shows no popup or modal referencing groups.

`~/Projects/4Shark/dot-claude-plans/active/content/atento-mexico-development-list/PLAN.md:61` records the same request under the "Pedidos Clientes" spreadsheet's Atento slice, verbatim: `Atento BR — Desativação de usuários, popup p/ retirar de grupos (P3, 4d)` — a 4-day estimate, matching the June figure exactly.

**Significance:** Two independent sources (this spike's code search, and the separate spreadsheet reference in `PLAN.md`) agree the feature does not exist and estimate it at 4 days. The June estimate holds. What the feature needs is undocumented beyond the one-line spreadsheet entry — "popup to remove from groups" implies a confirmation dialog surfaced on disable, letting the operator choose what happens to the groups the disabled user belonged to or managed, but no design exists yet to confirm scope (e.g., does it also cover the manager-successor case for a `Seat`, given `SeatAction`'s `promote`/`change_manager`/`demote` actions at `app/app/models/seat_action.rb:18` are a distinct, already-built mechanism for seat succession?).

### Finding 9: Goal audit — UNCERTAIN, an existing but narrower feature already covers part of the name

**Evidence:**

```ruby
# app/app/models/plan_goal_audit.rb:1-13
class PlanGoalAudit < Audit
  has_many :rows, class_name: 'PlanGoalAudit::Row', foreign_key: :audit_id, inverse_of: :plan_goal_audit, dependent: :destroy

  def self.lock_key(plan_id:)
    "plid.#{plan_id}.plan_goal_audit"
  end
  ...
end
```

`git -C ~/Projects/4Shark/app log --oneline --follow -- app/models/plan_goal_audit.rb` shows a single commit, `ed4926aa6`, dated `2025-12-05` per `git log -1 --format="%ad %s" --date=short ed4926aa6`: `feat(audit): add plan goals audit for missing user goals`. The worker set at `app/app/workers/plan_goal_audit/` (`producer.rb`, `group_consumer.rb`, `user_consumer.rb`, `finalizer.rb`) was last touched `2026-01-28` per `git log -1 --format="%ad" --date=short -- app/workers/plan_goal_audit`. A frontend screen exists at `app-webclient/src/app/plan-goal-audit/`.

**Significance:** `PlanGoalAudit` already ships, and it predates the 2026-06-11 meeting by over four months — this is strong evidence it is a *different* feature than whatever "auditoria de metas" refers to (an estimator would not price a shipped, four-month-old feature at 8 days), rather than evidence the June item is done. This spike found nothing else under a "goal audit" name, and neither the SOW nor the "Pedidos Clientes" excerpt in `PLAN.md` mentions goal auditing at all — the request traces to neither internal reference document available. What "auditoria de metas" is meant to add on top of the existing missing-goals check (a history of goal value changes? an audit of goal-document uploads over time, parallel to `UserHistory`? something else) could not be established from the sources searched. **Not found: a specification for this item beyond its name and its 8-day estimate.**

### Finding 10: Filter persistence — NOT DELIVERED, scope likely larger than 15 days once bounded

**Evidence:**

```typescript
// app-webclient/src/app/shared/filter.model.ts:62-119 (excerpt)
export class Filter implements FilterAttributes {
  afterDate: string;
  approverId: string;
  ...
  constructor(attr: FilterAttributes) { ... }
}
```

`Filter` is populated per-screen from the URL's query params (e.g. `app-webclient/src/app/trade/reward-transaction/reward-transaction.component.ts:45-58`: `this.route.queryParams.subscribe((params: Filter) => { this.filter = new Filter(params); ... })`) — nothing persists it beyond the current URL. `grep -rln "new Filter(" .../app-webclient/src/app | wc -l` returns **121** files. The closest existing work is narrower: `app-webclient/CHANGELOG.md:65` — `- Shared and override filter defaults in the plans list` under `## [1.281.0] - 2026-07-28`, a *default-value* fix scoped to one listing, not cross-session persistence.

**Significance:** No localStorage/sessionStorage-backed filter store exists anywhere in the codebase (`grep -rln "localStorage" .../app-webclient/src/app/shared` returns nothing). 121 call sites use the `Filter` class today. The June estimate of 15 days is plausible only if the item is scoped to a handful of high-traffic listings (the ones Atento México actually re-visits) rather than "every listing" — at 121 sites, a uniform treatment would cost substantially more. This is the item most likely to need a scope conversation before an estimate can be trusted either way.

### Finding 11: Sábana (consolidated calendar report) — NOT STARTED, and the 20-day figure likely does not include a dependency the SOW itself documents

**Evidence — nothing has been built:**

```
$ git -C ~/Projects/4Shark/app log --oneline --all --grep="sabana" -i
(no output)
$ gh -R 4shark/app pr list --search "sabana" --state all --limit 20
(no output)
```

**Evidence — the report needs a consolidation shape nothing in the codebase currently produces.** The closest existing batch mechanism, `CommissionReportCreationBatch` (`app/app/models/commission_report_creation_batch.rb:1-16`), is scoped `belongs_to :period` and produces one `CommissionReportCreationEvent` per report — a batch of *per-plan* reports, not a single row-per-employee table spanning every plan. The other candidate, `StatementPortableBatch::Consumer` (`app/app/workers/statement_portable_batch/consumer.rb:13-28`), renders **PDF**, one file per employee, by opening the webclient in headless Chromium and printing it (`Ferrum::Browser.new`, `browser.go_to(...)`, `browser.pdf(path: file_path.to_s)`) — a fundamentally different deliverable from a consolidated Excel table.

**Evidence — the salary column has a documented, unimplemented prerequisite.** `~/Projects/4Shark/dot-claude-plans/active/spike/atento-mexico-improvements/STATEMENT-OF-WORK-v2.md:175-177`:

> `Sueldo Mensual | Extra employee field (encrypted) — feed via upload with the monthly salary` ... `Secure storage of the monthly salary is enabled by deliverable 3.1 (extra-fields encryption).`

The field this depends on is `Field` (`app/app/models/field.rb:1-15`, the "extra employee field" model — `belongs_to :user`, a key/value pair). Its schema carries no encryption today: `db/schema.rb:822-830` — `create_table "fields" ... t.string "value", limit: 8000` — a plain string column, and `field.rb` declares no `encrypts` call, unlike `app/app/models/user.rb:258` (`encrypts :unique_register_id, deterministic: true`), which is the pattern this would need to follow. The related snapshot table that would also need encryption once statements start carrying salary data, `user_field_snapshots` (`db/schema.rb:2257-2267`), has the identical plain-string shape.

**Significance — the scope question the 20-day figure needs answered before it can be trusted.** The SOW prices this dependency as a *separate* line item: 3.1 "Encryption of extra employee fields" at 80h (10 days), distinct from 3.2 "Sábana" at 160h (20 days) — `STATEMENT-OF-WORK-v2.md:192-196`. The SOW's own "Conditions" for 3.2 name only Validation Rules (2.7, 120h) as a *recommended* (not mandatory) precondition (`STATEMENT-OF-WORK-v2.md:136-138`); it does not list encryption as a blocking condition in that section, even though Category B of the same document says the salary column specifically depends on it. The June 11 backlog carries a single "sabana" line at 20 days with no separate encryption item anywhere in the 13-item list this spike was given. Two readings follow, and they produce different total costs: (a) the 20-day estimate is for the report engineering only, and the salary column ships in a later iteration once encryption (a separate, currently-untracked 10-day item) is done — 20 days is then defensible for the report itself; (b) the 20-day estimate is assumed to include a complete report matching the client's full "TBL General" column set (which explicitly includes "Sueldo Mensual") — in which case the true cost is closer to 20 + 10 = 30 days before Validation Rules (2.7) is even factored in as the SOW's own recommended precondition.

Also relevant: item 12 above (results by payment type, Finding 7) resolves one of Sábana's Category A columns ("Comisión | Monetary values per payment type") ahead of time if it ships first — the same `UserPaymentTypeCommission` data this spike found backend-ready for the statement-show page is exactly what Sábana's payment-type column needs.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Ship Sábana without the salary column first, add it once field encryption lands | 20-day estimate holds; report delivers value (indicators, hierarchy, payment-type results) immediately | Client's own spreadsheet ("TBL General") includes salary — a report without it is a partial answer to the original ask, same shape as item 4 (employee history export) which `DELIVERY-TRACKING.md` already flagged as "a partial delivery, not a complete one" | `STATEMENT-OF-WORK-v2.md:172-177`; `DELIVERY-TRACKING.md:86` (partial-delivery precedent) |
| Ship Sábana complete, including salary, after encryption lands | One announcement, full scope, matches the client's ask exactly | Adds a ~10-day (80h) prerequisite not currently tracked as its own backlog item, pushing the effective delivery point past 20 days from now | `STATEMENT-OF-WORK-v2.md:122-126, 192-196` |
| Scope filter persistence to a short list of high-traffic screens | 15-day estimate becomes defensible against a bounded set | Leaves 100+ other `Filter`-using screens unpersisted, so "filter persistence" as a platform-wide claim would be inaccurate if announced that way | This spike's `grep -rln "new Filter(" \| wc -l` = 121 |

## What remains uncertain

- **"Filtro de estado nas transações"** — a status filter and UI select already exist for `RewardTransaction` since at least January 2026 (Finding 5). Whether the June item refers to this listing (making it stale) or a different "transaction" concept entirely (e.g. `UserPayment`, which has no generic status filter) was not resolved by this spike.
- **"Auditoria de metas"** — an existing `PlanGoalAudit` (missing-goals check, shipped December 2025) is the closest match by name, but its age relative to the backlog argues it is a different ask. No specification for what the June item should add was found in the SOW, the "Pedidos Clientes" excerpt, or the codebase (Finding 9).
- **Sábana's true scope** — whether the 20-day estimate is meant to include the salary column (and therefore implicitly the encryption prerequisite) is not settled by any source this spike read (Finding 11).
- **Filter persistence's true boundary** — which screens, if fewer than all 121 `Filter` call sites, is not specified anywhere found (Finding 10).
- **The "2 or 3 remain" recollection from 2026-07-29** — this spike's tally is 6 items delivered, 1 item already existing before the backlog (stale or misidentified), and 6 items genuinely open (naming, results-by-payment-type, deactivation/group popup, goal audit, filter persistence, Sábana). That is 6 open, not 2-3. Not found: a narrower "current sprint" scope that would reconcile the two counts — this discrepancy is reported as-is rather than resolved.

## Suggested options for main and the engineer

- **Option A — Treat the 6 confirmed-delivered items as closed and remove them from the active backlog**, keeping only the 6-7 genuinely open items (naming, payment-type breakdown, deactivation/group popup, goal audit, filter persistence, Sábana, plus the transaction-filter item pending clarification) in the tracked list going forward.
- **Option B — For Sábana specifically, split it into two tracked items matching the SOW's own split** (3.1 field encryption, ~10 days; 3.2 the report itself, ~20 days) rather than one 20-day line, so the dependency is visible in the backlog instead of implicit.
- **Option C — For filter persistence, scope a short list of screens with the engineer before re-estimating**, rather than either assuming 15 days covers all 121 call sites or re-deriving a number without a bounded list.
- **Option D — For the two ambiguous items (transaction state filter, goal audit), get one line of clarification from whoever wrote the June list** before spending engineering time — both could be zero-cost (already done, or a naming collision with an existing feature) or could be real, unscoped work.
