# TASKS — GraphQL Variables Migration

**Status:** COMPLETED ✅
**Total:** ~140 files migrated | **Total PRs:** 44 | **All PRs Merged**

---

# PR STATUS

## Released PRs

| GitHub PR | Module | Release |
|-----------|--------|---------|
| #5880 | Attachment | 1.253.0 |
| #5881 | Easy Product | 1.253.0 |
| #5896 | Easy Product (hotfix) | 1.253.0 |
| #5887 | Campaign | 1.253.0 |
| #5895 | Plan | 1.253.0 |
| #5898 | Plan Participation | 1.253.0 |
| #5899 | Indicator Incentives | 1.253.0 |
| #5900 | Deal Incentive | 1.253.0 |
| #5901 | Limiter Incentives | 1.253.0 |
| #5902 | Rankifier Incentives | 1.253.0 |
| #5913 | Redemption Incentives | 1.253.3 |
| #5914 | Rankifier | 1.253.3 |
| #5915 | Group | 1.253.3 |
| #5916 | User | 1.253.3 |
| #5917 | Deal | 1.253.3 |
| #5921 | Temporary Services (29 files) | 1.253.4 |
| #5923 | Fix parseInt() for GraphQL ID variables | 1.253.4 |
| #5924 | Misc | 1.253.5 |
| #5929 | Documents (Client, Deal, Goal) | 1.253.5 |
| #5930 | Documents 2 | 1.253.5 |
| #5931 | User Audit | 1.253.5 |
| #5933 | Documents 4 | 1.253.5 |
| #5934 | Audits | 1.253.5 |
| #5935 | Plan Misc | 1.253.5 |
| #5936 | Commission Batches | 1.253.5 |
| #5937 | Commission Events | 1.253.5 |
| #5938 | Documents 3 | 1.253.5 |
| #5939 | Goal | 1.253.5 |
| #5940 | Commission | 1.253.5 |
| #5941 | Collaborative Deal | 1.253.5 |
| #5942 | Payment | 1.253.5 |
| #5943 | Metric | 1.253.5 |
| #5944 | Dashboard | 1.253.5 |
| #5945 | Fix GraphQL Input Type Names (hotfix) | 1.253.5 |

## Merged PRs (Phase 2 — Friday Batch)

| GitHub PR | Module |
|-----------|--------|
| #5947 | Calendar + Calendar Audit |
| #5948 | Client |
| #5949 | Company |
| #5951 | Plan (7 files) |
| #5952 | Misc single-file modules (21 files) |

## Merged PRs (Phase 2 — Thread PRs)

| GitHub PR | Branch | Module |
|-----------|--------|--------|
| #5959 | feature/graphql-vars-thread-1 | acceptment, dashboard, deal |
| #5960 | feature/graphql-vars-thread-2 | incentive, indicator |
| #5961 | feature/graphql-vars-thread-3 | statement, partial-commission, payment |
| #5962 | feature/graphql-vars-thread-4 | indicator, subsidiary, seat |
| #5963 | feature/graphql-vars-thread-5 | variable, status, product, user-history, trade, upload |

## Originally Planned PRs #10-53 — SUPERSEDED

PRs #10 through #53 below were the original individual PR plan. All files from these PRs were consolidated into the thread-based execution (PRs #5947-#5952 and #5959-#5963). The individual PR plan is kept below as historical reference only.

---

## PR #1: Attachment Services (14 files) — MERGED (#5880)

**Branch:** `feature/graphql-vars-attachment`
**Status:** COMPLETED - No issues

- [x] `src/app/attachment/acceptment-document-attachment.service.ts`
- [x] `src/app/attachment/client-document-attachment.service.ts`
- [x] `src/app/attachment/collaborative-deal-document-attachment.service.ts`
- [x] `src/app/attachment/deal-document-attachment.service.ts`
- [x] `src/app/attachment/goal-document-attachment.service.ts`
- [x] `src/app/attachment/group-document-attachment.service.ts`
- [x] `src/app/attachment/incentive-document-attachment.service.ts`
- [x] `src/app/attachment/indicator-document-attachment.service.ts`
- [x] `src/app/attachment/kpi-document-attachment.service.ts`
- [x] `src/app/attachment/password-document-attachment.service.ts`
- [x] `src/app/attachment/product-document-attachment.service.ts`
- [x] `src/app/attachment/user-document-attachment.service.ts`
- [x] `src/app/attachment/user-identifier-document-attachment.service.ts`
- [x] `src/app/attachment/variable-document-attachment.service.ts`

---

## PR #2: Easy Product (11 files) — MERGED (#5881 + #5896)

**Branch:** `feature/graphql-vars-easy-product`
**Status:** COMPLETED - Issues fixed in PR #5896

- [x] `src/app/easy-product/easy-payment/create/easy-payment-create.component.ts`
- [x] `src/app/easy-product/easy-user-document/create/easy-user-document-create.service.ts`
- [x] `src/app/easy-product/easy-user/create/easy-user-create.component.ts`
- [x] `src/app/easy-product/easy-variable-document/create/easy-variable-document-create.service.ts`
- [x] `src/app/easy-product/plan-slice-commission/create/plan-slice-commission-create.component.ts`
- [x] `src/app/easy-product/plan-slice-commission/create/plan-slice-commission-kpi-document-create.service.ts`
- [x] `src/app/easy-product/plan-slice-commission/plan-slice-commission.service.ts`
- [x] `src/app/easy-product/plan-slice-commission/reprocess/plan-slice-commission-reprocess.component.ts`
- [x] `src/app/easy-product/plan-slice-commission/show/plan-slice-commission-show.component.ts`
- [x] `src/app/easy-product/plan-slice/plan-slice.service.ts`
- [x] `src/app/easy-product/plan-slice/show/plan-slice-show.component.ts`

