# PLAN - Content Security Policy (CSP) Headers

> Single-project feature for the `app` (Rails) project.
> Context: Pen test finding — CSP headers missing from all responses.
> **Status: COMPLETED** — Merged to `develop` on 2026-03-05.

## Objective

Enable Content Security Policy headers across the Rails application, with per-route policies that match
the security requirements of each route group, without breaking existing admin tooling (Sidekiq Web UI,
PgHero, PgExtras) or API consumers.

## Scope

### In Scope
- Inline style extraction from Devise login view and application layout into `application.css`
- Global CSP policy enabled via Rails initializer with nonce support
- Middleware to exclude `/sidekiq` paths from Rails-managed CSP (Sidekiq 8.0.10 manages its own)
- CSP disabled at controller level for GraphQL controllers (JSON-only)
- Permissions Policy enabled via existing commented-out initializer
- Verification of PgHero's `override_csp` option behavior

### Out of Scope
- Sidekiq CSP configuration (Sidekiq 8.0.10 already ships its own hardcoded CSP with nonce support)
- CSP violation reporting endpoint (no reporting infrastructure defined)
- Frontend (app-webclient) — does not go through Rails
- Cloudflare/Terraform-level headers

## What Was Implemented

### Phase 1: HTML Cleanup — Inline Style Extraction
- Extracted all 8 inline `style=` attributes from `app/views/devise/sessions/new.html.erb` into CSS classes in `app/assets/stylesheets/application.css`
- Replaced `<body style="background: #d2d6de;">` in `app/views/layouts/application.html.erb` with `<body class="app-body">`
- CSS classes: `.app-body`, `.login-wrapper`, `.login-logo`, `.login-card`, `.login-alert`, `.login-field-group`, `.login-label`, `.login-input`, `.login-submit-wrapper`, `.login-submit-button`

### Phase 2: Global CSP Policy
- Enabled `config/initializers/content_security_policy.rb` with enforce mode directly (no report-only period)
- Policy: `default-src 'self'`, `script-src 'self'` with nonce, `style-src 'self'`, `font-src 'none'`, `object-src 'none'`, `base-uri 'self'`
- Nonce generator: `SecureRandom.base64(16)` per request
- Nonce directives: `script-src` only

### Phase 3: Sidekiq Exclusion Middleware
- Created `app/middlewares/disable_content_security_policy.rb` (class `DisableContentSecurityPolicy`)
- Strips `content-security-policy` and `content-security-policy-report-only` headers for `/sidekiq` paths
- Registered in `config/application.rb` via `config.middleware.use DisableContentSecurityPolicy`
- This allows Sidekiq 8.0.10's own hardcoded CSP with nonce to be the only CSP applied

### Phase 4: CSP Disabled for JSON-only Controllers
- Added `content_security_policy false` to `GraphqlController` and `EasyGraphqlController`
- Both inherit from `JwtAuthorizedController < ApplicationController < ActionController::Base`, so the CSP module is available
- **`ApiController` was NOT changed** — it inherits from `ActionController::API` which does not include the CSP module. API controllers never receive CSP headers by default.

### Phase 5: PgHero Verification
- No `config/initializers/pghero.rb` exists
- PgHero's `override_csp` defaults to off — no action needed
- PgHero's inline scripts use `nonce: true`, covered by Rails nonce support

### Phase 6: Permissions Policy
- Enabled `config/initializers/permissions_policy.rb`
- Policy: `camera :none`, `gyroscope :none`, `microphone :none`, `usb :none`, `fullscreen :self`, `payment :none`

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| CSP approach | Per-route: controller-level overrides + path-based middleware | Cleanest Rails approach; middleware only for Sidekiq (mounted Rack app) |
| Sidekiq exclusion | Rack middleware (`DisableContentSecurityPolicy`) strips CSP headers | `content_security_policy false` only works in controllers; Sidekiq is a mounted Rack app |
| Nonce generation | `SecureRandom.base64(16)` per request | Secure random nonce; the commented-out default used `request.session.id` which is predictable |
| Report-only vs enforce | Enforce directly | All HTML routes are internal (4Shark-only); no external users access Rails HTML pages |
| Inline style extraction | Moved to `application.css` with semantic class names | Prerequisite for `style-src 'self'` without `unsafe-inline` |
| API CSP | No change needed | `ApiController < ActionController::API` does not include CSP module; never receives CSP headers |
| GraphQL CSP | `content_security_policy false` | JSON-only controllers; explicit opt-out documents intent |
| Middleware naming | `DisableContentSecurityPolicy` | Descriptive, no abbreviations; the "when" (Sidekiq paths) is an implementation detail |

## Key Findings During Implementation

1. **`ActionController::API` does NOT include the CSP module** — calling `content_security_policy false` on `ApiController` causes `NoMethodError`. API controllers inheriting from `ActionController::API` never receive CSP headers, so no action is needed.
2. **Sidekiq 8.0.10 manages its own CSP** with nonce support — hardcoded, cannot be disabled or customized. If both Rails and Sidekiq set CSP headers, browsers apply intersection (AND logic), breaking the UI because nonces won't match.
3. **PgHero's `override_csp` defaults to off** and no initializer exists — no action needed.
4. **Middlewares in this project** are loaded via `Dir['app/middlewares/*.rb'].each { |file| require_relative "../#{file}" }` in `config/application.rb`.

## Files Changed

| File | Change |
|------|--------|
| `app/assets/stylesheets/application.css` | Added CSS classes extracted from inline styles |
| `app/views/devise/sessions/new.html.erb` | Replaced 8 inline `style=` attributes with CSS classes |
| `app/views/layouts/application.html.erb` | Replaced inline body style with `.app-body` class |
| `config/initializers/content_security_policy.rb` | Enabled CSP with enforce mode |
| `config/initializers/permissions_policy.rb` | Enabled Permissions Policy |
| `app/middlewares/disable_content_security_policy.rb` | New — strips CSP for `/sidekiq` paths |
| `config/application.rb` | Added `DisableContentSecurityPolicy` middleware |
| `app/controllers/graphql_controller.rb` | Added `content_security_policy false` |
| `app/controllers/easy_graphql_controller.rb` | Added `content_security_policy false` |
| `CHANGELOG.md` | Added security entry |

## Validation Results

- **RSpec**: 5437 examples, 2 failures (pre-existing on `develop`, unrelated — `BIGDECIMAL_PRECISION` constant)
- **Rubocop**: 0 offenses
- **Brakeman**: 0 warnings
