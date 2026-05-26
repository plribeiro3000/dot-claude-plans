# TASKS — GitHub Environments to Terraform SSM Migration (Tier 1)

**Reference PLAN**: `~/.claude/plans/active/terraform/github-envs-to-terraform-ssm/PLAN.md`

**Reference Implementation**: `terraform/integrator-almaviva/ssm.tf` + `terraform/integrator-almaviva/compute.tf`

## Status (2026-03-21)

All Terraform tasks (Phases 1–4) complete. Validated with `terraform plan` — No changes across all 6 stacks.
Phase 5 (cross-plan update) complete.

**GitHub Actions progress**:
- ✅ **setup** (Tasks 1.8–1.10): action fixed, Dockerfile fixed, workflow updated. Deploy validated (GH run 23382179903).
- ✅ **onboarding** (Tasks 2.8–2.9): action fixed, workflow updated. Build (23382557820) + Deploy (23382573377) validated.
- ✅ **app** (Phases 3+4): PR #4879 merged. Deploys validated for beta-001, demo-001, shared-001, atento-001 (2026-03-21). GitHub Environments stripped — 0 variables, secrets reduzidos a AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY + MIGRATION_DATABASE_URL + REDIS_LOCK_URL (+ REDIS_SIDEKIQ_URL para atento/shared).
- ✅ **integrator almaviva**: PR #2057 merged. Deploy validado (run 23390838779). GitHub Environment limpo — 0 variáveis, apenas AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY. Pipeline image-only via `deploy-almaviva.yaml` dedicado.
- ✅ **setup Task 1.11**: GitHub Environment "Production" clean — 0 variables, only AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY
- ✅ **onboarding Task 2.10**: GitHub Environment "Production" clean — 0 variables, only AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY + REDIS_LOCK_URL + REDIS_SIDEKIQ_URL

**Key decisions (2026-03-21)**:
- GitHub Environments are NOT deleted — they are stripped to `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` only (onboarding also keeps `REDIS_LOCK_URL` + `REDIS_SIDEKIQ_URL` — used directly by runner for Redis lock operations)
- Deploy action is fixed to only update `.image` in the task def — never touches `environment` or `secrets`
- DIFFEND vars removed from Docker build args; `.diffend.yml` already in repo handles Diffend config
- All infrastructure vars (CLUSTER_NAME, CODEDEPLOY_*, etc.) hardcoded in workflow `env:` block

---

## PHASE 1: setup (Smallest stack, 1 service, 10 secrets)

### Task 1.1: Create feature branch for setup migration

**File**: None (git operation)

**Steps**:
1. From terraform repo root, create feature branch: `git checkout -b feature/terraform-ssm-setup`
2. Confirm branch is created and tracked

**Success**: Branch exists and is current working branch

---

### Task 1.2: Export current env var values from setup ECS task definition

**File**: Export to `/tmp/setup_env_values_20260321.txt` for reference

**Steps**:
1. Run: `AWS_PROFILE=4shark-elevated aws ecs describe-task-definition --task-definition setup-web --region us-east-1 --query 'taskDefinition.containerDefinitions[0].{environment: environment, secrets: secrets}' > /tmp/setup_task_def_20260321.json`
2. Extract and document all current values for the 10 secrets:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `DIFFEND_PROJECT_ID`
   - `DIFFEND_SHAREABLE_ID`
   - `DIFFEND_SHAREABLE_KEY`
   - `RAILS_MASTER_KEY`
   - `ROLLBAR_CLIENT_ACCESS_TOKEN`
   - `ROLLBAR_SERVER_ACCESS_TOKEN`
   - `SECRET_KEY_BASE`
   - `SETUP_DATABASE_URL`
3. Document the 10 non-sensitive vars from `environment` field for later use in `locals.env_vars`
4. Save values in secure location (not in git) — these will be used in task 1.6

**Success**: Current ECS task definition values extracted and documented

---

### Task 1.3: Create ssm.tf for setup stack

**File**: `/Users/plribeiro3000/Projects/4Shark/terraform/setup/ssm.tf`

**Content**: Follow `integrator-almaviva/ssm.tf` pattern exactly, adjusting:
- Stack name from `integrator-almaviva` → `setup`
- KMS key: use `arn:aws:kms:us-east-1:405749097490:key/mrk-fa0cda243274491784fc7b39bead5a03`
- SSM path prefix: `/setup/` (not `/integrator-almaviva/`)
- Secret names: exact 10 from PLAN.md variable classification (AWS_ACCESS_KEY_ID through SECRET_KEY_BASE, SETUP_DATABASE_URL)
- Region: us-east-1 (not sa-east-1)
- IAM policy: update resource ARN to `/setup/*` path
- IAM role_policy: attach to `ecsTaskExecutionRole` (same as almaviva)

