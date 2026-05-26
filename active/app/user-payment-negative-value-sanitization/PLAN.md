# PLAN — User Payment Negative Value Sanitization

## Current Situation

- Relevant context/architecture:
  - Company has a `money_sanitization` boolean flag (default `true`) that today only controls zeroing at `User Commission.billable_money` aggregate level via `Commission::MoneySanitizerProcessor`.
  - `User Commission` and `User Payment` are independent entities in different domains (commission vs. payment). A Payment has many Commissions; each Commission has many User Commissions; each Payment has many User Payments (one per user + payment_type). There is no direct relationship between a User Commission and a User Payment.
  - The payment flow (`Payment::Producer`, `Payment::Consumer`, `Payment::Finalizer`) reads `User Payment Type Commission` values directly and does not respect the sanitization performed on User Commission.
  - Two production environments exist: a shared multi-tenant environment and a dedicated Atento environment.

- Impacted components:
  - `app/workers/commission/money_sanitizer_processor.rb` (unchanged behavior, referenced for context)
  - `app/workers/payment/consumer.rb` (unchanged behavior, referenced for context)
  - `app/workers/payment/finalizer.rb` (new sanitization step to be added)
  - Company records in both production environments
  - Historical User Payment, User Commission, Commission, Payment records identified in SPIKE.md

- Versions/environment: Rails 8.1, PostgreSQL. Both production environments use the same codebase.

## Objective / Target State

- Desired outcome:
  - When `money_sanitization = true` on a Company, no User Payment shall carry a negative `billable_money` value after the Payment is finalized.
  - When `money_sanitization = false` on a Company, neither User Commission nor User Payment are sanitized. Raw values flow through, including negatives.
  - The User Commission sanitization rule remains unchanged (zeroes aggregate when negative).
  - Historical data corrected where necessary so each production environment reflects the new rule consistently.

- Success metrics / acceptance criteria:
  - After deployment, a scan of User Payments with `billable_money < 0` in Companies with `money_sanitization = true` returns zero results.
  - Company 97 remains with `money_sanitization = true`, and its historical negative User Payment is updated to zero.
  - Company 1879 is moved to `money_sanitization = false`, and its historical sanitized User Commissions are updated to raw sums.
  - Commission and Payment aggregate values are recalculated wherever their underlying components were touched.

## Problem / New Feature

- Objective description: the current `money_sanitization` flag only prevents negatives at User Commission aggregate level. In scenarios where the User Commission aggregate remains positive but an individual Payment Type bucket is negative, the negative value leaks to User Payment and from there into exported reports consumed by customer payroll systems.

- Symptoms:
  - Found 15 historical User Commissions in the shared environment with mixed-sign User Payment Type Commissions where the current display differs from the sum of positive Payment Type contributions.
  - Found 7 historical User Payments with negative `billable_money` across Companies 97 and 1879, all of which were included in downloaded `PaymentReport` files of purpose `ResultsByPaymentType`.
  - Company 1879 exhibits a recurring monthly pattern (Payment Type 2594 consistently negative).

## Challenges, Difficulties and Risks

- Technical:
  - User Payment is populated by `Payment::Consumer` via `update_counters` as multiple commission contributions accumulate. Zeroing must happen after all contributions are added, not per-contribution, to match the stated rule "zero when the User Payment itself is negative".
  - Commissions that already have an associated Payment cannot be reprocessed (state machine blocks it). This means historical data corrections must be done directly on the records and will not be undone by a later reprocessing.
  - The fix introduces a controlled divergence: when User Commission aggregate is positive but one Payment Type bucket is negative, the sum of User Payments for a user in a Payment may exceed the User Commission. Accepted because the surprise is always in favor of the vendor.

- Product/UX:
  - Company 1879 vendors who historically saw `0` on dashboard due to aggregate zeroing will now see the raw value (possibly negative) after historical correction. Narrative: "the dashboard had a bug that zeroed the display when the aggregate was negative. The paid value always reflected the raw sum. We corrected the display to match what was paid."
  - No external customer communication planned. If a vendor surfaces questions, the platform tenant response is that the payment value was never changed and the dashboard display was corrected.

