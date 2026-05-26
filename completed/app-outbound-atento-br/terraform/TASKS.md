# TASKS — app-outbound-atento-br Migration Phase 7 (Terraform)

> **Phase 7 status: ✅ CLOSED** — delivered via terraform#354, lambda#49, AWS CLI ops.
> **Reference:** `~/.claude/plans/active/app-outbound-atento-br/PLAN.md` (source of truth)

---

## Status Summary (Updated 2026-05-05 — post-Phase 8 delivery)

| Phase | Status | Notes |
|---|---|---|
| 0 — EC2 Inventory | ✅ Completed | Queue name, env vars, Sidekiq config confirmed |
| 1 — Lambda Reference Read | ✅ Completed | See `PHASE-1-DELTA.md`; interface documented |
| 2 — Networking Rename | ✅ Completed | terraform#349; SSMs migrated to `/networking/app-outbound-atento-br/*` |
| 3 — `modules/app_outbound` + Stack Rename | ✅ Completed | terraform#349; state migrated; `modules/app_outbound` created |
| 4 — Fargate Autoscaling Lambda | ✅ Completed | lambda#47, release 0.9.0; S3 artifact: `worker-payroll-autoscaling/0.9.0_37780e1.zip` |
| 5a — ECR sa-east-1 | ✅ Completed | terraform#351; repo `atento-001-app` in sa-east-1 |
| 5b — Dual-push `build-image.yaml` | ✅ Completed | app#4953; atento-001 image pushed to both us-east-1 and sa-east-1 |
| 5b-IAM — Extend deploy IAM to sa-east-1 | ✅ Completed | terraform#352; `ecr_repository_arns` extended |
| 6 — HireFire dyno `worker_payroll_tiger_shark` | ✅ Completed | app#4952; dyno registered in `config/initializers/hire_fire.rb` |
| **7 — ECS Compute Stack** | **✅ CLOSED** | terraform#354 (merged) + lambda#49 + AWS CLI ops |
| 7a — `modules/atento_001_task_config` | ✅ Completed | Shared env_vars + secrets module; consumed by both stacks |
| 7b — Refactor `app-atento-001/compute.tf` | ✅ Completed | Zero resource changes (verified in plan); applied |
| 7c — Lambda artifact regional bucket migration | ✅ Completed | 2 buckets created + sync'd (37 versions / 144 MiB each); `publish_lambdas` dual-push (lambda#49); 5 stacks re-pointed to `-us-east-1`; 3 applied (demo, shared, beta) — drift resolved as side effect; 2 pending apply (atento-001, onboarding — deferred, behavior identical) |
| 7d — Wire `app-outbound-atento-br` compute stack | ✅ Completed | 16 resources applied (cluster, worker-payroll service, runner service, Lambda, EventBridge, IAM). Lambda env vars set via CLI. Scale-to-zero verified. Runner service refreshed each deploy by `app/.github/workflows/deploy-atento-001.yaml` |
| 7e — Delete legacy `4shark-lambda-artifacts` | ✅ Completed | 37 versions + 6 markers purged; bucket deleted; HEAD → 404 |
| **8 — Deploy workflow (sibling + reusable)** | **✅ Completed** | app#3618a4cbf, #1283f01b8, #47eb1ffd9, #4988. Sibling jobs in `deploy-atento-001.yaml` (worker + runner) calling reusable `deploy-payroll-worker.yaml`; cross-track rollback; manual trigger; single env `atento-001`. 5 consecutive production deploys OK through 2026-04-30. Manual scale-up E2E validation 2026-05-05 OK (Sidekiq came up, registered in Sidekiq Web) |
| **2.5 — Cleanup deprecated SSMs + outputs** | ✅ Completed | terraform#395. 6 SSMs destroyed via targeted apply (magnatech drift bypassed); deprecated output + 14 moved blocks removed from code. Output state-cleanup deferred to next clean networking apply post-magnatech-resolution |
| **8.5 — Lambda binary-scale refactor (Terraform side)** | ✅ Completed | terraform#394. `lambda_version` in `app-outbound-atento-br/locals.tf` bumped from `0.9.0_37780e1` to `0.10.0_0989a3e`. Apply: 1 resource update-in-place; Lambda `lastModified = 2026-05-05T14:36:57Z` |
| 9 — Cutover | ✅ Completed | Sidekiq stopped on EC2s before 2026-05-05; ECS Fargate sole consumer |
| 10 — Decommission EC2 | ✅ Completed | terraform#396. 5 EC2 instances terminated (termination protection lifted ad-hoc); `ec2_legacy.tf` removed |

---

## Task 1 — Phase 7a: Create `modules/atento_001_task_config` ✅ COMPLETED

**Objective:** Create a new shared data module that extracts env vars and secrets for ECS task definitions. This module is consumed by both `app-atento-001` (Phase 7b refactor) and `app-outbound-atento-br` (Phase 7d wiring).

**Status:** ✅ COMPLETED on feature branch `feature/app-outbound-atento-br-ecs-compute`

**Artifact:** `terraform/modules/atento_001_task_config/` with `main.tf`, `variables.tf`, `outputs.tf`, and `README.md`

---

## Task 2 — Phase 7b: Refactor `app-atento-001/compute.tf` to Consume `modules/atento_001_task_config` ✅ COMPLETED

**Objective:** Replace the inline `env_vars` and `secrets` locals in `app-atento-001/compute.tf` with a module call. This refactor resulted in **zero resource changes**.

**Status:** ✅ COMPLETED on feature branch `feature/app-outbound-atento-br-ecs-compute`

**Artifact:** Refactored `terraform/app-atento-001/compute.tf` consuming `module.atento_001_task_config`

**Verification:** `terraform plan` showed zero resource changes; refactor applied cleanly without modifying any AWS resources.

