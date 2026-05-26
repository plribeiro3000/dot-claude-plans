# TASKS — Replace Enumerize String Fields with GraphQL Enums — Create graphql_enums/ with ApplicationGraphqlEnum

**Status:** ⛔ ABANDONED — Tasks were completed but the feature was reverted (tags 3.2.0 → 3.2.2) due to GraphQL specification limitation. See PLAN.md for details.

> **Objective of this iteration:** Migrate all enumerize fields exposed via GraphQL from String type to proper GraphQL Enum types, preventing 500 errors from invalid enum values and providing schema-level validation.
> **Reference:** derived from `PLAN.md` (Option 1 — Create graphql_enums/ with ApplicationGraphqlEnum Base Class).

---

## 0) Pre-conditions

- [x] `PLAN.md` **approved** (option: Create graphql_enums/ with ApplicationGraphqlEnum Base Class)
- [x] **Base branch:** `develop` • **Working branch:** `master` (or create `feature/graphql-enumerize-enums`)

---

## 1) Step by Step (atomic tasks)

### Task 1 — Create graphql_enums directory and setup base class ✅
- **Objective:** Establish the foundation for GraphQL enum types following Rails conventions
- **Actions (checklist):**
  - [x] Create `app/graphql_enums/` directory
  - [x] Move `app/graphql_types/enum_graphql_type.rb` to `app/graphql_enums/application_graphql_enum.rb`
  - [x] Rename class `EnumGraphqlType` to `ApplicationGraphqlEnum`
  - [x] Search codebase for any inheritance from `EnumGraphqlType` (should be none)
  - [x] Verify Rails autoloading picks up the new directory (check `config/application.rb` if needed)
- **Affected files/areas:**
  - `app/graphql_enums/application_graphql_enum.rb` (new location)
  - `app/graphql_types/enum_graphql_type.rb` (removed)
- **Completion criteria:**
  - Base class exists at new location
  - Old file removed
  - No references to old class name
  - Rails console can load `ApplicationGraphqlEnum`
- **Observations:** This is a foundational change - verify autoloading works before proceeding

---

### Task 2 — Inventory all enumerize fields exposed in GraphQL ✅
- **Objective:** Create comprehensive list of all enumerize fields that need migration
- **Actions (checklist):**
  - [x] Scan `app/graphql_types/` for String fields that map to enumerize model fields
  - [x] Scan `app/graphql_resolvers/` for String options filtering by enumerize fields
  - [x] Scan `app/graphql_mutations/` for String arguments setting enumerize fields
  - [x] Create master list of (model, field_name, enumerize_values) tuples
  - [x] Categorize by priority: high-traffic endpoints first (UserPayment, Commission, Payment)
- **Affected files/areas:**
  - `app/graphql_types/` (209 files)
  - `app/graphql_resolvers/` (265 files)
  - `app/graphql_mutations/` (195 files)
  - `app/models/` (44 models with enumerize)
- **Completion criteria:**
  - Complete list of all enumerize fields to migrate
  - List includes model name, field name, enumerize values, and enum constant reference (if any)
  - Prioritization defined
- **Observations:**
  - Focus on status/state fields first (~30+ models)
  - Note fields using constants (e.g., `Commission::STATUSES`)
  - Track fields with same name but different values across models
- **[HOLD POINT]** Pause after inventory to review list with user and confirm prioritization

---

### Task 3 ✅ — Migrate UserPayment.integration_status (pilot)
- **Objective:** Complete first migration as template for remaining fields
- **Actions (checklist):**
  - [x] Create `app/graphql_enums/user_payment_integration_status_enum.rb`
  - [x] Define `UserPaymentIntegrationStatusEnum < ApplicationGraphqlEnum`
  - [x] Add values: `value "PENDING", value: "pending"`, `value "SUCCESS", value: "success"`, `value "FAILURE", value: "failure"`
  - [x] Update `app/graphql_types/user_payment_graphql_type.rb` line 8: change `field :integration_status, String` to `field :integration_status, UserPaymentIntegrationStatusEnum`
  - [x] Update `app/graphql_resolvers/user_payment_graphql_resolver.rb` line 11: change `option(:integration_status, type: String)` to `option(:integration_status, type: UserPaymentIntegrationStatusEnum)`
  - [x] Check for mutations using this field and update if found
  - [x] Test valid values work correctly
  - [x] Test invalid values return 400 with clear error message
  - [x] Test resolver filtering still works
