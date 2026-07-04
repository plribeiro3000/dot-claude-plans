# PLAN — Migrate integrator email to standard Rails SMTP via Google SMTP relay

- **Projects:** integrator (code) + terraform (env/secrets, all integrator stacks)
- **Status:** approach VALIDATED on `cl-staging` (real email received at `paulo@4shark.com.br`). Now: finalize + roll out to all integrators.

## What was validated

Standard Rails ActionMailer delivery through the **Google Workspace SMTP relay** — `smtp-relay.gmail.com:587`, STARTTLS, **authenticated by IP** (no password, no OAuth). Proven end-to-end on `atento-cl-staging`: `MissingPermissionReportMailer.create(...).deliver_now` → exit 0, `MAIL_SENT_OK`, email delivered to the inbox.

### Why this is the path (not app password / not XOAUTH2)

- Google removed plain-password SMTP (less-secure-apps, 2022→2025). Account password no longer works.
- App passwords are being phased out — the admin toggle is gone from this Workspace; `myaccount/apppasswords` returns "not available".
- The mandatory-2FA policy (the original reason XOAUTH2 was hand-built) is not the blocker; even removing 2FA would not restore password SMTP.
- Google's own recommended method for apps is the **SMTP relay service** (IP-authenticated). It is the documented path, not a workaround.

### The single egress IP (confirmed)

All 5 integrator client VPCs (`atento`, `almaviva`, `commcenter`, `maqnelson`, `redebrasil`) route `0.0.0.0/0` → the same Transit Gateway `tgw-0508b36fb9563236e` → the shared egress VPC (`egress-sa-east-1`) → the **single** egress NAT → **EIP `54.207.183.89`**. One allowlist entry covers every integrator, including any future one (same TGW→egress path).

### Relay config (done in Workspace Admin)

Apps → Gmail → Routing → SMTP relay service: Allowed senders = "only addresses in my domains"; Authentication = IP `54.207.183.89/32`; Require TLS. All 12 integrator environments use `MAILER_FROM=nao-responda@4shark.com.br` (in-domain), so the sender restriction is satisfied everywhere.

---

## Workstream A — integrator code (hotfix/8.4.20, PR #2268) — FINAL

Already amended to the relay shape. No further code change needed.

- Deleted the hand-rolled stack (`MailDeliverer`, `GoogleAccessTokenFetcher`, `MailEnvelope` + parts) and the 3 `google_*` config methods.
- `production.rb` `smtp_settings` = `{ address, port, domain, enable_starttls_auto: true }` — **no `user_name`, no `password`, no `authentication`** (IP-authenticated relay). Reads host/port/domain from env (`MAILER_ADDRESS`/`PORT`/`DOMAIN`).
- 9 report consumers deliver via `.deliver_now`; the 2 attachment mailers (`IntegrationReport`, `OpenTransactions`) attach via Rails `attachments[...]`.
- Version `8.4.20`, CHANGELOG `### Changed → Email delivery`.

**The code is provider-agnostic** — it just reads `MAILER_ADDRESS`/`PORT`/`DOMAIN` and does an unauthenticated STARTTLS send. Switching host to the relay is an env concern (Workstream B), not code.

**Stays open until the productive env is ready** (see Ordering). Merging + `git hf hotfix finish 8.4.20` is the last step, after every productive integrator has the relay env.

## Workstream B — terraform, ALL integrators

Scope: **5 stacks, 12 environments.**

| Stack | Environments |
|---|---|
| `integrator-atento` | atento-br, atento-cl, atento-cl-staging✅, atento-co, atento-co-staging, atento-mx, atento-mx-staging |
| `integrator-almaviva` | almaviva |
| `integrator-commcenter` | commcenter, commcenter-staging |
| `integrator-maqnelson` | maqnelson |
| `integrator-redebrasil` | redebrasil |

