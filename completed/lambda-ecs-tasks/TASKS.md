# TASKS — ECS Migration: Lambdas + App Workflows

> **Status:** In Progress
> **Scope:** Beta-001 first. Other environments will be addressed after beta validation is complete to avoid rework.

---

## Part 1: App Workflow Restructuring ✅ COMPLETE (Validated)

### Phase 1.1: Modify Existing Deploy Workflows ✅

- [x] **Modify `deploy-beta-001.yaml`** - Remove migration and cleansing workers
- [x] **Modify `deploy-demo-001.yaml`** - Remove migration and cleansing workers
- [x] **Modify `deploy-shared-001.yaml`** - Remove migration and cleansing workers
- [x] **Modify `deploy-atento-001.yaml`** - Remove migration and cleansing workers

### Phase 1.2: Create New Workflows ✅

- [x] **Create `deploy-service.yaml`** - Deploy and start a service (migration or cleansing)
- [x] **Create `stop-service.yaml`** - Stop a service

### Phase 1.3: Deploy-ECS Action Enhancement ✅

- [x] **Add `desired-count` parameter** - Optional parameter to set task count on deploy

### Phase 1.4: GitHub Environment Standardization ✅

- [x] **Create new environments** - beta-001, demo-001, shared-001, atento-001 (kebab-case)
- [x] **Copy variables** - 41 variables copied to beta-001
- [x] **Configure secrets** - 18 secrets configured in beta-001
- [x] **Update all workflows** - Use new environment names
- [x] **Delete old environments** - Beta001, Demo001, Shared001, Atento001

### Phase 1.5: Remaining Environment Configuration ⏳ (On-demand)

- [ ] **Configure demo-001** - Variables and secrets (when deploying)
- [ ] **Configure shared-001** - Variables and secrets (when deploying)
- [ ] **Configure atento-001** - Variables and secrets (when deploying)

### PRs Merged

- **PR #4730**: Workflow restructuring
- **PR #4731**: Environment standardization

---

## Part 2: Lambda Migration (PR #8 - In Progress)

### Phase 2.1: Initial Code Changes ✅ Done

- [x] Update Gemfiles - Replace `aws-sdk-autoscaling` with `aws-sdk-ecs`
- [x] Update Lambda code to use ECS API
- [x] Create `config.yml` for Balancing Lambda
- [x] Update `bin/generate_lambda` - Include config.yml
- [x] Create PR #8

### Phase 2.2: Lambda Renaming ✅ COMPLETE

Source code directories renamed:
- [x] Rename `worker-standard-scaling/` → `worker-standard-autoscaling/`
- [x] Rename `worker-commission-scaling-minor/` → `worker-commission-autoscaling/`
- [x] Rename `worker-commission-scaling-major/` → `worker-commission-balancing/`
- [x] Update README.md - New terminology
- [x] Update PERMISSIONS.md - New AWS resource names
- [x] Update CHANGELOG.md
- [x] Update all Lambda READMEs
- [x] Update all lambda_function.rb logs
- [x] Update bin/generate_lambda comment
- [x] Regenerate diagram (image.dot → image.svg)

