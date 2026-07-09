# PLAN — Pritunl VPN: VM to Containerized ECS Migration

> Reference: `~/.claude/docs/DOCKER-IMAGE-TOOL-REPOSITORIES.md`, `~/.claude/docs/AUTOMATED-DEPENDENCY-UPDATES.md`, `~/.claude/docs/DEPLOYMENT-STRATEGY.md`; derived from `PLAN-SPIKE.md` (engineer-approved, converged)
> Auxiliary: `pritunl-ecs-migration_options-comparison_1.html` (historical options record — every discarded alternative, its pros/cons/cost/risk, and citations — superseded by this document as the plan of record)

## Objective

Migrate 4Shark's Pritunl VPN gateway from its current single-EC2-VM deployment (Ansible-provisioned) to a containerized deployment on ECS, following the "Docker-image tool repository" standard already applied to `pgbouncer` and `keycloak`. The engineer has decided: a 4Shark-authored Dockerfile installing Pritunl's own official signed package, ECS on a single dedicated EC2 container instance (privileged + host networking), MongoDB as a colocated sidecar container on persistent EBS, the existing Elastic IP reassociated to the new instance, a main-only branch model for the new `pritunl` repository, the config-owning parts of the current Ansible role folded into the Dockerfile/entrypoint while host-only prep (kernel modules, device nodes, OS hardening) moves to the EC2 launch template, and a maintenance-window cutover preceded by a pre-flip parallel-validation step against a temporary second IP.

## Scope

### In scope

- A new `pritunl` tool repository conforming to `DOCKER-IMAGE-TOOL-REPOSITORIES.md` (Dockerfile, Renovate custom-manager config + runner, hadolint CI, min-age gate, build-on-merge, deploy-on-demand), main-only branch model
- Terraform changes in the `terraform` repo: new ECS/EC2 resources (task definition, EC2 capacity provider, security group, IAM role) replacing `terraform/vpn/` and `terraform/modules/pritunl/`, while reusing the existing `aws_eip` resource
- Retirement of `ansible/roles/4shark.pritunl/` config-owning tasks into the Dockerfile/entrypoint; retention of a thin host-prep responsibility (WireGuard kernel module, `/dev/net/tun`, base OS hardening) moved to the EC2 launch template / AMI / user-data
- Preservation of the current VPN's externally-observable behavior: fixed public IP, OpenVPN + WireGuard connectivity, `*.4shark.internal` DNS resolution for connected clients, per-IP brute-force protection, and the existing MongoDB-held org/user/profile state
- Governance: adding the new `pritunl` repo to `terraform/identity/github_repositories.tf`'s `local.main_branch_repositories` and (once CI produces the check) `local.main_branch_repositories_with_min_age_check`; creating the per-environment ECR repositories the images push to

### Out of scope

- VPN gateway high availability (multi-instance) — the engineer's decision keeps a single dedicated container instance, matching today's posture; not a goal of this migration
- A staging VPN instance for pre-production image validation — ruled out by the main-only branch-model decision; a new Pritunl base-image version is validated as part of the maintenance-window cutover process instead, not on a permanent second instance
- Client-side rollout mechanics beyond the high-level cutover phases below (how individual engineers are notified/reconnect) — a communication-plan detail for the maintenance window, not an infrastructure decision

## Current architecture (what is being migrated away from)

- **Terraform stack**: `terraform/vpn/main.tf:10-27` instantiates `module.pritunl` with a fixed AMI, `t3a.micro`, in the management VPC's public subnet (`vpc-0bdc76f3b391694dd`, subnet `management-pub-a`), ports 14720 (OpenVPN) and 14721 (WireGuard).
- **Module** `terraform/modules/pritunl/main.tf:1-44`: a bare `aws_instance` with `lifecycle { ignore_changes = [ami, user_data, user_data_base64] }` (Ansible manages the OS post-boot, not Terraform), plus `aws_eip` (lines 32-39) + `aws_eip_association` (lines 41-44) giving the instance a static public IP.
- **IAM** `terraform/modules/pritunl/iam.tf:29-49`: the instance role grants `ec2:DescribeRouteTables`/`CreateRoute`/`ReplaceRoute`/`DeleteRoute` — Pritunl's own VPC route advertisement for the OpenVPN client subnets (confirmed by `terraform/modules/pritunl/README.md:111`: *"OpenVPN routes (100.80/16, 100.96/16) and client profiles are configured inside Pritunl directly — Terraform only provisions the EC2 instance, not the VPN configuration"*). This IAM shape carries forward unchanged onto the new ECS-EC2 instance's role — the same binary, running as a container instead of a systemd service, still needs to advertise the same routes.
- **Ansible role** `ansible/roles/4shark.pritunl/tasks/main.yml:1-264`: disables the host's `systemd-resolved` DNS stub listener and symlinks `/etc/resolv.conf` (lines 12-25); installs MongoDB 8.0 from apt (lines 32-79); installs Pritunl + WireGuard from `repo.pritunl.com/stable/apt` unpinned (lines 83-113); configures logrotate for pritunl/mongod (115-131); installs and configures dnsmasq to forward VPN-client DNS queries to the VPC resolver for `*.4shark.internal` (133-187); sets Pritunl's Mongo URI/rate-limiting/auditing via `pritunl set-*` commands (191-201); installs fail2ban watching `/var/log/pritunl_journal.log` for `admin_auth_failure` events, banning the source IP (203-237); and retrieves/displays one-time setup credentials (241-263).
- **dnsmasq specifics**: `ansible/roles/4shark.pritunl/templates/dnsmasq-vpn.conf.j2:1-19` binds to the VPN virtual interface address (`pritunl_dnsmasq_listen_address`, set per-host in `ansible/playbooks/vars/pritunl/4shark-vpn-001.yml:6` to `10.149.176.1`) and forwards to the VPC DNS resolver (`10.255.0.2`, same file line 7); `dnsmasq-override.conf.j2:1-11` makes the systemd unit start `After=`/`Requires=pritunl.service` because dnsmasq cannot bind the VPN interface address until Pritunl has created it.
- **fail2ban specifics**: `ansible/roles/4shark.pritunl/templates/fail2ban-filter-pritunl.conf.j2:1-9` matches `admin_auth_failure` events in Pritunl's JSON audit log; `fail2ban-jail-pritunl.conf.j2:1-9` bans for 7 days (`pritunl_fail2ban_bantime: 604800`, `defaults/main.yml:30`) after a single failed attempt (`pritunl_fail2ban_maxretry: 1`, `defaults/main.yml:29`) — the per-IP protection layer, since Pritunl's own global rate limiter is deliberately disabled (`pritunl_auth_limiter_count_max: 999999`, `defaults/main.yml:22`, comment: *"Set to 999999 to effectively disable — per-IP protection is handled by fail2ban"*).
- **Ubuntu codename target**: `ansible/roles/4shark.pritunl/defaults/main.yml:9,18` — `pritunl_mongodb_ubuntu_codename: "noble"` and `pritunl_ubuntu_codename: "noble"`, i.e. Ubuntu 24.04 LTS. `defaults/main.yml:6` pins the currently-installed MongoDB line at `8.0`.

