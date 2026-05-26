# Plan: Upgrade MongoDB 4.4 → 8.0 and Ubuntu 18.04 → 24.04 on Integrator Environments

**Status:** Draft
**Date:** 2026-02-23
**Project:** terraform + ansible (integrator environments)
**Scope:** 6 environments × 3 nodes = 18 EC2 instances

---

## Context

The 6 integrator environments run MongoDB 4.4 on Ubuntu 18.04 (Bionic). Both are well past End of Life:
- **MongoDB 4.4:** EOL since February 2024
- **Ubuntu 18.04:** EOL since June 2023

There are no automated backups, no upgrade procedures, and no documented process for maintaining these servers. This plan defines the exact upgrade sequence, respecting compatibility constraints between MongoDB versions and Ubuntu LTS releases.

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

## Upgrade Sequence (7 Steps)

Ubuntu 20.04 supports MongoDB 5.0 through 8.0, so all MongoDB hops can be completed on a single Ubuntu version after the first OS upgrade. This minimizes the number of OS upgrades interleaved with MongoDB upgrades.

```
START:  MongoDB 4.4 + Ubuntu 18.04 (Bionic)

Step 1: MongoDB 4.4 → 5.0    (on Ubuntu 18.04)  ← last MongoDB version on Bionic
Step 2: Ubuntu 18.04 → 20.04  (with MongoDB 5.0) ← OS upgrade required before MongoDB 7.0
Step 3: MongoDB 5.0 → 6.0    (on Ubuntu 20.04)
Step 4: MongoDB 6.0 → 7.0    (on Ubuntu 20.04)
Step 5: MongoDB 7.0 → 8.0    (on Ubuntu 20.04)  ← all MongoDB hops done
Step 6: Ubuntu 20.04 → 22.04  (with MongoDB 8.0)
Step 7: Ubuntu 22.04 → 24.04  (with MongoDB 8.0)

END:    MongoDB 8.0 + Ubuntu 24.04 (Noble)
```

### Why This Order

1. **Step 1 on Bionic:** MongoDB 5.0 is the last version that supports Ubuntu 18.04. Must upgrade MongoDB first because 4.4 packages may not install cleanly on newer Ubuntu.
2. **Step 2 before more MongoDB hops:** Ubuntu 20.04 supports MongoDB 5.0 through 8.0, creating a stable platform for all remaining MongoDB upgrades.
3. **Steps 3-5 on Focal:** All three remaining MongoDB hops can execute on Ubuntu 20.04 without any OS change in between. This is the fastest section.
4. **Steps 6-7 after MongoDB is done:** Ubuntu hops are simpler when MongoDB is already at its target version — no repo switching needed, just `do-release-upgrade` with MongoDB 8.0 packages available for all target Ubuntu versions.

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

**Rolling OS upgrade procedure (per node, same order: secondary → arbiter → primary):**

For each node:
1. Stop mongod: `systemctl stop mongod`
2. Verify data directory is on a separate EBS volume (`/data/db`) — data survives OS upgrade
3. Run: `do-release-upgrade`
4. Handle prompts:
   - Keep existing `/etc/mongod.conf` (or the custom `mongod.conf` from Ansible)
   - Accept default for other packages
5. Reboot when prompted
6. After reboot, reconfigure MongoDB 5.0 apt repository for `focal` codename:
   ```bash
   echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-5.0.gpg ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/5.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-5.0.list
   ```
7. `apt update && apt install -y mongodb-org` (reinstall to ensure correct packages)
8. Start mongod: `systemctl start mongod`
9. Wait for node to rejoin replica set: `rs.status()`

**For the primary:** Run `rs.stepDown()` before stopping mongod. Upgrade after secondary and arbiter are back online.

**Estimated time per node:** 30-45 minutes (including reboot and rejoin)

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

### Step 6: Ubuntu 20.04 → 22.04 (with MongoDB 8.0)

**Compatibility:** MongoDB 8.0 supports Ubuntu 22.04 ✓

**Library change:** Ubuntu 22.04 ships with OpenSSL 3.0 and `libssl3` instead of `libssl1.1`. MongoDB 8.0 supports OpenSSL 3.0 — no issue.

**Rolling OS upgrade procedure (same as Step 2):**
1. Stop mongod
2. `do-release-upgrade`
3. Reboot
4. Reconfigure apt repo for `jammy` codename:
   ```bash
   echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/8.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list
   ```
5. `apt update && apt install -y mongodb-org`
6. Start mongod, verify replica set

---

### Step 7: Ubuntu 22.04 → 24.04 (with MongoDB 8.0)

**Compatibility:** MongoDB 8.0 supports Ubuntu 24.04 ✓

**Rolling OS upgrade procedure (same as Steps 2 and 6):**
1. Stop mongod
2. `do-release-upgrade`
3. Reboot
4. Reconfigure apt repo for `noble` codename:
   ```bash
   echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu noble/mongodb-org/8.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list
   ```
5. `apt update && apt install -y mongodb-org`
6. Start mongod, verify replica set

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

1. **aster-maquinas** (has staging, smaller client)
2. **commcenter** (has staging)
3. **redebrasil** (1 app server, simpler)
4. **maqnelson**
5. **almaviva**
6. **atento-br** (largest Redis, likely highest traffic — last)

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
| Step 6 | Ubuntu 20.04 → 22.04 (3 nodes) | 2-3 hours |
| Step 7 | Ubuntu 22.04 → 24.04 (3 nodes) | 2-3 hours |
| Post-validation | Full test cycle | 1 hour |
| **Total per environment** | | **~12-16 hours** |

### All 6 Environments

| Phase | Timeline |
|-------|----------|
| Preparation (Ansible playbooks, backup setup, documentation) | 1 week |
| First environment (pilot, learning) | 2-3 days |
| Environments 2-6 (sequential, 1-2 days each) | 2 weeks |
| **Total** | **~4 weeks** |

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
4. **Create OS upgrade playbook** (`playbooks/upgrade-ubuntu.yml`) that:
   - Stops mongod
   - Runs `do-release-upgrade -f DistUpgradeViewNonInteractive`
   - Reconfigures MongoDB apt repository for new codename
   - Reinstalls MongoDB packages
   - Starts mongod
   - Validates replica set membership

---

## Terraform Changes

### During Upgrade (No Changes)

The Terraform module uses `lifecycle { ignore_changes = [ami, user_data, user_data_base64] }` on all MongoDB instances. The OS and MongoDB upgrades happen in-place via Ansible — Terraform does not need to be modified during the upgrade.

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
| `do-release-upgrade` breaks mongod config | mongod fails to start after OS upgrade | Keep original `mongod.conf`, reconfigure apt repo manually |
| Data loss during upgrade | Unrecoverable | Implement backups BEFORE starting (pre-requisite) |
| Application incompatibility with new MongoDB | Integration jobs fail | Test on pilot environment (aster-maquinas) first |
| `do-release-upgrade` prompts hang | Upgrade stalls, node offline too long | Use `-f DistUpgradeViewNonInteractive` flag for non-interactive mode |
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