---

## PR #3: Campaign (9 files) — MERGED (#5887)

**Branch:** `feature/graphql-vars-campaign`
**Status:** COMPLETED - Release 1.253.0

- [x] `src/app/campaign/campaign-attachment-signed-url.service.ts`
- [x] `src/app/campaign/campaign-attachment.service.ts`
- [x] `src/app/campaign/campaign.component.ts`
- [x] `src/app/campaign/campaign.service.ts`
- [x] `src/app/campaign/create/campaign-create.component.ts`
- [x] `src/app/campaign/show/campaign-show.component.ts`
- [x] `src/app/campaign/temporary-campaign.service.ts`
- [x] `src/app/campaign/update/campaign-update.component.ts`
- [x] `src/app/campaign/upload-file/campaign-upload-file.component.ts`

---

## PR #4: Plan (8 files) — MERGED (#5895)

**Branch:** `feature/graphql-vars-plan`
**Status:** COMPLETED - Release 1.253.0

- [x] `src/app/plan/create/plan-create.component.ts`
- [x] `src/app/plan/finish/plan-finish.component.ts`
- [x] `src/app/plan/participation-approval-batch/new/plan-participation-approval-batch-new.component.ts`
- [x] `src/app/plan/plan-responsible.service.ts`
- [x] `src/app/plan/plan.component.ts`
- [x] `src/app/plan/plan.service.ts`
- [x] `src/app/plan/show/plan-show.component.ts`
- [x] `src/app/plan/update/plan-update.component.ts`

---

## PR #5: Plan Participation (7 files) — MERGED (#5898)

**Branch:** `feature/graphql-vars-plan-participation`
**Status:** COMPLETED - Release 1.253.0

- [x] `src/app/plan-participation/approval-bach/pending/plan-participation-approval-batch-pending.service.ts`
- [x] `src/app/plan-participation/approval-bach/plan-participation-approval-batch.component.ts`
- [x] `src/app/plan-participation/approval-bach/plan-participation-approval-batch.service.ts`
- [x] `src/app/plan-participation/approval-bach/show/plan-participation-approval-batch-show.component.ts`
- [x] `src/app/plan-participation/plan-participation.component.ts`
- [x] `src/app/plan-participation/plan-participation.service.ts`
- [x] `src/app/plan-participation/show/plan-participation-show.component.ts`

---

## PR #6: Indicator Incentives (6 files) — MERGED (#5899)

**Branch:** `feature/graphql-vars-indicator-incentives`
**Status:** COMPLETED - Release 1.253.0

- [x] `src/app/indicator-incentives/clone/indicator-incentive-clone.component.ts`
- [x] `src/app/indicator-incentives/create/indicator-incentive-create.component.ts`
- [x] `src/app/indicator-incentives/indicator-incentives.component.ts`
- [x] `src/app/indicator-incentives/indicator-incentives.service.ts`
- [x] `src/app/indicator-incentives/show/indicator-incentive-show.component.ts`
- [x] `src/app/indicator-incentives/update/indicator-incentive-update.component.ts`

---

## PR #7: Deal Incentive (6 files) — MERGED (#5900)

**Branch:** `feature/graphql-vars-deal-incentive`
**Status:** COMPLETED - Release 1.253.0

- [x] `src/app/deal-incentive/clone/deal-incentive-clone.component.ts`
- [x] `src/app/deal-incentive/create/deal-incentive-create.component.ts`
- [x] `src/app/deal-incentive/deal-incentive.component.ts`
- [x] `src/app/deal-incentive/deal-incentive.service.ts`
- [x] `src/app/deal-incentive/show/deal-incentive-show.component.ts`
- [x] `src/app/deal-incentive/update/deal-incentive-update.component.ts`

---

## PR #8: Limiter Incentives (6 files) — MERGED (#5901)

**Branch:** `feature/graphql-vars-limiter-incentives`
**Status:** COMPLETED - Release 1.253.0

- [x] `src/app/limiter-incentives/clone/limiter-incentive-clone.component.ts`
- [x] `src/app/limiter-incentives/create/limiter-incentive-create.component.ts`
- [x] `src/app/limiter-incentives/limiter-incentives.component.ts`
- [x] `src/app/limiter-incentives/limiter-incentives.service.ts`
- [x] `src/app/limiter-incentives/show/limiter-incentive-show.component.ts`
- [x] `src/app/limiter-incentives/update/limiter-incentive-update.component.ts`

---

## PR #9: Rankifier Incentives (6 files) — MERGED (#5902)

**Branch:** `feature/graphql-vars-rankifier-incentives`
**Status:** COMPLETED - Release 1.253.0

- [x] `src/app/rankifier-incentives/clone/rankifier-incentive-clone.component.ts`
- [x] `src/app/rankifier-incentives/create/rankifier-incentive-create.component.ts`
- [x] `src/app/rankifier-incentives/rankifier-incentives.component.ts`
- [x] `src/app/rankifier-incentives/rankifier-incentives.service.ts`
- [x] `src/app/rankifier-incentives/show/rankifier-incentive-show.component.ts`
- [x] `src/app/rankifier-incentives/update/rankifier-incentive-update.component.ts`

