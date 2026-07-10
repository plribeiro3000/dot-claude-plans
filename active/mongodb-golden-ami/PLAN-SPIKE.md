# PLAN-SPIKE — MongoDB Golden-AMI Pipeline

> Reference: `~/.claude/plans/active/pritunl-ecs/PLAN.md` § "Execution progress & session discoveries" (decision status for SPIKE-2); `~/.claude/plans/active/spike/mongodb-base-image/SPIKE.md` (full — the spike that first surfaced this initiative)

## Objective

Replace the single hardcoded AMI id (`ami-0bd91caaa9bc42cf3`) that every self-managed 4Shark MongoDB VM boots from with a golden-AMI pipeline — Packer building a versioned MongoDB AMI from the existing `4shark.mongodb8` Ansible role. This is the engineer's already-made decision (not re-litigated here); this document plans **how** to build the pipeline, **in what order** to de-risk its adoption, and surfaces the sub-decisions the engineer still needs to make.

## Scope

### In scope

- A Packer build pipeline (HCL2 templates + provisioning) that produces a versioned MongoDB AMI from `ansible/roles/4shark.mongodb8/`.
- The CI/build machinery that runs that pipeline (location, trigger, versioning/promotion mechanism).
- The mechanism by which Terraform consumers (integrator stacks + the new Pritunl `terraform/vpn/` stack) reference the AMI the pipeline produces.
- The de-risking sequence: pipeline first → new Pritunl Mongo VM (greenfield) second → existing 15 integrator production Mongo VMs (rolling, per replica set) third, as its own high-risk track.

### Out of scope (open question)

- The Pritunl Mongo VM's Terraform resource definition itself (Phase 2, PR 2.3 of the Pritunl migration) — this plan produces the AMI that PR consumes; the PR's own shape (subnet, SG, IAM, EIP) is `pritunl-ecs/PLAN.md`'s territory, not this one's, except for the topology sub-decision (single-node vs PSA) explicitly surfaced below because it determines what the AMI must support.
- Any change to `app-*` backend MongoDB (Atlas-managed, no VM — confirmed structurally inapplicable in `~/.claude/plans/active/spike/mongodb-base-image/SPIKE.md` Finding 1).
- Retiring the legacy `4shark.mongodb` role (MongoDB 4.0) or auditing whether `provision-4client.yml` / `provision-4client-without-vpn.yml` are still invoked for any live client — flagged as uncertain in the base-image SPIKE, not resolved by this plan.

## Current state (cited)

### The hardcoded AMI — 5 stacks, 15 VMs, one identical id

Every one of the 15 integrator Mongo instances (5 clients × 3-node PSA replica set) pins the identical AMI:

```
terraform/integrator-almaviva/mongodb.tf:26
  ami           = "ami-0bd91caaa9bc42cf3"
```

`grep -c '^resource "aws_instance" "mongo' terraform/integrator-{almaviva,atento,commcenter,maqnelson,redebrasil}/mongodb.tf` returns `3` for every one of the five stacks — 15 self-managed Mongo VMs total, confirmed directly.

Terraform explicitly disclaims managing post-boot state on that AMI, and — critically for this plan — also disclaims tracking AMI changes at all:

```
terraform/integrator-almaviva/mongodb.tf:62
    ignore_changes  = [ami, user_data, user_data_base64]
```

This `ignore_changes = [ami, ...]` is present identically on all 15 instances (verified via the same grep pattern across all five `mongodb.tf` files). Adopting a versioned AMI pipeline means this lifecycle block has to be revisited for whichever instances Terraform should track — an AMI Terraform is expected to roll forward is the opposite of `ignore_changes = [ami]`.

The stack's own provider is pinned to `sa-east-1`:

```
terraform/integrator-almaviva/providers.tf:2
  region = "sa-east-1"
```

### The Ansible role Packer will bake — `4shark.mongodb8`

The role pins MongoDB 8.2 on Ubuntu 24.04 (noble):

```
ansible/roles/4shark.mongodb8/defaults/main.yml:5,8
mongodb_version: "8.2"
...
mongodb_ubuntu_codename: "noble"
```

Its `tasks/main.yml` installs the apt-repo key, `numactl` + `gnupg` prerequisites, MongoDB itself, a THP-disable systemd unit, and enables `mongod`:

```
ansible/roles/4shark.mongodb8/tasks/main.yml:3-9
- name: Install MongoDB prerequisites
  apt:
    name:
      - gnupg
      - numactl
    state: present
```

```
ansible/roles/4shark.mongodb8/tasks/main.yml:36-49
- name: Install disable-thp systemd unit
  template:
    src: "disable-thp.service.j2"
    dest: "/etc/systemd/system/disable-thp.service"
...
- name: Enable and start disable-thp service
  systemd:
    name: disable-thp
    enabled: true
    state: started
    daemon_reload: true
```

```
ansible/roles/4shark.mongodb8/tasks/main.yml:76-80
- name: Enable and start mongod
  systemd:
    name: mongod
    enabled: true
    state: started
```

This is a clean, self-contained provisioning target for a Packer `ansible` provisioner — no external service dependency inside the role itself.

### What is NOT bakeable — client-specific config happens post-boot, today

The role's own `mongod.conf` template makes the replica-set name conditional and empty by default:

```
ansible/roles/4shark.mongodb8/defaults/main.yml:14
mongodb_conf_replSetName: ""
```

```
ansible/roles/4shark.mongodb8/templates/mongod.conf.j2:17-20
{% if mongodb_conf_replSetName %}
replication:
  replSetName: {{ mongodb_conf_replSetName }}
{% endif %}
```

The value is supplied per client, at playbook-run time, not at role-default time:

```
ansible/playbooks/provision-4client-mongodb-server.yml:57-58
  vars:
    mongodb_conf_replSetName: "{{ client_name }}"
```

