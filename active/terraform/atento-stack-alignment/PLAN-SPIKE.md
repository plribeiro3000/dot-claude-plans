# PLAN-SPIKE — Atento Stack Alignment (Parallel Directory Migration)

> **Revision note (2026-07-06):** This draft replaces the prior version, which described the
> ECS migration only and left the question of full stack convergence open. The engineer has
> since locked the complete migration sequence: parallel directory → ownership migration →
> traffic cutover → destroy old compute → reclaim `app-atento-001/` slot → rename Aurora.
> This draft mirrors that end-to-end proven sequence from shared-001.
>
> Reference: shared-001 commit history (`0f8bb6f`, `f118eaa`, `5da46b2`, `32c5cec`);
> `app-shared-001/main.tf`, `app-atento-001/` current state (2026-07-06).
>
> Engineer-locked decisions carried into this draft:
> - **Option C for pooler** — `atento-001/` uses `module "ecs_cluster"` directly (NOT `module "app"`);
>   pooler stays in `app-atento-001/` state throughout the migration window; converges into
>   `module.app` via in-place `moved{}` blocks at reclaim, mirroring `app-shared-001/main.tf:125-133`
> - **Aurora rename is the FINAL step** — `cluster_identifier = "app-atento-001-cluster"` kept
>   immutable until all other steps succeed
> - **New parallel stack authored from `app-shared-001/` as template**

## Objective

Migrate the `app-atento-001` production ECS stack into the canonical `atento-001` naming
convention, replacing the legacy `app-*` prefix on all compute and infrastructure resources.
The migration must be zero-downtime and risk-staged, ending with a single `app-atento-001/`
Terraform directory that owns everything — identical to how `shared-001` ended after its
migration. The parallel directory (`atento-001/`) is a transient artifact that is destroyed
and reclaimed when the migration is complete.

**Current state snapshot (2026-07-06):**

- `app-atento-001-cluster` LIVE (9 ECS services, all `app-atento-001-*` prefix)
- `atento-001-connection-pooler` cluster LIVE (pooler already migrated — done)
- `connection-pooler-atento-001.4shark.internal` CNAME active
- Aurora `app-atento-001-cluster` LIVE (PG 16.13, MultiAZ, DeletionProtection: true)
- No `atento-001/` directory exists yet — parallel build NOT started

## Scope

### In scope

- Phase 0: Phase 1 variable and hardcode cleanup in `app-atento-001/` (pre-condition for
  parallel build — the template cannot be authored until these are parameterized)
- Phase 1: Create `atento-001/` parallel compute directory (from `app-shared-001/` template,
  `module "ecs_cluster"` directly per Option C, all `min_size = 0`, backend key
  `atento-001/terraform.tfstate`)
- Phase 2: Transfer ECR + SSM secrets ownership from `app-atento-001/` to `atento-001/`
  (code redefinition + manual cross-state `terraform state mv`)
- Phase 3: Transfer durable resource ownership (MongoDB, Redis, S3, IAM deploy user,
  OpenSearch reference, RDS) from `app-atento-001/` to `atento-001/`
  (physical git renames + code redefinition + state surgery)
- Phase 4: Prepare new cluster for traffic (whitelist new cluster SG in RDS/Redis/OpenSearch
  ingress rules; scale up `min_size` from 0 to production values)
- Phase 5: Traffic cutover (DNS flip from old `app-atento-001` ALB to new `atento-001` ALB;
  update `dns/alb_data.tf` and app repo deploy workflow)
- Phase 6: Destroy old compute from `app-atento-001/` (ECS cluster, ASGs, capacity providers,
  services, ALB; pooler NOT destroyed — stays in `app-atento-001/` state)
- Phase 7: Reclaim `app-atento-001/` directory slot:
  - 7a: Migrate pooler ownership to `atento-001/` state (code redefinition + state surgery)
  - 7b: Physical file moves + S3 state copy (`atento-001/tfstate` → `app-atento-001/tfstate`)
  - 7c: Introduce `module "app"` + `moved{}` blocks (mirroring `app-shared-001/main.tf:125-133`)
  - 7d: Aurora cluster rename (`app-atento-001-cluster` → `atento-001-cluster`)

### Out of scope (open question)

- SSM parameter value rotation (values kept as-is via `lifecycle { ignore_changes = [value] }`)
- MongoDB Atlas cluster/project name rename (open question — see below)
- Datadog monitor/dashboard updates referencing `app-atento-001` cluster name
- `compute.tf` file split (1,017 lines; hygiene improvement, not migration-blocking)

## Phase 0 — Hardcode Cleanup in `app-atento-001/` (Pre-condition)

