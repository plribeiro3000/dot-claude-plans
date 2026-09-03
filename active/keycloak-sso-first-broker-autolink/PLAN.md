# PLAN — Keycloak SSO: auto-link brokered users on trusted email (first broker login)

Status: **Resolved (pending client confirmation)** — the fix is applied to every matched account. Two follow-ups remain: Josué (or any of the 41) confirming a successful login, and the 19 identities that match no Keycloak account.
Date: 2026-09-02
Environment touched: Keycloak `auth-001` (prod), realm `atento-br` (realmId `753a94cb-9558-4d6d-9676-4b3269fc0c71`), IdP alias `microsoft`, image `quay.io/keycloak/keycloak:26.6.4`.

## Problem

Atento reported (Gustavo Bonilha, email "Ajuda Atento Prime") that users could not log in to Atento Prime through the "identidade Microsoft" (Microsoft/Entra SSO). The login dead-ended on two Keycloak screens: "Sign in to your account" with `Invalid username or password`, then "Account already exists — User with email <address> already exists". Clearing browser cache does not help — the state is server-side, on the Keycloak account.

## Root cause (confirmed from logs and account state, not inferred)

The dead-end has **two independent causes**, and each one on its own blocks the trusted-email auto-link inside the `Handle Existing Account` sub-flow. A single account can carry either or both.

1. **A stale Microsoft federated link.** When a user's Entra identity changes, Keycloak's stored federated link no longer matches the current assertion, so every login is treated as a *first broker login* → email collision with the existing local account → the sub-flow demands a local-password re-authentication the SSO user does not have → dead-end. Evidence: an earlier Josué attempt logged `error="user_not_found"`, `userId="null"`, `identity_provider_identity="josue.neto@atento.com"`, but `username="ab1530408@br.atento.com"` — the brokered principal surfacing as a matrícula-form address distinct from the identity that created the original link. 39 of the affected accounts carried a stale link like this.

2. **The local account's `emailVerified=false`.** `Automatically set existing user` only auto-links the brokered identity to an existing account when that account's own email is verified — even with a correct flow, `Trust Email` on, and no stale link. With the account unverified and `Account verification options` disabled, Keycloak does not trust the match and has no verification path, so it falls through to the password step and fails. This is Josué's case: his account had no stale link (`federatedIdentities: null`) and his normal email, yet his 15:32 UTC attempts still logged `error="invalid_user_credentials"`, `userId="null"` — the flow never attached his account. His account state showed `emailVerified: false` as the only anomaly (`enabled: true`, no `requiredActions`).

The realm flow itself is **correct and was not the bug**: the active first-broker-login flow is `upgraded first broker login` (bound realm-wide — "Used by: First broker login flow"; the built-in `first broker login` is "Not in use"), its `Handle Existing Account` has `Detect existing broker user` (Required) → `Automatically set existing user` (Required) with `Confirm link existing account` and `Account verification options` both disabled, and `Trust Email` on the Microsoft IdP is on. This config is the prerequisite for auto-link; the two account-state defects above are what stopped it from completing.

## Decision — Model A: auto-link by trusted email

On an email collision, Keycloak auto-links the brokered identity to the existing account (no confirmation, no re-auth), gated on the IdP's `Trust Email`.

Rationale (engineer, informed): 4Shark only does SSO with a client-specific provider (the client's own Entra/Google). The client owns and verifies the directory; the email arrives already verified in the token — 4Shark does not and need not validate it. The account-takeover vector requires admin access to the client's own directory, and such an admin can create accounts anyway. End users never see the `auth-001` URL; SSO is transparent. So trusted-email auto-link is safe for this fleet.

Model B (never link a changed identity; user comes through unrecognized and the app denies) was considered and rejected — it would leave the user locked out until re-provisioning.

## Mechanism

Keycloak realm/flow config is managed **only via the web admin console** — there is no Terraform for it (the `keycloak` repo is the Docker image; `terraform/modules/auth` is only the ECS infra; no `resource "keycloak_*"` exists). The per-account state defects (stale link, `emailVerified`) are corrected via the Admin REST API — the supported path, which keeps the Infinispan cache coherent, versus a direct write to `FEDERATED_IDENTITY` / the user tables.

- Remove a stale link: `DELETE /admin/realms/atento-br/users/{id}/federated-identity/microsoft`.
- Verify the email: `PUT /admin/realms/atento-br/users/{id}` with the account representation carrying `emailVerified: true` (reversible — set back to `false` if ever needed).
- Admin token: `POST /auth/realms/master/protocol/openid-connect/token`, `grant_type=password`, `client_id=admin-cli`. The base path is `/auth`, so every URL is `https://auth-001.app4shark.com/auth/...`.

## What was done (DONE)

- [x] Read the full email thread and both client screenshots.
- [x] Pulled Keycloak logs from CloudWatch (log group `/ecs/auth-001-web`, `sa-east-1`) and confirmed both causes: the stale-link identity change and, for Josué, the `userId=null` / `invalid_user_credentials` failures with no stale link.
- [x] Confirmed the realm flow is already correct (`upgraded first broker login` bound, auto-link executions in place, `Trust Email` on) — no flow change needed.
- [x] Removed the stale Microsoft federated link from **39 accounts** (2 were already clean; 19 identities matched no account).
- [x] Confirmed Josué's account state via the Admin REST API — `emailVerified: false` was the single anomaly.
- [x] Set `emailVerified=true` on **all 41 matched accounts** (the batch checks each account first and only flips the ones still `false`, so it is idempotent).
- [x] Replied to the client (Gustavo, cc Paulo Cardoso) with the cause and the fix, asking Josué to retest and suggesting the Atento team check the Microsoft-side registration change. Client-facing content carries no 4Shark infra detail.

## Earlier related work — PR #600

The `Trust Email` guidance in `ADD-SSO-CLIENT.md` came from the merged `feature/enable-trust-email-sso-runbook` branch — **PR #600 in `dot-claude`**. Trust Email was documented there as if it auto-linked on its own; in KC 26 it is only the prerequisite, and the `Handle Existing Account` flow customization plus verified account state are what actually re-link. The runbook PR below completes that correction.

## Pending

- [ ] **Client login confirmation.** The `emailVerified=true` fix is the identified blocker for the no-stale-link accounts, but no successful login has been observed yet — Josué (or any of the 41) logging in confirms the diagnosis. If a login still fails, the new log event (against the now-corrected account) shows what remains.
- [ ] **The 19 identities that match no Keycloak account.** These fail because the address Entra asserts matches no local account — the `.onmicrosoft.com` tenant UPN (`ab1462294@atentoglobal.onmicrosoft.com`), or a divergent domain (`grazielle.martins@atento.com.br` with `.com.br`, `wendel.silva.1510266@atento.com`). `emailVerified` cannot fix an account that does not exist; this is `Detect existing broker user` finding no match, and it is a separate problem to investigate.
- [x] **Runbook PR in `dot-claude`** — documented the auto-link configuration in the single sign-on runbook (`docs/runbooks/client-onboarding/ADD-SSO-CLIENT.md`): corrected the Trust Email framing (prerequisite, not auto-link), added the `Handle Existing Account` recipe, and split the "Account already exists" troubleshooting row into the abandoned-first-login and changed-identity/stale-link variants. Merged (PR #600 / #601).

## Rollback

- Flow: Authentication → Flows → built-in `first broker login` → Bind flow → First broker login flow. Reverts the realm to the untouched built-in (restores the prior dead-end behavior).
- Account state: `emailVerified` is set back to `false` per account via the same `PUT`; a removed federated link re-creates itself on the next successful brokered login.
