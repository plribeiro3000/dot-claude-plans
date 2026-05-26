# SPIKE — Integration Validation Portal (Query Validation System)

**Conducted by:** Engineering Team
**Date:** 2026-03-05
**Status:** Research complete — all decisions made, ready for planning

---

## Goal

Investigate the technical feasibility and approach for building a Query Validation Portal to remove the bottleneck in client integration onboarding. The system must allow IT teams to submit SQL queries for each integration flow and allow Operations teams to validate those queries through a secure, audited, and transparent process — organized in waves (Users first, then Indicators).

Specific questions to answer:

1. How to implement secure, unique, single-use authentication links for Operations users?
2. How to handle token expiration in long-lived validation processes (months)?
3. What PDF generation approach to use for the final signed document?
4. How to make the query definition dynamic per client?
5. Where does this system live — new app, existing app, or integrator?
6. What is the MVP scope?
7. What data model is needed?
8. How should the email notification flow work?
9. How to prevent link sharing / ensure identity verification?

---

## Method

- Analyzed the existing `app` Rails codebase (models, controllers, policies, workers, Gemfile, schema)
- Reviewed Rails 7.1/8.1 native capabilities for token generation
- Researched PDF generation options compatible with the current stack
- Investigated the magic link / prefetch attack problem and known mitigations
- Reviewed the existing authentication infrastructure (Devise, JWT, CompanyToken, Authenticator)
- Compared Prawn vs ferrum_pdf (GitHub activity, releases, downloads, licensing, maintenance)
- Compared AWS SES vs SendGrid vs Postmark (pricing, setup complexity, fit for low volume)

---

## Evidence

### 1. Existing Authentication Infrastructure

The `app` project uses **three parallel authentication mechanisms**:

| Mechanism | Model | Used For |
|-----------|-------|---------|
| Devise (basic) | `User` | Internal users logging in with email/password |
| JWT | `JsonWebToken` / `JwtAuthorizedController` | GraphQL and session-based API calls; token TTL is `JWT_TOKEN_EXPIRATION_TTL` env var (default 1 hour) |
| Company Token (UUID) | `CompanyToken` | Integrator API access — static per-company bearer token stored as UUID via `SecureRandom.uuid` |
| OAuth/OIDC (Keycloak) | `Authenticator` / `AuthenticatorConfiguration` | SSO login; decodes JWT from Keycloak to extract email |

**Key finding:** There is no existing "magic link" or time-limited, purpose-specific token mechanism. The application would need one. Rails 8.1.2 (which this project uses) inherits Rails 7.1's `generates_token_for` API natively.

**Source — `app/app/models/json_web_token.rb`:** The JWT encode method sets an expiration time via `ApplicationConfiguration.jwt_token_expiration_ttl` (default 1 hour). This is too short for a validation link that might sit in someone's inbox for days.

**Source — `app/app/models/company_token.rb`:** Uses `SecureRandom.uuid` with a unique index and `disabled_at` timestamp as the invalidation mechanism. This is the pattern to learn from.

### 2. Rails 7.1+ generates_token_for (Available in Rails 8.1.2)

Rails 7.1 introduced `ActiveRecord::Base.generates_token_for`, which allows:
- Tokens with configurable expiration (`expires_in:`)
- Tokens that embed record state — when the state changes, old tokens are invalidated
- Single-use behavior: if the token embeds a column that changes on use (e.g., a `used_at` timestamp or bcrypt salt), the token becomes invalid after first use

Example pattern for a validation token:

```ruby
generates_token_for :query_validation, expires_in: 30.days do
  # Embedding used_at means the token is invalidated once the record is updated
  used_at
end
```

**Important limitation:** `generates_token_for` tokens are **not stored in the database**. They are HMAC-signed tokens derived from the record's primary key and embedded data. This means:
- No table needed to track issued tokens
- Token revocation works by changing the embedded data (e.g., marking as used)
- A token cannot be "listed" or "looked up" — you can only verify it by calling `User.find_by_token_for(:query_validation, token)`

### 3. The Email Client Prefetch Problem

**Critical finding:** Microsoft Outlook and other email clients (including security scanners like Proofpoint) automatically prefetch URLs in emails. If the validation link is a GET request that directly consumes the token, Outlook will invalidate the token before the user clicks it.