**What:** Parameterize all hardcoded `app-atento-001` references in the existing stack so that
`app-shared-001/` can serve as a clean template for the new parallel directory. Without this
cleanup, authoring `atento-001/` requires manual search-and-replace across a hardcoded file.
This work was planned as Phase 1 in the prior PLAN.md but is not yet done.

**Current gap (as of 2026-07-06):**

| Item | Status | File:line |
|---|---|---|
| `local.env = "app-atento-001"` (hardcoded string) | NOT DONE | `compute.tf:26` |
| `lambda_cluster_name = "app-atento-001-cluster"` | NOT DONE | `compute.tf:319` |
| `lambda_tags.Environment = "app-atento-001"` | NOT DONE | `compute.tf:321-323` |
| `policy_name_prefix = "app-atento-001"` | NOT DONE | `compute.tf:843` |
| Scheduler role ARN suffix `"app-atento-001-ecs-scheduler-role"` | NOT DONE | `compute.tf:952` |
| Service capacity_provider map keys `"app-atento-001-*-service"` | NOT DONE | `compute.tf:291-299` |
| `name_prefix = "app-atento-001"` in `module "public_alb"` | NOT DONE | `compute.tf:429` |
| `networking_environment = "app-atento-001"` in `rds.tf` | NOT DONE | `rds.tf:7` |
| `variable "networking_environment"` added to `variables.tf` | NOT DONE | `variables.tf` (absent) |
| `variable "manage_iam"` added | NOT DONE | `variables.tf` (absent); `compute.tf:417` hardcodes `true` |
| `variable "lambda_scheduler_state"` added | NOT DONE | `variables.tf` (absent) |
| `variable "services"` added | NOT DONE | `variables.tf` (absent) |
| `output "alb_dns_name"` added | NOT DONE | `output.tf` (absent) |
| Module rename `networking_data` → `vpc_data` (call-site) | DONE | `connection_pooler.tf:63`, `compute.tf:307,403,404` |
| DNS decoupling in `dns/alb_data.tf` | DONE (name update still needed at cutover) | `dns/alb_data.tf:1-4` uses `data "aws_lb"` |
| Connection pooler | DONE (ahead of plan) | `connection_pooler.tf:58-131`; `identifier = "atento-001"` at line 61 |

**Deliver as:** A single PR touching `app-atento-001/compute.tf`, `variables.tf`, `output.tf`,
`rds.tf`. No AWS resources change — only code/variable parameterization.

---

## Phase 1 — Create `atento-001/` Parallel Directory (Compute-Only)

**What:** Author a new `atento-001/` Terraform directory as a compute-only stack using
`app-shared-001/` as the template. It holds an entirely separate backend state file. All ECS
services start at `min_size = 0` to avoid paying for idle EC2 during the migration window.
Per Option C, this directory does NOT contain `module "app"` — it calls `module "ecs_cluster"`
directly, exactly as `app-atento-001/compute.tf:399-420` does today.

**Key configuration decisions for `atento-001/`:**

| Parameter | Value | Source |
|---|---|---|
| Backend state key | `atento-001/terraform.tfstate` | Mirrors deleted `shared-001/providers.tf` key — Pattern 1 below |
| Module call | `module "ecs_cluster"` directly | Option C (locked) |
| `identifier` / `local.env` | `"atento-001"` | Resources created as `atento-001-*` |
| All service `min_size` | `0` | Shared-001 precedent — Pattern 2 below |
| `extra_ingress_cidrs` | `["10.12.0.0/26"]` | `app-atento-001/connection_pooler.tf:76` — cross-region outbound VPC CIDR |
| Durables | `data` sources only (NOT `resource`) | Ownership stays in `app-atento-001/` until Phase 3 |
| Pooler | NOT CREATED | Option C — no second pooler; old pooler stays in `app-atento-001/` state |

**ECS services to include (all 9 currently in `app-atento-001-cluster`):**

- `web`, `worker-system`, `worker-user`, `worker-commission`
- `worker-commission-tiger-shark`, `worker-commission-white-shark`
- `worker-cleansing`, `worker-migration`, `runner`

**Source patterns:**

**Pattern 1: Parallel directory backend state key** — `git show 32c5cec -- shared-001/providers.tf`

The deleted `shared-001/providers.tf` had its own S3 state key:

```hcl
backend "s3" {
  bucket = "4shark-terraform-state"
  key    = "shared-001/terraform.tfstate"
  region = "us-east-1"
}
```

The end-state `app-shared-001/providers.tf:28-31` after reclaim:
`key = "app-shared-001/terraform.tfstate"` — confirming the parallel dir always uses
its own key; the slot key is reserved for the final reclaimed state.

