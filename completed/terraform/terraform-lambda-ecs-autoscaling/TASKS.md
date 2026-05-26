# TASKS — Terraform: Lambda ECS Autoscaling Infrastructure

> **Status:** Complete - PR #106 Merged
> **Projects:** lambda, terraform

---

## Tasks

### Phase 0: Lambda Repository Updates (Project: `lambda`) ✅ DONE

- [x] Create S3 bucket `4shark-lambda-artifacts` with versioning enabled
- [x] Create `bin/publish_lambda` script
  - [x] Auto-detect version from CHANGELOG.md or VERSION
  - [x] Auto-detect SHA from `git rev-parse --short HEAD`
  - [x] Validate ALL required zips exist in `dist/`
  - [x] Fail if any zip is missing
  - [x] Upload all zips to S3 with `{lambda-name}/{version}_{sha}.zip` naming
  - [x] `--dry-run` option to show what would be uploaded
  - [x] `--force` option to overwrite existing files
- [x] Update DEPLOYMENT.md with new workflow
- [x] Add Docker environment check to `bin/generate_lambda`

### Phase 1: IAM Module (Project: `terraform`) ✅ DONE

- [x] Create `lambda-autoscaling/modules/lambda-iam/` directory
- [x] Create `modules/lambda-iam/variables.tf` with input variables
- [x] Create `modules/lambda-iam/main.tf` with IAM policies and roles
  - [x] 4 policies: CloudWatch logs, ECS worker, EventBridge invoke, invoke balancing
  - [x] 4 roles: commission-autoscaling, commission-balancing, standard-autoscaling, scheduler
- [x] Create `modules/lambda-iam/outputs.tf` with role ARNs

### Phase 2: Lambda Module (Project: `terraform`) ✅ DONE

- [x] Create `lambda-autoscaling/modules/lambda-ecs-autoscaling/` directory
- [x] Create `modules/lambda-ecs-autoscaling/variables.tf`
  - [x] S3 bucket and key variables (no filename)
  - [x] Removed environment variables (configured manually)
- [x] Create `modules/lambda-ecs-autoscaling/main.tf`
  - [x] Read package from S3
  - [x] Use S3 object ETag for source_code_hash
  - [x] No environment variables block
- [x] Create `modules/lambda-ecs-autoscaling/outputs.tf`

### Phase 3: Scheduler Module (Project: `terraform`) ✅ DONE

- [x] Create `lambda-autoscaling/modules/eventbridge-scheduler/` directory
- [x] Create `modules/eventbridge-scheduler/variables.tf`
- [x] Create `modules/eventbridge-scheduler/main.tf`
- [x] Create `modules/eventbridge-scheduler/outputs.tf`

### Phase 4: Integration (Project: `terraform`) ✅ DONE

- [x] Create separate `lambda-autoscaling/` directory (isolated state)
- [x] Create `lambda-autoscaling/variables.tf` with:
  - [x] `lambda_environment` - Environment name with validation
  - [x] `lambda_version` - Version string with format validation
  - [x] `aws_account_id`, `aws_region`, `lambda_s3_bucket`, `lambda_schedule_expression`
- [x] Create `lambda-autoscaling/main.tf` with:
  - [x] Fixed lambda mapping in `locals` (not passed as variable)
  - [x] Single IAM module call per environment
  - [x] Lambda modules using `for_each = local.lambdas`
  - [x] Scheduler modules only for lambdas with `schedule = true`
  - [x] Role assignment based on lambda type (commission/balancing/standard)
- [x] Create `lambda-autoscaling/terraform.tfvars` with static values
- [x] Ensure root terraform files are NOT modified (only additions)

### Phase 5: PRs ✅ DONE

- [x] Create PR for Lambda project (target: develop) - PR #8 ✅ Merged
- [x] Create PR for Terraform project (target: develop) - PR #106 ✅ Merged

---

## Usage

### Deploy Infrastructure

```bash
cd terraform/lambda-autoscaling
terraform init
terraform apply \
  -var="lambda_environment=beta-001" \
  -var="lambda_version=1.0.0_a1b2c3d"
```

### Resources Created

For the command above (beta-001 environment):

| Resource | Name |
|----------|------|
| IAM Policy | `CloudWatch-beta-001-lambda-logs-policy` |
| IAM Policy | `ECS-beta-001-lambda-worker-policy` |
| IAM Policy | `EventBridge-beta-001-lambda-invoke-policy` |
| IAM Policy | `Lambda-beta-001-invoke-balancing-policy` |
| IAM Role | `Lambda-beta-001-worker-commission-autoscaling-role` |
| IAM Role | `Lambda-beta-001-worker-commission-balancing-role` |
| IAM Role | `Lambda-beta-001-worker-standard-autoscaling-role` |
| IAM Role | `EventBridge-beta-001-scheduler-role` |
| Lambda | `Lambda-beta-001-worker-commission-autoscaling` |
| Lambda | `Lambda-beta-001-worker-commission-balancing` |
| Lambda | `Lambda-beta-001-worker-user-autoscaling` |
| Lambda | `Lambda-beta-001-worker-system-autoscaling` |
| Schedule | `Lambda-beta-001-worker-commission-autoscaling-schedule` |
| Schedule | `Lambda-beta-001-worker-user-autoscaling-schedule` |
| Schedule | `Lambda-beta-001-worker-system-autoscaling-schedule` |

**Note:** commission-balancing Lambda has no schedule (invoked by commission-autoscaling).

---

## Notes

- **Separate directory:** Lambda infrastructure is in `terraform/lambda-autoscaling/` with its own state
- **S3 bucket:** `4shark-lambda-artifacts`
- **S3 key pattern:** `{lambda-name}/{version}_{sha}.zip`
- **Lambda mapping:** Fixed in `locals`, not passed as variable (like the shell script)
- **Environment variables:** Configured manually in AWS Console, preserved by Terraform during updates
- **Deploy one environment at a time** (not all at once)
- **commission-balancing:** Has no EventBridge schedule - invoked by commission-autoscaling Lambda
- **Root terraform files:** Were NOT modified - only new directory was added

## Infrastructure Decisions

- **State management:** Local state only (no remote backend with S3/DynamoDB to avoid extra cost)
- **`.tfstate` in `.gitignore`:** State file is NOT committed - must always run from the same machine
- **Environment validation:** Accepts any `name-NNN` format (e.g., beta-001, shared-002, demo-003)
- **Lambda mapping:** Fixed in `locals` block, not passed as variable
- **Environment variables:** Managed manually in AWS Console. Terraform uses `lifecycle { ignore_changes = [environment] }` to preserve them during updates
- **Beta-001 import:** Existing resources were imported into Terraform state (17 resources). Terraform now manages beta-001
- **Updates via Terraform:** With `ignore_changes`, Terraform can update Lambda code without removing environment variables
- **Commission-balancing commented:** Beta-001 doesn't have commission-balancing Lambda, so related resources are commented out in the code. Uncomment when creating new environments that need it.
