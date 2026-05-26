# PLAN — Demo Legacy Infrastructure Cleanup

**Status:** COMPLETE
**Created:** 2026-02-11
**Completed:** 2026-02-18
**Projects:** terraform
**Environment:** demo (us-east-1)

## Current Situation

After the successful migration to ECS with dedicated ASGs and Lambda-managed autoscaling (completed 2026-02-10), several legacy resources remain in the demo environment:

- 1 EC2 instance still running (app server) — worker-image-demo already terminated
- 7 old shared worker ASGs (`worker-demo-*`) — **ALL DELETED**
- 2 worker AMIs used for the old EC2-based deploy — still exist
- Elastic IP associated with the running app server — still allocated
- 2 legacy security groups — still exist (Worker SG has 0 ENIs, APP SG has 1 ENI from demo-app001)
- 4 legacy Lambda functions — **ALL DELETED**
- 4 legacy IAM roles + 4 IAM policies — **ALL DELETED**
- 6 legacy CloudWatch log groups — still exist

### Progress Summary

| Category | Total | Deleted | Remaining |
|----------|-------|---------|-----------|
| EC2 Instances | 2 | 2 | 0 |
| ASGs | 7 | 7 | 0 |
| Launch Templates | 7 | 7 | 0 |
| AMIs | 2 | 2 | 0 |
| Elastic IPs | 1 | 1 | 0 |
| Security Groups | 2 | 2 | 0 |
| EventBridge Rules | 1 | 1 | 0 |
| Lambda Functions | 4 | 4 | 0 |
| IAM Roles | 4 | 4 | 0 |
| IAM Policies | 4 | 4 | 0 |
| CloudWatch Log Groups | 6 | 6 | 0 |

### Active Infrastructure (KEEP)

| Resource | Type | Purpose |
|----------|------|---------|
| `demo-001-web` (i-0c372c0631e78781d) | EC2 (ECS) | ECS cluster instance |
| `demo-001-*-asg` (8 ASGs) | ASG | New dedicated ASGs |
| `demo-001-pub-lb` | ALB | Public load balancer |
| `demo-001-pub-tg` / `demo-001-pub-alt-tg` | TG | CodeDeploy blue/green |
| `pgbouncer-demo-puma` (i-0d94ee11d885895be) | EC2 | PGBouncer for Puma |
| `pgbouncer-demo-sidekiq` (i-04af861d35a147a24) | EC2 | PGBouncer for Sidekiq |
| `PGBouncer-sg` (sg-027773fe5068c6ab4) | SG | PGBouncer security group (shared) |
| `4Shark-demo-prd-db` (sg-0be66cff163cf3805) | SG | RDS security group |
| `demo-001-pub-alb-*` (sg-04e70a42ba39ba621) | SG | Current ALB security group |
| `terraform-*` (sg-0358783e741aa6412) | SG | ECS instance security group |
| `/ecs/demo-001-*` | CloudWatch | New ECS log groups |
| `/aws/lambda/Lambda-demo-001-*` (3 log groups) | CloudWatch | New Lambda log groups |
| `demo-001-*` IAM roles (5+) | IAM | New ECS roles |
| `Lambda-demo-001-*` (3 functions) | Lambda | New ECS autoscaling |
| `codedeploy-hook-lambda-demo-001` | Lambda | CodeDeploy hook |
| `/aws/lambda/codedeploy-hook-lambda-demo-001` | CloudWatch | New CodeDeploy log group |
| `Lambda-demo-001-*` schedules (3) | EventBridge | New ECS autoscaling schedules |
| `TargetTracking-demo-001-*` (2 alarms) | CloudWatch | ASG target tracking |
| `demo-001-cluster` | ECS | ECS cluster (8 services) |
| VPC `vpc-0204a1f8b5de51941` | VPC | Shared with new ECS infra |

### Audit Findings (2026-02-11)