**Standard mitigations (ranked by effectiveness):**

1. **Intermediate confirmation page (recommended):** The GET request from the email opens a page showing "Click here to confirm validation." The token is only consumed when the user POSTs the confirmation. Email clients prefetch GET URLs but do not POST. This is the industry-standard solution.

2. **Two-step token:** Issue a short-lived "click token" that, when GET-fetched (potentially by Outlook), only generates a second "action token" valid for 15 minutes. The page then uses the action token via POST.

3. **User agent detection:** Reject requests from known scanner user agents (Outlook Safe Links, etc.). Fragile and easily bypassed.

**Conclusion:** Not directly applicable since we're using OTP authentication (see Evidence #10). The OTP flow inherently solves this — the GET only shows the OTP input page, no data is exposed.

### 4. Long-Lived Token Problem

Validation processes can take months. Options:

| Approach | Pros | Cons |
|----------|------|------|
| Long expiration (e.g., 90 days) with `generates_token_for` | Simple, no DB state | Token cannot be extended; if it expires, must re-send |
| Stored token with `expires_at` column (like `company_tokens`) | Full control, can extend/revoke anytime | Requires DB table, more code |
| Re-send on expiry (user requests new link) | Simplest UX path | Extra step for user |

**Recommendation from evidence:** The `CompanyToken` pattern (UUID stored in DB with `disabled_at`) gives full control. For a validation system where processes run for months, storing the token in a DB table is safer. The `generates_token_for` approach is elegant but not ideal when you need:
- To list all pending tokens for a client
- To revoke tokens without the record changing
- To extend expiration on demand

A DB-stored token table (similar to `company_tokens`) is more appropriate for this use case.

### 5. PDF Generation — Prawn vs ferrum_pdf

