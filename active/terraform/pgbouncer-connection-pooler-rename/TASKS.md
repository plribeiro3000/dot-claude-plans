# TASKS — pgbouncer → connection-pooler rename (zero-downtime)

Derived from `PLAN.md` (this folder). Zero-downtime expand/contract. Cutover order: **beta-001 → demo-001 → shared-001 → atento-001**.

Status: **T0–T3 done + legacy poolers scaled to zero. T4 (Contract) in progress.**

## T0 — New module (shared, once) — DONE

- [x] Copy `modules/pgbouncer/` → `modules/connection_pooler/`.
- [x] `local.name` suffix `-pgbouncer` → `-connection-pooler`; Cloud Map SD service `name` → `connection-pooler`; container `name` → `connection-pooler`. Left `dbname = "pgbouncer"`, `PGBOUNCER_*` (PgBouncer internals) untouched.
- [x] Fixed the CNAME to reference the SD service dynamically (`records = ["${aws_service_discovery_service.this.name}.${local.namespace_name}"]`) — the original hardcoded `pgbouncer.<ns>` broke resolution (found by the mandatory connection test).

## T1 — Companion PR in the `pgbouncer` repo (CI) — DONE

- [x] `build.yaml`: each env job pushes to both `<env>-pgbouncer` and `<env>-connection-pooler`. `deploy.yaml`: added a `pooler` input (pgbouncer|connection-pooler). (pgbouncer repo PR #15.)

## T2 — Expand (terraform) — DONE

- [x] All 4 stacks: added ECR `<env>-connection-pooler`, `connection_pooler.tf` with `module "connection_pooler"` beside the legacy pooler, cluster/IAM wiring — **created at `desired_count = 0`** (expand at zero). (terraform PR #611; #612 was a whole-repo `fmt -recursive` split out; #613 the CNAME fix across all 4.)
- [x] atento only: `extra_ingress_cidrs = ["10.12.0.0/26"]` (sa-east-1 payroll reaches the pooler by CIDR cross-region) + cross-region zone association.

## T3 — Cutover — DONE (per stack, in order)

One procedure per stack: copy the 3 out-of-band secrets → scale the pooler `0→2` (terraform PR) → **connection test via `bin/ecs` (`SELECT 1` through the new CNAME, expect `[["1"]]`)** → flip the app's DB URL SSM → redeploy the app (blue/green) → validate new pooler serves, old drains.

| Stack | scale PR | secrets | `DATABASE_URL` | `DATABASE_REPLICA_URL` | app redeploy |
|---|---|---|---|---|---|
| beta-001 | #614 | copied | flipped | — (n/a) | deploy-beta-001 |
| demo-001 | #615 | copied | flipped | — (n/a) | deploy-demo-001 |
| shared-001 | #616 | copied | flipped | **flipped** | 2× (see log) |
| atento-001 | #617 | copied | flipped | **flipped** | 2× (see log) |

Secrets and SSM URL flips were done out of band (no PR), value-to-file, never echoed to chat; each `put` verified by re-read.

## T3 — Execution log / lessons (things not in the original plan)

1. **`DATABASE_REPLICA_URL` — shared and atento only.** Those two stacks have a second DB URL for the read replica (`<env>001_follower`), which also pointed at the legacy pooler. Flipping only `DATABASE_URL` left all follower reads on the old pooler. **Cutover for shared/atento is complete only when BOTH URLs are flipped and the app is redeployed again.** beta/demo have a single `DATABASE_URL`.
2. **shared migration exceeds the CI waiter.** shared's `db:migrate` runs >10 min; the deploy's `aws ecs wait tasks-stopped` gives up (`Max attempts exceeded`) and marks the run failed **before the traffic shift** — even though the migration itself completes in the DB. shared's real cutover landed on the **second** deploy (schema already migrated → fast → passed the waiter → web+sidekiq shifted). Watch for this on any large-DB stack.
3. **Legacy module name differs per stack.** `module.pgbouncer` in beta/demo/atento, but **`module.pgbouncer_v2`** in shared. Always resolve the address from `terraform state list`, never from the file name.
4. **`gh run watch --exit-status` in a `; echo` chain reports the echo's exit code, not the run's.** Read the `conclusion` field (`gh run view --json conclusion`) to judge a deploy, not the wrapped command's exit.

## T3.5 — Scale legacy poolers to zero — DONE

- [x] beta + demo legacy pooler `desired_count 2→0` (terraform PR #618) — verified drained (0 client, 0 query over a window) first.
- [x] shared + atento legacy pooler `desired_count 2→0` (terraform PR #619) — same drain gate; atento held until its post-redeploy follower drain finished, then applied.
- All four legacy pooler services now `0/0`. Still declared in terraform (modules/secrets/CNAME/ECR intact) — removed in T4.

## T4 — Contract (drop all legacy code + infra) — IN PROGRESS

Destructive. Per stack, one terraform PR (or grouped), applied per stack, engineer-gated. The legacy pooler is already at `0/0`, so removal destroys idle resources.

Per `app-<env>-001/`:
- [ ] Remove the legacy module block (`module "pgbouncer"` / **`module "pgbouncer_v2"` for shared**) — destroys its ECS cluster, service, capacity provider, Cloud Map namespace + SD service, and the old CNAME record `pgbouncer-<env>-001.4shark.internal`.
- [ ] Remove the 3 legacy secrets (`<env>-pgbouncer-*` for beta/demo/atento, `app-<env>-pgbouncer-*` — wait, verify per stack: beta/demo/atento legacy = `<env>-pgbouncer-*`; shared legacy = `app-shared-001-pgbouncer-*`) — userlist, stats-password, datadog-api-key + their `_version`.
- [ ] Remove the legacy ECR `<env>-pgbouncer` from `main.tf`/`compute.tf` `ecr_repositories` (empty images first if the repo blocks on non-empty).
- [ ] Drop the legacy cluster/IAM PassRole wiring (`module.pgbouncer[_v2].cluster_name` / `.execution_role_arn`) from the `cluster_names` / `task_execution_role_arns` lists.

Cross-cutting:
- [ ] `pgbouncer` repo CI: drop the `<env>-pgbouncer` build tags from `build.yaml` and the `pgbouncer` option/default from `deploy.yaml` (leave only `connection-pooler`).
- [ ] Confirm no remaining reference to `pgbouncer-<env>-001.4shark.internal` anywhere (app SSM already flipped; grep terraform + app config).

## Gates

- Apply-before-merge, **per stack**. **Read every plan** — T4 is the first phase that DESTROYS; confirm the destroy list is only legacy pooler resources (cluster/service/SD/CNAME/secrets/ECR for the OLD module), never `module.connection_pooler`.
- Engineer `go` before each productive stack (shared-001 / atento-001).
- Order: do beta/demo first (non-prod) to prove the destroy plan shape, then shared/atento.
