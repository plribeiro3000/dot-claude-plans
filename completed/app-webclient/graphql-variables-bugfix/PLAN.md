# PLAN — GraphQL Variables Migration: Bug Fixes

## Objective

Fix all bugs found during the final audit of the GraphQL Variables Migration. This includes:
- **38 unmigrated files** still using string interpolation in GraphQL queries
- **6 error patterns** with confirmed bugs across the codebase

**Origin:** Final audit of the `graphql-variables-migration` plan, executed after all 44 PRs were merged.

### Audit Artifacts

- **`ANALYSIS-v2.md`** — Structured summary of all 12 audit agent results with tables, code samples, and conclusions
- **`audit-raw-logs/`** — Complete raw transcripts from each audit agent (12 files, ~150KB total)
  - See `audit-raw-logs/index.txt` for file index mapping agent IDs to categories

---

## Bug Categories

| # | Category | Type | Bugs | Files |
|---|----------|------|------|-------|
| 0 | Unmigrated files (string interpolation) | Migration gap | 38 files | 38 |
| 1 | Mutation arguments should be required (`!`) | Introduced | 4 locations | 4 |
| 2 | Loading state set outside `subscribe()` | Pre-existing | 17 locations | 10 |
| 4 | Query uses `ID!` instead of `ID` | Introduced | 12 queries | 11 |
| 5 | String `"true"` passed to Boolean variable | Introduced | 2 locations | 1 |
| 6 | `parseInt()` on GraphQL `ID` variables | Pre-existing | ~57 locations | ~35 |
| 8 | Numeric fields fail when value is `0` | Pre-existing | 12 locations | 6 |
| **Total** | | | **~140 locations** | **~70 files** |

**Note:** Errors 3 (boolean simple `if`) and 7 (Input type names) were verified clean.

---

## Category 0: Unmigrated Files (38 files)

### Problem

These files still use string interpolation (`${value}`) inside GraphQL queries/mutations instead of GraphQL variables. This is the original bug that the migration was meant to fix — special characters (`\r\n`, quotes) in user input cause "Unterminated string" GraphQL errors.

### Fix Pattern

Same as the original migration: extract values into `const variables: Record<string, any>` and declare typed GraphQL variable parameters.

### Files

#### acceptment-document (4 files)

| File | Methods to Migrate |
|------|--------------------|
| `acceptment-document/acceptment-document.component.ts` | `list()` (endCursor), `disabledButton()` (id), `downloadDocument()` (id) |
| `acceptment-document/show/acceptment-document-show.component.ts` | `ngOnInit()` (id), `getAcceptments()` (documentId, endCursor), `getDocumentErrors()` (documentId, endCursor) |
| `acceptment-document/create/acceptment-document-create.component.ts` | `uploadFile()` (filename, contentType), `uploadAttachment()` (documentId) |
| `acceptment-document/create/acceptment-document-create.service.ts` | `upload()` (filename, contentType) |

#### acceptment-reason (4 files)

| File | Methods to Migrate |
|------|--------------------|
| `acceptment-reason/acceptment-reason.component.ts` | `disabledButton()` (id), `enabledButton()` (id) |
| `acceptment-reason/show/acceptment-reason-show.component.ts` | `ngOnInit()` (id) |
| `acceptment-reason/update/acceptment-reason-update.component.ts` | `onSubmit()` (id, description, name), `getAcceptmentReason()` (id) |
| `acceptment-reason/create/acceptment-reason-create.component.ts` | `onSubmit()` (description, key, name) |

#### incentive-campaign (2 files)

| File | Methods to Migrate |
|------|--------------------|
| `incentive-campaign/show/incentive-campaign-show.component.ts` | `ngOnInit()` (id) |
| `incentive-campaign-fund/show/incentive-campaign-fund-show.component.ts` | `ngOnInit()` (id) |

#### incentive-payment (1 file)

| File | Methods to Migrate |
|------|--------------------|
| `incentive-payment/create/incentive-payment-create.component.ts` | `getCampaigns()` (companyId, id, search) |

#### indicator (1 file)

| File | Methods to Migrate |
|------|--------------------|
| `indicator/show/indicator-show.component.ts` | `ngOnInit()` (id) |

#### payment-report (2 files)