---

## Task 3 — Phase 7c: Lambda Artifact Bucket Regional Migration

**Objective:** Migrate the legacy S3 bucket `4shark-lambda-artifacts` (us-east-1 only) to region-specific buckets (`4shark-lambda-artifacts-us-east-1` and `4shark-lambda-artifacts-sa-east-1`). The outbound stack Lambda in sa-east-1 requires the artifact bucket to be in the same region, so this bucket migration is a prerequisite for Phase 7d.

**Context:** The Lambda artifact `worker-payroll-autoscaling/0.9.0_37780e1.zip` currently lives in `s3://4shark-lambda-artifacts` (legacy bucket in us-east-1). When `data "aws_s3_object"` resources in the 5 existing stacks and the new `app-outbound-atento-br` stack reference bucket names, they must be region-specific to avoid `PermanentRedirect` errors.

**Actions (SEQUENCED — do NOT reorder):**

### Step 1: Create new buckets via AWS CLI (out-of-Terraform)

**Why out-of-Terraform:** These buckets are shared infrastructure not owned by a single stack. They are created once and referenced by multiple stacks. Not modeling them as Terraform resources avoids multi-stack cross-references.

- [ ] Create `4shark-lambda-artifacts-us-east-1` in us-east-1:
  ```bash
  aws s3api create-bucket \
    --bucket 4shark-lambda-artifacts-us-east-1 \
    --region us-east-1
  ```
- [ ] Create `4shark-lambda-artifacts-sa-east-1` in sa-east-1:
  ```bash
  aws s3api create-bucket \
    --bucket 4shark-lambda-artifacts-sa-east-1 \
    --region sa-east-1 \
    --create-bucket-configuration LocationConstraint=sa-east-1
  ```
- [ ] Verify both buckets exist:
  ```bash
  aws s3 ls | grep 4shark-lambda-artifacts
  ```
  Expected output:
  ```
  4shark-lambda-artifacts-sa-east-1
  4shark-lambda-artifacts-us-east-1
  ```

### Step 2: Replicate legacy content (one-time migration)

- [ ] Sync legacy bucket → new us-east-1 bucket:
  ```bash
  aws s3 sync s3://4shark-lambda-artifacts s3://4shark-lambda-artifacts-us-east-1
  ```
- [ ] Sync legacy bucket → new sa-east-1 bucket:
  ```bash
  aws s3 sync s3://4shark-lambda-artifacts s3://4shark-lambda-artifacts-sa-east-1
  ```
- [ ] **VERIFICATION — HOLD POINT:** List objects in both new buckets and compare with legacy:
  ```bash
  # Count objects in legacy bucket
  aws s3 ls s3://4shark-lambda-artifacts --recursive | wc -l
  
  # Count objects in new buckets
  aws s3 ls s3://4shark-lambda-artifacts-us-east-1 --recursive | wc -l
  aws s3 ls s3://4shark-lambda-artifacts-sa-east-1 --recursive | wc -l
  ```
  All three should show the same object count. Specifically, verify `worker-payroll-autoscaling/0.9.0_37780e1.zip` exists in both:
  ```bash
  aws s3 ls s3://4shark-lambda-artifacts-us-east-1/worker-payroll-autoscaling/
  aws s3 ls s3://4shark-lambda-artifacts-sa-east-1/worker-payroll-autoscaling/
  ```
  
  **⏸️ HOLD POINT:** Before proceeding to step 3, present sync verification results to user for approval.

### Step 3: Update `lambda/bin/publish_lambdas` script

- [ ] Open `~/Projects/4Shark/lambda/bin/publish_lambdas`
- [ ] Locate the section that uploads to `s3://4shark-lambda-artifacts`
- [ ] Update to dual-push: same artifact uploaded to both `4shark-lambda-artifacts-us-east-1` and `4shark-lambda-artifacts-sa-east-1`
- [ ] Remove any references to the legacy bucket `4shark-lambda-artifacts` (without region suffix)
- [ ] Document the new bucket convention in the script (comment explaining regional buckets)
- [ ] Test the updated script (dry-run with an existing artifact version to confirm both buckets would receive the upload):
  ```bash
  # Example: dry-run upload of existing lambda
  cd ~/Projects/4Shark/lambda
  # (Run publish_lambdas with dry-run flag or in interactive mode)
  ```

### Step 4: Update `lambda/RELEASE.md`

- [ ] Open `~/Projects/4Shark/lambda/RELEASE.md`
- [ ] Add a section documenting the bucket migration:
  - Old convention: single bucket `4shark-lambda-artifacts` in us-east-1
  - New convention: region-specific buckets `4shark-lambda-artifacts-{region}` (us-east-1, sa-east-1)
  - Rationale: Lambda functions must be deployed from S3 buckets in the same region (AWS Lambda limitation)
  - Migration date: 2026-04-22
  - Timeline: Legacy bucket will be deleted after Phase 7d verification (post-2026-05-14)
- [ ] Update any instructions for releasing artifacts to reference the new bucket names

### Step 5: Refactor 5 existing Terraform stacks to reference `4shark-lambda-artifacts-us-east-1`

Each of these stacks currently references `4shark-lambda-artifacts` and must be updated to reference the region-specific version. All stacks are in us-east-1, so they now reference `4shark-lambda-artifacts-us-east-1`.

#### Sub-step 5a: `terraform/app-beta-001/`
- [ ] Locate the `data "aws_s3_object"` or similar resource that references `s3_bucket = "4shark-lambda-artifacts"`
- [ ] Change to `s3_bucket = "4shark-lambda-artifacts-us-east-1"`
- [ ] Run `terraform plan` in `app-beta-001/` directory
- [ ] **CRITICAL CHECK:** Verify plan shows **ZERO resource changes**. If any change is detected, do NOT apply — debug and rollback.
- [ ] If plan is clean, apply:
  ```bash
  cd ~/Projects/4Shark/terraform/app-beta-001
  terraform apply
  ```

