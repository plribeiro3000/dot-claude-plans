# PLAN — Atento Legacy Infrastructure Cleanup

**Status:** COMPLETE
**Created:** 2026-02-13
**Completed:** 2026-02-18
**Projects:** terraform
**Environment:** atento / atento-001 (us-east-1)

## Progress Summary

| Phase | Description | Status |
|-------|-------------|--------|
| 1 — ALB Traffic Verification | CloudWatch metrics check | DONE |
| 2 — ASGs + Launch Templates | Delete 7 ASGs + 7 LTs (manual) | DONE |
| 3A — EC2 Terminate (4 of 5) | Terminate app002/003/004 + worker-image | DONE |
| 3B — EC2 Terminate app001 | Terminate when cron jobs migrated | DONE |
| 4 — ALB + Target Group | Delete legacy ALB + TG | DONE |
| 5 — AMIs | Deregister 3 AMIs + delete 3 snapshots | DONE |
| 6 — Security Groups | Delete unused SGs | DONE (4 of 4) |
| 7 — EventBridge Rule | Delete rule + 3 targets | DONE |
| 8 — Lambda Functions | Delete 4 legacy functions | DONE |
| 9 — IAM Roles + Policies | Delete 4 roles + 4 policies | DONE |
| 10 — CloudWatch Log Groups | Delete 4 legacy log groups | DONE |
| 11 — Validation | Final health check | DONE |

**All phases complete.** Last items (app001 + SG) finished 2026-02-18 after cron migration to ECS Scheduled Tasks.

## Current Situation

After the successful migration to ECS with dedicated ASGs and Lambda-managed autoscaling (completed 2026-02-12), several legacy resources remain in the atento environment:

- 5 EC2 instances from the old deployment model (4 app servers + 1 worker image builder)
- 7 old shared worker ASGs (`worker-atento-*`) with their launch templates — all at desired=0
- 3 AMIs (2 worker + 1 app snapshot)
- A public ALB (`4Shark-Atento-prd-APP-LB`) still routing to 4 legacy app instances (DNS already switched to new ALB)
- 3 legacy security groups (APP, Worker, APP-LB)
- 4 legacy Lambda functions (old autoscaling, Sept 2025)
- 3 legacy IAM roles + 3 IAM policies (old EventBridge invoke roles) + 1 Lambda role + 1 Lambda policy
- 1 legacy EventBridge rule (DISABLED)
- 4 legacy CloudWatch log groups (Lambda auto-created)

These resources generate unnecessary cost and create confusion about what is active infrastructure vs. legacy.

### Active Infrastructure (KEEP)

