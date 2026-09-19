# PLAN — Magnatech Tiny (Olist) integration

Objective: integrate Magnatech's data from the Tiny (Olist) v3 ERP into 4Shark. The
prerequisite — a live OAuth2 token to Tiny — is restored and kept alive by a temporary
bridge; the integration itself is the work that starts on Monday.

Companion files in this folder: `tiny_token.sh` (the OAuth client: `authorize-url`,
`exchange`, `refresh`, `test`), `refresh_cron.sh` (the non-interactive hourly runner),
`SPIKE.md` (the research behind the managed-renewal design and the change-delivery model).

## Current state (2026-09-18)

Access to Magnatech's Tiny data is **restored and self-sustaining**. A fresh OAuth2
authorization was done with the client, the token pair is stored on a server, and an
hourly job refreshes it well inside Tiny's 24h refresh window — so the chain no longer
lapses and no further re-authorization with the client is needed while the bridge runs.

The renewal runs as a **temporary bridge on `atento-mongo004`** (see below). Its proper
home is a job inside a future `integrator-magnatech` Terraform stack, which does not exist
yet — building that is part of the integration work.

## Background — why access was lost (still load-bearing)

Tiny v3 uses OAuth2 **Authorization Code** (Keycloak at `accounts.tiny.com.br/realms/tiny`).
A human who owns the Tiny account authorizes the app once in the browser, producing a
short-lived `code`; that `code` is exchanged for an **access token (~4h)** and a **refresh
token (~24h)**. Access is kept alive by refreshing within the 24h window. There is no
`client_credentials`/service-account path confirmed on Tiny, so once the chain lapses,
re-consent by the account owner is the only way back.

An earlier refresh script lived as a loose file on an EC2 host that was later reprovisioned,
which wiped it; the 24h window then lapsed and the refresh token died. That is the failure
this plan's renewal design exists to avoid — the renewal must be a reliable, versioned job,
never a loose file on a host that a reprovision erases.

## Handoff — what was done on 2026-09-18 (for Monday)

- **Re-authorization with the client.** In a call with Bruna (Magnatech), the "4Shark
  Integrator" app's Client Secret was recovered and a fresh browser authorization produced a
  new `code`, which was exchanged for a valid token pair. `tiny_token.sh test` returned
  `HTTP 200` — reads against the Tiny v3 API work.
- **A bug in `tiny_token.sh` was fixed.** `save_tokens` read the response JSON from stdin,
  which the heredoc program already consumed, so it crashed on save. It now passes the JSON
  through an env var (`TINY_RESPONSE_JSON`) to `json.loads`. The exchange itself was always
  fine — only the save step was broken.
- **The token pair was placed on `atento-mongo004`** and an hourly refresh was installed and
  proven — a test refresh renewed the token (`OK: token renovado`), so the box now owns the
  live chain.
