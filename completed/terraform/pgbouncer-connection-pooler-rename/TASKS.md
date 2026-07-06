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

## T4 — Contract (drop all legacy code + infra) — DONE

Destructive, one terraform PR per stack, applied per stack, engineer-gated. Order beta → demo → shared → atento (non-prod first to prove the destroy shape).

| Stack | PR | legacy module | destroy count |
|---|---|---|---|
| beta-001 | #620 | `module.pgbouncer` | 28 |
| demo-001 | #621 | `module.pgbouncer` | 28 |
| shared-001 | #622 | `module.pgbouncer_v2` | 29 |
| atento-001 | #623 | `module.pgbouncer` (+ legacy cross-region zone assoc) | 29 |

Per stack each PR: moved `aws_route53_zone_association.internal` into `connection_pooler.tf` (same address → no-op, keeps the new CNAME resolving), deleted `pgbouncer.tf` (secrets + module), dropped the legacy ECR + cluster/IAM wiring. Every plan reviewed: destroys were ONLY the legacy module + secrets + ECR (+ atento's legacy `outbound_cloud_map`), zero `module.connection_pooler`. All apps verified healthy after each apply.

- [x] `pgbouncer` repo CI (PR #16): build pushes only `<env>-connection-pooler`; deploy drops the now-single-valued `pooler` input and targets `<env>-connection-pooler` directly. **Urgent because** the legacy ECRs were destroyed — the next build would have failed pushing to them.

### T4 execution notes (not in the original plan)

1. **Legacy ECR must be emptied before the destroy.** `module.ecr` has no `force_delete`; a non-empty repo blocks the destroy. Emptied each `<env>-pgbouncer` repo with `aws ecr batch-delete-image` (two rounds — tag + digest entries) before applying.
2. **Contract apply is a FULL apply (not `-target`), so it initializes the `rediscloud` + `mongodbatlas` providers** whose keys come from the stack `.envrc` via `op`. A transient `op` timeout leaves those keys empty and the apply errors at the end (`Missing Redis Cloud API Key`) — but the AWS destroys already completed (state written incrementally). Fix: re-run `plan`/`apply` (op responds → clean). The earlier `-target` applies never hit this because they skip those providers.
3. **`aws_route53_zone_association.internal` is shared by both poolers** — it must be MOVED (same address) into `connection_pooler.tf`, never deleted with `pgbouncer.tf`, or the new CNAME stops resolving.

## T5 — Residual follow-up (tiny)

- [ ] Stale comments in the 4 `connection_pooler.tf` ("the old `pgbouncer-<env>-001.4shark.internal` keeps resolving until the contract phase") — now false; drop them (Kaizen, comment-only).

## Gates (all satisfied)

- Apply-before-merge, per stack; every destroy plan reviewed; productive stacks (shared/atento) engineer-gated; non-prod first.
