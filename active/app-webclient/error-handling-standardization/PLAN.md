# Error Handling Standardization

## Overview

This plan addresses two related error handling issues in the codebase:
1. **Unsafe access** to `err.errors[0].extensions` without validation
2. **Missing error callbacks** in subscribe calls

---

## Problem 1: Unsafe Error Access

### Description

The codebase accesses GraphQL error responses without validation:

```typescript
// Current pattern (unsafe)
(err) => {
  this.parseErrors(err.errors[0].extensions);
}
```

If the backend returns an error in a different format (network error, timeout, 500 generic error), `err.errors` may be `undefined` or an empty array, causing:

```
Cannot read property 'extensions' of undefined
```

### Scope

- **84 files affected**
- Pattern: `err.errors[0].extensions` or `err.errors[0]` without prior validation

### Expected Behavior

Before accessing `err.errors[0].extensions`, the code must validate:
1. `err.errors` exists
2. `err.errors` is an array with at least one element
3. `err.errors[0].extensions` exists

If any of these conditions fail, the error should be handled gracefully (show generic error message or log the unexpected format).

### Proposed Solutions

#### Option A: Explicit validation at each call site

```typescript
(err) => {
  if (err.errors && err.errors.length > 0 && err.errors[0].extensions) {
    this.parseErrors(err.errors[0].extensions);
  } else {
    // Handle unexpected error format
    console.error('Unexpected error format:', err);
  }
}
```

**Pros**: Clear, explicit
**Cons**: Verbose, repeated in 84 places

#### Option B: Centralized helper function (Recommended)

Create a utility function in a shared location:

```typescript
// src/app/shared/utils/error-utils.ts
export function getGraphQLErrorExtensions(err: any): any | null {
  if (err && Array.isArray(err.errors) && err.errors.length > 0 && err.errors[0].extensions) {
    return err.errors[0].extensions;
  }
  return null;
}
```

Usage:
```typescript
(err) => {
  const extensions = getGraphQLErrorExtensions(err);
  if (extensions) {
    this.parseErrors(extensions);
  }
}
```

**Pros**: DRY, centralized, easy to maintain
**Cons**: Requires creating new utility file

#### Option C: Extend parseErrors to handle validation

Modify each component's `parseErrors` method to accept the full error object and handle validation internally:

```typescript
private parseErrors(err: any) {
  if (!err || !Array.isArray(err.errors) || !err.errors.length || !err.errors[0].extensions) {
    return;
  }
  const errorsExtensions = err.errors[0].extensions;
  // existing logic
}
```

**Pros**: Minimal change at call sites
**Cons**: Still duplicated in each component

### Recommendation

**Option B (Centralized helper function)** is recommended because:
- Single source of truth for error format handling
- Easy to update if backend error format changes
- Can add logging/monitoring in one place
- Reduces code duplication

---

## Problem 2: Missing Error Callbacks

### Description

Many subscribe calls don't have error callbacks, causing silent failures:

```typescript
// Current pattern (no error handling)
this.service.mutation(...).subscribe(() => {
  this.showMessage('Success', true);
});
// If mutation fails: nothing happens, user sees no feedback
```

### Impact Levels

| Type | Impact | Example |
|------|--------|---------|
| Mutations (user actions) | **High** | disable/enable buttons - user clicks, nothing happens on error |
| Queries (lookups) | **Low** | loading statuses/metrics - dropdown stays empty, not critical |

### High Impact Cases Found

| File | Method | Action |
|------|--------|--------|
| redemption-incentives.component.ts:137 | disable mutation | User disables incentive, no error shown if fails |
| redemption-incentives.component.ts:155 | enable mutation | User enables incentive, no error shown if fails |

### Low Impact Cases Found

| File | Method | Description |
|------|--------|-------------|
| redemption-incentive-create.component.ts:257 | getStatuses | Loads status dropdown |
| redemption-incentive-create.component.ts:284 | getMetrics | Loads metrics dropdown |
| redemption-incentive-create.component.ts:309 | getVariables | Loads variables dropdown |

