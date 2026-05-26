# Fix Plan - PR #5792 (old-front-secure-downloads)

> **Note:** This fix plan refers to the legacy frontend that still exists on the `old-front` branch of the app-webclient repository.

## Identified Problem

The Secure Downloads migration to the `old-front` branch was done incorrectly:
- **HTML files were copied wholesale from master**, changing layout, structure, and CSS classes
- **TS files were copied wholesale from master**, pulling in dependencies that do not exist in old-front
- **Result**: ~7000 lines changed when it should be far fewer

### Example of the error (user-audit.component.html)

**Original old-front:**
```html
<div class="row">
  <div class="col-md-6 col-12">
    <h2 class="section-title" translate>user_audit.other</h2>
    <ul class="breadcrumb">
      <li>
        <p [routerLink]="['/users/']">{{ 'breadcrumb.list' | translate }} /</p>
      </li>
```

**What was done (WRONG — copied from master):**
```html
<section>
  <h1 class="title">{{ 'user_audit.other' | translate }}</h1>
  <div class="breadcrumbs">
    <span class="breadcrumb" [routerLink]="['/users/']">{{ 'user.other' | translate }}</span>
```

**What should have been done (CORRECT — minimal change):**
- Keep ALL the original HTML structure
- Only swap `href="{{ element.attachment?.file?.file?.publicUrl }}"` for `(click)="download($event, element)"`

---

## Current Build Error

```
Error: src/app/upload/upload.component.ts:131:35 - error TS2339: Property 'type' does not exist on type 'Document'.
```

**Cause**: `upload.component.ts` was copied from master and uses `document.type`, but the `Document` model in old-front does not have that property.

---

## Current PR Stats

| Type | Quantity |
|------|----------|
| Created files (correct) | 29 |
| Modified files | 99 |
| Lines added | ~3,277 |
| Lines removed | ~5,431 |

---

## Fix Plan

### Phase 1: Revert ALL modified files to the original old-front state

```bash
# List every modified file
git diff --diff-filter=M --name-only old-front...old-front-secure-downloads

# Revert each file to the old-front version
git checkout old-front -- <each-file>
```

**Files to revert (99 files):**

#### HTML (34 files):
- src/app/acceptment-document/acceptment-document.component.html
- src/app/calendar-audit/calendar-audit.component.html
- src/app/campaign/show/campaign-show.component.html
- src/app/client-document/client-document.component.html
- src/app/collaborative-deal-document/collaborative-deal-document.component.html
- src/app/commission-indicator-audit/commission-indicator-audit.component.html
- src/app/commission-report-creation-batch/show/commission-report-creation-batch-show.component.html
- src/app/commission/show/commission-show.component.html
- src/app/dashboard/calendar/dashboard-calendar.component.html
- src/app/deal-document/deal-document.component.html
- src/app/easy-product/plan-slice-commission/show/plan-slice-commission-show.component.html
- src/app/goal-document/goal-document.component.html
- src/app/group-audit/group-audit.component.html
- src/app/group-document/group-document.component.html
- src/app/home/home.component.html
- src/app/incentive-document/incentive-document.component.html
- src/app/indicator-document/indicator-document.component.html
- src/app/monthly-usage/monthly-usage.component.html
- src/app/payment/show/payment-show.component.html
- src/app/plan-statement-audit/plan-statement-audit.component.html
- src/app/plan-statement/plan-statement-show/plan-statement-show.component.html
- src/app/product-document/product-document.component.html
- src/app/responsible-audit/responsible-audit.component.html
- src/app/statement-audit/statement-audit.component.html
- src/app/statement/statement-show/statement-show.component.html
- src/app/upload/upload.component.html
- src/app/user-audit/user-audit.component.html
- src/app/user-document/user-document.component.html
- src/app/user-identifier-audit/user-identifier-audit.component.html
- src/app/user-identifier-document/user-identifier-document.component.html
- src/app/user/show/user-show.component.html
- src/app/user/user.component.html
- src/app/variable-audit/variable-audit.component.html
- src/app/variable-document/variable-document.component.html

#### TypeScript Components (30+ files):
- All `*.component.ts` listed in the diff

#### TypeScript Services (15+ files):
- All `*.service.ts` that are NOT `temporary*.service.ts`

#### TypeScript Models (4 files):
- src/app/accumulated-deal/accumulated-deal.model.ts
- src/app/attachment/attachment.model.ts
- src/app/campaign/campaign.model.ts
- src/app/core/authentication/user-credential.model.ts

#### Other:
- src/assets/scripts/card.js

### Phase 2: Keep ONLY the temporary service files (already correct)

