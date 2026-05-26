# PLAN — MongoDB Atlas Phase 3: Cluster Name Standardization via mongosync

## Context

MongoDB Atlas clusters cannot be renamed. The current clusters have inconsistent names (Staging, Poc, Shared, App). This plan creates new clusters with standardized names, syncs data via mongosync, and cuts over the applications.

**Current → Target:**
| Project | Current | Target | Disk Change | Status |
|---------|---------|--------|-------------|--------|
| App Beta001 | `Staging` | `beta-001` | 10 GB (same) | **DONE** |
| App Demo001 | `Poc` | `demo-001` | 10 GB (same) | **DONE** |
| App Shared001 | `Shared` | `shared-001` | 52 → **126 GB** (auto-scaled during migration) | **DONE** |
| App Atento001 | `App` | `atento-001` | 90 → **79 GB** | **DONE** |

**Final cluster config (standardized):**
- All clusters: M10 base tier, auto-scaling M10↔M20, termination protection ON

---

## PR #1: Create New Clusters + Temporary IP Access — DONE

**Branch:** `feature/mongodb-rename-clusters` — merged
**PR:** #199

All 4 new clusters created with `mongodbatlas_advanced_cluster.migration_target` resource + temporary IP access for mongosync.

---

## mongosync — ALL DONE

### Beta (port 27182) — DONE
- Staging → beta-001: COMMITTED
- mongosync stopped

### Demo (port 27183) — DONE
- Poc → demo-001: COMMITTED
- mongosync stopped

### Shared (port 27184) — DONE
- Shared → shared-001: COMMITTED (40.2 GB, 2989 events)
- mongosync stopped

### Atento (port 27185) — DONE
- App → atento-001: COMMITTED (~27 GB)
- mongosync stopped

---

## Post-mongosync Cleanup — ALL DONE

### Beta — DONE
- [x] Temporary IP `177.172.213.104/32` removed from project
- [x] User `POhs87c83YyWDH5D` role reverted from `atlasAdmin` to `readWriteAnyDatabase`

### Demo — DONE
- [x] Temporary IP `177.172.213.104/32` removed from project

### Shared — DONE
- [x] Old cluster connections validated (only Atlas internal monitoring, no app traffic)
- [x] Temporary IP removal handled via migration_target resource removal

### Atento — DONE
- [x] Temporary IP removal handled via migration_target resource removal

---

## PR #2: Terraform Cleanup — ALL DONE

### Beta and Demo — DONE
**Branch:** `feature/mongodb-rename-clusters-cleanup-beta-demo` — merged (PR #202)

Changes applied:
- `app-beta-001/mongodb.tf`: `cluster_name = "beta-001"`, removed migration_target resource
- `app-demo-001/mongodb.tf`: `cluster_name = "demo-001"`, removed migration_target resource
- State manipulation: old clusters removed from state, new clusters imported
- `terraform plan` confirmed: no changes on both environments

### Shared and Atento — DONE
**Branch:** `feature/mongodb-rename-clusters-cleanup-shared-atento` — merged (PR #208)

Changes applied:
- `app-shared-001/mongodb.tf`: `cluster_name = "shared-001"`, tier M20→M10, disk 52→126 GB, added auto-scaling M10↔M20, termination protection ON, removed migration_target
- `app-atento-001/mongodb.tf`: `cluster_name = "atento-001"`, disk 90→79 GB, termination protection ON, removed migration_target
- State manipulation: old clusters removed from state, migration_target moved to module, backup schedules imported
- `terraform apply` confirmed on both environments

---

## Old Cluster Deletion — ALL DONE

### Beta (Staging) — DONE
- [x] Termination protection disabled via Atlas API
- [x] DELETE returned 202, cluster confirmed in DELETING state

### Demo (Poc) — DONE
- [x] Termination protection disabled via Atlas API
- [x] DELETE returned 202, cluster confirmed in DELETING state

### Shared — DONE
- [x] Termination protection disabled via Atlas API
- [x] DELETE returned 202

### Atento (App) — DONE
- [x] Termination protection disabled via Atlas API
- [x] DELETE returned 202

---

## Verification — ALL DONE

1. ~~**After PR #1 apply**: Atlas console shows 2 clusters per project (old + new)~~ DONE
2. ~~**After mongosync Beta/Demo**: New clusters contain same data as old~~ DONE
3. ~~**After deploy Beta/Demo**: Applications working normally with new connection strings~~ DONE
4. ~~**After PR #2 Beta/Demo**: Old clusters destroyed, `terraform plan` shows zero changes~~ DONE
5. ~~**After mongosync Shared/Atento**: New clusters contain same data as old~~ DONE
6. ~~**After deploy Shared/Atento**: Applications working normally with new connection strings~~ DONE
7. ~~**After PR #2 Shared/Atento**: Old clusters removed, terraform applied on both environments~~ DONE

---

## Remaining Items

- [ ] Terminate EC2 instance `i-085dfec1737268dd6` (mongosync-temp, t3a.xlarge)
- [ ] Update CHANGELOG.md with cluster standardization entry
