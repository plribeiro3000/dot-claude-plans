# PLAN - Payment Integration Feature

## Current Situation

- **Relevant context/architecture:**
  - Angular frontend with modules pattern following established conventions
  - GraphQL API for all backend communications via Apollo Client
  - Backend API already implemented (commit cd053f82d) with:
    - `integratePayment` mutation (input: payment ID, returns PaymentGraphqlType)
    - `payrollRequests` query with filters (id, payment_id, user_payment_id, action, status)
    - `PayrollRequestGraphqlType` with fields: id, company, action, status, requestBody, responseBody, duration, etc.
  - Payment-show component exists with an "integrate" button that currently navigates to external applications creation
  - The `integrate` action is already available via `payment_policy.integrate?` in backend

- **Impacted components:**
  - `src/app/payment/show/payment-show.component.ts` - Add integration mutation call
  - `src/app/payment/show/payment-show.component.html` - Update/add integration button
  - `src/app/payment/payment-routing.module.ts` - Add new route for integration report
  - `src/app/payment/payment.module.ts` - Register new components and services
  - Translation files: `src/translations/pt-BR.json`, `en.json`, `es.json`
  - New files for payroll-request module

- **Versions/environment:**
  - Angular project with legacy Material components (MatLegacy*)
  - Apollo Angular for GraphQL
  - i18n via ngx-translate

## Objective / Target State

- **Desired result:**
  1. Users can trigger payment integration directly from the payment-show page
  2. Users can view integration status and history (payroll requests) for a payment
  3. Integration follows existing UI/UX patterns (snackbar notifications, loading states)

- **Success metrics / acceptance criteria:**
  - Integration button calls `integratePayment` mutation successfully
  - Loading state shown during mutation execution
  - Success/error feedback via snackbar
  - New route `/payments/:paymentId/integration` displays payroll requests
  - Payroll requests list shows: user info, action type, status, duration, timestamps
  - Request/response bodies viewable in expandable sections
  - Navigation link from payment-show to integration report page
  - All strings translated in pt-BR, en, es

## Problem / New Feature

- **Objective description:**
  The backend API for payment integration (FPW/Payroll) has been implemented but the frontend lacks:
  1. A way to trigger the `integratePayment` mutation
  2. A view to monitor integration status via `payrollRequests` query

  The existing "integrate" button in payment-show currently redirects to external applications, which is a different feature. We need to either repurpose this button or add a new one for the actual integration API call.

- **Current behavior:**
  - Button with `*ngIf="payment.actions.includes('integrate')"` exists (lines 84-91)
  - Clicking it calls `externalApplication()` method which navigates to `/payments/:id/externalApplications/create`
  - No visibility into payroll request status after integration

## Challenges, Difficulties and Risks

- **Technical:**
  - Distinguishing between "integrate" (external applications) and "integrate" (payroll integration) - need to clarify if these are separate actions or the same
  - UserPayment model needs to be extended with new fields (integrationStatus, payrollRequests)
  - Need to handle potentially long-running integration process (async feedback)

- **Product/UX:**
  - Clear distinction between external application integration and payroll integration
  - Deciding how to display request/response bodies (can be large JSON objects)
  - Status visualization for different action types (check, execution, validation)

- **Security/Privacy:**
  - Request/response bodies may contain sensitive payroll data
  - Ensure only authorized users can view integration details

- **Performance:**
  - Payroll requests list may grow large - pagination needed
  - Request/response bodies should be lazy-loaded (expandable sections)

## Solution Options (Comparison)

### Option 1 - Separate Button and New Module

- **How it works:**
  - Add a new button "Integrar Folha" next to the existing "Enviar para Sistema Externo"
  - Create a new `payroll-request` module with its own components and services
  - New route: `/payments/:paymentId/payroll-requests`
  - Follow the exact pattern of `payment-report` module for consistency

- **Pros:**
  - Clear separation of concerns - external applications vs payroll integration
  - Follows existing codebase patterns exactly
  - Easier to maintain and extend independently
  - No risk of breaking existing functionality

