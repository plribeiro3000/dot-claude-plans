# DOMAIN - Incentive System (Phase 1)

> Reference: KNOWLEDGE.md, PROCESS.md

## Overview

This document describes the domain entities and their relationships for Phase 1 of the Incentive System. It focuses on what was discussed and implemented, not on technical design patterns.

## Entities

### Incentive Campaign

Represents a campaign created by the client to compensate employees through the incentive system.

**Key Attributes:**
- Name and description
- Period (when the campaign is active)
- Budget (cumulative counter - only increments)
- Released Budget (cumulative counter - only increments)
- Consumed Budget (cumulative counter - only increments)

**Key Rules:**
- Released Budget ≤ Budget (always)
- Consumed Budget ≤ Released Budget (always)
- Counters never decrease
- Available for payment approval = Budget - Released Budget

### Campaign Fund

Represents a fund addition request from client to campaign.

**Key Attributes:**
- Amount requested
- Status (Pending, Approved, Rejected)

**Key Rules:**
- When approved by 4Shark Finance, Campaign Budget is incremented
- Approval requires manual verification that money was received

### Incentive Payment

Represents commissions that route to the incentive system (separated from normal payroll).

**Key Attributes:**
- Employee receiving the payment
- Amount
- Status (Pending, Approved)

**Key Rules:**
- Only created for commissions from Plans that have an Incentive Campaign
- When approved by client, Released Budget is incremented
- When approved, credits the employee's Incentive Campaign Account

### Incentive Campaign Account

Represents an employee's account within a specific campaign.

**Key Attributes:**
- Employee
- Campaign
- Balance (credits from approved payments, debits from usage)

**Key Rules:**
- One account per employee per campaign (not global)
- Balance is campaign-scoped
- Unused balance expires according to campaign rules

### Plan

Represents a compensation plan that calculates commissions.

**Key Attributes:**
- Name
- Commission calculation rules
- Incentive Campaign (optional)
- Status (Draft, Approved, Active)

**Key Rules:**
- Can optionally have an Incentive Campaign selected
- Incentive Campaign can only be set during Plan creation or update
- Once Plan is approved, the Incentive Campaign association cannot be changed
- If Plan has Incentive Campaign, commissions go to Incentive Payment (not normal payroll)

### Incentive Item

Represents a product available in the 4Shark platform.

**Key Attributes:**
- Name and description
- Selected from partner's catalog (5000+ items, only subset made available)

### Incentive Catalogation

Associates an Incentive Item with an Incentive Campaign.

**Key Rules:**
- Defines which Incentive Items are available in a specific campaign
- Each campaign can have different items available

### Incentive Transaction

Base concept for money movements in an Incentive Campaign Account. There are two types:

- **Incentive Credit**: Adds balance (from approved payments)
- **Incentive Debit**: Removes balance (from item acquisitions - Phase 2)

### Incentive Credit

Represents a credit that adds balance to an employee's Incentive Campaign Account.

**Key Attributes:**
- Employee
- Amount
- Status (Final only - no pending state)
- Associated Incentive Payment
- Associated IncentiveUserPayment

**Key Rules:**
- Created as `final` directly when payment is approved (not during generation)
- No pending state - employees only see balance after approval
- Balance becomes available immediately upon credit creation

**Lifecycle:**
1. Payment generated → IncentiveUserPayment created (aggregates value per user)
2. Payment approved → Budget validated synchronously
3. Credit created as Final → Balance available immediately

### Incentive Debit

Represents a debit that removes balance from an employee's Incentive Campaign Account (Phase 2 - not implemented yet).

**Key Attributes:**
- Employee
- Amount
- Status (Pending, Processing, Final)
- Associated Item Order

**Key Rules:**
- Created when employee acquires an Incentive Item
- Transitions through states as order is processed
- Not implemented in Phase 1

## Relationships

```
Plan ───(optional)───► Incentive Campaign
                              │
                              ├───► Campaign Fund (many)
                              │
                              ├───► Incentive Payment (many)
                              │           │
                              │           └───► Incentive Credit (many)
                              │                       │
                              │                       └───► Incentive Campaign Account
                              │
                              ├───► Incentive Campaign Account (one per employee)
                              │           │
                              │           └───► Incentive Transaction (many: Credits and Debits)
                              │
                              └───► Incentive Catalogation (many) ───► Incentive Item
```

| From | To | Relationship |
|------|----|--------------|
| Plan | Incentive Campaign | Optional (0 or 1), immutable after Plan approval |
| Incentive Campaign | Campaign Fund | One to many |
| Incentive Campaign | Incentive Payment | One to many |
| Incentive Campaign | Incentive Campaign Account | One per employee |
| Incentive Campaign | Incentive Catalogation | One to many |
| Incentive Catalogation | Incentive Item | Many to one |
| Incentive Payment | Incentive Credit | One to many (one credit per employee commission) |
| Incentive Credit | Incentive Campaign Account | Many to one (credits belong to an account) |
| Incentive Campaign Account | Incentive Transaction | One to many (all credits and debits) |

## Domain Rules Summary

| Rule | Description |
|------|-------------|
| Budget Invariant | Released Budget ≤ Budget at all times |
| Released Budget Invariant | Consumed Budget ≤ Released Budget at all times |
| Counters Only Increment | Budget, Released Budget, Consumed Budget never decrease |
| Fund Approval Required | Budget only increments after 4Shark Finance approval |
| Budget Check Before Payment | Cannot approve payment if amount > available budget |
| Plan-Campaign Immutability | Once Plan is approved, Incentive Campaign association cannot change |
| Account Per Campaign | Each employee has separate account per campaign |
| Automatic Routing | Commissions route automatically based on Plan configuration |
| Single Approval Point | Only client approves payments; Finance only approves funds |
| Credits Created as Final | Incentive Credits are created as `final` directly when payment is approved |
| Budget Validation Synchronous | Budget is validated synchronously during approval, before credits are created |
| No Pending Credits | Employees only see balance after payment approval (no pending state) |

## Notes

- **Phase 1 only**: This model does NOT include employee balance usage (Phase 2)
- **Counter-based**: Budget counters are cumulative and never decrease
- **Campaign-scoped accounts**: Each employee has separate accounts per campaign, not a global balance
- **Automatic routing**: System automatically routes commissions based on Plan configuration

---

**Status:** DOCUMENTATION COMPLETE

**Files created:**
- KNOWLEDGE.md - Business knowledge and context
- PROCESS.md - Business processes and flows
- DOMAIN.md - Domain entities and relationships
