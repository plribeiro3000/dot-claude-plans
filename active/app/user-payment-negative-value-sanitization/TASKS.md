# NEXT TASKS — User Payment Negative Value Sanitization — Option 1

> **Objective of this iteration:** Close the coverage gap where the `money_sanitization` flag only acts on User Commission aggregate, allowing negative values to leak into User Payment and downstream payment artifacts. Before implementing, perform an exhaustive sweep of both production environments to validate that the proposed solution covers every scenario that exists in real data. Only then implement the code change, correct historical records, and roll out.
> **Reference:** `PLAN.md` and `SPIKE.md` in the same directory.

---

## 0) Pre-conditions

- [ ] `PLAN.md` approved (chosen solution: Option 1 — Sanitize User Payment at Finalizer, gated by `money_sanitization`)
- [ ] Base branch: `develop` • Working branch: `feature/user-payment-negative-value-sanitization`
- [ ] Access to both production environments via `bin/ecs connect` / `bin/ecs run` (Rails console)
- [ ] Execution model: no migrations, no rake tasks, no maintenance windows. All data inspection and correction runs interactively in Rails console as Ruby snippets, one block at a time, with the engineer checking outputs between steps. 4Shark is always live; the app cannot go down.

---

## 1) Step by Step (atomic tasks)

### Task 1 — Exhaustive discovery sweep across both production environments