- **Affected files/areas:**
  - `app/graphql_enums/user_payment_integration_status_enum.rb` (new)
  - `app/graphql_types/user_payment_graphql_type.rb`
  - `app/graphql_resolvers/user_payment_graphql_resolver.rb`
  - `app/models/user_payment.rb` (reference only)
- **Completion criteria:**
  - Enum created and working
  - Type and resolver updated
  - All tests pass
  - Invalid values rejected at schema level (400 error)
  - Valid values work as before
- **Observations:** This pilot establishes the pattern for remaining migrations

---

### Task 4 ✅ — Migrate Commission.status and related fields
- **Objective:** Migrate commission status fields using Commission::STATUSES constant
- **Actions (checklist):**
  - [x] Create `app/graphql_enums/commission_status_enum.rb`
  - [x] Define values from `Commission::STATUSES`: initial, processing, review, final, locked, error
  - [x] Update all GraphQL types using commission status field
  - [x] Update all resolvers with commission status options
  - [x] Update all mutations with commission status arguments
  - [x] Test all commission-related queries/mutations
  - [x] Verify filtering by status works correctly
- **Affected files/areas:**
  - `app/graphql_enums/commission_status_enum.rb` (new)
  - `app/models/commission.rb` (reference for STATUSES constant)
  - Multiple types/resolvers/mutations in commission context
- **Completion criteria:**
  - All commission status references use enum
  - Tests pass
  - Schema validation works
- **Observations:** Commission is high-traffic - test thoroughly

---

### Task 5 ✅ — Migrate Payment.status
- **Objective:** Migrate payment status field (10 values)
- **Actions (checklist):**
  - [x] Create `app/graphql_enums/payment_status_enum.rb`
  - [x] Extract all 10 status values from Payment model enumerize definition
  - [x] Update payment GraphQL type
  - [x] Update payment resolver
  - [x] Update payment mutations
  - [x] Test payment workflows
- **Affected files/areas:**
  - `app/graphql_enums/payment_status_enum.rb` (new)
  - `app/models/payment.rb`
  - Payment-related GraphQL files
- **Completion criteria:**
  - Payment status uses enum
  - All payment operations work
  - Tests pass

---

### Task 6 ✅ — Migrate IncentivePayment.status
- **Objective:** Migrate incentive payment status field
- **Actions (checklist):**
  - [x] Create `app/graphql_enums/incentive_payment_status_enum.rb`
  - [x] Extract values from IncentivePayment model
  - [x] Update GraphQL type
  - [x] Update resolver
  - [x] Update mutations
  - [x] Test incentive payment operations
- **Affected files/areas:**
  - `app/graphql_enums/incentive_payment_status_enum.rb` (new)
  - `app/models/incentive_payment.rb`
  - IncentivePayment GraphQL files
- **Completion criteria:**
  - IncentivePayment status uses enum
  - Operations work correctly

---

### Task 7 ✅ — Migrate PayrollRequest status and action
- **Objective:** Migrate payroll request enumerize fields
- **Actions (checklist):**
  - [x] Create `app/graphql_enums/payroll_request_status_enum.rb`
  - [x] Create `app/graphql_enums/payroll_request_action_enum.rb`
  - [x] Update PayrollRequest GraphQL type
  - [x] Update PayrollRequest resolver
  - [x] Update PayrollRequest mutations
  - [x] Test payroll request workflows
- **Affected files/areas:**
  - `app/graphql_enums/payroll_request_status_enum.rb` (new)
  - `app/graphql_enums/payroll_request_action_enum.rb` (new)
  - PayrollRequest GraphQL files
- **Completion criteria:**
  - Both status and action use enums
  - Payroll operations work

---

