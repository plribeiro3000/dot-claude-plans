# NEXT TASKS — App ECS Tags (Terraform) — Phase 1: Replace local.tags

> **Objective of this iteration:** Replace `local.tags` blocks in all four app stacks (`app-shared-001`, `app-atento-001`, `app-beta-001`, `app-demo-001`) with canonical three-tag schema (`Project`, `Environment`, `ManagedBy`). Plan, review, and apply each stack independently — all under a single PR that is opened before the first apply.
>
> **Reference:** derived from `PLAN.md` (Section: "Phase 1: Terraform — Replace `local.tags` in the Four App Stacks") and `~/.claude/docs/TERRAFORM-PR-WORKFLOW.md`.

---

## 0) Pre-conditions

- [ ] `PLAN.md` **approved** (Terraform Phase 1 is the next iteration)
- [ ] **Base branch:** `develop` • **Working branch:** `feature/app-ecs-tags` (must be created)
- [ ] All four app stacks are on current Terraform state (no pending drift unrelated to tags)
- [ ] AWS profile `default` (read-only) is available for plan queries
- [ ] AWS profile `4shark-mfa` (elevated, MFA-gated) is available for apply operations

---

## 1) Step by Step (atomic tasks)

### Task 1 — Create feature branch
- **Objective:** Set up isolated branch for Terraform changes.
- **Actions (checklist):**
  - [ ] Clone/pull latest `develop` in `/Users/plribeiro3000/Projects/4Shark/terraform`
  - [ ] Create feature branch: `git checkout -b feature/app-ecs-tags`
  - [ ] Verify branch is clean and on `develop` baseline
- **Affected files/areas:** Git repository state only
- **Completion criteria:** `git branch` shows `* feature/app-ecs-tags` (current branch)
- **Observations:** No uncommitted changes should exist before starting.

### Task 2 — Edit `local.tags` in app-shared-001
- **Objective:** Replace tags block in the shared-001 stack with canonical schema.
- **Actions (checklist):**
  - [ ] Open `/Users/plribeiro3000/Projects/4Shark/terraform/app-shared-001/main.tf`
  - [ ] Locate `local.tags` block at lines 18–22 (current: `Environment`, `Automation`, `Cluster`)
  - [ ] Replace with:
    ```hcl
    locals {
      tags = {
        Project     = "app"
        Environment = "shared-001"
        ManagedBy   = "terraform"
      }
    }
    ```
  - [ ] Verify no syntax errors and whitespace consistency
  - [ ] Git stage the file
- **Affected files/areas:** `app-shared-001/main.tf` (lines 18–22)
- **Completion criteria:** File saved, staged, and syntax valid
- **Observations:** All resources in this stack receive `local.tags` via module inputs and direct references — no per-resource edits needed.

### Task 3 — Edit `local.tags` in app-beta-001
- **Objective:** Replace tags block in the beta-001 stack with canonical schema.
- **Actions (checklist):**
  - [ ] Open `/Users/plribeiro3000/Projects/4Shark/terraform/app-beta-001/main.tf`
  - [ ] Locate `local.tags` block at lines 18–22 (current: `Environment`, `Automation`, `Cluster`)
  - [ ] Replace with:
    ```hcl
    locals {
      tags = {
        Project     = "app"
        Environment = "beta-001"
        ManagedBy   = "terraform"
      }
    }
    ```
  - [ ] Verify no syntax errors and whitespace consistency
  - [ ] Git stage the file
- **Affected files/areas:** `app-beta-001/main.tf` (lines 18–22)
- **Completion criteria:** File saved, staged, and syntax valid
- **Observations:** All resources in this stack receive `local.tags` — no per-resource edits needed.

### Task 4 — Edit `local.tags` in app-demo-001
- **Objective:** Replace tags block in the demo-001 stack with canonical schema.
- **Actions (checklist):**
  - [ ] Open `/Users/plribeiro3000/Projects/4Shark/terraform/app-demo-001/main.tf`
  - [ ] Locate `local.tags` block at lines 18–22 (current: `Environment`, `Automation`, `Cluster`)
  - [ ] Replace with:
    ```hcl
    locals {
      tags = {
        Project     = "app"
        Environment = "demo-001"
        ManagedBy   = "terraform"
      }
    }
    ```
  - [ ] Verify no syntax errors and whitespace consistency
  - [ ] Git stage the file
