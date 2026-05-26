# PROCESS - Incentive System (Phase 1)

> Reference: KNOWLEDGE.md

## Overview

The Incentive System transforms 4Shark from a commission calculator into a financial intermediary. Money flows through the platform in three distinct phases (Budget → Released Budget → Consumed Budget), allowing complete traceability and control of the incentive payment lifecycle.

This document describes the business processes that enable clients to fund campaigns, generate payments, and release money to employee accounts.

## Main Processes

1. **Campaign Setup Process** - Client creates and configures an Incentive Campaign
2. **Fund Addition Process** - Client deposits money to enable campaign payments
3. **Payment Generation Process** - System calculates commissions and prepares payments
4. **Payment Approval Process** - Client approves payments and releases budget to employees

---

## Process 1: Campaign Setup

### Trigger

Client decides to use the incentive system to pay variable compensation (commissions, bonuses, awards) to their employees.

### Main Flow

```
Client Creates Campaign
        │
        ▼
Client Configures Campaign Rules
(period, eligibility, balance validity)
        │
        ▼
Client Selects Incentive Items
(via Incentive Catalogation)
        │
        ▼
Campaign Ready (Budget = 0)
```

**Note**: Associating a Plan with an Incentive Campaign is done during Plan creation or update (see Notes section below).

### Detailed Steps

#### Step 1: Create Incentive Campaign

- **Actor**: Client
- **Input**: Campaign name, description
- **Action**: Creates a new Incentive Campaign in the system
- **Output**: Empty campaign with Budget = 0
- **Next**: Configure campaign rules

#### Step 2: Configure Campaign Rules

- **Actor**: Client
- **Input**: Campaign instance
- **Action**: Defines period, eligibility criteria, balance validity rules
- **Output**: Configured campaign
- **Next**: Select available Incentive Items

#### Step 3: Select Incentive Items (Incentive Catalogation)

- **Actor**: Client
- **Input**: Available Incentive Items from 4Shark catalog
- **Action**: Chooses which Incentive Items will be available in this campaign
- **Output**: Incentive Catalogation records (items selected for this campaign)
- **Next**: Campaign ready to receive funds

### Outcomes

| Outcome | Condition | Result |
|---------|-----------|--------|
| Campaign Created | Client completes all configuration steps | Campaign exists but has no budget yet |
| Campaign Incomplete | Client abandons configuration midway | Campaign exists but cannot be used for payments |

### Notes

- Campaign can be created without budget, but cannot make payments until funds are added
- Each campaign has isolated Incentive Catalogation - different campaigns can offer different Incentive Items
- Campaign creation does not trigger any money movement

### Plan and Incentive Campaign (Separate Configuration)

Associating a Plan with an Incentive Campaign is **NOT part of Campaign Setup**. It happens during **Plan creation or update**:

- **When creating a new Plan**: Client can optionally select an Incentive Campaign
- **When updating an existing Plan**: Client can optionally select or change the associated Incentive Campaign
- **Approved Plans cannot be modified**: Once a Plan is approved and in use, the Incentive Campaign association cannot be changed
- **Optional**: A Plan does not need to have an Incentive Campaign
- **Effect**: If a Plan has an Incentive Campaign selected, commissions from this Plan will route to Incentive Payment (not normal payroll)

---

## Process 2: Fund Addition (Campaign Fund)

### Trigger

Client needs to add money to the campaign budget to enable payment approvals.

### Main Flow

```
Client Requests Fund Addition
(specifies amount)
        │
        ▼
Client Makes Bank Transfer
(to 4Shark account)
        │
        ▼
Client Sends Proof of Transfer
(WhatsApp, email, etc.)
        │
        ▼
4Shark Finance Verifies Receipt
(manual bank account check)
        │
        ├── Money Received ──────► 4Shark Finance Approves
        │                                   │
        │                                   ▼
        │                          Campaign Budget Incremented
        │                          (Budget += amount)
        │
        └── Money NOT Received ──► Request Remains Pending
```

