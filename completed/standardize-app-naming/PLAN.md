# PLAN - Standardize App Stack Naming Convention

> Multi-project feature: `terraform` + `app`

## Objective

Remove the redundant `app-` prefix from the four main app stacks (`app-shared-001`, `app-atento-001`, `app-beta-001`, `app-demo-001`), aligning them with the 4Shark naming convention that uses the domain/client name directly. Document the convention in an ADR and a runbook. Migrate the two production stacks (shared and atento) using a parallel-cluster strategy to ensure zero downtime.

## Scope

### In Scope

- ADR-005: naming convention decision record
- Runbook: NAMING-CONVENTION.md with the convention rules and how to apply them
- `app-beta-001` → `beta-001`: rename directory + move S3 state key only (resources already correct)
- `app-demo-001` → `demo-001`: same as beta
- `app-shared-001` → `shared-001`: parallel cluster migration + refactor to modules + rename directory + move S3 state key
- `app-atento-001` → `atento-001`: same as shared
- `app` repo: update `deploy-shared-001.yaml` and `deploy-atento-001.yaml` (workflow env vars referencing old resource names)
- `app` repo: update `ENV-VARS.md` (SSM path table references `terraform/app-*` paths)
- `terraform` root `README.md`: update stack table and Mermaid diagram
- `terraform` `docs/runbooks/PENTEST-ACTIVATION.md`: update `app-beta-001` references
- Regenerate `README.md` in each renamed stack via terraform-docs
- Update `CHANGELOG.md` in `terraform` repo

### Out of Scope

- `app-atento-br`: do not touch
- S3 bucket names (`4shark-shared`, `4shark-atento-001`): persist as legacy
- MongoDB Atlas cluster names: persist as legacy
- SSM parameter paths: already correct (`/shared-001/`, `/atento-001/`), no change needed
- CloudWatch log groups for old resources: let 30-day TTL expire, do not delete manually
- IAM roles with `app-shared-001-*` / `app-atento-001-*` in their names: destroyed as part of cluster cleanup after swap

## Execution Phases

---

### Phase 1: Documentation — ADR + Runbook

**Objective**: Establish the naming convention as a recorded decision before any code changes. This makes the "why" traceable.

**Components**:
- `docs/adr/ADR-005-naming-convention.md`: Records the decision that stacks are named after the domain/client, not the tool. Documents the singleton vs. numbered-suffix rule. References the historical context (parallel cluster migration during EC2→ECS that introduced the `app-` prefix as a workaround).
- `docs/runbooks/NAMING-CONVENTION.md`: Operational reference. Convention rules, examples of correct and incorrect names, how to apply the convention when creating a new stack.

**Dependencies**: None. This phase can start immediately on a fresh feature branch.

**Success Criteria**:
- [ ] ADR-005 exists at `docs/adr/ADR-005-naming-convention.md`
- [ ] Runbook exists at `docs/runbooks/NAMING-CONVENTION.md`
- [ ] ADR covers: naming rule, singleton/numbered-suffix distinction, legacy exception policy (S3/MongoDB/SSM), historical context for `app-` prefix
- [ ] Runbook covers: convention table (current correct names), how to name a new stack, what "legacy" means

---

### Phase 2: Beta and Demo — Directory Rename + State Move

**Objective**: The cheapest renames: resources are already correct (`beta-001-cluster`, `demo-001-cluster`, etc.), only the directory name and the S3 state key are wrong.

**Components**:
- `app-beta-001/providers.tf`: change `key = "app-beta-001/terraform.tfstate"` → `key = "beta-001/terraform.tfstate"`
- Rename directory `app-beta-001/` → `beta-001/`
- Move S3 object: `app-beta-001/terraform.tfstate` → `beta-001/terraform.tfstate` in the Terraform state bucket
- `app-demo-001/providers.tf`: same change for `demo-001`
- Rename directory `app-demo-001/` → `demo-001/`
- Move S3 object: `app-demo-001/terraform.tfstate` → `demo-001/terraform.tfstate`
- Run `terraform init` in each renamed directory to confirm backend resolves
- Regenerate `README.md` in `beta-001/` and `demo-001/` via terraform-docs

**Dependencies**: Phase 1 complete (ADR in place).

