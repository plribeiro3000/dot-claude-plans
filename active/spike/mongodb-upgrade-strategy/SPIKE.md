# SPIKE — MongoDB Version Upgrade Strategy and Deploy Cadence

## Investigation question

What is the ideal, community-recommended way for 4Shark to perform MongoDB version
upgrades on the data-bearing PSA replica sets going forward, and what deploy/update
cadence should govern them? Specifically:

1. For **existing, data-bearing** replica sets: in-place rolling binary upgrade vs.
   immutable golden-image re-provision (fresh node → initial sync → swap) — which
   does the community/MongoDB/immutable-infrastructure practice recommend, and does
   4Shark's existing re-provision machinery (used for the Ubuntu 18→20 OS upgrade)
   make golden-image re-provision preferable for majors too?
2. Can MongoDB major versions be skipped (5→8 in one jump), on a live set or on a
   fresh image?
3. What cadence (patch / minor / major) should govern when a new MongoDB build gets
   applied to production?
4. How should Renovate be configured for the MongoDB version in a Packer/Ansible
   golden-AMI repo, to match that cadence?

## Sources consulted

- [MongoDB Docs — Upgrade a Replica Set to 8.0](https://www.mongodb.com/docs/manual/release-notes/8.0-upgrade-replica-set/) — official rolling in-place upgrade procedure and the "all members must be on 7.0 first" prerequisite
- [MongoDB Docs — Upgrade to the Latest Self-Managed Patch Release](https://www.mongodb.com/docs/manual/tutorial/upgrade-revision/) — patch-release upgrade guidance and "always upgrade to the latest patch" rationale
- [MongoDB Docs — MongoDB Versioning](https://www.mongodb.com/docs/manual/reference/versioning/) — release model: Major (2-year cadence, 5-year support), Minor (rapid), Patch
- [MongoDB Docs — Upgrade Major MongoDB Version for a Cluster (Atlas)](https://www.mongodb.com/docs/atlas/tutorial/major-version-change/) — "one major version at a time, cannot skip"
- [MongoDB Docs — Add Members to a Self-Managed Replica Set](https://www.mongodb.com/docs/manual/tutorial/expand-replica-set/) — initial sync trigger condition when adding a member
- [MongoDB Docs — Replica Set Data Synchronization](https://www.mongodb.com/docs/manual/core/replica-set-sync/) — initial sync cost/impact/risk (primary performance, disk space, oplog window, change streams)
- [MongoDB Docs — Replace a Self-Managed Replica Set Member](https://www.mongodb.com/docs/manual/tutorial/replace-replica-set-member/) — MongoDB's own re-provisioning pattern ("re-provision systems or rename hosts")
- [AWS Well-Architected — REL08-BP04 Deploy using immutable infrastructure](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/rel_tracking_change_management_immutable_infrastructure.html) — immutable infrastructure definition, benefits (config-drift reduction, reliable rollback)
- [Scalr — The Complete Idiot's Guide to Immutable Infrastructure](https://scalr.com/learning-center/the-complete-idiots-guide-to-immutable-infrastructure) — "externalize your state" — the stateful-workload caveat on immutable infrastructure
- [Renovate Docs — Minimum Release Age](https://docs.renovatebot.com/key-concepts/minimum-release-age/) — how `minimumReleaseAge` works and that it applies across major/minor/patch
- [Renovate Docs — Ansible Galaxy manager](https://docs.renovatebot.com/modules/manager/ansible-galaxy/) and community discussion on git-scm role sources — confirms `git-tags` datasource support for `scm: git` role entries
- Local codebase: `~/Projects/4Shark/mongodb/packer/mongodb.pkr.hcl`, `~/Projects/4Shark/mongodb/renovate.json`, `~/Projects/4Shark/mongodb/ansible/requirements.yml`, `~/Projects/4Shark/mongodb/ansible/playbook.yml`, `~/Projects/4Shark/ansible-role-mongodb/defaults/main.yml`, `~/Projects/4Shark/ansible-role-mongodb/tasks/main.yml`, `~/Projects/4Shark/ansible-role-mongodb/renovate.json` — verified via `git -C <repo> show <ref>:<path>` against `origin/main` to confirm actual committed state (not a locally stale checkout)
- See auxiliary: none — every citation below resolves to a public URL (quoted inline) or a local `file:line` (quoted inline); no fetched page was large enough to warrant an auxiliary file.

## Findings

### Finding 1: MongoDB's official upgrade procedure for a live replica set is rolling in-place, node by node

**Evidence:**

> "All replica set members must be running version 7.0. To upgrade a replica set from 6.0-series and earlier, first upgrade all members of the replica set to the latest 7.0-series release, and then follow the procedure to upgrade from MongoDB 7.0 to 8.0."

> "To upgrade an existing MongoDB deployment to 8.0, you must be running a 7.0-series release. To upgrade from a version earlier than the 7.0-series, you must successively upgrade major releases until you have upgraded to 7.0-series."

**Source:** [MongoDB Docs — Upgrade a Replica Set to 8.0](https://www.mongodb.com/docs/manual/release-notes/8.0-upgrade-replica-set/)

**Significance:** MongoDB's own documented procedure for upgrading a *live, data-bearing* replica set is binary replacement on each existing node (secondaries first, primary last via `rs.stepDown()`), one major at a time. This is the procedure 4Shark's current rolling in-place process already follows. MongoDB does not document a golden-image / re-provision path as the standard major-version upgrade procedure for a replica set that already holds data — the documented path assumes the existing nodes are upgraded, not replaced.

### Finding 2: A live replica set cannot skip a major version; a fresh image is not subject to this constraint

**Evidence:**

> "You can only upgrade your Atlas cluster one major version at a time, and you can't skip any major versions when upgrading your cluster. MongoDB supports upgrading one major version at a time: 5.0 -> 6.0 -> 7.0 (correct) 5.0 -> 7.0 (not supported, skip upgrade)."

**Source:** [MongoDB Docs — Upgrade Major MongoDB Version for a Cluster (Atlas)](https://www.mongodb.com/docs/atlas/tutorial/major-version-change/)

**Evidence (self-managed, matches the Atlas rule):**

> "All replica set members must be running version 7.0 ... To upgrade from a version earlier than the 7.0-series, you must successively upgrade major releases until you have upgraded to 7.0-series."

**Source:** [MongoDB Docs — Upgrade a Replica Set to 8.0](https://www.mongodb.com/docs/manual/release-notes/8.0-upgrade-replica-set/)

**Significance:** This confirms the 4Shark team's stated understanding: a *live* replica set (with data and an established FCV) cannot jump from 5.0 straight to 8.3 — it must step through 5.0→6.0→7.0→8.0 (each release-line, patch releases within a line notwithstanding), each gated by `featureCompatibilityVersion`. This constraint attaches to the *live replica set's on-disk state*, not to the MongoDB binary itself. A **fresh image with no data** (e.g., a Packer-built AMI provisioning a brand-new, empty `mongod`) has no prior FCV to step through — the `mongodb-org` package for the target series installs directly, and the resulting empty node can join a replica set (or start a new one) at that version outright. No fetched source states the "fresh image" half explicitly (no data-bearing FCV migration is required because there is no existing FCV) — this is a direct logical consequence of Findings 1–2 and the general MongoDB architecture (FCV governs on-disk feature usage of existing data, not package installation), not itself a distinct verbatim quote.

### Finding 3: Adding a new member to an existing replica set triggers initial sync, which is costly and carries operational risk

**Evidence:**

> "Ensure that you can copy the data directory to the new member and begin replication within the window allowed by the oplog. Otherwise, the new instance will have to perform an initial sync, which completely resynchronizes the data."

**Source:** [MongoDB Docs — Add Members to a Self-Managed Replica Set](https://www.mongodb.com/docs/manual/tutorial/expand-replica-set/)

**Evidence (cost and impact):**

> "An initial sync takes longer to complete compared to subsequent syncs, and reduces the performance of the primary from which the data is read."

> "Ensure the destination member has enough space in the local database to store the oplog data for the initial sync process to complete."

> "The oplog window must be long enough so that a destination member can fetch any new oplog entries that occur between the start and end of the Logical Initial Sync Process. If the window is too short, some entries may fall off the oplog before the destination member can apply them."

> "During the initial sync, MongoDB truncates the oplog on the destination member. This oplog truncation can impact processes, such as change streams, that depend on oplog data."

**Source:** [MongoDB Docs — Replica Set Data Synchronization](https://www.mongodb.com/docs/manual/core/replica-set-sync/)

**Significance:** The golden-image re-provision method (`rs.add` a fresh node, wait for initial sync, `rs.remove` the old node) that 4Shark already uses for OS upgrades has a real, documented cost independent of MongoDB version: it degrades the source (typically a secondary, but can affect the primary) during the sync window, needs local-database disk headroom for the oplog buffer, and risks falling off the oplog window on a busy/slow sync (forcing a retry). None of this is specific to major-version upgrades — it is the fixed cost of the re-provision method itself, paid on every node, every time it is used. An in-place binary upgrade pays none of this cost (no data copy — the existing data files are reused in place).

### Finding 4: MongoDB documents node re-provisioning as a legitimate, named maintenance pattern — but scoped to hostname/hardware change, not version upgrade

**Evidence:**

> "If you need to change the hostname of a replica set member without changing the configuration of that member or the set, you can use the operation outlined in this tutorial. For example if you must re-provision systems or rename hosts, you can use this pattern to minimize the scope of that change."

**Source:** [MongoDB Docs — Replace a Self-Managed Replica Set Member](https://www.mongodb.com/docs/manual/tutorial/replace-replica-set-member/)

**Significance:** MongoDB explicitly endorses re-provisioning nodes ("if you must re-provision systems") as a sanctioned pattern — this is the doctrinal basis for 4Shark's OS-upgrade approach, and confirms it is not an ad hoc workaround. However, the tutorial's scope is a hostname/`reconfig` change on an already-running replacement node, not a worked example of a *major MongoDB version* change via re-provision. The version-upgrade-specific procedure (Finding 1) is the separate, dedicated "Upgrade a Replica Set to X.0" family of pages, which documents binary-swap-in-place — MongoDB does not present re-provisioning as an alternative path to that procedure.

### Finding 5: Immutable infrastructure doctrine explicitly treats stateful data as a special case requiring externalization

**Evidence:**

> "Immutable infrastructure is a model that mandates that no updates, security patches, or configuration changes happen in-place on production workloads. When a change is needed, the architecture is built onto new infrastructure and deployed into production."

> "Reduction in configuration drifts: By replacing infrastructure resources with a known and version-controlled configuration, the infrastructure is set to a known, tested, and trusted state, avoiding configuration drifts."

**Source:** [AWS Well-Architected — REL08-BP04 Deploy using immutable infrastructure](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/rel_tracking_change_management_immutable_infrastructure.html)

**Evidence (the stateful caveat):**

> "You can't just replace a database server without losing all your data. The rule is simple: externalize your state."

> "Your immutable application instances should not store critical data locally. That data needs to live somewhere else, somewhere persistent."

**Source:** [Scalr — The Complete Idiot's Guide to Immutable Infrastructure](https://scalr.com/learning-center/the-complete-idiots-guide-to-immutable-infrastructure)

**Significance:** The general immutable-infrastructure doctrine (replace, don't patch) is built around the assumption that the workload being replaced is stateless or that its state lives elsewhere (managed DB, external volume). 4Shark's PSA replica-set nodes are exactly the case this doctrine tells you to externalize *from* — the data directory IS the node's local state, and MongoDB has no managed-service layer at 4Shark to externalize it to. The re-provision pattern 4Shark already uses (`rs.add` + initial sync + `rs.remove`) is a *database-native* adaptation of the replace-don't-patch idea — the "externalization" is done by the replica set's own replication protocol (initial sync copies the state onto the new immutable image) rather than by moving state off the node entirely. This is a different mechanism from the stateless-tier pattern the AWS/Scalr sources describe, and it inherits the initial-sync cost from Finding 3 as the price of using it.

### Finding 6: MongoDB's release model separates Major (2-year cadence), Minor (rapid), and Patch releases, with distinct support/urgency implications

**Evidence:**

> "Major Releases are made available every two years and have a five-year lifecycle. Major Releases introduce new features and improvements and are supported for MongoDB Atlas and on-premises deployments."

> "Minor releases introduce incremental improvements and new features within a major version release cycle. They are as stable as major releases and suitable for production workloads." ... "After a new minor release becomes available, MongoDB does not continue patching the previous minor release."

> "Patch Releases are made available as needed to both Major Releases and Minor Releases. Patch releases generally include bug fixes and minor improvements."

> "To upgrade between minor releases, you must upgrade sequentially through each minor release. You cannot skip minor releases. For example, to upgrade from 8.1 to 8.3, you must first upgrade from 8.1 to 8.2, and then upgrade from 8.2 to 8.3."

**Source:** [MongoDB Docs — MongoDB Versioning](https://www.mongodb.com/docs/manual/reference/versioning/)

**Evidence (patch-release rationale):**

> "Patch releases provide security patches, bug fixes, and new or changed features that generally do not contain any backward breaking changes. Always upgrade to the latest patch release in your release series."

**Source:** [MongoDB Docs — Upgrade to the Latest Self-Managed Patch Release](https://www.mongodb.com/docs/manual/tutorial/upgrade-revision/)

**Significance:** Three distinct cadence questions follow directly from this release model: (a) patch releases within the currently-deployed series (e.g. `8.0.x`) are described as safe and backward-compatible, and MongoDB's own guidance is to always be on the latest patch of the running series; (b) minor releases (`8.1`, `8.2`, `8.3`) are new feature/stability lines that also require sequential adoption and forfeit patch support on the prior minor once superseded; (c) major releases are the ~2-year cadence carrying the heaviest process (FCV walk, full regression). The Renovate PR in question (5→8.3) conflates all three: it is simultaneously a 3-major jump (5→6→7→8) and a minor jump within 8.x (8.0→8.1→8.2→8.3) — neither of which is a single legitimate step per MongoDB's own sequencing rules, on a live set.

### Finding 7: `minimumReleaseAge` is Renovate's supply-chain gate and applies uniformly across major/minor/patch unless a `packageRules` entry narrows it

**Evidence:**

> "minimumReleaseAge is a feature that requires Renovate to wait for a specified amount of time before suggesting a dependency update." ... "The use of minimumReleaseAge is not to slow down fast releasing project updates, but to provide a means to reduce risk supply chain security risks."

> "Renovate will wait for the set duration to pass for each separate version. Renovate does not wait until the package has seen no releases for x time-duration."

**Source:** [Renovate Docs — Minimum Release Age](https://docs.renovatebot.com/key-concepts/minimum-release-age/)

**Significance:** 4Shark's existing `minimumReleaseAge: 7 days` (confirmed at `~/Projects/4Shark/mongodb/renovate.json:8` and `~/Projects/4Shark/ansible-role-mongodb/renovate.json:8`) already provides the supply-chain quarantine window for any MongoDB version Renovate proposes — this part of governance is already in place and requires no change. What `minimumReleaseAge` does NOT do is distinguish "safe to auto-merge" from "needs manual major-version review" — that is a `packageRules`/`matchUpdateTypes` concern (Finding 8), separate from release age.

### Finding 8: Renovate supports gating major updates to manual approval independently from minor/patch cadence

**Evidence:**

> "Setting `\"enabled\": false` in a package rule will deactivate Renovate updates for all dependencies that match the rule's criteria." Example: `{ "packageRules": [{ "matchUpdateTypes": ["major"], "enabled": false }] }`

> "Alternatively, instead of completely disabling updates, you can use the 'Dependency Dashboard approval' workflow to get updates for certain packages — or certain types of updates — only after you give approval via the Dependency Dashboard." Example: `{ "packageRules": [{ "matchUpdateTypes": ["major"], "matchManagers": ["npm"], "dependencyDashboardApproval": true }] }`

**Source:** search-aggregated from [Renovate Docs — configuration-options](https://docs.renovatebot.com/configuration-options/) and the Mend.io Renovate Package Rules Guide (community summary; the underlying `matchUpdateTypes`/`dependencyDashboardApproval` option names and semantics are confirmed independently on `docs.renovatebot.com/configuration-options/`, which lists `matchUpdateTypes` and `dependencyDashboardApproval` as real, documented options)

**Significance:** Renovate has two independent mechanisms for taking MAJOR MongoDB bumps out of the automatic flow while leaving minor/patch bumps on the normal cadence: `enabled: false` (Renovate never proposes a major PR at all — the engineer would have to bump it by hand or temporarily flip the rule) or `dependencyDashboardApproval: true` (Renovate raises the major update as a checkbox on the Dependency Dashboard issue, and only opens the PR once an engineer ticks it). Both compose with `matchUpdateTypes: ["major"]` in `packageRules`, leaving `minimumReleaseAge` and the existing minor/patch flow untouched for everything else.

### Finding 9: The `mongodb` repo's Renovate-tracked variable does not actually control the installed MongoDB version — the Ansible role's own default does, pinned separately

**Evidence (Packer variable, tracked by Renovate):**

```hcl
# The MongoDB series baked in, kept in sync with the 4shark.mongodb role default.
# renovate: datasource=docker depName=mongo versioning=docker
variable "mongodb_version" {
  type    = string
  default = "5.0"
}
```

**Source:** `~/Projects/4Shark/mongodb/packer/mongodb.pkr.hcl:40-45`

**Evidence (the variable's only actual uses — naming/tagging, never passed to Ansible):**

```hcl
locals {
  version = "${var.mongodb_version}-${formatdate("YYYYMMDDhhmmss", timestamp())}"
}
...
  ami_description = "4Shark MongoDB ${var.mongodb_version} golden image"
...
    MongoDBVersion = var.mongodb_version
```

**Source:** `~/Projects/4Shark/mongodb/packer/mongodb.pkr.hcl:56,95,109`

**Evidence (the Ansible provisioner block passes no `extra_arguments` / `-e mongodb_version=...`):**

```hcl
  provisioner "ansible" {
    playbook_file = "${path.root}/../ansible/playbook.yml"
    galaxy_file   = "${path.root}/../ansible/requirements.yml"
    user          = "ubuntu"
    use_proxy = false
    ansible_env_vars = [
      "ANSIBLE_PIPELINING=True",
      "ANSIBLE_HOST_KEY_CHECKING=False",
    ]
  }
```

**Source:** `~/Projects/4Shark/mongodb/packer/mongodb.pkr.hcl:120-134`

**Evidence (the role's own default, which is what actually determines the installed package, confirmed at the `v0.1.0` tag pinned by `mongodb`'s `requirements.yml:12`):**

```yaml
mongodb_version: "5.0"
mongodb_gpg_key_url: "https://www.mongodb.org/static/pgp/server-5.0.asc"
mongodb_gpg_keyring: "/usr/share/keyrings/mongodb-server-5.0.gpg"
mongodb_ubuntu_codename: "focal"
```

**Source:** `~/Projects/4Shark/ansible-role-mongodb` at tag `v0.1.0` (`defaults/main.yml`), verified via `git -C ~/Projects/4Shark/ansible-role-mongodb show v0.1.0:defaults/main.yml`

**Evidence (the role task that consumes the default, with no other override path in the role):**

```yaml
- name: Add MongoDB Repository
  apt_repository:
    repo: "deb [ arch=amd64,arm64 signed-by={{ mongodb_gpg_keyring }} ] https://repo.mongodb.org/apt/ubuntu {{ mongodb_ubuntu_codename }}/mongodb-org/{{ mongodb_version }} multiverse"
    state: "present"
    update_cache: true
```

**Source:** `~/Projects/4Shark/ansible-role-mongodb/tasks/main.yml:23-27`

**Significance:** Today, bumping `mongodb/packer/mongodb.pkr.hcl`'s `mongodb_version` (what Renovate's `customManagers` entry at `~/Projects/4Shark/mongodb/renovate.json:10-19` tracks) changes only the AMI's name/description/tag — it does **not** change what MongoDB package gets installed. The actual installed version is `ansible-role-mongodb`'s `defaults/main.yml:5-8` `mongodb_version`, which travels with whatever git tag `~/Projects/4Shark/mongodb/ansible/requirements.yml:12` pins (`version: v0.1.0`), and `ansible-role-mongodb`'s own `renovate.json` has no `customManagers` entry watching that default value at all. Merging the open Renovate PR (5→8.3 on the packer variable) as-is would silently create a **mismatch**: the AMI's `MongoDBVersion` tag and `ami_description` would read "8.3" while the node actually still installs MongoDB 5.0 from the pinned `v0.1.0` role — a false signal for anyone reading the AMI tags to determine what version is running. Fixing this is a prerequisite for any cadence decision to be meaningful in practice, independent of which upgrade method or cadence 4Shark chooses.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| **In-place rolling binary upgrade** (current 4Shark practice for MongoDB majors) | Matches MongoDB's own documented procedure exactly (Finding 1); no data-copy cost — reuses existing data files; well-understood, already run 3 times in a row by the team | Requires SSH + apt access per node per hop; each major hop is a separate maintenance action (cannot batch 5→8 into one pass, Finding 2); risk is per-hop but repeated 3x for a 5→8 walk; any config drift from manual SSH steps is not caught until the next audit | Findings 1, 2 |
| **Golden-image re-provision** (current 4Shark practice for the OS upgrade; already-built machinery: `rs.add` fresh AMI node → initial sync → `rs.remove` old node) | Node state always matches a known, versioned, tested image (config-drift elimination, Finding 5); rollback is "don't cut over" rather than "downgrade a live binary"; reuses machinery 4Shark already proved out for Ubuntu 18→20 | Pays the initial-sync cost every time (primary/secondary read load, disk headroom for oplog buffer, oplog-window risk, change-stream impact — Finding 3); MongoDB's own version-upgrade documentation does not present this as the major-version-upgrade path (Finding 1) — it is documented for hostname/hardware re-provisioning (Finding 4), not as a substitute for the FCV-gated binary upgrade; still cannot skip majors even with a fresh image if the image itself must land on an intermediate FCV to match a mixed-version set during the swap window (a live set element remains until `rs.remove` completes) | Findings 1, 3, 4, 5 |
| **Fresh image built directly at a target major (no live-set major-skip)** | A brand-new, empty node built by Packer at the target series has no prior FCV to walk through — package install is direct, no sequential-major constraint applies to the empty node itself (Finding 2, reasoned) | Only usable for a *new* replica set or a full re-provision where the joining node's FCV compatibility with the *rest of the still-live set* is the actual constraint — a fresh 8.3 node still cannot join a replica set whose other members / FCV sit at 5.0 without the whole set completing its own 5→6→7→8 walk first | Finding 2 |

## What remains uncertain

- No fetched MongoDB source explicitly states the FCV-compatibility rule for a *freshly re-provisioned, empty* node joining a replica set whose other members are on an older major (i.e., can a node running 8.0 binaries do initial sync against a primary running 5.0?). Finding 2's fresh-image conclusion is reasoned from the general architecture (FCV governs on-disk feature usage, not package installation) and from Finding 1's "all members must be running version 7.0" prerequisite before an 8.0 upgrade proceeds — which implies wire-protocol/FCV compatibility between members is checked at the replica-set level regardless of how a member arrived at its binary version. This was not verified against a page documenting cross-major wire-protocol compatibility directly, and should be confirmed against MongoDB's replica set protocol/wire version compatibility documentation before betting a live-set operation on it.
- Whether Renovate's `ansible-galaxy` manager's `git-tags` datasource support (Finding 8's adjacent capability, referenced in Sources) actually fires against `~/Projects/4Shark/mongodb/ansible/requirements.yml`'s `scm: git` + `version: v0.1.0` shape without additional `packageRules`/`managerFilePatterns` configuration was not verified end-to-end against a real Renovate dependency-dashboard run — the cited community discussion documents general git-scm support and a known git+ssh limitation, not this exact file shape.
- No source was found stating a specific number of days/weeks 4Shark should target between a MongoDB minor release's GA and its production deploy beyond the existing blanket `minimumReleaseAge: 7 days` — MongoDB's own docs describe the release model but do not prescribe an adoption cadence for self-managed deployments.

## Suggested options for main and the engineer

**(a) Upgrade method for existing, data-bearing sets:**

- Option A1 — Keep in-place rolling binary upgrade for MongoDB majors, reserve golden-image re-provision for OS-level changes only (current split). Matches MongoDB's documented procedure exactly (Finding 1); avoids paying the initial-sync cost (Finding 3) on every version bump.
- Option A2 — Standardize on golden-image re-provision for majors too, reusing the OS-upgrade machinery. Trades the initial-sync cost (Finding 3) for config-drift elimination and a uniform "one way to change a node" operational model (Finding 5); would need the open uncertainty above (cross-major FCV compatibility for the newly-added node) resolved first.
- Option A3 — Hybrid: golden-image re-provision to land on the *last patch of the currently-running major* (matches the existing OS-upgrade flow, no FCV walk involved since the major doesn't change), then in-place binary hops for each major-version step (5→6→7→8) using MongoDB's documented procedure, then re-provision again once settled on the target major to pick up the corresponding OS baseline.

**(b) Handling the golden-AMI version bump:**

- Option B1 — Build fresh at the target major only for a *new* replica set (new client, new stack) or after a live set has already completed its in-place major walk and just needs its OS/AMI refreshed at the now-current major.
- Option B2 — Keep the golden AMI's baked-in MongoDB version equal to whatever major the *live production sets* are currently running (i.e., the AMI is a "day-2 patch/OS refresh" artifact, not a vehicle for major jumps) — this makes AMI version bumps track production reality rather than lead it.

**(c) Deploy cadence:**

- Option C1 — Patch releases within the currently-running series: apply promptly (matches MongoDB's "always upgrade to the latest patch release in your release series" guidance, Finding 6) once past the existing 7-day `minimumReleaseAge` quarantine.
- Option C2 — Minor releases (e.g. 8.1→8.2→8.3): batch/schedule rather than auto-apply each one — MongoDB's "you cannot skip minor releases" sequencing (Finding 6) means each minor is its own hop, so a cadence decision is needed on how many minors 4Shark lets accumulate before scheduling an upgrade window versus stepping through each as it lands.
- Option C3 — Major releases: always manual/scheduled, gated by an explicit maintenance action per major hop, given the FCV walk and the current per-node SSH procedure (Finding 1, Finding 2).

**(d) Renovate configuration:**

- Option D1 — Add a `packageRules` entry matching `matchUpdateTypes: ["major"]` on the MongoDB custom manager with `enabled: false`, so Renovate never proposes a major bump automatically; the engineer bumps it by hand when a major upgrade is deliberately scheduled (Finding 7/8).
- Option D2 — Same major gate, but via `dependencyDashboardApproval: true` instead of `enabled: false`, so a major bump still surfaces as a visible, checkable item on the Dependency Dashboard rather than disappearing entirely (Finding 8).
- Option D3 — Independent of A–C: fix Finding 9 first — either wire the packer `mongodb_version` variable into the Ansible provisioner as an extra-var so it actually controls the install, or remove the customManager/Renovate tracking from the packer variable and instead track the version where it is actually consumed (`ansible-role-mongodb`'s `defaults/main.yml`, and/or the `version: v0.1.0` role pin in `mongodb`'s `requirements.yml` via Renovate's `ansible-galaxy` git-tags support). Whichever cadence policy (C1–C3) and gating (D1/D2) is chosen, it needs to operate on the value that actually determines the installed MongoDB version, not the cosmetic AMI tag.
