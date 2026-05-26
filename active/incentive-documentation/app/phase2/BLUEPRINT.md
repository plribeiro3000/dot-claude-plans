# Phase 2 Issues - Known Items to Address

> Issues identified during Phase 1 analysis that belong to Phase 2 scope.
> Review this document when starting Phase 2 implementation.

**Date:** 2026-01-16

---

## Purpose

During Phase 1 analysis, some issues were identified that are not Phase 1 scope but need to be addressed in Phase 2. This document ensures they are not forgotten.

---

## Issue #1: `consumed_budget` Never Incremented

**Source:** ANALYSIS.md Issue #1

**Description:**

The `consumed_budget` field exists in `IncentiveCampaign` with validation (`consumed_budget <= released_budget`), but no code ever increments this value. It will always be 0.

**Why Phase 2:**

`consumed_budget` tracks money that **left 4Shark to the partner** when employees redeem vouchers. This only happens in Phase 2 (voucher redemption).

In Phase 1, money flows:
- Budget (deposited) → Released Budget (approved to employees)

In Phase 2, money flows:
- Released Budget → **Consumed Budget** (employee redeems voucher)

**When to Increment:**

Based on KNOWLEDGE-PHASE2.md and user decisions:
- Increment `consumed_budget` when **voucher is delivered** (partner status = 3)
- NOT when order is created
- NOT when balance is debited
- Only when the actual transaction with partner is complete

**Implementation Location:**

In the `StatusCheckConsumer` worker, when partner returns status = delivered:

```ruby
# Pseudocode
if partner_status == :delivered
  order_item.deliver!
  order_item.debit_transaction.approve!
  campaign.increment!(:consumed_budget, order_item.value)
  send_voucher_email
end
```

**Validation:**

The existing validation `consumed_budget <= released_budget` will work correctly once this is implemented.

---

## Issue #2: Incentive Catalogation CRUD

**Source:** ANALYSIS.md Issue #10

**Description:**

The `IncentiveCatalogation` model exists, but there's no service or UI to manage which items are available in each campaign.

**Why Phase 2:**

Catalogation defines which Incentive Items are available for employees to redeem. Without redemption functionality (Phase 2), there's no need to manage catalogation.

**Current State:**

- Model exists: `IncentiveCatalogation`
- Frontend service exists but is empty
- Management is done via Rails console or direct DB operations

**Phase 2 Requirement:**

For employees to browse and redeem items, each campaign must have catalogation records linking to available items.

**Options for Phase 2:**

| Option | Description | Recommendation |
|--------|-------------|----------------|
| A. Admin panel | Internal tool for 4Shark team | ✅ Recommended |
| B. Rails console | Continue manual management | ⚠️ Acceptable for small scale |
| C. Client UI | Allow clients to manage | ❌ Not needed per business decision |

**Note:** Since 4Shark internally manages campaigns (not client self-service), catalogation can also be internal-only.

---

## Issue #3: Incentive Item CRUD

**Source:** ANALYSIS.md Features Table

**Description:**

Incentive Items (products from partner catalog) exist as models but have no management UI.

**Why Phase 2:**

Items are the products employees can redeem. Management is needed before redemption goes live.

**Current State:**

- Model exists: `IncentiveItem`
- No admin UI

**Phase 2 Requirement:**

Need a way to:
1. Add new items from partner catalog
2. Set 4Shark internal SKU
3. Associate with partner

**Recommendation:** Admin panel or rake task for bulk import from partner.

---

## Issue #4: Employee Campaign Account View

**Source:** ANALYSIS.md Features Table

**Description:**

Employees need to see their balance in each campaign account.

**Why Phase 2:**

While balance exists after Phase 1 payment approval, there's no point showing it until employees can use it (redeem vouchers).

**Phase 2 Requirement:**

Employee portal showing:
- List of campaigns where they have balance > 0
- Balance per campaign
- Transaction history (credits and debits)
- Available items for redemption

---

## Issue #5: Compensation Mechanisms

**Source:** ANALYSIS.md Issue #11

**Description:**

No way to reverse operations if something goes wrong:
- Reverse an approved payment
- Correct a credit with wrong value
- Remove orphan transactions
- Reopen a finalized payment

**Why Partially Phase 2:**

Some compensation is needed for Phase 2 specifically:
- **Refund failed orders**: When partner fails/cancels, need to credit balance back
- **Manual voucher issues**: If voucher has problem, may need to refund

**Phase 1 Compensation:**

For Phase 1, documented scripts/rake tasks are sufficient (per PHASE1-ISSUES.md decision).

**Phase 2 Compensation:**

Need defined process for:
1. Partner cancels order → Credit balance back
2. Voucher delivery fails → Credit balance back
3. Employee disputes → Manual investigation + potential credit

**Current Design Decision:**

Refunds are **manual** (script creates Incentive Credit), not automatic. This is intentional to maintain human oversight on financial operations.

---

## Issue #6: Order State Management

**Source:** ANALYSIS.md analysis

**Description:**

The PRs from the other engineer implemented order state machines, but with issues:
- Balance deducted before partner confirms
- No rollback on partner failure
- `consumed_budget` never incremented

**Phase 2 Scope:**

Entire order flow needs correct implementation:

```
Correct Flow:
1. CREATE ORDER
   - Validate balance >= item value
   - Create Order (pending)
   - Debit balance immediately (sync with partner call)
   - Call partner API

2. PARTNER CONFIRMS
   - Order → processing
   - Wait for delivery status

3. DELIVERY
   - Order → completed
   - Debit → final
   - Increment consumed_budget
   - Send voucher email

4. FAILURE
   - Order → failed
   - Manual refund process (new Credit)
```

---

## Issue #7: Partner Integration Reliability

**Source:** New from Phase 2 planning

**Description:**

What happens when partner API is unavailable?

**Scenarios:**
- Partner API timeout on order creation
- Partner API down during polling
- Partner returns unexpected response

**To Define in Phase 2:**
- Retry policy
- Error notification
- Graceful degradation (show "temporarily unavailable"?)

---

## Checklist for Phase 2 Start

Before starting Phase 2 implementation, review:

- [ ] Issue #1: Implement `consumed_budget` increment
- [ ] Issue #2: Decide on Catalogation management approach
- [ ] Issue #3: Decide on Item management approach
- [ ] Issue #4: Design Employee portal UI
- [ ] Issue #5: Define compensation/refund process
- [ ] Issue #6: Implement correct order state flow
- [ ] Issue #7: Define partner error handling

---

**Status:** REFERENCE DOCUMENT

**Purpose:** Ensure Phase 2 addresses these known issues from Phase 1 analysis.
