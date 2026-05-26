# Implemented Features - Incentive System PRs

> Factual documentation of what was implemented across PRs 4399, 4514, 4609, 4659.
> No recommendations or improvements - only description of existing implementations.

**Date:** 2026-01-16
**PRs Analyzed:** 4399, 4514, 4609, 4659

---

## Summary by PR

| PR | Status | Focus |
|----|--------|-------|
| 4399 | CLOSED | Account Movement / Points Program (separate concept) |
| 4514 | CLOSED | Campaign Fund, IncentivePayment, Order creation |
| 4609 | CLOSED | Order integration services, workers, email |
| 4659 | OPEN | Refactored model names, consolidated workers |

---

## 1. Incentive Order Management

### 1.1 IncentiveOrder Model

**Location:** `app/models/incentive_order.rb`

**Attributes:**
- `incentive_campaign_account_id` (required)
- `owner_email` (required, email format validated)
- `status` (integer, state machine)
- `voucher_sent_at` (datetime, nullable)

**State Machine:**
```
initial (0) → partner_processing (1) → final (2)
```

**Events:**
- `partner_process` - transitions initial → partner_processing
- `finish` - transitions partner_processing → final

**Associations:**
- `belongs_to :campaign_account`
- `has_many :order_items` (IncentiveOrderItem)

**Methods:**
- `total_value` - sums all order_items values

**Scopes:**
- `for_campaign_account(id)`
- `for_owner_email(email)`

### 1.2 IncentiveOrderItem Model

**Location:** `app/models/incentive_order_item.rb`

**Attributes:**
- `incentive_order_id` (required)
- `incentive_catalogation_id` (required)
- `value` (required, decimal)
- `fee` (required, decimal)
- `status` (integer, state machine)
- `partner_status_id` (integer, from partner)
- `partner_delivery_date` (datetime, from partner)
- `synchronized` (boolean, default false)

**State Machine:**
```
pending (0) → success (1)
           → cancelled (2)
```

**Events:**
- `deliver` - transitions pending → success (triggers `approve_transaction` callback)
- `cancel` - transitions pending → cancelled (triggers `cancel_transaction` callback)

**Associations:**
- `belongs_to :order` (IncentiveOrder)
- `belongs_to :catalogation` (IncentiveCatalogation)
- `has_one :debit_transaction` (IncentiveDebit)

**Callbacks:**
- `before_validation on: :create` - automatically builds IncentiveDebit
- `after_transition on: :deliver` - calls `approve_transaction`
- `after_transition on: :cancel` - calls `cancel_transaction`

**Methods:**
- `composite_sku` - generates SKU format: `"{catalogation.sku}V{value.to_i}"`
- `approve_transaction` - approves the debit if processing
- `cancel_transaction` - cancels the debit if pending
- `delivered?` - returns true if status is success
- `synchronize_partner_status!(partner_status)` - updates partner fields

### 1.3 Order Creation Flow

**GraphQL Mutation:** `CreateIncentiveOrderGraphqlMutation`

**Arguments:**
- `campaign_account_id` (ID, required)
- `items` (Array of IncentiveOrderItemInputGraphqlType, required)
- `owner_email` (String, required)

**Item Input:**
- `incentive_catalogation_id` (ID, required)
- `value` (Float, required)
- `fee` (Float, required)

**Flow:**
1. Creates IncentiveOrder with nested order_items (accepts_nested_attributes_for)
2. Validates via IncentiveOrderPolicy
3. On save success, enqueues `IncentiveOrder::Producer` worker
4. Returns the created order

**Policy Validation (IncentiveOrderPolicy):**
- Checks `campaign_account.balance > 0`
- Checks `campaign_account.balance >= order.total_value`
- Requires permission `incentive_order_creation`

---

## 2. Transaction System

### 2.1 IncentiveTransaction Base

**Location:** `app/models/incentive_transaction.rb`

**Types (STI):**
- `IncentiveCredit` - for commission payments
- `IncentiveDebit` - for order redemptions

