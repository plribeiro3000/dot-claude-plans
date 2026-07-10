# SPIKE — Shared MongoDB Base Image for Integrators + Pritunl VPN

## Investigation question

Should 4Shark build a single shared MongoDB "base image" (a versioned Docker image on ECS, OR a golden AMI built with Packer) that both the integrator MongoDB instances and the new Pritunl VPN MongoDB VM launch from — standardizing MongoDB provisioning fleet-wide? This spike investigates feasibility, current state, trade-offs (Docker-on-ECS vs golden AMI vs status quo), and how the answer reshapes the Pritunl migration's Phase 2 Mongo-VM PR (PR 2.3).

This spike branched out of `~/.claude/plans/active/pritunl-ecs/PLAN.md`, where the engineer, after being asked how to provision the new dedicated Pritunl Mongo VM, asked whether a shared base image could serve both the integrators and the VPN at once.

## Sources consulted

- `terraform/modules/mongodb_atlas/` — the managed Atlas module (file listing only; not read in full, out of scope beyond confirming its consumers)
- `terraform/app-shared-001/mongodb.tf:1-2`, `terraform/app-demo-001/mongodb.tf:1-2`, `terraform/app-beta-001/mongodb.tf:1-2`, `terraform/app-atento-001/mongodb.tf:1-2` — confirm all four `app-*` stacks consume `module "mongodb_atlas"`
- `terraform/integrator-almaviva/mongodb.tf`, `terraform/integrator-commcenter/mongodb.tf` — read in full
- `terraform/integrator-redebrasil/mongodb.tf`, `terraform/integrator-atento/mongodb.tf`, `terraform/integrator-maqnelson/mongodb.tf` — headers read, resource count confirmed by grep
- `terraform/shared-resources/mongo-cwagent.tf` — read in full
- `ansible/roles/4shark.mongodb8/tasks/main.yml`, `ansible/roles/4shark.mongodb8/defaults/main.yml` — read in full
- `ansible/roles/4shark.mongodb/tasks/main.yml`, `ansible/roles/4shark.mongodb/defaults/main.yml` — read in full (legacy role)
- `ansible/playbooks/provision-4client-mongodb-server.yml` — read in full
- `ansible/playbooks/provision-4client.yml`, `ansible/playbooks/provision-4client-without-vpn.yml` — grepped for the legacy role reference
- `ansible/roles/4shark.pritunl/tasks/main.yml:1-80` — read in full for the MongoDB-owning portion
- `ansible/packer_build.sh`, `ansible/packer/aws-ami-ubuntu-16.04-python.json`, `ansible/packer/aws-ami-4shark-wp.json` — read/listed; `git -C ~/Projects/4Shark/ansible log` confirms last touch
- `~/.claude/docs/DOCKER-IMAGE-TOOL-REPOSITORIES.md` — read in full
- `~/.claude/skills/ec2-instances/SKILL.md` — read in full
- `~/.claude/plans/active/pritunl-ecs/PLAN.md:1-287` — read (partial, first 287 of 438 lines — the sections relevant to this spike's scope: current architecture, grounded facts, decisions 1-7); cited only where PLAN.md itself is the source of a quote

No auxiliary files were needed — every source is either small enough to quote inline or already lives in the codebase at the cited path.

## Findings

### Finding 1: Integrator Mongo splits cleanly into two worlds — Atlas (managed, app-side) and self-managed EC2 VMs (integrator-side). A shared base image can only ever help the second world.

**Evidence:** All four `app-*` backend stacks provision MongoDB through the managed Atlas module:

```
terraform/app-shared-001/mongodb.tf:1-2
module "mongodb_atlas" {
  source = "../modules/mongodb_atlas"
```

The same two-line shape appears at `terraform/app-demo-001/mongodb.tf:1-2`, `terraform/app-beta-001/mongodb.tf:1-2`, `terraform/app-atento-001/mongodb.tf:1-2`.

All five `integrator-*` client stacks (`almaviva`, `atento`, `commcenter`, `maqnelson`, `redebrasil`) instead provision three bare `aws_instance` resources each — a Primary-Secondary-Arbiter (PSA) replica set:

```
terraform/integrator-almaviva/mongodb.tf:25-31
resource "aws_instance" "mongo003" {
  ami           = "ami-0bd91caaa9bc42cf3"
  instance_type = "t3.small"
  key_name      = "kp-4shark"
  subnet_id     = nonsensitive(data.aws_ssm_parameter.prv_a_subnet_id.value)

  iam_instance_profile = "mongo-cwagent"
```

`grep -c '^resource "aws_instance" "mongo'` returns `3` for every one of the five integrator stacks — 15 self-managed Mongo VMs total.

**Significance:** the app-side databases (Rails app backend) are already on a managed, Atlas-hosted MongoDB — Terraform-provisioned, no OS to patch, no image to build. A shared base image/AMI concept is structurally inapplicable there; there is no VM. The only side of the fleet a shared image could possibly help is the integrator side's 15 self-managed VMs plus whatever the new Pritunl Mongo VM becomes.

### Finding 2: The integrator Mongo VMs already share a single AMI and a single Ansible role across all five clients — the base-AMI layer is already uniform, just not MongoDB-preinstalled

**Evidence:** every one of the 15 integrator Mongo instances (5 clients × 3 nodes) pins the identical AMI ID:

```
terraform/integrator-almaviva/mongodb.tf:26
  ami           = "ami-0bd91caaa9bc42cf3"
```

(confirmed identical at `terraform/integrator-redebrasil/mongodb.tf`, `terraform/integrator-atento/mongodb.tf`, `terraform/integrator-maqnelson/mongodb.tf`, `terraform/integrator-commcenter/mongodb.tf` via the same grep).

Terraform explicitly does not manage post-boot state on that AMI:

```
terraform/integrator-almaviva/mongodb.tf:62
    ignore_changes  = [ami, user_data, user_data_base64]
```

— the same `ignore_changes` shape the Pritunl PLAN.md documents for the current combined Pritunl VM (`~/.claude/plans/active/pritunl-ecs/PLAN.md:30`: *"a bare `aws_instance` with `lifecycle { ignore_changes = [ami, user_data, user_data_base64] }` (Ansible manages the OS post-boot, not Terraform)"*).

All 15 instances also share one IAM instance profile, defined once, not per-client:

```
terraform/shared-resources/mongo-cwagent.tf:1-4
# Instance profile for the CloudWatch Agent on MongoDB EC2 hosts.
# Defined here because the role/policy/profile are identical across the
# five integrator-{client} stacks and IAM is account-global, so each
# aws_instance.mongo* references this profile by name.
```

MongoDB itself is installed post-boot by a single shared Ansible role, invoked identically for every client:

```
ansible/playbooks/provision-4client-mongodb-server.yml:6
# Takes 3 bare Ubuntu EC2 instances (provisioned by Terraform) and configures them
```
```
ansible/playbooks/provision-4client-mongodb-server.yml:47,54
  roles:
    ...
    - 4shark.mongodb8
```

**Significance:** the integrator side of the fleet is not fragmented today. Every client's Mongo VMs already boot from the same generic Ubuntu AMI and are configured by the same Ansible role (`4shark.mongodb8`, MongoDB 8.2). A shared *golden Mongo AMI* would move MongoDB installation from "apt install at boot, via a shared role" to "baked into the image at build time" — a real change in when installation happens, but not a fix for a fragmentation problem, because there currently isn't one on the integrator side.

### Finding 3: Two MongoDB Ansible roles exist in the codebase — the current one (`4shark.mongodb8`) is already the single source of truth for every integrator client; a legacy role (`4shark.mongodb`, MongoDB 4.0) is referenced only by older all-in-one playbooks

**Evidence:** the current role pins MongoDB 8.2 on Ubuntu 24.04 (noble):

```
ansible/roles/4shark.mongodb8/defaults/main.yml:5,8
mongodb_version: "8.2"
...
mongodb_ubuntu_codename: "noble"
```

and includes a THP (transparent huge pages)-disable systemd unit and `numactl` prerequisite the legacy role does not have:

```
ansible/roles/4shark.mongodb8/tasks/main.yml:7
      - numactl
```
```
ansible/roles/4shark.mongodb8/tasks/main.yml:36
- name: Install disable-thp systemd unit
```

The legacy role pins MongoDB 4.0 on Ubuntu bionic (18.04), hardcoded rather than templated:

```
ansible/roles/4shark.mongodb/defaults/main.yml:4
mongodb_version: "4.0"
```
```
ansible/roles/4shark.mongodb/tasks/main.yml:17
    repo: "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-{{ mongodb_version }}.gpg ] https://repo.mongodb.org/apt/ubuntu bionic/mongodb-org/{{ mongodb_version }} multiverse"
```

It is referenced only by two playbooks, both of which provision the entire VPC + all client VMs via Ansible (not Terraform):

```
ansible/playbooks/provision-4client.yml:533
    - 4shark.mongodb
```
```
ansible/playbooks/provision-4client-without-vpn.yml:490
    - 4shark.mongodb
```

**Significance (inference):** the docstring at `provision-4client-mongodb-server.yml:6` ("Takes 3 bare Ubuntu EC2 instances (provisioned by Terraform)") matches exactly how today's `terraform/integrator-*/mongodb.tf` files actually provision the VMs (Finding 1/2). This is consistent with `provision-4client.yml`/`provision-4client-without-vpn.yml` (which provision VPC + instances via Ansible itself, not Terraform) being an older, pre-Terraform-migration all-in-one flow, superseded for MongoDB provisioning by the Terraform + `provision-4client-mongodb-server.yml` + `4shark.mongodb8` path. This spike did not confirm whether the legacy playbooks are still invoked in practice for any live client — flagged as uncertain below, not asserted.

### Finding 4: Pritunl's own MongoDB installation is a near-duplicate, independently-maintained copy of the same apt-install/config/systemd logic — not a reuse of `4shark.mongodb8`

**Evidence:** `4shark.pritunl` installs its own MongoDB, pinned independently at a different version:

```
ansible/roles/4shark.pritunl/defaults/main.yml:6
pritunl_mongodb_version: "8.0"
```

versus the integrator role's `8.2` (Finding 3). The install/config/systemd task shape is structurally identical — apt key, apt repo, install, template config, enable/start:

```
ansible/roles/4shark.pritunl/tasks/main.yml:52
    repo: "deb [ arch=amd64,arm64 signed-by={{ pritunl_mongodb_gpg_keyring }} ] https://repo.mongodb.org/apt/ubuntu {{ pritunl_mongodb_ubuntu_codename }}/mongodb-org/{{ pritunl_mongodb_version }} multiverse"
```
```
ansible/roles/4shark.pritunl/tasks/main.yml:56,63,72
- name: Install MongoDB
...
- name: Configure MongoDB
...
- name: Enable and start mongod
```

— the same four steps as `4shark.mongodb8/tasks/main.yml:25,31,67,76` (apt repo, install, template config, enable/start), but under Pritunl-prefixed variable names (`pritunl_mongodb_*` vs `mongodb_*`) and without the THP-disable unit or `numactl` prerequisite that `4shark.mongodb8` carries (Finding 3).

**Significance:** this is the one concrete, evidenced instance of the "Mongo-cluster problem" the engineer's premise describes — two independently-maintained copies of the same provisioning logic (`4shark.mongodb8` for integrators, the MongoDB-owning block of `4shark.pritunl` for the VPN) that must be kept in sync by hand, already drifted on version (8.2 vs 8.0) and on hardening steps (THP/numactl present in one, absent in the other). It is a real, evidenced drift — but it is a role-duplication problem, not necessarily an image-provisioning problem (see Trade-offs below, Option C).

### Finding 5: No live golden-AMI / Packer pipeline exists in the codebase today — the only Packer artifacts are dead 2016-era templates, untouched since the initial commit

**Evidence:**

```
ansible/packer_build.sh
AWS_PROFILE=4shark packer build $@
```

```
ansible/packer/aws-ami-ubuntu-16.04-python.json
{
    "builders": [
        {
            "type": "amazon-ebs",
            "region": "us-east-1",
            ...
            "source_ami": "ami-40d28157",
            "instance_type": "c4.large",
            ...
            "ami_name": "4shark-ubuntu-16.04-python-{{timestamp}}"
        }
    ],
```

`git -C ~/Projects/4Shark/ansible log -1 --format="%ai %s" -- packer/aws-ami-ubuntu-16.04-python.json` returns `2016-12-29 21:00:08 -0200 Initial Commit` — identical for `packer/aws-ami-4shark-wp.json` and `packer_build.sh`. None of the three files has been touched since the repository's first commit.

**Significance:** a golden-AMI approach via Packer would be net-new operational infrastructure at 4Shark, not an extension of an existing, exercised pipeline. The two existing templates target Ubuntu 16.04 (EOL) and are unrelated to MongoDB. There is no current muscle-memory, CI wiring, or Renovate-tracking pattern for AMI builds to build on.

### Finding 6: The `DOCKER-IMAGE-TOOL-REPOSITORIES.md` standard targets containerized third-party tools; it has no stated precedent or provision for a stateful database as a "tool repo"

**Evidence:**

```
~/.claude/docs/DOCKER-IMAGE-TOOL-REPOSITORIES.md:9
A repo whose only product is a container image — a thin wrapper over an upstream image (`edoburu/pgbouncer`, `quay.io/keycloak/keycloak`, …) plus a small amount of 4Shark glue (entrypoint, config injection, shutdown behavior).
```

The standard's checklist (branch model, base-image pin, Renovate, CI, build-on-merge, deploy-on-demand, `STOPSIGNAL` graceful shutdown) is written entirely in terms of a stateless or externally-stated wrapped tool; nothing in the document addresses EBS volumes, data directories, or backup/restore for the wrapped tool's own persistent state. The document explicitly scopes itself away from 4Shark's own applications: *"If the repo instead builds one of the 4Shark applications (`app`, `integrator`, …), this standard does NOT apply"* (`DOCKER-IMAGE-TOOL-REPOSITORIES.md:11`) — MongoDB is neither of those, but it is also not a stateless wrapped tool like pgbouncer or Keycloak.

**Significance:** adopting the Docker-image tool-repo standard for MongoDB would be extending it into territory (stateful storage) it was not designed for. This is not a blocker in principle, but it is new ground — the reference implementations (`pgbouncer`, `keycloak`) do not answer how the pattern handles a data directory that must survive container replacement.

### Finding 7: The current 4Shark ECS module has a host-path volume mechanism, but the Pritunl PLAN.md deliberately moved MongoDB off any ECS-container path — for reasons that would apply equally to a shared Mongo-on-ECS design

**Evidence (from PLAN.md, itself a grounded fact in that document):**

```
~/.claude/plans/active/pritunl-ecs/PLAN.md:47
**`modules/ecs_service` already supports a host-path-backed Docker volume** (`terraform/modules/ecs_service/main.tf:56-62` (`volume { host_path = try(volume.value.host_path, null) }`). This mechanism was the basis for the first-pass draft's colocated-MongoDB-sidecar design; it remains true infrastructure knowledge but is **no longer invoked by this migration** — MongoDB is placed on a dedicated VM, not a sidecar container, so no `host_path` volume wiring is needed for Mongo on the Pritunl task definition.
```

```
~/.claude/plans/active/pritunl-ecs/PLAN.md:61
The engineer moved MongoDB from a colocated sidecar to a **dedicated VM** because separating Mongo from the Pritunl container removes state from the ECS task's lifecycle entirely — a Pritunl container replacement (image bump, task restart, host replacement) no longer carries risk to the database, and the Mongo VM's own lifecycle (patching, backup, resizing) is decoupled from Pritunl's own release cadence; it also keeps MongoDB's install/config shape exactly as it is today (a real VM running a systemd-managed `mongod`), rather than re-platforming it into a container.
```

**Significance:** this is a directly applicable, already-made engineering decision. The rationale given for keeping Pritunl's Mongo off the ECS container path — decoupling a database's lifecycle (patching, backup, resizing) from a release-cadence-driven container's lifecycle (image bump, task restart, host replacement) — is a property of *any* container-hosted MongoDB, not specific to Pritunl. A shared Mongo-on-ECS design for the integrator fleet would face the identical trade-off: every MongoDB version bump becomes a container replacement event, and the container orchestration layer (ECS task placement, `awsvpc`/`bridge` networking, EBS attach across host replacement) would need to solve problems the VM model does not have.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| **Golden AMI (Packer)** — a versioned Mongo AMI all self-managed Mongo VMs (integrator + Pritunl) launch from | MongoDB pre-baked at image-build time, not apt-installed at every boot; fits the existing VM/`aws_instance` model without re-platforming; the integrator side already shares one generic AMI id (Finding 2), so this extends an existing shared-AMI habit rather than introducing a new deployment model | No live Packer pipeline exists today (Finding 5) — this is net-new CI/tooling, not an extension; a version bump now means rebuilding and re-launching the AMI (vs. today's `apt` upgrade in place); still needs a Renovate-style tracking mechanism for the AMI id, which nothing in the fleet currently has for AMIs | Findings 2, 5 |
| **Docker image on ECS** — Mongo-on-ECS following the `DOCKER-IMAGE-TOOL-REPOSITORIES.md` pattern | Fits 4Shark's existing tool-repo standard (Renovate, min-age gate, build-on-merge) if MongoDB is treated as a wrapped third-party tool | No precedent for a stateful database in that standard (Finding 6); the Pritunl PLAN.md already ruled out a colocated Mongo-container specifically to decouple database lifecycle from container lifecycle (Finding 7) — the same rationale applies fleet-wide, not just to Pritunl; EBS/host-path persistence across container replacement is unsolved in the existing reference implementations | Findings 6, 7 |
| **Status quo — shared Ansible role only, no new image artifact** (extend `4shark.mongodb8` to also provision the Pritunl Mongo VM, retiring the duplicate MongoDB tasks in `4shark.pritunl`) | Directly closes the one concrete, evidenced drift this spike found (Finding 4) — no new image pipeline, no new CI, reuses the role that already provisions all 15 integrator Mongo VMs uniformly; this is exactly the "recommended path" the Pritunl PLAN.md already surfaced independently: *"extract the MongoDB-only portion of `ansible/roles/4shark.pritunl/tasks/main.yml:32-79` ... into its own role ... pointed at the new Mongo VM"* (`PLAN.md:110`) | Does not "kill" the Mongo-cluster problem in the sense of a single deployable artifact — provisioning is still apt-install-at-boot, not baked; two engineers editing the shared role now affects both integrators and Pritunl simultaneously (a coupling this option deliberately introduces) | Findings 2, 4; `PLAN.md:110` |

