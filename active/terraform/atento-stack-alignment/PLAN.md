# PLAN — Atento Stack Alignment with beta/demo/shared pattern

## Current Situation

- **Stack location:** `terraform/app-atento-001/`
- **Current pattern:** Diverges from beta/demo/shared in multiple dimensions; uses `local.env = "app-atento-001"` internally for all resource naming
- **Why it diverges:** Atento was the first ECS Fargate migration (commit `cfb770a feat(integrator-atento): migrate EC2 to ECS Fargate with multi-cluster architecture`), predating the shared-001 parallel migration that established the cleaner naming pattern
- **Production status:** Atento is a paid multi-tenant production environment — high stakes for any operational change

### Inventory in AWS (validated 2026-04-27)

**us-east-1 (main cluster):**
- ECS cluster: `app-atento-001-cluster`
- Aurora cluster identifier: `app-atento-001-cluster`
- OpenSearch domain: `app-atento-001` (immutable name)
- 6 Lambdas: `Lambda-app-atento-001-*`
- All ECS services + task definitions: `app-atento-001-*`
- IAM scheduler role: `app-atento-001-ecs-scheduler-role`
- ALB: `app-atento-001-lb`
- ECR repo: `atento-001-app` ✓ already in new pattern
- S3 bucket: `4shark-atento-001` ✓ already in new pattern

**sa-east-1 (outbound):**
- ECS cluster: `app-outbound-atento-br-cluster` ✓ uses `app-outbound-{client}` naming convention (out of scope)

### Code-level divergences

| Aspect | Atento (current) | Standard (beta/demo/shared) |
|---|---|---|
| File structure | Monolithic `compute.tf` (953 lines) | Split: `main.tf` + `compute.tf` + `locals.tf` + `lambda.tf` + `scheduled-tasks.tf` |
| `local.env` | Hardcoded `"app-atento-001"` | Uses `var.environment` (e.g., `"shared-001"`) |
| Module name for VPC data | `module "networking_data"` | `module "vpc_data"` |
| `policy_name_prefix` | `"app-atento-001"` | `var.environment` |
| `output "alb_dns_name"` | Missing | Present (only shared-001 has it) |
| DNS lookup of ALB | `data "aws_lb"` by name | `terraform_remote_state` (only shared-001 has it) |

## Full Resource Naming Inventory (validated 2026-04-27)

This section maps every resource type across the 4 app stacks to identify what's in pattern vs out of pattern. Goal: have a single reference of what naming exists today before deciding what to align.

### Group A — ALWAYS use `app-` prefix (consistent across all 4 stacks)

These can't easily be changed (immutable names, GHA dependencies, or VPC owner separation):

| Resource | Atento | Beta | Demo | Shared |
|---|---|---|---|---|
| IAM user (deploy) | `app-atento-001` | `app-beta-001` | `app-demo-001` | `app-shared-001` |
| VPC SSM params | `/networking/app-atento-001/*` | `/networking/app-beta-001/*` | `/networking/app-demo-001/*` | `/networking/app-shared-001/*` |
| RDS Aurora cluster identifier | `app-atento-001-cluster` | `app-beta-001` (single instance, not Aurora) | `app-demo-001-cluster` | `app-shared-001-cluster` |
| RDS instance identifier | `app-atento-001-db-1`, `app-atento-001-db-2` | `app-beta-001` | `app-demo-001-db-1` | `app-shared-001-db-1`, `app-shared-001-db-2` |
| DB subnet group | `app-atento-001-db-subnet-group` | `app-beta-001-db-subnet-group` | `app-demo-001-db-subnet-group` | `app-shared-001-db-subnet-group` |
| OpenSearch domain | `app-atento-001` | (n/a) | (n/a) | `app-shared-001` |
| RDS log groups | `/aws/rds/cluster/app-atento-001-cluster/postgresql` | `/aws/rds/instance/app-beta-001/*` | `/aws/rds/cluster/app-demo-001-cluster/postgresql` | `/aws/rds/cluster/app-shared-001-cluster/postgresql` |
| Security group (data tier) | `app-atento-001-rds-*`, `app-atento-001-opensearch-*` | `app-beta-001-rds-*`, `app-beta-001-pgbouncer-sg` | `app-demo-001-rds-*` | `app-shared-001-rds-*`, `app-shared-001-pgbouncer-*`, `app-shared-001-opensearch-*` |

**Decision: keep as-is.** These represent the "data/identity layer" with `app-` prefix. Renaming is either impossible (OpenSearch immutable) or breaks integrations (IAM user → GHA secrets).

### Group B — NEVER use `app-` prefix (consistent across all 4 stacks)