- Security/privacy: none.

- Performance: Finalizer runs once per Payment at the end of processing. Additional query to zero negative User Payments is scoped by `payment_id` and uses existing indexes. Negligible overhead.

## Solution Options (comparative)

- **Option 1 — Sanitize User Payment at Finalizer, gated by `money_sanitization`** (APPROVED)
  - **How it works:** In `Payment::Finalizer`, before summing User Payments into `Payment.money`, check if the Payment's Company has `money_sanitization = true` and, if so, update all User Payments of this Payment with `billable_money < 0` to zero. Then proceed with the existing sum and `Payment.money` update.
  - **Pros:** Operates on the final consolidated value (after all Consumer contributions are applied). Does not modify User Payment Type Commission data. Does not touch User Commission logic. Clean separation of concerns between the two domains. Matches the "zero when the value itself is negative" rule explicitly.
  - **Cons:** Introduces the controlled divergence described in Challenges. Confirmed as acceptable given the rarity of the pattern in customers remaining with `money_sanitization = true`.
  - **When NOT to use:** N/A — this is the chosen approach.

- **Option 2 — Sanitize per contribution in Payment::Consumer**
  - **How it works:** At each invocation of `Payment::Consumer`, after computing the per-(user_commission, payment_type) sum, zero it if negative before calling `update_counters`.
  - **Pros:** Simpler place to add the check.
  - **Cons:** Zeroes each negative contribution individually, not the final User Payment aggregate. Produces a different result when multiple User Commissions contribute to the same User Payment and one contributes negative while another contributes positive. Does not match the stated rule.
  - **When NOT to use:** Chosen not to pursue. Final-value semantics are required.

- **Option 3 — Cascade zero from User Commission to User Payment**
  - **How it works:** When User Commission is zeroed by the existing sanitizer, also zero all User Payments that received contributions from that User Commission.
  - **Pros:** Aligns User Commission and Payment values.
  - **Cons:** User Payment aggregates multiple User Commissions. Zeroing the whole User Payment discards legitimate contributions from other User Commissions. Removing only the specific contribution requires reversing the `update_counters` delta, which is complex and brittle. There is also no direct relationship between User Payment and User Commission, so the cascade requires walking through the parent Payment and Commission relations, which is conceptually awkward.
  - **When NOT to use:** Chosen not to pursue due to conceptual and technical fragility.

## Execution Steps

Execution model: no migrations, no rake tasks, no maintenance windows. All data inspection and correction runs interactively in the Rails console via `bin/ecs connect`, one block at a time, with the engineer checking outputs between steps. 4Shark runs live at all times.

### 1. Discovery sweep across both production environments

Before any code change, revisit the entire data set with the full context now available (DB Schema, entity relationships, attention points). The previous scan targeted User Commissions with mixed-sign User Payment Type Commissions. This sweep goes broader to catch patterns that do not start at User Commission level — for example, a User Payment that ends up negative because multiple User Commissions of the same user contribute negative values on the same Payment Type, without any single User Commission showing mixed signs.

Scope: all Companies, both environments, no filter by `money_sanitization`.

Goal: find any scenario that Option 1 does not cover. If one emerges, update this plan before writing code. Avoiding puxadinhos is the goal — one solution that fits every customer, not a main solution plus exceptions.

Detailed snippets are in `TASKS.md`, Task 1.

### 2. Analyze sweep findings and confirm coverage

Group findings by pattern. For each pattern, verify explicitly that Option 1 leaves the system in a correct state. If a new pattern is not covered, document the gap and update this plan before any code change starts.

This is the gate. The solution is locked in only after this analysis completes.

### 3. Code change in Payment::Finalizer

In `app/workers/payment/finalizer.rb`, add a sanitization step before the final sum:

