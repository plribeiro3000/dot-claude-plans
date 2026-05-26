# TASKS — provision-4client-mongodb-server — Option 2 (new role)

> **Objective of this iteration:** Create a new `4shark.mongodb8` role and a single playbook `provision-4client-mongodb-server.yml` that configures 3 bare Ubuntu 24.04 EC2 instances as a MongoDB 8.2 ReplicaSet in one execution.
> **Reference:** derived from `PLAN.md` (Chosen Solution: Option 2).

---

## 0) Pre-conditions

- [x] `PLAN.md` **approved** (option: 2 — new role, MongoDB 8.2, old role untouched)
- [x] **Base branch:** `develop` • **Working branch:** `feature/provision-4client-mongodb-server`

---

## 1) Step by Step (atomic tasks)

### Task 1 — Create feature branch
- **Status:** DONE
- **Objective:** Create `feature/provision-4client-mongodb-server` from `develop`
- **Actions (checklist):**
  - [x] `git checkout -b feature/provision-4client-mongodb-server`

### Task 2 — Create role `4shark.mongodb8`
- **Status:** DONE
- **Objective:** New role that installs and configures MongoDB 8.2 on Ubuntu 24.04
- **Actions (checklist):**
  - [x] Create `roles/4shark.mongodb8/defaults/main.yml`
  - [x] Create `roles/4shark.mongodb8/tasks/main.yml`
  - [x] Create `roles/4shark.mongodb8/templates/mongod.conf.j2`
  - [x] Create `roles/4shark.mongodb8/templates/disable-thp.service.j2`
  - [x] Create `roles/4shark.mongodb8/handlers/main.yml`
- **Affected files:** `roles/4shark.mongodb8/`

### Task 3 — Create vars directory
- **Status:** DONE
- **Objective:** Create per-client vars structure for 4client MongoDB
- **Actions (checklist):**
  - [x] Create `playbooks/vars/4client-mongodb/.gitkeep`
- **Affected files:** `playbooks/vars/4client-mongodb/.gitkeep`

### Task 4 — Create `provision-4client-mongodb-server.yml` playbook
- **Status:** DONE
- **Objective:** Single playbook that configures 3 nodes + initializes ReplicaSet
- **Actions (checklist):**
  - [x] Create `playbooks/provision-4client-mongodb-server.yml` with:
    - Parameters: `client_name`, `mongo_arbiter`, `mongo_primary`, `mongo_secondary`
    - Play 1: Configure all 3 nodes (packages, NTP, users, engineers, mongodb8, Datadog)
    - Play 2: Initialize ReplicaSet on primary (idempotent with `rs.initiate()` containing all members)
    - Usage comment block at top
- **Affected files:** `playbooks/provision-4client-mongodb-server.yml`

### Task 5 — Update CHANGELOG.md
- **Status:** DONE
- **Actions (checklist):**
  - [x] Added entry: "MongoDB 8.2 server provisioning for 4client environments"

### Task 6 — Commit and create PR
- **Status:** DONE
- **Actions (checklist):**
  - [x] Commit: `feat(mongodb): MongoDB 8.2 server provisioning for 4client`
  - [x] PR #138 created, reviewed, fixes applied, squashed, merged

### Task 7 — Code review fixes (post-review)
- **Status:** DONE
- **Objective:** Address all issues found in code review of PR #138
- **Actions (checklist):**
  - [x] B1: Idempotent ReplicaSet — check `rs.status()` before `rs.initiate()`
  - [x] B2: Explicit `group: mongodb` on data/log directories
  - [x] B3: Document auth disabled by design (VPC/Security Group isolation)
  - [x] W1: Replace `curl | gpg` with `get_url` for GPG key download
  - [x] W2: Standardize `true/false` instead of `yes/no` in YAML
  - [x] S1: Merge prerequisite apt tasks into single task
  - [x] S2: Hardcode `logAppend: true` in template, remove variable
  - [x] S3: Add `group: root` to disable-thp.service template task
  - [x] S4: Document `client_name` parameter constraints in playbook header

---

## 2) Items Requiring User Confirmation

- [x] **MongoDB version:** 8.2
- [x] **Role strategy:** New role `4shark.mongodb8`, old role untouched
- [x] **ReplicaSet topology:** primary + secondary + arbiter, same for all clients
- [x] **Single playbook:** One command provisions all 3 nodes + ReplicaSet

---

## 3) Pending Items After This Iteration

- [ ] Create actual per-client vars files when Terraform provisions first client
- [ ] Create per-client vars files in `playbooks/vars/integrator/` for Ruby servers (separate feature)
- [ ] Refactor `provision-redis-5-master-slave.yml` to separate infra from config (deferred)

---

## Result

**PR #138** — Merged to `develop` on 2026-02-25.
All tasks completed. Role and playbook are production-ready.