| File | Methods to Migrate |
|------|--------------------|
| `payment-report/payment-report-permissions.service.ts` | `getPermissions()` (paymentId) |
| `payment-report/payment-report.component.ts` | `onSubmit()` (paymentId, purpose) |

#### payment-type (4 files)

| File | Methods to Migrate |
|------|--------------------|
| `payment-type/payment-type.component.ts` | `disabledButton()` (id), `enabledButton()` (id) |
| `payment-type/show/payment-type-show.component.ts` | `ngOnInit()` (id) |
| `payment-type/update/payment-type-update.component.ts` | `onSubmit()` (id, name, externalId), `getPaymentType()` (id) |
| `payment-type/create/payment-type-create.component.ts` | `onSubmit()` (externalId, name) |

#### plan-statement (2 files)

| File | Methods to Migrate |
|------|--------------------|
| `plan-statement/plan-statement-accept/plan-statement-accept.component.ts` | `onSubmit()` (id, signature) |
| `plan-statement/plan-statement-show/plan-statement-show.component.ts` | `getUsers()` (planId, userId, groupId), `getPlanStatement()` (id) |

#### product (4 files)

| File | Methods to Migrate |
|------|--------------------|
| `product/product.component.ts` | `disabledButton()` (id), `enabledButton()` (id) |
| `product/show/product-show.component.ts` | `ngOnInit()` (id) |
| `product/update/product-update.component.ts` | `onSubmit()` (id, name, externalId), `getProduct()` (id) |
| `product/create/product-create.component.ts` | `onSubmit()` (externalId, name) |

#### statement (1 file)

| File | Methods to Migrate |
|------|--------------------|
| `statement/statement-accept/statement-accept.component.ts` | `onSubmit()` (id, signature) |

#### status (4 files)

| File | Methods to Migrate |
|------|--------------------|
| `status/status.component.ts` | `disabledButton()` (id), `enabledButton()` (id) |
| `status/show/status-show.component.ts` | `ngOnInit()` (id) |
| `status/update/status-update.component.ts` | `onSubmit()` (id, name), `getStatus()` (id) |
| `status/create/status-create.component.ts` | `onSubmit()` (key, name) |

#### subsidiary (2 files)

| File | Methods to Migrate |
|------|--------------------|
| `subsidiary/subsidiary.component.ts` | `disabledButton()` (id), `enabledButton()` (id) |
| `subsidiary/show/subsidiary-show.component.ts` | `ngOnInit()` (id) |

#### trade (3 files)

| File | Methods to Migrate |
|------|--------------------|
| `trade/incentive-transaction/incentive-transaction.component.ts` | `getIncentiveTransactions()` (campaignId, search) |
| `trade/voucher/voucher.component.ts` | `getVouchers()` (campaignId, after, categoryId, searchByName) |
| `trade/redemption/redemption.component.ts` | `getCatalogation()` (id), `createRedemption()` (userId) |

#### variable (4 files)

| File | Methods to Migrate |
|------|--------------------|
| `variable/variable.component.ts` | `disabledButton()` (id), `enabledButton()` (id) |
| `variable/show/variable-show.component.ts` | `ngOnInit()` (id) |
| `variable/update/variable-update.component.ts` | `onSubmit()` (id, name), `getVariable()` (id) |
| `variable/create/variable-create.component.ts` | `onSubmit()` (calculation, dataType, default, frequency, key, name, overrideCalculation, type) |

---

## Category 1: Mutation Arguments Missing Required (`!`)

### Problem

Mutations declare arguments as nullable (`$field: Type`) when the backend requires them (`required: true`). The GraphQL server accepts the request but the mutation may fail silently or produce unexpected behavior when values are missing.

### Fix Pattern

Change `$field: Type` to `$field: Type!` for fields where backend has `required: true`.

### Bugs

| File | Line | Current | Should Be |
|------|------|---------|-----------|
| `user/change-password/user-change-password.component.ts` | 52 | `$currentPassword: String, $password: String, $passwordConfirmation: String` | `$currentPassword: String!, $password: String!, $passwordConfirmation: String!` |
| `password/password.component.ts` | 47 | `$currentPassword: String, $password: String, $passwordConfirmation: String` | `$currentPassword: String!, $password: String!, $passwordConfirmation: String!` |
| `campaign/campaign-attachment-signed-url.service.ts` | 56 | `$campaignId: ID, $contentType: String, $filename: String` | `$campaignId: ID!, $contentType: String!, $filename: String!` |
| `campaign/campaign-attachment.service.ts` | 42 | `$campaignId: ID` | `$campaignId: ID!` |