### Task 8 ✅ — Migrate Attachment.status
- **Objective:** Migrate attachment status using Attachment::STATUSES constant
- **Actions (checklist):**
  - [x] Create `app/graphql_enums/attachment_status_enum.rb`
  - [x] Define values from `Attachment::STATUSES`: final, processing, expired
  - [x] Update Attachment GraphQL type
  - [x] Update Attachment resolver
  - [x] Update mutations if any
  - [x] Test attachment operations
- **Affected files/areas:**
  - `app/graphql_enums/attachment_status_enum.rb` (new)
  - `app/models/attachment.rb` (reference for STATUSES constant)
  - Attachment GraphQL files
- **Completion criteria:**
  - Attachment status uses enum
  - All attachment operations work

---

### Task 9 ✅ — Migrate Document.status
- **Objective:** Migrate document status field
- **Actions (checklist):**
  - [x] Create `app/graphql_enums/document_status_enum.rb`
  - [x] Extract values from Document model
  - [x] Update Document GraphQL type
  - [x] Update Document resolver
  - [x] Update mutations
  - [x] Test document workflows
- **Affected files/areas:**
  - `app/graphql_enums/document_status_enum.rb` (new)
  - Document GraphQL files
- **Completion criteria:**
  - Document status uses enum
  - Document operations work

---

### Task 10 ✅ — Migrate Campaign.status
- **Objective:** Migrate campaign status field
- **Actions (checklist):**
  - [x] Create `app/graphql_enums/campaign_status_enum.rb`
  - [x] Extract values from Campaign model
  - [x] Update Campaign GraphQL type
  - [x] Update Campaign resolver
  - [x] Update mutations
  - [x] Test campaign operations
- **Affected files/areas:**
  - `app/graphql_enums/campaign_status_enum.rb` (new)
  - Campaign GraphQL files
- **Completion criteria:**
  - Campaign status uses enum
  - Campaign operations work

---

### Task 11 ✅ — Migrate Company.status and Company.locale
- **Objective:** Migrate company enumerize fields
- **Actions (checklist):**
  - [x] Create `app/graphql_enums/company_status_enum.rb`
  - [x] Create `app/graphql_enums/company_locale_enum.rb`
  - [x] Update Company GraphQL type
  - [x] Update Company resolver
  - [x] Update mutations
  - [x] Test company operations
- **Affected files/areas:**
  - `app/graphql_enums/company_status_enum.rb` (new)
  - `app/graphql_enums/company_locale_enum.rb` (new)
  - Company GraphQL files
- **Completion criteria:**
  - Both status and locale use enums
  - Company operations work

---

### Task 12 ✅ — Migrate Plan.status
- **Objective:** Migrate plan status field
- **Actions (checklist):**
  - [x] Create `app/graphql_enums/plan_status_enum.rb`
  - [x] Extract values from Plan model
  - [x] Update Plan GraphQL type
  - [x] Update Plan resolver
  - [x] Update mutations
  - [x] Test plan operations
- **Affected files/areas:**
  - `app/graphql_enums/plan_status_enum.rb` (new)
  - Plan GraphQL files
- **Completion criteria:**
  - Plan status uses enum
  - Plan operations work

---

### Task 13 ✅ — Migrate Variable calculation, frequency, and related fields
- **Objective:** Migrate variable enumerize fields
- **Actions (checklist):**
  - [x] Create `app/graphql_enums/variable_calculation_enum.rb`
  - [x] Create `app/graphql_enums/variable_frequency_enum.rb`
  - [x] Update Variable GraphQL type
  - [x] Update Variable resolver
  - [x] Update mutations
  - [x] Test variable operations
- **Affected files/areas:**
  - `app/graphql_enums/variable_calculation_enum.rb` (new)
  - `app/graphql_enums/variable_frequency_enum.rb` (new)
  - Variable GraphQL files
- **Completion criteria:**
  - Variable calculation and frequency use enums
  - Variable operations work

---

### Task 14 ✅ — Migrate Metric calculation and comparator
- **Objective:** Migrate metric enumerize fields
- **Actions (checklist):**
  - [x] Create `app/graphql_enums/metric_calculation_enum.rb`
  - [x] Create `app/graphql_enums/metric_comparator_enum.rb`
  - [x] Update Metric GraphQL type
  - [x] Update Metric resolver
  - [x] Update mutations
  - [x] Test metric operations
