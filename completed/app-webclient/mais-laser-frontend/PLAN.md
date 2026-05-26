# PLAN — Disponibilizar Front-end Mais Laser no Netlify

## Current Situation

- **Relevant context/architecture:**
  - The app-webclient is an Angular application that supports multiple branded frontends (themes)
  - Each brand has its own environment folder under `src/environments/{brand_name}/`
  - Theme colors are defined in `colorVariables.scss` and loaded via `stylePreprocessorOptions.includePaths` in angular.json
  - The theme system uses SCSS functions (`theme()`, `theme-fonts()`) to apply brand colors
  - Last similar addition was "4SHARK easy" in version 1.201.0 (2023-12-04)

- **Impacted components:**
  - `angular.json` - project configuration
  - `src/environments/mais_laser/` - new environment folder (to be created)
  - `CHANGELOG.md` - release documentation
  - Netlify - new site configuration
  - S3 - logo assets upload

- **Versions/environment:**
  - Angular 16 (current version)
  - Deployed to Netlify
  - Assets stored in S3 bucket `4shark-assets`

## Objective / Target State

- **Desired outcome:**
  - A fully configured "Mais Laser" branded frontend deployable to Netlify
  - Visual identity matching Mais Laser brand (green #34af23 and black #000)
  - PWA support with proper icons and manifest

- **Success metrics / acceptance criteria:**
  - `ng serve mais_laser` runs successfully
  - `ng build mais_laser --configuration=production` compiles without errors
  - Brand colors properly applied throughout the application
  - PWA manifest and icons correctly configured
  - Netlify site deployed and accessible

## Problem / New Feature

- **Objective description:**
  - Create a new themed frontend for the "Mais Laser" franchise
  - Follow the same pattern used for other branded frontends (4shark, 4shark_easy, self_telefonia, etc.)

- **Reference implementation:**
  - Commit `e2d060aa9` (feat(application): 4shark easy) - 2023-11-29

## Challenges, Difficulties and Risks

- **Technical:**
  - PWA icons will be added in a future iteration

- **Product/UX:**
  - Color palette matches Mais Laser brand identity

- **Security/privacy:**
  - No security concerns - this is visual theming only

- **Performance:**
  - No performance impact - same codebase, different assets

## Solution: Standard Theme Setup

Follow the exact pattern of existing themes (4shark_easy, self_telefonia).

---

## CONFIRMED ASSETS

### Logo (High Resolution with Transparent Background)

| Property | Value |
|----------|-------|
| **URL** | `https://www.sejafranqueadomaislaser.com.br/public/site/images/LOGO-MAISLASER.png` |
| **Dimensions** | 1774 x 577 pixels |
| **Format** | PNG with alpha channel (RGBA) |
| **Background** | Transparent (confirmed via ImageMagick analysis) |

**S3 URL:** `https://4shark-assets.s3.amazonaws.com/mais_laser/mais_laser.png`

### PWA Icons

Icons will be added in a future iteration. For now, use placeholder or 4shark default icons.

---

## CONFIRMED ENVIRONMENT VARIABLES

| Variable | Value | Source |
|----------|-------|--------|
| `ANALYTICS_ID` | **TBD** | User will create in GA4 |
| `APP_TITLE` | `Mais Laser` | Confirmed |
| `AVATAR_URL` | `https://4shark-assets.s3.amazonaws.com/defaults/avatar-1.png` | Default |
| `CLIENT_NAME` | `mais laser` | Confirmed |
| `FAVICON_ICO_URL` | `https://4shark-assets.s3.amazonaws.com/mais_laser/favicon.ico` | After S3 upload |
| `FAVICON_PNG_URL` | `https://4shark-assets.s3.amazonaws.com/mais_laser/favicon.png` | After S3 upload |
| `GRAPHQL_API_SERVER` | `demo001.app4shark.com` | Confirmed |
| `LOGO_PRIMARY_URL` | `https://4shark-assets.s3.amazonaws.com/mais_laser/mais_laser.png` | After S3 upload |
| `LOGO_SECONDARY_URL` | `https://4shark-assets.s3.amazonaws.com/mais_laser/mais_laser.png` | Same as primary |
| `MANIFEST_PATH` | `environments/mais_laser/manifest.json` | Standard |
| `MOBILE_CONFIGURATION_UUID` | `9841ffa1-1b17-49e6-b2aa-936578d1611f` | Same as demo |
| `ROLLBAR_ACCESS_TOKEN` | **TBD** | User will create in Rollbar |

---

## CONFIRMED COLOR PALETTE

From the Mais Laser website (https://www.sejafranqueadomaislaser.com.br/):

| Color | Hex Code | Usage | SCSS Variable |
|-------|----------|-------|---------------|
| Primary Green | `#34af23` | CTAs, buttons, brand accent | `$secondary` |
| Green Hover | `#2d9520` | Button hover states | `$secondary-hover` |
| Black | `#000000` | Text, primary UI elements | `$primary` |
| Dark Gray | `#1a1a1a` | Hover states for black elements | `$primary-hover` |

---

## IMPLEMENTATION STEPS

### Phase 1: Code Changes

#### 1.1 Create Environment Structure
Create `src/environments/mais_laser/`:

```
mais_laser/
├── assets/
│   └── (placeholder icons - to be added later)
├── styles/
│   └── colorVariables.scss
└── manifest.json
```

#### 1.2 Create Color Variables
File: `src/environments/mais_laser/styles/colorVariables.scss`

```scss
// Primary colors - Mais Laser brand
$secondary-hover: #2d9520;    // Darker green for hover
$primary-hover: #1a1a1a;      // Dark gray for hover
$secondary: #34af23;          // Main green (from brand)
$primary: #000000;            // Black (from brand)
```

#### 1.3 Create PWA Manifest
File: `src/environments/mais_laser/manifest.json`

```json
{
  "name": "Mais Laser",
  "short_name": "Mais Laser",
  "theme_color": "#000000",
  "background_color": "#34af23",
  "scope": "/",
  "start_url": "/",
  "display": "standalone",
  "icons": [
    {
      "src": "assets/icon-512x512.png",
      "sizes": "512x512",
      "type": "image/png"
    },
    {
      "src": "assets/icon-192x192.png",
      "sizes": "192x192",
      "type": "image/png"
    }
  ]
}
```

#### 1.4 Configure Angular Project
Add "mais_laser" project to `angular.json`:

**Key configuration points:**
- `assets`: include `src/environments/mais_laser`
- `stylePreprocessorOptions.includePaths`: `["src/environments/mais_laser/styles"]`
- Build command references: `mais_laser:build`

#### 1.5 Update CHANGELOG
Add entry under `[Unreleased]`:
```markdown
### Added

- Mais Laser application
```

### Phase 2: S3 Upload (User Action)

Upload logo to S3:
```bash
aws s3 cp logo-maislaser.png s3://4shark-assets/mais_laser/logo-maislaser.png --acl public-read
```

Source: `https://www.sejafranqueadomaislaser.com.br/public/site/images/LOGO-MAISLASER.png`

### Phase 3: Netlify Configuration (User Action)

#### 3.1 Create New Site

| Setting | Value |
|---------|-------|
| **Site name** | `fourshark-app-client-mais-laser` |
| **Custom domain** | `maislaser.app4shark.com` |
| **Repository** | `4shark/app-webclient` |
| **Branch** | `master` |
| **Build command** | `yarn build mais_laser` |
| **Publish directory** | `dist` |

#### 3.2 Set Environment Variables

Use Netlify CLI or UI to set all variables from the table above.

### Phase 4: Testing & Deployment

#### 4.1 Local Testing
```bash
# Serve locally
ng serve mais_laser

# Build for production
ng build mais_laser --configuration=production
```

#### 4.2 Deploy
- Merge to `master` branch triggers automatic Netlify deploy
- Verify at `https://maislaser.app4shark.com`

---

## FILES SUMMARY

### Files to CREATE

| File | Purpose |
|------|---------|
| `src/environments/mais_laser/styles/colorVariables.scss` | Brand color definitions |
| `src/environments/mais_laser/manifest.json` | PWA configuration |
| `src/environments/mais_laser/assets/` | Directory for icons (placeholder for now) |

### Files to MODIFY

| File | Change |
|------|--------|
| `angular.json` | Add "mais_laser" project configuration (~90 lines) |
| `CHANGELOG.md` | Add entry under [Unreleased] |

---

## PENDING ITEMS (User Action Required)

| Item | Action |
|------|--------|
| Google Analytics | Create GA4 property and provide `ANALYTICS_ID` |
| Rollbar | Create project and provide `ROLLBAR_ACCESS_TOKEN` |
| S3 Upload | Upload logo to `s3://4shark-assets/mais_laser/` |
| PWA Icons | Generate and add in future iteration |

---

## Internal References

- Reference commit: `e2d060aa9` (feat(application): 4shark easy)
- Color variables pattern: `src/environments/4shark_easy/styles/colorVariables.scss`
- Manifest pattern: `src/environments/self_telefonia/manifest.json`
- Angular config pattern: `angular.json` lines 4461-4550 (self_telefonia project)
- Theme system: `src/theme/theme.scss`
- Netlify reference sites:
  - `fourshark-app-client-easy` (easy.app4shark.com)
  - `fourshark-app-client-self-telefonia` (self-telefonia.app4shark.com)
  - `fourshark-app-client-demo` (demo.app4shark.com)

---

## STATUS: READY FOR APPROVAL

All technical details confirmed. Pending user action items (GA, Rollbar, S3) can be done in parallel with code implementation.

**To approve:** `APPROVED`