- **Objective:** Revisit the entire data set with the full context now available (DB Schema, entity relationships, what can be lost, known attention points) to surface every scenario where the current behavior leaves negative values in User Payment, Payment, Commission, User Commission, User Payment Type Commission, or any related artifact. The previous scan targeted User Commissions with mixed-sign User Payment Type Commissions; this sweep goes broader to catch patterns that do not start at User Commission level.
- **Rationale:** Before committing to the implementation, confirm that the proposed solution (sanitize at Payment::Finalizer when `money_sanitization = true`; flip Company 1879 to `false`) covers every scenario present in real data. If a new pattern emerges that the solution does not cover, iterate on the design before writing any code. Avoiding puxadinhos is the goal — one solution that fits every customer, not a main solution plus exceptions.
- **Actions (checklist):**
  - [ ] Re-read `db/schema.rb` for all tables involved: `companies`, `commissions`, `partial_commissions`, `user_commissions`, `user_payment_type_commissions`, `payments`, `user_payments`, `payment_types`, `commissionings`, `payment_exportations`, `payment_reports`, `payment_report_downloads`, and any table connected to the payment flow.
  - [ ] For each table, list the columns that can hold monetary values (`billable_money`, `money`, and per-incentive fields like `deal_money`, `modifier_money`, `ranking_money`, `limiter_money`, `redemption_money`, `points` where applicable).
  - [ ] Map the relationships end to end: Commission → User Commission → User Payment Type Commission on the commission side; Payment → User Payment on the payment side; Payment ↔ Commission link via `Commission.payment_id`.
  - [ ] In each production environment (shared multi-tenant first, dedicated Atento second), iterate **all Companies** — no filter by `money_sanitization`. The sweep is not scoped to the flag because the discovery goal is to find any scenario, in any account.
  - [ ] Run the following console snippets one at a time, capturing output between each step. Flush stdout frequently to keep the ECS Exec session alive.

    ```ruby
    # Step 1.1 — Negative User Payment billable_money across all Companies
    Company.find_each do |company|
      count = 0
      total = 0
      company.payments.find_each(batch_size: 200) do |payment|
        payment.user_payments.where('billable_money < 0').find_each(batch_size: 200) do |up|
          count += 1
          total += up.billable_money
          puts "company=#{company.id} payment=#{payment.id} user_payment=#{up.id} payment_type=#{up.payment_type_id} billable_money=#{up.billable_money}"
          $stdout.flush
        end
      end
      warn "# company=#{company.id} name=#{company.name} money_sanitization=#{company.money_sanitization} negatives=#{count} total=#{total}" if count > 0
      $stdout.flush
    end
    ```

    ```ruby
    # Step 1.2 — Negative Payment money across all Companies
    Company.find_each do |company|
      count = 0
      company.payments.where('money < 0').find_each do |p|
        count += 1
        puts "company=#{company.id} payment=#{p.id} status=#{p.status} money=#{p.money}"
        $stdout.flush
      end
      warn "# company=#{company.id} negatives=#{count}" if count > 0
      $stdout.flush
    end
    ```

    ```ruby
    # Step 1.3 — Negative Commission billable_money across all Companies
    Company.find_each do |company|
      count = 0
      Commission.where(company_id: company.id).where('billable_money < 0').find_each do |c|
        count += 1
        puts "company=#{company.id} commission=#{c.id} status=#{c.status} billable_money=#{c.billable_money} money=#{c.money}"
        $stdout.flush
      end
      warn "# company=#{company.id} negatives=#{count}" if count > 0
      $stdout.flush
    end
    ```

    ```ruby
    # Step 1.4 — Negative User Commission billable_money across all Companies (includes already-sanitized zeros plus raw negatives where flag=false)
    Company.find_each do |company|
      count = 0
      Commission.where(company_id: company.id).find_each(batch_size: 200) do |commission|
        commission.user_commissions.where('billable_money < 0').find_each do |uc|
          count += 1
          puts "company=#{company.id} commission=#{commission.id} user_commission=#{uc.id} billable_money=#{uc.billable_money}"
          $stdout.flush
        end
      end
      warn "# company=#{company.id} money_sanitization=#{company.money_sanitization} negatives=#{count}" if count > 0
      $stdout.flush
    end
    ```

    ```ruby
    # Step 1.5 — Same as the previous scope pass but broader: User Commissions whose sum of User Payment Type Commissions diverges from the stored billable_money
    Company.find_each do |company|
      count = 0
      Commission.where(company_id: company.id).find_each(batch_size: 200) do |commission|
        commission.user_commissions.find_each(batch_size: 200) do |uc|
          uptcs = uc.user_payment_type_commissions.pluck(:billable_money)
          next if uptcs.empty?
          raw_sum = uptcs.sum
          max_zero_sum = uptcs.sum { |v| [v, 0].max }
          next if uc.billable_money == raw_sum || uc.billable_money == max_zero_sum
          count += 1
          puts "company=#{company.id} user_commission=#{uc.id} stored=#{uc.billable_money} raw=#{raw_sum} max_zero=#{max_zero_sum}"
          $stdout.flush
        end
      end
      warn "# company=#{company.id} divergent=#{count}" if count > 0
      $stdout.flush
    end
    ```

    ```ruby
    # Step 1.6 — PartialCommission parity check (same logic as Commission)
    Company.find_each do |company|
      count = 0
      PartialCommission.where(company_id: company.id).where('billable_money < 0').find_each do |pc|
        count += 1
        puts "company=#{company.id} partial_commission=#{pc.id} billable_money=#{pc.billable_money}"
        $stdout.flush
      end
      warn "# company=#{company.id} partial_negatives=#{count}" if count > 0
      $stdout.flush
    end
    ```

    ```ruby
    # Step 1.7 — Outputs already exported: identify Payments whose negative User Payments were included in downloaded PaymentReports
    negative_payment_ids = UserPayment.where('billable_money < 0').distinct.pluck(:payment_id)
    negative_payment_ids.each do |pid|
      reports = PaymentReport.where(payment_id: pid, purpose: 'ResultsByPaymentType')
      reports.each do |r|
        downloads = r.downloads.count
        puts "payment=#{pid} report=#{r.id} status=#{r.status} created=#{r.created_at} downloads=#{downloads}"
        $stdout.flush
      end
    end
    ```

  - [ ] For each account that surfaces in any step, record: company id, company name, `money_sanitization` flag, status (active / cancelled), count and sum of negative records, whether any affected Payment has a downloaded PaymentReport.
  - [ ] Compare the sweep results against the 3 companies already identified (1385 cancelled, 97, 1879). Flag any **new** company or **new pattern** that was not covered by the earlier scan.