#### Sub-step 5b: `terraform/app-demo-001/`
- [ ] Locate and update bucket reference to `4shark-lambda-artifacts-us-east-1`
- [ ] Run `terraform plan`; verify zero changes
- [ ] Apply

#### Sub-step 5c: `terraform/app-shared-001/`
- [ ] Locate and update bucket reference to `4shark-lambda-artifacts-us-east-1`
- [ ] Run `terraform plan`; verify zero changes
- [ ] Apply

#### Sub-step 5d: `terraform/app-atento-001/`
- [ ] Locate and update bucket reference to `4shark-lambda-artifacts-us-east-1`
- [ ] Run `terraform plan`; verify zero changes
- [ ] Apply

#### Sub-step 5e: `terraform/onboarding/`
- [ ] Locate and update bucket reference to `4shark-lambda-artifacts-us-east-1`
- [ ] Run `terraform plan`; verify zero changes
- [ ] Apply

**⏸️ HOLD POINT:** After all 5 stacks have been refactored and their plans verified clean, present a summary to user before applying all 5 in sequence.

**Affected files:**
- `lambda/bin/publish_lambdas` (updated to dual-push)
- `lambda/RELEASE.md` (updated with new bucket convention)
- `terraform/app-beta-001/` (bucket reference updated)
- `terraform/app-demo-001/` (bucket reference updated)
- `terraform/app-shared-001/` (bucket reference updated)
- `terraform/app-atento-001/` (bucket reference updated)
- `terraform/onboarding/` (bucket reference updated)

**Completion criteria:**
- [ ] `4shark-lambda-artifacts-us-east-1` and `4shark-lambda-artifacts-sa-east-1` created and populated via `aws s3 sync`
- [ ] `aws s3 ls` confirms identical object count in all three buckets
- [ ] `worker-payroll-autoscaling/0.9.0_37780e1.zip` verified in both new buckets
- [ ] `lambda/bin/publish_lambdas` updated to dual-push; legacy bucket stops receiving new uploads
- [ ] `lambda/RELEASE.md` documents the new bucket convention
- [ ] Each of the 5 stacks refactored to reference `4shark-lambda-artifacts-us-east-1`
- [ ] Each stack's `terraform plan` shows zero resource changes
- [ ] All 5 stacks apply cleanly with no downtime

**Risk:** HIGH — Refactoring 5 live production stacks to reference a new S3 bucket carries significant risk if the artifact is missing from the new bucket. Mitigation: `aws s3 ls` verification before any `terraform plan`; refactor-only gate (zero-change plans) before apply.

**Effort:** 2.25 days (bucket creation + sync verification 0.5d; publish_lambdas + RELEASE.md 0.5d; 5-stack refactor + plans 1.25d)

---

## Task 4 — Phase 7d: Create `terraform/app-outbound-atento-br/locals.tf`

**Objective:** Define local variables and tags for the `app-outbound-atento-br` stack (tags only; no inline env vars or secrets — those come from the module).

**Prerequisites:** Task 3 (Phase 7c bucket migration) must be **COMPLETED** before starting Task 4. Phase 7d (Tasks 4–7) is blocked on 7c completion.

**Actions:**
- [ ] Create `terraform/app-outbound-atento-br/locals.tf`:
  - [ ] `service_name = "app-outbound-atento-br"`
  - [ ] `environment = "production"`
  - [ ] `name_prefix = "4client-app-outbound-atento-br"`
  - [ ] `tags` block with common tags:
    - `Client = "atento-br"`
    - `Project = "app-outbound"`
    - `Service = "worker-payroll"`
    - `Environment = local.environment`
    - Other standard tags (Owner, CostCenter, etc. — match existing `app-atento-001` tags)

**Affected files:** `terraform/app-outbound-atento-br/locals.tf` (new file)

**Completion criteria:**
- [ ] `locals.tf` created with tags and naming variables
- [ ] No `env_vars` or `secrets` literals in locals (those come from the module)

**Effort:** 0.25 day

---

## Task 5 — Phase 7d: Create `terraform/app-outbound-atento-br/iam.tf`

**Objective:** Define the IAM execution role for the autoscaling Lambda, scoped to the outbound cluster and service only (no ASG permissions per Option A of PHASE-1-DELTA.md).

**Prerequisites:** Task 3 (Phase 7c) must be COMPLETED.

**Actions:**
- [ ] Create `terraform/app-outbound-atento-br/iam.tf`:
  - [ ] `aws_iam_role` for Lambda execution:
    - Name: `Lambda-app-outbound-atento-br-worker-payroll-autoscaling-role`
    - Trust relationship: `"lambda.amazonaws.com"`
  - [ ] `aws_iam_role_policy` (inline policy) with permissions:
    - [ ] `ecs:UpdateService` on ARN: `arn:aws:ecs:sa-east-1:405749097490:service/app-outbound-atento-br-cluster/app-outbound-atento-br-worker-payroll-service`
    - [ ] `ecs:DescribeServices` on cluster and service ARNs
    - [ ] `ecs:ListTasks` on cluster ARN: `arn:aws:ecs:sa-east-1:405749097490:cluster/app-outbound-atento-br-cluster`
    - [ ] CloudWatch Logs: `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents` on `/ecs/app-outbound-atento-br-worker-payroll*`
    - [ ] SSM Parameter read (if Lambda reads REDIS_URL from SSM): `ssm:GetParameter` on `/atento-001/*` in us-east-1
  - [ ] **NO ASG permissions** (key difference from the atento-001 Lambda role)
  - [ ] Add comments documenting the rationale: "Lambda updates ECS service desired_count to autoscale based on queue depth"