- **Affected files/areas:**
  - `app/graphql_enums/metric_calculation_enum.rb` (new)
  - `app/graphql_enums/metric_comparator_enum.rb` (new)
  - Metric GraphQL files
- **Completion criteria:**
  - Metric calculation and comparator use enums
  - Metric operations work

---

### Task 15 ✅ — Migrate VariableTrackCollection.calculation
- **Objective:** Migrate variable track collection calculation field
- **Actions (checklist):**
  - [x] Check if can reuse existing calculation enum or needs new one
  - [x] Create `app/graphql_enums/variable_track_collection_calculation_enum.rb` if needed
  - [x] Update VariableTrackCollection GraphQL type
  - [x] Update resolver
  - [x] Update mutations
  - [x] Test operations
- **Affected files/areas:**
  - Possibly new enum or reuse existing
  - VariableTrackCollection GraphQL files
- **Completion criteria:**
  - Calculation field uses enum
  - Operations work

---

### Task 16 ✅ — Migrate Goal.direction and GoalPlan.direction
- **Objective:** Migrate goal direction fields
- **Actions (checklist):**
  - [x] Create `app/graphql_enums/goal_direction_enum.rb`
  - [x] Update Goal GraphQL type
  - [x] Update GoalPlan GraphQL type
  - [x] Update resolvers
  - [x] Update mutations
  - [x] Test goal operations
- **Affected files/areas:**
  - `app/graphql_enums/goal_direction_enum.rb` (new)
  - Goal and GoalPlan GraphQL files
- **Completion criteria:**
  - Direction fields use enum
  - Goal operations work

---

### Task 17 ✅ — Migrate CommissionGoal.direction
- **Objective:** Migrate commission goal direction field
- **Actions (checklist):**
  - [x] Check if can reuse goal direction enum
  - [x] Create separate enum if values differ
  - [x] Update CommissionGoal GraphQL type
  - [x] Update resolver
  - [x] Update mutations
  - [x] Test commission goal operations
- **Affected files/areas:**
  - Possibly reuse or new enum
  - CommissionGoal GraphQL files
- **Completion criteria:**
  - Direction field uses enum
  - Operations work

---

### Task 18 ✅ — Migrate Calendar.frequency
- **Objective:** Migrate calendar frequency field
- **Actions (checklist):**
  - [x] Check if can reuse Variable frequency enum
  - [x] Create `app/graphql_enums/calendar_frequency_enum.rb` if needed
  - [x] Update Calendar GraphQL type
  - [x] Update resolver
  - [x] Update mutations
  - [x] Test calendar operations
- **Affected files/areas:**
  - Possibly new or reused enum
  - Calendar GraphQL files
- **Completion criteria:**
  - Frequency field uses enum
  - Calendar operations work

---

### Task 19 ✅ — Migrate IndicatorDocument format and frequency
- **Objective:** Migrate indicator document enumerize fields
- **Actions (checklist):**
  - [x] Create `app/graphql_enums/indicator_document_format_enum.rb`
  - [x] Create `app/graphql_enums/indicator_document_frequency_enum.rb` or reuse existing
  - [x] Update IndicatorDocument GraphQL type
  - [x] Update resolver
  - [x] Update mutations
  - [x] Test operations
- **Affected files/areas:**
  - New enums
  - IndicatorDocument GraphQL files
- **Completion criteria:**
  - Format and frequency use enums
  - Operations work

---

### Task 20 ✅ — Migrate KpiDocument.format
- **Objective:** Migrate KPI document format field
- **Actions (checklist):**
  - [x] Check if can reuse IndicatorDocument format enum
  - [x] Create separate enum if values differ
  - [x] Update KpiDocument GraphQL type
  - [x] Update resolver
  - [x] Update mutations
  - [x] Test operations
- **Affected files/areas:**
  - Possibly reuse or new enum
  - KpiDocument GraphQL files
- **Completion criteria:**
  - Format field uses enum
  - Operations work