**Files to KEEP (29 created files):**
- src/app/acceptment-document/acceptment-document.service.ts (new)
- src/app/calendar-audit/temporary-calendar-audit.service.ts
- src/app/campaign/temporary-campaign.service.ts
- src/app/client-document/temporary-client-document.service.ts
- src/app/collaborative-deal-document/temporary-collaborative-deal-document.service.ts
- src/app/commission-indicator-audit/temporary-commission-indicator-audit.service.ts
- src/app/commission/temporary-commission.service.ts
- src/app/deal-document/temporary-deal-document.service.ts
- src/app/deal-extraction/deal-extraction.service.ts (new)
- src/app/goal-document/temporary-goal-document.service.ts
- src/app/group-audit/temporary-group-audit.service.ts
- src/app/group-document/temporary-group-document.service.ts
- src/app/incentive-document/temporary-incentive-document.service.ts
- src/app/indicator-document/temporary-indicator-document.service.ts
- src/app/monthly-usage/temporary-monthly-usage-audit.service.ts
- src/app/payment-exportation/temporary-payment-exportation.service.ts
- src/app/payment-report/temporary-payment-report.service.ts
- src/app/plan-statement-audit/temporary-plan-statement-audit.service.ts
- src/app/product-document/temporary-product-document.service.ts
- src/app/profile/temporary-profile.service.ts
- src/app/responsible-audit/temporary-responsible-audit.service.ts
- src/app/shared/constants/document-resolver.map.ts
- src/app/statement-audit/temporary-statement-audit.service.ts
- src/app/user-audit/temporary-user-audit.service.ts
- src/app/user-document/temporary-user-document.service.ts
- src/app/user-identifier-audit/temporary-user-identifier-audit.service.ts
- src/app/user-identifier-document/temporary-user-identifier-action-document.service.ts
- src/app/variable-audit/temporary-variable-audit.service.ts
- src/app/variable-document/temporary-variable-document.service.ts

### Phase 3: Apply the CORRECT (minimal) migration

For each component that needs Secure Downloads, change ONLY:

#### 3.1 In the .component.ts file:

```typescript
// 1. Import the temporary service
import { TemporaryXxxService } from './temporary-xxx.service';

// 2. Inject in the constructor
constructor(
  // ... other existing services
  private temporaryXxxService: TemporaryXxxService,
) {}

// 3. Add the download() method
download(event: Event, element: any) {
  event.preventDefault();

  const id = element.id; // or element.attachment?.id depending on the case

  if (!id) {
    return;
  }

  this.temporaryXxxService.get(id).valueChanges.subscribe((response: any) => {
    const url = response.data?.temporaryXxx?.url;

    if (url) {
      window.location.href = url;
    }
  });
}
```

#### 3.2 In the .component.html file:

**BEFORE:**
```html
<a href="{{ element.attachment?.file?.file?.publicUrl }}">
  <i class="fas fa-cloud-download-alt"></i>
  {{ element.attachment?.file.file.filename }}
</a>
```

**AFTER:**
```html
<a href="#" (click)="download($event, element)">
  <i class="fas fa-cloud-download-alt"></i>
  {{ element.attachment?.filename }}
</a>
```

#### 3.3 In the .service.ts file (listing):

**BEFORE:**
```graphql
attachment {
  file {
    file {
      publicUrl
      filename
    }
  }
}
```

**AFTER:**
```graphql
attachment {
  id
  filename
}
```

---

## Components to migrate correctly

| Component | Temporary Service | Download Type |
|-----------|-------------------|---------------|
| acceptment-document | temporaryAcceptmentDocument | attachment |
| calendar-audit | temporaryCalendarAudit | audit |
| campaign-show | temporaryCampaign | campaign |
| client-document | temporaryClientDocument | attachment |
| collaborative-deal-document | temporaryCollaborativeDealDocument | attachment |
| commission-indicator-audit | temporaryCommissionIndicatorAudit | audit |
| commission-report-creation-batch-show | (uses commission) | batch |
| commission-show | temporaryCommission | attachment |
| dashboard-calendar | temporaryCampaign | campaign |
| deal-document | temporaryDealDocument | attachment |
| goal-document | temporaryGoalDocument | attachment |
| group-audit | temporaryGroupAudit | audit |
| group-document | temporaryGroupDocument | attachment |
| home | temporaryCampaign | campaign |
| incentive-document | temporaryIncentiveDocument | attachment |
| indicator-document | temporaryIndicatorDocument | attachment |
| monthly-usage | temporaryMonthlyUsageAudit | audit |
| payment-show | (multiple) | payment |
| plan-statement-audit | temporaryPlanStatementAudit | audit |
| plan-statement-show | (multiple) | statement |
| product-document | temporaryProductDocument | attachment |
| responsible-audit | temporaryResponsibleAudit | audit |
| statement-audit | temporaryStatementAudit | audit |
| statement-show | (multiple) | statement |
| upload | (document-resolver-map) | upload |
| user-audit | temporaryUserAudit | audit |
| user-document | temporaryUserDocument | attachment |
| user-identifier-audit | temporaryUserIdentifierAudit | audit |
| user-identifier-document | temporaryUserIdentifierActionDocument | attachment |
| user-show | temporaryProfile | profile |
| user (list) | (user) | user |
| variable-audit | temporaryVariableAudit | audit |
| variable-document | temporaryVariableDocument | attachment |

---

## Next Steps

1. **User decision**: confirm this plan is correct
2. **Run Phase 1**: revert all 99 modified files
3. **Run Phase 2**: ensure the 29 temporary service files are intact
4. **Run Phase 3**: apply the minimal migration file by file
5. **Build and tests**: verify everything works
6. **Update PR**: force push to update PR #5792

---

## Estimate of Correct Changes

| Type | Estimate |
|------|----------|
| Modified files | ~65 (vs 99 currently) |
| Lines per HTML | ~5-10 lines per file |
| Lines per TS | ~15-20 lines per file |
| Approximate total | ~600-800 lines (vs ~8700 currently) |