**Attributes:**
- `company_id` (required)
- `incentive_campaign_account_id` (required)
- `value` (required, decimal)
- `status` (integer, state machine)
- `type` (required, STI)
- `user_commission_id` (required for Credit)
- `incentive_order_item_id` (required for Debit)
- `incentive_payment_id` (optional)

**Scopes:**
- `for_campaign(campaign_id)`
- `for_campaign_account(account_id)`
- `for_company(company_id)`
- `for_order_item(order_item_id)`
- `for_status(status)`
- `for_type(type)`
- `for_user_commission(user_commission_id)`

### 2.2 IncentiveCredit

**Location:** `app/models/incentive_credit.rb`

**State Machine:**
```
pending (0) → final (1)
```

**Events:**
- `approve` - transitions pending → final

**Methods:**
- `approve_and_update_balance!` - within transaction: approves and increments campaign_account.balance

**Associations:**
- `belongs_to :user_commission` (required)

### 2.3 IncentiveDebit

**Location:** `app/models/incentive_debit.rb`

**State Machine:**
```
pending (2) → processing (3) → final (4)
           → cancelled (5)
```

**Events:**
- `process` - transitions pending/processing → processing
- `approve` - transitions processing → final
- `cancel` - transitions pending → cancelled

**Methods:**
- `approve_and_update_balance!` - within transaction: approves and decrements campaign_account.balance

**Associations:**
- `belongs_to :order_item` (IncentiveOrderItem, required)

### 2.4 Debit Auto-Creation

When an IncentiveOrderItem is created, a `before_validation` callback automatically builds the IncentiveDebit:

```ruby
build_debit_transaction(
  company_id: order.campaign_account.company_id,
  incentive_campaign_account_id: order.campaign_account_id,
  value: value
)
```

---

## 3. Partner Integration (Incentivale)

### 3.1 Configuration

**Location:** `lib/application_configuration.rb`

**Environment Variables:**
- `INCENTIVALE_API_BASE_URL` - API base URL (required, raises error if missing)
- `INCENTIVALE_USERNAME` - OAuth username (required)
- `INCENTIVALE_PASSWORD` - OAuth password (required)
- `INCENTIVALE_CAMPAIGN_TOKEN` - Campaign token (required)
- `INCENTIVALE_ORDER_EMAIL` - Email for order notifications (required)
- `MAILER_EMAIL_FROM` - Mailer from address (required)

### 3.2 Token Service

**Location:** `app/services/incentivale/token_service.rb`

**Purpose:** Obtains and caches OAuth access token

**Flow:**
1. Check Rails cache for existing token
2. If cached, return immediately
3. Otherwise, POST to `/oauth/token` with username/password/grant_type
4. Parse response, extract `access_token`
5. Cache token for 50 minutes (TOKEN_TTL)
6. Return token

**Cache Key:** `incentivale:access_token`

**HTTP Configuration:**
- Uses SSL when scheme is https
- Timeout values from `payroll_open_timeout` and `payroll_read_timeout`

### 3.3 API Endpoints Used

**Base URL:** Configured via `INCENTIVALE_API_BASE_URL`

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/oauth/token` | POST | Get access token |
| `/api/v3/ExistRequest` | GET | Check if order exists at partner |
| `/api/v3/AddResquest` | POST | Create order at partner |
| `/api/v3/FindTracking` | GET | Get order status |

### 3.4 API Request Format

**ExistRequest (GET):**
```
/api/v3/ExistRequest?Token={campaign_token}&CodRequest={order_id}
```

**AddResquest (POST):**
```
Content-Type: application/x-www-form-urlencoded
Authorization: Bearer {access_token}

