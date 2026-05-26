# KNOWLEDGE - Incentive System Phase 2: Voucher Redemption

> Reference: KNOWLEDGE.md (Phase 1), PROCESS.md, DOMAIN.md, ANALYSIS.md

## The Problem

### Current State

Phase 1 implemented the flow of money from **Client → 4Shark → Employee Account**:
- Client deposits money (Budget)
- Client approves payment to employees (Released Budget)
- Employees have balance available in their Incentive Campaign Account

However, **employees cannot yet use their balance**. The money sits in their account with no way to spend it.

### Why Phase 2 Matters

Phase 2 completes the money lifecycle by enabling employees to **redeem their balance for vouchers**:
- Employee uses balance to acquire products (vouchers)
- Money flows from 4Shark to external partners
- Employee receives voucher code via email
- Budget counter increments to track consumed money (Consumed Budget)

Without Phase 2, the incentive system is incomplete - employees see balance but have no utility for it.

### Business Opportunity

With voucher redemption:
- Complete incentive money lifecycle (deposit → release → consume)
- Real value delivery to employees (actual products/services)
- Control over what employees can purchase (via Incentive Catalogation)
- Traceability of how incentive money is spent
- Support for multi-country expansion with multiple partners

---

## Current State (Phase 1 - Already Implemented)

### Money Flow - The Three Phases

```
PHASE 1: BUDGET (Deposited Money)
├── Client deposits money at 4Shark
├── 4Shark finance verifies and approves
├── Money is at 4Shark, ownership belongs to 4Shark
└── Client has not yet released it to employees

PHASE 2: RELEASED BUDGET (Released Money)
├── Client approves payment to employees
├── Money is still physically at 4Shark
├── Ownership belongs to employees (acquired right)
└── Employees have balance in their Incentive Campaign Account

PHASE 3: CONSUMED BUDGET (Used Money) ← NOT IMPLEMENTED
├── Employee uses balance to acquire vouchers
├── Money leaves 4Shark
├── Goes to external partner
└── Transaction completed
```

### What Exists Today

**Implemented:**
- Incentive Campaign creation and configuration
- Campaign Fund (client deposits money)
- Incentive Payment (client approves payment to employees)
- Incentive Campaign Account (employee balance per campaign)
- Incentive Credit (transactions that add balance)
- Incentive Item model (products available)
- Incentive Catalogation model (items per campaign)
- Budget and Released Budget counters

**Not Implemented:**
- Consumed Budget counter (never incremented)
- Incentive Debit (transactions that remove balance)
- Incentive Order (employee purchase request)
- Partner integration for voucher acquisition
- Voucher delivery mechanism
- Employee redemption UI

---

## Business Context

### Multi-Partner Strategy

**Critical Requirement:** The system must support multiple voucher partners.

**Current Situation:**
- First partner is **Incentivale** (Brazil only)
- 4Shark has clients in **9 Latin American countries**
- Incentivale only operates in Brazil
- A potential partner in Colombia has already been identified
- Future expansion requires additional partners per country/region

**Implication:**
- Data structure must be partner-agnostic from day one
- Partner-specific code (Incentivale) is acceptable as first implementation
- Database schema cannot be tied to a specific partner
- Naming conventions in data/schema should not reference specific partners

### 4Shark's Own Catalog

**Key Concept:** 4Shark maintains its own product catalog (Incentive Item), independent of partner catalogs.

**Why:**
- Partners have large catalogs (e.g., Incentivale has 5000+ SKUs)
- 4Shark selects a subset that makes sense for clients (30-50 items)
- Different campaigns can have different items (via Incentive Catalogation)
- Clients don't see partner complexity - only 4Shark's curated catalog
- Some clients may want to add their own products (e.g., insurance company offering their own gift cards)

**Flow:**
1. Partner has a large catalog of available products
2. 4Shark selects relevant items to add to Incentive Item
3. Client selects which Incentive Items are available in their campaign (via Incentive Catalogation)
4. Employees only see items available in their campaign