- **Affected files/areas:** `app-demo-001/main.tf` (lines 18–22)
- **Completion criteria:** File saved, staged, and syntax valid
- **Observations:** All resources in this stack receive `local.tags` — no per-resource edits needed.

### Task 5 — Edit `local.tags` in app-atento-001
- **Objective:** Replace tags block in the atento-001 stack. Note: `Environment` tag value changes from `"app-atento-001"` to `"atento-001"`.
- **Actions (checklist):**
  - [ ] Open `/Users/plribeiro3000/Projects/4Shark/terraform/app-atento-001/main.tf`
  - [ ] Locate `local.tags` block at lines 11–15 (current: `Environment = "app-atento-001"`, `Automation`, `Cluster`)
  - [ ] Replace with:
    ```hcl
    locals {
      tags = {
        Project     = "app"
        Environment = "atento-001"
        ManagedBy   = "terraform"
      }
    }
    ```
  - [ ] Verify no syntax errors; note that `Environment` value drops the `app-` prefix
  - [ ] Git stage the file
- **Affected files/areas:** `app-atento-001/main.tf` (lines 11–15)
- **Completion criteria:** File saved, staged, and syntax valid
- **Observations:** The cluster resource is still named `app-atento-001-cluster` — only the tag value changes. Full naming alignment deferred to future migration.

### Task 6 — Update CHANGELOG.md
- **Objective:** Document the tag schema change in the Terraform repository changelog.
- **Actions (checklist):**
  - [ ] Open `/Users/plribeiro3000/Projects/4Shark/terraform/CHANGELOG.md`
  - [ ] Locate `[Unreleased]` section
  - [ ] Add entry under `### Changed`:
    ```markdown
    ### Changed
    - App ECS cluster tags
    ```
  - [ ] Save and stage the file
- **Affected files/areas:** `terraform/CHANGELOG.md`
- **Completion criteria:** Entry added, file saved, staged

### Task 7 — Commit changes
- **Objective:** Create a single atomic commit for all four `local.tags` edits and changelog.
- **Actions (checklist):**
  - [ ] Verify all modified files are staged: `git status`
  - [ ] Create commit using Angular Commit Guidelines:
    ```
    git commit -m "$(cat <<'EOF'
    fix(tags): replace app cluster tags with canonical schema

    - Add Project=app tag to all four app stacks
    - Rename Automation to ManagedBy for consistency with integrators
    - Remove redundant Cluster tag
    - Update atento Environment value from app-atento-001 to atento-001
    EOF
    )"
    ```
  - [ ] Verify commit was created: `git log --oneline -1`
- **Affected files/areas:** Git history
- **Completion criteria:** Commit created with proper Angular format; no AI references
- **Observations:** One commit per PR is the standard. All tag edits + changelog in one atomic unit.

### Task 8 — Push branch to remote
- **Objective:** Make branch available on remote so the PR can be opened.
- **Actions (checklist):**
  - [ ] Run: `git push origin feature/app-ecs-tags:refs/heads/feature/app-ecs-tags`
  - [ ] Verify push succeeded (branch visible on remote)
- **Affected files/areas:** Remote repository
- **Completion criteria:** Branch pushed; no errors
- **Observations:** Use the explicit refspec — never `git push -u origin feature/app-ecs-tags` (push.default=upstream risk, see MEMORY.md).

### Task 9 — Open PR
- **Objective:** Create the formal audit trail before any apply. The PR must be open before the first `terraform plan` that leads to apply.
- **Actions (checklist):**
  - [ ] Open PR via `gh pr create` targeting `develop`
  - [ ] PR title: `fix(tags): replace app cluster tags with canonical schema`
  - [ ] PR body: summarize the change, reference the tag schema table from PLAN.md, note that applies are pending (apply-before-merge workflow)
  - [ ] Confirm PR URL and number are visible
