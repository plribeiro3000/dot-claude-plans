# CodeDeploy Hook Lambda: Python to Ruby Migration

## Status: Completed (2026-02-23)

## Context

The `codedeploy-hook-lambda-{environment}` Lambda is defined **inline** in the Terraform module `modules/codedeploy/`:
- Python code at `modules/codedeploy/lambda_function.py`
- Packaged via `archive_file` (local zip)
- Runtime: `python3.9`
- Function: receives CodeDeploy event (BeforeAllowTraffic), stores `DeploymentId` and `HookExecutionId` in SSM Parameter Store, and **does not return success** — pausing the deployment for external approval

Existing Ruby lambdas (`worker-autoscaling`, `worker-commission-autoscaling`, `worker-commission-balancing`) follow a different pattern:
- Code in `/Projects/4Shark/lambda/` repo
- Build via Docker (`public.ecr.aws/lambda/ruby:3.4`)
- Artifacts published to S3 (`s3://4shark-lambda-artifacts/{name}/{version}_{sha}.zip`)
- Terraform uses `lambda-ecs-autoscaling` module that reads the artifact from S3

## Goal

Migrate the CodeDeploy hook lambda from inline Python to Ruby in the `lambda/` repo, following the same build/publish/deploy pattern as the existing Ruby lambdas.

## Projects Involved

- **lambda**: New Ruby lambda code + build script updates
- **terraform**: Module and environment configuration changes

---

## Changes

### 1. Repo `lambda/` — New Ruby Lambda

**Create `lambda/codedeploy-hook/`:**
- `Gemfile` with `aws-sdk-codedeploy` and `aws-sdk-ssm`
- `lambda_function.rb` with the logic translated from Python to Ruby
- `README.md` with documentation

**Lambda logic (direct translation):**
1. Receive `event` with `DeploymentId`, `LifecycleEventHookExecutionId`, `LifecycleEvent`
2. Store the IDs in SSM Parameter Store (`/codedeploy-hooks/{deployment_id}/...`)
3. On SSM error, signal `Failed` to CodeDeploy
4. Do NOT signal `Succeeded` — deployment stays paused

**Update build/publish scripts:**
- `bin/generate_lambda`: `discover_lambdas()` uses glob `worker-*/` — needs to be changed to discover any directory containing `lambda_function.rb` (or `Gemfile`), making discovery generic
- `bin/publish_lambdas`: Same change to `discover_lambdas()`
- This allows `codedeploy-hook/` to be discovered automatically without the `worker-*` naming convention

### 2. Repo `terraform/` — Module `modules/codedeploy/`

**Remove:**
- `lambda_function.py` (Python code)
- `data "archive_file" "hook_lambda_zip"` (inline zip)

**Modify `aws_lambda_function.codedeploy_hook_lambda`:**
- From: `filename` + `source_code_hash` (local file)
- To: `s3_bucket` + `s3_key` + `source_code_hash` (S3 artifact, same as `lambda-ecs-autoscaling` module)
- Runtime: `python3.9` → `ruby3.4`
- Handler stays: `lambda_function.lambda_handler` (same Ruby pattern)

**Add variables to module:**
- `lambda_s3_bucket` (string) — S3 bucket for artifacts
- `lambda_version` (string) — artifact version (format: `version_sha`, e.g., `0.7.0_06edcd9`)

**Rename Lambda function:**
- From: `codedeploy-hook-lambda-{environment}`
- To: `Lambda-{environment}-codedeploy-hook` (standardized naming, same pattern as autoscaling lambdas)
- This causes a destroy+create of the Lambda function and its permission

**Add data source:**
- `data "aws_s3_object"` to fetch artifact etag (for `source_code_hash`)

**Keep intact** (already exist and are correct):
- IAM role + policy (SSM, CodeDeploy, CloudWatch permissions)
- `aws_lambda_permission` (CodeDeploy → Lambda)
- Outputs (`hook_lambda_name`, `hook_lambda_arn`)
- Conditional logic with `enable_hook_lambda`

