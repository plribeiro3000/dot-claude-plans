# TASKS — pgbouncer → connection-pooler rename (zero-downtime)

Derived from `PLAN.md` (this folder). Zero-downtime expand/contract. Cutover order: **beta-001 → demo-001 → shared-001 → atento-001**.

## T0 — New module (shared, once)

- [ ] `git mv`-style **copy** `modules/pgbouncer/` → `modules/connection_pooler/` (keep the old dir alive during expand).
- [ ] In `modules/connection_pooler/main.tf`: `local.name` suffix `-pgbouncer` → `-connection-pooler`; Cloud Map SD service `name` → `connection-pooler`; container `name` → `connection-pooler`. **Leave** `dbname = "pgbouncer"`, `PGBOUNCER_*` (PgBouncer internals).

## T1 — Companion PR in the `pgbouncer` repo (CI)

- [ ] `build.yaml` / `deploy.yaml`: add `<env>-connection-pooler` as build+deploy targets (keep `<env>-pgbouncer` until Contract). Merge only **after** the new ECRs exist (T2.b).

## T2 — Expand (terraform PR #1) — per stack ×4 (one procedure)

For each `app-<env>-001/`:
- [ ] a. Add ECR `<env>-connection-pooler` (`main.tf` `ecr_repositories` gets both old + new).
- [ ] b. Apply just the ECR add → merge the T1 CI PR → CI pushes `<env>-connection-pooler:latest`.
- [ ] c. Add `connection_pooler.tf` with a **new** `module "connection_pooler"` (source `../modules/connection_pooler`) beside the existing `module "pgbouncer_v2"` — new secrets (`app-<env>-connection-pooler-{userlist,stats-password,datadog-api-key}`), `internal_record_name = "connection-pooler-<env>.4shark.internal"`, `image = …/<env>-connection-pooler:latest`, same `databases`/backend/VPC inputs.
- [ ] d. `main.tf`: add `module.connection_pooler.cluster_name` / `.execution_role_arn` to the `cluster_names` / iam PassRole lists (keep the old ones during expand).
- [ ] e. Apply → the new pooler comes up **alongside** the old (same backend Postgres). No app impact.

## T3 — Cutover — per stack ×4, in order

- [ ] a. Populate the new out-of-band secrets (userlist / stats password / datadog key) for `<env>-connection-pooler`.
- [ ] b. Confirm the new pooler is healthy and resolvable at `connection-pooler-<env>.4shark.internal`.
- [ ] c. Flip the app's `DATABASE_URL` SSM parameter → the new CNAME; roll the app.
- [ ] d. Validate: app serves; new pooler connection count climbs; **old pooler drains to zero** (old CNAME still resolves so in-flight drains — no blip).
- [ ] e. **Engineer go** before moving to the next stack.

## T4 — Contract (terraform PR #2) — after all 4 stacks cut over

- [ ] Remove `module "pgbouncer_v2"`, old CNAME, old secrets, old SG per stack.
- [ ] Empty + destroy the old `<env>-pgbouncer` ECRs.
- [ ] `pgbouncer`-repo CI: drop the `<env>-pgbouncer` build/deploy targets.
- [ ] (Optional) rename `module "connection_pooler"` local block if any cosmetic alignment remains.

## Per-stack specifics

| Order | Stack | `identifier` | new CNAME | new ECR |
|---|---|---|---|---|
| 1 | beta-001 | `beta-001` | `connection-pooler-beta-001.4shark.internal` | `beta-001-connection-pooler` |
| 2 | demo-001 | `demo-001` | `connection-pooler-demo-001.4shark.internal` | `demo-001-connection-pooler` |
| 3 | shared-001 | `shared-001` | `connection-pooler-shared-001.4shark.internal` | `shared-001-connection-pooler` |
| 4 | atento-001 | `atento-001` | `connection-pooler-atento-001.4shark.internal` | `atento-001-connection-pooler` |

## Gates

- Apply-before-merge, **per stack**. Read each plan before apply (0 unexpected destroys during expand — the old fleet is untouched).
- Engineer `go` before each productive cutover (T3.e), especially shared-001 / atento-001.
- backend `max_connections` headroom checked before shared/atento cutover (both poolers briefly hold connections).
