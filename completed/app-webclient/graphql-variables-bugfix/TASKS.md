# TASKS — GraphQL Variables Migration: Bug Fixes

**Branch base:** `develop`
**Hotfix branch:** `hotfix/1.253.9`
**Pattern:** 1 PR per bug category (7 PRs — categories 3 and 7 verified clean, no PR needed)

---

## PR 1 — Category 0: Migrate Remaining 38 Files (String Interpolation → GraphQL Variables) — PR #5967

**Priority:** High (migration-introduced)
**Scope:** 40 files across 14 modules (38 originally planned + 2 Cat 4 fixes)
**Status:** COMPLETED ✅

### Problem

38 files still use string interpolation (`${value}`) inside GraphQL queries/mutations. Special characters in user input cause "Unterminated string" GraphQL errors.

### Fix Pattern

Same as the original migration: extract interpolated values into `const variables: Record<string, any>` and declare typed GraphQL variable parameters (`$field: Type`).

### Files (by module)

1. **acceptment-document** (4 files)
   - `acceptment-document/acceptment-document.component.ts` — `list()`, `disabledButton()`, `downloadDocument()`
   - `acceptment-document/show/acceptment-document-show.component.ts` — `ngOnInit()`, `getAcceptments()`, `getDocumentErrors()`
   - `acceptment-document/create/acceptment-document-create.component.ts` — `uploadFile()`, `uploadAttachment()`
   - `acceptment-document/create/acceptment-document-create.service.ts` — `upload()`

2. **acceptment-reason** (4 files)
   - `acceptment-reason/acceptment-reason.component.ts` — `disabledButton()`, `enabledButton()`
   - `acceptment-reason/show/acceptment-reason-show.component.ts` — `ngOnInit()`
   - `acceptment-reason/update/acceptment-reason-update.component.ts` — `onSubmit()`, `getAcceptmentReason()`
   - `acceptment-reason/create/acceptment-reason-create.component.ts` — `onSubmit()`

3. **incentive-campaign** (2 files)
   - `incentive-campaign/show/incentive-campaign-show.component.ts` — `ngOnInit()`
   - `incentive-campaign-fund/show/incentive-campaign-fund-show.component.ts` — `ngOnInit()`

4. **incentive-payment** (1 file)
   - `incentive-payment/create/incentive-payment-create.component.ts` — `getCampaigns()`

5. **indicator** (1 file)
   - `indicator/show/indicator-show.component.ts` — `ngOnInit()`

6. **payment-report** (2 files)
   - `payment-report/payment-report-permissions.service.ts` — `getPermissions()`
   - `payment-report/payment-report.component.ts` — `onSubmit()`

7. **payment-type** (4 files)
   - `payment-type/payment-type.component.ts` — `disabledButton()`, `enabledButton()`
   - `payment-type/show/payment-type-show.component.ts` — `ngOnInit()`
   - `payment-type/update/payment-type-update.component.ts` — `onSubmit()`, `getPaymentType()`
   - `payment-type/create/payment-type-create.component.ts` — `onSubmit()`

8. **plan-statement** (2 files)
   - `plan-statement/plan-statement-accept/plan-statement-accept.component.ts` — `onSubmit()`
   - `plan-statement/plan-statement-show/plan-statement-show.component.ts` — `getUsers()`, `getPlanStatement()`

9. **product** (4 files)
   - `product/product.component.ts` — `disabledButton()`, `enabledButton()`
   - `product/show/product-show.component.ts` — `ngOnInit()`
   - `product/update/product-update.component.ts` — `onSubmit()`, `getProduct()`
   - `product/create/product-create.component.ts` — `onSubmit()`

10. **statement** (1 file)
    - `statement/statement-accept/statement-accept.component.ts` — `onSubmit()`

11. **status** (4 files)
    - `status/status.component.ts` — `disabledButton()`, `enabledButton()`
    - `status/show/status-show.component.ts` — `ngOnInit()`
    - `status/update/status-update.component.ts` — `onSubmit()`, `getStatus()`
    - `status/create/status-create.component.ts` — `onSubmit()`