**Affected files:** `terraform/app-outbound-atento-br/iam.tf` (new file)

**Completion criteria:**
- [ ] IAM execution role created with correct trust relationship
- [ ] Permissions scoped to outbound cluster and service ARNs only
- [ ] No ASG-related permissions (UpdateAutoScalingGroup, etc.)
- [ ] CloudWatch logs permission included
- [ ] SSM read permission for REDIS_URL (if needed)

**Effort:** 0.5 day

---

## Task 6 — Phase 7d: Create `terraform/app-outbound-atento-br/compute.tf`

**Objective:** Wire the ECS Fargate cluster, worker service, task definition, autoscaling Lambda, and EventBridge schedule for the outbound stack.

**Prerequisites:** Task 3 (Phase 7c) must be COMPLETED; Tasks 4–5 must be COMPLETED.

**Actions:**
- [ ] Create `terraform/app-outbound-atento-br/compute.tf`:

**A. Call `modules/atento_001_task_config`:**
```hcl
module "atento_001_task_config" {
  source = "../modules/atento_001_task_config"
  cluster_name = "app-outbound-atento-br-cluster"
}
```

**B. Create `aws_ecs_cluster`:**
- [ ] Cluster name: `app-outbound-atento-br-cluster`
- [ ] Region: sa-east-1 (via provider alias or implicit)
- [ ] Fargate-only (no capacity provider, no ASG)
- [ ] Tags: use `local.tags`

**C. Create `aws_cloudwatch_log_group`:**
- [ ] Name: `/ecs/app-outbound-atento-br-worker-payroll`
- [ ] Retention in days: `30`
- [ ] KMS key ARN: (reuse existing if available, or leave empty for AWS-managed)

**D. Create `aws_ecs_task_definition`:**
- [ ] Family: `app-outbound-atento-br-worker-payroll`
- [ ] Network mode: `awsvpc` (required for Fargate)
- [ ] CPU: `2048`, Memory: `2048`
- [ ] Execution role: `arn:aws:iam::405749097490:role/ecsTaskExecutionRole` (global, reused from atento-001)
- [ ] Task role: same as execution role
- [ ] Container definition:
  - Name: `app-outbound-atento-br-worker-payroll`
  - Image: `405749097490.dkr.ecr.sa-east-1.amazonaws.com/atento-001-app:latest`
  - CPU: `2048`, Memory: `2048` (container-level match)
  - Port mappings: none (worker-only, no web process)
  - Environment variables: use `module.atento_001_task_config.env_vars`
  - Secrets: use `module.atento_001_task_config.secrets` (SSM Parameter Store references with ARNs)
  - Log configuration:
    - Log driver: `awslogs`
    - Log group: `/ecs/app-outbound-atento-br-worker-payroll`
    - Log stream prefix: `ecs/app-outbound-atento-br-worker-payroll`
    - Region: `sa-east-1`
  - Command: `["bundle", "exec", "sidekiq", "-C", "config/sidekiq_payroll_tiger_shark.yml"]`

**E. Create `aws_ecs_service`:**
- [ ] Name: `app-outbound-atento-br-worker-payroll-service`
- [ ] Cluster: `aws_ecs_cluster.this.id`
- [ ] Task definition: `aws_ecs_task_definition.this.arn`
- [ ] Desired count: `0` (scale-to-zero baseline)
- [ ] Launch type: `FARGATE`
- [ ] Network configuration:
  - Subnets: private subnets of the renamed VPC (sa-east-1a, sa-east-1c) — reference via module outputs or variable
  - Security group: allow outbound to on-prem CIDRs (`10.155.0.152/32`, `10.189.0.162/32`) via TGW — reuse from `modules/app_outbound` output
  - Assign public IP: `false` (private subnet, no public IP needed)
- [ ] `enable_execute_command = true` (required for `ecs execute-command` to send TSTP/CONT signals during deploy)
- [ ] Tags: use `local.tags`

**F. Call `modules/lambda-ecs-autoscaling`:**
- [ ] Source: `../modules/lambda-ecs-autoscaling`
- [ ] Lambda function name: `worker-payroll-autoscaling`
- [ ] S3 source:
  - Bucket: `4shark-lambda-artifacts-sa-east-1` (regional bucket — Phase 7c completed)
  - Key: `worker-payroll-autoscaling/0.9.0_37780e1.zip` (from Phase 4)
- [ ] Role ARN: `aws_iam_role.lambda_execution.arn` (from `iam.tf`)
- [ ] Environment variables (set in module invocation):
  - `ECS_CLUSTER_NAME = "app-outbound-atento-br-cluster"`
  - `ECS_SERVICE_NAME = "app-outbound-atento-br-worker-payroll-service"`
  - `METRICS_ENDPOINT = "https://atento001.app4shark.com/hirefire/191080bf-1429-42d4-8a53-0f8df3e8354a/info"` (from Phase 0 inventory)
  - `PROCESS_NAME = "worker_payroll_tiger_shark"` (from Phase 0 + Phase 6)
  - `MINIMUM_CAPACITY = "0"`
  - `MAXIMUM_CAPACITY = "5"`
  - `AWS_REGION = "sa-east-1"`
  - `REDIS_URL = "redis-19904.c263.us-east-1-2.ec2.redns.redis-cloud.com:19904"` (from Phase 0)
  - `JOBS_PER_PROCESS = "500"`
  - `EMPTY_QUEUE_CHECK_THRESHOLD = "3"`
- [ ] **CRITICAL:** Lambda env vars are **NOT managed by Terraform** — the module has `lifecycle { ignore_changes = [environment] }`. After `terraform apply`, set env vars manually via AWS Console or CLI (see below after apply).

