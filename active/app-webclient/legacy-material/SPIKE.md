# SPIKE — Legacy Material Design CSS in app-webclient

**Conducted by:** Engineering Team
**Date:** 2026-03-24
**Status:** Research complete — pending decisions

---

## Goal

Determine the extent of legacy Angular Material CSS remaining in the app-webclient codebase after the library was removed, assess whether it blocks the Angular 16 → 17 migration, and define a cleanup plan.

---

## Method

- Static analysis of all `.ts`, `.html`, `.scss` files for `mat-` prefixed classes and `@angular/material` imports
- Cross-referencing CSS selectors in stylesheets against actual DOM elements in HTML templates to classify as dead or active code
- Dependency audit via `package.json` and `node_modules/` to confirm Angular Material is not installed
- Angular 17 migration impact assessment

---

## Evidence

### Current UI Stack

| Library | Version | Status |
|---------|---------|--------|
| Bootstrap | ^5.3.8 | Active |
| ng-bootstrap | ^15.1.1 | Active |
| PrimeNG | ^16.9.1 | Active |
| @angular/cdk | ^16.2.0 | Active (104 files import from it) |
| @angular/material | — | **Not installed** |

Angular Material is not a dependency. The `@material/*` packages in `node_modules/` are transitive dependencies (from `@angular/cdk`), not directly used.

### Inventory of Legacy Material References

| Category | Selectors | Status | Action |
|----------|-----------|--------|--------|
| Form Field (`.mat-form-field-*`) | 26 | Dead code | Delete |
| Radio Button (`.mat-radio-*`) | 11 | Dead code | Delete |
| Expansion Panel (`.mat-expansion-panel-*`) | 9 | Dead code | Delete |
| Sidenav / Drawer (`.mat-sidenav-*`, `.mat-drawer-*`) | 8 | Dead code | Delete |
| Checkbox (`.mat-checkbox-*`) | 4 | Dead code | Delete |
| Select (`.mat-select-*`) | 3 | Dead code | Delete |
| Date Picker (`.mat-datepicker-*`, `.mat-date-range-*`) | 3 | Dead code | Delete |
| Button (`.mat-button-base`, `.mat-raised-button`, etc.) | ~25 | **Active** — custom CSS classes | Rename |
| Menu Trigger (`.mat-menu-trigger`, `.mat-mdc-menu-trigger`) | 5 | **Active** — custom CSS classes | Rename |
| Snack Bar (`.mat-snack-bar-container`) | 1 | Dead code | Delete |
| Slider (`.mat-slider-*`) | 1 | Dead code | Delete |
| Calendar (`.mat-calendar-body-selected`) | 1 | Dead code | Delete |
| Bottom Sheet (`.mat-bottom-sheet-container`) | 1 | Dead code | Delete |
| Spinner (`.mat-spinner-color`) | 2 | Dead code | Delete |
| Icon (`.mat-icon`) | 4 | Dead code | Delete |
| Dialog (`.mat-mdc-dialog-content`) | 2 | Dead code | Delete |
| Divider (`.mat-divider`) | 1 | Dead code | Delete |
| Table Column (`.mat-column-name`) | 3 | Dead code | Delete |
| Error (`.mat-error`) | 3 | Dead code | Delete |

**Total: ~113 dead selectors to delete, ~30 active selectors to rename.**

### Dead Code — Detailed File Map

#### `src/main.scss` (bulk of dead code)