12. **subsidiary** (2 files)
    - `subsidiary/subsidiary.component.ts` — `disabledButton()`, `enabledButton()`
    - `subsidiary/show/subsidiary-show.component.ts` — `ngOnInit()`

13. **trade** (3 files)
    - `trade/incentive-transaction/incentive-transaction.component.ts` — `getIncentiveTransactions()`
    - `trade/voucher/voucher.component.ts` — `getVouchers()`
    - `trade/redemption/redemption.component.ts` — `getCatalogation()`, `createRedemption()`

14. **variable** (4 files)
    - `variable/variable.component.ts` — `disabledButton()`, `enabledButton()`
    - `variable/show/variable-show.component.ts` — `ngOnInit()`
    - `variable/update/variable-update.component.ts` — `onSubmit()`, `getVariable()`
    - `variable/create/variable-create.component.ts` — `onSubmit()`

### Important Notes

- Files that also have `parseInt` bugs (Category 6) should have those fixed at the same time during migration:
  `variable.component.ts`, `status.component.ts`, `product.component.ts`, `payment-type.component.ts`, `acceptment-reason.component.ts`, `subsidiary.component.ts`, `acceptment-document.component.ts`
- Follow the same migration patterns from the 44 previous PRs (see `graphql-variables-migration/TASKS.md`)

### Verification

```bash
grep -r '\${' src/app/ --include="*.ts" | grep -v node_modules | grep -v '.spec.ts' | grep -v '\.d\.ts'
```

Filter out non-GraphQL template literals (URLs, CSS, logging) and confirm zero GraphQL interpolations remain.

---

## PR 2 — Category 1: Fix Mutation Arguments Missing Required (`!`) — PR #5968

**Priority:** Critical (migration-introduced — may cause silent failures in production)
**Scope:** 4 files, 4 locations
**Status:** COMPLETED ✅

### Problem

Mutations declare arguments as nullable (`$field: Type`) when the backend requires them (`required: true`). This allows the client to send requests without required fields.

### Fix Pattern

Add `!` to variable type declarations where backend has `required: true`.

### Changes

| # | File | Line | Current | Fix |
|---|------|------|---------|-----|
| 1 | `user/change-password/user-change-password.component.ts` | 52 | `$currentPassword: String, $password: String, $passwordConfirmation: String` | Add `!` to all three |
| 2 | `password/password.component.ts` | 47 | `$currentPassword: String, $password: String, $passwordConfirmation: String` | Add `!` to all three |
| 3 | `campaign/campaign-attachment-signed-url.service.ts` | 56 | `$campaignId: ID, $contentType: String, $filename: String` | `$campaignId: ID!` (contentType and filename are `required: false`) |
| 4 | `campaign/campaign-attachment.service.ts` | 42 | `$campaignId: ID` | `$campaignId: ID!` |

### Verification

```bash
# Verify no other mutations have missing required flags
grep -rn 'mutation.*\$.*: ID[^!]' src/app/ --include="*.ts" | grep -v node_modules | grep -v '.spec.ts'
grep -rn 'mutation.*\$.*: String[^!]' src/app/ --include="*.ts" | grep -v node_modules | grep -v '.spec.ts'
```

Cross-reference each with backend `required: true` flags.

---

## PR 3 — Category 2: Fix Loading State Outside `subscribe()` — PR #5969

**Priority:** Medium (pre-existing — loading spinners disappear instantly)
**Scope:** 10 files, 17 locations
**Status:** COMPLETED ✅

### Problem

`this.loadingXxx = false` is set AFTER `.subscribe()` (synchronously) instead of inside the callback (when response arrives). Loading spinners disappear before data loads.

### Fix Pattern

Move `this.loadingXxx = false` inside the subscribe callback, at the end of the response handler.

### Changes

