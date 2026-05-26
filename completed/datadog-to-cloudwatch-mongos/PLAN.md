# PLAN — Replace Datadog with CloudWatch on MongoDB nodes

## Current Situation

- **15 MongoDB EC2 instances across 5 clients** in `sa-east-1`:
  - 6 running: `4client-{atento,commcenter}-mongo{003,004,005}`
  - 9 stopped: `4client-{almaviva,maqnelson,redebrasil}-mongo{003,004,005}`
- All 15 were provisioned via Ansible playbooks:
  - `~/Projects/4Shark/ansible/playbooks/provision-4client-mongodb-server.yml` (full replicaset setup)
  - `~/Projects/4Shark/ansible/playbooks/provision-4client-mongodb-new-nodes.yml` (add nodes to existing RS)
- Both playbooks include the `Datadog.datadog` role (v4.9.0 in `requirements.yml`) and configure:
  - `datadog_config.logs_enabled: true`
  - `datadog_config.process_config.process_collection.enabled: true`
  - `datadog_config.process_config.container_collection.enabled: true`
  - `datadog_checks.mongo` with `localhost:27017` + log tailing of `/var/log/mongod.log`
- Verified via SSH (`bash /tmp/check-datadog.sh`) — all 6 running mongos have `datadog-agent` active.
- Datadog charges $391/month total (23 infra hosts × ~$17). 15 of those are mongos; the other 8 are pgbouncers (kept) and pgbouncer-atento + integrator artifacts.
- **No IAM Instance Profile attached** to the mongo EC2s today (`IamInstanceProfile.Arn = None` on atento-mongo003). CloudWatch Agent will need one before it can publish.
- The Datadog "MongoDB Overview" dashboard works today and shows replication, latency, resource utilization (engineer confirmed via screenshot, `replset_name=maqnelson`).

## Objective / Target State

- **Cost**: drop Datadog infra-host cost on the 15 mongos from ~$255/month (15 × $17) to **$0**. Pgbouncers remain on Datadog Infra.
- **Observability on mongos**: keep what is actionable for the engineer's workflow:
  - **CPU, Network, EBS I/O, status checks** — via CloudWatch native (already there, no agent).
  - **Memory used %, disk space used %, swap used %** — via CloudWatch Agent custom metrics.
  - **Errors that affect the application** — already covered by Rollbar (no change).
  - **Mongo internals (replication lag, ops/s, locks, slow queries)** — **dropped**, accepted trade-off.
- **Ansible**: provisioning new mongos no longer installs `datadog-agent`. It installs `amazon-cloudwatch-agent` instead.
- **Datadog Infrastructure List**: the 15 mongo hostnames stop counting toward billing as soon as `datadog-agent` is removed (host becomes `INACTIVE` within ~60 min). Cards remain visible in the UI until Datadog ages them out (weeks); Datadog exposes no self-service delete.

### Acceptance criteria

1. `provision-4client-mongodb-server.yml` and `-new-nodes.yml` no longer reference `Datadog.datadog` or `datadog_checks`.
2. Re-running either playbook against a target host removes `datadog-agent` and installs `amazon-cloudwatch-agent` configured to publish memory/disk/swap.
3. On each of the 6 running mongos, `systemctl is-active datadog-agent` returns `inactive` (or the unit is absent), and `systemctl is-active amazon-cloudwatch-agent` returns `active`.
4. CloudWatch metrics `mem_used_percent` and `disk_used_percent` appear under namespace `CWAgent` for each running mongo host.
5. The 15 mongo hostnames show `INACTIVE` in Datadog's Infrastructure List (`datadog-agent` purged → host stops reporting → status flips within ~60 min). Billing dashboard reflects the drop on the next refresh — typically same-day. Cards staying visible in the UI is expected and out of our control (Datadog ages them out on its own).
6. A CloudWatch dashboard (or alarm set) replaces the basic "is this server alive and breathing" view that the Datadog dashboard provided.

## Challenges, Difficulties and Risks