---

## PR #10: Redemption Incentives (6 files)

**Branch:** `feature/graphql-vars-redemption-incentives`

- [x] `src/app/redemption-incentives/clone/redemption-incentive-clone.component.ts`
- [x] `src/app/redemption-incentives/create/redemption-incentive-create.component.ts`
- [x] `src/app/redemption-incentives/redemption-incentives.component.ts`
- [x] `src/app/redemption-incentives/redemption-incentives.service.ts`
- [x] `src/app/redemption-incentives/show/redemption-incentive-show.component.ts`
- [x] `src/app/redemption-incentives/update/redemption-incentive-update.component.ts`

---

## PR #11: Rankifier (6 files)

**Branch:** `feature/graphql-vars-rankifier`

- [x] `src/app/rankifier/clone/rankifier-clone.component.ts`
- [x] `src/app/rankifier/create/rankifier-create.component.ts`
- [x] `src/app/rankifier/rankifier.component.ts`
- [x] `src/app/rankifier/rankifier.service.ts`
- [x] `src/app/rankifier/show/rankifier-show.component.ts`
- [x] `src/app/rankifier/update/rankifier-update.component.ts`

---

## PR #12: Group (6 files)

**Branch:** `feature/graphql-vars-group`

- [x] `src/app/group/finish/group-finish.component.ts`
- [x] `src/app/group/group.component.ts`
- [x] `src/app/group/group.service.ts`
- [x] `src/app/group/show/group-show.component.ts`
- [x] `src/app/group/start/group-start.component.ts`
- [x] `src/app/group/update/group-update.component.ts`

---

## PR #13: User (5 files)

**Branch:** `feature/graphql-vars-user`

- [x] `src/app/user/create/user-create.component.ts`
- [x] `src/app/user/show/user-show.component.ts`
- [x] `src/app/user/update/user-update.component.ts`
- [x] `src/app/user/user.component.ts`
- [x] `src/app/user/user.service.ts`

---

## PR #14: Deal (5 files)

**Branch:** `feature/graphql-vars-deal`

- [x] `src/app/deal/create/deal-create.component.ts`
- [x] `src/app/deal/deal.component.ts`
- [x] `src/app/deal/deal.service.ts`
- [x] `src/app/deal/show/deal-show.component.ts`
- [x] `src/app/deal/update/deal-update.component.ts`

---

## PR #15: Goal (5 files)

**Branch:** `feature/graphql-vars-goal`

- [x] `src/app/goal/create/goal-create.component.ts`
- [x] `src/app/goal/goal.component.ts`
- [x] `src/app/goal/goal.service.ts`
- [x] `src/app/goal/show/goal-show.component.ts`
- [x] `src/app/goal/update/goal-update.component.ts`

---

## PR #16: Commission (5 files)

**Branch:** `feature/graphql-vars-commission`

- [x] `src/app/commission/commission.component.ts`
- [x] `src/app/commission/commission.service.ts`
- [x] `src/app/commission/create/commission-create.component.ts`
- [x] `src/app/commission/show/commission-show.component.ts`
- [x] `src/app/commission/temporary-commission.service.ts`

---

## PR #17: Collaborative Deal (5 files)

**Branch:** `feature/graphql-vars-collaborative-deal`

- [x] `src/app/collaborative-deal/collaborative-deal.component.ts`
- [x] `src/app/collaborative-deal/collaborative-deal.service.ts`
- [x] `src/app/collaborative-deal/create/collaborative-deal-create.component.ts`
- [x] `src/app/collaborative-deal/show/collaborative-deal-show.component.ts`
- [x] `src/app/collaborative-deal/update/collaborative-deal-update.component.ts`

---

## PR #18: Payment (5 files)

**Branch:** `feature/graphql-vars-payment`

- [x] `src/app/payment/create/payment-create.component.ts`
- [x] `src/app/payment/exportation/payment-exportation-create.component.ts`
- [x] `src/app/payment/payment.component.ts`
- [x] `src/app/payment/payment.service.ts`
- [x] `src/app/payment/show/payment-show.component.ts`

---

## PR #19: Metric (5 files)

**Branch:** `feature/graphql-vars-metric`

- [x] `src/app/metric/create/metric-create.component.ts`
- [x] `src/app/metric/metric.component.ts`
- [x] `src/app/metric/metric.service.ts`
- [x] `src/app/metric/show/metric-show.component.ts`
- [x] `src/app/metric/update/metric-update.component.ts`

---

## PR #20: Dashboard (5 files)

**Branch:** `feature/graphql-vars-dashboard`

- [x] `src/app/dashboard/calendar/dashboard-calendar.component.ts`
- [x] `src/app/dashboard/incentive/dashboard-incentive.component.ts`
- [x] `src/app/dashboard/incentive/detail/dashboard-incentive-detail.component.ts`
- [x] `src/app/dashboard/maps-america/dashboard-maps-america.component.ts`
- [x] `src/app/dashboard/plan/dashboard-plan.component.ts`

---

## PR #21: Company (4 files)

**Branch:** `feature/graphql-vars-company`

- [x] `src/app/company/company.component.ts`
- [x] `src/app/company/company.service.ts`
- [x] `src/app/company/create/company-create.component.ts`
- [x] `src/app/company/update/company-update.component.ts`

---