- **Cons:**
  - More files to create and maintain
  - Two similar-looking buttons may confuse users initially
  - Slightly more code duplication

- **When NOT to use:**
  - If the existing integrate button was meant for payroll integration all along

### Option 2 - Replace Existing Button Behavior

- **How it works:**
  - Modify the existing "Enviar para Sistema Externo" button to call the integration mutation
  - Change the button label and behavior based on context
  - Add integration report as a sub-page of payment-show
  - Create a lighter service layer within the existing payment module

- **Pros:**
  - Less new code to write
  - Single integration point for users
  - More compact module structure

- **Cons:**
  - Risk of breaking existing external applications flow
  - Need to verify if external applications feature is still needed
  - Less modular - harder to extend independently
  - Mixed concerns in payment module

- **When NOT to use:**
  - If external applications feature must remain as-is
  - If the two features serve different purposes

### Option 3 - Hybrid Approach with Smart Button

- **How it works:**
  - Keep a single "Integrate" button that opens a dialog/bottom-sheet
  - Dialog shows integration options: "Payroll Integration" and "External Application"
  - Payroll integration calls mutation and links to new payroll-requests page
  - Create payroll-request as a sub-module within payment module

- **Pros:**
  - Clean UX with clear choice for users
  - Maintains both functionalities
  - Moderate code organization

- **Cons:**
  - Additional click for users
  - Dialog adds complexity
  - Slightly unusual pattern compared to rest of codebase

- **When NOT to use:**
  - If only one type of integration is relevant at a time

### Option 4 - Remove Legacy Code and Replace (APPROVED)

- **How it works:**
  - First, completely remove all External Application code (over-engineered legacy feature)
  - Replace the existing integrate button behavior with the actual payroll integration
  - Create `payroll-request` module for viewing integration history
  - Clean slate approach - no legacy baggage

- **Pros:**
  - Removes technical debt and unused code
  - Clean implementation without workarounds
  - Single integration flow - no confusion
  - Reduces codebase complexity
  - The "integrate" action already exists in backend for the correct purpose

- **Cons:**
  - Destructive change (removing code)
  - Need to verify no other features depend on External Application

- **When to use:**
  - When the legacy feature was over-engineered and doesn't fit the actual domain
  - When the feature name doesn't match the business domain (External Application ≠ Payroll Request)

## Proposed Steps (Option 4 - APPROVED)

### Phase 0: Remove External Application Legacy Code
**Files to DELETE completely:**
- `src/app/external-application/` (entire directory)
  - `create/external-application-create-form-builder.service.ts`
  - `create/external-application-create.service.ts`
  - `create/external-application-create.component.ts`
  - `create/external-application-create.component.html`
  - `external-application.model.ts`
  - `external-application.module.ts`
  - `external-application-routing.module.ts`

**Files to MODIFY (remove references):**
- `src/app/app.module.ts` - Remove ExternalApplicationModule import
- `src/app/payment/show/payment-show.component.ts` - Remove `externalApplication()` method
- `src/app/payment/show/payment-show.component.html` - Remove/update integrate button
- `src/translations/pt-BR.json` - Remove `external_application` keys
- `src/translations/en.json` - Remove `external_application` keys
- `src/translations/es.json` - Remove `external_application` keys

### Phase 1: Foundation (Services and Models)
1. Create `PayrollRequest` model interface with all API fields
2. Create `PaymentIntegrateService` extending `AppService` for the mutation
3. Create `PayrollRequestService` extending `AppService` for the query
4. Update `UserPayment` model with new integration fields

### Phase 2: Integration Button in Payment-Show
5. Add `PaymentIntegrateService` to payment-show component
6. Create `integrate()` method calling `integratePayment` mutation
7. Update the integrate button to call new `integrate()` method
8. Implement loading state and snackbar notifications
9. Add link/button to view integration report when payroll requests exist

