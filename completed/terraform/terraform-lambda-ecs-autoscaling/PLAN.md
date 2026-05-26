# PLAN — Terraform: Lambda ECS Autoscaling Infrastructure

> **Status:** Complete - PR #106 Merged
> **Created:** 2026-01-16
> **Updated:** 2026-01-21
> **Reference:** Continuation of `lambda-ecs-tasks` feature (completed)
> **Scope:** Infrastructure provisioning and updates - one environment at a time

---

## Executive Summary

Convert the shell script `setup-lambda-env.sh` (from the completed `lambda-ecs-tasks` feature) into Terraform infrastructure-as-code. This Terraform handles **infrastructure setup and Lambda updates** - one environment at a time. Lambda environment variables are configured manually by the engineer and preserved during Terraform updates via `lifecycle { ignore_changes = [environment] }`.

---

## Context & Background

### What Was Done (Previous Feature)

The `lambda-ecs-tasks` feature migrated Lambda functions from EC2 Auto Scaling Groups to ECS Services:

1. **App Workflow Restructuring** - PRs #4730, #4731
2. **Lambda Code Migration** - PR #8 (from ASG API to ECS API)
3. **Lambda Renaming** - PR #8 (domain-meaningful names)
4. **AWS IAM Setup** - Shell script (`setup-lambda-env.sh`)
5. **Lambda Deployment** - Pending
6. **EC2 Cleanup** - Pending (separate task)

### What This Feature Did

Converted step 4 (AWS IAM Setup) from shell script to Terraform, following market best practices. The Terraform code was tested by importing existing beta-001 resources and validating Lambda version updates.

### Resources Created (per environment)

| Type | Name Pattern | Count |
|------|--------------|-------|
| IAM Policy | `CloudWatch-{env}-lambda-logs-policy` | 1 |
| IAM Policy | `ECS-{env}-lambda-worker-policy` | 1 |
| IAM Policy | `EventBridge-{env}-lambda-invoke-policy` | 1 |
| IAM Policy | `Lambda-{env}-invoke-balancing-policy` | 1 |
| IAM Role | `Lambda-{env}-worker-commission-autoscaling-role` | 1 |
| IAM Role | `Lambda-{env}-worker-commission-balancing-role` | 1 |
| IAM Role | `Lambda-{env}-worker-standard-autoscaling-role` | 1 |
| IAM Role | `EventBridge-{env}-scheduler-role` | 1 |
| Lambda | `Lambda-{env}-worker-commission-autoscaling` | 1 |
| Lambda | `Lambda-{env}-worker-commission-balancing` | 1 |
| Lambda | `Lambda-{env}-worker-user-autoscaling` | 1 |
| Lambda | `Lambda-{env}-worker-system-autoscaling` | 1 |
| Schedule | (only for lambdas with schedule=true) | 3 |

---

## Architecture Decisions

### Decision 1: Deploy Strategy

**Decision:** Deploy **one environment at a time** for initial infrastructure setup.

**Rationale:**
- This Terraform is for infrastructure provisioning, not continuous deployment
- Each environment may have different lambdas configured
- Reduces blast radius during initial setup
- Allows gradual migration (beta first, then others)

### Decision 2: Lambda Environment Variables

**Decision:** Environment variables are configured manually by engineer and preserved by Terraform during updates.

**Implementation:**
- Terraform uses `lifecycle { ignore_changes = [environment] }` on Lambda resources
- This allows Terraform to update Lambda code without touching environment variables
- Engineer configures variables once in AWS Console, Terraform preserves them

**Rationale:**
- Environment variables vary per Lambda and per environment
- Manual configuration gives engineer full control
- Terraform handles infrastructure, engineer handles configuration
- Updates via Terraform don't require re-entering environment variables

### Decision 3: Module Structure

**Decision:** Create separate focused modules (IAM, Lambda, Scheduler).

**Rationale:**
- Aligns with Unix philosophy: "Do one thing well"
- Follows existing codebase pattern
- No external dependencies
- Full control over naming conventions