These are correctly aligned without `app-` prefix:

| Resource | Atento | Beta | Demo | Shared |
|---|---|---|---|---|
| ECR repository | `atento-001-app` | `beta-001-app` | `demo-001-app` | `shared-001-app` |
| S3 bucket | `4shark-atento-001` | `4shark-beta-001` | `4shark-demo-001` | `4shark-shared-001` |
| App SSM secrets | `/atento-001/*` | `/beta-001/*` | `/demo-001/*` | `/shared-001/*` |
| IAM policy `S3-bucket-4shark-*` | `S3-bucket-4shark-atento-001` | `S3-bucket-4shark-beta-001` | `S3-bucket-4shark-demo-001` | `S3-bucket-4shark-shared-001` |
| Container Insights log groups | `/aws/ecs/containerinsights/{cluster}/performance` (depends on cluster name) | same | same | same |

**Decision: keep as-is.** Already in clean pattern.

### Group C — Atento outlier (atento has `app-`, others don't)

This is the bulk of the alignment work. Atento has `app-` prefix; beta/demo/shared don't:

| Resource | Atento | Beta | Demo | Shared |
|---|---|---|---|---|
| ECS cluster | `app-atento-001-cluster` | `beta-001-cluster` | `demo-001-cluster` | `shared-001-cluster` |
| ECS services | `app-atento-001-{role}-service` | `beta-001-{role}-service` | `demo-001-{role}-service` | `shared-001-{role}-service` |
| ECS task families | `app-atento-001-{role}` | `beta-001-{role}` | `demo-001-{role}` | `shared-001-{role}` |
| Capacity providers | `app-atento-001-{role}-cp` | `beta-001-{role}-cp` | `demo-001-{role}-cp` | `shared-001-{role}-cp` |
| Auto Scaling Groups | `app-atento-001-{role}-asg` | `beta-001-{role}-asg` | `demo-001-{role}-asg` | `shared-001-{role}-asg` |
| Lambda functions | `Lambda-app-atento-001-*` | `Lambda-beta-001-*` | `Lambda-demo-001-*` | `Lambda-shared-001-*` |
| Lambda log groups | `/aws/lambda/Lambda-app-atento-001-*` | `/aws/lambda/Lambda-beta-001-*` | `/aws/lambda/Lambda-demo-001-*` | `/aws/lambda/Lambda-shared-001-*` |
| ECS log groups | `/ecs/app-atento-001-*` | `/ecs/beta-001-*` | `/ecs/demo-001-*` | `/ecs/shared-001-*` |
| EventBridge ECS schedules | `ECS-app-atento-001-cron-*` | `ECS-beta-001-cron-*` | `ECS-demo-001-cron-*` | `ECS-shared-001-cron-*` |
| EventBridge Lambda schedules | `Lambda-app-atento-001-worker-*` | `Lambda-beta-001-worker-*` | `Lambda-demo-001-worker-*` | `Lambda-shared-001-worker-*` |
| CodeDeploy applications | `app-atento-001-web-app` | `beta-001-web-app` | `demo-001-web-app` | `shared-001-web-app` |
| CodeDeploy deployment groups | `app-atento-001-web-dg` | `beta-001-web-dg` | `demo-001-web-dg` | `shared-001-web-dg` |
| IAM role - codedeploy | `app-atento-001-codedeploy-role` | `beta-001-codedeploy-role` | `demo-001-codedeploy-role` | `shared-001-codedeploy-role` |
| IAM role - ECS instance | `app-atento-001-ecs-instance-role` | `beta-001-ecs-instance-role` | `demo-001-ecs-instance-role` | `shared-001-ecs-instance-role` |
| IAM role - ECS scheduler | `app-atento-001-ecs-scheduler-role` | `beta-001-ecs-scheduler-role` | `demo-001-ecs-scheduler-role` | `shared-001-ecs-scheduler-role` |
| IAM role - codedeploy-hook-lambda | `codedeploy-hook-lambda-role-app-atento-001` | `codedeploy-hook-lambda-role-beta-001` | `codedeploy-hook-lambda-role-demo-001` | `codedeploy-hook-lambda-role-shared-001` |
| IAM role - EventBridge scheduler | `EventBridge-app-atento-001-scheduler-role` | `EventBridge-beta-001-scheduler-role` | `EventBridge-demo-001-scheduler-role` | `EventBridge-shared-001-scheduler-role` |
| IAM role - Lambda autoscaling | `Lambda-app-atento-001-worker-*-autoscaling-role` | `Lambda-beta-001-worker-*-autoscaling-role` | `Lambda-demo-001-worker-*-autoscaling-role` | `Lambda-shared-001-worker-*-autoscaling-role` |
| IAM policy - deploy | `app-atento-001-deploy-app-atento-001` (double `app-`!) | `beta-001-deploy-beta-001` | `demo-001-deploy-demo-001` | `shared-001-deploy-shared-001` |
| IAM policy - CloudWatch logs | `CloudWatch-app-atento-001-lambda-logs-policy` | `CloudWatch-beta-001-lambda-logs-policy` | `CloudWatch-demo-001-lambda-logs-policy` | `CloudWatch-shared-001-lambda-logs-policy` |
| IAM policy - AutoScaling | `AutoScaling-app-atento-001-lambda-worker-policy` | `AutoScaling-beta-001-lambda-worker-policy` | `AutoScaling-demo-001-lambda-worker-policy` | `AutoScaling-shared-001-lambda-worker-policy` |
| IAM policy - ECS lambda worker | `ECS-app-atento-001-lambda-worker-policy` | `ECS-beta-001-lambda-worker-policy` | `ECS-demo-001-lambda-worker-policy` | `ECS-shared-001-lambda-worker-policy` |
| IAM policy - EventBridge invoke | `EventBridge-app-atento-001-lambda-invoke-policy` | `EventBridge-beta-001-lambda-invoke-policy` | `EventBridge-demo-001-lambda-invoke-policy` | `EventBridge-shared-001-lambda-invoke-policy` |
| IAM policy - codedeploy-hook-lambda | `codedeploy-hook-lambda-policy-app-atento-001` | `codedeploy-hook-lambda-policy-beta-001` | `codedeploy-hook-lambda-policy-demo-001` | `codedeploy-hook-lambda-policy-shared-001` |