**Structure**:
```
locals {
  ssm_secret_names = toset([
    "AWS_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY",
    ...
  ])
}

resource "aws_ssm_parameter" "secrets" { ... }

resource "aws_iam_role_policy" "ecs_ssm_read" { ... }
```

**Success**: `ssm.tf` created with correct variable names, KMS key, region, and path prefix

---

### Task 1.4: Update setup/main.tf with locals.env_vars and wire into service definition

**File**: `/Users/plribeiro3000/Projects/4Shark/terraform/setup/main.tf`

**Steps**:
1. Read current `setup/main.tf` to understand how services are defined (module calls or inline)
2. Add `locals.env_vars` block with the 10 non-sensitive variables (from task 1.2):
   - CLUSTER_NAME
   - CODEDEPLOY_APP_NAME
   - CODEDEPLOY_DEPLOYMENT_GROUP
   - CODEDEPLOY_HOOK_LAMBDA_ARN
   - ENVIRONMENT
   - LANG
   - RACK_ENV
   - RAILS_ENV
   - RAILS_LOG_TO_STDOUT
   - RAILS_SERVE_STATIC_FILES
3. Add `locals.secrets` list with mappings to `aws_ssm_parameter.secrets[*].arn` (like almaviva pattern)
4. Update the ECS service module call (setup-web) to pass `environment_variables = local.env_vars` and `secrets = local.secrets`
5. Remove any existing hardcoded env vars from the service definition

**Success**: `locals.env_vars` block added, `locals.secrets` block created, service module wired correctly

---

### Task 1.5: Run terraform plan and save plan file

**File**: `/tmp/terraform_plan_setup_us_east_1_20260321.tfplan`

**Steps**:
1. Change to `terraform/setup/` directory
2. Run: `AWS_PROFILE=4shark-elevated terraform init` (if needed)
3. Run: `AWS_PROFILE=4shark-elevated terraform plan -out=/tmp/terraform_plan_setup_us_east_1_20260321.tfplan 2>&1 | tee /tmp/terraform_plan_setup_us_east_1_20260321.log`
4. Review plan output for:
   - 10 new SSM parameters created (name pattern `/setup/AWS_*`, `/setup/DIFFEND_*`, etc.)
   - 1 new IAM role policy attached to `ecsTaskExecutionRole`
   - ECS task definition updated with new `secrets` references (ARNs from SSM)
   - No destroyed resources
5. Note the plan summary (N added, M changed, 0 destroyed)

**Success**: Plan file saved with expected resource additions and no unexpected changes

---

### Task 1.6: Apply terraform plan (requires approval first)

**File**: Same plan file `/tmp/terraform_plan_setup_us_east_1_20260321.tfplan`

**Prerequisites**: User approval of plan from task 1.5

**Steps**:
1. With plan file ready, run: `AWS_PROFILE=4shark-elevated terraform apply /tmp/terraform_plan_setup_us_east_1_20260321.tfplan`
2. Verify output shows:
   - 10 SSM parameters created
   - 1 IAM policy created/updated
   - No destroyed resources
3. Commit the terraform changes (ssm.tf + main.tf updates)

**Success**: Terraform apply completed, 10 SSM parameters exist in AWS, IAM policy attached

---

### Task 1.7: Populate SSM parameter values with actual secrets

**File**: Values from task 1.2

**Steps**:
1. For each of the 10 secrets, run (using values from task 1.2):
   ```bash
   AWS_PROFILE=4shark-elevated aws ssm put-parameter \
     --name "/setup/<SECRET_NAME>" \
     --value "<VALUE>" \
     --type SecureString \
     --overwrite \
     --region us-east-1
   ```
2. Secrets to populate:
   - AWS_ACCESS_KEY_ID
   - AWS_SECRET_ACCESS_KEY
   - DIFFEND_PROJECT_ID
   - DIFFEND_SHAREABLE_ID
   - DIFFEND_SHAREABLE_KEY
   - RAILS_MASTER_KEY
   - ROLLBAR_CLIENT_ACCESS_TOKEN
   - ROLLBAR_SERVER_ACCESS_TOKEN
   - SECRET_KEY_BASE
   - SETUP_DATABASE_URL
3. Verify each parameter was created: `AWS_PROFILE=4shark-elevated aws ssm get-parameter --name "/setup/<NAME>" --region us-east-1 --query 'Parameter.{Name: Name, Type: Type}' --output table`

**Success**: All 10 SSM parameters populated with correct values (no PLACEHOLDER values remaining)

---

### Task 1.8: Fix deploy-ecs action in setup repo

