# Plan: IncentivePayment Flow Simplification

## Feature Rename

**Old:** IncentiveUserPayment Entity Creation
**New:** IncentivePayment Flow Simplification

This feature has expanded from just creating IncentiveUserPayment to a complete flow redesign that:
1. Creates IncentiveUserPayment entity (DONE)
2. Removes 4Shark approval step from IncentivePayment
3. Simplifies approval model (removes STI)
4. Simplifies state machine (removes `locked` status)
5. Aligns IncentivePayment with Payment pattern

---

## Business Context

### Problem Statement

The current IncentivePayment flow requires two approvals:
1. **Client submits** (`submit`) → `locked` → `review`
2. **4Shark approves** (`approve`) → `review` → `releasing`

This creates an issue: if a client has available budget but needs to finalize a payment at 3 AM, they can't because 4Shark approval is required.

### Decision

Since 4Shark already approves the money in CampaignFund, there's no need for a second approval in IncentivePayment. The client should be able to release payments directly when they have sufficient budget.

**Note:** No production data exists, so we can safely remove unused states and restructure the enum.

---

## Flow Comparison

### Current Flow (Two Approvals, 6 States)

```
initial → processing → locked → review → releasing → final
                          ↑         ↑
                    (client)   (4Shark)
```

### New Flow (Single Approval, 5 States)

```
initial → processing → review → releasing → final
                          ↑
                    (client approves)
```

**Key Changes:**
- `locked` status **removed** (not just unused - completely removed from enum)
- `review` is now where client reviews and approves
- No 4Shark approval step
- Client can release directly when budget is available

---

## Implementation Status

### ✅ MERGED - All Implementation Complete

| Component | PR | Status | Description |
|-----------|-----|--------|-------------|
| Backend - Entity | #4718 | ✅ Merged | IncentiveUserPayment entity creation |
| Backend - Flow | #4721 | ✅ Merged | Flow simplification, state machine, approval changes |
| Frontend | #5840 | ✅ Merged | UI updates, pagination, custom menu, translations |

### 🚀 PENDING - Deploy

| Component | Status | Action |
|-----------|--------|--------|
| Backend | ⏳ Awaiting deploy | Deploy to production FIRST |
| Frontend | PR #5841 (release/1.252.0) | Merge and deploy AFTER backend |

**⚠️ IMPORTANT: Deploy backend before frontend!**

Frontend depends on new backend endpoints:
- `incentiveUserPayments` resolver with `paymentId` argument
- `approver`, `approvedAt`, `value` fields on `IncentivePayment` type
- Updated `approveIncentivePayment` mutation logic

---

## Completed Work Summary

### Phase 1: Database Migration

#### 1.1 Add approval fields to `incentive_payments`

Following the Payment pattern, store approval data directly in the model.

```ruby
# Migration
add_reference :incentive_payments, :approver, foreign_key: { to_table: :users }
add_column :incentive_payments, :approved_from, :inet
add_column :incentive_payments, :approved_at, :datetime
```

#### 1.2 Drop `incentive_payment_approvals` table

```ruby
# Migration
drop_table :incentive_payment_approvals
```

**Affected indexes:**
- `index_incentive_payment_approvals_on_incentive_payment_id`
- `index_incentive_payment_approvals_on_user_id`
- `idx_on_incentive_payment_id_type_034c08dce4` (unique)

**Affected foreign keys:**
- `incentive_payment_approvals` → `incentive_payments`
- `incentive_payment_approvals` → `users`

#### 1.3 Update any existing incentive_payments status (if needed)

```ruby
# Migration (safety measure)
IncentivePayment.where(status: :locked).update_all(status: :review)
```

---

### Phase 2: Backend Model Changes

#### 2.1 `app/models/incentive_payment.rb`

**Add association:**
```ruby
belongs_to :approver, class_name: 'User', inverse_of: :approved_incentive_payments, optional: true
```