**Pattern 2: `min_size = 0` during parallel window** — `git show 32c5cec -- app-shared-001/terraform.tfvars`

The reclaim commit removed this comment, meaning it was present during the parallel window:

```
# all min=0 during parallel migration to avoid paying for idle EC2 instances.
# Scaled up per service during cutover.
web_min_size = 0
```

All workers also at `0`. Restored to production values at Phase 4 (before traffic cutover).

**New cluster SG warning** (from deleted `shared-001/main.tf` comment, removed in `32c5cec`):

```
# New ECS SG is created by module.ecs_cluster (via sgname local).
# RDS/Redis/OS ingress rules in app-shared-001 must be updated to accept the new SG
# before the first task can connect. Handled as a separate preparation step.
```

This is why Phase 4 exists as an explicit named step before traffic cutover.

**Deliver as:** A single PR creating the `atento-001/` directory. No apply yet — plan review
only. The plan must show ONLY ECS cluster resources being created; zero changes to durables.

---

## Phase 2 — Transfer ECR + SSM Secrets Ownership

**What:** Move ownership of ECR repositories and SSM parameters from `app-atento-001/` state
to `atento-001/` state via code-only redefinition + manual cross-state `terraform state mv`.
The manual state surgery happens between commit and apply and is NOT recorded in git.

**Proven pattern:** `git show 0f8bb6f` — ECR + SSM transfer for shared-001.

**ECR transfer (`0f8bb6f` pattern):**

`app-atento-001/main.tf` — remove the `module "ecr"` block (ownership dropped); add a
`data "aws_ecr_repository"` reference if the ARN is still needed:

```hcl
# REMOVE from app-atento-001/main.tf:
module "ecr" {
  source       = "../modules/ecr"
  repositories = local.ecr_repositories
  tags         = local.tags
}
```

`atento-001/main.tf` — change from `data "aws_ecr_repository"` to `module "ecr"` (ownership assumed):

```hcl
# ADD to atento-001/main.tf — resource replaces data source:
module "ecr" {
  source       = "../modules/ecr"
  repositories = local.ecr_repositories
  tags         = local.tags
}
```

**SSM transfer (`0f8bb6f` pattern):**

`app-atento-001/ssm.tf` — change `resource` → `data` for each SSM parameter; remove the
ECS SSM read IAM policy (it moves to `atento-001/ssm.tf`):

```hcl
# AFTER in app-atento-001/ssm.tf:
data "aws_ssm_parameter" "some_param" {
  name = "/atento-001/..."
}
# IAM policy removed from this file
```

`atento-001/ssm.tf` (new file) — `resource` blocks with `lifecycle { ignore_changes = [value] }`:

```hcl
resource "aws_ssm_parameter" "some_param" {
  name  = "/atento-001/..."
  type  = "SecureString"
  value = "placeholder"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_iam_role_policy" "ecs_ssm_read" { ... }
```

**Apply sequence:**
1. Git commit the code changes (NO apply yet)
2. Manual state surgery (NOT in git): enumerate every resource address from
   `terraform state list` output for the ECR and SSM resources; run
   `terraform state mv -state-out=../atento-001/terraform.tfstate 'module.ecr.xxx' 'module.ecr.xxx'`
   for each ECR resource; same for each SSM parameter
3. `terraform apply` in `app-atento-001/` — plan MUST show zero changes
4. `terraform apply` in `atento-001/` — plan MUST show zero changes

Any non-zero plan in steps 3 or 4 means the state surgery missed a resource. Do NOT continue
until both plans are clean.

---

## Phase 3 — Transfer Durable Resource Ownership

**What:** Move ownership of MongoDB Atlas config, Redis, S3, OpenSearch reference, IAM deploy
user, and RDS from `app-atento-001/` to `atento-001/` via physical git file renames plus
code redefinition + manual state surgery. RDS `cluster_identifier` stays as
`"app-atento-001-cluster"` — NOT renamed at this phase.

**Proven pattern:** `git show f118eaa` — durable resources transfer for shared-001.

**File renames (`git mv`):**

```
app-atento-001/mongodb.tf   →  atento-001/mongodb.tf
app-atento-001/redis.tf     →  atento-001/redis.tf
app-atento-001/rds.tf       →  atento-001/rds.tf
app-atento-001/s3.tf        →  atento-001/s3.tf
app-atento-001/opensearch.tf →  atento-001/opensearch.tf
```

The `rds.tf` file moves to `atento-001/` but `cluster_identifier` stays unchanged:

```hcl
# In atento-001/rds.tf after the move — cluster_identifier NOT changed:
resource "aws_rds_cluster" "this" {
  cluster_identifier = "app-atento-001-cluster"   # unchanged — rename is Phase 7d
  ...
}
```

