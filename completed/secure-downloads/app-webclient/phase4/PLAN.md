# PLAN - Phase 4: Frontend Reports + UX Improvements

## Branches

| Branch | Base | Purpose | PR Target |
|--------|------|---------|-----------|
| `hotfix/1.247.5` | `master` | New frontend (full UX + secure downloads) | `master` |
| `hotfix/old-front-secure-downloads` (to create) | `old-front` | Legacy frontend (secure downloads only, simpler UX) | `old-front` |

## Objective

1. **Reports Frontend Migration**: Implement secure downloads for all report types (using new mutations from backend hotfix/2.218.9)
2. **UX Improvement (Customer Feedback)**: Standardize all download listings to show filename in first column + Actions menu with download button
3. **CRITICAL**: Migrate BOTH frontends (master AND old-front) to use secure downloads

---

## Part 1: UX Improvement - Standardize Download Listings

### Customer Feedback
> "We need to see the filename in the listing to control which file we're downloading"

### Current State (Audits & Documents - already migrated)
- Column shows download icon + "Download" text as a link
- User cannot see the filename before clicking
- No consistency between different listing pages

### Target State
- **Column 1**: Filename (plain text, no link)
- **Last Column**: "Actions" with three-dots menu containing Download option (if user has permission)

### Files to Update (Already Migrated - Need UX Fix)

**Audit Components (10 files):**
1. `calendar-audit/calendar-audit.component.html`
2. `commission-indicator-audit/commission-indicator-audit.component.html`
3. `group-audit/group-audit.component.html`
4. `plan-goal-audit/plan-goal-audit.component.html`
5. `plan-statement-audit/plan-statement-audit.component.html`
6. `responsible-audit/responsible-audit.component.html`
7. `statement-audit/statement-audit.component.html`
8. `user-audit/user-audit.component.html`
9. `user-identifier-audit/user-identifier-audit.component.html`
10. `variable-audit/variable-audit.component.html`

**Document Components (14 files):**
1. `acceptment-document/acceptment-document.component.html`
2. `client-document/client-document.component.html`
3. `collaborative-deal-document/collaborative-deal-document.component.html`
4. `deal-document/deal-document.component.html` (already has Actions menu - reference)
5. `goal-document/goal-document.component.html`
6. `group-document/group-document.component.html`
7. `incentive-document/incentive-document.component.html`
8. `indicator-document/indicator-document.component.html`
9. `kpi-document/kpi-document.component.html`
10. `password-document/password-document.component.html`
11. `product-document/product-document.component.html`
12. `user-document/user-document.component.html`
13. `user-identifier-document/user-identifier-document.component.html`
14. `variable-document/variable-document.component.html`

### Target Pattern (Based on deal-document)

**Header:**
```html
<div class="list-header">
  <span class="column-s">ID</span>
  <span class="column-xxl">{{ 'document.filename' | translate }}</span>  <!-- Changed from 'attachment' -->
  <!-- ... other columns ... -->
  <span class="column-s no-visible">.</span>  <!-- Actions column placeholder -->
</div>
```

**Row:**
```html
<div class="list-item">
  <span class="column-s">{{ item.id }}</span>
  <span class="column-xxl">{{ item.attachment?.file?.file?.filename }}</span>  <!-- Plain text, no link -->
  <!-- ... other columns ... -->
  <div class="menu-container" (click)="stopPropagation($event)">
    <button class="column-s" (click)="toggleMenu(item)">
      <span class="material-symbols-outlined">more_horiz</span>
    </button>
    <div class="custom-menu" *ngIf="activeMenuId === item?.id">
      <button
        *ngIf="canDownload(item)"
        (click)="download($event, item); closeMenu()"
        class="option option-active"
      >
        <span class="material-symbols-outlined">cloud_download</span>
        {{ 'actions.resource.download' | translate }}
      </button>
    </div>
  </div>
</div>
```

