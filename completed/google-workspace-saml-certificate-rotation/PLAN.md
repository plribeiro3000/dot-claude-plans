# PLAN — Google Workspace SAML IdP certificate rotation (Cloudflare, AWS, MongoDB Atlas)

> Reference: derived from `../spike/google-workspace-saml-certificate-rotation/SPIKE.md` (Findings 1–10, Resolution of Finding 8, console-navigation table, rotation order)

## Objective

Replace the Google-issued SAML signing certificate that expires on 2026-09-20 13:07:43 UTC on all three Service Providers — AWS IAM Identity Center, Cloudflare Zero Trust, MongoDB Atlas — with the next Google-issued five-year certificate, without any SSO outage, and leave behind the record that makes the next rotation (~2031-09) a repeat rather than a rediscovery.

## Scope

### In scope
- One new Google certificate created in the Admin console, assigned to the three SAML apps
- AWS IAM Identity Center: import the new certificate, switch, delete the old one (console; no API exists)
- Cloudflare: `identity/cloudflare_sso.tf` `idp_public_certs` carries both certificates during the overlap, then only the new one (two PRs on the `identity` stack, applied by the policy-arbiter)
- MongoDB Atlas: replace the IdP Signature Certificate in Federation Management (console)
- `identity/README.md` § Engineer Identity Model corrected: the Identity Center identity source IS Google Workspace as an external SAML IdP (`https://d-906791aeb2.awsapps.com/start` redirects to `accounts.google.com`)
- Expiry of the new certificate recorded with months of lead time

### Out of scope
- An automated expiry monitor (spike Option D) — not adopted. 4Shark tracks every recurring operational date on the team calendar, and the calendar reminder is the control for this one too
- Scripting the Atlas side through the Admin API `pemFileInfo` PATCH (spike Option C) — needs an Organization Owner service account not yet located
- Any change to who may log in where; only the signing certificate moves

## Chosen approach

**Direction:** spike Option B — Cloudflare by terraform (the list-typed `idp_public_certs` already exists), AWS and Atlas by console — executed **AWS first**.

**Rationale (from engineer):** "começando pela aws que tenho outras formas de login então aprendemos e corrigimos o fluxo antes de fazer os outros dois" — AWS has independent login paths (IAM user with MFA; `policy-arbiter`), so a mistake there costs nothing and the flow is rehearsed before the two platforms where the fallback is thinner.

**Source patterns referenced:** Google "Maintain SAML certificates" (2-certificate ceiling, per-app dropdown), AWS "Rotate a SAML 2.0 certificate" (import → activate on IdP → delete), Cloudflare `idp_public_certs: List[String]`, Atlas "IdP Signature Certificate" upload/paste — all in the spike's `sources/`.

## Execution phases

### Phase 1: Preconditions

**Objective:** nothing in the rotation depends on something that has to be discovered mid-flight.

**Components:**
- Google Workspace super-admin account available to the engineer
- AWS console session for the policy-arbiter identity (Identity Center settings are `sso:*`, granted only to that identity — `identity/policy_arbiter_policies.tf:42`)
- Cloudflare backup API token with `SSO Connector Edit` present in 1Password (`identity/README.md:220-228`) — the only path back in if Cloudflare SSO breaks
- MongoDB Atlas Organization Owner session (break-glass account) for Federation Management

**Success criteria:**
- [x] Cloudflare `SSO Connector Edit` backup token confirmed in 1Password (engineer, 2026-09-03)
- [x] The other sessions above confirmed reachable (each was used during Phases 2–5)
- [x] Current certificate confirmed as serial `017C087823E3`, expiry 2026-09-20 (openssl on `cloudflare_sso.tf`; Identity Center listed the same expiry)

### Phase 2: Google — create the second certificate

**Objective:** the new certificate exists on the IdP side without any app pointing at it yet.