### Phase 3: Payroll Requests Page
10. Create `PayrollRequestComponent` following `PaymentReportComponent` pattern
11. Create template with Material table showing payroll requests
12. Implement pagination with "load more" pattern
13. Add expandable sections for request/response bodies
14. Add status badges with color coding (pending, success, failure)

### Phase 4: Routing and Module Configuration
15. Add route `/payments/:paymentId/payroll-requests` in `payment-routing.module.ts`
16. Register new components and services in `payment.module.ts`
17. Add necessary Material module imports

### Phase 5: Translations
18. Add translation keys for pt-BR.json:
    - `payroll_request.one`, `payroll_request.other`
    - `payroll_request.action.check`, `payroll_request.action.execution`, `payroll_request.action.validation`
    - `payroll_request.status.pending`, `payroll_request.status.success`, `payroll_request.status.failure`
    - `payment.page.integrate_payroll`, `payment.page.success_integrated`, `payment.page.fail_integrate`
19. Add same keys to en.json and es.json

### Phase 6: Testing and Polish
20. Test integration flow end-to-end
21. Verify error handling scenarios
22. Test pagination and data loading
23. Review accessibility and responsive design

## Internal References

- Existing patterns to follow:
  - `src/app/payment-report/payment-report.component.ts` - List component with pagination
  - `src/app/payment-report/payment-report.service.ts` - Service with list query
  - `src/app/payment/approve/payment-approve.service.ts` - Mutation service pattern
  - `src/app/payment/show/payment-show.component.ts` - Current payment-show implementation
  - `src/app/payment/payment-routing.module.ts` - Route configuration

- Files to DELETE (Phase 0):
  - `src/app/external-application/` (entire directory - 7 files)

- Files to MODIFY:
  - `src/app/app.module.ts` - Remove ExternalApplicationModule
  - `src/app/payment/show/payment-show.component.ts` - Remove externalApplication(), add integrate()
  - `src/app/payment/show/payment-show.component.html` - Update integrate button
  - `src/app/payment/payment-routing.module.ts` - Add payroll-requests route
  - `src/app/payment/payment.module.ts` - Register new components
  - `src/translations/pt-BR.json` - Remove external_application, add payroll_request
  - `src/translations/en.json` - Remove external_application, add payroll_request
  - `src/translations/es.json` - Remove external_application, add payroll_request

- New files to CREATE:
  - `src/app/payment/integrate/payment-integrate.service.ts`
  - `src/app/payroll-request/payroll-request.model.ts`
  - `src/app/payroll-request/payroll-request.service.ts`
  - `src/app/payroll-request/payroll-request.component.ts`
  - `src/app/payroll-request/payroll-request.component.html`
  - `src/app/payroll-request/payroll-request.component.scss`
  - `src/app/payroll-request/payroll-request.module.ts`

---

## Implementation Progress

### Backend (hotfix/3.0.3) - COMPLETED
- **PayrollIntegrationPolicy created** (`app/policies/payroll_integration_policy.rb`):
  - `create?` - checks if user can trigger integration (payment must be `final` or `integration_error`, company must have payroll integration configured)
  - `show?` - checks if user can view integration report (payment must be `integrated`)
- **PaymentGraphqlType updated**:
  - `integrate` action uses `PayrollIntegrationPolicy#create?`
  - `integration_report` action uses `PayrollIntegrationPolicy#show?`
- **IntegratePaymentGraphqlMutation updated**:
  - Now uses `PayrollIntegrationPolicy` instead of `PaymentPolicy`
  - Authorizes with `create?` instead of `integrate?`
- **Migrations created**:
  - `drop_payment_integration_action` - removes legacy action
  - `create_payroll_integration_creation_action` - for integration button visibility
  - `create_payroll_integration_listing_action` - for report visibility
- **PaymentPolicy cleaned up**:
  - Removed `integrate?` method (moved to PayrollIntegrationPolicy)