**File**: `setup/.github/actions/deploy-ecs/action.yaml`

**Steps**:
1. Remove inputs `secrets-json` and `vars-json`
2. In "Setup environment" step: remove DIFFEND_ from the secret regex (keep only AWS credentials)
3. In "Build and Push Image" step: remove DIFFEND_PROJECT_ID/SHAREABLE_ID/SHAREABLE_KEY build args
4. In "Register Task Definition" step: remove env-vars.json/env-secrets.json/env-merged.json generation; remove `.environment = $ENVS[0]` from jq; keep only `.image` update

**Success**: Action only updates the Docker image, preserves all other task def fields

---

### Task 1.9: Fix Dockerfile in setup repo

**File**: `setup/.github/docker/web/Dockerfile`

**Steps**:
1. Remove `ARG DIFFEND_PROJECT_ID`, `ARG DIFFEND_SHAREABLE_ID`, `ARG DIFFEND_SHAREABLE_KEY`
2. Change `COPY Gemfile Gemfile.lock ./` to `COPY Gemfile Gemfile.lock .diffend.yml ./`
   (`.diffend.yml` already exists in the repo with correct values)

**Success**: Dockerfile uses `.diffend.yml` file instead of build args for Diffend config

---

### Task 1.10: Update setup deploy workflow

**File**: `setup/.github/workflows/deploy.yaml`

**Steps**:
1. Hardcode infrastructure vars in the `env:` block (replace all `${{ vars.* }}`):
   - `CLUSTER_NAME: setup-cluster`
   - `ENVIRONMENT: setup`
   - `WEB_SERVICE_NAME: setup-web`
   - `WEB_ECR_REPO: 405749097490.dkr.ecr.us-east-1.amazonaws.com/setup-web`
   - `WEB_ASG_NAME: setup-web-asg`
   - `CODEDEPLOY_APP_NAME: setup-web-app`
   - `CODEDEPLOY_DEPLOYMENT_GROUP: setup-web-dg`
2. Remove `secrets-json: ${{ toJSON(secrets) }}` and `vars-json: ${{ toJSON(vars) }}` from the action call
3. Keep `environment: Production` on all jobs — DO NOT remove it (runner still needs AWS credentials from there)

**Success**: Workflow no longer injects env vars; infrastructure vars are hardcoded; GitHub Environment remains for AWS credentials

---

### Task 1.11: Strip GitHub Environment "Production" in setup repo

**File**: GitHub repo settings

**Steps**:
1. Go to setup repository settings → Environments → Production
2. Remove all secrets and variables **except** `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`
3. Confirm that only those 2 secrets remain

**Success**: GitHub Environment `Production` contains only deploy credentials

---

## PHASE 2: onboarding (Fargate stack, 14 secrets, 8 vars)

### Task 2.1: Create feature branch for onboarding migration (or reuse if still in same PR)

**File**: None (git operation)

**Steps**:
1. If setup branch is still current, continue with same branch
2. If new branch needed: `git checkout -b feature/terraform-ssm-onboarding`

**Success**: Working branch exists for onboarding changes

---

### Task 2.2: Export current env var values from onboarding ECS task definition

**File**: Export to `/tmp/onboarding_env_values_20260321.txt`

**Steps**:
1. Run: `AWS_PROFILE=4shark-elevated aws ecs describe-task-definition --task-definition onboarding-web --region us-east-1 --query 'taskDefinition.containerDefinitions[0].{environment: environment, secrets: secrets}' > /tmp/onboarding_task_def_20260321.json`
2. Extract all current values for secrets and variables
3. Special attention: Confirm actual value of `RAILS_SERVE_STATIC_FILES` — PLAN.md notes it appears as a GH secret but is non-sensitive, so it should move to `env_vars` after confirmation
4. Document the 8 non-sensitive vars from `environment` field

**Success**: Current onboarding ECS task definition values extracted

---

### Task 2.3: Create ssm.tf for onboarding stack

**File**: `/Users/plribeiro3000/Projects/4Shark/terraform/onboarding/ssm.tf`

**Content**: Follow Task 1.3 pattern:
- Stack name: `onboarding`
- KMS key: same `arn:aws:kms:us-east-1:405749097490:key/mrk-fa0cda243274491784fc7b39bead5a03`
- SSM path prefix: `/onboarding/`
- Secret names: 13 secrets (14 GH secrets minus `RAILS_SERVE_STATIC_FILES`):
  - AWS_ACCESS_KEY_ID
  - AWS_SECRET_ACCESS_KEY
  - DOMAIN
  - GOOGLE_CLIENT_ID
  - GOOGLE_CLIENT_SECRET
  - GOOGLE_REFRESH_TOKEN
  - MAIL_SENDER
  - MIGRATION_DATABASE_URL
  - ONBOARDING_DATABASE_URL
  - REDIS_LOCK_URL
  - REDIS_SIDEKIQ_URL
  - REDIS_URL
  - SECRET_KEY_BASE
