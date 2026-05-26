# Plan: Audit Download Button Visibility

## Overview

**Feature:** audit-download-visibility
**Type:** Multi-project (app + app-webclient)
**Status:** ✅ COMPLETED
**Related:** Backend hotfix 3.3.1 (TTL + policy validation)

## Context

The backend validates attachment availability in audit policies (blank or expired). The frontend needs to reflect this state visually by disabling the download button when the attachment is not available.

---

## Releases

| Project | Version | Type | Description |
|---------|---------|------|-------------|
| app | 3.3.1 | Hotfix | TTL + policy validation |
| app | 3.3.3 | Hotfix | Missing `field :actions` in `MonthlyUsageAuditGraphqlType` |
| app-webclient (develop) | 1.247.2, 1.247.3 | Feature | Initial `canDownload()` implementation |
| app-webclient (develop) | 1.249.3 | Hotfix | MonthlyUsage fix - fetch `actions` from `audit` |
| app-webclient (old-front) | PR #5820 | Feature | `canDownload()` for all audits |

---

## Implementation Status

### Backend (app) - ✅ DONE

**Hotfix 3.3.1** (December 2025):
- Added TTL to prevent indefinite file accumulation
- Policy validates attachment availability before allowing download

**Hotfix 3.3.3** (January 2026):
- Bug discovered: `MonthlyUsageAuditGraphqlType` had `def actions` method but no `field :actions` declaration
- Frontend couldn't access `monthlyUsage.audit.actions` via GraphQL
- Fix: Added `field :actions, [String], null: true` to expose the existing method

### Front-end NOVO (`develop`) - ✅ DONE

**Versions 1.247.2, 1.247.3** (December 2025):
- Added `actions` field to GraphQL queries
- Added `canDownload()` method to components
- Template uses conditional rendering pattern

**Hotfix 1.249.3** (January 2026):
- MonthlyUsage was fetching `actions` from wrong location (`monthlyUsage.actions` instead of `monthlyUsage.audit.actions`)
- Fixed GraphQL query and `canDownload()` method

### Front-end ANTIGO (`old-front`) - ✅ DONE

**PR #5820** (January 2026):
- Added `canDownload()` method to all audit components
- Added `actions` field to GraphQL queries
- Template uses conditional rendering with `*ngIf` and `ng-template`

---

## Pattern Applied

### Service (.service.ts)
Add `actions` field to GraphQL query inside `nodes { }`:
```graphql
nodes {
  actions    # <-- ADD THIS LINE
  id
  status
  # ... rest of fields
}
```

### Component (.component.ts)
Add method:
```typescript
canDownload(element: any): boolean {
  return element.actions?.includes('download');
}
```

### Template (.component.html)
Conditional rendering:
```html
<ng-container *ngIf="canDownload(element); else disabledDownload">
  <a href="#" (click)="download($event, element)">
    <i class="fas fa-cloud-download-alt"></i>
    {{ element.attachment?.filename }}
  </a>
</ng-container>
<ng-template #disabledDownload>
  <span class="text-muted">
    <i class="fas fa-cloud-download-alt"></i>
    {{ element.attachment?.filename || '-' }}
  </span>
</ng-template>
```

---

## Components Updated

| Component | Has Download | Fixed |
|-----------|--------------|-------|
| CalendarAudit | ✅ | ✅ |
| CommissionIndicatorAudit | ✅ | ✅ |
| GroupAudit | ✅ | ✅ |
| MonthlyUsage | ✅ | ✅ |
| MonthlyUsageResponsibility | ❌ No download | N/A |
| PlanStatementAudit | ✅ | ✅ |
| ResponsibleAudit | ✅ | ✅ |
| StatementAudit | ✅ | ✅ |
| UserAudit | ✅ | ✅ |
| UserIdentifierAudit | ✅ | ✅ |
| VariableAudit | ✅ | ✅ |
| Documents | ✅ Always available | N/A (no processing state) |

---

## Tasks Summary

1. [x] Backend: TTL + policy validation (hotfix 3.3.1)
2. [x] Backend: Add `field :actions` to `MonthlyUsageAuditGraphqlType` (hotfix 3.3.3)
3. [x] Frontend develop: Initial `canDownload()` implementation (1.247.2, 1.247.3)
4. [x] Frontend develop: Fix MonthlyUsage `actions` location (hotfix 1.249.3)
5. [x] Frontend old-front: Implement `canDownload()` for all audits (PR #5820)

---

**Created:** 2026-01-05
**Completed:** 2026-01-06