### Detailed Steps

#### Step 1: Request Fund Addition

- **Actor**: Client
- **Input**: Desired amount to add
- **Action**: Creates fund request in the system
- **Output**: Pending fund request with bank transfer instructions
- **Next**: Client performs bank transfer

#### Step 2: Perform Bank Transfer

- **Actor**: Client
- **Input**: 4Shark bank account details, amount from request
- **Action**: Transfers money via bank to 4Shark account
- **Output**: Bank transfer completed
- **Next**: Send proof to 4Shark

#### Step 3: Send Proof of Transfer

- **Actor**: Client
- **Input**: Bank receipt/proof of transfer
- **Action**: Sends proof via WhatsApp, email, or other channel
- **Output**: 4Shark Finance receives notification
- **Next**: Finance team verification

#### Step 4: Verify Money Receipt

- **Actor**: 4Shark Finance
- **Input**: Proof sent by client, bank account statement
- **Action**: Manually checks if money was actually received in 4Shark account
- **Output**: Verification result (money received or not)
- **Next**: If received → approve; if not → wait

#### Step 5: Approve Fund Addition

- **Actor**: 4Shark Finance
- **Input**: Verified fund request
- **Action**: Approves request in the system
- **Output**: Campaign Budget incremented by the amount
- **Next**: Client can now approve payments up to budget amount

### Decision Points

#### Decision 1: Money Received?

- **Question**: Did 4Shark actually receive the bank transfer?
- **Options**:
  - **Yes**: Approve request → increment Budget
  - **No**: Keep request pending → ask client to resend proof or confirm transfer
- **Who decides**: 4Shark Finance
- **Based on**: Bank account statement verification

### Outcomes

| Outcome | Condition | Result |
|---------|-----------|--------|
| Funds Added | Finance verifies and approves | Campaign Budget increased, available for payment approvals |
| Request Pending | Money not yet received or verified | Request remains in pending state, no budget change |
| Request Rejected | Proof invalid or transfer not found | Request marked as rejected, client must create new request |

### Notes

- **Manual verification is required** - Finance team must confirm money receipt before approval
- **External communication channel** - Proof is sent via WhatsApp/email, not through the system
- **Money ownership at this phase belongs to 4Shark** - Client has deposited but not yet released to employees
- **Budget can be incremented multiple times** - Client can add funds as needed
- **Approval is irreversible** - Once approved, budget cannot be removed (only consumed through payments)

---

## Process 3: Commission Generation and Approval

### Trigger

Client decides to generate commissions for a period based on compensation Plans.

### Main Flow

```
Client Generates Commissions
(based on compensation Plans)
        │
        ▼
System Calculates Values
(using sales data, metrics, Plan rules)
        │
        ▼
Client Reviews Commissions
        │
        ▼
Client Approves Commissions
        │
        ▼
Approved Commissions Available for Payment
        │
        ▼
System Checks Plan Configuration
        │
        ├── Plan has Incentive Campaign? ──► YES ──► Available in Incentive Payment
        │
        └── Plan has NO Incentive Campaign? ────► Available in Normal Payment
```

### Detailed Steps

#### Step 1: Generate Commissions

- **Actor**: Client
- **Input**: Period selection, Plan selection
- **Action**: Requests commission calculation for the selected period and plans
- **Output**: Calculated commission amounts per employee per Plan
- **Next**: Review commissions

#### Step 2: Review Commissions

- **Actor**: Client
- **Input**: Calculated commissions
- **Action**: Reviews values, makes adjustments if needed
- **Output**: Reviewed commissions ready for approval
- **Next**: Approve commissions

#### Step 3: Approve Commissions

- **Actor**: Client
- **Input**: Reviewed commissions
- **Action**: Approves commissions for payment
- **Output**: Approved commissions available for payment generation
- **Next**: Commissions routed based on Plan configuration

#### Step 4: Route Approved Commissions