- **Affected files/areas:** GitHub pull request
- **Completion criteria:** PR is open and visible on GitHub; URL recorded
- **Observations:** Per `~/.claude/docs/TERRAFORM-PR-WORKFLOW.md`: apply without an open PR is a policy violation. The PR does not need to be reviewed or approved before apply — it just needs to exist as the audit trail.

### Task 10 — Plan app-shared-001
- **Objective:** Generate and review plan for the shared-001 stack before apply.
- **Actions (checklist):**
  - [ ] Run `/aws-elevate` to validate MFA session
  - [ ] Change to `/Users/plribeiro3000/Projects/4Shark/terraform/app-shared-001`
  - [ ] Run: `terraform plan -out=/tmp/terraform_plan_app_shared_001_$(date +%Y%m%d_%H%M%S).tfplan`
  - [ ] Capture timestamp from plan filename (e.g., `20260427_154500`)
  - [ ] Read plan output and create structured summary:
    - Resources to change: list of resources with `~ tags` (approximately 26 per PLAN.md)
    - Resources to add: (should be 0)
    - Resources to destroy: (should be 0)
    - **STOP if any `+` or `-` appears** — investigate before proceeding
  - [ ] Present summary to engineer with explicit approval gate
- **Affected files/areas:** `app-shared-001` (read-only for plan generation)
- **Completion criteria:** Plan file saved to `/tmp/`, summary presented, engineer explicitly approves before Task 14 (apply)
- **[HOLD POINT]:** Wait for engineer approval: "Only `~ tags` expected. Zero additions and zero destructions. Any `+` or `-` = STOP."

### Task 11 — Plan app-beta-001
- **Objective:** Generate and review plan for the beta-001 stack before apply.
- **Actions (checklist):**
  - [ ] Ensure MFA session still valid (re-run `/aws-elevate` if needed)
  - [ ] Change to `/Users/plribeiro3000/Projects/4Shark/terraform/app-beta-001`
  - [ ] Run: `terraform plan -out=/tmp/terraform_plan_app_beta_001_$(date +%Y%m%d_%H%M%S).tfplan`
  - [ ] Capture timestamp from plan filename
  - [ ] Read plan output and create structured summary (approximately 22 changes, 0 additions, 0 destructions)
  - [ ] **STOP if any `+` or `-` appears**
  - [ ] Present summary to engineer with explicit approval gate
- **Affected files/areas:** `app-beta-001` (read-only for plan generation)
- **Completion criteria:** Plan file saved to `/tmp/`, summary presented, engineer explicitly approves before Task 15 (apply)
- **[HOLD POINT]:** Wait for engineer approval.

### Task 12 — Plan app-demo-001
- **Objective:** Generate and review plan for the demo-001 stack before apply.
- **Actions (checklist):**
  - [ ] Ensure MFA session still valid
  - [ ] Change to `/Users/plribeiro3000/Projects/4Shark/terraform/app-demo-001`
  - [ ] Run: `terraform plan -out=/tmp/terraform_plan_app_demo_001_$(date +%Y%m%d_%H%M%S).tfplan`
  - [ ] Capture timestamp from plan filename
  - [ ] Read plan output and create structured summary (approximately 23 changes, 0 additions, 0 destructions)
  - [ ] **STOP if any `+` or `-` appears**
  - [ ] Present summary to engineer with explicit approval gate
- **Affected files/areas:** `app-demo-001` (read-only for plan generation)
- **Completion criteria:** Plan file saved to `/tmp/`, summary presented, engineer explicitly approves before Task 16 (apply)
- **[HOLD POINT]:** Wait for engineer approval.

### Task 13 — Plan app-atento-001
- **Objective:** Generate and review plan for the atento-001 stack (largest resource graph — planned last).
- **Actions (checklist):**
  - [ ] Ensure MFA session still valid
  - [ ] Change to `/Users/plribeiro3000/Projects/4Shark/terraform/app-atento-001`
  - [ ] Run: `terraform plan -out=/tmp/terraform_plan_app_atento_001_$(date +%Y%m%d_%H%M%S).tfplan`
  - [ ] Capture timestamp from plan filename
  - [ ] Read plan output and create structured summary (approximately 25 changes, 0 additions, 0 destructions)
  - [ ] **STOP if any `+` or `-` appears** — atento has the most resources; investigate carefully
  - [ ] Present summary to engineer with explicit approval gate