| Resource | Type | Purpose |
|----------|------|---------|
| `atento-001-web` (4 instances) | EC2 (ECS) | ECS cluster web instances |
| `atento-001-worker-system` (1 instance) | EC2 (ECS) | ECS cluster worker instances |
| `atento-001-worker-commission` (1 instance) | EC2 (ECS) | ECS cluster worker instances |
| `atento-001-worker-user` (8 instances) | EC2 (ECS) | ECS cluster worker instances |
| `atento-001-*-asg` (8 ASGs) | ASG | New dedicated ASGs |
| `atento-001-pub-lb` | ALB | Public load balancer |
| `atento-001-pub-alb-*` (sg-045ebd3322d8f1ea3) | SG | Current ALB security group |
| `terraform-*` (sg-0b4655f5a79cc7478) | SG | ECS instance security group |
| `pgbouncer-atento-puma` (i-0cf3bfce8a0724fe4) | EC2 | PGBouncer for Puma |
| `pgbouncer-atento-sidekiq` (i-0f1b80edb0ea79746) | EC2 | PGBouncer for Sidekiq |
| `PgBouncer` (sg-0d40db569f5088ef9) | SG | PGBouncer security group |
| `pgbouncer-atento-sg` (sg-03979b34fde6479a4) | SG | PGBouncer security group (other VPC) |
| ~~`atento-prd-elasticsearch` (sg-0b022486f83571ab7)~~ | SG | DELETED — orphaned, not used by OpenSearch domain (uses different SG) |
| `4app-atento-br-teste-rds-sg` (sg-0ddb2a65901bac264) | SG | RDS security group (other VPC) |
| `/ecs/atento-001-*` (8 log groups) | CloudWatch | New ECS log groups |
| `/aws/lambda/Lambda-atento-001-*` (5 log groups) | CloudWatch | New Lambda log groups |
| `/aws/lambda/codedeploy-hook-lambda-atento-001` | CloudWatch | New CodeDeploy log group |
| `atento-001-*` IAM roles (5) | IAM | New ECS roles |
| `EventBridge-atento-001-*` IAM role + policy | IAM | New scheduler role |
| `Lambda-atento-001-*` (5 functions) | Lambda | New ECS autoscaling |
| `codedeploy-hook-lambda-atento-001` | Lambda | CodeDeploy hook |
| `app-atento-001` | IAM User | Deploy user (new) |
| VPC `vpc-0204a1f8b5de51941` | VPC | Shared with new ECS infra + other environments |
| `4app-atento-br-nat-gateway` EIP (3.212.42.252) | EIP | NAT Gateway (other VPC) — DO NOT RELEASE |

### Cross-Environment Resources (DO NOT DELETE)

| Resource | Used By | Notes |
|----------|---------|-------|
| `Lambda-worker-auto-scaling-standard-role` | shared, beta, demo, atento Lambdas | Shared IAM role across 4 environments |
| `Lambda-worker-auto-scaling-standard-policy` | ^ | Attached to standard role |
| `Lambda-worker-auto-scaling-major-role` | shared, beta, demo, atento Lambdas | Shared IAM role across 4 environments |
| `Lambda-worker-auto-scaling-major-policy` | ^ | Attached to major role |
| `*.app4shark.com` ACM cert | Both legacy and new ALBs | Wildcard certificate |

### Other Atento Resources (DO NOT DELETE — different system)

| Resource | Notes |
|----------|-------|
| `EC2-start-integrator-atento-br` (IAM role) | Integrator service, not part of app migration |
| `EC2-machine-atento-br` (IAM policy) | Integrator service |
| `Lambda-start-integrator-atento-br` (IAM policy) | Integrator service |
| `CloudWatch-Lambda-EC2-start-integrator-atento-br` (IAM policy) | Integrator service |
| `S3-bucket-4shark-integrator-atento-br` (IAM policy) | Integrator service |

### Audit Findings (2026-02-13)

- **EC2:** 5 legacy instances confirmed running. No IAM instance profiles (manually created). No public IPs or EIPs. All volumes have `DeleteOnTermination=true`.
- **Legacy ALB:** `4Shark-Atento-prd-APP-LB` is active with listener rule forwarding to `4Shark-Atento-prd-APP-TG-ssl` (4 legacy app instances, all healthy on HTTPS:443). DNS already switched to `atento-001-pub-lb` via CloudFlare. Verify zero traffic via CloudWatch before deletion.
- **ASGs:** 7 legacy ASGs (`worker-atento-*`) all at desired=0. 8 new ASGs (`atento-001-*`) active.
- **AMIs:** 3 AMIs found — 2 worker images (`v3.7.0`, `v3.8.0`) + 1 app snapshot (`atento-app002`).
- **Security Groups:** 3 legacy SGs in VPC `vpc-0204a1f8b5de51941`. ENIs tied to legacy EC2 instances and ALB. No cross-references from other SGs (to verify).
- **EventBridge:** 1 legacy rule DISABLED, 3 targets (system, user, minor Lambdas).
- **Lambda:** 4 legacy functions. `major` and `system`/`user` use shared cross-env roles (DO NOT delete roles). `minor` uses its own role.
- **IAM:** 3 EventBridge invoke roles + policies (atento-specific, safe to delete). 1 Lambda minor role + policy (atento-specific, safe to delete).
- **CloudWatch:** 4 legacy log groups with 7-day retention. `major` already at 0 bytes.
- **VPC:** `vpc-0204a1f8b5de51941` shared with new ECS infra + shared/demo environments — DO NOT DELETE.