**Remove associations:**
```ruby
# REMOVE
has_one :client_approval, class_name: 'ClientIncentivePaymentApproval', dependent: :destroy, inverse_of: :payment
has_one :internal_approval, class_name: 'InternalIncentivePaymentApproval', dependent: :destroy, inverse_of: :payment
```

**Update enum (remove `locked`):**
```ruby
# CURRENT
enumerize :status, in: { initial: 0, processing: 1, locked: 2, review: 3, releasing: 4, final: 5, failed: 6 }, default: :initial, scope: true

# NEW (remove locked, reorder)
enumerize :status, in: { initial: 0, processing: 1, review: 2, releasing: 3, final: 4, failed: 5 }, default: :initial, scope: true
```

**Update state machine:**
```ruby
# CURRENT
state_machine :status, initial: :initial do
  event :start_processing do
    transition initial: :processing
    transition processing: :processing
  end
  event :finish_processing do
    transition processing: :locked
  end
  event :submit do
    transition locked: :review
  end
  event :approve do
    transition review: :releasing
  end
  event :release do
    transition releasing: :final
  end
  event :error do
    transition processing: :failed
    transition releasing: :failed
  end
end

# NEW (simplified)
state_machine :status, initial: :initial do
  event :start_processing do
    transition initial: :processing
    transition processing: :processing
  end
  event :finish_processing do
    transition processing: :review  # Now goes directly to review
  end
  event :approve do
    transition review: :releasing   # Client approves from review
  end
  event :release do
    transition releasing: :final
  end
  event :error do
    transition processing: :failed
    transition releasing: :failed
  end
end
```

**Remove `submit_by`, update `approve_by`:**
```ruby
# REMOVE submit_by entirely

# REMOVE old approve_by

# NEW approve_by (following Payment pattern)
def approve_by(user_id:, from:)
  return false unless review?
  return false unless campaign.available_budget?(value)
  return true if approver_id.present?  # Already approved

  transaction do
    update!(approver_id: user_id, approved_from: from, approved_at: Time.zone.now)
    approve!
  end
rescue ActiveRecord::RecordInvalid
  errors.add(:base, :invalid)
  false
end
```

**Update `pending?`:**
```ruby
# CURRENT
def pending?
  initial? || processing? || locked? || review?
end

# NEW (remove locked)
def pending?
  initial? || processing? || review?
end
```

#### 2.2 `app/models/user.rb`

**Add association:**
```ruby
has_many :approved_incentive_payments, class_name: 'IncentivePayment', foreign_key: :approver_id, dependent: :nullify, inverse_of: :approver
```

**Remove association:**
```ruby
# REMOVE
has_many :incentive_payment_approvals, dependent: :destroy, inverse_of: :user
```

#### 2.3 Delete Approval Models

**Remove files:**
- `app/models/incentive_payment_approval.rb`
- `app/models/client_incentive_payment_approval.rb`
- `app/models/internal_incentive_payment_approval.rb`

---

### Phase 3: Backend Worker Changes

#### 3.1 `app/workers/incentive_payment/finalizer.rb`

The Finalizer currently transitions to `locked`. Now it transitions to `review`.

```ruby
# CURRENT
payment.finish_processing  # processing → locked

# NEW (no code change needed - state machine handles it)
payment.finish_processing  # processing → review
```

**No code change in Finalizer** - the state machine event `finish_processing` now transitions to `review` instead of `locked`.

---

### Phase 4: Backend GraphQL Changes

#### 4.1 `app/graphql_mutations/approve_incentive_payment_graphql_mutation.rb`

**Update to dispatch worker:**

```ruby
class ApproveIncentivePaymentGraphqlMutation < ApplicationMutation
  argument :id, ID, required: true

  policy IncentivePaymentPolicy
  type IncentivePaymentGraphqlType

  def execute
    payment = IncentivePayment.find(id)
    authorize(payment, :approve?)

    if payment.approve_by(user_id: current_user.id, from: remote_ip)
      IncentivePayment::ApprovalProducer.perform_async(payment.id)
    end

    respond_with(payment)
  end
end
```

