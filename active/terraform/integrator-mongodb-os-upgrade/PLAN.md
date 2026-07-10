# Plan: Upgrade MongoDB 4.4 → 8.0 and Ubuntu 18.04 → 24.04 on Integrator Environments

**Status:** Approved — decision of record (2026-07-08)
**Date:** 2026-02-23 (drafted); 2026-07-08 (approved)
**Project:** terraform + ansible (integrator environments)
**Scope:** 5 environments × 3 nodes = 15 EC2 instances

---

## Context

The 5 integrator environments run MongoDB 4.4 on Ubuntu 18.04 (Bionic). Both are well past End of Life:
- **MongoDB 4.4:** EOL since February 2024
- **Ubuntu 18.04:** EOL since June 2023

There are no automated backups, no upgrade procedures, and no documented process for maintaining these servers. This plan defines the exact upgrade sequence, respecting compatibility constraints between MongoDB versions and Ubuntu LTS releases.

**Why this plan, and not a re-platform:** the alternative of moving MongoDB off dedicated EC2 was evaluated in two spikes and rejected on the evidence. `~/.claude/plans/completed/spike/mongodb-on-ecs/SPIKE.md` ruled out ECS (no StatefulSet-equivalent primitive for a replica set). `~/.claude/plans/completed/spike/mongodb-eks-vs-ec2-cost-maintenance/SPIKE.md` ruled out EKS on quantified cost + maintenance grounds (every EKS scenario priced costs more in sa-east-1 — the cheapest is +16.6%/month — and EKS trades manual OS toil for a new Kubernetes-version-lifecycle + operator-tracking burden rather than reducing maintenance). This manual OS upgrade — by re-provisioning the nodes on the EC2 platform already in use — is the chosen path: it resolves the unmaintained-OS pain directly, at the lowest cost.

---

## Progress Log

**Rollout strategy (adopted 2026-07-08):** phased across the fleet, one hop at a time — take **all productive environments to MongoDB 5.0 first** (Step 1), validate each, and only then plan the subsequent hops (OS upgrade → 6.0 → …). Environments are done **one at a time**, prioritizing whichever is **closest to its next integration window** so there is room to migrate several in a day without colliding with a running integration.

### RESUME POINT — 2026-07-08 (Step 1 COMPLETE for the fleet; continue Friday)

**Done today:** all 4 productive integrators — **commcenter, almaviva, maqnelson, atento** — are on **MongoDB 5.0.34, FCV 5.0**, all validated app-side. **redebrasil excluded** (contract cancelled, infra to be torn down). Every node is still on **Ubuntu 18.04 (bionic)** — the OS was NOT touched yet.

**Access mechanism was torn down** at end of day (SSM key params `/integrator-<client>/mongo-ssh-key` deleted, runner task-def revisions with the `MONGO_SSH_KEY` secret deregistered). It must be **re-created per environment on Friday** using the recipe in § Operational learnings below (SSM SecureString + runner task-def revision + subnet-pinned jump task). atento's runner path is `/integrator-atento-br/*` and its shared mongo (`atento-br` replica set) is reached via the `integrator-atento-br` cluster.

**Node power state at end of day:** **almaviva & maqnelson mongo instances stopped** — they have ENABLED `start-mongodb` schedulers that bring them up before their windows. **commcenter & atento mongo left RUNNING** — both have their `start-mongodb` scheduler DISABLED/absent (no auto-start), so their mongo is **always-on by design** and must NOT be stopped without arranging a start before each integration window. (commcenter's mongo was mistakenly stopped mid-day and restarted before end of day once this was caught. atento's shared `atento-br` replica set serves 4 country integrations at different UTC times: br 02:00, co 09:30, mx 10:30, cl 14:00.)

**Friday's step — Step 2: Ubuntu 18.04 → 20.04 by RE-PROVISIONING (engineer decided 2026-07-08).**