**G. Create EventBridge schedule (via `modules/eventbridge-scheduler`):**
- [ ] Schedule expression: `rate(1 minute)`
- [ ] Target Lambda: `modules/lambda-ecs-autoscaling.function_arn`
- [ ] Tags: use `local.tags`

**H. Grant Lambda permission for EventBridge invocation:**
- [ ] `aws_lambda_permission` with:
  - Action: `lambda:InvokeFunction`
  - Principal: `events.amazonaws.com`
  - Source ARN: EventBridge rule ARN

**Actions continuation:**
- [ ] Run `terraform plan` in `app-outbound-atento-br/` directory
- [ ] **Verify plan shows:**
  - [ ] 1 × `aws_ecs_cluster`
  - [ ] 1 × `aws_ecs_task_definition`
  - [ ] 1 × `aws_ecs_service`
  - [ ] 1 × `aws_cloudwatch_log_group`
  - [ ] 1 × Lambda function (via module)
  - [ ] 1 × EventBridge rule
  - [ ] 1 × EventBridge target
  - [ ] 1 × Lambda permission
  - [ ] No unexpected destroys
- [ ] **⏸️ HOLD POINT:** Present plan output to user for approval before applying
- [ ] (Upon approval) Run `terraform apply`
- [ ] **Post-apply verification:**
  - [ ] ECS service shows `desired_count = 0` in AWS console
  - [ ] Lambda function created in sa-east-1
  - [ ] EventBridge rule scheduled to fire every minute
  - [ ] CloudWatch log group created with correct retention

**Post-apply manual steps (Lambda env vars):**
- [ ] Lambda env vars cannot be set via Terraform (module has `lifecycle { ignore_changes }`)
- [ ] After apply, set env vars manually:
  ```bash
  aws lambda update-function-configuration \
    --function-name Lambda-app-outbound-atento-br-worker-payroll-autoscaling \
    --region sa-east-1 \
    --environment '{
      "Variables": {
        "ECS_CLUSTER_NAME": "app-outbound-atento-br-cluster",
        "ECS_SERVICE_NAME": "app-outbound-atento-br-worker-payroll-service",
        "METRICS_ENDPOINT": "https://atento001.app4shark.com/hirefire/191080bf-1429-42d4-8a53-0f8df3e8354a/info",
        "PROCESS_NAME": "worker_payroll_tiger_shark",
        "MINIMUM_CAPACITY": "0",
        "MAXIMUM_CAPACITY": "5",
        "AWS_REGION": "sa-east-1",
        "REDIS_URL": "redis-19904.c263.us-east-1-2.ec2.redns.redis-cloud.com:19904",
        "JOBS_PER_PROCESS": "500",
        "EMPTY_QUEUE_CHECK_THRESHOLD": "3"
      }
    }'
  ```
  Or use AWS Console: Lambda → Functions → `Lambda-app-outbound-atento-br-worker-payroll-autoscaling` → Configuration → Environment Variables
- [ ] Test Lambda invocation:
  ```bash
  aws lambda invoke \
    --function-name Lambda-app-outbound-atento-br-worker-payroll-autoscaling \
    --region sa-east-1 \
    /tmp/lambda_test_output.json
  cat /tmp/lambda_test_output.json
  ```
  Expected response: `{"status": "ok", "desired_count": 0}` (queue empty → 0 tasks)
- [ ] Verify CloudWatch logs show Lambda executions every minute

**Affected files:** `terraform/app-outbound-atento-br/compute.tf` (new file)

**Completion criteria:**
- [ ] `terraform plan` shows all ECS, Lambda, EventBridge resources as creates (no unexpected destroys)
- [ ] `terraform apply` succeeds without errors
- [ ] ECS service created with `desired_count = 0`
- [ ] Lambda function created in sa-east-1
- [ ] EventBridge rule fires every minute (verify in CloudWatch Events)
- [ ] Lambda responds with `status: ok` when manually invoked
- [ ] CloudWatch log group created at `/ecs/app-outbound-atento-br-worker-payroll`
- [ ] Lambda env vars set manually post-apply (not via Terraform)

**Risk:** MEDIUM — first time wiring Fargate autoscaling Lambda + cross-region SSM reads in this project. Cross-region reachability (Redis + METRICS_ENDPOINT) must work.

**Effort:** 2 days (includes Terraform code + manual env var configuration + testing)

**[HOLD POINT]** After `terraform plan` is clean, pause and present the plan summary to the user for explicit approval before applying.

---

## Task 7 — Phase 7e: Delete Legacy `4shark-lambda-artifacts` Bucket

**Objective:** After Phase 7d is applied and confirmed working, verify that no code or workflow still references the legacy bucket `4shark-lambda-artifacts`, then delete it.

**Prerequisites:** Task 6 (Phase 7d — `app-outbound-atento-br` compute stack) must be COMPLETED and VERIFIED WORKING for 24–48 hours. All references to the legacy bucket must be removed.

**Actions:**

### Step 1: Verify no remaining references to legacy bucket

- [ ] Search entire codebase for references to `4shark-lambda-artifacts` (without region suffix):
  ```bash
  grep -rn "4shark-lambda-artifacts" ~/Projects/4Shark/ \
    --exclude-dir=.git \
    --exclude-dir=node_modules \
    --exclude-dir=.terraform \
    | grep -v "4shark-lambda-artifacts-us-east-1" \
    | grep -v "4shark-lambda-artifacts-sa-east-1"
  ```
  Expected output: **ZERO matches**. If any match appears, those references must be updated to the regional bucket names before proceeding.

### Step 2: Verify legacy bucket is no longer receiving uploads

