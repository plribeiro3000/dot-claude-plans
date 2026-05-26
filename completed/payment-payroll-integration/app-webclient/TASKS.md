# TASKS - Payment Integration Feature - Option 4 (Remove Legacy + Payroll Request)

> **Iteration objective:** Remove legacy External Application code and implement direct Payroll Request integration from the payment-show page, including a dedicated page to view integration history.
> **Reference:** Derived from `PLAN.md` (Option 4 - APPROVED).

---

## 0) Pre-conditions

- [x] `PLAN.md` **approved** (option: Option 4 - Remove legacy External Application code)
- [ ] **Base branch:** `develop` • **Working branch:** `feature/payment-integration`

---

## 1) Step-by-step (atomic tasks)

### Phase 0: Remove External Application Legacy Code

### Task 0.1 - Delete External Application directory
- **Objective:** Remove the entire legacy External Application module that will be replaced
- **Actions (checklist):**
  - [ ] Delete the directory `src/app/external-application/` and all its contents:
    - `create/external-application-create-form-builder.service.ts`
    - `create/external-application-create.service.ts`
    - `create/external-application-create.component.ts`
    - `create/external-application-create.component.html`
    - `external-application.model.ts`
    - `external-application.module.ts`
    - `external-application-routing.module.ts`
- **Affected files/areas:** `src/app/external-application/` (entire directory - 7 files)
- **Completion criteria:** Directory no longer exists in the project
- **Notes:** This is a destructive change - ensure no other features depend on this module

### Task 0.2 - Remove ExternalApplicationModule from app.module.ts
- **Objective:** Remove the module import from the main application module
- **Actions (checklist):**
  - [ ] Remove the import statement: `import { ExternalApplicationModule } from '@app/external-application/external-application.module';` (line 52)
  - [ ] Remove `ExternalApplicationModule` from the imports array (line 240)
- **Affected files/areas:** `src/app/app.module.ts`
- **Completion criteria:** No references to ExternalApplicationModule in app.module.ts; application compiles without errors

### Task 0.3 - Remove externalApplication() method from payment-show.component.ts
- **Objective:** Remove the legacy navigation method that is no longer needed
- **Actions (checklist):**
  - [ ] Remove the `externalApplication()` method (lines 142-144):
    ```typescript
    externalApplication() {
      this.router.navigate(['/payments', this.payment.id, 'externalApplications', 'create'], { replaceUrl: true });
    }
    ```
- **Affected files/areas:** `src/app/payment/show/payment-show.component.ts`
- **Completion criteria:** Method no longer exists in the component

### Task 0.4 - Update integrate button in payment-show.component.html
- **Objective:** Temporarily disable the integrate button until the new integration is implemented
- **Actions (checklist):**
  - [ ] Comment out or remove the button that calls `externalApplication()` (lines 84-91)
  - [ ] Leave the `*ngIf="payment.actions.includes('integrate')"` condition - will be reused
- **Affected files/areas:** `src/app/payment/show/payment-show.component.html`
- **Completion criteria:** Button is removed/commented; no compilation errors

### Task 0.5 - Remove external_application translation keys
- **Objective:** Clean up unused translation keys from all language files
- **Actions (checklist):**
  - [ ] Remove `"external_application"` key from `actions` object in `src/translations/pt-BR.json` (line 87)
  - [ ] Remove `"external_application"` root object in `src/translations/pt-BR.json` (line 1207+)
  - [ ] Remove same keys from `src/translations/en.json` (lines 84, 1204+)
  - [ ] Remove same keys from `src/translations/es.json` (lines 84, 1204+)
- **Affected files/areas:** `src/translations/pt-BR.json`, `src/translations/en.json`, `src/translations/es.json`
- **Completion criteria:** No `external_application` keys exist in any translation file

### Task 0.6 - Verify application compiles and runs
- **Objective:** Ensure all legacy code removal was successful
- **Actions (checklist):**
  - [ ] Run `npm run build` to verify compilation
  - [ ] Run `npm start` and navigate to a payment-show page
  - [ ] Verify no console errors related to external application
- **Affected files/areas:** N/A (validation step)
- **Completion criteria:** Application compiles and runs without errors related to removed code
- **[HOLD POINT]** Pause here until legacy removal is validated before proceeding to new implementation

---

### Phase 1: Foundation (Services and Models)