- Region: us-east-1

**Success**: `onboarding/ssm.tf` created

---

### Task 2.4: Update onboarding/main.tf with locals.env_vars and wire into service definition

**File**: `/Users/plribeiro3000/Projects/4Shark/terraform/onboarding/main.tf`

**Steps**:
1. Read current `onboarding/main.tf`
2. Add `locals.env_vars` with the 8 non-sensitive vars (plus `RAILS_SERVE_STATIC_FILES` if confirmed non-sensitive):
   - CLUSTER_NAME
   - CODEDEPLOY_APP_NAME
   - CODEDEPLOY_DEPLOYMENT_GROUP
   - CODEDEPLOY_HOOK_LAMBDA_ARN
   - ECS_PRIVATE_SUBNETS
   - ECS_TASK_SECURITY_GROUP
   - ENVIRONMENT
   - WEB_SERVICE_NAME
   - RAILS_SERVE_STATIC_FILES (if non-sensitive after task 2.2)
3. Add `locals.secrets` list with SSM parameter ARN mappings
4. Update service module to use `environment_variables = local.env_vars` and `secrets = local.secrets`

**Success**: `locals.env_vars` and `locals.secrets` blocks added, service module wired

---

### Task 2.5: Run terraform plan for onboarding

**File**: `/tmp/terraform_plan_onboarding_us_east_1_20260321.tfplan`

**Steps**:
1. Change to `terraform/onboarding/`
2. Run: `AWS_PROFILE=4shark-elevated terraform init` (if needed)
3. Run: `AWS_PROFILE=4shark-elevated terraform plan -out=/tmp/terraform_plan_onboarding_us_east_1_20260321.tfplan 2>&1 | tee /tmp/terraform_plan_onboarding_us_east_1_20260321.log`
4. Review plan for 13 SSM parameters, 1 IAM policy, task def update with secrets

**Success**: Plan file saved

---

### Task 2.6: Apply terraform plan for onboarding (requires approval)

**File**: Same plan file

**Prerequisites**: User approval of plan

**Steps**:
1. Run: `AWS_PROFILE=4shark-elevated terraform apply /tmp/terraform_plan_onboarding_us_east_1_20260321.tfplan`
2. Commit terraform changes

**Success**: 13 SSM parameters created, IAM policy attached

---

### Task 2.7: Populate onboarding SSM parameter values

**File**: Values from task 2.2

**Steps**:
1. For each of 13 secrets, run: `AWS_PROFILE=4shark-elevated aws ssm put-parameter --name "/onboarding/<NAME>" --value "<VALUE>" --type SecureString --overwrite --region us-east-1`
2. Verify each parameter created

**Success**: All 13 SSM parameters populated

---

### Task 2.8: Fix deploy action in onboarding repo

**File**: `onboarding/.github/actions/deploy/action.yaml`

**Steps**:
1. Remove inputs `secrets-json` and `vars-json`
2. In "Register Task Definition" step: remove env-vars.json/env-secrets.json/env-merged.json generation; keep only `.image` update
3. (No DIFFEND changes needed — onboarding Dockerfile already uses `.diffend.yml`)

**Success**: Action only updates the Docker image

---

### Task 2.9: Update onboarding deploy workflow

**File**: `onboarding/.github/workflows/deploy.yml`

**Steps**:
1. Hardcode infrastructure vars in the `env:` block (replace all `${{ vars.* }}`):
   - `CLUSTER_NAME: onboarding-cluster`
   - `ENVIRONMENT: Production`
   - `WEB_SERVICE_NAME: onboarding-web`
   - `CODEDEPLOY_APP_NAME: onboarding-web-app`
   - `CODEDEPLOY_DEPLOYMENT_GROUP: onboarding-web-dg`
   - `CODEDEPLOY_HOOK_LAMBDA_ARN: arn:aws:lambda:us-east-1:405749097490:function:Lambda-onboarding-codedeploy-hook`
   - `ECS_PRIVATE_SUBNETS: subnet-036ad8df2ef29358b,subnet-0c030c979cea9387b`
   - `ECS_TASK_SECURITY_GROUP: sg-0a720ef5ee1e9fa57`
2. Remove `secrets-json` and `vars-json` from all action calls
3. Keep `environment: Production` on all jobs

**Success**: Workflow no longer injects env vars; GitHub Environment remains for AWS credentials

---

### Task 2.10: Strip GitHub Environment "Production" in onboarding repo

**File**: GitHub repo settings