**State move procedure** (per stack):
1. Copy S3 object from old key to new key (AWS CLI `s3 cp`)
2. Update `providers.tf` with new key
3. Run `terraform init -reconfigure` in new directory to confirm it picks up the correct state
4. Run `terraform plan` — must show zero changes
5. Delete old S3 object only after zero-change plan confirmed

**Success Criteria**:
- [ ] Directories renamed to `beta-001/` and `demo-001/`
- [ ] `providers.tf` in each points to new S3 key
- [ ] `terraform plan` shows zero changes for both stacks
- [ ] Old S3 keys deleted
- [ ] terraform-docs README regenerated

---

### Phase 3: Shared — Parallel Cluster Migration

**Objective**: Migrate `app-shared-001` to `shared-001` with zero downtime. This is the most complex phase: the code is monolithic (inline resources, hardcoded names), so refactoring to modules and renaming resources must happen together. The strategy is to create new resources in parallel while old ones remain live, swap the ALB, then destroy the old ones.

**Components**:

**3a — Refactor compute.tf to modular pattern**

The existing `compute.tf` (~999 lines) uses inline resources and hardcodes the `app-shared-001-*` prefix. It must be rewritten using the same module pattern as `app-beta-001/main.tf` (modules: `ecs_cluster`, `ecs_capacity`, `ecs_service`, `codedeploy`, `ecr`, `iam_deploy`, `public_alb`, `networking_data`). New resource names use `shared-001-*` prefix.

Files affected in `app-shared-001/`:
- `compute.tf`: replace all inline ECS resources with module calls using `shared-001-*` names
- `locals.tf`: update `env`, `role_name`, `ecs_instance_profile`, `sgname`, `service_with_alb` values from `app-shared-001-*` to `shared-001-*`
- Other `.tf` files: no structural changes in this phase, but any cross-references to locals must be checked

**3b — Parallel cluster: add new resources alongside old**

In a single Terraform plan, add the new modular blocks while keeping all existing inline resources untouched. The plan will show new resources being created; existing resources must not be modified or destroyed in this apply.

New resources created:
- `shared-001-cluster` (ECS cluster)
- `shared-001-ecs-sg` (security group)
- `shared-001-ecs-instance-role` / `shared-001-ecs-instance-profile`
- `shared-001-web-service`, `shared-001-worker-system-service`, `shared-001-worker-user-service`, `shared-001-worker-commission-service`, `shared-001-worker-commission-tiger-shark-service`, `shared-001-worker-commission-white-shark-service`
- `shared-001-runner` (ECS runner task definition)
- `shared-001-web-app` (CodeDeploy app), `shared-001-web-dg` (deployment group)
- ECR repos (if any new ones needed — existing `shared-001-app` ECR is already correctly named, so no new ECR needed)
- CloudWatch log groups `/ecs/shared-001-web`, `/ecs/shared-001-worker-*`

**3c — Traffic swap**

When all new services are healthy (ECS service stable, CodeDeploy deployment group registered):
- Modify the ALB target group rule to forward to the new `shared-001-web` target group
- This is the zero-downtime cutover

**3d — Destroy old resources**

After traffic swap confirmed and monitored for stability:
- Remove the old inline resource blocks from `compute.tf`
- Apply: destroys `app-shared-001-cluster`, `app-shared-001-ecs-sg`, `app-shared-001-*` roles, `app-shared-001-*` services, `app-shared-001-runner`, `app-shared-001-web-app`, `app-shared-001-web-dg`
- CloudWatch log groups `/ecs/app-shared-001-*`: do NOT delete — let TTL expire

**3e — State move + directory rename**

- Update `providers.tf`: `key = "app-shared-001/terraform.tfstate"` → `key = "shared-001/terraform.tfstate"`
- Move S3 state object: old key → new key
- Run `terraform init -reconfigure`
- Run `terraform plan` — must show zero changes
- Rename directory `app-shared-001/` → `shared-001/`
- Regenerate README via terraform-docs

**Dependencies**: Phase 2 complete. The parallel strategy means Phases 3 and 4 can be started in parallel once Phase 2 is done, but they should not be applied simultaneously (each requires focused human review and approval).