| # | File | Line | Property | Fix |
|---|------|------|----------|-----|
| 1 | `trade/trade.component.ts` | 126 | `this.loading` | Move inside subscribe |
| 2 | `commission-creation-batch/create/commission-creation-batch-create.component.ts` | 105 | `this.loadingCalendars` | Move inside subscribe |
| 3 | `plan/create/plan-create.component.ts` | 289 | `this.loadingCalendars` | Move inside subscribe |
| 4 | `plan/create/plan-create.component.ts` | 329 | `this.loadingGroups` | Move inside subscribe |
| 5 | `plan/create/plan-create.component.ts` | 400 | `this.loadingUsers` | Move inside subscribe |
| 6 | `plan/update/plan-update.component.ts` | 450 | `this.loadingCalendars` | Move inside subscribe |
| 7 | `plan/update/plan-update.component.ts` | 500 | `this.loadingGroups` | Move inside subscribe |
| 8 | `plan/update/plan-update.component.ts` | 579 | `this.loadingUsers` | Move inside subscribe |
| 9 | `commission-report-creation-batch/create/commission-report-creation-batch-create.component.ts` | 107 | `this.loadingCalendars` | Move inside subscribe |
| 10 | `user-commission/show/user-commission-show.component.ts` | 367 | `this.loadingCalendars` | Move inside subscribe |
| 11 | `user-commission/show/user-commission-show.component.ts` | 465 | `this.loadingGroups` | Move inside subscribe |
| 12 | `easy-product/plan-slice/create/plan-slice-create.component.ts` | 198 | `this.loadingUsers` | Move inside subscribe |
| 13 | `easy-product/plan-slice-commission/create/plan-slice-commission-create.component.ts` | 166 | `this.loadingPlanSlices` | Move inside subscribe |
| 14 | `easy-product/easy-user/create/easy-user-create.component.ts` | 202 | `this.loadingCountries` | Move inside subscribe |
| 15 | `easy-product/easy-user/create/easy-user-create.component.ts` | 249 | `this.loadingStates` | Move inside subscribe |
| 16 | `easy-product/easy-payment/create/easy-payment-create.component.ts` | 125 | `this.loadingPlans` | Move inside subscribe |
| 17 | `statement/statement-show/statement-show.component.ts` | 307 | `this.loading` | Move inside nested subscribe |

### Special Case

Bug #17 (`statement-show`) is inside an outer subscribe but outside an inner nested subscribe. The fix requires placing `this.loading = false` at the end of the inner subscribe callback.

### Verification

```bash
# After fix, search for loading assignments after subscribe closing bracket
grep -B2 -A2 'this\.loading.*= false' src/app/ -r --include="*.ts" | grep -v node_modules | grep -v '.spec.ts'
```

Manually verify each result is inside a subscribe callback, not after it.

---

## PR 4 — Category 4: Fix Query Uses `ID!` Instead of `ID` — PR #5970

**Priority:** High (migration-introduced — schema inconsistency)
**Scope:** 11 files, 12 queries
**Status:** COMPLETED ✅

### Problem

Queries declare parameters as required (`$id: ID!`) but the backend resolver uses `option(:id, type: ID)` (optional). This is a schema type mismatch introduced during migration.

### Fix Pattern

Change `$id: ID!` to `$id: ID` in query declarations. This only applies to QUERIES, not mutations.

### Changes

