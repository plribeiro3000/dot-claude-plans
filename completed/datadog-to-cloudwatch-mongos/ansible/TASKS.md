# NEXT TASKS — Phases 1–7: Ansible CloudWatch Agent Deployment — Option B

> **Objective of this iteration:** Replace the Datadog Agent with CloudWatch Agent in MongoDB provisioning playbooks, validate on running clusters, roll out to stopped clusters, clean up Datadog infrastructure, and establish CloudWatch monitoring. Begins after Phase 0 (Terraform IAM instance profile) is complete.
>
> **Reference:** derived from `PLAN.md` § "Phase 1–7" and § "Decision 1 (1C: local `4shark.cloudwatch_agent` role)".

---

## 0) Pre-conditions

- [x] `PLAN.md` **approved** (Option B: Terraform first, then Ansible).
- [ ] **Phase 0 complete:** Terraform PR merged and applied; all 15 mongo instances have `mongo-cwagent` IAM instance profile attached.
- [ ] **Base branch:** `develop` • **Working branch:** `feature/replace-datadog-with-cloudwatch-mongos`
- [ ] Access to Ansible playbook runner (`run_playbook.sh` in ansible repo) and SSH into running MongoDB instances for Phase 2 validation.
- [ ] Datadog API token available (for Phase 5 host removal, if using API instead of UI).

---

## 1) Step by Step (atomic tasks)

### Task 1 — Create feature branch and prepare Ansible workspace

- **Objective:** Set up clean feature branch in the ansible repository.
- **Actions (checklist):**
  - [ ] Navigate to `~/Projects/4Shark/ansible/`
  - [ ] Verify on `develop` and up-to-date (`git pull origin develop`)
  - [ ] Create and check out: `git checkout -b feature/replace-datadog-with-cloudwatch-mongos`
- **Affected files/areas:** None yet (branch setup)
- **Completion criteria:** Feature branch created and checked out

---

### Task 2 — Create local Ansible role `4shark.cloudwatch_agent`

- **Objective:** Build a new role to install and configure the CloudWatch Agent.
- **Actions (checklist):**
  - [ ] Create role directory structure:
    ```
    roles/4shark.cloudwatch_agent/
    ├── tasks/
    │   └── main.yml
    ├── templates/
    │   └── amazon-cloudwatch-agent.json.j2
    ├── defaults/
    │   └── main.yml
    ├── handlers/
    │   └── main.yml
    └── README.md (optional, but recommended)
    ```
  - [ ] **`tasks/main.yml`:** Include the following tasks in order:
    - Uninstall `datadog-agent` if present (check if package exists, then apt remove)
    - Download `amazon-cloudwatch-agent` `.deb` from AWS S3 (architecture-aware: detect via `ansible_architecture` and fetch correct binary)
    - Install the `.deb` package
    - Copy the CloudWatch Agent config file from template (using `amazon-cloudwatch-agent.json.j2`)
    - Enable and start the `amazon-cloudwatch-agent` service
    - Register handlers for config changes
  - [ ] **`templates/amazon-cloudwatch-agent.json.j2`:** Exact JSON from PLAN.md § Decision 2 (metrics: mem_used_percent, disk_used_percent, swap_used_percent, namespace CWAgent, dimensions InstanceId)
  - [ ] **`defaults/main.yml`:** Set default variables:
    - `cloudwatch_agent_metrics_collection_interval: 60` (seconds)
    - `cloudwatch_agent_namespace: "CWAgent"`
  - [ ] **`handlers/main.yml`:** Add handler to restart `amazon-cloudwatch-agent` when config changes
  - [ ] Verify variable naming: no abbreviations, all names fully spelled out (e.g., `cloudwatch_agent_*`, not `cw_agent_*`)
- **Affected files/areas:** `ansible/roles/4shark.cloudwatch_agent/` (new role)
- **Completion criteria:**
  - [ ] Role directory exists with all 4 subdirectories
  - [ ] `tasks/main.yml` has uninstall + download + install + config + enable steps
  - [ ] Template `amazon-cloudwatch-agent.json.j2` matches Decision 2 JSON
  - [ ] No syntax errors in YAML files

---

### Task 3 — Update `provision-4client-mongodb-server.yml` playbook

