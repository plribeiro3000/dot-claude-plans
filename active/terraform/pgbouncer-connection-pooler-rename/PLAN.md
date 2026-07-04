# PLAN — Infra rename: pgbouncer → connection-pooler (full)

Derived from `ANALYSIS.md` in this folder. Read it for the full inventory + risk.

## Goal

Rename the entire connection-pooler fleet from `pgbouncer` to `connection-pooler` **everywhere in the infrastructure** — ECS cluster/service/task-family, ECR, the app-facing CNAME, secrets, security group, log group, IAM, the terraform module directory, and the Cloud Map/container names — across all 4 stacks (`demo-001`, `shared-001`, `beta-001`, `atento-001`). Only the technology/repo layer stays `pgbouncer` (the `pgbouncer` GitHub repo, the `edoburu/pgbouncer` upstream image, and PgBouncer's own `dbname`/`PGBOUNCER_*` runtime config).

## Decisions (engineer)

1. **Full physical rename** — everything, including the ECS cluster/service (destroy+recreate) and the ECR (+ its repo CI). Not just the soft layer.
2. **ECR + CI in scope.**
3. **All 4 stacks.**
4. **One PR** for the terraform side (module dir included) — *yields to #5*: zero-downtime forces expand/contract, so the apply is two phases (expand, then contract) with the cutover between (see Execution strategy).
5. **Zero downtime** — hard requirement. No connection blip on any stack; the new pooler runs alongside the old and the app cuts over before the old is retired.

## Two hard constraints (facts, not options)

- **The ECR rename needs a companion PR in the `pgbouncer` repo.** `build.yaml`/`deploy.yaml` there push/deploy `<env>-pgbouncer`; they must move to `<env>-connection-pooler`. Different repo → its own PR, coordinated with the terraform apply. The new ECR must **exist and hold a built image** before the pooler service can pull `<env>-connection-pooler:latest` (the empty-ECR problem — same as the keycloak cutover).
- **Each `app-<env>-001` is a separate terraform stack (own state).** "One PR" = one review covering all 4 stacks' files + the shared module; the `apply` is still **per stack** (4 applies), each a live cutover of that stack's DB connection path.

## The change set (one terraform PR)

**Shared module** (`modules/pgbouncer/` → `modules/connection_pooler/`):
- `git mv` the directory; update every `source = "../modules/pgbouncer"` → `"../modules/connection_pooler"` (all 4 stacks).
- `local.name`: `"${var.identifier}-pgbouncer"` → `"${var.identifier}-connection-pooler"` (`main.tf:16`) — cascades to cluster (`:107`), task family (`:251`), log group (`:242`), IAM prefix (`:222`).
- Cloud Map SD service `name`: `pgbouncer` → `connection-pooler` (`:132`).
- Container `name`: `pgbouncer` → `connection-pooler` (`:265`).
- **Untouched (PgBouncer internals):** `dbname = "pgbouncer"` (`:68`), `PGBOUNCER_STATS_PASSWORD`/`PGBOUNCER_INI_B64` (`:88,297`).

**Per stack ×4** (`app-<env>-001/`, one procedure, per-env values in the table):
- `pgbouncer.tf` → `connection_pooler.tf` (file rename).
- `module "pgbouncer_v2"` → `module "connection_pooler"` (block name → `terraform state mv`).
- `internal_record_name` → `connection-pooler-<env>.4shark.internal`.
- `image` → `…/<env>-connection-pooler:latest`; `ecr_repositories` (`main.tf`) → `<env>-connection-pooler`.
- Secret names → `app-<env>-connection-pooler-{userlist,stats-password,datadog-api-key}` (+ their `secret_id` refs).
- SG (`rds.tf`): `name_prefix` + `Name` tag `app-<env>-pgbouncer` → `app-<env>-connection-pooler`; resource local `aws_security_group.pgbouncer_app_<env>` → `…connection_pooler…` (`state mv`).
- `main.tf` refs `module.pgbouncer_v2.*` → `module.connection_pooler.*`.

**Untouched:** `identity/github*.tf` (the `pgbouncer` **repo** name + team + governance lists — repo = technology, stays).

## Execution strategy — ZERO DOWNTIME, expand/contract (Parallel Change)

**Zero downtime is a hard requirement.** An in-place rename apply is therefore ruled out: renaming the ECS cluster and the app-facing CNAME forces destroy+recreate, and destroying the CNAME the app dials drops connections. Instead the new `connection-pooler` fleet comes up **alongside** the still-serving `pgbouncer` fleet (both front the same backend Postgres), the app cuts over, then the old retires — the Parallel Change pattern (`DEPLOYMENT-STRATEGY.md`).

**Consequence — this is TWO terraform applies, not one in-place rename.** Zero-downtime *requires* the transient state where both poolers exist; that cannot be one destroy+recreate apply. Expand (add the new) and Contract (remove the old) are two phases with the cutover between them. This is the one place the earlier "single PR" wish yields to the "no downtime" requirement — parallel-run is the price of zero downtime. (Structured as an Expand PR then a Contract PR, or one PR applied in two passes with the app cutover between; either way the new runs beside the old during the window.)

**Phase A — Expand (new fleet alongside old, no app impact).**
1. Companion `pgbouncer`-repo PR: `build.yaml`/`deploy.yaml` also build+deploy `<env>-connection-pooler`. Merge only after the new ECR exists.
2. Terraform: ADD a second module instance `module "connection_pooler"` (source `../modules/connection_pooler`) **beside** the existing `module "pgbouncer_v2"` — new ECR, cluster, service, task-family, secrets, and the new CNAME `connection-pooler-<env>.4shark.internal`. The old pgbouncer pooler and its CNAME are untouched and keep serving.
3. Merge the `pgbouncer`-repo PR → CI pushes `<env>-connection-pooler:latest` → the new pooler service starts healthy against the same backend DB. Now two poolers run in parallel.

**Phase B — Cutover (per stack, beta-001 → demo-001 → shared-001 → atento-001).**
4. Populate the new out-of-band secrets (userlist/stats/datadog) so the new pooler authenticates.
5. Flip the app's `DATABASE_URL` (SSM) from `pgbouncer-<env>…` to `connection-pooler-<env>…` and roll the app. New connections open on the new pooler; the **old CNAME still resolves**, so existing connections drain gracefully — **no blip**.
6. Validate the app on the new pooler; watch the old pooler's connection count drain to zero.

**Phase C — Contract (remove old, after all stacks cut over).**
7. Terraform: remove `module "pgbouncer_v2"`, the old CNAME, the old secrets, and the old `<env>-pgbouncer` ECR (empty + destroy, like the keycloak legacy ECR). The `connection_pooler` module is now the only one, already canonically named.

## Risks

1. **4 productive DB poolers.** Zero-downtime is delivered by parallel-run + the `DATABASE_URL` flip as the cutover — never a destroy-in-place. Old CNAME kept until connections drain; order beta/demo first, then shared/atento.
2. **Empty new ECR.** The new pooler cannot start on `<env>-connection-pooler:latest` until the `pgbouncer`-repo CI has pushed an image (Phase A.3).
3. **Out-of-band secrets.** The new secrets must be re-populated for the new names before the new tasks are healthy (Phase B.4).
4. **Double running cost/DB load, briefly.** Two poolers per stack during the window means ~2× pooler tasks and both holding backend connections — bounded and short (cut over promptly); size the backend `max_connections` headroom before Phase B on shared/atento.
5. **Do NOT rename the existing module block in place.** Adding a *new* `connection_pooler` module beside the old avoids `state mv` gymnastics on live resources — the old is removed wholesale in Phase C, not mutated.

## Next step

Compose per-stack `TASKS.md` (the ordered cutover checklist ×4 + the companion `pgbouncer`-repo CI change), then open the single terraform PR and the companion repo PR. No apply until both PRs are open and the plans are reviewed per stack (apply-before-merge, per-stack).
