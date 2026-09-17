# PLAN — Magnatech Tiny API token re-authorization

Objective: restore 4Shark's access to Magnatech's data in the Tiny (Olist) ERP by
minting a fresh OAuth2 token pair, then keep it alive so the client does not have
to re-authorize again.

Companion script: `tiny_token.sh` in this folder (`authorize-url`, `exchange`,
`refresh`, `test`).

## Background — why access was lost

Tiny v3 uses OAuth2 **Authorization Code** (Keycloak at
`accounts.tiny.com.br/realms/tiny`). A human who owns the Tiny account authorizes
the app once in the browser, producing a short-lived `code`; that `code` is
exchanged for an **access token (~4h)** and a **refresh token (~24h)**. Access is
kept alive by refreshing within the 24h window.

Emerson built a token-refresh script (`/home/deploy/magnatech/refresh.sh`) on the
Atento mongo box in April 2026. That box was reprovisioned ~14/07/2026 (verified by
SSM on 15/09: nodes `integrator-atento-mongo004/005/006` carry nothing Magnatech).
The refresh stopped, the 24h window lapsed months ago, so the refresh token is dead.
The only way back is a fresh browser authorization — which needs the client.

There is no `client_credentials`/service-account path on Tiny, so re-consent by the
account owner is unavoidable when the chain lapses.

## Prerequisites

The `CLIENT_SECRET` of the "4Shark Integrator" app and the browser authorization both live
inside Magnatech's Tiny account, so both come from Bruna during the call — there is nobody on
4Shark's side to recover the secret from. Emerson, who registered the app in April, is no
longer with the company, and the value died with his `refresh.sh`. So there is no separate
"recover the secret beforehand" step: the call itself produces both the secret and the token.

Have ready before the call:
- The `tiny_token.sh` script in this folder and an open terminal, so the code can be exchanged
  the instant Bruna produces it (it expires in seconds).
- The known `CLIENT_ID` and `REDIRECT_URI` — script defaults `tiny-api-3e15fb0a…-1776193439`
  and `http://localhost:8080/oauth/tiny/callback`. Treat them as tentative: confirm against
  what Bruna reads off the app's access-keys screen, and override with `TINY_CLIENT_ID` /
  `TINY_REDIRECT_URI` if they differ (a regenerated or recreated app changes them). The
  `redirect_uri` must match the app's registered value exactly, or Keycloak rejects it.

## Procedure — the call with Bruna

Everything happens inside Magnatech's Tiny account, on Bruna's screen. The menu labels below
are from the layout the docs describe and MAY have moved — guide her by the GOAL of each step,
not a fixed click path. She produces two things: the app's Client Secret, then a fresh `code`.

1. **Find where API applications are managed.** Ask her to look, in the account settings, for
   the screen that lists API applications / integrations. Known path: Configurações > aba
   geral > Aplicativos — but the target is "wherever API apps are configured now", not that
   exact path. It depends on the "Construa" plan + the "Gestão de Aplicativos" extension; if
   she cannot find it at all, that dependency may be why.
2. **Open the "4Shark Integrator" app and get the secret.** In the app's access-keys area
   (labelled "Chaves de acesso" on the known layout), the Client ID and Client Secret are
   shown, with an action to generate new keys (which invalidates the old — fine, the old
   tokens are dead). Ask her to send you the Client Secret and confirm the Client ID. If the
   app is gone, ask her to create one ("+ novo aplicativo") — that yields a fresh
   client_id + secret; update the script env with both.
3. **Generate a fresh token (`code`).** With the Client ID confirmed, produce the
   authorization URL on your side — `bash tiny_token.sh authorize-url` — and send it for her
   to open while logged in. She authorizes and copies the value after `code=` from the page it
   redirects to. (If the app screen exposes its own authorize/connect action that returns a
   code, that works too — the goal is a fresh `code`.) What to say:
   > "Abre esse link logada na conta de vocês e autoriza o app. Vai cair numa página que
   > provavelmente não abre — tudo bem. Copia da barra do navegador o valor depois de
   > `code=` e me manda."
4. **Exchange immediately** — the `code` expires in seconds (the `Code not valid` error seen
   in April): `bash tiny_token.sh exchange`. It prompts for the code and the Client Secret;
   nothing is echoed. Tokens are written to `~/.magnatech_tiny_tokens` (mode 600) — the
   exchange script writes it, `refresh`/`test`/the catalog validation read it. Stopgap for the
   meeting; the managed renewal is the follow-up below.
5. **Verify:** `bash tiny_token.sh test`. `HTTP 200` on `GET /produtos?limit=1` = token valid
   and reads work. `401` = token not applied; `403` = valid but missing permission.

If the authorize page errors about scope, append `&scope=openid` to the URL.

## After access is restored

- Re-establish the daily refresh (`bash tiny_token.sh refresh`) as a **reliable,
  versioned** job — not a loose file on an EC2 that a reprovision wipes. Any outage
  longer than 24h kills the chain and forces another re-authorization with Bruna, so
  the renewal must not silently stop.
- Validate the product×category list Bruna sent (categories 0,7% and 2%) before
  building the integration script that consumes the token.
- Bring the integrator infra back up (it was aborted to avoid idle cost).

## Follow-up — the right shape for a daily integration on Tiny's delegated auth

The full study is in `SPIKE.md` in this folder (sources + trade-off table). Load-bearing
conclusions:

- **Auth:** authorize once, then refresh with a wide margin — a real integrator refreshes
  every ~3–3h50 against the 4h access / 24h refresh window, so one missed run never hits the
  24h cliff. Recovery when the chain lapses is a browser re-auth with the client, confirmed by
  two independent integrations, so it is inherent to Tiny's design, not our script. BEFORE
  building around this, test `client_credentials` with the recovered `CLIENT_SECRET`: the
  realm advertises the grant type, and if the "4Shark Integrator" app has service accounts
  enabled it removes the whole 24h-cliff/re-auth problem (machine-to-machine, no human). One
  side-effect-free curl settles it.
- **Change delivery:** the v3 OpenAPI spec exposes NO webhooks (129 paths, zero webhook
  resources; every webhook doc found is API 2.0). Poll incrementally by `dataAlteracao`
  (`/produtos`) and `dataAtualizacao` (`/pedidos`). `/estoque` has only a per-product GET —
  no bulk date-filtered listing — so stock needs a separate design. Revisit webhooks only if a
  v3 capability is confirmed directly with Tiny (`integracao@tiny.com.br`).
- **Where to host:** NOT EC2 (that caused this incident). 4Shark's `ecs_scheduled_task` module
  (Fargate + EventBridge, the harvester pattern) is the proven shape — Option A. AWS's own
  purpose-built alternative is Secrets Manager + a rotation Lambda with atomic
  AWSCURRENT/AWSPENDING versioning — Option B, which adds two net-new patterns. Either way two
  things are new here: an ECS task writing its OWN rotated secret back (`ssm:PutParameter` — no
  precedent in this codebase), and the cron/scheduler alarms (proven for `app`, not wired for
  integrator/harvester) that provide the alert-before-the-24h-cliff the process requires.

## Language note

Internal engineering doc → English per § Language Policy. The lines to be spoken to
the client (Bruna) are kept as pt-BR embedded quotes on purpose.
