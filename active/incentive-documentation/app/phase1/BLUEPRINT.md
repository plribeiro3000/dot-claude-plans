# Phase 1 Issues

> Issues identified for Phase 1 that need to be addressed before starting Phase 2.
> Issues that belong to Phase 2 scope are in PHASE2-ISSUES.md.

**Date:** 2026-01-16
**Status:** IN PROGRESS

---

## Progress

| # | Issue | Status | PR |
|---|-------|--------|-----|
| 1 | Redis Lock TTL | PENDING | - |
| 2 | Frontend Budget Validation | PENDING | - |
| 3 | GraphQL Budget Fields | PENDING | - |
| 4 | Plan-Campaign Immutability | PENDING | - |
| 5 | Credit Created as Final | ✅ DONE | #4792 (replaces #4734) |
| 6 | Worker Flow Review | ✅ DONE | #4792 (replaces #4734) |

---

## Decisions Made

| Decision | Answer | Impact |
|----------|--------|--------|
| Who creates campaigns? | **4Shark (internal)** | No Campaign CRUD UI needed for clients |
| Payment approval flow? | **Keep async** | Need to create credits for each account + increment budget columns |
| Credit + budget in same process? | **Yes, same async process** | Current architecture is correct |
| When to call release_payment? | **Synchronously during approval** | Budget validated BEFORE credits created |
| Worker namespace convention? | **Namespace of model being processed** | `IncentiveCredit::Producer`, not `IncentivePayment::Credit::Producer` |
| When to accumulate user payment value? | **During generation phase** | Consumer accumulates, Finalizer sums, Credits don't touch it |

---

## Business Rule Change

### Credit State: No More Pending

**Old Behavior:**
- Credit created as `pending` when payment is generated
- Credit transitions to `final` when payment is approved
- Employee sees pending credits before approval

**New Behavior:**
- Credit created directly as `final` when payment is approved
- No pending state for credits
- Employee only sees balance after approval

**Implementation:**
- Keep state machine in model (shared table with Debit)
- Modify credit creation to set `status: :final` directly
- Remove/skip pending → final transition logic in workers

---

## Issues Required

### Issue #1: Redis Lock TTL

**Priority:** 🔴 CRITICAL

**Problem:** Lock.acquire() can create locks without TTL. If worker dies, lock stays forever, blocking all future operations.

**Solution:** Add default TTL to all lock acquisitions.

**Files:**
- `app/models/lock.rb`

**Change:**
```ruby
# Before
def self.acquire(lock_key, lock_ttl = nil)
  connection.call('set', "lock:#{lock_key}", 'true', nx: true)
end

# After
def self.acquire(lock_key, lock_ttl = 1800) # 30 minutes default
  if lock_ttl
    connection.call('set', "lock:#{lock_key}", 'true', nx: true, ex: lock_ttl)
  else
    connection.call('set', "lock:#{lock_key}", 'true', nx: true)
  end
end
```

**Note:** 30 minutes is conservative. Adjust based on longest expected operation.

---

### Issue #2: Frontend Budget Validation

**Priority:** 🔴 CRITICAL

**Problem:** Frontend allows payment approval without checking available budget. Button never disabled for insufficient budget.

**Solution:**
1. Fetch budget fields in GraphQL query
2. Calculate available budget
3. Disable "Approve" button if insufficient
4. Show available budget to user

**Files:**
- `app-webclient/src/app/incentive-payment/incentive-payment.service.ts` (query)
- `app-webclient/src/app/incentive-payment/show/incentive-payment-show.component.ts` (logic)
- `app-webclient/src/app/incentive-payment/show/incentive-payment-show.component.html` (template)

**Query Change:**
```typescript
// Add to campaign fields in query
campaign {
  id
  name
  budget
  releasedBudget
  consumedBudget
}
```

**Component Logic:**
```typescript
get availableBudget(): number {
  return this.campaign.budget - this.campaign.releasedBudget;
}

get canApprove(): boolean {
  return this.payment.value <= this.availableBudget;
}
```

**Template:**
```html
<!-- Show available budget -->
<p>Available Budget: {{ availableBudget | currency }}</p>

<!-- Disable button if insufficient -->
<button [disabled]="!canApprove" (click)="approvePayment()">
  Approve
</button>

<!-- Show warning if insufficient -->
<p *ngIf="!canApprove" class="error">
  Insufficient budget. Add funds to campaign first.
</p>
```

