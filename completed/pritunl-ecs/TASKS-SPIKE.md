# TASKS-SPIKE — Pritunl VPN: VM to Containerized ECS Migration

> Reference: `PLAN.md` (engineer-approved, second-pass revision); `PLAN-SPIKE.md` (citations + technical rationale)
> Auxiliary: None yet — auxiliary files generated during execution (dependency diagrams, spike results, pattern code samples)

## Decomposition options (where multiple valid breakdowns exist)

### Option A: Grouped by repository + repository phase (5-6 PRs across `pritunl` repo and `terraform` repo)

**Breakdown:**
- `pritunl` repo Phase 1 as a single PR (Dockerfile + entrypoint + CI + Renovate config + CHANGELOG)
- `terraform` repo Phase 2 split into:
  - T2.1: ECR repositories + governance (`local.hubflow_repositories` + `local.hubflow_repositories_with_min_age_check`)
  - T2.2: MongoDB VM (bare instance + trimmed Ansible role + dedicated security group)
  - T2.3: Production Pritunl ECS (task definition, host prep, security group, IAM)
  - T2.4: Staging Pritunl ECS (task definition, host prep, at `desired_count=0`)
- Phase 3 cutover as a runbook/manual script (separate from PRs — executes against live infrastructure)
- Phase 4 VM retirement as split PRs or a final cleanup PR

**Trade-offs:**
- **Pros**: Clear repository boundary; phase 1 is self-contained; Terraform changes are loosely grouped; easy to roll back per component
- **Cons**: More PRs to review (5-6 total); higher coordination overhead across multiple PRs; Phase 2 sequencing must be enforced externally (the ECR repos and governance must land before ECS services can use them)

---

### Option B: Grouped by infrastructure layer + resource dependency order (4 PRs across both repos, strictly sequenced)

**Breakdown:**
- `pritunl` repo Phase 1 as a single PR (same as Option A)
- `terraform` repo Phase 2 split strictly by dependency:
  - T2.1: ECR repositories + governance (foundation; all ECS services depend on this)
  - T2.2: MongoDB VM + dedicated security group (needed before Pritunl ECS can start tasks)
  - T2.3-T2.4 (combined): Both Pritunl ECS instances (production + staging) in ONE PR, with the production instance carrying the forward-looking IAM + security group, and staging at `desired_count=0`
- Phase 3 and Phase 4 same as Option A

**Trade-offs:**
- **Pros**: Strict dependency ordering makes the sequence explicit; combining T2.3 + T2.4 as "Pritunl ECS" mirrors the logical "VPN gateway infrastructure" grouping; fewer total PRs (4 Terraform PRs vs 5); ECR/governance bottleneck is clear and explicit
- **Cons**: T2.3 + T2.4 in one PR means production and staging can't be separated (e.g., if one needs to be held back); staging instance at zero capacity still costs an EC2 host provisioning (even if stopped), so the "staging must succeed to merge" gate is less clean if a staging-specific issue arises

---