**Total resources to rename for atento alignment:** ~40+ named resources (including all ECS services × 9 + capacity providers × 9 + ASGs × 9 + lambdas × 5).

### Group D — ALB pattern divergence (3-way split, no consensus)

ALB and ALB-related resources have 3 different naming styles. There's no consistent pattern even among the 4 stacks:

| Resource | Atento | Beta | Demo | Shared |
|---|---|---|---|---|
| ALB | `app-atento-001-lb` | `beta-001-pub-lb` | `demo-001-pub-lb` | `shared-001-lb` |
| Target group (prod) | `app-atento-001-tg` | `beta-001-pub-tg` | `demo-001-pub-tg` | `shared-001-tg` |
| Target group (alt) | `app-atento-001-alt-tg` | `beta-001-pub-alt-tg` | `demo-001-pub-alt-tg` | `shared-001-alt-tg` |
| ECS bluegreen role | `app-atento-001-ecs-bg-role` | `beta-001-pub-ecs-bg-role` | `demo-001-pub-ecs-bg-role` | `shared-001-ecs-bg-role` (also `shared-001-pub-ecs-bg-role` legacy?) |
| ALB security group | `app-atento-001-alb-*` | `beta-001-pub-alb-*` | `demo-001-pub-alb-*` | `shared-001-alb-*` |

3 patterns:
- **Atento**: `app-atento-001-{lb,tg,alt-tg}` (with `app-`, no `-pub-`)
- **Beta/demo**: `{env}-pub-{lb,tg,alt-tg}` (with `-pub-` infix, no `app-`)
- **Shared**: `{env}-{lb,tg,alt-tg}` (no `app-`, no `-pub-`)

Plus shared has a stray `shared-001-pub-ecs-bg-role` IAM role (legacy from parallel migration?).

**Decision: tech debt accepted (Camada 4).** Same `replace_triggered_by` blocker as discussed; rename requires ECS service replacement. Out of scope for this plan.

### Stale / Legacy Resources Found

These should be cleaned up separately. **Each requires per-stack investigation before deletion** to confirm it's truly unused:

| Resource | Status | Why suspected stale |
|---|---|---|
| Log group `/aws/lambda/Lambda-app-shared-001-worker-system-autoscaling` | Almost certainly stale | Pre-parallel-migration name; current Lambda log groups are `Lambda-shared-001-*`. Verify no logs being written. |
| SSM `/shared-001/opensearch/master_user`, `/shared-001/opensearch/master_password` | Stale (LastModified 2026-02-25 — parallel migration era) | Created during parallel migration; current code reads `/app-shared-001/opensearch/*` (created by opensearch module with `domain_name = "app-shared-001"`). Verify no consumer references `/shared-001/opensearch/*` paths. |
| SSM `/atento-001/opensearch/master_user`, `/atento-001/opensearch/master_password` | Likely stale | Current atento code reads `/app-atento-001/opensearch/*` (created by opensearch module + referenced in `modules/atento_001_task_config/main.tf`). Origin of `/atento-001/opensearch/*` path unclear. Verify no consumer. |
| IAM policy `app-poc-deploy-demo-001` | Stale | Doesn't match any current stack pattern — POC remnant |
| IAM policy `ECS-deploy-atento-001-policy` | Investigate | Pre-PR #374 era pattern; need to verify no longer attached/used |
| IAM policy `ECS-deploy-demo-001-policy` | Investigate | Same |
| IAM policy `ECS-deploy-shared-001-policy` | Investigate | Same |
| IAM role `shared-001-pub-ecs-bg-role` | Stale | Stray from PR #372 rename (new shared ALB role is `shared-001-ecs-bg-role`); the `-pub-` variant is unused |

**Note on opensearch SSM paths:** Each stack has its own SSM paths for OpenSearch credentials — they are NOT duplicates of each other across stacks. Within atento and shared individually, however, there appear to be two co-existing path sets (`/app-{env}/opensearch/*` and `/{env}/opensearch/*`). The Terraform `opensearch` module creates `/${var.domain_name}/opensearch/*`; with `domain_name = "app-{env}"`, only the `/app-{env}/*` path is currently TF-managed. The `/{env}/opensearch/*` paths are leftover from earlier setup (parallel migration for shared, unknown origin for atento) and need verification before deletion.

### Pattern Summary

| Pattern | Resource categories | Stacks consistent |
|---|---|---|
| Always `app-` prefix | IAM user, VPC SSM, RDS, OpenSearch, DB subnet group, data SGs | All 4 ✓ |
| Never `app-` prefix | ECR, S3 bucket, app secrets SSM, S3 IAM policy | All 4 ✓ |
| `app-` only on atento (Group C) | ECS cluster/service/CP/ASG, Lambda, ECS log groups, scheduler, CodeDeploy, most IAM roles/policies | atento outlier ✗ |
| ALB pattern (Group D) | ALB, TG, bluegreen role, ALB SG | 3 different patterns ✗ |

### Why "Ou tudo tem app ou nada tem app" isn't achievable today

The "all or nothing" goal would require:
- **Removing `app-` from Group A:** breaks GitHub Actions (IAM user rename = new credentials), breaks VPC SSM consumers, requires Aurora rename (downtime), impossible for OpenSearch (immutable name)
- **Adding `app-` to Group B:** S3 bucket names are immutable, ECR rename means re-pushing all images and updating deploy pipeline, breaks SSM secret consumer paths

**Realistic achievable target:**
- Group A stays with `app-` (data/identity layer)
- Group B stays without `app-` (workload artifacts layer)
- Group C aligned to NO `app-` (atento migration brings it in line with beta/demo/shared)
- Group D — separate decision (ALB tech debt)

This means the codebase WILL have "some things with `app-`, some things without." The semantic split is: **identity/data tier uses `app-`; compute/runtime tier doesn't.** This is the de facto pattern of the 3 aligned stacks (beta/demo/shared); making atento conform brings consistency to that boundary.

## Objective / Target State

### Achievable alignment

| Resource | Target name | Achievable? |
|---|---|---|
| ECS cluster | `atento-001-cluster` | Yes (parallel stack) |
| ECS services, task defs | `atento-001-*` | Yes (parallel stack) |
| Capacity providers | `atento-001-*-cp` | Yes |
| Lambda functions | `Lambda-atento-001-*` | Yes (recreate, stateless) |
| CloudWatch log groups | `/ecs/atento-001-*` | Yes (recreate, accept history loss) |
| IAM scheduler role | `atento-001-ecs-scheduler-role` | Yes |
| Aurora cluster identifier | `atento-001-cluster` | Yes via `aws rds modify-db-cluster --new-db-cluster-identifier` (~2-5min downtime) |
| File structure | matches beta/demo/shared | Yes |
| `module "vpc_data"` | matches | Yes |
| IAM policy name | `atento-001-deploy-atento-001` | Yes |

### Tech debt residual (not achievable without disproportionate cost)

| Resource | Why deferred |
|---|---|
| OpenSearch domain `app-atento-001` | Domain name immutable in AWS — no rename API exists |
| ALB `app-atento-001-lb` | Same `replace_triggered_by` blocker as shared-001 (Camada 4) |
| IAM user `app-atento-001` | Mantém para compatibilidade com GitHub Actions secrets |

### Success metrics