## What remains uncertain

- Whether `ansible/playbooks/provision-4client.yml` and `provision-4client-without-vpn.yml` (the two remaining consumers of the legacy `4shark.mongodb` role, MongoDB 4.0) are still invoked for any live client, or are fully superseded by the Terraform + `provision-4client-mongodb-server.yml` path. This spike found no direct evidence either way beyond the docstring match noted in Finding 3 — inference, not confirmed.
- Whether any integrator client's Mongo replica set has ever needed a version bump in place (apt upgrade) versus a VM replacement, which would bear on how costly the golden-AMI "rebuild + relaunch" model would be relative to today's in-place apt upgrade — not investigated (would require production/operational history this spike did not have access to).
- Whether 4Shark's team has appetite to stand up and maintain a first-ever Packer/AMI-build CI pipeline (Finding 5) as a maintenance burden distinct from the existing Docker-image-tool-repo CI the team already runs for `pgbouncer`/`keycloak`.
- How EBS data-volume attach/reattach would work for a Docker-on-ECS Mongo design across container/host replacement — not resolved by any existing 4Shark precedent (Finding 7); would need its own design work if that path were chosen.

## How this reshapes the Pritunl Phase-2 Mongo-VM PR (PR 2.3)

The Pritunl PLAN.md's decision 3 already independently arrived at the "trimmed Ansible role, retargeted" path as its *recommended* option for the Mongo VM's provisioning (`PLAN.md:110`), without assuming a shared image existed. This spike's findings bear on that PR as follows, depending on which option above the engineer chooses:

- **If Option "status quo — shared Ansible role"** is chosen: PR 2.3 does not change materially from what PLAN.md decision 3 already describes — the Mongo VM is a bare `aws_instance` (mirroring `terraform/integrator-*/mongodb.tf`'s existing shape, including the shared `mongo-cwagent` IAM instance profile pattern from `terraform/shared-resources/mongo-cwagent.tf`), provisioned by a role extracted from `4shark.mongodb8` (not `4shark.pritunl`'s own duplicate tasks) — closing Finding 4's drift as a side effect. This is the smallest-diff option relative to what is already planned.
- **If "golden AMI"** is chosen: PR 2.3's `aws_instance` for the Mongo VM would reference a new `ami_id` variable pointing at a 4Shark-built Mongo AMI instead of the current generic Ubuntu AMI (`ami-0bd91caaa9bc42cf3`), and the `ignore_changes = [ami, ...]` lifecycle block (present on every existing integrator Mongo VM, `terraform/integrator-almaviva/mongodb.tf:62`) would need to be revisited — an AMI Terraform is expected to track version bumps of is the opposite of `ignore_changes = [ami]`. This is a broader-scoped change than PR 2.3 alone: the same AMI would need to be validated for both the integrator PSA topology and Pritunl's single-VM topology before either could adopt it, likely sequencing the golden-AMI build as its own prerequisite work ahead of PR 2.3, not inside it.
- **If "Docker-on-ECS Mongo"** is chosen: this would be the largest change — PR 2.3 would no longer create a Mongo VM at all, and Finding 7's already-made decision (decouple Mongo's lifecycle from the Pritunl container's lifecycle) would need to be explicitly revisited by the engineer, since a shared Mongo-on-ECS design re-couples every Mongo consumer (integrators + Pritunl) to a single container release cadence. This option was not the direction PLAN.md decision 3 took, and adopting it now would be a scope change to the already-approved plan, not an implementation detail within it.

## Suggested options for main and the engineer

- **Option A — Golden AMI (Packer):** stand up a first-ever Packer/AMI-build pipeline for MongoDB, used by both the integrator fleet and the new Pritunl Mongo VM. Highest setup cost (net-new CI, no existing pattern to extend); most fully realizes "one image, whole fleet."
- **Option B — Docker image on ECS:** treat MongoDB as a `DOCKER-IMAGE-TOOL-REPOSITORIES.md`-style tool repo. Fits existing CI/Renovate tooling, but requires solving statefulness (EBS/host-path across replacement) with no existing reference implementation, and re-opens the container-vs-VM lifecycle-coupling trade-off the Pritunl PLAN.md already resolved the other way for reasons that generalize past Pritunl.
- **Option C — Shared Ansible role only, no new image artifact:** extend `4shark.mongodb8` (already the single provisioning source for all 15 integrator Mongo VMs) to also provision the new Pritunl Mongo VM, retiring the duplicate MongoDB-install tasks in `4shark.pritunl`. Closes the one concretely evidenced drift (Finding 4) with the smallest footprint, and matches the path the Pritunl PLAN.md's decision 3 already recommended independently of this spike.
