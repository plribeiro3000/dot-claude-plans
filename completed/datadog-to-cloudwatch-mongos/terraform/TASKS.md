# NEXT TASKS — Phase 0: Terraform IAM Instance Profile — Option B

> **Objective of this iteration:** Create the IAM instance profile (`mongo-cwagent`) for CloudWatch Agent and attach it to all 15 MongoDB EC2 instances across 5 client stacks. This is a prerequisite before Ansible can provision the CloudWatch Agent.
>
> **Reference:** derived from `PLAN.md` § "Phase 0 — Terraform: IAM Instance Profile" and § "Decision 4 — IAM Instance Profile creation".

---

## 0) Pre-conditions

- [x] `PLAN.md` **approved** (Option B: Terraform first, then Ansible).
- [x] All 4 engineer decisions confirmed (1C, 2, 3B, 4).
- [ ] **Base branch:** `develop` • **Working branch:** `feature/mongo-cwagent-iam-profile`
- [ ] AWS credentials configured with read-only access (default profile) and MFA-elevated access (`4shark-mfa` profile via `/aws-elevate`).
- [ ] Terraform CLI installed and able to run `terraform plan` / `terraform apply` in `~/Projects/4Shark/terraform/`.

---

## 1) Step by Step (atomic tasks)

### Task 1 — Prepare workspace and create feature branch

- **Objective:** Set up a clean feature branch from `develop` in the terraform repository.
- **Actions (checklist):**
  - [ ] Navigate to `~/Projects/4Shark/terraform/`
  - [ ] Verify you are on `develop` and up-to-date (`git pull origin develop`)
  - [ ] Create and check out feature branch: `git checkout -b feature/mongo-cwagent-iam-profile`
- **Affected files/areas:** None yet (branch prep only)
- **Completion criteria:** `git branch -v` shows the feature branch as current with same commit as `origin/develop`

---

### Task 2 — Create IAM resources in `shared-resources/` stack

- **Objective:** Add the `mongo-cwagent` IAM role, policy attachment, and instance profile to the `shared-resources` stack.
- **Actions (checklist):**
  - [ ] Create new file `terraform/shared-resources/mongo-cwagent.tf` with exact HCL from PLAN.md § Decision 4:
    - `aws_iam_role.mongo_cwagent` with EC2 assume role trust policy (reference the existing `data.aws_iam_policy_document.ec2_assume` data source if it exists; if not, define inline)
    - `aws_iam_role_policy_attachment.mongo_cwagent_cloudwatch` attaching the AWS managed policy `arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy`
    - `aws_iam_instance_profile.mongo_cwagent` with role name `mongo_cwagent`
    - `output.mongo_cwagent_instance_profile_name` exposing the instance profile name
  - [ ] Verify variable naming: all names use `mongo_cwagent` or `mongo-cwagent` (hyphens in IAM resource names, underscores in Terraform identifiers) — no abbreviations
  - [ ] Check if `shared-resources/` already has an `ec2_assume` data source; if not, define: `data "aws_iam_policy_document" "ec2_assume" { statement { ... } }`
- **Affected files/areas:** `terraform/shared-resources/mongo-cwagent.tf` (new), `terraform/shared-resources/ec2_assume.tf` (if data source missing)
- **Completion criteria:**
  - [ ] File `terraform/shared-resources/mongo-cwagent.tf` exists with all 3 resources + 1 output
  - [ ] `terraform fmt` passes on the file (or runs silently)
  - [ ] `terraform validate` passes in the `shared-resources/` directory

---

### Task 3 — Update `shared-resources/README.md` with "Shared IAM Identities" section

- **Objective:** Document the new role in `shared-resources` and establish the inclusion rule for future IAM identities.
- **Actions (checklist):**
  - [ ] Read current `terraform/shared-resources/README.md` to understand scope and style
  - [ ] Add a new section **"Shared IAM Identities"** (after the "Scope" section) with:
    - Explanation: "This stack includes IAM identities (roles, policies, instance profiles) that are identical across all consuming stacks and should not be duplicated."
    - Inclusion rule: "An IAM identity belongs here when: (a) it is referenced by resources in 2+ `integrator-*` stacks, (b) the definition is identical across those stacks (no per-client variation), (c) there is no per-stack IAM boundary (e.g., cross-account, break-glass, or sensitive scope — those remain in the `identity/` stack with the `ivo` profile)."
    - Example: `mongo-cwagent` — instance profile for CloudWatch Agent on MongoDB EC2 instances, identical across all clients, created once and referenced by name in each `integrator-*/mongodb.tf`.
  - [ ] Update the "Scope" section if it currently says "configuration-only, no compute/network/IAM resources" — reword to allow IAM identities per the rule above.