---

### Task 21 ✅ — Migrate RankifierVariable.comparator
- **Objective:** Migrate rankifier variable comparator field
- **Actions (checklist):**
  - [x] Check if can reuse Metric comparator enum
  - [x] Create separate enum if needed
  - [x] Update RankifierVariable GraphQL type
  - [x] Update resolver
  - [x] Update mutations
  - [x] Test operations
- **Affected files/areas:**
  - Possibly reuse or new enum
  - RankifierVariable GraphQL files
- **Completion criteria:**
  - Comparator field uses enum
  - Operations work

---

### Task 22 ✅ — Migrate remaining status fields (batch)
- **Objective:** Complete migration of all remaining status fields from inventory
- **Actions (checklist):**
  - [x] For each remaining model with status field:
    - [x] Create corresponding enum file
    - [x] Update GraphQL type
    - [x] Update resolver
    - [x] Update mutations
    - [x] Test
  - [x] Verify complete coverage of inventory list
- **Affected files/areas:**
  - Multiple new enums
  - Multiple GraphQL files
- **Completion criteria:**
  - All status fields from inventory migrated
  - All tests pass
- **Observations:** This is a batch task for remaining lower-priority status fields

---

### Task 23 ✅ — Handle INCENTIVE_CREDIT_STATE_MACHINE and INCENTIVE_DEBIT_STATE_MACHINE
- **Objective:** Migrate incentive credit/debit state machine enumerize fields
- **Actions (checklist):**
  - [x] Create `app/graphql_enums/incentive_credit_state_enum.rb` with values: pending, final
  - [x] Create `app/graphql_enums/incentive_debit_state_enum.rb` with values: pending, processing, final
  - [x] Find models using these state machines
  - [x] Update corresponding GraphQL types
  - [x] Update resolvers
  - [x] Update mutations
  - [x] Test state transitions work correctly
- **Affected files/areas:**
  - `app/graphql_enums/incentive_credit_state_enum.rb` (new)
  - `app/graphql_enums/incentive_debit_state_enum.rb` (new)
  - Models with incentive state machines
  - Corresponding GraphQL files
- **Completion criteria:**
  - State machine fields use enums
  - State transitions validated at schema level
  - Operations work correctly

---

### Task 24 ✅ — Final verification and cleanup
- **Objective:** Ensure all migrations are complete and working correctly
- **Actions (checklist):**
  - [x] Verify all items from inventory are migrated
  - [x] Run full test suite
  - [x] Test GraphQL introspection shows all enum types correctly
  - [x] Verify no String fields remain for enumerize values
  - [x] Check for any orphaned enum files
  - [x] Update any documentation if needed
  - [x] Verify Rails autoloading works for all new enums
- **Affected files/areas:**
  - Entire `app/graphql_enums/` directory
  - All GraphQL types/resolvers/mutations
- **Completion criteria:**
  - All tests pass
  - GraphQL schema shows all enums
  - No 500 errors from invalid enum values
  - All invalid values return 400 with clear messages
  - Complete coverage verified
- **Observations:** Final quality check before marking feature complete

---

## 2) Items Requiring User Confirmation

- [x] **Prioritization strategy:** Confirm whether to migrate high-traffic endpoints first (UserPayment, Commission, Payment) or proceed alphabetically
- [x] **Enum reuse policy:** When multiple models have same field name (e.g., `status`, `direction`, `calculation`), confirm whether to create shared enums or model-specific enums
- [x] **Testing approach:** Confirm whether to test each migration individually or batch test after groups
- [x] **Branch strategy:** Confirm whether to use `master` or create `feature/graphql-enumerize-enums` branch

> **Expected response (example):**
> `APPROVED: Prioritize high-traffic first; create model-specific enums unless values identical; test individually; create feature branch.`

---

## 3) Pending Items After This Iteration (if any arise)

- [x] Update GraphQL documentation/schema exports if maintained separately
- [x] Update API client libraries if they exist (frontend SDK, mobile SDK, etc.)
- [x] Consider adding enum descriptions for better GraphQL introspection documentation
- [x] Monitor for any edge cases discovered during migration