### Task 1.1 - Create PayrollRequest model interface
- **Objective:** Define the TypeScript interface for PayrollRequest matching the backend GraphQL type
- **Actions (checklist):**
  - [ ] Create file `src/app/payroll-request/payroll-request.model.ts`
  - [ ] Define `PayrollRequest` class with properties:
    - `id: number`
    - `company: { name: string }`
    - `action: string` (enum: 'check', 'execution', 'validation')
    - `status: string` (enum: 'pending', 'success', 'failure')
    - `requestBody: string` (JSON string)
    - `responseBody: string` (JSON string)
    - `duration: number` (milliseconds)
    - `createdAt: Date`
    - `updatedAt: Date`
  - [ ] Follow existing model patterns (e.g., `PaymentReport` model)
- **Affected files/areas:** `src/app/payroll-request/payroll-request.model.ts` (new file)
- **Completion criteria:** Model interface matches backend `PayrollRequestGraphqlType` schema

### Task 1.2 - Create PaymentIntegrateService
- **Objective:** Create service to call the `integratePayment` GraphQL mutation
- **Actions (checklist):**
  - [ ] Create file `src/app/payment/integrate/payment-integrate.service.ts`
  - [ ] Extend `AppService` following the `PaymentApproveService` pattern
  - [ ] Implement named Apollo client 'paymentIntegrate' with `no-cache` policy
  - [ ] Add `integrate(paymentId: number)` method that executes:
    ```graphql
    mutation {
      integratePayment(id: $paymentId) {
        id
        status
      }
    }
    ```
- **Affected files/areas:** `src/app/payment/integrate/payment-integrate.service.ts` (new file)
- **Completion criteria:** Service can be injected and mutation executes successfully against the backend

### Task 1.3 - Create PayrollRequestService
- **Objective:** Create service to query payroll requests for a payment
- **Actions (checklist):**
  - [ ] Create file `src/app/payroll-request/payroll-request.service.ts`
  - [ ] Extend `AppService` following the `PaymentReportService` pattern
  - [ ] Implement named Apollo client 'payrollRequest' with `no-cache` policy
  - [ ] Add `list(after: string, paymentId: string)` method that executes:
    ```graphql
    query {
      payrollRequests(
        first: 9
        after: $after
        paymentId: $paymentId
      ) {
        pageInfo {
          endCursor
        }
        nodes {
          id
          company { name }
          action
          status
          requestBody
          responseBody
          duration
          createdAt
          updatedAt
        }
      }
    }
    ```
- **Affected files/areas:** `src/app/payroll-request/payroll-request.service.ts` (new file)
- **Completion criteria:** Service returns paginated payroll requests filtered by paymentId

---

### Phase 2: Integration Button in Payment-Show

### Task 2.1 - Inject PaymentIntegrateService into payment-show.component
- **Objective:** Make the integration service available in the payment-show component
- **Actions (checklist):**
  - [ ] Add import for `PaymentIntegrateService` in `payment-show.component.ts`
  - [ ] Inject service in constructor as `private integrateService: PaymentIntegrateService`
  - [ ] Add component state variables:
    - `integrating: boolean = false`
    - `integrated: boolean = false`
- **Affected files/areas:** `src/app/payment/show/payment-show.component.ts`
- **Completion criteria:** Service is injected and state variables are defined

### Task 2.2 - Implement integrate() method
- **Objective:** Create the method that triggers the payroll integration mutation
- **Actions (checklist):**
  - [ ] Add `integrate()` method following the `approve()` pattern:
    ```typescript
    integrate() {
      this.integrating = true;

      this.integrateService.mutation('paymentIntegrate', this.integrateQuery()).subscribe(
        () => {
          this.integrating = false;
          this.integrated = true;

          this.snackBar
            .open(this.translateService.instant('payment.page.success_integrated'), '', {
              duration: 2000,
              horizontalPosition: 'center',
              verticalPosition: 'top',
            })
            .afterDismissed()
            .subscribe(() => {
              window.location.reload();
            });
        },
        (err) => {
          this.integrating = false;

          this.snackBar.open(this.translateService.instant('payment.page.fail_integrate'), '', {
            duration: 2000,
            horizontalPosition: 'center',
            verticalPosition: 'top',
          });
        }
      );
    }
    ```
  - [ ] Add `integrateQuery()` private method:
    ```typescript
    private integrateQuery() {
      return `mutation {
        integratePayment(id: ${this.paymentId}) {
          id
          status
        }
      }`;
    }
    ```
