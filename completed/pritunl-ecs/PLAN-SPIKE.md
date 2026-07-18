# PLAN-SPIKE — Pritunl VPN: VM to Containerized ECS Migration

> Reference: `~/.claude/docs/DOCKER-IMAGE-TOOL-REPOSITORIES.md`, `~/.claude/docs/AUTOMATED-DEPENDENCY-UPDATES.md`, `~/.claude/docs/DEPLOYMENT-STRATEGY.md`
> Auxiliary: `pritunl-ecs-migration_options-comparison_1.html` (historical options record — every option, pro/con, cost/risk considered before the engineer's first round of decisions; kept for reference, superseded by this document as the plan of record)
> Status: **REVISED (second pass)** — the engineer changed three of the seven decisions after reviewing the first converged draft: (3) MongoDB moves from a colocated sidecar to a dedicated VM, (5) branch model moves from main-only to HubFlow (mirroring `keycloak`), (7) the cutover/deploy model gains a recurring staging→prod flow distinct from the one-time VM migration. Decisions (1) base image, (2) runtime/launch type, and (4) public entry (EIP) are unchanged from the first pass. This document encodes the final seven-decision set — it is not a menu of options.

## Objective

Migrate 4Shark's Pritunl VPN gateway from its current single-EC2-VM deployment (Ansible-provisioned) to a containerized deployment on ECS, following the "Docker-image tool repository" standard already applied to `pgbouncer` and `keycloak`. The engineer has decided: a 4Shark-authored Dockerfile installing Pritunl's own official signed package, ECS on a single dedicated EC2 container instance (privileged + host networking), MongoDB on a **dedicated MongoDB VM separate from the Pritunl container** (not a sidecar), the existing Elastic IP reassociated to the new production instance, a **HubFlow branch model** (`develop`/`master`, mirroring `keycloak`) with a `-staging` Pritunl instance normally scaled to zero, the config-owning parts of the current Ansible role folded into the Dockerfile/entrypoint while host-only prep (kernel modules, device nodes, OS hardening) moves to the EC2 launch template and the MongoDB tasks move to the dedicated Mongo VM, and a cutover model that separates the **recurring** HubFlow staging→prod promotion flow from the **one-time** VM→ECS migration (parallel stand-up, state migration, pre-flip validation, a single maintenance-window EIP flip, old VM kept stopped for rollback). This document is the single execution path for those seven decisions, plus the newly-researched mechanisms needed to build it (the Renovate update loop for a self-built package image, Pritunl's own graceful-shutdown signal, the WireGuard host/container split, the HubFlow build/deploy shape mirrored from `keycloak`, and the EC2-backed staging scale-to-zero mechanism).

## Scope

### In scope

- A new `pritunl` tool repository conforming to `DOCKER-IMAGE-TOOL-REPOSITORIES.md`'s **HubFlow shape** (Dockerfile, Renovate custom-manager config + runner, hadolint CI, min-age gate, `develop`/`master` branches, per-target build-on-merge, deploy-on-demand)
- Terraform changes in the `terraform` repo: new ECS/EC2 resources for a **production** Pritunl instance and a **staging** Pritunl instance (normally at zero capacity), a **dedicated MongoDB VM**, security groups, IAM roles — replacing `terraform/vpn/` and `terraform/modules/pritunl/`, while reusing the existing `aws_eip` resource for production
- Retirement of `ansible/roles/4shark.pritunl/` config-owning tasks into the Dockerfile/entrypoint; retention of a thin host-prep responsibility (WireGuard kernel module, `/dev/net/tun`, base OS hardening) moved to the EC2 launch template / AMI / user-data; **retargeting** (not retirement) of the MongoDB-owning tasks to the dedicated Mongo VM
- Preservation of the current VPN's externally-observable behavior: fixed public IP (production), OpenVPN + WireGuard connectivity, `*.4shark.internal` DNS resolution for connected clients, per-IP brute-force protection, and the existing MongoDB-held org/user/profile state
- Governance: adding the new `pritunl` repo to `terraform/identity/github_repositories.tf`'s `local.hubflow_repositories` and (once CI produces the check) `local.hubflow_repositories_with_min_age_check` — **not** `local.main_branch_repositories` (superseded by the branch-model change); creating two per-target ECR repositories (`<environment>` and `<environment>-staging`)
- A recurring operational flow: merge to `develop` → staging image builds → `-staging` instance scaled up → validate → `git hf release` → `master` image builds → production deploy — the standing model for every future Pritunl version bump, distinct from the one-time VM migration

### Out of scope (decided out)

- VPN gateway high availability (multi-instance) for production — the engineer's decision keeps a single dedicated container instance per environment (production, staging), matching today's posture; not a goal of this migration
- MongoDB high availability (replica set) — the engineer's decision is a single dedicated Mongo VM (decision 3), not a replica set; matches the single-dedicated-instance posture applied to Pritunl itself
- Client-side rollout mechanics beyond the high-level cutover phases below (how individual engineers are notified/reconnect) — a communication-plan detail for the maintenance window, not an infrastructure decision

## Current architecture (what is being migrated away from)

- **Terraform stack**: `terraform/vpn/main.tf:10-27` instantiates `module.pritunl` with a fixed AMI, `t3a.micro`, in the management VPC's public subnet (`vpc-0bdc76f3b391694dd`, subnet `management-pub-a`), ports 14720 (OpenVPN) and 14721 (WireGuard).
- **Module** `terraform/modules/pritunl/main.tf:1-44`: a bare `aws_instance` with `lifecycle { ignore_changes = [ami, user_data, user_data_base64] }` (Ansible manages the OS post-boot, not Terraform), plus `aws_eip` (lines 32-39) + `aws_eip_association` (lines 41-44) giving the instance a static public IP.
- **IAM** `terraform/modules/pritunl/iam.tf:29-49`: the instance role grants `ec2:DescribeRouteTables`/`CreateRoute`/`ReplaceRoute`/`DeleteRoute` — Pritunl's own VPC route advertisement for the OpenVPN client subnets (confirmed by `terraform/modules/pritunl/README.md:111`: *"OpenVPN routes (100.80/16, 100.96/16) and client profiles are configured inside Pritunl directly — Terraform only provisions the EC2 instance, not the VPN configuration"*). This IAM shape carries forward unchanged onto the new production ECS-EC2 instance's role — the same binary, running as a container instead of a systemd service, still needs to advertise the same routes.
- **Ansible role** `ansible/roles/4shark.pritunl/tasks/main.yml:1-264` (full task list read this pass): disables the host's `systemd-resolved` DNS stub listener and symlinks `/etc/resolv.conf` (lines 12-25, a host-level DNS setup task, distinct from the VPN-client-forwarding dnsmasq block further down); installs MongoDB 8.0 from apt (lines 32-79); installs Pritunl + WireGuard from `repo.pritunl.com/stable/apt` **unpinned** (lines 83-113); configures logrotate for pritunl/mongod (115-131); installs and configures **dnsmasq** to forward VPN-client DNS queries to the VPC resolver for `*.4shark.internal` (133-187); sets Pritunl's Mongo URI/rate-limiting/auditing via `pritunl set-*` commands (191-201); installs **fail2ban** watching `/var/log/pritunl_journal.log` for `admin_auth_failure` events, banning the source IP (203-237); and retrieves/displays one-time setup credentials (241-263).
- **dnsmasq specifics**: `ansible/roles/4shark.pritunl/templates/dnsmasq-vpn.conf.j2:1-19` binds to the VPN virtual interface address (`pritunl_dnsmasq_listen_address`, set per-host in `ansible/playbooks/vars/pritunl/4shark-vpn-001.yml:6` to `10.149.176.1`) and forwards to the VPC DNS resolver (`10.255.0.2`, same file line 7); `dnsmasq-override.conf.j2:1-11` makes the systemd unit start `After=`/`Requires=pritunl.service` because dnsmasq cannot bind the VPN interface address until Pritunl has created it.
- **fail2ban specifics**: `ansible/roles/4shark.pritunl/templates/fail2ban-filter-pritunl.conf.j2:1-9` matches `admin_auth_failure` events in Pritunl's JSON audit log; `fail2ban-jail-pritunl.conf.j2:1-9` bans for 7 days (`pritunl_fail2ban_bantime: 604800`, `defaults/main.yml:30`) after a single failed attempt (`pritunl_fail2ban_maxretry: 1`, `defaults/main.yml:29`) — the per-IP protection layer, since Pritunl's own global rate limiter is deliberately disabled (`pritunl_auth_limiter_count_max: 999999`, `defaults/main.yml:22`, comment: *"Set to 999999 to effectively disable — per-IP protection is handled by fail2ban"*).
- **Ubuntu codename target**: `ansible/roles/4shark.pritunl/defaults/main.yml:9,18` — `pritunl_mongodb_ubuntu_codename: "noble"` and `pritunl_ubuntu_codename: "noble"`, i.e. Ubuntu 24.04 LTS. `defaults/main.yml:6` pins the currently-installed MongoDB line at `8.0`.

## Grounded external facts (verified, cited — not re-derived from training data)

- **No official Pritunl (VPN) Docker image exists.** Docker Hub's `pritunl` organization publishes only `pritunl/pritunl-zero` and `pritunl/pritunl-bastion` — confirmed by fetching `hub.docker.com/u/pritunl`: *"No, there is no official `pritunl` or `pritunl-vpn` image listed for the VPN server product. Only Pritunl Zero-related images are displayed on this organization page."*
- **Every container of Pritunl needs `privileged: true` (or explicit `/dev/net/tun` + capability grants) and host-loaded WireGuard kernel modules**, confirmed across community images' own documentation:
  - `github.com/jippi/docker-pritunl` docker-compose.yml: `privileged: true` on the `pritunl` service; README: *"If you don't want to use `network=host`, then replace the `--network=host` CLI flag with the following ports..."* — confirms host networking is the default-documented path.
  - `github.com/goofball222/pritunl` README/compose: `network_mode: bridge`, `privileged: true`, plus *"The Docker host is required to have wireguard kernel modules installed and loaded."*
  - Consistent with what the current Ansible role already does at the host level (`apt: name: [pritunl, wireguard, wireguard-tools]`, `tasks/main.yml:99-107`) — containerizing relocates where the *process* runs, not where the *kernel capability* lives. **This is the technical basis for the host/image split in the Ansible-task mapping below**: `wireguard` (kernel module, host-global — cannot be namespaced per-container) stays a host concern; `wireguard-tools` (the userspace CLI Pritunl's own process invokes) is just another apt package inside the image, same as `pritunl` itself.
- **AWS Fargate cannot satisfy this.** Fargate does not expose `privileged: true`, host kernel modules, or `network_mode: host` to a task. Corroborated indirectly: both existing 4Shark tool-repo precedents (`connection-pooler`/pgbouncer and `auth-001`/keycloak) run on Fargate (`terraform/modules/connection_pooler/main.tf:250-260` — `requires_compatibilities = ["FARGATE"]`; `terraform/auth-001/ecs.tf:22-27,41` — same) — meaning no existing 4Shark tool repo has already solved the privileged/host-network case; this migration is the first.
- **Amazon DocumentDB is explicitly unsupported by Pritunl as its database.** Fetched from `forum.pritunl.com/t/is-aws-documentdb-supported-as-a-database/1299`: *"Pritunl, Pritunl Zero and Pritunl Cloud all utilize capped collections and tailable cursors for publish subscribe messaging. This prevents using the MongoDB API compatible databases such as DocumentDB."* No fix timeline given — a hard blocker, ruling out DocumentDB entirely regardless of where MongoDB itself is placed (colocated sidecar in the first-pass draft, or the dedicated VM decided in this revision).
- **`modules/ecs_service` today has no privileged/host-network branch** — `terraform/modules/ecs_service/main.tf:14` — `network_mode = var.launch_type == "FARGATE" ? "awsvpc" : "bridge"` — EC2 launch type gets `bridge`, never `host`, and there is no `privileged` variable exposed anywhere in the module's `container_definitions` block (`main.tf:21-54`, no `privileged` key present). This module cannot be reused unmodified for this migration; the new task definition is either a bespoke `aws_ecs_task_definition` (as `modules/pritunl` today is a bespoke `aws_instance`, not a reuse of a generic module) or an extension to `ecs_service` adding a `privileged` variable and a `host` network-mode branch.
- **`modules/ecs_service` already supports a host-path-backed Docker volume** — `terraform/modules/ecs_service/main.tf:56-62` (`volume { host_path = try(volume.value.host_path, null) }`). This mechanism was the basis for the first-pass draft's colocated-MongoDB-sidecar design; it remains true infrastructure knowledge but is **no longer invoked by this migration** — decision 3 (revised) places MongoDB on a dedicated VM, not a sidecar container, so no `host_path` volume wiring is needed for Mongo on the Pritunl task definition.
- **`modules/ecs_capacity` is the existing ASG-backed EC2 capacity-provider module** (`terraform/modules/ecs_capacity/main.tf:1-102`) already used by the EC2-launch-type fleet (`app-outbound-*`, `integrator-*`, `onboarding`, `setup`); its `aws_launch_template` (lines 1-51) already carries `block_device_mappings` for the root volume (7-13) and a `user_data` block that registers the instance with the target ECS cluster (24-28: `echo ECS_CLUSTER=${var.cluster_name} >> /etc/ecs/ecs.config`). This `user_data` block is the concrete vehicle for the host-level prep the Ansible-task mapping moves out of the container (WireGuard kernel module load, `/dev/net/tun` presence, base OS hardening) — it is the same mechanism already in production, just extended with the additional bootstrap commands.
- **ECS managed scaling cannot cleanly scale a capacity-provider ASG from zero to one instance.** Fetched from `docs.aws.amazon.com/AmazonECS/latest/developerguide/cluster-auto-scaling.html`, verbatim: *"When Amazon ECS scales out from 0 instances, it automatically launches 2 instances."* This is the grounded reason the staging Pritunl host (decision 7) is not brought up via `ecs_capacity`'s managed-scaling-from-zero — see decision 7 below.
- **No existing 4Shark Terraform precedent for security-group-to-security-group scoping** (`referenced_security_group_id` / `source_security_group_id`) — confirmed by an empty repository-wide `grep -rn "source_security_group_id" terraform/` this pass. The current convention scopes ingress by VPC CIDR instead (`terraform/auth-001/security_groups.tf:11-23,41-47` — `aws_vpc_security_group_ingress_rule` with `cidr_ipv4 = "10.255.0.0/16"`). The dedicated Mongo VM security group (decision 3) is the first place this codebase would need SG-to-SG scoping if it follows the engineer's "ONLY the Pritunl instance" wording literally.
- **No existing 4Shark Terraform module for a generic bare `aws_instance` VM** beyond `terraform/modules/pritunl` itself — confirmed by grepping every `terraform/modules/*/main.tf` for `aws_instance` this pass; every other stateful/tool module (`connection_pooler`, `rds_instance`, `rds_aurora_cluster`, `mongodb_atlas`) is either Fargate-based or a managed-service resource, not a bare EC2 instance. The dedicated Mongo VM (decision 3) is provisioned the same way the current combined VM already is — a bare `aws_instance`, Ansible-managed post-boot — there is no closer-fitting existing module to reuse.
- **`terraform/identity/github_repositories.tf:60-75`** — `local.hubflow_repositories` currently lists `ansible`, `app`, `app-mobileclient`, `app-sdk-advpl`, `app-sdk-dotnet`, `app-webclient`, `dot-claude`, `integrator`, `keycloak`, `lambda`, `onboarding`, `setup`, `simplex-harvester`, `terraform`; **`:81-91`** — `local.hubflow_repositories_with_min_age_check` lists `ansible`, `app`, `app-webclient`, `integrator`, `keycloak`, `lambda`, `onboarding`, `setup`, `terraform`. `pritunl` is added to both, following `keycloak`'s presence in each.
- **`terraform/auth-001/ecr.tf:1-29`** — confirms `keycloak`'s branch-model shape uses **two separate ECR repositories**, not one shared repo: `aws_ecr_repository.auth_001` (name `"auth-001"`) and `aws_ecr_repository.auth_001_staging` (name `"auth-001-staging"`), each with identical scanning/encryption config. The new Pritunl repos follow the same two-repository shape.
- **`terraform/auth-001/auth_001_staging.tf:1-194`** (full file read this pass) — the existing 4Shark precedent for a non-productive validation instance: `aws_ecs_service.auth_001_staging` runs `desired_count = 0` (line 152) on **Fargate** capacity (`capacity_provider_strategy { capacity_provider = "FARGATE" }`, lines 154-158), reusing the production cluster, VPC, security groups, ALB, and RDS instance, isolated only by its own database, hostname, target group, and log group (file header comment, lines 1-11). Because Fargate has no separate EC2 host to also stop, a desired-count-0 Fargate service carries no idle compute cost — this property does **not** transfer to Pritunl's EC2-backed runtime (decision 2), which is the basis for decision 7's staging-instance mechanism finding below.
- **`terraform/auth-001/security_groups.tf:11-23,41-47`** — the current 4Shark security-group convention: `aws_vpc_security_group_ingress_rule` resources scoped by VPC CIDR (`10.255.0.0/16`), used even for RDS access (`rds_postgres` rule, lines 41-47) rather than security-group-to-security-group references.

## Chosen architecture

Seven decisions total. (1), (2), and (4) are unchanged from the first-pass draft (reused verbatim, citations preserved). (3), (5), (6), and (7) are revised in this pass — the engineer changed MongoDB placement, the branch model, and the cutover/deploy model; (6) is rewritten because the MongoDB-owning Ansible tasks now target a third home (the Mongo VM) instead of the Pritunl image.

### 1. Base image — 4Shark-authored Dockerfile from Pritunl's own official apt repo

**Choice (unchanged):** `FROM ubuntu:24.04` (noble — matches the Ansible role's current target, `ansible/roles/4shark.pritunl/defaults/main.yml:9,18`), add Pritunl's own signed apt repo (`repo.pritunl.com/stable/apt`, same source as `ansible/roles/4shark.pritunl/tasks/main.yml:93-97`), install the official `pritunl` `.deb` pinned via a Dockerfile `ARG PRITUNL_VERSION`. Not a community image (jippi/goofball222/omegion).

**Rationale:** the community images all carry an unofficial supply-chain dependency on a single external maintainer; a self-built image from Pritunl's own signed repo matches the trust model 4Shark already runs today (the Ansible role installs from the same source) and matches `pgbouncer`'s and `keycloak`'s pattern of a 4Shark-owned Dockerfile rather than a vendored community image.

**The auto-update loop for a self-built package image (researched, unchanged from the first pass):** the `DOCKER-IMAGE-TOOL-REPOSITORIES.md` standard's item 2 assumes a `FROM upstream/image:<tag>@sha256:<digest>` — Renovate's `docker` datasource tracks a base-image tag directly. An apt-installed `.deb` has no such tag for that datasource to read. Renovate's own regex custom-manager docs describe exactly this gap: a comment-annotated `ARG`/`ENV` line paired with a non-Docker datasource. Fetched from `docs.renovatebot.com/modules/manager/regex/` (Advanced Capture section), verbatim:
  ```
  # renovate: datasource=github-releases depName=composer packageName=composer/composer
  ENV COMPOSER_VERSION=1.9.3
  ```
  with the matching `matchStrings` regex:
  ```
  "# renovate: datasource=(?<datasource>[a-z-]+?)(?: depName=(?<depName>.+?))? packageName=(?<packageName>.+?)(?: versioning=(?<versioning>[a-z-]+?))?\\s(?:ENV|ARG) .+?_VERSION=(?<currentValue>.+?)\\s"
  ```
  This is directly reusable for the Pritunl Dockerfile: annotate `ARG PRITUNL_VERSION=<pinned>` with `# renovate: datasource=github-releases packageName=pritunl/pritunl`, and add a `customManagers` block to `renovate.json` using that `matchStrings` pattern (`managerFilePatterns: ["/^Dockerfile$/"]`, `datasourceTemplate: "github-releases"`). The `github-releases` datasource resolves `releaseTimestamp` from the GitHub release's own publish date, so the 7-day `minimumReleaseAge` quarantine computes normally — no exemption needed (unlike the GHA-digest case, which cannot compute a timestamp at all).
  **Version-scheme caveat (unchanged, still unresolved this pass)**: fetching `github.com/pritunl/pritunl/releases` shows tags of the shape `pritunl v1.34.4681.89`, `pritunl v1.34.4649.96`, `pritunl v1.32.4567.52` — a four-numeric-field scheme (`major.minor.build.patch`), not three-field semver. `edoburu/pgbouncer` hit the same class of problem with its `-pN` build suffix and needed an explicit `versioning: regex:...` override (`pgbouncer/renovate.json:11-16`) because Renovate's default versioning would not order/cross a non-semver suffix. The Pritunl `ARG` custom manager likely needs the same treatment — flagged as a pre-implementation verification item (see Residual open items), unchanged from the first pass.

**Source patterns referenced:**
- `ansible/roles/4shark.pritunl/tasks/main.yml:83-107` — today's unpinned apt-install source, now pinned via `ARG`
- `pgbouncer/Dockerfile:1-32` — the tag+digest pin + Renovate-tracking comment pattern (adapted here for a custom-manager annotation instead of a `FROM` tag, since there is no upstream Docker image)
- `pgbouncer/renovate.json:11-16` — the precedent for a per-package `versioning: regex:` override when the upstream tag scheme is non-semver
- [docs.renovatebot.com/modules/manager/regex/](https://docs.renovatebot.com/modules/manager/regex/) — the `datasource=github-releases` + `ENV/ARG ..._VERSION=` comment-annotation pattern, quoted verbatim above
- [github.com/pritunl/pritunl/releases](https://github.com/pritunl/pritunl/releases) — confirms the `v1.34.4681.89`-style four-field tag scheme

### 2. Runtime / launch type — ECS on EC2, single dedicated container instance (per environment)

**Choice (unchanged):** ECS on EC2 (Fargate ruled out — grounded fact above). A single dedicated ECS container instance, `privileged: true` + host networking, WireGuard kernel modules present on the host. No HA / multi-instance within an environment.

**Rationale:** Fargate structurally cannot grant `privileged`/host-network/kernel-module access every community image documents as required. A single instance matches today's posture (one `t3a.micro` VM) — HA was explicitly decided out of scope. **Updated framing (this pass)**: "single dedicated instance" now applies **per environment** — the production Pritunl instance and the `-staging` Pritunl instance (decision 7) are each their own single dedicated instance, never sharing a host, never load-balanced; the HubFlow branch model (decision 5) adds a second environment, it does not change the no-HA-within-an-environment posture.

**Source patterns referenced:**
- `terraform/modules/ecs_service/main.tf:14` — confirms EC2 launch type today only ever gets `bridge`, never `host`, and no `privileged` variable exists — new Terraform work is required (bespoke task definition or an `ecs_service` extension)
- `terraform/modules/ecs_capacity/main.tf:1-102` — the reusable ASG-backed EC2 capacity-provider module, directly reusable for a single dedicated instance (subject to decision 7's finding about scale-from-zero for the staging instance specifically)
- `terraform/modules/connection_pooler/main.tf:250-260`, `terraform/auth-001/ecs.tf:22-27,41` — confirm no existing 4Shark tool repo has solved the privileged/host-network case (both existing tool repos are Fargate)

### 3. MongoDB — dedicated MongoDB VM, separate from the Pritunl container

**Choice (revised this pass):** MongoDB runs on a **dedicated MongoDB EC2 VM**, separate from the Pritunl ECS container — not a colocated sidecar (the first-pass draft's choice), not DocumentDB (hard blocker, unchanged). The Pritunl container is stateless; the Pritunl ECS instance reaches the Mongo VM over the VPC (private, not publicly exposed). State migration: `mongodump` on the current combined VM → `mongorestore` into the new dedicated Mongo VM.

**Rationale:** separating Mongo from the Pritunl container removes state from the ECS task entirely — a Pritunl container replacement (image bump, task restart, host replacement) no longer carries risk to the database, and the Mongo VM's own lifecycle (patching, backup, resizing) is decoupled from Pritunl's own release cadence. This also keeps MongoDB's install/config shape exactly as it is today (a real VM running a systemd-managed `mongod`, per the current Ansible role), rather than re-platforming it into a container as the first-pass sidecar draft would have required.

**MongoDB install/config placement — does NOT move into the Pritunl image.** Two paths were surfaced (execution-time implementation detail, not one of the seven fixed decisions):
- **Trimmed Ansible role, targeting the Mongo VM (recommended path — reuses currently-tested tasks unchanged in shape):** extract the MongoDB-only portion of `ansible/roles/4shark.pritunl/tasks/main.yml:32-79` (apt-repo/key/install, `mongod.conf` templating, systemd enable/start) into its own role (exact name/location not decided — e.g. a new `ansible/roles/4shark.mongodb-pritunl`, or a parameterized re-run of a trimmed `4shark.pritunl` role against the Mongo VM's inventory group), pointed at the new Mongo VM instead of the combined VM. Since a VM running systemd-managed `mongod` is exactly what these tasks already provision, this path needs no adaptation to the tasks themselves — only a new inventory target.
- **Alternative (not favored, surfaced for completeness):** author fresh provisioning for the Mongo VM from scratch (different config-management tooling, hand-rolled scripts, Terraform-only user-data). Not favored because it discards currently-tested, currently-running install/config logic for no compensating benefit — the Mongo VM's provisioning need is identical in shape to what the existing role already does, just retargeted.

**Network isolation:** a dedicated security group restricts ingress on MongoDB's port to ONLY the Pritunl ECS instance. This is narrower than 4Shark's current security-group convention (`terraform/auth-001/security_groups.tf:11-23,41-47` — CIDR-scoped by VPC range, not by security-group reference), and no existing precedent for security-group-to-security-group scoping was found in this codebase (grounded fact above). Flagged as a new pattern this migration would introduce, not an existing one — the exact mechanism (`referenced_security_group_id` on `aws_vpc_security_group_ingress_rule`, vs. a narrowed CIDR to the Pritunl instance's private IP) is an execution-time Terraform-authoring decision.

**State migration:** `mongodump` on the current combined VM's MongoDB → `mongorestore` into the new dedicated Mongo VM, unchanged in position within the cutover flow (Phase 3 below) from the first-pass draft.

**Source patterns referenced:**
- `forum.pritunl.com/t/is-aws-documentdb-supported-as-a-database/1299` — the DocumentDB blocker, quoted above, unchanged and still applicable regardless of Mongo's placement
- `ansible/roles/4shark.pritunl/tasks/main.yml:32-79` — today's self-managed MongoDB apt-install/config/systemd tasks, the basis for the recommended trimmed-Ansible-role path
- `ansible/roles/4shark.pritunl/defaults/main.yml:6` — `pritunl_mongodb_version: "8.0"`, carried forward unchanged to the Mongo VM
- `terraform/auth-001/security_groups.tf:11-23,41-47` — the current 4Shark ingress convention (CIDR-scoped, `aws_vpc_security_group_ingress_rule`), the base pattern the new dedicated Mongo SG departs from
- No existing 4Shark Terraform precedent for `referenced_security_group_id`/SG-to-SG scoping (confirmed by an empty repository-wide grep this pass) — flagged, not asserted as an existing pattern

### 4. Public entry — reassociate the existing Elastic IP (production only)

**Choice (unchanged):** Reassociate the existing `aws_eip` allocation (from `terraform/modules/pritunl/main.tf`) to the new **production** ECS-EC2 instance, preserving the fixed public IP so client `.ovpn`/WireGuard profiles need no change. No NLB.

**Rationale:** the EIP allocation is a distinct AWS resource from the instance and survives instance replacement when re-associated — reusing it needs zero client reconfiguration. Under host networking, the container shares the instance's network stack, so the association is instance-level (`aws_eip_association` against the new `aws_instance`, same shape as today), not an ENI belonging to a task. **Scope note (this pass):** this decision covers the production instance only. The `-staging` instance introduced by decision 7 does not get the production EIP; its own public-entry mechanism during a test window is a residual open item (see below).

**Source patterns referenced:**
- `terraform/modules/pritunl/main.tf:32-39` (`aws_eip`) and `:41-44` (`aws_eip_association`) — the exact resource shape to carry forward, re-targeting `instance_id`/`allocation_id` at the new production instance

### 5. Branch model — HubFlow (`develop`/`master`), mirroring `keycloak`

**Choice (revised this pass):** HubFlow, not main-only. `develop` builds the **staging** Pritunl image → the `-staging` ECS instance; `master` builds the **production** Pritunl image → the production ECS instance. A release promotes `develop` → `master` via `git hf release start/finish X.Y.Z`; the tag is the side effect of `finish` (not a manual `git tag`). The repo is still named `pritunl`.

**Rationale:** the engineer's revised decision reverses the first-pass main-only choice specifically to gain a non-production instance to validate a new Pritunl image before it reaches the VPN gateway every engineer depends on — the exact condition `DOCKER-IMAGE-TOOL-REPOSITORIES.md` names for the HubFlow shape: *"HubFlow — develop + master (the 4Shark GitFlow), for an actively-versioned tool that validates each new image on a non-production instance before production. Reference: keycloak."* (`~/.claude/docs/DOCKER-IMAGE-TOOL-REPOSITORIES.md:18`).

**Governance:** add `pritunl` to `local.hubflow_repositories` (`terraform/identity/github_repositories.tf:60-75`, where `keycloak` already appears) and to `local.hubflow_repositories_with_min_age_check` (`:81-91`, where `keycloak` already appears) once the repo's CI produces the `Verify Minimum Age` check — **not** `local.main_branch_repositories` (the first-pass draft's now-superseded governance target).

**Build/deploy shape mirrors `keycloak` exactly** (`keycloak/.github/workflows/build.yaml:1-108`, `deploy.yaml:1-101`, both read in full this pass):
- `build.yaml` triggers on `push: branches: [develop, master]` plus `workflow_dispatch` with an `environment` choice input; one explicit job per target (staging / production), each pushing `:latest` + `:<short-sha>` to that target's own ECR repository using that target's GitHub Environment credentials. Verbatim from keycloak's own header comment: *"develop builds the staging image (auth-001-staging), master builds the production image (auth-001). One explicit job per target"* (`keycloak/.github/workflows/build.yaml:4-5`).
- `deploy.yaml` is a separate, manual `workflow_dispatch` — build and deploy are decoupled (`DOCKER-IMAGE-TOOL-REPOSITORIES.md` item 7, identical for both branch shapes) — `aws ecs update-service --force-new-deployment` against a per-target cluster/service/task-family map, then a poll loop waiting for `rolloutState == COMPLETED` (`keycloak/.github/workflows/deploy.yaml:31-35,59-100`).
- **Two separate per-target ECR repositories**, not one shared repo — `terraform/auth-001/ecr.tf:1-29`: `aws_ecr_repository.auth_001` (name `"auth-001"`) and `aws_ecr_repository.auth_001_staging` (name `"auth-001-staging"`). The Pritunl repo follows the same shape: two ECR repositories, one per target.

**Source patterns referenced:**
- `~/.claude/docs/DOCKER-IMAGE-TOOL-REPOSITORIES.md:13-20` — the "Two repo shapes" section, the condition for choosing HubFlow over main-only
- `~/.claude/docs/DOCKER-IMAGE-TOOL-REPOSITORIES.md:26-31` (item 1 HubFlow variant), `:66-71` (item 6 HubFlow variant), `:89-104` (item 10 HubFlow variant) — every HubFlow-variant note in the standard, read in full this pass
- `keycloak/.github/workflows/build.yaml:1-108` — full build workflow, quoted above
- `keycloak/.github/workflows/deploy.yaml:1-101` — full deploy workflow
- `terraform/auth-001/ecr.tf:1-29` — the two-ECR-repo pattern
- `terraform/identity/github_repositories.tf:60-75` (`local.hubflow_repositories`), `:81-91` (`local.hubflow_repositories_with_min_age_check`) — governance lists `pritunl` is added to instead of the main-branch lists

### 6. Ansible role fate — config into image/entrypoint; host-only prep into the launch template; MongoDB tasks into the dedicated Mongo VM

**Choice (revised this pass — now a three-target split):** the Pritunl-container-owned config (dnsmasq, fail2ban, Pritunl's own `set-*` commands, install) moves into the Dockerfile + `configured-entrypoint.sh`, unchanged from the first-pass draft. Host-only kernel prep (WireGuard kernel module, `/dev/net/tun`, base OS hardening) moves to the EC2 launch template / AMI / user-data, unchanged. **Changed**: the MongoDB tasks (`tasks/main.yml:32-79`) no longer move into a sidecar image — they retarget to the dedicated Mongo VM (decision 3), via the recommended trimmed-Ansible-role path.

**Rationale:** the Pritunl/host split is unchanged from the first pass — `privileged: true` + host networking (decision 2) still gives the Pritunl container the same network-namespace/iptables reach dnsmasq and fail2ban need, so both stay co-located with Pritunl. The MongoDB split is new: since Mongo now lives on its own VM rather than inside a container, its provisioning responsibility maps most naturally onto the same mechanism the current combined VM already uses for it (Ansible + systemd) — retargeted, not re-platformed.

See the full three-target mapping table below, redone this pass for the image / ECS host / Mongo VM split.

### 7. Cutover / deploy model — a recurring HubFlow staging→prod flow, distinct from the one-time VM→ECS migration

**Choice (revised this pass):** two ECS "processes" going forward — a production Pritunl ECS instance (always on) and a `-staging` Pritunl ECS instance (normally at zero capacity, brought up only for a test window). The **recurring** operational flow once the repo/infra exist: merge to `develop` → staging image builds (decision 5) → `-staging` instance scaled up → validate → `git hf release` → `master` image builds → production deploy. This is distinct from the **one-time** VM→ECS migration: stand up the new production ECS instance + Mongo VM in parallel with the still-running current combined VM, migrate state (`mongodump`/`mongorestore`), validate on a temporary IP, then flip the existing EIP from the old VM to the production instance's ENI in a single maintenance window; the old combined VM is kept stopped (not terminated) afterward, as a rollback path.

**Rationale:** this decision separates two different kinds of "cutover" the first-pass main-only draft conflated into a single maintenance-window event: (1) the *recurring* staging→prod promotion every future Pritunl image change goes through (the HubFlow flow decision 5 established), and (2) the *one-time* migration off the current combined VM entirely. Conflating them would mean every routine version bump re-runs a maintenance-window/EIP-flip procedure that should only ever happen once. The recurring flow's own validation step is the `-staging` instance itself; the one-time migration keeps its own pre-flip parallel-validation step because the EIP flip is a one-off event with no equivalent in the recurring flow — once the one-time cutover is done, neither `develop` nor `master` deploys ever touch the EIP again.

**How the `-staging` instance is scaled to zero (implementation detail, researched this pass — not one of the seven fixed decisions on its own, but load-bearing for decision 7):** the engineer's language cites the connection-pooler/authenticators skills' pattern (`ecs-scale.sh`, desired_count 0/1). That pattern was built for **Fargate** services (`terraform/auth-001/auth_001_staging.tf:148-194` — `aws_ecs_service.auth_001_staging` at `desired_count = 0`, Fargate capacity), where a desired-count-0 service carries zero compute cost — there is no separate EC2 host to also stop. Pritunl's runtime (decision 2, EC2 with `privileged` + host networking, unchanged) does not have that property: an EC2-backed ECS service at desired_count=0 still leaves its underlying EC2 host running (and billing) unless the host itself is also stopped. Two candidate mechanisms were surfaced:
- **Stop/start the dedicated EC2 host directly** (`~/.claude/scripts/stop-instance.sh` / `start-instance.sh`, the existing 4Shark wrapper scripts), alongside `ecs-scale.sh` for the ECS service itself. This keeps the staging Pritunl instance a plain dedicated instance, mirroring decision 2's own "single dedicated instance" framing, rather than an autoscaled fleet member.
- **`ecs_capacity` module's ASG-backed capacity provider with `min_size = 0`** (`terraform/modules/ecs_capacity/main.tf:53-102`), relying on ECS managed scaling to launch/terminate the host automatically as the service's desired_count changes — this would let `ecs-scale.sh` alone drive both the service and the host, uniformly with the Fargate-based skills. **Ruled out by a grounded AWS-documented behavior**: fetched from `docs.aws.amazon.com/AmazonECS/latest/developerguide/cluster-auto-scaling.html`, verbatim: *"When Amazon ECS scales out from 0 instances, it automatically launches 2 instances."* A scale-from-zero event on the staging capacity provider would launch **two** EC2 hosts for a single Pritunl task that host networking limits to one task per host anyway — doubling the staging bring-up cost and instance count for no benefit, and diverging from decision 2's "single dedicated instance" framing.

This finding rules out the ASG-managed-scaling-from-zero path as the mechanism for staging; the direct stop/start path does not have this failure mode and is the path the execution phases below assume, pending final engineer sign-off at Terraform-authoring time.

**Source patterns referenced:**
- `terraform/auth-001/auth_001_staging.tf:1-194` (full file read this pass) — the Fargate desired-count-0 staging pattern the engineer's language references, and why it does not transfer unmodified to an EC2-backed instance
- `~/.claude/skills/authenticators/SKILL.md:17,70-90` — the existing scale-up/scale-down skill behavior for a staging authenticator instance, the direct precedent cited by the engineer
- `~/.claude/scripts/ecs-scale.sh:1-63` — the existing `aws ecs update-service --desired-count` wrapper, reused for the ECS-service half of staging bring-up/down regardless of which host mechanism is chosen
- `terraform/modules/ecs_capacity/main.tf:53-102` — the ASG-backed capacity-provider module and its managed-scaling configuration, the ruled-out alternative
- [docs.aws.amazon.com/AmazonECS/latest/developerguide/cluster-auto-scaling.html](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/cluster-auto-scaling.html) — *"When Amazon ECS scales out from 0 instances, it automatically launches 2 instances."* — fetched and quote-verified this pass

## Ansible-task → new-home mapping (redone this pass for the three-target world)

Exhaustive, one row per current task/responsibility in `ansible/roles/4shark.pritunl/tasks/main.yml:1-264`. "IMAGE" = Dockerfile or `configured-entrypoint.sh`; "HOST" = the Pritunl ECS launch template / custom AMI / user-data; "MONGO VM" = the new dedicated MongoDB VM (decision 3); "DROPPED" = no longer needed under the new architecture; "CUTOVER" = a one-off step in the cutover runbook, not a recurring host/image/VM responsibility.

| Current task (file:line) | New home | Why |
|---|---|---|
| Disable systemd-resolved DNS stub listener; symlink `/etc/resolv.conf` (`tasks/main.yml:12-25`) | **HOST** (Pritunl ECS host) | Generic host-level DNS bootstrap, structurally separate from the VPN-client-forwarding dnsmasq block further down. Not specific to VPN-client forwarding; folds into the Pritunl host launch-template/AMI "base OS hardening" bucket. Unrelated to MongoDB's placement — no change from the first pass |
| MongoDB apt-repo key, repo, install (`tasks/main.yml:32-61`) | **MONGO VM** *(changed — was IMAGE/sidecar in the first pass)* | Now the dedicated Mongo VM's own provisioning, via the recommended trimmed-Ansible-role path (decision 3). Version carried forward unchanged: `pritunl_mongodb_version: "8.0"` (`defaults/main.yml:6`) |
| Configure MongoDB (`mongod.conf` template, `tasks/main.yml:63-70`) | **MONGO VM** *(changed — was IMAGE/sidecar entrypoint)* | Config materialization via the same Ansible template task, retargeted to the Mongo VM's inventory entry — no adaptation to the task itself is needed |
| Enable/start `mongod` via systemd (`tasks/main.yml:72-76`) | **MONGO VM** *(changed — was IMAGE `CMD`/`ENTRYPOINT` in the first pass)* | The systemd unit concept fully applies again, since MongoDB now runs on a real VM, not inside a container — this task needs no rewrite at all, only a retargeted host |
| Pritunl apt-repo key, repo, install of `pritunl` (`tasks/main.yml:83-98`) | **IMAGE** | The pinned-version Dockerfile install — see decision 1. Unchanged |
| Apt install of `wireguard-tools` (userspace CLI, part of `tasks/main.yml:99-107`) | **IMAGE** | Userspace tooling Pritunl's own process invokes — just another apt package inside the image. Unchanged |
| WireGuard kernel module load/presence (implied by `tasks/main.yml:99-107`'s `wireguard` package) | **HOST** (Pritunl ECS host) | Kernel modules are host-global, not per-container-namespaceable. Confirmed by `github.com/goofball222/pritunl`'s README: *"The Docker host is required to have wireguard kernel modules installed and loaded."* Unchanged |
| `/dev/net/tun` device-node presence | **HOST** (Pritunl ECS host) | Device node must exist on the host for a privileged container to access it. Unchanged |
| Enable/start `pritunl` via systemd (`tasks/main.yml:109-113`) | **IMAGE** (container `CMD`/`ENTRYPOINT` + `STOPSIGNAL`) | Replaced by Docker's process model; the graceful-shutdown signal is researched in Residual open items. Unchanged |
| Logrotate for pritunl (`tasks/main.yml:117-131`, pritunl portion) | **DROPPED** | Replaced by the `awslogs` ECS log driver + CloudWatch Logs retention, matching the pgbouncer/connection-pooler pattern — file-based logrotate is unnecessary once Pritunl's logs go to stdout/stderr inside the ECS task. Unchanged |
| Logrotate for mongod (`tasks/main.yml:117-131`, mongod portion) | **MONGO VM** *(changed — was fully DROPPED alongside pritunl's logrotate in the first-pass sidecar draft)* | MongoDB is once again a systemd-managed process on a real VM, where file-based logrotate is the same appropriate mechanism it is today — this task carries forward unchanged, just retargeted |
| dnsmasq install + VPN-DNS-forwarding config (`tasks/main.yml:138-152`, `templates/dnsmasq-vpn.conf.j2:1-19`) | **IMAGE** (`configured-entrypoint.sh`, co-located with Pritunl) | Host networking (decision 2) means the container shares the host's network namespace, so dnsmasq inside the container can still bind the VPN virtual interface Pritunl creates, exactly as it does today from the host. Unchanged |
| dnsmasq logrotate (`tasks/main.yml:154-160`) | **DROPPED** | Same reasoning as pritunl's own logrotate above. Unchanged |
| dnsmasq systemd override forcing `After=`/`Requires=pritunl.service` (`tasks/main.yml:162-177`, `templates/dnsmasq-override.conf.j2:1-11`) | **IMAGE** (entrypoint ordering) | Replaced by an equivalent wait-loop inside `configured-entrypoint.sh`: start Pritunl, poll for the VPN virtual interface to appear, then start dnsmasq bound to that address. **Still the single highest-risk mapping in this table** — see Risks below. Unchanged |
| `pritunl set-mongodb` / rate-limit / auditing (`tasks/main.yml:191-201`) | **IMAGE** (`configured-entrypoint.sh`) *(detail changed)* | Config materialization at container start, direct parallel to pgbouncer's `configured-entrypoint.sh` pattern — but the Mongo URI now points at the **dedicated Mongo VM's private address over the VPC** instead of a local/sidecar hostname, and requires the new dedicated security group (decision 3) to actually permit the connection. This is the new Pritunl↔Mongo-VM network dependency flagged in Risks below |
| fail2ban install + filter + jail config (`tasks/main.yml:203-228`, `templates/fail2ban-filter-pritunl.conf.j2:1-9`, `fail2ban-jail-pritunl.conf.j2:1-9`) | **IMAGE** (`configured-entrypoint.sh`, co-located with Pritunl) | fail2ban needs to (a) read Pritunl's own JSON audit log and (b) manipulate the host's real netfilter/iptables rules to ban an IP; co-locating it inside the same privileged, host-networked container satisfies both without a bind-mount. Unchanged |
| Enable/start fail2ban via systemd (`tasks/main.yml:230-234`) | **IMAGE** (entrypoint-managed background process) | systemd unit concept does not apply; entrypoint starts it as a supervised background process alongside Pritunl and dnsmasq. Unchanged |
| Get/display initial setup credentials (`tasks/main.yml:241-263`) | **CUTOVER** | A one-time bootstrap step, run once against the new stack during the cutover phase (via ECS Exec or `docker exec`), not baked into the image, host, or Mongo VM, and not re-run on every deploy. Unchanged |
| Ansible handlers — restart systemd-resolved / dnsmasq / fail2ban | **DROPPED** | Ansible handler mechanics with no image/container equivalent — config changes at container start are applied by the entrypoint directly. Unchanged |
| Ansible handler — restart mongod | **MONGO VM** *(changed — was DROPPED in the first-pass sidecar draft)* | The Mongo VM is systemd-based again, so the "restart on notify" indirection this handler provides is valid there, unlike inside a container — carried forward unchanged, retargeted to the Mongo VM's inventory |

## Technical decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Base image | 4Shark-authored Dockerfile, official Pritunl apt repo, `ARG PRITUNL_VERSION` pin | Matches today's trust source; avoids a third-party community image as the supply-chain root for the VPN gateway every engineer depends on. **Unchanged** |
| Renovate update mechanism | `customManagers` regex block, `datasource=github-releases`, `packageName=pritunl/pritunl`, annotating the Dockerfile `ARG` | The only Renovate mechanism that can track a version with no `FROM <tag>` to read. **Unchanged** |
| Runtime / launch type | ECS on EC2, single dedicated container instance per environment, `privileged: true` + host networking | Fargate structurally cannot grant privileged/host-network/kernel-module access; single instance matches today's posture (HA explicitly out of scope), now applied per environment. **Unchanged, reframed for two environments** |
| MongoDB | **Dedicated MongoDB VM, separate from the Pritunl container** | DocumentDB is a hard blocker; a dedicated VM removes database state from the ECS task's lifecycle entirely and keeps Mongo's provisioning shape identical to today's. **Changed — was a colocated EBS-backed sidecar** |
| Public entry (production) | Reassociate the existing `aws_eip` to the new production instance | Same resource, re-targeted association — zero client reconfiguration. **Unchanged** |
| Branch model | **HubFlow (`develop`/`master`), mirroring `keycloak`** | Gains a non-production `-staging` instance to validate a new Pritunl image before it reaches the production VPN gateway. **Changed — was main-only** |
| dnsmasq / fail2ban placement | Both co-located inside the Pritunl image/entrypoint (not host-level services) | `privileged` + host networking (decision 2) already grants the network-namespace and iptables access both need. **Unchanged** |
| WireGuard kernel module / `/dev/net/tun` | Host launch template / AMI / user-data | Kernel modules and device nodes are host-global — a container cannot supply them for itself. **Unchanged** |
| MongoDB install/config | Recommended: trimmed Ansible role, retargeted to the Mongo VM | Reuses currently-tested tasks in their current shape, just retargeted. **New this pass** |
| Cutover | Recurring HubFlow staging→prod flow (ongoing) + a separate one-time VM→ECS migration (parallel stand-up, `mongodump`/`mongorestore`, pre-flip validation, single-window EIP flip, old VM stopped for rollback) | Conflating the recurring promotion flow with the one-time migration would re-run a maintenance-window/EIP-flip procedure on every routine version bump. **Changed — was a single maintenance-window model with no recurring flow** |

## Risks (cross-cutting)

Reordered this pass to lead with the dnsmasq/fail2ban/EIP/MongoDB risks per the engineer's explicit ordering request; the Renovate risk follows.

| Risk | Impact | Possible mitigation |
|------|--------|---------------------|
| **dnsmasq DNS forwarding for `*.4shark.internal`** depends on binding the VPN virtual interface only after Pritunl creates it (`ansible/roles/4shark.pritunl/templates/dnsmasq-override.conf.j2:1-11` — `After=`/`Requires=pritunl.service`). The chosen mapping replaces this systemd-level ordering with a hand-written wait-loop inside `configured-entrypoint.sh` (poll for the interface, then start dnsmasq) — a weaker guarantee than a declarative systemd dependency, and the single highest-risk item in the Ansible-task mapping | If the wait-loop is wrong (races, wrong interface name, insufficient poll interval), connected VPN clients silently lose internal DNS resolution — a regression that may not surface until an engineer tries to reach an internal hostname, well after the cutover appears successful | Validate internal-hostname resolution from a connected test client explicitly during the pre-flip parallel-validation step (cutover phase) AND during every `-staging` validation window under the recurring HubFlow flow — not only after the production EIP flips; consider a `healthcheck`-gated startup order rather than a bare sleep-poll loop, to fail loudly instead of silently if the interface never appears |
| **fail2ban per-IP protection** now runs inside the same container as Pritunl, relying on `privileged`+host-networking to reach the host's real iptables and reading the audit log from the local (container) filesystem. Pritunl's own global rate limiter is deliberately disabled today specifically because fail2ban carries this responsibility (`pritunl_auth_limiter_count_max: 999999`, `defaults/main.yml:22`) | If the co-located fail2ban fails to actually reach the host's iptables (an assumption about host-networking + privileged mode's iptables-namespace-sharing behavior that was reasoned from Docker's documented networking model, not independently load-tested against this exact image), the admin auth endpoint has no brute-force protection at all — with Pritunl's own limiter also off | Confirm fail2ban's bans are visible in the HOST's own `iptables -L` (not just the container's) as part of the pre-flip validation step and every `-staging` validation window; keep the option of re-enabling Pritunl's own `app.auth_limiter_count_max` as an interim safeguard if the co-located fail2ban does not work as reasoned |
| **EIP pinning** — every engineer's `.ovpn`/WireGuard client profile is configured against the current production public IP | An uncoordinated IP change locks every engineer out of private infrastructure simultaneously, including infrastructure needed to fix the VPN itself | Reassociate the existing EIP allocation (decision 4) rather than provisioning a new one; the pre-flip parallel-validation step uses a temporary second IP specifically so the real EIP only moves once the new production stack is proven working. The `-staging` instance never touches the production EIP at all (residual open item below covers its own entry point) |
| **MongoDB state migration and the new Pritunl↔Mongo-VM network dependency** — org/users/VPN profiles, dynamic OpenVPN routes exist only inside Pritunl's own database (confirmed by `terraform/modules/pritunl/README.md:111`), AND (new this pass) the Pritunl container's own runtime now depends on network reachability to a separate host for every database operation, where the first-pass sidecar draft had them on the same instance | A failed or incomplete `mongodump`/`mongorestore` during cutover means real client accounts and routes are lost, not just re-derivable configuration. Separately, ANY disruption to the Pritunl↔Mongo-VM network path (security-group misconfiguration, VPC routing change, Mongo VM downtime) now takes down the whole VPN gateway even if the Pritunl container itself is healthy — a new failure mode the colocated sidecar design did not have | Treat the Mongo migration as the highest-scrutiny step of the one-time cutover; validate restored state (user count, route entries) against the source before decommissioning the old combined VM; keep the old VM stopped (not terminated) for a rollback window. For the network dependency: confirm the dedicated security group (decision 3) actually permits the connection as part of both the pre-flip validation AND every `-staging` bring-up under the recurring HubFlow flow; monitor Mongo VM availability independently of Pritunl's own health checks |
| **Renovate update mechanism is untested** — the `github-releases` custom-manager + regex-versioning combination for the Dockerfile `ARG` (decision 1) has not been run against a live Renovate instance in this pass | The auto-update loop (`DOCKER-IMAGE-TOOL-REPOSITORIES.md`'s core guarantee) could silently fail to open bump PRs if the versioning regex is wrong, leaving the image pinned indefinitely with no visible failure | Validate the first Renovate run against the new `pritunl` repo manually (`workflow_dispatch`) before relying on the weekday cron; confirm a bump PR actually opens when a newer Pritunl release exists |

## Residual open items

- **STOPSIGNAL — partially resolved (unchanged from the first pass).** Pritunl's own systemd unit file (`pritunl/data/systemd/pritunl.service` on the `master` branch, fetched and independently re-confirmed twice in the first pass), reads, verbatim:
  ```
  [Unit]
  Description=Pritunl Daemon

  [Service]
  LimitNOFILE=500000
  ExecStart=%PREFIX%/bin/pritunl start
  SuccessExitStatus=SIGALRM
  TimeoutStopSec=20

  [Install]
  WantedBy=multi-user.target
  ```
  There is no `ExecStop`, `KillMode`, or `KillSignal` override — meaning Pritunl's own packaging relies on systemd's default stop behavior (send `SIGTERM` to the main process), with `TimeoutStopSec=20` as the grace window before a hard `SIGKILL`. This **confirms `SIGTERM`** — Docker's own default `STOPSIGNAL` — is the signal Pritunl's own unit file already depends on; the Dockerfile should set `STOPSIGNAL SIGTERM` explicitly (self-documenting, mirroring pgbouncer's explicit-signal pattern at `pgbouncer/Dockerfile:18-25`, even though it matches Docker's default), with the ECS task definition's `stopTimeout` set to at least 20s to preserve the same grace window the systemd unit grants.
  **What remains genuinely unresolved**: no source (Pritunl's own docs, changelog, or forum) was found describing *what the process does* upon receiving `SIGTERM` with respect to in-flight OpenVPN/WireGuard client sessions — whether it drains them or drops them immediately. `SuccessExitStatus=SIGALRM` hints the process uses `SIGALRM` internally for some part of its own lifecycle (commonly a worker-reload or heartbeat signal in Python daemons), but no source was found explaining that behavior precisely, so this is **not asserted** — only the two verified facts above (default `SIGTERM`, 20s grace) are claimed. **Pre-Dockerfile spike item**: validate in-flight-connection behavior on `SIGTERM` empirically against a real client connection, both during the one-time cutover's pre-flip validation and during a routine `-staging` deploy under the recurring HubFlow flow, since no documentation resolves it.
- **Apt-version-to-GitHub-release-tag correspondence** (decision 1, unchanged) — not independently confirmed; verify `apt-cache policy pritunl` against `repo.pritunl.com/stable/apt` matches the GitHub release tag numbering before finalizing the Renovate `ARG` wiring.
- **Renovate versioning regex for the four-field Pritunl tag scheme** (decision 1, unchanged) — the mechanism (custom regex manager + `github-releases` datasource) is settled; the exact `versioning:` regex needs empirical validation against a live Renovate run once the repo exists.
- **`ecs_service` module extension vs. bespoke task definition** (decision 2, unchanged) — not decided which approach carries the `privileged`/host-network Terraform work for the Pritunl instance(s); an execution-phase implementation choice, not a re-opening of the runtime decision itself.
- **fail2ban's host-iptables reach from a co-located, privileged, host-networked container** (unchanged) — reasoned from Docker's documented networking model, but not independently load-tested against this exact image and AWS ECS-on-EC2 combination. Flagged as a pre-flip validation item.
- **MongoDB VM's Ansible role — exact name and location** (new this pass, decision 3) — the recommended path (trim the existing role's Mongo-only tasks, retarget to the Mongo VM) is surfaced with rationale, but the exact new role name, whether it lives in the same `4shark.pritunl` role behind an inventory-group conditional or as an independent role, and how the Mongo VM's inventory entry is structured are not decided — an `ansible` repo authoring detail for the engineer to settle when Phase 2 begins.
- **Dedicated Mongo security-group mechanism** (new this pass, decision 3) — `referenced_security_group_id` (SG-to-SG scoping, no existing 4Shark precedent) vs. a narrowed CIDR to the Pritunl instance's private IP (matches the existing convention, but fragile across instance replacement). Not decided — flagged for Terraform-authoring time.
- **Staging MongoDB strategy** (new this pass, decision 3 × decision 7) — the `-staging` Pritunl instance's database is not decided: a **separate staging Mongo VM** (full isolation, doubles the Mongo VM footprint), a **separate database on the same production Mongo VM** (shared blast radius with production data, but no second VM to provision/patch), or an **ephemeral/seeded Mongo** brought up only for the test window (matches the "normally at zero" framing of the staging instance itself, but needs its own seed-data strategy so validation is meaningful). Explicitly flagged by the engineer as an open item — not decided in this pass.
- **Staging instance's public entry point during a test window** (new this pass, decision 4 × decision 7) — decision 4 pins the single existing EIP to production only. The `-staging` Pritunl instance therefore needs its own way to be reached for OpenVPN/WireGuard client validation during a bring-up window: a dedicated (possibly ephemeral) Elastic IP, the instance's default (non-elastic) public IP, or a private-only validation path (e.g. over the VPN's own management access / SSM) that never exposes staging publicly at all. Explicitly flagged by the engineer as an open item — not decided in this pass.
- **EC2 host bring-up mechanism for `-staging`** (new this pass, decision 7) — the direct stop/start-wrapper-script path is the one this document assumes (grounded reason to rule out ASG managed-scaling-from-zero, decision 7 above), but the engineer has not explicitly confirmed this mechanism; it is a researched finding, not yet a signed-off decision.

## Execution phases

### Phase 1: New repo scaffolding (HubFlow shape)

**Objective:** stand up the `pritunl` tool repository per `DOCKER-IMAGE-TOOL-REPOSITORIES.md`'s HubFlow shape (§ "Two repo shapes"), mirroring `keycloak`.

**Components:**
- `develop` + `master` branches (HubFlow-initialized via `git hf init`) — **not** a single `main`
- Dockerfile (`FROM ubuntu:24.04`, Pritunl apt repo, `ARG PRITUNL_VERSION`-pinned install, `wireguard-tools`, dnsmasq, fail2ban packages) + `configured-entrypoint.sh` (Pritunl `set-*` commands — now pointed at the dedicated Mongo VM's private address — dnsmasq wait-loop + start, fail2ban start, `STOPSIGNAL SIGTERM`)
- `renovate.json` (base `config:recommended` + `helpers:pinGitHubActionDigests` + `minimumReleaseAge: 7 days`, plus the `customManagers` block for the `ARG PRITUNL_VERSION` github-releases tracking) and the `renovate.yml` runner workflow, copied from `pgbouncer`/`terraform` — unchanged shape from the first pass
- `ci.yaml` (hadolint), the three min-age-gate files — unchanged
- `build.yaml` mirroring `keycloak/.github/workflows/build.yaml:1-108` — one job per target (`<env>-staging` on push to `develop`, `<env>` on push to `master`), `workflow_dispatch` with an `environment` choice
- `deploy.yaml` mirroring `keycloak/.github/workflows/deploy.yaml:1-101` — manual `workflow_dispatch`, per-target cluster/service/task-family map, `force-new-deployment` + stabilization poll
- `CHANGELOG.md` — HubFlow variant lifecycle (dated `## [X.Y.Z]` section created directly on the `release/*` branch, not under `## [Unreleased]` — `DOCKER-IMAGE-TOOL-REPOSITORIES.md` item 10 HubFlow variant)

**Dependencies:** none — can start immediately.

**Success criteria:**
- [ ] `git hf init` completed; `develop` and `master` both exist and are pushed
- [ ] Dockerfile builds locally with a pinned `PRITUNL_VERSION`
- [ ] Renovate runs once via `workflow_dispatch` and is confirmed able to compute the current version from the `ARG` annotation (does not need to find an update yet — just confirm the extraction works)
- [ ] hadolint CI passes on the Dockerfile

### Phase 2: Terraform — production ECS instance, dedicated Mongo VM, staging ECS instance, governance

**Objective:** provision the new infrastructure — the production Pritunl instance, the dedicated Mongo VM, and the `-staging` Pritunl instance — alongside (not replacing) the running combined VM.

**Components:**
- Production ECS task definition (bespoke or `ecs_service` extension — residual open item) with `privileged: true`, host networking — **no MongoDB sidecar container and no `host_path` volume wiring** (removed this pass; MongoDB moved off-container to decision 3's dedicated VM)
- Production `ecs_capacity` instance (or bespoke `aws_instance` — residual open item) for the single dedicated Pritunl container instance, launch template `user_data` extended with WireGuard kernel-module load + `/dev/net/tun` presence + base OS hardening (the host-prep items from the Ansible mapping)
- **Dedicated Mongo VM** — a bare `aws_instance` (no existing generic 4Shark VM module beyond `terraform/modules/pritunl` itself was found this pass), provisioned via the recommended trimmed-Ansible-role path (decision 3); its own EBS root volume for the MongoDB data directory
- **Dedicated Mongo security group** — ingress on MongoDB's port from ONLY the Pritunl instance (mechanism — SG reference vs. narrowed CIDR — a residual open item, decision 3)
- **`-staging` ECS instance + ECS service at `desired_count = 0` by default** (decision 7); host bring-up/down mechanism per decision 7's stop/start-wrapper-script finding, **not** `ecs_capacity` managed-scaling-from-zero (grounded fact above rules it out); staging's own database, and its own public-entry mechanism during test windows, are both residual open items — Phase 2 provisions the instance shape, not necessarily a final answer on either
- IAM role carrying forward the existing route-advertisement permissions (`terraform/modules/pritunl/iam.tf:29-49`) for the production instance; whether staging needs the same permissions is an execution-time detail, not decided here
- Security group carrying forward the existing port set (ports 14720/OpenVPN, 14721/WireGuard, per `terraform/modules/pritunl/security.tf`) for the production instance
- **Two per-target ECR repositories** for the Pritunl image (`<environment>` and `<environment>-staging`, `terraform/auth-001/ecr.tf:1-29` shape) — no MongoDB ECR repository needed (Mongo is VM-based, not a container, this pass)
- Identity-stack governance: add `pritunl` to `local.hubflow_repositories` (`terraform/identity/github_repositories.tf:60-75`); add to `local.hubflow_repositories_with_min_age_check` (`:81-91`) once the `Verify Minimum Age` check exists
- **Do not yet touch the existing `aws_eip`/`aws_eip_association`** — unchanged from the first pass; the new production instance gets a temporary/secondary Elastic IP for Phase 3's pre-flip validation, so the production EIP stays pointed at the current combined VM until the flip in Phase 3

**Dependencies:** Phase 1 (images must exist in ECR before either ECS service can start tasks).

**Success criteria:**
- [ ] New production ECS-EC2 instance registers with its cluster and the Pritunl container reaches a running/healthy state, connected to the new Mongo VM over the VPC
- [ ] Mongo VM's `mongod` running and reachable ONLY from the Pritunl security group (verify a connection attempt from outside that security group is refused)
- [ ] `-staging` ECS instance/service provisioned at zero capacity, confirmed to scale up/down cleanly via the chosen host mechanism before relying on it for the first `develop` validation
- [ ] `terraform plan`/`apply` clean, existing `terraform/vpn/`/`terraform/modules/pritunl/` untouched until Phase 4

### Phase 3: Cutover — the one-time VM → ECS migration (distinct from the recurring HubFlow flow)

**Objective:** migrate state and traffic from the current combined VM to the new production ECS + Mongo VM stack, with no unrecoverable data loss. This phase runs **once**; it is not part of the ongoing HubFlow staging→prod flow decision 7 establishes for future Pritunl version bumps.

**Components:**
- `mongodump` on the current combined VM's MongoDB → `mongorestore` into the new dedicated Mongo VM
- Pre-flip parallel-validation step: with the new production stack live on its temporary IP, validate OpenVPN + WireGuard connectivity, `*.4shark.internal` DNS resolution, and the Pritunl-to-Mongo-VM network path against a test client profile (this is where the dnsmasq wait-loop risk, the fail2ban host-iptables-reach risk, the `SIGTERM` in-flight-connection residual item, and the new Pritunl↔Mongo-VM network dependency get their first real signal)
- Scheduled maintenance window: reassociate the existing production `aws_eip` from the old combined VM to the new production instance
- Post-flip smoke test: reconnect a real client against the now-production IP, confirm DNS + routing + Mongo connectivity

**Dependencies:** Phase 2 complete and validated.

**Success criteria:**
- [ ] Restored Mongo state matches the source (user count, org count, route entries)
- [ ] Pre-flip validation passes DNS resolution, both VPN protocols, and Pritunl-to-Mongo-VM connectivity on the temporary IP
- [ ] Post-flip smoke test passes on the production EIP

### Phase 4: VM retirement

**Objective:** decommission the old combined VM once the new stack is proven in production.

**Components:**
- Stop (do not terminate) the old combined VM — retained as a rollback path for N days (N to be set by the engineer at cutover time, not decided here)
- After the retention window, remove `terraform/vpn/` and `terraform/modules/pritunl/`
- Update `ansible/playbooks/provision-pritunl.yml` and the `4shark.pritunl` role — reduce to only the trimmed Mongo-VM-targeting tasks (decision 3), or delete outright if the Mongo-VM role is authored as a fully independent role

**Dependencies:** Phase 3 complete, retention window elapsed with no rollback needed.

**Success criteria:**
- [ ] Old combined VM terminated
- [ ] Retired Terraform/Ansible code removed from the respective repos

**After Phase 4**, the standing operational model is the recurring HubFlow flow described in decision 7 (merge to `develop` → staging validate → `git hf release` → `master` → production deploy) — this is not a numbered phase; it is the ongoing lifecycle every future Pritunl version bump follows.

## Sources

- `terraform/vpn/main.tf:1-27` — current VPN stack instantiation
- `terraform/modules/pritunl/main.tf:1-44` — current EC2 instance + EIP module (EIP: lines 32-39, association: 41-44)
- `terraform/modules/pritunl/security.tf:1-53` — current security group (ports 443, 14720/udp, 14721/udp, internal VPC CIDR)
- `terraform/modules/pritunl/iam.tf:1-54` — current IAM role, including VPC route-advertisement permissions
- `terraform/modules/pritunl/README.md:109-114` — "Known Limitations": VPN configuration lives inside Pritunl, not Terraform
- `terraform/vpn/README.md:1-43` — stack-level documentation, EIP/topology narrative
- `ansible/roles/4shark.pritunl/tasks/main.yml:1-264` — full current provisioning role (systemd-resolved, MongoDB, Pritunl, logrotate, dnsmasq, Pritunl config, fail2ban, initial credentials)
- `ansible/roles/4shark.pritunl/defaults/main.yml:1-38` — current role defaults (MongoDB version, Ubuntu codename, rate limiting, fail2ban timing, dnsmasq cache)
- `ansible/roles/4shark.pritunl/templates/dnsmasq-vpn.conf.j2:1-19`, `dnsmasq-override.conf.j2:1-11` — dnsmasq VPN-DNS-forwarding configuration and the Pritunl-interface-readiness ordering dependency
- `ansible/roles/4shark.pritunl/templates/fail2ban-jail-pritunl.conf.j2:1-9`, `fail2ban-filter-pritunl.conf.j2:1-9` — fail2ban per-IP protection configuration
- `ansible/playbooks/provision-pritunl.yml:1-44`, `ansible/playbooks/vars/pritunl/4shark-vpn-001.yml:1-7` — playbook and per-host vars
- `pgbouncer/Dockerfile:1-32` — tag+digest pin pattern, STOPSIGNAL rationale, entrypoint-chaining pattern
- `pgbouncer/configured-entrypoint.sh:1-11` — runtime config materialization pattern
- `pgbouncer/renovate.json:1-39` — Renovate config with a per-image `versioning` override for a non-clean-semver tag scheme, the direct precedent for the Pritunl `ARG` custom-manager versioning question
- `pgbouncer/Dockerfile:18-25` — the explicit-`STOPSIGNAL`-with-rationale pattern this migration mirrors for `SIGTERM`
- `pgbouncer/CHANGELOG.md:1-25` — main-only repo changelog lifecycle example (superseded reference for the branch-model change; kept for the CHANGELOG shape itself)
- `terraform/modules/ecr/main.tf:1-10` — generic ECR repository module
- `terraform/modules/connection_pooler/main.tf:1-365` — full Fargate-based ECS tool module (task definition, service, security group, IAM, Cloud Map DNS) — the closest existing "small tool on ECS" precedent, not privileged/host-networked
- `terraform/modules/ecs_service/main.tf:1-165` — the generic EC2/Fargate ECS service module; line 14 confirms no privileged/host branch exists today; lines 56-62 confirm the `host_path` volume mechanism (no longer used by this migration's MongoDB placement)
- `terraform/modules/ecs_capacity/main.tf:1-102` — the ASG-backed EC2 capacity-provider module; lines 1-51 (launch template, `block_device_mappings`, `user_data`) are the concrete vehicle for host-level prep; lines 53-102 (ASG + managed scaling) are the mechanism ruled out for staging bring-up
- `~/.claude/docs/DOCKER-IMAGE-TOOL-REPOSITORIES.md` — the governing standard for the new repo (full text read; every checklist item and every "Two repo shapes"/HubFlow-variant note cross-referenced above)
- `~/.claude/docs/AUTOMATED-DEPENDENCY-UPDATES.md` — the three-layer dependency-update model the new repo plugs into
- `~/.claude/docs/DEPLOYMENT-STRATEGY.md` — the phased-vs-single deploy decision framework applied to the cutover phase
- `keycloak/.github/workflows/build.yaml:1-108` — full HubFlow build workflow (one job per branch/target), fetched and quote-verified this pass
- `keycloak/.github/workflows/deploy.yaml:1-101` — full HubFlow deploy workflow (manual dispatch, per-target cluster/service/task-family map, stabilization poll), read in full this pass
- `terraform/auth-001/ecr.tf:1-29` — the two-per-target-ECR-repository pattern, read in full this pass
- `terraform/auth-001/auth_001_staging.tf:1-194` — the existing Fargate staging-instance precedent (desired_count=0, shared cluster/VPC/ALB, own database/hostname/log group), read in full this pass
- `terraform/auth-001/security_groups.tf:1-53` — the current CIDR-scoped security-group convention (including RDS access), read in full this pass
- `terraform/identity/github_repositories.tf:60-91` — `local.hubflow_repositories` and `local.hubflow_repositories_with_min_age_check`, where `pritunl` is added instead of the main-branch lists
- `~/.claude/skills/authenticators/SKILL.md:1-90` — the existing scale-up/scale-down skill behavior for a staging authenticator instance, the direct precedent the engineer's decision 7 language cites
- `~/.claude/scripts/ecs-scale.sh:1-63` — the existing ECS desired-count wrapper script
- [github.com/jippi/docker-pritunl](https://github.com/jippi/docker-pritunl) — docker-compose.yml (`privileged: true`) and README (`--network=host` default path) — fetched and quote-verified
- [github.com/goofball222/pritunl](https://github.com/goofball222/pritunl/blob/main/README.md) — README (WireGuard kernel-module host requirement, `network_mode: bridge`, `privileged: true`) — fetched and quote-verified
- [hub.docker.com/u/pritunl](https://hub.docker.com/u/pritunl) — confirms no official Pritunl VPN image exists — fetched and quote-verified
- [forum.pritunl.com/t/is-aws-documentdb-supported-as-a-database/1299](https://forum.pritunl.com/t/is-aws-documentdb-supported-as-a-database/1299) — DocumentDB incompatibility (capped collections / tailable cursors) — fetched and quote-verified
- [docs.renovatebot.com/modules/manager/regex/](https://docs.renovatebot.com/modules/manager/regex/) — the `datasource=github-releases` + `ARG/ENV ..._VERSION=` comment-annotation example, quoted verbatim in decision 1 — fetched and quote-verified
- [github.com/pritunl/pritunl/releases](https://github.com/pritunl/pritunl/releases) — Pritunl's own four-field version-tag scheme (`v1.34.4681.89`) — fetched
- [github.com/pritunl/pritunl/blob/master/data/systemd/pritunl.service](https://github.com/pritunl/pritunl/blob/master/data/systemd/pritunl.service) — Pritunl's own systemd unit file, quoted verbatim in "Residual open items" — fetched and independently re-confirmed twice (Citation Discipline self-check)
- [docs.aws.amazon.com/AmazonECS/latest/developerguide/cluster-auto-scaling.html](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/cluster-auto-scaling.html) — *"When Amazon ECS scales out from 0 instances, it automatically launches 2 instances."* — fetched and quote-verified this pass, the grounded basis for ruling out ASG-managed-scaling-from-zero for the staging instance (decision 7)
- [registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) — the `referenced_security_group_id` argument surfaced in decision 3's network-isolation discussion; the rendered page could not be fetched with an extractable verbatim quote this pass, so this citation is **UNVERIFIED** per Citation Discipline — the attribute's existence should be independently confirmed against the provider's own argument reference before it is relied on at Terraform-authoring time
- See auxiliary file: `pritunl-ecs-migration_options-comparison_1.html` — the historical options record from the first pass (every discarded alternative, its pros/cons/cost/risk, and citations), superseded by this document as the plan of record