Source: `git show f118eaa -- shared-001/rds.tf` showed `cluster_identifier = "app-shared-001-cluster"`
kept intact during the equivalent durable-transfer phase of the shared-001 migration.

**IAM deploy user (`f118eaa` pattern):**

`app-atento-001/main.tf` — remove `resource "aws_iam_user" "deploy"` and policy blocks;
add `data "aws_iam_user" "deploy"` reference.

`atento-001/main.tf` — add `resource "aws_iam_user" "deploy"` + policy attachment (ownership assumed).

**OpenSearch callout:** The OpenSearch domain `app-atento-001` has an IMMUTABLE name in AWS.
The `opensearch.tf` file moves from `app-atento-001/` to `atento-001/` (state ownership
transfers), but the resource block's `domain_name = "app-atento-001"` cannot be changed.
Only the state entry address changes stacks; the physical AWS resource name stays `app-atento-001`.

**Apply sequence:** Code commit first, manual state surgery second, verify both plans show
zero changes before continuing.

---

## Phase 4 — Prepare New Cluster for Traffic

**What:** Whitelist the new `atento-001/` cluster security group in RDS, Redis, and OpenSearch
ingress rules. Scale ECS services from `min_size = 0` to production values. Validate that
tasks in the new cluster can reach all data stores.

**Steps:**
1. Get the new cluster SG ID from `atento-001/` outputs (`module.ecs_cluster.security_group_id`)
   — this is distinct from the current old cluster SG (`sg-02b23ed9dd3626fb7` in
   `app-atento-001/`)
2. Add the new SG to ingress rules in `atento-001/rds.tf`, `atento-001/redis.tf`,
   `atento-001/opensearch.tf`. Apply `atento-001/`
3. Scale up: set `web_min_size` and worker `min_size` to production values in
   `atento-001/terraform.tfvars`. Apply `atento-001/`
4. Validate: confirm tasks start and connect. App ECS tasks in `atento-001/` connect via
   the pooler still owned by `app-atento-001/` — the CNAME
   `connection-pooler-atento-001.4shark.internal` (`connection_pooler.tf:104`) must resolve
   from the new cluster's VPC (see Open Questions below)

**Source pattern:** The deleted `shared-001/main.tf` comment explicitly called this out as
"a separate preparation step" — it is not implied by the parallel build apply.

---

## Phase 5 — Traffic Cutover

**What:** DNS flip from the old `app-atento-001` ALB to the new `atento-001` ALB. After this
phase, production traffic runs entirely on the new cluster. The old `app-atento-001` ECS
cluster still exists but receives no traffic.

**Steps:**
1. Update `dns/alb_data.tf:4`: change `name = "app-atento-001-lb"` to the new ALB name
   (the new ALB is created by `atento-001/` and its name comes from `module "public_alb"`
   with `name_prefix = "atento-001"`)
2. Update the app repo deploy workflow (`.github/workflows/deploy-atento.yml` or equivalent):
   change ECS cluster reference from `app-atento-001-cluster` to `atento-001-cluster`
3. Update Route53 record to point at the `atento-001` ALB DNS name
4. Monitor error rates, 5xx responses, latency — rollback path is a Route53 revert (no state
   changes needed, fast)

**Source:** `dns/alb_data.tf:1-4` uses `data "aws_lb" "atento_001"` — DNS decoupling is
already done; only the hardcoded `name = "app-atento-001-lb"` needs updating here.

---

## Phase 6 — Destroy Old Compute from `app-atento-001/`

**What:** Remove the ECS cluster, ASGs, capacity providers, task definitions, services, and
ALB from `app-atento-001/`. The pooler (`module.connection_pooler`) is explicitly NOT
destroyed — it stays in `app-atento-001/` state and continues serving.

**Proven pattern:** `git show 5da46b2 --stat` and `git show 5da46b2 -- app-shared-001/main.tf`

Commit `5da46b2` deleted these files from `app-shared-001/` (equivalent action for `app-atento-001/`):

```
compute.tf   (1023 deletions)
output.tf    (14 deletions)
ssm.tf       (32 deletions)
vpc_data.tf  (4 deletions)
```

And stripped `app-shared-001/main.tf` to a minimal locals block. After the equivalent for
atento, `app-atento-001/main.tf` retains only:

```hcl
locals {
  environment = var.environment

  tags = {
    Environment = "atento-001"
    Automation  = "terraform"
  }
}
```

**What remains in `app-atento-001/` state after Phase 6:**
- `module.connection_pooler` and all its associated resources (Secrets Manager secrets,
  the pooler ECS service in the separate `atento-001-connection-pooler` cluster)