| # | File | Line | Query Name | Fix |
|---|------|------|-----------|-----|
| 1 | `group/show/group-show.component.ts` | 63 | `GroupShow` | `$id: ID!` → `$id: ID` |
| 2 | `group/show/group-show.component.ts` | 109 | `GroupificationsShow` | `$groupId: ID!` → `$groupId: ID` |
| 3 | `group/update/group-update.component.ts` | 44 | `GroupUpdate` | `$id: ID!` → `$id: ID` |
| 4 | `user/create/user-create.component.ts` | 545 | `Company` | `$id: ID!` → `$id: ID` |
| 5 | `user/show/user-show.component.ts` | 35 | `UserShow` | `$id: ID!` → `$id: ID` |
| 6 | `user/update/user-update.component.ts` | 348 | `UserUpdate` | `$id: ID!` → `$id: ID` |
| 7 | `deal/show/deal-show.component.ts` | 42 | `DealShow` | `$id: ID!` → `$id: ID` |
| 8 | `deal/update/deal-update.component.ts` | 92 | `DealUpdate` | `$id: ID!` → `$id: ID` |
| 9 | `rankifier/clone/rankifier-clone.component.ts` | 233 | `RankifierClone` | `$id: ID!` → `$id: ID` |
| 10 | `rankifier/show/rankifier-show.component.ts` | 34 | `RankifierShow` | `$id: ID!` → `$id: ID` |
| 11 | `rankifier/update/rankifier-update.component.ts` | 246 | `RankifierUpdate` | `$id: ID!` → `$id: ID` |
| 12 | `plan-goal-audit/plan-goal-audit.service.ts` | 42 | `PlanGoalAudits` | `$planId: ID!` → `$planId: ID` |

### DO NOT change these (correctly use `ID!`)

- All "temporary" queries (`TemporaryFileGraphqlResolver` uses `argument :id, ID, required: true`)
- `DownloadDocument` — calls temporary resolvers
- `GoalDatasets` / `GetGoalDatasets` with `$planId: ID!` — backend `argument :plan_id, ID, required: true`
- `PlanGoalAuditPermissions` with `$planId: ID!` — backend `argument :plan_id, ID, required: true`

### Verification

```bash
grep -rn 'query.*\$id: ID!' src/app/ --include="*.ts" | grep -v node_modules | grep -v '.spec.ts'
```

Cross-reference remaining `ID!` queries with backend resolvers to confirm they use `argument required: true`.

---

## PR 5 — Category 5: Fix String-to-Boolean Conversion in plan.service.ts — PR #5971

**Priority:** Critical (migration-introduced — causes GraphQL coercion error)
**Scope:** 1 file, 2 locations
**Status:** COMPLETED ✅

### Problem

`override` and `shared` in `plan.service.ts` are passed directly from `Filter` model without boolean conversion. When values come from URL query params, they arrive as strings (`"true"`, `"false"`). The GraphQL server rejects: `"Could not coerce value \"true\" to Boolean"`.

### Fix Pattern

Apply the same conversion pattern already used for `enabled` in the same file (line 52-54):

```typescript
// CURRENT (line 62) — BUG
if (params.override !== undefined && params.override !== null) {
  variables.override = params.override;
}

// FIX
if (params.override !== undefined && params.override !== null && params.override !== '') {
  variables.override = params.override === 'true' || params.override === true;
}
```

### Changes

| # | File | Line | Field | Fix |
|---|------|------|-------|-----|
| 1 | `plan/plan.service.ts` | 62 | `override` | Add `=== 'true' \|\| === true` conversion |
| 2 | `plan/plan.service.ts` | 74 | `shared` | Add `=== 'true' \|\| === true` conversion |

### Why `=== 'true' || === true`

The value can be either:
- A boolean `true`/`false` — when set from dropdown (`selectOverride`/`selectShared`)
- A string `"true"`/`"false"` — when set from URL query params (Angular Router)

Using `params.override === 'true' || params.override === true` handles both cases correctly.

### Verification

```bash
grep -n 'variables.override\|variables.shared' src/app/plan/plan.service.ts
```

Confirm both use the conversion pattern.

---

## PR 6 — Category 6: Remove `parseInt()` from GraphQL `ID` Variables — PR #5972

**Priority:** Medium (pre-existing — type mismatch, server coerces most cases)
**Scope:** ~35 files, ~57 locations
**Status:** COMPLETED ✅

### Problem

Frontend uses `parseInt(id, 10)` to convert string IDs to numbers. GraphQL `ID` type serializes as string. While the server often coerces numbers to IDs, it's incorrect and fragile.

