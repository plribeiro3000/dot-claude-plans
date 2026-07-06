# ANALYSIS — Infra rename: pgbouncer → connection-pooler

## Question

Survey everything in the infrastructure that still names the DB connection pooler `pgbouncer` and needs to become `connection-pooler`, so the fleet obeys the same naming convention the authenticator (keycloak → auth) now follows. Deliverable: the full inventory + risk, so the engineer can decide scope before a migration PLAN is written.

## The rule that decides each case

Per `PROJECTS-CATALOG.md` § Naming (documented this session): **the GitHub repo carries the technology name, the infrastructure carries the role name.** So:

- **Technology / repo / PgBouncer's own runtime → STAYS `pgbouncer`.** The `pgbouncer` GitHub repo, the `edoburu/pgbouncer` upstream image, and PgBouncer's own config (its admin `dbname`, `PGBOUNCER_*` env, stats user) keep the technology name — same way the `keycloak` repo stayed `keycloak`.
- **Infra role names → RENAME to `connection-pooler`.** ECS cluster/service/task-family, ECR, the app-facing DNS, secrets, security groups, log groups, the terraform module — the pooler's *role* in the infra — take the role name, same way the authenticator infra is `auth-001` (not `keycloak`).

## Already done (no action)

- **`Project = "connection-pooler"` tag** on the module (`modules/pgbouncer/main.tf:22`) — the fleet is already discoverable by the role tag.
- **`/connection-poolers` skill** (`~/.claude/skills/connection-poolers/`) — discovers **by the `Project=connection-pooler` tag**, not by resource name, so it is already correct and will keep working through the rename.

## Scope shape

The pooler is defined once in **`modules/pgbouncer/`** and instantiated by **4 productive stacks** — `app-demo-001`, `app-shared-001`, `app-beta-001`, `app-atento-001` — each `module "pgbouncer_v2"` in `app-<env>-001/pgbouncer.tf`. One procedure, 4 entities. The per-stack specifics table is at the end.

## Inventory — categorized

### A. STAYS (technology / repo / PgBouncer internals)

| Reference | Where | Why it stays |
|---|---|---|
| GitHub repo `pgbouncer` | `identity/github_repositories.tf:49,98,108`, `identity/github.tf:61` | Repo = technology name (like `keycloak` repo stayed) |
| `edoburu/pgbouncer` upstream image | Dockerfile in the `pgbouncer` repo | Upstream technology |
| Admin `dbname = "pgbouncer"` | `modules/pgbouncer/main.tf:68` | PgBouncer's own stats/admin DB — the tool's internal |
| `PGBOUNCER_STATS_PASSWORD`, `PGBOUNCER_INI_B64`, `PGBOUNCER_PREPARED_STATEMENTS` | `modules/pgbouncer/main.tf:88,297`, `app-*/compute.tf` | PgBouncer's own config env — the tool's contract |
| dot-claude docs that describe the *technology/repo* | `DOCKER-IMAGE-TOOL-REPOS.md`, `PROJECTS-CATALOG.md`, `DEPLOYMENT-STRATEGY.md` | These name pgbouncer as the reference *repo/technology* — correct as-is (light alignment only where they mean the infra role) |

### B. RENAMES to connection-pooler (infra role names)

Driven mostly by one local in the module: **`local.name = "${var.identifier}-pgbouncer"`** (`modules/pgbouncer/main.tf:16`). Changing it to `"${var.identifier}-connection-pooler"` cascades to the cluster, task family, log group, and IAM prefix.