(`atento-cl-staging` already migrated + `MAILER_PASSWORD` removed via PR #604.)

### B1. Change the mail host (per environment)
- `MAILER_ADDRESS`: `smtp.gmail.com` → `smtp-relay.gmail.com`
- `MAILER_DOMAIN`: `gmail.com` → `4shark.com.br` (HELO = sending domain)

Lives in each `local.<env>_env_vars` in the stack's `compute*.tf`.

### B2. Remove the now-unused OAuth env/secrets (per stack)
- `GOOGLE_CLIENT_ID` — from each `compute*.tf` env-vars block
- `GOOGLE_CLIENT_SECRET`, `GOOGLE_REFRESH_TOKEN` — from `local.ssm_secret_names` (shared list) AND each compute's `secrets` array; the SSM params are destroyed by removing them from the list
- `MAILER_PASSWORD` — already removed for atento (#604); the other 4 stacks never had it

**Removing `GOOGLE_*` is the CONTRACT step — it must trail the new code everywhere** (the old XOAUTH2 code depends on `GOOGLE_*`; removing it before the new code is live breaks delivery / blocks rollback).

### B3. Optional cleanup
Any dead mail-related SSM params or the old `smtp_password`/`MAILER_PASSWORD` scaffolding — verify none remain after the applies.

---

## Ordering (expand → contract) — the critical part

The **old production code uses XOAUTH2 + `GOOGLE_*`**; the **new code uses the relay + `MAILER_ADDRESS`**. They must not be mixed incorrectly. Per environment:

1. **Relay env in place, `GOOGLE_*` still present** (expand). Apply B1 (relay host) with `GOOGLE_*` untouched. Old code keeps working (ignores `MAILER_ADDRESS`, uses XOAUTH2); new code, once deployed, uses the relay. `terraform apply` of an env change re-registers the task def and rolls the service — for **productive** integrators this is a real deploy, so do it in an idle window (integrator is rolling / internal-only).
2. **Deploy the new code.** Merge hotfix #2268 → `hf hotfix finish 8.4.20` (tags master, back-merges develop). Build each integrator image from master (`gh workflow run build.yaml --ref master -f integrator=<slug>`) → deploy each (`gh workflow run deploy.yaml -f integrator=<slug>`). Now new code + relay env.
3. **Validate** each integrator (a real report email arrives, or a one-off send confirms). Mongo must be running for the deploy preflight.
4. **Remove `GOOGLE_*`** (contract). After ALL integrators are on the new code and confirmed, apply B2 across the stacks. This is the final cleanup; do it last so rollback stays possible until then.

**Merge gate:** merging #2268 is engineer-only and is step 2 — do not merge before the productive relay env is applied (step 1), or the first productive deploy of the new code would hit `smtp.gmail.com` with no auth.

---

## Per-stack execution (one PR per terraform stack)

Each stack is one feature branch + PR + apply-before-merge (MFA). Same shape as #604:

1. `integrator-atento` — B1 for the 6 remaining atento envs + B2 (`GOOGLE_*`). (cl-staging already B1.)
2. `integrator-almaviva` — B1 + B2.
3. `integrator-commcenter` — B1 (prod + staging) + B2.
4. `integrator-maqnelson` — B1 + B2.
5. `integrator-redebrasil` — B1 + B2.

Split B1 and B2 into separate applies per the Ordering above (B1 with the code deploy; B2 only after all confirmed) — or one PR per stack with the two applies sequenced.

## Verification checklist (per environment)
- Task boots on the new image (relay `smtp_settings`) without error.
- A send (`SomeReportMailer.create(to: <internal>).deliver_now`) exits 0 with `MAIL_SENT_OK`; email received.
- `GOOGLE_*` fully gone from the task def after B2; no code references remain (already true in the hotfix).

## Risks
- **Mixed state during rollout** — mitigated by expand/contract: relay env is harmless to old code; `GOOGLE_*` removal trails the new code.
- **Productive deploy window** — B1 apply rolls productive services; run when idle.
- **Relay deliverability** — SMTP accept ≠ inbox guarantee; validated on cl-staging (inbox), spot-check one productive send.
- **Sender domain** — all 12 use `nao-responda@4shark.com.br`; if any future front uses a non-`@4shark` from, the relay's "only my domains" rejects it — verify on new integrators.

## Open PRs
- **#2268** (integrator hotfix/8.4.20) — relay code, FINAL, open until productive env ready.
- **#604** (terraform, cl-staging relay + MAILER_PASSWORD removal) — validated, ready to merge.