- Atento file structure matches beta/demo/shared (visual code review)
- Plan output for app-atento-001 stack is "No changes" after Phase 1 apply
- All ECS, Lambda, log group, IAM scheduler, capacity provider names are `atento-001-*` after Phase 2
- Aurora cluster identifier is `atento-001-cluster` after Phase 2.6
- Atento application functioning correctly throughout migration (zero downtime except documented Aurora rename window)

## Problem / New Feature

Code-level inconsistency between atento and the other 3 app stacks (beta/demo/shared) creates:
- Maintenance friction: any cross-stack refactor needs special handling for atento
- Cognitive load: engineers context-switch when navigating atento vs others
- Onboarding cost: new engineers learn 2 patterns instead of 1
- Risk of "atento gets left behind" when patterns evolve

Functionally everything works. This is a code health and standardization initiative, not a defect fix.

## Challenges, Difficulties and Risks

### Technical
- **Aurora rename downtime:** `modify-db-cluster --new-db-cluster-identifier` causes 2-5min unavailability per AWS docs
- **DataDog monitors:** Multiple monitors reference resource names by string; need batch update during cutover
- **CodeDeploy state during cutover:** Deployments triggered mid-migration may behave inconsistently
- **GitHub Actions deploy pipeline:** May reference cluster name `app-atento-001-cluster` directly; needs update post-migration
- **Replication state:** Aurora failover during rename can be slower if replica lag is high

### Product/UX
- **Multi-tenant production environment:** Atento clients see any service degradation
- **Maintenance window required:** For Aurora rename specifically (~5min)
- **Communication:** Customers may need advance notice for Aurora window

### Security/privacy
- IAM policies attached to `app-atento-001` user remain valid — no credential rotation needed
- New CloudWatch log groups inherit retention from new code (30d), no compliance impact

### Performance
- Parallel stack runs alongside old during migration — temporary 2× cost for ECS instances
- Aurora replica may take time to reach consistency after rename

## Solution Options (comparative)

### Option 1 — Phase 1 only (minimal effort)

**How it works:** Do only Camadas 1+2 (file split, IAM policy alignment, vpc_data rename, DNS decoupling). Skip resource rename entirely.

- **Pros:** 1-2 days effort, zero downtime, low risk
- **Cons:** Resource names in AWS still have `app-atento-001-*` prefix — partial alignment only
- **When NOT to use:** If team wants atento truly aligned with beta/demo/shared

### Option 2 — Full migration (Camadas 1+2+3)

**How it works:** Phase 1 (code refactor) followed by Phase 2 (parallel stack with resource rename), mirroring shared-001 migration done Feb-April 2026.

- **Pros:** Atento becomes consistent with other 3 stacks; future maintenance simpler
- **Cons:** 4-6 weeks of work; high coordination cost; production risk during cutover
- **When NOT to use:** If team has higher-priority work; if atento is stable and unlikely to change

### Option 3 — Phase 1 now + Phase 2 deferred indefinitely

**How it works:** Do Phase 1 immediately (low risk, high value). Document Phase 2 as future work, defer indefinitely.

- **Pros:** Captures most of the value (code alignment) without committing to multi-week migration
- **Cons:** AWS resource naming divergence remains; "deferred indefinitely" often becomes "never done"
- **When NOT to use:** If team commits to full alignment within next quarter

## Proposed Steps (high level, don't execute yet)

### Phase 1 — On-stack refactor (Camadas 1+2)