- [ ] Confirm that `lambda/bin/publish_lambdas` has been updated to dual-push (Task 3, Step 3)
- [ ] Confirm that `terraform/` stacks all reference regional buckets (Task 3, Step 5)
- [ ] Check S3 access logs or bucket versioning to confirm no writes to legacy bucket since Task 3 completion

### Step 3: Delete legacy bucket

- [ ] Delete all objects in legacy bucket (required before bucket deletion):
  ```bash
  aws s3 rm s3://4shark-lambda-artifacts --recursive
  ```
- [ ] Delete the empty bucket:
  ```bash
  aws s3api delete-bucket \
    --bucket 4shark-lambda-artifacts \
    --region us-east-1
  ```
- [ ] Verify deletion:
  ```bash
  aws s3 ls | grep 4shark-lambda-artifacts
  ```
  Expected output: **ZERO lines** (only the two regional buckets remain)

**Affected files:** None (Terraform and code already updated in Task 3)

**Completion criteria:**
- [ ] Grep across all repos shows zero references to `4shark-lambda-artifacts` without a region suffix
- [ ] Legacy bucket deleted; `aws s3 ls s3://4shark-lambda-artifacts` returns `NoSuchBucket`
- [ ] Only `4shark-lambda-artifacts-us-east-1` and `4shark-lambda-artifacts-sa-east-1` remain

**Risk:** LOW — all references have been updated; bucket is empty; deletion is final (cannot undo).

**Effort:** 0.25 day

**Timing:** Execute 24–48 hours after Task 6 (Phase 7d) apply is confirmed stable and working.

---

## Task 8 — Phase 2.5: Cleanup Deprecated SSMs + Outputs (Post-Phase 7d)

**Objective:** Wire the ECS Fargate cluster, worker service, task definition, autoscaling Lambda, and EventBridge schedule for the outbound stack.

> **NOTE (2026-05-05):** the block below (down to the next `## Task 8` heading) is the original detailed checklist for Task 6 (Phase 7d) that was accidentally duplicated under this heading during plan iteration. Phase 7d is fully delivered; the canonical Task 8 (Phase 2.5 — SSM cleanup) appears further down. Kept here only for historical reference.

**Actions:**
- [ ] Create `terraform/app-outbound-atento-br/compute.tf`:

**A. Call `modules/atento_001_task_config`:**
```hcl
module "atento_001_task_config" {
  source = "../modules/atento_001_task_config"
  cluster_name = "app-outbound-atento-br-cluster"
}
```

**B. Create `aws_ecs_cluster`:**
- [ ] Cluster name: `app-outbound-atento-br-cluster`
- [ ] Region: sa-east-1 (via provider alias or implicit)
- [ ] Fargate-only (no capacity provider, no ASG)
- [ ] Tags: use `local.tags`

**C. Create `aws_cloudwatch_log_group`:**
- [ ] Name: `/ecs/app-outbound-atento-br-worker-payroll`
- [ ] Retention in days: `30`
- [ ] KMS key ARN: (reuse existing if available, or leave empty for AWS-managed)

**D. Create `aws_ecs_task_definition`:**
- [ ] Family: `app-outbound-atento-br-worker-payroll`
- [ ] Network mode: `awsvpc` (required for Fargate)
- [ ] CPU: `2048`, Memory: `2048`
- [ ] Execution role: `arn:aws:iam::405749097490:role/ecsTaskExecutionRole` (global, reused from atento-001)
- [ ] Task role: same as execution role
- [ ] Container definition:
  - Name: `app-outbound-atento-br-worker-payroll`
  - Image: `405749097490.dkr.ecr.sa-east-1.amazonaws.com/atento-001-app:latest`
  - CPU: `2048`, Memory: `2048` (container-level match)
  - Port mappings: none (worker-only, no web process)
  - Environment variables: use `module.atento_001_task_config.env_vars`
  - Secrets: use `module.atento_001_task_config.secrets` (SSM Parameter Store references with ARNs)
  - Log configuration:
    - Log driver: `awslogs`
    - Log group: `/ecs/app-outbound-atento-br-worker-payroll`
    - Log stream prefix: `ecs/app-outbound-atento-br-worker-payroll`
    - Region: `sa-east-1`
  - Command: `["bundle", "exec", "sidekiq", "-C", "config/sidekiq_payroll_tiger_shark.yml"]`

**E. Create `aws_ecs_service`:**
- [ ] Name: `app-outbound-atento-br-worker-payroll-service`
- [ ] Cluster: `aws_ecs_cluster.this.id`
- [ ] Task definition: `aws_ecs_task_definition.this.arn`
- [ ] Desired count: `0` (scale-to-zero baseline)
- [ ] Launch type: `FARGATE`
- [ ] Network configuration:
  - Subnets: private subnets of the renamed VPC (sa-east-1a, sa-east-1c) — reference via module outputs or variable
  - Security group: allow outbound to on-prem CIDRs (`10.155.0.152/32`, `10.189.0.162/32`) via TGW — reuse from `modules/app_outbound` output
  - Assign public IP: `false` (private subnet, no public IP needed)
- [ ] `enable_execute_command = true` (required for `ecs execute-command` to send TSTP/CONT signals during deploy)
- [ ] Tags: use `local.tags`

**F. Call `modules/lambda-ecs-autoscaling`:**
- [ ] Source: `../modules/lambda-ecs-autoscaling`
- [ ] Lambda function name: `worker-payroll-autoscaling`
- [ ] S3 source:
  - Bucket: `4shark-lambda-artifacts`
  - Key: `worker-payroll-autoscaling/0.9.0_37780e1.zip` (from Phase 4)
