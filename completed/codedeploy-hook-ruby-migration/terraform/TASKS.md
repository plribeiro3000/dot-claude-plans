# NEXT TASKS — CodeDeploy Hook Lambda (Ruby) — Terraform Repo

> **Objective of this iteration:** Update the CodeDeploy Terraform module to deploy the Ruby lambda from S3 instead of inline Python, and update all environments.
> **Reference:** derived from `PLAN.md` (sections 2-3 and execution order steps 3-5).

---

## 0) Pre-conditions

- [ ] `PLAN.md` **approved**
- [ ] Lambda artifact published to S3 (`codedeploy-hook/{version}_{sha}.zip`)
- [ ] **Base branch:** `master` (terraform repo) • **Working branch:** `feature/codedeploy-hook-ruby`

---

## 1) Step by Step (atomic tasks)

### Task 1 — Add S3 variables to `modules/codedeploy/`
- **Objective:** Add variables for S3-based lambda deployment.
- **Actions (checklist):**
  - [ ] Add `hook_lambda_s3_bucket` variable (string, no default)
  - [ ] Add `hook_lambda_s3_key` variable (string, no default)
  - [ ] Both should be required only when `enable_hook_lambda = true` (use `default = null`)
- **Affected files/areas:** `modules/codedeploy/variables.tf`
- **Completion criteria:** New variables defined with appropriate types and descriptions.

### Task 2 — Update lambda resource to use S3 source
- **Objective:** Replace inline Python zip with S3 artifact.
- **Actions (checklist):**
  - [ ] Remove `data "archive_file" "hook_lambda_zip"` block
  - [ ] Add `data "aws_s3_object" "hook_lambda_package"` to fetch artifact etag (conditional on `enable_hook_lambda`)
  - [ ] Modify `aws_lambda_function.codedeploy_hook_lambda`:
    - Remove: `filename`, old `source_code_hash`
    - Add: `s3_bucket = var.hook_lambda_s3_bucket`
    - Add: `s3_key = var.hook_lambda_s3_key`
    - Add: `source_code_hash = data.aws_s3_object.hook_lambda_package[0].etag`
    - Change: `runtime = "ruby3.4"` (was `"python3.9"`)
    - Keep: `handler = "lambda_function.lambda_handler"` (same for both runtimes)
  - [ ] Update `lifecycle.ignore_changes` — keep `[source_code_hash, last_modified]`
- **Affected files/areas:** `modules/codedeploy/main.tf` (lines 188-219)
- **Completion criteria:** Lambda resource uses S3 source with Ruby 3.4 runtime. No archive_file dependency.

### Task 3 — Remove Python source file
- **Objective:** Clean up the old Python code.
- **Actions (checklist):**
  - [ ] Delete `modules/codedeploy/lambda_function.py`
  - [ ] Delete `modules/codedeploy/lambda_function.zip` (if generated/committed)
- **Affected files/areas:** `modules/codedeploy/lambda_function.py`
- **Completion criteria:** No Python files remain in the codedeploy module.

### Task 4 — Update `shared-001` environment
- **Objective:** Pass S3 variables to the codedeploy module in shared-001.
- **Actions (checklist):**
  - [ ] In `shared-001/main.tf`, add to `module "codedeploy_web"`:
    - `hook_lambda_s3_bucket = var.lambda_s3_bucket`
    - `hook_lambda_s3_key = "codedeploy-hook/${var.lambda_version}.zip"`
  - [ ] Run `terraform plan` to verify changes (expect: lambda update in-place or recreate)
- **Affected files/areas:** `shared-001/main.tf`
- **Completion criteria:** Plan shows only the lambda resource changing (runtime + source).
- **[HOLD POINT]** Verify plan output before applying. Lambda recreation is expected.

### Task 5 — Update `demo-001` environment
- **Objective:** Same changes as shared-001 for demo.
- **Actions (checklist):**
  - [ ] In `demo-001/main.tf`, add to codedeploy module:
    - `hook_lambda_s3_bucket = var.lambda_s3_bucket`
    - `hook_lambda_s3_key = "codedeploy-hook/${var.lambda_version}.zip"`
  - [ ] Run `terraform plan` to verify
- **Affected files/areas:** `demo-001/main.tf`
- **Completion criteria:** Plan shows only the lambda resource changing.

### Task 6 — Update `beta-001` environment
- **Objective:** Same changes as shared-001 for beta.
- **Actions (checklist):**
  - [ ] In `beta-001/main.tf`, add to codedeploy module:
    - `hook_lambda_s3_bucket = var.lambda_s3_bucket`
    - `hook_lambda_s3_key = "codedeploy-hook/${var.lambda_version}.zip"`
  - [ ] Run `terraform plan` to verify
- **Affected files/areas:** `beta-001/main.tf`
- **Completion criteria:** Plan shows only the lambda resource changing.

### Task 7 — Update `atento-001` environment
- **Objective:** Same changes as shared-001 for atento.
- **Actions (checklist):**
  - [ ] In `atento-001/main.tf`, add to codedeploy module:
    - `hook_lambda_s3_bucket = var.lambda_s3_bucket`
    - `hook_lambda_s3_key = "codedeploy-hook/${var.lambda_version}.zip"`
  - [ ] Run `terraform plan` to verify
- **Affected files/areas:** `atento-001/main.tf`
- **Completion criteria:** Plan shows only the lambda resource changing.

### Task 8 — Verify `setup/` environment
- **Objective:** Confirm setup doesn't need changes.
- **Actions (checklist):**
  - [ ] Confirm `setup/main.tf` has `enable_hook_lambda = false`
  - [ ] Verify no new variables are required when hook is disabled (defaults to `null`)
- **Affected files/areas:** `setup/main.tf`
- **Completion criteria:** No changes needed, confirmed.

### Task 9 — Apply per environment
- **Objective:** Roll out the change environment by environment.
- **Actions (checklist):**
  - [ ] Apply `demo-001` first (lowest risk)
  - [ ] Trigger a test deployment to verify the Ruby lambda works
  - [ ] Apply `beta-001`
  - [ ] Apply `atento-001`
  - [ ] Apply `shared-001` (production, last)
- **Affected files/areas:** All environment state files
- **Completion criteria:** All environments running Ruby lambda. Test deployment succeeds (SSM parameters created, deployment pauses correctly).
- **[HOLD POINT]** After each environment apply, verify with a test deployment before proceeding to the next.

---

## 2) Items Requiring User Confirmation

- [ ] **Apply order:** Confirm `demo → beta → atento → shared` is the correct rollout order
- [ ] **Terraform apply:** User must run applies (Claude has no production access)
- [ ] **Lambda recreation:** Confirm it's acceptable that the lambda will be destroyed and recreated (short window where hook doesn't exist)
- [ ] **Naming:** Keep `codedeploy-hook-lambda-{environment}` or rename to `Lambda-{environment}-codedeploy-hook`?

---

## 3) Pending Items After This Iteration

- [ ] Remove `.zip` from `.gitignore` if `lambda_function.zip` was committed
- [ ] Monitor first deployment per environment to confirm SSM parameters are created correctly
- [ ] Consider adding CloudWatch alarms for the lambda (currently has none)