## PR #22: Client (4 files)

**Branch:** `feature/graphql-vars-client`

- [x] `src/app/client/client.component.ts`
- [x] `src/app/client/client.service.ts`
- [x] `src/app/client/show/client-show.component.ts`
- [x] `src/app/client/update/client-update.component.ts`

---

## PR #23: Product (4 files)

**Branch:** `feature/graphql-vars-product`

- [x] `src/app/product/product.component.ts`
- [x] `src/app/product/product.service.ts`
- [x] `src/app/product/show/product-show.component.ts`
- [x] `src/app/product/update/product-update.component.ts`

---

## PR #24: Variable (4 files)

**Branch:** `feature/graphql-vars-variable`

- [x] `src/app/variable/show/variable-show.component.ts`
- [x] `src/app/variable/update/variable-update.component.ts`
- [x] `src/app/variable/variable.component.ts`
- [x] `src/app/variable/variable.service.ts`

---

## PR #25: Indicator (4 files)

**Branch:** `feature/graphql-vars-indicator`

- [x] `src/app/indicator/create/indicator-create.component.ts`
- [x] `src/app/indicator/indicator.component.ts`
- [x] `src/app/indicator/indicator.service.ts`
- [x] `src/app/indicator/show/indicator-show.component.ts`

---

## PR #26: Status (4 files)

**Branch:** `feature/graphql-vars-status`

- [x] `src/app/status/show/status-show.component.ts`
- [x] `src/app/status/status.component.ts`
- [x] `src/app/status/status.service.ts`
- [x] `src/app/status/update/status-update.component.ts`

---

## PR #27: Subsidiary (4 files)

**Branch:** `feature/graphql-vars-subsidiary`

- [x] `src/app/subsidiary/show/subsidiary-show.component.ts`
- [x] `src/app/subsidiary/subsidiary.component.ts`
- [x] `src/app/subsidiary/subsidiary.service.ts`
- [x] `src/app/subsidiary/update/subsidiary-update.component.ts`

---

## PR #28: Payment Type (4 files)

**Branch:** `feature/graphql-vars-payment-type`

- [x] `src/app/payment-type/payment-type.component.ts`
- [x] `src/app/payment-type/payment-type.service.ts`
- [x] `src/app/payment-type/show/payment-type-show.component.ts`
- [x] `src/app/payment-type/update/payment-type-update.component.ts`

---

## PR #29: Calendar (4 files)

**Branch:** `feature/graphql-vars-calendar`

- [x] `src/app/calendar/calendar.component.ts`
- [x] `src/app/calendar/calendar.service.ts`
- [x] `src/app/calendar/show/calendar-show.component.ts`
- [x] `src/app/calendar/update/calendar-update.component.ts`

---

## PR #30: Acceptment Reason (4 files)

**Branch:** `feature/graphql-vars-acceptment-reason`

- [x] `src/app/acceptment-reason/acceptment-reason.component.ts`
- [x] `src/app/acceptment-reason/acceptment-reason.service.ts`
- [x] `src/app/acceptment-reason/show/acceptment-reason-show.component.ts`
- [x] `src/app/acceptment-reason/update/acceptment-reason-update.component.ts`

---

## PR #31: Trade (4 files)

**Branch:** `feature/graphql-vars-trade`

- [x] `src/app/trade/incentive-transaction/incentive-transaction.component.ts`
- [x] `src/app/trade/redemption/redemption.component.ts`
- [x] `src/app/trade/trade.component.ts`
- [x] `src/app/trade/voucher/voucher.component.ts`

---

## PR #32: Incentive Payment (4 files)

**Branch:** `feature/graphql-vars-incentive-payment`

- [x] `src/app/incentive-payment/create/incentive-payment-create.component.ts`
- [x] `src/app/incentive-payment/incentive-payment.service.ts`
- [x] `src/app/incentive-payment/incentive-user-payment.service.ts`
- [x] `src/app/incentive-payment/show/incentive-payment-show.component.ts`

---

## PR #33: User History (4 files)

**Branch:** `feature/graphql-vars-user-history`

- [x] `src/app/user-history/create/user-history-create.component.ts`
- [x] `src/app/user-history/user-history-show/user-history-show.component.ts`
- [x] `src/app/user-history/user-history.component.ts`
- [x] `src/app/user-history/user-history.service.ts`

---

## PR #34: Document Services - Client/Deal/Goal (12 files)

**Branch:** `feature/graphql-vars-documents-1`

- [x] `src/app/client-document/client-document.service.ts`
- [x] `src/app/client-document/create/client-document-create.service.ts`
- [x] `src/app/client-document/show/client-document-show.component.ts`
- [x] `src/app/client-document/temporary-client-document.service.ts`
- [x] `src/app/deal-document/create/deal-document-create.service.ts`
- [x] `src/app/deal-document/deal-document.service.ts`
- [x] `src/app/deal-document/show/deal-document-show.component.ts`
- [x] `src/app/deal-document/temporary-deal-document.service.ts`
- [x] `src/app/goal-document/create/goal-document-create.service.ts`
- [x] `src/app/goal-document/goal-document.service.ts`
- [x] `src/app/goal-document/show/goal-document-show.component.ts`
- [x] `src/app/goal-document/temporary-goal-document.service.ts`

---

## PR #35: Document Services - Group/Incentive/Indicator (12 files)

**Branch:** `feature/graphql-vars-documents-2`