### Decision 4: Lambda Package Source

**Decision:** Reference pre-built zips from S3 bucket.

**Implementation:**
- **S3 Bucket:** `4shark-lambda-artifacts`
- **S3 Key Pattern:** `{lambda-name}/{version}_{short-sha}.zip`
- **Script `bin/publish_lambda`** publishes to S3 (no version parameter - auto-detects)

### Decision 5: IAM Role Structure

**Decision:** Three Lambda roles with different permissions + one scheduler role.

**Roles:**
- `Lambda-{env}-worker-commission-autoscaling-role` - CloudWatch + ECS + invoke balancing
- `Lambda-{env}-worker-commission-balancing-role` - CloudWatch + ECS only
- `Lambda-{env}-worker-standard-autoscaling-role` - CloudWatch + ECS only (for user, system)
- `EventBridge-{env}-scheduler-role` - invoke Lambda

**Rationale:**
- Commission autoscaling needs permission to invoke balancing Lambda
- Balancing doesn't need invoke permission (invoked, not invoker)
- Standard lambdas (user, system) share the same permissions
- Follows least-privilege principle

### Decision 6: Terraform Variables and Lambda Mapping

**Decision:** Two variables at runtime + fixed lambda mapping in locals.

```bash
cd terraform/lambda-autoscaling
terraform apply \
  -var="lambda_environment=beta-001" \
  -var="lambda_version=1.0.0_a1b2c3d"
```

| Variable | Type | Description | Validation |
|----------|------|-------------|------------|
| `lambda_environment` | string | Environment name | Format: `name-NNN` (e.g., beta-001, shared-002) |
| `lambda_version` | string | Package version | Format: `X.Y.Z_sha` |

**Lambda mapping is fixed in `locals` (like the shell script):**

```hcl
locals {
  lambdas = {
    "commission"           = { package = "worker-commission-autoscaling", schedule = true }
    "commission-balancing" = { package = "worker-commission-balancing", schedule = false }
    "user"                 = { package = "worker-autoscaling", schedule = true }
    "system"               = { package = "worker-autoscaling", schedule = true }
  }
}
```

**Lambda naming computed by Terraform:**
- Key: `commission` → Lambda: `Lambda-beta-001-worker-commission-autoscaling`
- Key: `commission-balancing` → Lambda: `Lambda-beta-001-worker-commission-balancing`
- Key: `user` → Lambda: `Lambda-beta-001-worker-user-autoscaling`
- Key: `system` → Lambda: `Lambda-beta-001-worker-system-autoscaling`

**Note:** commission-balancing has `schedule = false` - it is invoked by commission autoscaling, not by EventBridge.

---

## S3 Structure

```
s3://4shark-lambda-artifacts/
├── worker-autoscaling/
│   ├── 1.0.0_a1b2c3d.zip
│   ├── 0.9.0_f4e5d6c.zip
│   └── ...
└── worker-commission-autoscaling/
    ├── 1.0.0_a1b2c3d.zip
    ├── 0.9.0_f4e5d6c.zip
    └── ...
```

---

## Workflow

### 1. Build Lambda Packages (Lambda repo)

```bash
bin/generate_lambda --all
```

Generates timestamped zips in `dist/`:
- `dist/worker-autoscaling_20260116_143022.zip`
- `dist/worker-commission-autoscaling_20260116_143025.zip`

### 2. Publish to S3 (Lambda repo)

```bash
bin/publish_lambdas
```

**Script behavior (no parameters needed):**
1. Copies artifacts from Docker container to local `dist/`
2. Reads version from `CHANGELOG.md`
3. Gets short SHA: `git rev-parse --short HEAD`
4. Composes version: `1.0.0_a1b2c3d`
5. Validates an artifact exists for each lambda directory
6. Uploads all to S3 with version naming