| Component | Lines | Selectors |
|-----------|-------|-----------|
| Select | 643–659 | `.mat-select-value`, `.mat-select-value-text`, `.mat-select-disabled` |
| Form Field | 665–667 | `.mat-form-field` |
| Checkbox | 669–687 | `.mat-checkbox`, `.mat-checkbox-label`, `.mat-checkbox-checked`, `.mat-checkbox-disabled`, `.mat-checkbox-background` |
| Snack Bar | 764–771 | `.mat-snack-bar-container` |
| Sidenav / Accordion | 780–815 | `.mat-sidenav-content`, `.mat-accordion`, `.mat-sidenav`, `.mat-expansion-panel-header`, `.mat-expansion-panel-header-title` |
| Icon | 851–865 | `.mat-icon` (inside `.box-shadow-1`, `.box-shadow-2`) |
| Expansion Panel | 1173–1255 | `.mat-expansion-panel-header.mat-expanded`, `.mat-expansion-panel-header` hover/focus, `.mat-expansion-indicator` |
| Slider | 1259–1263 | `.mat-accent .mat-slider-thumb`, `.mat-slider-thumb-label`, `.mat-slider-track-fill` |
| Form Field (focused) | 1273–1282 | `.mat-form-field.mat-focused`, `.mat-form-field-ripple` |
| Form Field (firstbox) | 1317–1365 | `.firstbox .mat-form-field-*` (label-wrapper, label, underline, infix, hide-placeholder, should-float) |
| Form Field (secondbox) | 1371–1429 | `.secondbox .mat-form-field-*` (same set + suffix) |
| Drawer | 1524–1539 | `.mat-drawer-container`, `.mat-drawer`, `.mat-drawer-inner-container`, `.mat-calendar-body-selected` |
| Radio | 1573–1645 | `.mat-radio-button`, `.mat-radio-container`, `.mat-radio-checked`, `.mat-radio-inner-circle`, `.mat-radio-outer-circle`, `.mat-radio-label-content`, `.mat-radio-group` |
| Expansion Panel | 1668–1682 | `.mat-expansion-panel-spacing`, `.mat-expansion-panel:not(.mat-expanded)` |
| Button Wrapper | 1712–1731 | `.mat-button-wrapper` (dead — no Material `<button>` generates this span) |
| Select Panel | 1831–1838 | `.mat-select-panel` |
| Menu Panel | 1958–1960 | `.mat-mdc-menu-panel` |
| Search Drawer | 1974–2027 | `.mat-drawer-container.search-container`, `.mat-drawer-inner-container`, `.mat-divider` |
| Login Form Field | 2121–2139 | `.login-container .mat-form-field-*` |
| Bottom Sheet | 2165–2167 | `.mat-bottom-sheet-container` |
| Radio (accent) | 2183–2195 | `.mat-radio-button.mat-accent`, `.mat-radio-checked` |
| Form Field (fill) | 2221–2224 | `.mat-form-field-appearance-fill` |
| Form Field (infix) | 2232–2234 | `.mat-form-field-infix` |
| Date Range | 2236–2248 | `.mat-date-range-input`, `.mat-date-range-input-container`, `.mat-datepicker-toggle.disabled-text` |
| Variable Track | 2257–2259 | `.variable-track-row .mat-form-field-infix` |
| Spinner | 2454–2456 | `.mat-spinner-color::ng-deep circle` |
| Menu Content | 2458–2462 | `::ng-deep .mat-mdc-menu-content` |
| Options Button | 2574–2576 | `.options-button.mat-button` |
| Radio (responsive) | 3486–3490 | `.mat-radio-group` |
| Form Field (responsive) | 3624–3648 | `.mat-form-field-infix`, `.mat-form-field-suffix`, `.mat-form-field-should-float` |
| Drawer (responsive) | 3706–3731 | `.mat-drawer-container` |

#### Component SCSS files (dead code)

| File | Selectors to Remove |
|------|-------------------|
| `src/app/deal-incentive/show/deal-incentive-show.component.scss:5` | `.mat-expansion-panel-header` |
| `src/app/indicator-incentives/show/indicator-incentive-show.component.scss:5` | `.mat-expansion-panel-header` |
| `src/app/limiter-incentives/show/limiter-incentive-show.component.scss:5` | `.mat-expansion-panel-header` |
| `src/app/rankifier-incentives/show/rankifier-incentive-show.component.scss:5` | `.mat-expansion-panel-header` |
| `src/app/redemption-incentives/show/redemption-incentive-show.component.scss:5` | `.mat-expansion-panel-header` |
| `src/app/plan-statement/plan-statement-show/plan-statement-show.component.scss:32,63-95` | `.mat-error`, `.mat-expansion-panel-header`, `.mat-expanded` |
| `src/app/user-history/user-history-show/user-history-show.component.scss:32,63-95` | `.mat-error`, `.mat-expansion-panel-header`, `.mat-expanded` |
| `src/app/plan-participation/show/plan-participation-show.component.scss:14` | `.mat-error` |
| `src/app/plan-statement/plan-statement-accept/plan-statement-accept.component.scss:19` | `.mat-mdc-dialog-content` |
| `src/app/statement/statement-accept/statement-accept.component.scss:21` | `.mat-mdc-dialog-content` |
| `src/app/dashboard/calendar/dashboard-calendar.component.scss:405` | `.mat-column-name` |
| `src/app/dashboard/plan/dashboard-plan.component.scss:277` | `.mat-column-name` |
| `src/app/dashboard/incentive/dashboard-incentive.component.scss:413` | `.mat-column-name` |
| `src/app/login/login.component.scss:26,38,160` | `.mat-raised-button`, `.mat-icon` |
| `src/app/legal-document-acceptance/legal-document-acceptance.component.scss:34,46` | `.mat-raised-button`, `.mat-icon` |
| `src/app/user/user.component.scss:53,57` | `.mat-spinner-color::ng-deep circle`, `::ng-deep .mat-mdc-menu-content` |
| `src/app/user/show/user-show.component.scss:174` | `.mat-spinner-color::ng-deep circle` |

#### Other files (dead code)

| File | What to Remove |
|------|---------------|
| `src/assets/styles/resets.scss` | Lines 3–13 (`.mat-button` reset + `.mat-button-focus-overlay`) and line 15 comment. The entire file may become empty. |

### Active Code — Detailed File Map

These `.mat-*` class names are used as **custom CSS classes** applied directly to HTML elements. They are not Angular Material components — just unfortunately named.

#### Button System

**Suggested rename:** `mat-button-base` → `btn-base`, `mat-raised-button` → `btn-raised`, `mat-stroked-button` → `btn-stroked`, `mat-flat-button` → `btn-flat`