- **Method: re-provision.** Replace each replica-set member with a fresh Ubuntu 20.04 instance (already on MongoDB 5.0) one member at a time so the set keeps quorum → 0-downtime: bring up the new 20.04 node, `rs.add()` it, wait for initial sync to `SECONDARY`, then remove/retire the old 18.04 member (`rs.remove()`); for the primary, `rs.stepDown()` first. Needs Terraform/AMI work — the mongo module pins the AMI with `lifecycle { ignore_changes = [ami] }`, so the AMI bump + instance replacement is driven deliberately (new instance alongside → join the set → retire the old).
- **Order: OS-first (engineer decided).** Do the OS upgrade to 20.04 across the fleet before any further Mongo hop; then Mongo 5.0→6.0→7.0→8.0 all run on 20.04+ (final OS hop: Ubuntu 20.04 → 24.04 direct, skipping 22.04 — see the 2026-07-10 refinement below).
- Re-create the access mechanism per environment first (SSM key + runner task-def revision — recipe in § Operational learnings), unless the re-provision approach is driven entirely via Terraform + the app's own connection (in which case SSH may not even be needed — evaluate Friday).

### Refinement — skip Ubuntu 22.04 (engineer decided 2026-07-10)

The final OS hop goes **20.04 → 24.04 directly, skipping 22.04** — the upgrade sequence drops from 7 steps to 6. This is safe and cheaper because the adopted OS-upgrade method is **re-provisioning** (Step 2 decision, 2026-07-08): a fresh Ubuntu 24.04 node is stood up and joined to the replica set, so there is no need to step through 22.04 as an intermediate LTS. MongoDB 8.0 supports 24.04, and the `libssl1.1` blocker only ever affected MongoDB ≤5.0. The Upgrade Sequence and Step Details below reflect this.

### commcenter — Step 1 (MongoDB 4.4 → 5.0) — DONE (2026-07-08)

- All 3 nodes upgraded **4.4.30 → 5.0.34**, rolling (secondary → arbiter → primary via `rs.stepDown()`), no read downtime; only the primary election blip (~10-20s) with the integrator idle.
- **FCV set to 5.0**; default write concern set to `{w:1}` before the upgrade (PSA safety).
- **Validated app-side**: web task booted healthy against 5.0, `buildInfo` version `5.0.34`, replica set `PRIMARY/SECONDARY/ARBITER` all seen, FCV `5.0`; `User.count` and `Job.last` consistent.
- Pre-upgrade backup: 15 EBS snapshots tagged `Purpose=pre-mongodb-upgrade` (all 5 environments, taken 2026-07-08).
- After validation: web scaled to 0 and the 3 mongo instances stopped.

### almaviva — MongoDB 4.0 → 5.0 (THREE hops) — DONE (2026-07-08)