**Output:**
```
Version: 1.0.0_a1b2c3d

Checking artifacts...
✓ dist/worker-autoscaling_20260116_143022.zip
✓ dist/worker-commission-autoscaling_20260116_143025.zip
✓ dist/worker-commission-balancing_20260116_143028.zip

Uploading to s3://4shark-lambda-artifacts/...
✓ worker-autoscaling/1.0.0_a1b2c3d.zip
✓ worker-commission-autoscaling/1.0.0_a1b2c3d.zip
✓ worker-commission-balancing/1.0.0_a1b2c3d.zip

Done! Version published: 1.0.0_a1b2c3d
```

**Options:**
- `--dry-run` - Show what would be uploaded without executing

### 3. Deploy Infrastructure (Terraform repo)

```bash
cd terraform/lambda-autoscaling
terraform init
terraform apply \
  -var="lambda_environment=beta-001" \
  -var="lambda_version=1.0.0_a1b2c3d"
```

### 4. Configure Lambda Environment Variables (Manual)

After Terraform creates the infrastructure, engineer manually configures environment variables for each Lambda:

| Variable | Example Value |
|----------|---------------|
| ECS_CLUSTER_NAME | beta-001-cluster |
| ECS_SERVICE_NAME | beta-001-worker-commission-service |
| MINIMUM_CAPACITY | 1 |
| MAXIMUM_CAPACITY | 15 |
| PROCESS_NAME | worker_commission |

---

## Module Structure

**IMPORTANT:** Lambda infrastructure is in a separate directory with its own state file.

```
terraform/
├── main.tf                           # ASG infrastructure (existing)
├── variables.tf                      # ASG variables (existing)
├── terraform.tfvars                  # ASG values (existing)
├── modules/
│   └── asg-launch-template/          # ASG module (existing)
│
└── lambda-autoscaling/               # <<< SEPARATE DIRECTORY
    ├── main.tf                       # Lambda orchestration
    ├── variables.tf                  # Lambda variables
    ├── terraform.tfvars              # Static values (bucket, account, region)
    └── modules/
        ├── lambda-iam/               # IAM resources
        │   ├── main.tf               # 4 policies, 4 roles
        │   ├── variables.tf
        │   └── outputs.tf
        ├── lambda-ecs-autoscaling/   # Lambda function
        │   ├── main.tf               # Lambda resource (reads from S3)
        │   ├── variables.tf
        │   └── outputs.tf
        └── eventbridge-scheduler/    # Scheduler
            ├── main.tf               # Schedule resource
            ├── variables.tf
            └── outputs.tf
```

### Module Responsibilities

| Module | Creates | Notes |
|--------|---------|-------|
| `lambda-iam` | 4 policies, 4 roles | Commission, balancing, standard roles + scheduler role |
| `lambda-ecs-autoscaling` | Lambda function | Reads package from S3, no env vars |
| `eventbridge-scheduler` | Schedule | Only for lambdas with `schedule = true` |

### Why Separate Directory?

- **Isolated state file** - Lambda changes don't affect ASG resources
- **Independent `terraform plan/apply`** - No risk of touching EC2 when deploying Lambda
- **Follows best practices** - Different concerns, different state files

---

## Resources Created (per environment)

For `lambda_environment=beta-001`:

| Type | Name | Count |
|------|------|-------|
| IAM Policy | `CloudWatch-beta-001-lambda-logs-policy` | 1 |
| IAM Policy | `ECS-beta-001-lambda-worker-policy` | 1 |
| IAM Policy | `EventBridge-beta-001-lambda-invoke-policy` | 1 |
| IAM Policy | `Lambda-beta-001-invoke-balancing-policy` | 1 |
| IAM Role | `Lambda-beta-001-worker-commission-autoscaling-role` | 1 |
| IAM Role | `Lambda-beta-001-worker-commission-balancing-role` | 1 |
| IAM Role | `Lambda-beta-001-worker-standard-autoscaling-role` | 1 |
| IAM Role | `EventBridge-beta-001-scheduler-role` | 1 |
| Lambda | `Lambda-beta-001-worker-commission-autoscaling` | 1 |
| Lambda | `Lambda-beta-001-worker-commission-balancing` | 1 |
| Lambda | `Lambda-beta-001-worker-user-autoscaling` | 1 |
| Lambda | `Lambda-beta-001-worker-system-autoscaling` | 1 |
| Schedule | `Lambda-beta-001-worker-commission-autoscaling-schedule` | 1 |
| Schedule | `Lambda-beta-001-worker-user-autoscaling-schedule` | 1 |
| Schedule | `Lambda-beta-001-worker-system-autoscaling-schedule` | 1 |