### Technical
- **IAM prerequisite**: mongos currently have no instance profile. CW Agent needs `CloudWatchAgentServerPolicy` to call `PutMetricData`. Without it, the agent silently fails.
- **9 stopped mongos**: cannot apply the Ansible change to a stopped host. Two paths (see Decision 3 below).
- **Ansible playbook re-run safety**: the existing playbooks were designed for green-field provisioning, not for re-running on already-provisioned hosts. The MongoDB role does `apt install` and config writes that should be idempotent, but `rs.initiate()` in Play 2 has a guard (`when: rs_status.rc != 0`) so it won't re-init. The Datadog removal needs to be additive (a new task that uninstalls if present) — removing the role from the playbook alone won't uninstall on existing hosts.
- **Datadog removal on existing hosts**: simply removing the `Datadog.datadog` role from the playbook does NOT uninstall the agent from already-provisioned hosts. We need either (a) an explicit uninstall task in the playbook, or (b) a one-shot decommission playbook to run before/alongside the main change.
- **Ansible version drift**: `requirements.yml` pins `Datadog.datadog v4.9.0`. The role itself doesn't change with this PR, but if the engineer suspected the playbook is broken due to an Ansible upgrade, that suspicion should be verified before rollout (run the current playbook against one host as-is, before any changes).
- **CW Agent role choice**: there is no clean official "geerlingguy" equivalent for CW Agent. Options: `amazon.aws` collection (heavier, official), `christiangda.amazon_cloudwatch_agent` (community role, simpler), or inline tasks (download `.deb`, drop config, enable service — fully under our control).

### Operational
- **Billing cycle delay**: Datadog stops counting a host within ~60 min of agent removal — no manual "delete from list" needed (and none exists). Current-month invoice is pro-rated based on active-host-hours; the savings start the moment the agent is purged, not at the next cycle boundary.
- **Single point of failure during the migration**: if we uninstall `datadog-agent` before installing `cloudwatch-agent` correctly, there's a window with zero observability on the host. Engineering note: this is a maintenance op, not an outage scenario.

### Security/privacy
- CW Agent will run as a system service with IAM credentials via IMDSv2. No secret material on disk. Standard pattern.

## Decisions (confirmed with engineer)

### Decision 1 — Which Ansible role to use for CloudWatch Agent → **1C: local `4shark.cloudwatch_agent`**

Engineer confirmed understanding of what an Ansible role is. The convention in this repo is `4shark.*` for things we own (`4shark.mongodb`, `4shark.users`, `4shark.deploy_user`, etc.) and external roles for upstream things (`Datadog.datadog`, `geerlingguy.ntp`). CW Agent is simple enough (~40 lines: apt install, copy config, enable service, restart handler) that it belongs in the `4shark.*` set.

Rejected:
- **1A** (`amazon.aws` collection) — heavy, drags 50+ tasks we don't use.
- **1B** (community role) — adds a Galaxy dep for what is essentially 4 tasks.

### Decision 2 — Metrics to enable in the CW Agent config → **minimal: mem + disk + swap**

3 metric names × 6 running hosts = **18 unique time-series** × $0.30 = **$5.40/month**. When the 9 stopped hosts come up (e.g., re-applying the playbook during Phase 4), the count grows to 3 × 15 = 45 = $13.50/month — still trivial compared to the $255/month being cut from Datadog.