---

## Category 2: Loading State Outside `subscribe()` (Pre-existing)

### Problem

The loading flag (e.g., `this.loadingCalendars = false`) is set AFTER the `.subscribe()` call, meaning it executes immediately (synchronously) instead of when the HTTP response arrives. The loading spinner disappears instantly instead of when data is ready.

### Fix Pattern

Move `this.loadingXxx = false` INSIDE the subscribe callback, at the end of the response handler.

```typescript
// WRONG
this.service.query(...).valueChanges.subscribe((response) => {
  // handle response
});
this.loadingCalendars = false;  // Executes immediately!

// CORRECT
this.service.query(...).valueChanges.subscribe((response) => {
  // handle response
  this.loadingCalendars = false;  // Executes when response arrives
});
```

### Bugs

| File | Line | Loading Flag |
|------|------|-------------|
| `trade/trade.component.ts` | 126 | `this.loading` |
| `commission-creation-batch/create/commission-creation-batch-create.component.ts` | 105 | `this.loadingCalendars` |
| `plan/create/plan-create.component.ts` | 289 | `this.loadingCalendars` |
| `plan/create/plan-create.component.ts` | 329 | `this.loadingGroups` |
| `plan/create/plan-create.component.ts` | 400 | `this.loadingUsers` |
| `plan/update/plan-update.component.ts` | 450 | `this.loadingCalendars` |
| `plan/update/plan-update.component.ts` | 500 | `this.loadingGroups` |
| `plan/update/plan-update.component.ts` | 579 | `this.loadingUsers` |
| `commission-report-creation-batch/create/commission-report-creation-batch-create.component.ts` | 107 | `this.loadingCalendars` |
| `user-commission/show/user-commission-show.component.ts` | 367 | `this.loadingCalendars` |
| `user-commission/show/user-commission-show.component.ts` | 465 | `this.loadingGroups` |
| `easy-product/plan-slice/create/plan-slice-create.component.ts` | 198 | `this.loadingUsers` |
| `easy-product/plan-slice-commission/create/plan-slice-commission-create.component.ts` | 166 | `this.loadingPlanSlices` |
| `easy-product/easy-user/create/easy-user-create.component.ts` | 202 | `this.loadingCountries` |
| `easy-product/easy-user/create/easy-user-create.component.ts` | 249 | `this.loadingStates` |
| `easy-product/easy-payment/create/easy-payment-create.component.ts` | 125 | `this.loadingPlans` |
| `statement/statement-show/statement-show.component.ts` | 307 | `this.loading` (inside outer subscribe but outside inner nested subscribe) |

---

## Category 4: Query Uses `ID!` Instead of `ID` (Introduced)

### Problem

Queries declare parameters as required (`$id: ID!`) but the backend resolver uses `option(:id, type: ID)` which makes them optional. While this doesn't cause runtime errors (the value is always provided), it's inconsistent with the backend schema and would prevent sending null values if ever needed.

### Fix Pattern

Change `$id: ID!` to `$id: ID` in query declarations (NOT mutations — mutations correctly use `ID!`).

### Bugs

| File | Line | Current | Should Be |
|------|------|---------|-----------|
| `group/show/group-show.component.ts` | 63 | `query GroupShow($id: ID!)` | `$id: ID` |
| `group/show/group-show.component.ts` | 109 | `query GroupificationsShow($groupId: ID!)` | `$groupId: ID` |
| `group/update/group-update.component.ts` | 44 | `query GroupUpdate($id: ID!)` | `$id: ID` |
| `user/create/user-create.component.ts` | 545 | `query Company($id: ID!)` | `$id: ID` |
| `user/show/user-show.component.ts` | 35 | `query UserShow($id: ID!)` | `$id: ID` |
| `user/update/user-update.component.ts` | 348 | `query UserUpdate($id: ID!)` | `$id: ID` |
| `deal/show/deal-show.component.ts` | 42 | `query DealShow($id: ID!)` | `$id: ID` |
| `deal/update/deal-update.component.ts` | 92 | `query DealUpdate($id: ID!)` | `$id: ID` |
| `rankifier/clone/rankifier-clone.component.ts` | 233 | `query RankifierClone($id: ID!)` | `$id: ID` |
| `rankifier/show/rankifier-show.component.ts` | 34 | `query RankifierShow($id: ID!)` | `$id: ID` |
| `rankifier/update/rankifier-update.component.ts` | 246 | `query RankifierUpdate($id: ID!)` | `$id: ID` |
| `plan-goal-audit/plan-goal-audit.service.ts` | 42 | `query PlanGoalAudits($planId: ID!)` | `$planId: ID` |