**Steps**:
1. Go to onboarding repo settings → Environments → Production
2. Remove all secrets and variables **except** `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`

**Success**: GitHub Environment `Production` contains only deploy credentials

---

## PHASE 3: app-beta-001 and app-demo-001 (Non-production app environments, ~21 secrets each)

### Task 3.1: Create feature branch for app beta/demo migration

**File**: None (git operation)

**Steps**:
1. Reuse existing branch or create: `git checkout -b feature/terraform-ssm-app-beta-demo`

**Success**: Working branch exists

---

### Task 3.2: Export beta-001 and demo-001 ECS task definition values

**File**: `/tmp/app_beta_001_env_values_20260321.txt` and `/tmp/app_demo_001_env_values_20260321.txt`

**Steps**:
1. For beta-001: `AWS_PROFILE=4shark-elevated aws ecs describe-task-definition --task-definition app-beta-001-web --region us-east-1 --query 'taskDefinition.containerDefinitions[0].{environment: environment, secrets: secrets}' > /tmp/app_beta_001_task_def_20260321.json`
2. For demo-001: `AWS_PROFILE=4shark-elevated aws ecs describe-task-definition --task-definition app-demo-001-web --region us-east-1 --query 'taskDefinition.containerDefinitions[0].{environment: environment, secrets: secrets}' > /tmp/app_demo_001_task_def_20260321.json`
3. Extract and document values for both stacks (values differ, variable names are the same per PLAN.md)

**Success**: Both task definitions exported

---

### Task 3.3: Create ssm.tf for app-beta-001

**File**: `/Users/plribeiro3000/Projects/4Shark/terraform/app-beta-001/ssm.tf`

**Content**:
- Stack name: `app-beta-001`
- KMS key: `arn:aws:kms:us-east-1:405749097490:key/mrk-fa0cda243274491784fc7b39bead5a03`
- SSM path prefix: `/app-beta-001/`
- 21 secrets (per PLAN.md AWS_ACCESS_KEY_ID through SECRET_KEY_BASE)
- Region: us-east-1

**Success**: `app-beta-001/ssm.tf` created

---

### Task 3.4: Create ssm.tf for app-demo-001

**File**: `/Users/plribeiro3000/Projects/4Shark/terraform/app-demo-001/ssm.tf`

**Content**: Same structure as 3.3, adjusted:
- Stack name: `app-demo-001`
- SSM path prefix: `/app-demo-001/`
- Same 21 secrets (values differ, names identical)

**Success**: `app-demo-001/ssm.tf` created

---

### Task 3.5: Update app-beta-001/compute.tf with locals.env_vars and locals.secrets

**File**: `/Users/plribeiro3000/Projects/4Shark/terraform/app-beta-001/compute.tf`

**Steps**:
1. Read current `compute.tf` to understand service definition structure (already exists, unlike setup/onboarding)
2. Add `locals.env_vars` block with ~48 non-sensitive vars (per PLAN.md list: AWS_BUCKET through WEB_SERVICE_NAME)
3. Add `locals.secrets` list with 21 SSM parameter ARN mappings
4. Update module calls (for each ECS service: web, worker, runner, scheduled tasks if present) to pass `environment_variables = local.env_vars` and `secrets = local.secrets`
5. Look for patterns like `for_each` loops or multiple service modules — wire each to use the same `local.env_vars` and `local.secrets`

**Success**: `locals.env_vars` and `locals.secrets` added, all services wired

---

### Task 3.6: Update app-demo-001/compute.tf with locals.env_vars and locals.secrets

**File**: `/Users/plribeiro3000/Projects/4Shark/terraform/app-demo-001/compute.tf`

**Content**: Same as Task 3.5, adjusted:
- Stack name references: `app-demo-001` instead of `app-beta-001`
- Values differ (from task 3.2), variable names identical to beta-001
- Same ~48 non-sensitive vars, same 21 secrets

**Success**: `app-demo-001/compute.tf` updated

---

### Task 3.7: Run terraform plan for app-beta-001

**File**: `/tmp/terraform_plan_app_beta_001_us_east_1_20260321.tfplan`

**Steps**:
1. Change to `terraform/app-beta-001/`
2. Run: `AWS_PROFILE=4shark-elevated terraform plan -out=/tmp/terraform_plan_app_beta_001_us_east_1_20260321.tfplan 2>&1 | tee /tmp/terraform_plan_app_beta_001_us_east_1_20260321.log`
3. Verify plan shows 21 SSM parameters, 1 IAM policy, task def updates

**Success**: Plan file saved

---

### Task 3.8: Apply terraform plan for app-beta-001 (requires approval)

**File**: Same plan file

**Prerequisites**: User approval