- **Affected files/areas:** `src/app/payment/show/payment-show.component.ts`
- **Completion criteria:** Method calls mutation and handles success/error with snackbar notifications

### Task 2.3 - Add integrate button to template
- **Objective:** Add the button that triggers payroll integration
- **Actions (checklist):**
  - [ ] Add button in `payment-show.component.html` after the approve button (around line 84):
    ```html
    <button
      class="menu-button filter-btn"
      *ngIf="payment.actions.includes('integrate')"
      (click)="integrate()"
      [disabled]="integrating"
    >
      <span class="material-symbols-outlined">integration_instructions</span>
      {{ integrating ? ('info.loading' | translate) : ('payment.page.integrate_payroll' | translate) }}
    </button>
    ```
- **Affected files/areas:** `src/app/payment/show/payment-show.component.html`
- **Completion criteria:** Button appears when `integrate` action is available, shows loading state during mutation

### Task 2.4 - Add link to view payroll requests
- **Objective:** Provide navigation to the payroll requests page
- **Actions (checklist):**
  - [ ] Add button/link in `payment-show.component.html` in the buttons-container section:
    ```html
    <button
      class="menu-button filter-btn"
      *ngIf="payment?.actions?.includes('integrate')"
      [routerLink]="['/payments/', payment.id, 'payroll_requests']"
    >
      <span class="material-symbols-outlined">history</span>
      <span>{{ 'payroll_request.page.view_history' | translate }}</span>
    </button>
    ```
- **Affected files/areas:** `src/app/payment/show/payment-show.component.html`
- **Completion criteria:** Link navigates to `/payments/:paymentId/payroll_requests`

---

### Phase 3: Payroll Requests Page

### Task 3.1 - Create PayrollRequestComponent
- **Objective:** Create the main component for displaying payroll request history
- **Actions (checklist):**
  - [ ] Create file `src/app/payroll-request/payroll-request.component.ts`
  - [ ] Follow the `PaymentReportComponent` pattern exactly
  - [ ] Define component with:
    - Selector: `app-payroll-request`
    - Template: `./payroll-request.component.html`
    - Styles: `./payroll-request.component.scss`
  - [ ] Implement properties:
    - `displayedColumns: string[] = ['id', 'action', 'status', 'duration', 'createdAt', 'actions']`
    - `endCursor: string`
    - `lastPageLength = 0`
    - `loading: boolean`
    - `pageLength = 9`
    - `paymentId: string`
    - `payrollRequests: MatLegacyTableDataSource<PayrollRequest[]>`
  - [ ] Implement methods:
    - `ngOnInit()` - get route params, call `getPayrollRequests()`
    - `getPayrollRequests()` - fetch data using `PayrollRequestService`
    - `hasMore()` - check if more pages exist
    - `handleScroll(scrolled: boolean)` - pagination trigger
- **Affected files/areas:** `src/app/payroll-request/payroll-request.component.ts` (new file)
- **Completion criteria:** Component fetches and displays paginated payroll requests

### Task 3.2 - Create PayrollRequestComponent template
- **Objective:** Create the HTML template for the payroll requests list
- **Actions (checklist):**
  - [ ] Create file `src/app/payroll-request/payroll-request.component.html`
  - [ ] Follow `payment-report.component.html` structure
  - [ ] Include:
    - Page title and breadcrumbs
    - Back button to payment-show
    - Material table with columns:
      - ID
      - Action (with translated labels for check/execution/validation)
      - Status (with colored badges: pending=warning, success=success, failure=danger)
      - Duration (formatted in seconds/ms)
      - Created At (formatted date)
      - Actions (expand button to view request/response)
    - Scroll container for pagination
    - Loading spinner template
  - [ ] Add expandable rows or dialog for viewing requestBody/responseBody
- **Affected files/areas:** `src/app/payroll-request/payroll-request.component.html` (new file)
- **Completion criteria:** Template displays all payroll request data with proper formatting

### Task 3.3 - Create PayrollRequestComponent styles
- **Objective:** Create component-specific styles
- **Actions (checklist):**
  - [ ] Create file `src/app/payroll-request/payroll-request.component.scss`
  - [ ] Follow `payment-report.component.scss` pattern
  - [ ] Add styles for:
    - Status badges (bg-warning, bg-danger, bg-success)
    - Expandable request/response sections
    - JSON formatting display (pre/code blocks)
- **Affected files/areas:** `src/app/payroll-request/payroll-request.component.scss` (new file)
- **Completion criteria:** Component is visually consistent with existing pages