- [x] `src/app/group-document/create/group-document-create.service.ts`
- [x] `src/app/group-document/group-document.service.ts`
- [x] `src/app/group-document/show/group-document-show.component.ts`
- [x] `src/app/group-document/temporary-group-document.service.ts`
- [x] `src/app/incentive-document/create/incentive-document-create.service.ts`
- [x] `src/app/incentive-document/incentive-document.service.ts`
- [x] `src/app/incentive-document/show/incentive-document-show.component.ts`
- [x] `src/app/incentive-document/temporary-incentive-document.service.ts`
- [x] `src/app/indicator-document/create/indicator-document-create.service.ts`
- [x] `src/app/indicator-document/indicator-document.service.ts`
- [x] `src/app/indicator-document/show/indicator-document-show.component.ts`
- [x] `src/app/indicator-document/temporary-indicator-document.service.ts`

---

## PR #36: Document Services - Product/User/Variable (12 files)

**Branch:** `feature/graphql-vars-documents-3`

- [x] `src/app/product-document/create/product-document-create.service.ts`
- [x] `src/app/product-document/product-document.service.ts`
- [x] `src/app/product-document/show/product-document-show.component.ts`
- [x] `src/app/product-document/temporary-product-document.service.ts`
- [x] `src/app/user-document/create/user-document-create.service.ts`
- [x] `src/app/user-document/show/user-document-show.component.ts`
- [x] `src/app/user-document/temporary-user-document.service.ts`
- [x] `src/app/user-document/user-document.service.ts`
- [x] `src/app/variable-document/create/variable-document-create.service.ts`
- [x] `src/app/variable-document/show/variable-document-show.component.ts`
- [x] `src/app/variable-document/temporary-variable-document.service.ts`
- [x] `src/app/variable-document/variable-document.service.ts`

---

## PR #37: Document Services - Password/Collaborative/User-Identifier (12 files)

**Branch:** `feature/graphql-vars-documents-4`

- [x] `src/app/password-document/create/password-document-create.service.ts`
- [x] `src/app/password-document/password-document.component.ts`
- [x] `src/app/password-document/password-document.service.ts`
- [x] `src/app/password-document/show/password-document-show.component.ts`
- [x] `src/app/collaborative-deal-document/collaborative-deal-document.service.ts`
- [x] `src/app/collaborative-deal-document/create/collaborative-deal-document-create.service.ts`
- [x] `src/app/collaborative-deal-document/show/collaborative-deal-document-show.component.ts`
- [x] `src/app/collaborative-deal-document/temporary-collaborative-deal-document.service.ts`
- [x] `src/app/user-identifier-document/create/user-identifier-document-create.service.ts`
- [x] `src/app/user-identifier-document/show/user-identifier-document-show.component.ts`
- [x] `src/app/user-identifier-document/temporary-user-identifier-action-document.service.ts`
- [x] `src/app/user-identifier-document/user-identifier-document.service.ts`

---

## PR #38: Acceptment Document (3 files)

**Branch:** `feature/graphql-vars-acceptment-document`

- [x] `src/app/acceptment-document/acceptment-document.component.ts`
- [x] `src/app/acceptment-document/create/acceptment-document-create.service.ts`
- [x] `src/app/acceptment-document/show/acceptment-document-show.component.ts`

---

## PR #39: Commission Batches (6 files)

**Branch:** `feature/graphql-vars-commission-batches`

- [x] `src/app/commission-creation-batch/commission-creation-batch.service.ts`
- [x] `src/app/commission-creation-batch/create/commission-creation-batch-create.component.ts`
- [x] `src/app/commission-creation-batch/show/commission-creation-batch-show.component.ts`
- [x] `src/app/commission-report-creation-batch/commission-report-creation-batch.service.ts`
- [x] `src/app/commission-report-creation-batch/create/commission-report-creation-batch-create.component.ts`
- [x] `src/app/commission-report-creation-batch/show/commission-report-creation-batch-show.component.ts`

---

## PR #40: Commission Events & Audit (7 files)

**Branch:** `feature/graphql-vars-commission-events`

- [x] `src/app/commission-indicator-audit/commission-indicator-audit.service.ts`
- [x] `src/app/commission-indicator-audit/create/commission-indicator-audit-create.component.ts`
- [x] `src/app/commission-indicator-audit/temporary-commission-indicator-audit.service.ts`
- [x] `src/app/commission-processing-event/commission-processing-event.component.ts`
- [x] `src/app/commission-processing-event/commission-processing-event.service.ts`
- [x] `src/app/commission-release-event/commission-release-event.component.ts`
- [x] `src/app/commission-release-event/commission-release-event.service.ts`

---

## PR #41: Partial Commission (3 files)

**Branch:** `feature/graphql-vars-partial-commission`

- [x] `src/app/partial-commission/create/partial-commission-create.component.ts`
- [x] `src/app/partial-commission/partial-commission.service.ts`
- [x] `src/app/partial-commission/show/partial-commission-show.component.ts`

---

## PR #42: Incentive Campaign (5 files)

**Branch:** `feature/graphql-vars-incentive-campaign`

- [x] `src/app/incentive-campaign/incentive-campaign.service.ts`
- [x] `src/app/incentive-campaign/show/incentive-campaign-show.component.ts`
- [x] `src/app/incentive-campaign-fund/create/incentive-campaign-fund-create.component.ts`
- [x] `src/app/incentive-campaign-fund/incentive-campaign-fund.service.ts`
- [x] `src/app/incentive-campaign-fund/show/incentive-campaign-fund-show.component.ts`

