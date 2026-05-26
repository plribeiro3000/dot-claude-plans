# Dedicated ASG per Process + Lambda-Managed Autoscaling

## Problem Statement

The current ECS infrastructure uses a single shared Auto Scaling Group (ASG) for all processes. This causes three critical issues:

1. **Cross-process interference**: Scaling down one process (e.g., audit finishes) terminates EC2 instances used by another process (e.g., commission still processing), killing running tasks without graceful shutdown.
2. **15-minute idle cost**: After tasks finish, EC2 instances sit idle for ~15 minutes waiting for the ECS Capacity Provider's managed draining/scaling to terminate them. For burst workloads (1-2 min processing), this means paying for ~17 minutes per ~1 minute of actual use.
3. **Deploy forces desired-count=1**: The deploy workflow hardcodes `desired-count: '1'` for all services, spinning up instances even when no work is pending (homologation environments with min=0).

## Solution

- **Dedicated ASG per ECS service**: Each process gets its own ASG + Launch Template + Capacity Provider, isolating scaling decisions.
- **Lambda manages both ECS Service and ASG**: On scale-up AND scale-down, the Lambda controls both the ECS desired_count and the ASG desired_capacity.
- **Capacity Provider with managed_scaling DISABLED** (for workers): CP only provides the instance-to-task mapping. Lambda is the sole manager of ASG capacity.
- **Web service keeps managed_scaling ENABLED**: Web always runs (desired=1), uses CodeDeploy blue/green which needs CP to provision a second instance during deployment.
- **Deploy preserves current desired_count**: Remove hardcoded `desired-count: '1'` from worker deploy steps.

## Service Inventory — Final State (after all phases)

| Service | desired_count | Lambda | ASG Management | CP managed_scaling |
|---------|--------------|--------|----------------|-------------------|
| web | 1 | None | CP (CodeDeploy) | ENABLED |
| worker-system | 1 | worker-system-autoscaling | Lambda | DISABLED |
| worker-user | 1 | worker-user-autoscaling | Lambda | DISABLED |
| worker-commission | 1 | worker-commission-autoscaling | Lambda | DISABLED |
| worker-commission-tiger-shark | 0 | worker-commission-balancing | Lambda | DISABLED |
| worker-commission-white-shark | 0 | worker-commission-balancing | Lambda | DISABLED |
| worker-cleansing | 0 | None | Manual | DISABLED |
| worker-migration | 0 | None | Manual | DISABLED |

## Revision Log

Items marked with `[REVISED]` were discovered during implementation and added after the original plan was reviewed. If you already read the original version, search for `[REVISED]` to find only what changed.

| Phase | What changed | Why |
|-------|-------------|-----|
| Phase 2 — item 2 | `aws_ecs_cluster_capacity_providers` must be moved out of `ecs_cluster` module | Circular dependency: new `ecs_capacity` modules depend on `ecs_cluster` outputs, and vice-versa |
| Phase 2 — Execution Order | Added `terraform state mv` step before apply | Moving the resource in code without moving it in state causes Terraform to destroy and recreate it, briefly deregistering all CPs from the cluster |
| Phase 2 — Tags | Added `tag_specifications` block to Launch Template + enriched tags per capacity module | Today `tags` on the Launch Template only tags the LT resource itself — it does not propagate to EC2 instances. Additionally, ECS instances had almost no tags (only `Name` and sometimes `Environment`), while Ansible instances in sa-east-1 have a well-defined pattern (`Name`, `Automation`, `Role`, `Type`, `Client`). The new tags align ECS instances with the same pattern: `Environment`, `Automation=terraform`, `Role` (web/worker), `Service` (system/commission/etc.), `Cluster`. |
| Phase 2 — Environment naming | Changed `var.environment` from `"beta"` to `"beta-001"` and removed all hardcoded `-001` from interpolations | The requirement is to support multiple clusters per environment (e.g., `shared-001`, `shared-002`, `atento-001`, `atento-002`). Having `var.environment = "beta"` with `-001` hardcoded across ~400 occurrences in `.tfvars`, `main.tf`, and modules makes it impossible to create a second cluster without duplicating and editing every file. With `var.environment = "beta-001"`, the cluster identity is a single variable — creating `shared-002` is just `var.environment = "shared-002"`. This also required removing unused environment directories (`atento/`, `demo/`, `poc/`, `shared/`) that contained the same hardcoding problem and were never validated. Impact: 4 resources are destroyed and recreated with correct names (3 CodeDeploy hook Lambda resources + 1 IAM deploy policy) — all non-critical, zero downtime. Also requires creating GitHub environment variables for `beta-001` and updating `deploy-beta-001.yaml` to use `${{ vars.* }}` instead of hardcoded values. |
| Phase 3 — Web service | Web service requires destroy + recreate instead of in-place update | AWS API does not allow changing `capacity_provider_strategy` on ECS services with `CODE_DEPLOY` deployment controller. This is an API limitation, not a Terraform limitation. Workers (rolling update) migrated fine. Web service must be destroyed and recreated with the dedicated CP and CODE_DEPLOY configured from scratch. Brief downtime on beta (acceptable — test environment not actively in use). |
| Phase 5 — IAM | Added `autoscaling:UpdateAutoScalingGroup` policy for Lambda roles | The v0.5.0 Lambda code calls `autoscaling:UpdateAutoScalingGroup` to manage ASG capacity, but the IAM roles only had ECS permissions. Discovered during Phase 7 validation when Lambdas failed with `AccessDeniedException`. Applies to all 3 roles (standard, commission, balancing). |