| # | Reference | Current | Target | file:line | Risk tier |
|---|---|---|---|---|---|
| 1 | **ECS cluster name** | `<env>-pgbouncer` | `<env>-connection-pooler` | `main.tf:16,107` (`local.name` → `aws_ecs_cluster.this`) | **T1 — destroy+recreate** |
| 2 | Task family | `<env>-pgbouncer` | `<env>-connection-pooler` | `main.tf:251` | T1 (new task-def, with the cluster) |
| 3 | Log group | `/ecs/<env>-pgbouncer` | `/ecs/<env>-connection-pooler` | `main.tf:242` | T2 — recreate (logs restart) |
| 4 | IAM policy prefix | `<env>-pgbouncer-secret-` | `<env>-connection-pooler-secret-` | `main.tf:222` | T2 |
| 5 | **App-facing CNAME** | `pgbouncer-<env>.4shark.internal` | `connection-pooler-<env>.4shark.internal` | `app-*/pgbouncer.tf` (`internal_record_name`) | **T1 — app cutover** (the app's `DATABASE_URL` points here) |
| 6 | Cloud Map SD service name | `pgbouncer` | `connection-pooler` | `main.tf:132` | T2 — behind the CNAME, internal |
| 7 | Container name | `pgbouncer` | `connection-pooler` | `main.tf:265` | T3 — cosmetic |
| 8 | **ECR repository** | `<env>-pgbouncer` | `<env>-connection-pooler` | `app-*/main.tf` (`ecr_repositories`), `app-*/pgbouncer.tf` (`image`) | **T1 — couples to the `pgbouncer` repo CI** (build.yaml pushes to `<env>-pgbouncer`) |
| 9 | Per-stack secrets | `app-<env>-pgbouncer-{userlist,stats-password,datadog-api-key}` | `app-<env>-connection-pooler-*` | `app-*/pgbouncer.tf` | T1 — recreate + re-populate out-of-band values |
| 10 | Security group | `app-<env>-pgbouncer-` (name_prefix) + `Name` tag | `app-<env>-connection-pooler-` | `app-*/rds.tf` | T2 — SG replace, refs update in place |
| 11 | Terraform module dir | `modules/pgbouncer/` | `modules/connection_pooler/` | dir | T3 — `git mv` + update `source` |
| 12 | Terraform block/resource local names | `module "pgbouncer_v2"`, `aws_security_group.pgbouncer_app_*`, `pgbouncer.tf` files | `module "connection_pooler"`, etc. | `app-*/pgbouncer.tf`, `app-*/main.tf`, `app-*/rds.tf` | T3 — `terraform state mv`, no infra change |

## Risk tiers

- **T1 — destroy+recreate + coordinated cutover (the hard part).** The ECS cluster name (#1/#2), the app-facing CNAME + the app's `DATABASE_URL` (#5), the ECR + the repo CI (#8), and the secrets (#9). Renaming any of these is not an in-place update: the cluster/service is replaced, the CNAME the app dials changes, the ECR the CI pushes to changes. Because the pooler fronts the app's live database connections, this is a **per-stack cutover with a connection blip** unless done expand/contract. This is exactly why the rename was deferred as its own migration.
- **T2 — recreate, low blast radius.** Log group, IAM prefix, SD service name, SG. Replaced but no app-visible contract breaks.
- **T3 — pure terraform refactor.** Module dir, block/resource local names, file names, container name — `git mv` + `terraform state mv`, zero infra change.

## The hard part, spelled out

The app connects to its database through the pooler via a **CNAME the app owns in config**: e.g. `pgbouncer-shared-001.4shark.internal`, wired into the app's `DATABASE_URL` (an SSM parameter, populated out of band). Renaming the CNAME to `connection-pooler-shared-001.4shark.internal` means the app's `DATABASE_URL` must flip to the new name **in lockstep**, or the app cannot reach its database. Combined with the ECS cluster destroy+recreate, a naive rename = downtime.

**Expand/contract is the safe shape, per stack:** stand up the connection-pooler-named resources (cluster, service, CNAME) alongside the pgbouncer-named ones → point the app's `DATABASE_URL` at the new CNAME → validate → retire the old. The `Computation`/app tolerance does not help here (this is a DB connection path, not a Sidekiq chain), so each stack is a small, watched cutover.

## Per-stack specifics (×4, same procedure)

| Stack | `identifier` | CNAME (current → target) | ECR (current → target) |
|---|---|---|---|
| `app-demo-001` | `demo-001` | `pgbouncer-demo-001.4shark.internal` → `connection-pooler-demo-001.4shark.internal` | `demo-001-pgbouncer` → `demo-001-connection-pooler` |
| `app-shared-001` | `shared-001` | `pgbouncer-shared-001.4shark.internal` → `connection-pooler-shared-001…` | `shared-001-pgbouncer` → `shared-001-connection-pooler` |
| `app-beta-001` | `beta-001` | `pgbouncer-beta-001.4shark.internal` → `connection-pooler-beta-001…` | `beta-001-pgbouncer` → `beta-001-connection-pooler` |
| `app-atento-001` | `atento-001` | `pgbouncer-atento-001.4shark.internal` → `connection-pooler-atento-001…` | `atento-001-pgbouncer` → `atento-001-connection-pooler` |

`shared-001` and `atento-001` are the productive high-traffic stacks; `beta-001`/`demo-001` are the lower-risk ones to cut over first.

## Open decisions for the engineer (before a PLAN)

1. **How far to push.** Do we rename the **physical ECS cluster/service and ECR** (T1, destroy+recreate + CI coupling), or only the **soft** layer (module dir, resource local names, container/SD name, tags — already done)? The tag + skill are already role-named; the *physical* rename is where the cost is.
2. **ECR + repo CI.** Renaming the ECR (#8) requires a coordinated change to the `pgbouncer` repo's `build.yaml`/`deploy.yaml` (they push/deploy `<env>-pgbouncer`). In scope, or leave the ECR as-is (the ECR name is the one place technology and role legitimately blur)?
3. **Cutover cadence.** All 4 stacks in one migration, or beta/demo first then shared/atento in a scheduled window?
4. **The module directory rename** (`modules/pgbouncer/` → `modules/connection_pooler/`) is cheap (T3) and can land first, independent of the physical cutover — do it as a standalone hygiene PR?

## Next step

Engineer picks the scope (decisions 1–4). Then a migration PLAN + per-stack TASKS: the expand/contract cutover, ordered beta/demo → shared/atento, each with its `DATABASE_URL` flip and validation. The T3 refactor (module dir + state mv) can be a separate low-risk PR up front.