- **Affected files/areas:** `app-atento-001` (read-only for plan generation)
- **Completion criteria:** Plan file saved to `/tmp/`, summary presented, engineer explicitly approves before Task 17 (apply)
- **Observations:** Atento is reviewed last due to largest resource graph and dedicated VPC. Extra care warranted.
- **[HOLD POINT]:** Wait for engineer approval.

### Task 14 — Apply app-shared-001
- **Objective:** Apply approved plan to shared-001 stack (production, run first to validate the pattern).
- **Actions (checklist):**
  - [ ] Verify engineer approved Task 10 plan
  - [ ] Retrieve plan filename from Task 10 (e.g., `/tmp/terraform_plan_app_shared_001_20260427_154500.tfplan`)
  - [ ] Ensure MFA session valid (re-run `/aws-elevate` if needed)
  - [ ] Change to `/Users/plribeiro3000/Projects/4Shark/terraform/app-shared-001`
  - [ ] Run: `terraform apply /tmp/terraform_plan_app_shared_001_TIMESTAMP.tfplan`
  - [ ] Wait for apply to complete (monitor for errors)
  - [ ] Verify apply succeeded (all resources updated in-place)
  - [ ] Report: "Applied app-shared-001: X resources changed."
  - [ ] If apply fails: fix on the same branch, commit + push to the open PR, re-plan (Task 10), re-apply
- **Affected files/areas:** `app-shared-001` (infrastructure state, AWS tags)
- **Completion criteria:** `terraform apply` completed successfully; no rollback needed; tags visible in AWS
- **Observations:** First apply — validates the pattern. Fix-on-same-PR if anything fails.

### Task 15 — Apply app-beta-001
- **Objective:** Apply approved plan to beta-001 stack.
- **Actions (checklist):**
  - [ ] Verify engineer approved Task 11 plan
  - [ ] Retrieve plan filename from Task 11
  - [ ] Ensure MFA session valid
  - [ ] Change to `/Users/plribeiro3000/Projects/4Shark/terraform/app-beta-001`
  - [ ] Run: `terraform apply /tmp/terraform_plan_app_beta_001_TIMESTAMP.tfplan`
  - [ ] Wait for apply to complete
  - [ ] Verify apply succeeded
  - [ ] Report: "Applied app-beta-001: X resources changed."
  - [ ] If apply fails: fix on the same branch, commit + push to the open PR, re-plan (Task 11), re-apply
- **Affected files/areas:** `app-beta-001` (infrastructure state, AWS tags)
- **Completion criteria:** `terraform apply` completed successfully

### Task 16 — Apply app-demo-001
- **Objective:** Apply approved plan to demo-001 stack.
- **Actions (checklist):**
  - [ ] Verify engineer approved Task 12 plan
  - [ ] Retrieve plan filename from Task 12
  - [ ] Ensure MFA session valid
  - [ ] Change to `/Users/plribeiro3000/Projects/4Shark/terraform/app-demo-001`
  - [ ] Run: `terraform apply /tmp/terraform_plan_app_demo_001_TIMESTAMP.tfplan`
  - [ ] Wait for apply to complete
  - [ ] Verify apply succeeded
  - [ ] Report: "Applied app-demo-001: X resources changed."
  - [ ] If apply fails: fix on the same branch, commit + push to the open PR, re-plan (Task 12), re-apply
- **Affected files/areas:** `app-demo-001` (infrastructure state, AWS tags)
- **Completion criteria:** `terraform apply` completed successfully