| File | Lines | Current Class | Suggested Class |
|------|-------|--------------|----------------|
| **HTML Templates** | | | |
| `src/app/shared/components/button/button.component.html` | 4 | `mat-raised-button mat-button-base` | `btn-raised btn-base` |
| `src/app/shared/components/button/button.component.html` | 7 | `mat-stroked-button mat-button-base` | `btn-stroked btn-base` |
| `src/app/shared/components/button/button.component.html` | 10 | `mat-flat-button mat-button-base` | `btn-flat btn-base` |
| `src/app/shared/components/button/button.component.html` | 16 | `mat-flat-button mat-button-base` | `btn-flat btn-base` |
| `src/app/shared/components/button/button.component.html` | 23 | `mat-stroked-button mat-button-base` | `btn-stroked btn-base` |
| `src/app/shared/components/button/button.component.html` | 32 | `mat-raised-button mat-button-base` | `btn-raised btn-base` |
| `src/app/shared/components/link/link.component.html` | 3 | `mat-button-base` | `btn-base` |
| `src/app/easy-product/plan-slice/show/plan-slice-show.component.html` | 237 | `mat-button-base` | `btn-base` |
| `src/app/easy-product/plan-slice-commission/show/plan-slice-commission-show.component.html` | 99, 108 | `mat-button-base` | `btn-base` |
| **SCSS Files** | | | |
| `src/app/shared/components/button/button.component.scss` | 6, 15, 19, 27 | `.mat-button-base`, `.mat-raised-button`, `.mat-flat-button`, `.mat-stroked-button` | `.btn-base`, `.btn-raised`, `.btn-flat`, `.btn-stroked` |
| `src/app/shared/components/link/link.component.scss` | 6 | `.mat-button-base` | `.btn-base` |
| `src/app/payment-report/payment-report.component.scss` | 6 | `.mat-button-base` | `.btn-base` |
| `src/app/plan-participation/show/plan-participation-show.component.scss` | 38 | `.mat-button-base` | `.btn-base` |

#### Menu Trigger

**Suggested rename:** `mat-menu-trigger` → `menu-trigger`, `mat-mdc-menu-trigger` → `menu-trigger`

| File | Line | Current Class | Suggested Class |
|------|------|--------------|----------------|
| `src/app/shell/shell.component.html` | 17 | `mat-mdc-menu-trigger` | `menu-trigger` |
| `src/app/easy-product/easy-user-document/create/easy-user-document-create.component.html` | 29 | `mat-menu-trigger` | `menu-trigger` |
| `src/app/easy-product/easy-variable-document/create/easy-variable-document-create.component.html` | 29 | `mat-menu-trigger` | `menu-trigger` |
| `src/app/easy-product/plan-slice-commission/create/plan-slice-commission-create.component.html` | 73 | `mat-menu-trigger` | `menu-trigger` |
| `src/app/easy-product/plan-slice-commission/reprocess/plan-slice-commission-reprocess.component.html` | 38 | `mat-menu-trigger` | `menu-trigger` |
| `src/main.scss` | 1952–1956 | `.mat-menu-trigger`, `.mat-mdc-menu-trigger` | `.menu-trigger` |

### Material Icons (no action needed)

The project loads Material Icons via Google Fonts CDN in `src/index.html` (lines 18–19):

```html
<link href="https://fonts.googleapis.com/icon?family=Material+Icons" rel="stylesheet" />
<link href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined" rel="stylesheet" />
```

These are a font, not a component library. Independent of Angular Material. No action needed.

### Angular 16 → 17 Migration Impact

**None of these items block the migration.**

Angular 17 removed `@angular/material/legacy-*` modules (deprecated in 15, removed in 17). Since this project does not have `@angular/material` as a dependency, that removal is irrelevant.

The only migration-related dependency is `@angular/cdk` (^16.2.0), which needs to be updated to 17.x via `ng update @angular/cdk`. CDK has no relation to these CSS classes.

---

## Conclusions

1. **Angular Material is fully removed as a dependency** — but ~143 CSS references to `.mat-*` classes remain across 22 files
2. **~113 selectors are dead code** — they target DOM elements that no longer exist and have zero effect on the application
3. **~30 selectors are active** — used as custom CSS class names on buttons and menu triggers. They work, but the naming creates confusion
4. **The cleanup does not block and is not blocked by the Angular 16 → 17 migration** — it can happen before, during, or after
5. **The `main.scss` file is the primary target** — it contains the vast majority of dead Material CSS

---

## Next Steps

This spike generates a cleanup task (no PLAN.md needed — it is mechanical work):

1. **Delete dead CSS from `main.scss`** — biggest impact, zero risk
2. **Delete dead CSS from 17 component `.scss` files** — same rationale
3. **Delete `resets.scss` content** — dead reset rules
4. **Rename active button classes** (`mat-button-base` → `btn-base`, etc.) — search-and-replace across HTML + SCSS
5. **Rename active menu trigger classes** (`mat-menu-trigger` → `menu-trigger`) — same approach
6. **Visual regression test** — compare before/after on key pages (login, dashboard, plan views, easy-product forms)

Suggested approach: one PR per step (or group steps 1–3 into a single "delete dead code" PR and steps 4–5 into a "rename classes" PR).