### Proposed Solution

For **high impact** mutations:
```typescript
this.service.mutation(...).subscribe(
  () => {
    this.showMessage(this.translateService.instant('success'), true);
  },
  (err) => {
    this.showMessage(this.translateService.instant('error.operation_failed'), false);
    console.error('Mutation failed:', err);
  }
);
```

For **low impact** queries (optional, for consistency):
```typescript
this.service.query(...).valueChanges.subscribe(
  (response) => { /* existing logic */ },
  (err) => {
    console.error('Query failed:', err);
    // Optionally show user-friendly message
  }
);
```

---

## Files to Update

### Problem 1: Unsafe Error Access (84 files)

<details>
<summary>Click to expand full list</summary>

1. src/app/acceptment-reason/create/acceptment-reason-create.component.ts
2. src/app/acceptment-reason/update/acceptment-reason-update.component.ts
3. src/app/calendar/create/calendar-create.component.ts
4. src/app/calendar/update/calendar-update.component.ts
5. src/app/calendar-audit/create/calendar-audit-create.component.ts
6. src/app/campaign/create/campaign-create.component.ts
7. src/app/campaign/update/campaign-update.component.ts
8. src/app/client/create/client-create.component.ts
9. src/app/client/update/client-update.component.ts
10. src/app/collaborative-deal/create/collaborative-deal-create.component.ts
11. src/app/collaborative-deal/update/collaborative-deal-update.component.ts
12. src/app/commission/create/commission-create.component.ts
13. src/app/commission/create-plan-acceptment/create-plan-acceptment.component.ts
14. src/app/commission-creation-batch/create/commission-creation-batch-create.component.ts
15. src/app/commission-indicator-audit/create/commission-indicator-audit-create.component.ts
16. src/app/commission-report-creation-batch/create/commission-report-creation-batch-create.component.ts
17. src/app/company/create/company-create.component.ts
18. src/app/company/update/company-update.component.ts
19. src/app/deal/create/deal-create.component.ts
20. src/app/deal/update/deal-update.component.ts
21. src/app/deal-incentive/clone/deal-incentive-clone.component.ts
22. src/app/deal-incentive/create/deal-incentive-create.component.ts
23. src/app/deal-incentive/update/deal-incentive-update.component.ts
24. src/app/easy-product/easy-payment/create/easy-payment-create.component.ts
25. src/app/easy-product/easy-user/create/easy-user-create.component.ts
26. src/app/easy-product/easy-variable/create/easy-variable-create.component.ts
27. src/app/easy-product/plan-slice/create/plan-slice-create.component.ts
28. src/app/easy-product/plan-slice-commission/create/plan-slice-commission-create.component.ts
29. src/app/easy-product/plan-slice-commission/reprocess/plan-slice-commission-reprocess.component.ts
30. src/app/goal/create/goal-create.component.ts
31. src/app/goal/update/goal-update.component.ts
32. src/app/group/create/group-create.component.ts
33. src/app/group/finish/group-finish.component.ts
34. src/app/group/start/group-start.component.ts
35. src/app/group/update/group-update.component.ts
36. src/app/group-audit/group-audit.component.ts
37. src/app/incentive-campaign-fund/create/incentive-campaign-fund-create.component.ts
38. src/app/indicator/create/indicator-create.component.ts
39. src/app/indicator-incentives/clone/indicator-incentive-clone.component.ts
40. src/app/indicator-incentives/create/indicator-incentive-create.component.ts
41. src/app/indicator-incentives/update/indicator-incentive-update.component.ts
42. src/app/limiter-incentives/clone/limiter-incentive-clone.component.ts
43. src/app/limiter-incentives/create/limiter-incentive-create.component.ts
44. src/app/limiter-incentives/update/limiter-incentive-update.component.ts
45. src/app/metric/create/metric-create.component.ts
46. src/app/metric/update/metric-update.component.ts
47. src/app/partial-commission/create/partial-commission-create.component.ts
48. src/app/password/password.component.ts
49. src/app/payment/create/payment-create.component.ts
50. src/app/payment/exportation/payment-exportation-create.component.ts
51. src/app/payment-type/create/payment-type-create.component.ts
52. src/app/payment-type/update/payment-type-update.component.ts
53. src/app/plan/create/plan-create.component.ts
54. src/app/plan/finish/plan-finish.component.ts
55. src/app/plan/update/plan-update.component.ts
56. src/app/plan-statement-audit/plan-statement-audit.component.ts
57. src/app/product/create/product-create.component.ts
58. src/app/product/update/product-update.component.ts
59. src/app/rankifier/clone/rankifier-clone.component.ts
60. src/app/rankifier/create/rankifier-create.component.ts
61. src/app/rankifier/update/rankifier-update.component.ts
62. src/app/rankifier-incentives/clone/rankifier-incentive-clone.component.ts
63. src/app/rankifier-incentives/create/rankifier-incentive-create.component.ts
64. src/app/rankifier-incentives/update/rankifier-incentive-update.component.ts
65. src/app/redemption-incentives/clone/redemption-incentive-clone.component.ts
66. src/app/redemption-incentives/create/redemption-incentive-create.component.ts
67. src/app/redemption-incentives/update/redemption-incentive-update.component.ts
68. src/app/responsible-audit/responsible-audit.component.ts
69. src/app/seat/demote/seat-demote.component.ts
70. src/app/seat/promote/seat-promote.component.ts
71. src/app/seat/update-parent-seat/update-parent-seat.component.ts
72. src/app/statement-audit/statement-audit.component.ts
73. src/app/status/create/status-create.component.ts
74. src/app/status/update/status-update.component.ts
75. src/app/subsidiary/create/subsidiary-create.component.ts
76. src/app/subsidiary/update/subsidiary-update.component.ts
77. src/app/user/create/user-create.component.ts
78. src/app/user/update/user-update.component.ts
79. src/app/user-audit/user-audit.component.ts
80. src/app/user-history/create/user-history-create.component.ts
81. src/app/user-identifier-audit/user-identifier-audit.component.ts
82. src/app/variable/create/variable-create.component.ts
83. src/app/variable/update/variable-update.component.ts
84. src/app/variable-audit/variable-audit.component.ts