- `providers.tf`, `variables.tf`, `terraform.tfvars` (stack config files)
- Durables are now in `atento-001/` state (migrated at Phases 2–3), so they are NOT here

**`terraform apply` in `app-atento-001/`** → destroys old ECS cluster. Verify the plan shows
ONLY compute resources being destroyed, NOT the pooler. If the pooler appears in the destroy
plan, STOP — Phase 6 is incorrect; investigate.

---

## Phase 7 — Reclaim `app-atento-001/` Slot + `module.app` Convergence + Aurora Rename

**What:** The culminating phase. All resources converge into a single `app-atento-001/` state
file under the canonical `module.app` structure, the `atento-001/` directory is destroyed,
and the Aurora cluster is renamed.

**Option C specifics at this phase:**
- `atento-001/` state contains: ECS cluster (`module.ecs_cluster`), ECR, SSM, IAM, MongoDB,
  Redis, S3, OpenSearch, RDS
- `app-atento-001/` state contains: `module.connection_pooler` only
- The `moved{}` blocks in Phase 7c require BOTH `module.ecs_cluster` and
  `module.connection_pooler` to be in the SAME state file → Phase 7a migrates the pooler first

---

### Phase 7a — Migrate Pooler Ownership to `atento-001/` State

**What:** Transfer `module.connection_pooler` from `app-atento-001/` state to `atento-001/`
state via the same code-redefinition + manual state surgery pattern as Phases 2–3.

After this sub-step, `atento-001/terraform.tfstate` is the single source of truth for ALL
resources. `app-atento-001/` state is empty (or contains only provider-level metadata).

**Steps:**
1. `git mv app-atento-001/connection_pooler.tf atento-001/connection_pooler.tf` — physical
   file move; the block remains `resource "module" "connection_pooler"` (no redefinition
   needed; `atento-001/` is assuming ownership of resources that were previously in
   `app-atento-001/` state)
2. Remove pooler blocks from `app-atento-001/` (the file is now gone; remove any remaining
   pooler references in `app-atento-001/main.tf` if any exist)
3. Manual state surgery: for each resource under `module.connection_pooler.*` in
   `app-atento-001/` state, run:
   `terraform state mv -state-out=../atento-001/terraform.tfstate 'module.connection_pooler.X' 'module.connection_pooler.X'`
4. Verify: `terraform apply` in `app-atento-001/` → zero changes (state empty or only locals);
   `terraform apply` in `atento-001/` → zero changes (pooler already in state, no delta)

The pooler resources to migrate include:
- `aws_secretsmanager_secret.connection_pooler_userlist` (`connection_pooler.tf:7`)
- `aws_secretsmanager_secret.connection_pooler_datadog_stats_password` (`connection_pooler.tf:24`)
- `aws_secretsmanager_secret.connection_pooler_datadog_api_key` (`connection_pooler.tf:41`)
- `module.connection_pooler.*` (all resources under the module; enumerate from `terraform state list`)
- `aws_route53_zone_association.connection_pooler_outbound_cloud_map` (`connection_pooler.tf:119`)
- `aws_route53_zone_association.internal` (`connection_pooler.tf:128`)

---

### Phase 7b — Physical File Moves + S3 State Copy

**What:** Move all Terraform source files from `atento-001/` into `app-atento-001/` via git
renames. Delete all root-level files from `atento-001/`. Copy the S3 state object so that
`app-atento-001/terraform.tfstate` holds the complete merged state.

**Proven pattern:** `git show 32c5cec --stat` — the file-move pattern for shared-001:

```
{shared-001 => app-shared-001}/compute.tf
{shared-001 => app-shared-001}/mongodb.tf
{shared-001 => app-shared-001}/opensearch.tf
{shared-001 => app-shared-001}/rds.tf
{shared-001 => app-shared-001}/redis.tf
{shared-001 => app-shared-001}/s3.tf
{shared-001 => app-shared-001}/ssm.tf
{shared-001 => app-shared-001}/output.tf
shared-001/main.tf                  (deleted)
shared-001/providers.tf             (deleted)
shared-001/terraform.tfvars         (deleted)
shared-001/variables.tf             (deleted)
shared-001/.terraform.lock.hcl     (deleted)
```

Equivalent for atento: `{atento-001 => app-atento-001}/compute.tf`, etc. All root-level
Terraform files in `atento-001/` are deleted (directory vacated).

**S3 state copy (manual, NOT in git):**

```
COPY:  4shark-terraform-state/atento-001/terraform.tfstate
    →  4shark-terraform-state/app-atento-001/terraform.tfstate
```