- **Started on MongoDB 4.0.28, FCV 4.0 — NOT 4.4.** The fleet is NOT uniform; do not assume a starting version. Reached 5.0 via three rolling hops (majors can't be skipped): **4.0.28 → 4.2.25 → 4.4.31 → 5.0.34**, each with its own `setFeatureCompatibilityVersion` (4.2 → 4.4 → 5.0). `setDefaultRWConcern {w:1}` done on 4.4 right before the 5.0 hop.
- All 3 nodes on **5.0.34, FCV 5.0**, verified healthy (mongo004 PRIMARY, mongo003/mongo005 SECONDARY/ARBITER).
- almaviva IS on active daily-shutdown (reference client). Its integration runs 01:00 UTC — left mongo running so that run happens on 5.0; the ShutDownWorker stops it afterward.
- **Validated app-side** (2026-07-08): `buildInfo` version `5.0.34`, FCV `5.0`, `User.count` consistent, `Job.last` shows a complete prior integration.
- **Stop/start reconstitution tested** (2026-07-08): stopped all 3 nodes, started them — replica set reconstituted automatically on 5.0 (mongo004 elected PRIMARY, all healthy). Confirms the daily-shutdown cycle works on 5.0.

### maqnelson — MongoDB 4.0 → 5.0 (THREE hops) — DONE (2026-07-08)

- Same starting point as almaviva: **4.0.28, FCV 4.0**. Three rolling hops **4.0.28 → 4.2.25 → 4.4.31 → 5.0.34**, FCV stepped 4.2 → 4.4 → 5.0, `setDefaultRWConcern {w:1}` before the 5.0 hop. The 4.2→4.4 `apt-get -f install` self-heal ran on all 3 nodes (`BROKEN=0` each).
- All 3 nodes **5.0.34, FCV 5.0**, verified healthy. **Validated app-side** (2026-07-08): `buildInfo` `5.0.34`, FCV `5.0`, `User.count` consistent, `Job.last` shows a complete integration (38820/38920 requests).

### atento — MongoDB 4.4 → 5.0 (single hop) — DONE (2026-07-08)

- Started on **4.4.29, FCV 4.4** (like commcenter — single hop). One rolling hop **4.4.29 → 5.0.34**, `setDefaultRWConcern {w:1}` before, FCV set to 5.0. `BROKEN=0` on all nodes.
- ONE shared replica set (`atento-br`) backs all FOUR country integrations (atento-br/cl/co/mx — separate databases on the same replica set), so this single migration covers all four. Used the `integrator-atento-br` runner/cluster as the jump; key staged at `/integrator-atento-br/mongo-ssh-key` (covered by the `/integrator-atento-*` ssm-read wildcard).
- All 3 nodes **5.0.34, FCV 5.0**, verified healthy (mongo003 PRIMARY, mongo004/mongo005 SECONDARY/ARBITER). **Validated app-side via atento-mx** (a different country integration than the atento-br jump) — `buildInfo` `5.0.34`, FCV `5.0`, `User.count` consistent, `Job.last` complete. Confirms the single shared-mongo migration serves all four country integrations.

### redebrasil — EXCLUDED (do NOT migrate)

- Client cancelled its contract; the integrator infrastructure will be torn down shortly, so redebrasil is NOT migrated. Its integration schedule is already DISABLED. Fleet scope for this migration is therefore **4 environments** (commcenter, almaviva, maqnelson, atento), not 5.

### Operational learnings (apply to every remaining environment)

- **Verify each environment's ACTUAL MongoDB version and FCV first** — the fleet is heterogeneous (commcenter was 4.4, almaviva was 4.0). The number of hops to 5.0 differs per environment.
- **The 4.2 → 4.4 hop leaves packages half-configured**: `mongodb-org-database-tools-extra` postinst fails on the first pass (`apt-get install` exits 100, packages in `iU` state). Always run `sudo apt-get -f install -y -o Dpkg::Options::=--force-confold` right after the install to complete configuration, and assert `dpkg -l | grep mongodb | grep -c '^iU'` is 0. (The 4.0→4.2 and 4.4→5.0 hops did not hit this, but the `-f install` step is harmless and worth keeping on every hop.)

- **No SSM on the mongo boxes** (profile `mongo-cwagent`) and the mongo SG allows traffic only from internal SGs (no public 22). The working access path is an **ephemeral ECS task on the integrator's own cluster** (same VPC/SG as the app, reaches mongo), SSH-ing to each node. The `kp-4shark` private key is delivered to the task as an **ECS SSM SecureString secret** (never on the command line). Per environment this needs: the key in `/integrator-<client>/mongo-ssh-key` (SecureString, encrypted with the client's own SSM KMS key so the existing `integrator-<client>-ssm-read` role can decrypt) + a runner task-def revision adding a `MONGO_SSH_KEY` secret.
- **SSH to the mongo nodes is slow to connect** (>15s) — use `ConnectTimeout` ≥ 20 and **pin the jump task to the target node's own subnet/AZ** (cross-AZ SSH timed out repeatedly). Node subnets differ within a replica set.
- **`apt-get install mongodb-org` keeps the server package back** on a major-version jump (the metapackage upgrades but `mongodb-org-server`/`-shell`/`-mongos`/`-tools` stay at the old version). Name the component packages explicitly: `apt-get install -y -o Dpkg::Options::=--force-confold mongodb-org mongodb-org-server mongodb-org-shell mongodb-org-mongos mongodb-org-tools`. Keep `mongod.conf` via `--force-confold`.
- **Per-environment schedulers**: check each client's EventBridge schedules (`integrator-<client>-scale-up-web/worker`, `ECS-integrator-<client>-cron-integration-cron-schedule`) so no integration runs mid-upgrade. commcenter was effectively NOT on active daily-shutdown (`AWS_INSTANCE_IDS` empty, start-mongodb scheduler disabled) — verify this per client, it may differ.

### Pending cleanup (end of whole migration)

- Remove the SSH-key SSM parameters (`/integrator-<client>/mongo-ssh-key`) and the runner task-def revisions that reference `MONGO_SSH_KEY`, per environment — a private key in Parameter Store is a hygiene debt kept only for the migration window.