## Objective / Target State

- Remove all legacy EC2 instances (4 app servers + 1 worker image builder), ASGs, launch templates, and AMIs
- Remove legacy ALB and target group (after verifying no traffic)
- Remove legacy Lambda functions, IAM roles/policies, EventBridge rule, and CloudWatch log groups
- Remove legacy security groups
- Drop old Terraform folders entirely (no PR needed for code removal)

### Success Criteria

- [x] No legacy EC2 instances running — 5 of 5 terminated (app001 **TERMINATED 2026-02-18**, cron migrated to ECS Scheduled Tasks)
- [x] No old worker ASGs (`worker-atento-*`) exist — DONE (deleted 2026-02-13)
- [x] No old launch templates (`worker-atento-*`) exist — DONE (deleted 2026-02-13)
- [x] Worker AMIs deregistered (+ app snapshot AMI) — DONE (3 AMIs + 3 snapshots)
- [x] Legacy ALB (`4Shark-Atento-prd-APP-LB`) and target group removed — DONE (zero traffic confirmed)
- [x] All legacy security groups removed — 4 of 4 done (APP SG **DELETED 2026-02-18**)
- [x] Legacy CloudWatch log groups deleted (4) — DONE
- [x] Legacy Lambda functions deleted (4) — DONE
- [x] Legacy EventBridge rule deleted — DONE
- [x] Legacy IAM roles and policies deleted (4 + 4) — DONE
- [x] Terraform code cleanup — old root Terraform files and `asg-launch-template` module removed (release 1.0.0, PR #143 merged 2026-02-13)
- [x] PGBouncer instances (puma + sidekiq) still running and healthy
- [x] ECS atento-001 services still running and healthy

## Resources to Remove

### 1. EC2 Instances (5 total, all running)

| Instance | ID | Type | State | SG | Vol Size | Est. Cost/mo |
|----------|-----|------|-------|----|----------|-------------|
| `atento-app001` | i-01fe7b0f0dc0cd5e2 | t2.medium | running | 4Shark-Atento-prd-APP | gp3 | ~$33 |
| `atento-app002` | i-0bfd054b31f4a8a11 | t2.medium | running | 4Shark-Atento-prd-APP | gp3 | ~$33 |
| `atento-app003` | i-0d8a1ba8c4c2ca0a3 | t2.medium | running | 4Shark-Atento-prd-APP | gp3 | ~$33 |
| `atento-app004` | i-00fd0644f9591b7c4 | t2.medium | running | 4Shark-Atento-prd-APP | gp3 | ~$33 |
| `worker-image-atento` | i-0ea8a28a4f735d5f6 | t3a.small | running | 4Shark-Atento-Worker | gp3 | ~$14 |

- No IAM instance profiles (manually created)
- All volumes have `DeleteOnTermination=true`
- No public IPs or EIPs associated

**EBS Volumes (auto-deleted with instances):**
- vol-03968ef618fa256ff (atento-app001)
- vol-0b887935c13c3aed3 (atento-app002)
- vol-0fd67bd9a15b90572 (atento-app003)
- vol-0b08cb14589149a63 (atento-app004)
- vol-05f4fbdb59cda5d9a (worker-image-atento)

### 2. Old Worker ASGs (7 total, all desired=0)

| ASG Name | Launch Template | Created |
|----------|----------------|---------|
| `worker-atento-cleansing-asg` | `worker-atento-cleansing2025...` (lt-0537348ebf6da0a5c) | 2025-08-18 |
| `worker-atento-commission-asg` | `worker-atento-commission2025...` (lt-0e7667f78bb17f02c) | 2025-08-18 |
| `worker-atento-commission_tiger_shark-asg` | `worker-atento-commission_tiger_shark2025...` (lt-0ed6f684d295dfaac) | 2025-08-18 |
| `worker-atento-commission_white_shark-asg` | `worker-atento-commission_white_shark2025...` (lt-0521ad31c16342651) | 2025-08-18 |
| `worker-atento-migration-asg` | `worker-atento-migration2025...` (lt-006c9241f392a6103) | 2025-08-18 |
| `worker-atento-system-asg` | `worker-atento-system2025...` (lt-0758a22033e6522d2) | 2025-08-18 |
| `worker-atento-user-asg` | `worker-atento-user2025...` (lt-02090ca3900afebe1) | 2025-08-18 |

### 3. Old Launch Templates (7 total)

| Launch Template | ID |
|-----------------|----|
| `worker-atento-cleansing2025...` | lt-0537348ebf6da0a5c |
| `worker-atento-commission2025...` | lt-0e7667f78bb17f02c |
| `worker-atento-commission_tiger_shark2025...` | lt-0ed6f684d295dfaac |
| `worker-atento-commission_white_shark2025...` | lt-0521ad31c16342651 |
| `worker-atento-migration2025...` | lt-006c9241f392a6103 |
| `worker-atento-system2025...` | lt-0758a22033e6522d2 |
| `worker-atento-user2025...` | lt-02090ca3900afebe1 |

### 4. Load Balancer + Target Group (Legacy)

| Resource | Detail |
|----------|--------|
| `4Shark-Atento-prd-APP-LB` | Public ALB, internet-facing, active |
| ARN | `arn:aws:elasticloadbalancing:us-east-1:405749097490:loadbalancer/app/4Shark-Atento-prd-APP-LB/07ad022dfd0bb760` |
| SG | `sg-0c3c89b3855f2c011` (4Shark-Atento-prd-APP-LB) |
| `4Shark-Atento-prd-APP-TG-ssl` | Target group, HTTPS:443, 4 healthy targets (legacy app instances) |
| TG ARN | `arn:aws:elasticloadbalancing:us-east-1:405749097490:targetgroup/4Shark-Atento-prd-APP-TG-ssl/6d457f715a3b3dc0` |

**CRITICAL:** DNS already switched to `atento-001-pub-lb` via CloudFlare. Verify zero traffic on legacy ALB via CloudWatch metrics (RequestCount) before deletion.

### 5. AMIs

| AMI ID | Name | Snapshot |
|--------|------|----------|
| ami-0a6c783ead9d0a096 | `worker-image-atento-v3.8.0` | snap-0737287c1c0458737 |
| ami-04df9ddd81789caf9 | `worker-image-atento-v3.7.0` | snap-049c163974e95ec94 |
| ami-039789a85d5826a42 | `atento-app002` (app snapshot) | snap-06ffc7764a7ce581a |

### 6. Security Groups

| SG | Name | ENIs | Status |
|----|------|------|--------|
| sg-028ac379bbf238e21 | `4Shark-Atento-prd-APP` | 4 ENIs (4 app instances) | Orphaned after EC2 termination |
| sg-017f04587a743355e | `4Shark-Atento-Worker` | 1 ENI (worker-image-atento) | Orphaned after EC2 termination |
| sg-0c3c89b3855f2c011 | `4Shark-Atento-prd-APP-LB` | 2 ENIs (ALB) | Orphaned after ALB deletion |

### 7. EventBridge Rule (Legacy)

| Rule | State | Schedule | Targets |
|------|-------|----------|---------|
| `Lambda-atento-worker-auto-scaling-rule` | DISABLED | rate(1 minute) | 3 Lambdas (system, user, minor) |

**Targets:**
- `Lambda-atento-worker-auto-scaling-system` (Id: Id9f1cbf64-a25e-43df-8982-174ff7759514)
- `Lambda-atento-worker-auto-scaling-user` (Id: Idcbadd28a-799f-467e-964a-a82a6df0d33e)
- `Lambda-atento-worker-auto-scaling-minor` (Id: Idf57dc9db-2de4-421d-b618-482aa1ecb9bd)

### 8. Lambda Functions (Legacy)

| Function | Runtime | Role | Last Modified |
|----------|---------|------|---------------|
| `Lambda-atento-worker-auto-scaling-major` | ruby3.4 | `Lambda-worker-auto-scaling-major-role` (*) | 2025-09 |
| `Lambda-atento-worker-auto-scaling-minor` | ruby3.4 | `Lambda-atento-worker-auto-scaling-minor-role` | 2025-09 |
| `Lambda-atento-worker-auto-scaling-system` | ruby3.4 | `Lambda-worker-auto-scaling-standard-role` (*) | 2025-09 |
| `Lambda-atento-worker-auto-scaling-user` | ruby3.4 | `Lambda-worker-auto-scaling-standard-role` (*) | 2025-09 |

(*) Roles marked with `*` are shared across environments (beta, demo, shared) — DO NOT delete roles, only delete Lambda functions.

### 9. IAM Roles + Policies (Legacy, atento-specific only)

| Role | Policy | Created |
|------|--------|---------|
| `Eventbridge-atento-invoke-minor-role` | `Eventbridge-atento-invoke-minor-policy` | 2025-09-09 |
| `Eventbridge-atento-invoke-system-role` | `Eventbridge-atento-invoke-system-policy` | 2025-09-09 |
| `Eventbridge-atento-invoke-user-role` | `Eventbridge-atento-invoke-user-policy` | 2025-09-09 |
| `Lambda-atento-worker-auto-scaling-minor-role` | `Lambda-atento-worker-auto-scaling-minor-policy` | 2025-09-10 |

### 10. CloudWatch Log Groups (Legacy)

| Log Group | Stored Bytes | Retention | Notes |
|-----------|-------------|-----------|-------|
| `/aws/lambda/Lambda-atento-worker-auto-scaling-major` | 0 bytes | 7 days | Legacy Lambda |
| `/aws/lambda/Lambda-atento-worker-auto-scaling-minor` | 8.2 MB | 7 days | Legacy Lambda |
| `/aws/lambda/Lambda-atento-worker-auto-scaling-system` | 5.8 MB | 7 days | Legacy Lambda |
| `/aws/lambda/Lambda-atento-worker-auto-scaling-user` | 5.8 MB | 7 days | Legacy Lambda |

## Challenges, Difficulties and Risks

### Technical
- EC2 instances are **manually created** (no Terraform, no IAM instance profiles) — remove via AWS CLI
- **Legacy ALB is active with 4 healthy targets** — DNS already switched via CloudFlare, MUST verify zero traffic before deletion
- VPC `vpc-0204a1f8b5de51941` is shared with new ECS infra AND other environments (Shared, Demo) — DO NOT DELETE
- ~~Module `asg-launch-template` is shared with other environments~~ — **DELETED** (release 1.0.0, all environments migrated to standalone directories)
- IAM policies must be detached from roles before role deletion
- `Lambda-worker-auto-scaling-standard-role` and `Lambda-worker-auto-scaling-major-role` are used by Lambda functions in beta, demo, and shared — DO NOT DELETE these roles
- EventBridge invoke policies are in `service-role/` path — use full ARN when detaching
- AMI `atento-app002` is an app snapshot (not worker image) — verify if still needed before deregistering

### Critical: PGBouncer Instances MUST NOT Be Touched
- `pgbouncer-atento-puma` (i-0cf3bfce8a0724fe4) — still actively used by ECS services
- `pgbouncer-atento-sidekiq` (i-0f1b80edb0ea79746) — still actively used by ECS services
- These were NOT migrated to ECS and remain essential infrastructure

### Critical: Integrator Resources MUST NOT Be Touched
- `EC2-start-integrator-atento-br` role + associated policies — separate system, not part of app migration

### Security/Privacy
- Legacy app servers may contain application data on EBS volumes — volumes auto-deleted with `DeleteOnTermination=true`

### Cost
- Current waste: 4×t2.medium (~$134/mo) + 1×t3a.small (~$14/mo) + ALB (~$22/mo) + EBS (~$5/mo)
- Total estimated savings: **~$175/month**

## Proposed Steps

**NOTE:** Migration completed 2026-02-12. Cleanup starts 2026-02-13 (DNS stable, no issues since migration).

### Phase 1 — CloudWatch Log Groups — DONE (2026-02-13)
1. Delete `/aws/lambda/Lambda-atento-worker-auto-scaling-major`
2. Delete `/aws/lambda/Lambda-atento-worker-auto-scaling-minor`
3. Delete `/aws/lambda/Lambda-atento-worker-auto-scaling-system`
4. Delete `/aws/lambda/Lambda-atento-worker-auto-scaling-user`

**Result:** Removes 4 legacy CloudWatch log groups

### Phase 2 — EventBridge Rule — DONE (2026-02-13)
1. Remove 3 targets from `Lambda-atento-worker-auto-scaling-rule`
2. Delete `Lambda-atento-worker-auto-scaling-rule` (DISABLED)

**Result:** Removes 1 EventBridge rule + 3 targets

### Phase 3 — Lambda Functions — DONE (2026-02-13)
1. Delete `Lambda-atento-worker-auto-scaling-major`
2. Delete `Lambda-atento-worker-auto-scaling-minor`
3. Delete `Lambda-atento-worker-auto-scaling-system`
4. Delete `Lambda-atento-worker-auto-scaling-user`

**Result:** Removes 4 legacy Lambda functions

### Phase 4 — IAM Roles + Policies — DONE (2026-02-13)
1. Detach `Eventbridge-atento-invoke-minor-policy` from `Eventbridge-atento-invoke-minor-role`, delete both
2. Detach `Eventbridge-atento-invoke-system-policy` from `Eventbridge-atento-invoke-system-role`, delete both
3. Detach `Eventbridge-atento-invoke-user-policy` from `Eventbridge-atento-invoke-user-role`, delete both
4. Detach `Lambda-atento-worker-auto-scaling-minor-policy` from `Lambda-atento-worker-auto-scaling-minor-role`, delete both

Note: `Lambda-atento-worker-auto-scaling-minor-policy` had multiple versions (v1 non-default + v2 default). Deleted v1 first, then deleted the policy.

**Result:** Removes 4 IAM roles + 4 IAM policies

### Phase 5 — AMIs + Snapshots — DONE (2026-02-13)
1. Deregister `worker-image-atento-v3.8.0` (ami-0a6c783ead9d0a096)
2. Deregister `worker-image-atento-v3.7.0` (ami-04df9ddd81789caf9)
3. Deregister `atento-app002` (ami-039789a85d5826a42) — verify if still needed
4. Delete associated snapshots (snap-0737287c1c0458737, snap-049c163974e95ec94, snap-06ffc7764a7ce581a)

**Result:** Removes 3 AMIs + 3 snapshots

### Phase 6 — ASGs + Launch Templates — DONE (2026-02-13)
1. Delete 7 ASGs (`worker-atento-*`)
2. Delete 7 launch templates (`worker-atento-*`)

**Result:** Removes 7 ASGs + 7 Launch Templates

### Phase 7 — EC2 Instances — PARTIAL (4 of 5 terminated)
1. Terminate `worker-image-atento` (i-0ea8a28a4f735d5f6) — DONE
2. Terminate 3 app instances (app002, app003, app004) — DONE
3. Verify ECS atento-001 services + PGBouncers still healthy — DONE
4. Terminate `atento-app001` — **DONE 2026-02-18** (cron migrated to ECS Scheduled Tasks, console replaced by `bin/ecs`)

**Result:** 5 of 5 EC2 instances terminated.

### Phase 8 — ALB + Target Group — DONE (2026-02-13)
1. CloudWatch RequestCount verified zero traffic on legacy ALB (24h window)
2. Delete 2 listeners (HTTP:80, HTTPS:443)
3. Delete ALB `4Shark-Atento-prd-APP-LB`
4. Delete TG `4Shark-Atento-prd-APP-TG-ssl`

**Result:** Deletes 1 ALB + 1 Target Group

### Phase 9 — Security Groups — PARTIAL (3 of 4 deleted)
1. Verify and delete `4Shark-Atento-prd-APP-LB` (sg-0c3c89b3855f2c011) — DONE
2. Verify and delete `4Shark-Atento-Worker` (sg-017f04587a743355e) — DONE
3. Verify and delete `4Shark-Atento-prd-APP` (sg-028ac379bbf238e21) — **DONE 2026-02-18**
4. Discovered and deleted orphaned `atento-prd-elasticsearch` (sg-0b022486f83571ab7) — not used by OpenSearch domain (uses sg-0e7cb6a64d4fcc54b instead)

Note: `4app-atento-br-teste-rds-sg` (sg-0ddb2a65901bac264) verified IN USE by RDS instances `atento-001-app-cluster` and `atento-001-app-ro` — kept.

**Result:** 4 SGs deleted + 1 orphaned SG discovered and deleted.

### Phase 10 — Terraform Code Cleanup — DONE (2026-02-13)
Old root Terraform files (`main.tf`, `variables.tf`, `terraform.tfvars`), `modules/asg-launch-template/`, and `lambda-autoscaling/` directory removed in release 1.0.0 (PR #143). Old S3 state buckets (`tfstateecs4shark`, `tfstateecs4shark-atento`, `tfstateecs4shark-demo`, `tfstateecs4shark-poc`, `tfstate-asg-lt`) deleted.

### Phase 11 — Validation ✅ DONE (2026-02-18)
- atento-app001 terminated (cron migrated to ECS Scheduled Tasks, console replaced by `bin/ecs`)
- `4Shark-Atento-prd-APP` SG deleted
- No legacy `*-app0*` instances remaining (verified via AWS CLI)
- All legacy resources removed

## Key Differences from Shared Cleanup

| Aspect | Shared | Atento |
|--------|--------|--------|
| Legacy EC2 instances | 5 (app001-004, worker-image) | **5** (app001-004, worker-image) |
| Legacy ALB | Public, 4 healthy targets | **Public, 4 healthy targets** |
| EIP to release | No | **No** (NAT Gateway EIP is separate system) |
| Extra AMIs | None | **1** (atento-app002 snapshot) |
| Integrator resources | N/A | **Yes** (EC2-start-integrator — DO NOT DELETE) |
| EventBridge invoke policy path | Standard | **service-role/** (use full ARN) |
| Est. monthly savings | ~$175 | **~$175** |

## Internal References

- Terraform atento-001: `terraform/atento-001/` (standalone directory with S3 backend `4shark-terraform-state`)
- ~~Terraform module: `terraform/modules/asg-launch-template/`~~ — **REMOVED** (release 1.0.0)
- ~~Old root Terraform: `terraform/main.tf`, `terraform/variables.tf`, `terraform/terraform.tfvars`~~ — **REMOVED** (release 1.0.0)
- Shared cleanup plan: `~/.claude/plans/completed/shared-legacy-infra-cleanup/PLAN.md` (reference)
- Demo cleanup plan: `~/.claude/plans/completed/demo-legacy-infra-cleanup/PLAN.md` (reference)
- Beta cleanup plan: `~/.claude/plans/completed/beta-legacy-infra-cleanup/PLAN.md` (reference)