| Criteria | Prawn | ferrum_pdf |
|----------|-------|------------|
| **GitHub Stars** | 4,800 | 496 |
| **Total Downloads** | 90.2M | 318K |
| **Latest Version** | 2.5.0 (Mar 2024) | 3.1.0 (Dec 2025) |
| **Releases in 2025** | 0 | 5 (2.0.0, 2.1.0, 3.0.0, 3.0.1, 3.1.0) |
| **Open Issues** | 68 | 1 |
| **License** | GPL-2.0 / GPL-3.0 | MIT |
| **External Dependency** | None (pure Ruby) | Chrome/Chromium on server |
| **Approach** | Programmatic (Ruby code draws PDF) | HTML to PDF (renders HTML with Chrome) |
| **Author** | Community (minimal maintenance) | Chris Oliver (GoRails, very active) |
| **Maintenance Status** | At risk — [creator discussing revival](https://github.com/orgs/prawnpdf/discussions/1386) | Thriving — 5 releases in 2025 |

**Key findings:**
- Prawn has not had a release in over 2 years, with gaps of years between releases
- Prawn uses **GPL license** which may have implications for proprietary software
- ferrum_pdf is actively maintained by a prominent Rails community member
- ferrum_pdf's HTML-to-PDF approach is more productive (write HTML/CSS, get PDF)
- Chrome dependency is trivial in a Docker-based deployment

### 6. Dynamic Query Definition Per Client

Different clients need different query sets (some have groups, transactions, etc.). The query catalog must be configurable per client.

Existing patterns to learn from:
- `UserIdentifier` with polymorphic identifier types — clients have different identifier configurations
- `Indicator` with configurable calculation rules — each client's indicators are independent

**Pattern for query catalog:**
- A `IntegrationQueryTemplate` model (managed by 4Shark admins) defines available query types
- A `IntegrationQuery` model links a template to a specific company with the actual SQL content
- Admins compose the required set per client from the catalog

### 7. Where Does This System Live?

**Options analyzed:**

| Location | Pros | Cons |
|----------|------|------|
| New standalone app | Clean separation; can have its own UI/auth; independent deploys | More infrastructure; more maintenance; no existing auth/user context |
| Existing `app` (this repo) | All company/user context already exists; email infrastructure; shared auth; existing permission model; S3 storage; Sidekiq | Mixed concern with compensation system; this app is API-only (GraphQL + REST) with no HTML UI for external parties |
| Integrator | Handles integration orchestration already; knows about the integration process | Less company/user context; different domain |

**Engineer decision:** The portal will be a **standalone new application** with its own domain and infrastructure. This means:
1. Full greenfield setup: database, email, PDF, authentication, UI
2. Will need an API integration with the existing `app` to fetch company/user/indicator context
3. Clean separation — independent deploy cycle, no risk to core compensation system

### 8. Email Provider — AWS SES vs SendGrid vs Postmark

| Criteria | AWS SES | SendGrid | Postmark |
|----------|---------|----------|----------|
| **Cost at 100 emails/mo** | ~$0.01 | $19.95/mo | ~$15/mo |
| **Cost at 1,000 emails/mo** | ~$0.10 | $19.95/mo | ~$15/mo |
| **Pricing model** | $0.10 / 1,000 emails | Fixed tiers | Fixed tiers |
| **Setup complexity** | Higher (DNS, verification) | Dashboard-friendly | Dashboard-friendly |
| **Already on AWS?** | Yes (ECS/EC2 infra) | N/A | N/A |
| **Deliverability** | Good (requires SPF/DKIM config) | Good out-of-the-box | Excellent (transactional focus) |

**Key findings:**
- For the expected volume (low — onboarding notifications), SES costs are essentially zero
- The team already operates on AWS — no new vendor relationship needed
- DNS setup (SPF/DKIM) is required regardless of provider
- SendGrid and Postmark add unnecessary fixed costs for this volume

### 9. Existing Patterns Directly Applicable

| Pattern | Source | Applicable To |
|---------|--------|--------------|
| UUID token with `disabled_at` | `CompanyToken` | Validation link tokens |
| IP address capture on actions | `UserHistory`, `Acceptment` (validates `:from` as IP) | Recording who validated and from where |
| State machine (initial -> processing -> final) | `Audit`, `Document` | Wave and query validation lifecycle |
| S3 file storage via Fog-AWS | `Document`, `Signature`, `Audit` | Storing generated PDFs |
| `SecureRandom.uuid` as unique identifier | `CompanyToken`, `AuthenticatorConfiguration` | Validation tokens |
| Immutable event records | `UserHistory`, `Audit` (no update, only create) | Audit trail / timeline |
| Sidekiq workers for async processing | Throughout | PDF generation async, email sending |
| `enumerize` + state_machine | `Audit`, `Document` | Query and wave status |
| Pundit for authorization | `DocumentPolicy`, `ApplicationPolicy` | Portal access control |
| Multi-locale support | i18n throughout | Portal can be multi-language from the start |

### 10. Identity Verification and Link Sharing

**Engineer decision:** Link-based authentication alone is NOT sufficient. The system needs to verify the person's identity, not just that someone has a link. If a link is shared/forwarded, the wrong person could validate queries under someone else's name.

**Chosen approach — OTP (One-Time Password) via email:**

1. User clicks the link in the email -> page loads
2. Page shows a code input field and automatically triggers an OTP send to the user's registered email
3. User checks their email, gets the 6-digit code, enters it on the page
4. System verifies the code -> user is now authenticated with confirmed identity
5. Session is established — user can proceed with validation

**Why this works:**
- Only the person with access to the email can get the code
- The link alone gives no access — it just shows the OTP input page
- If someone shares both the link AND the code, that's their responsibility (and the audit trail captures everything)
- Solves the Outlook prefetch problem too — the GET just shows the OTP page, no data is exposed

**Implementation considerations:**
- OTP codes should be short-lived (5-10 minutes)
- Allow resend if code expires
- Lock after N failed attempts (brute force protection)
- Store: who authenticated, when, IP address, user agent

---

## Decisions (All Resolved)

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| D1 | Where does it live? | **New standalone Rails app** | Clean separation, own domain (`integration.app4shark.com`), dedicated infra (ECS/EC2) |
| D2 | Technology stack | **Ruby on Rails** | Team's core competency, full-stack with server-rendered HTML |
| D3 | PDF generation | **ferrum_pdf** | Actively maintained (5 releases in 2025), MIT license, HTML-to-PDF is more productive, Chrome trivial in Docker |
| D4 | Email provider | **AWS SES** | Already on AWS, essentially free at this volume, no new vendor |
| D5 | Authentication | **OTP via email** | Identity verification required, not just link access. Solves prefetch problem inherently |
| D6 | UI approach | **Server-rendered HTML** (Rails ERB/Hotwire) | Simplest path for a portal with forms and validation flows |

---

## Conclusions

### C1: The system will be a standalone Rails application

**Decision (engineer):** This will be a brand new, independent Rails application with its own domain (e.g., `integration.app4shark.com`) and dedicated infrastructure (ECS cluster or EC2). It will NOT live inside the existing `app`.

**Implications:**
- Needs its own authentication, email, PDF, and database infrastructure
- Will need to communicate with the existing `app` via API to fetch company/user/indicator context (or replicate the minimum necessary data)
- Clean separation of concerns — the integration validation domain is fully independent
- Independent deploy cycle, no risk of affecting the core compensation system

### C2: Email via AWS SES

Since the team already operates on AWS, SES is the natural choice. For the expected low volume (onboarding notifications only), costs are essentially zero (~$0.10/1,000 emails). DNS setup (SPF/DKIM) is required but straightforward. No new vendor relationship needed.

### C3: Authentication via OTP (email verification), not magic links

**Decision (engineer):** Link-based auth is insufficient — we need identity verification. The flow is: click link -> enter OTP code sent to email -> authenticated session. This also inherently solves the Outlook prefetch problem (GET only shows OTP page, no data exposed).

### C4: Session-based authentication after OTP verification

Once the OTP is verified, a session is established. The user can navigate the validation portal without re-entering codes on every page. Session should have a reasonable TTL (e.g., 24 hours) given these processes can take time.

### C5: PDF generation via ferrum_pdf

ferrum_pdf is the clear winner over Prawn:
- **Actively maintained**: 5 releases in 2025, maintained by Chris Oliver (GoRails)
- **MIT license**: no GPL concerns
- **HTML-to-PDF**: write HTML/CSS templates, get high-quality PDFs
- **Prawn is at risk**: no releases in 2+ years, GPL license, [maintenance discussion ongoing](https://github.com/orgs/prawnpdf/discussions/1386)
- **Chrome dependency**: trivial in Docker-based deployment (already standard for ECS)

The PDF is a point-in-time snapshot of a validated wave. It must be immutable after generation and stored in S3.

### C6: Query catalog should be a configurable admin function

A query template catalog (managed by 4Shark admins) linked to per-company query definitions is the right model. Mirrors how indicators and user identifiers are handled for each client.

### C7: MVP scope

**Minimum to deliver value:**
1. Admin UI to define which queries are required per client/wave
2. Email invitation to IT with link to the portal
3. OTP email authentication for all external users (IT and Operations)
4. IT submission form (authenticated via OTP) to submit queries per flow
5. Operations validation portal (authenticated via OTP) to review and validate query results, with IP capture
6. Timeline/audit trail (immutable event records per company)
7. PDF generation (ferrum_pdf) when all queries in a wave are validated
8. Email with PDF to stakeholders

**Out of MVP:**
- Multi-wave dependency enforcement (Wave 2 can't start before Wave 1 — can be enforced manually first)
- Versioning of queries after corrections (v2.0, v3.0 documents)

### C8: Data model sketch

Core entities needed:

- `IntegrationWave` — belongs to Company; has state (pending, in_progress, validated, closed); Wave 1 = Users, Wave 2+ = Indicators
- `IntegrationQueryTemplate` — global catalog of query types (e.g., "User Registration", "Manager Change")
- `IntegrationQuery` — belongs to Wave + Template; has the SQL text submitted by IT; has validation state
- `ValidationToken` — belongs to User (Operations) + Wave; has UUID token, email, expires_at, used_at, ip_address
- `IntegrationEvent` — append-only audit trail; belongs to Wave; records every action with actor, timestamp, ip

### C9: Authorization model

- **4Shark admins**: full access to manage query catalog, client wave configuration, and view all timelines
- **IT contacts (client)**: authenticated via OTP email verification; can submit queries for their assigned flows
- **Operations contacts (client)**: authenticated via OTP email verification; can validate query results for their assigned waves
- All external users (IT and Operations) authenticate the same way: link -> OTP -> session
- No overlap with existing app user/seat hierarchy — this is a separate user base

---

## Next Steps

All decisions are resolved. The spike is complete and ready to move to planning.

**Next action:** Use `@agent-planner` to create PLAN.md for the Integration Validation Portal MVP.

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
>
> **Further reading:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/technical-spike/)
