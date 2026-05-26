# PLAN — Beta Legacy Infrastructure Cleanup

**Status:** COMPLETE
**Created:** 2026-02-10
**Completed:** 2026-02-18
**Projects:** terraform
**Environment:** beta-001 (us-east-1)

## Progress Summary

| Phase | Description | Status |
|-------|-------------|--------|
| 1 — DNS Verification | Cloudflare DNS check | DONE |
| 2 — Terraform: Remove Old Worker ASGs | PR to remove 7 ASGs + 7 LTs | SKIPPED (folders will be dropped entirely) |
| 3 — ALB Removal | Internal ALB + 2 TGs | DONE |
| 4 — EC2 Instances | Terminate legacy instances | DONE (3 of 3) |
| 5 — AMIs | Deregister worker AMIs | DONE |
| 6 — Elastic IP | Release EIP | DONE |
| 7 — Security Groups | Delete unused SGs | DONE (5 of 5) |
| 8 — EventBridge + Lambdas | Delete rule + 4 functions | DONE |
| 9 — IAM Roles + Policies | Delete 4 roles + 4 policies | DONE |
| 10 — CloudWatch Log Groups | Delete 12 legacy log groups | DONE |
| 11 — Validation | Terraform plan + health check | DONE |

## Current Situation

After the successful migration to ECS with dedicated ASGs and Lambda-managed autoscaling (completed 2026-02-10), several legacy resources remained in the beta-001 environment. Most have now been cleaned up.

### Active Infrastructure (KEEP)

| Resource | Type | Purpose |
|----------|------|---------|
| `beta-001-web` (2 instances) | EC2 (ECS) | ECS cluster instances |
| `beta-001-*-asg` (8 ASGs) | ASG | New dedicated ASGs |
| `beta-001-pub-lb` | ALB | Public load balancer |
| `beta-001-pub-tg` / `beta-001-pub-alt-tg` | TG | CodeDeploy blue/green |
| `beta-app001` (i-057a9e566ed594686) | EC2 | Kept (stopped) — user decision |
| `pgbouncer-beta-puma` (i-077d3c08becaf18ca) | EC2 | PGBouncer for Puma |
| `pgbouncer-beta-sidekiq` (i-08cba0c0dbeb8a311) | EC2 | PGBouncer for Sidekiq |
| `pgbouncer-beta` NLB + `nlbatg1-beta` TG | NLB | PGBouncer routing |
| `pritunl-beta-app0001` (i-03f3a7be5c6de8a69) | EC2 | VPN Client |
| AMI `pgbouncer-beta-puma` | AMI | PGBouncer base image |
| `pgbouncer-beta-sg` | SG | PGBouncer security group |
| `beta-001-pub-alb-*` | SG | Current ALB security group |
| `4Shark-Beta-APP` (sg-098ca9bc747d1b2bd) | SG | In use by beta-app001 |
| `/ecs/beta-001-*` (7 log groups) | CloudWatch | New ECS log groups |
| `beta-001-*` IAM roles (7) | IAM | New ECS roles |
| `Lambda-beta-001-*` (3 functions) | Lambda | New ECS autoscaling |
| `Lambda-beta-001-*` schedules (3) | EventBridge | New ECS autoscaling schedules |
| VPC `vpc-0968cc73edd5596b0` | VPC | Shared with new ECS infra |
| Subnets `Beta-prv-*` / `Beta-pub-*` | Subnet | Shared with new ECS infra |

### Remaining Legacy Resources

| Resource | Type | Status | Notes |
|----------|------|--------|-------|
| ~~7 `worker-beta-*` ASGs~~ | ASG | All desired=0 | **DELETED 2026-02-13 (AWS)** |
| ~~7 `worker-beta-*` Launch Templates~~ | LT | Unused | **DELETED 2026-02-13 (AWS)** |
| ~~`beta-app001` (i-057a9e566ed594686)~~ | EC2 | Terminated | **TERMINATED 2026-02-18** |
| ~~`4Shark-Beta-APP` (sg-098ca9bc747d1b2bd)~~ | SG | Deleted | **DELETED 2026-02-18** |

## Objective / Target State