</details>

### Problem 2: Missing Error Callbacks

**High priority** (mutations with user actions):
- src/app/redemption-incentives/redemption-incentives.component.ts (disable, enable)
- *Need to audit other list components for similar pattern*

**Low priority** (lookup queries):
- src/app/redemption-incentives/create/redemption-incentive-create.component.ts (getStatuses, getMetrics, getVariables)
- *Need to audit other create/update components for similar pattern*

---

## Execution Strategy

### Phase 1: Create Helper Function
1. Create `src/app/shared/utils/error-utils.ts` with `getGraphQLErrorExtensions` helper
2. Create unit tests for the helper
3. Export from shared module

### Phase 2: Update Files (Problem 1)
1. Update files in batches by module (group related files together)
2. Run tests after each batch
3. Consider creating a PR per module or one large PR

### Phase 3: Add Error Callbacks (Problem 2)
1. Start with high-impact mutations (disable/enable buttons)
2. Then address lookup queries if desired
3. Consider adding a generic error message translation key

---

## Estimated Effort

| Task | Files | Complexity |
|------|-------|------------|
| Helper function + tests | 1 | Low |
| Problem 1: Update 84 files | 84 | Low (find/replace) |
| Problem 2: High priority | ~20 | Medium |
| Problem 2: Low priority | ~50+ | Low |

---

## Status

- [ ] Planning approved
- [ ] Phase 1: Helper function created
- [ ] Phase 2: Unsafe error access fixed
- [ ] Phase 3: Missing error callbacks added (high priority)
- [ ] Phase 3: Missing error callbacks added (low priority)
- [ ] Tests passing
- [ ] PR created
