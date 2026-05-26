# Theme Colors Migration Plan

## Summary

Migrate hard-coded color values in SCSS files to use the existing `theme()` function, enabling proper client-specific theming across all tenants.

## Current State Analysis

### Existing Theme System (Working)

The theme infrastructure is already in place:

**File: `/src/theme/theme.scss`**
```scss
@import "colorVariables";  // Client-specific colors

$theme: (
  primary: (main: $primary, hover: $primary-hover),
  secondary: (main: $secondary, hover: $secondary-hover),
  // ... other color groups
);

@function theme($color, $shade) {
  @return map-get(map-get($theme, $color), $shade);
}
```

**Client Examples:**
| Client | Primary | Secondary |
|--------|---------|-----------|
| 4Shark | `#0889e2` (blue) | `#2b6190` |
| Grupo Elfa | `#ff003c` (red) | `#ff666c` |
| Dpaschoal | `#e30613` (red) | `#aa0300` |

### Problem: Hard-coded Colors

Instead of using `theme()`, most files have hard-coded hex values:

| Color | Occurrences | Should Be |
|-------|-------------|-----------|
| `#0889e2` | 50+ | `theme(primary, main)` |
| `#e0f2fe` | 10+ | `theme(primary, hover)` |
| `#80bcdd` | 5+ | `theme(secondary, hover)` |
| `#1f2937` | 15+ | `theme(gray-scale, 800)` |
| `#374151` | 8+ | `theme(gray-scale, 700)` |

---

## Implementation Strategy

### Phase 1: Pilot - Navigation Menu

**Target Files:**
- `/src/app/shell/navigation-menu/navigation-menu.component.scss`

**Changes:**
```scss
// BEFORE
.menu-option {
  color: #1f2937;
}
.submenu-option {
  color: #1f2937;
}
li.active {
  color: #0889e2;
}

// AFTER
.menu-option {
  color: theme(gray-scale, 800);
}
.submenu-option {
  color: theme(gray-scale, 800);
}
li.active {
  color: theme(primary, main);
}
```

### Phase 2: User Module (Comprehensive Test)

**Target Files:**
- `/src/app/user/user.component.scss`

**Why User Module:**
- 21 buttons, 3 menus, 10 permission checks
- Tests all interactive patterns
- High visibility for validation

**Changes:**
```scss
// BEFORE
.has-more:hover {
  color: #0889e2;
}
.mat-spinner-color::ng-deep circle {
  stroke: #0889e2 !important;
}
.search-icon {
  color: #0889e2;
}

// AFTER
.has-more:hover {
  color: theme(primary, main);
}
.mat-spinner-color::ng-deep circle {
  stroke: theme(primary, main) !important;
}
.search-icon {
  color: theme(primary, main);
}
```

### Phase 3: Global Styles

**Target Files:**
- `/src/main.scss` (50+ occurrences)
- `/src/assets/styles/button.scss`

### Phase 4: Remaining Components

**Target Directories:**
- `/src/app/shell/` (7 files)
- `/src/app/shared/components/` (4 files)
- `/src/app/dashboard/` (7 files)
- All other component SCSS files

---

## Color Mapping Reference

| Hard-coded | Theme Function | Notes |
|------------|----------------|-------|
| `#0889e2` | `theme(primary, main)` | Main brand color |
| `#e0f2fe` | `theme(primary, hover)` | Light primary for hover |
| `#80bcdd` | `theme(secondary, hover)` | Secondary hover |
| `#2b6190` | `theme(secondary, main)` | Secondary brand |
| `#1f2937` | `theme(gray-scale, 800)` | Dark text |
| `#374151` | `theme(gray-scale, 700)` | Medium-dark text |
| `#6b7280` | `theme(gray-scale, 500)` | Medium text |
| `#9ca3af` | `theme(gray-scale, 400)` | Light text |
| `#d1d5db` | `theme(gray-scale, 300)` | Borders |
| `#f9fafb` | `theme(gray-scale, 50)` | White/light bg |
| `#c700b3` | Keep as-is | Incentive-specific (magenta) |
| `#fb923c` | Keep as-is | Warning/orange (semantic) |

---

## Testing Plan

### Step 1: Setup Test Environment

```bash
# Build for Grupo Elfa (red theme - high contrast)
yarn start --project grupo_elfa
```

### Step 2: Login as Admin

1. Open `http://localhost:4200`
2. Login with admin credentials
3. Navigate to User module (most buttons/menus)

### Step 3: Visual Validation Checklist

#### Navigation Menu (Top Bar)
- [ ] Menu buttons show client primary color when active
- [ ] Submenu dropdown options show client primary on hover
- [ ] Mobile menu (if applicable) uses correct colors

#### User Index Page
- [ ] "New User" button uses primary color
- [ ] Filter button uses primary color
- [ ] Search icon uses primary color
- [ ] "Load More" button hover uses primary color
- [ ] Dropdown menu options use primary color on hover
- [ ] Spinner/loading indicator uses primary color

#### General
- [ ] Links use primary color
- [ ] Active states use primary color
- [ ] Hover states use primary hover or darken properly

### Step 4: Cross-Client Validation

After Grupo Elfa (red), test with:
1. **4Shark** (`yarn start --project 4shark`) - Blue theme (baseline)
2. **Dpaschoal** (`yarn start --project dpaschoal`) - Different red shade

---

## Files to Modify (Priority Order)

### Priority 1 - Navigation (Pilot)
1. `/src/app/shell/navigation-menu/navigation-menu.component.scss`

### Priority 2 - User Module (Validation)
2. `/src/app/user/user.component.scss`

### Priority 3 - Global
3. `/src/main.scss`
4. `/src/assets/styles/button.scss`

### Priority 4 - Shell Components
5. `/src/app/shell/shell.component.scss`
6. `/src/app/shell/profile-menu/profile-menu.component.scss`
7. `/src/app/shell/snack-bar-component.scss`

### Priority 5 - Shared Components
8. `/src/app/shared/components/button/button.component.scss`
9. `/src/app/shared/components/link/link.component.scss`

### Priority 6 - Dashboard
10. `/src/app/dashboard/calendar/dashboard-calendar.component.scss`
11. `/src/app/dashboard/plan/dashboard-plan.component.scss`

---

## Risks and Considerations

1. **Incentive Section Colors**: The magenta `#c700b3` is intentionally different for incentive modules - do NOT migrate this to primary.

2. **Semantic Colors**: Warning (`#fb923c`), Success (green), Alert (red) should remain semantic, not become primary.

3. **Regression Testing**: After each phase, run visual tests with multiple clients.

4. **Build Time**: Colors are baked at build time per client - no runtime switching possible.

---

## Success Criteria

- [ ] Navigation menu shows client-specific colors
- [ ] User module buttons/links show client-specific colors
- [ ] No visual regression on 4Shark (baseline)
- [ ] Grupo Elfa shows red instead of blue
- [ ] All interactive elements are visually consistent