#### 4.2 Delete `submit_incentive_payment_graphql_mutation.rb`

**Remove file entirely.**

#### 4.3 `app/graphql_types/mutation_type.rb`

**Remove:**
```ruby
field :submit_incentive_payment, mutation: SubmitIncentivePaymentGraphqlMutation
```

**Keep (already exists):**
```ruby
field :approve_incentive_payment, mutation: ApproveIncentivePaymentGraphqlMutation
```

#### 4.4 `app/policies/incentive_payment_policy.rb`

**Update `approve?`:**
```ruby
# CURRENT (requires review status and 4Shark user)
def approve?
  return false unless record.campaign.available_budget?(record.value)
  return false unless user.company.main?  # Only 4Shark
  return false unless record.review?
  user.permission?('incentive_payment_approval')
end

# NEW (client can approve when in review)
def approve?
  return false unless record.campaign.available_budget?(record.value)
  return false if user.company_id != record.company_id  # Same company
  return false unless record.review?
  user.permission?('incentive_payment_approval')
end
```

**Remove `submit?`:**
```ruby
# REMOVE entirely
def submit?
  ...
end
```

**Update `show?`:**
```ruby
def show?
  return false if company.client? && user.company_id != record.company_id
  return false if record.initial? || record.processing? || record.failed?
  return true if role.permission?('incentive_payment_listing')
  record.owner_id == user.id && user.permission?('incentive_payment_listing')
end
```

#### 4.5 `app/graphql_types/incentive_payment_graphql_type.rb`

**Update `actions` method:**
```ruby
def actions
  actions = []
  actions << 'visualization' if incentive_payment_policy.show?
  actions << 'approval' if incentive_payment_policy.approve?
  # Remove 'submit' - no longer exists
  actions
end
```

**Add fields:**
```ruby
field :approver, UserGraphqlType, null: true
field :approved_at, GraphQL::Types::ISO8601DateTime, null: true
field :value, Float, null: true
```

---

### Phase 5: Backend Tests

**Update specs:**
- `spec/models/incentive_payment_spec.rb` - Update state machine tests, remove locked references
- `spec/requests/graphql_mutations/graphql_controller_approve_incentive_payment_spec.rb` - Update to test new flow
- `spec/policies/incentive_payment_policy_spec.rb` - Update approve? tests, remove submit? tests

**Delete specs:**
- `spec/models/incentive_payment_approval_spec.rb`
- `spec/models/client_incentive_payment_approval_spec.rb`
- `spec/models/internal_incentive_payment_approval_spec.rb`
- `spec/requests/graphql_mutations/graphql_controller_submit_incentive_payment_spec.rb`

---

### Phase 6: Update State Machine Diagram

**Run the state machine diagram generator:**

```bash
bin/draw_state_machines
```

This will regenerate the state machine diagrams to reflect the new simplified flow.

---

### Phase 7: Frontend Changes

#### 7.1 `incentive-payment-show.component.ts`

**Remove dead code:**
```typescript
// REMOVE properties
liberating: boolean = false;
paying: boolean = false;

// REMOVE methods
liberatePayment() { ... }
canLiberate(): boolean { ... }
payPayment() { ... }
canPay(): boolean { ... }
```

**Update approve functionality (already exists, just verify):**
```typescript
approving: boolean = false;

approvePayment() {
  this.approving = true;
  const mutation = `approveIncentivePayment(id: ${this.incentivePayment.id}) {
    actions
    status
    approver { name }
    approvedAt
  }`;

  this.apolloService.mutate(mutation).subscribe({
    next: (response: any) => {
      if (response?.data?.approveIncentivePayment) {
        this.incentivePayment = {
          ...this.incentivePayment,
          ...response.data.approveIncentivePayment,
        };
      }
      this.approving = false;
    },
    error: (error) => {
      console.error('Error approving payment:', error);
      this.approving = false;
    },
  });
}

canApprove(): boolean {
  return this.incentivePayment?.actions?.includes('approval');
}
```

