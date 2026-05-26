# SPIKE — Money Sanitization Scope Coverage on User Payment

**Conducted by:** Paulo Ribeiro
**Date:** 2026-04-14
**Status:** Research complete — pending implementation (see PLAN.md)

---

## Goal

Investigate whether the Company flag `money_sanitization`, which currently zeroes `User Commission.billable_money` when its aggregate is negative, leaves negative values leaking into the downstream payment flow (`User Payment`, `Payment`, exported reports).

Questions to answer:
1. Can a User Payment end up with negative `billable_money` even when its parent User Commission was sanitized?
2. If yes, how widespread is this across the production data?
3. Did these negative values actually reach customers (via exports, payroll integrations, or manual downloads)?
4. What is the right design to close the gap without creating friction with existing customers?

---

## Method

- Read the commission calculation flow from the 5 incentive types down through `User Payment Type Commission`, `User Commission`, and `Commission`.
- Read the payment flow in `Payment::Producer`, `Payment::Consumer`, and `Payment::Finalizer`.
- Ran ActiveRecord queries in both production environments (shared multi-tenant and dedicated Atento) to measure the incidence of the pattern and identify affected records.
- Cross-referenced affected User Commissions with Payments, User Payments, Payment Exportations, Payment Reports, and download history.

---

## Evidence

### Current sanitization behavior

File: `app/workers/commission/money_sanitizer_processor.rb` — lines 19-21:

```ruby
if company.money_sanitization?
  UserCommission.where(money: ...0).update_all(money: 0)
  UserCommission.where(billable_money: ...0).update_all(billable_money: 0)
end
```

The flag acts only at the `User Commission` aggregate level. It does not touch `User Payment Type Commission`, `User Payment`, or `Payment`.

### Payment flow reads User Payment Type Commission directly

File: `app/workers/payment/consumer.rb` — lines 11-16:

```ruby
billable_money =
  UserPaymentTypeCommission
    .where(user_commission_id: user_commission_id, payment_type_id: payment_type_id)
    .sum(:billable_money)
```

This sum does not respect the sanitization performed on the parent `User Commission`. Negative `User Payment Type Commission` values flow through to `User Payment` unchecked.

File: `app/workers/payment/finalizer.rb` — lines 10-12:

```ruby
billable_money = UserPayment.with_uncached_connection { payment.user_payments.sum(:billable_money) }
points = UserPayment.with_uncached_connection { payment.user_payments.sum(:points) }
Payment.with_uncached_connection { payment.update_columns(money: billable_money, points: points) }
```

Finalizer sums all User Payments into `Payment.money` without any per-record validation.

### Scope of the pattern in production

Query strategy: iterate Plans that have more than one Payment Type (prerequisite for mixed-sign User Payment Type Commissions), then per-plan iterate final Commissions in Companies with `money_sanitization = true`, then per-commission iterate User Commissions and compare the current stored `billable_money` against the sum of positive User Payment Type Commissions.

Result in dedicated environment (Atento): 823 plans with multiple payment types, **zero** User Commissions affected.

Result in shared environment: 5565 plans with multiple payment types, **15 User Commissions** affected across 3 companies:

| Company | Status | User Commissions affected | Total display divergence |
|---------|--------|---------------------------|--------------------------|
| 1385    | cancelled long ago | 6 (across 2 commissions) | ~R$ 8,780 |
| 97      | active 6+ years    | 2 (across 2 commissions) | ~R$ 2,090 |
| 1879    | active, unknown tenure | 7 (across 4 commissions) | ~R$ 947 |

### Did negative values leave the platform?

For Companies 97 and 1879, six payments were generated containing the affected User Commissions. Status of each:

- All six Payments are in `final` status. None went through the formal `PaymentExportation` flow.
- All six Payments have a `PaymentReport` with purpose `ResultsByPaymentType`, and each report was downloaded at least once by a platform user.
- These two customers manually upload the downloaded report into an external payroll system.

User Payments with negative `billable_money` that were included in downloaded reports:

| Payment | Company | User   | Payment Type | Value        | Downloaded   |
|---------|---------|--------|--------------|--------------|--------------|
| 5451    | 97      | 365901 | 86           | -865.12      | 2025-01-31   |
| 6243    | 1879    | 771219 | 2594         | -107.14      | 2025-07-23   |
| 6475    | 1879    | 995385 | 2594         | -69.23       | 2025-08-26   |
| 6475    | 1879    | 1032493| 2594         | -111.11      | 2025-08-26   |
| 6475    | 1879    | 1050270| 2594         | -228.00      | 2025-08-26   |
| 6704    | 1879    | 793772 | 2594         | -285.71      | 2025-09-25   |
| 6704    | 1879    | 1065220| 2594         | -63.64       | 2025-09-25   |

These values reached the customer's internal payroll workflow. We have no visibility into whether the external system accepted the negatives, floored them at zero, or triggered a manual adjustment by the customer.

### Customer configuration patterns

Company 1879 shows a recurring pattern: the same Payment Type (2594) produces negative values every month over multiple months, in multiple user commissions. This suggests a stable plan configuration that systematically generates negative User Payment Type Commission values on one Payment Type.

Company 97 shows only two historical cases over 6+ years. Very rare occurrence.

---

## Conclusions

1. **The gap is real.** The `money_sanitization` flag only covers the User Commission aggregate. Negative values can and do leak through to User Payments and exported reports.

2. **Production impact is concentrated.** Only 3 companies in 2 production environments exhibit the pattern. One is cancelled. The other two are active.

3. **The negatives reached customers.** Via the `PaymentReport` download path, not via `PaymentExportation`. The customer's internal payroll system received files containing negative line items.

4. **User Commission and User Payment are independent entities in different domains.** User Payment is produced after User Commission and aggregates potentially multiple User Commissions. There is no direct relationship between them — the link is through their parents (Payment has many Commissions; Commission has many User Commissions; Payment has many User Payments, one per user + payment_type).

5. **Any design that tries to cascade or mirror sanitization between the two entities breaks.** The only coherent options are: (a) apply an independent sanitization rule at User Payment level, or (b) do not sanitize anywhere and let raw values flow.

6. **Option (a) introduces a controlled divergence.** In scenarios where the User Commission aggregate is positive but one of its Payment Types aggregates to negative, User Payment is zeroed while User Commission stays at its positive value. The consequence is that the sum of User Payments for a user in a given Payment may be larger than the User Commission shown on the dashboard. This is a "positive surprise" for the vendor (they receive more than they saw). It is accepted given its rarity (only one such case in 6+ years on Company 97).

7. **Option (b) keeps everything consistent but allows negative line items in exported files.** Chosen for Company 1879, whose plan configuration systematically produces negatives and whose operational flow already processes them externally for more than a year.

---

## Next Steps

Produces `PLAN.md` in the same directory covering:
- Code change to zero User Payment `billable_money` when negative, gated by `money_sanitization = true`.
- Per-customer migration decisions for Companies 97 and 1879.
- Data correction of historical records identified in the Evidence section.
- Rollout plan for both production environments.

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