**Steps**:
1. Run: `AWS_PROFILE=4shark-elevated terraform apply /tmp/terraform_plan_app_beta_001_us_east_1_20260321.tfplan`
2. Commit changes

**Success**: 21 SSM parameters created for beta-001

---

### Task 3.9: Run terraform plan for app-demo-001

**File**: `/tmp/terraform_plan_app_demo_001_us_east_1_20260321.tfplan`

**Steps**:
1. Change to `terraform/app-demo-001/`
2. Run: `AWS_PROFILE=4shark-elevated terraform plan -out=/tmp/terraform_plan_app_demo_001_us_east_1_20260321.tfplan 2>&1 | tee /tmp/terraform_plan_app_demo_001_us_east_1_20260321.log`

**Success**: Plan file saved

---

### Task 3.10: Apply terraform plan for app-demo-001 (requires approval)

**File**: Same plan file

**Prerequisites**: User approval

**Steps**:
1. Run: `AWS_PROFILE=4shark-elevated terraform apply /tmp/terraform_plan_app_demo_001_us_east_1_20260321.tfplan`
2. Commit changes

**Success**: 21 SSM parameters created for demo-001

---

### Task 3.11: Populate SSM parameters for app-beta-001 (21 secrets)

**File**: Values from task 3.2

**Steps**:
1. For each of 21 secrets, run: `AWS_PROFILE=4shark-elevated aws ssm put-parameter --name "/app-beta-001/<NAME>" --value "<VALUE>" --type SecureString --overwrite --region us-east-1`
2. Verify all 21 parameters populated

**Success**: All 21 SSM parameters for beta-001 populated

---

### Task 3.12: Populate SSM parameters for app-demo-001 (21 secrets)

**File**: Values from task 3.2

**Steps**:
1. For each of 21 secrets (different values than beta-001), run: `AWS_PROFILE=4shark-elevated aws ssm put-parameter --name "/app-demo-001/<NAME>" --value "<VALUE>" --type SecureString --overwrite --region us-east-1`
2. Verify all 21 parameters populated

**Success**: All 21 SSM parameters for demo-001 populated

---

### Task 3.13: Fix deploy-ecs action and Dockerfile in app repo

**File**: `app/.github/actions/deploy-ecs/action.yaml` and `app/.github/docker/Dockerfile`

**Steps**:
1. Action: remove inputs `secrets-json` and `vars-json`; remove env injection from Register Task Definition; keep only `.image` update
2. Dockerfile: remove `ARG DIFFEND_*`; add `.diffend.yml` to COPY: `COPY Gemfile Gemfile.lock .diffend.yml ./`

**Success**: Action and Dockerfile updated

---

### Task 3.14: Update app deploy workflows for beta-001 and demo-001

**Files**: `app/.github/workflows/deploy-beta-001.yaml` and `app/.github/workflows/deploy-demo-001.yaml`

**Steps**:
1. Hardcode infrastructure vars in the `env:` block for each workflow (replace all `${{ vars.* }}`)
2. Remove `secrets-json` and `vars-json` from all action calls
3. Keep `environment: beta-001` / `environment: demo-001` on all jobs

**Success**: Workflows no longer inject env vars

---

### Task 3.15: Strip GitHub Environments beta-001 and demo-001 in app repo

**File**: GitHub repo settings

**Steps**:
1. Go to app repo settings → Environments → beta-001: remove all secrets/vars except `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY`
2. Repeat for demo-001

**Success**: Both environments contain only deploy credentials

---

## PHASE 4: app-atento-001 and app-shared-001 (Production app environments, ~25 secrets each)

### Task 4.1: Create feature branch for app atento/shared migration

**File**: None (git operation)

**Steps**:
1. Create: `git checkout -b feature/terraform-ssm-app-atento-shared`

**Success**: Working branch exists

---

### Task 4.2: Export atento-001 and shared-001 ECS task definition values

**File**: `/tmp/app_atento_001_env_values_20260321.txt` and `/tmp/app_shared_001_env_values_20260321.txt`

**Steps**:
1. For atento-001: `AWS_PROFILE=4shark-elevated aws ecs describe-task-definition --task-definition app-atento-001-web --region us-east-1 --query 'taskDefinition.containerDefinitions[0].{environment: environment, secrets: secrets}' > /tmp/app_atento_001_task_def_20260321.json`
2. For shared-001: `AWS_PROFILE=4shark-elevated aws ecs describe-task-definition --task-definition app-shared-001-web --region us-east-1 --query 'taskDefinition.containerDefinitions[0].{environment: environment, secrets: secrets}' > /tmp/app_shared_001_task_def_20260321.json`
3. Extract and document all values
4. Special note: atento-001 and shared-001 have `DATABASE_REPLICA_URL` and `ELASTICSEARCH_USER`/`ELASTICSEARCH_PASSWORD` not present in beta/demo