The same playbook also performs `rs.initiate()` with client-specific hostnames after the role runs:

```
ansible/playbooks/provision-4client-mongodb-server.yml:90-97
      command: >
        {{ mongo_shell }} --quiet --eval "
          rs.initiate({
            _id: '{{ client_name }}',
            members: [
              { _id: 0, host: '4client-{{ client_name }}-mongo001.4shark.internal:27017' },
              ...
```

**Significance:** a golden AMI shared across every client can only bake the parts that are identical for everyone — packages, THP handling, systemd units, the base `mongod.conf` shape. The replica-set name, hostname-based member list, and `rs.initiate()` call are inherently per-instance and must remain a post-boot step (still driven by Ansible, `cloud-init`/`user_data`, or an equivalent instance-level mechanism) regardless of which sub-decisions below are chosen. This is a real constraint on Phase 1's Packer template scope, not an open question — it narrows what "bake into the image" can mean here.

### The dead Packer scaffolding — net-new tooling, not a revival

The only Packer artifacts in the codebase are two 2016-era JSON templates and a thin wrapper script, none touched since the ansible repo's initial commit:

```
ansible/packer_build.sh
AWS_PROFILE=4shark packer build $@
```

```
ansible/packer/aws-ami-ubuntu-16.04-python.json:1-16
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

`git -C ansible log -1 --format="%ai %s" -- packer/aws-ami-ubuntu-16.04-python.json packer/aws-ami-4shark-wp.json packer_build.sh` returns `2016-12-29 21:00:08 -0200 Initial Commit` for all three files — confirmed directly, none touched since. Both templates also target `region: "us-east-1"` (`aws-ami-4shark-wp.json` identically), while the Mongo fleet's own stacks run in `sa-east-1` (`terraform/integrator-almaviva/providers.tf:2`) — a further sign these templates are not a usable starting point, only historical evidence that no live Packer muscle-memory exists at 4Shark. `packer_build.sh` itself has no CI wiring — it is a local wrapper invoked by hand (`./packer_build.sh packer/<template>.json`), confirming a golden-AMI CI pipeline is net-new regardless of which repo hosts it.

### CI/build landscape at 4Shark — what pattern a new pipeline would extend

`ansible` is already governed as a HubFlow repo with the supply-chain min-age gate running:

```
terraform/identity/github_repositories.tf:61-77
  hubflow_repositories = toset([
    "ansible",
    ...
    "pritunl",
    ...
  ])
