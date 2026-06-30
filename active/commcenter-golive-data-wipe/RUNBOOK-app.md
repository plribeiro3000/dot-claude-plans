# RUNBOOK — Commcenter app wipe (MANUAL, one resource at a time)

`bin/ecs run app-shared-001`. You drive each step by hand: inflate the queue, fire ONE
producer (enqueues up to 10k consumers), watch the `cleansing` queue drain, check the
count, fire again. **Stop when the count hits 0.** Nothing here loops or auto-advances.

## Why this is safe

- Every `Company::Cleansing::*Producer` is **company-scoped** (`company.<resource>.limit(10_000)`)
  → a misfire only ever touches **company 2077**, never other tenants on shared-001.
- **Inflating the queue** (`increment_queue` >> executions) makes `done?` never true →
  the *consumer* never auto-chains to the next producer.
- **You only fire while `count > 0`** → the *producer* never runs empty, so its `else`
  branch (chain to the next producer) never fires. Both auto-advance paths are off; you
  control every step.

## ⚠️ The one rule

**Before each `perform_async`, confirm the resource count > 0. When it reaches 0, STOP —
do NOT fire that producer again.** Firing on an empty resource chains to the next one.

---

## Setup (paste once at the start of the session)

```ruby
require 'sidekiq/api'
company = Company.find(2077)
```

## Watch helper (paste anytime to see progress)

```ruby
# [pending cleansing jobs, busy cleansing workers]
[Sidekiq::Queue.new('cleansing').size, Sidekiq::Workers.new.count { |_p, _t, w| w['queue'] == 'cleansing' }]
```

When both are `0`, the batch you fired has finished — then check the resource count below.

---

## Per-resource steps (dependency order)

Already empty — **skip** (do not fire, would chain): `user_histories`, `payments`,
`commission_payments`, `statements`.

Each block: (1) confirm count, (2) inflate, (3) fire, (4) watch drain, (5) re-check.
Repeat (3)-(5) until the count is 0, then move on.

### 1) Commission — "premiações" (~21)

```ruby
company.commissions.count                                   # confirm > 0 before firing
company.computation.increment_queue(by: 1_000_000_000)      # queue >> executions
Company::Cleansing::CommissionProducer.perform_async(2077)  # enqueues up to 10k consumers
```
Watch drain (watch helper), then `company.commissions.count`. Repeat while > 0; stop at 0.
> Each CommissionConsumer destroys its `user_commissions` inline (cascade).

### 2) PartialCommission — "parciais" (~803) — IN PROGRESS (you've done ~100)

```ruby
company.partial_commissions.count
company.computation.increment_queue(by: 1_000_000_000)
Company::Cleansing::PartialCommissionProducer.perform_async(2077)
```
Repeat while `company.partial_commissions.count > 0`; stop at 0.

### Checkpoint — user_commissions should drain via 1 & 2

```ruby
UserCommission.where(user_id: company.users.select(:id)).count   # expect ~0 after 1 & 2
```
If > 0 after both are done, there are orphan user_commissions (no commission/partial parent) —
tell me, I'll handle that residue separately. Do NOT proceed to deals until this is understood.

### 3) DealDocumentEnrollment — blocker for deals (~79)

```ruby
DealDocumentEnrollment.where(deal_id: company.deals.select(:id)).count    # confirm > 0
company.computation.increment_queue(by: 1_000_000_000)
Company::Cleansing::DealDocumentEnrollmentProducer.perform_async(2077)
```
Repeat until the count above is 0. **Must reach 0 before step 4** (restrict_with_exception on Deal).

### 4) Deal — "deals" (~16,378 → ~2 batches of 10k)

```ruby
company.deals.count                                          # confirm > 0
company.computation.increment_queue(by: 1_000_000_000)
Company::Cleansing::DealProducer.perform_async(2077)         # one batch of up to 10k
```
Watch drain, re-check `company.deals.count`, fire again for the next batch. Stop at 0.

### 5) Client — "clientes" (~13,386 → ~2 batches)

```ruby
company.clients.count
company.computation.increment_queue(by: 1_000_000_000)
Company::Cleansing::ClientProducer.perform_async(2077)
```
Repeat until 0. (Incentives are group-bound, client_id nil — clients do NOT cascade incentives.)

### 6) Product — "produtos" (~367)

```ruby
company.products.count
company.computation.increment_queue(by: 1_000_000_000)
Company::Cleansing::ProductProducer.perform_async(2077)
```
Repeat until 0.

### 7) IndicatorDocumentEnrollment — blocker for indicators (~27)

```ruby
IndicatorDocumentEnrollment.where(modifier_id: company.indicators.select(:id)).count   # confirm > 0
company.computation.increment_queue(by: 1_000_000_000)
Company::Cleansing::IndicatorDocumentEnrollmentProducer.perform_async(2077)
```
Repeat until 0. **Must reach 0 before step 8.**

### 8) Indicator — "indicadores" (~3,981)

```ruby
company.indicators.count
company.computation.increment_queue(by: 1_000_000_000)
Company::Cleansing::IndicatorProducer.perform_async(2077)
```
Repeat until 0.

### 9) PlanStatement — "declaração de regra" (~1,321)

```ruby
company.plan_statements.count
company.computation.increment_queue(by: 1_000_000_000)
Company::Cleansing::PlanStatementProducer.perform_async(2077)
```
Repeat until 0.

### 10) Plan — "planos" (~25)

```ruby
company.plans.count
company.computation.increment_queue(by: 1_000_000_000)
Company::Cleansing::PlanProducer.perform_async(2077)
```
Repeat until 0. (Cascades campaigns, approvals, plan_variables, incentivations, goal_plans.)

### 11) Goal — "metas" (~131)

```ruby
company.goals.count
company.computation.increment_queue(by: 1_000_000_000)
Company::Cleansing::GoalProducer.perform_async(2077)
```
Repeat until 0.

---

## Teardown (after everything is 0)

```ruby
company.computation.reset_queue
company.computation.reset_executions
```
Then re-run `discovery-app.rb` for verification (all DELETE counts `@0`, all `KEEP_*` unchanged).
Then scale the `cleansing` service AND the `shared-001-worker-cleansing-asg` back to 0.
```