**Success**: Both task definitions exported

---

### Task 4.3: Create ssm.tf for app-atento-001

**File**: `/Users/plribeiro3000/Projects/4Shark/terraform/app-atento-001/ssm.tf`

**Content**:
- Stack name: `app-atento-001`
- KMS key: `arn:aws:kms:us-east-1:405749097490:key/mrk-fa0cda243274491784fc7b39bead5a03`
- SSM path prefix: `/app-atento-001/`
- 25 secrets (per PLAN.md: includes DATABASE_REPLICA_URL, ELASTICSEARCH_PASSWORD, ELASTICSEARCH_USER not in beta/demo)
- Region: us-east-1

**Success**: `app-atento-001/ssm.tf` created

---

### Task 4.4: Create ssm.tf for app-shared-001

**File**: `/Users/plribeiro3000/Projects/4Shark/terraform/app-shared-001/ssm.tf`

**Content**: Same structure as 4.3, adjusted:
- Stack name: `app-shared-001`
- SSM path prefix: `/app-shared-001/`
- Same 25 secrets (variable names identical, values differ)

**Success**: `app-shared-001/ssm.tf` created

---

### Task 4.5: Update app-atento-001/compute.tf with locals.env_vars and locals.secrets

**File**: `/Users/plribeiro3000/Projects/4Shark/terraform/app-atento-001/compute.tf`

**Steps**:
1. Read current `compute.tf`
2. Add `locals.env_vars` with ~55 non-sensitive vars (same list as beta/demo per PLAN.md: AWS_BUCKET through WEB_SERVICE_NAME)
3. Add `locals.secrets` list with 25 SSM parameter ARN mappings (including the extra DATABASE_REPLICA_URL, ELASTICSEARCH_* secrets)
4. Update all service module calls to pass `environment_variables = local.env_vars` and `secrets = local.secrets`

**Success**: `locals.env_vars` and `locals.secrets` added, all services wired

---

### Task 4.6: Update app-shared-001/compute.tf with locals.env_vars and locals.secrets

**File**: `/Users/plribeiro3000/Projects/4Shark/terraform/app-shared-001/compute.tf`

**Content**: Same as Task 4.5, adjusted:
- Stack name references: `app-shared-001`
- Values differ from atento, variable names identical
- Same ~55 non-sensitive vars, same 25 secrets

**Success**: `app-shared-001/compute.tf` updated

---

### Task 4.7: Run terraform plan for app-atento-001

**File**: `/tmp/terraform_plan_app_atento_001_us_east_1_20260321.tfplan`

**Steps**:
1. Change to `terraform/app-atento-001/`
2. Run: `AWS_PROFILE=4shark-elevated terraform plan -out=/tmp/terraform_plan_app_atento_001_us_east_1_20260321.tfplan 2>&1 | tee /tmp/terraform_plan_app_atento_001_us_east_1_20260321.log`

**Success**: Plan file saved

---

### Task 4.8: Apply terraform plan for app-atento-001 (requires approval)

**File**: Same plan file

**Prerequisites**: User approval

**Steps**:
1. Run: `AWS_PROFILE=4shark-elevated terraform apply /tmp/terraform_plan_app_atento_001_us_east_1_20260321.tfplan`
2. Commit changes

**Success**: 25 SSM parameters created for atento-001

---

### Task 4.9: Run terraform plan for app-shared-001

**File**: `/tmp/terraform_plan_app_shared_001_us_east_1_20260321.tfplan`

**Steps**:
1. Change to `terraform/app-shared-001/`
2. Run: `AWS_PROFILE=4shark-elevated terraform plan -out=/tmp/terraform_plan_app_shared_001_us_east_1_20260321.tfplan 2>&1 | tee /tmp/terraform_plan_app_shared_001_us_east_1_20260321.log`

**Success**: Plan file saved

---

### Task 4.10: Apply terraform plan for app-shared-001 (requires approval)

**File**: Same plan file

**Prerequisites**: User approval

**Steps**:
1. Run: `AWS_PROFILE=4shark-elevated terraform apply /tmp/terraform_plan_app_shared_001_us_east_1_20260321.tfplan`
2. Commit changes

**Success**: 25 SSM parameters created for shared-001

---

### Task 4.11: Populate SSM parameters for app-atento-001 (25 secrets)

**File**: Values from task 4.2

**Steps**:
1. For each of 25 secrets, run: `AWS_PROFILE=4shark-elevated aws ssm put-parameter --name "/app-atento-001/<NAME>" --value "<VALUE>" --type SecureString --overwrite --region us-east-1`
2. Verify all 25 parameters populated