- **Affected files/areas:** read-only queries against both production environments (shared multi-tenant and dedicated Atento).
- **Completion criteria:** A consolidated report exists (in conversation or written to `/tmp/` following the External Results Policy) listing every account with negative values in any of the surveyed tables, the specific records, and whether they were exposed via PaymentReport downloads.
- **Observations:** Session timeout mitigation: `$stdout.flush` after every `puts` and periodic `warn` to stderr. If any snippet runs longer than a few minutes without output, add a `warn "# checkpoint company=..."` at sensible intervals.

### Task 2 — Analyze sweep findings and confirm solution coverage

- **Objective:** Compare the sweep output against the design decisions in PLAN.md. Confirm that the chosen solution (Payment::Finalizer sanitization gated by `money_sanitization`, flip Company 1879 to `false`, data corrections for specific records) covers every scenario found. If a new pattern emerges that the solution does not cover, iterate on the design before any code is written.
- **Actions (checklist):**
  - [ ] Group sweep findings by pattern: (a) negative User Payment with no parent User Commission sanitized, (b) negative User Commission with flag false already, (c) negative Commission or Payment aggregate, (d) divergence between stored User Commission `billable_money` and the sum of its User Payment Type Commissions, (e) any pattern not anticipated by the SPIKE.
  - [ ] For each group, verify explicitly: does the chosen solution leave the system in a correct and consistent state for that pattern?
    - If yes, continue.
    - If no, document the gap and propose a design adjustment. Update PLAN.md before writing any code.
  - [ ] Document any additional companies beyond 1385, 97, 1879 that require historical data correction. Update the specific record lists used by Task 5.
  - [ ] Confirm the sweep output matches what the SPIKE predicted for the 3 known companies (the 7 historical negative User Payments tied to PaymentReport downloads). Any discrepancy is itself a finding to investigate.
- **Affected files/areas:** updates to `PLAN.md` and the record lists in Task 5, if findings require it. No application code touched yet.
- **Completion criteria:** Written confirmation that the solution covers every pattern found in the sweep, or an updated plan that does. No code change starts until this confirmation exists.
- **Observations:** This is the gate. The solution is locked in only after this task completes. The goal is to avoid discovering a new pattern after implementation and having to maintain a second exception-based solution alongside the main one.

### Task 3 — Add sanitization step to Payment::Finalizer

- **Objective:** Implement the sanitization logic in `app/workers/payment/finalizer.rb` such that, when the Payment's Company has `money_sanitization = true`, any User Payment with `billable_money < 0` is set to zero before the final aggregation.
- **Actions (checklist):**
  - [ ] Read existing implementation in `app/workers/payment/finalizer.rb`.
  - [ ] Add a sanitization step before the current sum:
    - Load the Company via `payment.company`.
    - If `company.money_sanitization?` is true, update all User Payments of the Payment with `billable_money < 0` to `0`.
    - Follow the existing pattern with `with_uncached_connection`.
  - [ ] Keep User Commission and User Payment Type Commission untouched. No code change in `Payment::Consumer` or `Commission::MoneySanitizerProcessor`.
- **Affected files/areas:** `app/workers/payment/finalizer.rb`.
- **Completion criteria:** Code change in place, consistent with existing patterns (frozen_string_literal, indentation, `with_uncached_connection` usage). No other files changed.

### Task 4 — RSpec coverage for Payment::Finalizer sanitization