**Success Criteria**:
- [ ] `compute.tf` is fully modular — no inline ECS resource blocks, no hardcoded `app-shared-001-*` strings
- [ ] `terraform plan` for parallel-cluster apply shows only additions (no modifications, no destroys)
- [ ] All new `shared-001-*` ECS services reach STABLE state
- [ ] ALB swap completed and traffic flows through new services
- [ ] Monitoring (CloudWatch, Rollbar) shows no error spike post-swap
- [ ] Old `app-shared-001-*` resources destroyed (plan shows only destroys, apply confirmed)
- [ ] `terraform plan` after cleanup shows zero changes
- [ ] Directory renamed, S3 state moved, `terraform init -reconfigure` succeeds
- [ ] `terraform plan` from new directory shows zero changes

---

### Phase 4: Atento — Parallel Cluster Migration

**Objective**: Same as Phase 3, applied to `app-atento-001`. Atento has more workers than shared (adds `worker-commission-tiger-shark` and `worker-commission-white-shark`), so the service list is larger.

**Components**: Identical steps to Phase 3 (3a through 3e), with:
- All `app-shared-001-*` occurrences replaced by `atento-001-*`
- Additional workers: `atento-001-worker-commission-tiger-shark-service`, `atento-001-worker-commission-white-shark-service`
- ECR: `atento-001-app` already correctly named

**Dependencies**: Phase 2 complete. Can be worked in parallel with Phase 3 (separate stack, separate plan), but sequential is safer to limit blast radius.

**Success Criteria**: Same checklist as Phase 3, prefixed with `atento-001-*`.

---

### Phase 5: App Repo — Workflow Updates

**Objective**: Once the new infrastructure resources are live (after Phase 3 and 4 ALB swaps), update the GitHub Actions workflows so deployments target the new resource names.

**Components**:

**deploy-shared-001.yaml**:
- `CLUSTER_NAME`: `app-shared-001-cluster` → `shared-001-cluster`
- `WEB_SERVICE_NAME`: `app-shared-001-web` → `shared-001-web`
- `CODEDEPLOY_APP_NAME`: `app-shared-001-web-app` → `shared-001-web-app`
- `CODEDEPLOY_DEPLOYMENT_GROUP`: `app-shared-001-web-dg` → `shared-001-web-dg`
- `CODEDEPLOY_HOOK_LAMBDA_ARN`: `Lambda-app-shared-001-codedeploy-hook` → `Lambda-shared-001-codedeploy-hook`
- Workers JSON: all `app-shared-001-worker-*` → `shared-001-worker-*`, ASGs `app-shared-001-worker-*-asg` → `shared-001-worker-*-asg`

**deploy-atento-001.yaml**:
- Same pattern for all `app-atento-001-*` → `atento-001-*`
- Workers include tiger-shark and white-shark variants

**ENV-VARS.md** (in `app/.github/`):
- Update SSM path table: `terraform/app-shared-001/` → `terraform/shared-001/`, same for atento

**Timing constraint**: This phase must be applied after the new resources are live and before the old ones are destroyed. If deployed while old resources still exist, both old and new workflows work. If deployed before new resources exist, pipeline breaks.

**Dependencies**: Phase 3 ALB swap complete (shared-001 services live). Phase 4 ALB swap complete (atento-001 services live). Both must be done before this phase is applied.

**Success Criteria**:
- [ ] `deploy-shared-001.yaml` has zero references to `app-shared-001-*`
- [ ] `deploy-atento-001.yaml` has zero references to `app-atento-001-*`
- [ ] `ENV-VARS.md` SSM table updated
- [ ] A full deploy to shared-001 completes successfully post-change
- [ ] A full deploy to atento-001 completes successfully post-change

---

### Phase 6: Documentation Cleanup

**Objective**: Bring all documentation in sync after infrastructure and workflow changes are done.

**Components**:
- `terraform/README.md`: update stack table (rename `app-*` entries) and Mermaid diagram node names
- `terraform/docs/runbooks/PENTEST-ACTIVATION.md`: replace `app-beta-001` with `beta-001` (line 8, line 47, line 75)
- `app/.github/ENV-VARS.md`: already covered in Phase 5 — verify completeness
- `terraform/CHANGELOG.md`: add entry under the new unreleased version