**Component additions needed:**
```typescript
activeMenuId: number | null = null;

toggleMenu(item: any) {
  this.activeMenuId = this.activeMenuId === item.id ? null : item.id;
}

stopPropagation(event: Event): void {
  event.stopPropagation();
}

closeMenu() {
  this.activeMenuId = null;
}

@HostListener('document:click', ['$event'])
onDocumentClick(event: Event) {
  const target = event.target as HTMLElement;
  if (!target.closest('.menu-container')) {
    this.closeMenu();
  }
}
```

---

## Part 2: Reports Frontend Migration

### Backend Mutations Available (from hotfix/2.218.9)

| Report Type | Mutation | Input | Returns |
|-------------|----------|-------|---------|
| Payment Report | `downloadPaymentReport` | `paymentReportId: ID!` | `PaymentReportDownloadGraphqlType` (backwards compatible) |
| Commission Report Creation Event | `downloadCommissionReportCreationEvent` | `commissionReportCreationEventId: ID!` | `TemporaryAttachmentGraphqlType` |
| Payment Exportation | `downloadPaymentExportation` | `paymentExportationId: ID!` | `TemporaryAttachmentGraphqlType` |
| Plan Statement Portable | `downloadPlanStatementPortable` | `planStatementPortableId: ID!` | `TemporaryAttachmentGraphqlType` |
| Plan Statement Portable Batch | `downloadPlanStatementPortableBatch` | `planStatementPortableBatchId: ID!` | `TemporaryAttachmentGraphqlType` |
| Deal Extraction | `downloadDealExtraction` | (none - generates client-side) | `DealExtractionDownloadGraphqlType` |

### Report Components to Update

#### 1. Payment Report (`src/app/payment-report/`)
**Current behavior:**
- Calls `downloadPaymentReport` mutation
- Opens `element.attachment?.file?.file?.publicUrl` (INSECURE - public URL)

**Target behavior:**
- Call `downloadPaymentReport` mutation
- Use returned presigned URL from mutation response (not from element)

**Files:**
- `payment-report.component.ts` - Update `downloadButton()` method
- `payment-report.component.html` - Add filename column + Actions menu

#### 2. Commission Report Creation Event (`src/app/commission-report-creation-batch/show/`)
**Current behavior:**
- Direct link to `commissionReportCreationEvent.attachment?.file?.file?.publicUrl`

**Target behavior:**
- Click handler calls `downloadCommissionReportCreationEvent` mutation
- Redirects to presigned URL

**Files:**
- `commission-report-creation-batch-show.component.ts` - Add download method
- `commission-report-creation-batch-show.component.html` - Update Actions menu

#### 3. Commission (Commission Report) (`src/app/commission/show/`)
**Current behavior:**
- Direct link to `commission.report?.file?.file?.publicUrl`

**Target behavior:**
- This needs investigation - commission.report is different from commission report creation event
- May need new mutation or use `getTemporaryAttachment`

**Files:**
- `commission-show.component.ts` - Add download method
- `commission-show.component.html` - Update download button

#### 4. Payment (Payment Exportation) (`src/app/payment/show/`)
**Current behavior:**
- Direct link to `payment.exportation.attachment?.file?.file?.publicUrl`

**Target behavior:**
- Click handler calls `downloadPaymentExportation` mutation
- Redirects to presigned URL

**Files:**
- `payment-show.component.ts` - Add download method
- `payment-show.component.html` - Update download link

#### 5. Deal Extraction (`src/app/deal-extraction/`)
**Current behavior:**
- Generates XLSX client-side and downloads immediately
- Calls `downloadDealExtraction` mutation just to log the download

**Target behavior:**
- Keep current behavior (client-side generation)
- `downloadDealExtraction` mutation just creates audit trail, no file in S3

**Files:** No changes needed (already correct)

---

## Execution Order

### Step 1: UX Pattern - Reference Component
Pick one component as reference, implement full pattern, test thoroughly.
**Recommendation:** Use `calendar-audit` (simplest audit)

