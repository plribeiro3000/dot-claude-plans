# PLAN — MongoDB Golden-AMI Pipeline

> Reference: `~/.claude/plans/active/pritunl-ecs/PLAN.md` § "Execution progress & session discoveries"; `~/.claude/plans/active/spike/mongodb-base-image/SPIKE.md` (full); derived from `PLAN-SPIKE.md`

## Objective

Replace the single hardcoded AMI id (`ami-0bd91caaa9bc42cf3`) that every self-managed 4Shark MongoDB VM boots from with a golden-AMI pipeline — Packer building a versioned MongoDB AMI from the existing `4shark.mongodb8` Ansible role, hosted in a new dedicated `mongodb` repository. The pipeline bakes the common base (MongoDB 8.2 + the role's hardening) shared by every consumer; per-client identity (replica-set name, member list, `rs.initiate()`) remains a post-boot step, unaffected by this initiative. Rollout follows a three-phase de-risking sequence: build the pipeline, adopt it on a greenfield low-stakes consumer (the new Pritunl Mongo VM), then cut the existing 15-VM integrator production fleet over on its own high-risk, runbook-driven track.

## Scope

### In scope

- A Packer build pipeline (HCL2 templates + provisioning) that produces a versioned MongoDB AMI from `4shark.mongodb8`, hosted in the new dedicated `mongodb` repository alongside the migrated role and the build CI.
- The CI/build machinery that runs that pipeline — location, trigger, and the versioning/promotion mechanism (Technical decisions below).
- The mechanism by which Terraform consumers (integrator stacks + the new Pritunl `terraform/vpn/` stack) reference the AMI the pipeline produces.
- Root (gp2) disk sizing for every consumer of the AMI, anchored on measured CloudWatch disk usage.
- The de-risking sequence: pipeline first (Phase 1) → new Pritunl Mongo VM, greenfield (Phase 2) → existing 15 integrator production Mongo VMs, rolling per replica set (Phase 3), as its own high-risk track.

### Out of scope

- The Pritunl Mongo VM's Terraform resource definition itself (Phase 2, PR 2.3 of the Pritunl migration) — this plan produces the AMI that PR consumes; the PR's own shape (subnet, SG, IAM, EIP) is `pritunl-ecs/PLAN.md`'s territory, not this one's, except for the topology decision (single-node) recorded below because it determines what the AMI must support.
- Any change to `app-*` backend MongoDB (Atlas-managed, no VM — confirmed structurally inapplicable in `~/.claude/plans/active/spike/mongodb-base-image/SPIKE.md` Finding 1).
- Retiring the legacy `4shark.mongodb` role (MongoDB 4.0) or auditing whether `provision-4client.yml` / `provision-4client-without-vpn.yml` are still invoked for any live client — flagged as uncertain in the base-image SPIKE, not resolved by this plan (see Open questions below).

## Chosen approach

**Direction:** golden-AMI pipeline — Packer building a versioned MongoDB AMI from the existing `4shark.mongodb8` Ansible role, hosted in a new dedicated `mongodb` repository, referenced by Terraform via a tag-filtered `data "aws_ami"` lookup, rolled out through a three-phase de-risking sequence.

Per the draft's "what is NOT bakeable" finding, the pipeline's Packer template bakes the packages/systemd-units/hardening/base-config shape of `4shark.mongodb8` (prerequisites, apt repo, `mongodb-org`, THP-disable unit, base `mongod.conf` skeleton):

```
ansible/roles/4shark.mongodb8/tasks/main.yml:3-9,36-49,76-80
- name: Install MongoDB prerequisites ... gnupg, numactl
- name: Install disable-thp systemd unit
- name: Enable and start mongod
```

The per-client identity (`replSetName`, hostname-based member list, `rs.initiate()`) stays a post-boot step exactly as it is today — a structural consequence of one AMI serving multiple clients, confirmed by:

```
ansible/roles/4shark.mongodb8/defaults/main.yml:14
mongodb_conf_replSetName: ""
```

```
ansible/playbooks/provision-4client-mongodb-server.yml:57-58,90-97
  vars:
    mongodb_conf_replSetName: "{{ client_name }}"
...
      command: > {{ mongo_shell }} --quiet --eval " rs.initiate({ _id: '{{ client_name }}', ... "
```

Ansible is not retired by this plan — it becomes Packer's build-time provisioner (the `ansible` provisioner running the same `4shark.mongodb8` role, unmodified in its provisioning logic) instead of a target-host `run_playbook.sh` invocation, per the grounded golden-AMI pattern below.

**Rationale (from engineer):** a dedicated repository co-locating the Packer definition, the migrated `4shark.mongodb8` role, and the build CI follows the community-standard co-located structure (`packer/` + `ansible/`); the `ansible` repo keeps its other roles, only the mongodb role migrates out. This resolves the cross-repo role-dependency concern the draft raised against a dedicated repo (Decision 1, Option B con) — migrating the role in, rather than referencing it across repos, removes the coordination step. Reduced root-disk sizing for new instances is anchored on real measured usage: CloudWatch `disk_used_percent` (path `/`, read-only, no SSH — the Mongo hosts run the CloudWatch agent) across all 15 integrator Mongo VMs shows the 60GB data-bearing nodes (mongo003/004) using ~5.5–11GB (9–18%) and the 20GB arbiters (mongo005) using ~3–5.6GB, giving ≈3.6× headroom at 40GB over the ~11GB real max.

**Source patterns referenced:**

- [InfraCloud — Automate building Golden AMIs with Packer, Ansible & CodeBuild](https://www.infracloud.io/blogs/automate-building-golden-ami/) — golden images built once at image-build time, never modified in place; Ansible reused unmodified as the build-phase provisioner.
- [HashiCorp Packer — manifest post-processor](https://developer.hashicorp.com/packer/docs/post-processors/manifest) — `"The manifest post-processor writes a JSON file with a list of all of the artifacts packer produces during a run."`
- [HashiCorp Packer — amazon-ami data source](https://developer.hashicorp.com/packer/integrations/hashicorp/amazon/latest/components/data-source/ami) — `"selects the newest created image when true. This is most useful for selecting a daily distro build."`
- [Trility — Terraform Managed AMIs With Packer](https://www.trility.io/insights/terraform-managed-amis-with-packer) and [HashiCorp Discuss — Select three most recent AMI IDs](https://discuss.hashicorp.com/t/select-three-most-recent-ami-ids/45478) — `data "aws_ami"` `most_recent`+filter consumption pattern.
- [HashiCorp — Automate Packer with GitHub Actions tutorial](https://developer.hashicorp.com/packer/tutorials/cloud-production/github-actions) — `packer init` → `packer validate` → `packer build` CI shape.
- [MongoDB Docs — Upgrade to the Latest Self-Managed Patch Release](https://www.mongodb.com/docs/manual/tutorial/upgrade-revision/) — `"The upgrade process follows a rolling upgrade strategy: upgrade secondaries first, then the primary."`
- [MongoDB Docs — Upgrade a Replica Set to 8.0](https://www.mongodb.com/docs/manual/release-notes/8.0-upgrade-replica-set/) — FCV bump sequencing and burn-in guidance.
- [Renovate Docs — aws-machine-image datasource](https://docs.renovatebot.com/modules/datasource/aws-machine-image/) — `"This datasource is experimental. Its syntax and behavior may change at any time!"` (grounds the decision NOT to rely on it).

## Execution phases

### Phase 1: Build the `mongodb` repo — Packer pipeline + migrated role + CI

**Objective:** produce a versioned, size-reduced MongoDB AMI from `4shark.mongodb8`, with CI, without touching any existing running instance.

**Components:**
- New dedicated repository `mongodb`, co-locating: the Packer HCL2 template(s) (provisioning via the `ansible` provisioner against `4shark.mongodb8`), the `4shark.mongodb8` role itself (migrated in from the `ansible` repo — `ansible` keeps its other roles), and the build CI.
- Packer template bakes only the identical-for-everyone parts (packages, THP unit, base `mongod.conf` skeleton) per the "what is NOT bakeable" finding — MongoDB 8.2, per `ansible/roles/4shark.mongodb8/defaults/main.yml:5,8` (`mongodb_version: "8.2"`, `mongodb_ubuntu_codename: "noble"`).
- CI wiring: `packer init` → `packer validate` → `packer build`, `manifest` post-processor to capture the resulting AMI id; each build tagged with build date + git commit (immutable, per Technical decisions below).
- Cleanup/lifecycle step retaining only the 3 most recent AMIs, to bound storage cost.
- The `data "aws_ami"` tag-filtered lookup mechanism stood up (Technical decisions below), pointing at nothing production-critical yet.

**Dependencies:** none — this phase can start immediately; it does not touch any `terraform/integrator-*` or `terraform/vpn/` resource.

**Success criteria:**
- [ ] A Packer build in the new `mongodb` repo produces a bootable MongoDB AMI with `mongod` installed, THP disabled, and the base config template in place.
- [ ] CI runs the build and tags the resulting AMI with build date + git commit; the AMI id is retrievable via the tag-filtered `data "aws_ami"` lookup.
- [ ] Only the 3 most recent AMIs are retained after a build.
- [ ] No existing `terraform/integrator-*/mongodb.tf` or `terraform/vpn/` file is modified in this phase.
- [ ] `ansible` repo's other roles are unaffected; the `4shark.mongodb8` role is fully migrated out (not duplicated across both repos).

### Phase 2: New Pritunl Mongo VM adopts the golden AMI (greenfield, single-node, 20GB)

**Objective:** validate the pipeline's output against a real, production-bound consumer, on infrastructure with zero existing data or traffic to protect.

**Components:**
- The Pritunl Mongo VM's `aws_instance` (PR 2.3 of the Pritunl migration, `terraform/vpn/`) references the golden AMI via the `data "aws_ami"` tag-filtered mechanism.
- Topology: single-node (standalone `mongod`, no replica set) — matches the current single-VM VPN model; no `rs.initiate()`, no `replSetName`, no arbiter/secondary sizing.
- Root (gp2) volume: 20GB — the Pritunl greenfield Mongo is born at this size from the start (no prior volume to shrink).

**Dependencies:** Phase 1 complete (an AMI must exist to reference); otherwise unblocked by Phase 3.

**Success criteria:**
- [ ] The Pritunl Mongo VM boots from the golden AMI at 20GB, `mongod` running standalone, reachable by the Pritunl container per `pritunl-ecs/PLAN.md`'s existing decision 3.
- [ ] No `4shark.pritunl` role duplication remains for MongoDB install/config (closes Finding 4 of the base-image SPIKE — `ansible/roles/4shark.pritunl/defaults/main.yml:6`, `pritunl_mongodb_version: "8.0"`, as a side effect).
- [ ] The pipeline has now been exercised end-to-end against one real, if low-stakes, consumer before Phase 3 touches production client data.

### Phase 3: Integrator production Mongo fleet rolling cutover — separate high-risk track

**Objective:** migrate the 15 existing production integrator Mongo VMs (5 clients × 3-node PSA) onto the golden AMI at the reduced disk size, one replica set at a time, with zero data loss and no extended quorum loss.

**Components:**
- Manual, runbook-driven replacement per replica set: secondaries first, wait for `SECONDARY` state, step down + replace the primary last, per the documented MongoDB rolling-upgrade sequence.
- Root (gp2) volume for replaced data-bearing nodes (mongo003/004): 60GB → 40GB. Arbiters (mongo005) stay at 20GB (unchanged). EBS cannot shrink in place, so 40GB applies only to the new instances created during this cutover — no existing volume is resized.
- Backup taken before each replica set's cutover begins.
- `ignore_changes = [ami, ...]` (`terraform/integrator-almaviva/mongodb.tf:62`-equivalent, all 5 stacks) explicitly revisited via the `data "aws_ami"` mechanism, one stack at a time — not a single fleet-wide flip.
- A maintenance window per client, sized to the primary step-down + full node replacement window.
- The exact per-stack/per-member sequence is decided at execution time — not over-specified here.

**Dependencies:** Phase 1 and Phase 2 both complete and validated; this phase should not start until Phase 2 has run in production for a burn-in period (duration not specified — see Open questions below).

**Success criteria:**
- [ ] Each of the 5 client replica sets is fully migrated to the golden AMI at 40GB (data nodes) with zero data loss, verified via replica set member count + `rs.status()` health per set.
- [ ] Arbiters remain at 20GB, unchanged.
- [ ] Each replica set's `mongodb.tf` lifecycle block reflects the `data "aws_ami"` tracking mechanism, consistently applied.
- [ ] No client-reported incident traceable to the cutover.

## Technical decisions

| Decision | Choice | Rationale (from engineer / from draft) |
|----------|--------|----------------------------------------|
| Packer template + build CI location | New dedicated repository `mongodb`, co-locating the Packer definition, the migrated `4shark.mongodb8` Ansible role, and the build CI (community-standard `packer/` + `ansible/` structure) | Engineer's choice. Resolves the cross-repo role-checkout concern the draft raised against a dedicated repo (Decision 1, Option B) by migrating the role in rather than referencing it across repos; `ansible` repo keeps its other roles, only mongodb migrates. Ansible is not retired — it becomes Packer's build-time provisioner |
| AMI reference mechanism in Terraform | `data "aws_ami"` filtering by a tag the pipeline stamps (not a hardcoded id, not SSM) | Engineer's choice, corresponding to the draft's Decision 2, Option A — `most_recent`/filter pattern documented by HashiCorp's own `amazon-ami` Packer data source and community Terraform guidance |
| AMI cleanup/lifecycle | Pipeline retains only the 3 most recent AMIs | Engineer's choice — bounds storage cost |
| AMI versioning + promotion | Each build produces an immutable AMI tagged with build date + git commit; promotion = the newest tagged AMI selected at `terraform apply`, pinnable to a specific version when needed; scheduled + on-demand rebuilds catch OS/MongoDB patches | Engineer's choice, combining elements of the draft's Decision 3 Options A and B. Renovate's `aws-machine-image` datasource is explicitly NOT relied on: `"This datasource is experimental. Its syntax and behavior may change at any time!"` (Renovate Docs) — a different risk posture than 4Shark's mechanically-verified datasources |
| Root (gp2) disk sizing — integrator data nodes | 60GB → 40GB, applied to NEW instances at Phase 3 cutover (EBS cannot shrink existing volumes in place) | Engineer's choice, anchored on measured CloudWatch `disk_used_percent` (path `/`, read-only, no SSH): mongo003/004 at ~5.5–11GB (9–18%) used of 60GB — ≈3.6× headroom over the ~11GB real max at 40GB |
| Root (gp2) disk sizing — integrator arbiters | Stay at 20GB, unchanged | Engineer's choice, anchored on measured usage: mongo005 arbiters at ~3–5.6GB used of 20GB — no reduction needed |
| Root (gp2) disk sizing — Pritunl Mongo | 20GB, born at this size (greenfield, no prior volume) | Engineer's choice — matches the integrator arbiter measured-usage baseline; the Pritunl VPN's own Mongo state (org/user/profile) is tiny |
| Integrator production cutover sequencing | Manual runbook-driven replacement, per replica set, secondaries-first / primary-last; its own Phase 3, HIGH RISK, separate track | Engineer's choice, corresponding to the draft's Decision 4, Option B — directly follows the documented MongoDB rolling-upgrade discipline; up-to-date backup + maintenance window required; exact per-stack/per-member sequence decided at execution time, not over-specified here |
| Pritunl Mongo VM topology | Single-node (standalone `mongod`, no replica set), greenfield, 20GB | Engineer's choice, corresponding to the draft's Decision 5, Option A — the VPN's org/user/profile state is tiny, matches the current single-VM VPN model; HA (PSA) can be revisited later |

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Touching 15 production Mongo replica sets across 5 clients (Phase 3) | High — integrator MongoDB holds live client integration state; a bad replacement sequence can take a replica set down or lose quorum | Follow the documented MongoDB rolling-upgrade discipline (secondaries first, wait for `SECONDARY`, step-down primary last); backup + staging-first validation before any production replica set is touched; treat Phase 3 as its own runbook-driven track, separate from Phase 1/2 |
| AMI-reference migration flips `ignore_changes = [ami, ...]` semantics (Phase 3) | Medium-High — the exact `lifecycle` block that currently prevents unplanned instance replacement (`terraform/integrator-almaviva/mongodb.tf:62`) must be deliberately revisited per stack; getting this wrong on 15 production instances risks an unintended `terraform apply` replacing a live Mongo node | Revisit the `ignore_changes` block explicitly per environment, one stack at a time, only as each stack's Phase 3 cutover happens — not a single fleet-wide flip |
| Drift between the new pipeline's AMI and the current static AMI during the transition window | Medium — while Phase 1 (pipeline) and Phase 2 (Pritunl greenfield) are underway, the 15 integrator VMs still run the old static AMI; any interim manual change to `4shark.mongodb8` now has to be applied twice — once to running VMs (as today), once when the next golden-AMI build picks it up | Treat the golden AMI as the sole path for `4shark.mongodb8` changes once Phase 1 ships, even before Phase 3 cuts over the integrator fleet, so there is one place changes land, not two |
| Net-new Packer/CI pipeline with no existing 4Shark muscle-memory | Medium — first-of-its-kind tooling at 4Shark; no prior incident/debugging history to draw on | Keep Phase 1 narrowly scoped (bake only what the "what is NOT bakeable" finding says is safe to bake); validate the pipeline's own build (not just its consumers) before Phase 2 begins |
| FCV bump ordering error during any future MongoDB version upgrade via this pipeline (Phase 3 and beyond) | Medium — MongoDB's official docs warn `setFeatureCompatibilityVersion` mid-initial-sync restarts the sync, and premature FCV bump narrows the downgrade window | Follow the documented sequence exactly: all members on new binary → burn-in period → FCV bump only then |
| Pritunl's own availability requirement for its MongoDB dependency has not been characterized, yet single-node (no failover) was chosen | Low-Medium — no automatic failover if the single Mongo VM fails; VPN sessions/config become unavailable until manual recovery | Accepted by the engineer's choice for Phase 2 (matches the current single-VM VPN model); HA (PSA) can be revisited later if the VPN's actual availability needs turn out to require it |
| Pritunl VPN Mongo VM (Phase 2) is the first production consumer of a brand-new pipeline | Low — mitigated structurally by being greenfield (no data to migrate, confirmed no existing `terraform/vpn/` Mongo resources) | Already the chosen sequencing rationale — Phase 2 before Phase 3, no additional mitigation needed beyond following that order |

## Assumptions

- A golden AMI shared across every client can only bake the parts identical for everyone (packages, THP handling, systemd units, base `mongod.conf` shape); the replica-set name, hostname-based member list, and `rs.initiate()` call remain a post-boot step regardless of any decision made here — a structural constraint, not an open question.
- Pritunl's MongoDB usage (capped collections, tailable cursors) rules out Amazon DocumentDB as a substitute — every option here assumes "a real `mongod` process somewhere."
- The shared `mongo-cwagent` IAM instance profile (`terraform/shared-resources/mongo-cwagent.tf:1-4,27-29`) is orthogonal to the AMI question — it attaches to the instance, not baked into the image — and needs no change for any phase of this plan.
- `terraform/vpn/` has no existing Mongo-related resources (confirmed via directory listing + `grep -rln "mongo" terraform/vpn/` returning nothing) — the Pritunl Mongo VM is genuinely greenfield, no data to migrate.
- EBS root volumes cannot shrink in place — the 40GB integrator data-node size and the 20GB Pritunl size apply only to newly created instances, never to an in-place resize of a running volume.

## Open questions

Residual items the draft flagged that the engineer's decisions above do not resolve:

- **Phase 2 burn-in period** — how long the Pritunl Mongo VM should run in production before Phase 3 (integrator fleet cutover) begins was not specified in the brief and is not assumed here.
- **Terraform Policy stance on `-replace`/stateful production resources** — whether 4Shark's Terraform Policy has an existing stance on `-replace`/automated-replacement patterns for stateful production resources that should directly inform Phase 3 execution was flagged as a citation gap in the draft's Decision 4 discussion, not independently verified in that research pass, and remains unverified here.
- **Legacy `4shark.mongodb` role (MongoDB 4.0)** — whether it and its two remaining playbook consumers (`provision-4client.yml`, `provision-4client-without-vpn.yml`) are still live for any client is unresolved by the base-image SPIKE and out of this plan's scope; this plan assumes the Phase 1 Packer template does not need to account for them (per Scope § Out of scope).

## Sources

- `terraform/integrator-almaviva/mongodb.tf:26,62` — hardcoded AMI id and the `ignore_changes` lifecycle block (identical shape confirmed across all 5 integrator stacks)
- `terraform/integrator-almaviva/providers.tf:2` — confirms `sa-east-1` as the fleet's region
- `ansible/roles/4shark.mongodb8/defaults/main.yml:5,8,14` — MongoDB version, Ubuntu codename, default empty `replSetName`
- `ansible/roles/4shark.mongodb8/tasks/main.yml:3-9,36-49,76-80` — prerequisites, THP-disable unit, mongod enable/start
- `ansible/roles/4shark.mongodb8/templates/mongod.conf.j2:17-20` — conditional `replSetName` block
- `ansible/playbooks/provision-4client-mongodb-server.yml:47-58,90-97` — role list, per-client `replSetName` var, `rs.initiate()` with client-specific hostnames
- `ansible/roles/4shark.pritunl/defaults/main.yml:6` — `pritunl_mongodb_version: "8.0"`, the drift this pipeline closes
- `terraform/shared-resources/mongo-cwagent.tf:1-4,27-29` — shared IAM instance profile, orthogonal to this plan
- `terraform/vpn/` (directory listing + `grep -rln "mongo"`) — confirms no existing Mongo resources, genuinely greenfield
- `~/.claude/plans/active/pritunl-ecs/PLAN.md:61,430` — the dedicated-VM rationale and the superseded SPIKE-2 direction
- `~/.claude/plans/active/spike/mongodb-base-image/SPIKE.md` (full) — Finding 1 (Atlas vs self-managed split), Finding 4 (Pritunl's MongoDB duplication/drift), Finding 5 (dead Packer), Finding 6 (Docker-tool-repo scope), Finding 7 (VM-not-container rationale)
- [InfraCloud — Automate building Golden AMIs with Packer, Ansible & CodeBuild](https://www.infracloud.io/blogs/automate-building-golden-ami/)
- [HashiCorp Packer — manifest post-processor](https://developer.hashicorp.com/packer/docs/post-processors/manifest)
- [HashiCorp Packer — amazon-ami data source](https://developer.hashicorp.com/packer/integrations/hashicorp/amazon/latest/components/data-source/ami)
- [Trility — Terraform Managed AMIs With Packer](https://www.trility.io/insights/terraform-managed-amis-with-packer)
- [HashiCorp Discuss — Select three most recent AMI IDs](https://discuss.hashicorp.com/t/select-three-most-recent-ami-ids/45478)
- [Renovate Docs — aws-machine-image datasource](https://docs.renovatebot.com/modules/datasource/aws-machine-image/)
- [GitHub — hashicorp/setup-packer](https://github.com/hashicorp/setup-packer)
- [HashiCorp — Automate Packer with GitHub Actions tutorial](https://developer.hashicorp.com/packer/tutorials/cloud-production/github-actions)
- [MongoDB Docs — Upgrade to the Latest Self-Managed Patch Release](https://www.mongodb.com/docs/manual/tutorial/upgrade-revision/)
- [MongoDB Docs — Upgrade a Replica Set to 8.0](https://www.mongodb.com/docs/manual/release-notes/8.0-upgrade-replica-set/)
- CloudWatch `disk_used_percent` (path `/`) across all 15 integrator Mongo VMs — measured directly by the main session (read-only, no SSH; the Mongo hosts run the CloudWatch agent) to anchor the disk-sizing decision

---

> **Authoring:** written by `@agent-plan-composer` from a validated `PLAN-SPIKE.md` plus the engineer's communicated choice. No new options, no new technical decisions, no new assumptions may be introduced at the composer stage — every claim traces to the draft or the engineer's choice. The `output-verifier` runs scope-containment, citation-integrity, contract-compliance, template-compliance, and reference-resolution checks after the write.