- **Terraform:** All 7 ASGs confirmed in `terraform/main.tf` lines 761-963. `local.demo` at lines 26-32. Variables in `variables.tf` lines 17-20 (ami_demo) + lines 274-356 (21 capacity vars). Values in `terraform.tfvars` line 3 + lines 135-171. Module `asg-launch-template` is shared with other environments — cannot delete module.
- **AWS CLI:** EC2 instances confirmed with no IAM instance profiles. Legacy IAM roles, policies, Lambdas, and CloudWatch log groups identified. No legacy CloudWatch alarms found (only demo-001 TargetTracking alarms). EventBridge Scheduler schedules only contain demo-001 schedules (no legacy ones). **1 legacy EventBridge rule found:** `Lambda-demo-worker-auto-scaling-rule` (DISABLED, rate(1 min), 3 Lambda targets). No internal ALB found (unlike beta). No PGBouncer NLB found.
- **PGBouncer:** 2 PGBouncer instances (puma + sidekiq) confirmed running with shared SG `PGBouncer-sg` — these are NOT migrated and MUST remain.
- **RDS:** SG `4Shark-demo-prd-db` attached to RDS instance — MUST remain.
- **VPC:** Shared between legacy and new ECS infra — DO NOT DELETE VPC, subnets, route tables, or NACLs.

## Objective / Target State

- Remove all legacy EC2 instances (app server + worker image builder), ASGs, launch templates, and AMIs
- Remove legacy Lambda functions, IAM roles/policies, and CloudWatch log groups
- Release Elastic IP (after DNS verification)
- Reduce monthly AWS costs by ~$75-80/month (EC2 instances + EIP)
- Clean Terraform state to only contain active resources

### Success Criteria