- **A separate, permanent IAM fix landed** (terraform PR #1179, merged and applied): the
  engineer `EngineerWriteAccess` policy granted `ssm:StartSession` only on the account-less
  session-document ARN, so no engineer could open an SSM session to any host. It now also
  lists the account-scoped document ARN, fixing interactive host access for every engineer
  and every host. The credential was moved to the box through that SSM session, so it never
  passed through the chat or CloudTrail.

## The renewal bridge on `atento-mongo004` (temporary)

Instance `i-0d1fb7cde4b56697b` (`integrator-atento-mongo004`, `sa-east-1`), reached via SSM
Session Manager. The renewal reads the stored secret, calls Tiny to refresh, and rewrites the
token file; a cron fires it hourly. Its log records one line per run.

Check it is alive (in an SSM session on the box):

```bash
sudo cat /var/log/magnatech-tiny-refresh.log
```

Each hour should add an `OK: token renovado` line. A `FALHOU` line means the refresh token
lapsed (the box was down > 24h, or the box was reprovisioned and the files are gone) — the
recovery is a fresh re-authorization with Bruna, same as the initial one.

**This bridge is temporary and carries a known risk:** `atento-mongo004` belongs to the
Atento integration, not Magnatech, and its `/opt/magnatech-tiny` files are NOT
Terraform-managed. If the box is reprovisioned, everything below vanishes silently and the
chain dies. Move the renewal into the `integrator-magnatech` stack as soon as it exists.

## Teardown — remove Magnatech from `atento-mongo004`

When the renewal moves to its own infrastructure (or the integration is dropped), everything
Magnatech must be wiped from this box so nothing of one client lingers on another client's
host. These are all the files created here:

| Path on the box | What it is |
|---|---|
| `/opt/magnatech-tiny/tiny_token.sh` | the OAuth client script |
| `/opt/magnatech-tiny/refresh_cron.sh` | the hourly runner |
| `/opt/magnatech-tiny/secret` | the Tiny Client Secret (mode 600) |
| `/opt/magnatech-tiny/tokens` | the access/refresh token pair (mode 600) |
| `/etc/cron.d/magnatech-tiny-refresh` | the hourly cron entry |
| `/var/log/magnatech-tiny-refresh.log` | the renewal log |

Removal (in an SSM session on `i-0d1fb7cde4b56697b`, as root) — delete the cron first so it
cannot fire mid-teardown:

```bash
sudo rm -f /etc/cron.d/magnatech-tiny-refresh
```

```bash
sudo rm -rf /opt/magnatech-tiny
```

```bash
sudo rm -f /var/log/magnatech-tiny-refresh.log
```

Confirm nothing remains:

```bash
sudo ls -la /opt/magnatech-tiny /etc/cron.d/magnatech-tiny-refresh /var/log/magnatech-tiny-refresh.log
```

It should report "No such file or directory" for all three. The token in Tiny is not revoked
by this — it simply stops being refreshed and lapses on its own within 24h.

## The integration itself — the work that starts Monday

The full research is in `SPIKE.md`. The load-bearing decisions to build on:

- **Renewal, done right.** Authorize once, then refresh with a wide margin (a real integrator
  refreshes every ~3–3h50 against the 4h/24h window, so one missed run never hits the cliff).
  Host it on the proven 4Shark shape — an `ecs_scheduled_task` (Fargate + EventBridge, the
  harvester pattern) inside a future `integrator-magnatech` stack — with the cron/scheduler
  alarms that alert before the 24h cliff. The one new piece versus a plain harvester is a task
  that writes its OWN rotated token back (`ssm:PutParameter`), which no ECS task in the
  codebase does today.
- **Test `client_credentials` first.** The realm advertises the grant type; if the "4Shark
  Integrator" app has service accounts enabled, machine-to-machine auth removes the whole
  24h-cliff / human-re-auth problem class. It is one side-effect-free curl with the recovered
  secret — settle it before designing the renewal around Authorization Code.
- **Change delivery is polling, not webhooks.** The v3 OpenAPI spec exposes no webhooks. Poll
  incrementally by `dataAlteracao` (`/produtos`) and `dataAtualizacao` (`/pedidos`). Stock
  (`/estoque`) has only a per-product GET — no bulk date-filtered listing — so it needs a
  separate design.
- **Validate the customer data.** Confirm the product×category list Bruna sent (categories
  0,7% and 2%) against Tiny before building the script that consumes the token.

## Local artifacts (this machine)

The source of truth for the two scripts is this folder (`tiny_token.sh`, `refresh_cron.sh`);
the box holds copies. `com.4shark.magnatech-tiny-refresh.plist` here is a launchd unit for a
Mac-local variant that is **not** used — the bridge runs on the box, not the workstation.
The Mac token/secret files (`~/.magnatech_tiny_tokens`, `~/.magnatech_tiny_secret`) are stale
now that the box owns the chain and can be deleted.

## Language note

Internal engineering doc → English per § Language Policy. Command values and the box paths
are literal.