---

## Compatibility Matrix (Official MongoDB Documentation)

| MongoDB | Ubuntu 18.04 (Bionic) | Ubuntu 20.04 (Focal) | Ubuntu 22.04 (Jammy) | Ubuntu 24.04 (Noble) |
|---------|:---------------------:|:--------------------:|:--------------------:|:--------------------:|
| **4.4** | YES | YES | NO | NO |
| **5.0** | YES | YES | NO | NO |
| **6.0** | YES | YES | YES (from 6.0.4) | NO |
| **7.0** | NO | YES | YES | NO |
| **8.0** | NO | YES | YES | YES |

### Key Library Dependencies

| Ubuntu | glibc | OpenSSL | libssl package |
|--------|-------|---------|----------------|
| 18.04 (Bionic) | 2.27 | 1.1.1 | libssl1.1 |
| 20.04 (Focal) | 2.31 | 1.1.1 | libssl1.1 |
| 22.04 (Jammy) | 2.35 | 3.0.2 | libssl3 |
| 24.04 (Noble) | 2.39 | 3.0.13 | libssl3 |

**Critical constraint:** MongoDB 5.0 and earlier require `libssl1.1`, which was removed in Ubuntu 22.04. This means MongoDB must be at least 6.0.4 before upgrading to Ubuntu 22.04.

---

## Upgrade Sequence (6 Steps)

Ubuntu 20.04 supports MongoDB 5.0 through 8.0, so all MongoDB hops can be completed on a single Ubuntu version after the first OS upgrade. This minimizes the number of OS upgrades interleaved with MongoDB upgrades. The final OS hop goes **20.04 → 24.04 directly, skipping 22.04** (refinement 2026-07-10): re-provisioning stands up a fresh 24.04 node directly, and MongoDB 8.0 supports 24.04, so 22.04 as an intermediate LTS is unnecessary.

```
START:  MongoDB 4.4 + Ubuntu 18.04 (Bionic)

Step 1: MongoDB 4.4 → 5.0    (on Ubuntu 18.04)  ← last MongoDB version on Bionic
Step 2: Ubuntu 18.04 → 20.04  (with MongoDB 5.0) ← OS upgrade required before MongoDB 7.0
Step 3: MongoDB 5.0 → 6.0    (on Ubuntu 20.04)
Step 4: MongoDB 6.0 → 7.0    (on Ubuntu 20.04)
Step 5: MongoDB 7.0 → 8.0    (on Ubuntu 20.04)  ← all MongoDB hops done
Step 6: Ubuntu 20.04 → 24.04  (with MongoDB 8.0, re-provision) ← skips 22.04

END:    MongoDB 8.0 + Ubuntu 24.04 (Noble)
```

### Why This Order

1. **Step 1 on Bionic:** MongoDB 5.0 is the last version that supports Ubuntu 18.04. Must upgrade MongoDB first because 4.4 packages may not install cleanly on newer Ubuntu.
2. **Step 2 before more MongoDB hops:** Ubuntu 20.04 supports MongoDB 5.0 through 8.0, creating a stable platform for all remaining MongoDB upgrades.
3. **Steps 3-5 on Focal:** All three remaining MongoDB hops can execute on Ubuntu 20.04 without any OS change in between. This is the fastest section.
4. **Step 6 (final OS hop) after MongoDB is done:** with MongoDB already at 8.0, the last Ubuntu hop is a single re-provision **20.04 → 24.04, skipping 22.04** — MongoDB 8.0 supports 24.04, and the re-provision method (fresh instance) has no requirement to step through each intermediate LTS.

---

## Step Details

### Step 1: MongoDB 4.4 → 5.0 (on Ubuntu 18.04)

**Compatibility:** MongoDB 5.0 supports Ubuntu 18.04 ✓

**PSA Gotcha (CRITICAL):** Starting with MongoDB 5.0, the default write concern changes to `w: "majority"`. In a PSA topology (Primary-Secondary-Arbiter), if the secondary goes down, writes with `w: "majority"` block indefinitely because the arbiter does not hold data and cannot acknowledge writes.