### Fix Pattern

Remove `parseInt()` calls. Use `event.id` directly:

```typescript
// CURRENT — BUG
this.form.controls.userId.setValue(parseInt(event.id, 10));

// FIX
this.form.controls.userId.setValue(event.id);
```

### Exception — DO NOT CHANGE

`parseInt()` is correct for `variableId` in Rankifier components (backend type is `Integer`, not `ID`):
- `rankifier/create/rankifier-create.component.ts:66`
- `rankifier/clone/rankifier-clone.component.ts:71`
- `rankifier/update/rankifier-update.component.ts:81`

### Changes by File

| # | File | Lines | Fields | Fix |
|---|------|-------|--------|-----|
| 1 | `deal/create/deal-create.component.ts` | 275, 323, 371, 419 | productId, clientId, userId, statusId | Remove parseInt |
| 2 | `deal/update/deal-update.component.ts` | 164, 172, 180, 388, 436, 484, 532 | statusId, clientId, productId (×2 each) | Remove parseInt |
| 3 | `plan/create/plan-create.component.ts` | 234, 241, 267, 425, 430, 434 | incentiveId, calendarId, paymentTypeId, groupId, campaignId | Remove parseInt |
| 4 | `plan/update/plan-update.component.ts` | 192, 196, 205, 380, 430, 460, 509, 559 | calendarId, groupId, campaignId, incentiveId, paymentTypeId | Remove parseInt |
| 5 | `campaign/create/campaign-create.component.ts` | 136 | planId | Remove parseInt |
| 6 | `campaign/update/campaign-update.component.ts` | 135, 180 | planId | Remove parseInt |
| 7 | `commission-creation-batch/create/...component.ts` | 82, 114 | calendarId, periodId | Remove parseInt |
| 8 | `commission-creation-batch/show/...component.ts` | 106 | id | `String(parseInt(...))` → `String(event)` |
| 9 | `commission-report-creation-batch/create/...component.ts` | 84, 116 | calendarId, periodId | Remove parseInt |
| 10 | `indicator/create/indicator-create.component.ts` | 142, 190 | variableId, userId | Remove parseInt |
| 11 | `subsidiary/create/subsidiary-create.component.ts` | 144 | companyId | Remove parseInt |
| 12 | `subsidiary/update/subsidiary-update.component.ts` | 149 | companyId | Remove parseInt |
| 13 | `seat/demote/seat-demote.component.ts` | 141, 201 | userId, parentId | Remove parseInt |
| 14 | `seat/promote/seat-promote.component.ts` | 141, 200 | userId, parentId | Remove parseInt |
| 15 | `seat/update-parent-seat/update-parent-seat.component.ts` | 134, 185 | userId, parentId | Remove parseInt |
| 16 | `deal-incentive/create/deal-incentive-create.component.ts` | 210 | groupId | Remove parseInt |
| 17 | `deal-incentive/update/deal-incentive-update.component.ts` | 46, 196, 254 | dealIncentiveId, groupId | Remove parseInt |
| 18 | `deal-incentive/clone/deal-incentive-clone.component.ts` | 46, 199, 249 | dealIncentiveId, groupId | Remove parseInt |
| 19 | `indicator-incentives/create/indicator-incentive-create.component.ts` | 216 | groupId | Remove parseInt |
| 20 | `indicator-incentives/update/indicator-incentive-update.component.ts` | 197, 255 | groupId | Remove parseInt |
| 21 | `indicator-incentives/clone/indicator-incentive-clone.component.ts` | 200, 250 | groupId | Remove parseInt |
| 22 | `rankifier-incentives/create/rankifier-incentive-create.component.ts` | 219 | groupId | Remove parseInt |
| 23 | `rankifier-incentives/update/rankifier-incentive-update.component.ts` | 201, 231, 285, 290 | groupId, rankifierId | Remove parseInt |
| 24 | `rankifier-incentives/clone/rankifier-incentive-clone.component.ts` | 203, 232, 286, 291 | groupId, rankifierId | Remove parseInt |
| 25 | `limiter-incentives/create/limiter-incentive-create.component.ts` | 213 | groupId | Remove parseInt |
| 26 | `limiter-incentives/update/limiter-incentive-update.component.ts` | 192, 242 | groupId | Remove parseInt |
| 27 | `limiter-incentives/clone/limiter-incentive-clone.component.ts` | 197, 247 | groupId | Remove parseInt |
| 28 | `partial-commission/create/partial-commission-create.component.ts` | 137, 197 | planId, periodId | Remove parseInt |
| 29 | `user-history/create/user-history-create.component.ts` | 112 | userId | Remove parseInt |
| 30 | `incentive-payment/create/incentive-payment-create.component.ts` | 197, 198 | campaignId, periodId | Remove parseInt |
| 31 | `incentive-campaign-fund/create/incentive-campaign-fund-create.component.ts` | 155, 173 | campaignId | Remove parseInt |
| 32 | `easy-product/plan-slice/create/plan-slice-create.component.ts` | 176, 207 | variableId, userIds | Remove parseInt |
| 33 | `easy-product/plan-slice-commission/create/...component.ts` | 175 | planSliceId | Remove parseInt |
| 34 | `profile/profile.component.ts` | 48 | profileId | Remove parseInt |
| 35 | `shell/profile-menu/profile-menu.component.ts` | 57 | profileId | Remove parseInt |