---

## Category 5: String `"true"` Passed to Boolean Variable (Introduced)

### Problem

The `Filter` model stores `override` and `shared` as strings (from URL query params). When passed directly to GraphQL variables expecting `Boolean`, the server rejects: `"Could not coerce value \"true\" to Boolean"`.

### Fix Pattern

Convert string to boolean before assigning, matching the existing pattern used for `enabled`:

```typescript
// WRONG - passes string "true"
if (params.override !== undefined && params.override !== null) {
  variables.override = params.override;
}

// CORRECT - converts to boolean
if (params.override !== undefined && params.override !== null && params.override !== '') {
  variables.override = params.override === 'true';
}
```

### Bugs

| File | Line | Field |
|------|------|-------|
| `plan/plan.service.ts` | 62 | `variables.override = params.override` |
| `plan/plan.service.ts` | 74 | `variables.shared = params.shared` |

---

## Category 6: `parseInt()` on GraphQL `ID` Variables (Pre-existing)

### Problem

Frontend uses `parseInt(id, 10)` to convert IDs to numbers, but GraphQL `ID` type serializes as string. This causes type mismatches. While the GraphQL server often coerces numbers to IDs, it's incorrect and can cause issues with certain ID formats.

### Fix Pattern

Remove `parseInt()` and use the value directly, or use `String()` when the source type is uncertain:

```typescript
// WRONG
variables.userId = parseInt(event.id, 10);
this.form.controls.userId.setValue(parseInt(event.id, 10));

// CORRECT
variables.userId = event.id;
this.form.controls.userId.setValue(event.id);
```

**Exception:** Keep `parseInt()` for fields where backend type is `Integer` (not `ID`):
- `rankifier/*/` → `variableId` is `Integer` type ✅ KEEP

### Bugs by File

