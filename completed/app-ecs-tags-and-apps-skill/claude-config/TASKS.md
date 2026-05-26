# NEXT TASKS — App ECS Skill (/apps) — Phase 2: Claude Config Implementation

> **Objective of this iteration:** Create the `/apps` skill in Claude Config by building `scripts/apps-services.sh` and `commands/apps.md`, mirroring the `/integrators` pattern. The skill covers two projects (`app`, `app-outbound`) across two regions (`us-east-1` for app, `sa-east-1` for app-outbound). Update documentation and test end-to-end after tags are live in AWS.
>
> **Reference:** derived from `PLAN.md` (Section: "Phase 2: Claude Config — /apps Skill").

---

## 0) Pre-conditions

- [ ] `PLAN.md` **approved** (Claude Config Phase 2)
- [ ] **Terraform Phase 1 is complete and merged** — all five stacks have tags live in AWS (four `app-*` stacks in `us-east-1`, one `app-outbound-atento-br` stack in `sa-east-1`)
- [ ] **Base branch:** `develop` • **Working branch:** `feature/apps-skill` (must be created in the `.claude` working copy)
- [ ] Working directory: `/Users/plribeiro3000/Projects/4Shark/.claude/` (NOT `~/.claude/` — per Configuration Changes Policy)
- [ ] Verify `app` tags are live:
  ```bash
  aws resourcegroupstaggingapi get-resources \
    --region us-east-1 \
    --resource-type-filters ecs:cluster \
    --tag-filters '[{"Key":"Project","Values":["app"]}]' \
    --query 'ResourceTagMappingList[].ResourceARN' \
    --output json
  ```
  Expected: 4 cluster ARNs
- [ ] Verify `app-outbound` tags are live:
  ```bash
  aws resourcegroupstaggingapi get-resources \
    --region sa-east-1 \
    --resource-type-filters ecs:cluster \
    --tag-filters '[{"Key":"Project","Values":["app-outbound"]}]' \
    --query 'ResourceTagMappingList[].ResourceARN' \
    --output json
  ```
  Expected: 1 cluster ARN

---

## 1) Step by Step (atomic tasks)

### Task 1 — Create feature branch in .claude working copy

- **Objective:** Set up isolated branch for Claude Config changes.
- **Actions (checklist):**
  - [ ] Navigate to `/Users/plribeiro3000/Projects/4Shark/.claude/`
  - [ ] Pull latest `develop` if not already up-to-date: `git pull origin develop`
  - [ ] Create feature branch: `git checkout -b feature/apps-skill`
  - [ ] Confirm: `git branch` shows `* feature/apps-skill`
- **Affected files/areas:** Git repository state only
- **Completion criteria:** Feature branch created and current; ready for code changes
- **Observations:** This is the `.claude` working copy, not the global `~/.claude/`. Configuration Changes Policy requires using the working copy for all edits.

---

### Task 2 — Create `scripts/apps-services.sh`

