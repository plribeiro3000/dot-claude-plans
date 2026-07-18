# PLAN — Onboarding idle-environment teardown

> Status: **COMPLETED** — applied and merged 2026-07-17 (terraform PR #765, dns PR #767).
> Repo: `terraform`. Environment: `onboarding` (us-east-1, account 405749097490).
> This plan was reconstructed after execution; the phases below record what was actually done.

## Objective

The `onboarding` environment is provisioned but not in use, so it bills for cost-bearing infrastructure that nothing consumes. Decommission that infrastructure while keeping a cheap "bring-back" skeleton and a retained restore point, so the environment can be recreated when it is actually needed.

## Scope

### In scope
- Scale both `onboarding` ECS services to zero (web, sidekiq).
- Destroy the cost-bearing infrastructure: public ALB, CodeDeploy blue/green machinery, both ECS services, the Redis Cloud subscription, the RDS PostgreSQL instance, and its cross-region disaster-recovery backup.
- Remove the now-dangling Cloudflare DNS record `onboarding.app4shark.com` and the load-balancer data source that fed it (`dns` stack).
- Retain a manual RDS snapshot as the restore point before dropping the database.

### Out of scope
- The `onboarding` application code and its GitHub Actions deploy pipeline (untouched).
- The in-progress dedicated-task-role IAM migration (steps 2/3 of the expand-contract in `iam_task_role.tf` / `ssm.tf`) — left as-is; the teardown only removed what it had to.
- Any other environment (`beta`, `demo`, `setup`, `shared-001`, integrators).

## Chosen approach

**Direction:** Drop the cost-bearing resources entirely (not "stop"), keep a thin bring-back skeleton, retain a manual snapshot.

**Rationale (from engineer):**
- "Stop the RDS" is not durable — AWS auto-restarts a stopped RDS instance after 7 days and storage keeps billing while stopped. The engineer chose **drop-with-snapshot**: the manual snapshot is the restore point, and compute/storage/PI/backup all go to zero.
- Task scaling did not need Terraform — `desired_count` is in `ignore_changes` on the `ecs_service` module (`modules/ecs_service/main.tf`), so scaling to zero via the CLI/skill produces no drift.
- Dropping the ALB forces the web service (wired to it via `ALB_HOSTNAME` and the target group) and CodeDeploy out too; the engineer chose the **thin skeleton** — remove those, but keep `var.services` so the ECR repository and its image survive, plus the cluster, deploy IAM, dedicated task role, and SSM parameters.
- The engineer chose to remove the Cloudflare CNAME in the same effort (it would otherwise point at a deleted ALB).

**Source patterns referenced:**
- `modules/ecs_service/main.tf` (`ignore_changes = [desired_count, task_definition, load_balancer]`) — why task-zero is drift-free.
- `modules/rds_instance/{main,variables}.tf` — `skip_final_snapshot` defaults to `false` and the module sets **no** `final_snapshot_identifier`, so a destroy would error; the manual-snapshot-then-`skip_final_snapshot=true` path avoids it.
- `onboarding/main.tf` — the ALB → CodeDeploy → web-service → ECR dependency chain that dictated the removal order.

## Execution phases

### Phase 0: Scale tasks to zero (no Terraform)

**Objective:** Stop the only compute that scaling can stop (the web Fargate task), with zero drift.

**Components:**
- `onboarding-web-service`: `desired_count` 1 → 0 (via `ecs-scale.sh`).
- `onboarding-sidekiq-service`: already 0.

**Dependencies:** none.

**Success criteria:**
- [x] Both services report `desired=0`.
- [x] No Terraform change required (`desired_count` in `ignore_changes`).

### Phase 1: Manual RDS snapshot

**Objective:** Capture the database as an independent restore point before any destructive step.

**Components:**
- `aws rds create-db-snapshot` → `onboarding-preteardown-20260717` (type: manual — survives outside the Terraform lifecycle).

**Dependencies:** MFA elevation (`4shark-mfa`).

**Success criteria:**
- [x] Snapshot status `available` (100%) before the database drop.

### Phase 2: Remove idle infra + disarm the database (terraform PR #765, apply 1)

**Objective:** Destroy the ALB, CodeDeploy, both ECS services, and the Redis Cloud subscription; make the RDS destroyable.

**Components:**
- Removed from `main.tf`: `module.public_alb`, `module.codedeploy_web`, `module.ecs_services`, the `local.services` enrichment, and the dead ALB naming locals; set `module.iam_deploy.enable_codedeploy = false`.
- Removed `redis.tf` (`module.redis_cloud`).
- Removed the ALB/CodeDeploy/Redis outputs from `output.tf`.
- `rds.tf`: `deletion_protection` true → false, added `skip_final_snapshot = true`.
- Kept: `var.services` (drives `module.ecr` + the image), the cluster, `aws_security_group.ecs_tasks`, deploy IAM, the dedicated task role, all SSM parameters.

**Dependencies:** Phase 1 snapshot available; PR open before apply (apply-before-merge).

**Success criteria:**
- [x] `terraform apply` → 0 add, **2 change** (deploy IAM policy, RDS disarm), **28 destroy**.

### Phase 3: Drop the database + cross-region backup (terraform PR #765, apply 2)

**Objective:** Destroy the RDS and its DR backup, now that deletion protection is off.

**Components:**
- Removed `rds.tf` (instance, subnet group, RDS security group), `backup.tf` (`module.backup`), and `monitoring_data.tf` (orphaned — only `backup.tf` used its remote-state data source).

**Dependencies:** Phase 2 applied (deletion protection false in AWS state).

**Success criteria:**
- [x] RDS, subnet group, RDS SG destroyed; `skip_final_snapshot=true` confirmed (no final snapshot — manual snapshot is the restore point).
- [x] Blocker surfaced: the two backup vaults failed to delete (`InvalidRequestException: Backup vault cannot be deleted because it contains recovery points`), leaving 2 vaults + 2 KMS keys in state. Resolved in Phases 4–5 (fix-forward on the same PR).

### Phase 4: Empty the backup vaults

**Objective:** Delete the recovery points so the vaults can be removed.

**Components:**
- 7 recovery points in `onboarding-local` (us-east-1) + 7 in `onboarding-dr` (us-west-2) — daily RDS backups/copies 2026-07-11 → 2026-07-17, all of the now-destroyed RDS. Deleted individually via `aws backup delete-recovery-point`.

**Dependencies:** engineer's explicit go (permanent backup-data deletion); the manual snapshot retained as the restore point.

**Success criteria:**
- [x] Both vaults report 0 recovery points; no delete errors.

### Phase 5: Remove the emptied vaults + KMS keys (terraform PR #765, apply 3)

**Objective:** Finish the backup teardown.

**Success criteria:**
- [x] `terraform apply` → **4 destroy** (2 vaults + 2 KMS keys).
- [x] Final state = thin skeleton only (cluster, ECR + image, deploy IAM, task role, `ecs_tasks` SG, 11 SSM parameters).
- [x] PR #765 consolidated to a single commit (`4989a2c`) and merged.

### Phase 6: Remove the DNS record (dns PR #767)

**Objective:** Remove the Cloudflare CNAME left pointing at the deleted ALB, and the `data.aws_lb.onboarding` source that referenced the gone ALB (which had broken the `dns` stack's plan).

**Components:**
- Removed `cloudflare_dns_record.onboarding_cname` (`public_dns_app4shark_com.tf`) and `data.aws_lb.onboarding` (`alb_data.tf`).

**Dependencies:** Phase 5 (ALB already gone). Rebased onto `develop` after PR #765 merged (CHANGELOG conflict resolved by keeping both entry sets).

**Success criteria:**
- [x] `terraform apply` → 1 destroy (the CNAME); a follow-up plan reports "No changes".
- [x] Rebased, force-pushed, merged.

## Technical decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| RDS: stop vs drop | Drop with retained manual snapshot | "Stop" auto-restarts in 7 days and keeps billing storage; drop-with-snapshot zeroes compute/storage/PI/backup and the snapshot is the restore point |
| Task scaling channel | CLI/skill, not Terraform | `desired_count` is in `ignore_changes` — scaling is drift-free without a PR |
| Bring-back skeleton size | Thin skeleton | Keep near-free ECR (+image), cluster, deploy IAM, task role, SSM; drop everything that bills. `var.services` kept so ECR survives |
| RDS destroy mechanics | Two applies (disarm, then drop) | AWS destroys an RDS only after an apply where `deletion_protection` is already false; the module has no `final_snapshot_identifier`, so `skip_final_snapshot=true` + a prior manual snapshot is the clean path |
| Backup vault removal | Delete recovery points, then destroy | A vault holding recovery points cannot be deleted; the 14 points were redundant copies of the idle DB, superseded by the manual snapshot |
| DNS record | Remove in the same effort | The CNAME would otherwise dangle at a deleted ALB, and the `data.aws_lb.onboarding` reference broke the `dns` stack plan |

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Data loss when dropping the RDS | High | Manual snapshot `onboarding-preteardown-20260717` taken and confirmed `available` before the drop |
| Terraform drift from scaling tasks outside Terraform | Low | `desired_count` is in `ignore_changes`; verified, no drift |
| Dropping the ALB cascades to the ECS services and the ECR image | Medium | `var.services` kept so `module.ecr` and the image survive; services removed deliberately (non-functional without the ALB) |
| Backup vault deletion blocked by recovery points | Medium | Surfaced as a blocker; fixed forward on the same PR (delete points → re-apply), never close-and-reopen |
| `dns` stack plan broken by the removed ALB | Medium | `data.aws_lb.onboarding` removed alongside the CNAME in PR #767 |
| Interrupting the in-progress task-role IAM migration | Low | Teardown removed only what it had to; the dedicated role stays referenced by `module.iam_deploy` and survives |

## Assumptions

- `onboarding` is genuinely idle — no traffic, no in-flight data that the daily backups uniquely hold beyond the manual snapshot.
- The manual snapshot is a sufficient restore point (the daily recovery points were redundant copies of the same idle DB).
- The kept skeleton (ECR image, IAM, SSM, cluster) is what a future reactivation will build on.

## Execution record

- **terraform PR #765** — `chore(onboarding): remove idle load balancer, deploy machinery, redis and database` — commit `4989a2c`, merged. Applied in 3 phases (28 + 12 + 4 destroys; RDS modified then destroyed).
- **dns PR #767** — `chore(dns): remove idle onboarding dns record` — commit `e662c27` (rebased), merged. 1 destroy.
- **Retained restore point:** manual RDS snapshot `onboarding-preteardown-20260717` (us-east-1).
- **Skeleton left in state:** `aws_ecs_cluster.this`, `module.ecr["onboarding-web"]` (+ image), `aws_iam_user.deploy` + access key + `module.iam_deploy` policy, `aws_iam_role.ecs_task_execution` (+ its 3 policies), `aws_security_group.ecs_tasks`, `aws_ssm_parameter.secrets[*]` (11), the two GitHub Actions environment secrets.

---

## Restore procedure — bringing `onboarding` back

When the environment is needed again, the code that described the removed resources is gone from `develop`, so bring-back is re-adding it plus a snapshot restore. Do it as its own PR, apply-before-merge, MFA-gated — same discipline as the teardown.

1. **Re-add the Terraform code.** Recreate, in the `onboarding` stack: the `local.services` enrichment + `module.ecs_services`, `module.public_alb`, `module.codedeploy_web`, `redis.tf` (`module.redis_cloud`), `rds.tf` (instance + subnet group + RDS SG), `backup.tf`, `monitoring_data.tf`, the removed `output.tf` outputs, and flip `module.iam_deploy.enable_codedeploy` back to `true`. The fastest starting point is `git revert` of PR #765's merge (then adjust the RDS block per step 2); the exact prior content is in the PR #765 diff. Keep `var.services` (it was never removed).

2. **Restore the RDS from the snapshot — this is the one non-mechanical step.** The `rds_instance` module has **no `snapshot_identifier` variable**, so a plain re-apply would create an EMPTY database, not restore the data. Two options:
   - Extend `modules/rds_instance` with a `snapshot_identifier` variable wired to `aws_db_instance.snapshot_identifier`, set it to `onboarding-preteardown-20260717`, and apply. (Cleaner; the variable can stay `null` for every other consumer.)
   - Or restore the snapshot to a new instance out-of-band (`aws rds restore-db-instance-from-db-snapshot`), then `terraform import` it into `module.rds_instance.aws_db_instance.this`. (No module change; more manual.)
   Either way, set `deletion_protection = true` and remove `skip_final_snapshot = true` once restored.

3. **Repoint the SSM parameters.** The SSM parameters were kept but their values are stale (`ignore_changes = [value]`, last set to the old endpoints). After the RDS and Redis come back with NEW endpoints, set the real values by hand:
   - `ONBOARDING_DATABASE_URL`, `MIGRATION_DATABASE_URL` → the restored RDS endpoint.
   - `REDIS_URL`, `REDIS_SIDEKIQ_URL`, `REDIS_LOCK_URL` → the new Redis Cloud endpoint (a re-added `module.redis_cloud` creates a fresh subscription with a new endpoint/password).
   Use `aws ssm put-parameter --name "/onboarding/<NAME>" --value "<value>" --type SecureString --overwrite`.

4. **Re-add the DNS record.** In the `dns` stack, recreate `data.aws_lb.onboarding` and `cloudflare_dns_record.onboarding_cname` (`git revert` of PR #767's merge). The CNAME will resolve to the NEW ALB's DNS name automatically via the data source.

5. **Scale the services up.** After the stack applies with the services defined, set the desired counts through the `/onboarding` skill (or `ecs-scale.sh`) — `desired_count` is in `ignore_changes`, so Terraform will not set it. Then trigger a deploy so the tasks pull the `onboarding-web` image (kept in ECR).

6. **Verify.** ALB health check green, web reachable at `onboarding.app4shark.com`, sidekiq processing, database reachable from the tasks (SSM values correct), and the cross-region backup plan active again.

**Note on the snapshot's lifetime:** the manual snapshot `onboarding-preteardown-20260717` is retained indefinitely until explicitly deleted. Do not delete it until a restore is confirmed working — it is the only copy of the pre-teardown data (the daily recovery points were deleted in Phase 4).