| File | Line(s) | Fields | Fix |
|------|---------|--------|-----|
| `deal/create/deal-create.component.ts` | 275, 323, 371, 419 | productId, clientId, userId, statusId | Remove parseInt |
| `deal/update/deal-update.component.ts` | 164, 172, 180, 388, 436, 484, 532 | statusId, clientId, productId (init + select handlers) | Remove parseInt |
| `plan/create/plan-create.component.ts` | 234, 425, 430, 434 | incentiveId, calendarId, groupId, campaignId | Remove parseInt |
| `plan/update/plan-update.component.ts` | 192, 196, 205, 509, 559 | calendarId, groupId, campaignId, userId, incentiveId | Remove parseInt |
| `campaign/create/campaign-create.component.ts` | 136 | planId | Remove parseInt |
| `campaign/update/campaign-update.component.ts` | 135, 180, 436 | planId | Remove parseInt |
| `commission-creation-batch/create/commission-creation-batch-create.component.ts` | 82, 114 | calendarId, periodId | Remove parseInt |
| `commission-creation-batch/show/commission-creation-batch-show.component.ts` | 106 | id (`String(parseInt(...))`) | Change to `String(event)` |
| `commission-report-creation-batch/create/commission-report-creation-batch-create.component.ts` | 84, 116 | calendarId, periodId | Remove parseInt |
| `indicator/create/indicator-create.component.ts` | 142, 190 | variableId, userId | Remove parseInt |
| `subsidiary/create/subsidiary-create.component.ts` | 144 | companyId | Remove parseInt |
| `subsidiary/update/subsidiary-update.component.ts` | 149 | companyId | Remove parseInt |
| `seat/demote/seat-demote.component.ts` | ~141 | userId | Remove parseInt |
| `seat/promote/seat-promote.component.ts` | ~134 | userId | Remove parseInt |
| `seat/update-parent-seat/update-parent-seat.component.ts` | ~200 | userId, parentId | Remove parseInt |
| `deal-incentive/create/deal-incentive-create.component.ts` | 210 | groupId | Remove parseInt |
| `deal-incentive/update/deal-incentive-update.component.ts` | 46, 196, 254 | dealIncentiveId, groupId | Remove parseInt |
| `deal-incentive/clone/deal-incentive-clone.component.ts` | 46, 199, 249 | dealIncentiveId, groupId | Remove parseInt |
| `partial-commission/create/partial-commission-create.component.ts` | 137, 197 | planId, periodId | Remove parseInt |
| `user-history/create/user-history-create.component.ts` | 112 | userId | Remove parseInt |
| `incentive-payment/create/incentive-payment-create.component.ts` | 197, 198 | campaignId, periodId | Remove parseInt |
| `incentive-campaign-fund/create/incentive-campaign-fund-create.component.ts` | 155, 173 | campaignId | Remove parseInt |
| `easy-product/plan-slice/create/plan-slice-create.component.ts` | 176, 207 | variableId, userIds | Remove parseInt |
| `easy-product/plan-slice-commission/create/plan-slice-commission-create.component.ts` | 175 | planSliceId | Remove parseInt |
| `rankifier-incentives/create/rankifier-incentive-create.component.ts` | — | groupId | Remove parseInt |
| `rankifier-incentives/update/rankifier-incentive-update.component.ts` | — | groupId | Remove parseInt |
| `rankifier-incentives/clone/rankifier-incentive-clone.component.ts` | — | groupId | Remove parseInt |
| `indicator-incentives/create/indicator-incentive-create.component.ts` | — | groupId | Remove parseInt |
| `indicator-incentives/update/indicator-incentive-update.component.ts` | — | groupId | Remove parseInt |
| `indicator-incentives/clone/indicator-incentive-clone.component.ts` | — | groupId | Remove parseInt |
| `limiter-incentives/create/limiter-incentive-create.component.ts` | — | groupId | Remove parseInt |
| `limiter-incentives/update/limiter-incentive-update.component.ts` | — | groupId | Remove parseInt |
| `limiter-incentives/clone/limiter-incentive-clone.component.ts` | — | groupId | Remove parseInt |
| `profile/profile.component.ts` | 48 | profileId | Remove parseInt |
| `shell/profile-menu/profile-menu.component.ts` | 57 | profileId | Remove parseInt |

**Files in Category 0 (unmigrated)** that ALSO have parseInt will be fixed during migration:
- `variable/variable.component.ts`
- `status/status.component.ts`
- `product/product.component.ts`
- `payment-type/payment-type.component.ts`
- `acceptment-reason/acceptment-reason.component.ts`
- `subsidiary/subsidiary.component.ts`
- `acceptment-document/acceptment-document.component.ts`

---

## Category 8: Numeric Fields Fail When Value is `0` (Pre-existing)

### Problem

Using `if (this.form.value.field)` for numeric fields won't send the value when it equals `0`, because `0` is falsy in JavaScript. The field keeps its previous value or becomes null.

### Fix Pattern

Use explicit null/undefined check:

```typescript
// WRONG - won't send value if it's 0
if (this.form.value.installment) {
  variables.installment = this.form.value.installment;
}

// CORRECT - handles 0 correctly
if (this.form.value.installment !== undefined && this.form.value.installment !== null) {
  variables.installment = this.form.value.installment;
}
```

### Bugs

| File | Line | Field | GraphQL Type |
|------|------|-------|-------------|
| `collaborative-deal/create/collaborative-deal-create.component.ts` | 93 | `installment` | Int |
| `collaborative-deal/create/collaborative-deal-create.component.ts` | 109 | `unitaryValue` | Float |
| `collaborative-deal/create/collaborative-deal-create.component.ts` | 121 | `workHours` | Float |
| `collaborative-deal/update/collaborative-deal-update.component.ts` | 213 | `unitaryValue` | Float |
| `collaborative-deal/update/collaborative-deal-update.component.ts` | 217 | `workHours` | Float |
| `deal/create/deal-create.component.ts` | 99 | `installment` | Int |
| `deal/create/deal-create.component.ts` | 115 | `soldPrice` | Float |
| `deal/create/deal-create.component.ts` | 131 | `workHours` | Float |
| `deal/update/deal-update.component.ts` | 208 | `installment` | Int |
| `deal/update/deal-update.component.ts` | 220 | `soldPrice` | Float |
| `deal/update/deal-update.component.ts` | 236 | `workHours` | Float |
| `metric/create/metric-create.component.ts` | 79 | `installment` | Int |

