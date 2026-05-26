# NEXT TASKS — Content Security Policy (CSP) Headers Implementation

> **Status: ALL TASKS COMPLETED** — Merged to `develop` on 2026-03-05.
> **Reference:** derived from `PLAN.md` (sections: Phase 1 through Phase 7).

---

## 0) Pre-conditions

- [x] `PLAN.md` **approved** (option: Full CSP implementation with per-route policies)
- [x] **Base branch:** `develop` • **Working branch:** `feature/csp-headers`

---

## 1) Step by Step (atomic tasks)

### Task 1 — Extract inline styles from Devise login view ✅
- **Completed:** Removed all 8 inline `style=` attributes, created semantic CSS classes in `application.css`

### Task 2 — Extract inline styles from application layout ✅
- **Completed:** Replaced `<body style="background: #d2d6de;">` with `<body class="app-body">`

### Task 3 — Configure global CSP policy in Rails initializer ✅
- **Completed:** Enabled CSP in enforce mode directly (no report-only period). Nonce via `SecureRandom.base64(16)`

### Task 4 — Create Sidekiq exclusion middleware ✅
- **Completed:** Created `DisableContentSecurityPolicy` middleware (originally named `SkipCspForSidekiq`, renamed for clarity)

### Task 5 — Disable CSP for JSON-only controllers ✅
- **Completed:** Added `content_security_policy false` to `GraphqlController` and `EasyGraphqlController`
- **Note:** `ApiController < ActionController::API` does NOT include the CSP module — no change needed

### Task 6 — Verify and configure PgHero CSP behavior ✅
- **Completed:** Verification only — no initializer exists, `override_csp` defaults to off. No action needed.

### Task 7 — Enable Permissions Policy header ✅
- **Completed:** Enabled with restrictive defaults (camera/gyroscope/microphone/usb/payment: none, fullscreen: self)

### Task 8 — Update CHANGELOG.md ✅
- **Completed:** Added security entry under `[Unreleased]`

---

## 2) Items Requiring User Confirmation

- [x] **Inline style extraction semantics:** CSS class names approved (`.login-wrapper`, `.login-card`, etc.)
- [x] **CSP report-only observation period:** Go straight to enforce — all HTML routes are internal (4Shark-only)
- [x] **Easy GraphQL controller location:** `app/controllers/easy_graphql_controller.rb`, inherits from `JwtAuthorizedController`
- [x] **PgHero override_csp default:** Defaults to off. No initializer exists. No action needed.

---

## 3) Pending Items After This Iteration

None — all phases completed and validated.