### Files shared with Category 0 (parseInt inside unmigrated files)

These have BOTH string interpolation AND parseInt — will be fixed in PR 1:
- `variable/variable.component.ts`
- `status/status.component.ts`
- `product/product.component.ts`
- `payment-type/payment-type.component.ts`
- `acceptment-reason/acceptment-reason.component.ts`
- `subsidiary/subsidiary.component.ts`
- `acceptment-document/acceptment-document.component.ts`

**These 7 files should NOT be changed in PR 6** — they will be handled in PR 1 during full migration.

### Verification

```bash
grep -rn 'parseInt(' src/app/ --include="*.ts" | grep -v node_modules | grep -v '.spec.ts' | grep -v '.d.ts' | grep -v 'date-formatter' | grep -v 'relative-progress-bar' | grep -v 'dashboard-calendar' | grep -v 'dashboard-plan'
```

Remaining `parseInt` calls should only be:
- Rankifier `variableId` (correct — Integer type)
- UI calculations (date-formatter, progress-bar, dashboard-calendar)
- Files from Category 0 (if PR 1 not yet merged)

---

## PR 7 — Category 8: Fix Numeric Fields Fail When Value is `0` — PR #5973

**Priority:** Medium (pre-existing — value `0` silently dropped)
**Scope:** 6 files, 12 locations
**Status:** COMPLETED ✅

### Problem

`if (this.form.value.field)` is falsy when `field === 0`. The field is not sent to the server, causing silent data loss for zero values.

### Fix Pattern

Replace truthy check with explicit null/undefined check (same pattern already used for `quantity`, `budget`, `goal`):

```typescript
// CURRENT — BUG (0 is falsy)
if (this.form.value.installment) {
  variables.installment = this.form.value.installment;
}

// FIX
if (this.form.value.installment !== undefined && this.form.value.installment !== null) {
  variables.installment = this.form.value.installment;
}
```

### Changes