**Update query to include new fields:**
```typescript
private incentivePaymentShowQuery(incentivePaymentId = '') {
  return `query {
    incentivePayments (id: ${incentivePaymentId}) {
      nodes {
        id
        status
        value
        approvedAt
        approver {
          id
          name
        }
        company {
          id
          name
        }
        campaign {
          id
          name
          availableBudget
        }
        owner {
          id
          name
        }
        period {
          id
          name
        }
        actions
        userPayments {
          id
          value
          user {
            name
            primaryIdentifierValue
          }
        }
      }
    }
  }`;
}
```

#### 7.2 `incentive-payment-show.component.html`

**Remove dead code:**
```html
<!-- REMOVE liberate button -->
<button class="menu-button" *ngIf="canLiberate()" ...>

<!-- REMOVE pay button -->
<button class="menu-button mg-r-10" *ngIf="canPay()" ...>
```

**Keep approve button (already exists):**
```html
<button class="menu-button mg-r-10" *ngIf="canApprove()" (click)="approvePayment()" [disabled]="approving">
  <span class="material-symbols-outlined" *ngIf="!approving">check_circle</span>
  <span class="loading-spinner" *ngIf="approving"></span>
  <span>{{ 'incentive_payment.approve' | translate }}</span>
</button>
```

**Add value display:**
```html
<div class="infos" *ngIf="incentivePayment?.value">
  <span class="info-type">{{ 'incentive_payment.value' | translate }}:</span>
  <span class="info-value">{{ incentivePayment?.value | currency }}</span>
</div>
```

**Add approver display (like Payment):**
```html
<div class="infos" *ngIf="incentivePayment?.approver">
  <span class="info-type">{{ 'incentive_payment.approver' | translate }}:</span>
  <span class="info-value">{{ incentivePayment?.approver?.name }}</span>
</div>
<div class="infos" *ngIf="incentivePayment?.approvedAt">
  <span class="info-type">{{ 'incentive_payment.approved_at' | translate }}:</span>
  <span class="info-value">{{ incentivePayment?.approvedAt | date: 'shortDate' }}</span>
</div>
```

**Add userPayments table (like Payment):**
```html
<ng-container *ngIf="incentivePayment?.userPayments?.length > 0">
  <div class="list">
    <h4 class="middle-title">{{ 'incentive_user_payment.other' | translate }}</h4>
    <div class="list-header">
      <span class="column-l">{{ 'user.name' | translate }}</span>
      <span class="column-l">{{ 'user.externalId' | translate }}</span>
      <span class="column-l">{{ 'incentive_user_payment.value' | translate }}</span>
    </div>
    <div *ngFor="let userPayment of incentivePayment.userPayments" class="list-item">
      <span class="column-m">{{ userPayment?.user?.name }}</span>
      <span class="column-m">{{ userPayment?.user?.primaryIdentifierValue }}</span>
      <span class="column-m">{{ userPayment?.value | currency }}</span>
    </div>
  </div>
</ng-container>
```

#### 7.3 `incentive-payment.component.html`

**Remove `locked` from status filter:**
```html
<!-- REMOVE -->
<option value="locked">{{ 'incentive_payment.status.options.locked' | translate }}</option>
```

**Keep `review` (now used by client):**
```html
<option value="review">{{ 'incentive_payment.status.options.review' | translate }}</option>
```

#### 7.4 `incentive-payment.model.ts`

**Add new fields:**
```typescript
interface IncentivePaymentAttributes {
  // ... existing fields
  approvedAt?: string;
  approver?: User;
  value?: number;
}

export class IncentivePayment implements IncentivePaymentAttributes {
  // ... existing fields
  approvedAt?: string;
  approver?: User;
  value?: number;

  constructor(attr: IncentivePaymentAttributes) {
    // ... existing assignments
    this.approvedAt = attr.approvedAt;
    this.approver = attr.approver;
    this.value = attr.value;
  }
}
```

