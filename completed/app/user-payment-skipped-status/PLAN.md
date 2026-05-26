# Plan: Add Skipped Integration Status for User Payments

## Overview

**Feature:** user-payment-skipped-status
**Type:** Multi-project (app + app-webclient)
**Status:** ✅ Completed
**Related:** [payment-payroll-integration](../../../completed/payment-payroll-integration/PLAN.md) (completed)

## Problem

The integration report page was displaying many User Payment records without payroll request logs. The initial assumption was that payroll requests were not being returned, but the actual problem was different:

1. User Payments with `billable_money = 0` were being marked as `success` instead of a dedicated status
2. These records had no actual integration logs because they were never sent to the payroll system
3. There was no way to filter these records separately from actual successful integrations
4. This made the report confusing - mixing records that were truly integrated with those that were skipped

## Root Cause

In `check_producer.rb`, user payments with zero billable money were being marked as `success`:
```ruby
Payment.with_uncached_connection { payment.user_payments.where(billable_money: 0).update_all(integration_status: :success) }
```

This was semantically incorrect - these records were not successfully integrated, they were intentionally skipped.

## Solution

Add a new `skipped` integration status to properly categorize User Payments that were not sent to the payroll system because they had no billable amount.

### Backend (app) - hotfix/3.4.2
- Added `skipped: 3` to the `integration_status` enum in `UserPayment` model
- Added `skip` event to the state machine
- Updated `check_producer.rb` to use `:skipped` instead of `:success`
- Added enumerize test
- Regenerated state machine diagram
- PR: https://github.com/4shark/app/pull/4712

### Frontend (app-webclient) - hotfix/1.250.1
- Added translations for "skipped" status (pt-BR, en, es)
- Added filter option for skipped status
- Added badge styling for skipped status
- Fixed optional chaining to use early return pattern
- Fixed duration display to show seconds directly
- PR: https://github.com/4shark/app-webclient/pull/5828

### Data Migration
```sql
UPDATE user_payments SET integration_status = 3 WHERE billable_money = 0 AND integration_status = 1;
```

## Outcome

- Users can now properly filter and understand which payments were actually integrated vs skipped
- The report accurately reflects the integration status of each record
- Records with zero billable money are correctly categorized

---

**Created:** 2026-01-07
**Completed:** 2026-01-07