| # | File | Line | Field | Type |
|---|------|------|-------|------|
| 1 | `collaborative-deal/create/collaborative-deal-create.component.ts` | 93 | `installment` | Int |
| 2 | `collaborative-deal/create/collaborative-deal-create.component.ts` | 109 | `unitaryValue` | Float |
| 3 | `collaborative-deal/create/collaborative-deal-create.component.ts` | 121 | `workHours` | Float |
| 4 | `collaborative-deal/update/collaborative-deal-update.component.ts` | 213 | `unitaryValue` | Float |
| 5 | `collaborative-deal/update/collaborative-deal-update.component.ts` | 217 | `workHours` | Float |
| 6 | `deal/create/deal-create.component.ts` | 99 | `installment` | Int |
| 7 | `deal/create/deal-create.component.ts` | 115 | `soldPrice` | Float |
| 8 | `deal/create/deal-create.component.ts` | 131 | `workHours` | Float |
| 9 | `deal/update/deal-update.component.ts` | 208 | `installment` | Int |
| 10 | `deal/update/deal-update.component.ts` | 220 | `soldPrice` | Float |
| 11 | `deal/update/deal-update.component.ts` | 236 | `workHours` | Float |
| 12 | `metric/create/metric-create.component.ts` | 79 | `installment` | Int |

### Already Correct (reference for pattern)

- `budget` in plan-create/update — uses `!== undefined && !== null`
- `goal` in plan-create/update — uses `!== undefined && !== null`
- `quantity` in deal/collaborative-deal — uses `!== undefined && !== null`

### Verification

```bash
grep -rn 'if (this.form.value\.' src/app/ --include="*.ts" | grep -v node_modules | grep -v '.spec.ts'
```

Cross-reference each result with GraphQL types. All `Int` and `Float` fields must use explicit null check.

---

## Execution Order

Based on priority:

| Order | PR | Category | Priority | Reason |
|-------|----|----------|----------|--------|
| 1 | PR 2 | Cat 1 — Mutation nullability | Critical | May cause silent failures |
| 2 | PR 5 | Cat 5 — String-to-boolean | Critical | Causes GraphQL error on deep links |
| 3 | PR 4 | Cat 4 — Query ID! → ID | High | Schema inconsistency |
| 4 | PR 1 | Cat 0 — Unmigrated files | High | Original migration gap |
| 5 | PR 6 | Cat 6 — parseInt for IDs | Medium | Type mismatch, server coerces |
| 6 | PR 7 | Cat 8 — Numeric zero | Medium | Value 0 silently dropped |
| 7 | PR 3 | Cat 2 — Loading outside subscribe | Medium | Spinner UX issue |

### Categories NOT requiring PRs

- **Category 3** (Boolean simple `if`): Verified clean — all boolean fields already use correct patterns
- **Category 7** (Wrong Input type names): Verified clean — all Input types use correct `Graphql` suffix

---

## Process per PR

1. Create branch from `develop` (or `hotfix/1.253.9` if hotfix)
2. Apply all fixes for that category
3. Run `yarn prettier --write` on changed files
4. Run `yarn build` to verify compilation
5. Single commit: `fix(graphql): <description>`
6. Create PR targeting `develop`

---

**Status:** COMPLETED ✅

---

## Delivery Summary

| PR | Category | GitHub PR |
|----|----------|-----------|
| PR 1 | Cat 0 — Unmigrated files + Cat 4 fixes | #5967 |
| PR 2 | Cat 1 — Mutation nullability | #5968 |
| PR 3 | Cat 2 — Loading outside subscribe | #5969 |
| PR 4 | Cat 4 — Query ID! → ID | #5970 |
| PR 5 | Cat 5 — String-to-boolean | #5971 |
| PR 6 | Cat 6 — parseInt for IDs | #5972 |
| PR 7 | Cat 8 — Numeric zero | #5973 |

All 7 PRs merged into develop.

**Additional observations:**
- The `|| ''` pattern for ID fields was identified as a pre-existing defensive pattern, documented in the `graphql-type-contract-standardization` plan for future nullability contract work.
- Copilot review comments on PR #5967 were analyzed and determined to be pre-existing patterns, not new bugs.

---

## Completion Note

**Date:** 2026-01-27

All bug fixes from the GraphQL Variables Migration audit have been completed. 9 bug categories audited, 7 PRs created and merged (categories 3 and 7 were verified clean). Remaining type safety issues are tracked in the `graphql-type-contract-standardization` plan for future work.