**Already correct** (no fix needed):
- `budget` in plan-create and plan-update
- `goal` in plan-update
- `quantity` in deal and collaborative-deal

---

## Execution Strategy

### PR Organization

Since there are many independent fixes, they should be organized by module/category for clear review:

| PR | Category | Files | Description |
|----|----------|-------|-------------|
| 1 | Cat 0 | 4 | Migrate acceptment-document |
| 2 | Cat 0 | 4 | Migrate acceptment-reason |
| 3 | Cat 0 | 4 | Migrate payment-type |
| 4 | Cat 0 | 4 | Migrate product |
| 5 | Cat 0 | 4 | Migrate status |
| 6 | Cat 0 | 4 | Migrate variable |
| 7 | Cat 0 | 3 | Migrate trade (incentive-transaction, voucher, redemption) |
| 8 | Cat 0 | 2 | Migrate plan-statement |
| 9 | Cat 0 | 2 | Migrate subsidiary (show, component) |
| 10 | Cat 0 | 1 | Migrate indicator/show |
| 11 | Cat 0 | 2 | Migrate incentive-campaign + fund show |
| 12 | Cat 0 | 1 | Migrate incentive-payment/create |
| 13 | Cat 0 | 2 | Migrate payment-report |
| 14 | Cat 0 | 1 | Migrate statement/statement-accept |
| 15 | Cat 1 | 4 | Fix mutation nullability |
| 16 | Cat 2 | 10 | Fix loading state outside subscribe |
| 17 | Cat 4 | 11 | Fix query ID! → ID |
| 18 | Cat 5 | 1 | Fix string-to-boolean conversion in plan.service |
| 19 | Cat 6 | ~35 | Fix parseInt for GraphQL IDs |
| 20 | Cat 8 | 6 | Fix numeric fields value 0 |

**Alternative:** Consolidate into fewer PRs if hotfix urgency requires faster review. Categories 1, 4, 5 are migration-introduced bugs and should be prioritized.

### Process

1. All branches from `develop`
2. One commit per PR
3. Verify types against backend before each fix
4. Run `yarn prettier --write` on changed files only
5. Run `yarn build` to verify compilation
6. Single changelog entry at release

### Priority

1. **Critical (migration-introduced, may be broken in production):**
   - Category 1: Mutation nullability
   - Category 5: String-to-boolean conversion

2. **High (migration-introduced, inconsistent but working):**
   - Category 4: Query ID! vs ID
   - Category 0: Unmigrated files

3. **Medium (pre-existing bugs, working before migration):**
   - Category 6: parseInt for IDs
   - Category 8: Numeric fields value 0
   - Category 2: Loading state outside subscribe

---

**Status:** COMPLETED ✅

---

## Delivery Summary

All 9 bug categories were audited. 7 PRs were created and merged into develop:

| PR | Category | Description |
|----|----------|-------------|
| #5967 | Cat 0 + Cat 4 | 40 unmigrated files migrated + 2 Cat 4 bugs fixed |
| #5968 | Cat 1 | Fix mutation arguments missing required (`!`) |
| #5969 | Cat 2 | Fix loading state outside `subscribe()` |
| #5970 | Cat 4 | Fix query `ID!` → `ID` (remaining 10 queries) |
| #5971 | Cat 5 | Fix string-to-boolean conversion in plan.service.ts |
| #5972 | Cat 6 | Remove `parseInt()` from GraphQL `ID` variables |
| #5973 | Cat 8 | Fix numeric fields fail when value is `0` |

**Categories 3 and 7** were verified clean — no PRs needed.

**Additional finding:** The `|| ''` pattern for ID fields was identified as a pre-existing defensive pattern (not a new bug from the migration). This is documented in the `graphql-type-contract-standardization` plan for future nullability contract standardization.

**Copilot review:** Comments on PR #5967 were analyzed and determined to be pre-existing defensive patterns, not new bugs introduced by the migration.

---

## Completion Note

**Date:** 2026-01-27

All bug fixes from the GraphQL Variables Migration audit have been completed and merged into develop. Remaining type safety issues are tracked in the `graphql-type-contract-standardization` plan for future work.