**Components:**
- Admin console → Menu → Security → Authentication → SSO with SAML applications → **Certificates** → **Add another certificate**
- Download the new certificate (PEM) and note its name and expiry (~2031-09)

**Dependencies:** Phase 1.

**Success criteria:**
- [x] Two certificates listed; the old one still assigned to all three apps (2026-09-03)
- [x] New PEM downloaded to `~/Downloads/Google_2031-9-2-85638_SAML2_0.pem` — `notBefore=Sep 3 15:56:38 2026 GMT`, `notAfter=Sep 2 15:56:38 2031 GMT`, serial `01A067FC8C91`, SHA-256 fingerprint `89:86:BE:81:D4:D7:D2:6B:77:79:6B:F1:9C:44:C8:18:4B:39:AF:32:C1:B2:9F:A6:1D:76:66:DF:E2:E1:48:05`

### Phase 3: AWS IAM Identity Center (the rehearsal)

**Objective:** AWS trusts both certificates, the Google app is switched, the old certificate is retired — and the flow is learned.

**Components:**
- Identity Center → Settings → Identity source → Actions → **Manage authentication** → **Import certificate** (new PEM). "All imported certificates are automatically active."
- Google Admin console → the AWS SAML app → certificate dropdown → choose the new certificate
- Test: sign in at `https://d-906791aeb2.awsapps.com/start` through Google; fallback is the IAM user console login
- Identity Center → Manage authentication → delete the old certificate ("There must always be at least one valid certificate listed")

**Dependencies:** Phase 2.

**Success criteria:**
- [x] New certificate imported; Identity Center lists both (created 9/21/2021 → expires 9/20/2026; created 9/3/2026 → expires 9/2/2031), both active (2026-09-03)
- [x] Portal login succeeds with the Google app on the new certificate (incognito window, 2026-09-03)
- [x] Only the new certificate remains in Identity Center (old one deleted 2026-09-03)
- [x] Google per-app switch took effect immediately for the AWS app — no propagation delay observed

### Phase 4: Cloudflare (terraform)

**Objective:** Cloudflare trusts both certificates through a reviewed PR, then only the new one.

**Components:**
- PR 1 on `terraform/identity`: `cloudflare_sso.tf` `idp_public_certs = [old, new]`; plan and apply by the policy-arbiter (`identity/README.md` § Stack Governance)
- Google Admin console → the Cloudflare SAML app → choose the new certificate
- Test: Cloudflare dashboard login for an `@4shark.com.br` member and a Zero Trust login; fallback is the `SSO Connector Edit` token
- PR 2: `idp_public_certs = [new]`; apply

**Dependencies:** Phase 3 (lessons applied); Phase 1 backup token.

**Success criteria:**
- [x] PR 1 open — https://github.com/4shark/terraform/pull/1132 (worktree `terraform/.claude/worktrees/google-saml-cert-rotation`, branch `feature/google-saml-certificate-rotation`; carries the README correction and the CHANGELOG entries)
- [x] PR 1 applied and merged 2026-09-03 (`cloudflare_zero_trust_access_identity_provider.google` updated in place, `idp_public_certs` = [old, new]; confirmation plan clean; worktree and branch cleaned up)
- [x] PR 2 applied 2026-09-03 — https://github.com/4shark/terraform/pull/1133 (worktree `terraform/.claude/worktrees/google-saml-cert-cleanup`, branch `feature/google-saml-certificate-cleanup`); state carries only the new certificate; confirmation plan clean; merged, worktree and branch cleaned up. Phase 4 complete
- [x] Dashboard SSO login verified on the new certificate (Google app switched, incognito login, 2026-09-03)

### Phase 5: MongoDB Atlas

**Objective:** Atlas validates assertions signed by the new certificate.