```

```
terraform/identity/github_repositories.tf:83-93
  hubflow_repositories_with_min_age_check = toset([
    "ansible",
    ...
```

But `find ansible/.github -type f` returns only `scripts/verify-minimum-age.sh` and `workflows/{renovate.yml, reverify-minimum-age.yaml, verify-minimum-age.yaml}` — confirmed directly — no `build.yaml`, `ci.yaml`, or `deploy.yaml`. The ansible repo has branch protection + Renovate + the min-age gate, but no build-on-merge pipeline of any kind today, because it has never produced a deployable artifact (only playbooks/roles consumed by `run_playbook.sh` against a target host).

The Docker-image tool-repo pattern (`pritunl`, `keycloak`) DOES have that build-on-merge machinery, e.g.:

```
keycloak/.github/workflows/build.yaml:1-8
name: Build

# Build the Keycloak image and push it to the authenticator ECR that matches the
# branch: develop builds the staging image (auth-001-staging), master builds the
# production image (auth-001). One explicit job per target — each builds the root
# Dockerfile and pushes :latest + :<short-sha> using that target's GitHub Environment
# credentials.
```

but that standard is explicitly scoped to a **container image** deliverable, not an AMI:

```
~/.claude/docs/DOCKER-IMAGE-TOOL-REPOSITORIES.md:9
A repo whose only product is a container image — a thin wrapper over an upstream image (`edoburu/pgbouncer`, `quay.io/keycloak/keycloak`, …) plus a small amount of 4Shark glue (entrypoint, config injection, shutdown behavior).
```

```
~/.claude/docs/DOCKER-IMAGE-TOOL-REPOSITORIES.md:11
If the repo instead builds one of the 4Shark applications (`app`, `integrator`, …), this standard does NOT apply — those follow the HubFlow + blue/green machinery in `DEPLOYMENT-STRATEGY.md`.
```

**Significance:** the standard's checklist (image-tag+digest pin, Renovate `docker` datasource, `build.yaml` pushing to ECR, ECS `deploy.yaml`) is written entirely in terms of a container registry and an ECS service — none of that maps 1:1 onto "produce an AMI and reference it from `aws_instance.ami`". A new golden-AMI pipeline is closer in shape (build-on-merge + versioned artifact + supply-chain gate) than it is identical in mechanics.

### The shared cwagent IAM instance profile — already fleet-wide, unaffected by this plan

```
terraform/shared-resources/mongo-cwagent.tf:1-4
# Instance profile for the CloudWatch Agent on MongoDB EC2 hosts.
# Defined here because the role/policy/profile are identical across the
# five integrator-{client} stacks and IAM is account-global, so each
# aws_instance.mongo* references this profile by name.
```

```
terraform/shared-resources/mongo-cwagent.tf:27-29
resource "aws_iam_instance_profile" "mongo_cwagent" {
  name = "mongo-cwagent"
  role = aws_iam_role.mongo_cwagent.name
}
```

This profile is orthogonal to the AMI question — it attaches to the instance, not baked into the image — and needs no change for any option below.

### The Pritunl Mongo constraint — real MongoDB required, DocumentDB is a hard blocker

Already established and carried forward from the base-image spike: Pritunl's MongoDB usage (capped collections, tailable cursors) rules out Amazon DocumentDB as a substitute. This constrains every option below to "a real `mongod` process somewhere" — it does not by itself decide VM-vs-container or single-node-vs-PSA.

### The de-risking sequence is already agreed at the plan level

```
~/.claude/plans/active/pritunl-ecs/PLAN.md:430
**Direction (pending engineer confirmation): PR 2.3's Mongo VM reuses the existing `4shark.mongodb8` role + the shared Mongo AMI** rather than a new role, a new Docker image, or a new AMI pipeline — kills the duplication and the 8.0/8.2 drift. No shared-base-image initiative needed.
```

That line predates the engineer's decision to build the golden-AMI pipeline (recorded in this task's brief); it is superseded by the brief, not a contradiction — the base-image SPIKE's finding that Pritunl's own MongoDB install (`4shark.pritunl`) duplicates and drifts from `4shark.mongodb8` (pinned at `8.0` vs `8.2`, no THP/`numactl` hardening) is exactly the drift a shared AMI closes:

```
~/.claude/plans/active/spike/mongodb-base-image/SPIKE.md Finding 4
ansible/roles/4shark.pritunl/defaults/main.yml:6
pritunl_mongodb_version: "8.0"
```

Confirmed directly: `terraform/vpn/` currently has no Mongo-related resources (`main.tf`, `outputs.tf`, `providers.tf`, `stack.tm.hcl` only, `grep -rln "mongo" terraform/vpn/` returns nothing) — the new Pritunl Mongo VM is genuinely greenfield, no data to migrate, matching the "lowest risk, adopt first" framing in the brief.

## Grounded external practices (WebSearch, cited)

### Packer + Ansible as the golden-AMI builder — the modern hybrid

Per [InfraCloud — "Automate building Golden AMIs with Packer, Ansible & CodeBuild"](https://www.infracloud.io/blogs/automate-building-golden-ami/) and corroborating community sources surfaced in the same search, golden images are built once at image-build time and never modified in place; Ansible runs during the Packer build phase only, reusing the same roles/playbooks a team already has, and Packer's own `manifest` post-processor is the mechanism CI pipelines use to learn the resulting AMI id:

```
https://developer.hashicorp.com/packer/docs/post-processors/manifest
"The manifest post-processor writes a JSON file with a list of all of the artifacts packer produces during a run."
```

This lines up directly with 4Shark's situation: `4shark.mongodb8` is exactly the kind of role this pattern reuses unmodified — Packer becomes a new *front door* to the same provisioning logic, not a rewrite of it.

### Terraform AMI reference mechanisms

The `hashicorp/amazon` Packer plugin's own `amazon-ami` data source documents the `most_recent` selection pattern that Terraform's `data "aws_ami"` mirrors on the consuming side:

```
https://developer.hashicorp.com/packer/integrations/hashicorp/amazon/latest/components/data-source/ami
"will filter and fetch an Amazon AMI, and output all the AMI information..."
"selects the newest created image when true. This is most useful for selecting a daily distro build."
```

Community guidance ([Trility — "Terraform Managed AMIs With Packer"](https://www.trility.io/insights/terraform-managed-amis-with-packer), corroborated by the HashiCorp Discuss thread ["Select three most recent AMI IDs"](https://discuss.hashicorp.com/t/select-three-most-recent-ami-ids/45478)) describes the common pattern as combining `most_recent = true` with name/tag filters in `data "aws_ami"` to pick up a Packer-built image automatically, as an alternative to hardcoding an id.

### Renovate's AMI-tracking datasource — experimental

```
https://docs.renovatebot.com/modules/datasource/aws-machine-image/
"This datasource is experimental. Its syntax and behavior may change at any time!"
"The optional currentImageName comment is automatically updated by Renovate to track the actual AMI name corresponding to the AMI ID."
```

This bears directly on Decision 3 below (automated vs manual rebuild cadence): a Renovate-driven "detect new AMI, open a PR" loop is possible but rests on a datasource HashiCorp's own docs mark experimental — a different risk profile than the mechanically-verified `docker`/`deb` datasources 4Shark's `AUTOMATED-DEPENDENCY-UPDATES.md` model otherwise relies on.

### CI wiring for Packer builds

```
https://github.com/hashicorp/setup-packer
"The hashicorp/setup-packer Action sets up the Packer CLI in your GitHub Actions workflow..."
```

Per HashiCorp's own tutorial (["Automate Packer with GitHub Actions"](https://developer.hashicorp.com/packer/tutorials/cloud-production/github-actions)) the standard shape is `packer init` (plugin download) → `packer validate` → `packer build`, triggered on push to designated branches or a version tag — directly composable with 4Shark's existing GitHub Actions conventions (`ci.yaml`-style validate-on-PR, `build.yaml`-style build-on-merge) regardless of which repo hosts it (Decision 1).

### MongoDB replica-set rolling upgrade — secondaries first, primary last

```
https://www.mongodb.com/docs/manual/tutorial/upgrade-revision/
"The upgrade process follows a rolling upgrade strategy: upgrade secondaries first, then the primary."
```

The documented sequence: upgrade each secondary's `mongod` binary via the OS package manager (official docs state this is the **preferred** method over binary replacement), wait for `rs.status()` to show the member back in `SECONDARY` state before moving to the next one, then `rs.stepDown()` the primary to force an election, confirm the new primary via `rs.status()`, and finally upgrade the stepped-down former primary the same way. The official 8.0 upgrade guide additionally documents a **Feature Compatibility Version (FCV) bump** as the final step, only after every member is running the new binary:

```
https://www.mongodb.com/docs/manual/release-notes/8.0-upgrade-replica-set/
db.adminCommand( { setFeatureCompatibilityVersion: "8.0", confirm: true } )
```

with an explicit caution to allow a "burn-in period" before bumping FCV, since FCV is not easily reversible once feature usage begins. Backup before upgrade and staging-first validation are both called out as pre-upgrade checklist items in the same official documentation. This whole sequence governs Phase 3 below — it does not apply to Phase 1 (image build) or Phase 2 (a brand-new, dataless Pritunl VM has no "existing members" to roll).

## Chosen approach — golden-AMI pipeline (Packer + `4shark.mongodb8`)

The engineer has decided: Packer builds a versioned MongoDB AMI by running the existing `4shark.mongodb8` Ansible role as an image-build-time provisioner, replacing the single hardcoded AMI id. Concretely, per the "what is bakeable" finding above, this means the pipeline's Packer template baking the packages/systemd-units/hardening/base-config shape of `4shark.mongodb8` (prerequisites, apt repo, `mongodb-org`, THP-disable unit, base `mongod.conf` skeleton), while the per-client identity (`replSetName`, hostname-based member list, `rs.initiate()`) stays a post-boot step exactly as it is today, unaffected by this initiative. This is not an open question — it is a structural consequence of one AMI serving multiple clients — but it does shape Phase 1's Packer template scope, called out explicitly in Phase 1 below.

What remains open is **how** the pipeline is built, versioned, referenced, and rolled out — the five decisions below.

## Open sub-decisions — options with trade-offs, engineer to choose

### Decision 1: Where does the Packer template + build CI live?

**Option A — inside the `ansible` repo** (alongside `4shark.mongodb8` and the dead `packer/` directory it would replace)

- Pros: co-located with the role it bakes — one PR changes the role and the image together, no cross-repo coordination; `ansible` is already a HubFlow repo with the min-age gate wired (`terraform/identity/github_repositories.tf:61-93`), so branch protection + supply-chain gate already exist, only a `build.yaml`-equivalent (Packer build, not Docker build) needs to be added; reuses the existing `packer/` directory name rather than inventing a new one.
- Cons: `ansible` today has no build-on-merge machinery of any kind (confirmed above) — this is still net-new CI work regardless; mixes a "provisioning source" repo with a "deployable artifact producer" repo, a distinction the Docker-tool-repo standard treats as a reason for a dedicated repo (`DOCKER-IMAGE-TOOL-REPOSITORIES.md:9`, though that standard is container-scoped, not AMI-scoped, per the current-state finding above); every `ansible` CI run now potentially includes an AMI build step, which the repo's existing consumers (all the other roles/playbooks) have no reason to wait on.
- Cost: smaller — one existing repo, existing governance already in Terraform.
- Risk: coupling a fast-moving playbook/role repo to a slower, AMI-build-cadence artifact.

**Option B — a new dedicated repo** (mirroring the `pritunl`/`keycloak` Docker-tool-repo shape, but for a Packer/AMI deliverable instead of a Docker image)

- Pros: clean separation between "provisioning source" (`ansible`) and "deployable artifact" (the new repo) — matches the spirit, if not the letter, of `DOCKER-IMAGE-TOOL-REPOSITORIES.md`'s rationale (item 9's governance-via-Terraform, item 5's min-age gate, items 6-7's build/deploy split) even though the standard itself is written for containers; a dedicated repo can pin its own CI cadence (e.g., nightly/weekly rebuild) independent of `ansible`'s own commit cadence.
- Cons: this stretches a container-oriented standard onto an AMI deliverable with no adaptation — `DOCKER-IMAGE-TOOL-REPOSITORIES.md` explicitly has no "item 6-equivalent" for Packer build-on-merge or "item 7-equivalent" for an AMI-consuming deploy step, so most of the checklist would need to be reinterpreted rather than copied; the role itself (`4shark.mongodb8`) still lives in `ansible` — the new repo would need to either vendor/reference it (Ansible `roles_path`/Galaxy-style dependency) or the build would need cross-repo checkout, adding a coordination step Option A does not have; another repo to govern in Terraform (`main_branch_repositories` or `hubflow_repositories`), another `renovate.json`, another min-age wiring.
- Cost: higher — new repo scaffolding, new governance PR, cross-repo dependency to solve.
- Risk: the cross-repo role-checkout mechanism becoming its own maintenance burden; two places to look when debugging a bad AMI (which repo's Packer config, which repo's role version).

### Decision 2: AMI reference mechanism in Terraform

**Option A — `data "aws_ami"` filtered by name/tag pattern, `most_recent = true`**

- Pros: no extra state to manage — Terraform reads the latest matching AMI directly from the EC2 API at plan time, per the `most_recent`/filter pattern both HashiCorp's own `amazon-ami` Packer data source and community Terraform guidance document (URLs above); simplest to reason about, no separate write step after the Packer build besides tagging the AMI correctly.
- Cons: every `terraform plan` picks up the newest matching AMI automatically — a `new_ami_launches_new_instances`-type surprise unless every consumer keeps `ignore_changes = [ami]` deliberately and promotes explicitly via `-replace` or a pinned filter value; "most recent" is inherently mutable across time, which cuts against reproducible/auditable plans unless the filter is pinned to a specific build tag per environment.
- Cost: lower — no new AWS resource, just a Packer step to tag the AMI consistently (name pattern + tags Terraform's filter can match).
- Risk: an unintentional AMI rollout to production if a filter is too broad and `ignore_changes` is dropped somewhere.

**Option B — SSM Parameter Store value written by the pipeline, read by Terraform**

- Pros: an explicit, versioned pointer — the pipeline writes the new AMI id to a named SSM parameter only when a build is meant to be "current"; Terraform's `data "aws_ssm_parameter"` read is exactly the pattern already used elsewhere in these same stacks for subnet ids (`terraform/integrator-almaviva/mongodb.tf:16-19`, `data "aws_ssm_parameter" "prv_a_subnet_id"`) — a familiar, already-idiomatic mechanism in this codebase, not a new concept; separates "a build happened" from "this build is promoted", giving an explicit gate.
- Cons: one more moving part — the pipeline needs write access to SSM (an IAM permission it does not have today), and a human or automation step to decide *when* to update the parameter (Decision 3 territory); if forgotten, environments silently keep running an old AMI with no Terraform-visible drift signal.
- Cost: medium — new SSM parameter(s) (likely one per environment/client given the per-stack `ignore_changes` pattern), a pipeline IAM permission, and a decision on the write trigger.
- Risk: the promotion step itself becoming a manual bottleneck or a forgotten step, silently pinning stale AMIs.

**Option C — a Terraform variable bumped explicitly, per stack, in a PR** (closest to today's shape, just versioned instead of a single eternal literal)

- Pros: zero new AWS resource or IAM permission; every AMI change is a reviewable, auditable Terraform diff — matches 4Shark's existing PR-gated apply model exactly; keeps `ignore_changes = [ami]` semantics intact until a deliberate PR removes/changes it per stack, so no unplanned rollout risk.
- Cons: fully manual promotion — an engineer must open a PR per stack (or per client) to bump the AMI id string after every build meant for that environment; does not "close the loop" the way the brief's "golden-AMI pipeline" framing implies — the pipeline produces artifacts but promotion stays a hand process, same as today's hardcoded id, just repeated per rebuild instead of once.
- Cost: lowest engineering cost, highest ongoing operational (PR-per-promotion) cost.
- Risk: low technical risk, but does not reduce the toil this initiative is partly meant to remove.

### Decision 3: AMI versioning + promotion trigger

**Option A — automated cadence** (a scheduled rebuild, e.g. weekly/monthly, auto-opens a PR or auto-writes the pointer on a successful build)

- Pros: patches (MongoDB point releases, Ubuntu security updates) flow into a fresh AMI without a human remembering to trigger a build; can be paired with Renovate's `aws-machine-image` datasource (URL above) to auto-detect and propose the new AMI id in a PR, mirroring the `docker`/`deb` datasource pattern `AUTOMATED-DEPENDENCY-UPDATES.md` already uses for other artifacts.
- Cons: the `aws-machine-image` datasource is explicitly marked experimental by Renovate's own docs (quoted above) — a different risk posture than the mechanically-verified datasources the rest of 4Shark's dependency-update model relies on; an automated rebuild landing on a bad MongoDB patch release still needs the same 7-day-quarantine-style gate the rest of the fleet has, which does not exist for AMIs today; a scheduled rebuild with no consumer promotes it (Decision 2 Option C) accomplishes nothing beyond producing an unused AMI.
- Cost: higher upfront (cadence + Renovate custom-manager wiring), lower ongoing toil.
- Risk: shipping an unvetted MongoDB/OS patch automatically to a database tier, without the same quarantine model the fleet uses elsewhere.

**Option B — manual/on-demand build** (`workflow_dispatch`, or triggered by a change to `4shark.mongodb8`), explicit promotion per Decision 2's mechanism

- Pros: mirrors keycloak/pritunl's own `deploy.yaml` philosophy — "build always happens on merge/dispatch; promotion (deploy) is a separate explicit choice" (`DOCKER-IMAGE-TOOL-REPOSITORIES.md` item 7's rationale, generalized) — a pattern 4Shark already trusts for tool repos; no dependency on an experimental Renovate datasource; every AMI that exists was deliberately built for a reason someone can name.
- Cons: relies on someone noticing an upstream MongoDB/Ubuntu security patch and triggering a rebuild — no automatic signal unless paired with a lighter-weight notification (e.g., Renovate `deb`/`docker` datasource on the *role's* pinned versions, separate from the experimental AMI datasource); does not remove all manual toil, only shifts where it sits.
- Cost: lower upfront, but latent ongoing cost of "who watches for MongoDB patch releases".
- Risk: staleness — an AMI nobody rebuilds silently drifts behind current MongoDB patches, same failure mode the current single static id already has, just with better tooling to fix it once someone notices.

### Decision 4: Integrator production cutover sequencing/automation

**Option A — Terraform `-replace` + rolling, orchestrated by the pipeline/automation**

- Pros: consistent, repeatable, less manual keystroke risk per replica-set member; could be scripted once and reused across all 5 client stacks.
- Cons: `terraform -replace` on a stateful `aws_instance` destroys and recreates it — for a Mongo replica-set member this must be sequenced with MongoDB's own rolling-upgrade discipline (secondary drains from the replica set, new member rejoins, only then move to the next), which Terraform itself has no native awareness of; automating "wait for `rs.status()` to show `SECONDARY`" inside a Terraform-driven flow means wrapping `terraform apply` with external orchestration (a script or a runbook step), not a pure-Terraform capability — `4shark`'s own Terraform Policy already treats `-target`/automated-replace patterns for routine stateful operations cautiously per `TERRAFORM-POLICY.md` (see auto-injected terraform context, not independently re-verified in this spike — flagged as a citation gap).
- Cost: higher upfront (needs a wrapper/orchestration layer around raw Terraform), lower per-execution toil once built.
- Risk: touching production Mongo replica sets with less human-in-the-loop judgment per step, on a first-of-its-kind pipeline.

**Option B — manual runbook-driven replacement, per replica set, secondaries-first / primary-last**

- Pros: directly follows the documented MongoDB rolling-upgrade discipline (URLs above: upgrade/replace secondaries one at a time, wait for `SECONDARY` state, `rs.stepDown()` the primary last, confirm election, replace the former primary); matches 4Shark's `/runbook` skill pattern already in use for other operational, database-adjacent procedures; maximal human judgment at each step for a first-time, production-database-touching change; backup + maintenance-window practice (both called out in MongoDB's own upgrade docs) fits naturally into a runbook checklist.
- Cons: 5 clients × 3 nodes = 15 replacements done by hand (or semi-scripted) the first time through — slower, more toil per cutover; no automatic guardrail preventing a step being done out of order beyond the runbook's own discipline.
- Cost: lower engineering cost (no orchestration layer to build), higher operational time per cutover round.
- Risk: human error in sequencing (skipping the wait-for-SECONDARY step, replacing the primary before the last secondary is done) — mitigated by the runbook's explicit ordering, not eliminated.

### Decision 5: Pritunl Mongo VM topology — single-node vs PSA

**Option A — single-node** (one `mongod`, no replica set)

- Pros: matches "the VPN doesn't need integrator-grade HA" reasoning — Pritunl's own MongoDB usage is session/config state for the VPN service itself, not client business data; simpler AMI consumer (no `rs.initiate()`, no `replSetName`, no arbiter/secondary sizing); fewer moving parts for the very-first adopter of a brand-new pipeline, keeping Phase 2 genuinely low-risk as the brief intends.
- Cons: no automatic failover if the single Mongo VM fails — Pritunl VPN sessions/config become unavailable until manual recovery; diverges from the integrator fleet's PSA precedent, meaning the golden AMI would need to support two different post-boot config shapes (single-node vs PSA) rather than one uniform one.
- Cost: lower — one VM, one EBS volume, no multi-AZ subnet wiring for Mongo specifically.
- Risk: single point of failure for the VPN's own backing store; the base-image SPIKE did not investigate Pritunl's actual availability requirements for its Mongo dependency — **not researched**, flagged as a gap for the engineer to weigh in on, not assumed here.

**Option B — PSA** (mirrors the integrator topology exactly: primary + secondary + arbiter across 2 AZs)

- Pros: identical topology to what the golden AMI already needs to support for the integrator fleet — no second post-boot config shape to build or test; automatic failover if one Mongo VM fails, consistent with the integrator fleet's own HA reasoning (`terraform/integrator-almaviva/mongodb.tf:1-11`'s documented AZ-quorum rationale); the golden-AMI pipeline gets validated against the *same* topology it will need for Phase 3's larger rollout, arguably making Phase 2 a better dress rehearsal for Phase 3.
- Cons: 3 VMs instead of 1 for a service whose own PLAN.md already chose "dedicated VM, decoupled from container lifecycle" specifically to keep Pritunl's infra footprint small (`pritunl-ecs/PLAN.md:61`); more subnets/AZs/security-group wiring to stand up for Phase 2, arguably reintroducing some of the complexity the VM-not-container decision was trying to avoid; less clear that Pritunl's own workload needs 3-node HA the way client-data replica sets do.
- Cost: higher — 3× the VM/EBS footprint of Option A, more Terraform surface for the Phase-2 PR.
- Risk: lower operational risk (no SPOF), but a bigger surface for the *first* adopter of a brand-new pipeline to debug if something goes wrong.

## Risks (cross-cutting)

| Risk | Impact | Possible mitigation |
|------|--------|---------------------|
| Touching 15 production Mongo replica sets across 5 clients (Phase 3) | High — integrator MongoDB holds live client integration state; a bad replacement sequence can take a replica set down or lose quorum | Follow the documented MongoDB rolling-upgrade discipline (secondaries first, wait for `SECONDARY`, step-down primary last per URLs above); backup + staging-first validation before any production replica set is touched; treat Phase 3 as its own runbook-driven track, separate from Phase 1/2 |
| AMI-reference migration flips `ignore_changes = [ami, ...]` semantics (Decision 2) | Medium-High — the exact `lifecycle` block that currently prevents unplanned instance replacement (`terraform/integrator-almaviva/mongodb.tf:62`) must be deliberately revisited per stack; getting this wrong on 15 production instances risks an unintended `terraform apply` replacing a live Mongo node | Decide Decision 2 explicitly per environment before any integrator stack's `mongodb.tf` is edited; consider keeping `ignore_changes = [ami]` on production stacks even after the pipeline exists, promoting only via an explicit `-replace` step (ties to Decision 4) |
| Drift between the new pipeline's AMI and the current static AMI during the transition window | Medium — while Phase 1 (pipeline) and Phase 2 (Pritunl greenfield) are underway, the 15 integrator VMs still run the old static AMI; any interim manual change to `4shark.mongodb8` (bug fix, hardening addition) now has to be applied twice — once to running VMs (as today), once when the next golden-AMI build picks it up | Treat the golden AMI as the sole path for `4shark.mongodb8` changes once Phase 1 ships, even before Phase 3 cuts over the integrator fleet, so there is one place changes land, not two |
| Net-new Packer/CI pipeline with no existing 4Shark muscle-memory (Finding 5, base-image SPIKE) | Medium — first-of-its-kind tooling at 4Shark; no prior incident/debugging history to draw on | Keep Phase 1 narrowly scoped (bake only what the "what is NOT bakeable" finding says is safe to bake); validate the pipeline's own build (not just its consumers) before Phase 2 begins |
| FCV bump ordering error during any future MongoDB version upgrade via this pipeline (Phase 3 and beyond) | Medium — MongoDB's official docs warn `setFeatureCompatibilityVersion` mid-initial-sync restarts the sync, and premature FCV bump narrows the downgrade window | Follow the documented sequence exactly: all members on new binary → burn-in period → FCV bump only then (per URLs above) |
| Pritunl VPN Mongo VM (Phase 2) is the first production consumer of a brand-new pipeline | Low — mitigated structurally by being greenfield (no data to migrate, confirmed no existing `terraform/vpn/` Mongo resources) | Already the brief's own reasoning for sequencing Phase 2 before Phase 3 — no additional mitigation needed beyond following that order |

## Execution phases

### Phase 1: Build the Packer golden-AMI pipeline

**Objective:** produce a versioned MongoDB AMI from `4shark.mongodb8`, with CI, without touching any existing running instance.

**Components:**
- Packer HCL2 template(s) provisioning via the `ansible` provisioner against `4shark.mongodb8`, baking only the identical-for-everyone parts (packages, THP unit, base `mongod.conf` skeleton) per the "what is NOT bakeable" finding above.
- CI wiring (location per Decision 1; trigger/versioning per Decision 3) — `packer init` → `packer validate` → `packer build`, `manifest` post-processor to capture the resulting AMI id for downstream consumption.
- Whatever promotion/reference mechanism Decision 2 lands on, stood up but pointing at nothing production-critical yet.

**Dependencies:** none — this phase can start immediately; it does not touch any `terraform/integrator-*` or `terraform/vpn/` resource.

**Success criteria:**
- [ ] A Packer build produces a bootable MongoDB AMI with `mongod` installed, THP disabled, and the base config template in place.
- [ ] CI runs the build (per Decision 1/3's chosen trigger) and the resulting AMI id is retrievable via whichever mechanism Decision 2 selects.
- [ ] No existing `terraform/integrator-*/mongodb.tf` or `terraform/vpn/` file is modified in this phase.

### Phase 2: New Pritunl Mongo VM adopts the golden AMI (greenfield)

**Objective:** validate the pipeline's output against a real, production-bound consumer, on infrastructure with zero existing data or traffic to protect.

**Components:**
- The Pritunl Mongo VM's `aws_instance` (PR 2.3 of the Pritunl migration, `terraform/vpn/`) references the golden AMI via Decision 2's mechanism instead of the generic Ubuntu AMI the base-image SPIKE's superseded direction assumed.
- Post-boot config (client-specific `replSetName`/`rs.initiate()` equivalent, or none at all if Decision 5 picks single-node) applied exactly as it would be for any other consumer of this AMI.
- Topology per Decision 5 (single-node vs PSA).

**Dependencies:** Phase 1 complete (an AMI must exist to reference); Decision 2 and Decision 5 resolved; otherwise unblocked by Phase 3.

**Success criteria:**
- [ ] The Pritunl Mongo VM boots from the golden AMI, `mongod` running, reachable by the Pritunl container per `pritunl-ecs/PLAN.md`'s existing decision 3.
- [ ] No `4shark.pritunl` role duplication remains for MongoDB install/config (closes Finding 4 of the base-image SPIKE as a side effect).
- [ ] The pipeline has now been exercised end-to-end against one real, if low-stakes, consumer before Phase 3 touches production client data.

### Phase 3: Integrator production Mongo fleet rolling cutover — separate high-risk track

**Objective:** migrate the 15 existing production integrator Mongo VMs (5 clients × 3-node PSA) onto the golden AMI, one replica set at a time, with zero data loss and no extended quorum loss.

**Components:**
- Per Decision 4's chosen mechanism (orchestrated `-replace` or manual runbook), each of the 5 replica sets is cut over independently: secondaries first, wait for `SECONDARY` state, step down + replace the primary last, per the documented MongoDB rolling-upgrade sequence (URLs above).
- Backup taken before each replica set's cutover begins (per MongoDB's own pre-upgrade checklist).
- `ignore_changes = [ami, ...]` (`terraform/integrator-*/mongodb.tf:62`-equivalent, all 5 stacks) explicitly revisited per Decision 2's chosen mechanism, one stack at a time — not a single fleet-wide flip.
- A maintenance window per client, sized to the primary step-down + replacement window (MongoDB's own docs describe the step-down failover itself as ~10-20 seconds, but the full node replacement — new instance boot + role convergence + resync — is materially longer and client-communication-worthy).

**Dependencies:** Phase 1 and Phase 2 both complete and validated; Decision 4 resolved; this phase should not start until Phase 2 has run in production for a burn-in period the engineer is comfortable with (not specified here — **open question**, see below).

**Success criteria:**
- [ ] Each of the 5 client replica sets is fully migrated to the golden AMI with zero data loss, verified via replica set member count + `rs.status()` health per set.
- [ ] Each replica set's `mongodb.tf` lifecycle block reflects the chosen AMI-tracking decision (Decision 2), consistently applied.
- [ ] No client-reported incident traceable to the cutover.

## Technical decisions to be made (NOT decided here)

| Decision point | Options | Trade-off summary | Engineer to choose |
|----------------|---------|-------------------|---------------------|
| Where does the Packer template + build CI live? | A: inside `ansible` repo / B: new dedicated repo | A is less net-new plumbing but couples repos with different cadences; B mirrors the tool-repo shape but stretches a container-oriented standard onto an AMI and needs a cross-repo role dependency | □ |
| AMI reference mechanism in Terraform | A: `data "aws_ami"` most_recent+filter / B: SSM Parameter Store pointer / C: Terraform var bumped per PR | A is simplest but implicitly mutable; B is explicit/idiomatic to this codebase's existing SSM usage but needs new IAM + a promotion trigger; C is lowest-risk but highest ongoing manual toil | □ |
| AMI versioning + promotion trigger | A: automated cadence (Renovate `aws-machine-image`, experimental) / B: manual/on-demand build + explicit promotion | A reduces toil but relies on an experimental Renovate datasource with no quarantine-gate equivalent for AMIs; B mirrors the tool-repo build/deploy split 4Shark already trusts but needs someone to notice upstream patches | □ |
| Integrator production cutover sequencing/automation (Phase 3) | A: Terraform `-replace` + rolling, orchestrated / B: manual runbook-driven, secondaries-first/primary-last | A is repeatable but Terraform has no native awareness of MongoDB's own rolling-upgrade discipline, needing an external wrapper; B directly follows documented MongoDB practice and 4Shark's own `/runbook` pattern but is slower per cutover round | □ |
| Pritunl Mongo VM topology (Phase 2) | A: single-node / B: PSA (mirrors integrator topology) | A is simpler and keeps Phase 2 low-risk but is a SPOF and needs a second post-boot config shape; B reuses the exact topology Phase 3 will need (better dress rehearsal) but is 3× the footprint for a service whose own PLAN.md chose "small dedicated VM" | □ |

## Open questions for the engineer

- How long should Phase 2 (Pritunl Mongo VM) run in production before Phase 3 (integrator fleet cutover) begins — a specific burn-in period was not specified in the brief and is not assumed here.
- Whether Pritunl's own availability requirement for its MongoDB dependency has ever been characterized (Decision 5's Option A con flags this as **not researched** — the base-image SPIKE did not investigate it).
- Whether 4Shark's Terraform Policy has an existing stance on `-replace`/automated-replacement patterns for stateful production resources that should directly inform Decision 4 — flagged as a citation gap in the Decision 4 discussion above, not independently verified in this research pass.
- Whether the legacy `4shark.mongodb` role (MongoDB 4.0) and its two remaining playbook consumers (`provision-4client.yml`, `provision-4client-without-vpn.yml`) are still live for any client — unresolved by the base-image SPIKE, and out of this plan's scope, but worth a decision on whether Phase 1's Packer template should account for them at all (this plan assumes not, per Scope § Out of scope).

## Sources

- `terraform/integrator-almaviva/mongodb.tf:26,62` — hardcoded AMI id and the `ignore_changes` lifecycle block (identical shape confirmed across all 5 integrator stacks via `grep -c`)
- `terraform/integrator-almaviva/providers.tf:2` — confirms `sa-east-1` as the fleet's region
- `ansible/roles/4shark.mongodb8/defaults/main.yml:5,8,14` — MongoDB version, Ubuntu codename, default empty `replSetName`
- `ansible/roles/4shark.mongodb8/tasks/main.yml:3-9,36-49,76-80` — prerequisites, THP-disable unit, mongod enable/start
- `ansible/roles/4shark.mongodb8/templates/mongod.conf.j2:17-20` — conditional `replSetName` block
- `ansible/playbooks/provision-4client-mongodb-server.yml:47-58,90-97` — role list, per-client `replSetName` var, `rs.initiate()` with client-specific hostnames
- `ansible/packer_build.sh`, `ansible/packer/aws-ami-ubuntu-16.04-python.json:1-16`, `ansible/packer/aws-ami-4shark-wp.json` — dead 2016-era Packer scaffolding, confirmed via `git log` (`2016-12-29 21:00:08 -0200 Initial Commit`) and region mismatch (`us-east-1` vs the fleet's `sa-east-1`)
- `terraform/identity/github_repositories.tf:61-77,83-93` — `ansible` and `pritunl` governed as HubFlow repos with the min-age check
- `keycloak/.github/workflows/build.yaml:1-8` — the Docker-tool-repo build-on-merge pattern, per-branch/per-environment job shape
- `~/.claude/docs/DOCKER-IMAGE-TOOL-REPOSITORIES.md:9,11` — the standard's explicit container-image scope, does not extend to AMIs
- `terraform/shared-resources/mongo-cwagent.tf:1-4,27-29` — shared IAM instance profile, orthogonal to this plan
- `terraform/vpn/` (directory listing + `grep -rln "mongo"`) — confirms no existing Mongo resources, genuinely greenfield
- `ansible/roles/4shark.pritunl/defaults/main.yml:6` — `pritunl_mongodb_version: "8.0"`, the drift this pipeline closes
- `~/.claude/plans/active/pritunl-ecs/PLAN.md:61,430` — the dedicated-VM rationale and the superseded SPIKE-2 direction
- `~/.claude/plans/active/spike/mongodb-base-image/SPIKE.md` (full) — Finding 1 (Atlas vs self-managed split), Finding 2 (existing shared-AMI habit), Finding 3 (legacy role), Finding 4 (Pritunl's MongoDB duplication/drift), Finding 5 (dead Packer), Finding 6 (Docker-tool-repo scope), Finding 7 (VM-not-container rationale)
- [InfraCloud — Automate building Golden AMIs with Packer, Ansible & CodeBuild](https://www.infracloud.io/blogs/automate-building-golden-ami/) — Packer+Ansible golden-AMI pattern
- [HashiCorp Packer — manifest post-processor](https://developer.hashicorp.com/packer/docs/post-processors/manifest) — "The manifest post-processor writes a JSON file with a list of all of the artifacts packer produces during a run."
- [HashiCorp Packer — amazon-ami data source](https://developer.hashicorp.com/packer/integrations/hashicorp/amazon/latest/components/data-source/ami) — `most_recent`/filter selection pattern
- [Trility — Terraform Managed AMIs With Packer](https://www.trility.io/insights/terraform-managed-amis-with-packer) — Terraform-side `data "aws_ami"` consumption pattern
- [HashiCorp Discuss — Select three most recent AMI IDs](https://discuss.hashicorp.com/t/select-three-most-recent-ami-ids/45478) — corroborates the `most_recent`+filter pattern
- [Renovate Docs — aws-machine-image datasource](https://docs.renovatebot.com/modules/datasource/aws-machine-image/) — "This datasource is experimental. Its syntax and behavior may change at any time!"
- [GitHub — hashicorp/setup-packer](https://github.com/hashicorp/setup-packer) — CI action for running Packer in GitHub Actions
- [HashiCorp — Automate Packer with GitHub Actions tutorial](https://developer.hashicorp.com/packer/tutorials/cloud-production/github-actions) — `packer init` → `validate` → `build` CI shape
- [MongoDB Docs — Upgrade to the Latest Self-Managed Patch Release](https://www.mongodb.com/docs/manual/tutorial/upgrade-revision/) — rolling upgrade: secondaries first, primary last, package-manager preferred, backup/staging pre-checklist
- [MongoDB Docs — Upgrade a Replica Set to 8.0](https://www.mongodb.com/docs/manual/release-notes/8.0-upgrade-replica-set/) — FCV bump sequencing and burn-in guidance
- See auxiliary: `mongodb-golden-ami_open-decisions-comparison_1.html` — visual side-by-side of the 5 open decisions for engineer review