**Pre-upgrade action (BEFORE upgrading any node):**
1. Connect to the primary
2. Run `rs.reconfigForPSASet()` or manually set the default write concern:
   ```javascript
   db.adminCommand({
     setDefaultRWConcern: 1,
     defaultWriteConcern: { w: 1 }
   })
   ```
3. Verify: `db.adminCommand({ getDefaultRWConcern: 1 })`

**Rolling upgrade procedure:**
1. Upgrade secondary (stop mongod, switch to 5.0 repo, install, start, wait for SECONDARY state)
2. Upgrade arbiter (stop, switch repo, install, start)
3. Step down primary (`rs.stepDown()`), wait for election (~10-20s), upgrade old primary
4. Verify all nodes: `rs.status()`
5. Set FCV: `db.adminCommand({ setFeatureCompatibilityVersion: "5.0" })`
6. Verify FCV: `db.adminCommand({ getParameter: 1, featureCompatibilityVersion: 1 })`

**Write downtime:** ~10-20 seconds (during primary election)

---

### Step 2: Ubuntu 18.04 → 20.04 (with MongoDB 5.0)

**Compatibility:** MongoDB 5.0 supports Ubuntu 20.04 ✓

**Re-provision procedure (per member, same order: secondary → arbiter → primary), keeping quorum for 0-downtime:**

For each member:
1. Provision a fresh Ubuntu 20.04 instance running MongoDB 5.0, apt repo pinned to the `focal` codename:
   ```bash
   echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-5.0.gpg ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/5.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-5.0.list
   ```
2. `rs.add()` the new node; wait for initial sync to `SECONDARY` (`rs.status()`).
3. `rs.remove()` the old 18.04 member it replaces, then retire that instance.
4. For the primary member: `rs.stepDown()` first, wait for the election, then replace it after the secondary and arbiter are already on 20.04.

**Estimated time per member:** 30-45 minutes (mostly initial sync + verify)

---

### Step 3: MongoDB 5.0 → 6.0 (on Ubuntu 20.04)

**Compatibility:** MongoDB 6.0 supports Ubuntu 20.04 ✓

**Breaking changes:**
- Removal of Legacy Opcodes (OP_INSERT, OP_UPDATE, OP_DELETE). Drivers older than MongoDB 3.6 will stop working. The Integrator uses Mongoid with a modern Ruby driver — not affected.

**Rolling upgrade procedure:**
1. Upgrade secondary (stop, switch to 6.0 repo for focal, install, start, wait SECONDARY)
2. Upgrade arbiter
3. Step down primary, upgrade
4. Set FCV: `db.adminCommand({ setFeatureCompatibilityVersion: "6.0" })`

**Write downtime:** ~10-20 seconds

---

### Step 4: MongoDB 6.0 → 7.0 (on Ubuntu 20.04)

**Compatibility:** MongoDB 7.0 supports Ubuntu 20.04 ✓

**Breaking changes:**
- `confirm: true` parameter becomes mandatory in `setFeatureCompatibilityVersion`
- Free Monitoring discontinued (not relevant for self-managed)

**Rolling upgrade procedure:**
1. Upgrade secondary
2. Upgrade arbiter
3. Step down primary, upgrade
4. Set FCV: `db.adminCommand({ setFeatureCompatibilityVersion: "7.0", confirm: true })`

**Write downtime:** ~10-20 seconds

---

### Step 5: MongoDB 7.0 → 8.0 (on Ubuntu 20.04)

**Compatibility:** MongoDB 8.0 supports Ubuntu 20.04 ✓

**Benefits:**
- Up to 36% higher read throughput
- Up to 32% better web application performance
- Up to 20% more concurrent writes during replication
- LTS release with support until October 2029

**Rolling upgrade procedure:**
1. Upgrade secondary
2. Upgrade arbiter
3. Step down primary, upgrade
4. Set FCV: `db.adminCommand({ setFeatureCompatibilityVersion: "8.0", confirm: true })`

**Write downtime:** ~10-20 seconds

---

### Step 6: Ubuntu 20.04 → 24.04 (with MongoDB 8.0, re-provision — skips 22.04)

**Compatibility:** MongoDB 8.0 supports Ubuntu 24.04 ✓. **22.04 is skipped entirely** (refinement 2026-07-10): the adopted OS-upgrade method is **re-provisioning** (Step 2 decision, 2026-07-08) — a fresh Ubuntu 24.04 node is stood up and joined to the replica set, so there is no requirement to step through 22.04 as an intermediate LTS.