**Total:** 15 resources per environment

**Note:** commission-balancing Lambda has no schedule - it is invoked by commission autoscaling Lambda.

---

## Prerequisites

1. **S3 Bucket exists:** `4shark-lambda-artifacts`
2. **Lambda packages in S3:** Run `bin/publish_lambda` from lambda repo
3. **ECS Cluster exists:** `{env}-001-cluster`
4. **ECS Services exist:** `{env}-001-worker-{service}-service`

---

## Migration Strategy

Deploy to beta-001 first, validate, then deploy to other environments:

```bash
cd terraform/lambda-autoscaling
terraform init

# 1. Deploy beta-001
terraform apply \
  -var="lambda_environment=beta-001" \
  -var="lambda_version=1.0.0_a1b2c3d"

# 2. Configure env vars manually in AWS Console, test

# 3. Deploy demo-001
terraform apply \
  -var="lambda_environment=demo-001" \
  -var="lambda_version=1.0.0_a1b2c3d"

# 4. Continue with shared-001, atento-001...
```

---

## Problems Found and Solutions

### Problem 1: Lambda Package Versioning

**Problem:** Initial approach used local zip files with timestamps. This creates issues:
- Terraform needs files at apply time
- No version control for deployed packages
- Hard to rollback or track which version is deployed

**Solution:** S3 bucket with version+SHA naming (`1.0.0_a1b2c3d.zip`)
- Version comes from project's CHANGELOG/VERSION
- SHA provides exact git commit traceability
- Multiple versions coexist in S3 (no overwrites)
- Rollback = deploy different version string

### Problem 2: Deploy All Environments at Once

**Problem:** Initial implementation created all 4 environments in a single terraform apply with version per environment variables:
```bash
-var="lambda_version_beta=1.0.0_abc"
-var="lambda_version_demo=0.9.0_xyz"
...
```

This is problematic because:
- Each environment may have different lambdas
- Different schedules per environment
- Blast radius too large for initial setup
- This Terraform is for infrastructure, not continuous deployment

**Solution:** Deploy one environment at a time with fixed lambda mapping in locals:
```bash
-var="lambda_environment=beta-001"
-var="lambda_version=1.0.0_a1b2c3d"
```

### Problem 3: Lambda Naming Consistency

**Problem:** Allowing engineers to specify full lambda names could lead to inconsistent naming:
```bash
-var='lambdas={
  "Lambda-beta-worker-commission": "...",  # Wrong!
  "commission-autoscaling": "...",          # Wrong!
}'
```

**Solution:** Engineer provides only the service identifier, Terraform computes the full name:
- Input: `"commission": "worker-commission-autoscaling"`
- Output: `Lambda-beta-001-worker-commission-autoscaling`
- Validation: Keys cannot contain "worker" or "autoscaling"

### Problem 4: Lambda Environment Variables in Terraform

**Problem:** Initial implementation included environment variables in Terraform:
```hcl
environment {
  variables = {
    ECS_CLUSTER_NAME = var.ecs_cluster_name
    ECS_SERVICE_NAME = var.ecs_service_name
    MINIMUM_CAPACITY = var.minimum_capacity
    MAXIMUM_CAPACITY = var.maximum_capacity
    PROCESS_NAME     = var.process_name
  }
}
```

Issues:
- Business logic coupled to Terraform
- Values vary per lambda and per environment
- Engineer loses control over configuration

**Solution:** Remove environment variables from Terraform entirely. Engineer configures them manually in AWS Console after deployment.
- Terraform creates infrastructure (IAM, Lambda, Scheduler)
- Engineer configures behavior (environment variables)

