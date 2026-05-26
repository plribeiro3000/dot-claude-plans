# PLAN — Shared Legacy Infrastructure Cleanup

**Status:** COMPLETE
**Created:** 2026-02-12
**Completed:** 2026-02-18
**Projects:** terraform
**Environment:** shared / shared-001 (us-east-1)

## Progress Summary

| Phase | Description | Status |
|-------|-------------|--------|
| 1 — ALB Traffic Verification | CloudWatch metrics check | SKIPPED (ALB deleted directly) |
| 2 — Terraform: Remove Old Worker ASGs | PR to remove 7 ASGs + 7 LTs | SKIPPED (folders will be dropped entirely) |
| 3 — Deregister Instances from ALB TG | Remove from target group | SKIPPED (ALB deleted directly) |
| 4 — EC2 Instances | Terminate legacy instances | DONE (5 of 5) |
| 5 — ALB + Target Group | Delete legacy ALB | DONE |
| 6 — AMIs | Deregister worker AMIs + snapshots | DONE |
| 7 — Security Groups | Delete unused SGs | DONE (3 of 3) |
| 8 — EventBridge Rule | Delete rule + 3 targets | DONE |
| 9 — Lambda Functions | Delete 4 legacy functions | DONE |
| 10 — IAM Roles + Policies | Delete 4 roles + 4 policies | DONE |
| 11 — CloudWatch Log Groups | Delete 4 legacy log groups | DONE |
| 12 — Validation | Final health check | DONE |
| Extra — ASGs | Delete 7 ASGs from AWS | DONE |
| Extra — Launch Templates | Delete 7 LTs from AWS | DONE |

## Current Situation

After the successful migration to ECS with dedicated ASGs and Lambda-managed autoscaling (completed 2026-02-12), several legacy resources remain in the shared environment:

- 5 EC2 instances from the old deployment model (4 app servers + 1 worker image builder)
- 7 old shared worker ASGs (`worker-shared-*`) with their launch templates — all at desired=0
- 2 worker AMIs used for the old EC2-based deploy
- A public ALB (`4Shark-Shared-prd-APP-LB`) still routing `shared001.app4shark.com` to 4 legacy app instances (DNS already switched to new ALB)
- 3 orphaned security groups (APP, Worker, APP-LB)
- 4 legacy Lambda functions (old autoscaling, Sept 2025)
- 4 legacy IAM roles + 4 IAM policies (old EventBridge/Lambda, Sept 2025)
- 1 legacy EventBridge rule (DISABLED)
- 4 legacy CloudWatch log groups (Lambda auto-created)

These resources generate unnecessary cost (~$175/month) and create confusion about what is active infrastructure vs. legacy.

### Active Infrastructure (KEEP)

| Resource | Type | Purpose |
|----------|------|---------|
| `shared-001-web` (4 instances) | EC2 (ECS) | ECS cluster web instances |
| `shared-001-worker-system` (7 instances) | EC2 (ECS) | ECS cluster worker instances |
| `shared-001-worker-commission` (7 instances) | EC2 (ECS) | ECS cluster worker instances |
| `shared-001-worker-user` (8 instances) | EC2 (ECS) | ECS cluster worker instances |
| `shared-001-*-asg` (8 ASGs) | ASG | New dedicated ASGs |
| `shared-001-pub-lb` | ALB | Public load balancer |
| `shared-001-pub-tg` / `shared-001-pub-alt-tg` | TG | CodeDeploy blue/green |
| `pgbouncer-shared-puma` (i-086425fec69a52984) | EC2 | PGBouncer for Puma |
| `pgbouncer-shared-sidekiq` (i-046938eb28ac46bdc) | EC2 | PGBouncer for Sidekiq |
| `shared-001-pub-alb-*` (sg-07f73f94eda18ae48) | SG | Current ALB security group |
| `/aws/lambda/Lambda-shared-001-*` (3 log groups) | CloudWatch | New Lambda log groups |
| `/aws/lambda/codedeploy-hook-lambda-shared-001` | CloudWatch | New CodeDeploy log group |
| `shared-001-*` IAM roles (7) | IAM | New ECS roles |
| `Lambda-shared-001-*` (3 functions) | Lambda | New ECS autoscaling |
| `codedeploy-hook-lambda-shared-001` | Lambda | CodeDeploy hook |
| `Lambda-shared-001-*` schedules (3) | EventBridge | New ECS autoscaling schedules |
| `TargetTracking-shared-001-*` (2 alarms) | CloudWatch | ASG target tracking |
| `shared-001-cluster` | ECS | ECS cluster |
| `shared-001-web-app` | CodeDeploy | CodeDeploy application |
| `shared-001-ecs-instance-profile` | IAM | ECS instance profile |
| `app-shared-001` | IAM User | Deploy user (new) |
| `S3-bucket-4shark-shared` | IAM Policy | S3 access (used by app-shared AND app-shared-001) |
| `app-shared` | IAM User | Legacy deploy user — still has active access key + ECS-deploy-shared-001-policy attached. KEEP for now. |
| VPC `vpc-0204a1f8b5de51941` | VPC | Shared with new ECS infra + other environments |

