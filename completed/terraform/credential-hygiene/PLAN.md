# PLAN — Credential management & hygiene (Terraform + app) — ✅ CLOSED

**Multi-workstream session, all workstreams delivered.** Closed 2026-07-03.

Every application/infra secret now has a single source of truth outside 1Password (SSM, Secrets Manager, the app DB, or Keycloak), and the redundant 1Password copies were removed. Five PRs merged across two repos.

---

## Workstream 1 — Deploy AWS credentials in Terraform — ✅ DONE (merged)

- Brought all GitHub Actions deploy access keys under Terraform (import, no rotation); published `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` as GitHub environment secrets across 12 stacks (app shared/beta/demo/atento-001, setup, onboarding, auth-001, 5 integrators).
- Reusable module `modules/iam_deploy_key`. Secret reconstructed from SSM (import) or `.secret` (variant), validated read-only via STS.
- **PR #589 merged**, all 12 applied, 0 change/destroy. Worktree cleaned up.
- Spike + plan: `spike/terraform-deploy-credentials/SPIKE.md`, `terraform/deploy-credentials/PLAN.md`.

## Workstream 3 — MongoDB user password in Terraform — ✅ DONE (merged, all envs)

Goal: Terraform owns the MongoDB Atlas app-user credential so the value leaves 1Password and rotation becomes possible. Imported the CURRENT password (no rotation → no downtime).

- `modules/mongodb_atlas` gained a managed-password path: `database_users` object got `manage_password` (non-sensitive flag driving the `for_each` split) + `password`. Legacy users keep `ignore_changes = [password]`; managed users own the password (`mongodbatlas_database_user.managed_users`).
- **Username + password both from SSM** (`/<env>/MONGO_USERNAME` String, `/<env>/MONGO_PASSWORD` SecureString) — the co-location the engineer asked for. `nonsensitive()` unwraps the username so it can be a `for_each` key (a `data.aws_ssm_parameter.value` is always marked sensitive, even for a String param). `MONGO_URL` is derived from host + user + password + db and adopted via `moved` blocks — byte-equal (verified by no-change plan on the parameter).
- `mongo_database` kept as a tfvars variable (it is config, not the credential — the split the engineer objected to was user-vs-password, now resolved).
- readAnyDatabase users on shared-001/atento-001 stay on the legacy path (their password is not consumed by managed infra → managing them would be a rotation, out of scope). atento-001 consumes `MONGO_URL` by ARN through the `atento_001_task_config` module, so its parameter name is unchanged and no compute change was needed.
- **beta-001 pilot: PR #600 merged & applied** (`0 add, 1 change, 0 destroy` — the app-user password reconciled into state, no functional effect). Validated: `/ecs/beta-001-web` logs show mongo connecting, zero auth errors.
- **demo-001 + shared-001 + atento-001 rollout: PR #603 merged & applied** — same shape per env, byte-equal `MONGO_URL`, converged to `No changes`. shared/atento web logs post-apply: zero mongo connection errors.
- **Future:** swap the seeded SSM password for a generated `random_password` + rotation trigger.

## Workstream 4a — Drop the dead `MONGO_DATABASE` — ✅ DONE (merged)

- `mongo_database` reader (`app/lib/application_configuration.rb`) had zero callers — dev/prod Mongoid take the DB from `MONGO_URL`. Removed the reader + the obsolete installation-doc line.
- **Correction to the original assumption:** `MONGO_TEST_DATABASE` / `mongo_test_database` is NOT dead — `config/mongoid.yml` uses it for the test client, and CI sets it. **KEPT.** Only `MONGO_DATABASE` was removed.
- **PR #5202 (app repo) merged.** The committed `.env` still carries a `MONGO_DATABASE` default line (the file is outside the agent's edit permission) — harmless, engineer can drop it manually.

## Workstream 4b — Drop Emerson's migration statement_timeout markers — ✅ DONE (merged, applied)

- Removed the 6 `MIGRATION_2026…` markers from `app-shared-001/compute.tf` and `modules/atento_001_task_config/main.tf` (consumed only at `db:migrate` time for a deploy that already ran → inert).
- Changelog: dropped the stale `[Unreleased]` Added entry (added-and-removed within the same cycle).
- **PR #605 merged & applied** on shared-001 + atento-001 — task-def revision churn only (`ignore_changes = [task_definition]` → no service redeploy). Converged to `No changes`.

## Workstream 2 — 1Password cleanup — ✅ DONE (32 items removed)

Principle established with the engineer: a DB/system credential that has a source of truth outside 1Password (SSM / Secrets Manager / app DB / Keycloak) → the 1P copy is redundant → remove. Credentials that CANNOT live elsewhere (AWS root, the Terraform-bootstrap item, personal web logins, human web-dashboard logins, SSH keys) stay.

**Round 1 — 26 removed** (validated from scratch; homes verified read-only):
- MongoDB app (4) → `/<env>/MONGO_PASSWORD`; PostgreSQL master (7) → Secrets Manager (RDS-managed, instance for beta/onboarding/setup + Aurora **cluster** for atento/demo/shared + `auth-001-sm` for auth-001 — the cluster level was the correction after an instance-only first look); Integrator client DB (5) → `/integrator-<client>/CLIENT_PASSWORD`; deploy AWS keys (3); ex-clients Aster Maquinas + Valecard (3); superseded `[Atento] MongoDB - OLD` (1); SSO (3) — Atento BR + Maqnelson (app DB `authenticator_configurations`) + 4Shark (Keycloak realm `four-shark`).

**Round 2 — 6 removed** (Rollbar service tokens): Setup/Shared001 Server + Client → `/<env>/ROLLBAR_SERVER|CLIENT_ACCESS_TOKEN`; Development Server + Client → dropped by decision (App-Development Rollbar project; recreate if needed).

**Method:** for each batch, resolve titles → unique IDs → reverse-verify the IDs map back to exactly the intended set → generate a script with a runtime pre-flight (re-fetch each id's title, abort on any mismatch). Engineer ran the scripts (`archive` then `delete`). Agent never deleted from the vault directly.

**KEPT (confirmed):** user logins (app4shark client accounts, personal SaaS, VPN PINs, personal AWS key); Elastic Index (human web-dashboard login — value is in SSM but the 1P purpose is the human login); Terraform ENV (bootstrap, read by `.envrc` via `op`); Amazon Root; 4Shark App Master Key; MongoDB - Ivo/Paulo (Atlas console logins); Redis (Redis Labs login); active SSH keys.

**Still open — 4 service items, home to define** (not yet removed): `Administrador Máquinas 4Shark`, `Setup 4Shark`, `Setup Authentication`, `Yubico API key`. Next session: confirm where each is consumed (→ SSM or stays in 1P).

**Heuristic learned:** a 1Password LOGIN with no URL is more likely a service password (user logins carry a URL to bind them). Useful filter, not decisive — the item's username disambiguates (person email → user; generated string / no email → service). Reports: `/tmp/1password_final_scan_20260703.html`, `/tmp/1password_nourl_logins_20260703.html`.

---

## Net result

- **5 PRs merged:** terraform #589 (deploy keys), #600 (mongo beta), #603 (mongo demo/shared/atento), #605 (migration markers); app #5202 (dead `MONGO_DATABASE`).
- **32 redundant 1Password credentials removed**; 4 service items pending a home decision.
- Every removed credential's source of truth verified outside 1Password before removal.
- **Follow-up carried forward:** mongo password rotation (`random_password`); the 4 open 1P service items; the `.env` `MONGO_DATABASE` default line in the app repo.