- [x] No legacy EC2 instances running — demo-app001 **TERMINATED 2026-02-18** (cron migrated to ECS Scheduled Tasks, console replaced by `bin/ecs`)
- [x] No old worker ASGs (`worker-demo-*`) exist — **DELETED 2026-02-11**
- [x] No old launch templates (`worker-demo-*`) exist — **DELETED 2026-02-11**
- [x] Worker AMIs deregistered — **DELETED 2026-02-12** (snapshots also deleted)
- [x] Elastic IP released — **RELEASED 2026-02-12**
- [x] Legacy security group `4Shark-Demo-Worker` deleted — **DELETED 2026-02-12**
- [x] Security group `4Shark-Demo-prd-APP` — **DELETED 2026-02-18**
- [x] Legacy CloudWatch log groups deleted — **DELETED 2026-02-12**
- [x] Legacy Lambda functions deleted — **DELETED 2026-02-11**
- [x] Legacy IAM roles and policies deleted — **DELETED 2026-02-12**
- [x] Terraform code cleanup — old root Terraform files and `asg-launch-template` module removed (release 1.0.0, PR #143 merged 2026-02-13)
- [x] PGBouncer instances (puma + sidekiq) still running and healthy
- [x] ECS demo-001 services still running and healthy

## Resources to Remove

### 1. EC2 Instances

| Instance | ID | Type | State | Status |
|----------|-----|------|-------|--------|
| `demo-app001` | i-0b74f0731fb052055 | t3.large → t3.small (resized after audit) | **running** | PENDING — ~$14/mo |
| `worker-image-demo` | i-0fae0ac07b261301b | t3a.small | terminated | **DONE** (by Janderson, 2026-02-11) |

**EBS Volumes:**
- vol-0a9631f76e0bb971b (10GB gp3, demo-app001) — still active
- vol-015e5d29736ecf659 (10GB gp3, worker-image-demo) — deleted with instance

### 2. Old Worker ASGs — **ALL DONE** (by Janderson, 2026-02-11)

All 7 ASGs and their 7 launch templates have been deleted:

| ASG Name | Status |
|----------|--------|
| ~~`worker-demo-cleansing-asg`~~ | **DELETED** |
| ~~`worker-demo-commission-asg`~~ | **DELETED** |
| ~~`worker-demo-commission_tiger_shark-asg`~~ | **DELETED** |
| ~~`worker-demo-commission_white_shark-asg`~~ | **DELETED** |
| ~~`worker-demo-migration-asg`~~ | **DELETED** |
| ~~`worker-demo-system-asg`~~ | **DELETED** |
| ~~`worker-demo-user-asg`~~ | **DELETED** |

**Terraform-managed** in `terraform/main.tf` — Terraform state still needs cleanup (Phase 2).

### 3. Old Launch Templates — **ALL DONE** (by Janderson, 2026-02-11)

All 7 launch templates prefixed `worker-demo-*` have been deleted.

### 4. AMIs — **ALL DONE** (2026-02-12)

| AMI ID | Name | Status |
|--------|------|--------|
| ~~ami-09c4ce9b7b05d250d~~ | ~~`worker-image-demo-v3.7.0`~~ | **DELETED** (AMI + snapshot) |
| ~~ami-042585670b08ee535~~ | ~~`worker-image-demo-v3.8.0`~~ | **DELETED** (AMI + snapshot) |

### 5. Elastic IP — **DONE** (2026-02-12)

| EIP | IP | Status |
|-----|-----|--------|
| ~~`4Shark-Demo-prd-APP`~~ | ~~54.162.171.130~~ | **RELEASED** |

### 6. Security Groups — PARTIALLY DONE (2026-02-12)

| SG | Name | Status |
|-----|------|--------|
| sg-0345d56db03e50853 | `4Shark-Demo-prd-APP` | **KEPT** — demo-app001 still in use (cron) |
| ~~sg-092d04453a53ffdf1~~ | ~~`4Shark-Demo-Worker`~~ | **DELETED** |

### 7. EventBridge Rule — **DONE** (by Janderson, 2026-02-11)

| Rule | Status |
|------|--------|
| ~~`Lambda-demo-worker-auto-scaling-rule`~~ | **DELETED** |

### 8. Lambda Functions — **ALL DONE** (by Janderson, 2026-02-11)

| Function | Status |
|----------|--------|
| ~~`Lambda-demo-worker-auto-scaling-minor`~~ | **DELETED** |
| ~~`Lambda-demo-worker-auto-scaling-system`~~ | **DELETED** |
| ~~`Lambda-demo-worker-auto-scaling-user`~~ | **DELETED** |
| ~~`Lambda-demo-worker-auto-scaling-major`~~ | **DELETED** |

### 9. IAM Roles + Policies — **ALL DONE** (2026-02-12)

| Role | Policy | Status |
|------|--------|--------|
| ~~`Eventbridge-demo-invoke-minor-role`~~ | ~~`Eventbridge-demo-invoke-minor-policy`~~ | **DELETED** |
| ~~`Eventbridge-demo-invoke-system-role`~~ | ~~`Eventbridge-demo-invoke-system-policy`~~ | **DELETED** |
| ~~`Eventbridge-demo-invoke-user-role`~~ | ~~`Eventbridge-demo-invoke-user-policy`~~ | **DELETED** |
| ~~`Lambda-demo-worker-auto-scaling-minor-role`~~ | ~~`Lambda-demo-worker-auto-scaling-minor-policy`~~ | **DELETED** |

**Side effect resolved:** `Lambda-demo-worker-auto-scaling-minor-policy` was also attached to `Lambda-atento-worker-auto-scaling-minor-role`. Recreated as `Lambda-atento-worker-auto-scaling-minor-policy` (v2) with correct permissions (autoscaling + logs + invoke for `Lambda-atento-worker-auto-scaling-major`), attached to `Lambda-atento-worker-auto-scaling-minor-role`.

### 10. CloudWatch Log Groups — **ALL DONE** (2026-02-12)

| Log Group | Status |
|-----------|--------|
| ~~`/aws/lambda/Lambda-demo-worker-auto-scaling-major`~~ | **DELETED** |
| ~~`/aws/lambda/Lambda-demo-worker-auto-scaling-minor`~~ | **DELETED** |
| ~~`/aws/lambda/Lambda-demo-worker-auto-scaling-system`~~ | **DELETED** |
| ~~`/aws/lambda/Lambda-demo-worker-auto-scaling-user`~~ | **DELETED** |
| ~~`/aws/lambda/codedeploy-hook-lambda-demo`~~ | **DELETED** (orphaned, Lambda was deleted) |
| ~~`/ecs/task-demo-app001`~~ | **DELETED** (legacy naming, empty) |

## Challenges, Difficulties and Risks

### Technical
- Old worker ASGs are Terraform-managed — must be removed via Terraform PR, not manually
- EC2 instance `demo-app001` is **manually created** (confirmed: no Terraform resource, no IAM instance profile) — remove via AWS CLI
- AMI deregistration is not reversible — snapshots should be kept briefly as safety net
- Elastic IP release is permanent — DNS must be verified safe first
- VPC `vpc-0204a1f8b5de51941` is shared with new ECS infra AND other environments (Atento, Shared, Setup) — DO NOT DELETE
- ~~Module `asg-launch-template` is shared with other environments~~ — **DELETED** (release 1.0.0, all environments migrated to standalone directories)
- Lambda functions may have CloudWatch log groups auto-created — confirmed 4 exist under `/aws/lambda/Lambda-demo-worker-*`
- **demo-app001 is RUNNING (t3.large)** — more costly than beta-app001 which was already stopped. Stop first, verify nothing breaks, then terminate.

### Incident: Atento IAM Policy Deletion (2026-02-12)
- `Lambda-demo-worker-auto-scaling-minor-policy` was attached to BOTH `Lambda-demo-worker-auto-scaling-minor-role` (demo) AND `Lambda-atento-worker-auto-scaling-minor-role` (atento)
- Policy was incorrectly deleted during demo IAM cleanup, temporarily breaking atento Lambda
- **Resolution:** Created `Lambda-atento-worker-auto-scaling-minor-policy` with correct permissions and attached to the atento role
- **Lesson learned:** Always verify cross-environment attachments with `list-entities-for-policy` before deleting ANY IAM policy

### Critical: PGBouncer Instances MUST NOT Be Touched
- `pgbouncer-demo-puma` (i-0d94ee11d885895be) — still actively used by ECS services
- `pgbouncer-demo-sidekiq` (i-04af861d35a147a24) — still actively used by ECS services
- SG `PGBouncer-sg` (sg-027773fe5068c6ab4) — shared by both PGBouncers
- These were NOT migrated to ECS and remain essential infrastructure

### Security/Privacy
- `demo-app001` may contain application data on its EBS volume — create snapshot backup before termination

### Cost
- Current waste: ~$14/month (demo-app001 t3.small, resized from t3.large after audit)
- Already saved: ~$15/month (worker-image-demo terminated) + ~$3.65/month (EIP released)
- Remaining estimated savings: **~$14/month** (demo-app001 termination)

## Proposed Steps

### Phase 1 — DNS Verification — **DONE** (2026-02-12)
1. ~~Check Cloudflare DNS for any records pointing to `54.162.171.130`~~ — No DNS records found
2. ~~Check if `demo.app4shark.com` or `demo001.app4shark.com` resolve to this IP~~ — Confirmed by user
3. ~~Confirm EIP is safe to release~~ — Safe to release after EC2 termination

### Phase 2 — Terraform: Remove Old Worker ASGs — SKIPPED
ASGs and LTs were deleted directly from AWS by Janderson (2026-02-11). Old Terraform folders will be dropped entirely — no PR needed for code removal.

### Phase 3 — Manual: Terminate Legacy EC2 Instance — DONE (2026-02-18)
`worker-image-demo` already terminated. `demo-app001` terminated 2026-02-18 (cron migrated to ECS Scheduled Tasks, console replaced by `bin/ecs`).

**Result:** 1 EC2 instance terminated + 1 EBS volume deleted

### Phase 4 — Manual: Deregister AMIs — **DONE** (2026-02-12)

~~1. Deregister `worker-image-demo-v3.8.0` (ami-042585670b08ee535)~~
~~2. Deregister `worker-image-demo-v3.7.0` (ami-09c4ce9b7b05d250d)~~
~~3. Delete associated snapshots~~

**Result:** ~~Removes 2 AMIs~~ — Already completed. Snapshots also deleted (no rollback needed).

### Phase 5 — Manual: Release Elastic IP — **DONE** (2026-02-12)

~~1. Disassociate from demo-app001~~
~~2. Release `4Shark-Demo-prd-APP` (eipalloc-07ef3164971760037)~~

**Result:** ~~Releases 1 Elastic IP~~ — Already completed. demo-app001 kept running (cron), just without public IP.

### Phase 6 — Manual: Delete Security Groups — DONE (2026-02-18)

~~1. Delete `4Shark-Demo-Worker` (sg-092d04453a53ffdf1)~~ — **DELETED 2026-02-12**
~~2. Delete `4Shark-Demo-prd-APP` (sg-0345d56db03e50853)~~ — **DELETED 2026-02-18**

**Result:** 2 SGs deleted.

### Phase 7 — Delete Legacy EventBridge Rule — **DONE** (by Janderson, 2026-02-11)

~~1. Verify rule exists and is DISABLED~~
~~2. Remove all 3 targets~~
~~3. Delete the rule~~

**Result:** ~~Removes 1 EventBridge rule + 3 targets~~ — Already completed.

### Phase 8 — Delete Legacy Lambda Functions — **DONE** (by Janderson, 2026-02-11)

~~1. Delete all 4 legacy Lambda functions~~

**Result:** ~~Removes 4 legacy Lambda functions~~ — Already completed.

### Phase 9 — Delete Legacy IAM Roles and Policies — **DONE** (2026-02-12)

~~1. Detach policies from roles~~
~~2. Delete roles~~
~~3. Delete policies~~

**Result:** ~~Removes 4 IAM roles + 4 IAM policies~~ — Already completed.

**Note:** Recreated atento policy as `Lambda-atento-worker-auto-scaling-minor-policy` to replace the cross-environment dependency.

### Phase 10 — Manual: Delete Legacy CloudWatch Log Groups — **DONE** (2026-02-12)

~~1. Delete 4 legacy `/aws/lambda/Lambda-demo-worker-*` log groups~~
~~2. Delete orphaned `/aws/lambda/codedeploy-hook-lambda-demo` log group~~
~~3. Delete legacy `/ecs/task-demo-app001` log group~~

**Result:** ~~Removes 6 legacy CloudWatch log groups~~ — Already completed. Verified `/aws/lambda/codedeploy-hook-lambda-demo-001` (new infra) still exists.

### Phase 11 — Validation — DONE (2026-02-18)
- demo-app001 terminated, `4Shark-Demo-prd-APP` SG deleted
- No legacy `*-app0*` instances remaining (verified via AWS CLI)
- All legacy resources removed

## Key Differences from Beta Cleanup

| Aspect | Beta | Demo |
|--------|------|------|
| Legacy EC2 instances | 3 (app001, worker-image, puma-backup) | 2 (app001, worker-image) |
| app001 state | stopped | **running** (t3.large) |
| Internal ALB | Yes (4Shark-Beta-dev-APP-LB) | No |
| PGBouncer NLB | Yes (pgbouncer-beta NLB) | No |
| Legacy /ecs/ log groups | 7 | 1 (/ecs/task-demo-app001) |
| Legacy /aws/lambda/ log groups | 4 + 1 codedeploy | 4 + 1 codedeploy |
| Est. monthly savings | ~$75-95 | ~$75-80 |

## Internal References

- Terraform demo-001: `terraform/demo-001/` (standalone directory with S3 backend `4shark-terraform-state`)
- ~~Terraform root: `terraform/main.tf`~~ — **REMOVED** (release 1.0.0)
- ~~Terraform module: `terraform/modules/asg-launch-template/`~~ — **REMOVED** (release 1.0.0)
- ~~Terraform vars: `terraform/variables.tf`, `terraform/terraform.tfvars`~~ — **REMOVED** (release 1.0.0)
- Beta cleanup plan: `~/.claude/plans/completed/beta-legacy-infra-cleanup/PLAN.md` (reference)
- Shared cleanup plan: `~/.claude/plans/completed/shared-legacy-infra-cleanup/PLAN.md` (reference)