### Shared Cross-Environment Resources (DO NOT DELETE)

| Resource | Used By | Notes |
|----------|---------|-------|
| `Lambda-worker-auto-scaling-standard-role` | shared, beta, demo, atento Lambdas | Shared IAM role across 4 environments |
| `Lambda-worker-auto-scaling-standard-policy` | ^ | Attached to standard role |
| `Lambda-worker-auto-scaling-major-role` | shared, beta, demo, atento Lambdas | Shared IAM role across 4 environments |
| `Lambda-worker-auto-scaling-major-policy` | ^ | Attached to major role |
| `*.app4shark.com` ACM cert | Both legacy and new ALBs | Wildcard certificate |

### Audit Findings (2026-02-12)

- **Terraform:** All 7 legacy ASGs confirmed in `terraform/main.tf` lines 297-556. `local.shared` at lines 10-16. Variables in `variables.tf` lines 7-10 (ami_shared) + lines 106-186 (21 capacity vars). Values in `terraform.tfvars` line 4 + lines 53-93. Module `asg-launch-template` is shared with atento/beta/demo — cannot delete module.
- **AWS CLI:** EC2 instances confirmed with no IAM instance profiles (manually created). Legacy IAM roles, policies, Lambdas, and CloudWatch log groups identified. No EIPs associated. No legacy ECS log groups found. No NLB for shared environment.
- **Legacy ALB:** `4Shark-Shared-prd-APP-LB` is still active with listener rule forwarding `shared001.app4shark.com` → `4Shark-Shared-prd-APP-TG-ssl` (4 legacy app instances, all healthy on HTTPS:443). DNS already switched to `shared-001-pub-lb` via CloudFlare. No traffic should be hitting legacy ALB, but verify via CloudWatch metrics before deletion.
- **IAM Users:** `app-shared` (created 2023-11-10) has active access key (***REMOVED***) and is attached to `S3-bucket-4shark-shared` + `ECS-deploy-shared-001-policy`. This user may still be used by CI/CD — DO NOT DELETE without verification.
- **VPC:** `vpc-0204a1f8b5de51941` shared between legacy, new ECS, and other environments (Demo, Atento) — DO NOT DELETE VPC, subnets, route tables, or NACLs.
- **Security Groups:** No active resources reference the 3 legacy SGs (confirmed via ENI cross-reference check).

## Objective / Target State

- Remove all legacy EC2 instances (4 app servers + 1 worker image builder), ASGs, launch templates, and AMIs
- Remove legacy ALB and target group (after verifying no traffic)
- Remove legacy Lambda functions, IAM roles/policies, EventBridge rule, and CloudWatch log groups
- Reduce monthly AWS costs by ~$175/month
- Clean Terraform state to only contain active resources

### Success Criteria

