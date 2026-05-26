# NEXT TASKS — CodeDeploy Hook Lambda (Ruby) — Lambda Repo

> **Objective of this iteration:** Create the Ruby version of the CodeDeploy hook lambda and update build/publish scripts to support non-`worker-*` lambda directories.
> **Reference:** derived from `PLAN.md` (sections 1 and execution order step 1-2).

---

## 0) Pre-conditions

- [x] `PLAN.md` **approved**
- [ ] **Base branch:** `master` (lambda repo) • **Working branch:** `feature/codedeploy-hook-ruby`

---

## 1) Step by Step (atomic tasks)

### Task 1 — Create `codedeploy-hook/` directory structure
- **Objective:** Create the new lambda directory following the existing pattern.
- **Actions (checklist):**
  - [ ] Create `lambda/codedeploy-hook/` directory
  - [ ] Create `Gemfile` with `aws-sdk-codedeploy` and `aws-sdk-ssm` gems (plus `bigdecimal`)
  - [ ] Run `bundle install` to generate `Gemfile.lock`
- **Affected files/areas:** `lambda/codedeploy-hook/Gemfile`, `lambda/codedeploy-hook/Gemfile.lock`
- **Completion criteria:** Directory exists with valid Gemfile and lock file.

### Task 2 — Implement `lambda_function.rb`
- **Objective:** Translate the Python lambda logic to Ruby following the existing handler pattern.
- **Actions (checklist):**
  - [ ] Create `lambda/codedeploy-hook/lambda_function.rb`
  - [ ] Include `VERSION` and `SHA` constants (for build injection)
  - [ ] Include `LOGGER` setup (same pattern as `worker-autoscaling`)
  - [ ] Implement `lambda_handler(event)` method:
    - Extract `DeploymentId`, `LifecycleEventHookExecutionId`, `LifecycleEvent` from event
    - Store both IDs in SSM Parameter Store (`/codedeploy-hooks/{deployment_id}/deployment-id` and `/codedeploy-hooks/{deployment_id}/hook-id`)
    - On SSM error: signal `Failed` to CodeDeploy via `put_lifecycle_event_hook_execution_status`
    - Do NOT signal `Succeeded` (deployment stays paused)
    - Return `{ statusCode: 200, body: ... }`
- **Affected files/areas:** `lambda/codedeploy-hook/lambda_function.rb`
- **Completion criteria:** Ruby handler mirrors the Python logic exactly. Uses `Aws::SSM::Client` and `Aws::CodeDeploy::Client`.

### Task 3 — Create README.md
- **Objective:** Document the lambda's purpose and behavior.
- **Actions (checklist):**
  - [ ] Create `lambda/codedeploy-hook/README.md`
  - [ ] Document: purpose (BeforeAllowTraffic hook), SSM parameters created, error handling, how deployment pauses
- **Affected files/areas:** `lambda/codedeploy-hook/README.md`
- **Completion criteria:** README clearly explains what the lambda does and how it fits in the CodeDeploy flow.

### Task 4 — Update `bin/generate_lambda` discovery
- **Objective:** Make lambda discovery generic so `codedeploy-hook/` is found automatically.
- **Actions (checklist):**
  - [ ] Change `discover_lambdas()` from glob `worker-*/` to discovering any directory containing `lambda_function.rb`
  - [ ] Exclude known non-lambda directories (`bin/`, `dist/`, `.git/`, `vendor/`)
  - [ ] Verify `--all` flag discovers all 4 lambdas (3 existing + codedeploy-hook)
  - [ ] Verify `--lambda-name codedeploy-hook` still works for single builds
- **Affected files/areas:** `lambda/bin/generate_lambda`
- **Completion criteria:** `discover_lambdas` finds `worker-autoscaling`, `worker-commission-autoscaling`, `worker-commission-balancing`, and `codedeploy-hook`.

### Task 5 — Update `bin/publish_lambdas` discovery
- **Objective:** Same discovery change for the publish script.
- **Actions (checklist):**
  - [ ] Change `discover_lambdas()` from glob `worker-*/` to same generic pattern as `generate_lambda`
  - [ ] Verify dry-run shows all 4 lambdas
- **Affected files/areas:** `lambda/bin/publish_lambdas`
- **Completion criteria:** `publish_lambdas` discovers and uploads all 4 lambda artifacts.

### Task 6 — Update CHANGELOG.md
- **Objective:** Document the new lambda in the changelog.
- **Actions (checklist):**
  - [ ] Add entry under `[Unreleased]` for the new codedeploy-hook lambda
- **Affected files/areas:** `lambda/CHANGELOG.md`
- **Completion criteria:** Changelog entry exists.

### Task 7 — Build and publish
- **Objective:** Generate artifact and upload to S3.
- **Actions (checklist):**
  - [ ] Start Docker container: `docker start -ai lambda-builder`
  - [ ] Inside container: `git pull && bin/generate_lambda --all`
  - [ ] On host: `bin/publish_lambdas`
  - [ ] Verify artifact exists at `s3://4shark-lambda-artifacts/codedeploy-hook/{version}_{sha}.zip`
- **Affected files/areas:** S3 bucket
- **Completion criteria:** Artifact uploaded and accessible.
- **[HOLD POINT]** Pause here — Terraform changes depend on the artifact being available in S3.

---

## 2) Items Requiring User Confirmation

- [ ] **Lambda repo base branch:** Confirm it's `master` (not `main` or `develop`)
- [ ] **Gemfile extras:** Should we include `bigdecimal` gem? (existing lambdas include it)
- [ ] **Build/publish:** User must perform these steps (requires Docker + AWS credentials)

---

## 3) Pending Items After This Iteration

- [ ] Terraform module changes (see `terraform/TASKS.md`)
- [ ] Terraform environment apply per environment
