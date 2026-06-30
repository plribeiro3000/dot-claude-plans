# PLAN: SAML 2.0 support for SSO onboarding

**Status:** Done — both PRs merged (app #5115, terraform #473), branches and worktrees cleaned up
**Date:** 2026-06-03
**Type:** Multi-system feature (`app` + `terraform`)
**Feeds from:** `plans/active/spike/keycloak-saml-idp-federation/SPIKE.md` (research complete 2026-05-28)

---

## Goal

Let clients federate Keycloak to their IdP via **SAML 2.0** (instead of OIDC),
changing **only** the Keycloak ↔ client-IdP boundary. Keycloak ↔ `app` stays
OIDC and unchanged. Document the onboarding, and make the `app` model accept a
SAML-only configuration.

## Decisions made (engineer)

1. **Doc structure — Option C.** Keep one operator runbook (`ADD-SSO-CLIENT.md`)
   with shared steps; extract the client-facing instruction blocks into
   per-IdP×protocol files under `sso-client-instructions/`.
2. **SAML is email-match only.** Every user must have a real, unique email.
   User-identifier matching (Microsoft Graph path) stays **OIDC-only** going
   forward. Bases without real mailboxes (e.g., call center) cannot use SAML.
3. **`identity_provider_protocol` column.** Add to `authenticator_configurations`,
   **integer-backed `enumerize`** (`oidc: 0`, `saml: 1`), default `:oidc`,
   `scope: true` — platform convention. Named `identity_provider_protocol`
   (not `protocol`) because it is the client-IdP↔Keycloak boundary; the
   app↔Keycloak boundary stays OIDC. When `oidc` → validate `identity_provider_*`
   as today; when `saml` → skip those validations.
4. **No new DB columns for SAML** (confirmed by code — see Evidence). SAML
   config (metadata/certificate) lives in Keycloak, not the database.

## Evidence — field-by-field code confirmation

The downstream Keycloak→`app` token exchange is OIDC regardless of the upstream
protocol, so the Keycloak-client fields are always needed; the IdP-credential
fields are used only by the Graph (identifier) path.

| Field | Used by | Needed under SAML (email-match) |
|---|---|---|
| `url`, `realm`, `client_id`, `client_secret`, `uuid` | `authenticator.rb:10-31` (`find_email_by`, Keycloak token exchange) | **Yes — keep validating** |
| `provider`, `type` | general | Yes |
| `identity_provider_client_id` | `azure_identity_provider.rb:39` (Graph only) | No — skip under SAML |
| `identity_provider_client_secret` | `azure_identity_provider.rb:40` (Graph only) | No — skip under SAML |
| `identity_provider_tenant_id` | `azure_identity_provider.rb:13` (Graph only) | No — skip under SAML |
| `identity_provider_user_uuid` | branch trigger `sessions_controller.rb:84` + Graph `$select` | nil under SAML; no presence validation today |

Branch that isolates the two paths: `sessions_controller.rb:84` —
`if authenticator_configuration.identity_provider_user_uuid.present?` (Graph)
`else` (email). Under SAML the `else` branch runs.

---

## Execution phases

### Phase 1 — `app`: `protocol` column + conditional validations

Repo: `~/Projects/4Shark/app` (own feature branch).

1. **Generate** the migration (do not hand-write — RAILS-MIGRATIONS discipline):
   add `protocol` to `authenticator_configurations`, string, `null: false`,
   `default: "oidc"`. Existing rows backfill to `oidc` via the default. Run
   `db:migrate`, commit migration + `schema.rb` together.
2. Model `AuthenticatorConfiguration`:
   - `PROTOCOLS = %w[oidc saml].freeze`
   - `validates :protocol, presence: true, inclusion: { in: PROTOCOLS }`
   - Gate the three IdP-credential validations on OIDC:
     - `validates :identity_provider_client_id, presence: true, if: :oidc?`
     - `validates :identity_provider_client_secret, presence: true, if: :oidc?`
     - `validates :identity_provider_tenant_id, presence: true, if: -> { oidc? && microsoft? }`
   - Add `oidc?` / `saml?` predicates (mirroring `microsoft?`).
   - *(Exact validation shape to follow existing siblings — Pattern Priming
     before writing.)*
3. Model spec: a SAML config without `identity_provider_*` is valid; an OIDC
   config without them is invalid; protocol inclusion. Read sibling specs first.
4. CHANGELOG entry under `### Added`.

### Phase 2 — `terraform`: runbook restructure (Option C)

Repo worktree: `~/Projects/4Shark/terraform-worktrees/sso-runbook-saml`
(branch `feature/sso-runbook-saml`).

**Already done this session** (4 client-instruction files created):
`sso-client-instructions/{ENTRA,GOOGLE}-{OIDC,SAML}.md`.

Remaining:

5. `ADD-SSO-CLIENT.md` edits:
   - Intro + "How the Flow Works": note SAML supported at the IdP boundary;
     identifier matching is OIDC-only.
   - Prerequisites: add protocol decision (OIDC/SAML); SAML ⇒ real emails.
   - Step 2: add a short OIDC-vs-SAML branch (SAML = add IdP as SAML v2.0
     provider, import client metadata, export SP descriptor entity ID + ACS URL
     to send the client, NameID = email; the downstream OIDC client is still
     created either way). Material in SPIKE Task A.
   - Step 3: replace the two inline blocks with a reference table pointing to
     the four `sso-client-instructions/` files by IdP × protocol.
   - Step 4: add `protocol: "oidc"` / `"saml"` to the `create!` example; note
     that under SAML the `identity_provider_*` fields are left `nil`.
   - Verification + Known Limitations: SAML-specific lines.
6. CHANGELOG entry (if the `terraform` repo keeps one).

### Phase 3 — coordinate + ship

7. Open the `app` PR (Phase 1) and the `terraform` PR (Phase 2). The runbook's
   Step 4 `protocol: "saml"` only works once the `app` PR is merged, so the
   `app` change is the gating dependency — call it out in the terraform PR.

---

## Risks / notes

- **Ordering dependency:** SAML configs can't be created until the `app`
  migration + validation change is live. Docs can merge first (harmless) but
  onboarding a real SAML client waits on `app`.
- **`encrypts` on the three IdP fields** stays as-is; under SAML they're `nil`,
  which is fine (nothing to encrypt, nothing validated).
- **`provider` stays `microsoft`/`google`** under SAML — it identifies the IdP
  vendor, not the protocol. No new provider value.
- **Runbook location:** SPIKE flagged it may belong in `dot-claude` rather than
  `terraform`. Out of scope here — separate, non-blocking decision.

## Open items

- None blocking. Phase 1 validation shape will be finalized via Pattern Priming
  against sibling models/specs at write time.
