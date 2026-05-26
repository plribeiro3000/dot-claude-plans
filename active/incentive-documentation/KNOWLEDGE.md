# KNOWLEDGE - Incentive System Documentation

## The Problem

### Current State
Today, 4Shark calculates variable compensation (commissions, bonuses, profit sharing, awards) for client employees, but the money does not flow through the platform:
- Client calculates values in 4Shark
- Exports to external payroll system
- Payroll system processes payment via bank

### Why It Matters
The client has no visibility or control over the actual money flow through the platform. The system acts only as a calculator, not as a financial intermediary.

### Business Opportunity
With the Incentive system, money flows through 4Shark before reaching the employee, creating:
- Greater control and traceability of financial flow
- New business possibilities and services
- Ability to audit the entire money lifecycle

## Current State

### How It Works Today (Phase 1 - Already Implemented)

#### Campaign Creation
1. Client creates an Incentive Campaign in the system
2. Defines which Incentive Items will be available via Incentive Catalogation
3. Links the campaign to one or more variable compensation Plans
4. Defines campaign rules (period, eligibility, balance validity)

#### Money Flow - The Three Phases
Money goes through three distinct phases for control and audit purposes:

**Phase 1 - Budget (Deposited Money)**
- Client deposits money at 4Shark
- 4Shark finance team verifies and approves
- Money is at 4Shark, ownership belongs to 4Shark
- Client has not yet released it to employees

**Phase 2 - Released Budget (Released Money)**
- Client approves payment to employees
- Money is still physically at 4Shark
- But ownership belongs to employees (acquired right)
- Employees can use their balance whenever they want

**Phase 3 - Consumed Budget (Used Money)**
- Employee uses their balance to acquire Incentive Items
- Money leaves 4Shark
- Goes to external partner
- Transaction completed

#### Adding Funds to Campaign
1. Client requests fund addition specifying desired amount
2. Client makes bank transfer to 4Shark account
3. Client sends proof of transfer (WhatsApp, email, etc)
4. 4Shark finance team verifies if money was received
5. Finance team approves the request in the system
6. Campaign budget is incremented

#### Payment Generation and Approval
1. System calculates commissions normally based on plans
2. Commissions from plans linked to campaigns go to separate flow (Incentive Payment)
3. Client views total amount to pay employees
4. If there is sufficient budget → client approves → money is released
5. If there is no budget → client needs to add funds first

#### Incentive Campaign Account
- Each employee has an Incentive Campaign Account PER CAMPAIGN (not global)
- After payment approval, balance is credited to the employee's campaign account
- The account tracks all credits (from payments) and debits (from usage)
- Unused balance expires according to campaign rules

### What Works Well

- **Clear money flow segregation**: The three phases allow tracking exactly where every cent is
- **Fraud control**: Separation between budget and released budget prevents improper releases
- **Campaign flexibility**: Client can create different campaigns with different Incentive Items and rules
- **Campaign account isolation**: Balance from one campaign does not mix with another, facilitating control
- **Simplified approval**: Only client approves payments (4Shark only approves funds)
- **Customizable Incentive Catalogation**: Each campaign can have different Incentive Items available via Incentive Catalogation

### Pain Points

- **Still has limitations**: Phase 1 solves the basic flow, but there are unmet needs
- **Non-existent documentation**: Knowledge is in people's heads, not documented
- **Undocumented complexity**: New developers have difficulty understanding the system
- **Scattered business rules**: There is no single source of truth about how the system works

### Difficulties

- **New developer onboarding**: Without documentation, it's hard to understand the business context
- **System evolution**: Adding new features without breaking existing understanding
- **Stakeholder communication**: Difficult to explain what exists and what is missing
- **Maintenance**: Changes can break undocumented assumptions

## Domain Concepts