```ruby
def perform(payment_id)
  payment = Payment.with_uncached_connection { Payment.find(payment_id) }
  company = Company.with_uncached_connection { payment.company }

  if company.money_sanitization?
    UserPayment.with_uncached_connection do
      payment.user_payments.where('billable_money < 0').update_all(billable_money: 0)
    end
  end

  billable_money = UserPayment.with_uncached_connection { payment.user_payments.sum(:billable_money) }
  points = UserPayment.with_uncached_connection { payment.user_payments.sum(:points) }
  Payment.with_uncached_connection { payment.update_columns(money: billable_money, points: points) }

  Payment.with_uncached_connection { payment.finish_process! }
  Lock.delete(payment.lock_key)
end
```

No changes to `Payment::Consumer` or `Commission::MoneySanitizerProcessor`.

### 4. RSpec coverage

Create `spec/workers/payment/finalizer_spec.rb` verifying:
- When Company has `money_sanitization = true`, negative User Payments of the finalized Payment become zero and positives remain untouched.
- When Company has `money_sanitization = false`, negative User Payments remain negative.
- `Payment.money` reflects the post-sanitization sum in both cases.

Follow project RSpec conventions (TESTING.md): all `let` at top, alphabetical order; `before` for actions only; `it` for one-line assertions with explicit values; no instance variables.

### 5. Historical data corrections in Rails console

Executed interactively via `bin/ecs connect`, one block at a time, with pre- and post-state checks around each update.

**Company 97 (shared environment, remains with `money_sanitization = true`):**

- User Payment 70858 (user 365901, payment 5451, payment_type 86): update `billable_money` from `-865.12` to `0`.
- Recalculate `Payment.money` for Payment 5451 by summing its current User Payments.

The second historical User Commission (72970306) is left untouched — its corresponding User Payment was never negative because the Payment was scoped to a single Payment Type and the negative Payment Type Commission did not propagate.

**Company 1879 (shared environment, flag changes from `true` to `false`):**

- Update `Company.money_sanitization` from `true` to `false`.
- User Commission 88965496 (commission 54762): update `billable_money` from `0` to `-11.54`.
- User Commission 88965499 (commission 54762): update `billable_money` from `0` to `-11.11`.
- Recalculate `Commission.billable_money` for Commission 54762 summing its current User Commissions.

Other User Commissions identified in the investigation (78489866, 88529581, 88965501, 89582283, 89582288) already hold the raw sum on `billable_money` — no correction needed.

User Payments of Company 1879 with negative `billable_money` are left as-is — they reflect the raw value that matches the new `money_sanitization = false` state and also match what was historically exported in the downloaded reports.

**Any additional records surfaced by step 1 / step 2:** corrected using the same interactive pattern.

### 6. Deploy code change

Standard commit, PR, and deployment flow. No maintenance window. Code reaches both production environments through the normal pipeline. Historical corrections from step 5 are already in place when the code deploys.

### 7. Post-deployment verification

- In both production environments, run the scan confirming zero User Payments with negative `billable_money` in Companies with `money_sanitization = true`.
- Confirm Company 97: User Payment 70858 has `billable_money = 0`; Payment 5451's `money` reflects the sum of its User Payments.
- Confirm Company 1879: `money_sanitization` flag is `false`; User Commissions 88965496 and 88965499 show the expected negative values; Commission 54762's `billable_money` equals the sum of its User Commissions.
- Observe the next real Payment::Finalizer run in each environment and confirm no regressions.
- Update `CHANGELOG.md` on the `app` project with a user-focused entry under `### Fixed`.

## Internal References

- Code: `app/workers/commission/money_sanitizer_processor.rb`
- Code: `app/workers/payment/consumer.rb`
- Code: `app/workers/payment/finalizer.rb`
- Code: `app/models/payment.rb`
- Code: `app/models/user_payment.rb`
- Code: `app/models/user_commission.rb`
- Code: `app/models/company.rb`
- Code: `app/work_books/payment_work_book/results_by_payment_type_sheet.rb`
- Related: `SPIKE.md` in the same directory

---

**Status:** APPROVED — Option 1. Execution proceeds as described in Execution Steps. Detailed task breakdown in `TASKS.md` in the same directory.