### Campaign-Scoped Redemption

**Key Concept:** Employees have one account per campaign, not a global balance.

**Implications:**
- Employee can have multiple campaign accounts with different balances
- Each campaign has its own available items (via Incentive Catalogation)
- Employee can only spend balance on items available in that specific campaign
- If campaign has R$1000 balance but items only in R$50 and R$100 denominations, employee can only buy those

### Item Value Flexibility

**Key Concept:** Items can have variable values.

**Example:**
- Incentive Item: "Amazon Gift Card"
- Catalogation: Available in campaign X
- Value can be: R$50, R$100, R$200, etc.
- SKU format follows pattern: `{item_sku}V{value}` (e.g., "AMAZONV100" = Amazon gift card worth R$100)

---

## The Voucher Redemption Flow

### Happy Path (Synchronous Part)

```
Employee Opens Incentive Portal
        │
        ▼
System Shows Campaigns with Balance > 0
        │
        ▼
Employee Selects Campaign
        │
        ▼
System Shows Available Items (via Incentive Catalogation)
        │
        ▼
Employee Selects Item and Value
        │
        ▼
System Validates:
- Item available in this campaign? (Catalogation check)
- Balance >= Item value? (Account balance check)
        │
        ├── Validation Failed ──► Show Error
        │
        └── Validation Passed ──► SYNCHRONOUS: Call Partner API
                                        │
                                        ├── Partner Error ──► Show Error
                                        │                     (no balance change)
                                        │
                                        └── Partner Success ──► Create Debit
                                                                Decrement Balance
                                                                Return Success to Employee
                                                                (order in processing)
```

### Voucher Delivery (Asynchronous Part)

```
System Polls Partner API (periodically)
        │
        ▼
Check Order Status via FindTracking endpoint
        │
        ├── Status = Delivered (3) ──► Get Voucher Code
        │                                    │
        │                                    ▼
        │                              Send Email to Employee
        │                              (with voucher code)
        │                                    │
        │                                    ▼
        │                              Increment consumed_budget
        │                              Mark Order as Completed
        │
        └── Status = Cancelled (7) ──► Mark Order as Failed
                                       (manual refund process)
```

### Error Handling (Manual Process)

**When partner fails or cancels:**
1. Partner provides list of failed orders (via report or email)
2. 4Shark creates manual script
3. Script creates Incentive Credit transactions to refund balance
4. Employee can then redeem again

**Rationale:** Error scenarios are rare and complex. Automating refunds introduces risk of financial inconsistency. Manual process ensures human verification.

---

## Key Business Rules

### Balance Rules

| Rule | Description |
|------|-------------|
| **Balance Check** | Employee cannot order if balance < item value |
| **Immediate Debit** | Balance is decremented synchronously when partner confirms order reception |
| **No Partial Orders** | Cannot order item worth more than balance (no "pay later") |
| **Campaign Isolation** | Cannot use balance from Campaign A to buy item from Campaign B |
| **Database as Truth** | Always query database for balance, never cache in application objects |

### Budget Counter Rules

| Counter | When Incremented | Invariant |
|---------|-----------------|-----------|
| **budget** | When 4Shark Finance approves fund addition | - |
| **released_budget** | When client approves payment to employees | released_budget ≤ budget |
| **consumed_budget** | When voucher is delivered (partner status = 3) | consumed_budget ≤ released_budget |

### Item Availability Rules

| Rule | Description |
|------|-------------|
| **Catalogation Required** | Employee can only see items that exist in Incentive Catalogation for their campaign |
| **Value Validation** | Item value must not exceed employee's balance |
| **No Stock Check** | Initially, no real-time stock check with partner (trust that items are available) |

### Partner Integration Rules