Direction confirmed:
- `shared-001/providers.tf` (deleted in `32c5cec`): `key = "shared-001/terraform.tfstate"` (source)
- `app-shared-001/providers.tf:30` (current): `key = "app-shared-001/terraform.tfstate"` (dest)

Update `app-atento-001/providers.tf` backend key after the copy; confirm the existing value
is `"app-atento-001/terraform.tfstate"` before the copy so there is no ambiguity.

---

### Phase 7c — Introduce `module "app"` + `moved{}` Blocks

**What:** Replace standalone `module "ecs_cluster"` + `module "connection_pooler"` in the
new `app-atento-001/main.tf` with a single `module "app"` call (which bundles both). Add
`moved{}` blocks to update state addresses in-place without recreating any resource.

**Source pattern — `app-shared-001/main.tf:125-133`:**

```hcl
moved {
  from = module.ecs_cluster
  to   = module.app.module.ecs_cluster
}

moved {
  from = module.connection_pooler
  to   = module.app.module.connection_pooler
}
```

These are INTRA-STATE moves only. After Phase 7a, both `module.ecs_cluster` (from
`atento-001/`, now in `app-atento-001/` state) and `module.connection_pooler` (also migrated
at 7a into the same state) reside in `app-atento-001/terraform.tfstate`. The `moved{}` blocks
translate the old state addresses to the new `module.app.*` addresses.

`terraform apply` at this step MUST show a zero-change plan (only address renames in state;
no resource creation or destruction). If the plan shows any resource changes, STOP and diagnose
before applying.

**`module "app"` configuration reference:** `app-shared-001/main.tf:67-123` — the full
`module "app"` call shows the required parameters: `identifier`, `environment`, `vpc_id`,
`subnet_ids`, `tags`, cluster parameters, connection pooler `databases` list, CNAME, image.

For atento, `identifier = "atento-001"` and the pooler databases list comes from
`app-atento-001/connection_pooler.tf:79-96` (writer: `atento001_master`, reader:
`atento001_follower`).

---

### Phase 7d — Aurora Cluster Rename (Absolute Final Step)

**What:** Rename the Aurora cluster from `app-atento-001-cluster` to `atento-001-cluster`.
This is the only step where `aws_rds_cluster.cluster_identifier` changes. All previous phases
kept it as `"app-atento-001-cluster"`.

**Current state:** `app-atento-001/rds.tf:58` — `cluster_identifier = "app-atento-001-cluster"`

**Rename command (NOT in git; executed between commit and apply):**

```
aws rds modify-db-cluster --db-cluster-identifier app-atento-001-cluster --new-db-cluster-identifier atento-001-cluster
```

This is a live-cluster rename: no downtime expected (~5 min for the rename to complete),
but the pooler's backend endpoint URL changes. The pooler must be restarted after the rename
so it picks up the new RDS endpoint DNS.

**Steps:**
1. Run the AWS CLI rename (schedule during off-hours)
2. Update `app-atento-001/rds.tf`: change `cluster_identifier = "atento-001-cluster"`
3. Restart the pooler ECS service so it re-resolves the Aurora endpoint
4. `terraform plan` must show zero changes (cluster already has the new name; Terraform reads
   current state and finds alignment)
5. If Terraform shows a diff on `cluster_identifier`, run `terraform state show` on the RDS
   resource to verify the stored ID matches the new name; re-import if needed

**RDS endpoint preservation:** `aws rds modify-db-cluster` preserves the cluster endpoint
DNS when renaming (`app-atento-001-cluster.cluster-cvw5l7p4adp1.us-east-1.rds.amazonaws.com`
→ renamed; verify the CNAME updates in Route53 before restarting the pooler).

---

## Technical Decisions to Be Made

| Decision | Options | Trade-off summary | Engineer to choose |
|---|---|---|---|
| Pooler option | Option C (LOCKED) | `atento-001/` uses `module "ecs_cluster"` directly; pooler stays in `app-atento-001/` through cutover; converges via `moved{}` at Phase 7 | locked |
| Aurora rename timing | Final Phase 7d (LOCKED) | Immutable identifier until all state surgery succeeds; rename causes ~5 min of endpoint DNS change + pooler restart required | locked |
| New stack template | `app-shared-001/` (LOCKED) | Services-map-driven, proven pattern | locked |
| Phase 7a placement | Sub-step of Phase 7 vs explicit Phase 6b (after destroy, before reclaim) | Making it a standalone Phase 6b gives a named pause point after destroy; keeping it 7a groups all reclaim work together — operational preference only | □ |
| MongoDB Atlas cluster name | Rename in Phase 7d alongside Aurora, OR keep as-is permanently | Unknown if MongoDB Atlas cluster name is as immutable as OpenSearch domain name — needs investigation before Phase 3 file rename | □ |
| Datadog monitor updates | Phase 4 (before cutover, old cluster still running) vs Phase 7 (after reclaim) | Monitors referencing `app-atento-001-*` service names will silently miss metrics after Phase 6 (destroy compute) if not updated first | □ |
| SG bridging during Phase 4 | Remove old cluster SG from RDS/Redis/OS ingress after Phase 6 vs leave permanently | Old cluster SG (`sg-02b23ed9dd3626fb7`) no longer exists after Phase 6; leaving the rule is harmless but noisy; removing it is clean but requires a post-destroy apply | □ |