| Term | Definition |
|------|------------|
| **Incentive Campaign** | Campaign created by client to compensate employees via incentive system. Defines budget, period, eligibility, and which Incentive Items are available (via Incentive Catalogation) |
| **Budget** | Phase 1: Money deposited by client at 4Shark and approved by finance. Ownership belongs to 4Shark |
| **Released Budget** | Phase 2: Money approved by client for payment to employees. Still physically at 4Shark, but ownership belongs to employees |
| **Consumed Budget** | Phase 3: Money used by employees to acquire Incentive Items. Leaves 4Shark and goes to external partner |
| **Campaign Fund** | Process of adding money to a campaign. Client deposits, sends proof, finance approves |
| **Incentive Payment** | Segregated payment flow for commissions linked to incentive campaigns. Does not go to normal payroll |
| **Incentive Campaign Account** | Account that holds an employee's balance within a specific campaign. Each campaign has its own isolated account per employee, with its own balance and transaction history. Not a global employee account - it's campaign-scoped |
| **Incentive Item** | Products available in the 4Shark platform. Selected from partner's catalog (5000+ items) - only a subset is made available |
| **Incentive Catalogation** | Association between an Incentive Item and an Incentive Campaign. Defines which items are available in that specific campaign |
| **Incentive Transaction** | Movement of money in an Incentive Campaign Account. Can be a Credit (money in) or Debit (money out) |
| **Incentive Credit** | Credit transaction that adds balance to an employee's Incentive Campaign Account. Created as `final` directly when payment is approved. Credits are only created AFTER budget validation passes, ensuring money is always available before crediting employees |
| **Incentive Debit** | Debit transaction that removes balance from an employee's Incentive Campaign Account when acquiring Incentive Items (Phase 2 - not implemented yet) |

## Constraints

### Business Constraints
- Budget must exist before approving payment: Client cannot release money without having deposited first
- Balance per campaign: Employee cannot use balance from one campaign in another
- Balance expires: If not used within campaign period, it's lost (unless company runs promotion)
- Limited Incentive Items: Not all 5000+ partner items are available, 4Shark selects a subset to create Incentive Items
- Single approval: Only client approves payments (4Shark does not intervene in payment flow)

### Operational Constraints
- Manual proof: Client needs to send deposit proof via external channel (WhatsApp/email)
- Manual verification: 4Shark finance needs to manually verify if money was received
- Incentive Catalogation per campaign: Each campaign defines which Incentive Items will be available through Incentive Catalogation

### Regulatory Constraints
- Traceability: Every money movement needs to be auditable
- Ownership segregation: System needs to clearly identify who owns the money at each phase

## Open Questions

*None at the moment. This document captures the knowledge of Phase 1 already implemented.*

## Key Insights

- **The incentive system transforms 4Shark from calculator to financial intermediary**: This is the fundamental business change
- **The three budget phases are about control and audit**: It's not just accounting, it's about preventing fraud and having visibility
- **Isolated campaigns allow flexibility**: Client can create campaigns with completely different rules (e.g., Christmas with double points but fewer items)
- **Flow segregation is essential**: Commissions linked to Incentive Campaigns cannot mix with normal payroll
- **Incentive Catalogation is competitive advantage**: Client chooses which Incentive Items to offer per campaign, not forced to partner's complete catalog
- **Approval simplification was important**: Removing 4Shark approval on payment eliminated unnecessary bureaucracy
- **Incentive Campaign Accounts give granular control**: Allows tracking exactly how much each employee earned and spent in each specific campaign

## Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Budget validation timing | **Synchronous during approval** | Must validate BEFORE creating credits. If done async after credits, could create credits without available budget (bug found in original implementation) |
| Credit creation timing | **Async AFTER approval confirmed** | Credits only created when payment is `final`. Approval + budget validation in same transaction ensures atomicity |
| Credit initial status | **Final from creation** | No pending state. Employees only see balance when money is guaranteed. Simpler flow, no state transition needed |
| Worker namespace | **Model being processed** | Workers go in namespace of the model they CREATE, not the model that triggers them. `IncentiveCredit::Producer` creates credits, so it's under IncentiveCredit |
| Value accumulation | **During generation phase** | IncentiveUserPayment.value accumulated during generation (processing state), NOT during credit creation. Avoids double-counting |
| Error handling pattern | **raise RecordNotSaved** | Use `raise ActiveRecord::RecordNotSaved.new(message, record)` for conditional rollbacks, not `ActiveRecord::Rollback` (project pattern) |

---

**Status:** READY FOR PROCESS MODELING

**Next Step:** This document captures the business knowledge of Phase 1 (already implemented). Use `@agent-process-modeler` to create PROCESS.md documenting the business processes and workflows.