Body:
- Token: campaign_token
- CodRequest: order.id
- SKU: order_item.composite_sku
- AmountPremium: 1
- Email: incentivale_order_email
- Name: (empty)
- CPF_CNPJ: (empty)
- Address: (empty)
- AddressNumber: (empty)
- Complement: (empty)
- District: (empty)
- City: (empty)
- State: (empty)
- CEP: (empty)
- PhoneContact: (empty)
```

**FindTracking (GET):**
```
/api/v3/FindTracking?Token={campaign_token}&CodRequest={order_id}
```

### 3.5 Partner Status IDs

| StatusId | Meaning | Action |
|----------|---------|--------|
| 3 | Delivered | Transition to success, send voucher email |
| 7 | Cancelled | Transition to cancelled |

---

## 4. Async Workers

### 4.1 IncentiveOrder::Producer

**Location:** `app/workers/incentive_order/producer.rb`

**Queue:** `incentive_orders`

**Purpose:** Dispatches each order item to Consumer

**Input:** `incentive_order_id`

**Flow:**
1. Find IncentiveOrder
2. Get company_id from campaign_account
3. Get all order_item IDs
4. For each item_id, enqueue `Consumer.with_company_id(company_id).dynamic_perform_async(item_id)`

### 4.2 IncentiveOrder::Consumer

**Location:** `app/workers/incentive_order/consumer.rb`

**Queue:** `incentive_orders` (TenantWorker)

**Purpose:** Creates order at partner API

**Input:** `order_item_id`

**Flow:**
1. Find IncentiveOrderItem
2. Get order and campaign token
3. Call ExistRequest to check if order already exists
4. If exists (Success=true), return (idempotency)
5. If not exists, call AddResquest to create order
6. If creation successful, call `order.partner_process!`
7. If creation fails, re-enqueue Consumer in 5 minutes (retry)

### 4.3 IncentiveOrder::StatusCheckProducer

**Location:** `app/workers/incentive_order/status_check_producer.rb`

**Queue:** `incentive_orders` (ApplicationWorker)

**Purpose:** Finds all pending order items and dispatches status check

**Flow:**
1. Query all IncentiveOrderItem where status = pending
2. Get all IDs
3. Use `Sidekiq::Client.push_bulk` to enqueue all StatusCheckConsumer jobs

### 4.4 IncentiveOrder::StatusCheckConsumer

**Location:** `app/workers/incentive_order/status_check_consumer.rb`

**Queue:** `incentive_orders` (TenantWorker)

**Purpose:** Checks order status with partner and updates local state

**Input:** `order_item_id`

**Flow:**
1. Find IncentiveOrderItem
2. Skip if not pending
3. Get order and call FindTracking API
4. Parse response, get first item from `ListLote`
5. **If StatusId = 3 (delivered):**
   - Call `order_item.deliver!`
   - Call `order_item.synchronize_partner_status!`
   - If delivered, send voucher email with `CodeCard`
6. **If StatusId = 7 (cancelled):**
   - Call `order_item.cancel!`
   - Call `order_item.synchronize_partner_status!`

---

## 5. Email Delivery

### 5.1 IncentiveOrderMailer

**Location:** `app/mailers/incentive_order_mailer.rb`

**Method:** `voucher_email(item_order_id, voucher_code)`

**Data Loaded:**
- `@order_item` = IncentiveOrderItem
- `@order` = IncentiveOrder
- `@catalogation` = IncentiveCatalogation
- `@item` = IncentiveItem
- `@voucher_code` = code from partner API
- `@recipient_email` = order.owner_email

**Delivery:** `deliver_later` (async via ActionMailer)

### 5.2 Email Templates

**HTML:** `app/views/incentive_order_mailer/voucher_email.html.erb`
**Text:** `app/views/incentive_order_mailer/voucher_email.text.erb`

**Content:**
- Header with title
- Greeting message
- Product information (item name, order number)
- Voucher code in highlighted box
- Instructions
- Footer

**I18n Keys Used:**
- `incentive_order_mailer.voucher_email.subject`
- `incentive_order_mailer.voucher_email.title`
- `incentive_order_mailer.voucher_email.greeting`
- `incentive_order_mailer.voucher_email.message`
- `incentive_order_mailer.voucher_email.product`
- `incentive_order_mailer.voucher_email.order_number`
- `incentive_order_mailer.voucher_email.voucher_code`
- `incentive_order_mailer.voucher_email.instructions`
- `incentive_order_mailer.voucher_email.footer`

---

## 6. GraphQL API

### 6.1 Queries

**incentive_orders:**
- Resolver: `IncentiveOrdersGraphqlResolver`
- Scope: `IncentiveOrderScope`
- Order: `id: :desc`
- Type: `IncentiveOrderGraphqlType.connection_type`

### 6.2 Mutations

**create_incentive_order:**
- Mutation: `CreateIncentiveOrderGraphqlMutation`
- Arguments: campaign_account_id, items, owner_email
- Type: `[IncentiveOrderGraphqlType]`

### 6.3 Types

**IncentiveOrderGraphqlType:**
- Fields: actions, campaign_account, campaign_account_id, created_at, id, items, owner_email, updated_at, value
- `value` computed as sum of order_items values

**IncentiveOrderItemGraphqlType:**
- Fields: catalogation, catalogation_id, created_at, date_delivery, fee, id, incentive_transaction, order, order_id, partner_status_id, status, updated_at, value

**IncentiveOrderItemInputGraphqlType:**
- Arguments: fee, incentive_catalogation_id, value

---

## 7. Database Schema

### 7.1 incentive_orders Table

```sql
CREATE TABLE incentive_orders (
  id bigserial PRIMARY KEY,
  created_at timestamp NOT NULL,
  incentive_campaign_account_id bigint NOT NULL REFERENCES incentive_campaign_accounts,
  integration_status integer NOT NULL DEFAULT 0,
  owner_email varchar NOT NULL DEFAULT '',
  status integer NOT NULL DEFAULT 0,
  updated_at timestamp NOT NULL,
  voucher_sent_at timestamp
);