- **Objective:** Replace Datadog role with CloudWatch Agent role in the main MongoDB provisioning playbook.
- **Actions (checklist):**
  - [ ] Read `playbooks/provision-4client-mongodb-server.yml` to understand structure
  - [ ] In the first play (MongoDB server provisioning):
    - Remove `Datadog.datadog` from the `roles:` list
    - Add `4shark.cloudwatch_agent` to the `roles:` list (in the same position or after the MongoDB role)
    - Remove the `datadog_config:` and `datadog_checks:` keys from the `vars:` section
  - [ ] Verify the play still references the `4shark.mongodb` role (should be unchanged)
  - [ ] Verify no other changes are introduced
- **Affected files/areas:** `ansible/playbooks/provision-4client-mongodb-server.yml`
- **Completion criteria:**
  - [ ] Playbook no longer has `Datadog.datadog` or `datadog_*` variables
  - [ ] `4shark.cloudwatch_agent` role is included
  - [ ] Play structure and other roles unchanged

---

### Task 4 — Update `provision-4client-mongodb-new-nodes.yml` playbook

- **Objective:** Replace Datadog role with CloudWatch Agent role in the new-nodes playbook.
- **Actions (checklist):**
  - [ ] Read `playbooks/provision-4client-mongodb-new-nodes.yml`
  - [ ] In the single play (adding new nodes to existing replicaset):
    - Remove `Datadog.datadog` from `roles:`
    - Add `4shark.cloudwatch_agent` to `roles:`
    - Remove `datadog_config:` and `datadog_checks:` from `vars:`
  - [ ] Verify the play still includes the MongoDB tasks (should be unchanged)
- **Affected files/areas:** `ansible/playbooks/provision-4client-mongodb-new-nodes.yml`
- **Completion criteria:**
  - [ ] Playbook no longer references Datadog
  - [ ] `4shark.cloudwatch_agent` is included
  - [ ] No other changes

---

### Task 5 — Update `requirements.yml` to remove Datadog role dependency

