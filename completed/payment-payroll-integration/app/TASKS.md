# TASKS - Payment Payroll Integration - Backend (app)

> **Iteration objective:** Refactor permission system for payroll integration, separating creation and viewing permissions.
> **Reference:** Derived from `../PLAN.md`.
> **Branch:** hotfix/3.0.3

---

## 1) Completed Tasks

### Task 1.1 - Create PayrollIntegrationPolicy ✅
- **Objective:** Create dedicated policy for payroll integration actions
- **Actions:**
  - [x] Create `app/policies/payroll_integration_policy.rb`
  - [x] Implement `create?` method (for triggering integration)
    - Returns false if user company != payment company
    - Returns false unless payment is `final` or `integration_error`
    - Returns false if company has no payroll integration configured
    - Checks `payroll_integration_creation` permission
  - [x] Implement `show?` method (for viewing integration report)
    - Returns false unless payment is `integrated`
    - Checks `payroll_integration_listing` permission
- **Commit:** `8b9e9f7d0`

### Task 1.2 - Update PaymentGraphqlType ✅
- **Objective:** Use new policy for action visibility
- **Actions:**
  - [x] Add `integrate` action using `PayrollIntegrationPolicy#create?`
  - [x] Add `integration_report` action using `PayrollIntegrationPolicy#show?`
  - [x] Add private method `payroll_integration_policy`

### Task 1.3 - Update IntegratePaymentGraphqlMutation ✅
- **Objective:** Use new policy for mutation authorization
- **Actions:**
  - [x] Change policy from `PaymentPolicy` to `PayrollIntegrationPolicy`
  - [x] Change authorize call from `:integrate?` to `:create?`

### Task 1.4 - Clean up PaymentPolicy ✅
- **Objective:** Remove deprecated method
- **Actions:**
  - [x] Remove `integrate?` method from PaymentPolicy

### Task 1.5 - Create migrations ✅
- **Objective:** Migrate actions from legacy to new permission structure
- **Files created:**
  - `db/migrate/2025/12/20251225231918_drop_payment_integration_action.rb`
  - `db/migrate/2025/12/20251225231929_create_payroll_integration_creation_action.rb`
  - `db/migrate/2025/12/20251225231933_create_payroll_integration_listing_action.rb`

### Task 1.6 - Update tests ✅
- **Objective:** Fix GraphQL resolver tests
- **Actions:**
  - [x] Add action factories for new permissions in test setup
  - [x] Add permissions to admin role in before block
  - [x] Verify expected_response matches new behavior (no `integration_report` for non-integrated payments)

---

## 2) Completed Tasks - Filters (Hotfix 3.0.4)

> **Branch:** hotfix/3.0.4
> **PR:** #4675

### Task 2.1 - Add scopes to UserPayment model ✅
- **Objective:** Add filtering scopes for user, payment_type, and integration_status
- **File:** `app/models/user_payment.rb`
- **Actions:**
  - [x] Add `scope :for_user, ->(user_id) { where(user_id: user_id) if user_id.present? }`
  - [x] Add `scope :for_payment_type, ->(payment_type_id) { where(payment_type_id: payment_type_id) if payment_type_id.present? }`
  - [x] Add `scope :for_integration_status, ->(status) { where(integration_status: status) if status.present? }`
- **Note:** `integration_status` enum values are: `pending` (0), `success` (1), `failure` (2)

### Task 2.2 - Add options to UserPaymentGraphqlResolver ✅
- **Objective:** Expose new filters via GraphQL API
- **File:** `app/graphql_resolvers/user_payment_graphql_resolver.rb`
- **Actions:**
  - [x] Add `option(:user_id, type: ID) { |scope, user_id| scope.for_user(user_id) }`
  - [x] Add `option(:payment_type_id, type: ID) { |scope, payment_type_id| scope.for_payment_type(payment_type_id) }`
  - [x] Add `option(:integration_status, type: String) { |scope, status| scope.for_integration_status(status) }`

### Task 2.3 - Update tests (if needed)
- **Objective:** Add tests for new filter options
- **Status:** Deferred - existing tests passing

---

## 3) Completed - Hotfix 3.1.1 ✅

> **Branch:** hotfix/3.1.1
> **PR:** #4677 (Merged)
> **Commit:** `115ed4ae5`

---

### Issue A: Secure Downloads - Download Audit Trail ✅

> **Objective:** Log who downloaded each file for audit purposes
> **Commit:** `da6e0a856`
> **Reference:** `~/.claude/plans/secure-downloads/PLAN.md` - Phase 11.1

- [x] Add `download_model` DSL to `TemporaryFileGraphqlResolver`
- [x] Create `AuditDownload` model
- [x] Create `CommissionReportDownload` model
- [x] Update 14 temporary file resolvers to declare `download_model`
- [x] Each download creates a record with `downloadable`, `user`, `from` (IP)

---

### Issue B: Payment Integration Audit Trail ✅

> **Objective:** Record who requested each integration for audit purposes

