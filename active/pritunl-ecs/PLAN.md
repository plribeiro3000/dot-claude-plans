# PLAN — Pritunl VPN: VM to Containerized ECS Migration

> Reference: `~/.claude/docs/DOCKER-IMAGE-TOOL-REPOSITORIES.md`, `~/.claude/docs/AUTOMATED-DEPENDENCY-UPDATES.md`, `~/.claude/docs/DEPLOYMENT-STRATEGY.md`; derived from `PLAN-SPIKE.md` (engineer-approved, second-pass revision)
>
> **Revised 2026-07-16** — five corrections:
> 1. The dedicated Mongo VM boots the **MongoDB golden AMI** (8.0 / Ubuntu 24.04, no Ansible on the VM), superseding the "trimmed Ansible role" path this plan recommended before that pipeline existed. Consequence: `4shark.pritunl` is deleted **entirely** at Phase 4 (decisions 3, 7, the Ansible mapping, Phase 4).
> 2. The series is **8.0**, not 8.2 — the cutover carries **no MongoDB version change** at all.
> 3. **The Pritunl container is NOT stateless** — `/var/lib/pritunl/pritunl.uuid` is filesystem-resident host identity that no `mongodump` carries, and a volume-less task regenerates it on every start. **New SPIKE-9, gates PR 2.4.** See the `pritunl.uuid` row in Risks.
> 4. Decision 2 (ECS on **EC2**, not Fargate) re-verified against AWS's own docs and **reconfirmed** — the blocker is device mappings (`/dev/net/tun`), which is protocol-independent. Not reopenable as a protocol choice.
> 5. The Pritunl **image's** Ubuntu base is a decision separate from all of the above, currently **broken on `develop`** (base bumped to 26.04, pins left at noble). See decision 1.
> 6. **SPIKE-3 reversed — the Mongo SG is SG-based, not CIDR-scoped.** The prior resolution rested on three false claims (a "zero SG-to-SG precedent" produced by a bad grep, and two runbooks that govern other situations). The governing standard, `terraform/docs/NETWORK-ACCESS-MODEL.md`, was never consulted and mandates the opposite. See decision 3 and the retracted grounded fact.
> 7. **New decision 4 — resource naming.** Everything this migration creates is `vpn-*` per ADR-010: no `4shark-` prefix, no `-001`. Nothing is renamed; the migration recreates these resources anyway, so the old names simply retire with the old VM. Decisions 5-8 renumbered accordingly.
> 8. **Build credentials were missing from this plan entirely** — it provisioned ECR but no identity that could push to it, and `build.yaml` has failed on every run since the scaffold. Added as PR 2.4 (option A: Terraform-managed IAM user + static key, **both** environments declared). PRs renumbered: 2.4 credentials → 2.5 staging → SPIKE-9 → 2.6 prod.
> 9. **New Phase 5 — the OIDC spike.** Option A's cost is a long-lived credential; option B (OIDC) removes it but is greenfield here. Phase 5 writes the spike + plan for that migration and leaves them ready, unscheduled, for whenever the engineer picks it up. Two unrelated findings from the same diagnosis are recorded under "Out of scope — follow-ups".
> Auxiliary: `pritunl-ecs-migration_options-comparison_1.html` (historical options record — every discarded alternative, its pros/cons/cost/risk, and citations — superseded by this document as the plan of record)

## Objective

Migrate 4Shark's Pritunl VPN gateway from its current single-EC2-VM deployment (Ansible-provisioned) to a containerized deployment on ECS, following the "Docker-image tool repository" standard already applied to `pgbouncer` and `keycloak`. The engineer has decided: a 4Shark-authored Dockerfile installing Pritunl's own official signed package, ECS on a single dedicated EC2 container instance (privileged + host networking), MongoDB on a **dedicated VM booted from the MongoDB golden AMI, separate from the Pritunl container** (not a sidecar, and not provisioned by Ansible), the existing Elastic IP reassociated to the new production instance, a **HubFlow branch model** (`develop`/`master`, mirroring `keycloak`) with a `-staging` Pritunl instance normally scaled to zero, the config-owning parts of the current Ansible role folded into the Dockerfile/entrypoint while host-only prep (kernel modules, device nodes, OS hardening) moves to the EC2 launch template and the MongoDB tasks are superseded by the golden AMI (retiring the role entirely), and a cutover model that separates the **recurring** HubFlow staging→prod promotion flow from the **one-time** VM→ECS migration (parallel stand-up, state migration, pre-flip validation, a single maintenance-window EIP flip, old VM kept stopped for rollback).

## Scope

### In scope

- A new `pritunl` tool repository conforming to `DOCKER-IMAGE-TOOL-REPOSITORIES.md`'s **HubFlow shape** (Dockerfile, Renovate custom-manager config + runner, hadolint CI, min-age gate, `develop`/`master` branches, per-target build-on-merge, deploy-on-demand)
- Terraform changes in the `terraform` repo: new ECS/EC2 resources for a **production** Pritunl instance and a **staging** Pritunl instance (normally at zero capacity), a **dedicated MongoDB VM**, security groups, IAM roles — replacing `terraform/vpn/` and `terraform/modules/pritunl/`, while reusing the existing `aws_eip` resource for production
- **Full retirement of `ansible/roles/4shark.pritunl/`**: its config-owning tasks move into the Dockerfile/entrypoint, a thin host-prep responsibility (WireGuard kernel module, `/dev/net/tun`, base OS hardening) moves to the EC2 launch template / AMI / user-data, and its MongoDB-owning tasks are **superseded by the golden AMI** — not retargeted anywhere. No fragment of the role survives *(revised 2026-07-16; this previously scoped the MongoDB tasks as "retargeting, not retirement")*
- Preservation of the current VPN's externally-observable behavior: fixed public IP (production), OpenVPN + WireGuard connectivity, `*.4shark.internal` DNS resolution for connected clients, per-IP brute-force protection, and the existing MongoDB-held org/user/profile state
- Governance: adding the new `pritunl` repo to `terraform/identity/github_repositories.tf`'s `local.hubflow_repositories` and (once CI produces the check) `local.hubflow_repositories_with_min_age_check` — **not** `local.main_branch_repositories`; creating two per-target ECR repositories (`<environment>` and `<environment>-staging`)
- A recurring operational flow: merge to `develop` → staging image builds → `-staging` instance scaled up → validate → `git hf release` → `master` image builds → production deploy — the standing model for every future Pritunl version bump, distinct from the one-time VM migration

### Out of scope

- VPN gateway high availability (multi-instance) for production — the engineer's decision keeps a single dedicated container instance per environment (production, staging), matching today's posture; not a goal of this migration
- MongoDB high availability (replica set) — the engineer's decision is a single dedicated Mongo VM, not a replica set; matches the single-dedicated-instance posture applied to Pritunl itself
- Client-side rollout mechanics beyond the high-level cutover phases below (how individual engineers are notified/reconnect) — a communication-plan detail for the maintenance window, not an infrastructure decision

## Current architecture (what is being migrated away from)

- **Terraform stack**: `terraform/vpn/main.tf:10-27` instantiates `module.pritunl` with a fixed AMI, `t3a.micro`, in the management VPC's public subnet (`vpc-0bdc76f3b391694dd`, subnet `management-pub-a`), ports 14720 (OpenVPN) and 14721 (WireGuard).
- **Module** `terraform/modules/pritunl/main.tf:1-44`: a bare `aws_instance` with `lifecycle { ignore_changes = [ami, user_data, user_data_base64] }` (Ansible manages the OS post-boot, not Terraform), plus `aws_eip` (lines 32-39) + `aws_eip_association` (lines 41-44) giving the instance a static public IP.
- **IAM** `terraform/modules/pritunl/iam.tf:29-49`: the instance role grants `ec2:DescribeRouteTables`/`CreateRoute`/`ReplaceRoute`/`DeleteRoute` — Pritunl's own VPC route advertisement for the OpenVPN client subnets (confirmed by `terraform/modules/pritunl/README.md:111`: *"OpenVPN routes (100.80/16, 100.96/16) and client profiles are configured inside Pritunl directly — Terraform only provisions the EC2 instance, not the VPN configuration"*). This IAM shape carries forward unchanged onto the new production ECS-EC2 instance's role — the same binary, running as a container instead of a systemd service, still needs to advertise the same routes.
- **Ansible role** `ansible/roles/4shark.pritunl/tasks/main.yml:1-264`: disables the host's `systemd-resolved` DNS stub listener and symlinks `/etc/resolv.conf` (lines 12-25, a host-level DNS setup task, distinct from the VPN-client-forwarding dnsmasq block further down); installs MongoDB 8.0 from apt (lines 32-79); installs Pritunl + WireGuard from `repo.pritunl.com/stable/apt` **unpinned** (lines 83-113); configures logrotate for pritunl/mongod (115-131); installs and configures **dnsmasq** to forward VPN-client DNS queries to the VPC resolver for `*.4shark.internal` (133-187); sets Pritunl's Mongo URI/rate-limiting/auditing via `pritunl set-*` commands (191-201); installs **fail2ban** watching `/var/log/pritunl_journal.log` for `admin_auth_failure` events, banning the source IP (203-237); and retrieves/displays one-time setup credentials (241-263).
- **dnsmasq specifics**: `ansible/roles/4shark.pritunl/templates/dnsmasq-vpn.conf.j2:1-19` binds to the VPN virtual interface address (`pritunl_dnsmasq_listen_address`, set per-host in `ansible/playbooks/vars/pritunl/4shark-vpn-001.yml:6` to `10.149.176.1`) and forwards to the VPC DNS resolver (`10.255.0.2`, same file line 7); `dnsmasq-override.conf.j2:1-11` makes the systemd unit start `After=`/`Requires=pritunl.service` because dnsmasq cannot bind the VPN interface address until Pritunl has created it.
- **fail2ban specifics**: `ansible/roles/4shark.pritunl/templates/fail2ban-filter-pritunl.conf.j2:1-9` matches `admin_auth_failure` events in Pritunl's JSON audit log; `fail2ban-jail-pritunl.conf.j2:1-9` bans for 7 days (`pritunl_fail2ban_bantime: 604800`, `defaults/main.yml:30`) after a single failed attempt (`pritunl_fail2ban_maxretry: 1`, `defaults/main.yml:29`) — the per-IP protection layer, since Pritunl's own global rate limiter is deliberately disabled (`pritunl_auth_limiter_count_max: 999999`, `defaults/main.yml:22`, comment: *"Set to 999999 to effectively disable — per-IP protection is handled by fail2ban"*).
- **Ubuntu codename target**: `ansible/roles/4shark.pritunl/defaults/main.yml:9,18` — `pritunl_mongodb_ubuntu_codename: "noble"` and `pritunl_ubuntu_codename: "noble"`, i.e. Ubuntu 24.04 LTS. `defaults/main.yml:6` pins the currently-installed MongoDB line at `8.0`.

## Grounded external facts