**Commit:** `464e19d` (force pushed to PR #8)

### Phase 2.3: AWS IAM Roles/Policies Setup ⏳ In Progress

Create new IAM Roles and Policies with the new naming convention. All resources are isolated per environment (no global policies).

**Documentation:**
- `BLUEPRINT.md` - Complete migration plan with phases and cleanup checklist
- `IAM-NAMING-CONVENTION.md` - Naming standard
- `PLAN.md` section 4 - Execution steps

#### Resources to Create (Beta-001)

| Type | Name |
|------|------|
| Policy | `CloudWatch-beta-001-lambda-logs-policy` |
| Policy | `ECS-beta-001-lambda-worker-policy` |
| Policy | `EventBridge-beta-001-lambda-invoke-policy` |
| Role | `Lambda-beta-001-worker-commission-autoscaling-role` |
| Role | `Lambda-beta-001-worker-standard-autoscaling-role` |
| Role | `EventBridge-beta-001-scheduler-role` |

#### Resources to Remove (After Validation)

| Type | Name |
|------|------|
| Policy | `Lambda-beta-worker-auto-scaling-minor-policy` |
| Policy | `Eventbridge-beta-invoke-minor-policy` |
| Policy | `Eventbridge-beta-invoke-user-policy` |
| Policy | `Eventbridge-beta-invoke-system-policy` |
| Role | `Lambda-beta-worker-auto-scaling-minor-role` |
| Role | `Eventbridge-beta-invoke-minor-role` |
| Role | `Eventbridge-beta-invoke-user-role` |
| Role | `Eventbridge-beta-invoke-system-role` |

**Note:** Global policies (`Lambda-worker-auto-scaling-major-*`, `Lambda-worker-auto-scaling-standard-*`) only removed after ALL environments are migrated.

#### Scripts

- `setup-lambda-env.sh <env>` - Creates policies, roles, Lambdas, and schedules (all-in-one)
- `validate-lambda-env.sh <env>` - Validates all resources exist and are correctly configured

#### Progress (Beta-001)

- [ ] Phase 1: Run `setup-lambda-env.sh beta-001` (creates all resources automatically)
- [ ] Phase 1: Run `validate-lambda-env.sh beta-001` (validates all resources)
- [ ] Phase 2: Parallel operation (24-48h)
- [ ] Phase 3: Disable old Lambdas
- [ ] Phase 4: Remove old resources

**Other environments:** Will be addressed when migrating each environment to ECS.

### Phase 2.4: Create New Lambda Functions (Automated)

**Note:** The `setup-lambda-env.sh` script creates Lambdas automatically. This phase is tracked in Phase 2.3 Progress.

**beta-001 (3 Lambdas):**
- `Lambda-beta-001-worker-commission-autoscaling`
- `Lambda-beta-001-worker-user-autoscaling`
- `Lambda-beta-001-worker-system-autoscaling`

### Phase 2.5: EventBridge Scheduler Schedules (Automated)

**Note:** The `setup-lambda-env.sh` script creates schedules automatically. This phase is tracked in Phase 2.3 Progress.

**beta-001 (3 Schedules):**
- `Lambda-beta-001-worker-commission-autoscaling-schedule`
- `Lambda-beta-001-worker-user-autoscaling-schedule`
- `Lambda-beta-001-worker-system-autoscaling-schedule`

### Phase 2.6: Validation ⏳ Pending

- [ ] Verify ECS services scale up/down correctly in beta-001
- [ ] Check CloudWatch Logs for errors
- [ ] Monitor 24-48h before rolling to other environments

---

## Summary (Beta-001 Scope)

| Item | Count | Status |
|------|-------|--------|
| Deploy workflows modified | 4 | ✅ |
| New workflows created | 2 | ✅ |
| GitHub Environments configured | 1 (beta-001) | ✅ |
| Lambda directories renamed | 3 | ✅ |
| Lambda documentation updated | 6 | ✅ |
| IAM Policies to create (beta-001) | 3 | ⏳ |
| IAM Roles to create (beta-001) | 3 | ⏳ |
| New Lambdas to create (beta-001) | 3 | ⏳ |
| EventBridge Scheduler schedules to create (beta-001) | 3 | ⏳ |

**Note:** Other environments will be addressed after beta-001 validation is complete.

---

## Next Steps (Beta-001)

See `BLUEPRINT.md` for detailed commands and checklist.

**Phase 1: Create New Resources**
1. Run `setup-lambda-env.sh beta-001` - Creates policies, roles, Lambdas, and schedules
2. Run `validate-lambda-env.sh beta-001` - Validates all resources

**Phase 2: Parallel Operation (24-48h)**
3. Monitor new Lambdas in CloudWatch Logs
4. Verify ECS services scale correctly

**Phase 3: Disable Old Lambdas**
5. Remove old Lambda targets from legacy EventBridge rule
6. Monitor for 24h

**Phase 4: Remove Old Resources**
7. Delete old Lambdas
8. Detach policies from roles
9. Delete roles
10. Delete policies
11. Delete legacy EventBridge rule

**After Beta-001:** Repeat for other environments when migrating to ECS

---

## Reference

- **Lambda PR #8**: https://github.com/4shark/lambda/pull/8
- **App PR #4730**: Workflow restructuring
- **App PR #4731**: Environment standardization