**Components:**
- Atlas → Organization → sidebar Identity & Access → **Federation** → **Open Federation Management App** → Identity Providers → "Google Workspace" → edit → **IdP Signature Certificate** → upload/paste the new PEM
- Google Admin console → the Atlas SAML app → choose the new certificate
- Test the Atlas SSO login immediately — whether Atlas accepts two certificates at once is unconfirmed, so this step may be a cutover; the break-glass Atlas login is the fallback

**Dependencies:** Phase 3.

**Success criteria:**
- [x] Atlas SSO login succeeds on the new certificate (Federation Management App → Google Workspace → Identity Provider Signature Certificate replaced, Save and Finish; Google app switched; incognito login, 2026-09-03). Phase 5 complete

### Phase 6: Cleanup and record

**Objective:** no trace of the old certificate, and the next rotation is scheduled.

**Components:**
- Google: delete the old certificate — the confirmation window must list no apps
- `identity/README.md` § Engineer Identity Model rewritten to state the external-IdP identity source, in the same PR series as Phase 4 (terraform `CHANGELOG.md` entry under `## [Unreleased]`)
- Expiry of the new certificate recorded as a calendar reminder six months ahead — the calendar is 4Shark's control for recurring operational dates; no automated monitor

**Success criteria:**
- [x] Only one certificate on Google (`Google_2031-9-2-85638`), assigned to all three apps — old certificate deleted 2026-09-03 with no app listed in the confirmation window
- [x] README corrected and merged (PR #1132)
- [x] Reminder in place — event "Rotacionar certificado SAML do Google Workspace (AWS Identity Center, Cloudflare, MongoDB Atlas)" on `paulo@4shark.com.br`, 2031-03-03 09:00 America/Sao_Paulo (six months before the 2031-09-02 expiry; first business day), with the full procedure in its description and reminders at 7 days, 1 day and 30 minutes
- [x] Spike folder moved to `completed/spike/google-workspace-saml-certificate-rotation/`; this plan moved to `completed/`

## Technical decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Order of platforms | AWS → Cloudflare → Atlas | Engineer: AWS has independent login paths, so the flow is rehearsed where a mistake is free |
| Cloudflare update path | Two terraform PRs (overlap, then removal) | `idp_public_certs` is a list; keeps the certificate under the stack's review and apply governance |
| AWS update path | Console (Manage authentication) | No `sso-admin` API for the identity source or its certificates was found |
| Atlas update path | Console | Terraform provider schema has no certificate field; Admin API needs a credential not yet located |
| Old certificate on Google | Deleted last | Google only lists a certificate's apps in the delete confirmation, so an early delete is the one irreversible step |
| Expiry control | Calendar reminder on 2031-03-03, no automated monitor | Engineer: 4Shark tracks every recurring operational date on the team calendar; a monitor would be a second mechanism for a five-year event |

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Certificate expires (2026-09-20) before the three switches complete | High — SSO down for every `@4shark.com.br` user on that platform | Phases 2–5 done well inside the 17-day window; per-platform break-glass documented in `identity/README.md:198-237` |
| Atlas does not accept two certificates simultaneously | Med — brief SSO gap on Atlas during the switch | Switch and test in one sitting with the break-glass account logged in |
| Cloudflare SSO breaks and the backup token is missing | High — dashboard lockout | Phase 1 verifies the token exists before any Cloudflare change |
| Google per-app switch propagates with a delay | Low | AWS rehearsal measures it; the old certificate stays active on the SP side until the login is proven |

## Assumptions

- The Google Admin console lets each SAML app pick its certificate independently ("Click the Down arrow and choose a certificate."), so the three switches are sequential, not simultaneous
- The policy-arbiter identity can reach the Identity Center console (its policy grants `sso:*` under MFA)
- The three Google SAML apps are the only consumers of the expiring certificate — confirmed on Google's delete confirmation window in Phase 6 before deleting

---

> **Authoring:** written by the main session directly from the verified spike and the engineer's instruction to rotate AWS first; no researcher/composer pipeline was run because the engineer chose the direction in chat.