### Task 17 — Apply app-atento-001
- **Objective:** Apply approved plan to atento-001 stack (production, largest resource graph — run last).
- **Actions (checklist):**
  - [ ] Verify engineer approved Task 13 plan
  - [ ] Retrieve plan filename from Task 13
  - [ ] Ensure MFA session valid
  - [ ] Change to `/Users/plribeiro3000/Projects/4Shark/terraform/app-atento-001`
  - [ ] Run: `terraform apply /tmp/terraform_plan_app_atento_001_TIMESTAMP.tfplan`
  - [ ] Wait for apply to complete
  - [ ] Verify apply succeeded
  - [ ] Report: "Applied app-atento-001: X resources changed."
  - [ ] If apply fails: fix on the same branch, commit + push to the open PR, re-plan (Task 13), re-apply
- **Affected files/areas:** `app-atento-001` (infrastructure state, AWS tags)
- **Completion criteria:** `terraform apply` completed successfully; tags live in AWS

### Task 18 — Validate tags in AWS
- **Objective:** Confirm all four stacks' resources are now tagged with the new schema.
- **Actions (checklist):**
  - [ ] Run query to validate `Project=app` tag is present across all four clusters:
    ```bash
    aws resourcegroupstaggingapi get-resources \
      --region sa-east-1 \
      --resource-type-filters ecs:cluster \
      --tag-filters '[{"Key":"Project","Values":["app"]}]' \
      --query 'ResourceTagMappingList[].{ARN:ResourceARN,Tags:Tags}' \
      --output table
    ```
  - [ ] Verify output shows exactly four clusters: `shared-001-cluster`, `beta-001-cluster`, `demo-001-cluster`, `app-atento-001-cluster`
  - [ ] Verify each cluster has tags: `Project=app`, `Environment=<stack-id>`, `ManagedBy=terraform`
  - [ ] Report validation result to engineer
- **Affected files/areas:** AWS infrastructure only (read-only query)
- **Completion criteria:** Query output confirms all four clusters are present with correct tags

### Task 19 — Merge PR
- **Objective:** Merge the PR to `develop` after all four applies have succeeded.
- **Actions (checklist):**
  - [ ] Confirm all four applies completed successfully (Tasks 14–17)
  - [ ] Confirm AWS validation passed (Task 18)
  - [ ] Merge the open PR on GitHub
- **Affected files/areas:** `develop` branch
- **Completion criteria:** PR merged; `develop` contains the tag changes
- **Observations:** Per `~/.claude/docs/TERRAFORM-PR-WORKFLOW.md`: merge only after apply succeeds. Merging a PR with a failing apply violates the policy and leaves the next PR to clean up.

### Task 20 — Run /merge-cleanup
- **Objective:** Clean up local and remote branches after merge.
- **Actions (checklist):**
  - [ ] Run `/merge-cleanup` from the terraform repository
  - [ ] Verify local `feature/app-ecs-tags` branch is deleted
  - [ ] Verify stale remote refs are pruned
- **Affected files/areas:** Local and remote Git branches
- **Completion criteria:** `git branch` no longer shows `feature/app-ecs-tags`; remote refs pruned

---

## 2) Items Requiring User Confirmation

- [ ] **Apply-before-merge policy understood:** The PR is opened (Task 9) before any plan/apply runs. Merge only after all applies succeed. Per `~/.claude/docs/TERRAFORM-PR-WORKFLOW.md`. Proceed with this understanding?
- [ ] **Apply order confirmed:** shared-001 (prod) → beta-001 → demo-001 → atento-001 (prod, largest). Proceed in this order?
- [ ] **Plan approval gate:** Each plan must show only `~ tags` changes, zero `+` and zero `-`. Any `+` or `-` = STOP and investigate. Proceed with this understanding?
- [ ] **MFA session validity:** `/aws-elevate` will be run before applies and re-checked as needed. Acceptable?

> **Expected response (example):**
> `APPROVED: apply-before-merge understood; apply order confirmed; plan gate understood; MFA checks understood.`

---

## 3) Pending Items After This Iteration (if any arise)

- [ ] **Phase 2 (Claude Config):** After Terraform PR is merged, proceed to feature branch creation and script/command implementation in the `.claude` working copy. This requires tags to be live in AWS before functional testing.
- [ ] **Flag in PLAN.md:** Update status after Phase 1 is complete.