### Task 3.4 - Implement request/response body viewer (inline expandable)
- **Objective:** Allow users to view the full request and response JSON bodies inline
- **Actions (checklist):**
  - [ ] Add expand/collapse functionality on each list item
  - [ ] Show requestBody and responseBody in expandable sections below each row
  - [ ] Format JSON for readability (pretty print using `<pre><code>`)
  - [ ] Use existing infinite scroll pagination pattern
- **Affected files/areas:** `src/app/payroll-request/payroll-request.component.ts`, `src/app/payroll-request/payroll-request.component.html`
- **Completion criteria:** Users can expand each payroll request row to view request/response bodies inline

---

### Phase 4: Routing and Module Configuration

### Task 4.1 - Create PayrollRequestModule
- **Objective:** Create the Angular module for payroll request feature
- **Actions (checklist):**
  - [ ] Create file `src/app/payroll-request/payroll-request.module.ts`
  - [ ] Follow `PaymentReportModule` structure
  - [ ] Import necessary modules:
    - CommonModule
    - SharedModule
    - ComponentsModule
    - Material modules (MatLegacyTableModule, MatBottomSheetModule, etc.)
  - [ ] Declare components: `PayrollRequestComponent`
  - [ ] Provide services: `PayrollRequestService`
  - [ ] Export PayrollRequestComponent for use in routing
- **Affected files/areas:** `src/app/payroll-request/payroll-request.module.ts` (new file)
- **Completion criteria:** Module compiles without errors and exports necessary components

### Task 4.2 - Add route in payment-routing.module.ts
- **Objective:** Configure the route for the payroll requests page
- **Actions (checklist):**
  - [ ] Add import for `PayrollRequestComponent`
  - [ ] Add route configuration:
    ```typescript
    {
      path: 'payments/:paymentId/payroll_requests',
      component: PayrollRequestComponent,
    },
    ```
  - [ ] Add after the `payment_reports` route (around line 34)
- **Affected files/areas:** `src/app/payment/payment-routing.module.ts`
- **Completion criteria:** Navigation to `/payments/:id/payroll_requests` loads the PayrollRequestComponent

### Task 4.3 - Register services and imports in payment.module.ts
- **Objective:** Ensure all new services are available in the payment module
- **Actions (checklist):**
  - [ ] Add import for `PaymentIntegrateService`
  - [ ] Add `PaymentIntegrateService` to providers array
  - [ ] Add import for `PayrollRequestModule`
  - [ ] Add `PayrollRequestModule` to imports array
- **Affected files/areas:** `src/app/payment/payment.module.ts`
- **Completion criteria:** All services are injectable in payment components

### Task 4.4 - Register PayrollRequestModule in app.module.ts
- **Objective:** Add the new module to the application
- **Actions (checklist):**
  - [ ] Add import statement: `import { PayrollRequestModule } from '@app/payroll-request/payroll-request.module';`
  - [ ] Add `PayrollRequestModule` to the imports array (in alphabetical order, after PaymentReportModule)
- **Affected files/areas:** `src/app/app.module.ts`
- **Completion criteria:** Module is loaded with the application

---

### Phase 5: Translations

### Task 5.1 - Add Portuguese (pt-BR) translations
- **Objective:** Add all necessary translation keys for the new feature
- **Actions (checklist):**
  - [ ] Add to `src/translations/pt-BR.json`:
    ```json
    "payroll_request": {
      "one": "Requisição de Folha",
      "other": "Requisições de Folha",
      "id": "ID",
      "action": {
        "one": "Ação",
        "check": "Verificação",
        "execution": "Execução",
        "validation": "Validação"
      },
      "status": {
        "one": "Status",
        "pending": "Pendente",
        "success": "Sucesso",
        "failure": "Falha"
      },
      "duration": "Duração",
      "created_at": "Criado em",
      "request_body": "Corpo da Requisição",
      "response_body": "Corpo da Resposta",
      "page": {
        "view_history": "Ver Histórico de Integração",
        "no_records": "Nenhuma requisição de integração encontrada"
      }
    }
    ```
  - [ ] Add payment-related keys:
    ```json
    "payment.page.integrate_payroll": "Integrar Folha",
    "payment.page.success_integrated": "Folha integrada com sucesso!",
    "payment.page.fail_integrate": "Falha ao integrar folha. Tente novamente."
    ```
- **Affected files/areas:** `src/translations/pt-BR.json`
- **Completion criteria:** All UI text in pt-BR is translatable