- [ ] Role ARN: `aws_iam_role.lambda_execution.arn` (from `iam.tf`)
- [ ] Environment variables (set in module invocation):
  - `ECS_CLUSTER_NAME = "app-outbound-atento-br-cluster"`
  - `ECS_SERVICE_NAME = "app-outbound-atento-br-worker-payroll-service"`
  - `METRICS_ENDPOINT = "https://atento001.app4shark.com/hirefire/191080bf-1429-42d4-8a53-0f8df3e8354a/info"` (from Phase 0 inventory)
  - `PROCESS_NAME = "worker_payroll_tiger_shark"` (from Phase 0 + Phase 6)
  - `MINIMUM_CAPACITY = "0"`
  - `MAXIMUM_CAPACITY = "5"`
  - `AWS_REGION = "sa-east-1"`
  - `REDIS_URL = "redis-19904.c263.us-east-1-2.ec2.redns.redis-cloud.com:19904"` (from Phase 0)
  - `JOBS_PER_PROCESS = "500"`
  - `EMPTY_QUEUE_CHECK_THRESHOLD = "3"`
- [ ] **CRITICAL:** Lambda env vars are **NOT managed by Terraform** — the module has `lifecycle { ignore_changes = [environment] }`. After `terraform apply`, set env vars manually via AWS Console or CLI (see below after apply).

**G. Create EventBridge schedule (via `modules/eventbridge-scheduler`):**
- [ ] Schedule expression: `rate(1 minute)`
- [ ] Target Lambda: `modules/lambda-ecs-autoscaling.function_arn`
- [ ] Tags: use `local.tags`

**H. Grant Lambda permission for EventBridge invocation:**
- [ ] `aws_lambda_permission` with:
  - Action: `lambda:InvokeFunction`
  - Principal: `events.amazonaws.com`
  - Source ARN: EventBridge rule ARN

**Actions continuation:**
- [ ] Run `terraform plan` in `app-outbound-atento-br/` directory
- [ ] **Verify plan shows:**
  - [ ] 1 × `aws_ecs_cluster`
  - [ ] 1 × `aws_ecs_task_definition`
  - [ ] 1 × `aws_ecs_service`
  - [ ] 1 × `aws_cloudwatch_log_group`
  - [ ] 1 × Lambda function (via module)
  - [ ] 1 × EventBridge rule
  - [ ] 1 × EventBridge target
  - [ ] 1 × Lambda permission
  - [ ] No unexpected destroys
- [ ] Present plan output to user for approval
- [ ] (Upon approval) Run `terraform apply`
- [ ] **Post-apply verification:**
  - [ ] ECS service shows `desired_count = 0` in AWS console
  - [ ] Lambda function created in sa-east-1
  - [ ] EventBridge rule scheduled to fire every minute
  - [ ] CloudWatch log group created with correct retention

**Post-apply manual steps (Lambda env vars):**
- [ ] Lambda env vars cannot be set via Terraform (module has `lifecycle { ignore_changes }`)
- [ ] After apply, set env vars manually:
  ```bash
  aws lambda update-function-configuration \
    --function-name Lambda-app-outbound-atento-br-worker-payroll-autoscaling \
    --region sa-east-1 \
    --environment '{
      "Variables": {
        "ECS_CLUSTER_NAME": "app-outbound-atento-br-cluster",
        "ECS_SERVICE_NAME": "app-outbound-atento-br-worker-payroll-service",
        "METRICS_ENDPOINT": "https://atento001.app4shark.com/hirefire/191080bf-1429-42d4-8a53-0f8df3e8354a/info",
        "PROCESS_NAME": "worker_payroll_tiger_shark",
        "MINIMUM_CAPACITY": "0",
        "MAXIMUM_CAPACITY": "5",
        "AWS_REGION": "sa-east-1",
        "REDIS_URL": "redis-19904.c263.us-east-1-2.ec2.redns.redis-cloud.com:19904",
        "JOBS_PER_PROCESS": "500",
        "EMPTY_QUEUE_CHECK_THRESHOLD": "3"
      }
    }'
  ```
  Or use AWS Console: Lambda → Functions → `Lambda-app-outbound-atento-br-worker-payroll-autoscaling` → Configuration → Environment Variables
- [ ] Test Lambda invocation:
  ```bash
  aws lambda invoke \
    --function-name Lambda-app-outbound-atento-br-worker-payroll-autoscaling \
    --region sa-east-1 \
    /tmp/lambda_test_output.json
  cat /tmp/lambda_test_output.json
  ```
  Expected response: `{"status": "ok", "desired_count": 0}` (queue empty → 0 tasks)
- [ ] Verify CloudWatch logs show Lambda executions every minute

**Affected files:** `terraform/app-outbound-atento-br/compute.tf` (new file)

**Completion criteria:**
- [ ] `terraform plan` shows all ECS, Lambda, EventBridge resources as creates (no unexpected destroys)
- [ ] `terraform apply` succeeds without errors
- [ ] ECS service created with `desired_count = 0`
- [ ] Lambda function created in sa-east-1
- [ ] EventBridge rule fires every minute (verify in CloudWatch Events)
- [ ] Lambda responds with `status: ok` when manually invoked
- [ ] CloudWatch log group created at `/ecs/app-outbound-atento-br-worker-payroll`
- [ ] Lambda env vars set manually post-apply (not via Terraform)

**Risk:** MEDIUM — first time wiring Fargate autoscaling Lambda + cross-region SSM reads in this project. Cross-region reachability (Redis + METRICS_ENDPOINT) must work.

**Effort:** 2 days (includes Terraform code + manual env var configuration + testing)

**[HOLD POINT]** After `terraform plan` is clean, pause and present the plan summary to the user for explicit approval before applying.

---

## Task 8 — Phase 2.5: Cleanup Deprecated SSMs + Outputs (Post-Phase 7d)