---

## Current Status

**Last updated:** 2026-02-10 — **COMPLETED**

| Phase | Status | Notes |
|-------|--------|-------|
| Phase 0 | ✅ Complete | Deploy workflow updated |
| Phase 1 | ✅ Complete | Lambdas disabled, workers at 0 |
| Phase 2 | ✅ Complete | Terraform applied. `state mv` + `apply` done on 2026-02-10. |
| Phase 3 | ✅ Complete | Workers migrated via in-place update. Web service required destroy + recreate (AWS API limitation with CODE_DEPLOY). |
| Phase 4 | ✅ Complete | Shared ASG + CP removed |
| Phase 5 | ✅ Complete | v0.5.0 published to S3. Env vars set. Lambda code deployed. IAM policy applied (PR terraform #119). |
| Phase 6 | ✅ Complete | Schedulers re-enabled via Terraform (`lambda_scheduler_state=ENABLED`). |
| Phase 7 | ✅ Complete | worker-system: scale-up 0→1 (318 jobs), processed in ~2 min, histerese 3x1 min, scale-down to 0, EC2 terminated in 52 sec. worker-user and worker-commission stable at 0 (no jobs). |
| Phase 8 | ✅ Complete | Shared ASG variables removed from beta (PR terraform #120 merged). Module `ecs_cluster` retains `create_asg` flag until all environments migrate. |

### Issues Found During Migration

| Issue | Resolution |
|-------|-----------|
| `CODEDEPLOY_HOOK_LAMBDA_ARN` hardcoded with old name in deploy workflow | Migrated all 7 env vars to `${{ vars.* }}` (app PR #4794, merged) |
| ALB listeners pointing to empty TG after incomplete CodeDeploy blue/green | Fixed via CLI: redirected listeners to alt-tg where primary taskset was. Terraform PR #118 added `ignore_changes [default_action]` to prevent drift. |
| IAM roles missing `autoscaling:UpdateAutoScalingGroup` permission | Created policy + attachments for all 3 roles (terraform PR #119) |

### Remaining PRs

| Repository | PR | Description | Status |
|------------|-----|-------------|--------|
| terraform | [#114](https://github.com/4shark/terraform/pull/114) | Dedicated ASGs per service + environment naming cleanup | Awaiting merge |
| app | [#4788](https://github.com/4shark/app/pull/4788) | Remove unused deploy workflows | Awaiting merge |
| lambda | [#21](https://github.com/4shark/lambda/pull/21) | Scale-up with ASG update | Awaiting merge |
| terraform | [#119](https://github.com/4shark/terraform/pull/119) | IAM policy for Lambda autoscaling roles | Awaiting merge |

### Beta-001 Migration Complete

All 8 phases completed on 2026-02-10. Next environment: demo.

---

## Migration Strategy

The migration is designed for **zero downtime** and **full reversibility between phases**.

Before any infrastructure change, all Lambda schedulers are disabled and worker services are scaled to zero. This eliminates any possibility of conflict between the Capacity Provider and the Lambda during migration. All new worker Capacity Providers are created with their final configuration (`managed_scaling: DISABLED`) from the start — no temporary states.

Each phase produces a well-defined expected state. After each phase, the expected state must be validated before proceeding. If a phase fails, it can be reverted to the previous phase's state, the issue can be diagnosed, and the phase can be retried or the plan can be adjusted.

---

## Phase 0: App — Remove forced desired-count from deploy

**Repository**: `app`
**Risk**: Low
**Downtime**: None

### Changes

Remove `desired-count: '1'` from worker deploy steps in the deploy workflow (`deploy-beta-001.yaml`). The `deploy-ecs` action already supports omitting this parameter — when not provided, `aws ecs update-service` runs without `--desired-count`, preserving the current value.

### Behavior After Change

- If service has desired_count=0: deploy updates task definition only, no tasks launched, no EC2 needed.
- If service has desired_count=15: deploy performs rolling update of all 15 tasks with the new image.
- If service has desired_count=1: deploy replaces the running task with the new version.

### Validation

```bash
# Before deploy: record current desired_count for each service
aws ecs describe-services --cluster beta-001-cluster \
  --services beta-001-worker-system-service beta-001-worker-user-service \
  beta-001-worker-commission-service \
  --query 'services[].{name:serviceName,desired:desiredCount}'

# Execute deploy

# After deploy: verify desired_count is unchanged
# Same command — values must be identical
```

### Expected State After Phase 0

No infrastructure changes. Deploy workflow no longer forces desired-count=1 on workers.

| Component | State |
|-----------|-------|
| Lambda schedulers | Enabled (unchanged) |
| Worker services | Same desired_count as before deploy |
| ASG | Shared, unchanged |
| Capacity Providers | Single shared CP, unchanged |

### Recovery

Restore `desired-count: '1'` in the workflow.

---

## Phase 1: Preparation — Disable Lambdas + scale workers to zero

**Repository**: None (AWS CLI operations)
**Risk**: Low
**Downtime**: None (staging environment, not actively processing)

### Changes

1. **Disable all Lambda EventBridge schedulers** to prevent Lambda executions during infrastructure changes.
2. **Scale all worker services to desired_count=0** to ensure no running tasks during migration.
3. **Wait for all tasks to drain** and confirm no tasks are running.

Web service is NOT affected — it continues running normally.

### Commands

```bash
# 1. Disable Lambda schedulers
for scheduler in $(aws scheduler list-schedules --query 'Schedules[?contains(Name,`beta`)].Name' --output text); do
  echo "Disabling $scheduler"
  aws scheduler update-schedule --name $scheduler --state DISABLED \
    --flexible-time-window '{"Mode":"OFF"}' \
    --schedule-expression "$(aws scheduler get-schedule --name $scheduler --query 'ScheduleExpression' --output text)" \
    --target "$(aws scheduler get-schedule --name $scheduler --query 'Target' --output json)"
done

# 2. Scale worker services to 0
for svc in beta-001-worker-system-service beta-001-worker-user-service \
  beta-001-worker-commission-service beta-001-worker-commission-tiger-shark-service \
  beta-001-worker-commission-white-shark-service beta-001-worker-cleansing-service \
  beta-001-worker-migration-service; do
  echo "Scaling $svc to 0"
  aws ecs update-service --cluster beta-001-cluster --service $svc --desired-count 0
done

# 3. Wait for tasks to drain
aws ecs wait services-stable --cluster beta-001-cluster \
  --services beta-001-worker-system-service beta-001-worker-user-service \
  beta-001-worker-commission-service
```

### Validation

```bash
# Verify schedulers are disabled
aws scheduler list-schedules --query 'Schedules[?contains(Name,`beta`)].{name:Name,state:State}'

# Verify all worker services at desired=0 with 0 running tasks
aws ecs describe-services --cluster beta-001-cluster \
  --services beta-001-worker-system-service beta-001-worker-user-service \
  beta-001-worker-commission-service \
  --query 'services[].{name:serviceName,desired:desiredCount,running:runningCount}'

# Verify web is still running
aws ecs describe-services --cluster beta-001-cluster \
  --services beta-001-web-service \
  --query 'services[0].{name:serviceName,desired:desiredCount,running:runningCount}'
```

### Expected State After Phase 1

| Component | State |
|-----------|-------|
| Lambda schedulers | **DISABLED** |
| Worker services | desired_count=0, running_count=0 |
| Web service | desired_count=1, running (unchanged) |
| ASG (shared) | Instances draining as tasks stop |
| Capacity Providers | Single shared CP, unchanged |

### Recovery

Re-enable Lambda schedulers. Lambdas will detect queue state and scale services accordingly.

```bash
for scheduler in $(aws scheduler list-schedules --query 'Schedules[?contains(Name,`beta`)].Name' --output text); do
  aws scheduler update-schedule --name $scheduler --state ENABLED \
    --flexible-time-window '{"Mode":"OFF"}' \
    --schedule-expression "$(aws scheduler get-schedule --name $scheduler --query 'ScheduleExpression' --output text)" \
    --target "$(aws scheduler get-schedule --name $scheduler --query 'Target' --output json)"
done
```

---

## Phase 2: Terraform Apply 1 — Create dedicated ASGs + Capacity Providers

**Repository**: `terraform`
**Risk**: None (only creates new resources, does not modify existing)
**Downtime**: None

### Changes

1. **Create `ecs_capacity` module**: New module at `modules/ecs_capacity/`. Inputs: name, AMI, instance type, subnets, security groups, CP configuration (managed_scaling, managed_draining). Creates: Launch Template + ASG + Capacity Provider. Outputs: CP name, ASG name/ARN.

2. `[REVISED]` **Move `aws_ecs_cluster_capacity_providers` out of `ecs_cluster` module**: The resource that registers Capacity Providers on the cluster currently lives inside `modules/ecs_cluster/main.tf`. It must be moved to `beta/main.tf` because the new `ecs_capacity` modules depend on `ecs_cluster` outputs (cluster name, security group), and `ecs_cluster` cannot simultaneously depend on `ecs_capacity` outputs (CP names) — this would create a circular dependency.

3. **Instantiate 8 capacity modules in `beta/main.tf`** with their final configuration:

   | Module | managed_scaling | managed_draining | Notes |
   |--------|----------------|-----------------|-------|
   | capacity_web | ENABLED | ENABLED | CodeDeploy needs automatic instance provisioning |
   | capacity_worker_system | DISABLED | DISABLED | Lambda manages |
   | capacity_worker_user | DISABLED | DISABLED | Lambda manages |
   | capacity_worker_commission | DISABLED | DISABLED | Lambda manages |
   | capacity_worker_commission_tiger_shark | DISABLED | DISABLED | Lambda manages |
   | capacity_worker_commission_white_shark | DISABLED | DISABLED | Lambda manages |
   | capacity_worker_cleansing | DISABLED | DISABLED | Manual (infra prepared for future Lambda) |
   | capacity_worker_migration | DISABLED | DISABLED | Manual (infra prepared for future Lambda) |

   All ASGs: same AMI, instance type (t3a.medium), subnets, security group, user_data (`ECS_CLUSTER=beta-001-cluster`). All instances register to the same ECS cluster.

4. **Register all CPs on the cluster** via the relocated `aws_ecs_cluster_capacity_providers` resource in `beta/main.tf`: shared CP + 8 new dedicated CPs.

5. **Do NOT modify ECS services** — they continue referencing the shared CP.

6. `[REVISED]` **Enrich instance tags and add `tag_specifications` to Launch Template**: Add `tag_specifications { resource_type = "instance" }` block to propagate tags to EC2 instances. Each capacity module receives specific tags following the Ansible pattern from sa-east-1:

   | Tag | Web example | Worker example |
   |-----|-------------|----------------|
   | Environment | beta-001 | beta-001 |
   | Automation | terraform | terraform |
   | Role | web | worker |
   | Service | web | system |
   | Cluster | beta-001 | beta-001 |

7. `[REVISED]` **Change `var.environment` from `"beta"` to `"beta-001"`**: Remove all hardcoded `-001` from string interpolations in `beta/main.tf` (9 occurrences), `modules/codedeploy/main.tf` (4 occurrences), and `beta.tfvars` (`cluster_name = "cluster"` instead of `"001-cluster"`). Remove unused environment directories (`atento/`, `demo/`, `poc/`, `shared/`). This causes 4 resources to be destroyed and recreated with corrected names:

   | Resource | Old name | New name |
   |----------|----------|----------|
   | CodeDeploy Hook Lambda Role | `codedeploy-hook-lambda-role-beta` | `codedeploy-hook-lambda-role-beta-001` |
   | CodeDeploy Hook Lambda Policy | `codedeploy-hook-lambda-policy-beta` | `codedeploy-hook-lambda-policy-beta-001` |
   | CodeDeploy Hook Lambda Function | `codedeploy-hook-lambda-beta` | `codedeploy-hook-lambda-beta-001` |
   | IAM Deploy Policy | `app-staging-deploy-beta` | `app-staging-deploy-beta-001` |

8. `[REVISED]` **Create GitHub environment variables for `beta-001`** and update `deploy-beta-001.yaml` to use `${{ vars.* }}` instead of hardcoded values. Remove deploy workflows for non-validated environments (`deploy-atento-001.yaml`, `deploy-shared-001.yaml`, `deploy-demo-001.yaml`, `deploy-bluegreen-poc.yaml`).

### Execution Order `[REVISED]`

After merging the code changes, the following steps must be executed in order:

```bash
# Step 1: terraform init (download new module)
cd beta/
terraform init

# Step 2: Move the capacity providers resource in state
# This tells Terraform the resource moved from inside the module to outside.
# Only changes the state file in S3 — does NOT touch AWS infrastructure.
terraform state mv \
  module.ecs_cluster.aws_ecs_cluster_capacity_providers.this \
  aws_ecs_cluster_capacity_providers.this

# Step 3: Plan — verify what Terraform will do
terraform plan -var-file=beta.tfvars
# Expected:
#   - 4 to destroy + 4 to create (CodeDeploy hook Lambda role/policy/function + IAM deploy policy — renamed from *-beta to *-beta-001)
#   - aws_ecs_cluster_capacity_providers.this: UPDATE in-place (adding 8 new CPs)
#   - 24 to add (8x Launch Template + 8x ASG + 8x Capacity Provider)
#   - Tag updates in-place on VPC resources (Name tags: vpc-beta → vpc-beta-001, etc.)
#   - NO changes to ECS cluster, ECS services, or existing shared ASG/CP names

# Step 4: Apply
terraform apply -var-file=beta.tfvars

# Step 5: Create GitHub environment variables (after apply, ARNs are live)
gh variable set CLUSTER_NAME --env beta-001 --repo 4shark/app --body "beta-001-cluster"
gh variable set ENVIRONMENT --env beta-001 --repo 4shark/app --body "beta-001"
gh variable set WEB_SERVICE_NAME --env beta-001 --repo 4shark/app --body "beta-001-web"
gh variable set WEB_ECR_REPO --env beta-001 --repo 4shark/app --body "405749097490.dkr.ecr.us-east-1.amazonaws.com/beta-001-web"
gh variable set CODEDEPLOY_APP_NAME --env beta-001 --repo 4shark/app --body "beta-001-web-app"
gh variable set CODEDEPLOY_DEPLOYMENT_GROUP --env beta-001 --repo 4shark/app --body "beta-001-web-dg"
gh variable set CODEDEPLOY_HOOK_LAMBDA_ARN --env beta-001 --repo 4shark/app --body "arn:aws:lambda:us-east-1:405749097490:function:codedeploy-hook-lambda-beta-001"
```

> **Important**: If step 2 (`state mv`) is skipped, Terraform will destroy the `aws_ecs_cluster_capacity_providers` at the old address and create it at the new address. This causes a brief window where no CPs are registered on the cluster. The `state mv` prevents this by moving the resource address without any infrastructure change.
>
> **Important**: Step 5 (GitHub env vars) must be done BEFORE merging the app workflow PR that references `${{ vars.* }}`. Otherwise the workflow would read empty variables. The order is: Terraform apply → GitHub env vars → merge app PR.

### Validation

```bash
# Verify new CPs exist with correct managed_scaling configuration
aws ecs describe-capacity-providers \
  --query 'capacityProviders[?contains(name,`beta-001`)].{name:name,scaling:autoScalingGroupProvider.managedScaling.status,draining:autoScalingGroupProvider.managedDraining}'

# Verify all CPs registered on the cluster (old + 8 new)
aws ecs describe-clusters --clusters beta-001-cluster \
  --query 'clusters[0].capacityProviders'

# Verify new ASGs exist (all at desired=0)
aws autoscaling describe-auto-scaling-groups \
  --query 'AutoScalingGroups[?contains(AutoScalingGroupName,`beta-001-worker`) || contains(AutoScalingGroupName,`beta-001-web`)].{name:AutoScalingGroupName,min:MinSize,max:MaxSize,desired:DesiredCapacity}'

# Verify services still on old CP (unchanged)
aws ecs describe-services --cluster beta-001-cluster \
  --services beta-001-worker-system-service \
  --query 'services[0].capacityProviderStrategy[0].capacityProviderName'
# Expected: beta-001-capacity-provider (old shared CP)
```

### Expected State After Phase 2

| Component | State |
|-----------|-------|
| Lambda schedulers | DISABLED |
| Worker services | desired_count=0, still on **shared CP** |
| Web service | desired_count=1, still on **shared CP** |
| ASG (shared) | Still exists, may have web instance |
| **New ASGs (8x)** | **Created, desired=0, empty** |
| **New CPs (8x)** | **Created, registered on cluster** |
| Worker CPs | **managed_scaling=DISABLED, managed_draining=DISABLED** |
| Web CP | **managed_scaling=ENABLED, managed_draining=ENABLED** |

### Recovery

Remove the new modules from Terraform and apply. New resources are destroyed, services remain on shared CP unchanged. If the `state mv` needs to be reverted: `terraform state mv aws_ecs_cluster_capacity_providers.this module.ecs_cluster.aws_ecs_cluster_capacity_providers.this`.

---

## Phase 3: Terraform Apply 2 — Migrate services to dedicated Capacity Providers

**Repository**: `terraform`
**Risk**: Low (worker services at desired=0, no tasks to move)
**Downtime**: None

### Changes

Update each ECS service's `capacity_provider_strategy` to reference its dedicated CP.

```hcl
# Before
capacity_provider = var.capacity_provider_name  # shared: beta-001-capacity-provider

# After (per service)
capacity_provider = module.capacity_worker_system.capacity_provider_name  # dedicated
```

### What Happens Internally

For worker services (all at desired_count=0): No tasks to move. ECS updates the service's CP reference. No rolling update, no instances needed.

For web service (desired_count=1): ECS triggers a rolling update. The new web CP has `managed_scaling: ENABLED`, which provisions an instance in the dedicated web ASG. New task starts on the new instance, old task drains from shared ASG instance.

### Validation

```bash
# Verify each service uses its dedicated CP
for svc in beta-001-web-service beta-001-worker-system-service beta-001-worker-user-service \
  beta-001-worker-commission-service beta-001-worker-commission-tiger-shark-service \
  beta-001-worker-commission-white-shark-service beta-001-worker-cleansing-service \
  beta-001-worker-migration-service; do
  echo "=== $svc ==="
  aws ecs describe-services --cluster beta-001-cluster --services $svc \
    --query 'services[0].{service:serviceName,cp:capacityProviderStrategy[0].capacityProviderName,desired:desiredCount,running:runningCount}'
done

# Verify web task is running on new web ASG instance
aws ecs list-tasks --cluster beta-001-cluster --service-name beta-001-web-service \
  --query 'taskArns[0]' --output text | \
  xargs -I {} aws ecs describe-tasks --cluster beta-001-cluster --tasks {} \
  --query 'tasks[0].containerInstanceArn' --output text | \
  xargs -I {} aws ecs describe-container-instances --cluster beta-001-cluster \
  --container-instances {} --query 'containerInstances[0].ec2InstanceId'

# Verify shared ASG is draining (web instance moved to dedicated ASG)
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names beta-001-asg \
  --query 'AutoScalingGroups[0].{desired:DesiredCapacity,instances:Instances[*].InstanceId}'
```

### Expected State After Phase 3

| Component | State |
|-----------|-------|
| Lambda schedulers | DISABLED |
| Worker services | desired_count=0, on **dedicated CPs** |
| Web service | desired_count=1, running on **dedicated web CP** |
| ASG (shared) | **Draining / empty** (no services reference it) |
| Web ASG | **1 instance** (web task running) |
| Worker ASGs | **0 instances** (no tasks) |

### Recovery

Change services back to the shared CP in Terraform and apply. Web task migrates back to shared ASG via rolling update.

---

## Phase 4: Terraform Apply 3 — Remove shared ASG + Capacity Provider

**Repository**: `terraform`
**Risk**: Low (resources already unused)
**Downtime**: None

### Pre-conditions

```bash
# Confirm shared ASG has no instances
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names beta-001-asg \
  --query 'AutoScalingGroups[0].{desired:DesiredCapacity,instances:Instances}'
# Expected: desired=0, instances=[]

# Confirm no service references the old CP
aws ecs describe-services --cluster beta-001-cluster \
  --services beta-001-web-service beta-001-worker-system-service \
  beta-001-worker-user-service beta-001-worker-commission-service \
  --query 'services[].{name:serviceName,cp:capacityProviderStrategy[0].capacityProviderName}'
# Expected: all on dedicated CPs, none on beta-001-capacity-provider
```

### Changes

1. Remove the old shared CP from `aws_ecs_cluster_capacity_providers`.
2. Remove the old shared ASG, Launch Template, and Capacity Provider resources.
3. Remove aggressive scale-down CloudWatch alarm and ASG policies (no longer needed).

### Validation

```bash
# Verify shared CP no longer exists on the cluster
aws ecs describe-clusters --clusters beta-001-cluster \
  --query 'clusters[0].capacityProviders'
# Expected: only dedicated CPs, no beta-001-capacity-provider

# Verify shared ASG no longer exists
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names beta-001-asg \
  --query 'AutoScalingGroups'
# Expected: empty or not found
```

### Expected State After Phase 4

| Component | State |
|-----------|-------|
| Lambda schedulers | DISABLED |
| Worker services | desired_count=0, on dedicated CPs |
| Web service | desired_count=1, on dedicated web CP |
| **ASG (shared)** | **REMOVED** |
| **Shared CP** | **REMOVED** |
| Web ASG | 1 instance |
| Worker ASGs | 0 instances |

### Recovery

If removal fails, the shared resources can be re-added to Terraform and re-applied. Since no service references them, they exist as orphaned resources — no functional impact.

---

## Phase 5: Lambda — Update code + env vars + deploy

**Repository**: `lambda`
**Risk**: Low (Lambdas are disabled, changes are not active until Phase 6)
**Downtime**: None

### Code Changes

**`worker-autoscaling/lambda_function.rb`** — Add `update_auto_scaling_group` in the scale-up block (lines 92-103):

```ruby
# Current scale-up (only ECS service)
if unlocked && new_capacity > current_capacity
  ecs_client.update_service(
    cluster: ecs_cluster_name,
    service: ecs_service_name,
    desired_count: new_capacity
  )
  REDIS.del(redis_key)
  LOGGER.info("Scale UP: #{current_capacity} -> #{new_capacity}")
end

# New scale-up (ECS service + ASG)
if unlocked && new_capacity > current_capacity
  ecs_client.update_service(
    cluster: ecs_cluster_name,
    service: ecs_service_name,
    desired_count: new_capacity
  )

  begin
    auto_scaling_client = Aws::AutoScaling::Client.new(region: aws_region)
    auto_scaling_client.update_auto_scaling_group(
      auto_scaling_group_name: auto_scaling_group_name,
      min_size: new_capacity,
      desired_capacity: new_capacity
    )
    LOGGER.info("Auto Scaling Group: #{auto_scaling_group_name} | Set min_size and desired capacity: #{new_capacity}")
  rescue => e
    LOGGER.error("Failed to update Auto Scaling Group #{auto_scaling_group_name}: #{e.message}")
  end

  REDIS.del(redis_key)
  LOGGER.info("Scale UP: #{current_capacity} -> #{new_capacity}")
end
```

**`worker-commission-autoscaling/lambda_function.rb`** — Same change.

**`worker-commission-balancing/lambda_function.rb`** — Already manages ASG per worker on both directions. Verify config.yml mapping is correct.

> **Note on min_size during scale-up**: The scale-up code sets `min_size = new_capacity` to ensure the ASG provisions instances immediately. The existing scale-down code already resets both `min_size: 0` and `desired_capacity: 0` when the queue is empty, so the full cycle is covered — no manual intervention needed to lower min_size after a burst.

### Environment Variable Updates

```
Lambda-beta-worker-system-autoscaling:
  AUTO_SCALING_GROUP_NAME = beta-001-worker-system-asg

Lambda-beta-worker-user-autoscaling:
  AUTO_SCALING_GROUP_NAME = beta-001-worker-user-asg

Lambda-beta-worker-commission-autoscaling:
  AUTO_SCALING_GROUP_NAME = beta-001-worker-commission-asg
```

### Lambda Layer Update (commission-balancing config.yml)

> **Note**: Beta environment does not have commission-balancing. This step applies only to production environments (shared/atento).

```yaml
# Only for production environments:
services:
  worker_commission:
    ecs_service: beta-001-worker-commission-service
    auto_scaling_group_name: beta-001-worker-commission-asg
  worker_commission_tiger_shark:
    ecs_service: beta-001-worker-commission-tiger-shark-service
    auto_scaling_group_name: beta-001-worker-commission-tiger-shark-asg
  worker_commission_white_shark:
    ecs_service: beta-001-worker-commission-white-shark-service
    auto_scaling_group_name: beta-001-worker-commission-white-shark-asg
```

### IAM Policy Update `[REVISED]`

The v0.5.0 Lambda code introduces `autoscaling:UpdateAutoScalingGroup` calls to manage ASG capacity on scale-up and scale-down. The existing IAM roles only had ECS permissions (`ecs:DescribeServices`, `ecs:UpdateService`). A new policy `AutoScaling-{environment}-lambda-worker-policy` must be created and attached to all 3 Lambda roles:

- `Lambda-{environment}-worker-standard-autoscaling-role` (user + system)
- `Lambda-{environment}-worker-commission-autoscaling-role` (commission)
- `Lambda-{environment}-worker-commission-balancing-role` (balancing, conditional on `commission_balancing` flag)

The policy is scoped to `arn:aws:autoscaling:{region}:{account_id}:autoScalingGroup:*:autoScalingGroupName/{environment}-*-asg`.

> **Status**: PR [#119](https://github.com/4shark/terraform/pull/119) open. Terraform will create 1 new policy + 3 attachments (4 resources to add, 0 to change, 0 to destroy).

### Deployment Steps

1. Generate new Lambda zips (Docker container build).
2. Publish to S3.
3. Update Lambda functions with new code.
4. Update environment variables (AWS CLI or Terraform lambda-autoscaling).
5. Update Lambda Layer for commission-balancing (Terraform lambda-autoscaling).
6. **Apply IAM policy update** (Terraform lambda-autoscaling — PR #119).

### Validation

```bash
# Verify Lambda code version
for fn in Lambda-beta-worker-system-autoscaling Lambda-beta-worker-user-autoscaling Lambda-beta-worker-commission-autoscaling; do
  echo "=== $fn ==="
  aws lambda get-function-configuration --function-name $fn \
    --query '{version:Environment.Variables.VERSION,asg:Environment.Variables.AUTO_SCALING_GROUP_NAME}'
done

# Verify schedulers are still DISABLED (Lambdas should NOT be running yet)
aws scheduler list-schedules --query 'Schedules[?contains(Name,`beta`)].{name:Name,state:State}'
```

### Expected State After Phase 5

| Component | State |
|-----------|-------|
| Lambda schedulers | **DISABLED** (not yet re-enabled) |
| Lambda code | **Updated** (ASG management on scale-up) |
| Lambda env vars | **Pointing to dedicated ASGs** |
| Lambda Layer | **Updated config.yml** |
| Worker services | desired_count=0, on dedicated CPs |
| Web service | desired_count=1, on dedicated web CP |
| Worker ASGs | 0 instances |

### Recovery

Revert Lambda to previous version (restore old zip from S3). Revert env vars to previous values. Since Lambdas are disabled, reverting code and env vars has no runtime impact — it just prepares for a retry.

---

## Phase 6: Re-enable Lambdas

**Repository**: None (AWS CLI operations)
**Risk**: Medium (Lambdas start managing ASGs for the first time)
**Downtime**: None

### Changes

Re-enable all Lambda EventBridge schedulers. Lambdas will start executing every minute, detect queue state, and scale ECS services + dedicated ASGs accordingly.

### Commands

```bash
for scheduler in $(aws scheduler list-schedules --query 'Schedules[?contains(Name,`beta`)].Name' --output text); do
  echo "Enabling $scheduler"
  aws scheduler update-schedule --name $scheduler --state ENABLED \
    --flexible-time-window '{"Mode":"OFF"}' \
    --schedule-expression "$(aws scheduler get-schedule --name $scheduler --query 'ScheduleExpression' --output text)" \
    --target "$(aws scheduler get-schedule --name $scheduler --query 'Target' --output json)"
done
```

### Validation

```bash
# Verify schedulers are enabled
aws scheduler list-schedules --query 'Schedules[?contains(Name,`beta`)].{name:Name,state:State}'

# Monitor Lambda executions (wait 2-3 minutes for at least 2 executions)
for fn in Lambda-beta-worker-system-autoscaling Lambda-beta-worker-user-autoscaling Lambda-beta-worker-commission-autoscaling; do
  echo "=== $fn ==="
  aws logs tail /aws/lambda/$fn --since 5m --format short 2>/dev/null | tail -5
done

# Verify services are being managed (if there are jobs in queue, services should scale up)
aws ecs describe-services --cluster beta-001-cluster \
  --services beta-001-worker-system-service beta-001-worker-user-service \
  beta-001-worker-commission-service \
  --query 'services[].{name:serviceName,desired:desiredCount,running:runningCount}'
```

### Expected State After Phase 6

| Component | State |
|-----------|-------|
| Lambda schedulers | **ENABLED** |
| Lambda code | Updated, executing every minute |
| Worker services | Scaling based on queue (0 if no jobs, N if jobs pending) |
| Web service | desired_count=1, running (unchanged) |
| Worker ASGs | Scaling with services (Lambda manages) |
| Web ASG | 1 instance (CP manages) |

### Recovery

Disable Lambda schedulers (same as Phase 1). Diagnose Lambda logs, fix issues, re-enable.

---

## Phase 7: End-to-end validation

**Risk**: None (observation only)

### Scale-up Test

1. Enqueue jobs for one of the worker processes.
2. Wait ~1 minute for Lambda execution.
3. Verify:

```bash
# ECS service scaled up
aws ecs describe-services --cluster beta-001-cluster \
  --services beta-001-worker-system-service \
  --query 'services[0].{desired:desiredCount,running:runningCount}'

# Dedicated ASG scaled up
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names beta-001-worker-system-asg \
  --query 'AutoScalingGroups[0].{desired:DesiredCapacity,instances:Instances[*].InstanceId}'

# Other ASGs NOT affected (isolation test)
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names beta-001-worker-user-asg beta-001-worker-commission-asg \
  --query 'AutoScalingGroups[].{name:AutoScalingGroupName,desired:DesiredCapacity}'
```

### Scale-down Test

1. Let the queue drain completely.
2. Wait for hysteresis (3 empty checks x 1 minute = ~3 minutes).
3. Verify:

```bash
# ECS service scaled down
aws ecs describe-services --cluster beta-001-cluster \
  --services beta-001-worker-system-service \
  --query 'services[0].{desired:desiredCount,running:runningCount}'

# Dedicated ASG scaled down
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names beta-001-worker-system-asg \
  --query 'AutoScalingGroups[0].{desired:DesiredCapacity,instances:Instances[*].InstanceId}'

# Measure time from "queue empty" to "instance terminated"
# Expected: < 5 minutes (vs ~15 minutes before migration)
```

### Cross-process Isolation Test

1. Enqueue jobs for commission process (scales up commission ASG).
2. Enqueue jobs for system process (scales up system ASG).
3. Let system queue drain first (system scales down).
4. Verify commission ASG is NOT affected by system scale-down.

```bash
# Commission ASG should still be scaled up
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names beta-001-worker-commission-asg \
  --query 'AutoScalingGroups[0].{desired:DesiredCapacity,instances:Instances[*].InstanceId}'

# System ASG should be scaled down
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names beta-001-worker-system-asg \
  --query 'AutoScalingGroups[0].{desired:DesiredCapacity,instances:Instances[*].InstanceId}'
```

---

## Phase 8: Terraform — Cleanup legacy code

**Repository**: `terraform`
**Risk**: None
**Downtime**: None

### Changes

Full inventory of what needs to be cleaned up should be done at execution time. Known items so far:

- Remove unused variables (`aggressive_scale_down_*`, `scale_down_*`, etc.)
- Remove shared ASG code from `ecs_cluster` module entirely (Launch Template, ASG, Capacity Provider, scaling policies, CloudWatch alarm) — currently behind `create_asg` flag from Phase 4, should be deleted not flagged
- Remove `create_asg` variable from module
- Remove old `asg-launch-template` module from root `main.tf` (if still exists)
- Update documentation and variable files

---

## Environment Rollout Order

1. **beta** — Full migration, validate all phases.
2. **demo** — Replicate after beta is stable.
3. **shared** / **atento** (production) — Replicate after demo is stable. Production environments have minimum_capacity=1, so Phase 1 must account for brief period with no workers while services migrate. Consider executing during a maintenance window.

Each environment follows the same phase sequence independently.

---

## Summary

| Phase | Repository | Description | Risk |
|-------|-----------|-------------|------|
| 0 | app | Remove desired-count:1 from worker deploy | Low |
| 1 | AWS CLI | Disable Lambdas + scale workers to 0 | Low |
| 2 | terraform | Create dedicated ASGs + CPs (final config) | None |
| 3 | terraform | Migrate services to dedicated CPs | Low |
| 4 | terraform | Remove shared ASG + CP | Low |
| 5 | lambda | Update code + env vars + deploy | Low |
| 6 | AWS CLI | Re-enable Lambdas | Medium |
| 7 | — | End-to-end validation | None |
| 8 | terraform | Cleanup legacy code | None |

Each phase produces an expected state that must be validated before proceeding. If a phase fails, it can be reverted to the previous phase's state for diagnosis and retry.
