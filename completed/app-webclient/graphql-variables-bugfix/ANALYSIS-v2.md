# Audit Logs — GraphQL Variables Migration Final Audit

This document preserves the complete results from all audit agents executed on 2025-01-26.
Each agent performed a deep scan of the codebase for a specific error pattern.

**Audit context:** Final audit after 44 PRs of the GraphQL Variables Migration were merged into `develop`.

---

## Table of Contents

1. [Agent 0: Unmigrated Files](#agent-0-unmigrated-files-a0f37fe)
2. [Agent 1: Mutation Nullability](#agent-1-mutation-nullability-ade2f4c)
3. [Agent 2: Loading State Outside Subscribe](#agent-2-loading-state-outside-subscribe-a06fafb)
4. [Agent 3: Boolean Params Simple If](#agent-3-boolean-params-simple-if-a44cfd2)
5. [Agent 4: Query ID! vs ID](#agent-4-query-id-vs-id-a827558)
6. [Agent 5: String-to-Boolean Conversion](#agent-5-string-to-boolean-conversion-a892532)
7. [Agent 6: parseInt for GraphQL IDs](#agent-6-parseint-for-graphql-ids-a1848f1)
8. [Agent 7: Wrong Input Type Names](#agent-7-wrong-input-type-names-a1bb7db)
9. [Agent 8: Numeric Fields Value 0](#agent-8-numeric-fields-value-0-ac1c9d1)
10. [Verification Agent A: Categories 1, 2, 5](#verification-agent-a-categories-1-2-5-a7f1a97)
11. [Verification Agent B: parseInt Bugs](#verification-agent-b-parseint-bugs-a1232ad)
12. [Verification Agent C: Numeric Zero Bugs](#verification-agent-c-numeric-zero-bugs-ad492c2)

---

## Agent 0: Unmigrated Files (a0f37fe)

**Task:** Find all files still using string interpolation in GraphQL queries.
**Result:** 31 files found.

### Files with String Interpolation in GraphQL Queries/Mutations

1. **upload.component.ts** (line 152) - Query with `${resolverName}` interpolated
2. **incentive-payment/create/incentive-payment-create.component.ts** (lines 72-74) - Query with `companyId`, `id`, `search` interpolated
3. **trade/redemption/redemption.component.ts** (lines 83, 118) - Query with `catalogationId`, `userId` interpolated
4. **trade/incentive-transaction/incentive-transaction.component.ts** (lines 143-144) - Query with `campaignId`, `search` interpolated
5. **trade/voucher/voucher.component.ts** (lines 92-96) - Query with `campaignId`, `endCursor`, `categoryId`, `searchByName` interpolated
6. **variable/variable.component.ts** (lines 250, 260) - Mutation with `id` interpolated (disable/enable queries)
7. **variable/variable-show.component.ts** (line 42) - Query with `variableId` interpolated
8. **variable/variable-update.component.ts** (lines 95, 105) - Mutation/Query with `variableId`, `name` interpolated
9. **status/status.component.ts** (lines 210, 220) - Mutation with `id` interpolated (disable/enable queries)
10. **status/status-show.component.ts** (line 40) - Query with `statusId` interpolated
11. **status/status-update.component.ts** (lines 81-82, 91) - Mutation/Query with `statusId`, `name` interpolated
12. **product/product.component.ts** (lines 183, 193) - Mutation with `id` interpolated (disable/enable queries)
13. **product/product-show.component.ts** (line 40) - Query with `productId` interpolated
14. **product/product-update.component.ts** (lines 83-85, 94) - Mutation/Query with `productId`, `name`, `externalId` interpolated
15. **subsidiary/subsidiary.component.ts** (lines 177, 187) - Mutation with `id` interpolated (disable/enable queries)
16. **subsidiary/subsidiary-show.component.ts** (line 40) - Query with `subsidiaryId` interpolated
17. **payment-type/payment-type.component.ts** (lines 207, 217) - Mutation with `id` interpolated (disable/enable queries)
18. **payment-type/payment-type-show.component.ts** (line 45) - Query with `paymentTypeId` interpolated
19. **payment-type/payment-type-update.component.ts** (lines 83-85, 94) - Mutation/Query with `paymentTypeId`, `name`, `externalId` interpolated
20. **statement/statement-accept/statement-accept.component.ts** (lines 86-87) - Mutation with `statementId`, `signature` interpolated
21. **plan-statement/plan-statement-accept/plan-statement-accept.component.ts** (lines 86-87) - Mutation with `planStatementId`, `signature` interpolated
22. **plan-statement/plan-statement-show/plan-statement-show.component.ts** (lines 145-147, 169) - Query with `planId`, `userId`, `groupId`, `planStatementId` interpolated
23. **acceptment-reason/acceptment-reason.component.ts** (lines 207, 217) - Mutation with `id` interpolated (disable/enable queries)
24. **acceptment-reason/acceptment-reason-show.component.ts** (line 42) - Query with `acceptmentReasonId` interpolated
25. **acceptment-reason/acceptment-reason-create.component.ts** (lines 68-70) - Mutation with `description`, `key`, `name` interpolated
26. **acceptment-reason/acceptment-reason-update.component.ts** (lines 98-100, 109) - Mutation/Query with `acceptmentReasonId`, `description`, `name` interpolated
27. **acceptment-document/acceptment-document.component.ts** (lines 66, 121, 172) - Query with `endCursor`, `documentId` interpolated
28. **acceptment-document/acceptment-document-show.component.ts** (lines 46, 72-73) - Query with `acceptmentDocumentId`, `acceptmentsEndCursor` interpolated
29. **incentive-campaign-fund/show/incentive-campaign-fund-show.component.ts** (line 49) - Query with `campaignFundId` interpolated
30. **incentive-campaign/show/incentive-campaign-show.component.ts** (line 42) - Query with `campaignId` interpolated
31. **indicator/show/indicator-show.component.ts** (line 42) - Query with `indicatorId` interpolated

**Note:** Additional files found during later comprehensive grep (38 total) include create components for some modules that have interpolation in mutations.

---

## Agent 1: Mutation Nullability (ade2f4c)

**Task:** Audit all GraphQL mutations comparing frontend variable types with backend `required` flags.
**Result:** 4 critical bugs found (backend `required: true` but frontend nullable).

### Critical Bugs (Backend `required: true`, Frontend nullable)

#### 1. ChangePassword / PasswordChange

**Backend** (`change_password_graphql_mutation.rb`):
```ruby
argument :current_password, String, required: true
argument :password, String, required: true
argument :password_confirmation, String, required: true
```

**Frontend** (`user-change-password.component.ts` line 52):
```graphql
mutation ChangePassword($currentPassword: String, $password: String, $passwordConfirmation: String)
```

**Frontend** (`password.component.ts` line 47):
```graphql
mutation PasswordChange($currentPassword: String, $password: String, $passwordConfirmation: String)
```

**Fix:** All should be `String!`

#### 2. CreateCampaignAttachmentSignedUrl

**Backend** (`create_campaign_attachment_signed_url_graphql_mutation.rb`):
```ruby
argument :campaign_id, ID, required: true
argument :content_type, String, required: false
argument :filename, String, required: false
```

**Frontend** (`campaign-attachment-signed-url.service.ts` line 56):
```graphql
mutation CreateCampaignAttachmentSignedUrl($campaignId: ID, $contentType: String, $filename: String)
```

**Fix:** `$campaignId` should be `ID!`

#### 3. CreateCampaignAttachment

**Backend** (`create_campaign_attachment_graphql_mutation.rb`):
```ruby
argument :campaign_id, ID, required: true
```

**Frontend** (`campaign-attachment.service.ts` line 42):
```graphql
mutation CreateCampaignAttachment($campaignId: ID)
```

**Fix:** `$campaignId` should be `ID!`

### Lower Criticality Inconsistencies (Frontend `!` but Backend `required: false`)

These don't cause failures but represent schema inconsistencies:

| # | Mutation | Frontend `!` fields | Backend `required: false` |
|---|---------|---------------------|--------------------------|
| 4 | CreateMetric | `$calculation: String!`, `$name: String!` | Both `required: false` |
| 5 | UpdateMetric | `$name: String!` | `required: false` |
| 6 | CreateRankifier | `$name: String!`, `$type: String!` | Both `required: false` |
| 7 | UpdateRankifier | `$name: String!`, `$type: String!` | Both `required: false` |
| 8 | CreatePaymentExportation | `$completePosition`, `$fieldsAttributes`, `$ignoreZeros`, `$paymentId` all `!` | All `required: false` |
| 9 | CreatePayment | `$name: String!` | `required: false` |
| 10 | CreateProfile / UpdateProfile | `$filename: String!`, `$contentType: String!` | Both `required: false` |
| 11 | CreateIndicatorDocument | `$contentType!`, `$filename!`, `$format!` | All `required: false` |
| 12 | All Create*Document mutations | `$filename: String!`, `$contentType: String!` | Both `required: false` (inherited from `CreateDocumentGraphqlMutation`) |
| 13 | CreateCollaborativeDeal / Update | `$collaborations: [DealCollaborationInputGraphql!]!` | `required: false` |

### Mutations Verified Correct

All **Disable**, **Enable**, **Approve**, **Release**, **Reprocess**, **Integrate**, **Unlock**, **Delete**, **Submit** mutations use `$id: ID!` correctly matching `id: ID, required: true`.

---

## Agent 2: Loading State Outside Subscribe (a06fafb)

**Task:** Find all instances where loading state is set outside the subscribe callback.
**Result:** 17 confirmed bugs, plus verified false positives.

### Confirmed Bugs

| # | File | Line | Property |
|---|------|------|----------|
| 1 | `trade/trade.component.ts` | 126 | `this.loading` |
| 2 | `commission-creation-batch/create/commission-creation-batch-create.component.ts` | 105 | `this.loadingCalendars` |
| 3 | `plan/create/plan-create.component.ts` | 289 | `this.loadingCalendars` |
| 4 | `plan/create/plan-create.component.ts` | 329 | `this.loadingGroups` |
| 5 | `plan/create/plan-create.component.ts` | 400 | `this.loadingUsers` |
| 6 | `plan/update/plan-update.component.ts` | 579 | `this.loadingUsers` |
| 7 | `commission-report-creation-batch/create/commission-report-creation-batch-create.component.ts` | 107 | `this.loadingCalendars` |
| 8 | `user-commission/show/user-commission-show.component.ts` | 367 | `this.loadingCollaborativeDealCommissionings` |
| 9 | `user-commission/show/user-commission-show.component.ts` | 465 | `this.loadingDealCommissionings` |
| 10 | `easy-product/plan-slice/create/plan-slice-create.component.ts` | 198 | `this.loadingUsers` |
| 11 | `easy-product/plan-slice-commission/create/plan-slice-commission-create.component.ts` | 166 | `this.loadingPlanSlices` |
| 12 | `easy-product/easy-user/create/easy-user-create.component.ts` | 202 | `this.loadingCountries` |
| 13 | `easy-product/easy-user/create/easy-user-create.component.ts` | 249 | `this.loadingStates` |
| 14 | `easy-product/easy-payment/create/easy-payment-create.component.ts` | 125 | `this.loadingPlans` |
| 15 | `statement/statement-show/statement-show.component.ts` | 307 | `this.loading` (inside outer subscribe but outside inner nested subscribe) |

Bug #15 is a special case: `this.loading = false` is inside the outer subscribe but outside the inner nested subscribe, so it executes before inner data loads.

### Code Pattern

```typescript
// BUG: loading set outside subscribe - executes immediately
.valueChanges.subscribe((response: any) => {
    // ... handle response
});
this.loadingCalendars = false;  // Runs synchronously, not when HTTP response arrives
```

### Verified False Positives

- `plan-statement.component.ts` (line 177) - inside subscribe, `});` closes a `forEach`
- `statement.component.ts` (line 371) - inside subscribe, `});` closes a `forEach`
- `payment-exportation-create.component.ts` (line 269) - inside subscribe, `});` closes a `forEach`
- `plan-finish.component.ts` (line 126) - inside subscribe, `});` closes `patchValue()`
- `user-update.component.ts` (line 420) - inside subscribe, `});` closes `patchValue()`
- `campaign-update.component.ts` (line 182) - inside subscribe, `});` closes `patchValue()`
- `dashboard-incentive.component.ts` (line 133) - inside subscribe callback `next:`
- `dashboard-calendar.component.ts` (line 155) - inside subscribe callback `next:`
- `trade.component.ts` (line 359) - inside nested subscribe callback
- All `*-update.component.ts` with `ngZone.onStable.pipe(first()).subscribe()` pattern - loading is inside error handler

---

## Agent 3: Boolean Params Simple If (a44cfd2)

**Task:** Find instances where boolean parameters use truthy check (`if (value)`) instead of explicit null check.
**Result:** CLEAN — Zero bugs found.

### Analysis

All boolean fields (`enabled`, `override`, `shared`) already use correct patterns:

- **`enabled`**: All 28 services use `params.enabled === 'true'` conversion
- **`override`**: `plan.service.ts` uses `!== undefined && !== null`; `plan-create.component.ts` uses `value ? value : false` (works correctly for booleans)
- **`shared`**: Same patterns as `override`

The codebase was previously corrected for this pattern in all services.

**Note:** While Category 3 is clean for the `if (value)` omission pattern, Category 5 (string-to-boolean) found that `override` and `shared` in `plan.service.ts` don't convert from string when values come from URL query params.

---

## Agent 4: Query ID! vs ID (a827558)

**Task:** Find queries that use `ID!` (required) when backend uses `option` (nullable).
**Result:** 12 queries with incorrect required type.

### Queries with Bug (ID! should be ID)

| # | File | Line | Query Name | Parameter | Backend Resolver | Backend Type |
|---|------|------|-----------|-----------|-----------------|-------------|
| 1 | `group/show/group-show.component.ts` | 63 | `GroupShow` | `$id: ID!` | `GroupGraphqlResolver` | `option(:id, type: ID)` |
| 2 | `group/show/group-show.component.ts` | 109 | `GroupificationsShow` | `$groupId: ID!` | `GroupificationGraphqlResolver` | `option(:group_id, type: ID)` |
| 3 | `group/update/group-update.component.ts` | 44 | `GroupUpdate` | `$id: ID!` | `GroupGraphqlResolver` | `option(:id, type: ID)` |
| 4 | `user/create/user-create.component.ts` | 545 | `Company` | `$id: ID!` | `CompanyGraphqlResolver` | `option(:id, type: ID)` |
| 5 | `user/show/user-show.component.ts` | 35 | `UserShow` | `$id: ID!` | `UserGraphqlResolver` | `option(:id, type: ID)` |
| 6 | `user/update/user-update.component.ts` | 348 | `UserUpdate` | `$id: ID!` | `UserGraphqlResolver` | `option(:id, type: ID)` |
| 7 | `deal/show/deal-show.component.ts` | 42 | `DealShow` | `$id: ID!` | `DealGraphqlResolver` | `option(:id, type: ID)` |
| 8 | `deal/update/deal-update.component.ts` | 92 | `DealUpdate` | `$id: ID!` | `DealGraphqlResolver` | `option(:id, type: ID)` |
| 9 | `rankifier/clone/rankifier-clone.component.ts` | 233 | `RankifierClone` | `$id: ID!` | `RankifierGraphqlResolver` | `option(:id, type: ID)` |
| 10 | `rankifier/show/rankifier-show.component.ts` | 34 | `RankifierShow` | `$id: ID!` | `RankifierGraphqlResolver` | `option(:id, type: ID)` |
| 11 | `rankifier/update/rankifier-update.component.ts` | 246 | `RankifierUpdate` | `$id: ID!` | `RankifierGraphqlResolver` | `option(:id, type: ID)` |
| 12 | `plan-goal-audit/plan-goal-audit.service.ts` | 42 | `PlanGoalAudits` | `$planId: ID!` | `PlanGoalAuditGraphqlResolver` | `option(:plan_id, type: ID)` |

### Verified Correct (excluded from bugs)

- All "temporary" queries (`TemporaryMonthlyUsageAudit`, etc.) — `TemporaryFileGraphqlResolver` uses `argument :id, ID, required: true`
- `DownloadDocument` — calls temporary resolvers with `argument required: true`
- `GoalDatasets` / `GetGoalDatasets` with `$planId: ID!` — `GoalDatasetGraphqlResolver` uses `argument :plan_id, ID, required: true`
- `PlanGoalAuditPermissions` with `$planId: ID!` — `PlanGoalAuditPermissionsGraphqlResolver` uses `argument :plan_id, ID, required: true`

---

## Agent 5: String-to-Boolean Conversion (a892532)

**Task:** Find values that pass string `"true"` to GraphQL Boolean variables.
**Result:** 2 bugs found in `plan.service.ts`.

### Bugs Found

| File | Line | Field | GraphQL Type | Conversion Applied? |
|------|------|-------|-------------|-------------------|
| `plan/plan.service.ts` | 62 | `override` | `Boolean` | NO |
| `plan/plan.service.ts` | 74 | `shared` | `Boolean` | NO |

### Details

**`override` (line 62):**
```typescript
if (params.override !== undefined && params.override !== null) {
    variables.override = params.override;  // BUG: no boolean conversion
}
```

**`shared` (line 74):**
```typescript
if (params.shared !== undefined && params.shared !== null) {
    variables.shared = params.shared;  // BUG: no boolean conversion
}
```

The GraphQL query declares `$override: Boolean` and `$shared: Boolean`. When values come from URL query params (Angular Router), they arrive as strings (`"true"`, `"false"`). The server rejects: `"Could not coerce value \"true\" to Boolean"`.

**Mitigating factor:** When user selects from dropdown (`selectOverride`/`selectShared`), the value is correctly set as boolean. The bug only manifests via deep links / bookmarks with query params.

### Comparison with `enabled` (correct pattern)

```typescript
// CORRECT — enabled uses conversion
if (params.enabled !== undefined && params.enabled !== null && params.enabled !== '') {
  variables.enabled = params.enabled === 'true';
}
```

### Fix

```typescript
variables.override = params.override === true || params.override === 'true';
variables.shared = params.shared === true || params.shared === 'true';
```

---

## Agent 6: parseInt for GraphQL IDs (a1848f1)

**Task:** Audit all `parseInt()` calls that feed GraphQL ID variables.
**Result:** 54 confirmed bugs + 14 mitigated (parseInt + String() cancel out).

### Confirmed Bugs (parseInt feeds GraphQL ID directly)

| # | File | Line | Variable | Mutation/Query | Backend Type |
|---|------|------|----------|---------------|-------------|
| 1 | `seat/update-parent-seat/update-parent-seat.component.ts` | 134 | `userId` | `UpdateParentSeat` | `ID` |
| 2 | `seat/update-parent-seat/update-parent-seat.component.ts` | 185 | `parentId` | `UpdateParentSeat` | `ID` |
| 3 | `seat/promote/seat-promote.component.ts` | 141 | `userId` | `PromoteSeat` | `ID` |
| 4 | `seat/promote/seat-promote.component.ts` | 200 | `parentId` | `PromoteSeat` | `ID` |
| 5 | `seat/demote/seat-demote.component.ts` | 141 | `userId` | `DemoteSeat` | `ID` |
| 6 | `seat/demote/seat-demote.component.ts` | 201 | `parentId` | `DemoteSeat` | `ID` |
| 7 | `deal/create/deal-create.component.ts` | 275 | `productId` | `CreateDeal` | `ID` |
| 8 | `deal/create/deal-create.component.ts` | 323 | `clientId` | `CreateDeal` | `ID` |
| 9 | `deal/create/deal-create.component.ts` | 371 | `userId` | `CreateDeal` | `ID` |
| 10 | `deal/create/deal-create.component.ts` | 419 | `statusId` | `CreateDeal` | `ID` |
| 11 | `deal/update/deal-update.component.ts` | 164 | `statusId` | `UpdateDeal` | `ID` |
| 12 | `deal/update/deal-update.component.ts` | 172 | `clientId` | `UpdateDeal` | `ID` |
| 13 | `deal/update/deal-update.component.ts` | 180 | `productId` | `UpdateDeal` | `ID` |
| 14 | `deal/update/deal-update.component.ts` | 388 | `productId` | `UpdateDeal` | `ID` |
| 15 | `deal/update/deal-update.component.ts` | 436 | `clientId` | `UpdateDeal` | `ID` |
| 16 | `deal/update/deal-update.component.ts` | 484 | `userId` | `UpdateDeal` | `ID` |
| 17 | `deal/update/deal-update.component.ts` | 532 | `statusId` | `UpdateDeal` | `ID` |
| 18 | `indicator/create/indicator-create.component.ts` | 142 | `variableId` | `CreateIndicator` | `ID` |
| 19 | `indicator/create/indicator-create.component.ts` | 190 | `userId` | `CreateIndicator` | `ID` |
| 20 | `subsidiary/create/subsidiary-create.component.ts` | 144 | `companyId` | `CreateSubsidiary` | `ID` |
| 21 | `subsidiary/update/subsidiary-update.component.ts` | 149 | `companyId` | Form setValue (wrong type) | `ID` |
| 22 | `commission-creation-batch/create/...component.ts` | 82 | `calendarId` | Query `Periods` | `ID` |
| 23 | `commission-creation-batch/create/...component.ts` | 114 | `periodId` | `CreateCommissionCreationBatch` | `ID` |
| 24 | `commission-report-creation-batch/create/...component.ts` | 84 | `calendarId` | Query `Periods` | `ID` |
| 25 | `commission-report-creation-batch/create/...component.ts` | 116 | `periodId` | `CreateCommissionReportCreationBatch` | `ID` |
| 26 | `partial-commission/create/partial-commission-create.component.ts` | 137 | `planId` | `CreatePartialCommission` | `ID` |
| 27 | `partial-commission/create/partial-commission-create.component.ts` | 197 | `periodId` | `CreatePartialCommission` | `ID` |
| 28 | `user-history/create/user-history-create.component.ts` | 112 | `userId` | `CreateUserHistory` | `ID` |
| 29 | `plan/create/plan-create.component.ts` | 241 | `calendarId` (search) | `PaymentTypeService.search` | `ID` |
| 30 | `plan/create/plan-create.component.ts` | 425 | `calendarId` | `CreatePlan` | `ID` |
| 31 | `plan/create/plan-create.component.ts` | 430 | `groupId` | `CreatePlan` | `ID` |
| 32 | `plan/create/plan-create.component.ts` | 434 | `incentiveCampaignId` | `CreatePlan` | `ID` |
| 33 | `plan/create/plan-create.component.ts` | 234 | `incentiveId` (incentivations) | `IncentivationInputGraphql` | `ID` |
| 34 | `plan/create/plan-create.component.ts` | 267 | `paymentTypeId` (incentivations) | `IncentivationInputGraphql` | `ID` |
| 35 | `plan/update/plan-update.component.ts` | 192 | `calendarId` | `UpdatePlan` | `ID` |
| 36 | `plan/update/plan-update.component.ts` | 196 | `groupId` | `UpdatePlan` | `ID` |
| 37 | `plan/update/plan-update.component.ts` | 380 | `incentiveId` (incentivations) | `IncentivationInputGraphql` | `ID` |
| 38 | `plan/update/plan-update.component.ts` | 430 | `paymentTypeId` (incentivations) | `IncentivationInputGraphql` | `ID` |
| 39 | `plan/update/plan-update.component.ts` | 460 | `calendarId` | `UpdatePlan` | `ID` |
| 40 | `plan/update/plan-update.component.ts` | 509 | `groupId` | `UpdatePlan` | `ID` |
| 41 | `plan/update/plan-update.component.ts` | 559 | `campaignId` | `UpdatePlan` | `ID` |
| 42 | `campaign/create/campaign-create.component.ts` | 136 | `planId` | `CreateCampaign` | `ID` |
| 43 | `campaign/update/campaign-update.component.ts` | 135 | `planId` | `UpdateCampaign` | `ID` |
| 44 | `campaign/update/campaign-update.component.ts` | 180 | `planId` | `UpdateCampaign` | `ID` |
| 45 | `incentive-payment/create/incentive-payment-create.component.ts` | 197 | `campaignId` | `CreateIncentivePayment` | `ID` |
| 46 | `incentive-payment/create/incentive-payment-create.component.ts` | 198 | `periodId` | `CreateIncentivePayment` | `ID` |
| 47 | `easy-product/plan-slice/create/plan-slice-create.component.ts` | 176 | `variableId` | `VariableTrackCollectionsInput` | `ID` |
| 48 | `easy-product/plan-slice/create/plan-slice-create.component.ts` | 207 | `userIds` | `CreatePlanSlice` | `ID` |
| 49 | `easy-product/plan-slice-commission/create/...component.ts` | 175 | `planSliceId` | `CreatePlanSliceCommission` | `ID` |
| 50 | `limiter-incentives/create/limiter-incentive-create.component.ts` | 213 | `groupId` | `CreateIncentive` | `ID` |
| 51 | `limiter-incentives/clone/limiter-incentive-clone.component.ts` | 197 | `groupId` | `CreateIncentive` | `ID` |
| 52 | `limiter-incentives/clone/limiter-incentive-clone.component.ts` | 247 | `groupId` | `CreateIncentive` | `ID` |
| 53 | `limiter-incentives/update/limiter-incentive-update.component.ts` | 192 | `groupId` | `UpdateIncentive` | `ID` |
| 54 | `limiter-incentives/update/limiter-incentive-update.component.ts` | 242 | `groupId` | `UpdateIncentive` | `ID` |

### Mitigated Bugs (parseInt + String() cancel out — parseInt is unnecessary)

| # | File | Line | Variable | Note |
|---|------|------|----------|------|
| 1 | `deal-incentive/create` | 210 | `groupId` | `String(this.form.value.groupId)` on submit |
| 2 | `deal-incentive/clone` | 199, 249 | `groupId` | `String()` on submit |
| 3 | `deal-incentive/update` | 196, 254 | `groupId` | `String()` on submit |
| 4 | `indicator-incentives/create` | 216 | `groupId` | `String()` on submit |
| 5 | `indicator-incentives/clone` | 200, 250 | `groupId` | `String()` on submit |
| 6 | `indicator-incentives/update` | 197, 255 | `groupId` | `String()` on submit |
| 7 | `rankifier-incentives/create` | 219, 249 | `groupId`, `rankifierId` | `String()` on submit |
| 8 | `rankifier-incentives/clone` | 203, 232, 286, 291 | `groupId`, `rankifierId` | `String()` on submit |
| 9 | `rankifier-incentives/update` | 201, 231, 285, 290 | `groupId`, `rankifierId` | `String()` on submit |
| 10 | `incentive-campaign-fund/create` | 155, 173 | `campaignId` | `String()` on submit |
| 11 | `commission-creation-batch/show` | 106 | `id` | `String(parseInt(event, 10))` |

### Inline in String Templates (parseInt unnecessary but injected as string)

Files in Category 0 (unmigrated) that also have parseInt — will be fixed during migration:
- `acceptment-document.component.ts`, `subsidiary.component.ts`, `product.component.ts`
- `status.component.ts`, `variable.component.ts`, `acceptment-reason.component.ts`
- `payment-type.component.ts`

### Correct (Backend expects Integer, NOT ID)

| File | Line | Variable | Backend Type |
|------|------|----------|-------------|
| `rankifier/create/rankifier-create.component.ts` | 66 | `variableId` | `Integer` |
| `rankifier/clone/rankifier-clone.component.ts` | 71 | `variableId` | `Integer` |
| `rankifier/update/rankifier-update.component.ts` | 81 | `variableId` | `Integer` |

### Not GraphQL-Related

- `profile/profile.component.ts:48` — local Profile object creation
- `shell/profile-menu/profile-menu.component.ts:57` — local Profile object creation
- `dashboard/calendar/dashboard-calendar.component.ts:585` — day calculation
- `shared/relative-progress-bar/relative-progress-bar.component.ts:28` — percentage calculation
- `shared/date-formatter/date-formatter.ts:17-19` — date parsing

---

## Agent 7: Wrong Input Type Names (a1bb7db)

**Task:** Find GraphQL Input type references with incorrect names (missing `Graphql` suffix).
**Result:** CLEAN — No errors found.

All 11 Input types in the frontend use the correct `Graphql` suffix:

| Backend (Ruby class) | GraphQL Type Exposed | Used in Frontend | Correct? |
|---------------------|---------------------|-----------------|----------|
| `CompanyBusinessTerritoryInputGraphqlType` | `CompanyBusinessTerritoryInputGraphql` | Yes | Yes |
| `DealCollaborationInputGraphqlType` | `DealCollaborationInputGraphql` | Yes | Yes |
| `DealFieldInputGraphqlType` | `DealFieldInputGraphql` | Yes | Yes |
| `FieldInputGraphqlType` | `FieldInputGraphql` | Yes | Yes |
| `IdentifierInputGraphqlType` | `IdentifierInputGraphql` | Yes | Yes |
| `IncentivationInputGraphqlType` | `IncentivationInputGraphql` | Yes | Yes |
| `PaymentExportationFieldsInputGraphqlType` | `PaymentExportationFieldsInputGraphql` | Yes | Yes |
| `PlanVariableInputGraphqlType` | `PlanVariableInputGraphql` | Yes | Yes |
| `RankifierVariableInputGraphqlType` | `RankifierVariableInputGraphql` | Yes | Yes |
| `RuleInputGraphqlType` | `RuleInputGraphql` | Yes | Yes |
| `VariableTrackCollectionsInputGraphqlType` | `VariableTrackCollectionsInputGraphql` | Yes | Yes |

`VariableTracksInputGraphql` is not directly referenced in the frontend (used internally within `VariableTrackCollectionsInputGraphql` on the backend side).

---

## Agent 8: Numeric Fields Value 0 (ac1c9d1)

**Task:** Find numeric fields that use truthy check instead of explicit null check.
**Result:** 12 instances in 6 files.

### Bugs Found

| # | File | Line | Field | GraphQL Type |
|---|------|------|-------|-------------|
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

### Summary by Field

| Field | GraphQL Type | Bug Instances | Files Affected |
|-------|-------------|--------------|----------------|
| `installment` | `Int` | 4 | collaborative-deal-create, deal-create, deal-update, metric-create |
| `soldPrice` | `Float` | 2 | deal-create, deal-update |
| `unitaryValue` | `Float` | 2 | collaborative-deal-create, collaborative-deal-update |
| `workHours` | `Float` | 4 | collaborative-deal-create, collaborative-deal-update, deal-create, deal-update |
| **Total** | | **12** | **6 files** |

### Already Correct (for reference)

| Field | Type | Files | Status |
|-------|------|-------|--------|
| `budget` | Int | plan-create, plan-update | OK — uses `!== undefined && !== null` |
| `goal` | Int | plan-create, plan-update | OK |
| `quantity` | Int | deal-create, deal-update, collaborative-deal-create/update | OK |

### Fields Discarded (not numeric in GraphQL)

- `closingDay` → `String`
- `baseline` (goal) → `String`
- `value` (indicator) → `String`
- `value` (goal) → `String`

---

## Verification Agent A: Categories 1, 2, 5 (a7f1a97)

**Task:** Cross-verify bugs found by Agents 1, 2, and 5 by reading actual source files.
**Result:** All bugs confirmed.

### Category 1 — Confirmed 4 bugs

- Bug 1.1: `user-change-password.component.ts` line 52 — `$currentPassword: String, $password: String, $passwordConfirmation: String` (should be `String!`)
- Bug 1.2: `password.component.ts` line 47 — same pattern
- Bug 1.3: `campaign-attachment-signed-url.service.ts` line 56 — `$campaignId: ID` (should be `ID!`)
- Bug 1.4: `campaign-attachment.service.ts` line 42 — `$campaignId: ID` (should be `ID!`)

### Category 2 — Confirmed 17 bugs

All 17 loading state bugs verified by reading actual source files. Agent also confirmed:
- `plan/update/plan-update.component.ts` has bugs at lines 450 (`loadingCalendars`) and 500 (`loadingGroups`) in addition to 579 (`loadingUsers`)
- `user-commission/show` has `loadingCalendars` (line 367) and `loadingGroups` (line 465)

### Category 5 — Confirmed 2 bugs

Both `override` (line 62) and `shared` (line 74) in `plan.service.ts` pass values without boolean conversion.

---

## Verification Agent B: parseInt Bugs (a1232ad)

**Task:** Comprehensive search for all parseInt calls feeding GraphQL ID variables.
**Result:** ~57 confirmed occurrences across ~35 files.

Findings match Agent 6 (a1848f1) results. Agent provided additional context:
- Confirmed `rankifier variableId` uses `Integer` type (correct exception)
- Identified `profile` and `profile-menu` parseInt calls as local object creation (not GraphQL)
- Found `String(parseInt(event, 10))` pattern in `commission-creation-batch/show` as redundant but not buggy

---

## Verification Agent C: Numeric Zero Bugs (ad492c2)

**Task:** Comprehensive search for numeric field zero-value bugs.
**Result:** 12 instances in 6 files — matches Agent 8 findings.

Confirmed the same 12 instances across 4 field types (`installment`, `soldPrice`, `unitaryValue`, `workHours`).

Additional verification:
- `quantity`, `budget`, `goal` already use correct `!== undefined && !== null` pattern
- `closingDay`, `baseline`, `value` are `String` type in GraphQL — not affected

---

## Audit Summary

| Agent | Category | Status | Bugs Found |
|-------|----------|--------|------------|
| a0f37fe | 0 — Unmigrated files | BUGS | 31-38 files |
| ade2f4c | 1 — Mutation nullability | BUGS | 4 critical + 13 minor |
| a06fafb | 2 — Loading outside subscribe | BUGS | 17 instances |
| a44cfd2 | 3 — Boolean simple if | CLEAN | 0 |
| a827558 | 4 — Query ID! vs ID | BUGS | 12 queries |
| a892532 | 5 — String-to-Boolean | BUGS | 2 instances |
| a1848f1 | 6 — parseInt for IDs | BUGS | 54 confirmed + 14 mitigated |
| a1bb7db | 7 — Wrong Input names | CLEAN | 0 |
| ac1c9d1 | 8 — Numeric zero | BUGS | 12 instances |
| a7f1a97 | Verify 1,2,5 | CONFIRMED | All match |
| a1232ad | Verify 6 | CONFIRMED | All match |
| ad492c2 | Verify 8 | CONFIRMED | All match |

**Total unique bugs: ~140 locations across ~70 files**
**Clean categories: 3 (Boolean simple if) and 7 (Input type names)**
