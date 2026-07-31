# SPIKE — Barigui Roadmap: Code-Grounded Task Breakdown

## Investigation question

Break the seven Barigui demands from the 2026-07-13 meeting (Adriano Silva,
Luigi Hespanhol) into PR-sized tasks with dependencies, checkable acceptance
criteria, and a day estimate per task — grounded in the actual code of `app`
(Rails backend) and `app-webclient` (Angular front), not in the meeting text
alone. This feeds a delivery roadmap the client will receive, so every
estimate below traces to a citation an engineer can re-verify.

Repos read at: `app` commit `611d5a5c80d9ecd42df90e325615d178a153a8d4`,
`app-webclient` commit `f1920fb6bed46c477028113d90df1994ad48f278` (both
`develop`, captured 2026-07-30, after the `app` repo's 3.60.0 release the
engineer flagged).

## Sources consulted

- `~/Projects/4Shark/app-webclient/src/app/dashboard/plan/dashboard-plan.component.ts` — the seller/manager dashboard: ranking, indicator charts, seat-based guards. Full copy: `roadmap-barigui_excerpt_1.ts`.
- `~/Projects/4Shark/app-webclient/src/app/dashboard/plan/dashboard-plan.component.html` — same component's template. Full copy: `roadmap-barigui_excerpt_2.html`.
- `~/Projects/4Shark/app/app/graphql_resolvers/user_aggregated_user_commission_dataset_graphql_resolver.rb` and `~/Projects/4Shark/app/app/models/user_commission_dataset/user_aggregator.rb` — the backend behind the ranking widget. Full copy: `roadmap-barigui_excerpt_3.rb`.
- `~/Projects/4Shark/app/app/graphql_types/query_type.rb:247` — field wiring for the ranking resolver (quoted inline below).
- `~/Projects/4Shark/app/app/scopes/user_scope.rb`, `~/Projects/4Shark/app/app/scopes/hierarchy_scope.rb` — existing user-scoping precedent. Copied inline in `roadmap-barigui_excerpt_3.rb`.
- `~/Projects/4Shark/app-webclient/src/app/plan-statement/plan-statement-show/plan-statement-show.component.ts` and its `.html` — the plan-acceptance flow (collapse/expand + signature lock). Full copies: `roadmap-barigui_excerpt_4.ts`, `roadmap-barigui_excerpt_5.html`.
- `~/Projects/4Shark/app-webclient/src/app/statement/statement-show/statement-show.component.ts` and its `.html` — the second, independent acceptance flow with the same mechanism. Partial copies: `roadmap-barigui_excerpt_6.ts`, `roadmap-barigui_excerpt_7.html`.
- `~/Projects/4Shark/app-webclient/src/app/plan-statement/plan-statement-accept/plan-statement-accept.component.scss` and `~/Projects/4Shark/app-webclient/src/app/statement/statement-accept/statement-accept.component.scss` — the signature-pad modal styling (demand 5).
- `~/Projects/4Shark/app/app/models/variable.rb` (frequency enum), `~/Projects/4Shark/app/app/models/seat.rb` (seat-type hierarchy), `~/Projects/4Shark/app/db/schema.rb` (companies table, `manager_legal_module`/`operator_legal_module` precedent). Excerpts: `roadmap-barigui_excerpt_8.rb`.
- `~/Projects/4Shark/app-webclient/src/app/variable/variable.component.ts` — the established generic infinite-scroll listing pattern used across ~90 other entities. Full copy: `roadmap-barigui_excerpt_9.ts`.
- `~/Projects/4Shark/app-webclient/CHANGELOG.md` (lines 1-140) — dates the infinite-scroll rollout and the already-shipped signature-lock feature. Excerpt: `roadmap-barigui_changelog_1.md`.
- `~/Projects/4Shark/app-webclient/src/app/shared/filter.model.ts` — confirms no generic `sort` field exists in the shared Filter model.
- `~/Projects/4Shark/app/docs/architecture/DASHBOARD_DENORMALIZATION.md` — architecture doc explaining the Mongo aggregation/denormalization the ranking widget is built on.
- `find ~/Projects/4Shark/app-webclient/src -name "*.spec.ts"` — confirms exactly 7 spec files exist in the whole front-end, none at the feature layer touched by these demands.
- `find ~/Projects/4Shark/app/spec` — confirms no aggregator specs and no resolver specs exist for the ranking backend; a `spec/requests/graphql_resolvers/` directory convention exists for other resolvers (e.g. `graphql_controller_variable_audit_resolver_spec.rb`) but none covers this one.
- [graphql-ruby.org — Using Connections](https://graphql-ruby.org/pagination/using_connections) — confirms a resolver returning a plain Array under a `.connection_type` gets `first`/`after` pagination automatically, without extra GraphQL-layer code.

## Findings

### Finding 1: The dashboard ranking is capped at 10 records inside the Mongo pipeline, not at the GraphQL layer

**Evidence:**
```ruby
# app/models/user_commission_dataset/user_aggregator.rb:26-28 (by_calendar)
pipeline.push({ '$sort': order_by })
pipeline.push({ '$limit': 10 })
UserCommissionDataset.collection.aggregate(pipeline).to_a
```
The identical `{ '$limit': 10 }` appears again at `user_aggregator.rb:50-52` inside `by_plan`. The resolver's declared return type is `UserCommissionDatasetGraphqlType.connection_type` (`user_aggregated_user_commission_dataset_graphql_resolver.rb:10`), and the field is wired with `field :user_aggregated_user_commission_datasets, resolver: UserAggregatedUserCommissionDatasetGraphqlResolver` (`query_type.rb:247`) — no explicit `connection: true` needed since the resolver's own `type` ends in `.connection_type`.

**Significance:** graphql-ruby's own documentation states: *"With connection fields, you can return collection objects from fields or resolvers: the collection object (Array, Mongoid relation, Sequel dataset, ActiveRecord relation) will be automatically paginated with the provided arguments."* (graphql-ruby.org/pagination/using_connections). Because the aggregator already returns a plain Ruby `Array` (`.to_a`) into a field typed as a connection, the GraphQL layer already knows how to honor `first`/`after` — the only thing standing between "10 max" and a browsable, paginated ranking is the two `$limit: 10` lines inside the Mongo pipeline itself. This directly explains the original ask ("raise the limit from 10 to 20-30") and shows the agreed solution (separate page, infinite scroll) is buildable on the SAME connection-type field, once the hardcoded cap is replaced with something bounded by the actual candidate set (see Finding 2) rather than a flat number.

### Finding 2: No resolver argument exists today for "search by user" or "filter by manager"

**Evidence:**
```ruby
# app/graphql_resolvers/user_aggregated_user_commission_dataset_graphql_resolver.rb:4-8
argument :calendar_id, ID, required: false
argument :sort, String, required: false
argument :period_id, ID, required: false
argument :plan_id, ID, required: false
argument :user_id, ID, required: false
```
There is no `search` or `manager_id` argument. `grep -rln "manager_id\|managerId\|immediate_manager\|parent_id" app/graphql_resolvers app/models` found no existing manager-scoping resolver argument anywhere in the backend. Two candidate building blocks exist but neither is a drop-in fit: `HierarchyScope` (`app/scopes/hierarchy_scope.rb`) resolves the FULL recursive descendant subtree of a seat, not direct reports only —
```ruby
# app/scopes/hierarchy_scope.rb:5-7
hierarchy_sql =
  "(WITH RECURSIVE hierarchy(id) AS (SELECT id FROM seats WHERE id = #{user.seat.id} " \
  'UNION ALL SELECT seats.id FROM hierarchy JOIN seats ON seats.parent_id = hierarchy.id) SELECT id FROM hierarchy)'
```
— and `Seat.belongs_to :parent, polymorphic: true` (`app/models/seat.rb:10`) confirms "immediate manager" is `seat.parent`, so a narrower, non-recursive scope (`User.joins(:seat).where(seats: { parent_id: manager.seat.id })`) would need to be written new; nothing in the codebase does this today.

**Significance:** "search by user" and "filter by immediate manager" are both new resolver arguments requiring new `$match` stages in the Mongo pipeline. Search-by-name is a cross-store operation: Mongo holds only `user_id` (per `DASHBOARD_DENORMALIZATION.md` §1, *"Documents store IDs and computed values, never names"*), so a name search must first resolve matching `user_id`s from PostgreSQL (via a `User` search scope — not directly verified to exist; `Variable` has `pg_search_scope :search_for` at `variable.rb:94` as the established pattern shape) and then feed those IDs into the existing `user_id: { '$in': [...] }` match clause already used for the `user_id` argument.

### Finding 3: The seller ("SalesRepresentative") dashboard already hides the ranking and the plan average — but not the manager's name or the group signature percentages

**Evidence:**
```html
<!-- dashboard-plan.component.html:108, 118 (ranking and average boxes) -->
<div class="col-12 col-lg-2 current-user-seat" *ngIf="currentUserSeat != 'SalesRepresentative'">
  ...selectedUserRanking...
</div>
<div class="col-12 col-lg-2 current-user-seat" *ngIf="currentUserSeat != 'SalesRepresentative'">
  ...selectedUserMoney vs averageMoneyUser...
</div>
```
```html
<!-- dashboard-plan.component.html:156-158 (manager name — NOT guarded) -->
<div
  class="col-12"
  [class]="currentUserSeat != 'SalesRepresentative' ? 'col-lg-2 current-user-seat' : 'col-lg-3'"
>
  <!-- user.parent (immediate manager) name always renders; only the column width changes -->
```
```html
<!-- dashboard-plan.component.html:268-270 (plan signature %, and 286-288 for statement signature % — NOT guarded) -->
<div class="col-12 col-lg-3">
  <div class="box-widget-new">
    <div class="variable-remuneration">
      <ng-container *ngIf="plan?.totalAcceptedStatements > 0; else withoutAcceptedPlanStatementsTemplate">
```
Both un-guarded boxes sit OUTSIDE any `currentUserSeat` condition — they render for every seat type including `SalesRepresentative`. The whole "employee ranking" section further down (`dashboard-plan.component.html:600` onward, per the full copy) IS correctly guarded with `*ngIf="currentUserSeat != 'SalesRepresentative'"`.

**Significance:** the demand names four things to remove from the seller's screen — plan average, group ranking, immediate manager name, group signature percentage. Two of the four (plan average, group ranking) are ALREADY hidden from `SalesRepresentative`. The other two (manager name, both signature percentages) are NOT guarded anywhere and render unconditionally. This is consistent with Luigi's own framing — "part of this may be a bug rather than intended behaviour" — the codebase shows a partially-applied rule, not an absent one. Fixing the two un-guarded boxes is a same-shape, mechanical change (add the identical `*ngIf` already used two lines above); no backend change is implied. The "segmentation by access level" language in the demand is NOT reflected in the code beyond this binary `SalesRepresentative` vs. everyone-else split — `Seat::TYPES` (`seat.rb:7-8`) names a 10-level hierarchy (`SuperAdmin` down to `SalesRepresentative`) that the dashboard template never branches on.

### Finding 4: The indicator "back" panel always renders a line chart; `Variable.frequency` (including `monthly`) is not even fetched by the dashboard query

**Evidence:**
```ruby
# app/models/variable.rb:68-79
enumerize :frequency,
          in: {
            daily: 0,
            weekly: 1,
            monthly: 2,
            single: 3
          },
```
```typescript
// dashboard-plan.component.ts:891-911 (getVariables query)
const variableShowQuery = `query Variables($type: String, $planId: ID) {
  variables (
    type: $type
    planId: $planId
  ) {
    nodes {
      id
      name
      dataType
      metric {
        id
      }
    }
  }
}`;
```
No `frequency` field is requested. The corresponding template branch (`dashboard-plan.component.html`, "back" face of the indicator widget) renders `<app-line-charts>` unconditionally based on `variable.dataType` only — never on `variable.frequency`.

**Significance:** the fix is a small, well-contained change: add `frequency` to the existing query, and add one more conditional branch alongside the three existing `dataType` branches (`NumberDataType`/`PercentDataType`/`DurationDataType`) that renders a prominent number instead of `<app-line-charts>` when `variable.frequency === 'monthly'`. No schema or resolver change is needed — `frequency` already exists on the `Variable` model; only whether `VariableGraphqlType` already exposes it as a field needs a quick confirmation (not verified in this spike — the `Variable` GraphQL type file was not read).

### Finding 5: The collapse/expand + signature lock mechanism already shipped on 2026-07-28 — six days after the meeting — in the OPPOSITE default polarity from what Barigui is asking for

**Evidence:**
```markdown
<!-- CHANGELOG.md, [1.281.0] - 2026-07-28 -->
### Added
- Full-content view for the rule declaration
- Full-content view for the result declaration
- Full content review required before signing a declaration
- Guidance when a declaration must be fully expanded to sign
### Fixed
- Panel collapse while reviewing a declaration
- Forced-acceptance details on the rule declaration
```
```typescript
// plan-statement-show.component.ts:217-219
if (this.shouldExpandOnLoad || (this.planStatement.actions && this.planStatement.actions.includes('accept'))) {
  this.expandPanels(true);
}
...
readyToSign() {
  return this.allExpanded() && !this.loading;
}
```
```html
<!-- plan-statement-show.component.html:421 -->
<button class="menu-button" (click)="openSignatureDialog()" [disabled]="!readyToSign()">
```
The identical shape exists independently in `statement-show.component.ts:223-225` (`this.reviewing = true` on `actions.includes('accept')`) and `statement-show.component.ts:945-951` (`isExpanded()` falls back to `this.reviewing` when a panel has no individually-set `.expanded`), gated the same way at `statement-show.component.ts:1037-1038` (`readyToSign()`).

**Significance:** the signature LOCK (cannot sign until every section is opened) is done, in production, in both flows. What is NOT done — and directly contradicts Barigui's ask — is the DEFAULT state: today, whenever a plan/statement can be accepted, EVERY section auto-expands on load (`expandPanels(true)` / `reviewing = true`). Barigui wants collapsed-by-default, forcing an active click per section. Atento Brasil's stated preference (expanded for the end user signing their own statement, collapsed for an administrator reviewing someone else's) is a THIRD, role-dependent polarity that the current code does not implement at all — the auto-expand trigger today is `actions.includes('accept')` (can this viewer sign it), not "is this viewer the statement's own user". Distinguishing "the end user" from "an administrator" is derivable from data already in both queries (`planStatement.user.id` / `statement.user.id`) compared against the logged-in user's own ID — which neither component currently fetches or compares (the `me`-query pattern already exists elsewhere, e.g. `dashboard-plan.component.ts:135-141`).

### Finding 6: No PDF export code exists in either repository — the item-4/Atento cross-client dependency could not be confirmed in code

**Evidence:** `grep -rli pdf app-webclient/src/app --include="*.ts"` returned only `invoice.component.ts` (unrelated — trade/invoice feature). `grep -rli pdf app/app --include="*.rb"` returned only `StatementPortableWorkBook`/`PlanStatementPortableWorkBook` files, which read and checksum ALREADY-EXISTING signed-statement PDF attachments into an audit workbook (`app/work_books/statement_portable_work_book/statements_work_sheet.rb:39-41`, *"Reads one PDF into memory at a time... so the footprint stays bounded to a single statement PDF"*) — this is a batch export of prior signatures, not a generator for the rule/formula declaration PDF the meeting describes. No `wicked_pdf`, `Prawn`, or equivalent PDF-generation gem appears in `app/Gemfile`.

**Significance:** the meeting recorded that the collapse/expand work would be built "alongside the PDF export work requested by Atento Brasil," implying a scheduling or shared-component dependency. Nothing in either repo currently implements that PDF export, so the coupling cannot be verified as a CODE dependency — it may be a planning/scheduling decision made in the meeting with no technical coupling yet, or the PDF export may be genuinely unbuilt and this spike cannot assess its shape or size. This should be treated as an open question for the engineer, not as a confirmed blocking dependency.

### Finding 7: The formula-hiding request (demand 7) touches at least 11 render sites across 3 files, in 2 different structural shapes

**Evidence:** the "description + always-visible formula" pattern repeats:
- `dashboard-plan.component.html:397-420` (1 occurrence — "Meus Incentivos" panel)
- `plan-statement-show.component.html` — 5 occurrences at lines 137-155 (deal), 182-200 (indicator), 262-280 (ranking), 307-325 (limiter), 352-370 (redemption); each shares this exact shape:
```html
<div *ngIf="rule.description; else noRuleDescription">
  ...
  <span class="show-item-value bold">{{ 'plan_statement.page.formula' | translate }}:</span>
  <span class="show-item-value">{{ rule.value }}</span>
  ...
</div>
<ng-template #noRuleDescription>
  <span>{{ rule.value }}</span>
</ng-template>
```
- `statement-show.component.html` — 5 more occurrences at lines 163-217 (deal), 265-300 (indicator), 377-413 (rankifier), 423-460 (limiter), 470-499 (redemption); here the fallback is at the PANEL HEADER, not per-rule:
```html
<span class="show-panel-header-tittle">{{
  indicatorCommissioning.rule.description
    ? indicatorCommissioning.rule.description
    : indicatorCommissioning.rule.value
}}</span>
```

**Significance:** none of these 11 occurrences is a shared component or partial — each is a hand-repeated block. Any change needs to preserve the existing fallback logic exactly: when `rule.description` is blank, the formula is the ONLY content available and must stay visible (both shapes already encode this — an `else` template in one file, a ternary in the other) — hiding the formula unconditionally would leave some rules with nothing displayed at all. The two structural shapes (per-rule fallback vs. panel-header fallback) mean a single shared component cannot be dropped in without first deciding whether to unify the two shapes (a design decision, not made here) or build two variants.

## Trade-offs surfaced

| Approach (demand 1 — ranking pagination) | Pros | Cons | Source |
|---|---|---|---|
| Remove `$limit: 10`, let `first`/`after` bound the page size via the existing connection type | No GraphQL-layer code needed; matches the pattern used by ~90 other listings | Loads the FULL matching set into the Ruby-level Array before pagination slices it (graphql-ruby's ArrayConnection is in-memory) — needs a sane upper bound (e.g. cap at a few hundred) since a very large team's aggregation would otherwise load unboundedly | graphql-ruby.org/pagination/using_connections; `user_aggregator.rb:27,51` |
| Push search/manager filtering into the Mongo `$match` BEFORE removing the limit | Shrinks the in-memory set to exactly what the engineer is looking for, independent of the pagination question | Requires resolving name-search and manager-filter to `user_id` lists from PostgreSQL first (cross-store), adding one more query round-trip per ranking request | `DASHBOARD_DENORMALIZATION.md` §1 (IDs-only in Mongo); `hierarchy_scope.rb` |

| Approach (demand 4 — collapse default) | Pros | Cons | Source |
|---|---|---|---|
| One company-level boolean (mirrors `manager_legal_module`/`operator_legal_module`) deciding collapsed-vs-expanded default | Matches an existing, precedented shape in the schema and in Ruby call sites | Does not by itself cover Atento's ask (expanded for END USER, collapsed for ADMIN on the SAME company) — that axis is about the VIEWER's relationship to the statement, not the company | `db/schema.rb:518,521`; `commission.rb:298-301,329-330` |
| Compare `current_user.id` against `planStatement.user.id`/`statement.user.id` to distinguish end-user from admin, and use that (instead of, or combined with, a company flag) to pick the default | Directly matches Atento's stated need without inventing a new axis | Neither `PlanStatementShowComponent` nor `StatementShowComponent` currently fetches or compares the logged-in user's own ID against the record's owner — new query fields + new comparison logic in both components | `plan-statement-show.component.ts` (no such comparison exists); `dashboard-plan.component.ts:135-141` (the `me` query pattern to reuse) |

## What remains uncertain

- **Demand 3 — Luigi's screen URLs/IDs.** The demand text says Luigi still owes concrete URLs/IDs for the parts he was unsure about. This spike found that the manager-name and signature-percentage boxes are un-guarded in `dashboard-plan.component.html` specifically — but the demand may also refer to OTHER screens this spike did not search for (the note only names this one dashboard component as read). If Luigi's screens turn out to be different pages, this finding does not transfer to them automatically.
- **Demand 4 — the PDF-export dependency.** Per Finding 6, no PDF-generation code exists in either repo today. Whether the scheduling coupling the meeting recorded is still intended, already superseded by the 1.281.0 shipment, or needs re-confirming with Atento's side is outside what the code can answer.
- **Demand 4 — whether 1.281.0 already satisfies part of Barigui's ask.** The signature LOCK is done; only the DEFAULT expand/collapse state remains open, and this spike could not determine from the code alone whether Barigui has already seen and accepted (or rejected) the 1.281.0 behavior.
- **Demand 5 — root cause of "small text".** No mobile-specific `@media` rule exists in either signature-accept component's SCSS (verified by direct grep — zero matches in both files). The fixed `width="400" height="170"` canvas (`plan-statement-accept.component.html:7`) is a plausible candidate on a narrow viewport, but this is a hypothesis, not a confirmed defect — a screenshot or device repro from Luigi is needed before this can be sized with confidence.
- **Demand 6 — which screen "navegar entre vendedores" refers to.** Two candidate interpretations were investigated: (a) the generic entity-listing filter/scroll-position split found in `variable.component.ts` (filter VALUES persist via `route.queryParams`; scroll DEPTH does not, since `endCursor` resets on every params change), and (b) the dashboard ranking's own `userSort` field, which has no persistence mechanism at all (no `Filter.sort` field exists — confirmed in `filter.model.ts`). Neither could be confirmed as THE screen the demand means without asking which one Luigi/Adriano had in mind.
- **Demand 2 — whether `VariableGraphqlType` already exposes `frequency`.** The Ruby model has the field; the GraphQL type file itself was not read in this spike, so whether the schema already exposes it (making this a pure front-end change) or needs a one-line addition on the backend is unconfirmed.
- **Whether `User` has a name-search scope equivalent to `Variable.search_for`** (`variable.rb:94`), needed for demand 1's "search by user". Not directly verified — only the shape (`pg_search_scope`) is established elsewhere.

## Suggested options for main and the engineer

The table below is a task decomposition consistent with the evidence above —
not a mandated sequence. Ordering reflects technical dependency only; the
engineer decides delivery priority.

| # | Task | Repo | Depends on | Estimate | Why this size |
|---|------|------|------------|----------|----------------|
| 1a | Remove the hardcoded `$limit: 10` in `UserCommissionDataset::UserAggregator#by_plan`/`#by_calendar`; add `search` and `manager_id` resolver arguments with matching `$match` stages; bound the result set explicitly (per Trade-offs table) | `app` | none | 2 days | Two symmetric aggregator methods to change identically (Finding 1); one new non-recursive manager scope to write (Finding 2, no existing scope fits); a cross-store name search to wire (Finding 2); zero existing specs for this aggregator or resolver to extend — new spec files needed, following the `spec/requests/graphql_resolvers/graphql_controller_<name>_resolver_spec.rb` naming convention found elsewhere |
| 1b | New "full ranking" page/route + component + service, mirroring the `variable.component.ts` infinite-scroll + `Filter`/`queryParams` pattern; search input, manager-filter control, existing 4-option sort reused; "ver mais" link added from the dashboard's employee section | `app-webclient` | 1a | 2.5 days | New component+template+service scaffold sized against the ~150-line established pattern (`roadmap-barigui_excerpt_9.ts`); manual QA checklist in place of tests (0 feature-layer spec files exist in this repo) covering scroll, search debounce, manager filter, and all 4 sort options |
| 2 | Add `frequency` to the `getVariables()` query in `dashboard-plan.component.ts`; branch the indicator "back" panel to render a totalizer number instead of `<app-line-charts>` when `frequency === 'monthly'` | `app-webclient` (+ possible 1-field `app` GraphQL type check) | none | 1 day | One field added to an existing query, one new conditional branch alongside three already-existing `dataType` branches (Finding 4); size assumes the GraphQL type already exposes `frequency` — unconfirmed, see "What remains uncertain" |
| 3 | Guard the immediate-manager box and both signature-percentage boxes in `dashboard-plan.component.html` with the same `*ngIf="currentUserSeat != 'SalesRepresentative'"` already used two lines above each | `app-webclient` | Luigi's screen confirmation (partial) | 1 day | Mechanical, same-shape template edit at 3 sites (Finding 3); plan-average and group-ranking need NO work — already correctly guarded. Manual QA across seat types since there is no test at this layer |
| 4 | Change the default expand/collapse state in BOTH `PlanStatementShowComponent` and `StatementShowComponent` from "auto-expand when action includes accept" to a decided default; add the `current_user.id` vs. statement-owner comparison needed for Atento's end-user/admin polarity; decide and add the per-company or per-viewer toggle | `app` (migration + GraphQL field) + `app-webclient` (both components) | Engineer decision on the Trade-offs table; PDF-export coupling unconfirmed (Finding 6) | 3 days | Two independent components share the SAME mechanism but are NOT DRY (Finding 5) — each needs its own fix; new schema migration + GraphQL field following the `manager_legal_module` precedent shape (Finding 5, Trade-offs); new owner-comparison query field + logic in both components, none of which exists today |
| 5 | Reproduce the mobile signature text-size issue on a real/emulated device; fix once the exact cause (candidate: fixed 400×170 canvas, or absence of a mobile breakpoint) is confirmed | `app-webclient` | Luigi's screenshot/repro | 0.5 day once cause is confirmed; not yet estimable | No code defect found by static reading — zero `@media` rules in either signature-accept SCSS (Finding/uncertainty on demand 5) |
| 6 | Fix filter/state persistence for whichever screen "navegar entre vendedores" turns out to mean | `app-webclient` | Confirmation of which screen (uncertain) | Not yet estimable | Two candidate root causes identified (scroll-depth reset in the generic listing pattern; no persistence at all for the ranking's own sort field) — sizing requires knowing which one is in scope |
| 7 | Build a formula-behind-a-button/popup component; replace the 11 inline `rule.value` renders across 3 files, preserving the existing "no description → formula is the only content" fallback at each of the 2 distinct shapes found | `app-webclient` | none (independent of 4, but shares the same "declaration" screens) | 3 days | 11 call sites across 3 files, 2 distinct fallback shapes to preserve exactly (Finding 7); a new shared component needs building since none of the 11 sites currently shares one; manual QA per incentive type, no test convention at this layer |

Cross-cutting notes:

- **1a → 1b** is a hard dependency: the frontend page cannot search/filter/paginate before the backend arguments exist.
- **Task 4** and **Task 7** both touch the same "declaration" screens (`plan-statement-show`, `statement-show`) but are otherwise independent — sequencing between them is a scheduling choice, not a technical dependency.
- **Task 3**'s "segmentation by access level" language, if it means more than the current binary `SalesRepresentative`/other split, is not sized here — the evidence (Finding 3) only supports fixing the two un-guarded boxes at the binary level already in place elsewhere in the same template.
