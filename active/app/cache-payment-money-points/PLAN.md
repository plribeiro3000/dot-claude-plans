# Plan: Cache money and points on Payment

## Problem

`Payment#money` and `Payment#points` are computed at runtime via N+1:
- `user_payments.sum(&:billable_money)` — 1 SQL query per payment
- `user_payments.sum(&:points)` — 1 SQL query per payment

With 9 payments per page = 18 extra queries per request. Causing timeouts for users with large datasets.

## Solution

Cache the computed values as columns on the `payments` table. Update the cache at the end of the processing pipeline, where it already happens today.

---

## Step 1 — Migration

Generate migration to add `money` and `points` columns to `payments`:

```
rails generate migration AddMoneyAndPointsToPayments money:decimal points:decimal
```

Precision and scale must match `user_payments`:
```ruby
add_column :payments, :money, :decimal, precision: 28, scale: 6, default: '0.0', null: false
add_column :payments, :points, :decimal, precision: 28, scale: 6, default: '0.0', null: false
```

---

## Step 2 — Create Payment::Finalizer worker

Pattern reference: `RewardPayment::Finalizer` and `DealIncentive::Finalizer`.

The Consumer handles individual items. Aggregate logic and state transition belong in a dedicated Finalizer, called once when all consumers are done.

**New file:** `app/workers/payment/finalizer.rb`

```ruby
# frozen_string_literal: true

class Payment < ApplicationRecord
  class Finalizer < ApplicationWorker
    sidekiq_options queue: :payment_processing

    def perform(payment_id)
      payment = Payment.with_uncached_connection { Payment.find(payment_id) }

      cached_money  = UserPayment.with_uncached_connection { payment.user_payments.sum(:billable_money) }
      cached_points = UserPayment.with_uncached_connection { payment.user_payments.sum(:points) }
      Payment.with_uncached_connection { payment.update_columns(money: cached_money, points: cached_points) }

      Payment.with_uncached_connection { payment.finish_process! }
      Lock.delete(payment.lock_key)
    end
  end
end
```

**Update `app/workers/payment/consumer.rb`** — replace the finish block with a Finalizer call:

```ruby
# Before:
return unless payment.computation.done?

Payment.with_uncached_connection { payment.finish_process! }
Lock.delete(payment.lock_key)

# After:
return unless payment.computation.done?

Payment::Finalizer.perform_async(payment_id)
```

The Consumer no longer owns the lock or the state transition — that responsibility moves to the Finalizer.

---

## Step 3 — Update Payment model methods

**File:** `app/models/payment.rb`

Replace the N+1 methods with simple attribute reads:

```ruby
# Before:
def money
  @money ||= user_payments.sum(&:billable_money)
end

def points
  @points ||= user_payments.sum(&:points)
end

# After: columns exist on the table — no method needed
# (ActiveRecord reads them automatically as attributes)
```

Remove both instance methods. ActiveRecord will serve the column values directly.

---

## Step 4 — Backfill (Rails console)

Run directly in the Rails console on each environment after the migration is deployed. Idempotent — running again just overwrites with the same values.

```ruby
Payment.find_each do |payment|
  money  = payment.user_payments.sum(:billable_money)
  points = payment.user_payments.sum(:points)
  payment.update_columns(money: money, points: points)
end
```

- `find_each` — batches of 1000, no memory spike
- SQL `SUM` — no Ruby enumeration
- `update_columns` — skips callbacks

---

## Files to change

| File | Change |
|------|--------|
| `db/migrate/<timestamp>_add_money_and_points_to_payments.rb` | New migration |
| `app/workers/payment/finalizer.rb` | New — aggregate + `finish_process!` + lock release |
| `app/workers/payment/consumer.rb` | Replace finish block with `Payment::Finalizer.perform_async` |
| `app/models/payment.rb` | Remove `money` and `points` instance methods |

## Out of scope

- No change to GraphQL type — `money` and `points` fields already exist and map by name
- No change to frontend
- No need to change `Payment::Producer` (it already calls `user_payments.destroy_all` on reprocess — the cache will be reset to 0 by the next run of Consumer)