---

## PR #43: Plan Statement (5 files)

**Branch:** `feature/graphql-vars-plan-statement`

- [x] `src/app/plan-statement/plan-statement-show/plan-statement-show.component.ts`
- [x] `src/app/plan-statement/plan-statement.component.ts`
- [x] `src/app/plan-statement/plan-statement.service.ts`
- [x] `src/app/plan-statement-audit/plan-statement-audit.service.ts`
- [x] `src/app/plan-statement-audit/temporary-plan-statement-audit.service.ts`

---

## PR #44: Plan Misc (6 files)

**Branch:** `feature/graphql-vars-plan-misc`

- [x] `src/app/plan-acceptment/plan-acceptment.component.ts`
- [x] `src/app/plan-acceptment/plan-acceptment.service.ts`
- [x] `src/app/plan-goal-audit/plan-goal-audit.component.ts`
- [x] `src/app/plan-goal-audit/temporary-plan-goal-audit.service.ts`
- [x] `src/app/plan-rollback/plan-rollback.component.ts`
- [x] `src/app/plan-rollback/plan-rollback.service.ts`

---

## PR #45: Statement (4 files)

**Branch:** `feature/graphql-vars-statement`

- [x] `src/app/statement/statement-show/statement-show.component.ts`
- [x] `src/app/statement/statement.component.ts`
- [x] `src/app/statement-audit/statement-audit.service.ts`
- [x] `src/app/statement-audit/temporary-statement-audit.service.ts`

---

## PR #46: Payment Report (3 files)

**Branch:** `feature/graphql-vars-payment-report`

- [x] `src/app/payment-report/payment-report-permissions.service.ts`
- [x] `src/app/payment-report/payment-report.service.ts`
- [x] `src/app/payment-report/temporary-payment-report.service.ts`

---

## PR #47: Calendar Audit (3 files)

**Branch:** `feature/graphql-vars-calendar-audit`

- [x] `src/app/calendar-audit/calendar-audit.service.ts`
- [x] `src/app/calendar-audit/create/calendar-audit-create.component.ts`
- [x] `src/app/calendar-audit/temporary-calendar-audit.service.ts`

---

## PR #48: Audit Services - Group/Responsible/Variable (6 files)

**Branch:** `feature/graphql-vars-audits`

- [x] `src/app/group-audit/group-audit.service.ts`
- [x] `src/app/group-audit/temporary-group-audit.service.ts`
- [x] `src/app/responsible-audit/responsible-audit.service.ts`
- [x] `src/app/responsible-audit/temporary-responsible-audit.service.ts`
- [x] `src/app/variable-audit/temporary-variable-audit.service.ts`
- [x] `src/app/variable-audit/variable-audit.service.ts`

---

## PR #49: User Audit (6 files)

**Branch:** `feature/graphql-vars-user-audit`

- [x] `src/app/user-audit/temporary-user-audit.service.ts`
- [x] `src/app/user-audit/user-audit.service.ts`
- [x] `src/app/user-identifier-audit/temporary-user-identifier-audit.service.ts`
- [x] `src/app/user-identifier-audit/user-identifier-audit.service.ts`
- [x] `src/app/user-identifier/user-identifier.service.ts`
- [x] `src/app/user-identifier-action/user-identifier-action.service.ts`

---

## PR #50: Profile & Upload (4 files)

**Branch:** `feature/graphql-vars-profile-upload`

- [x] `src/app/profile/profile.service.ts`
- [x] `src/app/profile/temporary-profile.service.ts`
- [x] `src/app/upload/upload.component.ts`
- [x] `src/app/upload/upload.service.ts`

---

## PR #51: Seat (3 files)

**Branch:** `feature/graphql-vars-seat`

- [x] `src/app/seat/demote/seat-demote.component.ts`
- [x] `src/app/seat/promote/seat-promote.component.ts`
- [x] `src/app/seat/update-parent-seat/update-parent-seat.component.ts`

---

## PR #52: Monthly Usage (3 files)

**Branch:** `feature/graphql-vars-monthly-usage`

- [x] `src/app/monthly-usage/monthly-usage.component.ts`
- [x] `src/app/monthly-usage/temporary-monthly-usage-audit.service.ts`
- [x] `src/app/monthly-usage-responsibility/monthly-usage-responsibility.component.ts`

---

## PR #53: Misc Services (12 files)

**Branch:** `feature/graphql-vars-misc`

- [x] `src/app/app.service.ts`
- [x] `src/app/core/apollo.service.ts`
- [x] `src/app/deal-extraction/deal-extraction.component.ts`
- [x] `src/app/incentive/incentive.service.ts`
- [x] `src/app/incentive-transaction/incentive-transaction.service.ts`
- [x] `src/app/payment-exportation/temporary-payment-exportation.service.ts`
- [x] `src/app/period/period.service.ts`
- [x] `src/app/plan_statement_statistic/plan-statement-statistic.service.ts`
- [x] `src/app/register-type/register-type.service.ts`
- [x] `src/app/requirement/requirement.service.ts`
- [x] `src/app/shared/goal-widget/goal-widget.component.ts`
- [x] `src/app/signature/temporary-signature.service.ts`
- [x] `src/app/state/state.service.ts`
- [x] `src/app/statement-statistic/statement-statistic.service.ts`
- [x] `src/app/user-commission/show/user-commission-show.component.ts`
- [x] `src/app/user-payment/user-payment.component.ts`
- [x] `src/app/user-payment/user-payment.service.ts`