- **No official Pritunl (VPN) Docker image exists.** Docker Hub's `pritunl` organization publishes only `pritunl/pritunl-zero` and `pritunl/pritunl-bastion` — confirmed by fetching `hub.docker.com/u/pritunl`: *"No, there is no official `pritunl` or `pritunl-vpn` image listed for the VPN server product. Only Pritunl Zero-related images are displayed on this organization page."*
- **Every container of Pritunl needs `privileged: true` (or explicit `/dev/net/tun` + capability grants) and host-loaded WireGuard kernel modules**, confirmed across community images' own documentation:
  - `github.com/jippi/docker-pritunl` docker-compose.yml: `privileged: true` on the `pritunl` service; README: *"If you don't want to use `network=host`, then replace the `--network=host` CLI flag with the following ports..."* — confirms host networking is the default-documented path.
  - `github.com/goofball222/pritunl` README/compose: `network_mode: bridge`, `privileged: true`, plus *"The Docker host is required to have wireguard kernel modules installed and loaded."*
  - Consistent with what the current Ansible role already does at the host level (`apt: name: [pritunl, wireguard, wireguard-tools]`, `tasks/main.yml:99-107`) — containerizing relocates where the *process* runs, not where the *kernel capability* lives. This is the technical basis for the host/image split in the Ansible-task mapping below: `wireguard` (kernel module, host-global — cannot be namespaced per-container) stays a host concern; `wireguard-tools` (the userspace CLI Pritunl's own process invokes) is just another apt package inside the image, same as `pritunl` itself.
- **AWS Fargate cannot satisfy this.** Fargate does not expose `privileged: true`, host kernel modules, or `network_mode: host` to a task. Corroborated indirectly: both existing 4Shark tool-repo precedents (`connection-pooler`/pgbouncer and `auth-001`/keycloak) run on Fargate (`terraform/modules/connection_pooler/main.tf:250-260` — `requires_compatibilities = ["FARGATE"]`; `terraform/auth-001/ecs.tf:22-27,41` — same) — meaning no existing 4Shark tool repo has already solved the privileged/host-network case; this migration is the first.
- **Amazon DocumentDB is explicitly unsupported by Pritunl as its database.** Fetched from `forum.pritunl.com/t/is-aws-documentdb-supported-as-a-database/1299`: *"Pritunl, Pritunl Zero and Pritunl Cloud all utilize capped collections and tailable cursors for publish subscribe messaging. This prevents using the MongoDB API compatible databases such as DocumentDB."* No fix timeline given — a hard blocker, ruling out DocumentDB entirely regardless of where MongoDB itself is placed.
- **`modules/ecs_service` today has no privileged/host-network branch** — `terraform/modules/ecs_service/main.tf:14` — `network_mode = var.launch_type == "FARGATE" ? "awsvpc" : "bridge"` — EC2 launch type gets `bridge`, never `host`, and there is no `privileged` variable exposed anywhere in the module's `container_definitions` block (`main.tf:21-54`, no `privileged` key present). This module cannot be reused unmodified for this migration; the new task definition is either a bespoke `aws_ecs_task_definition` (as `modules/pritunl` today is a bespoke `aws_instance`, not a reuse of a generic module) or an extension to `ecs_service` adding a `privileged` variable and a `host` network-mode branch.
- **`modules/ecs_service` already supports a host-path-backed Docker volume** — `terraform/modules/ecs_service/main.tf:56-62` (`volume { host_path = try(volume.value.host_path, null) }`). This mechanism was the basis for the first-pass draft's colocated-MongoDB-sidecar design; it remains true infrastructure knowledge but is **no longer invoked by this migration** — MongoDB is placed on a dedicated VM, not a sidecar container, so no `host_path` volume wiring is needed for Mongo on the Pritunl task definition.
- **`modules/ecs_capacity` is the existing ASG-backed EC2 capacity-provider module** (`terraform/modules/ecs_capacity/main.tf:1-102`) already used by the EC2-launch-type fleet (`app-outbound-*`, `integrator-*`, `onboarding`, `setup`); its `aws_launch_template` (lines 1-51) already carries `block_device_mappings` for the root volume (7-13) and a `user_data` block that registers the instance with the target ECS cluster (24-28: `echo ECS_CLUSTER=${var.cluster_name} >> /etc/ecs/ecs.config`). This `user_data` block is the concrete vehicle for the host-level prep the Ansible-task mapping moves out of the container (WireGuard kernel module load, `/dev/net/tun` presence, base OS hardening) — it is the same mechanism already in production, just extended with the additional bootstrap commands.
- **ECS managed scaling cannot cleanly scale a capacity-provider ASG from zero to one instance.** Fetched from `docs.aws.amazon.com/AmazonECS/latest/developerguide/cluster-auto-scaling.html`, verbatim: *"When Amazon ECS scales out from 0 instances, it automatically launches 2 instances."* This is the grounded reason the staging Pritunl host is not brought up via `ecs_capacity`'s managed-scaling-from-zero — see decision 8 below.
- ~~**No existing 4Shark Terraform precedent for security-group-to-security-group scoping**~~ — **RETRACTED 2026-07-16: this "grounded fact" was false, and it propagated into SPIKE-3's (now reversed) CIDR resolution.** It rested on an empty `grep -rn "source_security_group_id" terraform/`, but the codebase never uses that argument — it expresses SG references as an inline `ingress { security_groups = [...] }` block, which that grep cannot match. **SG-based ingress is the fleet's standard shape**, with precedent throughout: RDS 5432 from the pooler SG + app cluster SG (`app-shared-001/rds.tf:18-24`), OpenSearch 443 from the app cluster SG, the connection pooler 6432 from the app cluster SG (`modules/connection_pooler/main.tf`), the app ECS instances from the public ALB SG (`modules/ecs_cluster/main.tf`).
- **The governing standard is `terraform/docs/NETWORK-ACCESS-MODEL.md`** — the repo's canonical answer to "when to allow by security group vs by IP/CIDR vs by SaaS allowlist", which this plan never consulted. Its decision table (`:45`) places this case unambiguously: a source that is *"An AWS resource in the **same region + reachable VPC**"* → **SG-based (default)**; CIDR is the fallback *"only where a security group cannot express the source"* (`:26`), and then at the tightest range. The Pritunl instance and the Mongo VM are both in the management VPC in `sa-east-1`. The doc also forecloses re-litigating it per stack: *"This was once decided case by case; it is now a fixed standard"* (`:3`). The `auth-001` CIDR shape this plan cited as "the current convention" is an older stack, not the standard.
- **SG-based allows are identity-pinned — the real cost of choosing correctly here** (`NETWORK-ACCESS-MODEL.md:69`). An allow references a specific SG id, so rebuilding the source with a **new** SG silently voids it — the exact gap that took down `app-atento-001` when a cutover pointed traffic at a cluster whose SG was not yet whitelisted on the pooler. Directly relevant: this migration rebuilds the Pritunl instance, so re-check this allow at cutover.
- **No existing 4Shark Terraform module for a generic bare `aws_instance` VM** beyond `terraform/modules/pritunl` itself — confirmed by grepping every `terraform/modules/*/main.tf` for `aws_instance`; every other stateful/tool module (`connection_pooler`, `rds_instance`, `rds_aurora_cluster`, `mongodb_atlas`) is either Fargate-based or a managed-service resource, not a bare EC2 instance. The dedicated Mongo VM is provisioned the same way the current combined VM already is — a bare `aws_instance`, Ansible-managed post-boot — there is no closer-fitting existing module to reuse.
- **`terraform/identity/github_repositories.tf:60-75`** — `local.hubflow_repositories` currently lists `ansible`, `app`, `app-mobileclient`, `app-sdk-advpl`, `app-sdk-dotnet`, `app-webclient`, `dot-claude`, `integrator`, `keycloak`, `lambda`, `onboarding`, `setup`, `simplex-harvester`, `terraform`; **`:81-91`** — `local.hubflow_repositories_with_min_age_check` lists `ansible`, `app`, `app-webclient`, `integrator`, `keycloak`, `lambda`, `onboarding`, `setup`, `terraform`. `pritunl` is added to both, following `keycloak`'s presence in each.
- **`terraform/auth-001/ecr.tf:1-29`** — confirms `keycloak`'s branch-model shape uses **two separate ECR repositories**, not one shared repo: `aws_ecr_repository.auth_001` (name `"auth-001"`) and `aws_ecr_repository.auth_001_staging` (name `"auth-001-staging"`), each with identical scanning/encryption config. The new Pritunl repos follow the same two-repository shape.
- **`terraform/auth-001/auth_001_staging.tf:1-194`** — the existing 4Shark precedent for a non-productive validation instance: `aws_ecs_service.auth_001_staging` runs `desired_count = 0` (line 152) on **Fargate** capacity (`capacity_provider_strategy { capacity_provider = "FARGATE" }`, lines 154-158), reusing the production cluster, VPC, security groups, ALB, and RDS instance, isolated only by its own database, hostname, target group, and log group (file header comment, lines 1-11). Because Fargate has no separate EC2 host to also stop, a desired-count-0 Fargate service carries no idle compute cost — this property does **not** transfer to Pritunl's EC2-backed runtime, which is the basis for decision 8's staging-instance mechanism finding below.
- **`terraform/auth-001/security_groups.tf:11-23,41-47`** — the current 4Shark security-group convention: `aws_vpc_security_group_ingress_rule` resources scoped by VPC CIDR (`10.255.0.0/16`), used even for RDS access (`rds_postgres` rule, lines 41-47) rather than security-group-to-security-group references.

## Chosen approach

**Direction:** Containerize Pritunl via a 4Shark-authored Dockerfile built from Pritunl's own official apt repository, deployed on ECS running on a single dedicated EC2 container instance per environment (privileged + host networking, no HA within an environment). MongoDB runs on a dedicated MongoDB VM, separate from the Pritunl container. The existing Elastic IP is reassociated to the new production instance. The new `pritunl` repository follows a **HubFlow branch model** (mirroring `keycloak`): `develop` builds the staging image, deployed to a `-staging` ECS instance normally scaled to zero; `master` builds the production image. The config-owning parts of the current Ansible role move into the Dockerfile/entrypoint; host-only prep (WireGuard kernel module, `/dev/net/tun`, base OS hardening) moves to the EC2 launch template; MongoDB-owning tasks retarget to the dedicated Mongo VM. Cutover separates the recurring HubFlow staging→prod promotion flow (every future Pritunl version bump) from the one-time VM→ECS migration, which happens in a maintenance window preceded by a pre-flip parallel-validation step on a temporary second IP.

**Rationale (from engineer):** every community Docker image was ruled out because they carry an unofficial supply-chain dependency on a single external maintainer; a self-built image from Pritunl's own signed repo matches the trust model 4Shark already runs today and matches `pgbouncer`'s and `keycloak`'s pattern of a 4Shark-owned Dockerfile. Fargate was ruled out because it structurally cannot grant the privileged/host-network/kernel-module access every community image documents as required. A single instance per environment matches today's posture (HA was explicitly decided out of scope). DocumentDB was ruled out as a hard blocker (unsupported capped collections/tailable cursors). The engineer moved MongoDB from a colocated sidecar to a **dedicated VM** because separating Mongo from the Pritunl container removes state from the ECS task's lifecycle entirely — a Pritunl container replacement (image bump, task restart, host replacement) no longer carries risk to the database, and the Mongo VM's own lifecycle (patching, backup, resizing) is decoupled from Pritunl's own release cadence; it also keeps MongoDB's install/config shape exactly as it is today (a real VM running a systemd-managed `mongod`), rather than re-platforming it into a container. The existing EIP is reassociated rather than replaced so client `.ovpn`/WireGuard profiles need no change. The engineer moved the branch model from main-only to **HubFlow** specifically to gain a non-production instance to validate a new Pritunl image before it reaches the VPN gateway every engineer depends on — the exact condition `DOCKER-IMAGE-TOOL-REPOSITORIES.md` names for the HubFlow shape: *"HubFlow — develop + master (the 4Shark GitFlow), for an actively-versioned tool that validates each new image on a non-production instance before production. Reference: keycloak."* (`~/.claude/docs/DOCKER-IMAGE-TOOL-REPOSITORIES.md:18`). Config-owning Ansible tasks move into the image/entrypoint because `privileged: true` + host networking gives the Pritunl container the same network-namespace and iptables reach the current host-level dnsmasq/fail2ban processes rely on. The engineer separated the **cutover model** into a recurring HubFlow staging→prod flow and a one-time VM→ECS migration because conflating them would mean every routine version bump re-runs a maintenance-window/EIP-flip procedure that should only ever happen once.

**Source patterns referenced:**
- `ansible/roles/4shark.pritunl/tasks/main.yml:83-107` — today's unpinned apt-install source, now pinned via `ARG`
- `pgbouncer/Dockerfile:1-32` — the tag+digest pin + Renovate-tracking comment pattern (adapted here for a custom-manager annotation instead of a `FROM` tag, since there is no upstream Docker image)
- `pgbouncer/renovate.json:11-16` — the precedent for a per-package `versioning: regex:` override when the upstream tag scheme is non-semver
- `terraform/modules/pritunl/main.tf:32-39` (`aws_eip`) and `:41-44` (`aws_eip_association`) — the exact resource shape carried forward
- `~/.claude/docs/DOCKER-IMAGE-TOOL-REPOSITORIES.md:13-20` — "Two repo shapes" section, the condition for choosing HubFlow over main-only
- `keycloak/.github/workflows/build.yaml:1-108`, `deploy.yaml:1-101` — the HubFlow build/deploy shape this repo mirrors
- `terraform/auth-001/ecr.tf:1-29` — the two-ECR-repo pattern

### 1. Base image — 4Shark-authored Dockerfile from Pritunl's own official apt repo

**Decision:** `FROM ubuntu:24.04` (noble — matches the Ansible role's current target, `ansible/roles/4shark.pritunl/defaults/main.yml:9,18`), add Pritunl's own signed apt repo (`repo.pritunl.com/stable/apt`, same source as `ansible/roles/4shark.pritunl/tasks/main.yml:93-97`), install the official `pritunl` `.deb` pinned via a Dockerfile `ARG PRITUNL_VERSION`. Not a community image (jippi/goofball222/omegion).

**The image's Ubuntu version is a real, permanent decision — it does NOT go away when the VPN moves to ECS.** *(Recorded 2026-07-16 to close a live misreading.)* A container carries its own userland: the image is literally `FROM ubuntu:<version>` and apt-installs `pritunl`, `dnsmasq`, `fail2ban` and `wireguard-tools` from that release's archive. The host EC2's operating system is **independent** of it — this image would still be Ubuntu 24.04 if the ECS container instance ran Amazon Linux, which it in fact will. What containerizing removes is **Ansible provisioning the host's OS**, not the image's base. Two corollaries worth stating because both have been assumed the other way:
- **The current VPN VM was never 26.04.** It runs `ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-20260218` (`ami-032ab7316dbf1ea74`, `terraform/vpn/main.tf`) — Ubuntu 24.04. The `26.04` on `develop` came from a Renovate major bump (PR #7), not from anything in Terraform, and has no relationship to the EC2 at all.
- **MongoDB's `noble` ceiling is not the reason to stay on 24.04 here.** This image installs no MongoDB (decision 3 puts Mongo on its own VM), so MongoDB's apt-repo support has zero bearing on this base. The reason is internal to this Dockerfile: the apt-source line hardcodes `noble` and all seven `ARG` pins are noble-era versions. Base and pins are one coupled decision. That coupling — and the fact that Renovate broke it on `develop` — is the Renovate risk row below.

**Auto-update loop for a self-built package image:** `DOCKER-IMAGE-TOOL-REPOSITORIES.md`'s item 2 assumes a `FROM upstream/image:<tag>@sha256:<digest>` — Renovate's `docker` datasource tracks a base-image tag directly. An apt-installed `.deb` has no such tag for that datasource to read. Renovate's own regex custom-manager docs describe exactly this gap. Fetched from `docs.renovatebot.com/modules/manager/regex/` (Advanced Capture section), verbatim:
```
# renovate: datasource=github-releases depName=composer packageName=composer/composer
ENV COMPOSER_VERSION=1.9.3
```
with the matching `matchStrings` regex:
```
"# renovate: datasource=(?<datasource>[a-z-]+?)(?: depName=(?<depName>.+?))? packageName=(?<packageName>.+?)(?: versioning=(?<versioning>[a-z-]+?))?\\s(?:ENV|ARG) .+?_VERSION=(?<currentValue>.+?)\\s"
```
This is directly reusable for the Pritunl Dockerfile: annotate `ARG PRITUNL_VERSION=<pinned>` with `# renovate: datasource=github-releases packageName=pritunl/pritunl`, and add a `customManagers` block to `renovate.json` using that `matchStrings` pattern (`managerFilePatterns: ["/^Dockerfile$/"]`, `datasourceTemplate: "github-releases"`). The `github-releases` datasource resolves `releaseTimestamp` from the GitHub release's own publish date, so the 7-day `minimumReleaseAge` quarantine computes normally — no exemption needed.

**Version-scheme caveat:** fetching `github.com/pritunl/pritunl/releases` shows tags of the shape `pritunl v1.34.4681.89`, `pritunl v1.34.4649.96`, `pritunl v1.32.4567.52` — a four-numeric-field scheme (`major.minor.build.patch`), not three-field semver. `edoburu/pgbouncer` hit the same class of problem with its `-pN` build suffix and needed an explicit `versioning: regex:...` override (`pgbouncer/renovate.json:11-16`). The Pritunl `ARG` custom manager likely needs the same treatment — flagged as a pre-implementation verification item (see Residual open items).

**Source patterns referenced:**
- `ansible/roles/4shark.pritunl/tasks/main.yml:83-107` — today's unpinned apt-install source, now pinned via `ARG`
- `pgbouncer/Dockerfile:1-32` — the tag+digest pin + Renovate-tracking comment pattern
- `pgbouncer/renovate.json:11-16` — the precedent for a per-package `versioning: regex:` override
- [docs.renovatebot.com/modules/manager/regex/](https://docs.renovatebot.com/modules/manager/regex/) — the `datasource=github-releases` + `ENV/ARG ..._VERSION=` comment-annotation pattern, quoted verbatim above
- [github.com/pritunl/pritunl/releases](https://github.com/pritunl/pritunl/releases) — confirms the `v1.34.4681.89`-style four-field tag scheme

### 2. Runtime / launch type — ECS on EC2, single dedicated container instance (per environment)

**Decision:** ECS on EC2 (Fargate ruled out — grounded fact above). A single dedicated ECS container instance, `privileged: true` + host networking, WireGuard kernel modules present on the host. No HA / multi-instance within an environment. "Single dedicated instance" applies **per environment** — the production Pritunl instance and the `-staging` Pritunl instance are each their own single dedicated instance, never sharing a host, never load-balanced; the HubFlow branch model adds a second environment, it does not change the no-HA-within-an-environment posture.

**Re-verified against AWS's own documentation 2026-07-16 — Fargate remains impossible, and the reason is more fundamental than this decision originally recorded.** The original grounding leaned on community images' READMEs (what *Pritunl* needs); the authoritative constraint is on AWS's side (what *Fargate* refuses), and all four blockers hold today:
- **`awsvpc` is mandatory on Fargate** — `host` network mode is EC2-only.
- **`privileged` is not supported** on Fargate.
- **`CAP_NET_ADMIN` is explicitly blocked** — Fargate restricts added Linux capabilities to prevent privilege escalation; only `CAP_SYS_PTRACE` is permitted.
- **Device mappings are not supported at all** — so `/dev/net/tun` cannot be exposed. `aws/containers-roadmap` issue [#239](https://github.com/aws/containers-roadmap/issues/239) requests exactly this, **opened April 2019 and still open with no AWS response after 7 years**. It was filed by someone trying to run BoringTun (userspace WireGuard) on Fargate — the same use case as this migration.

**The device blocker is protocol-independent — this is the load-bearing point.** `/dev/net/tun` is what *any* tunnel needs: WireGuard, OpenVPN, IPsec alike. So "use a simpler VPN protocol to fit Fargate" is not an available trade — there is no protocol that establishes a tunnel without a tun device. On Fargate the Pritunl container would start, pass health checks, and serve no VPN to anyone. **Do not reopen this as a protocol choice; the choice is tunnel or no tunnel.**

**What EC2 launch type actually costs — one line, not "managing an OS".** The ECS container instance runs the ECS-optimized AMI: AWS publishes and patches it, adoption is a Terraform apply, no Ansible, no per-host provisioning. The OS-management burden the VM model carried does not survive this migration under either launch type. The single OS-touching item that remains is the launch template's `user_data` loading the WireGuard kernel module + ensuring `/dev/net/tun` — and it exists solely because a kernel module is host-global and cannot be namespaced into a container. That line is the entire delta between EC2 and Fargate here.

**Source patterns referenced (added 2026-07-16):**
- [docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-security-considerations.html](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-security-considerations.html) — capabilities lockdown (`CAP_NET_ADMIN` restricted, `CAP_SYS_PTRACE` the sole exception)
- [docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-task-networking.html](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-task-networking.html) — `awsvpc` required on Fargate
- [docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html) — `privileged` unsupported on Fargate
- [github.com/aws/containers-roadmap#239](https://github.com/aws/containers-roadmap/issues/239) — `/dev/net/tun` request, open since 2019-04-05, unanswered

**Source patterns referenced:**
- `terraform/modules/ecs_service/main.tf:14` — confirms EC2 launch type today only ever gets `bridge`, never `host`, and no `privileged` variable exists — new Terraform work is required (bespoke task definition or an `ecs_service` extension)
- `terraform/modules/ecs_capacity/main.tf:1-102` — the reusable ASG-backed EC2 capacity-provider module, directly reusable for a single dedicated instance (subject to decision 8's finding about scale-from-zero for the staging instance specifically)
- `terraform/modules/connection_pooler/main.tf:250-260`, `terraform/auth-001/ecs.tf:22-27,41` — confirm no existing 4Shark tool repo has solved the privileged/host-network case (both existing tool repos are Fargate)

### 3. MongoDB — dedicated VM booted from the MongoDB golden AMI, separate from the Pritunl container

**Decision:** MongoDB runs on a **dedicated MongoDB EC2 VM launched from the MongoDB golden AMI**, separate from the Pritunl ECS container — not a colocated sidecar, not DocumentDB (hard blocker). The Pritunl ECS instance reaches the Mongo VM over the VPC (private, not publicly exposed). State migration: `mongodump` on the current combined VM → `mongorestore` into the new dedicated Mongo VM.

**"The Pritunl container is stateless" — CORRECTED 2026-07-16. It is not, and this plan asserted it without checking.** Nearly all Pritunl state (orgs, users, VPN profiles, the dynamic OpenVPN routes) does live in MongoDB, so the `mongodump`/`mongorestore` migration path is sound and no configuration is rebuilt by hand at cutover. **But host identity is the exception**: `/var/lib/pritunl/pritunl.uuid` is a filesystem-resident 32-character string identifying this host within the Pritunl cluster. It is not a Mongo document, so it does not travel in a dump, and it is regenerated whenever it is absent — which, for a container with no persistent volume, is every single start. See the `pritunl.uuid` row in Risks for the mechanism, the deploy-time consequence, and the candidate directions. **This must be settled before PR 2.4 authors the task definition.**

**This is the one EC2 instance in the target architecture that exists *for* an OS.** The Pritunl ECS container instance is also EC2 — decision 2 requires it (Fargate cannot grant `privileged`/host-networking/kernel modules) — but that host is a generic ECS container host whose OS is an ECS-optimized AMI, not something this migration provisions or versions. The Mongo VM is the opposite: its whole value is the OS image it boots. So "which Ubuntu?" is a live question for exactly one instance here, and the golden AMI answers it.

**MongoDB install/config placement — the golden AMI, no provisioning on the VM at all.** *(Revised 2026-07-16 — supersedes the "trimmed Ansible role" path this decision previously recommended. That path is dead: it was written before the MongoDB golden-AMI pipeline existed.)*

The Mongo VM launches **from the MongoDB golden AMI** — Ubuntu 24.04 + MongoDB 8.0, already installed, configured and systemd-enabled inside the image — selected via a tag-filtered `data "aws_ami"` lookup. **No Ansible role runs on this VM, ever.** This is the same image the entire integrator Mongo fleet now runs (12 nodes across four clients, cut over 2026-07-14/15), so the Pritunl Mongo VM inherits an image already burned in on production replica sets rather than being its own first user.

The two paths this decision previously weighed — a trimmed Ansible role retargeted at the Mongo VM, or fresh hand-rolled provisioning — are **both moot**. The question they answered ("how does Ansible provision this VM?") no longer has a subject: the provisioning happens once, at image-build time, in the `mongodb` repo's Packer build consuming `ansible-role-mongodb`. The VM just boots it. This also closes, at the image, the 8.0-vs-drift concern the old path carried — the AMI is the single source of the installed series.

**Version and OS are not choices here — both are pinned upstream** (full grounding in `~/Projects/4Shark/dot-claude-plans/active/mongodb-golden-ami/PLAN.md` § "Version and OS are both pinned by upstream constraints"):
- **MongoDB 8.0**, the X.0 LTS line — rapid releases (8.1/8.2/8.3) are not for self-managed deployments.
- **Ubuntu 24.04 (`noble`)**, a ceiling — MongoDB's apt repo 404s for `resolute` (26.04), so a 26.04 node would have no MongoDB to install. Verbatim from `mongodb/packer/mongodb.pkr.hcl:71-75`: *"24.04 is the ceiling, not a waypoint ... Do not advance these past `noble` until that repo exists."*

**This constraint governs the Mongo VM only — it does NOT reach the Pritunl container image.** The Pritunl image installs no MongoDB (decision 1; the container reaches the Mongo VM over the VPC), so nothing about MongoDB's Ubuntu support bears on the Dockerfile's base. The Dockerfile's own base pin is a separate matter with a separate reason — see decision 1 and Risks.

**Network isolation:** a dedicated security group allows ingress on MongoDB's port from **the Pritunl instance's security group, by reference** — not a CIDR. *(Corrected 2026-07-16; this paragraph previously framed SG-based scoping as "a new pattern this migration would introduce" and deferred the mechanism to authoring time. Both were wrong.)* This is neither new nor a judgement call: `terraform/docs/NETWORK-ACCESS-MODEL.md` is the repo's canonical standard for this exact decision and mandates SG-based for any source that is an AWS resource in the same region and a reachable VPC (`:45`), which describes the Pritunl instance exactly. It is also the fleet's normal shape — see the retracted "grounded fact" above for the precedents this plan wrongly reported as nonexistent. The one thing to carry forward is the standard's own gotcha (`:69`): the allow is pinned to the Pritunl SG's identity, so it must be re-checked whenever that SG is rebuilt — including at this migration's cutover.

**State migration:** `mongodump` on the current combined VM's MongoDB → `mongorestore` into the new dedicated Mongo VM, positioned within Phase 3 below.

**Source patterns referenced:**
- `forum.pritunl.com/t/is-aws-documentdb-supported-as-a-database/1299` — the DocumentDB blocker, quoted above
- `~/Projects/4Shark/dot-claude-plans/active/mongodb-golden-ami/PLAN.md` — the golden-AMI pipeline; its Phase 2 IS this Mongo VM adoption, and its Phase 3 (12 integrator nodes, complete 2026-07-14/15) is the burn-in this VM inherits
- `mongodb/packer/mongodb.pkr.hcl:45-54` (series `8.0`, LTS-only), `:71-75` (`noble` ceiling, 26.04 has no MongoDB apt repo) — the two upstream pins quoted above
- `terraform/integrator-almaviva/mongodb.tf:33-35` — the deployed shape of a golden-AMI Mongo node (`ami = "ami-0244451ea895c4e3c"`, `ignore_changes = [ami, user_data, user_data_base64]`); note this stack pins the literal id where the golden-AMI plan's own decision calls for a `data "aws_ami"` tag lookup — that discrepancy is tracked in the golden-AMI plan, and PR 2.3 should use the tag lookup rather than copy the hardcoded id forward
- `ansible/roles/4shark.pritunl/tasks/main.yml:32-79` — today's self-managed MongoDB apt-install/config/systemd tasks. **Superseded, not retargeted**: these are now baked into the golden AMI via `ansible-role-mongodb`; the tasks are retired with the rest of the role in Phase 4, not moved
- `ansible/roles/4shark.pritunl/defaults/main.yml:6` — `pritunl_mongodb_version: "8.0"`, the series today's combined VM runs; the golden AMI installs the same `8.0`, so the migration carries no version change for Pritunl's own database
- `terraform/auth-001/security_groups.tf:11-23,41-47` — the current 4Shark ingress convention (CIDR-scoped, `aws_vpc_security_group_ingress_rule`), the base pattern the new dedicated Mongo SG departs from
- No existing 4Shark Terraform precedent for `referenced_security_group_id`/SG-to-SG scoping (confirmed by an empty repository-wide grep) — flagged, not asserted as an existing pattern

### 4. Resource naming — `vpn-*`, per ADR-010; the `4shark-vpn-001-*` scheme dies with the old VM

**Decision (added 2026-07-16):** every resource this migration creates is named `vpn-*` — no `4shark-` prefix, no `-001` suffix. The application is **`vpn`**; `pritunl` is the tool the repo is named after, exactly as `keycloak` (tool/repo) builds the `auth-001` (application) stack.

**Grounding:** `terraform/docs/adr/ADR-010-resource-naming-convention.md:27` — *"Every application prefixes its resources with the application name — `integrator-<client>-*`, `onboarding-*`, `setup-*`, `app-outbound-<client>-*` — across compute **and** infrastructure, no exception."* The only exception is the main `app` application's compute plane, which is not this.
- **No `-001`.** The numeric suffix is `app`'s environment sequence (`shared-001`, `atento-001`), not universal numbering. `setup` and `onboarding` carry none because there is one of each. `auth-001` carries one because authenticators are deliberately per-region-per-client-base (`auth-NNN`). There is exactly one VPN and no plan for a second — so no number, mirroring `setup`.
- **No `4shark-`.** ADR-010 uses `4shark-` only where the namespace is global and the "recognize it in the console" argument does not apply — S3 buckets (`ADR-010:36,50`). For EC2/SG/IAM the prefix is the application name. `4shark-vpn-001-*` is the same species as the `4client-*` scheme ADR-010 records as acknowledged technical debt (`:62-71`).

**Already conformant — no action:** the stack directory `terraform/vpn/` and the two ECR repositories `vpn` / `vpn-staging` (PR 2.1, merged) already follow the rule.

**Target names:**

| Today (`name_prefix = "4shark-vpn-001"`) | New |
|---|---|
| `4shark-vpn-001` (instance) | `vpn` |
| `4shark-vpn-001-sg` | `vpn-sg` |
| `4shark-vpn-001-eip` | `vpn-eip` |
| `4shark-vpn-001-role` / `-profile` | `vpn-role` / `vpn-profile` |
| `4shark-vpn-001-vpc-route` | `vpn-vpc-route` |
| — | `vpn-mongo`, `vpn-mongo-sg` (new, PR 2.3) |
| — | `vpn-cluster`, `vpn-staging-*` (new, PR 2.4/2.5) |

**This is NOT the piecemeal retrofit ADR-010 forbids.** `ADR-010:73-77` bars correcting deployed names reactively (*"never one at a time"*) — a rule that exists to protect **live resources from rename churn**. Nothing here is renamed: the migration destroys and recreates every VPN resource anyway (instance, SGs, IAM), and the Mongo VM does not exist yet. These are **new** resources, and for new resources the ADR is explicit: *"from this ADR forward, every **new** resource follows the rule."* The `4shark-vpn-001-*` names are retired when the old VM is at Phase 4 — no extra step, no migration cost.

**The one carried-over resource is the EIP, and it costs nothing.** Decision 5 reuses the existing `aws_eip` allocation deliberately (client profiles must not change), so only its `Name` tag moves to `vpn-eip`. Retagging an EIP does not touch the address.

### 5. Public entry — reassociate the existing Elastic IP (production only)

**Decision:** Reassociate the existing `aws_eip` allocation (from `terraform/modules/pritunl/main.tf`) to the new **production** ECS-EC2 instance, preserving the fixed public IP so client `.ovpn`/WireGuard profiles need no change. No NLB. Under host networking, the container shares the instance's network stack, so the association is instance-level (`aws_eip_association` against the new `aws_instance`, same shape as today), not an ENI belonging to a task. This decision covers the production instance only. The `-staging` instance does not get the production EIP; its own public-entry mechanism during a test window is a residual open item (see below).

**Source patterns referenced:**
- `terraform/modules/pritunl/main.tf:32-39` (`aws_eip`) and `:41-44` (`aws_eip_association`) — the exact resource shape to carry forward, re-targeting `instance_id`/`allocation_id` at the new production instance

### 6. Branch model — HubFlow (`develop`/`master`), mirroring `keycloak`

**Decision:** HubFlow, not main-only. `develop` builds the **staging** Pritunl image → the `-staging` ECS instance; `master` builds the **production** Pritunl image → the production ECS instance. A release promotes `develop` → `master` via `git hf release start/finish X.Y.Z`; the tag is the side effect of `finish` (not a manual `git tag`). The repo is named `pritunl`.

**Governance:** add `pritunl` to `local.hubflow_repositories` (`terraform/identity/github_repositories.tf:60-75`, where `keycloak` already appears) and to `local.hubflow_repositories_with_min_age_check` (`:81-91`, where `keycloak` already appears) once the repo's CI produces the `Verify Minimum Age` check — **not** `local.main_branch_repositories`.

**Build/deploy shape mirrors `keycloak` exactly** (`keycloak/.github/workflows/build.yaml:1-108`, `deploy.yaml:1-101`):
- `build.yaml` triggers on `push: branches: [develop, master]` plus `workflow_dispatch` with an `environment` choice input; one explicit job per target (staging / production), each pushing `:latest` + `:<short-sha>` to that target's own ECR repository using that target's GitHub Environment credentials. Verbatim from keycloak's own header comment: *"develop builds the staging image (auth-001-staging), master builds the production image (auth-001). One explicit job per target"* (`keycloak/.github/workflows/build.yaml:4-5`).
- `deploy.yaml` is a separate, manual `workflow_dispatch` — build and deploy are decoupled (`DOCKER-IMAGE-TOOL-REPOSITORIES.md` item 7, identical for both branch shapes) — `aws ecs update-service --force-new-deployment` against a per-target cluster/service/task-family map, then a poll loop waiting for `rolloutState == COMPLETED` (`keycloak/.github/workflows/deploy.yaml:31-35,59-100`).
- **Two separate per-target ECR repositories**, not one shared repo — `terraform/auth-001/ecr.tf:1-29`: `aws_ecr_repository.auth_001` (name `"auth-001"`) and `aws_ecr_repository.auth_001_staging` (name `"auth-001-staging"`). The Pritunl repo follows the same shape: two ECR repositories, one per target.

**Source patterns referenced:**
- `~/.claude/docs/DOCKER-IMAGE-TOOL-REPOSITORIES.md:13-20` — the "Two repo shapes" section, the condition for choosing HubFlow over main-only
- `~/.claude/docs/DOCKER-IMAGE-TOOL-REPOSITORIES.md:26-31`, `:66-71`, `:89-104` — every HubFlow-variant note in the standard
- `keycloak/.github/workflows/build.yaml:1-108` — full build workflow, quoted above
- `keycloak/.github/workflows/deploy.yaml:1-101` — full deploy workflow
- `terraform/auth-001/ecr.tf:1-29` — the two-ECR-repo pattern
- `terraform/identity/github_repositories.tf:60-75` (`local.hubflow_repositories`), `:81-91` (`local.hubflow_repositories_with_min_age_check`) — governance lists `pritunl` is added to

### 7. Ansible role fate — config into image/entrypoint; host-only prep into the launch template; MongoDB tasks superseded by the golden AMI

**Decision (three-target split):** the Pritunl-container-owned config (dnsmasq, fail2ban, Pritunl's own `set-*` commands, install) moves into the Dockerfile + `configured-entrypoint.sh`. Host-only kernel prep (WireGuard kernel module, `/dev/net/tun`, base OS hardening) moves to the EC2 launch template / AMI / user-data. The MongoDB tasks (`tasks/main.yml:32-79`) are **superseded by the golden AMI** — they are retired with the rest of the role in Phase 4, not retargeted anywhere. *(Revised 2026-07-16 — this third target previously read "retarget to the dedicated Mongo VM via a trimmed Ansible role".)*

**Rationale:** `privileged: true` + host networking (decision 2) gives the Pritunl container the same network-namespace/iptables reach dnsmasq and fail2ban need, so both stay co-located with Pritunl. Mongo's provisioning does not need a home in this migration at all: `ansible-role-mongodb` already owns it, one layer up, at image-build time. The whole role therefore dies at Phase 4 — no surviving fragment, no new inventory group, no `4shark.mongodb-pritunl` role to author.

**Net effect on the Ansible monorepo:** `4shark.pritunl` retires completely. This is a cleaner outcome than the three-target split originally implied, and it aligns this migration with the direction recorded in the golden-AMI plan — *"Infra provisioning is moving OFF Ansible onto Terraform"* — with the one legitimate exception that Ansible survives *inside the Packer build*, where it is a build tool rather than a fleet-management tool.

See the full mapping table below for the image / ECS host / golden AMI split.

### 8. Cutover / deploy model — a recurring HubFlow staging→prod flow, distinct from the one-time VM→ECS migration

**Decision:** two ECS "processes" going forward — a production Pritunl ECS instance (always on) and a `-staging` Pritunl ECS instance (normally at zero capacity, brought up only for a test window). The **recurring** operational flow once the repo/infra exist: merge to `develop` → staging image builds (decision 6) → `-staging` instance scaled up → validate → `git hf release` → `master` image builds → production deploy. This is distinct from the **one-time** VM→ECS migration: stand up the new production ECS instance + Mongo VM in parallel with the still-running current combined VM, migrate state (`mongodump`/`mongorestore`), validate on a temporary IP, then flip the existing EIP from the old VM to the production instance's ENI in a single maintenance window; the old combined VM is kept stopped (not terminated) afterward, as a rollback path.

**Rationale:** this decision separates two different kinds of "cutover": (1) the *recurring* staging→prod promotion every future Pritunl image change goes through (the HubFlow flow decision 6 established), and (2) the *one-time* migration off the current combined VM entirely. Conflating them would mean every routine version bump re-runs a maintenance-window/EIP-flip procedure that should only ever happen once. The recurring flow's own validation step is the `-staging` instance itself; the one-time migration keeps its own pre-flip parallel-validation step because the EIP flip is a one-off event with no equivalent in the recurring flow — once the one-time cutover is done, neither `develop` nor `master` deploys ever touch the EIP again.

**How the `-staging` instance is scaled to zero (implementation detail, load-bearing for decision 8):** the engineer's language cites the connection-pooler/authenticators skills' pattern (`ecs-scale.sh`, desired_count 0/1). That pattern was built for **Fargate** services (`terraform/auth-001/auth_001_staging.tf:148-194` — `aws_ecs_service.auth_001_staging` at `desired_count = 0`, Fargate capacity), where a desired-count-0 service carries zero compute cost — there is no separate EC2 host to also stop. Pritunl's runtime (decision 2, EC2 with `privileged` + host networking) does not have that property: an EC2-backed ECS service at desired_count=0 still leaves its underlying EC2 host running (and billing) unless the host itself is also stopped. Two candidate mechanisms were surfaced:
- **Stop/start the dedicated EC2 host directly** (`~/.claude/scripts/stop-instance.sh` / `start-instance.sh`, the existing 4Shark wrapper scripts), alongside `ecs-scale.sh` for the ECS service itself. This keeps the staging Pritunl instance a plain dedicated instance, mirroring decision 2's own "single dedicated instance" framing, rather than an autoscaled fleet member.
- **`ecs_capacity` module's ASG-backed capacity provider with `min_size = 0`** (`terraform/modules/ecs_capacity/main.tf:53-102`), relying on ECS managed scaling to launch/terminate the host automatically as the service's desired_count changes. **Ruled out by a grounded AWS-documented behavior**: fetched from `docs.aws.amazon.com/AmazonECS/latest/developerguide/cluster-auto-scaling.html`, verbatim: *"When Amazon ECS scales out from 0 instances, it automatically launches 2 instances."* A scale-from-zero event on the staging capacity provider would launch **two** EC2 hosts for a single Pritunl task that host networking limits to one task per host anyway — doubling the staging bring-up cost and instance count for no benefit.

This finding rules out the ASG-managed-scaling-from-zero path as the mechanism for staging; the direct stop/start path does not have this failure mode and is the path the execution phases below assume, pending final engineer sign-off at Terraform-authoring time (see Residual open items).

**Source patterns referenced:**
- `terraform/auth-001/auth_001_staging.tf:1-194` — the Fargate desired-count-0 staging pattern the engineer's language references, and why it does not transfer unmodified to an EC2-backed instance
- `~/.claude/skills/authenticators/SKILL.md:17,70-90` — the existing scale-up/scale-down skill behavior for a staging authenticator instance, the direct precedent cited by the engineer
- `~/.claude/scripts/ecs-scale.sh:1-63` — the existing `aws ecs update-service --desired-count` wrapper, reused for the ECS-service half of staging bring-up/down regardless of which host mechanism is chosen
- `terraform/modules/ecs_capacity/main.tf:53-102` — the ASG-backed capacity-provider module and its managed-scaling configuration, the ruled-out alternative
- [docs.aws.amazon.com/AmazonECS/latest/developerguide/cluster-auto-scaling.html](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/cluster-auto-scaling.html) — *"When Amazon ECS scales out from 0 instances, it automatically launches 2 instances."*

## Ansible-task → new-home mapping

Exhaustive, one row per current task/responsibility in `ansible/roles/4shark.pritunl/tasks/main.yml:1-264`. "IMAGE" = the Pritunl Dockerfile or `configured-entrypoint.sh`; "HOST" = the Pritunl ECS launch template / custom AMI / user-data; "GOLDEN AMI" = already inside the MongoDB golden image the dedicated Mongo VM boots (decision 3) — nothing to do at all, listed to show the task is accounted for; "DROPPED" = no longer needed under the new architecture; "CUTOVER" = a one-off step in the cutover runbook, not a recurring responsibility.

*(Revised 2026-07-16: the five rows previously routed to a "MONGO VM" target — implying Ansible would run there — are now "GOLDEN AMI" or "DROPPED". Nothing provisions that VM post-boot.)*

| Current task (file:line) | New home | Why |
|---|---|---|
| Disable systemd-resolved DNS stub listener; symlink `/etc/resolv.conf` (`tasks/main.yml:12-25`) | **HOST** (Pritunl ECS host) | Generic host-level DNS bootstrap, structurally separate from the VPN-client-forwarding dnsmasq block further down. Not specific to VPN-client forwarding; folds into the Pritunl host launch-template/AMI "base OS hardening" bucket. Unrelated to MongoDB's placement |
| MongoDB apt-repo key, repo, install (`tasks/main.yml:32-61`) | **GOLDEN AMI** | Baked into the image at Packer build time by `ansible-role-mongodb`, not run on the VM. Same series: `8.0` in the AMI, `8.0` in `defaults/main.yml:6` — no version change at cutover. These tasks are retired in Phase 4, not retargeted |
| Configure MongoDB (`mongod.conf` template, `tasks/main.yml:63-70`) | **GOLDEN AMI** | `mongod.conf` is materialized inside the image by the same role the integrator fleet's 12 nodes run. Nothing templates it per-VM |
| Enable/start `mongod` via systemd (`tasks/main.yml:72-76`) | **GOLDEN AMI** | The systemd unit is enabled in the image; `mongod` is running the moment the VM boots. No post-boot step |
| Pritunl apt-repo key, repo, install of `pritunl` (`tasks/main.yml:83-98`) | **IMAGE** | The pinned-version Dockerfile install — see decision 1 |
| Apt install of `wireguard-tools` (userspace CLI, part of `tasks/main.yml:99-107`) | **IMAGE** | Userspace tooling Pritunl's own process invokes — just another apt package inside the image |
| WireGuard kernel module load/presence (implied by `tasks/main.yml:99-107`'s `wireguard` package) | **HOST** (Pritunl ECS host) | Kernel modules are host-global, not per-container-namespaceable. Confirmed by `github.com/goofball222/pritunl`'s README: *"The Docker host is required to have wireguard kernel modules installed and loaded."* |
| `/dev/net/tun` device-node presence | **HOST** (Pritunl ECS host) | Device node must exist on the host for a privileged container to access it |
| Enable/start `pritunl` via systemd (`tasks/main.yml:109-113`) | **IMAGE** (container `CMD`/`ENTRYPOINT` + `STOPSIGNAL`) | Replaced by Docker's process model; the graceful-shutdown signal is researched in Residual open items |
| Logrotate for pritunl (`tasks/main.yml:117-131`, pritunl portion) | **DROPPED** | Replaced by the `awslogs` ECS log driver + CloudWatch Logs retention, matching the pgbouncer/connection-pooler pattern — file-based logrotate is unnecessary once Pritunl's logs go to stdout/stderr inside the ECS task |
| Logrotate for mongod (`tasks/main.yml:117-131`, mongod portion) | **GOLDEN AMI** | File-based logrotate is still the right mechanism (MongoDB is a systemd-managed process on a real VM), but it is the image's responsibility, not a per-VM task. Confirm at PR 2.3 that `ansible-role-mongodb` covers mongod logrotate; if it does not, that is a gap in the role — fix it there, benefiting the whole fleet, never as a one-off on this VM |
| dnsmasq install + VPN-DNS-forwarding config (`tasks/main.yml:138-152`, `templates/dnsmasq-vpn.conf.j2:1-19`) | **IMAGE** (`configured-entrypoint.sh`, co-located with Pritunl) | Host networking (decision 2) means the container shares the host's network namespace, so dnsmasq inside the container can still bind the VPN virtual interface Pritunl creates, exactly as it does today from the host |
| dnsmasq logrotate (`tasks/main.yml:154-160`) | **DROPPED** | Same reasoning as pritunl's own logrotate above |
| dnsmasq systemd override forcing `After=`/`Requires=pritunl.service` (`tasks/main.yml:162-177`, `templates/dnsmasq-override.conf.j2:1-11`) | **IMAGE** (entrypoint ordering) | Replaced by an equivalent wait-loop inside `configured-entrypoint.sh`: start Pritunl, poll for the VPN virtual interface to appear, then start dnsmasq bound to that address. **Still the single highest-risk mapping in this table** — see Risks below |
| `pritunl set-mongodb` / rate-limit / auditing (`tasks/main.yml:191-201`) | **IMAGE** (`configured-entrypoint.sh`) | Config materialization at container start, direct parallel to pgbouncer's `configured-entrypoint.sh` pattern — but the Mongo URI now points at the **dedicated Mongo VM's private address over the VPC** instead of a local/sidecar hostname, and requires the new dedicated security group (decision 3) to actually permit the connection. This is the new Pritunl↔Mongo-VM network dependency flagged in Risks below |
| fail2ban install + filter + jail config (`tasks/main.yml:203-228`, `templates/fail2ban-filter-pritunl.conf.j2:1-9`, `fail2ban-jail-pritunl.conf.j2:1-9`) | **IMAGE** (`configured-entrypoint.sh`, co-located with Pritunl) | fail2ban needs to (a) read Pritunl's own JSON audit log and (b) manipulate the host's real netfilter/iptables rules to ban an IP; co-locating it inside the same privileged, host-networked container satisfies both without a bind-mount |
| Enable/start fail2ban via systemd (`tasks/main.yml:230-234`) | **IMAGE** (entrypoint-managed background process) | systemd unit concept does not apply; entrypoint starts it as a supervised background process alongside Pritunl and dnsmasq |
| Get/display initial setup credentials (`tasks/main.yml:241-263`) | **CUTOVER** | A one-time bootstrap step, run once against the new stack during the cutover phase (via ECS Exec or `docker exec`), not baked into the image, host, or Mongo VM, and not re-run on every deploy |
| Ansible handlers — restart systemd-resolved / dnsmasq / fail2ban | **DROPPED** | Ansible handler mechanics with no image/container equivalent — config changes at container start are applied by the entrypoint directly |
| Ansible handler — restart mongod | **DROPPED** | The handler exists to restart `mongod` when a config task changes something. No config task runs on the VM anymore — the config is in the image — so there is nothing to notify. A config change means a new AMI and a node replacement, not a restart |

## Execution phases

This migration spans two repositories plus retirement of the current Ansible role: a new `pritunl` tool repository (Phase 1), Terraform changes in the `terraform` repo (Phase 2), a one-time cutover procedure that touches both live stacks (Phase 3), and removal of the old Terraform module/Ansible role (Phase 4). After Phase 4, the standing operational model is the recurring HubFlow flow (decision 8) — not a numbered phase, but the ongoing lifecycle every future Pritunl version bump follows.

### Phase 1: New repo scaffolding (HubFlow shape)

**Objective:** stand up the `pritunl` tool repository per `DOCKER-IMAGE-TOOL-REPOSITORIES.md`'s HubFlow shape (§ "Two repo shapes"), mirroring `keycloak`.

**Components:**
- `develop` + `master` branches (HubFlow-initialized via `git hf init`) — **not** a single `main`
- Dockerfile (`FROM ubuntu:24.04`, Pritunl apt repo, `ARG PRITUNL_VERSION`-pinned install, `wireguard-tools`, dnsmasq, fail2ban packages) + `configured-entrypoint.sh` (Pritunl `set-*` commands — now pointed at the dedicated Mongo VM's private address — dnsmasq wait-loop + start, fail2ban start, `STOPSIGNAL SIGTERM`)
- `renovate.json` (base `config:recommended` + `helpers:pinGitHubActionDigests` + `minimumReleaseAge: 7 days`, plus the `customManagers` block for the `ARG PRITUNL_VERSION` github-releases tracking) and the `renovate.yml` runner workflow, copied from `pgbouncer`/`terraform`
- `ci.yaml` (hadolint), the three min-age-gate files
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
- Production ECS task definition (bespoke — SPIKE-7 resolved) with `privileged: true`, host networking. **No MongoDB sidecar container** (MongoDB is off-container, on decision 3's dedicated VM). **Volume wiring is now an OPEN question, not a settled "none"** — this line previously read "no `host_path` volume wiring", which was correct about *MongoDB* but wrongly generalized to the whole task: `/var/lib/pritunl` may need a `host_path` volume to preserve host identity across task restarts. Settle the `pritunl.uuid` question (Risks) BEFORE authoring this task definition — it is the one input that changes its shape
- Production `ecs_capacity` instance (or bespoke `aws_instance` — residual open item) for the single dedicated Pritunl container instance, launch template `user_data` extended with WireGuard kernel-module load + `/dev/net/tun` presence + base OS hardening (the host-prep items from the Ansible mapping)
- **Dedicated Mongo VM** — a bare `aws_instance` (no existing generic 4Shark VM module beyond `terraform/modules/pritunl` itself was found) launched from the **MongoDB golden AMI via a tag-filtered `data "aws_ami"` lookup** (decision 3) — no Ansible, no user-data provisioning; its own EBS root volume for the MongoDB data directory. Mirror `terraform/integrator-almaviva/mongodb.tf`'s deployed node shape (including `ignore_changes = [ami, user_data, user_data_base64]`) but resolve the AMI by tag rather than copying the hardcoded id those stacks currently pin
- **Dedicated Mongo security group** (`vpn-mongo-sg`) — ingress on MongoDB's port referencing the **Pritunl instance's security group**, per `terraform/docs/NETWORK-ACCESS-MODEL.md:45` (same region + reachable VPC → SG-based). Not a CIDR; SPIKE-3 is resolved, not open
- **`-staging` ECS instance + ECS service at `desired_count = 0` by default** (decision 8); host bring-up/down mechanism per decision 8's stop/start-wrapper-script finding, **not** `ecs_capacity` managed-scaling-from-zero (grounded fact above rules it out); staging's own database, and its own public-entry mechanism during test windows, are both residual open items — Phase 2 provisions the instance shape, not necessarily a final answer on either
- IAM role carrying forward the existing route-advertisement permissions (`terraform/modules/pritunl/iam.tf:29-49`) for the production instance; whether staging needs the same permissions is an execution-time detail, not decided here
- Security group carrying forward the existing port set (ports 14720/OpenVPN, 14721/WireGuard, per `terraform/modules/pritunl/security.tf`) for the production instance
- **Two per-target ECR repositories** for the Pritunl image (`<environment>` and `<environment>-staging`, `terraform/auth-001/ecr.tf:1-29` shape) — no MongoDB ECR repository needed (Mongo is VM-based, not a container)
- **Build credentials — the identity that PUSHES the image** *(added 2026-07-16; this plan had ECR but nothing that could write to it, and the omission blocked the whole phase — see the Blocker below).* An IAM user `vpn-image-build` scoped to ECR push on the two `vpn` repositories only, its access key, and **both** GitHub Environment secret pairs (`vpn` and `vpn-staging`), all Terraform-declared. Mirrors `terraform/mongodb`'s `iam.tf` + `github.tf` and `terraform/auth-001`'s `github_deploy.tf` — the engineer's chosen option A. **Declare both environments, not one**: `auth-001`'s Terraform covers only the production env, and `auth-001-staging`'s secrets were created by hand — mirroring keycloak faithfully would reproduce that gap
- Identity-stack governance: add `pritunl` to `local.hubflow_repositories` (`terraform/identity/github_repositories.tf:60-75`); add to `local.hubflow_repositories_with_min_age_check` (`:81-91`) once the `Verify Minimum Age` check exists
- **Do not yet touch the existing `aws_eip`/`aws_eip_association`** — the new production instance gets a temporary/secondary Elastic IP for Phase 3's pre-flip validation, so the production EIP stays pointed at the current combined VM until the flip in Phase 3

**Dependencies:** Phase 1 (images must exist in ECR before either ECS service can start tasks). **Note the ordering trap this phase hit:** Phase 1 was marked DONE because the repo and workflows existed, but no image has ever reached ECR — the build had no credentials. "Phase 1 complete" and "an image exists" are not the same claim; the build-credentials PR is what makes the second one true.

**Success criteria:**
- [ ] **`build.yaml` green — an image actually in ECR.** The single criterion this phase never had, and the reason a broken Dockerfile and a credential-less build both went unnoticed for six days. Nothing downstream is real until this passes
- [ ] New production ECS-EC2 instance registers with its cluster and the Pritunl container reaches a running/healthy state, connected to the new Mongo VM over the VPC
- [ ] Mongo VM's `mongod` running and reachable ONLY from the Pritunl security group (verify a connection attempt from outside that security group is refused)
- [ ] `-staging` ECS instance/service provisioned at zero capacity, confirmed to scale up/down cleanly via the chosen host mechanism before relying on it for the first `develop` validation
- [ ] `terraform plan`/`apply` clean, existing `terraform/vpn/`/`terraform/modules/pritunl/` untouched until Phase 4

### Phase 3: Cutover — the one-time VM → ECS migration (distinct from the recurring HubFlow flow)

**Objective:** migrate state and traffic from the current combined VM to the new production ECS + Mongo VM stack, with no unrecoverable data loss. This phase runs **once**; it is not part of the ongoing HubFlow staging→prod flow decision 8 establishes for future Pritunl version bumps.

> **SUPERSEDED 2026-07-16 — read decision 18 first.** The engineer chose to register the organization, user, server and routes by hand instead of running `mongodump`/`mongorestore`, and that is already done on the production stack. The paragraph below remains as the reasoning of record for WHY the restore existed, because its central claim is still true and is now the cost being paid: a hand-made organization has a new CA, so the team's existing profiles will NOT survive the flip and everyone must download a new one. The dump/restore steps in this phase are not being executed.

**What migrates vs. what is rebuilt — the short answer: nothing is rebuilt by hand.** Every org, user, VPN profile and dynamic OpenVPN route lives inside Pritunl's own MongoDB (`terraform/modules/pritunl/README.md:111`), so the dump/restore carries the whole operational state across. Engineers keep their existing `.ovpn`/WireGuard profiles (the EIP is reassociated, not replaced — decision 5), and no account is recreated. **The one exception is host identity** (`/var/lib/pritunl/pritunl.uuid`), which is filesystem state and does not travel in a dump — see Risks; whether the old VM's uuid must be carried onto the new stack for the restored server-to-host attachments to resolve is part of that same open question.

**Components:**
- `mongodump` on the current combined VM's MongoDB → `mongorestore` into the new dedicated Mongo VM
- Carry host identity across, per whatever the `pritunl.uuid` question resolves to (Risks) — the restored database's server-to-host attachments reference the OLD VM's host id, so this is a cutover step, not only a runtime concern
- Pre-flip parallel-validation step: with the new production stack live on its temporary IP, validate OpenVPN + WireGuard connectivity, `*.4shark.internal` DNS resolution, and the Pritunl-to-Mongo-VM network path against a test client profile (this is where the dnsmasq wait-loop risk, the fail2ban host-iptables-reach risk, the `SIGTERM` in-flight-connection residual item, and the new Pritunl↔Mongo-VM network dependency get their first real signal)
- Scheduled maintenance window: reassociate the existing production `aws_eip` from the old combined VM to the new production instance
- Post-flip smoke test: reconnect a real client against the now-production IP, confirm DNS + routing + Mongo connectivity

**Dependencies:** Phase 2 complete and validated.

**Success criteria:**
- [ ] Restored Mongo state matches the source (user count, org count, route entries)
- [ ] The new stack presents as the SAME Pritunl host as the old VM — exactly one host in the web console, no zombie entry, the VPN server attached to the live host (the `pritunl.uuid` question, resolved)
- [ ] Pre-flip validation passes DNS resolution, both VPN protocols, and Pritunl-to-Mongo-VM connectivity on the temporary IP
- [ ] Post-flip smoke test passes on the production EIP
- [ ] A task restart (not just a first boot) leaves the VPN serving — proves host identity survives the container lifecycle, which is what every future HubFlow deploy depends on

### Phase 4: VM retirement

**Objective:** decommission the old combined VM once the new stack is proven in production.

**Components:**
- Stop (do not terminate) the old combined VM — retained as a rollback path for N days (N to be set by the engineer at cutover time, not decided here)
- After the retention window, remove `terraform/vpn/` and `terraform/modules/pritunl/`
- **Delete `ansible/roles/4shark.pritunl/` outright, plus `ansible/playbooks/provision-pritunl.yml`** — no trimmed remainder, no Mongo-VM-targeting fragment. The MongoDB tasks are superseded by the golden AMI (decision 3/6), the config tasks moved into the image, and the host-prep tasks moved into the launch template. Nothing in the role has a surviving consumer *(revised 2026-07-16; this step previously said "reduce to only the trimmed Mongo-VM-targeting tasks", which the golden-AMI adoption made obsolete)*

**Dependencies:** Phase 3 complete, retention window elapsed with no rollback needed.

**Success criteria:**
- [ ] Old combined VM terminated
- [ ] Retired Terraform/Ansible code removed from the respective repos
- [ ] `ansible/roles/4shark.pritunl/` no longer exists in the monorepo, and no playbook references it

### 18. Production stack validated end-to-end — and the state migration was replaced by hand registration

**Executed 2026-07-16, after release 1.0.0 put an image in the `vpn` ECR.** The production ECS stack runs the released image, was configured by hand to mirror the old VM, and passed the same end-to-end tests staging did.

**The engineer decided against `mongodump`/`mongorestore` and registered the organization, user, server and routes by hand.** This reverses decision 8's cutover step and the plan's repeated claim that *"nothing is rebuilt by hand"*. The cost is stated plainly because it lands on the whole team, not on the person who chose it: **a hand-made organization has a new CA, so every existing `.ovpn`/WireGuard profile stops working at the flip and every engineer must download a new one.** The `mongorestore` existed precisely to avoid that — the CA and every user certificate are Mongo documents (*"All data for Pritunl is stored in the MongoDB database"*), so a restore carries them unchanged. The objection was raised once and the engineer chose to proceed; recorded here so the flip's comms account for it.

**A second cost of the same choice, less obvious:** the pre-flip validation is weaker. With a restore, the flip is validated against the team's REAL profiles. Registered from scratch, only new profiles can be tested — whether the old ones survive is not a question that can be asked, because they are known not to.

**The Public Address is the flip's load-bearing field, and it is not obvious.** Pritunl bakes the host's public address into every generated profile. The production host's auto-detected address (`56.125.176.186`) is temporary — it dies at the flip, when traffic starts arriving on the EIP (`18.228.109.20`). So the field must hold the EIP for a distributed profile to survive the flip, and the EIP currently routes to the OLD VM — meaning a profile that is correct for after the flip cannot be tested before it. The sequence that resolves this: set the temporary IP → download → test → set the EIP → re-download → distribute. The engineer pays two downloads; the team pays one.

**Proved on the production stack, each by direct observation:**

| Claim | Evidence |
|---|---|
| The released image runs in production | ECS `Desired: 1, Running: 1`, image `fc0a55b` |
| The dnsmasq config is loaded | `ss`: `10.149.176.1:53` + `127.0.0.1:53`, no wildcard |
| `bind-dynamic` attaches after Pritunl creates the interface | `fd=9` on the VPN address vs `fd=4` on loopback |
| A client connects over WireGuard | `wg show` on the production container: peer `10.149.176.18/32`, endpoint = the engineer's IP, handshake 1m27s |
| The tunnel carries real traffic | 22.30 KiB received / 15.90 KiB sent |
| Internal DNS resolves through the tunnel | client `nslookup` → `10.1.3.161` via `10.149.176.1` |
| The client reaches a real service in the VPC | `nc -vz 10.255.2.102 27017` → `succeeded!` |
| The route/server config mirrors the old VM | all 12 routes compared one by one; `0.0.0.0/0` removed |

**Two corrections to claims made earlier in this session — both were wrong, both are recorded because the reasoning that produced them will recur:**

1. **"The container log is empty, therefore the client never reached production" was never valid.** Pritunl does not write per-connection events to stdout — they go to Mongo, which is what the console's Server Output pane reads. The log was equally empty while a tunnel was demonstrably active. The conclusion happened to be right the first time (the real cause was found by reading the profile file, not the log), but the inference was unsound and would have been wrong the second time.
2. **Editing the profile's `.ovpn` `remote` line does nothing.** The Pritunl desktop client reads `remotes_data` from the sibling `.conf`; the `.ovpn` is not the source of truth. A `sed` on the `.ovpn` applied cleanly and changed no behaviour. The console (change Public Address, re-download) is the mechanism, not file editing.

**Still NOT proved:** SIGTERM behaviour (SPIKE-8), measured at the flip; and the flip itself.

### 16. The dnsmasq config must be written where dnsmasq reads it — the config was inert, and the failure looked like success

**Decision (2026-07-16, found while inspecting the container after the first successful client connection):** the entrypoint writes its dnsmasq config to `/etc/dnsmasq.conf`, the path the binary reads with no flags, rather than to `/etc/dnsmasq.d/`. Fixed in pritunl PR 1.6.

**What was actually running.** `ss` inside the container showed dnsmasq bound to `0.0.0.0:53` — the wildcard — not to the configured `listen-address`. The config file existed at `/etc/dnsmasq.d/vpn-dns.conf` with correct content, and dnsmasq had never read a line of it: not `listen-address`, not `server=` (the VPC resolver), not `no-resolv`, not `cache-size`, and **not `bind-dynamic`**.

**The mechanism, traced end to end.** `/etc/dnsmasq.conf` ships with every `conf-dir` line commented out (line 678: `#conf-dir=/etc/dnsmasq.d`). What loads that directory on a VM is the init script: `/etc/default/dnsmasq:29` sets `CONFIG_DIR=/etc/dnsmasq.d,.dpkg-dist,...` and `/etc/init.d/dnsmasq:57` expands it into `-7 ${CONFIG_DIR}` on the command line. The ansible role writes to `/etc/dnsmasq.d/` and works because systemd invokes that script. This entrypoint runs `dnsmasq --keep-in-foreground` directly and never passes through it.

**This is decision 14's twin.** Both are behaviour the VM's packaging supplied invisibly — there, `iproute2` present because it is `Priority: important`; here, `-7` injected by an init script. In both cases the Ansible role's *content* was ported faithfully and the *mechanism underneath it* was not, because nothing in the role names it.

**Why this one is the most dangerous defect of the migration.** The other four failed loudly enough that something was visibly broken. This one **produced a correct-looking result**: with no config, dnsmasq binds the wildcard (so it answers on the VPN address anyway) and, lacking `no-resolv`, falls back to `/etc/resolv.conf` — which under host networking is the HOST's file, already carrying `nameserver 10.255.0.2` and `search 4shark.internal`. Internal names would have resolved. **The DNS test — the single highest-risk item in this plan, the reason the staging environment exists — would have PASSED**, and this plan would have recorded `bind-dynamic` as validated when `bind-dynamic` was not loaded.

**It also corrects a claim made earlier today (decision 11's neighbourhood, and the WireGuard note in the routing discussion).** The plan stated that the container's one deliberate divergence from the VM was `bind-dynamic` vs `bind-interfaces`, and that the staging test would measure it. Neither was true while this defect was live: the divergence was not `bind-dynamic` vs `bind-interfaces` but **no configuration at all** vs the VM's, and no test could have measured `bind-dynamic` because it was never in effect.

**Why the default path rather than passing `-7`.** Both load the config today. `-7` is a flag an edit to the invocation can drop, and dropping it restores exactly this silent failure. `/etc/dnsmasq.conf` is what the binary reads on its own — `--conf-file=<path> Specify configuration file (defaults to /etc/dnsmasq.conf)`, per its own `--help` — so there is nothing to forget. The overwritten file is 100% comments in the built image (verified: `grep -vE "^#|^$"` returns nothing).

**Success criterion:** `ss` shows dnsmasq bound to `10.149.176.1:53` and `127.0.0.1:53` — NOT `0.0.0.0:53`. That check distinguishes a loaded config from an ignored one; "internal names resolve" does not, and never did.

**VERIFIED (2026-07-16, after the fix):** `ss` reports `10.149.176.1:53` and `127.0.0.1:53`, no wildcard. The two sockets also settle `bind-dynamic` itself, which no earlier evidence could: the loopback socket is `fd=4` (bound at start) while the VPN address is `fd=9` — a much later descriptor, opened only once Pritunl created `tun1`. That late attach IS the behaviour `bind-dynamic` exists to provide, observed rather than inferred, and it retires the plan's highest-risk item.

### 17. Staging validation — what the first end-to-end client run actually proved

**Executed 2026-07-16.** The results below are the reason PR 1.5 and 1.6 exist: the run found two defects that every other signal reported as healthy.

**Proved, each by direct observation:**

| Claim | Evidence |
|---|---|
| `bind-dynamic` attaches to the VPN address after Pritunl creates the interface | `ss`: `10.149.176.1:53` on a late `fd=9`, loopback on `fd=4` |
| The dnsmasq config is loaded | `ss`: no `0.0.0.0:53` bind |
| dnsmasq forwards to the VPC resolver and answers correctly | Query from inside the container: `ANCOUNT 1`, `10.1.3.161`, matching the Route53 record |
| A client resolves internal names through the tunnel | Client `nslookup`: `Server: 10.149.176.1`, `Address: 10.1.3.161` |
| **A WireGuard client reaches dnsmasq across the two `/28`s** | Same `nslookup`, from a client on `10.149.176.18` (the WG network) to `10.149.176.1` (the OpenVPN network) |
| WireGuard carries real traffic on the new host | `wg show`: handshake, ~25 KiB transferred, peer `10.149.176.18/32` |
| `pritunl.uuid` survives container replacement | Host id `e2eea324…` unchanged across three tasks |
| Each service lands on its own host | Task placed on the staging instance specifically |

**The WG-to-dnsmasq crossing was an open question this plan carried and could not answer from any source** — the two virtual networks are adjacent but distinct `/28`s, nothing in code or vendor docs said whether Pritunl routes between them, and it was recorded as "test it and observe". It routes.

| **A client reaches a real service in the VPC** | `nc -vz 10.255.2.102 27017` from the connected client: `succeeded!` |

**The infrastructure-access test proves more than reachability, because of WHICH target answered.** The Mongo VM's security group opens `27017/tcp` to the VPN hosts' security groups ONLY — no CIDR, no ICMP (verified: a single rule, three group ids). A packet arriving with the client's own `10.149.176.18` source would have matched nothing and been dropped. It completed a TCP handshake, so the gateway is source-NATting client traffic to its own address, and that address is inside the allowed group. Route, forwarding, NAT and the SG allow are all confirmed by one observation.

**`ping` was deliberately not used** — the same group has no ICMP rule, so it would have timed out with the data path working perfectly. On a day defined by signals that meant the opposite of what they showed, choosing a probe the target is configured to answer is the difference between a result and a coin flip.

**A stale record surfaced in passing, and did not affect anything.** `4client-commcenter-app002.4shark.internal` resolves to `10.1.3.161`, which exists as neither an EC2 instance nor an ENI in either region — the Route53 record outlived its host. The DNS test is unaffected (resolution is what it measures, and it measured it), but the record is orphaned. Recorded under "Out of scope — follow-ups".

**Still NOT proved — do not treat as validated:**

- **SIGTERM behaviour (SPIKE-8).** Untouched. Measured at the cutover's pre-flip step.
- **Production.** Nothing here says anything about the production image, which does not exist in ECR yet.

**Staging validation is otherwise COMPLETE.** Every question this environment was created to answer has an observed answer.

### 14. The image must install `iproute2` — Pritunl's undeclared dependency on the `ip` binary

**Decision (2026-07-16, found the first time a VPN server was ever started on the container):** the Dockerfile installs `iproute2`, pinned and Renovate-tracked like every other package. Fixed in pritunl PR 1.5.

**What happened.** With the staging server configured to mirror production exactly, Start reported `Status: Online` with a climbing uptime — and a real client got "Server is offline". The container log carried the answer: `FileNotFoundError: [Errno 2] No such file or directory: 'ip'`, raised from `server/instance.py:1542` inside `start_wg`, and separately from `tables_clear` (`ip rule del`, `ip route flush table 100`) and `setup/clean.py:81` at container boot. Pritunl's Python shells out to `ip` to build its policy-routing rules and to create the WireGuard interface. The binary was not in the image.

**Why OpenVPN's own log was misleading.** It showed `TUN/TAP device tun0 opened`, `net_addr_v4_add: 10.149.176.1/28 dev tun0`, `Initialization Sequence Completed`, then `SIGINT[hard,] received` — all in the same second. OpenVPN 2.6 talks netlink directly and never needs `ip`, so it came up perfectly; Pritunl then aborted the server and killed it. Reading that log alone points at OpenVPN, which is the one component that was working.

**The dependency is undeclared, and the VM could never have revealed it.** The `pritunl` package does not depend on `iproute2`. It did not need to: `iproute2` is `Priority: important`, so it is present in any default Ubuntu install, and the Ansible role never had a reason to name it. The container is `FROM ubuntu:24.04` with `--no-install-recommends` — minimal on purpose, so the accident does not repeat. Verified by exec against the running container: `ip` was the ONLY missing binary; `iptables`, `ip6tables`, `wg`, `openvpn`, `dnsmasq` and `fail2ban-server` were all present.

**This is the same class as decision 13, one layer deeper** — a property true by accident on the VM, invisible until the container disturbed it. Fourth instance in this migration.

### 15. Every health signal this stack emits can be green while the VPN serves nothing

**Not a decision — a property of the system, recorded because it has now decided the outcome of four separate diagnoses and will decide more.**

When the `iproute2` defect was live, this is what each layer reported: the image **built**; hadolint **passed**; the container stayed **RUNNING**; ECS reached **steady state**; the ECS task **health check** had nothing to say; the Pritunl console showed **`Status: Online`** with **`Uptime 0d 0h 0m 57s`**. Every one of them was green. The VPN served nothing, and the only component that knew was a client trying to connect.

The same shape has now appeared four times, each with a different cause: the Fargate trap (a healthy container that cannot open `/dev/net/tun`), the dead fail2ban (container RUNNING, console unprotected for ten minutes), the misplaced task (service running, on the wrong host), and this. `terraform-ci` validating nothing (recorded under follow-ups) is a fifth, outside this stack.

**The operational consequence, which the cutover must respect:** for this workload, *"it is running"* is not evidence of anything. The only signals that mean something are end-to-end and client-driven — a client connects, a route carries traffic, a name resolves. Phase 3's pre-flip validation is written that way; nothing about "the ECS service is healthy" may be substituted for it, at any point.

**A concrete gap this exposes, in scope for a follow-up rather than this migration:** the PR CI (`ci.yaml`) runs hadolint alone — it lints without building. The Dockerfile's own header already documents the consequence (the 26.04 bump "broke develop silently — hadolint lints without building"), and the build only runs on merge to `develop`. So a PR's green check proves the Dockerfile is well-formed and nothing more. Recorded under "Out of scope — follow-ups".

### 13. Each service must be pinned to its own host — decision 2 needed a mechanism, not a sentence

**Decision (2026-07-16, found the moment production's host existed):** each service carries a placement constraint binding it to its own instance. Without one, ECS places any service's task on any instance in the cluster.

**What happened.** Bringing staging up for validation, its console was unreachable on the staging host's address. The AWS path was provably fine — security group open on 443, network ACL allow-all, public subnet with an active internet-gateway route, Pritunl answering `302` on loopback with `bind_addr: "0.0.0.0"`. The contradiction resolved on one detail: the socket table showed a local address of `10.255.0.7`, and the staging host is `10.255.0.85`. **The `vpn-staging` task was running on the PRODUCTION host.** The staging host had zero tasks.

**The cause is a gap between the decision and the code.** Decision 2 says *"a single dedicated container instance ... never sharing a host"*. That was written as a description and never expressed as a constraint. With one host in the cluster it was accidentally true; the instant PR 2.6 added production's host, ECS had two candidates and put staging's task wherever it liked. Nothing in the Terraform said otherwise.

**It also invalidates part of an earlier diagnosis.** Production's task was reported as blocked solely by an empty ECR — true, and it remains true. But it was not the whole story: with both services unconstrained on two hosts, and host networking allowing exactly one task per host, the two would contend for placement even once an image exists. The empty repository was hiding a second fault behind it.

**Why this is the same failure the migration keeps producing** — a property that held by accident rather than by construction, invisible while the accident lasted. `bind-dynamic`, the `touch`, the liveness gate and now this all share it: something true because nothing had disturbed it yet.

**The fix:** `placement_constraints` with a `memberOf` expression matching each host by an attribute, so `vpn` can only land on the production instance and `vpn-staging` only on the staging one. The attribute is set per container instance; the constraint is declared per service.

**Success criterion — the test that would have caught it:** with both hosts up, scale staging to 1 and confirm the task lands on the staging instance specifically, not merely "somewhere in the cluster". "The service is running" was the assertion that hid this for an hour.

**RESOLVED (2026-07-16, terraform PR 2.7, applied and merged).** Both services carry a `memberOf` constraint over the ECS built-in `ec2InstanceId` attribute, so each host is matched by identity. A custom attribute via `user_data` was rejected: both hosts set `ignore_changes = [user_data]`, so an attribute written there would not reach the running instances, and forcing it would replace the host — destroying the state volume the Pritunl uuid lives on.

Verified against the success criterion above, not against "it is running": with both hosts registered, staging scaled to 1 placed its task on the staging instance, and the console answered `302` at that host's own address. Apply was `2 changed, 0 destroyed` — in-place, so no service was recreated.

**A second defect was stacked behind this one.** The console was also being probed over HTTP, which the security group never opens (443, 14720, 14721 only). Either fault alone produces "connection refused", so fixing the placement without noticing the scheme would have looked like no progress. Worth naming because it is the same shape as the earlier stack (26.04 base → build credentials → dnsmasq pin): faults that mask each other, where the visible symptom is identical for each.

### 12. Deployment shape — stop the old task before starting the new one

**Decision (2026-07-16, found by testing decision 11):** the ECS service runs with `minimum_healthy_percent = 0` and `maximum_percent = 100`. The old task stops, then the new one starts. A deploy therefore carries a brief VPN outage, by design.

**What happened.** Forcing a new deployment onto the second task-definition revision deadlocked. ECS, verbatim:

> *"(service vpn-staging) was unable to place a task because no container instance met all of its requirements. The closest matching (container-instance …) has insufficient memory available."*

The service carried the ECS defaults — `minimumHealthyPercent = 100`, `maximumPercent = 200` — which instruct ECS to place the **new** task before draining the old. Two tasks × 768 MB do not fit a 1 GB `t3a.micro`, so the new task could never place, and the rollout sat wedged: revision 3 `PRIMARY` with 0 running, revision 2 `ACTIVE` still serving.

**Two independent reasons force this, not one.** Memory is the one that fired, and could in principle be bought off with a bigger instance. Host networking cannot: the new task must bind the same VPN ports the old task still holds, so a second task on the same host is impossible at any instance size. Decision 2's runtime makes rolling deployment structurally unavailable — one host, one task, always.

**This only ever surfaces on the SECOND deploy.** The first has no incumbent to displace, so it succeeds and proves nothing. Every future HubFlow promotion (decision 8's whole recurring flow) is a second deploy.

**Why the outage is acceptable — it is what the engineer already described.** The stated production flow is: validate on staging, promote, deploy, *"aí tem downtime em produção, mas eu faço num horário que ninguém tá usando, comunico o time"*. The deploy window is already understood as an outage. This decision makes the infrastructure match that expectation instead of silently wedging while pretending otherwise.

**A second default had to go with it.** The first apply of `maximum_percent = 100` was refused outright: *"Availability Zone Rebalancing does not support maximumPercent <= 100 % as deployment configuration"*. AZ rebalancing is ENABLED by default on a new service, and it demands the same headroom for the same reason — it moves tasks between zones. There is nothing here to move: one dedicated host, one AZ, one task pinned by host networking. It is set to `DISABLED`, because a feature with no work to do should not be the thing that dictates the deployment shape.

**Consequence for `DEPLOYMENT-STRATEGY.md`'s framework:** the VPN cannot take the blue/green or rolling shape the rest of the fleet uses. Not a choice — a property of the privileged/host-networked single-instance runtime that Fargate's limitations forced (decision 2). Worth stating plainly so nobody later reads the VPN's stop-then-start as an oversight.

### 11. Host identity — persist `/var/lib/pritunl` on a host-path volume (SPIKE-9, RESOLVED)

**Decision (2026-07-16):** the task definition mounts `/var/lib/pritunl` from a `host_path` volume on the dedicated container instance. Both environments. This closes SPIKE-9.

**The answer needed no console, because it is not a question of fact — it is a consequence of two things already known:**

1. **A container without a volume has an ephemeral filesystem.** Every task start is a new container, so `/var/lib/pritunl/pritunl.uuid` is absent, and Pritunl mints a new one. This is Docker semantics, not Pritunl behaviour — there is nothing to observe.
2. **Pritunl's own docs make the consequence explicit.** Removing that file and restarting is the *documented procedure for creating a host*: *"To quickly create hosts with one server remove the `/var/lib/pritunl/pritunl.uuid` file then restart the Pritunl service."* So a volume-less task does, unintentionally and on every single start, exactly what the vendor documents as the way to fabricate a new host.

**Therefore, without the volume:** every deploy registers a new host and abandons the previous one, the console accumulates one zombie per deploy, and clients pay for it — *"When a VPN client attempts to connect to an empty or offline host it will fail and move on to the next host this increases the connection time."* The failure is silent in ECS terms: the container is healthy, the service is steady, the VPN degrades.

**Why `host_path` is viable here specifically:** decision 2's posture — a single dedicated instance per environment, host networking pinning one task per host — means the task always lands on the same host. A host-path volume is normally fragile because a task can be rescheduled elsewhere; that failure mode does not exist in this design. `modules/ecs_service/main.tf:56-62` already supports the mechanism; this task definition is bespoke (SPIKE-7) and declares it directly.

**VERIFIED EMPIRICALLY 2026-07-16, not merely reasoned.** With the volume in place, the uuid was read from the running container, the task was stopped, and the uuid was read again from its replacement:

```
task 8b9dd97626b64bc08d8f5abf3e37cd1e  ->  e2eea324533846dda96403066a68be58
task 364313ec724047d48fb8555c5468c134  ->  e2eea324533846dda96403066a68be58
```

Different container, identical identity. SPIKE-9 is closed on evidence.

**Verification is by ECS Exec, added in the same change.** `auth-001`'s cluster already carries `execute_command_configuration` (`terraform/auth-001/ecs.tf:4-8`) and `modules/ecs_service` already exposes `enable_execute_command` — so this is the fleet's existing shape, not a new pattern. Beyond proving this decision, it is what makes staging debuggable at all: today the only window into a running task is CloudWatch, which is how fail2ban managed to die unnoticed for ten minutes.

**What the console would still add, and why it does not gate this:** whether an *already-configured* VPN server re-attaches to a new host. Staging's database is empty — no org, no server — so there is nothing to strand and nothing to observe. That question belongs to the Phase 3 cutover, where a restored database carries real server-to-host attachments; it is recorded there, not here.

### 9. Companion-process startup — pre-create the log fail2ban needs; the entrypoint is not a supervisor

**Decision (added 2026-07-16, after the first staging bring-up):** `configured-entrypoint.sh` creates the Pritunl audit log with `touch` before starting `fail2ban-server`. One line, no wait-loop.

```sh
touch /var/log/pritunl_journal.log
fail2ban-server -f -x &
```

**What happened.** The first task that ran end-to-end produced this, and the container stayed `RUNNING` throughout:

```
fail2ban [40]: ERROR   Failed during configuration: Have not found any log file for pritunl jail
fail2ban [40]: ERROR   Async configuration of server failed
```

The entrypoint starts fail2ban before Pritunl, and the jail reads `/var/log/pritunl_journal.log`, which only exists once Pritunl runs. fail2ban fails configuration and dies. **Pritunl kept serving on 443 for ten minutes with no brute-force protection at all** — its own limiter is deliberately off (`app.auth_limiter_count_max = 999999`, visible in the same log), so fail2ban is the only layer. ECS reported `steady state` the whole time.

**Why `touch` and not the maintainer's own advice.** fail2ban has no option to tolerate a missing log — the `jail.conf` man page is explicit: *"only the files that exist at start up matching this glob pattern will be considered"*, and no `allowmissing`-style setting exists. So the file must be there at start; the only question is how. In `fail2ban/fail2ban#3884` the maintainer (`sebres`) answers a user with a script orchestrating fail2ban's startup: *"No need to dance with tambourine around own start of fail2ban"*, recommending instead `fail2ban-client set $jail addlogpath <path>` at runtime, or a fixed symlink.

**Neither transfers to this case, and the reason matters:** `addlogpath` solves a *dynamic path* — not knowing **where** the log will be. Ours is not that. We know where; we do not know **when**. Applying `addlogpath` here means detecting the moment the file appears — a wait-loop, which is precisely the tambourine dance he rejects. His advice, applied to our shape, reintroduces what it warns against. A symlink fails identically: a link to a nonexistent target is not a file that exists at start.

`touch` sidesteps the whole question by depending on nothing: idempotent, no timing, no polling, no race, nothing to maintain, and legible to the next reader in two seconds.

**Unverified, to confirm in the staging window:** whether Pritunl *recreates* the log (unlink + create) rather than appending. If it recreates, fail2ban must follow to the new inode — standard behaviour it performs for logrotate every day, but not confirmed for this case. `touch` satisfies the start-up requirement either way; this only affects whether the jail keeps watching afterwards.

**What this decision does NOT fix — see decision 10.** `touch` makes fail2ban start. It does not make fail2ban's *death* visible, and the death is what actually happened today.

**The pattern underneath.** This is the second companion process to need a workaround for the same underlying reason: on the VM, systemd guaranteed ordering (`After=`/`Requires=pritunl.service`); the container has nothing that does. dnsmasq already needed one (`bind-dynamic`), fail2ban needs another, and each future process will need its own. The Ansible mapping already named this family as the migration's highest risk — it has now confirmed twice.

### 10. fail2ban's failure must be loud — verify it started; let the container die if it did not

**Decision (2026-07-16):** after starting fail2ban, the entrypoint asks it whether it is alive and exits non-zero if it is not. `fail2ban-client ping` answers `PONG` when the server is up — the documented liveness check. Under the entrypoint's `set -eu`, a failed ping kills the container before Pritunl ever binds a port.

**The problem it closes.** fail2ban runs backgrounded and non-essential; only Pritunl is `essential`. So fail2ban could die and the container stayed `RUNNING`, the service reported `steady state`, no alarm fired, and the admin console sat on the public internet with **zero** brute-force protection — its own limiter being off by design. That is not hypothetical: it happened on 2026-07-16 and was caught only because someone read the logs by hand. This turns a silent gap into a task that refuses to start.

**Why NOT an ECS `healthCheck`, the obvious native answer.** A failing health check makes ECS replace the task — an automatic VPN outage. This plan's own EIP risk row states the consequence: an unplanned VPN outage *"locks every engineer out of private infrastructure simultaneously, including infrastructure needed to fix the VPN itself"*. Building a mechanism that can take the gateway down by itself, to guard against a rare condition, inverts the risk it is meant to reduce. A container that refuses to start is loud without being armed.

**Why NOT s6-overlay — for now.** s6-overlay is genuinely the community's answer to this exact shape, and its `finish` scripts decide whether a dead service restarts or takes the container with it. It is the *correct* end state, and it addresses the root: this entrypoint is a hand-rolled process supervisor, which is what produced both the dnsmasq ordering workaround and the fail2ban failure. But it replaces PID 1, and PID 1 is precisely what SPIKE-8 — the unresolved question of whether Pritunl drains or drops in-flight VPN sessions on `SIGTERM` — turns on. Introducing it now would change the variable of an open experiment. **Registered as Phase 7**, deliberately after the cutover, not smuggled in behind a fix.

**VERIFIED IN BOTH DIRECTIONS 2026-07-16.** A gate that has never refused anything is not a gate, so both paths were exercised against a live task:

```
fail2ban alive  ->  Server replied: pong        (task starts, "Server ready")
fail2ban killed ->  ERROR Failed to access socket path ... EXIT_CODE=255
```

The `255` under `set -e` is what kills the entrypoint before Pritunl binds a port.

**What this does NOT cover — and the same test demonstrated it.** After `fail2ban-client stop` inside the running task, **the container stayed `RUNNING` and the service stayed healthy** with the console unprotected. The silent failure reproduced on demand, in front of us. This gate verifies fail2ban *started*; nothing watches it afterwards, because nothing in this design can — the entrypoint `exec`s into Pritunl and ceases to exist. A fail2ban that dies at hour six is still silent. That residual is exactly what Phase 7 exists for; it is accepted here because the observed failure mode was start-time, and because the alternative (an armed health check) is worse than the risk.

**No longer gates the cutover.** The start-time gap is closed; the run-time gap is a known, recorded residual with an owner.

### Phase 7: Replace the hand-rolled supervisor with s6-overlay

**Objective:** stop the entrypoint from being a process supervisor. Adopt s6-overlay so dnsmasq, fail2ban and Pritunl are supervised services with declared ordering and declared failure behaviour, instead of three background jobs and a shell script's good intentions.

**Why this earns its own phase.** Three separate defects in this migration trace to one cause — a shell script starting processes that depend on each other, with nothing supervising them: dnsmasq could not bind before Pritunl created the interface (worked around with `bind-dynamic`), fail2ban could not read a log Pritunl had not created (worked around with `touch`), and fail2ban's death was invisible (worked around with a start-time ping). Each workaround is correct and each is a patch on the same hole. The Ansible mapping named this family as the migration's highest risk before any of them happened; it is now three for three.

**Why AFTER the cutover, not before.** s6-overlay becomes PID 1. SPIKE-8 — does Pritunl drain or drop live VPN sessions on `SIGTERM`? — is an open empirical question about PID 1's behaviour, to be answered during the cutover's pre-flip validation. Changing PID 1 first would answer it about s6 rather than about Pritunl, and the cutover is the one moment where the answer matters most.

**Deliverables:** a `SPIKE.md` establishing the ordering and failure policy per service (does a dead fail2ban restart, or take the container down?), then the image change. Unscheduled; it retires three workarounds rather than adding a feature.

**Success criteria:**
- [ ] The entrypoint no longer starts or backgrounds any process — it materializes config and nothing else
- [ ] Killing fail2ban inside a running task produces a visible, deliberate outcome, not silence
- [ ] `bind-dynamic` and the `touch` are removed, their reason now expressed as service ordering

### Phase 5: Spike — retire the static build credential in favour of OIDC

**Objective:** produce a ready-to-execute plan for moving GitHub Actions → AWS authentication off static access keys onto OIDC role assumption. **This phase delivers a `SPIKE.md` and a `PLAN.md`, not infrastructure.** It is deliberately the last phase and is NOT scheduled — the engineer picks it up when they choose. Its whole purpose is that when that moment comes, there is nothing to re-research: the decision is made, the work is written, someone just executes.

**Why this exists:** Phase 2 chose option A (IAM user + static key) to unblock the critical path, with the trade-off recorded openly — it creates a long-lived credential in GitHub, its value lands in Terraform state, and rotation is a manual `apply -replace` someone has to remember. Option B (OIDC) removes that entire class of problem: no stored secret, short-lived tokens per run. It was not chosen because it is greenfield at 4Shark and Phase 2 could not absorb the detour — not because it is wrong. This phase is where that debt gets paid, on the engineer's schedule.

**What the spike must establish (the research already done — do NOT redo it):**
- **The OIDC provider exists in the account** (`arn:aws:iam::<account>:oidc-provider/token.actions.githubusercontent.com`) but is **declared by no Terraform** — it is an unmanaged, hand-created resource. Adopting or re-declaring it is part of the work.
- **No role trusts it.** Of the 101 IAM roles in the account (full list, not truncated), zero have `token.actions.githubusercontent.com` in their trust policy, and no terraform/github/actions-named role exists at all.
- **The `terraform` repo's workflows already reference the pattern but have never exercised it** — `terraform-ci.yml:9-10,56-60,94-98` sets `id-token: write` and `role-to-assume: ${{ secrets.AWS_TERRAFORM_ROLE_ARN }}`, but the `Validate`/`Plan` jobs that would assume the role are always skipped (see the separate `terraform-ci` finding), so the step has never run. The appearance of adoption is exactly what made this look cheap; it is not.
- **The static-key consumers to migrate**, all reading `secrets.AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` from a GitHub Environment: `pritunl` (`build.yaml`, `deploy.yaml`), `keycloak` (`build.yaml`, `deploy.yaml`), `mongodb` (Packer build), plus whatever the `app`/`integrator`/`onboarding`/`setup` deploy workflows use — enumerate them, this list is not yet exhaustive.

**Questions the spike answers:**
- Is this fleet-wide, or per-repo incremental? If incremental, which repo goes first — and is `pritunl` the right pilot precisely because its credential is the newest and least entangled?
- What is the role-per-repo vs role-per-environment granularity, and how is the trust policy's `sub` claim scoped (repo, branch, environment) so a `develop` build cannot push a production image?
- Does the `terraform` repo's own `AWS_TERRAFORM_ROLE_ARN` secret point at anything, or is it dead configuration to be cleaned up in the same pass?
- What happens to the existing IAM users and their keys — deleted, or left disabled for a rollback window?

**Deliverables:**
- `SPIKE.md` in `~/Projects/4Shark/dot-claude-plans/active/spike/github-actions-oidc/` — the findings above, verified fresh, plus the answers.
- A `PLAN.md` alongside it, complete enough to hand to `/execute` without a research round.

**Dependencies:** none — the spike can be written at any point. Placed last because it is a follow-up to a decision Phase 2 made, and nothing in Phases 1-4 waits on it.

**Success criteria:**
- [ ] `SPIKE.md` answers every question above with a citation, not an opinion
- [ ] `PLAN.md` exists and is executable as-written — no "research X first" steps remaining
- [ ] Neither document is scheduled; both sit in `active/spike/` until the engineer picks them up

**After Phase 4**, the standing operational model is the recurring HubFlow flow described in decision 8 (merge to `develop` → staging validate → `git hf release` → `master` → production deploy) — this is not a numbered phase; it is the ongoing lifecycle every future Pritunl version bump follows. Phase 5 is orthogonal to that lifecycle: it changes how the build authenticates, not how it promotes.

### Phase 6: Exempt the Ubuntu archive from the 7-day quarantine

**Objective:** stop `minimumReleaseAge: 7 days` from applying to `deb`-datasource packages, and document why that is a deliberate exception rather than an oversight. Two PRs — one in `pritunl` (the config), one in `dot-claude` (the doc).

**Why — the quarantine is not just unhelpful here, it is actively harmful.** Discovered 2026-07-16 when the first successful build attempt failed on `E: Version '2.90-2ubuntu0.3' for 'dnsmasq' was not found`:

- **Ubuntu's archive keeps only the current version in each pocket.** When `2.90-2ubuntu0.4` was published to `noble-updates` and `noble-security` on 2026-07-14, `2ubuntu0.3` was removed. An exact pin does not go stale gradually — it dies the instant upstream publishes.
- **The quarantine then blocks the only fix.** Renovate detected the bump correctly (the dependency dashboard lists `dnsmasq 2.90-2ubuntu0.3 → Updates: 2.90-2ubuntu0.4` under "Pending Status Checks"), but `minimumReleaseAge` holds it for 7 days. So the pin is dead and the repair is queued: **a guaranteed unbuildable window every time any pinned Ubuntu package is updated.**
- **And it was holding a CVE fix.** `2.90-2ubuntu0.4` is a security update addressing two CVEs, published to the security pocket. 4Shark's own policy already recognises this exact case for Dependabot — *"Cooldown bypass is intentional: a published CVE is already public, waiting helps attackers"* (`AUTOMATED-DEPENDENCY-UPDATES.md`). The same reasoning applies; it simply never reached the `deb` path because that path arrived with this repo.

**The rationale for the exception (engineer's decision):** `minimumReleaseAge`'s threat model is typosquatting and compromised maintainers — a package published by anyone, to a registry that accepts anyone. The Ubuntu archive is not that shape: it is a curated, signed distribution where the vendor performs the review the quarantine is a proxy for. Re-imposing a 7-day wait on top of Ubuntu's own process is over-engineering, and here it is over-engineering with a concrete cost — a broken build and a delayed CVE fix.

**Why `pritunl` is the ONLY repo that gets this** — verified, not assumed: a grep across every `renovate.json` and `Dockerfile` in `~/Projects/4Shark/` finds the `deb` datasource **only** in `pritunl`. `mongodb` tracks its series via `endoflife-date`; `pgbouncer` and the rest track upstream images via the `docker` datasource. So this is not a privilege granted to one project — `pritunl` is simply the only project that pins archive packages, and therefore the only one the rule can reach. **The exception generalizes: any future repo pinning `deb` packages should carry it too.** That is what the doc must say, so the next reader does not read the exception as arbitrary.

**Scope — what is NOT exempted.** Only `matchDatasources: ["deb"]`. The `docker` base-image pin keeps its 7-day quarantine (upstream Docker Hub is exactly the registry the threat model targets), and every GitHub Action keeps its existing treatment. The base image's **major** also keeps its dependency-dashboard hold (decision 1's coupling), which is a separate control.

**Components:**
- **PR in `pritunl`** — bump `ARG DNSMASQ_VERSION` to `2.90-2ubuntu0.4` (unblocks the build, ships the CVE fix), plus a `packageRule` setting `minimumReleaseAge: null` for `matchDatasources: ["deb"]`, with the reasoning inline so it is not re-litigated.
- **PR in `dot-claude`** — update `docs/AUTOMATED-DEPENDENCY-UPDATES.md` with the exception: what is exempt (`deb` only), why (the archive's threat model differs, and the pin-death/quarantine interaction makes the rule harmful), why `pritunl` is currently the only holder (it is the only `deb` consumer), and that the exception follows the datasource, not the repo. **The doc lives only in `dot-claude`** — there is no copy in the terraform repo; the § Configuration Changes Policy path (PR against the working copy, never editing `~/.claude/` directly) applies.

**Dependencies:** none — but the `pritunl` PR gates the build, and therefore gates PR 2.5, SPIKE-9 and PR 2.6.

**Success criteria:**
- [ ] `build.yaml` green — an image in the `vpn-staging` ECR repository (the Phase-2 criterion this finally satisfies)
- [ ] A subsequent Ubuntu package update opens a Renovate PR that is mergeable immediately, with no 7-day wait
- [ ] The `docker` base-image pin still shows a pending min-age check on its next bump — proof the exemption is scoped to `deb` and did not leak

## Out of scope — follow-ups this migration surfaced but does not fix

Both were found while diagnosing the build failure on 2026-07-16. Neither is caused by this migration, and neither belongs in its diff (§ Scope Discipline — inconsistencies that are not blocking are follow-up tasks). Recorded here so they are not lost.

- **`keycloak`'s `auth-001-staging` GitHub Environment holds hand-made AWS secrets.** Both secrets exist on the repo; `terraform/auth-001/github_deploy.tf` declares only the `auth-001` pair, and a repo-wide grep for `auth-001-staging` finds no secret resource. Someone created them by hand — an undeclared credential with no owner and no rotation. This migration's Phase 2 avoids reproducing it (both `vpn` environments are declared), but keycloak's own gap remains open. Natural to fold into the Phase 5 OIDC work, since that pass touches every static-key consumer anyway.
- **An orphaned record in the `4shark.internal` private zone.** `4client-commcenter-app002.4shark.internal` → `10.1.3.161`, an address that is neither an EC2 instance nor an ENI in `us-east-1` or `sa-east-1`. Found while picking a resolvable name for the staging DNS test. Harmless to that test, but the zone has two A records total and one of them points at nothing — worth a sweep of the zone rather than a one-record fix, and it belongs to whoever owns that client's stack, not to this migration.
- **`pritunl`'s PR CI builds nothing.** `ci.yaml` runs hadolint alone, which lints the Dockerfile without building it; the build happens only on merge to `develop` (`build.yaml`). The Dockerfile header already names the cost — the 26.04 bump "broke develop silently — hadolint lints without building, so nothing failed until someone tried to build" — and every image defect this migration hit (26.04 base, stale dnsmasq pin, missing `iproute2`) reached `develop` through a green PR. A build step on PR would have caught the first two before merge. Not fixed here: it is a CI change, not part of this migration's diff (§ Scope Discipline). Same family as the `terraform-ci` gap below.
- **`terraform-ci` validates nothing.** The `Validate` and `Plan` jobs were `skipped` even on PR #722, which changed `vpn/mongodb.tf` — so the `changed-stacks` detector is not detecting changed stacks, and the terraform repo's CI has been a no-op. Same class of failure as the two this migration already hit: a green check that proves nothing. Worth its own investigation; it protects every stack, not just this one.

## Technical decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Base image | 4Shark-authored Dockerfile, official Pritunl apt repo, `ARG PRITUNL_VERSION` pin | Matches today's trust source; avoids a third-party community image as the supply-chain root for the VPN gateway every engineer depends on |
| Renovate update mechanism | As built: `customManagers` regex block with `datasource=deb` for every `ARG` (not `github-releases`), plus a standard digest pin on the base | Tracks the vendor's own stable apt train rather than upstream GitHub releases. **Needs the base image's major constrained** — a major bump is not mechanical (see the Renovate risk) |
| Image base OS | `FROM ubuntu:24.04` (noble), pinned by tag + digest | Coupled to the apt-source codename and all seven `ARG` pins — base and pins move together or not at all. Independent of both the ECS host's OS and MongoDB's `noble` ceiling |
| Runtime / launch type | ECS on EC2, single dedicated container instance per environment, `privileged: true` + host networking | Fargate structurally cannot grant privileged/host-network/kernel-module access; single instance matches today's posture (HA explicitly out of scope), applied per environment |
| MongoDB | **Dedicated VM booted from the MongoDB golden AMI** (8.0 / Ubuntu 24.04), separate from the Pritunl container | DocumentDB is a hard blocker; a dedicated VM removes database state from the ECS task's lifecycle entirely. The golden AMI means zero provisioning on the VM and an image already burned in on four production integrator replica sets |
| Mongo network isolation | **SG-based** — `vpn-mongo-sg` allows MongoDB's port from the Pritunl instance's SG, by reference | `NETWORK-ACCESS-MODEL.md:45` — same region + reachable VPC → SG-based is the standard; CIDR is the fallback only where an SG cannot express the source |
| Resource naming | **`vpn-*`** — no `4shark-` prefix, no `-001` suffix | ADR-010's application-prefix rule; one VPN means no instance number (mirrors `setup`), and `4shark-` is reserved for globally-namespaced resources. New resources, so no retrofit |
| Public entry (production) | Reassociate the existing `aws_eip` to the new production instance | Same resource, re-targeted association — zero client reconfiguration |
| Branch model | **HubFlow (`develop`/`master`), mirroring `keycloak`** | Gains a non-production `-staging` instance to validate a new Pritunl image before it reaches the production VPN gateway |
| dnsmasq / fail2ban placement | Both co-located inside the Pritunl image/entrypoint (not host-level services) | `privileged` + host networking already grants the network-namespace and iptables access both need |
| WireGuard kernel module / `/dev/net/tun` | Host launch template / AMI / user-data | Kernel modules and device nodes are host-global — a container cannot supply them for itself |
| MongoDB install/config | **Baked into the golden AMI** — nothing runs on the VM | `ansible-role-mongodb` owns it at image-build time. Consequence: `4shark.pritunl` retires entirely at Phase 4, with no surviving fragment |
| Build credentials (GitHub Actions → ECR) | **IAM user + static key, fully Terraform-managed, both environments declared** (option A) | The workflows were already written for this in Phase 1, and `mongodb` + `auth-001` both run it. OIDC (option B) removes the long-lived credential entirely and is the better end state, but it is greenfield here — the provider is unmanaged, no role trusts it, and the one repo that appears to use it never actually runs the step. Phase 2 takes the established path; **Phase 5 is the spike that plans the move to OIDC** |
| fail2ban's missing log at startup | **`touch` the file in the entrypoint before starting fail2ban** (decision 9) | fail2ban has no option to tolerate a missing log — the man page is explicit that only files existing at start are considered. The maintainer's own advice (`addlogpath` at runtime, or a symlink) solves a *dynamic path*, not a *late-arriving file*; applying it here would require detecting when the file appears — the wait-loop he explicitly rejects. `touch` depends on nothing: idempotent, no timing, no maintenance |
| fail2ban dying silently | **The entrypoint pings it and exits if it is dead** (decision 10) | Turns a silent gap into a container that refuses to start. NOT an ECS health check: that would let the mechanism take the VPN down on its own, and an unplanned VPN outage locks the team away from the infrastructure needed to fix it. NOT s6-overlay yet: it replaces PID 1, which is the variable SPIKE-8 is measuring — Phase 7 |
| Pritunl host identity (`pritunl.uuid`) | **`host_path` volume for `/var/lib/pritunl`** (decision 11, SPIKE-9 resolved) | A volume-less container mints a new uuid every start, which is Pritunl's own *documented procedure for creating a host* — so every deploy would register a new host, abandon the old one, and leave clients timing out against offline entries. `host_path` is safe here because the single-dedicated-instance posture pins the task to one host. Verified via ECS Exec, added in the same change | Filesystem state outside MongoDB; a volume-less task regenerates it every start, stranding the VPN server on a dead host. Decide before authoring the task definition |
| Cutover | Recurring HubFlow staging→prod flow (ongoing) + a separate one-time VM→ECS migration (parallel stand-up, `mongodump`/`mongorestore`, pre-flip validation, single-window EIP flip, old VM stopped for rollback) | Conflating the recurring promotion flow with the one-time migration would re-run a maintenance-window/EIP-flip procedure on every routine version bump |

## Risks

Ordered to lead with the dnsmasq/fail2ban/EIP/MongoDB risks per the engineer's explicit ordering request; the Renovate risk follows.

| Risk | Impact | Mitigation |
|------|--------|------------|
| **dnsmasq DNS forwarding for `*.4shark.internal`** depends on binding the VPN virtual interface only after Pritunl creates it (`ansible/roles/4shark.pritunl/templates/dnsmasq-override.conf.j2:1-11` — `After=`/`Requires=pritunl.service`). The chosen mapping replaces this systemd-level ordering with a hand-written wait-loop inside `configured-entrypoint.sh` — a weaker guarantee than a declarative systemd dependency, and the single highest-risk item in the Ansible-task mapping | If the wait-loop is wrong (races, wrong interface name, insufficient poll interval), connected VPN clients silently lose internal DNS resolution — a regression that may not surface until an engineer tries to reach an internal hostname, well after the cutover appears successful | Validate internal-hostname resolution from a connected test client explicitly during the pre-flip parallel-validation step (cutover phase) AND during every `-staging` validation window under the recurring HubFlow flow — not only after the production EIP flips; consider a `healthcheck`-gated startup order rather than a bare sleep-poll loop, to fail loudly instead of silently if the interface never appears |
| **fail2ban per-IP protection** now runs inside the same container as Pritunl, relying on `privileged`+host-networking to reach the host's real iptables and reading the audit log from the local (container) filesystem. Pritunl's own global rate limiter is deliberately disabled today specifically because fail2ban carries this responsibility (`pritunl_auth_limiter_count_max: 999999`, `defaults/main.yml:22`) | If the co-located fail2ban fails to actually reach the host's iptables (an assumption about host-networking + privileged mode's iptables-namespace-sharing behavior that was reasoned from Docker's documented networking model, not independently load-tested against this exact image), the admin auth endpoint has no brute-force protection at all — with Pritunl's own limiter also off | Confirm fail2ban's bans are visible in the HOST's own `iptables -L` (not just the container's) as part of the pre-flip validation step and every `-staging` validation window; keep the option of re-enabling Pritunl's own `app.auth_limiter_count_max` as an interim safeguard if the co-located fail2ban does not work as reasoned |
| **EIP pinning** — every engineer's `.ovpn`/WireGuard client profile is configured against the current production public IP | An uncoordinated IP change locks every engineer out of private infrastructure simultaneously, including infrastructure needed to fix the VPN itself | Reassociate the existing EIP allocation (decision 5) rather than provisioning a new one; the pre-flip parallel-validation step uses a temporary second IP specifically so the real EIP only moves once the new production stack is proven working. The `-staging` instance never touches the production EIP at all (residual open item below covers its own entry point) |
| **MongoDB state migration and the new Pritunl↔Mongo-VM network dependency** — org/users/VPN profiles, dynamic OpenVPN routes exist only inside Pritunl's own database (confirmed by `terraform/modules/pritunl/README.md:111`), AND the Pritunl container's own runtime now depends on network reachability to a separate host for every database operation, where a colocated sidecar would have had them on the same instance | A failed or incomplete `mongodump`/`mongorestore` during cutover means real client accounts and routes are lost, not just re-derivable configuration. Separately, ANY disruption to the Pritunl↔Mongo-VM network path (security-group misconfiguration, VPC routing change, Mongo VM downtime) now takes down the whole VPN gateway even if the Pritunl container itself is healthy — a new failure mode a colocated design would not have | Treat the Mongo migration as the highest-scrutiny step of the one-time cutover; validate restored state (user count, route entries) against the source before decommissioning the old combined VM; keep the old VM stopped (not terminated) for a rollback window. For the network dependency: confirm the dedicated security group (decision 3) actually permits the connection as part of both the pre-flip validation AND every `-staging` bring-up under the recurring HubFlow flow; monitor Mongo VM availability independently of Pritunl's own health checks |
| **`pritunl.uuid` — host identity is state that lives OUTSIDE MongoDB, and the design currently discards it on every task start.** *(Found 2026-07-16; not covered anywhere in this plan, the Dockerfile, or the entrypoint.)* Pritunl identifies each host in its cluster by a 32-character string in **`/var/lib/pritunl/pritunl.uuid`** — a file on the host filesystem, NOT a MongoDB document. It therefore does not appear in a `mongodump`, and the plan's "the Pritunl container is stateless" premise (decision 3) is false as written. Pritunl's own docs make the mechanism explicit — removing the file is the *documented procedure for fabricating a new host*: *"To quickly create hosts with one server remove the `/var/lib/pritunl/pritunl.uuid` file then restart the Pritunl service."* An ECS task with no persistent volume does exactly that, unintentionally, on every start. Confirmed in the code as built: `configured-entrypoint.sh:47` runs only `pritunl set-mongodb "${MONGODB_URI}"` and never touches `/var/lib/pritunl`; the Dockerfile declares no `VOLUME`; and Phase 2 explicitly specifies **"no `host_path` volume wiring"** | **This breaks every deploy, not just the cutover — so it lands squarely on the recurring HubFlow flow decision 8 establishes, not only the one-time migration.** Each task start mints a fresh uuid → Pritunl registers a NEW host in the cluster → the VPN server stays attached to the PREVIOUS host, which is now offline → *"Pritunl will not attempt to run a server on an offline host"*, so the VPN does not come up. Meanwhile the dead host entry persists in the web console until deleted by hand, accumulating one zombie per deploy. The failure is silent in ECS terms: the container is healthy and running, it just serves no VPN — the same shape as the Fargate trap, one layer down | Decide where host identity lives BEFORE authoring the task definition (this is a design decision, not an authoring detail — it changes the task definition, the entrypoint, and possibly the cutover). Candidate directions, unevaluated: (a) persist `/var/lib/pritunl` on a `host_path` volume on the dedicated container instance — the mechanism `modules/ecs_service/main.tf:56-62` already supports and which the single-dedicated-instance posture (decision 2) makes viable, since the task always lands on the same host; (b) inject a fixed uuid at container start from a known value (SSM/Secrets Manager), writing the file in the entrypoint before Pritunl starts; (c) verify whether a single-host deployment tolerates a changing uuid at all — it may be that a lone host with one server re-attaches cleanly, in which case this is a non-issue. **(c) is the cheap test that decides whether (a)/(b) are needed at all — run it on the `-staging` instance before PR 2.4.** The cutover carries the same question: the old VM's existing uuid may need to be carried onto the new stack so the restored Mongo's server-to-host attachments still resolve |
| **Renovate update mechanism — resolved differently than decision 1 assumed, and now MATERIALIZED as a live defect on `develop`.** As built, the Dockerfile does not use `github-releases` for `PRITUNL_VERSION`; every pin (base image + all seven `ARG`s) uses the `deb` datasource against the ubuntu archive and `repo.pritunl.com/stable`. Renovate runs and opens PRs. **But the base image and the apt pins are coupled and Renovate does not know it**: PR #7 (`Update ubuntu Docker tag to v26`) was merged into `develop` and bumped ONLY `FROM ubuntu:24.04` → `ubuntu:26.04`, leaving `PRITUNL_VERSION=1.32.4567.52-0ubuntu1~noble`, `CA_CERTIFICATES_VERSION=20260601~24.04.1`, the other five noble-era pins, AND the hardcoded `... /stable/apt noble main` apt-source line all untouched. PR #8 then bumped the 26.04 digest, compounding it. `master` is still correctly on `24.04` | A 26.04 base cannot resolve 24.04-versioned packages from its archive — the image cannot build. Nothing caught it: `ci.yaml` runs hadolint, which lints syntax and never builds, and `build.yaml` has failed on every run since the 2026-07-10 scaffold (pre-dating the bump), so its red status carried no signal. The `develop` branch — the branch that feeds the staging validation instance decision 6 depends on — is broken and looks the same as it did when it worked | Revert `develop`'s base to `ubuntu:24.04`, aligning it with `master` and closing PR #8. Then constrain the base image's **major** in `renovate.json` — an Ubuntu major bump is not a mechanical edit; it requires rewriting every `ARG` and the apt-source codename in one coherent change, which is a human task Renovate cannot represent. Leave minor/digest bumps automated. Separately, get `build.yaml` green (it needs the Phase-2 ECR repos, now merged) so a broken Dockerfile fails loudly instead of blending into a pre-existing red |

## Residual open items

These items are surfaced by the draft as unresolved and remain unresolved here — they require pre-implementation verification or execution-time authoring decisions, not a design decision, and are not blockers to starting the phases above.

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
  There is no `ExecStop`, `KillMode`, or `KillSignal` override — Pritunl's own packaging relies on systemd's default stop behavior (send `SIGTERM`), with `TimeoutStopSec=20` as the grace window before a hard `SIGKILL`. This confirms `SIGTERM` — Docker's own default `STOPSIGNAL` — is the signal Pritunl's own unit file already depends on; the Dockerfile should set `STOPSIGNAL SIGTERM` explicitly (self-documenting, mirroring `pgbouncer/Dockerfile:18-25`, even though it matches Docker's default), with the ECS task definition's `stopTimeout` set to at least 20s.
  **What remains genuinely unresolved**: no source describes what the process does upon receiving `SIGTERM` with respect to in-flight OpenVPN/WireGuard client sessions — whether it drains them or drops them immediately. `SuccessExitStatus=SIGALRM` hints the process uses `SIGALRM` internally for some part of its own lifecycle, but no source explains that behavior precisely — this is not asserted, only the two verified facts above (default `SIGTERM`, 20s grace) are claimed. **Pre-Dockerfile spike item**: validate in-flight-connection behavior on `SIGTERM` empirically against a real client connection, both during the one-time cutover's pre-flip validation and during a routine `-staging` deploy under the recurring HubFlow flow, since no documentation resolves it.
- **Apt-version-to-GitHub-release-tag correspondence** — not independently confirmed; verify `apt-cache policy pritunl` against `repo.pritunl.com/stable/apt` matches the GitHub release tag numbering before finalizing the Renovate `ARG` wiring.
- **Renovate versioning regex for the four-field Pritunl tag scheme** — the mechanism (custom regex manager + `github-releases` datasource) is settled; the exact `versioning:` regex needs empirical validation against a live Renovate run once the repo exists.
- **fail2ban's host-iptables reach from a co-located, privileged, host-networked container** — reasoned from Docker's documented networking model, but not independently load-tested against this exact image and AWS ECS-on-EC2 combination. Flagged as a pre-flip validation item.
- ~~**MongoDB VM's Ansible role — exact name and location**~~ — **CLOSED 2026-07-16, moot.** No Ansible runs on the Mongo VM; the golden AMI carries it (decision 3). There is no role to name and no inventory entry to structure.
- ~~**Dedicated Mongo security-group mechanism**~~ — **CLOSED 2026-07-16, and shipped.** SPIKE-3 resolved SG-based per `terraform/docs/NETWORK-ACCESS-MODEL.md:45`; `vpn-mongo-sg` (`sg-04769cd441169ce02`) is deployed with ingress 27017 referencing the Pritunl SG. This item's premise — "no existing 4Shark precedent for SG-to-SG" — was itself false (a bad grep; see the retracted grounded fact).
- ~~**`ecs_service` module extension vs. bespoke task definition**~~ — **CLOSED**, SPIKE-7 resolved bespoke (the module is consumed by ~19 stacks; isolating a one-off privileged/host-network case is not worth the regression surface).
- ~~**Staging MongoDB strategy**~~ / ~~**Staging instance's public entry point**~~ / ~~**EC2 host bring-up mechanism for `-staging`**~~ — **CLOSED** by SPIKE-4 (separate database on the production Mongo VM), SPIKE-5 (default non-elastic public IP on stop/start) and SPIKE-6 (direct host stop/start). See `phase-2-terraform/phase-2_blocking-decisions.md`; they are listed here only because this section was never pruned after that document resolved them.
- ~~**Renovate versioning regex for the four-field Pritunl tag scheme**~~ — **CLOSED, and the premise changed.** The repo does not use `github-releases` for `PRITUNL_VERSION`; every `ARG` uses the `deb` datasource against the vendor's own apt repo, so there is no four-field tag scheme to write a `versioning:` regex for. The custom manager is confirmed working — Renovate's dependency dashboard detects all seven `ARG`s.

## Assumptions

- Host networking (`network_mode: host`) plus `privileged: true` gives a container the host's network namespace, and iptables rules set from inside such a container are the host's actual rules — this is the basis for co-locating dnsmasq and fail2ban inside the Pritunl container instead of keeping them as separate host services. Not independently load-tested against this exact ECS-on-EC2/Docker combination (see Residual open items).
- `SIGTERM` is Pritunl's default stop signal with a 20-second grace window, matching Docker's own default `STOPSIGNAL` — confirmed from Pritunl's own systemd unit file, though the in-flight-session drain behavior on receiving that signal is not documented anywhere and is unverified.
- The apt package version served by Pritunl's `stable` repo corresponds one-to-one with the GitHub release tag numbering Renovate will track — very likely true given they are the same release process, but not independently confirmed by inspecting `apt-cache policy pritunl` output.
- The `github-releases` datasource + regex custom-manager mechanism will successfully track Pritunl's four-field version scheme once a `versioning:` regex is tuned — the mechanism is settled by Renovate's own documented pattern; the exact regex for this specific tag shape has not been run against a live Renovate instance.
- ~~The MongoDB VM's provisioning need is identical in shape to what the current Ansible role's MongoDB tasks already do — the recommended trimmed-Ansible-role path assumes those tasks need no adaptation, only a retargeted inventory entry.~~ **Retired 2026-07-16** — the golden AMI removed the premise: no Ansible runs on the Mongo VM, so there is no inventory entry and no retargeting (decision 3).
- The direct stop/start EC2-host mechanism (rather than ASG managed-scaling-from-zero) is the correct way to bring the `-staging` instance up and down — a researched finding ruling out the ASG alternative, but not yet explicitly signed off by the engineer at Terraform-authoring time (see Residual open items).

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
- `pgbouncer/CHANGELOG.md:1-25` — repo changelog lifecycle example (kept for the CHANGELOG shape itself)
- `terraform/modules/ecr/main.tf:1-10` — generic ECR repository module
- `terraform/modules/connection_pooler/main.tf:1-365` — full Fargate-based ECS tool module (task definition, service, security group, IAM, Cloud Map DNS) — the closest existing "small tool on ECS" precedent, not privileged/host-networked
- `terraform/modules/ecs_service/main.tf:1-165` — the generic EC2/Fargate ECS service module; line 14 confirms no privileged/host branch exists today; lines 56-62 confirm the `host_path` volume mechanism (not used by this migration's MongoDB placement)
- `terraform/modules/ecs_capacity/main.tf:1-102` — the ASG-backed EC2 capacity-provider module; lines 1-51 (launch template, `block_device_mappings`, `user_data`) are the concrete vehicle for host-level prep; lines 53-102 (ASG + managed scaling) are the mechanism ruled out for staging bring-up
- `~/.claude/docs/DOCKER-IMAGE-TOOL-REPOSITORIES.md` — the governing standard for the new repo (full text read; every checklist item and every "Two repo shapes"/HubFlow-variant note cross-referenced above)
- `~/.claude/docs/AUTOMATED-DEPENDENCY-UPDATES.md` — the three-layer dependency-update model the new repo plugs into
- `~/.claude/docs/DEPLOYMENT-STRATEGY.md` — the phased-vs-single deploy decision framework applied to the cutover phase
- `keycloak/.github/workflows/build.yaml:1-108` — full HubFlow build workflow (one job per branch/target)
- `keycloak/.github/workflows/deploy.yaml:1-101` — full HubFlow deploy workflow (manual dispatch, per-target cluster/service/task-family map, stabilization poll)
- `terraform/auth-001/ecr.tf:1-29` — the two-per-target-ECR-repository pattern
- `terraform/auth-001/auth_001_staging.tf:1-194` — the existing Fargate staging-instance precedent (desired_count=0, shared cluster/VPC/ALB, own database/hostname/log group)
- `terraform/auth-001/security_groups.tf:1-53` — the current CIDR-scoped security-group convention (including RDS access)
- `terraform/identity/github_repositories.tf:60-91` — `local.hubflow_repositories` and `local.hubflow_repositories_with_min_age_check`, where `pritunl` is added instead of the main-branch lists
- `~/.claude/skills/authenticators/SKILL.md:1-90` — the existing scale-up/scale-down skill behavior for a staging authenticator instance, the direct precedent the engineer's decision 8 language cites
- `~/.claude/scripts/ecs-scale.sh:1-63` — the existing ECS desired-count wrapper script
- [github.com/jippi/docker-pritunl](https://github.com/jippi/docker-pritunl) — docker-compose.yml (`privileged: true`) and README (`--network=host` default path)
- [github.com/goofball222/pritunl](https://github.com/goofball222/pritunl/blob/main/README.md) — README (WireGuard kernel-module host requirement, `network_mode: bridge`, `privileged: true`)
- [hub.docker.com/u/pritunl](https://hub.docker.com/u/pritunl) — confirms no official Pritunl VPN image exists
- [forum.pritunl.com/t/is-aws-documentdb-supported-as-a-database/1299](https://forum.pritunl.com/t/is-aws-documentdb-supported-as-a-database/1299) — DocumentDB incompatibility (capped collections / tailable cursors)
- [docs.renovatebot.com/modules/manager/regex/](https://docs.renovatebot.com/modules/manager/regex/) — the `datasource=github-releases` + `ARG/ENV ..._VERSION=` comment-annotation example, quoted verbatim in decision 1
- [github.com/pritunl/pritunl/releases](https://github.com/pritunl/pritunl/releases) — Pritunl's own four-field version-tag scheme (`v1.34.4681.89`)
- [github.com/pritunl/pritunl/blob/master/data/systemd/pritunl.service](https://github.com/pritunl/pritunl/blob/master/data/systemd/pritunl.service) — Pritunl's own systemd unit file, quoted verbatim in "Residual open items" — independently re-confirmed twice (Citation Discipline self-check)
- [docs.aws.amazon.com/AmazonECS/latest/developerguide/cluster-auto-scaling.html](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/cluster-auto-scaling.html) — *"When Amazon ECS scales out from 0 instances, it automatically launches 2 instances."* — the grounded basis for ruling out ASG-managed-scaling-from-zero for the staging instance (decision 8)
- `terraform/docs/NETWORK-ACCESS-MODEL.md` — **the governing standard for decision 3's network isolation**: the SG-vs-CIDR-vs-SaaS decision table (`:41-51`), the SG-based default for same-region/reachable-VPC sources (`:45`), CIDR as fallback only where an SG cannot express the source (`:26`), and the identity-pinning gotcha (`:69`)
- `terraform/docs/adr/ADR-010-resource-naming-convention.md` — **the governing standard for decision 4**: the application-prefix rule (`:27`), the `4shark-`-only-for-global-namespace distinction (`:36,50`), the `4client-` legacy precedent for this class of name (`:62-71`), and the new-resources-follow-the-rule change policy (`:73-77`)
- ~~[registry.terraform.io/.../vpc_security_group_ingress_rule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) — the `referenced_security_group_id` argument~~ — **dropped 2026-07-16.** It was carried as UNVERIFIED, and it is moot: the local shape is an `aws_security_group` with inline `ingress { security_groups = [...] }` blocks (`modules/pritunl/security.tf`, `app-shared-001/rds.tf:18-24`), not the newer per-rule resource.
- See auxiliary file: `pritunl-ecs-migration_options-comparison_1.html` — the historical options record (every discarded alternative, its pros/cons/cost/risk, and citations), superseded by this document as the plan of record

---

> **Authoring:** written by `@agent-plan-composer` from the engineer-validated `PLAN-SPIKE.md` (second-pass revision — the engineer changed the MongoDB placement, branch model, and cutover/deploy model decisions after reviewing the first converged draft; the base image, runtime/launch-type, and public-entry decisions are unchanged). No new options, no new technical decisions, no new assumptions were introduced at the composer stage — every claim traces to the draft. The `output-verifier` and `policy-verifier` run scope-containment, citation-integrity, contract-compliance, template-compliance, reference-resolution, and policy-conformance checks after this write.

---

## Execution progress & session discoveries (2026-07-10)

Appended by the main session to record what was executed and discovered. This section is the source of truth for resuming; the plan body above is the original strategy.

### Phase 1 — DONE (merged)

- **Repo `pritunl` created and governed** — added to the identity stack (`repositories` + `hubflow_repositories` + `auto_init`, infrastructure team) in [terraform#668](https://github.com/4shark/terraform/pull/668); applied via the `ivo` break-glass profile (MFA) and merged. The same PR backfilled the description on the 15 repositories that had none.
- **Branches bootstrapped to HubFlow**, mirroring `keycloak`: `develop` + `master`, default branch `develop`, `main` removed, `hubflow.prefix.versiontag = v`. Branch protections active.
- **Scaffold merged** — [pritunl#1](https://github.com/4shark/pritunl/pull/1): `Dockerfile`, `configured-entrypoint.sh`, `fail2ban-pritunl.filter`, `renovate.json`, `ci.yaml`, `renovate.yml`, `build.yaml`, `deploy.yaml`, the three min-age files, `CHANGELOG.md`, `README.md`, `.dockerignore`. **hadolint clean, image builds with `--no-cache`, pinned Pritunl version verified installed.**

### Discoveries that change the plan

1. **The apt `stable` channel lags upstream GitHub releases** — Pritunl's `repo.pritunl.com/stable/apt` (noble) is at `1.32.4567.52-0ubuntu1~noble` while GitHub releases are `1.34.x`. **Supersedes SPIKE-1's github-releases assumption**: the image installs the pinned `.deb` from apt, so Renovate tracks the apt channel via the **`deb` datasource**, not `github-releases`. The apt stable train is the correct thing for a production VPN to track.
2. **DL3008 resolved the idiomatic way — pin ALL apt packages + Renovate `deb`** — not a hadolint ignore. Every package is pinned via `ARG *_VERSION`; a single Renovate regex `customManager` pairs them with the `deb` datasource (ubuntu archive `noble` + `noble-updates` + `noble-security` for the OS packages, the pritunl repo for pritunl). Reproducible builds + supply-chain min-age on the OS packages, auto-maintained. (Grounded in Renovate deb-datasource docs + community multi-package examples.)
3. **Pinned ubuntu base digest** = `ubuntu:24.04@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90`.
4. **`STOPSIGNAL SIGTERM`** grounded in Pritunl's own systemd unit (no `KillSignal` override → systemd default SIGTERM, `TimeoutStopSec=20`); ECS `stopTimeout >= 20s`. Session-drain-on-SIGTERM stays a Phase-3 live-test item (SPIKE-8).
5. **CI lesson (recorded for future tool repos)** — a script the CI invokes directly (`.github/scripts/verify-minimum-age.sh`) needs the **executable bit committed (0755)**; the `Write` tool creates files `0644`, which made the "Verify Minimum Age" check fail with exit 126 (Permission denied). Fixed with `chmod +x` + amend. Set the exec bit on any CI-invoked script at scaffold time.
6. **Phase-2 coupling** — `terraform/modules/iam_deploy`'s `ECSClusterAll` statement builds `Resource` from `var.cluster_names` unconditionally, so `cluster_names = []` yields an invalid empty-`Resource` policy. **The deploy IAM is coupled to the ECS cluster** — the "ECR-only" first PR is NOT separable; the Build-unblock PR must include the ECS cluster + task-execution role. The module already exposes `ec2_instance_arns` for `ec2:Start/StopInstances` — it anticipates the Mongo VM + the staging-at-zero start/stop model.
7. **Infra naming (locked)** — prod `vpn`, staging `vpn-staging`, region `sa-east-1`, registry `405749097490.dkr.ecr.sa-east-1.amazonaws.com`. The new ECS infrastructure **extends the existing `terraform/vpn/` stack** (alongside `module.pritunl` — the current VM — which stays until cutover).

### Phase-2 decisions — status

Phase 2 is decomposed into **5 PRs (Option A)** — see `phase-2-terraform/TASKS-SPIKE.md` and `phase-2-terraform/phase-2_blocking-decisions.md`.

- **SPIKE-4** (staging Mongo) → ✅ **RESOLVED — separate database on the production Mongo VM (4B)**, per the documented `auth-001` staging precedent (`auth_001_staging.tf`: reuses the prod data host, isolated only by its own database). See `phase-2-terraform/phase-2_blocking-decisions.md`.
- **SPIKE-5** (staging public entry) → ✅ **RESOLVED — the instance's default (non-elastic) public IP on stop/start (5B)**. An always-allocated EIP contradicts the zero-idle-cost staging posture; validation needs a reachable VPN endpoint (rules out private-only); the tester brings the instance up and reads the fresh IP then. See `phase-2-terraform/phase-2_blocking-decisions.md`.
- **SPIKE-3** (Mongo SG scoping) → ✅ **RESOLVED — CIDR-scoped ingress (3B)** from the management VPC private subnet where Pritunl runs. 4Shark's documented convention is CIDR (`VPC-CROSS-VPC-CONNECTIVITY.md:40`, `auth-001/security_groups.tf`); zero SG-to-SG precedent in the repo; `VPC-DEPOSED-SG-DEPENDENCY.md` documents the migration fragility SG-to-SG references add. See `phase-2-terraform/phase-2_blocking-decisions.md`.
- **SPIKE-2** (Mongo VM provisioning) → **spike done** (`~/.claude/plans/active/spike/mongodb-base-image/SPIKE.md`). Finding reframes the premise: the shared base the engineer wanted **already exists** — the 15 self-managed integrator Mongo VMs already share ONE AMI (`ami-0bd91caaa9bc42cf3`) + ONE Ansible role (`4shark.mongodb8`, MongoDB 8.2); `app-*` Mongo is Atlas (managed, no VM). The only real drift is Pritunl itself: `4shark.pritunl` duplicates Mongo install logic, pinned at 8.0 without the hardening `4shark.mongodb8` has. **RESOLVED (2026-07-10): a dedicated golden-AMI pipeline was built and merged** — see the "Golden-AMI pipeline built" subsection below. PR 2.3's Mongo VM launches from the new golden AMI (MongoDB 8.2) via a `data "aws_ami"` tag lookup, so no per-VM Ansible role runs at all (the 2A/2B question is moot) and the 8.0→8.2 drift is closed at the AMI. This supersedes the earlier "reuse `4shark.mongodb8` + the shared AMI `ami-0bd91caaa9bc42cf3`" direction — the shared base is now a versioned Packer-built golden AMI, not the hand-baked `ami-0bd91caaa9bc42cf3`.
- **SPIKE-6** (staging host stop/start lifecycle) → ✅ **RESOLVED — direct stop/start** via `stop-instance.sh`/`start-instance.sh` + `ecs-scale.sh` (ASG-from-zero ruled out by the AWS-documented "launches 2 instances" behavior).
- **SPIKE-7** (`ecs_service` extend vs bespoke task def) → ✅ **RESOLVED — bespoke `aws_ecs_task_definition` (7B)**: `modules/ecs_service` is consumed by ~19 stacks (regression blast radius) and `modules/pritunl` is already bespoke. See `phase-2-terraform/phase-2_blocking-decisions.md`.
- **SPIKE-8** (Pritunl SIGTERM session-drain) → ⏳ empirical Phase-3 test (not doc-resolvable, not a Phase-2 blocker) — proceed with `STOPSIGNAL SIGTERM` + ECS `stopTimeout: 20s`; the drain-vs-drop test runs during Phase-3 pre-flip validation.

### Next steps

**One Phase-2 decision reopened 2026-07-16 — SPIKE-9 below.** Every other decision is resolved (see "Phase-2 decisions — status" and `phase-2-terraform/phase-2_blocking-decisions.md`) and those PRs are execution-only. **PR 2.1 (ECR) and PR 2.2 (governance) are DONE + merged** (see "Phase 2 execution progress" below). Remaining order:

**Renumbered 2026-07-16** — the build-credentials PR is inserted as 2.4 (it must precede anything that needs an image), so the old 2.4 (prod ECS) becomes 2.6; staging keeps 2.5. The remaining order follows the real dependency chain: credentials → image → staging → SPIKE-9 → prod.

1. ✅ **PR 2.3 (Mongo VM)** — DONE + merged ([terraform#722](https://github.com/4shark/terraform/pull/722)). Golden AMI via `data "aws_ami"` (SPIKE-2) + SG-based Mongo SG (SPIKE-3). `vpn-mongo` (`i-0b3b9eb2ebf95834a`) + `vpn-mongo-sg` applied; 2 added, 0 changed, 0 destroyed. The host stands empty alongside the running VM, as the parallel stand-up intends.
2. ✅ **PR 2.4 (build credentials)** — DONE + merged ([terraform#724](https://github.com/4shark/terraform/pull/724)). IAM user `vpn` (named after the application, not `vpn-image-build` — it gains ECS deploy permissions at 2.6) + access key + `vpn-image-push` policy scoped to the two ECR repositories, plus **both** GitHub Environment secret pairs. 2 imported, 8 added, 0 destroyed. **Proved, not assumed**: the next build ran past `Configure AWS credentials` for the first time and reached the image build.
3. **Phase 6 (dnsmasq bump + `deb` quarantine exemption) — NEXT, and it gates the build.** Two PRs: `pritunl` (version bump + `packageRule`), `dot-claude` (document the exception). See Phase 6.
4. **PR 2.5 (staging ECS)** — desired_count=0, DB on the shared Mongo VM (SPIKE-4), default public IP on stop/start (SPIKE-5), direct host stop/start (SPIKE-6). **Depends on Phase 6** (needs an image in `vpn-staging`, which needs a build that completes).
4. **SPIKE-9 (`pritunl.uuid` host identity) — blocks PR 2.6.** Does a single-host Pritunl deployment tolerate a regenerated uuid on restart, or does the VPN server strand itself on the previous (now offline) host? Empirical, on the `-staging` instance: start it, note the host in the console, restart the task, see whether the server still serves. The answer decides whether 2.6's task definition needs a `host_path` volume for `/var/lib/pritunl`, an injected fixed uuid, or nothing. **Depends on 2.5.** See the `pritunl.uuid` row in Risks.
5. **PR 2.6 (prod ECS)** — bespoke `aws_ecs_task_definition`, privileged + host networking (SPIKE-7). **Gated on SPIKE-9** — host identity determines the task definition's volume shape.
6. **Phase 3** — empirical SIGTERM/session-drain test (SPIKE-8) + the one-time cutover.
7. **Phase 5** — the OIDC spike (writes `SPIKE.md` + `PLAN.md`, ships no infrastructure). Unscheduled; the engineer picks it up when they choose.

Each PR in a fresh, focused session with Pattern Priming + PR-first + gated plan/apply.

### Golden-AMI pipeline built (2026-07-10) — resolves SPIKE-2

A dedicated MongoDB golden-AMI pipeline was built, merged, and validated in production. This is the shared Mongo base the VPN's dedicated Mongo VM (PR 2.3) consumes — it replaces both the "reuse `ami-0bd91caaa9bc42cf3` + `4shark.mongodb8`" idea and any per-VM Ansible provisioning.

**What was built (all merged):**
- **`mongodb`** repo (main-only, Docker-image-tool-repository shape) — Packer HCL2 build (`packer/mongodb.pkr.hcl`) that bakes the role onto Ubuntu 24.04 and snapshots a versioned, tagged AMI. Builds on push-to-main or `workflow_dispatch`; prunes to the 3 most recent.
- **`ansible-role-mongodb`** repo (main-only) — the MongoDB provisioning role (`4shark.mongodb`, MongoDB **8.0**, THP/numactl hardening, `mongod.conf` with an EMPTY `replSetName`), split out of the ansible monorepo so the build pins + auto-updates it. Pulled at build time via `ansible/requirements.yml` (currently pinned to `main`; a `v1.0.0` tag is deferred — not yet cut).
- **`terraform/mongodb`** stack — the AMI-build IAM user (`mongodb-ami-build`, minimum Packer EC2 policy), its access key, a read-only deploy key on `ansible-role-mongodb`, and the `mongodb` GitHub Environment secrets. Applied.

**Build facts for reference:** builds in **sa-east-1** in account `405749097490`, in the **management VPC public subnet** (`subnet-05ef68e0a36f73693`), on a `t3a.micro` (unlimited CPU credits), Ansible connecting directly with pipelining. ~10 min wall time (~7 min of which is the EBS snapshot). AMI tagged `Name=mongodb`, `Version=<series>-<UTC-timestamp>`, `MongoDBVersion`, `UbuntuRelease`, plus `GitCommit`/`BuildDate`/`ManagedBy` (`mongodb/packer/mongodb.pkr.hcl:131-139`). Root volume 40GB gp2, sized from measured integrator usage (~6-11GB) and overridable at launch.

**Series and OS (corrected 2026-07-16 — this section previously said 8.2):** the AMI is **MongoDB 8.0 on Ubuntu 24.04**, not 8.2. `mongodb_version` tracks the X.0 LTS line only — rapid releases (8.1/8.2/8.3) are not for self-managed deployments — and 24.04 is a ceiling because MongoDB's apt repo 404s for 26.04. **There is therefore no version move at cutover**: today's combined VM runs `pritunl_mongodb_version: "8.0"` (`ansible/roles/4shark.pritunl/defaults/main.yml:6`) and the AMI installs 8.0. The earlier claim of an inherent "8.0→8.2 move" was wrong and is retracted. Full grounding: the golden-AMI plan's § "Version and OS are both pinned by upstream constraints".

**How PR 2.3 consumes it:** the dedicated Mongo VM is a bare `aws_instance` whose `ami` comes from a `data "aws_ami"` lookup (`owners = ["self"]`, `most_recent = true`, filter `tag:Name = "mongodb"`) — never a hardcoded id. Single-node standalone `mongod` (the empty `replSetName` is already baked; Pritunl needs a plain standalone, no replica set — matches the golden-AMI plan's Phase 2 "greenfield, single-node, 20GB"). No Ansible runs on the VM. **Note the deployed integrator stacks pin the literal AMI id** rather than the tag lookup (`terraform/integrator-almaviva/mongodb.tf:34`) — that is a known discrepancy tracked in the golden-AMI plan; PR 2.3 follows the decision (tag lookup), not the drift.

**Still open for the Mongo VM specifically:** confirm at authoring time that the golden AMI's baked `mongod.conf` bind address / auth posture suits the Pritunl-container-over-VPC connection (the URI Pritunl sets points at the Mongo VM's private address — decision 3). If it does not, the fix belongs in `ansible-role-mongodb` (a role gap affecting the whole fleet), never as a one-off tweak on this VM. SPIKE-3 (the SG mechanism) is **resolved — SG-based, referencing the Pritunl SG** per `terraform/docs/NETWORK-ACCESS-MODEL.md`; see `phase-2-terraform/phase-2_blocking-decisions.md` (that resolution was reversed from an earlier, wrongly-grounded "CIDR-scoped" answer).

**Cross-reference:** the golden-AMI plan of record is `~/Projects/4Shark/dot-claude-plans/active/mongodb-golden-ami/PLAN.md`. Its Phase 2 IS this Pritunl Mongo VM adoption. **Its Phase 3 (integrator fleet cutover) is now COMPLETE** — 12 nodes across `almaviva`/`atento`/`commcenter`/`maqnelson` on `ami-0244451ea895c4e3c`, cut over 2026-07-14/15. Out of scope for this migration, but materially relevant to it: the image PR 2.3 adopts is no longer unproven — it is running four production replica sets.

### Phase 2 execution progress (2026-07-10)

- **PR 2.1 (ECR) — DONE + merged** ([terraform#679](https://github.com/4shark/terraform/pull/679)): added `vpn` + `vpn-staging` ECR repositories to the **`vpn` stack** (`vpn/ecr.tf`), mirroring the auth-001 two-target shape (`image_tag_mutability = MUTABLE`, scan-on-push, AES256). Tags are inline `{ Environment = "management", Role = "vpn" }` — the `vpn` stack has no `local.tags` and tags inline, so the new file matches the local convention rather than auth-001's `local.tags`. Plan was clean (2 add / 0 change / 0 destroy — the `module.pritunl` VM untouched), applied via `4shark-mfa`, merged. The pritunl build workflow now has push targets in `405749097490.dkr.ecr.sa-east-1.amazonaws.com`.
- **PR 2.2 (governance) — DONE + merged** ([terraform#680](https://github.com/4shark/terraform/pull/680)): Phase 1 (#668) had already added `pritunl` to `local.repositories` and `local.hubflow_repositories`, so 2.2 was scoped to the `Verify Minimum Age` required-status-check lists. **Broadened mid-flight to close a gap the engineer spotted**: the golden-AMI repos `mongodb` and `ansible-role-mongodb` were registered in `local.main_branch_repositories` but never added to `local.main_branch_repositories_with_min_age_check`, even though their CI produces the check. So the final change added THREE repos to their respective required-check lists — `pritunl` → `hubflow_repositories_with_min_age_check`; `mongodb` + `ansible-role-mongodb` → `main_branch_repositories_with_min_age_check`. Plan clean (0 add / **4 change** / 0 destroy — the 4 `github_branch_protection` resources gained the required check), applied via `ivo`, merged. Verified: all 4 branches (`pritunl` master+develop, `mongodb` main, `ansible-role-mongodb` main) now require `Verify Minimum Age`. Each already produces the check, so no merges are blocked.
- **PRs 2.3–2.5** — not started; all decision-unblocked (spikes resolved above). PR 2.3 is next and is the first substantial one (bare `aws_instance` from the golden AMI + CIDR-scoped Mongo SG + IAM); best done in a fresh, focused session.
