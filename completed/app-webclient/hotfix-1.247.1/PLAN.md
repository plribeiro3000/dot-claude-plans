# Hotfix 1.247.1 - Bug Fixes

**Status:** ✅ COMPLETED

## Overview

This hotfix addresses two critical UI bugs reported by customers after the release 1.247.0:

1. **Broken action buttons** in commission detail view (user commission list)
2. **Unauthorized menu visibility** - "4Shark Incentive" link showing for users without permission

---

## Bug #1: Broken Action Buttons in Commission Detail

### Problem Description

When viewing a commission detail (`/commissions/:id`), the list of user commissions shows action buttons (3-dot menu) that appear visually broken:
- The buttons display "***" instead of the proper icon
- The dropdown menu doesn't position correctly
- The buttons have a strange format/shape

### Root Cause Analysis

**File:** `src/app/commission/show/commission-show.component.html` (lines 177-189)

The custom menu implementation is missing the required `.menu-container` wrapper div. The current structure:

```html
<button class="column-l" (click)="toggleMenu(userCommission.id)">
  <span class="material-symbols-outlined">more_horiz</span>
</button>
<div class="custom-menu" *ngIf="activeMenuId === userCommission.id">
  ...
</div>
```

Should be wrapped in a `.menu-container` div to:
1. Provide relative positioning context for the absolute-positioned dropdown
2. Apply proper button styling
3. Match the pattern used in other components (e.g., variable.component.html)

### Solution

Wrap the button and custom-menu in a `.menu-container` div:

```html
<div class="menu-container column-l">
  <button (click)="toggleMenu(userCommission.id)">
    <span class="material-symbols-outlined">more_horiz</span>
  </button>
  <div class="custom-menu" *ngIf="activeMenuId === userCommission.id">
    ...
  </div>
</div>
```

### Files to Modify

1. `src/app/commission/show/commission-show.component.html`

### Testing Plan

1. Navigate to `/commissions`
2. Click on a commission to view details
3. Verify the action button (3 dots) appears correctly with proper icon
4. Click the button and verify the dropdown menu appears positioned correctly
5. Click "Visualizar" and verify navigation to user commission detail works

---

## Bug #2: "4Shark Incentive" Menu Showing Without Permission

### Problem Description

The "4Shark Incentive" menu link is visible to all authenticated users, even those who don't have any incentive-related permissions. Users without permission to access the incentive module should not see this menu option.

### Root Cause Analysis

**File:** `src/app/shell/navigation-menu/navigation-menu.component.html` (lines 1-71)

The menu logic has two branches:
1. `*ngIf="hasIncentiveAdministrativeDropdown()"` - Shows dropdown with admin options
2. `#incentiveMenuLink` template - Shows simple link to `/incentives`

The problem: When `hasIncentiveAdministrativeDropdown()` returns `false`, the template fallback (`#incentiveMenuLink`) is shown **without any permission check**. This means all users see the link.

The `hasIncentiveAdministrativeDropdown()` method checks for admin permissions:
- `incentiveCampaignListing`
- `campaignFundsListing`
- `incentivePaymentListing`

### Solution

**For now, this feature is not ready for general users.** The menu should only be visible if the user has at least one of the administrative permissions.

Simply remove the `else incentiveMenuLink` fallback and delete the `#incentiveMenuLink` template. This way:
- Users WITH admin permissions → see the dropdown menu
- Users WITHOUT admin permissions → see nothing

**Desktop menu (lines 2-71):**

Change from:
```html
<ng-container *ngIf="hasIncentiveAdministrativeDropdown(); else incentiveMenuLink">
  <!-- dropdown menu -->
</ng-container>
<ng-template #incentiveMenuLink>
  <!-- simple link - REMOVE THIS -->
</ng-template>
```

To:
```html
<ng-container *ngIf="hasIncentiveAdministrativeDropdown()">
  <!-- dropdown menu only -->
</ng-container>
```

**Mobile menu (lines 534-587):** Apply the same logic - remove the fallback template and only show the dropdown for users with admin permissions.

### Files to Modify

1. `src/app/shell/navigation-menu/navigation-menu.component.html` (desktop menu - lines 2-71)
2. `src/app/shell/navigation-menu/navigation-menu.component.html` (mobile menu - lines 534-587)

### Testing Plan

1. Log in as a user WITHOUT any incentive admin permissions
2. Verify "4Shark Incentive" menu is NOT visible at all
3. Log in as a user WITH at least one admin permission (`incentive_campaign_listing`, `campaign_fund_listing`, or `incentive_payment_listing`)
4. Verify "4Shark Incentive" menu IS visible as a dropdown with admin options

---

## Implementation Order

1. Fix Bug #1 (action buttons) - Lower risk, isolated change
2. Fix Bug #2 (menu permission) - Affects navigation, needs more testing

## Estimated Complexity

- Bug #1: Low complexity (~5 minutes implementation)
- Bug #2: Low complexity (~10 minutes implementation)

## Risk Assessment

- **Bug #1:** Very low risk - CSS/structure fix, no logic changes
- **Bug #2:** Low risk - Adding permission check, existing permission system

---

## Changelog Entry (for CHANGELOG.md)

```markdown
### Fixed

- Action menu buttons now display correctly in commission user details view
- "4Shark Incentive" menu is now only visible to users with appropriate permissions
```
