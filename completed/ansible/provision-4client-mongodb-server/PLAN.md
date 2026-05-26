# PLAN — provision-4client-mongodb-server

## Current Situation

- **Architecture**: MongoDB runs in a 3-node ReplicaSet (1 primary, 1 secondary, 1 arbiter) per 4client environment
- **Current provisioning**: Managed inline within `playbooks/provision-4client.yml` — no dedicated playbook for standalone MongoDB server provisioning
- **MongoDB role**: `roles/4shark.mongodb` installs MongoDB 4.4 from Ubuntu bionic (18.04) repository — incompatible with Ubuntu 24.04
- **Missing capabilities on MongoDB nodes**:
  - No engineer SSH access (role `4shark.engineers` is not applied)
  - No Datadog monitoring integration
- **ReplicaSet setup**: Done inline in `provision-4client.yml` using the deprecated `mongo` shell (replaced by `mongosh` in MongoDB 6+)
- **Vars structure**: No dedicated vars directory for 4client MongoDB configuration

- **Impacted components**:
  - New role `roles/4shark.mongodb8/` (old `roles/4shark.mongodb/` stays untouched)
  - New playbook `playbooks/provision-4client-mongodb-server.yml` (single playbook, configures all 3 nodes + ReplicaSet)
  - New vars directory `playbooks/vars/4client-mongodb/`

- **Versions/environment**: Ubuntu 24.04 (Noble) on AWS EC2, MongoDB 8.2, Mongoid 9.0.x (app: 9.0.10, integrator: 9.0.8)

---

## Objective / Target State

- A single playbook `provision-4client-mongodb-server.yml` that takes 3 bare Ubuntu 24.04 EC2 instances and fully configures them as a MongoDB ReplicaSet (arbiter + primary + secondary) in one run
- A new role `4shark.mongodb8` for MongoDB 8.2 on Ubuntu 24.04 (Noble), independent from the old `4shark.mongodb` role
- Engineer SSH access on all MongoDB nodes
- Datadog monitoring with MongoDB integration (metrics + slow query logs)
- Per-client vars files under `playbooks/vars/4client-mongodb/`

**Success criteria:**
- Running `provision-4client-mongodb-server.yml` with 3 IPs produces a fully configured MongoDB ReplicaSet in one execution
- Datadog agent runs and ships MongoDB metrics and logs
- Engineers can SSH into MongoDB nodes
- Role is idempotent (re-running does not break a running instance)

---

## Problem / New Feature

The current MongoDB provisioning is embedded in a monolithic playbook (`provision-4client.yml`) that provisions an entire VPC. There is no way to:

- Provision a single MongoDB node in isolation (e.g., replacing a failed node)
- Upgrade OS from Ubuntu 18.04 to 24.04 (the role hardcodes bionic repos)
- Monitor MongoDB via Datadog
- Give engineers direct SSH access to debug production issues

---

## Challenges, Difficulties and Risks

- **Technical**:
  - MongoDB 4.4 is EOL and its APT repository only supports Ubuntu 18.04 (bionic) — must upgrade to MongoDB 7.0
  - The `mongo` shell command used in ReplicaSet setup tasks was removed in MongoDB 6.0+ and replaced by `mongosh` — tasks must be rewritten
  - The `rc.local` approach for disabling transparent hugepages is unreliable on modern systemd-based Ubuntu — should be migrated to a systemd unit
  - ReplicaSet initialization must be idempotent — re-running the replicaset playbook against an already-configured primary must not fail
  - The `mongod.conf.j2` template does not include `mongodb_conf_replSetName` in defaults, so it is currently undefined unless set explicitly

- **Security/privacy**:
  - Engineer SSH keys are managed via the `4shark.engineers` role — no new risk, following existing pattern

- **Performance**:
  - Transparent hugepage disabling is critical for MongoDB performance — migration to systemd unit must preserve this behavior

---

## Chosen Solution

**Option 2 — Create a new role `4shark.mongodb8`, leave old role `4shark.mongodb` intact**

- **How it works:** Create a new role for MongoDB 8.2 on Ubuntu 24.04 (Noble); the new playbook uses the new role; the old playbooks (`provision-4client.yml`, `provision-4client-without-vpn.yml`) continue to use `4shark.mongodb` untouched
- **Rationale:** The engineer needs to test Terraform-based provisioning alongside Ansible configuration. If issues arise, the old monolithic Ansible playbooks must still work as a fallback. Zero regression risk on existing environments is mandatory.
- **MongoDB version:** 8.2 (latest minor release, supported on-premises for Community Edition, compatible with Mongoid 9.0.x used in both app and integrator)
- **GPG key:** `https://www.mongodb.org/static/pgp/server-8.0.asc` (same key for 8.0 and 8.2)
- **APT repo:** `deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu noble/mongodb-org/8.2 multiverse`

---

## Proposed Steps (high level, don't execute yet)

### Phase 1 — Create new role `4shark.mongodb8`

1. Create `roles/4shark.mongodb8/defaults/main.yml`:
   - `mongodb_version: "8.2"`
   - `mongodb_ubuntu_codename: "noble"`
   - `mongodb_conf_bindip: "0.0.0.0"`
   - `mongodb_conf_port: "27017"`
   - `mongodb_conf_dbpath: "/data/db"`
   - `mongodb_conf_logpath: "/var/log/mongodb/mongod.log"`
   - `mongodb_conf_logappend: "true"`
   - `mongodb_conf_replSetName: ""`