| Rule | Description |
|------|-------------|
| **Synchronous Order Creation** | Order sent to partner in same request as employee's action |
| **Asynchronous Delivery** | Voucher delivery is polled via scheduled job |
| **No Webhook** | Partner doesn't push status - system polls via FindTracking |
| **Email by 4Shark** | Voucher code sent by 4Shark mailer, not partner's email |
| **No Code Storage** | Voucher code should not be stored in database (one-time use) |
| **Idempotency** | Use order ID as cod_request for partner to prevent duplicates |

---

## Domain Concepts

### Existing Concepts (From Phase 1)

| Term | Definition |
|------|------------|
| **Incentive Campaign** | Campaign created by client with budget, period, and available items |
| **Incentive Campaign Account** | Employee's balance within a specific campaign (one per employee per campaign) |
| **Incentive Transaction** | Base for money movements (Credit or Debit) |
| **Incentive Credit** | Transaction that adds balance (from approved payments) |
| **Incentive Item** | Product in 4Shark's catalog (curated from partner catalogs) |
| **Incentive Catalogation** | Links an Incentive Item to an Incentive Campaign |

### New Concepts (Phase 2)

| Term | Definition |
|------|------------|
| **Incentive Debit** | Transaction that removes balance when employee acquires voucher |
| **Incentive Order** | Employee's request to redeem balance for a voucher |
| **Incentive Order Item** | Links order to specific catalogation and value |
| **Consumed Budget** | Campaign counter tracking money actually spent by employees |
| **Partner** | External voucher provider (Incentivale, others in future) |
| **Voucher Code** | Unique code from partner that employee uses to redeem product |

### Concept Relationships

```
Employee
    │
    └── has many ──► Incentive Campaign Account (one per campaign)
                          │
                          ├── has balance
                          │
                          └── has many ──► Incentive Transaction
                                               ├── Incentive Credit (money in)
                                               └── Incentive Debit (money out)
                                                        │
                                                        └── belongs to ──► Incentive Order Item
                                                                                 │
                                                                                 └── belongs to ──► Incentive Order
```

```
Incentive Campaign
    │
    ├── has ──► budget, released_budget, consumed_budget
    │
    ├── has many ──► Incentive Campaign Account (one per employee)
    │
    └── has many ──► Incentive Catalogation
                          │
                          └── belongs to ──► Incentive Item
```

---

## Constraints

### Business Constraints

- **Balance must exist before redemption**: Employee cannot redeem without sufficient balance
- **Campaign-scoped items**: Employee can only redeem items available in their campaign
- **Single partner initially**: Start with Incentivale, but data structure must support more
- **Manual refunds**: Failed orders are handled manually, not automated
- **No spending limits initially**: No daily/weekly/monthly limits on redemption (may add later)

### Operational Constraints

- **Polling for status**: No webhook from partner, must poll periodically
- **Email via 4Shark**: Partner doesn't send email directly to employee
- **Curated catalog**: 4Shark selects items, clients don't add items directly
- **Internal catalogation management**: Initially no UI for Incentive Catalogation (manual DB operations)

### Technical Constraints

- **Synchronous validation**: Balance check and partner call in same request
- **Database as lock**: Use database transactions and counters as source of truth
- **No voucher storage**: Avoid storing voucher codes in database (security + one-time use)
- **Partner-agnostic schema**: Database columns/tables cannot reference specific partner names

### Financial Constraints

- **Payment cycle with partner**: 4Shark pays partner every 15 days
- **Client payment before release**: Client should pay before approving release to employees
- **Commercial flexibility**: 4Shark may release early based on client relationship (manual override)

---

## Phase 1 Changes

### Removed: Pending Credits on Payment Generation

**Original Design:**
- When client generates payment, create Incentive Credit as "pending"
- Employees see pending credits (creates incentive to push for approval)
- When client approves, credits transition to "final"

**New Decision:**
- Do NOT create pending credits on payment generation
- Only create credits (as final) when client approves payment
- Employees only see balance after approval

**Rationale:** After discussion with clients and stakeholders, showing pending credits creates more confusion than benefit for initial launch.

---

## What We Know

### From Phase 1 Documentation