- Remove all legacy EC2 instances, ASGs, launch templates, AMIs, and networking resources that are no longer needed
- Remove legacy Lambda functions, IAM roles/policies, and CloudWatch log groups
- Release Elastic IP
- Reduce monthly AWS costs
- Clean Terraform state to only contain active resources

### Success Criteria

- [x] Legacy Lambda functions deleted (4)
- [x] Legacy EventBridge rule deleted
- [x] Legacy IAM roles and policies deleted (4 + 4)
- [x] Legacy CloudWatch log groups deleted (12)
- [x] Worker AMIs deregistered (2) + snapshots deleted (2)
- [x] Old internal ALB and target groups removed
- [x] Elastic IP released
- [x] Legacy security groups removed (4 of 5 — `4Shark-Beta-APP` kept with beta-app001)
- [x] Legacy EC2 instances terminated (worker-image-beta, beta-puma-backup)
- [x] beta-app001 — **TERMINATED 2026-02-18** (cron migrated to ECS Scheduled Tasks, console replaced by `bin/ecs`)
- [x] No old worker ASGs (`worker-beta-*`) exist — **DELETED 2026-02-13 (AWS)**
- [x] No old launch templates (`worker-beta-*`) exist — **DELETED 2026-02-13 (AWS)**
- [x] `4Shark-Beta-APP` (sg-098ca9bc747d1b2bd) — **DELETED 2026-02-18**
- [x] Terraform code cleanup — old root Terraform files and `asg-launch-template` module removed (release 1.0.0, PR #143 merged 2026-02-13)

## Completed Phases

### Phase 1 — DNS Verification ✅ DONE
- Cloudflare has no A records pointing to 98.85.197.230
- Only CNAMEs: `beta` → webclient, `beta001` → `beta-001-pub-lb`
- EIP confirmed safe to release

### Phase 8 — EventBridge Rule + Lambda Functions ✅ DONE (2026-02-12)
- Removed 3 targets from `Lambda-beta-worker-auto-scaling-rule`
- Deleted rule `Lambda-beta-worker-auto-scaling-rule`
- Deleted `Lambda-beta-worker-auto-scaling-minor`
- Deleted `Lambda-beta-worker-auto-scaling-system`
- Deleted `Lambda-beta-worker-auto-scaling-user`
- Deleted `Lambda-beta-worker-auto-scaling-major`

### Phase 9 — IAM Roles + Policies ✅ DONE (2026-02-12)
- Cross-environment check: no dependencies from other environments
- 3 EventBridge policies had multiple versions — deleted v1 (non-default) before deleting policies
- Deleted roles + policies:
  - `Eventbridge-beta-invoke-minor-role` + `Eventbridge-beta-invoke-minor-policy`
  - `Eventbridge-beta-invoke-system-role` + `Eventbridge-beta-invoke-system-policy`
  - `Eventbridge-beta-invoke-user-role` + `Eventbridge-beta-invoke-user-policy`
  - `Lambda-beta-worker-auto-scaling-minor-role` + `Lambda-beta-worker-auto-scaling-minor-policy`

### Phase 10 — CloudWatch Log Groups ✅ DONE (2026-02-12)
Deleted 12 log groups:
1. `/ecs/beta-app001-task` (0 bytes, legacy)
2. `/ecs/beta-task` (0 bytes, legacy)
3. `/ecs/beta-worker-user` (0 bytes, legacy)
4. `/ecs/beta-worker_user` (0 bytes, legacy)
5. `/ecs/beta.app0001` (0 bytes, legacy)
6. `/ecs/betaapp001` (0 bytes, legacy)
7. `/ecs/beta_001_worker_cleansing` (86 MB, transitional — active service uses `/ecs/beta-001-worker-cleansing` with hyphens)
8. `/aws/lambda/Lambda-beta-worker-auto-scaling-minor` (Lambda auto-created)
9. `/aws/lambda/Lambda-beta-worker-auto-scaling-system` (Lambda auto-created)
10. `/aws/lambda/Lambda-beta-worker-auto-scaling-user` (Lambda auto-created)
11. `/aws/lambda/Lambda-beta-worker-auto-scaling-major` (Lambda auto-created)
12. `/aws/lambda/codedeploy-hook-lambda-beta` (orphaned — active function is `codedeploy-hook-lambda-beta-001`)

### Phase 5 — AMIs ✅ DONE (2026-02-12)
- Deregistered `worker-image-beta-v3.8.0` (ami-0c14bfdf210f61e06)
- Deregistered `worker-image-beta-v3.7.0` (ami-0bb13eede2776c00a)
- Deleted associated snapshots (2)

### Phase 4 — EC2 Instances ✅ DONE (partial) (2026-02-12)
- Terminated `worker-image-beta` (i-0f161420d6c52d262)
- Terminated `beta-puma-backup` (i-0aa46ae5eb981de1a)
- **KEPT** `beta-app001` (i-057a9e566ed594686) — user decision, stopped instance

### Phase 3 — ALB Removal ✅ DONE (2026-02-12)
- ALB `4Shark-Beta-dev-APP-LB` — internal, 0 targets in both TGs, created by Ivan 2025-11-16, not Terraform-managed
- Deleted ALB `4Shark-Beta-dev-APP-LB`
- Deleted TG `beta`
- Deleted TG `no-other`

### Phase 7 — Security Groups ✅ DONE (partial) (2026-02-12)
Dependency chain discovered and resolved:
- `default` SG (sg-0fcac894a61202d85) referenced `ecs-l8w0dg87` in ingress — revoked
- `4Shark-Beta-APP` (sg-098ca9bc747d1b2bd) referenced `ecs-instance-beta-app001` in ingress — revoked

Deleted SGs:
1. `4Shark-Beta-Web` (sg-065474bf0caf77666) — 0 ENIs
2. `4Shark-Beta-Worker` (sg-021c3388b2d932b8e) — ENI released after worker-image-beta termination
3. `ecs-instance-beta-app001` (sg-0e6d5e9b26c16d232) — 0 ENIs, 0 ingress rules, never used
4. `ecs-l8w0dg87` (sg-0feeef9d431815ddc) — "Created in ECS Console", 0 ENIs, migration artifact

**KEPT:** `4Shark-Beta-APP` (sg-098ca9bc747d1b2bd) — in use by beta-app001

### Phase 6 — Elastic IP ✅ DONE (2026-02-12)
- Disassociated EIP `4Shark-Staging-APP` (98.85.197.230) from beta-app001
- Released EIP (eipalloc-03151ca7a0d965374)

## Pending Phases — ALL COMPLETE

### Phase 2 — Terraform: Remove Old Worker ASGs — SKIPPED
ASGs and LTs were deleted directly from AWS on 2026-02-13. Old Terraform folders will be dropped entirely — no PR needed for code removal.

### Phase 11 — Validation ✅ DONE (2026-02-18)
- beta-app001 terminated (cron migrated to ECS Scheduled Tasks, console replaced by `bin/ecs`)
- `4Shark-Beta-APP` SG deleted
- No legacy `*-app0*` instances remaining (verified via AWS CLI)
- All legacy resources removed

## Challenges, Difficulties and Risks

### Technical
- Old worker ASGs are Terraform-managed — must be removed via Terraform PR, not manually
- ~~Module `asg-launch-template` is shared with atento/shared/demo~~ — **DELETED** (release 1.0.0, all environments migrated to standalone directories)
- VPC `vpc-0968cc73edd5596b0` is shared with new ECS infra — DO NOT DELETE

### Lessons Learned (Execution)
- SG deletion requires full dependency analysis — SGs can cross-reference each other in ingress/egress rules
- IAM policies with multiple versions require deleting non-default versions first
- Always show resource data/table before destructive operations for user confirmation
- `ecs-l8w0dg87` was not in original plan — discovered during SG analysis (ECS Console artifact)
- `no-other` TG was not in original plan — discovered as second TG on the ALB

## Internal References

- Terraform beta-001: `terraform/beta-001/` (standalone directory with S3 backend `4shark-terraform-state`)
- ~~Terraform root: `terraform/main.tf`~~ — **REMOVED** (release 1.0.0)
- ~~Terraform module: `terraform/modules/asg-launch-template/`~~ — **REMOVED** (release 1.0.0)
- ~~Terraform vars: `terraform/variables.tf`, `terraform/terraform.tfvars`~~ — **REMOVED** (release 1.0.0)
- Completed migration plan: `~/.claude/plans/completed/dedicated-asg-lambda-autoscaling/PLAN.md`