- **Actor**: System
- **Input**: Approved commissions, Plan configuration
- **Action**: Routes commissions to appropriate payment flow
- **Output**: Commissions available in Incentive Payment or Normal Payment
- **Next**: Client generates payment

### Decision Points

#### Decision 1: Plan has Incentive Campaign?

- **Question**: Does this Plan have an Incentive Campaign selected?
- **Options**:
  - **Yes**: Commissions available in Incentive Payment flow
  - **No**: Commissions available in Normal Payment flow (payroll export)
- **Who decides**: System (automatic based on Plan configuration)
- **Based on**: Whether the Plan has an Incentive Campaign associated

### Outcomes

| Outcome | Condition | Result |
|---------|-----------|--------|
| Available in Incentive Payment | Plan has Incentive Campaign | Commissions go to Incentive Payment, separated from normal payroll |
| Available in Normal Payment | Plan has no Incentive Campaign | Commissions go to standard payroll flow, exported to external system |

### Notes

- **Client-initiated process**: Commission generation is NOT automatic - client must trigger it
- **Dashboard uses partial data**: System generates partial calculations for dashboard, but these are NOT the actual commissions
- **Approval required before payment**: Commissions must be approved before they can be included in any payment
- **Automatic routing after approval**: Once approved, system automatically routes based on Plan configuration
- **Same calculation engine**: Commission calculation follows same rules regardless of Incentive Campaign association

---

## Process 4: Payment Approval

### Trigger

Client wants to release calculated payments to employee accounts.

### Main Flow

```
Client Views Pending Payments
(total amount per campaign)
        │
        ▼
Client Decides to Approve
        │
        ▼
System Validates Budget (SYNCHRONOUS)
(Available = Budget - Released Budget)
        │
        ├── Amount > Available? ──► YES ──► Approval FAILS
        │                                          │
        │                                          ▼
        │                                  Payment stays in "review"
        │                                  Client Must Add Funds First
        │
        └── Amount <= Available? ──► YES ──► TRANSACTION:
                                             │ - Released Budget += Amount
                                             │ - Payment → "final"
                                             ▼
                                           ASYNC: Create Credits
                                           (IncentiveCredit::Producer)
                                                    │
                                                    ▼
                                           Credit Employee Accounts
                                           (status: final from creation)
                                                    │
                                                    ▼
                                           Payment Complete
```

### Detailed Steps

#### Step 1: View Pending Payments

- **Actor**: Client
- **Input**: Campaign selection
- **Action**: Views list of pending Incentive Payments and total amount
- **Output**: Understanding of how much needs to be approved
- **Next**: Decide to approve or not

#### Step 2: Initiate Approval

- **Actor**: Client
- **Input**: Selected payments to approve
- **Action**: Requests approval of payment batch
- **Output**: Approval request sent to system
- **Next**: System validates budget

#### Step 3: Validate Budget Availability

- **Actor**: System
- **Input**: Campaign Budget, Released Budget, total payment amount
- **Action**: Calculates Available = Budget - Released Budget, then checks if Amount > Available
- **Output**: Validation result (sufficient or insufficient)
- **Next**: If Amount > Available → show error; otherwise → process approval

#### Step 4: Process Approval

- **Actor**: System
- **Input**: Validated payment batch
- **Action**:
  1. SYNCHRONOUSLY in same transaction: validate budget AND increment Released Budget AND transition payment to `final`
  2. ASYNCHRONOUSLY after transaction commits: create Incentive Credits as `final` for each employee
  3. Each credit creation increments the employee's Incentive Campaign Account balance
- **Output**: Employees have balance available in their campaign accounts
- **Next**: Payment complete

**Important**: Budget validation and payment finalization happen in the SAME transaction. If budget is insufficient, the transaction rolls back and no credits are ever created. Credits are only created AFTER the payment is confirmed as `final`.

#### Step 5: Handle Insufficient Budget