- Three-phase budget lifecycle (Budget → Released Budget → Consumed Budget)
- Campaign-scoped accounts and balances
- Incentive Item and Catalogation models exist
- Counter-based budget tracking (only increment, never decrement)

### From PR Analysis (4399, 4514, 4609, 4659)

**Partner Integration (Incentivale):**
- Base URL configured via environment variable
- OAuth2 authentication (password grant)
- Token cached for 50 minutes
- Endpoints: /oauth/token, /api/v3/AddResquest, /api/v3/ExistRequest, /api/v3/FindTracking
- Status IDs: 1 = Pending, 3 = Delivered, 7 = Cancelled
- SKU format: `{catalogation.sku}V{value.to_i}`

**Worker Pattern:**
- Producer/Consumer pattern for async processing
- TenantWorker for multi-tenant queue processing
- StatusCheckProducer scheduled to poll all pending orders
- StatusCheckConsumer updates status from partner API

**Email Delivery:**
- IncentiveOrderMailer sends voucher code to employee
- HTML and text templates available
- I18n keys for localization

### From User Context

- 4Shark operates in 9 Latin American countries
- Incentivale only operates in Brazil
- Potential partner already identified in Colombia
- Multi-partner support is strategic requirement
- Partner payment cycle is 15 days
- Initial UI for Incentive Catalogation management not needed (internal operation)

---

## What We Need to Clarify

### Answered Questions

| Question | Answer | Source |
|----------|--------|--------|
| Partner integration method? | REST API with OAuth2 | PR Analysis |
| Real-time or async? | Sync for order creation, async for delivery | User |
| Voucher delivery? | Email from 4Shark | User + PRs |
| Voucher code storage? | Avoid storing (one-time use) | User |
| Error handling? | Manual refund via script | User |
| Pending credits? | No - only create on approval | User |

### Open Questions

| Question | Options | Impact |
|----------|---------|--------|
| Balance reservation during processing? | Reserve vs immediate debit | Race condition handling |
| consumed_budget increment timing? | On order creation vs on delivery | Counter accuracy |
| Retry policy for partner failures? | Auto-retry vs manual | Error recovery complexity |
| Status polling frequency? | Every minute vs every 5 minutes vs configurable | Partner API load |
| Order cancellation by employee? | Allow before partner processing vs never | UX flexibility |

---

## Key Insights

### Multi-Partner Architecture

The most important architectural decision is **partner abstraction**. While first implementation is Incentivale-specific:
- Database schema must be generic
- Service interfaces should allow different partner implementations
- Configuration should support multiple partners per country/region

### Synchronous-First Approach

User explicitly requested synchronous order creation:
- Employee action → Partner API call → Response → UI feedback
- No "your order is being processed" for initial submission
- Async only for voucher delivery polling

### Manual Error Handling

Automating refunds introduces complexity and risk:
- Failed orders are rare
- Financial consistency is critical
- Manual scripts with human verification preferred
- Can automate later if volume justifies

### Database as Source of Truth

Balance and budget counters should always be queried from database:
- Never cache balance in application objects
- Use database transactions for atomicity
- Counters only increment (immutable history)

### Voucher Security

Voucher codes are valuable and should be treated carefully:
- Avoid storing in database
- One-time delivery via email
- If employee loses email, need manual process with partner

---

## Reference: Existing Implementation from PRs

The following components were implemented in the rejected PRs and can be used as reference:

**Reusable (with adjustments):**
- Incentivale API services (TokenService, OrderCreationService, etc.)
- Worker structure (Producer/Consumer pattern)
- Email templates and mailer
- Configuration for Incentivale credentials

**Needs Redesign:**
- Order state machine (different flow)
- Balance update timing (sync vs async)
- Debit creation timing
- consumed_budget increment

See `ANALYSIS.md` for detailed documentation of what was implemented.

---

**Status:** READY FOR PROCESS MODELING

**Next Step:** Use this knowledge to create PROCESS-PHASE2.md documenting the detailed business processes for voucher redemption.