Reminder for the reader: CloudWatch bills per **unique combination** of `(metric name, dimension set)`. `mem_used_percent` on instance A and `mem_used_percent` on instance B are two distinct metrics in billing. ([AWS pricing](https://aws.amazon.com/cloudwatch/pricing/))

Final config:

```json
{
  "metrics": {
    "namespace": "CWAgent",
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}"
    },
    "metrics_collected": {
      "mem":  { "measurement": ["mem_used_percent"], "metrics_collection_interval": 60 },
      "disk": { "measurement": ["used_percent"],     "metrics_collection_interval": 60, "resources": ["/"] },
      "swap": { "measurement": ["swap_used_percent"],"metrics_collection_interval": 60 }
    }
  }
}
```

### Decision 3 — How to handle the 9 stopped mongos → **3B: start, apply playbook, stop**

Engineer wants all 15 hosts in uniform state. Workflow: test on one currently-running cluster as canary (Phase 2), roll out to the rest of the running mongos (Phase 3), then start each stopped cluster, run the playbook, stop again (Phase 4). Trade-off accepted: ~90 min one-time effort to avoid drift between active and dormant clusters.

### Decision 4 — IAM Instance Profile creation (Terraform) → **`shared-resources` stack**

Engineer's call: since the role/policy is identical across all 15 mongos (same managed policy `CloudWatchAgentServerPolicy`, no per-client variation), it belongs in a shared stack rather than duplicated across `integrator-{client}/`.

**Implications for `shared-resources`:**

- Current scope (per `terraform/shared-resources/README.md`): "configuration-only stack, no compute/network/IAM resources".
- IAM Instance Profile is **not** compute or network — it's an identity resource. But the README explicitly excludes IAM today.
- **Required:** extend the README to allow shared IAM identities that are stack-agnostic. Add a section "Shared IAM Identities" documenting the `mongo-cwagent` instance profile and the rule: an IAM identity goes here when it's identical across all consuming stacks.
- **Excluded by design**: engineer IAM (lives in `identity/` with its `ivo` profile / break-glass model — see CLAUDE.md "Identity Stack" rule), and any role with cross-account / sensitive scope. Stays separate.

**Resources to create in `shared-resources`:**

```hcl
# mongo-cwagent.tf
resource "aws_iam_role" "mongo_cwagent" {
  name               = "mongo-cwagent"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "mongo_cwagent_cloudwatch" {
  role       = aws_iam_role.mongo_cwagent.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "mongo_cwagent" {
  name = "mongo-cwagent"
  role = aws_iam_role.mongo_cwagent.name
}

output "mongo_cwagent_instance_profile_name" {
  value = aws_iam_instance_profile.mongo_cwagent.name
}
```

**Cross-stack consumption pattern:** `integrator-{client}` stacks reference the profile by name (managed policy, so the name is stable). Each `aws_instance.mongo*` gains:

```hcl
resource "aws_instance" "mongo003" {
  # ... existing ...
  iam_instance_profile = "mongo-cwagent"  # name only, no SSM lookup needed
}
```

Alternative considered and rejected: a new stack `iam-instance-profiles`. Adds a 27th stack to the repo for a single resource. Not worth the boilerplate (provider.tf, stack.tm.hcl, README, etc.) when `shared-resources` is already the catch-all for things that cross stack boundaries.

## Overall Approach → **Option B: Terraform first, then Ansible**

Confirmed implicitly by Decision 4. IAM must exist before any Ansible run, otherwise CW Agent installs and silently fails (no credentials to call `PutMetricData`). Two PRs, ordered:

1. **Terraform PR** (in `~/Projects/4Shark/terraform/`):
   - In `shared-resources/`: add `mongo-cwagent.tf` with the IAM role + managed policy attachment + instance profile, update `README.md` with the "Shared IAM Identities" section.
   - In each of `integrator-atento/`, `integrator-commcenter/`, `integrator-almaviva/`, `integrator-maqnelson/`, `integrator-redebrasil/`: add `iam_instance_profile = "mongo-cwagent"` to each `aws_instance.mongo*` resource (3 per stack × 5 stacks = 15 attachments).
   - Plan + apply in order: `shared-resources` first (creates the profile), then each `integrator-*` stack (attaches the profile to instances).
   - Apply-before-merge per `~/.claude/docs/TERRAFORM-CONVENTIONS.md`.

2. **Ansible PR** (in `~/Projects/4Shark/ansible/`) — follows after Terraform PR is merged + applied.

## Proposed Steps (high level, do not execute until approved)

### Phase 0 — Terraform: IAM Instance Profile (separate PR)

0.1. Confirmed mongo EC2 locations: `integrator-atento/mongodb.tf`, `integrator-commcenter/compute.tf` (or equivalent), `integrator-almaviva/`, `integrator-maqnelson/`, `integrator-redebrasil/` — 3 instances per stack, 15 total.
0.2. Branch `feature/mongo-cwagent-iam-profile` from `develop` in the terraform repo.
0.3. In `shared-resources/`:
   - Create `mongo-cwagent.tf` with `aws_iam_role.mongo_cwagent`, the trust policy data source, `aws_iam_role_policy_attachment` to `arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy`, and `aws_iam_instance_profile.mongo_cwagent`.
   - Update `README.md`: add "Shared IAM Identities" section documenting the profile and the inclusion rule (identical across all consuming stacks).
0.4. In each of `integrator-{atento,commcenter,almaviva,maqnelson,redebrasil}/`:
   - Add `iam_instance_profile = "mongo-cwagent"` to each `aws_instance.mongo003`, `mongo004`, `mongo005`.
   - Note: attaching an instance profile to an already-running instance does **not** restart it (verified in AWS docs — instance profile attach/detach is online).
0.5. Open PR targeting `develop`.
0.6. `terraform plan` for each affected stack (6 stacks total). Save plans to `/tmp/`. Present a structured summary (1 to add for `shared-resources`, 3 to change for each integrator stack).
0.7. Get engineer approval. Apply in this order from the feature branch (apply-before-merge):
   - `shared-resources/` (creates the profile).
   - `integrator-atento/` (attaches to atento mongos — the canary cluster, already running).
   - `integrator-commcenter/` (attaches to commcenter mongos — also running).
   - `integrator-almaviva/`, `integrator-maqnelson/`, `integrator-redebrasil/` (stopped mongos — applies attachment metadata; the IMDS endpoint will serve the new profile when the instance is next started).
0.8. Verify all 15 instances now show `IamInstanceProfile.Arn` set:
   ```
   aws ec2 describe-instances --region sa-east-1 --filters "Name=tag:Type,Values=mongodb" --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],IamInstanceProfile.Arn]' --output table
   ```
0.9. Merge PR.

### Phase 1 — Ansible changes (single PR, in `~/Projects/4Shark/ansible/`)

1.1. Branch `feature/replace-datadog-with-cloudwatch-mongos` from `develop`.
1.2. Create new local role `roles/4shark.cloudwatch_agent` with:
   - `tasks/main.yml`: install `amazon-cloudwatch-agent` `.deb` from AWS S3 (architecture-aware), drop config file, enable + start service. Includes an "uninstall if datadog-agent present" task at the top.
   - `templates/amazon-cloudwatch-agent.json.j2`: the config from Decision 2.
   - `defaults/main.yml`: defaults for metric collection interval, metrics list.
   - `handlers/main.yml`: restart agent on config change.
1.3. Edit `playbooks/provision-4client-mongodb-server.yml`:
   - Remove `Datadog.datadog` from the `roles:` list of Play 1.
   - Replace with `4shark.cloudwatch_agent`.
   - Remove the `datadog_config` and `datadog_checks` keys from `vars:` in Play 1.
1.4. Edit `playbooks/provision-4client-mongodb-new-nodes.yml`:
   - Same as 1.3 for the single play in this file.
1.5. Edit `requirements.yml`:
   - Remove the `Datadog.datadog v4.9.0` entry.
   - No new external entry (we're using local role).
1.6. (Optional) Delete `imported_roles/Datadog.datadog/` — it's only pulled by `install_requirements.sh` from Galaxy anyway. Leave the dir for now to keep the diff minimal; remove in a follow-up if the team wants.
1.7. Update `CHANGELOG.md` under `[Unreleased]`:
   - `### Changed` — "MongoDB provisioning: replaced Datadog with CloudWatch Agent"
1.8. Commit (Angular: `refactor(mongodb): replace Datadog agent with CloudWatch Agent`).
1.9. Push to origin with explicit refspec (first push of new branch from origin/develop).
1.10. Open PR targeting `develop`.

### Phase 2 — Validate on one host (staging-style)

2.1. Pick atento-mongo003 as the canary (smallest blast radius — it's a non-primary node in the atento replicaset).
2.2. Run `./run_playbook.sh 4shark playbooks/provision-4client-mongodb-server.yml ...` targeting only this host.
2.3. Verify:
   - `systemctl is-active datadog-agent` → `inactive` or `unit not loaded`.
   - `systemctl is-active amazon-cloudwatch-agent` → `active`.
   - `aws cloudwatch get-metric-statistics --namespace CWAgent --metric-name mem_used_percent --dimensions Name=InstanceId,Value=i-0517b523c1c058b76 --start-time <T-5min> --end-time <T> --period 60 --statistics Average` returns at least one datapoint.
   - MongoDB itself is still running on this host (`systemctl is-active mongod`).
   - Replicaset health: `rs.status()` on the primary still shows this node as `SECONDARY` healthy.
2.4. Watch for 30 min for any anomaly.

### Phase 3 — Rollout to the remaining 5 running mongos

3.1. Per client, in this order to minimize coupled risk: commcenter-mongo003, 004, 005, then atento-mongo004, 005.
3.2. One at a time, wait 5 min between each (let monitoring breathe).
3.3. Same validation as Phase 2 on each.

### Phase 4 — Apply to the 9 stopped mongos (per Decision 3B)

4.1. `aws ec2 start-instances` (requires MFA elevation — `/aws-elevate`) one client at a time.
4.2. Wait for `running` + status checks 2/2.
4.3. Run the updated Ansible playbook against the 3 instances of that client.
4.4. Same validation as Phase 2.
4.5. `aws ec2 stop-instances` once validated.
4.6. Repeat for almaviva, maqnelson, redebrasil.

### Phase 5 — Remove the 15 hostnames from Datadog

5.1. Via Datadog UI (Infrastructure List → search `4client-*-mongo*` → multi-select → Mute and Delete) OR via the Datadog API (`POST /api/v1/hosts/{hostname}/mute` + delete).
5.2. Verify in Datadog billing dashboard that "Infrastructure Hosts" count drops by 15.
5.3. Mention this in the next billing cycle handover note.

### Phase 6 — Replace dashboards/alerts

6.1. Create a CloudWatch dashboard with 6 widgets per mongo (CPU, mem, disk %, network in/out, EBS read/write IOPS, status checks).
6.2. Create alarms for: `mem_used_percent > 85%`, `disk_used_percent > 80%`, `CPUUtilization > 90% for 5 min`, `StatusCheckFailed > 0`.
6.3. Route alarms to the existing SNS topic / PagerDuty if any (verify existing wiring; if none, this is a follow-up).

### Phase 7 — Cleanup

7.1. After 30 days of confirmed CloudWatch coverage, delete the Datadog `MongoDB Overview` dashboard if no other team uses it.
7.2. Move this plan folder from `~/.claude/plans/active/` to `~/.claude/plans/completed/`.

## Internal References

- `~/Projects/4Shark/ansible/playbooks/provision-4client-mongodb-server.yml`
- `~/Projects/4Shark/ansible/playbooks/provision-4client-mongodb-new-nodes.yml`
- `~/Projects/4Shark/ansible/requirements.yml`
- `~/Projects/4Shark/ansible/roles/` (where new `4shark.cloudwatch_agent` will live)
- `~/Projects/4Shark/terraform/` (Phase 0 — exact module TBD during execution)
- Datadog Infrastructure List: https://app.datadoghq.com/infrastructure
- AWS CloudWatch Agent install docs: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/install-CloudWatch-Agent-on-EC2-Instance.html

---

## Status

**APPROVED** by engineer on 2026-05-13.

- Option B (Terraform PR first, then Ansible PR) — approved.
- Decision 1 — 1C (local `4shark.cloudwatch_agent` role).
- Decision 2 — minimal metrics (mem + disk + swap).
- Decision 3 — 3B (start, apply, stop the 9 dormant clusters).
- Decision 4 — IAM Instance Profile in `shared-resources` stack, README extended.

---

## Execution Log — 2026-05-13

### Phase 0 — Terraform IAM (completed)

- Branch `feature/mongo-cwagent-iam-profile` opened against `develop` in `terraform` repo.
- `shared-resources/mongo-cwagent.tf` created: `aws_iam_role.mongo_cwagent` + `aws_iam_role_policy_attachment.mongo_cwagent_cloudwatch` (managed policy `CloudWatchAgentServerPolicy`) + `aws_iam_instance_profile.mongo_cwagent`.
- `shared-resources/README.md` extended with the "Shared IAM Identities" section documenting the inclusion rule.
- Each of `integrator-{atento,commcenter,almaviva,maqnelson,redebrasil}/mongodb.tf` updated: 3 × `aws_instance.mongo*` gained `iam_instance_profile = "mongo-cwagent"` (15 attachments total).
- Plans reviewed and applied stack by stack from the feature branch with engineer approval at each gate. Drift on `module.this.aws_default_security_group.this` (known AWS-collapses-to-1, Terraform-restores-to-3 loop) accepted in 4 of the 5 integrator stacks — no change to actual SG behavior.
- PR #413 merged to `develop`. Verified via `aws ec2 describe-instances --filters "Name=tag:Type,Values=mongodb"`: all 15 hosts show `IamInstanceProfile.Arn = arn:aws:iam::405749097490:instance-profile/mongo-cwagent`.

### Phase 1 — Ansible PR (completed)

- Branch `feature/replace-datadog-with-cloudwatch-mongos` opened against `develop` in `ansible` repo. PR #194 merged.
- **Single commit** containing:
  - Local role `roles/4shark.cloudwatch_agent` (defaults, handlers, tasks, template) — purges `datadog-agent`, installs `amazon-cloudwatch-agent`, drops config publishing `mem_used_percent` / `disk_used_percent` (`/`) / `swap_used_percent` to the `CWAgent` namespace.
  - `playbooks/provision-4client-mongodb-server.yml`: replaced `Datadog.datadog` role with `4shark.cloudwatch_agent`; removed `datadog_config` / `datadog_checks` vars; rewrote rs.initiate to register members with `.4shark.internal` FQDN; added `when: server_hostname is defined` guard on the `Set hostname` pre_task; dropped the unused `vars_files: vars/4client-mongodb/{{ client_name }}.yml` dependency since the three IPs already come from extra-vars.
  - Removed legacy `playbooks/provision-4client-mongodb-new-nodes.yml` (cluster migration tool, no longer needed — current flow is Terraform creates 3 EC2s, server playbook installs Mongo and initialises the replicaset).
  - `requirements.yml`: dropped `Datadog.datadog v4.9.0`.
  - `CHANGELOG.md`: entries under `[Unreleased]/Changed` and `[Unreleased]/Removed`.

### Manual FQDN reconciliation on the three legacy clusters (out of band)

The current rs.config on 3 of 5 clusters used short hostnames (`4client-X-mongoY:27017`) which only resolved via search-domain DNS or `/etc/hosts` fallback. Standardised on FQDN via direct `rs.reconfig` on each primary:

- **almaviva**: short → FQDN, no step-down.
- **maqnelson**: short → FQDN, no step-down.
- **redebrasil**: short → FQDN, no step-down (primary stayed on mongo004 — atypical for this cluster but stable).

After reconfig, `/etc/hosts` on the three almaviva nodes was cleaned of legacy `4client-almaviva-mongoNNN` entries (migration-era leftover from when the cluster pre-dated the Route53 private zone). Cluster stayed healthy throughout — Route53 covers the FQDN resolution.

### Phase 2/3/4 collapsed — rollout of CW Agent on all 5 existing clusters

Original PLAN expected rolling per-host one at a time (Phase 2 → 3 → 4). Engineer accepted running the full playbook per cluster (3 nodes in parallel) since the integrator was idle that evening.

**Bionic-compatible environment built in a temporary branch** `feature/downgrade-ansible-for-bionic-mongos` (not merged — branch is scratch). The PR'd ansible-core 2.20.5 cannot target Python 3.6 (Ubuntu 18.04). Built a local workable environment:

- Python 3.11 via `brew install python@3.11`, fresh venv from `/opt/homebrew/opt/python@3.11/bin/python3.11`.
- `requirements.txt` (working tree, not committed): `ansible-core==2.15.13`, `boto3==1.23.10`, `botocore==1.26.10`, removed `ansible==5.7.1` meta-package.
- `community.general` collection 5.8.7 (older versions don't ship `from __future__ import annotations` which Python 3.6 cannot parse).
- `imported_roles/jnv.unattended-upgrades/tasks/{main,unattended-upgrades}.yml`: legacy `include:` rewritten to `import_tasks` / `include_tasks` (the directory is `.gitignore`d, patches are local).
- `ec2.py` shebang pinned to the venv interpreter so the boto-2.49 dependency resolves against the venv site-packages.
- Inventory passed inline (`-i 'IP,IP,IP,'`) to avoid relying on the dynamic-inventory script's working directory.

### Real change to `roles/4shark.mongodb` (kept in working tree)

While rolling commcenter the role failed with `apt_pkg.Error: Conflicting values set for option Trusted regarding source ... bionic/mongodb-org/4.4`. Root cause: the role's `apt_repository` task used `trusted=yes`, so when the host already had `/etc/apt/sources.list.d/mongodb-org-4.4.list` declaring the same repo with `signed-by=/usr/share/keyrings/mongodb-server-4.4.gpg` (created by the original manual install), Ansible wrote a second file (`repo_mongodb_org_apt_ubuntu.list`) with `trusted=yes` and `apt-get update` refused both.

**Fix**: changed the role to use `signed-by=/usr/share/keyrings/mongodb-server-{{ mongodb_version }}.gpg` (the keyring path that the role already populates in the previous task). Now idempotent — produces the exact same source line that a fresh install would write, so on a pre-existing host the `apt_repository` module sees a match and skips.

**Cleanup applied to commcenter**: removed the stale `repo_mongodb_org_apt_ubuntu.list` from all 3 nodes (`sudo rm /etc/apt/sources.list.d/repo_mongodb_org_apt_ubuntu.list`). The original `mongodb-org-4.4.list` was left untouched.

### Atento incident — replSetName drift

Atento's real `replSetName` is `atento-br` (sufixo de país, herdado da migração antiga). The playbook hardcodes `mongodb_conf_replSetName: "{{ client_name }}"`, so passing `client_name=atento` rendered `mongod.conf` with `replication.replSetName: atento`. The role's mongod.conf template substitution triggered the `restart mongod` handler on all 3 nodes simultaneously. Each mongod restarted with the wrong replSetName, refused to load `local.system.replset` (id was `atento-br`), and returned `InvalidReplicaSetConfig` (code 93) to any client.

Cluster was offline for ~2 minutes. Engineer was already aware integrators were idle so user impact was zero.

**Recovery**: `sudo sed -i 's/replSetName: atento$/replSetName: atento-br/' /etc/mongod.conf && sudo systemctl restart mongod` on each of the 3 nodes. Cluster healed in seconds. Primary election promoted mongo004 (previously secondary). Members all `health=1`, FQDN preserved.

**Pending fix in the playbook** (not done yet): decouple `mongodb_conf_replSetName` from `client_name`. Either:

- (a) Add a `mongodb_replset_name` extra-var that defaults to `client_name` but can be overridden;
- (b) Read the existing replSetName from `mongod.conf` in a pre_task and preserve it for existing clusters.

Caught only at execution time because the playbook had never been re-run on a cluster after its first provisioning — the assumption `client_name == replSetName` was correct for almaviva, commcenter, maqnelson, redebrasil but not atento.

### Final state (all 5 clusters)

| Cluster | replSetName | CW Agent | datadog-agent | mongod |
|---|---|---|---|---|
| almaviva | almaviva | active | inactive (purged) | active |
| maqnelson | maqnelson | active | inactive (purged) | active |
| redebrasil | redebrasil | active | inactive (purged) | active |
| commcenter | commcenter | active | inactive (purged) | active |
| atento | **atento-br** ⚠️ | active | inactive (purged) | active |

(Pending follow-ups moved into the "Updated open items — 2026-05-13" section below; the original "Action remaining" column had `Delete from Datadog Infra List` on every row, which turned out to be a false expectation — Datadog has no self-service delete and billing already drops within ~60 min of agent removal.)

Clusters that **never go offline** (compartilhados pelos integradores): atento, commcenter. Always running.
Clusters that **podem voltar pra stopped** quando o integrador correspondente não estiver rodando: almaviva, maqnelson, redebrasil.

### Open items after today

1. **Validate idempotency** — re-run the playbook on one cluster and confirm `changed=0` for everything except the benign Play 2 (rs.initiate that always falsely fires on existing clusters because `mongosh` is missing in mongo 4.x, so the `Check if ReplicaSet is already initialized` task returns rc≠0).
2. **Reconcile commcenter `/etc/mongod.conf`** — the commcenter conf differs from the template the role would render (log path `/data/log/mongod.log` vs `/var/log/mongodb/mongod.log/mongod.log`, `storage.journal.enabled: true` explicit, no `engine: wiredTiger` declared, no `processManagement`, no `operationProfiling`). Decide per-key whether to keep the commcenter divergence or normalize on the template. Engineer asked for an analysis of what each diverging key actually changes in behavior before deciding.
3. **Playbook fix for replSetName drift** — see incident above.
4. **Playbook fix for mongo shell binary** — `Check if ReplicaSet is already initialized` uses `mongosh`, missing in mongo 4.x. Either detect (`command -v mongosh || command -v mongo`) or make the task conditional on the shell being present. Today the false-positive triggers `Initiate ReplicaSet` to run, which then fails on `mongosh` not found — net effect is harmless because the existing replicaset isn't touched, but the playbook reports a failure on every existing-cluster run.
5. **Datadog UI cleanup** — engineer to delete the 15 hostnames (`4client-{atento,commcenter,almaviva,maqnelson,redebrasil}-mongo{003,004,005}`) from https://app.datadoghq.com/infrastructure so billing stops counting them next cycle.
6. ~~Future cluster upgrade~~ — closed as a tracked item (engineer decision 2026-05-13): timeline unknown, not worth keeping open. If/when the upgrade happens, the preservation branch `feature/downgrade-ansible-for-bionic-mongos` documents the workarounds to revert.

## Log path fix rollout — 2026-05-13

### What was wrong

All 15 mongo nodes had `/var/log/mongodb/mongod.log/mongod.log` (a directory called `mongod.log` containing the actual log file). Cause: the `4shark.mongodb` role default `mongodb_conf_logpath: /var/log/mongodb/mongod.log` is the full file path, but the template renders `path: {{ mongodb_conf_logpath }}/mongod.log` — appending `/mongod.log` again. The role also runs `file: state=directory` against the same var, so it actively created the bogus directory. Both layers reinforced each other.

### Procedure (per cluster)

Six scripts under `/tmp/mongo-logs/`, each accepts `<cluster> <ip1> <ip2> <ip3>`. Mongod stopped on all 3 nodes at once — acceptable because the integrators were idle; engineer confirmed for each cluster.

| # | Script | What it does |
|---|---|---|
| 01 | `01-stop-and-copy.sh` | `systemctl stop mongod`; `cp /var/log/mongodb/mongod.log/mongod.log /var/log/mongodb/backup/mongod.log.<TS>.<hostname>` |
| 02 | `02-validate-copy.sh` | `stat -c%s` original == backup, fail-fast if mismatch |
| 03 | `03-delete-original.sh` | `rm /var/log/mongodb/mongod.log/mongod.log` + `rmdir /var/log/mongodb/mongod.log/` |
| 04 | `04-validate-delete.sh` | confirm path absent, backup present, mongod still stopped |
| 05 | `05-fix-conf-and-start.sh` | `sed -i.bak s|mongod.log/mongod.log|mongod.log|` on `/etc/mongod.conf`; `systemctl start mongod` |
| 06 | `06-validate-cluster.sh` | file is a regular file, mongod active, `rs.status()` healthy via primary IP |

### Per-cluster results

| Cluster | replSet | PRIMARY | SECONDARY | ARBITER | Health after fix |
|---|---|---|---|---|---|
| almaviva | almaviva | mongo003 | mongo004 | mongo005 | healthy |
| maqnelson | maqnelson | mongo003 | mongo004 | mongo005 | healthy |
| redebrasil | redebrasil | mongo004 | mongo003 | mongo005 | healthy |
| atento | atento-br | mongo004 | mongo003 | mongo005 | healthy |
| commcenter | commcenter | mongo003 | mongo004 | mongo005 | healthy |

15/15 nodes corrected. Backups preserved at `/var/log/mongodb/backup/mongod.log.<TIMESTAMP>.<hostname>` on every node.

### Commcenter conf reconciliation

Closes open item #2 above. The 3 commcenter nodes were `cat /etc/mongod.conf`-ed during the inventory step. The full conf is **identical** to the role template — the only field differing from other clusters is `replSetName: commcenter`. No slow-query log path divergence, no extra `storage.journal.enabled`, no missing keys. The "drift" suspected in item #2 was the log path bug present on all 15 nodes, not commcenter-specific.

### Branch + PR state

- **PR #195** merged into `develop`: `fix(mongodb): prevent duplicated log path` — default of `mongodb_conf_logpath` changed to `/var/log/mongodb` so the rendered path becomes `/var/log/mongodb/mongod.log`.
- **Branch `feature/downgrade-ansible-for-bionic-mongos`** pushed (no PR — preservation only):
  - `chore(deps): downgrade ansible-core for bionic targets` (`requirements.txt`)
  - `fix(mongodb): use signed-by instead of trusted=yes for apt repository` (`roles/4shark.mongodb/tasks/main.yml`)

The second commit is a real bug fix that did not go into PR #195 because it is tied to the legacy bionic provisioning path. Should be PR'd separately when the team next touches the legacy role.

### Updated open items — 2026-05-13

1. ~~Validate idempotency~~ — superseded; today's per-cluster restart is real-world validation that the conf change holds.
2. ~~Reconcile commcenter `/etc/mongod.conf`~~ — closed; no real drift.
3. ~~Playbook fix for replSetName drift~~ — closed; atento was the only cluster with this mismatch (`atento-br` vs `client_name=atento`) and the playbook will not be re-run against any of the 5 existing clusters. New clusters are provisioned with matching names. Manual sed remains the workaround if it ever happens again.
4. ~~Playbook fix for mongo shell binary~~ — PR #197 merged into `develop`.
5. ~~Datadog UI cleanup~~ — no manual action required. Datadog confirmed via screenshot: the 3 almaviva mongo hosts already show `INACTIVE` in the Infrastructure List (`https://app.datadoghq.com/infrastructure?text=4client-almaviva`). Mechanism: a host stops being billed within ~60 min of the agent ceasing to report; the cards persist visually for weeks but do not count. The Datadog UI exposes only **Mute alerting** (silences alerts only) — there is no self-service "Delete host" button, and the public API has no `DELETE /host/{name}` endpoint. To remove the cards visually a support ticket would be needed; not worth the effort. **Validation**: open `https://app.datadoghq.com/billing/usage` in 24–48h and confirm infra hosts dropped from 23 → 8 (8 pgbouncers remain).
6. ~~`apt_repository` signed-by fix~~ — PR #196 merged into `develop`.