## Risks (Cross-Cutting)

| Risk | Impact | Possible mitigation |
|---|---|---|
| New cluster SG not whitelisted before cutover | ECS tasks cannot reach RDS/Redis/OpenSearch → database connectivity failure | Phase 4 is a mandatory explicit preparation step; validate task health before Phase 5 DNS flip |
| State surgery misses a resource (Phases 2, 3, or 7a) | `terraform apply` shows resource recreation or destroy in the wrong stack | `terraform state list` before and after each `state mv`; both plans MUST show zero changes before continuing |
| `moved{}` blocks applied before pooler is in same state file | Terraform cannot find `module.connection_pooler` address → apply error | Phase 7a (pooler state migration) must complete with zero-change applies in BOTH stacks before Phase 7b |
| S3 state copy in wrong direction | `app-atento-001/terraform.tfstate` overwritten with empty state → all resources become unmanaged | Always copy `atento-001/` → `app-atento-001/`; back up both state files before the copy |
| Aurora rename causes RDS endpoint DNS change; pooler not restarted | Pooler cannot connect to RDS after rename → app DB errors | Restart pooler ECS service explicitly after rename; schedule Phase 7d during off-hours |
| OpenSearch domain `app-atento-001` confused with mutable name | Engineers attempt to rename → AWS rejects → plan halts | Document explicitly: OpenSearch domain name is IMMUTABLE; only state ownership transfers, not the physical name |
| `dns/alb_data.tf` ALB name not updated at cutover | DNS stack breaks when old ALB is destroyed | Include `dns/alb_data.tf:4` update in the Phase 5 cutover PR, BEFORE the old ALB destroy in Phase 6 |
| Pooler CNAME conflict during Phase 1 parallel window | If `module "app"` were accidentally used in `atento-001/`, Route53 CNAME collision | Option C is locked — `atento-001/` calls `module "ecs_cluster"` only, never `module "app"` |

## Open Questions for the Engineer

1. **Phase 7a placement:** Should migrating the pooler state (`module.connection_pooler` from
   `app-atento-001/` → `atento-001/`) be a standalone Phase 6b (after destroy, before
   reclaim) or kept as sub-step 7a within the reclaim phase? Either ordering is correct;
   this is a runbook preference only.

2. **MongoDB Atlas cluster name:** Is the MongoDB Atlas cluster/project name `app-atento-001`
   immutable like the OpenSearch domain name? The `mongodb.tf` file moves to `atento-001/`
   at Phase 3 (state ownership transfer), but the cluster name itself may or may not be
   renameable. If renameable, add it to Phase 7d alongside Aurora. If not, document it as
   permanently named `app-atento-001` (same situation as OpenSearch).

3. **Datadog monitors:** Do existing Datadog monitors reference the `app-atento-001-*` ECS
   service names or cluster name? These break silently after Phase 6 (destroy compute) if
   not updated. When should monitor updates run — Phase 4 (before cutover, old cluster still
   running) or Phase 7 (after reclaim)?

4. **Pooler CNAME DNS resolution from new VPC:** The new `atento-001/` ECS tasks (Phases
   4–6) connect via the pooler still owned by `app-atento-001/`. Does the pooler's
   `internal_record_name = "connection-pooler-atento-001.4shark.internal"` resolve correctly
   from the new cluster's VPC? The `aws_route53_zone_association.internal` at
   `connection_pooler.tf:128` currently associates the OLD VPC with the internal zone.
   A second zone association for the NEW VPC may be needed before Phase 4 validation succeeds.

5. **`github_deploy.tf`:** `app-atento-001/` includes a `github_deploy.tf`. Does this file
   move to `atento-001/` at Phase 3 (durable ownership) or stay until Phase 7 (reclaim)?
   Its content (GitHub Actions deploy key/secret) determines whether it is compute-adjacent
   or infrastructure-adjacent.