**Engineer chooses at review:** No recommendation here — both are valid. The deciding factors are:
- **If easier to review/iterate:** Option A (more modular, each PR addresses one system)
- **If coordination/clarity is priority:** Option B (dependency order forces a sequence that's hard to violate)

---

## Tasks (assuming Option B — pending engineer choice)

### Pre-implementation spike tasks (complete BEFORE blocking tasks)

These are not implementation tasks but research/validation tasks that unblock the main work. They surface decisions or verify assumptions the PLAN flagged as residual.

---

#### SPIKE-1: Renovate versioning regex validation for Pritunl's four-field tag scheme

**Phase**: Phase 1 (Dockerfile scaffolding)  
**Blocks**: T1.4 (Renovate config write) and T1.6 (Renovate validation)

**Description**: The PLAN identifies (decision 1) that Pritunl's version tags follow a four-field scheme (`v1.34.4681.89`) instead of semantic versioning. Renovate's default `versioning` strategy cannot order/cross this non-clean-semver suffix. The plan cites `pgbouncer/renovate.json:11-16` as precedent for a per-package `versioning: regex:` override, but the exact regex for Pritunl's four-field shape has not been tested against a live Renovate instance.

**Acceptance criteria**:
- [ ] Verify Pritunl's apt-repo version scheme matches GitHub release tags (e.g., confirm `apt-cache policy pritunl` on a machine with the repo shows a version that corresponds to a GitHub release tag)
- [ ] Draft and test the `versioning` regex against a local Renovate dry-run or a temporary branch — confirm it orders the four-field versions correctly (e.g., `v1.34.4681.89` > `v1.34.4649.96` > `v1.32.4567.52`)
- [ ] Document the final regex in the Renovate config with a comment explaining the four-field override

**Pattern reference**: `pgbouncer/renovate.json:11-16` — the existing non-semver `versioning: regex:` precedent in 4Shark

```json
"versioning": "regex:^v?(?<major>\\d+)\\.(?<minor>\\d+)\\.(?<patch>\\d+)\\.(?<build>\\d+)$",
```
(exact regex TBD by spike)

**Dependencies**: None — can start immediately.

**Open question**: Does the four-field scheme always maintain strict ordering (e.g., is `1.34.4681.89` always newer than `1.34.4649.96`), or can the build field reset? Clarify from Pritunl's own changelog/versioning docs before finalizing the regex.

---

#### SPIKE-2: MongoDB VM Ansible role placement decision

**Phase**: Phase 2 (Terraform + Ansible infra)  
**Blocks**: T2.2 (MongoDB VM provisioning)

**Description**: The PLAN (decision 3) recommends retargeting the existing `ansible/roles/4shark.pritunl/` role's MongoDB-only tasks to the new dedicated Mongo VM. Two options were surfaced but not decided:
1. Extract MongoDB tasks into a new, independent role (e.g., `ansible/roles/4shark.mongodb-pritunl/`)
2. Keep tasks in the existing `4shark.pritunl` role, use an inventory-group conditional to run only Mongo tasks against the Mongo VM

The decision affects how the Mongo VM is provisioned in T2.2 and how the Pritunl host (Phase 1 Dockerfile) references Mongo's private address.

**Acceptance criteria**:
- [ ] Engineer or main decides: new independent role vs conditional-in-existing-role
- [ ] Ansible inventory structure for the Mongo VM is defined (which inventory file, which group, what hostname/IP pattern)
- [ ] Playbook structure is documented (e.g., `provision-pritunl.yml` extended to run against both the Pritunl host and the Mongo VM, or a separate `provision-pritunl-mongo.yml` playbook)

**Pattern reference**: `ansible/roles/4shark.pritunl/tasks/main.yml:32-79` — the MongoDB-only portion that will be extracted/retargeted

```yaml
# From ansible/roles/4shark.pritunl/tasks/main.yml:32-79
# MongoDB apt-repo key, repo, install
# MongoDB config (mongod.conf template)
# Enable/start mongod via systemd
# Logrotate for mongod
# Handlers: restart mongod
```

**Dependencies**: Depends on engineer/main choice; no hard blockers.

**Open question**: Should the Mongo VM's provisioning happen in the `terraform` repo (as a Terraform-managed `user_data` bootstrap), or is an Ansible playbook run post-boot the preferred pattern? The PLAN assumes Ansible (decision 3), but the exact execution mechanism (Terraform `provisioner`, Systems Manager Session Manager, SSH post-boot) is unspecified.

---

#### SPIKE-3: Dedicated MongoDB security group mechanism

**Phase**: Phase 2 (Terraform + Ansible infra)  
**Blocks**: T2.2 (MongoDB VM security group write)

**Description**: The PLAN (decision 3) states the MongoDB VM's security group should restrict ingress to "ONLY the Pritunl instance". The PLAN notes this is narrower than 4Shark's current convention (CIDR-scoped by VPC range). Two candidate mechanisms were surfaced:
1. **Security-group-to-security-group scoping** via `referenced_security_group_id` on the `aws_vpc_security_group_ingress_rule` (no existing 4Shark precedent; cited as UNVERIFIED in the PLAN's sources)
2. **Narrowed CIDR** to the Pritunl instance's private IP (e.g., `10.x.x.x/32`), matching the existing CIDR convention but fragile across Pritunl instance replacement

The decision affects the Terraform code in T2.2 and potentially the risk profile of the Pritunl↔Mongo-VM network dependency (PLAN risk #4).

**Acceptance criteria**:
- [ ] Engineer or main decides: SG-to-SG vs narrowed CIDR
- [ ] If SG-to-SG: verify the `referenced_security_group_id` Terraform argument exists in the current AWS provider version and write a proof-of-concept (PoC) ingress rule
- [ ] If narrowed CIDR: document the Pritunl instance's fixed private IP address allocation strategy (is it a static private IP in the launch template, or a secondary ENI?)
- [ ] Security group draft written and validated with `terraform plan`

**Pattern reference**: `terraform/auth-001/security_groups.tf:11-23,41-47` — the existing CIDR-scoped convention (no SG-to-SG precedent in 4Shark)

```hcl
# From terraform/auth-001/security_groups.tf:11-23
resource "aws_vpc_security_group_ingress_rule" "rds_postgres" {
  security_group_id            = aws_security_group.auth_001.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  cidr_ipv4                    = "10.255.0.0/16"  # ← existing pattern: VPC-wide CIDR
}
```

**Dependencies**: None — can be decided in parallel with T2.1.

**Open question**: Does the Pritunl ECS instance get a static private IP (fixed across restarts), or is a dynamic private IP acceptable if the security group is refreshed at boot? If dynamic, the narrowed-CIDR approach becomes fragile.

---

#### SPIKE-4: Staging MongoDB strategy

**Phase**: Phase 2 (Terraform + Ansible infra)  
**Blocks**: T2.4 (Staging ECS instance provisioning)

**Description**: The PLAN (decision 3 × decision 7) explicitly flags that the `-staging` Pritunl instance's database strategy is **not decided**. Three options were surfaced:
1. **Separate staging Mongo VM** (dedicated instance, full isolation, doubles Mongo footprint)
2. **Separate database on the same production Mongo VM** (shared EC2 instance, isolated at the MongoDB level, no second VM cost)
3. **Ephemeral/seeded Mongo** (brought up only for the test window via ECS task or ECS sidecar, matches the "normally at zero capacity" framing of the staging instance)

The choice affects the Terraform code (does staging need its own `aws_instance`?) and the staging validation flow (do we restore a backup, use a seed, or run against live data?).

**Acceptance criteria**:
- [ ] Engineer or main decides: separate staging VM vs shared prod Mongo vs ephemeral
- [ ] MongoDB provisioning/seeding strategy documented:
  - If separate staging VM: does it use the same Ansible role as T2.2, or a different seed?
  - If shared prod Mongo: confirm the prod Mongo VM can handle two databases concurrently; name the staging database (e.g., `pritunl_staging`)
  - If ephemeral: document the ECS task or sidecar definition and the seed-data source (backup from production, seed script, etc.)
- [ ] Terraform code drafted for the chosen mechanism

**Pattern reference**: `terraform/auth-001/auth_001_staging.tf:1-194` — the existing Fargate staging-instance pattern (separate database, shared RDS instance). The Mongo choice is analogous but not identical (auth-001 uses a managed RDS, not a self-managed MongoDB).

```hcl
# From terraform/auth-001/auth_001_staging.tf:148-194
resource "aws_ecs_service" "auth_001_staging" {
  # ...
  desired_count = 0  # ← staging normally at zero
  # ...
}
# Staging uses separate RDS database ("auth_001_staging" database name)
```

**Dependencies**: Depends on engineer/main choice; can be decided in parallel with T2.3.

**Open question**: If ephemeral Mongo, does the seed come from a `mongodump` of production (taken at a scheduled time)? Is this a runtime bootstrap or a pre-baked container?

---

#### SPIKE-5: Staging Pritunl instance public entry point mechanism

**Phase**: Phase 2 (Terraform + Ansible infra)  
**Blocks**: T2.4 (Staging ECS instance provisioning) and Phase 3 (cutover pre-flip validation)

**Description**: The PLAN (decision 4 × decision 7) states the production EIP is reassociated only to production; staging never touches it. Staging therefore needs its own entry point for OpenVPN/WireGuard client validation during a bring-up window. Three options were surfaced:
1. **Dedicated (possibly ephemeral) Elastic IP** for staging only (clean, explicit, cost-neutral if released when staging scales to zero)
2. **Default (non-elastic) public IP** assigned to the staging instance's ENI (simpler, but the IP changes if the instance is stopped/started)
3. **Private-only validation path** (e.g., via Systems Manager Session Manager or the VPN's own management interface) — never exposes staging publicly

The choice affects Terraform (EIP allocation for staging) and the validation procedure in Phase 3.

**Acceptance criteria**:
- [ ] Engineer or main decides: dedicated EIP vs default public IP vs private-only
- [ ] If dedicated EIP: confirm it is released when staging scales to zero (to avoid idle charges)
- [ ] If default public IP: document the procedure to communicate the changing IP to engineers (e.g., via an output, a DNS alias, etc.)
- [ ] If private-only: document the validation path (Systems Manager, bastion, etc.) and confirm it can reach VPN ports 14720/14721
- [ ] Terraform code drafted for the chosen mechanism

**Pattern reference**: `terraform/modules/pritunl/main.tf:32-39` — the production EIP pattern (to be reused for production only)

```hcl
# From terraform/modules/pritunl/main.tf:32-39
resource "aws_eip" "pritunl" {
  instance = aws_instance.pritunl.id
  domain   = "vpc"
  tags = {
    Name = "pritunl-eip"
  }
}
```

**Dependencies**: Depends on engineer/main choice; must be decided before T2.4 (staging instance) can be fully specified.

**Open question**: Does the staging instance need to scale to zero by stopping the EC2 host itself, or just the ECS service? If the host stays running (but scaled-down), an EIP remains a cost. If the host stops, does a default public IP need to be pre-allocated?

---

#### SPIKE-6: EC2 host bring-up mechanism for `-staging` confirmation

**Phase**: Phase 2 (Terraform + Ansible infra)  
**Blocks**: T2.4 (Staging ECS instance provisioning)

**Description**: The PLAN (decision 7) surfaces two candidate mechanisms for scaling the staging Pritunl host from zero to one:
1. **Direct stop/start via `~/.claude/scripts/stop-instance.sh` / `start-instance.sh`** (the found working approach; keeps the staging instance a plain dedicated instance; does not introduce ASG complexity; but requires manual scripts in the skills layer)
2. **`ecs_capacity` module's ASG-backed capacity provider with `min_size=0`** (would automate the host lifecycle with ECS desired_count; but AWS docs note it launches **2 instances** on scale-from-zero, violating the "single dedicated instance" framing)

The PLAN rules out option 2 on the documented AWS behavior but does **not** get explicit engineer sign-off on option 1 — it is a "researched finding, not yet a signed-off decision" (residual open item).

**Acceptance criteria**:
- [ ] Engineer or main confirms: direct stop/start wrapper (option 1) is the intended mechanism
- [ ] If option 1: verify the existing `~/.claude/scripts/stop-instance.sh` / `start-instance.sh` scripts are sufficient (or extend them if staging host needs special handling)
- [ ] Terraform code for staging instance provisioned as a bespoke `aws_instance` (not via ASG)
- [ ] Skills or runbook documentation updated to show the stop/start workflow for staging bring-up/down

**Pattern reference**: `~/.claude/scripts/ecs-scale.sh:1-63` — the existing wrapper for ECS service desired-count scaling; the stop-instance/start-instance wrappers are the EC2-host complement

```bash
# From ~/.claude/scripts/ecs-scale.sh (excerpt)
aws ecs update-service --cluster "$cluster_name" --service "$service_name" --desired-count "$desired_count"
```

**Dependencies**: No hard blockers; should be confirmed before T2.4 to avoid late-stage rework.

**Open question**: Is there infrastructure-as-code (Terraform) preference for managing the staging host's start/stop state, or is the skills-layer wrapper sufficient? If Terraform-managed, should desired state be encoded (e.g., a `staging_desired_count` variable)?

---

#### SPIKE-7: `ecs_service` module extension vs. bespoke task definition decision

**Phase**: Phase 2 (Terraform + Ansible infra)  
**Blocks**: T2.3 (Production ECS) and T2.4 (Staging ECS)

**Description**: The PLAN (decision 2) requires a task definition with `privileged: true` and `network_mode: host` for the Pritunl container. The PLAN notes (grounded fact) that the existing `terraform/modules/ecs_service/main.tf:14` only sets `network_mode = "bridge"` for EC2 launch type, and there is **no `privileged` variable exposed** in the module. Two paths exist:
1. **Extend `ecs_service` module**: add a `privileged` variable and a `host` network-mode branch (one-time, reusable for future privileged containers)
2. **Bespoke task definition**: write custom `aws_ecs_task_definition` and `aws_ecs_service` resources for Pritunl ECS instances (lower reuse, but no module modification risk)

The choice affects execution complexity for T2.3 and T2.4 and future projects that need privileged containers.

**Acceptance criteria**:
- [ ] Engineer or main decides: extend module vs bespoke
- [ ] If extend module:
  - [ ] Verify the existing `ecs_service` module is the right place (no versioning constraints, no downstream consumers that would break)
  - [ ] Draft the `privileged` variable and `host` network-mode conditional
  - [ ] Test with a non-production example (e.g., a dummy container)
- [ ] If bespoke:
  - [ ] Review existing task definitions in the codebase to match style/naming
  - [ ] Draft Pritunl-specific task definition and service resources
- [ ] Terraform code ready for T2.3 / T2.4 implementation

**Pattern reference**: `terraform/modules/ecs_service/main.tf:14-54` — the current module structure (no privileged/host branch); and `terraform/modules/ecs_capacity/main.tf:1-51` — the launch template pattern that will be extended for host-prep user_data

```hcl
# From terraform/modules/ecs_service/main.tf:14
network_mode = var.launch_type == "FARGATE" ? "awsvpc" : "bridge"  # ← no host option
# And lines 21-54: container_definitions has no privileged key
```

**Dependencies**: Must be decided before T2.3 / T2.4; can be decided in parallel with other spikes.

**Open question**: If extending the module, should the `privileged` variable default to false (safe, explicit opt-in) or be omitted entirely (forcing an explicit input)? What is the naming convention for the host network-mode branch (e.g., `network_mode = var.network_mode` with a default, or an explicit `enable_host_networking` boolean)?

---

#### SPIKE-8: Pritunl SIGTERM graceful-shutdown behavior validation

**Phase**: Phase 3 (Cutover)  
**Blocks**: T3.2 (pre-flip validation) and Phase 1 Dockerfile finalization (STOPSIGNAL setting)

**Description**: The PLAN (residual open item) confirms that Pritunl's systemd unit file relies on `SIGTERM` with a 20-second grace window (`TimeoutStopSec=20`), but **does not document** what the process does with in-flight OpenVPN/WireGuard client sessions when it receives `SIGTERM`. Two possibilities:
1. The process **drains** in-flight sessions cleanly within the 20-second window
2. The process **drops** in-flight sessions immediately

This matters for the cutover phase: if sessions drop without warning, engineers connected to the VPN will lose access mid-cutover.

**Acceptance criteria**:
- [ ] Validate empirically: establish a live OpenVPN or WireGuard connection to a test Pritunl instance
- [ ] Send `SIGTERM` to the Pritunl process (via `docker stop` or `kill -15` on a running container/VM)
- [ ] Observe the connection behavior: does it persist for ~20 seconds (drain) or drop immediately?
- [ ] Document the finding with the exact Pritunl version tested (e.g., `v1.34.4681.89`)
- [ ] If drain: the Dockerfile's `STOPSIGNAL SIGTERM` + ECS `stopTimeout: 20s` is sufficient; document the graceful-shutdown behavior in comments
- [ ] If drop: explore workarounds (e.g., force-drain clients via fail2ban, pre-cutover notification, phased cutover)

**Pattern reference**: `pgbouncer/Dockerfile:18-25` — the explicit STOPSIGNAL pattern this will mirror

```dockerfile
# From pgbouncer/Dockerfile:18-25
STOPSIGNAL SIGTERM
STOPTIMEOUT 20s
# Rationale: pgbouncer drains in-flight connections on SIGTERM
```

**Dependencies**: No hard blockers for Phase 1 (Dockerfile can set STOPSIGNAL as-is and document the open question), but **must be resolved before Phase 3** to finalize the cutover runbook.

**Open question**: If Pritunl does NOT drain, are there alternative shutdown signals (e.g., `SIGALRM` that appears in the systemd file) that trigger graceful shutdown? Check Pritunl's own documentation or source code.

---

### Main implementation tasks (in dependency order)

---

#### T1: Phase 1 — New `pritunl` tool repository scaffolding (HubFlow shape)

**Blocks**: All Phase 2 and Phase 3 work (images must be built before ECS tasks can start)

---

##### T1.0: Create `pritunl` GitHub repository and register in governance (ENGINEER/MAIN ACTION)

**Phase**: Phase 1  
**Repository**: GitHub org + `terraform/identity/`

**Description**: Create the new `pritunl` repository in the 4Shark GitHub organization and add it to the `terraform/identity/github_repositories.tf` governance lists. This is the **first task** and is an engineer/main action, not an agent implementation task.

**Acceptance criteria**:
- [ ] `github.com/4shark/pritunl` repository exists with:
  - [ ] Empty state or README only
  - [ ] `develop` branch as default (not `master`)
  - [ ] Initial `master` branch exists
- [ ] `terraform/identity/github_repositories.tf` updated:
  - [ ] `local.hubflow_repositories` includes `"pritunl"`
  - [ ] Once CI produces the check: `local.hubflow_repositories_with_min_age_check` includes `"pritunl"`
  - [ ] NOT in `local.main_branch_repositories` (HubFlow shape, not main-only)
- [ ] Terraform plan/apply clean
- [ ] GitHub branch protection rules applied (require PR, require `Verify Minimum Age` check once CI ships)

**Dependencies**: None — can start immediately; blocks all subsequent Phase 1 tasks.

**Note**: This task is blocking and requires engineer/main authorization (likely a GitHub/Terraform admin action, not an agent implementation). Once this is done, the repo exists and subsequent tasks can proceed.

---

##### T1.1: Scaffold Dockerfile with base image, Pritunl install, and entrypoint skeleton

**Phase**: Phase 1  
**Repository**: `pritunl` (new)

**Description**: Write the Dockerfile (`FROM ubuntu:24.04`), add Pritunl's signed apt repository, install `pritunl` and supporting packages (`wireguard-tools`, `dnsmasq`, `fail2ban`) pinned via `ARG PRITUNL_VERSION`, and create a `configured-entrypoint.sh` skeleton that will later materialize Pritunl's runtime config (Mongo URI, rate limiting, dnsmasq, fail2ban startup).

**Acceptance criteria**:
- [ ] Dockerfile exists with:
  - [ ] `FROM ubuntu:24.04` (noble)
  - [ ] Pritunl apt-repo added (key + repo URL from `ansible/roles/4shark.pritunl/tasks/main.yml:93-97`)
  - [ ] `ARG PRITUNL_VERSION=<pinned-version>` with renovate annotation: `# renovate: datasource=github-releases packageName=pritunl/pritunl` (exact regex TBD by SPIKE-2)
  - [ ] `apt install pritunl wireguard-tools dnsmasq fail2ban` (conditional: only run if not already installed for idempotency)
  - [ ] `STOPSIGNAL SIGTERM` (explicit, with comment referencing systemd unit file; grace window detail TBD by SPIKE-8)
- [ ] `configured-entrypoint.sh` exists with:
  - [ ] Skeleton sections for: (a) Pritunl `set-*` commands (Mongo URI, rate limiting, auditing), (b) dnsmasq wait-loop + start, (c) fail2ban start
  - [ ] Comments marking sections as TODO — implementation deferred until Phase 2 knows Mongo VM private address
  - [ ] Helper functions for health checks / logging (copy from `pgbouncer/configured-entrypoint.sh:1-11` pattern)
- [ ] Local build test: `docker build -t pritunl:local .` succeeds

**Pattern reference**: `pgbouncer/Dockerfile:1-32` — base image pin pattern, explicit STOPSIGNAL, entrypoint chain

```dockerfile
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y pgbouncer
STOPSIGNAL SIGTERM
ENTRYPOINT ["/bin/bash", "/configured-entrypoint.sh"]
```

And `pgbouncer/configured-entrypoint.sh:1-11`:

```bash
#!/bin/bash
set -e
# Materialize config from env vars
cat > /etc/pgbouncer/pgbouncer.ini << EOF
...
EOF
exec pgbouncer -u pgbouncer /etc/pgbouncer/pgbouncer.ini
```

**Dependencies**: 
- Depends on T1.0 (repo must exist)
- Requires SPIKE-1 (Renovate regex) and SPIKE-8 (SIGTERM behavior) to finalize annotations

**Open question**: Should the entrypoint perform a health check on Pritunl startup (e.g., `curl http://localhost/health`)? Or rely on ECS health checks?

---

##### T1.2: Add Renovate configuration and custom-manager regex for Pritunl versioning

**Phase**: Phase 1  
**Repository**: `pritunl` (new)

**Description**: Write `renovate.json` with base `config:recommended`, `helpers:pinGitHubActionDigests`, `minimumReleaseAge: 7 days`, and a `customManagers` block to track the Dockerfile `ARG PRITUNL_VERSION` via `datasource=github-releases`. Include the exact regex discovered in SPIKE-1.

**Acceptance criteria**:
- [ ] `renovate.json` exists with:
  - [ ] `extends: ["config:recommended", "helpers:pinGitHubActionDigests"]`
  - [ ] `minimumReleaseAge: 7` (days)
  - [ ] `customManagers` block:
    ```json
    [
      {
        "customType": "regex",
        "fileMatch": ["^Dockerfile$"],
        "matchStrings": ["# renovate: datasource=(?<datasource>[a-z-]+?) packageName=(?<packageName>.+?)(?: versioning=(?<versioning>[a-z-]+?))?\\s(?:ENV|ARG) .+?_VERSION=(?<currentValue>.+?)\\s"],
        "datasourceTemplate": "github-releases",
        "versioning": "<regex-from-SPIKE-1>"
      }
    ]
    ```
  - [ ] Comment explaining the four-field version override for Pritunl
- [ ] `renovate.yml` runner workflow added (copy from `pgbouncer/renovate.yml` or `terraform/renovate.yml`)
- [ ] Renovate runs manually via `workflow_dispatch` and extracts `PRITUNL_VERSION` correctly (dry-run, no actual bump yet)

**Pattern reference**: `pgbouncer/renovate.json:1-39` — the non-semver `versioning` override precedent

```json
{
  "extends": ["config:recommended"],
  "customManagers": [
    {
      "customType": "regex",
      "fileMatch": ["^Dockerfile$"],
      "matchStrings": ["# renovate: datasource=github-releases packageName=edoburu/pgbouncer\\s(?:ENV|ARG) PGBOUNCER_VERSION=(?<currentValue>.+?)\\s"],
      "datasourceTemplate": "github-releases",
      "versioning": "regex:^pgbouncer-(?<major>\\d+)-(?<minor>\\d+)-(?<patch>\\d+)(-p(?<build>\\d+))?$"
    }
  ]
}
```

**Dependencies**: 
- Depends on T1.1 (Dockerfile `ARG` annotation must exist)
- Depends on SPIKE-1 (exact regex discovered and tested)

**Open question**: Should the version regex be strict (fail if it doesn't match) or permissive (match any version format)? Recommend strict for safety.

---

##### T1.3: Add CI workflows (hadolint, min-age gate, build.yaml, deploy.yaml)

**Phase**: Phase 1  
**Repository**: `pritunl` (new)

**Description**: Write GitHub Actions workflows for:
1. **`ci.yaml`**: hadolint linting on every Dockerfile push
2. **Minimum-age gate files**: `.github/scripts/verify-minimum-age.sh`, `.github/workflows/verify-minimum-age.yaml` (PR trigger + daily re-verify), `.github/workflows/reverify-minimum-age.yaml` — these may be shared across repos; check if they already exist in a common location or if this repo needs its own copy
3. **`build.yaml`**: one job per target (`develop` → `:latest` + `:<short-sha>` to `<environment>-staging` ECR, `master` → production ECR); includes `workflow_dispatch` with environment choice input
4. **`deploy.yaml`**: manual `workflow_dispatch`, per-target cluster/service/task-family map, `aws ecs update-service --force-new-deployment`, stabilization poll waiting for `rolloutState == COMPLETED`

**Acceptance criteria**:
- [ ] `ci.yaml` runs hadolint on Dockerfile and blocks merge on lint failure
- [ ] Minimum-age gate files present (shared or repo-specific); gate blocks merge until 7 days have elapsed for a new version
- [ ] `build.yaml`:
  - [ ] Triggers on `push: branches: [develop, master]` and `workflow_dispatch`
  - [ ] One explicit job per target (staging/production)
  - [ ] Each job pushes `:latest` + `:<short-sha>` to its target's ECR repo
  - [ ] GitHub Environments used for credentials per target (`STAGING_ECR_REGISTRY`, `PRODUCTION_ECR_REGISTRY`, etc., or auto-derived from Terraform)
- [ ] `deploy.yaml`:
  - [ ] Manual `workflow_dispatch` only (no auto-trigger on merge)
  - [ ] Input: choice of `environment` (staging / production)
  - [ ] Calls `aws ecs update-service --force-new-deployment` with per-target cluster/service/task-family
  - [ ] Polls for `rolloutState == COMPLETED` with timeout
- [ ] All workflows pass dry-run test (e.g., `workflow_dispatch` on `develop` succeeds, produces images in ECR)

**Pattern reference**: `keycloak/.github/workflows/build.yaml:1-108` and `keycloak/.github/workflows/deploy.yaml:1-101`

```yaml
# From keycloak/build.yaml excerpt
name: build
on:
  push:
    branches: [develop, master]
  workflow_dispatch:
    inputs:
      environment:
        type: choice
        options: [staging, production]
jobs:
  build-staging:
    if: github.ref == 'refs/heads/develop' || github.event.inputs.environment == 'staging'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build and push to ECR
        run: |
          aws ecr get-login-password | docker login --username AWS --password-stdin $ECR_REGISTRY
          docker build -t $ECR_REGISTRY/auth-001-staging:latest -t $ECR_REGISTRY/auth-001-staging:$SHORT_SHA .
          docker push $ECR_REGISTRY/auth-001-staging:latest
          docker push $ECR_REGISTRY/auth-001-staging:$SHORT_SHA
```

**Dependencies**: 
- Depends on T1.0 (repo must exist)
- Depends on T2.1 (ECR repos must exist so push targets are known)
- Requires `workflow_dispatch` to create the AWS ECR and IAM credentials (done in T2.1)

**Open question**: Should GitHub Environments be pre-created manually, or auto-derived from Terraform outputs? If auto-derived, when does the Terraform config for ECR repos run relative to this workflow?

---

##### T1.4: Add CHANGELOG.md with HubFlow lifecycle

**Phase**: Phase 1  
**Repository**: `pritunl` (new)

**Description**: Write `CHANGELOG.md` following Keep a Changelog + Semantic Versioning format. Include notes on the HubFlow lifecycle specific to this repo: dated `## [X.Y.Z] - YYYY-MM-DD` sections are created directly on the `release/*` branch, **NOT** under `## [Unreleased]` (unlike main-only repos). Seed the CHANGELOG with a `## [Unreleased]` section (empty, ready for the first development cycle).

**Acceptance criteria**:
- [ ] `CHANGELOG.md` exists with:
  - [ ] Header explaining the HubFlow lifecycle (dated sections on release branches)
  - [ ] `## [Unreleased]` section (empty)
  - [ ] Blank lines around all headings (CommonMark compliance)
  - [ ] Section order: Added, Changed, Deprecated, Removed, Fixed, Security
- [ ] Commit includes the CHANGELOG.md and is pushed to `develop` as part of the PR

**Pattern reference**: `pgbouncer/CHANGELOG.md:1-25` — example CHANGELOG shape (note: pgbouncer is main-only, so structure differs; check `keycloak/CHANGELOG.md` for HubFlow shape)

**Dependencies**: None — can be done in parallel with T1.1-T1.3.

---

##### T1.5: Merge Phase 1 PR and validate

**Phase**: Phase 1  
**Repository**: `pritunl` (new)

**Description**: Create a single PR with all Phase 1 components (Dockerfile, entrypoint skeleton, renovate.json, CI workflows, CHANGELOG.md). Ensure all checks pass, then merge to `develop`.

**Acceptance criteria**:
- [ ] PR created with all Phase 1 components
- [ ] All CI checks pass:
  - [ ] hadolint passes
  - [ ] Minimum-age gate passes (or is waived for the initial commit)
  - [ ] Build workflow runs successfully via `workflow_dispatch`, produces images in ECR with tags
- [ ] Manual verification: pull the `pritunl:latest` image locally and run `docker run -it pritunl:latest bash` to confirm the Dockerfile layers are correct
- [ ] PR merged to `develop`
- [ ] Master branch exists and is ready for HubFlow release (no commits yet)

**Pattern reference**: Standard GitHub PR workflow (no special pattern; just good hygiene)

**Dependencies**: All T1.1-T1.4 must be completed.

---

### Phase 2 — Terraform Infrastructure Tasks

---

#### T2.0: Pre-phase dependency verification

**Phase**: Phase 2 (preparation)  
**Repository**: `terraform`

**Description**: Confirm all SPIKE tasks (SPIKE-2 through SPIKE-7) have been completed and decisions documented. This is a gate before Terraform authoring begins.

**Acceptance criteria**:
- [ ] SPIKE-1 result: exact Renovate regex documented (T1.2 can finalize now)
- [ ] SPIKE-2 result: Mongo VM Ansible role placement decided (new role vs conditional)
- [ ] SPIKE-3 result: dedicated Mongo security group mechanism decided (SG-to-SG vs CIDR)
- [ ] SPIKE-4 result: staging Mongo strategy decided (separate VM vs shared vs ephemeral)
- [ ] SPIKE-5 result: staging public-entry mechanism decided (dedicated EIP vs default IP vs private-only)
- [ ] SPIKE-6 result: EC2 host bring-up mechanism confirmed (direct stop/start)
- [ ] SPIKE-7 result: `ecs_service` module decision made (extend vs bespoke)
- [ ] SPIKE-8 in progress: Pritunl SIGTERM behavior validation underway (needed for Phase 3 runbook, but T2.x doesn't require it yet)

**Dependencies**: All spike tasks must be started/completed before T2.1.

---

##### T2.1: ECR repositories + identity-stack governance

**Phase**: Phase 2  
**Repository**: `terraform`

**Description**: Create two ECR repositories for Pritunl images (`pritunl` for production, `pritunl-staging` for staging) with identical scanning/encryption config (matching `terraform/auth-001/ecr.tf:1-29` pattern). Update `terraform/identity/github_repositories.tf` to add `pritunl` to `local.hubflow_repositories` and `local.hubflow_repositories_with_min_age_check`.

**Acceptance criteria**:
- [ ] `terraform/ecr/pritunl.tf` (or within existing `ecr.tf`) defines:
  - [ ] `aws_ecr_repository.pritunl` (name: `"pritunl"`)
  - [ ] `aws_ecr_repository.pritunl_staging` (name: `"pritunl-staging"`)
  - [ ] Both with `image_tag_mutability = "IMMUTABLE"`, `scan_on_push = true`, `encryption_config` block
  - [ ] IAM policy allowing GitHub Actions to push to both repos (per target environment)
- [ ] `terraform/identity/github_repositories.tf`:
  - [ ] Add `"pritunl"` to `local.hubflow_repositories` list
  - [ ] Add `"pritunl"` to `local.hubflow_repositories_with_min_age_check` list (once CI check exists)
- [ ] GitHub Actions workflows (from T1.3) can now push images to ECR (test push manually)
- [ ] `terraform plan` and `terraform apply` clean

**Pattern reference**: `terraform/auth-001/ecr.tf:1-29`

```hcl
resource "aws_ecr_repository" "auth_001" {
  name                 = "auth-001"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}
```

**Dependencies**: 
- Depends on T1.0 (repo must exist so GitHub Actions credentials can be set up)
- Depends on T2.0 (all spike decisions must be made)
- Blocks T2.3 and T2.4 (ECS services depend on ECR repos)

---

##### T2.2: MongoDB VM (bare instance + security group + Ansible role provisioning)

**Phase**: Phase 2  
**Repository**: `terraform` + `ansible`

**Description**: Provision a dedicated MongoDB EC2 VM alongside the running combined VM. Include:
1. Bare `aws_instance` resource (no ASG, single dedicated instance) with EBS root volume
2. Dedicated security group (ingress restricted to Pritunl instance only; mechanism per SPIKE-3)
3. Launch template with user_data to register with Ansible and optionally trigger Ansible playbook (or Ansible run happens post-boot via SSH/SSM)
4. Extract/refactor Ansible MongoDB tasks from `ansible/roles/4shark.pritunl/` into the target location (per SPIKE-2 decision: new role or conditional)

**Acceptance criteria**:
- [ ] `terraform/mongodb/pritunl.tf` (or within existing module) defines:
  - [ ] `aws_instance.pritunl_mongodb` with:
    - [ ] `instance_type = "t3a.small"` or engineer-specified (TBD)
    - [ ] `ami = data.aws_ami.ubuntu_24_04_lts.id`
    - [ ] EBS root volume sized for MongoDB data
    - [ ] `user_data` script that either:
      - [ ] Registers the instance in Ansible inventory (via tags, DNS, etc.)
      - [ ] Or directly triggers the Ansible playbook (via `provisioner` or external)
    - [ ] Tags: `Name`, `Project`, `Environment`, etc.
  - [ ] `aws_security_group.pritunl_mongodb` with:
    - [ ] Ingress on port 27017 from Pritunl instance only (mechanism per SPIKE-3)
    - [ ] Egress unrestricted (or minimally, allow updates)
  - [ ] Static or ENI-backed private IP (if necessary for security group references; per SPIKE-3)
- [ ] Ansible provisioning (per SPIKE-2 decision):
  - [ ] If new role: `ansible/roles/4shark.mongodb-pritunl/` created with trimmed tasks from `ansible/roles/4shark.pritunl/tasks/main.yml:32-79`
  - [ ] If conditional: `ansible/roles/4shark.pritunl/tasks/main.yml` updated to conditionally run Mongo tasks only for the `mongodb_host` inventory group
  - [ ] Playbook: `ansible/playbooks/provision-pritunl-mongo.yml` (new or extension to existing playbook) targets the Mongo VM's inventory
  - [ ] Variables: `pritunl_mongodb_version: "8.0"` (carried forward unchanged)
  - [ ] Handlers: `restart mongod` configured for systemd
- [ ] Manual verification:
  - [ ] EC2 instance launches, reaches running state
  - [ ] Ansible playbook runs successfully (or is queued for manual run)
  - [ ] MongoDB process (`mongod`) is running on the instance
  - [ ] Port 27017 is reachable ONLY from the Pritunl security group (test from a machine outside the Pritunl group — should be refused)
- [ ] `terraform plan` clean; `terraform apply` succeeds and instance is reachable

**Pattern reference**: `terraform/modules/ecs_capacity/main.tf:1-51` — launch template and user_data pattern for host prep

```hcl
resource "aws_launch_template" "example" {
  ...
  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo "ECS_CLUSTER=${var.cluster_name}" >> /etc/ecs/ecs.config
  EOF
  )
}
```

And `ansible/roles/4shark.pritunl/tasks/main.yml:32-79` — MongoDB tasks to extract.

**Dependencies**: 
- Depends on T2.0 (spike decisions, especially SPIKE-2 and SPIKE-3)
- Blocks T2.3 (Pritunl ECS must be able to connect to Mongo VM)
- No hard dependency on T2.1 (can run in parallel)

**Open question**: Should the Mongo VM be in a separate subnet / availability zone for isolation, or in the same private subnet as the Pritunl ECS instances? This affects security group design (cross-AZ considerations).

---

##### T2.3: Production Pritunl ECS (task definition, host prep, security group, IAM)

**Phase**: Phase 2  
**Repository**: `terraform`

**Description**: Provision the production Pritunl ECS instance and supporting infrastructure:
1. **ECS task definition** (per SPIKE-7 decision: bespoke or extended module) with:
   - [ ] `privileged: true`
   - [ ] `network_mode: "host"`
   - [ ] Container definition pointing to production ECR image (`pritunl:latest`)
   - [ ] `environment` variables: `PRITUNL_MONGO_URL`, `PRITUNL_AUTH_RATE_LIMIT_DISABLED`, etc. (sourced from Terraform variables / Mongo VM private IP)
   - [ ] `stopTimeout: 20` (seconds; matches systemd `TimeoutStopSec`)
   - [ ] Logging to CloudWatch Logs (ECS log driver)
   - [ ] Port mappings for 14720/tcp (OpenVPN) and 14721/udp (WireGuard)
2. **ECS service** (per SPIKE-7 decision):
   - [ ] Cluster: shared Pritunl ECS cluster (create if doesn't exist)
   - [ ] Service: `pritunl` with `desired_count = 1`
   - [ ] Capacity provider: EC2-backed (reference the capacity provider from the host ASG)
3. **EC2 instance / ASG** (via `ecs_capacity` module or bespoke):
   - [ ] Launch template with `user_data` extended to:
     - [ ] Disable `systemd-resolved` DNS stub (host-level DNS bootstrap, from Ansible mapping row 1)
     - [ ] Load WireGuard kernel module (`modprobe wireguard`)
     - [ ] Ensure `/dev/net/tun` device node exists (or is provisioned by the kernel)
     - [ ] Base OS hardening (TBD: kernel params, security updates, etc.)
     - [ ] Register with ECS cluster
   - [ ] Instance type: `t3a.medium` or engineer-specified (TBD; larger than current `t3a.micro`)
4. **Security group**:
   - [ ] Ingress: ports 14720/tcp, 14721/udp (OpenVPN/WireGuard client connections)
   - [ ] Ingress: port 443/tcp (Pritunl admin API, optional; check current `terraform/modules/pritunl/security.tf`)
   - [ ] Egress: unrestricted (or minimally, allow Mongo VM port 27017)
5. **IAM role**:
   - [ ] Carry forward route-advertisement permissions from current role (`ec2:DescribeRouteTables`, `CreateRoute`, `ReplaceRoute`, `DeleteRoute` — from `terraform/modules/pritunl/iam.tf:29-49`)
   - [ ] Add ECS service role permissions (ECS task execution, CloudWatch Logs, ECR pull)
6. **EIP (production only)**:
   - [ ] **Do NOT associate the production EIP yet** (PLAN decision 4, phase 3 handles the flip)
   - [ ] Create the Pritunl instance with a temporary/secondary Elastic IP for Phase 3 validation (or rely on default public IP if pre-allocated)

**Acceptance criteria**:
- [ ] `terraform plan` output shows:
  - [ ] ECR repository and task definition created
  - [ ] ECS service at `desired_count = 1`
  - [ ] EC2 instance / ASG with extended launch template
  - [ ] Security groups with correct ports
  - [ ] IAM role with route-advertisement + ECS permissions
  - [ ] No association to the production EIP yet
- [ ] `terraform apply` succeeds
- [ ] Manual verification:
  - [ ] EC2 instance launches and joins the ECS cluster
  - [ ] Pritunl container starts and reaches running state (check CloudWatch Logs)
  - [ ] Ports 14720/14721 are reachable from the VPC
  - [ ] MongoDB connection works (entrypoint can `connect to <mongo-vm-ip>:27017`)
  - [ ] DNS resolution for `*.4shark.internal` works from inside the container (dnsmasq wait-loop + start works)
  - [ ] fail2ban is running inside the container (check logs)

**Pattern reference**: `terraform/modules/ecs_capacity/main.tf` (capacity provider), `terraform/modules/connection_pooler/main.tf` (full ECS example), and `terraform/modules/pritunl/main.tf` (existing Pritunl IAM/security group)

**Dependencies**: 
- Depends on T1.5 (image pushed to ECR)
- Depends on T2.1 (ECR repo created, image can be pulled)
- Depends on T2.2 (Mongo VM running and reachable)
- Depends on SPIKE-7 (decide on task definition approach)
- Blocks T3 (cutover phase requires this instance)

**Open question**: Should the production Pritunl instance be in a dedicated ASG (only this one instance) or part of a shared Pritunl ECS capacity provider? Dedicated is simpler; shared might be more cost-efficient if other tools join later.

---

##### T2.4: Staging Pritunl ECS (task definition, host prep, public entry, desired_count=0)

**Phase**: Phase 2  
**Repository**: `terraform`

**Description**: Provision the staging Pritunl ECS instance (normally at zero capacity). Mirrors T2.3 but with staging-specific details:
1. **ECS task definition**: same structure as T2.3 but:
   - [ ] Pointing to staging ECR image (`pritunl-staging:latest`)
   - [ ] `PRITUNL_MONGO_URL` pointing to staging MongoDB (per SPIKE-4 decision: separate VM, shared database, or ephemeral)
   - [ ] Logging to a separate CloudWatch log group (`/ecs/pritunl-staging`)
2. **ECS service**:
   - [ ] Same cluster as production
   - [ ] Service: `pritunl-staging` with `desired_count = 0` (default; scaled up manually during validation)
3. **EC2 instance / ASG**:
   - [ ] Same launch template as production (host prep, kernel modules, ECS registration)
   - [ ] ASG configured to scale between 0 and 1 instance (or bespoke, per SPIKE-6: direct stop/start)
4. **Security group**:
   - [ ] Same ports as production (14720/tcp, 14721/udp, 443/tcp)
5. **Public entry point** (per SPIKE-5 decision):
   - [ ] If dedicated EIP: allocate and associate to staging instance
   - [ ] If default public IP: output the instance's public IP (may change on stop/start)
   - [ ] If private-only: no public IP; reference SSM Session Manager or VPN management interface for validation
6. **Database** (per SPIKE-4 decision):
   - [ ] If separate staging Mongo VM: create it here (or in a separate task, depending on grouping)
   - [ ] If shared production Mongo: ensure the staging database name is distinct (e.g., `pritunl_staging` vs `pritunl_production`)
   - [ ] If ephemeral: documented but provisioning deferred to validation phase

**Acceptance criteria**:
- [ ] `terraform plan` output shows:
  - [ ] Staging ECS service at `desired_count = 0`
  - [ ] Staging EC2 instance (stopped, not running, unless engineer requires it up during Phase 2)
  - [ ] Staging security group with same ports
  - [ ] Public entry point (EIP, default IP, or private-only note)
  - [ ] Staging database configuration per SPIKE-4 decision
- [ ] `terraform apply` succeeds
- [ ] Manual verification:
  - [ ] Scaling up works: `aws ecs update-service --desired-count 1` (or `start-instance.sh`) brings the instance online
  - [ ] Pritunl container starts and reaches running state
  - [ ] Connection to staging public entry point (IP/EIP) works (or SSM path works, if private-only)
  - [ ] Staging database is reachable and distinct from production
  - [ ] Scaling down works: `aws ecs update-service --desired-count 0` (or `stop-instance.sh`) stops the instance

**Pattern reference**: `terraform/auth-001/auth_001_staging.tf:1-194` — the existing Fargate staging-instance pattern (adapted for EC2)

```hcl
resource "aws_ecs_service" "auth_001_staging" {
  desired_count = 0  # ← normally at zero
  ...
}
```

**Dependencies**: 
- Depends on T1.5 (staging image pushed to ECR)
- Depends on T2.1 (ECR repo created)
- Depends on T2.2 or SPIKE-4 decision result (Mongo configuration for staging)
- Depends on SPIKE-4, SPIKE-5, SPIKE-6, SPIKE-7 (all staging-specific decisions)
- Blocks Phase 3 validation (staging instance is part of the cutover pre-flip checks)

**Open question**: Should the staging instance be pre-scaled to 1 at the end of T2.4 to test the bring-up procedure, or kept at 0 until Phase 3 validation? Recommend keeping at 0 and testing the scale-up as part of Phase 3 pre-checks.

---

### Phase 3 — Cutover (One-Time VM to ECS Migration)

---

##### T3.1: MongoDB state migration (`mongodump` → `mongorestore`)

**Phase**: Phase 3  
**Repository**: (manual / runbook)

**Description**: Extract the current combined VM's MongoDB data and restore it into the new dedicated Mongo VM. This is the critical state-transfer step and the primary risk point.

**Acceptance criteria**:
- [ ] Script/runbook documenting:
  - [ ] `ssh` into current combined VM
  - [ ] `mongodump --out /tmp/pritunl-backup-$(date +%s)` to export all databases
  - [ ] Transfer dump to Mongo VM (e.g., via `scp`, `aws s3`, or direct `mongorestore` over network if credentials allow)
  - [ ] `mongorestore /path/to/dump` on the Mongo VM
  - [ ] Verify restored data: user count, org count, route entries match the source
  - [ ] Capture and document the verified counts (for proof of successful restore)
- [ ] Restore validation queries:
  - [ ] `mongo pritunl --eval "db.users.count()"`
  - [ ] `mongo pritunl --eval "db.organization.count()"`
  - [ ] `mongo pritunl --eval "db.routes.count()"`
  - [ ] Compare counts to the source dump

**Pattern reference**: No existing 4Shark pattern; standard MongoDB backup/restore procedures

```bash
mongodump --out /tmp/pritunl-backup --db pritunl
mongorestore /tmp/pritunl-backup/pritunl --db pritunl
```

**Dependencies**: 
- Depends on T2.2 (Mongo VM running and reachable)
- Depends on T2.3 (production Pritunl ECS ready to connect to restored Mongo)
- Blocks T3.2 (pre-flip validation)

---

##### T3.2: Pre-flip parallel validation (connectivity, DNS, Mongo over temporary IP)

**Phase**: Phase 3  
**Repository**: (manual / runbook)

**Description**: With the new production stack live on a **temporary secondary Elastic IP** (or default public IP if no EIP allocated yet), validate that all systems work correctly **before** flipping the production EIP. This is where the dnsmasq wait-loop, fail2ban iptables reach, and Pritunl↔Mongo-VM network are first tested in a realistic scenario.

**Acceptance criteria**:
- [ ] OpenVPN connectivity:
  - [ ] Generate a test client profile pointing to the temporary IP
  - [ ] Import into OpenVPN client (or another test tool)
  - [ ] Establish connection; confirm it reaches "connected" state
- [ ] WireGuard connectivity:
  - [ ] Generate a test WireGuard peer key via Pritunl admin
  - [ ] Import into WireGuard client
  - [ ] Bring up the tunnel; confirm it routes traffic
- [ ] DNS resolution for `*.4shark.internal`:
  - [ ] From an active VPN client connection, query a known internal hostname (e.g., `app.4shark.internal`)
  - [ ] Confirm resolution succeeds (resolves to internal IP)
  - [ ] This validates dnsmasq is running, listening on the VPN interface, and forwarding to the VPC resolver
- [ ] Pritunl↔Mongo-VM network:
  - [ ] From inside the Pritunl container (via `docker exec` or ECS Exec), test connection to Mongo VM
  - [ ] `nc -zv <mongo-vm-ip> 27017` (or `mongo --host <mongo-vm-ip>`)
  - [ ] Confirm connection succeeds; this validates the dedicated security group is working
- [ ] fail2ban brute-force protection (optional, but recommended):
  - [ ] Attempt multiple failed Pritunl admin login attempts from a test client IP
  - [ ] Confirm fail2ban bans the IP (check Pritunl's admin panel or `iptables -L` on the host)
  - [ ] Verify the ban blocks subsequent connection attempts
- [ ] Document all results and timestamp (for the cutover record)

**Pattern reference**: No existing 4Shark runbook; aligns with cutover best practices (validate on a temporary IP before flipping production traffic)

**Acceptance criteria (SPIKE-8 required)**:
- [ ] If SPIKE-8 finds that Pritunl **drains** in-flight connections on `SIGTERM`:
  - [ ] Document: "graceful shutdown confirmed; in-flight sessions will drain within 20 seconds"
  - [ ] This is low-risk for the EIP flip
- [ ] If SPIKE-8 finds that Pritunl **drops** in-flight connections immediately:
  - [ ] Investigate workarounds (e.g., pre-flip notification, graceful client disconnect procedure)
  - [ ] Escalate to engineer if risk is unacceptable

**Dependencies**: 
- Depends on T3.1 (Mongo state restored)
- Depends on T2.3 (production ECS running on temporary IP)
- Depends on SPIKE-8 (understand SIGTERM behavior; may gate this task)
- Blocks T3.3 (EIP flip)

---

##### T3.3: Scheduled maintenance window — EIP reassociation

**Phase**: Phase 3  
**Repository**: `terraform`

**Description**: In a scheduled maintenance window (after pre-flip validation passes), reassociate the production Elastic IP from the old combined VM to the new production Pritunl ECS instance. This is the critical flip and should be done in a controlled window.

**Acceptance criteria**:
- [ ] Maintenance window scheduled and communicated to engineers (time, expected downtime, rollback plan)
- [ ] Terraform code updated:
  - [ ] `terraform/modules/pritunl/main.tf` (or wherever EIP is defined) changed to:
    - [ ] Update `aws_eip_association.pritunl` to point to the new production instance ID (not the old combined VM)
  - [ ] Plan shows only the EIP association change
- [ ] **Within the maintenance window**:
  - [ ] Run `terraform apply` to reassociate EIP (downtime is ~seconds to ~minutes, depending on ECS health check timing)
  - [ ] Monitor Pritunl admin panel (or CloudWatch logs) for errors
  - [ ] Confirm new instance is healthy and processing connections
- [ ] Post-flip smoke test (see T3.4)

**Pattern reference**: `terraform/modules/pritunl/main.tf:41-44` — the EIP association resource (unchanged in shape, just re-targeted)

```hcl
resource "aws_eip_association" "pritunl" {
  instance_id       = aws_instance.pritunl.id  # ← changes from old combined VM to new ECS instance
  allocation_id     = aws_eip.pritunl.id
  private_ip_address = "10.x.x.x"  # TBD based on ECS instance ENI
}
```

**Dependencies**: 
- Depends on T3.2 (pre-flip validation passes)
- Blocks T3.4 (post-flip smoke test)

**Risk**: This is the highest-risk task; any mistake locks all engineers out of the VPN. Engineer review and explicit confirmation before execution is critical.

---

##### T3.4: Post-flip smoke test

**Phase**: Phase 3  
**Repository**: (manual / runbook)

**Description**: After the EIP flip, confirm that the production VPN is healthy and processing traffic at the new IP address.

**Acceptance criteria**:
- [ ] OpenVPN connectivity:
  - [ ] Reconnect a real client to the production EIP (now pointing to new Pritunl instance)
  - [ ] Confirm connection succeeds
- [ ] WireGuard connectivity:
  - [ ] Reconnect a real WireGuard client
  - [ ] Confirm tunnel is active and routing traffic
- [ ] DNS resolution:
  - [ ] From the connected VPN client, resolve `*.4shark.internal` hostnames
  - [ ] Confirm resolution works
- [ ] Admin access:
  - [ ] Access Pritunl admin panel at the EIP IP
  - [ ] Confirm the database reflects the restored state (user count, orgs, routes are correct)
- [ ] Document results and timestamp (cutover complete)

**Pattern reference**: Standard VPN smoke-test procedures; no new pattern.

**Dependencies**: 
- Depends on T3.3 (EIP flipped)
- Completes Phase 3

---

### Phase 4 — VM Retirement

---

##### T4.1: Stop old combined VM (retain for rollback window)

**Phase**: Phase 4  
**Repository**: `terraform` (or manual)

**Description**: Stop (do not terminate) the old combined Pritunl VM. This serves as a rollback path if the new stack has critical issues.

**Acceptance criteria**:
- [ ] Old combined VM (`terraform/vpn/main.tf`'s instance) is stopped (not terminated)
- [ ] VM remains stopped for a retention window (engineer-specified duration; recommend N = 7-14 days)
- [ ] Terraform code **does not yet remove** the old Terraform modules (removed in T4.2, after retention window)
- [ ] Document the stop time and rollback procedure (if needed, use Terraform to stop → EIP flip back → resume)

**Pattern reference**: Terraform `aws_instance` resource can be stopped without destruction (just change instance state)

**Dependencies**: 
- Depends on T3.4 (post-flip smoke test passes; new stack is healthy)
- Blocks T4.2 (retention window must elapse first)

---

##### T4.2: Remove old Terraform modules and infrastructure code

**Phase**: Phase 4  
**Repository**: `terraform` + `ansible`

**Description**: After the retention window elapses (and no rollback is needed), remove the old `terraform/vpn/` and `terraform/modules/pritunl/` code. Update `ansible/playbooks/provision-pritunl.yml` to remove or reduce the role.

**Acceptance criteria**:
- [ ] `terraform/vpn/main.tf` removed or gutted (no Pritunl module instantiation)
- [ ] `terraform/modules/pritunl/` directory removed
- [ ] `ansible/playbooks/provision-pritunl.yml` updated:
  - [ ] If a new independent Mongo role exists: role removed (Mongo provisioning now happens in `terraform/` via the Mongo VM)
  - [ ] If Mongo role conditional remains: trimmed to only Mongo tasks, applied only to `mongodb_host` inventory group
  - [ ] Pritunl tasks removed (no longer needed; container image handles it)
- [ ] `terraform plan` shows resource deletions (old VPN stack); apply to remove
- [ ] Ansible playbook still runs but no longer targets the combined VM (which is now stopped/terminated)

**Pattern reference**: Standard Terraform/Ansible cleanup (no new pattern)

**Dependencies**: 
- Depends on T4.1 (retention window elapsed; old VM confirmed stopped)
- Completion signals end of Phase 4

---

##### T4.3: Terminate old combined VM (after retention window)

**Phase**: Phase 4  
**Repository**: `terraform` (optional, if not already done)

**Description**: After the retention window, terminate the old combined Pritunl VM and release its EBS volumes.

**Acceptance criteria**:
- [ ] Old combined VM is terminated (can be done via Terraform `destroy` or manual AWS console)
- [ ] EBS volumes are deleted (follow AWS default: delete on termination)
- [ ] Document final decommissioning timestamp

**Pattern reference**: Standard EC2 lifecycle; no new pattern

**Dependencies**: 
- Depends on T4.1 (retention window elapsed)
- Completion signals VM retirement is final

---

## Cross-cutting concerns

### Testing strategy
- **Phase 1 (Dockerfile)**: local `docker build` test; Renovate dry-run to verify version extraction
- **Phase 2 (Terraform)**: `terraform plan` must be clean and reviewed before `apply`; manual validation of EC2/ECS launch, container startup, connectivity
- **Phase 3 (Cutover)**: pre-flip validation on temporary IP is the main test; post-flip smoke test confirms success
- **Phase 4 (Retirement)**: cleanup is straightforward; no complex testing needed

### Error handling
- **Phase 1 Dockerfile build failure**: revert Dockerfile, fix, re-build locally before pushing
- **Phase 2 Terraform failures**: revert Terraform code, debug resource issues, retry; keep the old combined VM untouched until new stack is stable
- **Phase 3 pre-flip validation failure**: do NOT flip EIP; investigate the issue (dnsmasq, fail2ban, Mongo connection, etc.) and fix before proceeding
- **Phase 3 post-flip failure**: if the new stack is unhealthy, EIP flip can be reversed (Terraform change) to revert to the old VM; rollback procedure should be documented and tested before cutover

### Observability
- **Phase 1**: GitHub Actions logs (build workflow)
- **Phase 2**: Terraform apply logs; CloudWatch Logs for ECS container startup
- **Phase 3**: CloudWatch Logs for Pritunl/dnsmasq/fail2ban; ECS container health checks; manual connection tests
- **Phase 4**: Terraform apply logs for resource deletion; EC2 console for VM state

---

## Open questions for the engineer

1. **Decomposition option choice**: Option A (per-component PRs, more modular) or Option B (dependency-ordered PRs, fewer total)?

2. **Phase 1 health checks**: Should the Dockerfile entrypoint perform a health check on Pritunl startup, or rely on ECS health checks?

3. **SPIKE-1 result**: Once the Renovate versioning regex is finalized, confirm it works with a live test

4. **SPIKE-2 result**: New independent Mongo Ansible role, or conditional in the existing role?

5. **SPIKE-3 result**: Security-group-to-security-group scoping (new pattern) or narrowed CIDR (existing pattern)?

6. **SPIKE-4 result**: Separate staging Mongo VM, shared prod Mongo database, or ephemeral Mongo?

7. **SPIKE-5 result**: Dedicated staging EIP, default public IP, or private-only validation path for staging?

8. **SPIKE-6 result**: Confirm direct stop/start EC2-host mechanism (vs ASG managed scaling)

9. **SPIKE-7 result**: Extend `ecs_service` module or write bespoke task definitions?

10. **SPIKE-8 result**: Does Pritunl drain or drop in-flight sessions on `SIGTERM`? This affects cutover risk assessment.

11. **Retention window**: How many days should the old combined VM be kept stopped before final termination (T4.1)?

12. **Staging bring-up test**: Should the staging instance be pre-scaled to 1 at the end of T2.4 to test the bring-up, or kept at 0 until Phase 3 validation?

---

## Sources

All sources are from the approved PLAN.md and PLAN-SPIKE.md. Specific citations per task above.