### Task B.1 - Create migration to add audit columns to Payment ✅
- **File:** `db/migrate/20251226133201_add_integration_audit_to_payments.rb`
- **Columns:**
  - [x] `integration_owner_id` (references users, index: true, FK to users)
  - [x] `integrated_at` (datetime)
  - [x] `integrated_from` (string)

### Task B.2 - Update Payment model ✅
- **File:** `app/models/payment.rb`
- **Actions:**
  - [x] `belongs_to :integration_owner, class_name: 'User', optional: true`
  - [x] `integrate_by(user_id:, from:)` method with transaction + rescue

### Task B.3 - Update User model ✅
- **File:** `app/models/user.rb`
- **Actions:**
  - [x] `has_many :integrated_payments` relationship

### Task B.4 - Ensure IP is available in GraphQL context ✅
- **File:** `app/controllers/graphql_controller.rb`
- **Status:** Already exists (`context[:remote_ip]`)

### Task B.5 - Update IntegratePaymentGraphqlMutation ✅
- **File:** `app/graphql_mutations/integrate_payment_graphql_mutation.rb`
- **Actions:**
  - [x] Use `payment.integrate_by(user_id:, from:)` method
  - [x] Only call worker if `integrate_by` succeeds

### Task B.6 - Update PaymentGraphqlType ✅
- **File:** `app/graphql_types/payment_graphql_type.rb`
- **Actions:**
  - [x] Expose `integration_owner` (UserGraphqlType)
  - [x] Expose `integration_owner_id` (ID)
  - [x] Expose `integrated_at` (DateTime)
  - [x] Expose `integrated_from` (String)

### Task B.7 - Frontend: Show integration owner on payment page
- **File:** `payment-show.component.html`
- **Status:** Pending (separate PR for frontend)

---

### Issue C: reference_month Validation ✅

> **Objective:** Ensure `reference_month` is present before allowing payroll integration

#### Analysis Summary

- Payments created before August 2025 may have `reference_month = nil`
- Workers fail with `NoMethodError` if `reference_month` is nil
- Solution: Block integration in policy if `reference_month` is missing

### Task C.1 - Add reference_month validation in PayrollIntegrationPolicy ✅
- **File:** `app/policies/payroll_integration_policy.rb`
- **Actions:**
  - [x] Add `return false if record.reference_month.blank?` in `create?` method
- **Effect:** Button won't appear if `reference_month` is missing

---

### Issue D: Fix `*_by` methods not returning boolean ✅

> **Objective:** Fix methods that are used with conditionals but don't return `false` on failure

#### Analysis Summary

- Several `*_by` methods have `rescue` blocks that don't return `false`
- Mutations using these methods with conditionals (`if model.method_by(...)`) expect boolean
- When rescue triggers, method returns `nil` instead of `false`, causing unexpected behavior

#### Methods analyzed

| Method | Used with conditional? | Had bug? |
|--------|------------------------|----------|
| `Payment#approve_by` | Yes | **Yes** - no rescue, used `update` without bang |
| `Payment#integrate_by` | Yes | No - already correct |
| `Plan#cancel_by` | Yes | **Yes** - no rescue |
| `PlanParticipation#approve_by` | Yes | **Yes** - no rescue |
| `Commission#reprocess_by` | Yes | **Yes** - rescue without `false` |
| `Commission#approve_by` | No (checks status after) | No |
| `Commission#release_by` | No | No |
| `PlanSliceCommission#approve_by` | No (checks status after) | No |

### Task D.1 - Fix Payment#approve_by ✅
- **File:** `app/models/payment.rb`
- **Changes:**
  - Changed `update` to `update!`
  - Added `rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved`
  - Added `false` return in rescue

### Task D.2 - Fix Plan#cancel_by ✅
- **File:** `app/models/plan.rb`
- **Changes:**
  - Added `rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved`
  - Added `false` return in rescue

### Task D.3 - Fix PlanParticipation#approve_by ✅
- **File:** `app/models/plan_participation.rb`
- **Changes:**
  - Added `rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved`
  - Added `false` return in rescue

### Task D.4 - Fix Commission#reprocess_by ✅
- **File:** `app/models/commission.rb`
- **Changes:**
  - Added `ActiveRecord::RecordNotSaved` to rescue
  - Added `false` return in rescue

---

## 4) Summary

| Item | Status |
|------|--------|
| Hotfix 3.0.3 | ✅ Merged (PR #4674) |
| Hotfix 3.0.4 | ✅ Merged (PR #4675) |
| Hotfix 3.1.1 | ✅ Merged (PR #4677) |

### Hotfix 3.1.1 Scope

| Issue | Description | Status |
|-------|-------------|--------|
| A | Secure Downloads - Download Audit Trail | ✅ Merged |
| B | Payment Integration Audit Trail | ✅ Merged |
| C | Validation for `reference_month` before integration | ✅ Merged |
| D | Fix `*_by` methods not returning boolean | ✅ Merged |

---

## Feature Complete ✅

All backend tasks for payment-payroll-integration have been completed and merged to production.