- **Objective:** Add tests that exercise both branches of the new sanitization logic.
- **Actions (checklist):**
  - [ ] Read 2–3 existing spec files in `spec/workers/payment/` to mirror the project's RSpec structure exactly (TESTING.md policy).
  - [ ] Create `spec/workers/payment/finalizer_spec.rb` covering:
    - Company with `money_sanitization = true`: User Payments with `billable_money < 0` become zero; positive User Payments remain unchanged; `Payment.money` reflects the post-sanitization sum.
    - Company with `money_sanitization = false`: User Payments with `billable_money < 0` remain negative; `Payment.money` reflects the raw sum.
  - [ ] Follow project conventions strictly: all `let` at top, alphabetical order; `before` for actions only; `it` for one-line assertions with explicit values; no instance variables; use existing factories.
  - [ ] Run `bundle exec rspec spec/workers/payment/finalizer_spec.rb` locally and confirm green.
- **Affected files/areas:** `spec/workers/payment/finalizer_spec.rb` (new).
- **Completion criteria:** Spec passes locally. Structure matches project conventions.

### Task 5 — Historical data corrections in Rails console

- **Objective:** Apply the specific historical data corrections listed in PLAN.md, plus any additional records surfaced by Task 1 / Task 2. All corrections are executed interactively in Rails console via `bin/ecs connect`, one block at a time, with the engineer verifying output between blocks.
- **Rationale for this execution model:** No migrations, no rake tasks, no maintenance windows. 4Shark is always live and the data surface of this correction is tiny (a handful of records). Interactive execution lets the engineer validate each step before moving to the next.
- **Actions (checklist):**
  - [ ] Open Rails console in the shared production environment via `bin/ecs connect`.
  - [ ] Confirm the target records before touching anything. Run read-only checks for each record that will be updated, capture the pre-state to `/tmp/` if useful.

    ```ruby
    # Pre-check — Company 97
    UserPayment.find(70858).slice(:id, :payment_id, :user_id, :payment_type_id, :billable_money)
    Payment.find(5451).slice(:id, :money, :status)
    ```

    ```ruby
    # Pre-check — Company 1879
    Company.find(1879).slice(:id, :name, :money_sanitization)
    UserCommission.find(88965496).slice(:id, :commission_id, :billable_money)
    UserCommission.find(88965499).slice(:id, :commission_id, :billable_money)
    Commission.find(54762).slice(:id, :billable_money, :money, :status)
    ```

  - [ ] Correct Company 97 records.

    ```ruby
    # Fix User Payment 70858: -865.12 -> 0
    up = UserPayment.find(70858)
    raise "unexpected value" unless up.billable_money == BigDecimal('-865.12')
    up.update_columns(billable_money: 0)

    # Recalculate Payment 5451 money from current User Payments
    payment = Payment.find(5451)
    new_money = payment.user_payments.sum(:billable_money)
    payment.update_columns(money: new_money)
    puts "payment=#{payment.id} new_money=#{new_money}"
    ```

  - [ ] Correct Company 1879 records.

    ```ruby
    # Flip money_sanitization flag
    company = Company.find(1879)
    raise "unexpected flag" unless company.money_sanitization == true
    company.update_columns(money_sanitization: false)

    # Fix User Commission 88965496: 0 -> -11.54
    uc = UserCommission.find(88965496)
    raise "unexpected value" unless uc.billable_money == 0
    uc.update_columns(billable_money: BigDecimal('-11.54'))

    # Fix User Commission 88965499: 0 -> -11.11
    uc = UserCommission.find(88965499)
    raise "unexpected value" unless uc.billable_money == 0
    uc.update_columns(billable_money: BigDecimal('-11.11'))

    # Recalculate Commission 54762 billable_money from current User Commissions
    commission = Commission.find(54762)
    new_billable = commission.user_commissions.sum(:billable_money)
    commission.update_columns(billable_money: new_billable)
    puts "commission=#{commission.id} new_billable=#{new_billable}"
    ```

  - [ ] Execute any additional corrections identified by Task 1 / Task 2 using the same interactive pattern (pre-check → update → post-check).
  - [ ] After all corrections, run a post-check scan in the same console session.

    ```ruby
    # Post-check — Companies with money_sanitization = true should have no negative User Payments
    Company.where(money_sanitization: true).find_each do |c|
      negatives = UserPayment.joins(:payment).where('payments.company_id = ? AND user_payments.billable_money < 0', c.id).count
      puts "company=#{c.id} negatives=#{negatives}" if negatives > 0
    end
    ```

  - [ ] Repeat the process in the dedicated Atento environment for any corrections surfaced there by Task 1. If Task 1 confirms Atento is clean, only the read-only post-check is needed.