### 3. Repo `terraform/` — Environments (`shared-001/`, `demo-001/`, `beta-001/`, `atento-001/`)

**In each environment that uses the codedeploy module:**
- Centralize `lambda_s3_bucket` and `lambda_version` in each environment's `locals` block
- Pass `lambda_s3_bucket` and `lambda_version` to the codedeploy module
- Remove `lambda_s3_bucket` and `lambda_version` from `variables.tf` and `terraform.tfvars` (centralized in `locals`)

### 4. Repo `app/` — Update GitHub Environment Variables

**After Terraform apply, update `CODEDEPLOY_HOOK_LAMBDA_ARN` in each GitHub environment:**
- All 4 deploy workflows (`deploy-beta-001.yaml`, `deploy-demo-001.yaml`, `deploy-shared-001.yaml`, `deploy-atento-001.yaml`) read the hook lambda ARN from `${{ vars.CODEDEPLOY_HOOK_LAMBDA_ARN }}`
- The ARN is injected into the AppSpec dynamically via jq in the `deploy-web` job
- New ARN values after apply:
  - `beta-001`: `arn:aws:lambda:us-east-1:405749097490:function:Lambda-beta-001-codedeploy-hook`
  - `demo-001`: `arn:aws:lambda:us-east-1:405749097490:function:Lambda-demo-001-codedeploy-hook`
  - `shared-001`: `arn:aws:lambda:us-east-1:405749097490:function:Lambda-shared-001-codedeploy-hook`
  - `atento-001`: `arn:aws:lambda:us-east-1:405749097490:function:Lambda-atento-001-codedeploy-hook`

**`setup/` environment:** Already uses `enable_hook_lambda = false`, no changes needed.

---

## Execution Order

1. **Lambda repo** — Create Ruby code and update build scripts ✅
2. **Build & Publish** — Generate artifact and publish to S3 (release 0.7.0, SHA 06edcd9) ✅
3. **Terraform module** — Change `modules/codedeploy/` to use S3 + rename function ✅
4. **Terraform environments** — Centralize config in `locals`, pass to codedeploy module ✅
5. **Terraform apply** — Apply per environment (lambda will be destroyed+created with new name and Ruby runtime)
6. **GitHub env vars** — Update `CODEDEPLOY_HOOK_LAMBDA_ARN` in all 4 GitHub environments (beta-001, demo-001, shared-001, atento-001)

---

## Risks and Considerations

- **Zero downtime**: The lambda is only called during deployments. If no deploy is in progress, the swap is transparent.
- **Resource recreation**: Changing from `filename` → `s3_bucket` + runtime change will force lambda recreation. The existing `lifecycle { ignore_changes = [source_code_hash, last_modified] }` does not prevent this.
- **Name standardized**: Renamed from `codedeploy-hook-lambda-{environment}` to `Lambda-{environment}-codedeploy-hook` (same pattern as autoscaling lambdas). This forces destroy+create of the Lambda function and its permission. Requires updating `CODEDEPLOY_HOOK_LAMBDA_ARN` GitHub environment variable in all 4 environments after Terraform apply.
- **Same release**: The new lambda is published alongside the others (same CHANGELOG version), so `lambda_version` continues pointing to all artifacts.

---

## Key Files Reference

| File | Description |
|------|-------------|
| `terraform/modules/codedeploy/main.tf` (L188-235) | Current inline Python lambda + permission |
| `terraform/modules/codedeploy/lambda_function.py` | Current Python code (to be removed) |
| `terraform/modules/codedeploy/variables.tf` (L96-100) | `enable_hook_lambda` variable |
| `terraform/modules/lambda-ecs-autoscaling/main.tf` | Reference pattern for S3-based lambda |
| `lambda/worker-autoscaling/lambda_function.rb` | Reference pattern for Ruby handler |
| `lambda/bin/generate_lambda` | Build script (needs discovery update) |
| `lambda/bin/publish_lambdas` | Publish script (needs discovery update) |
| `terraform/shared-001/main.tf` (L478-505) | codedeploy module usage example |