- **Objective:** Remove the external Datadog role dependency from Galaxy requirements.
- **Actions (checklist):**
  - [ ] Read `ansible/requirements.yml`
  - [ ] Find and remove the line(s) defining `Datadog.datadog v4.9.0` (or current version)
  - [ ] Ensure no new external role entry is added (we're using local role `4shark.cloudwatch_agent`)
  - [ ] Verify the file still has other dependencies (e.g., `geerlingguy.*`, `community.*`)
- **Affected files/areas:** `ansible/requirements.yml`
- **Completion criteria:**
  - [ ] `Datadog.datadog` entry removed
  - [ ] File structure otherwise unchanged

---

### Task 6 — Update `CHANGELOG.md` with Phase 1 changes

- **Objective:** Document the provisioning change in the changelog.
- **Actions (checklist):**
  - [ ] Read `CHANGELOG.md` and locate the `## [Unreleased]` section
  - [ ] Under `### Changed`, add one line:
    ```
    - MongoDB provisioning: replaced Datadog Agent with CloudWatch Agent
    ```
  - [ ] No technical details (role names, file paths, etc.) — just the user-facing change
- **Affected files/areas:** `CHANGELOG.md`
- **Completion criteria:**
  - [ ] Changelog entry added under `[Unreleased] / Changed`
  - [ ] Entry is concise and user-focused

---

### Task 7 — Commit Phase 1 Ansible changes

- **Objective:** Create a single atomic commit with all playbook and role changes.
- **Actions (checklist):**
  - [ ] Run `git status` to verify all Ansible files are staged/modified
  - [ ] Stage all changes:
    ```
    git add roles/4shark.cloudwatch_agent/ playbooks/provision-4client-mongodb-server.yml playbooks/provision-4client-mongodb-new-nodes.yml requirements.yml CHANGELOG.md
    ```
  - [ ] Verify: `git status` shows all 5+ items in "Changes to be committed"
  - [ ] Commit:
    ```
    git commit -m "refactor(mongodb): replace Datadog Agent with CloudWatch Agent"
    ```
  - [ ] Verify: `git log -1` shows the new commit
- **Affected files/areas:** All modified Ansible files
- **Completion criteria:**
  - [ ] Single commit created with message starting with `refactor(mongodb):`
  - [ ] Commit includes all playbook, role, and requirements changes

---

### Task 8 — Push feature branch and open PR

- **Objective:** Push to origin and open PR for Phase 1 Ansible changes.
- **Actions (checklist):**
  - [ ] Verify on `feature/replace-datadog-with-cloudwatch-mongos`
  - [ ] Push with explicit refspec (first push): `git push origin feature/replace-datadog-with-cloudwatch-mongos:refs/heads/feature/replace-datadog-with-cloudwatch-mongos`
  - [ ] Set tracking: `git branch --set-upstream-to=origin/feature/replace-datadog-with-cloudwatch-mongos feature/replace-datadog-with-cloudwatch-mongos`
  - [ ] Open PR targeting `develop` (via GitHub UI or `gh pr create`)
  - [ ] Verify CI (YAML validation, linting) passes
- **Affected files/areas:** Remote branch + GitHub PR
- **Completion criteria:**
  - [ ] Feature branch pushed
  - [ ] PR is open and CI passes

---

### Task 9 — Phase 2: Validate on atento-mongo003 (canary)

- **Objective:** Run the updated playbook on a single non-primary MongoDB instance to validate the CloudWatch Agent setup before rolling out further.
- **Actions (checklist):**
  - [ ] Ensure Phase 0 (Terraform) is complete and merged
  - [ ] Ensure Phase 1 PR is merged (if required before testing) OR test from the feature branch if pre-approval testing is allowed
  - [ ] Run the updated playbook targeting only `atento-mongo003`:
    ```
    ./run_playbook.sh 4shark playbooks/provision-4client-mongodb-server.yml --limit atento-mongo003
    ```
    (Exact command depends on your `run_playbook.sh` signature; adjust as needed)
  - [ ] After playbook completes:
    - [ ] SSH into `atento-mongo003`
    - [ ] Verify `systemctl is-active datadog-agent` returns `inactive` or `Unit datadog-agent.service not loaded`
    - [ ] Verify `systemctl is-active amazon-cloudwatch-agent` returns `active`
    - [ ] Verify MongoDB is still running: `systemctl is-active mongod` returns `active`
    - [ ] Check replicaset health: `mongo --eval "rs.status()"` shows this node as `SECONDARY` with healthy status
    - [ ] Wait 2–3 minutes for CloudWatch Agent to send first batch of metrics, then verify:
      ```
      aws cloudwatch get-metric-statistics --namespace CWAgent --metric-name mem_used_percent --dimensions Name=InstanceId,Value=<i-xxxxx> --start-time <T-5min> --end-time <T> --period 60 --statistics Average
      ```
      Should return at least one datapoint with a numeric value
  - [ ] Monitor logs if needed: `tail -f /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log` (or similar path)
  - [ ] Watch for 30 minutes for any anomalies (error rates, connection failures, replication lag spikes)
  - [ ] **[HOLD POINT]** After 30 min of stable observation, engineer approves canary success before proceeding to Phase 3
- **Affected files/areas:** atento-mongo003 (production instance)
- **Completion criteria:**
  - [ ] Datadog Agent removed and inactive
  - [ ] CloudWatch Agent active and sending metrics (at least one datapoint in CloudWatch)
  - [ ] MongoDB replicaset still healthy and running
  - [ ] No errors in CloudWatch Agent logs for 30 min
  - [ ] Engineer approves canary

---

### Task 10 — Phase 3: Rollout to remaining 5 running MongoDB instances

- **Objective:** Deploy CloudWatch Agent to the other 5 running mongos (commcenter-mongo003/004/005, atento-mongo004/005) one at a time, with 5-minute waits between each.
- **Actions (checklist):**
  - [ ] Ensure Phase 2 (canary) is approved
  - [ ] For each target host in order: `commcenter-mongo003`, `commcenter-mongo004`, `commcenter-mongo005`, `atento-mongo004`, `atento-mongo005`:
    - [ ] Run the updated playbook targeting that host:
      ```
      ./run_playbook.sh 4shark playbooks/provision-4client-mongodb-server.yml --limit <hostname>
      ```
    - [ ] After playbook completes, verify same 4 steps as canary (datadog inactive, cloudwatch active, mongod running, replicaset healthy)
    - [ ] Verify CloudWatch metrics appear for this host
    - [ ] **Wait 5 minutes** before moving to next host (let monitoring breathe)
  - [ ] Total time: ~5 hosts × (5 min playbook run + 5 min wait) = ~50 minutes
  - [ ] **[HOLD POINT]** After all 5 rollout, engineer confirms all 6 running mongos (atento + commcenter) are CloudWatch-enabled
- **Affected files/areas:** 5 production MongoDB instances
- **Completion criteria:**
  - [ ] All 5 instances complete playbook run
  - [ ] All 5 show CloudWatch Agent active and metrics appearing
  - [ ] All 5 replicasets remain healthy
  - [ ] Engineer approves Phase 3 completion

---

### Task 11 — Phase 4: Apply to 9 stopped MongoDB instances (almaviva, maqnelson, redebrasil)

- **Objective:** Start each stopped cluster one at a time, run the playbook, validate, and stop again.
- **Actions (checklist):**
  - [ ] Ensure Phase 3 (rollout to running clusters) is approved
  - [ ] For each client in order: `almaviva`, `maqnelson`, `redebrasil`:
    - [ ] **Start the cluster:**
      ```
      /aws-elevate  # Activate MFA-elevated profile
      aws ec2 start-instances --instance-ids i-<almaviva-mongo003> i-<almaviva-mongo004> i-<almaviva-mongo005> --region sa-east-1
      ```
      (Substitute actual instance IDs from terraform state or AWS console)
    - [ ] Wait for status "running" + 2/2 status checks: `aws ec2 wait instance-running && aws ec2 wait instance-status-ok`
    - [ ] Run the playbook:
      ```
      ./run_playbook.sh 4shark playbooks/provision-4client-mongodb-server.yml --limit 'almaviva-mongo003,almaviva-mongo004,almaviva-mongo005'
      ```
    - [ ] Verify all 3 instances post-run: cloudwatch active, datadog inactive, mongod running, replicaset health
    - [ ] Verify CloudWatch metrics appear
    - [ ] Wait 5 minutes for observation
    - [ ] **Stop the cluster:**
      ```
      /aws-elevate  # Ensure MFA still active
      aws ec2 stop-instances --instance-ids i-<almaviva-mongo003> i-<almaviva-mongo004> i-<almaviva-mongo005> --region sa-east-1
      ```
    - [ ] Repeat for `maqnelson` and `redebrasil`
  - [ ] Total time: 3 clients × (~15 min per cycle) = ~45 minutes
  - [ ] **[HOLD POINT]** After all 9 stopped instances are processed, engineer confirms Phase 4 complete
- **Affected files/areas:** 9 stopped MongoDB instances
- **Completion criteria:**
  - [ ] All 9 instances have CloudWatch Agent installed and configured (verified when running)
  - [ ] All 9 instances restarted successfully after playbook run
  - [ ] CloudWatch Agent will serve credentials from IMDS on next start (no manual config needed in future)
  - [ ] Engineer approves Phase 4

---

### Task 12 — Phase 5: Remove MongoDB hosts from Datadog Infrastructure

- **Objective:** Delete the 15 MongoDB hostnames from Datadog to stop billing them as infrastructure hosts.
- **Actions (checklist):**
  - [ ] Choose one of two approaches:
    - **Approach A (UI):** Via Datadog → Infrastructure List → search `4client-*-mongo*` → multi-select all 15 → Mute → Delete
    - **Approach B (API):** Use Datadog API (`POST /api/v1/hosts/{hostname}/mute` + delete) with API token
  - [ ] After deletion, verify in Datadog billing dashboard or host list that the 15 hosts are gone
  - [ ] **[HOLD POINT]** Confirm deletion with engineer; Datadog billing adjustment will appear in next cycle
- **Affected files/areas:** Datadog infrastructure (external service)
- **Completion criteria:**
  - [ ] All 15 `4client-*-mongo*` hosts removed from Datadog Infrastructure List
  - [ ] Datadog console shows zero hosts matching that pattern
  - [ ] Engineer confirms next billing cycle should not include those hosts

---

### Task 13 — Phase 6: Create CloudWatch dashboard and alarms for MongoDB monitoring

- **Objective:** Replace the Datadog MongoDB dashboard with a CloudWatch dashboard showing key metrics and set up alarms.
- **Actions (checklist):**
  - [ ] Create a CloudWatch dashboard named `MongoDB-CloudWatch-Monitor` (or similar):
    - [ ] Add widgets (per mongo instance or aggregated):
      - **CPU Utilization** (native CloudWatch EC2 metric)
      - **Memory Used %** (CWAgent custom metric `mem_used_percent`)
      - **Disk Used %** (CWAgent custom metric `disk_used_percent`)
      - **Network In/Out** (native EC2 metrics)
      - **EBS Read/Write IOPS** (native EBS metrics)
      - **Status Check Failed** (native EC2 status check)
    - [ ] Configure time range and auto-refresh appropriate for monitoring (e.g., 1-hour window, 1-minute refresh)
  - [ ] Create alarms (optional, based on team preference):
    - `mem_used_percent > 85%` → SNS notification
    - `disk_used_percent > 80%` → SNS notification
    - `CPUUtilization > 90% for 5 min` → SNS notification
    - `StatusCheckFailed > 0` → SNS notification
  - [ ] Route alarms to existing SNS topic / PagerDuty if applicable (verify current wiring; if none exist, document for follow-up)
  - [ ] **[HOLD POINT]** Show engineer the dashboard and alarms; get approval before proceeding
- **Affected files/areas:** AWS CloudWatch (new dashboard and alarms)
- **Completion criteria:**
  - [ ] CloudWatch dashboard created with 6+ widgets showing mongo metrics
  - [ ] Alarms created (if desired) and connected to notification channels
  - [ ] Engineer approves the monitoring setup

---

### Task 14 — Phase 7: Cleanup and archive

- **Objective:** Final cleanup and archival of the migration plan.
- **Actions (checklist):**
  - [ ] (Optional) Review and delete the Datadog `MongoDB Overview` dashboard if no other team uses it (confirm with engineer first)
  - [ ] Merge Phase 1 PR if not already merged
  - [ ] Update the `PLAN.md` status to reflect completion
  - [ ] Move the plan folder from `~/.claude/plans/active/datadog-to-cloudwatch-mongos/` to `~/.claude/plans/completed/datadog-to-cloudwatch-mongos/`
  - [ ] Document any follow-up tasks or lessons learned as comments in the completed plan
- **Affected files/areas:** Planning filesystem, Datadog (optional deletion)
- **Completion criteria:**
  - [ ] Phase 1 PR merged to `develop`
  - [ ] Plan folder moved to `completed/`
  - [ ] Datadog MongoDB dashboard removed (if applicable)

---

### Task 15 — Final Verification: All 15 hosts sending CloudWatch metrics

- **Objective:** Confirm that all 15 MongoDB instances (6 running + 9 that were temporarily started) are sending CloudWatch metrics.
- **Actions (checklist):**
  - [ ] Query CloudWatch for instances sending `mem_used_percent` metrics:
    ```
    aws cloudwatch list-metrics --namespace CWAgent --metric-name mem_used_percent --region sa-east-1 --query 'Metrics[].Dimensions[?Name==`InstanceId`]'
    ```
  - [ ] Count the results: should be at least 6 (running cluster mongos) + presence of metrics from the other 9 (which were started and ran playbook)
  - [ ] For the 6 running instances, verify continuous metrics: `aws cloudwatch get-metric-statistics --namespace CWAgent --metric-name mem_used_percent --start-time <T-30min> --end-time <T> --period 300 --statistics Average` should show multiple datapoints
  - [ ] **[HOLD POINT]** Confirm final verification with engineer
- **Affected files/areas:** CloudWatch (verification only)
- **Completion criteria:**
  - [ ] All 15 hosts have sent at least one `mem_used_percent` metric to CloudWatch
  - [ ] Running hosts show continuous metrics (datapoints every 60 seconds)
  - [ ] Engineer approves final verification

---

## 2) Items Requiring User Confirmation

- [ ] **CloudWatch Agent source URL:** The `.deb` download URL in the `4shark.cloudwatch_agent` role must match the correct AWS S3 bucket for the region (sa-east-1) and architecture. Verify against AWS docs before Task 2.
- [ ] **Playbook runner syntax:** The exact command format for `run_playbook.sh` and `--limit` flag may vary. Confirm with the engineer before Task 9.
- [ ] **Datadog API token:** Needed only if using Approach B (API) in Phase 5. If using UI, no token needed.
- [ ] **Stopped instance IDs:** For Phase 4, the exact instance IDs for almaviva, maqnelson, redebrasil mongos must be determined from terraform state or AWS console. Prepare before Task 11.
- [ ] **CloudWatch alarms SNS routing:** Confirm whether existing SNS topics exist and which team receives notifications. This affects Phase 6 setup.

---

## 3) Pending Items After This Iteration

- [ ] **Per-client failover testing:** After Phase 7, the ops team may want to test failover scenarios for each replicaset under CloudWatch monitoring (not part of this plan, but good follow-up).
- [ ] **30-day CloudWatch cost analysis:** After 30 days of running, compare actual CloudWatch costs against projected $13.50/month to validate the Decision 2 budget. Document in memory for future cost reviews.
- [ ] **Datadog dashboard sunset:** Phase 6 created a replacement dashboard, but the Datadog MongoDB dashboard can be deleted after confirming all team members are comfortable with CloudWatch. Set a reminder for 30–60 days post-completion.

---

**Next:** Merge Phase 1 PR. Begin Task 9 (Phase 2 canary validation) once engineer approves.