### Step 2: Apply UX Pattern to All Audits (10 components)
Batch update all audit components with new UX pattern.

### Step 3: Apply UX Pattern to All Documents (14 components)
Batch update all document components with new UX pattern.

### Step 4: Reports Migration + UX
Migrate each report type to use secure downloads AND apply new UX pattern:
1. Payment Report
2. Commission Report Creation Event
3. Commission Show
4. Payment Show

### Step 5: Validation
- Build succeeds (`ng build`)
- All download buttons work correctly
- Filenames visible in all listings
- Actions menu works consistently

---

## Translation Keys Needed

May need to add:
- `document.filename` or `attachment.filename`
- `actions.column` (for header, though we're using invisible placeholder)

---

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Breaking existing downloads | High | Test each component after migration |
| Menu behavior inconsistent | Medium | Use exact same pattern from deal-document |
| Missing permissions on reports | Medium | Test with different user roles |
| Old frontend (old-front branch) | High | This work is for master only - old-front needs separate migration |

---

---

## Part 3: Old-Front Migration (CRITICAL)

### Why This Is Required

- `old-front` branch serves legacy clients still in production
- Cannot close S3 bucket until BOTH frontends use presigned URLs
- Different codebase structure - needs separate analysis

### Branch Strategy

```
1. git checkout old-front
2. git pull origin old-front
3. git hf hotfix start old-front-secure-downloads  (or manual branch creation)
4. Implement secure downloads (simpler pattern)
5. PR to old-front branch
```

### Scope for old-front

**DO:**
- Replace all `publicUrl` usages with mutation calls
- Use same mutations as master (backend is shared)
- Test thoroughly

**DON'T:**
- Apply the new UX (filename + Actions menu) - different design system
- Refactor or modernize code
- Change anything beyond security fix

### Files to Investigate in old-front

Need to analyze old-front branch to find:
1. All `publicUrl` usages for downloads
2. Component structure differences
3. Service patterns used

### Estimated Components (to verify)

- Audit components (may be different set)
- Document components
- Report components (payment-report, commission, etc.)
- Payment exportation

---

## Execution Order (UPDATED)

### Phase A: Master Branch (hotfix/1.247.5)

1. **Step A1**: UX Pattern - Reference Component (calendar-audit)
2. **Step A2**: Apply UX Pattern to All Audits (10 components)
3. **Step A3**: Apply UX Pattern to All Documents (14 components)
4. **Step A4**: Reports Migration + UX
5. **Step A5**: Validation & PR to master

### Phase B: Old-Front Branch (new hotfix)

1. **Step B1**: Checkout old-front, create hotfix branch
2. **Step B2**: Analyze codebase structure
3. **Step B3**: Identify all publicUrl usages
4. **Step B4**: Migrate to secure downloads (no UX changes)
5. **Step B5**: Validation & PR to old-front

### Phase C: Cleanup (After Both Deployed)

1. Remove backwards compatibility types from backend
2. Update features.md to mark complete

---

## Success Criteria

### Master Branch (hotfix/1.247.5)
- [ ] All audits show filename + Actions menu with Download
- [ ] All documents show filename + Actions menu with Download
- [ ] Payment Report uses presigned URL
- [ ] Commission Report Creation Event uses presigned URL
- [ ] Commission Show uses presigned URL (if applicable)
- [ ] Payment Show (exportation) uses presigned URL
- [ ] Build succeeds with no errors
- [ ] Customer can see filenames before downloading
- [ ] PR merged to master

### Old-Front Branch
- [ ] All audit downloads use presigned URLs
- [ ] All document downloads use presigned URLs
- [ ] All report downloads use presigned URLs
- [ ] Build succeeds with no errors
- [ ] PR merged to old-front

### Final
- [ ] Both frontends deployed
- [ ] Backend cleanup complete (remove backwards compat types)
- [ ] S3 bucket can be secured (Phase 8)