**Success**: All 25 SSM parameters for atento-001 populated

---

### Task 4.12: Populate SSM parameters for app-shared-001 (25 secrets)

**File**: Values from task 4.2

**Steps**:
1. For each of 25 secrets (different values than atento), run: `AWS_PROFILE=4shark-elevated aws ssm put-parameter --name "/app-shared-001/<NAME>" --value "<VALUE>" --type SecureString --overwrite --region us-east-1`
2. Verify all 25 parameters populated

**Success**: All 25 SSM parameters for shared-001 populated

---

### Task 4.13: Update app deploy workflows for atento-001 and shared-001

**Files**: `app/.github/workflows/deploy-atento-001.yaml` and `app/.github/workflows/deploy-shared-001.yaml`

**Steps**:
1. Hardcode infrastructure vars in the `env:` block for each workflow (replace all `${{ vars.* }}`)
2. Remove `secrets-json` and `vars-json` from all action calls
3. Keep `environment: atento-001` / `environment: shared-001` on all jobs
4. Note: these workflows also use `secrets.MIGRATION_DATABASE_URL` and `secrets.REDIS_*` directly in runner steps — these remain in the GitHub Environment alongside the AWS credentials until a further migration (out of scope for now)

**Success**: Workflows no longer inject env vars into task def

---

### Task 4.14: Strip GitHub Environments atento-001 and shared-001 in app repo

**File**: GitHub repo settings

**Steps**:
1. Go to app repo settings → Environments → atento-001: remove all secrets/vars **except**: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `MIGRATION_DATABASE_URL`, `REDIS_LOCK_URL`, `REDIS_SIDEKIQ_URL`
2. Repeat for shared-001
3. Remove all remaining GH vars (CLUSTER_NAME, ENVIRONMENT, WEB_SERVICE_NAME, CODEDEPLOY_*, etc.) — these are now hardcoded in the workflow

**Note**: MIGRATION_DATABASE_URL and REDIS_* are kept because they are used directly by the runner (not just injected into ECS). Removing them is a future task.

**Success**: Environments stripped to runner-required secrets only

---

## PHASE 5: Cross-Plan Update

### Task 5.1: Update integrators-ec2-to-ecs PLAN.md with SSM pattern reference

**File**: `~/.claude/plans/active/terraform/integrators-ec2-to-ecs/PLAN.md`

**Steps**:
1. Read current integrators-ec2-to-ecs PLAN.md
2. Locate the "Technical Decisions" or "Env var management" section
3. Update the row for env var management strategy from "GitHub Actions secrets injected at deploy time" to:
   ```
   SSM Parameter Store (SecureString) + Terraform env_vars — same pattern as integrator-almaviva and Tier 1 migration (github-envs-to-terraform-ssm/PLAN.md)
   ```
4. Add a note to each per-integrator phase (Atento BR, CommCenter, Aster, etc.) that:
   ```
   Each integrator's compute.tf must include env_vars (non-sensitive locals) and secrets (SSM parameter ARN list) from the start.
   Reference: integrator-almaviva/ssm.tf pattern.
   GitHub Environments are not created for new integrators during this workflow.
   ```
5. Add reference to this plan: `github-envs-to-terraform-ssm/PLAN.md`

**Success**: integrators-ec2-to-ecs PLAN.md updated with settled SSM strategy

---

## Summary

**Phase 1 (setup)**: Terraform ✅ — Pending: tasks 1.8–1.11 (action, Dockerfile, workflow, strip GH env)
**Phase 2 (onboarding)**: Terraform ✅ — Pending: tasks 2.8–2.10 (action, workflow, strip GH env)
**Phase 3 (beta/demo)**: Terraform ✅ — Pending: tasks 3.13–3.15 (action+Dockerfile, workflows, strip GH envs)
**Phase 4 (atento/shared)**: Terraform ✅ — Pending: tasks 4.13–4.14 (workflows, strip GH envs — MIGRATION_DATABASE_URL and REDIS_* kept in GH env for now)
**Phase 5 (cross-plan)**: ✅ Complete

**Critical Rules**:
- Always use `AWS_PROFILE=4shark-elevated` for all terraform and AWS CLI commands
- Save plan files to `/tmp/terraform_plan_{stack}_{region}_{timestamp}.tfplan` before applying
- Use `tee` to log plan output to `/tmp/` for audit trail
- Never skip `ignore_changes = [value]` on SSM parameters (values are populated out-of-band)
- Source of truth for current values = running ECS task definition (not GitHub Environments)
- No application deploy required — running tasks unaffected until next normal release deploy
- Require explicit user approval before each `terraform apply`