### Problem 5: Commission Balancing Lambda

**Problem:** Commission processes need a balancing mechanism when multiple instances are running. The commission-autoscaling Lambda needs to invoke commission-balancing Lambda to redistribute work.

**Solution:** Three separate Lambda roles:
- `Lambda-{env}-worker-commission-autoscaling-role` - CloudWatch + ECS + **invoke balancing**
- `Lambda-{env}-worker-commission-balancing-role` - CloudWatch + ECS only
- `Lambda-{env}-worker-standard-autoscaling-role` - CloudWatch + ECS only (for user, system)

Plus a new policy:
- `Lambda-{env}-invoke-balancing-policy` - Permission to invoke commission-balancing Lambda

**Why separate roles:**
- Commission-autoscaling needs extra permission to invoke balancing
- Balancing doesn't need invoke permission (least privilege)
- Standard lambdas (user, system) don't need invoke permission

### Problem 6: Publish Script Version Parameter

**Problem:** Initial design required passing version to publish script:
```bash
bin/publish_lambda --version 1.0.0_a1b2c3d
```

Issues:
- Redundant - version is in CHANGELOG/VERSION
- SHA can be computed from git
- Risk of human error (wrong version)

**Solution:** Script auto-detects everything:
```bash
bin/publish_lambda  # No parameters
```
- Reads version from CHANGELOG.md or VERSION file
- Gets SHA from `git rev-parse --short HEAD`
- Validates all required zips exist before uploading

### Problem 7: Terraform Removes Lambda Environment Variables on Update

**Problem:** Running `terraform apply` to update Lambda code removes existing environment variables because they are not defined in the Terraform configuration.

**Solution:** Added `lifecycle { ignore_changes = [environment] }` to the Lambda resource. This allows:
1. **Setup:** Terraform creates Lambda without environment variables
2. **Manual config:** Engineer configures environment variables in AWS Console
3. **Updates:** Terraform updates Lambda code while preserving existing environment variables

---

## Implementation Notes

### Beta-001 Import

Beta-001 already had Lambda infrastructure created via shell script. To avoid recreating resources, we used Terraform's declarative import blocks (Terraform 1.5+) to import 17 existing resources into the state file. After import, Terraform applied minor changes (tags and S3 configuration) to align resources with the code.

The import blocks were removed from the codebase after successful import since they are single-use and would cause errors if applied to new environments where the resources don't exist.

### Commission-Balancing Lambda

The commission-balancing Lambda and related IAM resources are defined in the code but **commented out**. This is because beta-001 doesn't have a commission-balancing Lambda - only other environments (like Atento-001) use it.

When creating new environments that need commission-balancing:
1. Uncomment the resources in `modules/lambda-iam/main.tf`
2. Uncomment the outputs in `modules/lambda-iam/outputs.tf`
3. Uncomment the entry in `locals.lambdas` in `main.tf`

### S3 Bucket

The S3 bucket `4shark-lambda-artifacts` was created manually with versioning enabled. It stores Lambda deployment packages with the naming pattern `{lambda-name}/{version}_{sha}.zip`.

---

## Success Criteria (Validated)

1. ✅ `terraform plan` shows expected resources for the specified environment
2. ✅ `terraform apply` creates all resources successfully
3. ✅ Lambda functions are created with correct IAM roles
4. ✅ EventBridge schedules are created and enabled
5. ✅ Engineer can configure environment variables post-deployment
6. ✅ Lambda functions execute successfully and scale ECS services
7. ✅ Lambda version updates work via Terraform without losing environment variables

---

## References

- Previous feature: `~/.claude/plans/completed/lambda-ecs-tasks/`
- Shell script: `~/.claude/plans/completed/lambda-ecs-tasks/setup-lambda-env.sh`
- Naming convention: `~/.claude/plans/completed/lambda-ecs-tasks/IAM-NAMING-CONVENTION.md`
- Terraform repo: `~/Projects/4Shark/terraform/`
- Lambda repo: `~/Projects/4Shark/lambda/`