CREATE INDEX index_incentive_orders_on_incentive_campaign_account_id ON incentive_orders(incentive_campaign_account_id);
CREATE INDEX index_incentive_orders_on_integration_status ON incentive_orders(integration_status);
```

### 7.2 incentive_order_items Table

```sql
CREATE TABLE incentive_order_items (
  id bigserial PRIMARY KEY,
  created_at timestamp NOT NULL,
  fee decimal(10,2) NOT NULL DEFAULT 0.0,
  incentive_catalogation_id bigint NOT NULL REFERENCES incentive_catalogations,
  incentive_order_id bigint NOT NULL REFERENCES incentive_orders,
  partner_delivery_date timestamp,
  partner_status_id integer,
  status integer NOT NULL DEFAULT 0,
  synchronized boolean NOT NULL DEFAULT false,
  updated_at timestamp NOT NULL,
  value decimal(10,2) NOT NULL DEFAULT 0.0
);

CREATE UNIQUE INDEX ON incentive_order_items(incentive_order_id, incentive_catalogation_id);
```

### 7.3 incentive_transactions Updates

Added column:
- `incentive_order_item_id` bigint REFERENCES incentive_order_items

Removed column:
- `incentive_item_order_id`

---

## 8. Sidekiq Configuration

### 8.1 Queue Definition

**File:** `config/sidekiq_user.yml`

Added queue: `[incentive_orders, 10]`

### 8.2 HireFire Configuration

**File:** `config/initializers/hire_fire.rb`

Added `:incentive_orders` to managed queues

---

## 9. SKU Format

**Format:** `{catalogation.sku}V{value.to_i}`

**Examples:**
- catalogation.sku = "GIFT100", value = 50.25 → "GIFT100V50"
- catalogation.sku = "AMAZON", value = 100.00 → "AMAZONV100"

**Implementation:** `IncentiveOrderItem#composite_sku`

---

## 10. Balance Management

### 10.1 Policy Check (On Order Creation)

```ruby
# IncentiveOrderPolicy#create?
return false if record.campaign_account.balance.zero?
return false if record.campaign_account.balance.negative?
return false if record.campaign_account.balance < record.total_value
```

### 10.2 Balance Update Methods

**IncentiveCredit#approve_and_update_balance!:**
```ruby
transaction do
  approve!
  campaign_account.increment!(:balance, value)
end
```

**IncentiveDebit#approve_and_update_balance!:**
```ruby
transaction do
  approve!
  campaign_account.decrement!(:balance, value)
end
```

