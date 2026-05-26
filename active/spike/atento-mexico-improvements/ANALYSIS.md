# ANALYSIS — Atento México Improvements

> **Phase:** Technical analysis complete — all implementation items analyzed.
> **Input:** `ANALYSIS-v2.md` (decisions), `KNOWLEDGE.md` (domain context)
> **Scope:** Covers the 9 items marked for implementation (A1–A9). Will NOT implement (#8, #10, #11, #13), Training (#5, #17), and Operational fixes (#15, #16) are out of scope here — see `ANALYSIS-v2.md` for those decisions.
> **Principle:** Open-Close — don't break existing flows, extend with new ones. Every feature must benefit all clients, not just Atento México.

---

## A1. Monthly Usage: User Registration Date (#1)

**Client request:** Add user registration date to the Monthly Usage drill-down screen.

**Code analysis:**
- Backend: `UserGraphqlType` already exposes `created_at` — no changes needed
- Frontend: `monthly-usage-responsibility.component.ts` queries `user { name }` — just add `createdAt` to the query and a column to the template

**Decision:** Frontend-only change. Add `createdAt` to the GraphQL query and a new column in the drill-down table.

**Impact:** Frontend only (1 component)
**Effort:** Trivial — less than 1 hour

---

## A2. Simplified Report — Payment Summary per Employee (#2)

**Client request:** When employees are promoted/transferred or during audits, HR needs a summary of all approved payments per employee over a date range. Today this requires manually downloading and consolidating data from multiple places.

**Code analysis:**

The system already has a feature that consolidates ALL historical data per user: **UserHistory**.

### Existing Feature — UserHistory

**Model:** `UserHistory` (`app/models/user_history.rb`)
- Per-user snapshot created on demand (admin triggers it)
- Status machine: `processing` → `final`
- Links ALL historical records for that user via join tables:

| Sub-history | Model | Data |
|-------------|-------|------|
| Payments | `UserPaymentHistory` → `UserPayment` | `billable_money`, `points`, `payment_type { name, external_id }`, `payment { name, status }` |
| Indicators | `UserIndicatorHistory` → `Indicator` | output values, variable name, compiled_at |
| Transactions | `UserDealHistory` → `Deal` | date, value, type |
| Groups | `UserGroupificationHistory` → `GroupificationHistory` | group name, start/end dates |
| Hierarchy | `UserSeatHistory` → `SeatHistory` | seat kind, parent, start/end dates |
| Goals | `UserGoalHistory` → `Goal` | value, type, variable, start/end dates |
| Plan Statements | `UserPlanStatementHistory` → `PlanStatement` | plan name/status/goal, acceptment |
| Statements | `UserStatementHistory` → `Statement` | accepted_at, commission plan |

**Processor:** `UserHistory::Processor` (`app/workers/user_history/processor.rb`)
- Sidekiq worker (queue: `document_processing`)
- Iterates each data type, links ALL records for the user (no period filter — brings everything)
- Finishes by transitioning status to `final`

**Frontend:** `user-history-show.component.ts`
- Shows all 8 sections on a single page
- Each section paginated (9 items per page) with "load more"
- **Problem:** With hundreds of records over time, pagination makes it impractical to see the full picture

### Decision — Add Excel export to UserHistory

Instead of creating a new report type (which would need a new screen with no natural place in the system flow), extend UserHistory with Excel export capability. This feature already collects exactly the data the client needs — and more.

**Why this approach is better:**
- No new screen or navigation path needed — the page already exists
- No new data collection logic — Processor already gathers everything
- The client gets MORE than just payments — full historical context (indicators, groups, hierarchy changes, goals, plan statements, etc.)
- Follows the existing report generation pattern (PaymentReport → PaymentWorkBook)

### What to Build

**Backend:**
1. `UserHistoryWorkBook` — new WorkBook following `PaymentWorkBook` pattern
   - One sheet per data section (Payments, Indicators, Transactions, Groups, Hierarchy, Goals, Plan Statements, Statements)
   - Payment sheet columns: payment name, status, payment_type name, payment_type external_id, billable_money, points
   - Other sheets follow the same data already shown in the frontend
2. Report generation mechanism — reuse the same pattern as `PaymentReport`:
   - Attachment on UserHistory (or a new `UserHistoryReport` model if needed for lock/expiration)
   - Worker to generate Excel async
   - GraphQL mutation to trigger export
3. Reference files:
   - `app/work_books/payment_work_book.rb` — WorkBook pattern
   - `app/work_books/payment_work_book/results_by_payment_type_sheet.rb` — Sheet pattern with user data + payment type columns
   - `app/workers/payment/report_generator.rb` — async report generation pattern
   - `app/graphql_mutations/create_payment_report_graphql_mutation.rb` — mutation pattern

**Frontend:**
- Add "Export Excel" button to `user-history-show.component.ts`
- Show download link when report is ready (same UX as PaymentReport downloads)

**Impact:** Backend + Frontend
- Backend: new WorkBook + sheets + worker + mutation + attachment handling
- Frontend: 1 button + download link on existing page

**Effort:** Medium — 2-3 days. The WorkBook/Sheet pattern is well established. Main work is creating sheets for each data section and wiring up the async generation flow.

---

## A3. Complete Report (Sábana) — Consolidated Control Spreadsheet (#3)

**Client request:** Atento México manually maintains a ~120-column Excel spreadsheet ("TBL General" / "Sábana General") consolidating all operational indicators and bonus calculation results across 130 plans for financial control and auditing.

### Two Distinct Problems

This request covers **two separate problems** that must be delivered independently:

1. **Contractual obligation (Sábana report):** Atento México has a contract with Banco de México that requires them to deliver a consolidated file in a specific format. This is non-negotiable — the bank expects this file.
2. **Data validation (Validation Rules):** They need to ensure indicator values are correct before they propagate through calculations and reach payments. Today they do this manually at the end (reviewing the sábana); the system should catch errors at the entry point.

**Delivery strategy:** Validation Rules first (higher value, lower effort, prevents the problem at the source). Sábana report second (contractual requirement, higher effort, blocked by column mapping session).

### What Exists Today

**CommissionWorkBook** (`app/work_books/commission_work_book.rb`) generates a report **per individual plan** with 7 sheets:

1. **SummaryWorkSheet** — one row per user: name, register_type, unique_register_id, external_id + monetary breakdown (deal_money, modifier_money, ranking_money, limiter_money, redemption_money, billable_money) + points + acceptment
2. **IndicatorWorkSheet** — one row per user: user data + one column per Variable with `AggregatedIndicator.output` (calculated value)
3. DealWorkSheet, RankingWorkSheet, LimiterWorkSheet, RedemptionWorkSheet, IndicatorPremiumWorkSheet

**AggregatedIndicator** (`app/models/aggregated_indicator.rb`) — calculated/aggregated value per user × variable × commission. Method `calculate!` applies aggregation logic (sum, average, last) with frequency and override handling. Method `output` returns the formatted value.

**Variable** (`app/models/variable.rb`) — indicator template/definition. Properties: `data_type` (Number, Percent, String, Boolean, Date, Duration), `calculation` (average, sum, last), `frequency` (daily, weekly, monthly, single). **Has NO validation rules for min/max values** — accepts any value on upload.

### Strategy 1 — Validation Rules (deliver first)

**Objective:** New resource — "Validation Rule" — associated to each Variable. Configurable rules that reject or flag invalid indicator data at upload time, before it propagates to calculation and payment.

**Examples of rules:**
- Quality score (PercentDataType) cannot exceed 100%
- Number of calls (NumberDataType) cannot be negative
- TMA cannot be greater than 1,000
- Any min/max/range constraint the client defines per variable

**Key design decisions:**

#### 1. Validation Rule as a separate entity (not fields on Variable)
Each Variable has a menu of validation rules. The client creates, configures, and manages rules per variable. This is a full CRUD resource, not just min/max fields.

#### 2. Activation/deactivation with history — NOT delete
Rules **cannot be simply deleted**. If a rule was active and blocked indicator uploads, then the user deletes the rule, there's no audit trail for why data was rejected during that period.

Instead:
- Rules can be **activated** and **deactivated** at any time
- The system maintains a **history of when each rule was active**
- This provides auditability: "From date X to date Y, this rule was active — indicators with values outside the range were rejected during this period"

**Data model:**
- `validation_rules` table — the rule definition (belongs_to variable, rule_type, min_value, max_value, etc.)
- `validation_rule_periods` table — activation history (belongs_to validation_rule, activated_at, deactivated_at)
- A rule is "active" when it has an open period (activated_at set, deactivated_at null)
- Deactivating a rule closes the current period (sets deactivated_at)
- Reactivating creates a new period

#### 3. Enforcement at all entry points
Validation must apply everywhere indicator data enters the system:
- **Upload** (IndicatorDocument::Processor) — reject row if value violates active rules
- **API** (if indicators are pushed via integration) — reject with error
- **Manual entry** (UI forms) — validate client-side + server-side

This adds runtime overhead but solves the real problem: catching errors at entry instead of discovering them at payment time.

#### 4. Error behavior
When a rule is violated during upload: the row is rejected with a `DocumentError` including the line number, variable name, offending value, and which rule was violated. Same all-or-nothing approach as other documents — or configurable per variable (strict vs. tolerant).

**What to build:**

**Backend:**
1. Migration: `validation_rules` table (variable_id, rule_type, min_value, max_value, description)
2. Migration: `validation_rule_periods` table (validation_rule_id, activated_at, deactivated_at)
3. `ValidationRule` model — belongs_to Variable, has_many ValidationRulePeriods
4. `ValidationRulePeriod` model — belongs_to ValidationRule, scope `active` (deactivated_at nil)
5. `ValidationRule::Validator` service — given a value + variable, checks all active rules
6. Hook into `IndicatorDocument::Processor` — call validator before accepting each row
7. Hook into indicator API endpoints and manual creation mutations
8. GraphQL types, resolvers, mutations for CRUD + activate/deactivate

**Frontend:**
- Validation Rules management section within Variable detail/edit screen
- List of rules per variable with status (active/inactive)
- Create/edit rule form (rule type, min/max values)
- Activate/deactivate toggle with confirmation
- History view showing all activation periods

**Impact:** Backend + Frontend
**Effort:** Medium — 3-5 days. New entity with lifecycle management, integration at multiple entry points, frontend CRUD.

### Strategy 2 — Consolidated Report (Sábana)

**Objective:** Report per calendar that consolidates ALL plans into a single table. One row per employee, columns = employee data + all indicators from all plans + calculation results per payment type + payment status.

**BLOCKED:** The column mapping session with the client has not happened yet. Some columns in their current spreadsheet (~120 columns) don't exist in ForShark (e.g., "centro", "login AC", "fecha de ingreso"). Until we know which columns the system can provide vs. which need new development, we cannot design the report structure.

**Context:** This report exists because Banco de México requires it contractually. It's not optional — it must be delivered eventually.

**Data available in the system today:**

| Data | Model | Access |
|------|-------|--------|
| Employee data | User | name, register_type, unique_register_id, external_id |
| Indicator values | AggregatedIndicator | via user_commission.aggregated_indicators → output |
| Monetary breakdown | UserCommission | deal_money, modifier_money, ranking_money, limiter_money, redemption_money, billable_money |
| Payment status | CommissionPayment → Payment | if Payment with status >= final exists = "paid approved" |
| Plan/group | Commission → Plan → Group | plan name, group name |

**Architecture (preliminary — subject to change after column mapping):**
- New model: `CalendarReport` (belongs_to calendar, belongs_to company) — scoped per calendar
- New WorkBook: `CalendarReportWorkBook` — iterates all plans in the calendar, builds dynamic columns
- Async batch processing — with ~10,000 users × 130 plans, cannot be real-time
- Dynamic columns based on the union of all Variables across all plans in the calendar
- Status column: "paid approved" vs "not paid approved" (Luis confirmed two states is sufficient)

**What the sábana essentially is:** The CommissionWorkBook's SummaryWorkSheet + IndicatorWorkSheet fused together and multiplied across all 130 plans. The challenge is dynamic column generation — each plan has different variables.

**Impact:** Backend + Frontend
**Effort:** High — 7-10 days (after column mapping session defines the exact column set)
**Dependency:** Column mapping session with Atento México must happen first

---

## A4. Bulk User Update via Upload (#4)

**Client request:** Allow updating existing users via the same file upload used for creation (~20 users/fortnight for name corrections, status changes).

**Code analysis:**
- Backend: `UserDocument::Processor` processes CSV line by line, always calls `User.new` + `save` — if user exists (match by email+company or unique_register_id), validation fails and row is rejected
- CSV layout: 14 columns (email, password, first name, last name, unique_register_id, city, state, external_id, department, seat_type, parent_seat_id, subsidiary_id, register_type, parent_subsidiary_id)
- Frontend: upload component is generic — no changes needed

**Decision:** Backend-only change. Modify `UserDocument::Processor` to detect existing users by unique identifier and update instead of rejecting. Rules:
- If user does not exist → create (current behavior)
- If user exists → update fields that are non-empty in the CSV
- Password column is ignored for existing users (password reset is a separate flow)
- Audit: log which users were created vs updated in document results

**Impact:** Backend only (1 worker)
**Effort:** Medium-Low — 1-2 days. Core logic is simple, care needed for field update rules and audit trail.

---

## A5. Bulk Import of Groups (#6)

**Client request:** Create groups in bulk via file upload instead of one by one through the UI.

**Code analysis:**
- `Group` model: simple entity with 2 required fields — `name` (unique per company) and `external_id` (unique per company, alphanumeric)
- `GroupDocument` currently exists but does **Groupification** (associating users to existing groups), NOT group creation. Uses Producer/Consumer pattern with `GroupDocument::Row`.
- Manual group creation form: just 2 fields — `name` and `externalId`
- Document patterns for entity creation exist: `UserDocument::Processor` (single-pass), `DealDocument` (Producer/Consumer with find_or_initialize_by)

**Decision:** Two-step implementation:

### Step 1 — Rename GroupDocument → GroupificationDocument
The current `GroupDocument` name is misleading — it does groupification, not group management. Rename it to match its actual purpose before creating the real `GroupDocument`.

Scope:
- Backend: rename model, workers (Producer, Consumer, Finalizer), Row model, GraphQL types/mutations/resolvers
- Migration: `UPDATE documents SET type = 'GroupificationDocument' WHERE type = 'GroupDocument'`
- Frontend: rename components, services, routes, translations
- Tests: update all references

### Step 2 — Create new GroupDocument (group creation)
Follow the existing Document pattern to create groups via file upload.

Scope:
- Backend: new `GroupDocument < Document` model, `GroupDocument::Processor` (single-pass like UserDocument), GraphQL mutations
- CSV layout: `name`, `external_id` (same 2 fields as manual creation)
- If group already exists (name or external_id collision), register `DocumentError` and continue
- Frontend: new upload component with help template, reusing existing upload services (S3 pre-signed URL, attachment)

Existing flows (manual group creation, groupification upload) remain untouched.

**Impact:** Backend + Frontend (rename ~8-10 files + new model/processor/component)
**Effort:** Medium — 2-3 days. Rename is mechanical but extensive; new document follows established pattern.

---

## A6. Bulk Import of Plans (#7)

**Client request:** Create 130 plans/month via file upload instead of one by one through the UI.

**Code analysis:**
- Plan creation requires: name, type, goal, calendar_id, group_id, and at least 1 incentivation (incentive_id + payment_type_id pair)
- Optional: budget, description, override, shared, policy_document, responsible_ids
- After creation, callback `create_variables` creates PlanVariable for each variable linked to incentives
- No PlanDocument or bulk creation mechanism exists today
- **IncentiveDocument** already solves a similar complexity problem — multi-line CSV with `#####` separator between incentives, conditional rules per type, external_id lookups for Group/Client/Product. This is the reference pattern for PlanDocument.
- **Incentive model does NOT have `external_id`** — only internal `id`. Group, Client, Product all have `external_id`.

**Key decisions:**

### 1. Multiple payment types per plan — mandatory
Each incentivation is a pair of incentive + payment type. A plan can have multiple incentivations with different payment types. This is fundamental for Brazilian labor law compliance. The CSV must support multiple incentive:payment_type pairs per plan.

### 2. No incentive export — add external_id to Incentive instead
Exporting incentives would expose 4Shark's business intelligence (all calculation rules). Instead, add an `external_id` field to the Incentive model (unique per company, like Group and PaymentType already have). The client manages their own external IDs and references those in the CSV.

This requires:
- Migration: add `external_id` (string) to `incentives` table with unique index per company
- Update IncentiveGraphqlType to expose `external_id`
- Update IncentiveDocument::Processor to support `external_id` on creation
- Update Incentive creation form/mutation to accept `external_id`
- Frontend: add `external_id` field to incentive forms

### 3. Use IncentiveDocument as the reference pattern
The IncentiveDocument already handles multi-entity CSV with `#####` separators, conditional processing per type, and external_id lookups. The PlanDocument should follow the same approach:

**CSV format (inspired by IncentiveDocument):**

```
plan_name,description,type,goal,calendar_id,group_external_id,budget,override,shared
incentive_external_id,payment_type_external_id
incentive_external_id,payment_type_external_id
responsible_external_id (optional)
#####
next_plan_name,description,type,goal,...
...
#####
```

Each plan block:
- Line 1: Plan header (basic fields)
- Lines 2-N: Incentivation pairs (incentive_external_id + payment_type_external_id)
- Optional: responsible user lines (if needed)
- `#####`: separator between plans

**Validation — all-or-nothing:**
As requested by Luis in the meeting — reject entire file if any plan has errors. Two-pass processing:
1. Parse and validate all plans (dry-run)
2. If all valid → create all plans
3. If any error → fail with detailed error report (line number + error description)

**Processing flow:**
1. Producer reads file, splits by `#####` separator
2. First pass: validate all plan blocks (lookups, field validation, incentivation validation)
3. If errors → mark document as `failed` with all DocumentErrors
4. If clean → second pass: create all plans with incentivations
5. After create callback handles `create_variables` automatically

**Lookup strategy (all by external_id):**
- Calendar: by `id` (internal — calendars are few, easy to reference)
- Group: by `external_id` (via `Group.get_id`)
- Incentive: by `external_id` (NEW — needs migration first)
- PaymentType: by `external_id` (already exists)
- Responsible users: by `external_id` or identifier (already exists)

**Dependencies:**
- A5 must be delivered first (groups must exist)
- Incentive `external_id` migration must be done first (prerequisite within this item)

**Impact:** Backend + Frontend
- Backend: migration (incentive external_id) + new PlanDocument model + Producer/Consumer workers + GraphQL mutations + update IncentiveDocument processor + update incentive forms
- Frontend: new upload component + help template + add external_id to incentive creation/edit forms

**Effort:** High — 5-7 days. Most complex document due to multi-entity relationships, all-or-nothing validation, and the prerequisite of adding external_id to incentives. The IncentiveDocument pattern reduces risk significantly.

---

## A7. Additional Columns in Partials Listing (#9)

**Client request:** Add group name, number of collaborators, and final generated amount to each row in the Partials listing.

**Code analysis:**
- Listing today: 4 columns (ID, Plan name, Period, Status) — query from Postgres only
- PartialCommission model has monetary fields (`money`, `billable_money`, etc.) but these are totals, not hierarchy-filtered
- Hierarchy filtering uses recursive CTE (`HierarchyScope`) — admin sees all, manager sees their team
- Computed/aggregated data lives in MongoDB (used for dashboards)
- The team already has a pattern of enriching Postgres responses with Mongo data in serializers

**Architectural decision: Postgres listing + per-item Mongo aggregation in serializer**

The listing stays in Postgres. The GraphQL resolver/serializer enriches each item with computed data from MongoDB. This is the same pattern already used in other parts of the application.

**How it works:**
1. Postgres serves the paginated listing as today (plan name, status, period, etc.)
2. For each item in the page, the serializer runs a Mongo aggregation:
   - Filters by `partial_commission_id`
   - Applies hierarchy filtering based on the current user's org position
   - Returns `collaborator_count` (distinct users) and `total_amount` (sum of money)
3. Each Mongo aggregation is small — filters by a single commission ID first, bringing ~50 records to memory on average (worst case ~5,000 for one specific large client)
4. 9-20 Mongo aggregations run in parallel (one per item in the page)

**Why NOT a single batch Mongo query:**
The hierarchy filtering is per-user — an admin sums all user_commissions, a manager sums only their team's. This conditional logic per commission makes a single batch query impractical. Individual aggregations per item, filtered by commission ID first, are small and fast.

**The 3 columns:**

| Column | Source | Hierarchy-aware? | Implementation |
|--------|--------|-------------------|----------------|
| Group name | `plan.group.name` (Postgres) | No | Add to GraphQL query — trivial |
| Collaborators count | Mongo aggregation (distinct users per commission, filtered by hierarchy) | Yes | New resolver field with Mongo call |
| Final amount | Mongo aggregation (sum of money per commission, filtered by hierarchy) | Yes | New resolver field with Mongo call |

**Group name** is purely Postgres (simple join, no Mongo needed).
**Collaborators count** and **final amount** come from Mongo, enriched in the serializer.

**What needs to happen in the calculation pipeline:**
- When a partial commission is calculated, the results are already written to Mongo (for dashboards)
- Ensure the Mongo collection has the data needed: user_commission records with `partial_commission_id`, `user_id`, `money`, and hierarchy info
- Add index on `partial_commission_id` in the relevant Mongo collection if not present

### Reference Pattern — Existing Codebase

The application already has a well-established 3-layer pattern for enriching Postgres listings with Mongo aggregated data:

**Layer 1 — Mongoid Dataset Model** (`app/models/user_commission_dataset.rb`)
- Stores computed commission data per user/plan/period in MongoDB
- Fields: `money`, `points`, `calendar_id`, `period_id`, `plan_id`, `user_id`
- Has compound index `{ period_id: 1, plan_id: 1, user_id: 1 }`

**Layer 2 — Aggregator** (`app/models/user_commission_dataset/calendar_aggregator.rb`)
- Class method `call(calendar_id, user_ids)` runs a MongoDB aggregation pipeline
- Pipeline: `$match` → `$project` → `$group` (by plan) → `$group` (by calendar) → `$project`
- Returns aggregated `money`, `points`, `users_quantity` per plan
- **Hierarchy filtering**: receives pre-filtered `user_ids` array — if empty, matches all users; if populated, adds `user_id: { '$in': user_ids }` to `$match`
- Other aggregators in the same directory follow the same pattern: `plan_aggregator.rb`, `user_aggregator.rb`, `plan_and_period_aggregator.rb`, etc.

**Layer 3 — GraphQL Resolver** (`app/graphql_resolvers/calendar_aggregated_user_commission_dataset_graphql_resolver.rb`)
- Resolves hierarchy-filtered `user_ids` before calling the aggregator:
```ruby
def user_ids
  return nil if current_company.main? || current_role.unscoped_queries?
  UserScope.new(current_user, User).resolve.pluck(:id)
end
```
- Passes `user_ids` to the aggregator: `CalendarAggregator.call(calendar_id, user_id)`

**Layer 4 — GraphQL Type** (`app/graphql_types/user_commission_dataset_graphql_type.rb`)
- Enriches Mongo hash results with Postgres data via memoized lookups:
```ruby
def plan
  @plan ||= Plan.find(object[:plan_id])
rescue ActiveRecord::RecordNotFound
  nil
end
```
- Exposes computed fields (`money`, `points`, `users_quantity`) alongside Postgres relations (`plan`, `calendar`, `period`)

### What to Build for A7

**Current state of PartialCommission listing:**
- Resolver: `PartialCommissionGraphqlResolver` — `CollectionGraphqlResolver` with `PartialCommissionScope`, filters by calendar/company/period/plan/status
- Type: `PartialCommissionGraphqlType` — exposes `id`, `status`, `plan`, `period`, `company`, `user_commissions`, `owner`, `actions`
- No Mongo aggregation today — purely Postgres

**New fields to add to `PartialCommissionGraphqlType`:**
1. `group_name` — from `plan.group.name` (pure Postgres, trivial)
2. `collaborators_count` — new Mongo aggregation (hierarchy-aware)
3. `total_amount` — new Mongo aggregation (hierarchy-aware)

**Implementation approach:**
- Create `UserCommissionDataset::PartialCommissionAggregator` following the `CalendarAggregator` pattern
  - `call(partial_commission_id, user_ids)` → `$match` by partial commission + user_ids → `$group` → returns `{ users_quantity, money }`
- Add computed fields to `PartialCommissionGraphqlType` that call the aggregator per item
- Hierarchy filtering via `UserScope` in the type (same as resolver pattern)

**Impact:** Backend + Frontend
- Backend: 1 new aggregator + 3 new fields in GraphQL type + verify Mongo indexes
- Frontend: expand listing query + 3 new columns in template

**Effort:** Medium — 2-3 days. The Mongo aggregation pattern already exists in the codebase. Main work is implementing the hierarchy-aware aggregation per item and ensuring Mongo has the right indexes.

**Note:** A9 (#14 — same columns in Compensations listing) follows the exact same approach. Implementing A7 first creates the pattern that A9 reuses.

---

## A8. Plan Summary in Partial Result (#12)

**Client request:** Display plan metadata (ID, Name, Type, Calendar, Group, Status, etc.) on the Partial result screen.

**Code analysis:**
- Backend: `PartialCommissionGraphqlType` already exposes `plan` → `PlanGraphqlType` with all fields — no changes needed
- Frontend: `partial-commission-show.component.ts` queries only `plan { name goal budget }` — needs to expand the query
- Reference: `plan-show.component.ts` already has the full plan summary layout — can replicate the same visual structure

**Decision:** Frontend-only change. Expand the GraphQL query to include all plan fields and add a "Plan Data" summary section replicating the existing layout from the Plan detail screen.

**Impact:** Frontend only (1 component)
**Effort:** Trivial — less than 1 hour

---

## A9. Additional Columns in Compensations Listing (#14)

**Client request:** Same as A7 but for the Compensations listing screen — add group name, number of collaborators, and final generated amount.

**Decision:** Same architecture as A7 — Postgres listing + per-item Mongo aggregation in serializer. Once A7 establishes the pattern, A9 reuses it.

### What to Build for A9

**Current state of Commission listing:**
- Resolver: `CommissionGraphqlResolver` — `CollectionGraphqlResolver` with `CommissionScope`, filters by calendar/company/period/plan/status/payment/responsible/enabled
- Type: `CommissionGraphqlType` — exposes `id`, `status`, `plan`, `period`, `company`, `payment`, `user_commissions`, `owner`, `approver`, `report`, `actions`, timestamps
- No Mongo aggregation today — purely Postgres

**New fields to add to `CommissionGraphqlType`:**
1. `group_name` — from `plan.group.name` (pure Postgres, trivial)
2. `collaborators_count` — reuse aggregator pattern from A7
3. `total_amount` — reuse aggregator pattern from A7

**Implementation approach:**
- Create `UserCommissionDataset::CommissionAggregator` (or reuse PartialCommissionAggregator if the Mongo query structure is identical — both filter by commission ID)
- Add computed fields to `CommissionGraphqlType` following the same approach as A7

**Impact:** Backend + Frontend (same scope as A7)
**Effort:** Medium-Low — 1-2 days. Pattern already exists from A7, just apply to the Commission model/type/component.
**Dependency:** Deliver A7 first to establish the pattern.