**Library note:** Ubuntu 24.04 ships OpenSSL 3.0 (`libssl3`); MongoDB 8.0 supports it — no issue. The `libssl1.1` constraint only ever blocked MongoDB ≤5.0, long past by this step.

**Procedure — re-provision one replica-set member at a time (same shape as Step 2), keeping quorum for 0-downtime:**
1. Provision a fresh Ubuntu 24.04 instance running MongoDB 8.0, apt repo pinned to the `noble` codename:
   ```bash
   echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu noble/mongodb-org/8.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list
   ```
2. `rs.add()` the new node; wait for initial sync to `SECONDARY`.
3. `rs.remove()` the old 20.04 member it replaces (for the primary, `rs.stepDown()` first).
4. Repeat per member (SECONDARY → ARBITER → PRIMARY order); verify the replica set is healthy on 24.04.

---

## Node Order for Every Step

Every step (MongoDB or Ubuntu upgrade) follows the same rolling order:

```
1. SECONDARY  → upgrade → verify SECONDARY state in rs.status()
2. ARBITER    → upgrade → verify ARBITER state in rs.status()
3. PRIMARY    → rs.stepDown() → wait election → upgrade → verify
```

This ensures the replica set is always available. Write downtime occurs only during the primary step-down election (~10-20 seconds per step).

---

## Pre-Requisites (Before Starting Step 1)

### 1. Implement Backups

There are currently NO backups. Before touching anything:

- Configure `mongodump` on the secondary node, scheduled via cron, uploading to S3
- Configure EBS snapshots via AWS Data Lifecycle Manager as additional safety
- Verify backup integrity by restoring to a test instance

### 2. Verify Replica Set Health

On each environment, connect to the primary and run:

```javascript
rs.status()           // All members healthy
rs.conf()             // Verify PSA topology
db.adminCommand({ getParameter: 1, featureCompatibilityVersion: 1 })  // Should be "4.4"
```

### 3. Verify Data Directory Location

Confirm `/data/db` is on a separate EBS volume (not the root volume). If data is on the root volume, an OS upgrade failure could lose data.

### 4. Verify Mongoid Driver Compatibility

The Integrator uses Mongoid (latest) with Ruby 3.4.1. Modern Mongoid versions support MongoDB 5.0 through 8.0. Verify the exact Mongoid version in the Gemfile.lock and check compatibility:
- Mongoid 9.x supports MongoDB 5.0 through 8.0
- Mongoid 8.x supports MongoDB 4.4 through 7.0

### 5. Application Connection String

The Integrator connects using all 3 replica set members in the URI:
```
mongodb://mongo000:27017,mongo001:27017,mongo002:27017/database
```

No changes needed — the driver handles rolling upgrades transparently. During primary election, writes pause for ~10-20 seconds and resume automatically.

---

## Environment Execution Order

Start with the lowest-risk environment and progress to the most critical:

1. **commcenter** (has staging — pilot)
2. **redebrasil** (1 app server, simpler)
3. **maqnelson**
4. **almaviva**
5. **atento-br** (largest Redis, likely highest traffic — last)

Each environment completes ALL 7 steps before moving to the next. Do not upgrade Step 1 across all environments first — finish one environment end-to-end, learn from it, then proceed.

---

## Validation After Each Step

After every step (MongoDB or Ubuntu upgrade), verify:

1. `rs.status()` — all members in correct state (PRIMARY, SECONDARY, ARBITER)
2. `rs.conf()` — replica set configuration unchanged
3. `db.adminCommand({ getParameter: 1, featureCompatibilityVersion: 1 })` — FCV matches expected version
4. `db.serverStatus().version` — MongoDB version correct
5. Application health check — Integrator can read and write
6. Run one integration job and verify it completes successfully

---

## Estimated Timeline

### Per Environment (all 7 steps)