### Task 5.2 - Add English (en) translations
- **Objective:** Add English translations for internationalization
- **Actions (checklist):**
  - [ ] Add to `src/translations/en.json`:
    ```json
    "payroll_request": {
      "one": "Payroll Request",
      "other": "Payroll Requests",
      "id": "ID",
      "action": {
        "one": "Action",
        "check": "Check",
        "execution": "Execution",
        "validation": "Validation"
      },
      "status": {
        "one": "Status",
        "pending": "Pending",
        "success": "Success",
        "failure": "Failure"
      },
      "duration": "Duration",
      "created_at": "Created at",
      "request_body": "Request Body",
      "response_body": "Response Body",
      "page": {
        "view_history": "View Integration History",
        "no_records": "No integration requests found"
      }
    }
    ```
  - [ ] Add payment-related keys:
    ```json
    "payment.page.integrate_payroll": "Integrate Payroll",
    "payment.page.success_integrated": "Payroll integrated successfully!",
    "payment.page.fail_integrate": "Failed to integrate payroll. Please try again."
    ```
- **Affected files/areas:** `src/translations/en.json`
- **Completion criteria:** All UI text in English is translatable

### Task 5.3 - Add Spanish (es) translations
- **Objective:** Add Spanish translations for internationalization
- **Actions (checklist):**
  - [ ] Add to `src/translations/es.json`:
    ```json
    "payroll_request": {
      "one": "Solicitud de Nómina",
      "other": "Solicitudes de Nómina",
      "id": "ID",
      "action": {
        "one": "Acción",
        "check": "Verificación",
        "execution": "Ejecución",
        "validation": "Validación"
      },
      "status": {
        "one": "Estado",
        "pending": "Pendiente",
        "success": "Éxito",
        "failure": "Fallo"
      },
      "duration": "Duración",
      "created_at": "Creado en",
      "request_body": "Cuerpo de la Solicitud",
      "response_body": "Cuerpo de la Respuesta",
      "page": {
        "view_history": "Ver Historial de Integración",
        "no_records": "No se encontraron solicitudes de integración"
      }
    }
    ```
  - [ ] Add payment-related keys:
    ```json
    "payment.page.integrate_payroll": "Integrar Nómina",
    "payment.page.success_integrated": "¡Nómina integrada con éxito!",
    "payment.page.fail_integrate": "Error al integrar nómina. Inténtelo de nuevo."
    ```
- **Affected files/areas:** `src/translations/es.json`
- **Completion criteria:** All UI text in Spanish is translatable

---

### Phase 6: Testing and Polish

### Task 6.1 - Test legacy code removal
- **Objective:** Verify external application code was completely removed
- **Actions (checklist):**
  - [ ] Search codebase for any remaining references to "externalApplication" or "external-application"
  - [ ] Verify routes `/payments/:id/externalApplications/*` return 404
  - [ ] Check browser console for any import/module errors
- **Affected files/areas:** N/A (validation step)
- **Completion criteria:** No trace of external application code remains

### Task 6.2 - Test integration flow
- **Objective:** Verify the complete integration mutation flow
- **Actions (checklist):**
  - [ ] Navigate to a payment with `integrate` action available
  - [ ] Click "Integrar Folha" button
  - [ ] Verify loading state appears
  - [ ] Verify success snackbar on successful integration
  - [ ] Verify error snackbar on failed integration (simulate network error if needed)
  - [ ] Verify page reloads after success
- **Affected files/areas:** N/A (validation step)
- **Completion criteria:** Integration flow works end-to-end with proper feedback

### Task 6.3 - Test payroll requests page
- **Objective:** Verify the payroll requests list displays correctly
- **Actions (checklist):**
  - [ ] Navigate to `/payments/:paymentId/payroll_requests`
  - [ ] Verify table displays with correct columns
  - [ ] Verify pagination works (load more button)
  - [ ] Verify status badges have correct colors
  - [ ] Verify request/response bodies are viewable
  - [ ] Verify breadcrumb navigation works
- **Affected files/areas:** N/A (validation step)
- **Completion criteria:** Page displays all payroll request data correctly

### Task 6.4 - Test translations
- **Objective:** Verify all translations are applied correctly
- **Actions (checklist):**
  - [ ] Switch language to pt-BR and verify all text
  - [ ] Switch language to en and verify all text
  - [ ] Switch language to es and verify all text
  - [ ] Check for any missing translation keys (appear as raw keys in UI)