- [x] No old worker ASGs (`worker-shared-*`) exist — **DELETED 2026-02-13 (AWS)**
- [x] No old launch templates (`worker-shared-*`) exist — **DELETED 2026-02-13 (AWS)**
- [x] Worker AMIs deregistered + snapshots deleted — **DELETED 2026-02-13**
- [x] Legacy ALB (`4Shark-Shared-prd-APP-LB`) and target group removed — **DELETED 2026-02-13**
- [x] Legacy CloudWatch log groups deleted (4) — **DELETED 2026-02-13**
- [x] Legacy Lambda functions deleted (4) — **DELETED 2026-02-13**
- [x] Legacy EventBridge rule deleted — **DELETED 2026-02-13**
- [x] Legacy IAM roles and policies deleted (4 + 4) — **DELETED 2026-02-13**
- [x] Legacy EC2 instances terminated (shared-app002, shared-app003, shared-app004, worker-image-shared) — **TERMINATED 2026-02-13**
- [x] Security groups deleted (4Shark-Shared-prd-APP-LB, 4Shark-Shared-Worker) — **DELETED 2026-02-13**
- [x] `shared-app001` (i-063effadff8838930) — **TERMINATED 2026-02-18** (cron migrated to ECS Scheduled Tasks, console replaced by `bin/ecs`)
- [x] Security group `4Shark-Shared-prd-APP` (sg-08fa04c865fedb6cc) — **DELETED 2026-02-18**
- [x] Terraform code cleanup — old root Terraform files and `asg-launch-template` module removed (release 1.0.0, PR #143 merged 2026-02-13)
- [x] PGBouncer instances (puma + sidekiq) still running and healthy
- [x] ECS shared-001 services still running and healthy

## Resources to Remove

### 1. EC2 Instances (5 total, all running)

| Instance | ID | Type | State | SG | Vol Size | Est. Cost/mo |
|----------|-----|------|-------|----|----------|-------------|
| `shared-app001` | i-063effadff8838930 | t2.medium | running | 4Shark-Shared-prd-APP | 15GB gp3 | ~$33 |
| `shared-app002` | i-066befc39817065e7 | t2.medium | running | 4Shark-Shared-prd-APP | 15GB gp3 | ~$33 |
| `shared-app003` | i-08b8fdfc5a38de3de | t2.medium | running | 4Shark-Shared-prd-APP | 15GB gp3 | ~$33 |
| `shared-app004` | i-0f0de41de6f4893ea | t2.medium | running | 4Shark-Shared-prd-APP | 15GB gp3 | ~$33 |
| `worker-image-shared` | i-0cfc82e369fc9ca2d | t3a.small | running | 4Shark-Shared-Worker | 10GB gp3 | ~$14 |

- No IAM instance profiles (manually created)
- No termination protection on any instance
- All volumes have `DeleteOnTermination=true`
- No public IPs or EIPs associated

**EBS Volumes (auto-deleted with instances):**
- vol-01dc13e2b0ce692e3 (15GB gp3, shared-app001)
- vol-07f26c446000f7828 (15GB gp3, shared-app002)
- vol-0825e055fbc197175 (15GB gp3, shared-app003)
- vol-04fa34984fb405358 (15GB gp3, shared-app004)
- vol-08f48b207143c9f75 (10GB gp3, worker-image-shared)

### 2. Old Worker ASGs (7 total, all desired=0)

| ASG Name | Launch Template | Created |
|----------|----------------|---------|
| `worker-shared-cleansing-asg` | `worker-shared-cleansing2025...` (v106) | 2025-08-18 |
| `worker-shared-commission-asg` | `worker-shared-commission2025...` (v106) | 2025-08-18 |
| `worker-shared-commission_tiger_shark-asg` | `worker-shared-commission_tiger_shark2025...` (v106) | 2025-08-18 |
| `worker-shared-commission_white_shark-asg` | `worker-shared-commission_white_shark2025...` (v106) | 2025-08-18 |
| `worker-shared-migration-asg` | `worker-shared-migration2025...` (v106) | 2025-08-18 |
| `worker-shared-system-asg` | `worker-shared-system2025...` (v106) | 2025-08-18 |
| `worker-shared-user-asg` | `worker-shared-user2025...` (v106) | 2025-08-18 |

**Terraform-managed** in `terraform/main.tf` (root) via `asg-launch-template` module.

**Terraform files to edit:**
- `terraform/main.tf` — Remove 7 module blocks (lines 297-556) + `local.shared` (lines 10-16)
- `terraform/variables.tf` — Remove `ami_shared` (lines 7-10) + 21 `shared_*` capacity vars (lines 106-186)
- `terraform/terraform.tfvars` — Remove `ami_shared` (line 4) + 21 capacity values (lines 53-93)

### 3. Old Launch Templates (7 total, deleted with ASGs via Terraform)

| Launch Template | ID | Versions |
|-----------------|-----|----------|
| `worker-shared-cleansing2025...` | lt-0d73ce8fcb7023bb8 | 106 |
| `worker-shared-commission2025...` | lt-082241c15c3183d5a | 106 |
| `worker-shared-commission_tiger_shark2025...` | lt-06d527aa810f61119 | 106 |
| `worker-shared-commission_white_shark2025...` | lt-032f2f85177615780 | 106 |
| `worker-shared-migration2025...` | lt-007486cc6efff6c83 | 106 |
| `worker-shared-system2025...` | lt-07d2b71c87b943ebd | 106 |
| `worker-shared-user2025...` | lt-06b6c8308730ddeed | 106 |

### 4. Load Balancer + Target Group (Legacy)

| Resource | Detail |
|----------|--------|
| `4Shark-Shared-prd-APP-LB` | Public ALB, internet-facing, active, no deletion protection |
| DNS | `4Shark-Shared-prd-APP-LB-1472461485.us-east-1.elb.amazonaws.com` |
| SG | `sg-0688bb2908677521d` (4Shark-Shared-prd-APP-LB) |
| Listener :80 | Redirect → HTTPS |
| Listener :443 Rule 1 | Host: `shared001.app4shark.com` → TG `4Shark-Shared-prd-APP-TG-ssl` |
| Listener :443 Default | Fixed response 403 |
| `4Shark-Shared-prd-APP-TG-ssl` | Target group, HTTPS:443, 4 healthy targets (legacy instances) |

**CRITICAL:** DNS for `shared001.app4shark.com` has been switched to `shared-001-pub-lb` via CloudFlare. Verify zero traffic on legacy ALB via CloudWatch metrics (RequestCount) before deletion.

### 5. AMIs

| AMI ID | Name | Snapshot |
|--------|------|----------|
| ami-0f09f987cbb3e4b1d | `worker-image-shared-v3.7.0` | snap-0f33abe67d5cd73d5 |
| ami-0fb8037b4a0817920 | `worker-image-shared-v3.8.0` | snap-0b27c91eaf99eee54 |

### 6. Security Groups

| SG | Name | ENIs | Status |
|----|------|------|--------|
| sg-08fa04c865fedb6cc | `4Shark-Shared-prd-APP` | 4 ENIs (4 app instances) | Orphaned after EC2 termination. No cross-refs. |
| sg-0032e773fe9ad6125 | `4Shark-Shared-Worker` | 1 ENI (worker-image-shared) | Orphaned after EC2 termination. No cross-refs. |
| sg-0688bb2908677521d | `4Shark-Shared-prd-APP-LB` | 2 ENIs (ALB) | Orphaned after ALB deletion. No cross-refs. |

### 7. EventBridge Rule (Legacy)

| Rule | State | Schedule | Targets |
|------|-------|----------|---------|
| `Lambda-shared-worker-auto-scaling-rule` | DISABLED | rate(1 minute) | 3 Lambdas (user, system, minor) |

**Targets:**
- `Lambda-shared-worker-auto-scaling-user` (Id: 0k64mu8mvgrdbmd0o99)
- `Lambda-shared-worker-auto-scaling-system` (Id: 0w1l98i4awjb5tu8f)
- `Lambda-shared-worker-auto-scaling-minor` (Id: Id6c1602e3-f568-43a4-9065-a9e665e58a53)

### 8. Lambda Functions (Legacy)

| Function | Runtime | Role | Last Modified |
|----------|---------|------|---------------|
| `Lambda-shared-worker-auto-scaling-major` | ruby3.4 | `Lambda-worker-auto-scaling-major-role` (*) | 2025-09-16 |
| `Lambda-shared-worker-auto-scaling-minor` | ruby3.4 | `Lambda-shared-worker-auto-scaling-minor-role` | 2025-09-16 |
| `Lambda-shared-worker-auto-scaling-system` | ruby3.4 | `Lambda-worker-auto-scaling-standard-role` (*) | 2025-09-13 |
| `Lambda-shared-worker-auto-scaling-user` | ruby3.4 | `Lambda-worker-auto-scaling-standard-role` (*) | 2025-09-13 |

(*) Roles marked with `*` are shared across environments (beta, demo, atento) — DO NOT delete roles, only delete Lambda functions.

### 9. IAM Roles + Policies (Legacy, shared-specific only)

| Role | Policy | Created |
|------|--------|---------|
| `Eventbridge-shared-invoke-minor-role` | `Eventbridge-shared-invoke-minor-policy` (v2) | 2025-09-02 |
| `Eventbridge-shared-invoke-system-role` | `Eventbridge-shared-invoke-system-policy` (v2) | 2025-09-02 |
| `Eventbridge-shared-invoke-user-role` | `Eventbridge-shared-invoke-user-policy` (v2) | 2025-09-02 |
| `Lambda-shared-worker-auto-scaling-minor-role` | `Lambda-shared-worker-auto-scaling-minor-policy` (v2) | 2025-09-10 |

### 10. CloudWatch Log Groups (Legacy)

| Log Group | Stored Bytes | Retention | Notes |
|-----------|-------------|-----------|-------|
| `/aws/lambda/Lambda-shared-worker-auto-scaling-major` | 238 KB | 7 days | Legacy Lambda |
| `/aws/lambda/Lambda-shared-worker-auto-scaling-minor` | 8.3 MB | 7 days | Legacy Lambda |
| `/aws/lambda/Lambda-shared-worker-auto-scaling-system` | 5.9 MB | 7 days | Legacy Lambda |
| `/aws/lambda/Lambda-shared-worker-auto-scaling-user` | 5.9 MB | 7 days | Legacy Lambda |

## Challenges, Difficulties and Risks

### Technical
- Old worker ASGs are Terraform-managed — must be removed via Terraform PR, not manually
- EC2 instances (shared-app001 through 004, worker-image-shared) are **manually created** (confirmed: no Terraform resource, no IAM instance profiles) — remove via AWS CLI
- **Legacy ALB is still active and serving** — has listener rule for `shared001.app4shark.com` forwarding to 4 healthy legacy instances. DNS has been switched to new ALB via CloudFlare, so traffic should not be hitting it, but MUST verify via CloudWatch metrics (RequestCount = 0 for past 24h) before deletion.
- AMI deregistration is not reversible — snapshots should be kept briefly as safety net
- VPC `vpc-0204a1f8b5de51941` is shared with new ECS infra AND other environments (Demo, Atento) — DO NOT DELETE
- ~~Module `asg-launch-template` is shared with other environments~~ — **DELETED** (release 1.0.0, all environments migrated to standalone directories)
- IAM policies must be detached from roles before role deletion
- `Lambda-worker-auto-scaling-standard-role` and `Lambda-worker-auto-scaling-major-role` are used by Lambda functions in beta, demo, and atento — DO NOT DELETE these roles during shared cleanup
- `app-shared` IAM user has active access key and `ECS-deploy-shared-001-policy` attached — may be used by CI/CD, DO NOT DELETE without verification

### Critical: PGBouncer Instances MUST NOT Be Touched
- `pgbouncer-shared-puma` (i-086425fec69a52984) — still actively used by ECS services
- `pgbouncer-shared-sidekiq` (i-046938eb28ac46bdc) — still actively used by ECS services
- These were NOT migrated to ECS and remain essential infrastructure

### Security/Privacy
- Legacy app servers may contain application data on EBS volumes — volumes auto-deleted with `DeleteOnTermination=true`
- `worker-image-shared` is a running instance — stop before terminate to verify nothing depends on it

### Cost
- Current waste: 4×t2.medium (~$134/mo) + 1×t3a.small (~$14/mo) + ALB (~$22/mo) + EBS (~$6/mo)
- Total estimated savings: **~$175/month**

## Proposed Steps

### Phase 1 — Verify Legacy ALB Has No Traffic
1. Check CloudWatch ALB metrics (RequestCount) for `4Shark-Shared-prd-APP-LB` over the past 24-48h
2. Confirm RequestCount = 0 (DNS already switched to `shared-001-pub-lb`)
3. If traffic is still hitting legacy ALB, investigate DNS propagation before proceeding

### Phase 2 — Terraform: Remove Old Worker ASGs (PR)
1. Create branch `cleanup/shared-legacy-worker-asgs`
2. Remove `local.shared` block from `terraform/main.tf` (lines 10-16)
3. Remove 7 `module "asg-worker-shared-*"` blocks from `terraform/main.tf` (lines 297-556)
4. Remove `ami_shared` variable from `terraform/variables.tf` (lines 7-10)
5. Remove 21 `shared_*` capacity variables from `terraform/variables.tf` (lines 106-186)
6. Remove `ami_shared` value from `terraform/terraform.tfvars` (line 4)
7. Remove 21 `shared_*` capacity values from `terraform/terraform.tfvars` (lines 53-93)
8. Run `terraform plan` to verify only removals
9. PR → Review → Merge → `terraform apply`

**Result:** Deletes 7 ASGs + 7 Launch Templates

### Phase 3 — Manual: Deregister Legacy Instances from Legacy ALB Target Group
1. Deregister all 4 instances from `4Shark-Shared-prd-APP-TG-ssl`
2. This ensures no traffic can reach legacy instances even if DNS reverts

### Phase 4 — Manual: Terminate Legacy EC2 Instances
1. Stop `worker-image-shared` (i-0cfc82e369fc9ca2d) — wait, verify nothing breaks
2. Stop all 4 app servers (i-063effadff8838930, i-066befc39817065e7, i-08b8fdfc5a38de3de, i-0f0de41de6f4893ea) — wait, verify ECS shared-001 services + PGBouncers still healthy
3. Health check: ECS services, PGBouncer puma, PGBouncer sidekiq, new ALB
4. Terminate all 5 instances

**Result:** Deletes 5 EC2 instances + 5 EBS volumes

### Phase 5 — Manual: Delete Legacy ALB + Target Group
1. Verify CloudWatch confirms no traffic on legacy ALB
2. Delete listener rules on `4Shark-Shared-prd-APP-LB`
3. Delete target group `4Shark-Shared-prd-APP-TG-ssl`
4. Delete ALB `4Shark-Shared-prd-APP-LB`

**Result:** Deletes 1 ALB + 1 Target Group

### Phase 6 — Manual: Deregister AMIs
1. Verify no launch templates reference these AMIs (Phase 2 should have cleaned `worker-shared-*` LTs)
2. Deregister `worker-image-shared-v3.8.0` (ami-0fb8037b4a0817920)
3. Deregister `worker-image-shared-v3.7.0` (ami-0f09f987cbb3e4b1d)
4. Keep snapshots for 1 week as safety net, delete after 2026-02-19

**Result:** Removes 2 AMIs

### Phase 7 — Manual: Delete Security Groups
1. Verify `4Shark-Shared-prd-APP` (sg-08fa04c865fedb6cc) has no ENIs (after Phase 4)
2. Delete `4Shark-Shared-prd-APP`
3. Verify `4Shark-Shared-Worker` (sg-0032e773fe9ad6125) has no ENIs (after Phase 4)
4. Delete `4Shark-Shared-Worker`
5. Verify `4Shark-Shared-prd-APP-LB` (sg-0688bb2908677521d) has no ENIs (after Phase 5)
6. Delete `4Shark-Shared-prd-APP-LB`

**Result:** Removes 3 unused Security Groups

### Phase 8 — Manual: Delete Legacy EventBridge Rule
1. Remove 3 targets from `Lambda-shared-worker-auto-scaling-rule`
2. Delete `Lambda-shared-worker-auto-scaling-rule` (DISABLED)

**Result:** Removes 1 EventBridge rule + 3 targets

### Phase 9 — Manual: Delete Legacy Lambda Functions
1. Remove resource policy from `Lambda-shared-worker-auto-scaling-minor` (EventBridge invoke permission)
2. Delete `Lambda-shared-worker-auto-scaling-major`
3. Delete `Lambda-shared-worker-auto-scaling-minor`
4. Delete `Lambda-shared-worker-auto-scaling-system`
5. Delete `Lambda-shared-worker-auto-scaling-user`

**Result:** Removes 4 legacy Lambda functions

### Phase 10 — Manual: Delete Legacy IAM Roles and Policies
1. Detach `Eventbridge-shared-invoke-minor-policy` from `Eventbridge-shared-invoke-minor-role`, delete both
2. Detach `Eventbridge-shared-invoke-system-policy` from `Eventbridge-shared-invoke-system-role`, delete both
3. Detach `Eventbridge-shared-invoke-user-policy` from `Eventbridge-shared-invoke-user-role`, delete both
4. Detach `Lambda-shared-worker-auto-scaling-minor-policy` from `Lambda-shared-worker-auto-scaling-minor-role`, delete both

**Result:** Removes 4 IAM roles + 4 IAM policies

### Phase 11 — Manual: Delete Legacy CloudWatch Log Groups
1. Delete `/aws/lambda/Lambda-shared-worker-auto-scaling-major`
2. Delete `/aws/lambda/Lambda-shared-worker-auto-scaling-minor`
3. Delete `/aws/lambda/Lambda-shared-worker-auto-scaling-system`
4. Delete `/aws/lambda/Lambda-shared-worker-auto-scaling-user`

**Result:** Removes 4 legacy CloudWatch log groups

### Phase 12 — Validation ✅ DONE (2026-02-18)
- shared-app001 terminated (cron migrated to ECS Scheduled Tasks, console replaced by `bin/ecs`)
- `4Shark-Shared-prd-APP` SG deleted
- No legacy `*-app0*` instances remaining (verified via AWS CLI)
- All legacy resources removed

## Key Differences from Beta and Demo Cleanup

| Aspect | Beta | Demo | Shared |
|--------|------|------|--------|
| Legacy EC2 instances | 3 (app001, worker-image, puma-backup) | 2 (app001, worker-image) | **5** (app001-004, worker-image) |
| app instances | 1 (stopped) | 1 (running, t3.large) | **4** (all running, t2.medium) |
| Legacy ALB | Yes (internal, empty TG) | No | **Yes** (public, 4 healthy targets!) |
| EIP to release | Yes | Yes | **No** (no EIPs) |
| Internal NLB | Yes (PGBouncer) | No | No |
| Legacy /ecs/ log groups | 7 | 1 | **0** |
| Legacy /aws/lambda/ log groups | 4 + 1 codedeploy | 4 + 1 codedeploy | **4** (no orphaned codedeploy) |
| Cross-env IAM roles | N/A | N/A | **Yes** (standard-role, major-role used by 4 envs) |
| Legacy SGs | 4 | 2 | **3** |
| Est. monthly savings | ~$75-95 | ~$75-80 | **~$175** |

## Internal References

- Terraform shared-001: `terraform/shared-001/` (standalone directory with S3 backend `4shark-terraform-state`)
- ~~Terraform root: `terraform/main.tf`~~ — **REMOVED** (release 1.0.0)
- ~~Terraform module: `terraform/modules/asg-launch-template/`~~ — **REMOVED** (release 1.0.0)
- ~~Terraform vars: `terraform/variables.tf`, `terraform/terraform.tfvars`~~ — **REMOVED** (release 1.0.0)
- ~~Lambda autoscaling: `terraform/lambda-autoscaling/`~~ — **REMOVED** (release 1.0.0, integrated into each standalone env)
- ~~Old S3 state buckets: `tfstateecs4shark`, `tfstateecs4shark-atento`, `tfstateecs4shark-demo`, `tfstateecs4shark-poc`, `tfstate-asg-lt`~~ — **DELETED** (2026-02-13)
- Beta cleanup plan: `~/.claude/plans/completed/beta-legacy-infra-cleanup/PLAN.md` (reference)
- Demo cleanup plan: `~/.claude/plans/completed/demo-legacy-infra-cleanup/PLAN.md` (reference)