### Frontend (feature/payment-payroll-integration) - COMPLETED ✅
- **Completed**:
  - Legacy External Application code removed
  - PayrollRequest component renamed to UserPayment component
  - Integration button implemented
  - UserPayment list with expandable payroll requests
  - Balance column added to payroll requests (shows value from check and validation)
  - Payroll requests ordered: check → execution → validation
  - Currency formatting uses environment variables
  - Button visibility uses whitelist approach (`actions.includes('integration_report')`)
  - Translations added for `payroll_request.balance`
  - **Filters implemented:**
    - Filter by user (autocomplete)
    - Filter by payment type (autocomplete)
    - Filter by integration status (dropdown: pending/integrated/failed)
    - Apply/Clear filters buttons
    - URL queryParams persistence
  - **Integration confirmation dialog added:**
    - Warns user before starting payroll integration
    - Translated in pt-BR, en, es

---

## Phase 7: Audit Trail - Payment Columns (PENDING)

### Problem
Currently, when a user clicks "Integrate Payroll":
1. The mutation directly triggers the `FpwIntegration::CheckProducer` job
2. **There is no record of who requested the integration**
3. No audit trail for accountability

### Proposed Solution
Add audit columns directly to `Payment`, following the existing pattern of `approver_id`/`approved_at`.

### New Payment Columns

| Column | Type | Description | Existing pattern |
|--------|------|-------------|------------------|
| `integration_owner_id` | FK → users | Who requested the integration | (like `approver_id`) |
| `integrated_at` | datetime | When it was requested | (like `approved_at`) |
| `integrated_from` | inet | Origin IP address | (like `*_from`) |

### Current vs New Flow

**Current:**
```
User clicks → Mutation → Job CheckProducer
                 ↑
            No record of who requested
```

**New:**
```
User clicks → Mutation → Saves integration_owner_id, integrated_at, integrated_from → Job CheckProducer
```

### Backend Tasks

#### Task 7.1 - Create migration to add columns to Payment
- **File:** `db/migrate/YYYYMMDDHHMMSS_add_integration_audit_to_payments.rb`
- **Columns:**
  - `integration_owner_id` (references users, null: true, index: true)
  - `integrated_at` (datetime)
  - `integrated_from` (inet)
- **FK:** `add_foreign_key :payments, :users, column: :integration_owner_id`

#### Task 7.2 - Update Payment model
- **File:** `app/models/payment.rb`
- **Changes:**
  - `belongs_to :integration_owner, class_name: 'User', optional: true`

#### Task 7.3 - Ensure IP is available in GraphQL context
- **File:** `app/controllers/graphql_controller.rb`
- **Check:** if `context[:ip]` or `context[:remote_ip]` already exists
- **If not:** add `request.remote_ip` to context

#### Task 7.4 - Update IntegratePaymentGraphqlMutation
- **File:** `app/graphql_mutations/integrate_payment_graphql_mutation.rb`
- **Changes:**
  - Before triggering the job, update the payment:
    ```ruby
    payment.update!(
      integration_owner_id: current_user.id,
      integrated_at: Time.current,
      integrated_from: context[:remote_ip]
    )
    ```

#### Task 7.5 - Update PaymentGraphqlType
- **File:** `app/graphql_types/payment_graphql_type.rb`
- **Changes:**
  - Expose `integration_owner` (User)
  - Expose `integrated_at` (DateTime)
  - Expose `integrated_from` (String) - admins only?

### Frontend Tasks

#### Task 7.6 - Show who integrated on payment page
- **File:** `payment-show.component.html`
- **Changes:**
  - Add section showing "Integrated by: [name] on [date]"
  - Only show if `integrated_at` exists

### Considerations

1. **Backward compatibility:** Existing payments will have `integration_owner_id` as null
2. **IP in GraphQL:** Check if already available in context (usually `request.remote_ip`)
3. **Security:** Evaluate if `integration_ip` should be visible to all or admins only

---

**Status:** ✅ COMPLETED
- Backend: hotfix/3.0.3 (merged), hotfix/3.0.4 (merged), hotfix/3.1.1 (deployed 2025-12-26)
- Frontend: feature/payment-payroll-integration (merged)
- Phase 7 - Audit Trail: ✅ COMPLETED (hotfix/3.1.1)