- **Objective:** Implement the shell script that discovers app ECS clusters and services by tag across two projects and two regions, mirroring `integrator-services.sh`.
- **Actions (checklist):**
  - [ ] Create file: `/Users/plribeiro3000/Projects/4Shark/.claude/scripts/apps-services.sh`
  - [ ] Implement script with these components:
    - Shebang: `#!/usr/bin/env bash`
    - `set -euo pipefail`
    - Region-per-project mapping (hardcoded in script):
      - `app` → `us-east-1`
      - `app-outbound` → `sa-east-1`
    - Cache file: `/tmp/apps_ecs_services.json`
    - Argument parsing:
      - `--project <name>` — optional; accepted values: `app`, `app-outbound`; default: query both
      - `--environment <env>` — optional; filter by `Environment` tag value
      - `--no-cache` — delete cache file and force fresh AWS query
      - unknown options → print error to stderr and exit 1
    - Query logic:
      - When `--project app`: query only `us-east-1` with `Project=app` tag filter
      - When `--project app-outbound`: query only `sa-east-1` with `Project=app-outbound` tag filter
      - When no `--project`: run both queries and union the JSON arrays
    - Per-region query sequence (same as `integrator-services.sh`):
      1. `aws resourcegroupstaggingapi get-resources --region <region> --resource-type-filters ecs:cluster --tag-filters <filters>` → get cluster ARNs
      2. For each ARN: `aws ecs list-tags-for-resource --region <region>` → extract `Project` and `Environment` tag values
      3. `aws ecs list-services --region <region> --cluster <cluster>` → get service ARNs
      4. `aws ecs describe-services --region <region> --cluster <cluster> --services <arns>` → get running/desired counts and status
    - Output JSON fields per service record: `Project`, `Cluster`, `Environment`, `Name`, `Status`, `Running`, `Desired`
    - Final output: `echo "$RESULTS" | jq '.' | tee "$CACHE_FILE"`
    - If no clusters found for a region: skip silently (the other region's results are still returned)
    - If a cluster has no services: emit a placeholder record with `Name: "(no services)"`, `Status: "-"`, `Running: 0`, `Desired: 0` (same as integrator pattern)
  - [ ] Validate syntax: `bash -n /Users/plribeiro3000/Projects/4Shark/.claude/scripts/apps-services.sh`
  - [ ] Make executable: `chmod +x /Users/plribeiro3000/Projects/4Shark/.claude/scripts/apps-services.sh`
  - [ ] Git stage the file
- **Affected files/areas:** `scripts/apps-services.sh` (new file)
- **Completion criteria:** Script created, syntax valid, executable, staged
- **Observations:**
  - Reference implementation: `~/.claude/scripts/integrator-services.sh` (lines 1–104). The new script follows the same structure exactly, extended to support two project/region pairs.
  - Unlike integrators, there is no `Client` tag on app or app-outbound clusters.
  - The `Project` field is mandatory in the output — it is the only way to distinguish app vs app-outbound records when both regions are queried together.
  - Cache file is `/tmp/apps_ecs_services.json` — distinct from `/tmp/integrator_ecs_services.json`.

---

### Task 3 — Create `commands/apps.md`

- **Objective:** Document the `/apps` skill for engineers, mirroring the `/integrators` command file structure.
- **Actions (checklist):**
  - [ ] Create file: `/Users/plribeiro3000/Projects/4Shark/.claude/commands/apps.md`
  - [ ] Implement command file with the following structure:
    - **YAML front matter:**
      ```yaml
      ---
      name: apps
      description: Manage app ECS clusters and services (list, scale up, scale down, check status, logs). Covers two projects: app (us-east-1) and app-outbound (sa-east-1). If the engineer already specified the project/environment and action, execute immediately without asking.
      ---
      ```
    - **Opening paragraph:** two projects, two regions — `app` in `us-east-1`, `app-outbound` in `sa-east-1`; all resources tagged with `Project=app` or `Project=app-outbound`.
    - **Available tags for filtering:**
      - `Project` — `app` (us-east-1) or `app-outbound` (sa-east-1)
      - `Environment` — for `app`: `shared-001`, `beta-001`, `demo-001`, `atento-001`; for `app-outbound`: `outbound-atento-br`
      - `ManagedBy` — always `terraform`
    - **Naming conventions:**
      - Clusters: `{environment}-cluster` for app (e.g., `shared-001-cluster`); `app-{project-suffix}-{environment}-cluster` for app-outbound (e.g., `app-outbound-atento-br-cluster`)
      - Note: `app-atento-001-cluster` keeps the `app-` prefix — it is a naming artifact, not a pattern
      - Services: `{environment}-web-service`, `{environment}-worker-service`, `{environment}-scheduler-service`
      - CloudWatch log groups: `/ecs/{environment}-web`, `/ecs/{environment}-worker`, `/ecs/{environment}-scheduler`
      - Use the region that matches the project when querying CloudWatch logs
    - **Important rules section** (mirrors `/integrators`):
      - Only ask when information is genuinely missing
      - Do NOT dump raw AWS output to the engineer
      - When no `--project` flag, list both projects across both regions
    - **Session cache section:**
      - Cache file: `/tmp/apps_ecs_services.json`
      - Check if exists before querying AWS
      - Use `--no-cache` to force fresh query
    - **Step 1 — Find the clusters and services:** Bash examples:
      ```bash
      # All clusters — both projects, both regions
      bash ~/.claude/scripts/apps-services.sh

      # Only app clusters (us-east-1)
      bash ~/.claude/scripts/apps-services.sh --project app

      # Only app-outbound clusters (sa-east-1)
      bash ~/.claude/scripts/apps-services.sh --project app-outbound

      # Filter by Environment tag
      bash ~/.claude/scripts/apps-services.sh --environment shared-001

      # Force refresh (ignore cache)
      bash ~/.claude/scripts/apps-services.sh --no-cache
      ```
    - **Fallback — no results:** If engineer specifies an environment that doesn't match, run without filter, show closest matches as numbered list, ask which one.
    - **Step 2 — Act:**
      - **List or check status:** Report project, environment, service name, running/desired counts, status.
      - **Scale up:** `aws ecs update-service --region <correct-region-for-project> --cluster <cluster> --service <service> --desired-count <N>`. If `AccessDenied`, run `/aws-elevate` and retry with `--profile 4shark-mfa`. Update cache. Report result.
      - **Scale down (to zero):** Confirm with engineer before scaling to zero. Same command with `--desired-count 0`. Update cache. Report result.
      - **Check logs:** `aws logs tail /ecs/{service-name} --region <correct-region-for-project> --since 30m --format short`
  - [ ] Git stage the file
- **Affected files/areas:** `commands/apps.md` (new file)
- **Completion criteria:** File created, complete, staged
- **Observations:** Reference: `~/.claude/commands/integrators.md` (lines 1–116). Key differences: two projects/regions instead of one, `--project` flag instead of `--client`, `Environment` is the primary filter. The region used for `update-service` and `logs tail` commands must match the project.

---

### Task 4 — Update `CLAUDE.md` (Available Commands section)

- **Objective:** Document the new `/apps` command in the global documentation.
- **Actions (checklist):**
  - [ ] Open `/Users/plribeiro3000/Projects/4Shark/.claude/CLAUDE.md`
  - [ ] Locate "Available Commands" section — find the `### /integrators` subsection
  - [ ] Add new subsection immediately after `/integrators`:
    ```markdown
    ### /apps
    - **Purpose**: Manage app ECS clusters and services (list, scale up/down, check status, logs)
    - **Behavior**: Discovers clusters by `Project=app` and `Project=app-outbound` tags across `us-east-1` and `sa-east-1`, filters by `Project` and `Environment` tags, acts on services, reports the result — caches results in session
    - **Important**: Only ask when information is genuinely missing — if the engineer already specified environment and action, execute immediately
    ```
  - [ ] Verify the formatting matches the `/integrators` entry immediately above it
  - [ ] Git stage the file
- **Affected files/areas:** `CLAUDE.md` (edit only, ~5 lines added)
- **Completion criteria:** `/apps` entry added, formatted consistently, staged
- **Observations:** Working copy path: `/Users/plribeiro3000/Projects/4Shark/.claude/CLAUDE.md` — not the global `~/.claude/CLAUDE.md`.

---

### Task 5 — Update `CHANGELOG.md`

- **Objective:** Document the new `/apps` skill in the changelog.
- **Actions (checklist):**
  - [ ] Open `/Users/plribeiro3000/Projects/4Shark/.claude/CHANGELOG.md`
  - [ ] Locate `[Unreleased]` section
  - [ ] Add entry under `### Added` (create the subsection if it does not exist):
    ```markdown
    - `/apps` skill for managing app ECS clusters and services
    ```
  - [ ] Git stage the file
- **Affected files/areas:** `CHANGELOG.md` (edit only, ~1 line added)
- **Completion criteria:** Entry added, file staged
- **Observations:** Keep the entry concise — the section title `### Added` already conveys this is a new feature.

---

### Task 6 — Validate script end-to-end against AWS (tags must be live)

- **Objective:** Confirm the script works correctly across both projects and both regions with live AWS infrastructure.
- **Actions (checklist):**
  - [ ] **Guard:** run prerequisite checks (from Pre-conditions section above); if either returns empty — HALT and wait for Terraform Phase 1 completion.
  - [ ] Run script with no flags (both projects):
    ```bash
    bash /Users/plribeiro3000/Projects/4Shark/.claude/scripts/apps-services.sh
    ```
    Expected: valid JSON array with 5 records (4 app + 1 app-outbound); all records have `Project` field.
  - [ ] Run with `--project app`:
    ```bash
    bash /Users/plribeiro3000/Projects/4Shark/.claude/scripts/apps-services.sh --project app
    ```
    Expected: 4 records; all with `"Project": "app"`; all from `us-east-1`.
  - [ ] Run with `--project app-outbound`:
    ```bash
    bash /Users/plribeiro3000/Projects/4Shark/.claude/scripts/apps-services.sh --project app-outbound
    ```
    Expected: 1 record; `"Project": "app-outbound"`; from `sa-east-1`.
  - [ ] Run with `--environment shared-001`:
    ```bash
    bash /Users/plribeiro3000/Projects/4Shark/.claude/scripts/apps-services.sh --environment shared-001
    ```
    Expected: 1 record; `"Environment": "shared-001"`.
  - [ ] Run with `--no-cache` (forces fresh AWS query):
    ```bash
    bash /Users/plribeiro3000/Projects/4Shark/.claude/scripts/apps-services.sh --no-cache
    ```
    Expected: same results as no-flag run; cache file recreated.
  - [ ] Verify cache file exists after any successful run: `ls -l /tmp/apps_ecs_services.json`
  - [ ] Save output to `/tmp/apps_services_validation_$(date +%Y%m%d_%H%M%S).json`
  - [ ] Report: "Script validated — N clusters returned; filtering by project and environment works correctly."
- **Affected files/areas:** AWS (read-only queries); `/tmp/apps_ecs_services.json` (cache)
- **Completion criteria:** All 5 filter scenarios return correct results; `Project` field present; cache created
- **[HOLD POINT]:** If tags are not live in AWS (either region returns empty), halt and wait for Terraform Phase 1 completion.

---

### Task 7 — Commit changes

- **Objective:** Create an atomic commit for all Phase 2 changes.
- **Actions (checklist):**
  - [ ] Verify all modified files are staged: `git status`
  - [ ] Expected staged files: `scripts/apps-services.sh`, `commands/apps.md`, `CLAUDE.md`, `CHANGELOG.md`
  - [ ] No other files staged (verify)
  - [ ] Create commit:
    ```
    feat(skills): add /apps command for app ECS cluster management
    ```
    (commit body optional — the subject line is sufficient per Angular guidelines)
  - [ ] Verify commit created: `git log --oneline -1`
- **Affected files/areas:** Git history
- **Completion criteria:** Commit created with Angular format; no AI/Claude references in commit message
- **Observations:** One commit per PR is the standard. Do not amend — create a new commit if corrections are needed after the first commit.

---

### Task 8 — Push to remote

- **Objective:** Push the feature branch to the remote repository.
- **Actions (checklist):**
  - [ ] Push using explicit refspec (required — see MEMORY.md Git Push Rule):
    ```bash
    git push origin feature/apps-skill:refs/heads/feature/apps-skill
    ```
  - [ ] Verify push succeeded: `git log --oneline origin/feature/apps-skill..HEAD` should return nothing
- **Affected files/areas:** Remote repository
- **Completion criteria:** Branch pushed to remote; no divergence between local and remote

---

### Task 9 — Open PR

- **Objective:** Create PR against `develop` in the `.claude` repository for code review.
- **Actions (checklist):**
  - [ ] Confirm target branch is `develop`
  - [ ] Create PR via `gh pr create` (in the `.claude` repository):
    - Title: `feat(skills): add /apps command for app ECS cluster management`
    - Body: describe that the script covers two projects (`app` in `us-east-1`, `app-outbound` in `sa-east-1`), mirrors the `/integrators` pattern, includes `Project` field in output to distinguish clusters across regions, and has been validated end-to-end against live AWS.
  - [ ] Share PR URL with engineer
- **Affected files/areas:** GitHub pull request
- **Completion criteria:** PR opened against `develop` in the `.claude` repository; URL shared

---

### Task 10 — Merge and cleanup

- **Objective:** Merge the PR after approval and clean up local branch.
- **Actions (checklist):**
  - [ ] Wait for PR approval
  - [ ] Merge PR via GitHub UI or `gh pr merge`
  - [ ] Run `/merge-cleanup` in the `.claude` working copy to delete local feature branch and prune remote refs
  - [ ] Pull latest `develop` in the working copy: `git pull origin develop`
  - [ ] Verify files are present after merge:
    - `scripts/apps-services.sh` (executable)
    - `commands/apps.md`
    - `CLAUDE.md` (contains `/apps` entry)
    - `CHANGELOG.md` (contains `/apps` entry)
  - [ ] Run one final smoke test:
    ```bash
    bash ~/.claude/scripts/apps-services.sh --project app --environment shared-001
    ```
    Expected: 1 record for shared-001 cluster.
  - [ ] Report: "Skill `/apps` is live and functional."
- **Affected files/areas:** Git branches; file verification
- **Completion criteria:** PR merged; branch cleaned up; all files present and functional

---

## 2) Items Requiring User Confirmation

- [ ] **Timing dependency:** Phase 2 tasks must not start until Terraform Phase 1 is **merged and applied** in both regions. If tags are not live in AWS, Task 6 (validation) will fail.
- [ ] **Cache scope:** Cache file `/tmp/apps_ecs_services.json` is session-local and covers both projects/regions in a single file. Engineers use `--no-cache` to force a fresh query. Acceptable?
- [ ] **No Client tag on app or app-outbound clusters:** The `/apps` command does not support `--client` filtering. `--project` and `--environment` are the only filters. Acceptable?

---

## 3) Pending Items After This Iteration (if any arise)

- [ ] **Log group patterns:** If app services use non-standard CloudWatch log group naming (e.g., not `/ecs/{environment}-*`), update the command documentation with actual patterns.
- [ ] **app-outbound growth:** If additional app-outbound stacks are added in the future, update the `app-outbound` environment values documented in `commands/apps.md`.
- [ ] **Post-merge:** Update `PLAN.md` status from "READY FOR TASK CREATION" to "COMPLETE" once all tasks are done.