2. Create `roles/4shark.mongodb8/tasks/main.yml`:
   - Install GPG key from `https://www.mongodb.org/static/pgp/server-8.0.asc`
   - Add APT repo for MongoDB 8.2 on Ubuntu noble
   - Install `mongodb-org` and `numactl`
   - Create systemd unit to disable transparent hugepages (replaces old `rc.local` approach)
   - Create data and log directories
   - Configure mongod via template
   - Enable and start mongod service
3. Create `roles/4shark.mongodb8/templates/mongod.conf.j2` — based on existing template but clean
4. Create `roles/4shark.mongodb8/templates/disable-thp.service.j2` — systemd unit for transparent hugepages
5. Create `roles/4shark.mongodb8/handlers/main.yml` — restart mongod handler

### Phase 2 — Create vars structure

4. Create directory `playbooks/vars/4client-mongodb/`
5. Create one example vars file per active client (or a `generic.yml` template showing the expected structure):
   - `engineers` list (SSH keys)
   - `mongodb_conf_replSetName`
   - `mongodb_version`, `mongodb_ubuntu_codename`
   - Datadog API key reference

### Phase 3 — Create provisioning playbook (single playbook, multiple plays)

6. Create `playbooks/provision-4client-mongodb-server.yml`:
   - Parameters: `client_name`, `mongo_arbiter` (IP), `mongo_primary` (IP), `mongo_secondary` (IP)
   - `vars_files`: `vars/4client-mongodb/{{ client_name }}.yml`
   - **Play 1 — Configure all 3 nodes** (hosts: mongo_arbiter, mongo_primary, mongo_secondary):
     - Set hostname
     - Roles: `4shark.common_packages`, `jnv.unattended-upgrades`, `geerlingguy.ntp`, `4shark.users`, `4shark.deploy_user`, `4shark.engineers`, `4shark.mongodb8`, `Datadog.datadog`
     - Datadog: MongoDB integration (metrics from localhost:27017) + mongod log file
   - **Play 2 — Initialize ReplicaSet and add members** (hosts: mongo_primary only):
     - Check if ReplicaSet already initialized
     - `mongosh --eval 'rs.initiate()'`
     - `mongosh --eval 'rs.add("4client-{{ client_name }}-mongo002:27017")'`
     - `mongosh --eval 'rs.addArb("4client-{{ client_name }}-mongo000:27017")'`
   - Usage:
     ```
     ./run_playbook.sh 4shark playbooks/provision-4client-mongodb-server.yml \
       client_name=cliente1 \
       mongo_arbiter=10.1.5.10 \
       mongo_primary=10.1.5.11 \
       mongo_secondary=10.1.5.12
     ```

---

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| MongoDB version | 8.2 | Latest minor release, on-premises Community Edition support, Mongoid 9.0.x compatible |
| Role strategy | New role `4shark.mongodb8`, old role untouched | Zero regression risk; old playbooks must continue to work as Terraform migration fallback |
| ReplicaSet setup | Same playbook, second play targeting primary only | Single command provisions everything; consistent with how old `provision-4client.yml` works |
| Hugepage disabling | Systemd unit (new role only) | `rc.local` is deprecated and unreliable on Ubuntu 24.04 with systemd |
| Mongo shell | `mongosh` (included in mongodb-org 8.2) | `mongo` was removed in MongoDB 6.0 |
| Datadog MongoDB check | `mongo` integration (metrics) + log file | Standard Datadog integration for MongoDB; slow query log already configured in mongod.conf |

---

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| ReplicaSet playbook is not idempotent | Medium | Check `rs.status().ok` before running `rs.initiate()`; tolerate "already initialized" errors |
| MongoDB 8.2 behavioral differences vs 4.4 | Low | Mongoid 9.0.x officially supports 8.2; test with app/integrator before production rollout |

---

## Assumptions

- New MongoDB nodes run Ubuntu 24.04 (Noble) on AWS EC2
- Existing 4client MongoDB nodes (Ubuntu 18.04) will continue to use `provision-4client.yml` with the old `4shark.mongodb` role untouched
- The 3-node ReplicaSet topology (primary + secondary + arbiter) is fixed and does not vary per client
- Datadog agent is already installed via a role available in the project (`Datadog.datadog`)
- Per-client vars files for MongoDB will follow the same structure as `playbooks/vars/integrator/` (one file per client)
- Engineer SSH keys are already defined in each client's vars file via the `engineers` variable

---

## Internal References

- `playbooks/provision-integrator-server.yml` — pattern for the new main playbook
- `playbooks/provision-integrator-ruby.yml` — pattern for the utility (replicaset) playbook
- `playbooks/provision-4client.yml` (lines 525–556) — current MongoDB install + ReplicaSet setup
- `roles/4shark.mongodb/` — old role (DO NOT MODIFY)
- `roles/4shark.engineers/tasks/main.yml` — engineer SSH access role

---

**Status:** COMPLETED — PR #138 merged to `develop` on 2026-02-25.
Option 2 (new role `4shark.mongodb8`, MongoDB 8.2, old role untouched).