- **Affected files/areas:** N/A (validation step)
- **Completion criteria:** All text is properly translated in all supported languages

### Task 6.5 - Run linter and type check
- **Objective:** Ensure code quality standards are met
- **Actions (checklist):**
  - [ ] Run `npm run lint` and fix any errors
  - [ ] Run `npm run build` to verify TypeScript compilation
  - [ ] Fix any type errors
- **Affected files/areas:** All new/modified files
- **Completion criteria:** No linting errors, successful build

### Task 6.6 - Final review and cleanup
- **Objective:** Ensure code is production-ready
- **Actions (checklist):**
  - [ ] Remove any console.log statements
  - [ ] Remove any commented-out code
  - [ ] Verify consistent code formatting
  - [ ] Review component structure for best practices
  - [ ] Update CHANGELOG.md with feature description
- **Affected files/areas:** All new/modified files, `CHANGELOG.md`
- **Completion criteria:** Code is clean and ready for PR

---

## 2) Items requiring user confirmation

- [x] **Feature flag:** Not needed - system already uses granular permissions via `payment_policy.integrate?`
- [x] **Backend endpoint confirmation:** Available via commit cd053f82d
- [x] **Permission check:** Handled by existing permission resolver pattern (`*_permissions_graphql_resolver`)
- [x] **UI decision:** Inline expandable sections with infinite scroll pagination (consistent with existing list patterns)

> **APPROVED:** No feature flag; inline expandable for request/response; infinite scroll pagination.

---

## 3) Outstanding items after this iteration (if any)

- [ ] Consider adding unit tests for new services (PaymentIntegrateService, PayrollRequestService)
- [ ] Consider adding E2E tests for the integration flow
- [ ] Monitor for performance issues with large payroll request lists
- [ ] Update `PLAN.md` if additional iterations are required

---

## 4) Implementation Progress (2025-12-25)

### Completed
- [x] Phase 0: Remove External Application Legacy Code
- [x] Phase 1: Foundation (Services and Models)
- [x] Phase 2: Integration Button in Payment-Show
- [x] Phase 3: UserPayment Page (renamed from PayrollRequest)
- [x] Phase 4: Routing and Module Configuration
- [x] Phase 5: Translations

### Additional Changes (not in original plan)
- [x] Renamed PayrollRequest component to UserPayment component
- [x] Added balance column to payroll requests (shows value from check and validation)
- [x] Ordered payroll requests: check → execution → validation
- [x] Currency formatting uses environment variables
- [x] Button visibility uses whitelist approach (`actions.includes('integration_report')`)

### Completed - Filters ✅

#### Task F.1 - Update UserPaymentService to accept filters ✅
- **File:** `src/app/user-payment/user-payment.service.ts`
- **Actions:**
  - [x] Add `userId` parameter to GraphQL query
  - [x] Add `paymentTypeId` parameter to GraphQL query
  - [x] Add `integrationStatus` parameter to GraphQL query
- **GraphQL params:** `userId`, `paymentTypeId`, `integrationStatus`

#### Task F.2 - Update Filter model ✅
- **File:** `src/app/shared/filter.model.ts`
- **Actions:**
  - [x] Add `integrationStatus?: string` property
  - Note: `userId` and `paymentTypeId` already existed in the model

#### Task F.3 - Add filter UI to UserPaymentComponent ✅
- **Files:** `user-payment.component.ts`, `user-payment.component.html`
- **Actions:**
  - [x] Add user autocomplete filter (search by name)
  - [x] Add payment type autocomplete filter
  - [x] Add integration status dropdown filter (pending/integrated/failed)
  - [x] Add "Apply Filters" and "Clear Filters" buttons
  - [x] Reset pagination when filters change
  - [x] Persist filters via URL queryParams

#### Task F.4 - Add translations for filters ✅
- **Status:** Translations already existed for the keys used:
  - `user.one`
  - `payment_type.one`
  - `user_payment.integration_status`
  - `user_payment.integration_status_values.*`

#### Task F.5 - Add integration confirmation dialog ✅
- **File:** `src/app/payment/show/payment-show.component.ts`
- **Actions:**
  - [x] Add confirm() dialog before starting integration
  - [x] Add translation key `payment.page.integrate_confirmation`

### Summary
| Item | Status |
|------|--------|
| Branch | `feature/payment-payroll-integration` |
| Commit | `aab20e29c feat(payment): add payroll integration` |
| PR Status | Pushed and ready for review |
