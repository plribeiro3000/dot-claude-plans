# Incentive Payment Mutations - Remove Raises Refactoring

**Status:** ✅ COMPLETED

## Overview
Refactor IncentiveCampaign methods to remove `raise ArgumentError` usage and follow Rails Way pattern with `errors.add` + return false.

## Problem Statement
Current implementation uses multiple `raise ArgumentError` for validation in model methods. This causes:
- Web flows: 500 errors, broken user experience
- Sidekiq workers: Infinite retries, potential duplications
- Architecture: Exceptions used for flow control (anti-pattern)

## Philosophy
**Exceptions should ONLY be used when "it's better to break the system than continue".**

For validation and expected failures:
- ✅ Use `errors.add` + return false
- ✅ Let callers check return value
- ✅ Workers mark as error state instead of raising

## Affected Methods

### IncentiveCampaign (app/models/incentive_campaign.rb)
1. `increment_released_budget!` (lines 50-59) - 3 raises
2. `increment_budget!` (lines 63-74) - 3 raises
3. `available_budget?` (lines 79-88) - 3 raises
4. `can_release_payment_with_lock!` (lines 89-98) - 3 raises
5. `consume_budget!` (lines 102-120) - 4 raises + inconsistent rescue

## Affected Callers

### CampaignFund.approve_by
- **File**: app/models/campaign_fund.rb:50
- **Context**: Web flow (GraphQL mutation)
- **Change**: Verify return value, add error, rollback transaction

### ApprovalFinalizer
- **File**: app/workers/incentive_payment/approval_finalizer.rb:28,35
- **Context**: Background worker
- **Change**: Check return values, mark payment as error instead of raising

### IncentivePayment & Policy
- **Files**: Multiple
- **Context**: Validations and policies
- **Change**: Already handle boolean returns (minimal impact)

## Success Criteria
1. All `raise ArgumentError` removed from IncentiveCampaign
2. All callers properly check return values
3. Workers mark errors instead of raising
4. All tests passing
5. No regression in behavior

## Risks
- Large refactoring touching critical payment flow
- Need to ensure all callers are updated
- Worker behavior changes (no more retries on validation errors)

## Notes
- Keep custom PaymentReleaseException for critical DB/infrastructure failures
- Remove inconsistent bang naming (consume_budget! returns false)
- Follow code-style-rules.md (150 columns, no unnecessary breaks)