Single PR. Low risk, zero AWS impact (other than IAM policy state surgery + manual policy create like PR #374 for shared/beta/demo).

1. Split `compute.tf` (953 lines) into `main.tf` + `compute.tf` (env_vars+secrets only) + `locals.tf` (services map transformation) + `lambda.tf` + `scheduled-tasks.tf`
2. Rename `module "networking_data"` → `module "vpc_data"` with `moved {}` block
3. Update all references in `rds.tf`, `opensearch.tf`, `mongodb.tf`
4. Add `output "alb_dns_name"` to `output.tf`
5. Update `dns/alb_data.tf` to use `terraform_remote_state` for atento (replacing `data "aws_lb" "atento_001"`)
6. Update `dns/public_dns_app4shark_com.tf` to use new data source
7. IAM policy alignment via state surgery technique (same as PR #374):
   - Manually create `atento-001-deploy-atento-001` in AWS with same document as current
   - Attach to user `app-atento-001`
   - State rm old + import new in TF state
   - Code change: `policy_name_prefix = var.environment`
   - Plan should show only tag updates
8. Add variables `networking_environment`, `manage_iam`, `lambda_scheduler_state`, `services` to `variables.tf`
9. Move `services_raw` map from compute.tf locals to `var.services` in `terraform.tfvars`

**Estimated effort:** 1-2 days. **Risk:** Low. **Downtime:** Zero.

### Phase 2 — Parallel stack migration (Camada 3)

Replicates shared-001 parallel migration playbook (Feb-April 2026). Multi-PR sequence:

**PR 2.1 — Create `terraform/atento-001/` directory structure**
- Copy structure from `app-beta-001/` as template
- Backend key: `atento-001/terraform.tfstate`
- Empty stack initially (no apply yet); just structure + Terramate config

**PR 2.2 — Migrate ECR + SSM secrets ownership**
- ECR `atento-001-app` already exists in AWS — `state mv` from old to new stack
- Create new SSM secrets under `/atento-001/...` paths (or migrate ownership)
- Pattern from commit `0f8bb6f`

**PR 2.3 — Migrate durable resources (OpenSearch, Aurora, MongoDB references) ownership**
- `state mv` between stacks (offline state manipulation via S3 pull/push)
- Resources keep current names initially (no rename yet)
- Pattern from commits `f118eaa`, `a9614ef`

**PR 2.4 — Build parallel cluster + compute (Camada 3 core)**
- New ECS cluster `atento-001-cluster`
- New capacity providers `atento-001-*-cp`
- New Lambdas `Lambda-atento-001-*`
- New log groups `/ecs/atento-001-*`
- New IAM scheduler role `atento-001-ecs-scheduler-role`
- New ALB initially with same name pattern as current (or new pattern depending on decision)
- Tasks at `desired_count = 0` initially

**PR 2.5 — Traffic migration**
- Push images to ECR
- Scale up tasks on new cluster (manual `aws ecs update-service`)
- Validate functional (smoke tests, health checks)
- Update DataDog monitors to reference new resource names
- Cloudflare CNAME flip: `atento001.app4shark.com` → new ALB DNS via `terraform_remote_state` output

**PR 2.6 — Aurora rename** (window: ~5min Aurora downtime)
- Maintenance window communicated to Atento clients
- `aws rds modify-db-cluster --db-cluster-identifier app-atento-001-cluster --new-db-cluster-identifier atento-001-cluster --apply-immediately`
- Wait for failover completion (~2-5min)
- Update terraform state to reflect new identifier
- Validate connectivity from ECS tasks

**PR 2.7 — Drain old cluster**
- Set old cluster ECS services to `desired_count = 0`
- Wait for tasks to drain
- Validate stability on new cluster

**PR 2.8 — Destroy old `app-atento-001/` compute stack**
- Pattern from commit `5da46b2`
- Old ALB, services, lambdas, capacity providers destroyed
- Old IAM resources cleaned up
- IAM user `app-atento-001` retained for GitHub Actions compatibility

### Phase 3 — Tech debt acceptance

Items NOT addressed by this migration (documented as accepted tech debt):
- OpenSearch domain `app-atento-001` (immutable name in AWS)
- ALB final naming (Camada 4 — same `replace_triggered_by` blocker as shared)
- IAM user `app-atento-001` (kept for compatibility)

## Lessons Learned from shared-001 Migration (Feb-April 2026)

These incidents happened during shared-001's parallel migration. Document them here so the atento migration doesn't repeat them.

### Incident 1: ECS services left at desired_count=0 post-migration

**What happened:** After the parallel stack migration completed, several worker services on shared-001 (`worker-commission`, `worker-system`, `worker-user`) were left with `desired_count = 0`. The CloudWatch alarms `shared-001-ecs-service-down-*` went into ALARM state but were not noticed during operational handover. The expectation was that the autoscaling Lambdas would scale up workers based on Sidekiq queue metrics, but since there were zero tasks running, no metrics were emitted, and the Lambdas had nothing to scale based on. The result: workers sat dead indefinitely until an engineer noticed and manually fixed via `aws ecs update-service --desired-count N`.

**Why it happened:**
- `desired_count` is in the `ignore_changes` lifecycle of the ECS service module, so Terraform doesn't manage it after creation
- During parallel migration, services were created with `desired_count = 0` (initial state)
- Autoscaling Lambdas decide scale based on app metrics from running tasks; if no tasks → no metrics → no scale-up decision → permanent zero
- CloudWatch alarms were in ALARM but ignored as "expected during migration"

**How to avoid in atento:**
- After Phase 2.4 (parallel cluster + compute), explicitly run `aws ecs update-service --cluster atento-001-cluster --service <each service> --desired-count <baseline>` for each service
- Validate via `aws ecs describe-services` that `runningCount` matches expected operational baseline
- Validate that ALL `*-ecs-service-down-*` CloudWatch alarms are NOT in ALARM state before declaring migration complete
- Don't trust autoscaling to recover from zero — recovery from zero requires manual intervention
- Set `desired_count` in tfvars to operational baseline (not 0), even though it's in `ignore_changes` (initial creation uses code value)

### Incident 2: ALB rename blocked by `replace_triggered_by`

**What happened:** During shared-001 alignment work, the team wanted to rename ALB from `shared-001-lb` to `shared-001-pub-lb` (matching beta/demo pattern). Discovered that the `ecs_service` module has:

```hcl
resource "terraform_data" "lb_config" {
  input = length(var.load_balancers) > 0 ? jsonencode([for lb in var.load_balancers : lb.target_group_arn]) : null
}

resource "aws_ecs_service" "this" {
  ...
  lifecycle {
    ignore_changes = [load_balancer, ...]
    replace_triggered_by = [terraform_data.lb_config]  # ← forces full service replacement on TG change
  }
}
```

This `replace_triggered_by` was added to handle VPC migration scenarios where TG ARNs change (TG has `vpc_id` as ForceNew). For ALB rename, however, this means: TG rename → TG replacement → new ARN → terraform_data.lb_config replaced → ECS service replaced → all tasks destroyed → 5-15min downtime.

**The blocker:**
- ECS service replacement = destroy + create = full downtime (no `create_before_destroy`)
- Web service uses `deployment_controller_type = "CODE_DEPLOY"` which expects specific ALB/listener config; doesn't help here
- ECS service `load_balancer` block is in `ignore_changes` (CodeDeploy manages), so changing target_group_arn in code doesn't propagate to running service without a CodeDeploy deployment

**Resolution for shared-001:** ALB rename was deferred as accepted tech debt (Camada 4). Same blocker applies to atento.

**To unblock in the future (NOT part of this plan):**
1. Modify `ecs_service` module to remove or condition `replace_triggered_by`
2. OR use parallel ALB approach with manual CodeDeploy operation to migrate task registration (multi-PR + manual ops)

## Related Cleanup Work — shared-001 SSM (separate from this plan, but flagged here)

**Stale orphan to delete (low risk):**
- `/shared-001/opensearch/master_user` (LastModified 2026-02-25)
- `/shared-001/opensearch/master_password` (LastModified 2026-02-25)

These were created during shared-001 parallel migration and abandoned. Current TF-managed path is `/app-shared-001/opensearch/*` (set by `opensearch` module via `domain_name = "app-shared-001"`). The orphans are NOT in TF state and NOT referenced in code (verified via `grep -rn "/shared-001/opensearch" app-shared-001/`).

**Pre-deletion validation:** grep all consumer projects for the orphan paths (`app/`, `integrator/`, GHA workflows, etc.) to confirm zero consumers before deletion.

**Future migration (deferred — separate from atento alignment):**

Once orphan is cleaned up, consider migrating shared-001's TF-managed OpenSearch SSM from `/app-shared-001/opensearch/*` → `/shared-001/opensearch/*` to fully remove `app-` prefix from shared-001's compute layer. Steps:

1. Modify `modules/opensearch/main.tf`: add `var.ssm_path_prefix` (default = `var.domain_name` for backward compat)
2. Update `app-shared-001/opensearch.tf`: pass `ssm_path_prefix = var.environment`
3. State surgery: copy current value from `/app-shared-001/opensearch/*` to `/shared-001/opensearch/*`, state rm + import to new addresses
4. Update `app-shared-001/compute.tf` lines 74-75: change hardcoded ARNs from `/app-shared-001/opensearch/*` to `/shared-001/opensearch/*`
5. Update `app-shared-001/ssm.tf` IAM policy resource ARN
6. Apply: TF sees no diff (state matches code)
7. Cleanup old `/app-shared-001/opensearch/*` (now orphan)
8. Trigger CodeDeploy deployment to roll out task definition update with new secret ARN

**Atento NOT changed** — atento keeps `/app-atento-001/opensearch/*` because OpenSearch domain is `app-atento-001` (immutable name), and the module change defaults to backward-compatible behavior.

## Pre-Migration Operational Checklist (Phase 2)

Before each Phase 2 PR application, prepare:

### Capacity warmup
- Verify `web_min_size`, `worker_*_min_size` in tfvars are >= 1 for services that need it (not 0)
- Confirm via `aws ec2 describe-instances` that capacity provider has running instance(s)

### Pre-prepared commands (copy-paste ready)
```bash
# After Phase 2.4 apply (parallel cluster created):
aws ecs update-service --cluster atento-001-cluster --service atento-001-web-service --desired-count 2 --profile 4shark-mfa
aws ecs update-service --cluster atento-001-cluster --service atento-001-worker-system-service --desired-count 1 --profile 4shark-mfa
# ... (same for each worker service)

# After Phase 2.5 traffic migration:
# DNS apply ready to flip
cd terraform/dns && terraform apply tfplan

# After Phase 2.6 Aurora rename:
aws rds modify-db-cluster --db-cluster-identifier app-atento-001-cluster --new-db-cluster-identifier atento-001-cluster --apply-immediately --profile 4shark-mfa
```

### Monitoring during cutover
- ECS services console open (check `runningCount` vs `desiredCount`)
- ALB target health (new ALB targets healthy?)
- CloudWatch alarms list (any unexpected ALARM?)
- Cloudflare CNAME analytics (is `atento001.app4shark.com` resolving?)
- Application logs (any errors after switch?)

### Plan B (rollback ready)
- Cloudflare CNAME revert: ready to flip back to old ALB DNS
- ECS scale: ready to set new cluster `desired_count = 0` and old cluster back to operational
- Aurora: read replica still serving if primary fails

### Validation post-migration (don't declare done without this)
- All ECS services `runningCount = desiredCount` and matching expected operational baseline
- Zero CloudWatch alarms in ALARM state related to atento
- Application smoke test passing (web request, login flow, basic API)
- DataDog monitors all updated to new resource names
- CodeDeploy deployment group config reflects new ALB / TG names
- GHA deploy pipeline succeeds (test deployment to verify)

## Internal References

### Code in scope
- `terraform/app-atento-001/compute.tf` (953 lines) — primary refactor target
- `terraform/app-atento-001/main.tf` (79 lines) — IAM user + S3 policy
- `terraform/app-atento-001/variables.tf` — needs new variables
- `terraform/app-atento-001/terraform.tfvars` — needs `services` map + new vars
- `terraform/app-atento-001/output.tf` — needs `alb_dns_name`
- `terraform/app-atento-001/dns_data.tf`, `monitoring.tf`, `monitoring_data.tf`, `mongodb.tf`, `opensearch.tf`, `rds.tf`, `redis.tf`, `s3.tf`, `ssm.tf`
- `terraform/dns/alb_data.tf` — `data "aws_lb" "atento_001"` to be decoupled
- `terraform/dns/public_dns_app4shark_com.tf` — references atento ALB DNS

### Reference patterns (shared-001 migration commits Feb-April 2026)
- `0c5354c feat(shared-001): parallel stack for app-shared-001 rename migration`
- `0f8bb6f refactor(shared-001): migrate ECR and SSM secrets ownership from app-shared-001`
- `f118eaa refactor(shared-001): move durable data resources from app-shared-001`
- `a9614ef refactor(shared-001): move opensearch domain from app-shared-001`
- `6970efb refactor(shared-001): move cloudwatch monitoring from app-shared-001`
- `e629650 feat(shared-001): migrate app-shared-001 to dedicated VPC`
- `5da46b2 chore(app-shared-001): destroy compute stack after full migration`
- `32c5cec chore(app-shared-001): rename shared-001 stack and reclaim app-shared-001 slot`

### Reference module
- `terraform/modules/iam_deploy/main.tf` — policy name format, log group ARN dependency

### Stack templates
- `terraform/app-beta-001/` — closest cleanest reference for new structure
- `terraform/app-shared-001/` — most recent migration with same pattern

## Estimated effort summary

| Phase | Effort | Risk | Downtime |
|---|---|---|---|
| Phase 1 (Camadas 1+2) | 1-2 days | Low | Zero |
| Phase 2.1 (parallel dir) | 1 day | Low | Zero |
| Phase 2.2 (ECR/SSM ownership) | 1-2 days | Low | Zero |
| Phase 2.3 (durable resources ownership) | 2-3 days | Medium | Zero |
| Phase 2.4 (parallel cluster) | 1 week | Medium | Zero |
| Phase 2.5 (traffic migration) | 3-5 days | High | Zero (with care) |
| Phase 2.6 (Aurora rename) | 1 day | Medium | 2-5min |
| Phase 2.7 (drain old) | 2-3 days | Low | Zero |
| Phase 2.8 (destroy old) | 1 day | Low | Zero |
| **Total Phase 2** | **~4-6 weeks** | **Medium-High** | **2-5min Aurora** |

---

**Question:** Which option do you prefer to follow?

Answer with: `APPROVED: Option 1` (Phase 1 only — minimal effort), `APPROVED: Option 2` (Full migration Phases 1+2), or `APPROVED: Option 3` (Phase 1 now, Phase 2 deferred).