#### 7.5 Translations

**Update `pt-BR.json`, `en.json`, `es.json`:**

```json
"incentive_payment": {
  "status": {
    "options": {
      "initial": "Inicial",
      "processing": "Processando",
      "review": "Aguardando Aprovação",
      "releasing": "Liberando",
      "final": "Finalizado",
      "failed": "Erro"
    }
  },
  "value": "Valor Total",
  "approver": "Aprovado por",
  "approved_at": "Aprovado em"
}
```

**Note:** Remove `locked` translation, update `review` translation to "Aguardando Aprovação".

---

## Files Summary

### Backend - Delete

| File | Reason |
|------|--------|
| `app/models/incentive_payment_approval.rb` | STI base class no longer needed |
| `app/models/client_incentive_payment_approval.rb` | STI subclass no longer needed |
| `app/models/internal_incentive_payment_approval.rb` | STI subclass no longer needed |
| `app/graphql_mutations/submit_incentive_payment_graphql_mutation.rb` | Replaced by approve |
| `spec/models/incentive_payment_approval_spec.rb` | Model deleted |
| `spec/models/client_incentive_payment_approval_spec.rb` | Model deleted |
| `spec/models/internal_incentive_payment_approval_spec.rb` | Model deleted |
| `spec/requests/graphql_mutations/graphql_controller_submit_incentive_payment_spec.rb` | Mutation deleted |

### Backend - Modify

| File | Changes |
|------|---------|
| `app/models/incentive_payment.rb` | Remove `locked` from enum, update state machine, add approver fields, remove approval associations, replace submit_by/approve_by |
| `app/models/user.rb` | Add approved_incentive_payments, remove incentive_payment_approvals |
| `app/graphql_mutations/approve_incentive_payment_graphql_mutation.rb` | Update to call approve_by and dispatch worker |
| `app/graphql_types/mutation_type.rb` | Remove submit_incentive_payment |
| `app/graphql_types/incentive_payment_graphql_type.rb` | Add approver, approved_at, value fields; update actions |
| `app/policies/incentive_payment_policy.rb` | Update approve?, remove submit?, update show? |
| `spec/models/incentive_payment_spec.rb` | Update state machine tests |
| `spec/requests/graphql_mutations/graphql_controller_approve_incentive_payment_spec.rb` | Update tests |
| `spec/policies/incentive_payment_policy_spec.rb` | Update tests |

### Backend - Create

| File | Description |
|------|-------------|
| Migration: add approver fields to incentive_payments | Add approver_id, approved_from, approved_at |
| Migration: drop incentive_payment_approvals | Drop table and indexes |
| Migration: migrate locked to review | Update any existing records |

### Frontend - Modify

| File | Changes |
|------|---------|
| `incentive-payment-show.component.ts` | Remove dead code (liberate, pay), update query |
| `incentive-payment-show.component.html` | Remove dead buttons, add value/approver display, add userPayments table |
| `incentive-payment.component.html` | Remove locked from status filter |
| `incentive-payment.model.ts` | Add approvedAt, approver, value fields |
| `translations/*.json` | Remove locked, update review text, add new keys |

---

## State Machine Comparison

### Before (6 states)

```
┌─────────┐     ┌────────────┐     ┌────────┐     ┌────────┐     ┌───────────┐     ┌───────┐
│ initial │────▶│ processing │────▶│ locked │────▶│ review │────▶│ releasing │────▶│ final │
└─────────┘     └────────────┘     └────────┘     └────────┘     └───────────┘     └───────┘
                      │                                                │
                      │                                                │
                      ▼                                                ▼
                 ┌────────┐                                       ┌────────┐
                 │ failed │◀──────────────────────────────────────│ failed │
                 └────────┘                                       └────────┘
```