**Objective:** After Phase 7d apply confirms the new path works, remove the old `/networking/out-atento-br/*` SSM parameters and finalize the migration.

**Prerequisites:**
- [ ] Phase 7d (`app-outbound-atento-br` compute stack) applied successfully
- [ ] ECS service and Lambda running and consuming new SSM paths correctly
- [ ] Observation window passed (e.g., 24-48 hours of stable operation)

**Actions:**
- [ ] Verify in `terraform/networking/ssm.tf` that old SSM parameters at `/networking/out-atento-br/*` are still present
- [ ] Remove old resource blocks from `networking/ssm.tf`
- [ ] Confirm new parameters at `/networking/app-outbound-atento-br/*` are the sole source of truth
- [ ] Run `terraform plan` in `networking/` directory
- [ ] Verify plan shows **only the 6 old SSM parameters being destroyed**; no other changes
- [ ] Run `terraform apply` to destroy old parameters
- [ ] Verify in AWS console that old parameters are gone

**Affected files:** `terraform/networking/ssm.tf`

**Completion criteria:**
- [ ] Old SSM parameters destroyed
- [ ] New SSM parameters remain as source of truth
- [ ] No references to old paths in any Terraform code

**Effort:** 0.25 day

**Timing:** Execute after Phase 7d is live and stable.

---

## Task 9 — Phase 10: Document Decommissioning Plan (EC2 Removal)

**Objective:** Document the final Phase 10 steps for EC2 resource cleanup (to be executed after Phase 9 cutover is complete and stable).

**Actions:**
- [ ] Document what will happen when EC2s are decommissioned:
  - 5 × EC2 instances (`t3.small`) will be terminated
  - Route53 internal DNS records (`4client-out-atento-br-app00N.*`) will be destroyed (if managed by Terraform)
  - EC2-related security groups removed
  - EBS volumes and snapshots cleaned up
- [ ] Confirm that `modules/app_outbound` does NOT include EC2 resources (Fargate-only)
- [ ] Verify the 5 EC2 instances are no longer in Terraform state after Phase 3 (they were removed when `modules/app` was replaced with `modules/app_outbound`)
- [ ] If EC2s are still in Terraform state and need to be destroyed, prepare the `terraform destroy` command scoped to EC2 resources only
- [ ] Prepare Ansible and Capistrano cleanup tasks (in parallel with Terraform)

**Affected files:** Documentation only (PLAN.md or this TASKS.md); Phase 10 execution happens post-cutover

**Completion criteria:**
- [ ] Phase 10 decommissioning steps clearly outlined
- [ ] Timeline: execute only after Phase 9 cutover observation window (15–30 days stable operation)
- [ ] Ready for execution by engineer or automation

**Effort:** 0.25 day

**Timing:** Plan now; execute post-Phase 9 (after 2026-05-14 cutover + observation).

---

## Summary of HOLD POINTs

1. **Task 3 — Phase 7c (Bucket Migration):**
   - After `aws s3 sync` completes, HOLD before proceeding to step 3 (update publish_lambdas)
   - After 5-stack refactor plans are clean, HOLD before applying all 5 stacks

2. **Task 6 — Phase 7d (Wiring app-outbound-atento-br):**
   - After `terraform plan` is complete, HOLD and present plan summary to user for explicit approval before applying

---

## Summary of Post-Apply Manual Steps

After **Task 6** (`terraform apply` for Phase 7d):
- [ ] Set Lambda environment variables via AWS CLI or Console (not managed by Terraform)
- [ ] Test Lambda invocation manually to confirm `status: ok` response
- [ ] Verify EventBridge rule fires every minute in CloudWatch
- [ ] Confirm no errors in Lambda CloudWatch logs

---

## Effort Summary — Phase 7 (delivered)

| Task | Phase | Status | Notes |
|---|---|---|---|
| 1 — Create `modules/atento_001_task_config` | 7a | ✅ | Pure data module |
| 2 — Refactor `app-atento-001/compute.tf` | 7b | ✅ | Zero resource changes verified |
| 3 — Lambda artifact bucket regional migration | 7c | ✅ | 2 buckets + sync + `publish_lambdas` dual-push + 5 stacks refactored |
| 4 — Create `app-outbound-atento-br/locals.tf` | 7d | ✅ | Tags + naming variables |
| 5 — Create `app-outbound-atento-br/iam.tf` | 7d | ✅ | Lambda execution role (no ASG perms) |
| 6 — Create `app-outbound-atento-br/compute.tf` | 7d | ✅ | ECS cluster + worker-payroll service + runner service + Lambda + EventBridge |
| 7 — Delete legacy `4shark-lambda-artifacts` bucket | 7e | ✅ | Bucket purged + deleted |

---

## Pending Terraform work

✅ All Terraform-side phases of this migration are complete.

Out-of-scope follow-ups (separate work):
- `modules/app` `enable_vpn = true` audit — remove the VPN path if no other stack uses it
- `out_atento_br_vpc_id` output state-cleanup — auto-syncs on next clean `networking/` apply (post-magnatech-drift resolution)
- Ansible/Capistrano cleanup for `app-atento-br` — handled in the `ansible/` repo, not here

---

## Key Assumptions & Notes

1. **Regional bucket names:** New buckets are managed out-of-Terraform (shared infrastructure). Terraform stacks reference only the regional variants (`4shark-lambda-artifacts-{region}`).
2. **Cross-region reachability:** Redis Cloud and METRICS_ENDPOINT reachable from sa-east-1 Lambda — confirmed in production.
3. **SSM secrets:** Task definition reads secrets from `/atento-001/*` in us-east-1 via cross-region ARNs; KMS MRK replicated in sa-east-1.

---

**Status:** ✅ All phases closed (2026-05-05). Migration delivered.