| Step | Action | Estimated Time |
|------|--------|---------------|
| Pre-checks + backup verification | Verify health, backup | 30 min |
| Step 1 | MongoDB 4.4 → 5.0 | 60-90 min |
| Step 2 | Ubuntu 18.04 → 20.04 (3 nodes) | 2-3 hours |
| Step 3 | MongoDB 5.0 → 6.0 | 60-90 min |
| Step 4 | MongoDB 6.0 → 7.0 | 60-90 min |
| Step 5 | MongoDB 7.0 → 8.0 | 60-90 min |
| Step 6 | Ubuntu 20.04 → 24.04 (3 nodes, re-provision, skips 22.04) | 2-3 hours |
| Post-validation | Full test cycle | 1 hour |
| **Total per environment** | | **~12-16 hours** |

### All 5 Environments

| Phase | Timeline |
|-------|----------|
| Preparation (Ansible playbooks, backup setup, documentation) | 1 week |
| First environment (pilot, learning) | 2-3 days |
| Environments 2-5 (sequential, 1-2 days each) | ~1.5 weeks |
| **Total** | **~3 weeks** |

---

## Ansible Automation

### Existing Role

The current `4shark.mongodb` role installs MongoDB 4.4 from the Bionic repository. It needs to be parameterized for version upgrades.

### Required Ansible Work

1. **Parameterize the MongoDB role** to accept version and Ubuntu codename as variables
2. **Create upgrade playbook** (`playbooks/upgrade-mongodb.yml`) that:
   - Validates current FCV and replica set health
   - Switches apt repository to the target MongoDB version
   - Installs new packages
   - Waits for node to rejoin replica set
   - Sets FCV (on primary only)
3. **Use `community.mongodb` Ansible collection** for:
   - `community.mongodb.mongodb_status` — validate replica set
   - `community.mongodb.mongodb_stepdown` — step down primary
   - `community.mongodb.mongodb_maintenance` — enable/disable maintenance mode
4. **Create OS re-provision playbook** (`playbooks/reprovision-node.yml`) that, per replica-set member:
   - Provisions a fresh instance on the target Ubuntu LTS with the correct MongoDB apt repository/codename
   - `rs.add()` the new node and waits for initial sync to `SECONDARY`
   - `rs.remove()` and retires the old member (steps down the primary first)
   - Validates replica set membership

---

## Terraform Changes

### During Upgrade

**MongoDB version hops (Steps 1, 3, 4, 5)** are in-place (apt on the running node) — no Terraform change. **OS hops (Steps 2 and 6)** are re-provisioning: a fresh instance is stood up on the new Ubuntu LTS, joined to the replica set, and the old one retired. The module pins the AMI with `lifecycle { ignore_changes = [ami, user_data, user_data_base64] }`, so the AMI/instance replacement for an OS hop is driven deliberately (new instance alongside → join → retire the old), not by a fleet-wide AMI bump.

### After Upgrade (Post-Migration Cleanup)

After all environments are upgraded:

1. **Update the default AMI** in `modules/integrator/variables.tf` to an Ubuntu 24.04 AMI (for any future instances)
2. **Update the Ansible role** to install MongoDB 8.0 from the Noble repository (for any new environments)
3. **Consider updating the `mongod.conf` template** if MongoDB 8.0 has new recommended settings

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| PSA write concern issue on 5.0 upgrade | Writes block if secondary goes down | Set `defaultWriteConcern: { w: 1 }` BEFORE Step 1 |
| Data loss during upgrade | Unrecoverable | Implement backups BEFORE starting (pre-requisite) |
| Application incompatibility with new MongoDB | Integration jobs fail | Test on pilot environment (commcenter) first |
| EBS volume detachment during OS upgrade | Data directory unavailable | Verify `/data/db` mount in `/etc/fstab` survives reboot |
| MongoDB repo GPG key mismatch after OS upgrade | apt update fails | Re-import GPG key for the target MongoDB version |

---

## Post-Upgrade: Operational Hygiene

After completing all upgrades, implement:

### Backups
- `mongodump` via cron on secondary → S3 (daily, 7-day retention)
- EBS snapshots via AWS DLM (daily, 7-day retention)
- Monthly backup restore test

### Monitoring
- Datadog MongoDB integration (already have Datadog agent on app servers)
- Alerts: replication lag, disk usage, connections, slow queries

### Future Upgrades
- With this process documented and automated via Ansible, future upgrades (e.g., MongoDB 8.0 → 9.0, Ubuntu 24.04 → 26.04) become a 1-step operation per dimension instead of 7 steps