- **Affected files/areas:** production database records in both environments. No application code changes.
- **Completion criteria:** Every affected record holds the expected target value. Pre- and post-state captured for audit. No Company with `money_sanitization = true` has any User Payment with `billable_money < 0`.

### Task 6 — Deploy code change

- **Objective:** Ship the Payment::Finalizer change to both production environments via the standard deployment flow. No maintenance window — 4Shark runs live.
- **Actions (checklist):**
  - [ ] Commit the code and spec changes on `feature/user-payment-negative-value-sanitization` following Angular commit guidelines. One commit for the PR is the standard.
  - [ ] Open a Pull Request against `develop`. PR title matches the commit message. Body optional (feature branch convention).
  - [ ] Follow the review / merge / deploy flow in use by the team. Deploy reaches both production environments through the normal pipeline.
  - [ ] Confirm the Finalizer change is active in production via application logs on the next Payment::Finalizer run.
- **Affected files/areas:** deployment pipeline artifacts. No operational downtime.
- **Completion criteria:** Code is in production in both environments. No incidents observed. Historical corrections from Task 5 are already in place at deploy time (Task 5 precedes Task 6).

### Task 7 — Post-deployment verification

- **Objective:** Validate the target state across both production environments after the code is live.
- **Actions (checklist):**
  - [ ] In shared environment Rails console, confirm:

    ```ruby
    UserPayment.find(70858).billable_money # expect: 0
    Payment.find(5451).money               # expect: sum of its User Payments

    Company.find(1879).money_sanitization  # expect: false
    UserCommission.find(88965496).billable_money # expect: BigDecimal("-11.54")
    UserCommission.find(88965499).billable_money # expect: BigDecimal("-11.11")
    Commission.find(54762).billable_money  # expect: sum of its User Commissions

    # Rule holds after deploy
    Company.where(money_sanitization: true).find_each do |c|
      negatives = UserPayment.joins(:payment).where('payments.company_id = ? AND user_payments.billable_money < 0', c.id).count
      puts "company=#{c.id} negatives=#{negatives}"
    end
    ```

  - [ ] In dedicated Atento environment console, repeat the scan. Expect zero negatives.
  - [ ] Observe the next real Payment::Finalizer run in each environment (check application logs) and confirm no regressions.
  - [ ] Update `CHANGELOG.md` on the `app` project with a user-focused entry. Per project convention, keep it short and in past tense under the appropriate section (`### Fixed`).
- **Affected files/areas:** `CHANGELOG.md` in `app` project; production verification queries.
- **Completion criteria:** All assertions pass in both environments. CHANGELOG updated. Feature folder is ready to move from `plans/active/app/user-payment-negative-value-sanitization/` to `plans/completed/app/user-payment-negative-value-sanitization/` after PR is merged.

---

## 2) Items Requiring User Confirmation

- [ ] Confirm the list of specific records in Task 5 remains as scoped by SPIKE.md, or extend it with any records surfaced by Task 1 / Task 2.
- [ ] Confirm that after Task 2 no new scenario was found that requires adjusting PLAN.md before moving to Task 3.

---

## 3) Pending Items After This Iteration

- [ ] Changelog entry in `CHANGELOG.md` (covered by Task 7).
- [ ] Move feature folder from `active/` to `completed/` after merge.