## Grounded external facts

- **No official Pritunl (VPN) Docker image exists.** Docker Hub's `pritunl` organization publishes only `pritunl/pritunl-zero` and `pritunl/pritunl-bastion` — confirmed by fetching `hub.docker.com/u/pritunl`: *"No, there is no official `pritunl` or `pritunl-vpn` image listed for the VPN server product. Only Pritunl Zero-related images are displayed on this organization page."*
- **Every container of Pritunl needs `privileged: true` (or explicit `/dev/net/tun` + capability grants) and host-loaded WireGuard kernel modules**, confirmed across community images' own documentation:
  - `github.com/jippi/docker-pritunl` docker-compose.yml: `privileged: true` on the `pritunl` service; README: *"If you don't want to use `network=host`, then replace the `--network=host` CLI flag with the following ports..."* — confirms host networking is the default-documented path.
  - `github.com/goofball222/pritunl` README/compose: `network_mode: bridge`, `privileged: true`, plus *"The Docker host is required to have wireguard kernel modules installed and loaded."*
  - Consistent with what the current Ansible role already does at the host level (`apt: name: [pritunl, wireguard, wireguard-tools]`, `tasks/main.yml:99-107`) — containerizing relocates where the *process* runs, not where the *kernel capability* lives. This is the technical basis for the host/image split in the Ansible-task mapping below: `wireguard` (kernel module, host-global) stays a host concern; `wireguard-tools` (the userspace CLI Pritunl's own process invokes) is just another apt package inside the image.
- **AWS Fargate cannot satisfy this.** Fargate does not expose `privileged: true`, host kernel modules, or `network_mode: host` to a task. Corroborated indirectly: both existing 4Shark tool-repo precedents (`connection-pooler`/pgbouncer and `auth-001`/keycloak) run on Fargate (`terraform/modules/connection_pooler/main.tf:250-260` — `requires_compatibilities = ["FARGATE"]`; `terraform/auth-001/ecs.tf:22-27,41` — same) — this migration is the first to solve the privileged/host-network case.
- **Amazon DocumentDB is explicitly unsupported by Pritunl as its database.** Fetched from `forum.pritunl.com/t/is-aws-documentdb-supported-as-a-database/1299`: *"Pritunl, Pritunl Zero and Pritunl Cloud all utilize capped collections and tailable cursors for publish subscribe messaging. This prevents using the MongoDB API compatible databases such as DocumentDB."* No fix timeline given — a hard blocker.
- **`modules/ecs_service` today has no privileged/host-network branch** — `terraform/modules/ecs_service/main.tf:14` — `network_mode = var.launch_type == "FARGATE" ? "awsvpc" : "bridge"` — EC2 launch type gets `bridge`, never `host`, and there is no `privileged` variable exposed anywhere in the module's `container_definitions` block. This module cannot be reused unmodified; the new task definition is either a bespoke `aws_ecs_task_definition` or an extension to `ecs_service` adding a `privileged` variable and a `host` network-mode branch.
- **`modules/ecs_service` already supports a host-path-backed Docker volume** — `terraform/modules/ecs_service/main.tf:56-62`:
  ```hcl
  dynamic "volume" {
    for_each = var.volumes
    content {
      name      = volume.value.name
      host_path = try(volume.value.host_path, null)
    }
  }
  ```
  This is the existing mechanism the MongoDB-sidecar-on-EBS decision reuses: an additional EBS volume attached to the container instance via its launch template's `block_device_mappings` (pattern already used for the root volume — `terraform/modules/ecs_capacity/main.tf:7-13`), mounted at a host path by the instance's user-data/launch config, then bound into the Mongo container task definition via this existing `volume`/`host_path` mechanism.
- **`modules/ecs_capacity` is the existing ASG-backed EC2 capacity-provider module** (`terraform/modules/ecs_capacity/main.tf:1-102`) already used by the EC2-launch-type fleet (`app-outbound-*`, `integrator-*`, `onboarding`, `setup`); its `aws_launch_template` already carries `block_device_mappings` for the root volume (7-13) and a `user_data` block that registers the instance with the target ECS cluster (24-28). This `user_data` block is the concrete vehicle for the host-level prep the Ansible-task mapping moves out of the container (WireGuard kernel module load, `/dev/net/tun` presence, base OS hardening).
- **`terraform/identity/github_repositories.tf:94-100`** — `local.main_branch_repositories` currently lists `compliance`, `data-privacy`, `google-analytics-manager`, `pgbouncer`, `rubocop-fourshark`; **`:106-109`** — `local.main_branch_repositories_with_min_age_check` currently lists `data-privacy`, `pgbouncer`. `pritunl` is added to the first list at repo creation and to the second once its CI produces the `Verify Minimum Age` check.
- **`terraform/app-shared-001/ecr.tf:1-21`** — the `<environment>-<image>` ECR-naming pattern already in use: `locals { ecr_repositories = toset(["${var.environment}-app", "${var.environment}-connection-pooler"]) }` feeding `module.ecr`. The new `pritunl` and `pritunl-mongodb` (or similarly named) repositories follow the same shape.

## Chosen approach

**Direction:** Containerize Pritunl via a 4Shark-authored Dockerfile built from Pritunl's own official apt repository, deployed on ECS running on a single dedicated EC2 container instance (privileged + host networking, no HA), with MongoDB as a colocated sidecar container on a persistent EBS volume, the existing Elastic IP reassociated to the new instance, in a new main-only `pritunl` repository following the `DOCKER-IMAGE-TOOL-REPOSITORIES.md` standard. The config-owning parts of the current Ansible role move into the Dockerfile/entrypoint; host-only prep (WireGuard kernel module, `/dev/net/tun`, base OS hardening) moves to the EC2 launch template. Cutover happens in a maintenance window preceded by a pre-flip parallel-validation step on a temporary second IP.

**Rationale (from engineer):** the engineer decided against every community Docker image (Options A–C in the auxiliary HTML) because they carry an unofficial supply-chain dependency on a single external maintainer; a self-built image from Pritunl's own signed repo matches the trust model 4Shark already runs today and matches `pgbouncer`'s and `keycloak`'s pattern of a 4Shark-owned Dockerfile. Fargate was ruled out because it structurally cannot grant the privileged/host-network/kernel-module access every community image documents as required. A single instance matches today's posture (HA was explicitly decided out of scope). DocumentDB was ruled out as a hard blocker (unsupported capped collections/tailable cursors); a sidecar-with-EBS is the closest architectural match to today. The existing EIP is reassociated rather than replaced so client `.ovpn`/WireGuard profiles need no change. Main-only branch model was chosen because there is exactly one VPN gateway and no staging instance to validate against — matching `DOCKER-IMAGE-TOOL-REPOSITORIES.md`'s stated condition for the main-only shape. Config-owning Ansible tasks move into the image/entrypoint because `privileged: true` + host networking gives the Pritunl container the same network-namespace and iptables reach the current host-level dnsmasq/fail2ban processes rely on, so both can be co-located rather than staying separate host services — only kernel-module loading and device-node presence are structurally host-only.

**Source patterns referenced:**
- `ansible/roles/4shark.pritunl/tasks/main.yml:83-107` — today's unpinned apt-install source, now pinned via `ARG`
- `pgbouncer/Dockerfile:1-32` — the tag+digest pin + Renovate-tracking comment pattern (adapted for a custom-manager annotation instead of a `FROM` tag)
- `pgbouncer/renovate.json:11-16` — the precedent for a per-package `versioning: regex:` override when the upstream tag scheme is non-semver
- `terraform/modules/pritunl/main.tf:32-39` (`aws_eip`) and `:41-44` (`aws_eip_association`) — the exact resource shape carried forward
- `~/.claude/docs/DOCKER-IMAGE-TOOL-REPOSITORIES.md:17` — *"main-only ... For a simple, stable tool with no staging instance. Reference: pgbouncer"*

### 1. Base image — 4Shark-authored Dockerfile from Pritunl's own official apt repo

**Decision:** `FROM ubuntu:24.04` (noble — matches the Ansible role's current target, `ansible/roles/4shark.pritunl/defaults/main.yml:9,18`), add Pritunl's own signed apt repo (`repo.pritunl.com/stable/apt`, same source as `ansible/roles/4shark.pritunl/tasks/main.yml:93-97`), install the official `pritunl` `.deb` pinned via a Dockerfile `ARG PRITUNL_VERSION`. Not a community image.

**Auto-update loop for a self-built package image:** `DOCKER-IMAGE-TOOL-REPOSITORIES.md`'s item 2 assumes a `FROM upstream/image:<tag>@sha256:<digest>` — Renovate's `docker` datasource tracks a base-image tag directly. An apt-installed `.deb` has no such tag. Renovate's own regex custom-manager docs describe exactly this gap. Fetched from `docs.renovatebot.com/modules/manager/regex/` (Advanced Capture section), verbatim:
```
# renovate: datasource=github-releases depName=composer packageName=composer/composer
ENV COMPOSER_VERSION=1.9.3
```
with the matching `matchStrings` regex:
```
"# renovate: datasource=(?<datasource>[a-z-]+?)(?: depName=(?<depName>.+?))? packageName=(?<packageName>.+?)(?: versioning=(?<versioning>[a-z-]+?))?\\s(?:ENV|ARG) .+?_VERSION=(?<currentValue>.+?)\\s"
```
This is directly reusable for the Pritunl Dockerfile: annotate `ARG PRITUNL_VERSION=<pinned>` with `# renovate: datasource=github-releases packageName=pritunl/pritunl`, and add a `customManagers` block to `renovate.json` using that `matchStrings` pattern (`managerFilePatterns: ["/^Dockerfile$/"]`, `datasourceTemplate: "github-releases"`). The `github-releases` datasource resolves `releaseTimestamp` from the GitHub release's own publish date, so the 7-day `minimumReleaseAge` quarantine computes normally.

**Version-scheme caveat:** fetching `github.com/pritunl/pritunl/releases` shows tags of the shape `pritunl v1.34.4681.89`, `pritunl v1.34.4649.96`, `pritunl v1.32.4567.52` — a four-numeric-field scheme, not three-field semver. `edoburu/pgbouncer` hit the same class of problem with its `-pN` build suffix and needed an explicit `versioning: regex:...` override (`pgbouncer/renovate.json:11-16`). The Pritunl `ARG` custom manager likely needs the same treatment — a `versioning` capture or `versioningTemplate` with a 4-group regex (`^v(?<major>\d+)\.(?<minor>\d+)\.(?<build>\d+)\.(?<patch>\d+)$`) — this was **not empirically validated against a live Renovate run**, see Residual open items.

**Source patterns referenced:** `ansible/roles/4shark.pritunl/tasks/main.yml:83-107`; `pgbouncer/Dockerfile:1-32`; `pgbouncer/renovate.json:11-16`; [docs.renovatebot.com/modules/manager/regex/](https://docs.renovatebot.com/modules/manager/regex/); [github.com/pritunl/pritunl/releases](https://github.com/pritunl/pritunl/releases).

### 2. Runtime / launch type — ECS on EC2, single dedicated container instance

**Decision:** ECS on EC2 (Fargate ruled out per the grounded fact above). A single dedicated ECS container instance, `privileged: true` + host networking, WireGuard kernel modules present on the host. No HA / multi-instance.

**Source patterns referenced:** `terraform/modules/ecs_service/main.tf:14`; `terraform/modules/ecs_capacity/main.tf:1-102`; `terraform/modules/connection_pooler/main.tf:250-260`; `terraform/auth-001/ecs.tf:22-27,41`.

### 3. MongoDB — container/sidecar on the same instance, persistent EBS

**Decision:** A MongoDB container running as a sidecar on the same ECS-EC2 instance, state on a persistent EBS volume (Docker host-path volume backed by an EBS device). Not DocumentDB. State migration is `mongodump` on the current VM → `mongorestore` into the new Mongo.

**Source patterns referenced:** `forum.pritunl.com/t/is-aws-documentdb-supported-as-a-database/1299`; `ansible/roles/4shark.pritunl/tasks/main.yml:32-79`; `terraform/modules/ecs_service/main.tf:56-62`; `terraform/modules/ecs_capacity/main.tf:7-13`.

### 4. Public entry — reassociate the existing Elastic IP

**Decision:** Reassociate the existing `aws_eip` allocation (from `terraform/modules/pritunl/main.tf`) to the new ECS-EC2 instance, preserving the fixed public IP. No NLB. Under host networking, the container shares the instance's network stack, so the association is instance-level (`aws_eip_association` against the new `aws_instance`, same shape as today), not an ENI belonging to a task.

**Source patterns referenced:** `terraform/modules/pritunl/main.tf:32-39` (`aws_eip`), `:41-44` (`aws_eip_association`).

### 5. Branch model — main-only, repo named `pritunl`

**Decision:** Main-only (pgbouncer reference), not HubFlow. The new repo is named `pritunl`.

**Source patterns referenced:** `~/.claude/docs/DOCKER-IMAGE-TOOL-REPOSITORIES.md:17`; `terraform/identity/github_repositories.tf:94-100`.

### 6. Ansible role fate — config into image/entrypoint, host-only prep into the launch template

**Decision:** the config responsibilities of `ansible/roles/4shark.pritunl` move into the Dockerfile + a `configured-entrypoint.sh` (Pritunl install, `pritunl set-mongodb`/rate-limit/auditing, dnsmasq config, fail2ban config, logrotate replaced by CloudWatch Logs). The host-level prep a container cannot own — WireGuard kernel module load, `/dev/net/tun`, base OS hardening — moves to the EC2 launch template / a minimal custom AMI / user-data, not into the image. See the exhaustive per-task mapping below.

## Ansible-task → new-home mapping

Exhaustive, one row per current task/responsibility in `ansible/roles/4shark.pritunl/tasks/main.yml:1-264`. "IMAGE" = Dockerfile or `configured-entrypoint.sh`; "HOST" = EC2 launch template / custom AMI / user-data; "DROPPED" = no longer needed under the new architecture; "CUTOVER" = a one-off step in the cutover runbook.

| Current task (file:line) | New home | Why |
|---|---|---|
| Disable systemd-resolved DNS stub listener; symlink `/etc/resolv.conf` (`tasks/main.yml:12-25`) | **HOST** | Generic host-level DNS bootstrap — structurally separate from the VPN-client DNS forwarding block; folds into the host launch-template/AMI "base OS hardening" bucket |
| MongoDB apt-repo key, repo, install (`tasks/main.yml:32-61`) | **IMAGE** (separate MongoDB sidecar image) | Becomes the Mongo sidecar container's own build. Version carried forward unchanged: `pritunl_mongodb_version: "8.0"` (`defaults/main.yml:6`) |
| Configure MongoDB (`mongod.conf` template, `tasks/main.yml:63-70`) | **IMAGE** (Mongo sidecar entrypoint) | Config materialization at container start, same pattern as pgbouncer's `configured-entrypoint.sh` |
| Enable/start `mongod` via systemd (`tasks/main.yml:72-76`) | **IMAGE** (container `CMD`/`ENTRYPOINT`) | systemd unit concept does not apply inside a container; Docker's own process supervision replaces it |
| Pritunl apt-repo key, repo, install of `pritunl` (`tasks/main.yml:83-98`) | **IMAGE** | The pinned-version Dockerfile install — see decision 1 |
| Apt install of `wireguard-tools` (part of `tasks/main.yml:99-107`) | **IMAGE** | Userspace tooling Pritunl's own process invokes — just another apt package inside the image |
| WireGuard kernel module load/presence (implied by `tasks/main.yml:99-107`'s `wireguard` package) | **HOST** | Kernel modules are host-global, not per-container-namespaceable. Confirmed by `github.com/goofball222/pritunl`'s README: *"The Docker host is required to have wireguard kernel modules installed and loaded."* |
| `/dev/net/tun` device-node presence | **HOST** | Device node must exist on the host for a privileged container to access it |
| Enable/start `pritunl` via systemd (`tasks/main.yml:109-113`) | **IMAGE** (container `CMD`/`ENTRYPOINT` + `STOPSIGNAL`) | Replaced by Docker's process model; the graceful-shutdown signal is addressed in Residual open items |
| Logrotate for pritunl/mongod (`tasks/main.yml:117-131`) | **DROPPED** | Replaced by the `awslogs` ECS log driver + CloudWatch Logs retention, matching the pgbouncer/connection-pooler pattern. **Implementation note**: Pritunl's default logging target (file vs stdout) needs confirming during entrypoint authoring |
| dnsmasq install + VPN-DNS-forwarding config (`tasks/main.yml:138-152`, `templates/dnsmasq-vpn.conf.j2:1-19`) | **IMAGE** (`configured-entrypoint.sh`, co-located with Pritunl) | Host networking means the container shares the host's network namespace, so dnsmasq inside the container can still bind the VPN virtual interface Pritunl creates, exactly as it does today from the host |
| dnsmasq logrotate (`tasks/main.yml:154-160`) | **DROPPED** | Same reasoning as pritunl/mongod logrotate above |
| dnsmasq systemd override forcing `After=`/`Requires=pritunl.service` (`tasks/main.yml:162-177`, `templates/dnsmasq-override.conf.j2:1-11`) | **IMAGE** (entrypoint ordering) | Replaced by a wait-loop inside `configured-entrypoint.sh`: start Pritunl, poll for the VPN virtual interface to appear, then start dnsmasq bound to that address. **This is the single highest-risk mapping in this table** — see Risks below |
| `pritunl set-mongodb` / rate-limit / auditing (`tasks/main.yml:191-201`) | **IMAGE** (`configured-entrypoint.sh`) | Config materialization at container start — direct parallel to `pgbouncer/configured-entrypoint.sh:1-11` |
| fail2ban install + filter + jail config (`tasks/main.yml:203-228`, `templates/fail2ban-filter-pritunl.conf.j2:1-9`, `fail2ban-jail-pritunl.conf.j2:1-9`) | **IMAGE** (`configured-entrypoint.sh`, co-located with Pritunl) | fail2ban needs to (a) read Pritunl's own JSON audit log and (b) manipulate the host's real netfilter/iptables rules. Co-locating it inside the same privileged, host-networked container means (a) is a local file read and (b) works because host networking shares the network namespace — the same `privileged`+host-network grant decision 2 already makes |
| Enable/start fail2ban via systemd (`tasks/main.yml:230-234`) | **IMAGE** (entrypoint-managed background process) | systemd unit concept does not apply; entrypoint starts it as a supervised background process alongside Pritunl and dnsmasq |
| Get/display initial setup credentials (`tasks/main.yml:241-263`) | **CUTOVER** | A one-time bootstrap step, run once against the new stack during the cutover phase (via ECS Exec or `docker exec`), not baked into the image |
| Ansible handlers (restart systemd-resolved / mongod / dnsmasq / fail2ban) | **DROPPED** | Ansible handler mechanics with no container equivalent — config changes at container start are applied by the entrypoint directly |

## Execution phases

This migration spans two repositories plus retirement of the current Ansible role: a new `pritunl` tool repository (Phase 1), Terraform changes in the `terraform` repo (Phase 2), a cutover procedure that touches both live stacks (Phase 3), and removal of the old Terraform module/Ansible role (Phase 4).

### Phase 1: New repo scaffolding (`pritunl` repository)

**Objective:** stand up the `pritunl` tool repository per `DOCKER-IMAGE-TOOL-REPOSITORIES.md`.

**Components:**
- Dockerfile (`FROM ubuntu:24.04`, Pritunl apt repo, `ARG PRITUNL_VERSION`-pinned install, `wireguard-tools`, dnsmasq, fail2ban packages) + `configured-entrypoint.sh` (Pritunl `set-*` commands, dnsmasq wait-loop + start, fail2ban start, `STOPSIGNAL SIGTERM`)
- Separate MongoDB sidecar Dockerfile (or a documented choice to use an official `mongo:8.0` image directly, matching `defaults/main.yml:6`'s pinned version — an execution-time detail, not reopened here)
- `renovate.json` (base `config:recommended` + `helpers:pinGitHubActionDigests` + `minimumReleaseAge: 7 days`, plus the `customManagers` block for the `ARG PRITUNL_VERSION` github-releases tracking) and the `renovate.yml` runner workflow, copied from `pgbouncer`/`terraform`
- `ci.yaml` (hadolint), the three min-age-gate files, `build.yaml`/`deploy.yaml` (one job per environment)
- `CHANGELOG.md`

**Dependencies:** none — can start immediately.

**Success criteria:**
- [ ] Dockerfile builds locally with a pinned `PRITUNL_VERSION`
- [ ] Renovate runs once via `workflow_dispatch` and is confirmed able to compute the current version from the `ARG` annotation (does not need to find an update yet — just confirm the extraction works)
- [ ] hadolint CI passes on the Dockerfile

### Phase 2: Terraform — ECS/EC2, MongoDB volume, EIP association, governance (`terraform` repository)

**Objective:** provision the new infrastructure alongside (not replacing) the running VM.

**Components:**
- ECS task definition (bespoke or `ecs_service` extension) with `privileged: true`, host networking, the MongoDB sidecar container, and the `host_path` volume wiring (`terraform/modules/ecs_service/main.tf:56-62` pattern)
- `ecs_capacity` module instance for the single dedicated container instance, launch template `user_data` extended with WireGuard kernel-module load + `/dev/net/tun` presence + base OS hardening (the host-prep items from the Ansible mapping), second `block_device_mappings` entry for the Mongo EBS volume
- IAM role carrying forward the existing route-advertisement permissions (`terraform/modules/pritunl/iam.tf:29-49`)
- Security group carrying forward the existing port set (ports 14720/OpenVPN, 14721/WireGuard, per `terraform/modules/pritunl/security.tf`)
- Per-environment ECR repositories for the Pritunl and MongoDB images (`terraform/modules/ecr` pattern, `terraform/app-shared-001/ecr.tf:1-21` shape)
- Identity-stack governance: add `pritunl` to `local.main_branch_repositories` (`terraform/identity/github_repositories.tf:94-100`); add to `local.main_branch_repositories_with_min_age_check` (`:106-109`) once the `Verify Minimum Age` check exists
- **Do not yet touch the existing `aws_eip`/`aws_eip_association`** — the new instance gets a temporary/secondary Elastic IP for Phase 3's pre-flip validation, so the production EIP stays pointed at the current VM until the flip in Phase 3

**Dependencies:** Phase 1 (images must exist in ECR before the ECS service can start tasks).

**Success criteria:**
- [ ] New ECS-EC2 instance registers with its cluster and both containers (Pritunl, Mongo) reach a running/healthy state
- [ ] `terraform plan`/`apply` clean, existing `terraform/vpn/`/`terraform/modules/pritunl/` untouched until Phase 4

### Phase 3: Cutover

**Objective:** migrate state and traffic from the VM to the new ECS stack with no unrecoverable data loss.

**Components:**
- `mongodump` on the current VM's MongoDB → `mongorestore` into the new sidecar's MongoDB
- Pre-flip parallel-validation step: with the new stack live on its temporary IP, validate OpenVPN + WireGuard connectivity and `*.4shark.internal` DNS resolution against a test client profile (this is where the dnsmasq wait-loop risk, the fail2ban host-iptables-reach risk, and the `SIGTERM` in-flight-connection residual item get their first real signal)
- Scheduled maintenance window: reassociate the existing production `aws_eip` from the old VM to the new instance
- Post-flip smoke test: reconnect a real client against the now-production IP, confirm DNS + routing

**Dependencies:** Phase 2 complete and validated.

**Success criteria:**
- [ ] Restored Mongo state matches the source (user count, org count, route entries)
- [ ] Pre-flip validation passes DNS resolution and both VPN protocols on the temporary IP
- [ ] Post-flip smoke test passes on the production EIP

### Phase 4: VM retirement (`terraform` and Ansible repositories)

**Objective:** decommission the old infrastructure once the new stack is proven in production.

**Components:**
- Stop (do not terminate) the old VM — retained as a rollback path for N days (N to be set by the engineer at cutover time, not decided here)
- After the retention window, remove `terraform/vpn/` and `terraform/modules/pritunl/`
- Update `ansible/playbooks/provision-pritunl.yml` and the `4shark.pritunl` role — either delete outright or reduce to documentation-only, per whatever host-prep responsibilities Phase 2's launch template did not already fully absorb

**Dependencies:** Phase 3 complete, retention window elapsed with no rollback needed.

**Success criteria:**
- [ ] Old VM terminated
- [ ] Retired Terraform/Ansible code removed from the respective repos

## Technical decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Base image | 4Shark-authored Dockerfile, official Pritunl apt repo, `ARG PRITUNL_VERSION` pin | Matches today's trust source; avoids a third-party community image as the supply-chain root for the VPN gateway every engineer depends on |
| Renovate update mechanism | `customManagers` regex block, `datasource=github-releases`, `packageName=pritunl/pritunl`, annotating the Dockerfile `ARG` | The only Renovate mechanism that can track a version with no `FROM <tag>` to read — confirmed against Renovate's own regex-manager docs |
| Runtime / launch type | ECS on EC2, single dedicated container instance, `privileged: true` + host networking | Fargate structurally cannot grant privileged/host-network/kernel-module access; single instance matches today's posture (HA explicitly out of scope) |
| MongoDB | Sidecar container, persistent EBS-backed host-path volume | DocumentDB is a hard blocker (unsupported capped collections/tailable cursors); sidecar is the closest match to today's colocated topology |
| Public entry | Reassociate the existing `aws_eip` to the new instance | Same resource, re-targeted association — zero client reconfiguration |
| Branch model | Main-only, repo `pritunl` | No staging instance exists or is planned; matches the pgbouncer reference condition |
| dnsmasq / fail2ban placement | Both co-located inside the Pritunl image/entrypoint (not host-level services) | `privileged` + host networking already grants the network-namespace and iptables access both need; co-location avoids a bind-mount for the audit log fail2ban reads |
| WireGuard kernel module / `/dev/net/tun` | Host launch template / AMI / user-data | Kernel modules and device nodes are host-global — a container cannot supply them for itself |
| Cutover | Maintenance window, preceded by a pre-flip parallel-validation step on a temporary second IP | Simplest state-transfer story for irreplaceable org/user/profile data; the pre-flip validation step reduces the risk a hard maintenance-window cutover otherwise carries by proving connectivity and DNS resolution before the EIP moves |

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| **dnsmasq DNS forwarding for `*.4shark.internal`** depends on binding the VPN virtual interface only after Pritunl creates it (`ansible/roles/4shark.pritunl/templates/dnsmasq-override.conf.j2:1-11` — `After=`/`Requires=pritunl.service`). The chosen mapping replaces this systemd-level ordering with a hand-written wait-loop inside `configured-entrypoint.sh` — a weaker guarantee than a declarative systemd dependency, and the single highest-risk item in the Ansible-task mapping | If the wait-loop is wrong (races, wrong interface name, insufficient poll interval), connected VPN clients silently lose internal DNS resolution — a regression that may not surface until an engineer tries to reach an internal hostname, well after the cutover appears successful | Validate internal-hostname resolution from a connected test client explicitly during the pre-flip parallel-validation step, not only after the EIP flips; consider a `healthcheck`-gated startup order rather than a bare sleep-poll loop, to fail loudly instead of silently if the interface never appears |
| **fail2ban per-IP protection** now runs inside the same container as Pritunl, relying on `privileged`+host-networking to reach the host's real iptables and reading the audit log from the local (container) filesystem. Pritunl's own global rate limiter is deliberately disabled today specifically because fail2ban carries this responsibility (`pritunl_auth_limiter_count_max: 999999`, `defaults/main.yml:22`) | If the co-located fail2ban fails to actually reach the host's iptables (an assumption reasoned from Docker's documented networking model, not independently load-tested against this exact image), the admin auth endpoint has no brute-force protection at all — with Pritunl's own limiter also off | Confirm fail2ban's bans are visible in the HOST's own `iptables -L` (not just the container's) as part of the pre-flip validation step; keep the option of re-enabling Pritunl's own `app.auth_limiter_count_max` as an interim safeguard if the co-located fail2ban does not work as reasoned |
| **EIP pinning** — every engineer's `.ovpn`/WireGuard client profile is configured against the current public IP | An uncoordinated IP change locks every engineer out of private infrastructure simultaneously, including infrastructure needed to fix the VPN itself | Reassociate the existing EIP allocation rather than provisioning a new one; the pre-flip parallel-validation step uses a temporary second IP specifically so the real EIP only moves once the new stack is proven working |
| **MongoDB state** (org/users/VPN profiles, dynamic OpenVPN routes) exists only inside Pritunl's own database — confirmed by `terraform/modules/pritunl/README.md:111` | A failed or incomplete `mongodump`/`mongorestore` during cutover means real client accounts and routes are lost, not just re-derivable configuration | Treat the Mongo migration as the highest-scrutiny step of the cutover; validate restored state (user count, route entries) against the source before decommissioning the old instance; keep the old VM stopped (not terminated) for a rollback window |
| **Renovate update mechanism is untested** — the `github-releases` custom-manager + regex-versioning combination for the Dockerfile `ARG` has not been run against a live Renovate instance | The auto-update loop (`DOCKER-IMAGE-TOOL-REPOSITORIES.md`'s core guarantee) could silently fail to open bump PRs if the versioning regex is wrong, leaving the image pinned indefinitely with no visible failure | Validate the first Renovate run against the new `pritunl` repo manually (`workflow_dispatch`) before relying on the weekday cron; confirm a bump PR actually opens when a newer Pritunl release exists |

## Residual open items

These items are surfaced by the draft as unresolved and remain unresolved here — they require pre-implementation verification, not a design decision, and are not blockers to starting the phases above.

- **STOPSIGNAL — partially resolved.** Pritunl's own systemd unit file (`pritunl/data/systemd/pritunl.service` on the `master` branch), quoted verbatim:
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
  There is no `ExecStop`, `KillMode`, or `KillSignal` override — Pritunl's own packaging relies on systemd's default stop behavior (send `SIGTERM`), with `TimeoutStopSec=20` as the grace window before a hard `SIGKILL`. This confirms `SIGTERM` — Docker's own default `STOPSIGNAL` — is the signal Pritunl's own unit file already depends on; the Dockerfile should set `STOPSIGNAL SIGTERM` explicitly (mirroring `pgbouncer/Dockerfile:18-25`), with the ECS task definition's `stopTimeout` set to at least 20s.
  **What remains genuinely unresolved**: no source describes what the process does upon receiving `SIGTERM` with respect to in-flight OpenVPN/WireGuard client sessions — whether it drains them or drops them immediately. `SuccessExitStatus=SIGALRM` hints the process uses `SIGALRM` internally for some part of its own lifecycle, but no source explains that behavior precisely — this is not asserted, only the two verified facts above (default `SIGTERM`, 20s grace) are claimed. **Pre-Dockerfile spike item**: validate in-flight-connection behavior on `SIGTERM` empirically against a real client connection during the pre-flip parallel-validation step.
- **Apt-version-to-GitHub-release-tag correspondence** — not independently confirmed; verify `apt-cache policy pritunl` against `repo.pritunl.com/stable/apt` matches the GitHub release tag numbering before finalizing the Renovate `ARG` wiring.
- **Renovate versioning regex for the four-field Pritunl tag scheme** — the mechanism (custom regex manager + `github-releases` datasource) is settled; the exact `versioning:` regex needs empirical validation against a live Renovate run once the repo exists.
- **`ecs_service` module extension vs. bespoke task definition** — not decided which approach carries the `privileged`/host-network Terraform work; an execution-phase implementation choice, not a re-opening of the runtime decision itself.
- **fail2ban's host-iptables reach from a co-located, privileged, host-networked container** — reasoned from Docker's documented networking model, but not independently load-tested against this exact image and AWS ECS-on-EC2 combination. Flagged as a pre-flip validation item.

## Assumptions

- Host networking (`network_mode: host`) plus `privileged: true` gives a container the host's network namespace, and iptables rules set from inside such a container are the host's actual rules — this is the basis for co-locating dnsmasq and fail2ban inside the Pritunl container instead of keeping them as separate host services. Not independently load-tested against this exact ECS-on-EC2/Docker combination (see Residual open items).
- `SIGTERM` is Pritunl's default stop signal with a 20-second grace window, matching Docker's own default `STOPSIGNAL` — confirmed from Pritunl's own systemd unit file, though the in-flight-session drain behavior on receiving that signal is not documented anywhere and is unverified.
- The apt package version served by Pritunl's `stable` repo corresponds one-to-one with the GitHub release tag numbering Renovate will track — very likely true given they are the same release process, but not independently confirmed by inspecting `apt-cache policy pritunl` output.
- The `github-releases` datasource + regex custom-manager mechanism will successfully track Pritunl's four-field version scheme once a `versioning:` regex is tuned — the mechanism is settled by Renovate's own documented pattern; the exact regex for this specific tag shape has not been run against a live Renovate instance.

## Sources

- `terraform/vpn/main.tf:1-27` — current VPN stack instantiation
- `terraform/modules/pritunl/main.tf:1-44` — current EC2 instance + EIP module (EIP: lines 32-39, association: 41-44)
- `terraform/modules/pritunl/security.tf:1-53` — current security group (ports 443, 14720/udp, 14721/udp, internal VPC CIDR)
- `terraform/modules/pritunl/iam.tf:1-54` — current IAM role, including VPC route-advertisement permissions
- `terraform/modules/pritunl/README.md:109-114` — "Known Limitations": VPN configuration lives inside Pritunl, not Terraform
- `terraform/vpn/README.md:1-43` — stack-level documentation, EIP/topology narrative
- `ansible/roles/4shark.pritunl/tasks/main.yml:1-264` — full current provisioning role
- `ansible/roles/4shark.pritunl/defaults/main.yml:1-38` — current role defaults (MongoDB version, Ubuntu codename, rate limiting, fail2ban timing, dnsmasq cache)
- `ansible/roles/4shark.pritunl/templates/dnsmasq-vpn.conf.j2:1-19`, `dnsmasq-override.conf.j2:1-11` — dnsmasq VPN-DNS-forwarding configuration and the Pritunl-interface-readiness ordering dependency
- `ansible/roles/4shark.pritunl/templates/fail2ban-jail-pritunl.conf.j2:1-9`, `fail2ban-filter-pritunl.conf.j2:1-9` — fail2ban per-IP protection configuration
- `ansible/playbooks/provision-pritunl.yml:1-44`, `ansible/playbooks/vars/pritunl/4shark-vpn-001.yml:1-7` — playbook and per-host vars
- `terraform/identity/github_repositories.tf:94-100` (`local.main_branch_repositories`), `:106-109` (`local.main_branch_repositories_with_min_age_check`) — governance lists `pritunl` is added to
- `pgbouncer/Dockerfile:1-32` — tag+digest pin pattern, STOPSIGNAL rationale, entrypoint-chaining pattern
- `pgbouncer/configured-entrypoint.sh:1-11` — runtime config materialization pattern
- `pgbouncer/renovate.json:1-39` — Renovate config with a per-image `versioning` override for a non-clean-semver tag scheme
- `pgbouncer/.github/workflows/build.yaml:1-193`, `deploy.yaml:1-54` — main-only build-on-merge/deploy-on-demand workflow shape
- `pgbouncer/CHANGELOG.md:1-25` — main-only repo changelog lifecycle example
- `terraform/app-shared-001/ecr.tf:1-21` — `<environment>-<image>` ECR-naming pattern reused for the new Pritunl/MongoDB repositories
- `terraform/app-shared-001/connection_pooler.tf:1-63` — stack-level secrets/DNS-association pattern for a colocated stateful tool
- `terraform/modules/connection_pooler/main.tf:1-365` — full Fargate-based ECS tool module (task definition, service, security group, IAM, Cloud Map DNS) — the closest existing "small tool on ECS" precedent, not privileged/host-networked
- `terraform/modules/ecr/main.tf:1-10` — generic ECR repository module
- `terraform/auth-001/ecr.tf:1-29` — keycloak's per-target ECR repositories (production + staging)
- `terraform/modules/ecs_service/main.tf:1-165` — the generic EC2/Fargate ECS service module; line 14 confirms no privileged/host branch exists today; lines 56-62 confirm the existing `host_path` volume mechanism this migration reuses for MongoDB
- `terraform/modules/ecs_capacity/main.tf:1-102` — the ASG-backed EC2 capacity-provider module; lines 1-51 (launch template, `block_device_mappings`, `user_data`) are the concrete vehicle for host-level prep
- `~/.claude/docs/DOCKER-IMAGE-TOOL-REPOSITORIES.md` — the governing standard for the new repo
- `~/.claude/docs/AUTOMATED-DEPENDENCY-UPDATES.md` — the three-layer dependency-update model the new repo plugs into
- `~/.claude/docs/DEPLOYMENT-STRATEGY.md` — the phased-vs-single deploy decision framework applied to the cutover phase
- [github.com/jippi/docker-pritunl](https://github.com/jippi/docker-pritunl) — docker-compose.yml (`privileged: true`) and README (`--network=host` default path)
- [github.com/goofball222/pritunl](https://github.com/goofball222/pritunl/blob/main/README.md) — README (WireGuard kernel-module host requirement, `network_mode: bridge`, `privileged: true`)
- [hub.docker.com/u/pritunl](https://hub.docker.com/u/pritunl) — confirms no official Pritunl VPN image exists
- [forum.pritunl.com/t/is-aws-documentdb-supported-as-a-database/1299](https://forum.pritunl.com/t/is-aws-documentdb-supported-as-a-database/1299) — DocumentDB incompatibility (capped collections / tailable cursors)
- [docs.renovatebot.com/modules/manager/regex/](https://docs.renovatebot.com/modules/manager/regex/) — the `datasource=github-releases` + `ARG/ENV ..._VERSION=` comment-annotation example, quoted verbatim above
- [github.com/pritunl/pritunl/releases](https://github.com/pritunl/pritunl/releases) — Pritunl's own four-field version-tag scheme (`v1.34.4681.89`)
- [github.com/pritunl/pritunl/blob/master/data/systemd/pritunl.service](https://github.com/pritunl/pritunl/blob/master/data/systemd/pritunl.service) — Pritunl's own systemd unit file, quoted verbatim in "Residual open items"
- `pgbouncer/Dockerfile:18-25` — the explicit-`STOPSIGNAL`-with-rationale pattern this migration mirrors for `SIGTERM`
- See auxiliary file: `pritunl-ecs-migration_options-comparison_1.html` — the historical options record, superseded by this document as the plan of record

---

> **Authoring:** written by `@agent-plan-composer` from the engineer-validated `PLAN-SPIKE.md` (status: CONVERGED — all seven sub-decisions already decided by the engineer prior to composition). No new options, no new technical decisions, no new assumptions were introduced at the composer stage — every claim traces to the draft. The `output-verifier` and `policy-verifier` run scope-containment, citation-integrity, contract-compliance, template-compliance, reference-resolution, and policy-conformance checks after this write.