**Dependencies**: Phases 3, 4, 5 complete.

**Success Criteria**:
- [ ] `terraform/README.md` contains no `app-shared-001`, `app-atento-001`, `app-beta-001`, or `app-demo-001` references
- [ ] `PENTEST-ACTIVATION.md` references `beta-001` not `app-beta-001`
- [ ] `CHANGELOG.md` updated
- [ ] `grep -r "app-shared-001\|app-atento-001\|app-beta-001\|app-demo-001" terraform/` returns only historical comments or the ADR (which documents the old names as legacy)

---

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| State migration method | AWS CLI `s3 cp` old key → new key, update `providers.tf`, `terraform init -reconfigure`, verify zero-change plan, then delete old key | Safest: no state is lost; old object remains until zero-change plan confirms new backend resolves correctly |
| Production migration strategy | Parallel cluster: add new resources → swap ALB → destroy old resources | Zero downtime. ECS does not allow renaming clusters in-place; this was the same technique used in the original EC2→ECS migration |
| Modularization approach | Follow exact pattern of `app-beta-001/main.tf` (modules: `ecs_cluster`, `ecs_capacity`, `ecs_service`, `codedeploy`, `ecr`, `iam_deploy`, `public_alb`, `networking_data`) | Beta and demo already work correctly with this pattern; shared and atento will reach the same baseline |
| CloudWatch log groups for old resources | Do not delete — let 30-day TTL expire | Preserves observability for any post-migration incident investigation |
| S3 bucket / Atlas cluster / SSM paths | Keep existing names as legacy | These are data-bearing resources; renaming them requires data migration with risk; the naming convention decision intentionally exempts persistent data resources |
| Phase ordering: beta/demo before shared/atento | Yes | Establishes that the rename procedure works end-to-end before touching production stacks |
| Phase 3 and Phase 4 sequencing | Sequential (not parallel) | Limits blast radius; each production migration needs focused review and approval |

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| State move leaves stack in broken state | High | Keep old S3 key until `terraform plan` shows zero changes from new key; rollback is: revert `providers.tf`, `terraform init -reconfigure` pointing back to old key |
| New cluster services fail to reach STABLE state | High | Old cluster remains live with traffic during phase 3b/3c; rollback is: destroy new resources (they never received traffic) |
| ALB swap causes traffic interruption | High | Validate new services are healthy (ECS stable, CodeDeploy deployment group active) before swap; monitor Rollbar and CloudWatch for 10 minutes post-swap before proceeding to cleanup |
| Lambda hook ARN name hardcoded in workflow | Medium | Lambda function `Lambda-app-shared-001-codedeploy-hook` must be renamed or a new one created before workflow update; verify Terraform manages this Lambda and that renaming is part of Phase 3 scope |
| Atento workers tiger-shark / white-shark missed | Medium | Explicit inventory: `worker-commission-tiger-shark`, `worker-commission-white-shark` are in scope; checklist in Phase 4 covers both |
| Drift between old and new compute.tf during parallel phase | Medium | Phase 3b plan must be reviewed to confirm zero modifications to existing resources before apply |
| beta-001/demo-001 brief downtime during state move | Low | Acceptable per scope; if zero downtime is required, schedule during off-hours |
| ADR references old names in historical context | Low | Expected and correct — ADR documents the legacy names explicitly as part of the decision record |

## Assumptions

- The Terraform state S3 bucket name and region are accessible via the default AWS profile (read) and 4shark-mfa profile (write).
- The Lambda function `Lambda-app-shared-001-codedeploy-hook` is managed by Terraform within `app-shared-001/compute.tf`; similarly for atento. If it is not, the Lambda rename is an additional out-of-scope step that must be flagged during Phase 3a review.
- GitHub Environments (`shared-001`, `atento-001`) already use the correct names (confirmed in `ENV-VARS.md` — only the Terraform stack path reference inside that doc is wrong).
- `terraform-docs` is available in the local environment to regenerate READMEs.
- The `app` repo is at `~/Projects/4Shark/app`; the `terraform` repo is at `~/Projects/4Shark/terraform`.
- No other repository (integrator, setup, etc.) references `app-shared-001-*` or `app-atento-001-*` resource names directly.