---

### Issue #3: GraphQL Budget Fields

**Priority:** 🔴 CRITICAL (blocks Issue #2)

**Problem:** GraphQL queries for Incentive Payment don't include campaign budget fields.

**Solution:** Add budget fields to IncentiveCampaignGraphqlType and ensure they're fetched in payment queries.

**Files:**
- `app/graphql_types/incentive_campaign_graphql_type.rb` (if fields not exposed)
- `app-webclient/src/app/incentive-payment/incentive-payment.service.ts` (query)

**Verify fields exist:**
```ruby
# IncentiveCampaignGraphqlType should have:
field :budget, Float, null: false
field :released_budget, Float, null: false
field :consumed_budget, Float, null: false
```

---

### Issue #4: Plan-Campaign Immutability

**Priority:** 🟡 HIGH

**Problem:** Frontend allows editing `incentiveCampaignId` even after Plan is approved. Business rule: once approved, cannot change.

**Solution:**
1. Frontend: Disable field when plan is not draft
2. Backend: Validate in model or mutation

**Files:**
- `app-webclient/src/app/plan/update/plan-update.component.html`
- `app/models/plan.rb` or `app/graphql_mutations/update_plan_graphql_mutation.rb`

**Frontend Change:**
```html
<ng-autocomplete
  [disabled]="plan.status !== 'draft'"
  ...
/>
```

**Backend Change:**
```ruby
# In Plan model
validate :campaign_immutable_after_approval

def campaign_immutable_after_approval
  if incentive_campaign_id_changed? && !draft?
    errors.add(:incentive_campaign_id, "cannot be changed after plan approval")
  end
end
```

---

### Issue #5: Credit Created as Final

**Priority:** 🔴 CRITICAL (business rule change)
**Status:** ✅ IMPLEMENTED (PR #4734)

**Problem:** Current code creates credits as `pending` then transitions to `final`. New rule: create directly as `final`.

**Solution Implemented:**

Credits are now created by `IncentiveCredit::Consumer` with `status: :final` directly:

```ruby
# app/workers/incentive_credit/consumer.rb
campaign_account.incentive_transactions.create!(
  type: 'IncentiveCredit',
  company_id: campaign_account.company_id,
  incentive_user_payment_id: user_payment.id,
  user_commission_id: user_commission.id,
  value: user_commission.billable_money,
  status: :final  # Direct to final
)
campaign_account.increment!(:balance, user_commission.billable_money)
```

**Files Changed:**
- Created `app/workers/incentive_credit/producer.rb`
- Created `app/workers/incentive_credit/consumer.rb`
- Removed `app/workers/incentive_payment/approval_producer.rb`
- Removed `app/workers/incentive_payment/approval_consumer.rb`
- Removed `app/workers/incentive_payment/approval_finalizer.rb`

**Note:** State machine kept in model (IncentiveTransaction uses STI with IncentiveDebit which needs states).

---

### Issue #6: Worker Flow Review

**Priority:** 🟡 HIGH
**Status:** ✅ IMPLEMENTED (PR #4734)

**Problem:** With credits created as final (not pending), the worker flow needs review.

**Bug Discovered During Implementation:**

O código original chamava `release_payment` (validação de orçamento) no `ApprovalFinalizer`, DEPOIS de criar os créditos. Isso era um bug - criava créditos sem validar se havia orçamento disponível.

**Solution:** `release_payment` agora é chamado SINCRONAMENTE dentro de `approve_by`, na mesma transaction da aprovação:

```ruby
# app/models/incentive_payment.rb
def approve_by(user_id:, from:)
  return false unless review?
  return true if approver_id.present?

  transaction do
    update!(approver_id: user_id, approved_from: from, approved_at: Time.zone.now)
    approve!
    raise ActiveRecord::RecordNotSaved.new('Failed to release payment', self) unless campaign.release_payment(id)
    true
  end
rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved
  errors.add(:base, :invalid)
  false
end
```

**New Flow Implemented:**

```
PHASE 1 - GENERATION (payment: processing)
├── IncentivePayment::Producer
├── IncentivePayment::Consumer (creates IncentiveUserPayment, accumulates value)
└── IncentivePayment::Finalizer (sums values, transitions to review)

PHASE 2 - APPROVAL (payment: review → final) [SYNCHRONOUS]
├── approve_by called
├── release_payment validates budget
└── If OK: transitions to final

PHASE 3 - CREDIT CREATION (payment: final)
├── IncentiveCredit::Producer
└── IncentiveCredit::Consumer (creates credit as final, updates account balance)
```

**Files Changed:**
- Modified `app/models/incentive_payment.rb` - approve_by calls release_payment sync
- Modified `app/workers/incentive_payment/consumer.rb` - creates IncentiveUserPayment, calls update_counters
- Modified `app/workers/incentive_payment/finalizer.rb` - sums user_payments.value
- Modified `app/graphql_mutations/approve_incentive_payment_graphql_mutation.rb` - calls IncentiveCredit::Producer after approval

**Pattern Followed:** `raise ActiveRecord::RecordNotSaved.new(message, record)` instead of `raise ActiveRecord::Rollback` (project pattern from campaign_fund.rb).

---

## Issues NOT Needed for Phase 1

These have been moved to **PHASE2-ISSUES.md**:

| Issue | Reason |
|-------|--------|
| consumed_budget increment | Phase 2 scope (voucher redemption) |
| Incentive Catalogation CRUD | Internal operation, no UI needed |
| Incentive Item CRUD | Phase 2 scope |
| Employee Campaign Account view | Phase 2 scope |
| Compensation mechanisms | Documented scripts sufficient for now |

---

## Implementation Order

Recommended sequence:

```
1. Issue #3: GraphQL Budget Fields
   └── Enables frontend validation

2. Issue #2: Frontend Budget Validation
   └── User sees budget, cannot approve without funds

3. Issue #1: Redis Lock TTL
   └── Prevents deadlocks

4. Issue #5: Credit Created as Final
   └── Business rule change

5. Issue #6: Worker Flow Review
   └── Simplify based on #5

6. Issue #4: Plan-Campaign Immutability
   └── Frontend + backend validation
```

---

## Testing Checklist

After issues, verify:

- [ ] Lock with TTL expires correctly (test with short TTL)
- [ ] Frontend shows available budget on payment approval screen
- [ ] Frontend disables "Approve" when budget insufficient
- [ ] Backend rejects approval when budget insufficient
- [x] Credits are created as final (no pending state) - PR #4734
- [x] Account balance incremented correctly - PR #4734
- [x] released_budget incremented correctly (sync during approval) - PR #4734
- [ ] Plan cannot change campaign after approval (frontend disabled)
- [ ] Plan cannot change campaign after approval (backend validates)

---

## Files Summary

### Pending Changes

| File | Issues |
|------|-------------|
| `app/models/lock.rb` | #1 - Add TTL |
| `app/models/plan.rb` | #4 - Immutability validation |
| `app/graphql_types/incentive_campaign_graphql_type.rb` | #3 - Verify budget fields |
| `app-webclient/.../incentive-payment.service.ts` | #2, #3 - Query changes |
| `app-webclient/.../incentive-payment-show.component.ts` | #2 - Logic |
| `app-webclient/.../incentive-payment-show.component.html` | #2 - Template |
| `app-webclient/.../plan-update.component.html` | #4 - Disable field |

### Completed Changes (PR #4734)

| File | Change |
|------|--------|
| `app/models/incentive_payment.rb` | #5, #6 - approve_by calls release_payment sync |
| `app/workers/incentive_payment/consumer.rb` | #5, #6 - Creates IncentiveUserPayment, accumulates value |
| `app/workers/incentive_payment/finalizer.rb` | #5, #6 - Sums user_payments.value |
| `app/workers/incentive_credit/producer.rb` | #5, #6 - NEW: Dispatches credit creation |
| `app/workers/incentive_credit/consumer.rb` | #5, #6 - NEW: Creates credit as final |
| `app/graphql_mutations/approve_incentive_payment_graphql_mutation.rb` | #5, #6 - Calls IncentiveCredit::Producer |
| `app/workers/incentive_payment/approval_*.rb` | #5, #6 - REMOVED (3 files) |

---

**Status:** IN PROGRESS

**Next Step:** Wait for PR #4734 review, then continue with issues #1, #2, #3, #4.
