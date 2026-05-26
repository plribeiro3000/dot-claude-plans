# PLAN — Complete Incentive System Implementation

## Current Situation

- **Architecture:** Multi-project (app: Ruby on Rails backend, app-webclient: Angular frontend)
- **Impacted components:** Incentive Campaign, Payment, Credit/Debit, Order, Partner Integration, Employee Portal
- **Phase 1 (Budget → Released Budget):** Implemented with known issues (4 pending fixes, 2 done via PR #4792)
- **Phase 2 (Released Budget → Consumed Budget):** Not implemented. PRs 4399/4514/4609/4659 attempted it but were closed/rejected due to architectural flaws
- **Supporting documentation:** KNOWLEDGE.md, PROCESS.md, DOMAIN.md (Phase 1 domain model), KNOWLEDGE-PHASE2.md, ANALYSIS.md (Phase 2 research)

## Objective / Target State

Complete the incentive money lifecycle so employees can redeem their balance for vouchers:

1. Fix remaining Phase 1 issues that block Phase 2
2. Implement voucher redemption (Consumed Budget phase)
3. Integrate with Incentivale as first partner
4. Build employee-facing redemption portal

**Success criteria:**
- Employee can browse available items, place an order, and receive a voucher via email
- `consumed_budget` counter accurately tracks money that left 4Shark
- Budget invariants hold: `consumed_budget ≤ released_budget ≤ budget`
- Partner failures don't cause financial inconsistencies

## Problem / New Feature

### Phase 1 Issues (4 pending)

| # | Issue | Project | Severity | Blocks Phase 2? |
|---|-------|---------|----------|-----------------|
| 1 | Redis Lock without TTL — deadlock risk | app | CRITICAL | Yes |
| 2 | Frontend allows payment approval without budget check | app-webclient | CRITICAL | No |
| 3 | GraphQL queries missing budget fields (blocks #2) | app + app-webclient | CRITICAL | No |
| 4 | Plan-Campaign association editable after approval | app + app-webclient | HIGH | No |

### Phase 2 Gap

Employees have balance in their Incentive Campaign Account but cannot use it. The money lifecycle stops at "Released Budget" — the "Consumed Budget" phase is missing entirely.

### Architectural Flaw in Previous PRs

The rejected PRs deducted employee balance at order creation, before partner confirmation. This means:
- If partner fails, employee loses money with no automatic recovery
- `consumed_budget` was never incremented — campaign accounting is wrong
- No balance reservation mechanism — race conditions possible

The correct flow (defined in KNOWLEDGE-PHASE2.md) is:
1. Employee places order → partner API called synchronously
2. Partner confirms reception → balance deducted, debit created
3. Partner delivers voucher (async polling) → `consumed_budget` incremented, email sent
4. Partner fails → manual refund process (new Incentive Credit via script)

## Multi-Partner Architecture

4Shark operates in 9 Latin American countries. First partner is Incentivale (Brazil only). A potential partner in Colombia has been identified.

| Principle | Description |
|-----------|-------------|
| Partner-agnostic schema | Database columns/tables don't reference specific partners |
| Incentive Item as abstraction | 4Shark's curated catalog (30-50 items), not partner's full catalog (5000+) |
| Partner in code only | Partner-specific logic in services, not models |
| Configuration per partner | Environment variables for credentials |

## Technical Constraints

| Constraint | Description |
|------------|-------------|
| Database as source of truth | Always query DB for balance, never cache. Use transactions for atomicity |
| Sync + async pattern | Order creation: synchronous (employee waits). Voucher delivery: async (polling) |
| Voucher security | Codes not stored in DB. One-time delivery via email. Lost voucher = manual process |
| Concurrency | Database locks for critical operations. Redis locks with TTL for distributed locking |
| Counters only increment | budget, released_budget, consumed_budget never decrease (audit trail) |

## Design Decisions Already Made

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Credit state | Final-only (no pending) | Employees only see balance after approval. Implemented in PR #4792 |
| consumed_budget timing | On voucher delivery (partner status = 3) | Not on order creation, not on balance debit |
| Error handling | Manual refund via script (new Credit) | Automating refunds introduces financial risk. Rare events justify manual oversight |
| Partner API flow | Sync order creation, async delivery polling | Employee gets immediate feedback, delivery confirmed via scheduled job |
| Catalogation management | Internal (4Shark team), no client UI | Decision from Phase 1 analysis |

## Current Implementation Status

### Fully Implemented (Phase 1)
- Campaign Fund (deposit money)
- Incentive Payment state machine
- Incentive Credit creation (as final)
- Budget and Released Budget tracking
- Campaign Account balance management
- Plan → Campaign association
- Budget validation synchronous during approval (PR #4792)
- Worker flow: generation → approval → credit creation (PR #4792)

### Partially Implemented / Needs Fixes
- Budget validation on payment approval: backend OK, frontend missing
- Campaign CRUD: only list/view, no create/update (but 4Shark manages internally — acceptable)
- Plan-Campaign immutability after approval: not validated
- Redis Lock TTL: currently no TTL — deadlock risk

### Not Implemented (Phase 2)
- Consumed Budget increment
- Incentive Debit
- Incentive Order + Order Item
- Partner integration (Incentivale services exist in rejected PRs — reusable)
- Voucher delivery (email templates exist in rejected PRs — reusable)
- Employee redemption UI
- Order history UI

## Entity Relationships (Phase 1 + Phase 2 Combined)

```
Client
  └── has many ──► Incentive Campaign
                        │
                        ├── has many ──► Campaign Fund
                        │
                        ├── has many ──► Incentive Payment
                        │                     │
                        │                     └── generates ──► Incentive Credit (many)
                        │
                        ├── has many ──► Incentive Campaign Account (one per employee)
                        │                     │
                        │                     ├── has ──► balance
                        │                     │
                        │                     ├── has many ──► Incentive Transaction
                        │                     │                     ├── Credit
                        │                     │                     └── Debit
                        │                     │
                        │                     └── has many ──► Incentive Order
                        │                                           │
                        │                                           └── has many ──► Order Item
                        │
                        └── has many ──► Incentive Catalogation
                                              │
                                              └── belongs to ──► Incentive Item

Plan ──(optional)──► Incentive Campaign
```

## Reusable Components from Rejected PRs

These components from PR 4609 can be reused as-is:

| Component | Location | Notes |
|-----------|----------|-------|
| Incentivale Token Service | `app/services/incentivale/token_service.rb` | OAuth2 with 50min cache |
| Incentivale Order Creation | `app/services/incentivale/order_creation_service.rb` | Partner API call |
| Incentivale Order Status | `app/services/incentivale/order_status_service.rb` | Status polling |
| Incentivale Order Existence | `app/services/incentivale/order_existence_service.rb` | Idempotency check |
| Voucher Email Mailer | `app/mailers/incentive_order_mailer.rb` | HTML + text templates |
| Email Templates | `app/views/incentive_order_mailer/*` | I18n ready |
| Incentivale Config | `lib/application_configuration.rb` | Environment variables |

Components that need to be **rewritten** (wrong architecture in PRs):
- IncentiveTransaction (remove after_create balance callback)
- IncentiveOrder (proper state machine, no immediate debit)
- Order creation mutation (sync partner call, no immediate balance deduction)
- Order workers (correct state transitions)

## Challenges, Difficulties and Risks

### Technical
- **Concurrency on balance**: Multiple simultaneous orders could overdraw. Database-level locking required
- **Partner API reliability**: Incentivale may be down. Need graceful degradation
- **Balance reservation vs immediate debit**: KNOWLEDGE-PHASE2.md discusses both approaches — sync partner call with immediate debit on confirmation is the chosen pattern

### Product/UX
- **Employee experience**: First time employees interact with 4Shark directly (previously only admin/client users)
- **Item availability**: No real-time stock check with partner initially (trust items are available)
- **Order tracking**: Employee needs visibility into order status (pending → delivered)

### Financial
- **Double spending prevention**: Must lock at DB level during order creation
- **Partner failure recovery**: Manual process — requires documented runbook
- **Payment cycle**: 4Shark pays partner every 15 days (cash flow consideration)

## Proposed Steps (high level)

### Step 1 — Phase 1 Fixes (app then app-webclient)

Fix remaining Phase 1 issues. Backend first because GraphQL fields must exist before frontend can use them.

**app (backend):**
1. Add TTL to Redis Lock (prevents deadlock)
2. Expose budget fields in GraphQL IncentiveCampaignType (if not already)
3. Add Plan-Campaign immutability validation in model

**app-webclient (frontend):**
4. Fetch budget fields in payment approval query
5. Show available budget and disable approve button when insufficient
6. Disable campaign field on Plan update when not draft

### Step 2 — Phase 2 Foundation (app only)

Prepare the backend for order flow without changing existing Phase 1 behavior.

1. Fix IncentiveTransaction: remove after_create balance callback (if present from PRs)
2. Implement `consume_budget!` method on IncentiveCampaign
3. Implement IncentiveOrder with state machine (pending → processing → completed / failed)
4. Implement IncentiveOrderItem with state machine (pending → success / cancelled)
5. Implement IncentiveDebit state transitions (pending → processing → final / cancelled)
6. Wire up: OrderItem delivery → Debit finalization → balance decrement → consumed_budget increment

### Step 3 — Partner Integration (app only)

Connect to Incentivale using the reusable services from PR 4609.

1. Copy/adapt Incentivale services
2. Implement order creation flow: validate → call partner sync → create debit → decrement balance
3. Implement status polling workers (Producer/Consumer pattern)
4. Implement voucher email delivery on partner delivery confirmation
5. Implement order cancellation handling (debit cancelled, manual refund)

### Step 4 — Employee Portal (app-webclient, with app GraphQL support)

Build the employee-facing UI.

**app (backend):**
1. GraphQL queries: campaigns with balance, available items per campaign, order history
2. GraphQL mutation: create order

**app-webclient (frontend):**
3. Campaign list (campaigns where employee has balance > 0)
4. Item catalog per campaign (from Incentive Catalogation)
5. Order creation flow (select item, confirm, see result)
6. Order history view (status tracking)

### Step 5 — Admin Tooling (app, optional)

Internal tools for 4Shark team. Can be deferred if Rails console is acceptable initially.

1. Incentive Item management (CRUD or bulk import)
2. Incentive Catalogation management (associate items with campaigns)
3. Order monitoring dashboard
4. Refund script template

## Incentivale API Reference

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/oauth/token` | POST | Get access token (password grant) |
| `/api/v3/ExistRequest` | GET | Check if order exists (idempotency) |
| `/api/v3/AddResquest` | POST | Create order |
| `/api/v3/FindTracking` | GET | Get order status |

**Status IDs:** 1 = Pending, 3 = Delivered, 7 = Cancelled
**SKU Format:** `{catalogation.sku}V{value.to_i}` (e.g., "GIFT100V50")
**Auth:** OAuth2 password grant, token cached 50 minutes

## Internal References

### Supporting Files (this directory)
- `KNOWLEDGE.md` — Phase 1 business knowledge and domain concepts
- `PROCESS.md` — Phase 1 business processes (4 detailed flows)
- `DOMAIN.md` — Phase 1 domain entities and relationships

### Supporting Files (app/)
- `KNOWLEDGE-PHASE2.md` — Phase 2 business knowledge (multi-partner, voucher flow, constraints)
- `ANALYSIS.md` — Factual documentation of PRs 4399/4514/4609/4659
- `phase1/BLUEPRINT.md` — Phase 1 implementation details (6 issues, 2 done, 4 pending)
- `phase2/BLUEPRINT.md` — Phase 2 implementation details (7 issues deferred from Phase 1)

### Code References
- `app/models/incentive_campaign.rb` — Campaign with budget counters
- `app/models/incentive_payment.rb` — Payment state machine
- `app/models/incentive_transaction.rb` — Base for Credit/Debit (STI)
- `app/models/incentive_credit.rb` — Credit (adds balance)
- `app/models/incentive_debit.rb` — Debit (removes balance, Phase 2)
- `app/models/incentive_order.rb` — Order (exists from PRs, needs rewrite)
- `app/models/incentive_order_item.rb` — Order item (exists from PRs, needs rewrite)
- `app/models/lock.rb` — Redis lock (needs TTL fix)
- `app/workers/incentive_credit/` — Credit workers (from PR #4792)
- `app/services/incentivale/` — Partner services (from PR 4609, reusable)

---

**Question:** Which option do you prefer to follow?

This plan has a single approach (5 sequential steps). The main decision point is:

- **APPROVED: Full plan** — Execute all 5 steps in order
- **APPROVED: Steps 1-3 only** — Fix Phase 1 + build backend for Phase 2, defer employee portal