---

# Summary

| PR | Module | Files |
|----|--------|-------|
| #1 | Attachment | 14 |
| #2 | Easy Product | 11 |
| #3 | Campaign | 9 |
| #4 | Plan | 8 |
| #5 | Plan Participation | 7 |
| #6 | Indicator Incentives | 6 |
| #7 | Deal Incentive | 6 |
| #8 | Limiter Incentives | 6 |
| #9 | Rankifier Incentives | 6 |
| #10 | Redemption Incentives | 6 |
| #11 | Rankifier | 6 |
| #12 | Group | 6 |
| #13 | User | 5 |
| #14 | Deal | 5 |
| #15 | Goal | 5 |
| #16 | Commission | 5 |
| #17 | Collaborative Deal | 5 |
| #18 | Payment | 5 |
| #19 | Metric | 5 |
| #20 | Dashboard | 5 |
| #21 | Company | 4 |
| #22 | Client | 4 |
| #23 | Product | 4 |
| #24 | Variable | 4 |
| #25 | Indicator | 4 |
| #26 | Status | 4 |
| #27 | Subsidiary | 4 |
| #28 | Payment Type | 4 |
| #29 | Calendar | 4 |
| #30 | Acceptment Reason | 4 |
| #31 | Trade | 4 |
| #32 | Incentive Payment | 4 |
| #33 | User History | 4 |
| #34 | Documents 1 | 12 |
| #35 | Documents 2 | 12 |
| #36 | Documents 3 | 12 |
| #37 | Documents 4 | 12 |
| #38 | Acceptment Document | 3 |
| #39 | Commission Batches | 6 |
| #40 | Commission Events | 7 |
| #41 | Partial Commission | 3 |
| #42 | Incentive Campaign | 5 |
| #43 | Plan Statement | 5 |
| #44 | Plan Misc | 6 |
| #45 | Statement | 4 |
| #46 | Payment Report | 3 |
| #47 | Calendar Audit | 3 |
| #48 | Audits | 6 |
| #49 | User Audit | 6 |
| #50 | Profile & Upload | 4 |
| #51 | Seat | 3 |
| #52 | Monthly Usage | 3 |
| #53 | Misc | 17 |
| **TOTAL** | | **315** |

---

# Metrics

- **Total Files Migrated:** ~140
- **Total PRs Created:** 44 (34 released + 10 merged from Phase 2)
- **Execution Strategy:** Individual PRs for first 34, then consolidated thread-based parallel execution for remaining files
- **Status:** COMPLETED ✅ — All PRs merged into develop

---

# Autonomous Execution Rules

## Agreed Decisions

| Item | Decision |
|------|----------|
| Open PRs | Fix, amend, force push |
| New PRs | Based on latest `develop` |
| Commits | One per PR |
| Build | GitHub CI validates - user reports errors later |
| Changelog | Single entry at the end |
| Backend | `~/Projects/4Shark/app` for type verification |

---

## Required Patterns

### Pattern 1: INLINE Queries (DO NOT use private methods)
```typescript
// ❌ WRONG
this.service.mutation('name', this.myQuery(), variables)

private myQuery() {
  return `mutation...`;
}

// ✅ CORRECT
this.service.mutation(
  'name',
  `mutation MyMutation($id: ID!) {
    myMutation(id: $id) { id }
  }`,
  variables,
)
```

### Pattern 2: CONDITIONAL Variables (DO NOT use `|| undefined`)
```typescript
// ❌ WRONG - undefined becomes null in Ruby backend
variables: {
  search: value || undefined,
}

// ✅ CORRECT - only add if value exists
const variables: Record<string, any> = {};
if (value) {
  variables.search = value;
}
```

### Pattern 3: Always use EXPLICIT object notation (NO shorthand)
```typescript
// ❌ WRONG - shorthand notation inside objects
watchQuery({ query: gql`...`, variables })
{ id }

// ✅ CORRECT - always explicit key: value inside objects
watchQuery({ query: gql`...`, variables: variables })
{ id: id }

// NOTE: As function argument, use just the value:
// ✅ CORRECT - function argument
this.service.mutation('name', query, variables)
```

### Pattern 4: Always declare `variables` BEFORE the call
```typescript
// ❌ WRONG - inline in call
this.service.mutation('name', query, { id: String(event) })

// ✅ CORRECT - declare before
const variables: Record<string, any> = { id: String(event) };

this.service.mutation('name', query, variables)
```

### Pattern 5: IDs are simple strings (DO NOT convert unnecessarily)
```typescript
// ❌ WRONG - redundant conversion
String(parseInt(event, 10))

// ✅ CORRECT - GraphQL ID accepts string directly
String(event)
// or if already string:
event
```

### Pattern 6: Verify Types in Backend
```typescript
// Always check in ~/Projects/4Shark/app/app/graphql_*/
// Some mutations use Int instead of ID, String instead of ID, etc.
```

