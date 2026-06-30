# ANALYSIS — Integration visualization specialization (Phase 2)

**Date**: 2026-06-29
**Scope**: current state of how a payment's payroll integration is visualized (app GraphQL backend + `app-webclient` Angular front), and the gap to specialize it per account configuration — Maqnelson has user-triggered reprocess/retry, Atento (FPW) does not.
**Source**: read-only discovery across `app` and `app-webclient` (file:line citations below).

---

## 1. Current backend surface (`app` GraphQL)

- **Integration TYPE is NOT exposed via GraphQL.** `CompanyGraphqlType` has no `payroll_integration` field (the association exists on the model — `company.rb:72 has_one :payroll_integration`). There is no `PayrollIntegrationGraphqlType`. The front cannot ask which integration an account uses.
- **The only indirect signal is the `actions` array** on `PaymentGraphqlType`:
  - `payment_graphql_type.rb:48-49` — `actions << 'integrate' if payroll_integration_policy.create?` / `actions << 'integration_report' if payroll_integration_policy.show?`.
  - `PayrollIntegrationPolicy#create?` (`payroll_integration_policy.rb:5-6`) gates on `company.payroll_integration.present?` **and** `record.final? || record.integration_error?` — it checks **presence, never type**.
- **Status is exposed as bare strings.** `UserPayment.integration_status` enum `{pending, success, failure, skipped}` → `user_payment_graphql_type.rb:8` (`field :integration_status, String`). `Payment.status` (incl. `pending_integration`/`integrating`/`integrated`/`integration_error`) → `payment_graphql_type.rb:34`.
- **Reprocess trigger = re-call `integratePayment`.** No dedicated reprocess mutation exists (`integrate_payment_graphql_mutation.rb`). The state machine already allows it: `queue_integration` transitions `final → pending_integration` **and** `integration_error → pending_integration` (`payment.rb:81-97`).
- **The ONLY type-branching (FPW vs Maqnelson) is server-side**, in `PayrollIntegration::Dispatcher` (`dispatcher.rb:12-19`). No capability methods (`reprocessable?` / `supports_retry?`) exist on `PayrollIntegration` or its subclasses.

## 2. Current front surface (`app-webclient`, Angular)

Single-workspace (`src/app/`), whitelabel client projects in `angular.json`. Integration UI spans `payment/`, `user-payment/`.

- **Payment list** — status filter includes `pending_integration`/`integrating`/`integrated` (`payment/payment.component.html:79-81`); row renders `payment.status`.
- **Payment show** — "Integrate Payroll" button gated on `payment.actions.includes('integrate')` → `integrate()` → `integratePayment` mutation (`payment/show/payment-show.component.html:97-104`, `.ts:216-224`); "Integration Report" link gated on `actions.includes('integration_report')` → routes to the user-payments screen (`payment-show.component.html:26-31`).
- **User-payment (integration audit) screen** — per-row `integrationStatus` badge `pending/success/failure/skipped` (`user-payment/user-payment.component.html:127-137`); expandable `payrollRequests` showing `action/balance/status/duration`, **sorted `['check','execution','validation']`** (`user-payment.component.html:152-189`). **This is FPW-3-wave-shaped.**
- **No retry/reprocess UI anywhere** (zero hits for `retry`/`reprocess`/`reintegrar`). **The front does NOT branch on integration type** (zero hits for `FpwIntegration`/`MaqnelsonIntegration`/`payrollIntegration`). The front is blind to the integration type — it only consumes `actions`, `status`, `integrationStatus`.

## 3. The gap

1. **The front cannot distinguish Maqnelson from FPW.** To show/hide the reprocess affordance per account, the backend must expose a capability (or the type).
2. **A "reprocess" already exists implicitly for BOTH integrations.** The Integrate button reappears when a payment is in `integration_error`, because the policy allows `create?` from `integration_error` (`payroll_integration_policy.rb:6`). So **"Atento não tem retry" is a PRODUCT decision to suppress**, not a current technical block. The specialization = expose the capability + the front presents an explicit reprocess affordance for Maqnelson, and suppresses it for FPW.
3. **The integration report / user-payment screen is FPW-shaped.** It is built around FPW's 3 actions (`check/execution/validation`) — sort order and per-action labels. Maqnelson logs a **single batch-level send** action; the current layout won't represent it correctly. So the report visualization itself may need specialization, beyond the retry button — this is a scope question.

## 4. Decisions needed (before any code)

| # | Decision | Options |
|---|---|---|
| Q1 | How to model the reprocess capability | Polymorphic method on `PayrollIntegration` (subclass overrides) **[rec]** vs. type-check in the resolver/policy |
| Q2 | How to expose it to the front | Extend the `actions` array with a `reprocess` entry gated by the capability **[rec]** vs. expose the integration type / a capability field for the front to branch on |
| Q3 | The reprocess trigger | Reuse `integratePayment` (state machine + policy already support re-integration from `integration_error`) **[rec]** vs. a dedicated `reprocessPayment` mutation |
| Q4 | Scope of the report visualization | Only the reprocess affordance **[rec for now]** vs. also specialize the integration-report/user-payment screen for Maqnelson's batch-send shape |
