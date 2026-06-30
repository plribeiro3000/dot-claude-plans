# PLAN — Grupo Barigui SSO Rollout

Single Sign-On for Grupo Barigui (Company `1087`) via **Google Workspace SAML 2.0**,
brokered by Keycloak (`auth-001`, realm `barigui`) into the 4Shark `app` backend.

## Current state — LIVE in production (web + mobile)

Web and mobile SSO are both live in production. Web (`grupobarigui.app4shark.com`)
validated end to end by the client (Matheus, 2026-06-16): login screen straight
into the platform, no first-access screen, no redirect interstitial. Mobile
confirmed OK (the app fetches `setup` Configuration `34404b35` via the QR /
`MOBILE_CONFIGURATION_UUID`, pulling Barigui branding + the SSO `auth_url`).
Announced to the client the same day.

**Password login stays available** — SSO is additive. `basic_authentication`
on Company 1087 is still `true`.

## Completed

- **Keycloak** (realm `barigui`, auth-001): SAML IdP `saml` imported from the
  Google metadata (Validate Signatures On, NameID = Email, assertion
  encryption Off, AuthnRequests unsigned). Browser flow auto-redirects to the
  IdP (Identity Provider Redirector default = `saml`, forms disabled).
  First-broker-login profile page suppressed (Review Profile off +
  `firstName`/`lastName` not required). AuthnRequest sent via HTTP-Redirect
  binding (no "Authentication Redirect" interstitial).
- **app** (Company 1087): two `AuthenticatorConfiguration` rows, both
  `account` / `google` / `saml` / realm `barigui`:
  - Web `5360d89b-77b8-4838-bbb3-733264c4f5d6` → redirect host `shared001`
  - Mobile `aa7e9df1-2f03-49ed-a2fa-c274b77217d9`
- **setup** (Configuration id 10): mobile `auth_url` set with the mobile UUID.
- **Front (web)**: production env vars point to the web UUID `5360d89b` /
  `shared001`. Beta env vars removed and beta redeployed (SSO link gone from
  beta).
- **Front (web) — SSO button labels** (hotfix `1.269.1`, 2026-06-16): the
  sign-in buttons were renamed from "Identidade Google" / "Identidade
  Microsoft" to action labels across all three locales — pt-BR `Entrar com
  Google` / `Entrar com Microsoft`, en `Sign in with Google` / `Sign in with
  Microsoft`, es `Iniciar sesión con Google` / `Iniciar sesión con
  Microsoft`. Requested by Matheus (he asked for "Login via Google"; we used
  "Entrar com" to stay consistent with the existing "Entrar" button and avoid
  the English word "login", which does not translate cleanly across the
  platform's locales). Article dropped on purpose ("com Google", not "com o
  Google") so the label is a single translatable string. Communicated to the
  client 2026-06-16.

## Remaining

Nothing pending on the 4Shark side — web and mobile are live, and the
button-label change shipped (hotfix 1.269.1) and was communicated to the
client. Client validation is in: Matheus confirmed on 2026-06-16 that SSO
works in production and authorized enabling it **for all users**, handling
any individual difficulties case by case ("Podemos deixar ativo para todos e
caso os usuários tenham alguma dificuldade, nós vamos tratando
pontualmente").

One open item, client-gated:

1. **SSO-only enforcement (future, only on explicit client request)** — make
   login SSO-only by disabling password login: `Company.find(1087).update!(
   basic_authentication: false)`. Confirmed lever: `SessionsController#create`
   (`app`) requires `company.basic_authentication?` for password login. Matheus
   chose an **additive** rollout (SSO available alongside password, issues
   handled one by one) and did NOT request SSO-only — so `basic_authentication`
   on Company 1087 stays `true`. Do NOT disable password login until the client
   explicitly asks (per the 2026-06-16 email: "quando validarem a utilização e
   estiverem confortáveis nós podemos ativar o login para ser apenas por SSO").

## Client-side dependencies (Barigui, not blocking our deploy)

- **Google Admin** — the custom SAML app must be turned ON for the OUs of
  **all** users who will use SSO, not just the test account. Otherwise those
  users get `403 app_not_configured_for_user` from Google.
- **User must exist in 4Shark** — SSO identifies, it does not provision. A
  Barigui user without a matching `@grupobarigui.com.br` `User` in Company
  1087 lands on `error=unauthorized` and keeps using password.

## Diagnostics

Keycloak realm events: CloudWatch log group `/ecs/auth-001-web`, filter by
realm `barigui`, `type="LOGIN_ERROR"` / `CUSTOM_REQUIRED_ACTION_ERROR`
(realm logs errors only; success is not logged).

Runbook: `~/.claude/docs/runbooks/client-onboarding/ADD-SSO-CLIENT.md`
(every learning from this rollout was folded back into it).