6. **Phase 0 scope:** Should Phase 0 hardcode cleanup be a separate PR merged to develop
   first, then the parallel build starts in a second PR? Or should Phase 0 and Phase 1 be
   combined into a single PR for `atento-001/` creation?

## Sources

- `app-shared-001/main.tf:67-123` — `module "app"` call (identifier, environment, vpc_id,
  subnet_ids, tags, cluster config, pooler databases list, CNAME, image)
- `app-shared-001/main.tf:125-133` — canonical intra-state `moved{}` blocks:
  `from = module.ecs_cluster / to = module.app.module.ecs_cluster` and
  `from = module.connection_pooler / to = module.app.module.connection_pooler`
- `app-shared-001/providers.tf:28-31` — end-state backend key after reclaim:
  `key = "app-shared-001/terraform.tfstate"`
- `git show 32c5cec -- shared-001/providers.tf` — deleted parallel dir backend key:
  `key = "shared-001/terraform.tfstate"` (the parallel directory always used its own S3 object)
- `git show 0f8bb6f` — ECR/SSM ownership transfer: `module "ecr"` removed from
  `app-shared-001/main.tf`; `resource "aws_ssm_parameter"` → `data "aws_ssm_parameter"` in
  `app-shared-001/ssm.tf`; new `shared-001/ssm.tf` with `lifecycle { ignore_changes = [value] }`;
  cross-state state surgery performed manually between commit and apply (not recorded in git)
- `git show f118eaa` — durable resources: physical git renames
  `{app-shared-001 => shared-001}/mongodb.tf,rds.tf,redis.tf,s3.tf`; IAM user changed
  resource → data in source stack; `cluster_identifier = "app-shared-001-cluster"` kept
  intact (not renamed during migration)
- `git show 5da46b2 --stat` and `git show 5da46b2 -- app-shared-001/main.tf` — destroy
  compute: deleted `compute.tf` (1023 lines), `output.tf`, `ssm.tf`, `vpc_data.tf`; stripped
  `main.tf` to minimal `locals { environment, tags }` block; pooler NOT deleted (pooler was
  separately owned, not in the destroyed files)
- `git show 32c5cec` — reclaim: physical file moves from `shared-001/` → `app-shared-001/`;
  new consolidated `main.tf` with `module.app`; `terraform.tfvars` restored `web_min_size = 1`
  (comment: "all min=0 during parallel migration to avoid paying for idle EC2 instances.
  Scaled up per service during cutover."); deleted all `shared-001/` root-level Terraform files
- `app-atento-001/connection_pooler.tf:61` — `identifier = "atento-001"` (pooler already
  migrated to correct naming; DONE)
- `app-atento-001/connection_pooler.tf:65` — `app_security_group_id = module.ecs_cluster.security_group_id` — SG coupling: new cluster SG must replace old cluster SG at Phase 7c apply (via `module.app`)
- `app-atento-001/connection_pooler.tf:76` — `extra_ingress_cidrs = ["10.12.0.0/26"]`
  (sa-east-1 cross-region outbound VPC CIDR; must be carried into `atento-001/` cluster config)
- `app-atento-001/connection_pooler.tf:104` — `internal_record_name = "connection-pooler-atento-001.4shark.internal"` (live CNAME; DNS conflict source for any second pooler — reason Option C uses no pooler in `atento-001/`)
- `app-atento-001/connection_pooler.tf:119,128` — zone associations to migrate at Phase 7a
  (cross-region `vpc-0985020bde92bca75` + VPC-internal zone)
- `app-atento-001/rds.tf:58` — `cluster_identifier = "app-atento-001-cluster"` (immutable
  until Phase 7d; confirmed LIVE in AWS per `/tmp/rds_clusters.json`)
- `app-atento-001/compute.tf:26` — `local.env = "app-atento-001"` (Phase 0 NOT DONE)
- `app-atento-001/compute.tf:291-299` — capacity_provider map keys hardcoded
  `"app-atento-001-*-service"` (Phase 0 NOT DONE)
- `dns/alb_data.tf:1-4` — `data "aws_lb" "atento_001"` with `name = "app-atento-001-lb"`
  (DNS decoupling done; ALB name update required in Phase 5 cutover PR)
- `/tmp/ecs_clusters_us_east_1.json` (queried 2026-07-06) — `app-atento-001-cluster` LIVE;
  `atento-001-connection-pooler` LIVE; no `atento-001-cluster` exists
- `/tmp/rds_clusters.json` (queried 2026-07-06) — `app-atento-001-cluster` LIVE, Aurora
  PG 16.13, MultiAZ, DeletionProtection: true; endpoint:
  `app-atento-001-cluster.cluster-cvw5l7p4adp1.us-east-1.rds.amazonaws.com`