### After (5 states)

```
┌─────────┐     ┌────────────┐     ┌────────┐     ┌───────────┐     ┌───────┐
│ initial │────▶│ processing │────▶│ review │────▶│ releasing │────▶│ final │
└─────────┘     └────────────┘     └────────┘     └───────────┘     └───────┘
                      │                                 │
                      │                                 │
                      ▼                                 ▼
                 ┌────────┐                        ┌────────┐
                 │ failed │◀───────────────────────│ failed │
                 └────────┘                        └────────┘
```

**Run `bin/draw_state_machines` after implementation to update the official diagrams.**

---

## Potential Gaps and Risks

### 1. Permission Key

**Current:** `incentive_payment_approval` exists but was for 4Shark users.

**Risk:** Need to verify if clients have this permission or if it needs to be granted.

**Mitigation:** Check Action table and Permission assignments. May need to grant permission to client users.

### 2. Enum Value Change

**Current:** `locked: 2, review: 3, releasing: 4, final: 5, failed: 6`

**New:** `review: 2, releasing: 3, final: 4, failed: 5`

**Risk:** Enum values change in database.

**Mitigation:** No production data. Migration will handle any existing records.

### 3. Workers Don't Check Status

**Current:** ApprovalProducer doesn't verify payment status before processing.

**Analysis:** This is fine because:
- `approve_by` verifies `review?` before transitioning
- `release_payment` verifies `releasing?` before completing
- Race conditions are prevented by Lock mechanism

### 4. Frontend Error Handling

**Current:** Error handling just logs to console.

**Risk:** User doesn't see error messages.

**Recommendation:** Add toast/snackbar for errors (can be done later).

### 5. Translation Completeness

**Risk:** Missing translations for new fields.

**Mitigation:** Check all 3 locale files (pt-BR, en, es).

---

## Execution Order

### PR 1: Backend Flow Simplification

1. Migration: Add approver fields to incentive_payments
2. Migration: Drop incentive_payment_approvals table
3. Migration: Migrate any locked records to review
4. Delete approval model files
5. Update IncentivePayment model (enum, state machine, approve_by)
6. Update User model
7. Delete submit mutation, update approve mutation
8. Update GraphQL type and policy
9. Update/delete specs
10. Run tests
11. **Run `bin/draw_state_machines` to update diagrams**

### PR 2: Frontend Updates

1. Update incentive-payment-show component (ts + html)
2. Update incentive-payment list component
3. Update model
4. Update translations (remove locked, update review)
5. Remove dead code
6. Test manually

---

## Verification Checklist

### Backend

```ruby
# Rails console
payment = IncentivePayment.find_by(status: :review)
payment.approve_by(user_id: User.first.id, from: '127.0.0.1')
payment.reload.status # Should be 'releasing'
payment.approver # Should be User.first
payment.approved_at # Should be set
```

```graphql
# GraphQL
mutation {
  approveIncentivePayment(id: 1) {
    id
    status
    approver { name }
    approvedAt
  }
}
```

### Frontend

1. Access payment during `processing` → should show loading/message
2. Access payment after `review` → should show details + approve button (for client user)
3. Click approve → payment should transition to `releasing` then `final`
4. After approval → should show approver name and date
5. Should see userPayments table with values
6. Status filter should NOT show "locked" option

---

## Summary

| Aspect | Before | After |
|--------|--------|-------|
| Approvals | 2 (client submit + 4Shark approve) | 1 (client approve) |
| Models | 4 (Payment + 3 Approval models) | 1 (Payment only) |
| States | 6 (initial, processing, locked, review, releasing, final, failed) | 5 (initial, processing, review, releasing, final, failed) |
| Status flow | initial → processing → locked → review → releasing → final | initial → processing → review → releasing → final |
| 3 AM releases | ❌ Blocked (needs 4Shark) | ✅ Client can release |
| Consistency with Payment | ❌ Different pattern | ✅ Same pattern |