- **Affected files/areas:** `terraform/shared-resources/README.md`
- **Completion criteria:**
  - [ ] README has a new "Shared IAM Identities" section with the rule and `mongo-cwagent` example
  - [ ] The scope statement now permits shared IAM identities

---

### Task 4 — Add `iam_instance_profile` to `integrator-atento/` mongo EC2 instances

- **Objective:** Attach the `mongo-cwagent` instance profile to the 3 MongoDB instances in the atento stack.
- **Actions (checklist):**
  - [ ] Read the atento stack's compute file (likely `terraform/integrator-atento/mongodb.tf` or `terraform/integrator-atento/compute.tf`)
  - [ ] Locate the 3 `aws_instance` resources for `mongo003`, `mongo004`, `mongo005`
  - [ ] Add `iam_instance_profile = "mongo-cwagent"` to each instance (single line, referencing the profile name as a string, not a Terraform interpolation)
  - [ ] Verify no other changes are introduced; the diff should show only the 3 added lines
- **Affected files/areas:** `terraform/integrator-atento/mongodb.tf` (or `compute.tf` if that's where instances are)
- **Completion criteria:**
  - [ ] Each of the 3 mongo instances in atento stack has the `iam_instance_profile = "mongo-cwagent"` line
  - [ ] `terraform fmt` passes
  - [ ] No other changes in the file

---

### Task 5 — Add `iam_instance_profile` to `integrator-commcenter/` mongo EC2 instances

- **Objective:** Attach the `mongo-cwagent` instance profile to the 3 MongoDB instances in the commcenter stack.
- **Actions (checklist):**
  - [ ] Locate the commcenter stack's compute file (likely `terraform/integrator-commcenter/mongodb.tf` or `terraform/integrator-commcenter/compute.tf`)
  - [ ] Find the 3 `aws_instance` resources for `mongo003`, `mongo004`, `mongo005`
  - [ ] Add `iam_instance_profile = "mongo-cwagent"` to each instance
  - [ ] Verify the diff is minimal (only the 3 added lines)
- **Affected files/areas:** `terraform/integrator-commcenter/mongodb.tf` (or `compute.tf`)
- **Completion criteria:**
  - [ ] Each of the 3 mongo instances in commcenter stack has `iam_instance_profile = "mongo-cwagent"`
  - [ ] `terraform fmt` passes
  - [ ] No other changes in the file

---

### Task 6 — Add `iam_instance_profile` to `integrator-almaviva/` mongo EC2 instances

- **Objective:** Attach the `mongo-cwagent` instance profile to the 3 MongoDB instances in the almaviva stack (stopped).
- **Actions (checklist):**
  - [ ] Locate the almaviva stack's compute file
  - [ ] Find the 3 `aws_instance` resources for `mongo003`, `mongo004`, `mongo005`
  - [ ] Add `iam_instance_profile = "mongo-cwagent"` to each instance
  - [ ] Verify minimal diff
- **Affected files/areas:** `terraform/integrator-almaviva/mongodb.tf` (or `compute.tf`)
- **Completion criteria:**
  - [ ] Each of the 3 mongo instances in almaviva stack has `iam_instance_profile = "mongo-cwagent"`
  - [ ] `terraform fmt` passes

---

### Task 7 — Add `iam_instance_profile` to `integrator-maqnelson/` mongo EC2 instances

- **Objective:** Attach the `mongo-cwagent` instance profile to the 3 MongoDB instances in the maqnelson stack (stopped).
- **Actions (checklist):**
  - [ ] Locate the maqnelson stack's compute file
  - [ ] Find the 3 `aws_instance` resources for `mongo003`, `mongo004`, `mongo005`
  - [ ] Add `iam_instance_profile = "mongo-cwagent"` to each instance
  - [ ] Verify minimal diff
- **Affected files/areas:** `terraform/integrator-maqnelson/mongodb.tf` (or `compute.tf`)
- **Completion criteria:**
  - [ ] Each of the 3 mongo instances in maqnelson stack has `iam_instance_profile = "mongo-cwagent"`
  - [ ] `terraform fmt` passes

---

### Task 8 — Add `iam_instance_profile` to `integrator-redebrasil/` mongo EC2 instances

- **Objective:** Attach the `mongo-cwagent` instance profile to the 3 MongoDB instances in the redebrasil stack (stopped).
- **Actions (checklist):**
  - [ ] Locate the redebrasil stack's compute file
  - [ ] Find the 3 `aws_instance` resources for `mongo003`, `mongo004`, `mongo005`
  - [ ] Add `iam_instance_profile = "mongo-cwagent"` to each instance
  - [ ] Verify minimal diff
- **Affected files/areas:** `terraform/integrator-redebrasil/mongodb.tf` (or `compute.tf`)
- **Completion criteria:**
  - [ ] Each of the 3 mongo instances in redebrasil stack has `iam_instance_profile = "mongo-cwagent"`
  - [ ] `terraform fmt` passes

---

### Task 9 — Run `terraform plan` for `shared-resources/` and present summary

- **Objective:** Validate the IAM changes in the shared stack and get engineer approval before applying.
- **Actions (checklist):**
  - [ ] Navigate to `terraform/shared-resources/`
  - [ ] Run `terraform init` if this is the first plan in this session (or if `.terraform/` is missing)
  - [ ] Run `terraform plan -out=/tmp/shared-resources.tfplan` and capture output to `/tmp/shared-resources.plan.txt`
  - [ ] Execute: `terraform show /tmp/shared-resources.tfplan > /tmp/shared-resources.plan.txt`
  - [ ] Present a summary to the engineer in structured format:
    - Plan result: 1 resource to add (instance profile `mongo-cwagent`)
    - Underlying: 1 IAM role + 1 policy attachment (shown as part of the profile creation)
    - Estimated cost impact: $0 (IAM is free)
  - [ ] **[HOLD POINT]** Wait for engineer approval: "ok" or "approved" means proceed to Task 10 (apply)
- **Affected files/areas:** `terraform/shared-resources/` (plan only)
- **Completion criteria:**
  - [ ] `/tmp/shared-resources.tfplan` and `/tmp/shared-resources.plan.txt` exist and can be reviewed
  - [ ] Summary presented clearly showing 1 addition to shared-resources
  - [ ] Engineer explicitly approves before proceeding

---

### Task 10 — Apply `terraform plan` for `shared-resources/` (create IAM instance profile)

- **Objective:** Create the `mongo-cwagent` IAM role, policy attachment, and instance profile.
- **Actions (checklist):**
  - [ ] Ensure previous task (Task 9) has engineer approval
  - [ ] Navigate to `terraform/shared-resources/`
  - [ ] Run `/aws-elevate` to activate MFA-elevated AWS profile (`4shark-mfa`)
  - [ ] Run `terraform apply /tmp/shared-resources.tfplan --profile 4shark-mfa`
  - [ ] Verify output shows: "Apply complete! Resources added: 3." (role, policy attachment, instance profile)
  - [ ] Verify the output `mongo_cwagent_instance_profile_name` is displayed (should be `"mongo-cwagent"`)
- **Affected files/areas:** AWS IAM (shared-resources stack applies)
- **Completion criteria:**
  - [ ] `terraform apply` completes successfully
  - [ ] Output shows the instance profile name and ARN
  - [ ] No errors or warnings

---

### Task 11 — Run `terraform plan` for `integrator-atento/` and present summary

- **Objective:** Validate the instance profile attachment to atento mongo instances.
- **Actions (checklist):**
  - [ ] Navigate to `terraform/integrator-atento/`
  - [ ] Run `terraform init` if needed
  - [ ] Run `terraform plan -out=/tmp/integrator-atento.tfplan` and save to `/tmp/integrator-atento.plan.txt`
  - [ ] Present summary: 3 resources to modify (the 3 mongo instances getting the IAM profile attachment)
  - [ ] **[HOLD POINT]** Wait for engineer approval
- **Affected files/areas:** `terraform/integrator-atento/` (plan only)
- **Completion criteria:**
  - [ ] Plan shows 3 modifications (one per mongo instance)
  - [ ] Engineer approves

---

### Task 12 — Apply `terraform plan` for `integrator-atento/` (attach profile to running cluster)

- **Objective:** Attach the `mongo-cwagent` instance profile to the 3 running atento mongo instances (no restart needed).
- **Actions (checklist):**
  - [ ] Ensure Task 11 approval received
  - [ ] Navigate to `terraform/integrator-atento/`
  - [ ] Ensure `/aws-elevate` is still active (MFA-elevated profile available)
  - [ ] Run `terraform apply /tmp/integrator-atento.tfplan --profile 4shark-mfa`
  - [ ] Verify output: "Apply complete! Resources changed: 3."
- **Affected files/areas:** AWS EC2 instances in atento stack
- **Completion criteria:**
  - [ ] Apply completes with 3 changes
  - [ ] No errors

---

### Task 13 — Run `terraform plan` for `integrator-commcenter/` and present summary

- **Objective:** Validate the instance profile attachment to commcenter mongo instances.
- **Actions (checklist):**
  - [ ] Navigate to `terraform/integrator-commcenter/`
  - [ ] Run `terraform init` if needed
  - [ ] Run `terraform plan -out=/tmp/integrator-commcenter.tfplan` and save output
  - [ ] Present summary: 3 resources to modify
  - [ ] **[HOLD POINT]** Wait for engineer approval
- **Affected files/areas:** `terraform/integrator-commcenter/` (plan only)
- **Completion criteria:**
  - [ ] Plan shows 3 modifications
  - [ ] Engineer approves

---

### Task 14 — Apply `terraform plan` for `integrator-commcenter/` (attach profile to running cluster)

- **Objective:** Attach the `mongo-cwagent` instance profile to the 3 running commcenter mongo instances.
- **Actions (checklist):**
  - [ ] Ensure Task 13 approval received
  - [ ] Navigate to `terraform/integrator-commcenter/`
  - [ ] Run `terraform apply /tmp/integrator-commcenter.tfplan --profile 4shark-mfa`
  - [ ] Verify: "Apply complete! Resources changed: 3."
- **Affected files/areas:** AWS EC2 instances in commcenter stack
- **Completion criteria:**
  - [ ] Apply completes with 3 changes
  - [ ] No errors

---

### Task 15 — Run `terraform plan` for `integrator-almaviva/` and present summary

- **Objective:** Validate the instance profile attachment to almaviva mongo instances (stopped cluster).
- **Actions (checklist):**
  - [ ] Navigate to `terraform/integrator-almaviva/`
  - [ ] Run `terraform init` if needed
  - [ ] Run `terraform plan -out=/tmp/integrator-almaviva.tfplan` and save output
  - [ ] Present summary: 3 resources to modify
  - [ ] **[HOLD POINT]** Wait for engineer approval
- **Affected files/areas:** `terraform/integrator-almaviva/` (plan only)
- **Completion criteria:**
  - [ ] Plan shows 3 modifications
  - [ ] Engineer approves

---

### Task 16 — Apply `terraform plan` for `integrator-almaviva/` (attach profile to stopped cluster)

- **Objective:** Attach the `mongo-cwagent` instance profile to the 3 stopped almaviva mongo instances (instance profile is attached in metadata; IMDS will serve it on next start).
- **Actions (checklist):**
  - [ ] Ensure Task 15 approval received
  - [ ] Navigate to `terraform/integrator-almaviva/`
  - [ ] Run `terraform apply /tmp/integrator-almaviva.tfplan --profile 4shark-mfa`
  - [ ] Verify: "Apply complete! Resources changed: 3."
- **Affected files/areas:** AWS EC2 instances in almaviva stack
- **Completion criteria:**
  - [ ] Apply completes with 3 changes
  - [ ] No errors

---

### Task 17 — Run `terraform plan` for `integrator-maqnelson/` and present summary

- **Objective:** Validate the instance profile attachment to maqnelson mongo instances (stopped cluster).
- **Actions (checklist):**
  - [ ] Navigate to `terraform/integrator-maqnelson/`
  - [ ] Run `terraform init` if needed
  - [ ] Run `terraform plan -out=/tmp/integrator-maqnelson.tfplan` and save output
  - [ ] Present summary: 3 resources to modify
  - [ ] **[HOLD POINT]** Wait for engineer approval
- **Affected files/areas:** `terraform/integrator-maqnelson/` (plan only)
- **Completion criteria:**
  - [ ] Plan shows 3 modifications
  - [ ] Engineer approves

---

### Task 18 — Apply `terraform plan` for `integrator-maqnelson/` (attach profile to stopped cluster)

- **Objective:** Attach the `mongo-cwagent` instance profile to the 3 stopped maqnelson mongo instances.
- **Actions (checklist):**
  - [ ] Ensure Task 17 approval received
  - [ ] Navigate to `terraform/integrator-maqnelson/`
  - [ ] Run `terraform apply /tmp/integrator-maqnelson.tfplan --profile 4shark-mfa`
  - [ ] Verify: "Apply complete! Resources changed: 3."
- **Affected files/areas:** AWS EC2 instances in maqnelson stack
- **Completion criteria:**
  - [ ] Apply completes with 3 changes
  - [ ] No errors

---

### Task 19 — Run `terraform plan` for `integrator-redebrasil/` and present summary

- **Objective:** Validate the instance profile attachment to redebrasil mongo instances (stopped cluster).
- **Actions (checklist):**
  - [ ] Navigate to `terraform/integrator-redebrasil/`
  - [ ] Run `terraform init` if needed
  - [ ] Run `terraform plan -out=/tmp/integrator-redebrasil.tfplan` and save output
  - [ ] Present summary: 3 resources to modify
  - [ ] **[HOLD POINT]** Wait for engineer approval
- **Affected files/areas:** `terraform/integrator-redebrasil/` (plan only)
- **Completion criteria:**
  - [ ] Plan shows 3 modifications
  - [ ] Engineer approves

---

### Task 20 — Apply `terraform plan` for `integrator-redebrasil/` (attach profile to stopped cluster)

- **Objective:** Attach the `mongo-cwagent` instance profile to the 3 stopped redebrasil mongo instances.
- **Actions (checklist):**
  - [ ] Ensure Task 19 approval received
  - [ ] Navigate to `terraform/integrator-redebrasil/`
  - [ ] Run `terraform apply /tmp/integrator-redebrasil.tfplan --profile 4shark-mfa`
  - [ ] Verify: "Apply complete! Resources changed: 3."
- **Affected files/areas:** AWS EC2 instances in redebrasil stack
- **Completion criteria:**
  - [ ] Apply completes with 3 changes
  - [ ] No errors

---

### Task 21 — Verify all 15 instances have the IAM instance profile attached

- **Objective:** Confirm that all 15 MongoDB EC2 instances across the 5 stacks now have the `mongo-cwagent` instance profile attached.
- **Actions (checklist):**
  - [ ] Run the AWS CLI query (single line):
    ```
    aws ec2 describe-instances --region sa-east-1 --filters "Name=tag:Type,Values=mongodb" --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],IamInstanceProfile.Arn]' --output table
    ```
  - [ ] Review the output table:
    - All 15 hosts listed (atento-mongo003/004/005, commcenter-mongo003/004/005, almaviva-mongo003/004/005, maqnelson-mongo003/004/005, redebrasil-mongo003/004/005)
    - Each row shows `IamInstanceProfile.Arn` with a value like `arn:aws:iam::ACCOUNT:instance-profile/mongo-cwagent` (not `None`)
  - [ ] Count the rows to confirm exactly 15 instances with profiles set
- **Affected files/areas:** AWS EC2 (verification only, no changes)
- **Completion criteria:**
  - [ ] AWS CLI output confirms all 15 mongo instances have `IamInstanceProfile.Arn` set to the `mongo-cwagent` profile
  - [ ] No instances show `None` for the ARN field

---

### Task 22 — Commit the Terraform changes

- **Objective:** Create a single atomic commit with all Terraform file changes.
- **Actions (checklist):**
  - [ ] From the terraform repo root, run `git status` to verify all Terraform files are modified/new
  - [ ] Stage all Terraform changes: `git add terraform/shared-resources/mongo-cwagent.tf terraform/shared-resources/README.md terraform/integrator-atento/mongodb.tf terraform/integrator-commcenter/mongodb.tf terraform/integrator-almaviva/mongodb.tf terraform/integrator-maqnelson/mongodb.tf terraform/integrator-redebrasil/mongodb.tf` (adjust paths if instances are in `compute.tf` instead of `mongodb.tf`)
  - [ ] Verify staged changes: `git status` should show all 6–7 files in "Changes to be committed"
  - [ ] Commit with Angular style message:
    ```
    git commit -m "feat(iam): add mongo-cwagent instance profile for CloudWatch Agent"
    ```
    The message should not include AI co-authorship, Claude references, or detailed technical description. The commit message is clear and minimal.
  - [ ] Verify the commit: `git log -1` shows the new commit
- **Affected files/areas:** All modified Terraform files (shared-resources + 5 integrator stacks)
- **Completion criteria:**
  - [ ] Single commit created with message starting with `feat(iam):`
  - [ ] Commit includes all Terraform changes (mongo-cwagent.tf, README.md, and 5 stack mongodb.tf files)
  - [ ] `git log` shows the commit on the feature branch

---

### Task 23 — Push the feature branch with explicit refspec and open PR

- **Objective:** Push the feature branch and create a PR for review before final merge.
- **Actions (checklist):**
  - [ ] Verify you are on `feature/mongo-cwagent-iam-profile`
  - [ ] Push with explicit refspec (first push of new branch): `git push origin feature/mongo-cwagent-iam-profile:refs/heads/feature/mongo-cwagent-iam-profile`
  - [ ] After successful push, set tracking: `git branch --set-upstream-to=origin/feature/mongo-cwagent-iam-profile feature/mongo-cwagent-iam-profile`
  - [ ] Open PR via GitHub (or `gh pr create --title "feat(iam): add mongo-cwagent instance profile for CloudWatch Agent" --body "Terraform changes for Phase 0 of the Datadog-to-CloudWatch migration...."`) targeting `develop`
  - [ ] Verify PR is open and CI (terraform validate, linting, etc.) passes
- **Affected files/areas:** Remote branch + GitHub PR
- **Completion criteria:**
  - [ ] Feature branch is pushed to origin
  - [ ] PR is open on GitHub, targeting `develop`
  - [ ] PR title matches the commit message format
  - [ ] CI checks pass (if automated checks are configured)

---

### Task 24 — Merge PR to `develop`

- **Objective:** Finalize Phase 0 by merging the Terraform changes into the development branch.
- **Actions (checklist):**
  - [ ] Ensure PR has engineer approval and all CI checks pass
  - [ ] Merge the PR (via GitHub UI or `gh pr merge --merge`, creating a merge commit per 4Shark workflow — one commit per PR)
  - [ ] After merge, run `/merge-cleanup` to clean up the feature branch
- **Affected files/areas:** `develop` branch now includes Phase 0 IAM changes
- **Completion criteria:**
  - [ ] PR is merged
  - [ ] Feature branch is deleted (by merge-cleanup)
  - [ ] Verify `develop` is updated: `git log origin/develop -1` shows the merge commit

---

## 2) Items Requiring User Confirmation

- [ ] **AWS CLI access:** Default profile has read-only access; `/aws-elevate` activates MFA-elevated profile (`4shark-mfa`) for write operations. Confirm this is available.
- [ ] **File locations:** Confirm the exact paths where MongoDB EC2 instances are defined (e.g., `mongodb.tf` vs. `compute.tf` in each stack). If different, adjust task file references accordingly.
- [ ] **PR target branch:** All PRs target `develop` (not `main` or `master`). Confirm this is correct.
- [ ] **Cost impact:** Instance profile attachment is free. CloudWatch custom metrics will cost ~$5.40/month initially (3 metrics × 6 hosts), scaling to ~$13.50/month when all 15 are online. Acceptable per PLAN.md Decision 2.

---

## 3) Pending Items After This Iteration

- [ ] **Phase 1 (Ansible):** Create `ansible/TASKS.md` for Phases 1–7 (CloudWatch Agent provisioning, playbook changes, rollout validation). This begins after Phase 0 terraform PR is merged and applied.
- [ ] **Phase 2 validation:** After Terraform merge, Phase 2 of Ansible tasks (canary test on atento-mongo003) will require SSH/Ansible playbook execution — not part of this Phase 0 task list.

---

**Next:** After engineer confirms the checklist above, proceed to task execution. Phase 0 completion unblocks Phase 1 (Ansible changes).