### Pattern 7: Blank lines BEFORE and AFTER multiline statements
```typescript
// ❌ WRONG - no blank line after multiline declaration or before if
const variables: Record<string, any> = {};
if (id) {
  variables.id = id;
}

const variables: Record<string, any> = {
  first: 9,
  enabled: true,
};
if (name) {
  variables.search = name;
}

// ✅ CORRECT - blank line after declaration and before if
const variables: Record<string, any> = {};

if (id) {
  variables.id = id;
}

const variables: Record<string, any> = {
  first: 9,
  enabled: true,
};

if (name) {
  variables.search = name;
}

// GENERAL RULE:
// - Blank line AFTER const/let declaration (especially if multiline)
// - Blank line BEFORE if/for/while/return when preceded by statement
// - Blank line AFTER if/for/while block if followed by another statement
```

### Pattern 8: Verify mutation/query names in backend
```typescript
// ❌ WRONG - wrong mutation name
mutation CreateCampaign($id: ID!) {
  createCampaign(id: $id) { ... }  // Used in UPDATE screen
}

// ✅ CORRECT - check file in backend
// ~/Projects/4Shark/app/app/graphql_mutations/update_campaign_graphql_mutation.rb
mutation UpdateCampaign($id: ID!, $name: String) {
  updateCampaign(id: $id, name: $name) { ... }
}

// ALWAYS verify:
// 1. Mutation/query name matches backend file
// 2. Required parameters (required: true) are included
// 3. Parameter types are correct (ID, Int, String, Boolean)
```

---

## Verification Checklist per PR

Before committing, verify ALL items:

- [x] No query/mutation uses string interpolation (`${variable}`)
- [x] No private method defines queries (inline directly in call)
- [x] No `|| undefined` in variables
- [x] Variables built conditionally with `if (value)`
- [x] Types verified in backend (`~/Projects/4Shark/app/app/graphql_*/`)
- [x] Mutation/query names match backend (create vs update!)
- [x] Required backend parameters are included (e.g., $id: ID!)
- [x] Blank lines BEFORE and AFTER multiline statements
- [x] Objects use explicit `{ key: value }`, NEVER shorthand `{ key }`
- [x] `const variables` declared BEFORE GraphQL call
- [x] `yarn prettier --write` executed on specific files

---

## Process for Open PRs (Correction)

```bash
# 1. Checkout branch
git checkout feature/graphql-vars-<module>

# 2. Apply fixes to files

# 3. Format
yarn prettier --write src/app/<module>/**/*.ts

# 4. Build to verify
yarn build

# 5. Amend and force push
git add .
git commit --amend --no-edit
git push --force
```

---

## Process for New PRs

```bash
# 1. Update develop
git checkout develop
git pull origin develop

# 2. Create branch
git checkout -b feature/graphql-vars-<module>

# 3. Make changes to files

# 4. Format ONLY changed files (DO NOT use **/*)
yarn prettier --write src/app/<module>/file1.ts src/app/<module>/file2.ts

# 5. Add ONLY module files (DO NOT use git add .)
git add src/app/<module>/

# 6. Verify only correct files are staged
git status

# 7. Single commit
git commit -m "fix(<module>): use GraphQL variables instead of string concatenation"

# 8. Push and create PR
git push -u origin feature/graphql-vars-<module>
gh pr create --base develop --title "fix(<module>): use GraphQL variables instead of string concatenation" --body "Converts <module> module GraphQL queries and mutations from string concatenation to use GraphQL variables."
```

**IMPORTANT:** Never use `git add .` or `yarn prettier --write **/*.ts` - always specify exact files to avoid including unrelated files.

---

# Correction History

## PR #5887 - Campaign — FIXED ✓

**Applied fixes:**
- Private methods converted to inline queries
- Bug fix: `updateCampaign` mutation corrected (was calling `createCampaign`)
- Parameter `$id: ID!` added to update mutation
- Blank lines added per pattern

## PR #5895 - Plan — FIXED ✓

**Applied fixes:**
- `value || undefined` replaced with conditional construction
- Blank lines added after `variables` declaration
- Blank lines added before `if` blocks

## PR #5960 (Thread 2) — FIXED ✓

**Applied fixes:**
- `incentive-campaign-fund-create.component.ts`: Removed conditional/fallback for `campaignId` and `value` — always assigned since they are required fields (Error 1)

## PR #5961 (Thread 3) — FIXED ✓

**Applied fixes:**
- `statement-show.component.ts`: Added `.flat()` to `rankifierVariableIds` — nested array from `.map().map()` was not flattened (string interpolation auto-flattened, GraphQL variables don't)
- `payment-type.service.ts`: Removed conditional for `id` in disable/enable mutations — always assigned `{ id: id }` since `$id: ID!` is required (Error 1)
- `statement-show.component.ts`: `commission.planId` without optional chaining — **NOT FIXED**, deferred to `error-handling-standardization` plan

## PR #5962 (Thread 4) — FIXED ✓

**Applied fixes:**
- `indicator-create.component.ts`: Moved `this.loadingVariables = false` inside subscribe callback (Error 2)

## PR #5963 (Thread 5) — FIXED ✓

**Applied fixes:**
- `upload.service.ts`: Added `query` method using `'upload'` connection name (was inheriting `AppService.query` which used first parameter as connection name, causing mismatch)

---

# Completion Note

**Date:** 2026-01-27

All 140 files have been successfully migrated from string interpolation to typed GraphQL variables. All 44 PRs are merged into develop. Bug fixes for issues discovered during the final audit were tracked and completed separately in the `graphql-variables-bugfix` plan. Remaining type safety issues (nullability contracts, `|| ''` defensive patterns for ID fields) are tracked in the `graphql-type-contract-standardization` plan for future work.