- **Actor**: System
- **Input**: Budget amount, payment amount
- **Action**: Shows error message to client
- **Output**: "Insufficient Budget" error
- **Next**: Client must add funds via Fund Addition Process

### Decision Points

#### Decision 1: Amount exceeds Available Budget?

- **Question**: Is payment Amount > Available Budget (Budget - Released Budget)?
- **Options**:
  - **Yes**: Block approval → show error → client must add funds
  - **No**: Process approval → increment Released Budget → credit accounts
- **Who decides**: System (automatic validation)
- **Based on**: Payment Amount vs. Available Budget

### Outcomes

| Outcome | Condition | Result |
|---------|-----------|--------|
| Payment Approved | Amount <= Available | Released Budget incremented, employees have balance in accounts |
| Insufficient Budget | Amount > Available | Approval blocked, client must add funds first |

### Notes

- **Counters only increment** - Budget, Released Budget, and Consumed Budget are cumulative counters that only increase (never decrease). Available balance is calculated as Budget - Released Budget
- **One account per campaign** - Each employee receives balance in their specific Incentive Campaign Account for that campaign
- **Balance is usable immediately** - Once approved, employees can use their balance according to campaign rules
- **Money still at 4Shark** - Released Budget means ownership transferred to employees, but money is still physically at 4Shark

### Incentive Credits Lifecycle

**Important:** Credits are NOT created during payment generation. They are only created AFTER approval.

When an Incentive Payment is generated:
1. **IncentiveUserPayment records are created** - Aggregates value per user
2. **Payment goes to `review` status** - Waiting for client approval
3. **No credits exist yet** - Employees do not see pending balances

When the client approves the Incentive Payment:
1. **Budget validation happens SYNCHRONOUSLY** - Before any credits are created
2. **If budget insufficient** - Approval fails, payment stays in `review`, no credits created
3. **If budget sufficient** - Payment transitions to `final`, `released_budget` incremented
4. **Credits created as `final` directly** - One credit per user_commission, status is `final` from creation
5. **Balance becomes available immediately** - Employee can use their balance

**Why this design:**
- Budget validation MUST happen before credits are created (prevents creating credits without available funds)
- Synchronous validation ensures atomicity (approval + budget reservation in same transaction)
- Credits only exist when money is guaranteed (no "pending" state that might not materialize)

---

## The Three Budget Phases

This diagram shows the complete money lifecycle:

```
PHASE 1: BUDGET
(Money Deposited)
        │
        │  Client deposits
        │  Finance approves
        ▼
┌─────────────────┐
│     BUDGET      │ ← Money physically at 4Shark
│                 │   Ownership: 4Shark
│ (Available for  │   Client has NOT released to employees yet
│   approval)     │
└─────────────────┘
        │
        │  Client approves payment
        │  System validates budget
        ▼
┌─────────────────┐
│ RELEASED BUDGET │ ← Money physically at 4Shark
│                 │   Ownership: Employees (acquired right)
│ (Approved for   │   Credited to Incentive Campaign Accounts
│   employees)    │
└─────────────────┘
        │
        │  (Phase 2 - NOT IMPLEMENTED)
        │  Employee uses balance
        ▼
┌─────────────────┐
│ CONSUMED BUDGET │ ← Money leaves 4Shark
│                 │   Goes to external partner
│ (Money used)    │   Transaction completed
└─────────────────┘
```

### Why Three Phases?

**Control & Audit**: Each phase has clear ownership and traceability
- **Budget**: Client has deposited, but not committed to employees
- **Released Budget**: Client has committed, employees have right to use
- **Consumed Budget**: Money has left the platform, transaction complete

**Fraud Prevention**: Separation prevents unauthorized releases
- Cannot release more than deposited (Budget limit)
- Cannot consume more than released (Released Budget limit)

**Business Flexibility**: Allows different operations at each phase
- Budget phase: Client can plan and forecast
- Released Budget phase: Employees can accumulate and decide when to use
- Consumed Budget phase: Platform tracks actual outflow