### 10.3 When Balance is Updated

- Credit: When `approve_and_update_balance!` is called (not automatic)
- Debit: When `approve_and_update_balance!` is called (triggered by OrderItem state machine callback `approve_transaction`)

---

## 11. PR 4399 - Account Movement (Separate Concept)

**Note:** This PR implements a **different concept** - "Points Program" - not directly related to Incentive Orders.

### 11.1 AccountMovement Model

**Location:** `app/models/account_movement.rb`

**Types (STI):**
- `CreditTransaction`
- `DebitTransaction`

**Attributes:**
- `company_id` (required)
- `user_id` (required)
- `type` (required)
- `value` (required)

**Associations:**
- `belongs_to :company`
- `belongs_to :user`

**Scopes:**
- `for_company(company_id)`
- `for_type(type)`
- `for_user(user_id)`

---

## 12. State Machine Diagrams

State machine diagrams are generated and stored at:
- `docs/state_machines/IncentiveOrder_status.png`
- `docs/state_machines/IncentiveOrderItem_status.png`

---

## 13. Test Coverage

### 13.1 Model Specs

**IncentiveOrder:**
- validates campaign_account_id presence
- validates owner_email presence
- accepts nested attributes for order_items

**IncentiveOrderItem:**
- validates fee, incentive_catalogation_id, incentive_order_id, value presence
- enumerize status (pending, success, cancelled)

**IncentiveDebit:**
- enumerize status (pending, processing, final, cancelled)
- belongs_to order_item

**IncentiveCredit:**
- enumerize status (pending, final)
- belongs_to user_commission

---

## 14. Migration History

| Migration | Description |
|-----------|-------------|
| 20251212171426 | Add owner_email to incentive_orders |
| 20251212171929 | Add status to incentive_item_orders |
| 20251212172447 | Drop unique index on incentive_orders uid |
| 20251212172539 | Drop uid on incentive_orders |
| 20251212180042 | Add voucher_sent_at to incentive_item_orders |
| 20251212181507 | Create incentive_order_items table |
| 20251212182100 | Remove foreign keys from incentive_item_orders |
| 20251212182101 | Drop incentive_item_order_id on incentive_transactions |
| 20251212182148 | Drop incentive_item_orders table |
| 20251212182917 | Add unique index on incentive_order_items |
| 20251215172130 | Add incentive_order_item_id on incentive_transactions |
| 20251215172638 | Add index on incentive_order_item_id |
| 20251215173258 | Add foreign key for incentive_order_items |
| 20251215173730 | Validate foreign key |
| 20251216171647 | Add index on incentive_order_item_id |
| 20251219143556 | Add status to incentive_order |

---

## 15. Key Implementation Decisions

### 15.1 Naming Convention
- Renamed `IncentiveItemOrder` → `IncentiveOrderItem` (PR 4659)
- Renamed `item_orders` association → `order_items`

### 15.2 Order ID as Partner Reference
- Uses `order.id` as `CodRequest` for partner API
- No UUID - uses sequential integer ID

### 15.3 Debit Creation Timing
- IncentiveDebit created automatically via `before_validation` on IncentiveOrderItem
- Debit is in `pending` state when created

### 15.4 Balance Update Timing
- Balance decremented when OrderItem transitions to `success` (via callback chain)
- OrderItem.deliver! → approve_transaction → debit.approve! (but doesn't call approve_and_update_balance!)
- **Note:** The `approve_transaction` callback calls `debit_transaction.approve!`, not `approve_and_update_balance!`

### 15.5 Retry Strategy
- Consumer worker retries in 5 minutes if partner API fails
- Uses `dynamic_perform_in(5.minutes, order_item_id)`

### 15.6 Idempotency
- Consumer checks `ExistRequest` before creating order at partner
- If order exists, skips creation

### 15.7 Status Polling
- `StatusCheckProducer` runs periodically (scheduled job)
- Queries all pending OrderItems and dispatches StatusCheckConsumer

---

**Status:** DOCUMENTATION COMPLETE