---

## Actors

| Actor | Role | Responsibilities |
|-------|------|------------------|
| **Client** | Company using 4Shark | Creates campaigns, deposits funds, approves payments, configures Plans |
| **4Shark Finance** | Finance team | Verifies bank transfers, approves fund requests, ensures money was received |
| **4Shark Internal** | Internal team | Manages Incentive Items and Catalogation (curated catalog for employees) |
| **Employee** | Client's employee | Receives balance in Incentive Campaign Account, redeems vouchers |
| **Partner** | Voucher provider | Provides vouchers to employees (Incentivale for Brazil, others in future) |
| **System** | 4Shark platform | Calculates commissions, routes payments, validates budget, credits accounts, integrates with partners |

---

## Complete Sequence Diagram

```
Client          System          4Shark Finance          Bank
  │                │                    │                 │
  │──Campaign─────►│                    │                 │
  │   Setup        │                    │                 │
  │                │                    │                 │
  │──Fund Request─►│                    │                 │
  │                │                    │                 │
  │────────────Transfer Money──────────────────────────►│
  │                │                    │                 │
  │──Send Proof────────────────────────►│                 │
  │                │                    │                 │
  │                │                    │──Check Account─►│
  │                │                    │                 │
  │                │                    │◄───Confirmed────│
  │                │                    │                 │
  │                │◄───Approve Fund────│                 │
  │                │                    │                 │
  │                │  [Budget += Amount] │                 │
  │                │                    │                 │
  │◄───Confirmed───│                    │                 │
  │                │                    │                 │
  │                │ [Calculate         │                 │
  │                │  Commissions]      │                 │
  │                │                    │                 │
  │                │ [Create Incentive  │                 │
  │                │  Payments]         │                 │
  │                │                    │                 │
  │◄───View Pending│                    │                 │
  │    Payments    │                    │                 │
  │                │                    │                 │
  │──Approve───────►│                    │                 │
  │   Payments     │                    │                 │
  │                │                    │                 │
  │                │ [Validate Budget]  │                 │
  │                │                    │                 │
  │                │ [Budget → Released │                 │
  │                │  Budget]           │                 │
  │                │                    │                 │
  │                │ [Credit Employee   │                 │
  │                │  Accounts]         │                 │
  │                │                    │                 │
  │◄───Success─────│                    │                 │
```

---

## Critical Business Rules

### Budget Rules
1. **Budget must exist before approval**: Cannot approve payments without sufficient available budget (Budget - Released Budget)
2. **Counters only increment**: Budget, Released Budget, and Consumed Budget never decrease - they are cumulative totals
3. **Invariant validation**: Released Budget ≤ Budget (always), Consumed Budget ≤ Released Budget (always) - enables automatic daily reconciliation

### Campaign Rules
1. **One account per campaign per employee**: Balances are isolated by campaign
2. **Campaign must have Incentive Catalogation**: Campaign must define available Incentive Items

### Plan Rules
1. **One campaign per Plan**: A Plan can only be associated with one Incentive Campaign
2. **Set only during create/update**: The Incentive Campaign can only be selected when creating or updating a Plan
3. **Approved Plans are immutable**: Once approved, the Incentive Campaign association cannot be changed

### Payment Rules
1. **Automatic routing by Plan**: System automatically routes based on whether Plan has Incentive Campaign
2. **Separated from payroll**: Incentive Payments never mix with normal payroll export
3. **Single approval point**: Only client approves payments, 4Shark does not intervene

### Fund Rules
1. **Manual verification required**: Finance must verify actual bank receipt before approval
2. **External proof channel**: Proof is sent outside the system (WhatsApp/email)
3. **Money ownership changes**: Budget = 4Shark owns, Released Budget = employees own

---

**Status:** READY FOR DOMAIN MODELING

**Next Step:** This document describes the business processes of Phase 1. Use `@agent-domain-modeler` to create DOMAIN.md mapping these processes to domain entities and their relationships.
