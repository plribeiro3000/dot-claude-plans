# PLAN — Infrastructure Standardization (S3 Buckets + RDS Databases + MongoDB Atlas + OpenSearch + Redis Cloud + KeyCloak)

## Context

S3 buckets, RDS databases, MongoDB Atlas clusters, OpenSearch domains, Redis Cloud databases, and the KeyCloak auth cluster across environments have inconsistent naming, networking, and configuration. This was discovered during the import of these resources into Terraform management. The goal is to standardize naming to `{environment}` and align configurations across all environments. The `4shark` prefix is reserved **only for S3 buckets** (globally unique names required). All other AWS resources use `{environment}-*` pattern (e.g., `shared-001`, `beta-001`).

This plan is split into **six features**, executed in order of complexity and risk: ~~S3~~ ✓ → ~~RDS~~ ✓ → ~~MongoDB Atlas~~ ✓ → ~~OpenSearch~~ ✓ → ~~Redis Cloud~~ ✓ → ~~KeyCloak~~ ✓.

**STATUS: ALL PARTS COMPLETED.**

---

# PART 1: S3 Bucket Name Standardization — COMPLETED

All S3 work is done. Summary of what was executed:

| Project | Old Bucket | New Bucket | Status |
|---------|-----------|------------|--------|
| app-atento-001 | `4shark-atento-001` | `4shark-atento-001` | Already correct |
| app-beta-001 | `4shark-staging` | `4shark-beta-001` | **Migrated** |
| app-demo-001 | `4shark-poc` | `4shark-demo-001` | **Migrated** |
| app-shared-001 | `4shark-shared` | `4shark-shared-001` | **Migrated** |

### What was done

1. **PR #178** (`feature/standardize-s3-buckets`) — Created new buckets with SRR replication, IAM roles, dual-bucket IAM policies
2. **`terraform apply`** on 3 environments — new buckets + replication created
3. **`aws s3 sync`** — existing objects copied to new buckets, object counts verified
4. **App cutover** — `S3_BUCKET` env var updated, apps deployed pointing to new buckets
5. **Final `aws s3 sync`** — caught stragglers from in-flight jobs
6. **PR #180** (`feature/cleanup-s3-migration`) — Removed replication (code + apply), state rm old buckets, state mv new → standard, code cleanup, IAM policies updated
7. **Validated via AWS CLI** — replication gone, IAM roles gone, IAM policies reference only new buckets

### Old bucket cleanup (Task 1.7) — DONE

Old buckets have been permanently deleted from AWS:

| Old Bucket | Validation | Deletion |
|------------|------------|----------|
| `4shark-staging` (was beta) | Path + size comparison: all objects present in new bucket | Emptied (all versions + delete markers) and deleted |
| `4shark-poc` (was demo) | Path + size comparison: all objects present in new bucket | Emptied (all versions + delete markers) and deleted |
| `4shark-shared` (was shared) | 28,358 identical files, 0 only in old, 26 only in new, 5 divergent (explained by commission reprocessing during cutover window) | Emptied (28,515 versions/markers) and deleted |

**Investigation note**: 5 commission report files in `4shark-shared` had different sizes between old and new buckets. Root cause: commissions 61061, 61069, 61070, 61071, 61085 were reprocessed by users between the final sync and bucket deletion. `Commission::Producer` destroys the report during reprocessing, and new reports were generated writing to the new bucket. Confirmed via `CommissionProcessingEvent` records in Rails console. No data loss.

---

# PART 2: RDS Database Standardization — COMPLETED

All RDS renames are done. Summary of what was executed:

| Project | Type | Old Identifier | New Identifier | PR |
|---------|------|----------------|----------------|-----|
| app-beta-001 | RDS | `beta-db` | `beta-001` | #198 |
| app-demo-001 | Aurora | `demo-prd` | `demo-001-cluster` | #198 |
| app-shared-001 | Aurora | `production-app-2` | `shared-001-cluster` | #199 |
| app-atento-001 | Aurora | `atento-001-app-cluster-cluster` | `atento-001-cluster` | #199 |
| setup | RDS | `setup-prd-db` | `setup-001` | #199 |

Aurora instance identifiers (also renamed):

| Old Instance | New Instance | PR |
|-------------|-------------|-----|
| `demo-prd-instance-1` | `demo-001-db-1` | #198 |
| `production-app-2-instance-1` | `shared-001-db-1` | #199 |
| `production-app-2-instance-1-us-east-1b` | `shared-001-db-2` | #199 |
| `atento-001-app-cluster` | `atento-001-db-1` | #199 |
| `atento-001-app-ro` | `atento-001-db-2` | #199 |

### What was done

1. **PR #177** — Module updates + configuration standardization (monitoring, security)
2. **PR #198** (`feature/standardize-rds-identifiers`) — Beta + Demo renames (AWS CLI rename → deploy → Terraform state reconciliation → code update)
3. **PR #199** (`feature/standardize-rds-identifiers-002`) — Shared + Atento + Setup renames (same procedure)
4. **Stale DNS cleanup** — Removed 8 CNAME records from `4shark.io` public zone that exposed RDS endpoints (security: information disclosure) and 1 stale ALB alias. All pointed to non-existent resources after renames.

### Notes

- **auth-001** (`auth001` → `auth-001`) was excluded from this scope. The RDS rename is trivial, but the ECS cluster (`4shark-keycloak`) also needs renaming to `auth-001-cluster`. Since ECS clusters can't be renamed, this requires creating a new cluster and migrating the service — separate feature.
- **Naming convention established**:
  - RDS standalone: `{env}` (e.g., `beta-001`)
  - Aurora cluster: `{env}-cluster` (e.g., `demo-001-cluster`)
  - Aurora instance: `{env}-db-{n}` (numbered, not role-based, because Aurora failover swaps writer/reader roles)

### Database Renaming — Downtime analysis (historical reference)

**Critical constraint**: Rename and deploy MUST be sequential, not parallel.

Why:
1. If rename fails mid-way, the deploy would point the app to a non-existent endpoint
2. If deploy starts before rename completes, the app loses DB connectivity during rename AND during the deploy rollout
3. Rollback is simpler when operations are sequential — you know exactly which step failed

**Downtime per environment**:

| Phase | Duration | App status |
|-------|----------|------------|
| 1. AWS CLI rename | ~5 min | **DOWN** — DB endpoint changes, app loses connection |
| 2. Wait for DB available | included in above | **DOWN** — DB not yet accepting connections |
| 3. Deploy app with new endpoint | varies | **DOWN** — old containers have wrong endpoint, new containers starting |
| 4. New containers healthy | — | **UP** |

| Environment | Rename | Deploy | Total downtime |
|-------------|--------|--------|----------------|
| Beta | ~5 min | ~8 min | **~13 min** |
| Setup | ~5 min | ~1-2 min (no Sidekiq, fast app) | **~6-7 min** |
| Demo | ~5 min | ~8 min | **~13 min** |
| Shared | ~5 min | ~12-15 min | **~17-20 min** |
| Atento | ~5 min | ~12-15 min | **~17-20 min** |

**Order: Beta → Setup → Demo → Shared → Atento** (least critical first)

**Scheduling**: Each environment must be done independently. Recommended during low-traffic windows. Not all environments need to be done on the same day.

### Rename procedure — RDS standalone (Beta, Setup)

```bash
# === PHASE 1: RENAME (app goes down) ===

aws rds modify-db-instance \
  --db-instance-identifier beta-db \
  --new-db-instance-identifier beta-001 \
  --apply-immediately

# Wait for rename to complete
aws rds wait db-instance-available --db-instance-identifier beta-001

# === PHASE 2: DEPLOY (app stays down until deploy finishes) ===

# Update DATABASE_HOST env var to new endpoint: beta-001.xxxx.us-east-1.rds.amazonaws.com
# Deploy the application (~8 min)
# App comes back up when new containers are healthy

# === PHASE 3: TERRAFORM RECONCILIATION ===

cd app-beta-001
terraform state rm 'module.rds_instance.aws_db_instance.this'
# Update rds.tf: identifier = "beta-001"
terraform import 'module.rds_instance.aws_db_instance.this' beta-001
terraform plan  # verify zero changes
```

**Rollback if rename fails**: If `modify-db-instance` fails, the old identifier is still valid. No action needed — app continues working.

**Rollback if deploy fails**: The DB is already renamed. Fix the deploy issue and redeploy. The old endpoint no longer exists, so rolling back the deploy won't help — must fix forward.

### Rename procedure — Aurora cluster (Demo, Shared, Atento)

Aurora requires renaming instances BEFORE the cluster (instances must exist in the cluster during rename).

```bash
# === PHASE 1: RENAME INSTANCES (app may experience brief hiccups) ===

# Rename all instances first
aws rds modify-db-instance \
  --db-instance-identifier demo-prd-instance-1 \
  --new-db-instance-identifier demo-001-1 \
  --apply-immediately

aws rds wait db-instance-available --db-instance-identifier demo-001-1

# === PHASE 2: RENAME CLUSTER (app goes down — endpoint changes) ===

aws rds modify-db-cluster \
  --db-cluster-identifier demo-prd \
  --new-db-cluster-identifier demo-001 \
  --apply-immediately

aws rds wait db-cluster-available --db-cluster-identifier demo-001

# === PHASE 3: DEPLOY (app stays down until deploy finishes) ===

# Update DATABASE_HOST env var to new cluster endpoint
# Deploy the application (~8 min)

# === PHASE 4: TERRAFORM RECONCILIATION ===

cd app-demo-001
terraform state rm 'module.rds_aurora_cluster.aws_rds_cluster.this'
terraform state rm 'module.rds_aurora_cluster.aws_rds_cluster_instance.this["demo-prd-instance-1"]'

terraform import 'module.rds_aurora_cluster.aws_rds_cluster.this' demo-001
terraform import 'module.rds_aurora_cluster.aws_rds_cluster_instance.this["demo-001-1"]' demo-001-1
terraform plan  # verify zero changes
```

**For Shared (2 instances):**

```bash
# Rename both instances
aws rds modify-db-instance \
  --db-instance-identifier production-app-2-instance-1 \
  --new-db-instance-identifier shared-001-1 \
  --apply-immediately
aws rds modify-db-instance \
  --db-instance-identifier production-app-2-instance-1-us-east-1b \
  --new-db-instance-identifier shared-001-2 \
  --apply-immediately

aws rds wait db-instance-available --db-instance-identifier shared-001-1
aws rds wait db-instance-available --db-instance-identifier shared-001-2

# Rename cluster
aws rds modify-db-cluster \
  --db-cluster-identifier production-app-2 \
  --new-db-cluster-identifier shared-001 \
  --apply-immediately
aws rds wait db-cluster-available --db-cluster-identifier shared-001

# Deploy app with new endpoint (~8 min)

# Terraform reconciliation
cd app-shared-001
terraform state rm 'module.rds_aurora_cluster.aws_rds_cluster.this'
terraform state rm 'module.rds_aurora_cluster.aws_rds_cluster_instance.this["production-app-2-instance-1"]'
terraform state rm 'module.rds_aurora_cluster.aws_rds_cluster_instance.this["production-app-2-instance-1-us-east-1b"]'

terraform import 'module.rds_aurora_cluster.aws_rds_cluster.this' shared-001
terraform import 'module.rds_aurora_cluster.aws_rds_cluster_instance.this["shared-001-1"]' shared-001-1
terraform import 'module.rds_aurora_cluster.aws_rds_cluster_instance.this["shared-001-2"]' shared-001-2
terraform plan  # verify zero changes
```

**For Atento (2 instances):**

```bash
# Rename both instances
aws rds modify-db-instance \
  --db-instance-identifier atento-001-app-cluster \
  --new-db-instance-identifier atento-001-1 \
  --apply-immediately
aws rds modify-db-instance \
  --db-instance-identifier atento-001-app-ro \
  --new-db-instance-identifier atento-001-2 \
  --apply-immediately

aws rds wait db-instance-available --db-instance-identifier atento-001-1
aws rds wait db-instance-available --db-instance-identifier atento-001-2

# Rename cluster
aws rds modify-db-cluster \
  --db-cluster-identifier atento-001-app-cluster-cluster \
  --new-db-cluster-identifier atento-001 \
  --apply-immediately
aws rds wait db-cluster-available --db-cluster-identifier atento-001

# Deploy app with new endpoint (~8 min)

# Terraform reconciliation
cd app-atento-001
terraform state rm 'module.rds_aurora_cluster.aws_rds_cluster.this'
terraform state rm 'module.rds_aurora_cluster.aws_rds_cluster_instance.this["atento-001-app-cluster"]'
terraform state rm 'module.rds_aurora_cluster.aws_rds_cluster_instance.this["atento-001-app-ro"]'

terraform import 'module.rds_aurora_cluster.aws_rds_cluster.this' atento-001
terraform import 'module.rds_aurora_cluster.aws_rds_cluster_instance.this["atento-001-1"]' atento-001-1
terraform import 'module.rds_aurora_cluster.aws_rds_cluster_instance.this["atento-001-2"]' atento-001-2
terraform plan  # verify zero changes
```

### PR 2: Update Identifiers in Terraform Code (after all renames complete)

**Task 2.8 — Update identifiers in Terraform code**

For each project, update the `rds.tf` with the new identifiers:

- `app-beta-001/rds.tf`: `identifier = "beta-001"`
- `app-demo-001/rds.tf`: `cluster_identifier = "demo-001"`, instance key `"demo-001-1"`
- `app-shared-001/rds.tf`: `cluster_identifier = "shared-001"`, instance keys `"shared-001-1"`, `"shared-001-2"`
- `app-atento-001/rds.tf`: `cluster_identifier = "atento-001"`, instance keys `"atento-001-1"`, `"atento-001-2"`
- `setup/rds.tf`: `identifier = "setup-001"`

**Verification**: `terraform plan` shows zero changes for each project (state was already reconciled during rename).

---

# PART 3: MongoDB Atlas Standardization

## Current Situation

MongoDB Atlas is managed manually via the web console. There are 4 projects with 1 cluster each, all running MongoDB 7.0 on AWS US_EAST_1.

**Organization:** 4Shark (`5bca5c89cf09a21bb6f53bc3`)

| Project | Project ID | Cluster | Tier | Disk | Environment Dir |
|---------|-----------|---------|------|------|-----------------|
| App Atento001 | `68c8474b6729fd188d1544ee` | App | M10 (autoscale M10-M20) | 90 GB | `app-atento-001/` |
| App Beta001 | `64bae502368f7b00e7dfb3cf` | Staging | M10 | 10 GB | `app-beta-001/` |
| App Demo001 | `5f1c9cacf1bcf214d3dd52a2` | Poc | M10 | 10 GB | `app-demo-001/` |
| App Shared001 | `5bca5c89cf09a21c475619f6` | Shared | M20 | 52 GB | `app-shared-001/` |

### Current Problems

1. **No Terraform management** — all changes require manual intervention via Atlas console
2. **Network access is inconsistent**:
   - Atento001: specific NAT Gateway IPs (correct)
   - Beta001: `0.0.0.0/0` (open to the world)
   - Demo001: `0.0.0.0/0` (open to the world)
   - Shared001: VPC peering (`10.254.0.0/16`)
3. **Unnecessary VPC peering on Shared001**: Shared001, Demo001, and Atento001 all share the same Production VPC (`vpc-0204a1f8b5de51941`) with the same NAT Gateway IPs. VPC peering provides no additional benefit over IP-based access in this scenario.
4. **Atento001 missing termination protection**
5. **Naming inconsistency**: Project and cluster names don't follow convention — but renaming is out of scope (clusters cannot be renamed; project renaming is a future effort)

### Network Topology

| VPC | CIDR | NAT Gateway IPs | Atlas Projects |
|-----|------|-----------------|----------------|
| Production | `10.254.0.0/16` | `34.195.63.108`, `34.226.84.227` | Shared001, Demo001, Atento001 |
| Beta | `10.154.0.0/16` | `3.218.162.113` | Beta001 |

### Database Users

| Project | Username | Roles | Auth DB |
|---------|----------|-------|---------|
| Atento001 | `hFDHNHZwJ9gfzkyFysbn` | atlasAdmin | admin |
| Atento001 | `pKw4ksz8G9PWokhdCnLo` | readWriteAnyDatabase | admin |
| Beta001 | `POhs87c83YyWDH5D` | atlasAdmin | admin |
| Demo001 | `alksmd713asn1308a7` | atlasAdmin | admin |
| Shared001 | `wnvmnDbCz1rgp91O` | atlasAdmin | admin |
| Shared001 | `pZeCmygevVsCXxZ6` | readAnyDatabase | admin |

### Backup Schedules

| Cluster | Hourly | Daily | Weekly | Monthly | Yearly | PIT Window |
|---------|--------|-------|--------|---------|--------|------------|
| App (Atento001) | 6h/7d | 1d/7d | weekly/4w | monthly/12m | yearly/1y | 7d |
| Staging (Beta001) | 6h/2d | 1d/7d | weekly/4w | monthly/12m | — | 2d |
| Poc (Demo001) | 6h/2d | 1d/7d | weekly/4w | monthly/12m | — | 7d |
| Shared (Shared001) | — | 1d/7d | — | — | — | 1d |

### Authentication

Terraform authenticates to MongoDB Atlas via **API Key** (HTTP Digest, no expiration):
- Public Key: `pvgxbddy`
- Role: Organization Owner
- Credentials stored in `.envrc` (gitignored), loaded via `direnv`
- Environment variables: `MONGODB_ATLAS_PUBLIC_KEY`, `MONGODB_ATLAS_PRIVATE_KEY`

## Strategy: Import as-is, then standardize network

**Three-phase approach**:
1. **Phase 1**: Import all existing resources into Terraform state exactly as they are (no changes)
2. **Phase 2**: Standardize network access (remove VPC peering, close 0.0.0.0/0, add NAT Gateway IPs) + backup policies + termination protection
3. **Phase 3**: Standardize cluster names via mongosync migration (create new cluster → sync → cutover → delete old)

**Out of scope**: Project renaming (future effort).

## Implementation — Branch: `feature/import-mongodb-atlas`

### PR 1: MongoDB Atlas Module + Environment Configuration + Imports

**Task 3.1 — Create/finalize MongoDB Atlas module** (`modules/mongodb_atlas/`)

Reusable module following existing patterns. Module already created and validated:
- `main.tf`: `mongodbatlas_project` + `mongodbatlas_advanced_cluster` (provider v2.x syntax)
- `variables.tf`: All input variables (org_id, project/cluster name, tier, disk, autoscaling, users, IPs, peering, backup)
- `outputs.tf`: project_id, cluster_id, connection_string_standard_srv
- `database_users.tf`: Users with for_each, lifecycle ignore_changes on password
- `network.tf`: IP access lists (for_each), network container (count), VPC peering (count)
- `backup.tf`: Backup schedule with dynamic blocks for hourly/daily/weekly/monthly/yearly
- `versions.tf`: required_providers for mongodb/mongodbatlas >= 2.0

**Task 3.2 — Add MongoDB Atlas to each environment**

For each environment directory, add two files:

1. Update `providers.tf` — add `mongodbatlas` provider and required_providers entry:
```hcl
provider "mongodbatlas" {}

# In required_providers block:
mongodbatlas = {
  source  = "mongodb/mongodbatlas"
  version = "~> 2.0"
}
```

2. Create `mongodb.tf` — module call with environment-specific values:
```hcl
module "mongodb" {
  source = "../modules/mongodb_atlas"

  org_id       = "5bca5c89cf09a21bb6f53bc3"
  project_name = "App Shared001"   # Current name (as-is)
  cluster_name = "Shared"          # Current name (as-is)
  cluster_tier = "M20"
  disk_size_gb = 52
  # ... (full config per environment)
}
```

Environments:
- `app-atento-001/mongodb.tf`
- `app-beta-001/mongodb.tf`
- `app-demo-001/mongodb.tf`
- `app-shared-001/mongodb.tf`

**Task 3.3 — Run `terraform init` on each environment**

Each environment needs `terraform init` to download the `mongodbatlas` provider.

**Task 3.4 — Import resources into each environment's state**

Import order per environment (dependencies matter):
1. Project
2. Network container (Shared001 only)
3. Cluster
4. Database users
5. IP access lists
6. VPC peering (Shared001 only)
7. Backup schedule

Import commands per environment:

**app-atento-001/**
```bash
terraform import 'module.mongodb.mongodbatlas_project.this' 68c8474b6729fd188d1544ee
terraform import 'module.mongodb.mongodbatlas_advanced_cluster.this' 68c8474b6729fd188d1544ee-App
terraform import 'module.mongodb.mongodbatlas_database_user.users["hFDHNHZwJ9gfzkyFysbn"]' 68c8474b6729fd188d1544ee-admin-hFDHNHZwJ9gfzkyFysbn
terraform import 'module.mongodb.mongodbatlas_database_user.users["pKw4ksz8G9PWokhdCnLo"]' 68c8474b6729fd188d1544ee-admin-pKw4ksz8G9PWokhdCnLo
terraform import 'module.mongodb.mongodbatlas_project_ip_access_list.entries["34.226.84.227/32"]' 68c8474b6729fd188d1544ee-34.226.84.227%2F32
terraform import 'module.mongodb.mongodbatlas_project_ip_access_list.entries["34.195.63.108/32"]' 68c8474b6729fd188d1544ee-34.195.63.108%2F32
terraform import 'module.mongodb.mongodbatlas_cloud_backup_schedule.this' 68c8474b6729fd188d1544ee-App
```

**app-beta-001/**
```bash
terraform import 'module.mongodb.mongodbatlas_project.this' 64bae502368f7b00e7dfb3cf
terraform import 'module.mongodb.mongodbatlas_advanced_cluster.this' 64bae502368f7b00e7dfb3cf-Staging
terraform import 'module.mongodb.mongodbatlas_database_user.users["POhs87c83YyWDH5D"]' 64bae502368f7b00e7dfb3cf-admin-POhs87c83YyWDH5D
terraform import 'module.mongodb.mongodbatlas_project_ip_access_list.entries["0.0.0.0/0"]' 64bae502368f7b00e7dfb3cf-0.0.0.0%2F0
terraform import 'module.mongodb.mongodbatlas_cloud_backup_schedule.this' 64bae502368f7b00e7dfb3cf-Staging
```

**app-demo-001/**
```bash
terraform import 'module.mongodb.mongodbatlas_project.this' 5f1c9cacf1bcf214d3dd52a2
terraform import 'module.mongodb.mongodbatlas_advanced_cluster.this' 5f1c9cacf1bcf214d3dd52a2-Poc
terraform import 'module.mongodb.mongodbatlas_database_user.users["alksmd713asn1308a7"]' 5f1c9cacf1bcf214d3dd52a2-admin-alksmd713asn1308a7
terraform import 'module.mongodb.mongodbatlas_project_ip_access_list.entries["0.0.0.0/0"]' 5f1c9cacf1bcf214d3dd52a2-0.0.0.0%2F0
terraform import 'module.mongodb.mongodbatlas_cloud_backup_schedule.this' 5f1c9cacf1bcf214d3dd52a2-Poc
```

**app-shared-001/**
```bash
terraform import 'module.mongodb.mongodbatlas_project.this' 5bca5c89cf09a21c475619f6
terraform import 'module.mongodb.mongodbatlas_network_container.this[0]' 5bca5c89cf09a21c475619f6-5f14a54be475e2633c4dc031
terraform import 'module.mongodb.mongodbatlas_advanced_cluster.this' 5bca5c89cf09a21c475619f6-Shared
terraform import 'module.mongodb.mongodbatlas_database_user.users["wnvmnDbCz1rgp91O"]' 5bca5c89cf09a21c475619f6-admin-wnvmnDbCz1rgp91O
terraform import 'module.mongodb.mongodbatlas_database_user.users["pZeCmygevVsCXxZ6"]' 5bca5c89cf09a21c475619f6-admin-pZeCmygevVsCXxZ6
terraform import 'module.mongodb.mongodbatlas_project_ip_access_list.entries["10.254.0.0/16"]' 5bca5c89cf09a21c475619f6-10.254.0.0%2F16
terraform import 'module.mongodb.mongodbatlas_network_peering.this[0]' 5bca5c89cf09a21c475619f6-68c32af33ec6db02f7bbd3c6
terraform import 'module.mongodb.mongodbatlas_cloud_backup_schedule.this' 5bca5c89cf09a21c475619f6-Shared
```

**Task 3.5 — Validate with `terraform plan` per environment**

Each environment must show **zero changes** after import. If plan shows diffs, adjust HCL to match current state exactly.

**Task 3.6 — Update CHANGELOG.md**

**[HOLD POINT]** Pause here and wait for user confirmation before proceeding to Phase 2 (network standardization). Phase 2 makes breaking changes to network access and requires coordination.

### Phase 2: Network Standardization (manual, per environment)

**Task 3.7 — Remove VPC peering from Shared001**

Order: Add IPs BEFORE removing peering.

```bash
cd app-shared-001/
# 1. Update mongodb.tf: add NAT Gateway IPs to access list, keep peering enabled
# 2. terraform apply (adds IPs while peering still active)
# 3. Verify connectivity via application logs
# 4. Update mongodb.tf: set enable_network_peering = false, remove 10.254.0.0/16 entry
# 5. terraform apply (removes peering + container + old access entry)
# 6. Verify AWS peering connection pcx-07ce30a23d5c62aaf is deleted
```

Final access list: `34.195.63.108/32`, `34.226.84.227/32`

**Task 3.8 — Replace 0.0.0.0/0 on Beta001**

```bash
cd app-beta-001/
# 1. Update mongodb.tf: add NAT Gateway IP 3.218.162.113/32, keep 0.0.0.0/0
# 2. terraform apply (adds IP while open access still active)
# 3. Verify connectivity
# 4. Update mongodb.tf: remove 0.0.0.0/0 entry
# 5. terraform apply (removes open access)
```

Final access list: `3.218.162.113/32`

**Task 3.9 — Replace 0.0.0.0/0 on Demo001**

Same procedure as Beta001 but with Production VPC NAT Gateway IPs.

Final access list: `34.195.63.108/32`, `34.226.84.227/32`

**Task 3.10 — Enable termination protection on Atento001**

```bash
cd app-atento-001/
# Update mongodb.tf: termination_protection_enabled = true
# terraform apply
```

**Task 3.11 — Final validation**

Run `terraform plan` on all 4 environments — must show zero changes.

Final access list state:

| Project | Access List IPs | Source |
|---------|----------------|--------|
| Atento001 | `34.195.63.108/32`, `34.226.84.227/32` | Production VPC NAT GWs (no change) |
| Beta001 | `3.218.162.113/32` | Beta VPC NAT GW |
| Demo001 | `34.195.63.108/32`, `34.226.84.227/32` | Production VPC NAT GWs |
| Shared001 | `34.195.63.108/32`, `34.226.84.227/32` | Production VPC NAT GWs (replaces peering) |

### Phase 3: Cluster Name Standardization (via mongosync)

Clusters in MongoDB Atlas cannot be renamed. The strategy is to create new clusters with correct names and migrate data using **mongosync** (MongoDB's cluster-to-cluster sync tool).

#### Target naming

| Project | Current Cluster | Target Cluster |
|---------|----------------|----------------|
| App Atento001 | `App` | `atento-001` |
| App Beta001 | `Staging` | `beta-001` |
| App Demo001 | `Poc` | `demo-001` |
| App Shared001 | `Shared` | `shared-001` |

#### Prerequisites

- MongoDB 6.0+ on both source and destination (all clusters run 7.0 — ok)
- M10+ tier (all clusters are M10 or M20 — ok)
- Destination cluster must be empty

#### Migration procedure per environment

Same zero-downtime pattern used for S3 migration:

```
1. Terraform creates new cluster (same project, same tier/config, standardized name)
2. mongosync connects source → destination, starts continuous sync
3. Verify sync is caught up (lag = 0)
4. Cutover: update MONGODB_URI env var, deploy app pointing to new cluster
5. Stop mongosync
6. Terraform destroys old cluster
7. Terraform state + code cleanup
```

**Order: Beta → Demo → Shared → Atento** (least critical first, largest last)

#### mongosync details

- Standalone binary — runs outside Terraform (not a Terraform resource)
- Supports Atlas-to-Atlas within same project, no restrictions
- No naming constraints between source and destination
- Handles replica sets (all 4 clusters are replica sets)

#### Terraform tasks

**PR (code changes — after all migrations)**

- **Task 3.12**: Create new clusters via Terraform (same config as existing, new names)
- **Task 3.13**: Run mongosync per environment (manual, outside Terraform)
- **Task 3.14**: Cutover — update connection strings, deploy apps
- **Task 3.15**: Destroy old clusters via Terraform
- **Task 3.16**: Clean up Terraform state and code (remove old cluster references)
- **Task 3.17**: Update CHANGELOG.md

---

# PART 4: OpenSearch Domain Standardization — COMPLETED

## Current Situation

Two OpenSearch domains exist with non-standard names, inconsistent versions, and mixed networking:

| Domain | Environment | Engine | Network | Disk | TLS |
|--------|------------|--------|---------|------|-----|
| `elastic-index-2` | Shared | OpenSearch 2.19 | **Public** (no VPC) | 100GB gp3 | Min TLS 1.0 |
| `atento-prd-elasticsearch` | Atento | OpenSearch 3.3 | VPC (Production) | 10GB gp3 | Min TLS 1.2 |

Both: 2x t3.small, zone-aware (us-east-1a + us-east-1b), KMS encryption, node-to-node encryption, fine-grained access control.

### Target

| Domain | Environment | Engine | Network | Disk | TLS |
|--------|------------|--------|---------|------|-----|
| `shared-001` | Shared | OpenSearch 3.3 | VPC (Production, private subnets) | 10GB gp3 | Min TLS 1.2 |
| `atento-001` | Atento | OpenSearch 3.3 | VPC (Production, private subnets) | 10GB gp3 | Min TLS 1.2 |

### Naming convention

AWS services (RDS, OpenSearch, ECS, etc.) require names to start with a lowercase letter — `4shark-*` is invalid. The `4shark` prefix is used **only for S3 buckets**, which require globally unique names. All other resources follow the pattern `{environment}-*` (e.g., `shared-001-cluster`, `atento-001-web-asg`).

OpenSearch domain names: `{environment}` (e.g., `shared-001`, `atento-001`).

### Key differences from current state

1. **Shared moves from public to VPC** — security improvement
2. **Both standardized to OpenSearch 3.3** — latest available version
3. **Shared disk reduced from 100GB to 10GB** — data is ephemeral (TTL 2 days), 100GB was over-provisioned
4. **TLS 1.2 minimum** for both — Shared was allowing TLS 1.0

## Strategy: Recreate (not import)

**Why not import + rename?**
- AWS does not allow renaming OpenSearch domains
- Importing would mean: import → Terraform detects name mismatch → forces replacement → same outcome as recreating, but with more steps
- Data is ephemeral (deal index with 2-day TTL) — nothing to migrate

**Why this is safe:**
- The Rails app has a native fallback: `ELASTIC_INDEX=false` makes the app skip all OpenSearch operations and use direct DB queries for commission metrics
- Zero functional downtime — only performance impact during the migration window (DB queries are slower than OpenSearch queries)

### App configuration (for reference)

| Variable | Purpose |
|----------|---------|
| `ELASTIC_INDEX` | Feature flag: `true` enables OpenSearch, any other value disables it (default: disabled) |
| `ELASTICSEARCH_HOST` | OpenSearch endpoint URL |
| `ELASTICSEARCH_USER` | HTTP basic auth username |
| `ELASTICSEARCH_PASSWORD` | HTTP basic auth password |
| `ELASTIC_INDEX_TTL` | Document TTL in days (default: 2) |

### Compatibility validation

- App gem: `elasticsearch` 7.13.3 — compatible with OpenSearch 3.3
- Requires `override_main_response_version: true` on domain (makes OpenSearch report as ES 7.x to the client)
- All operations are basic CRUD + bool queries — no version-specific features
- Scroll API used in `Expirator` worker is deprecated but still functional

### Network configuration

Both domains use the **Production VPC** (`vpc-0204a1f8b5de51941`, CIDR `10.254.0.0/16`):

| Resource | Value |
|----------|-------|
| VPC | `vpc-0204a1f8b5de51941` (Production) |
| Subnet A | `subnet-043bc50dc26aeabe4` (production-prv-a, us-east-1a) |
| Subnet B | `subnet-0a2a3cf53344bb353` (production-prv-b, us-east-1b) |
| Security Group | Default SG allows all traffic from `10.254.0.0/16` (Production VPC CIDR) |
| KMS Key | `arn:aws:kms:us-east-1:405749097490:key/2e15e5f0-c6ee-4946-a0a2-2a4b86e82f47` |

## Detailed AWS CLI Data (from investigation)

### `elastic-index-2` (Shared) — Full Configuration

| Setting | Value |
|---------|-------|
| Engine | OpenSearch 2.19 |
| Network | **Public** (no VPC) |
| Instances | 2x `t3.small.search`, zone-aware |
| EBS | 100GB gp3 (3000 IOPS, 125 MB/s) |
| TLS | Min TLS 1.0 |
| Encryption | KMS at rest + node-to-node |
| KMS Key | `2e15e5f0-c6ee-4946-a0a2-2a4b86e82f47` |
| Security | Fine-grained access control + internal user DB |
| Logging | 4 log types: search slow, app, audit, index slow |
| Security Group | N/A (public) |
| Subnets | N/A (public) |
| Advanced Options | `override_main_response_version: true`, `fielddata.cache.size: 20` |
| AutoTune | Disabled |
| Off-peak window | 10:00 UTC |

### `atento-prd-elasticsearch` (Atento) — Full Configuration

| Setting | Value |
|---------|-------|
| Engine | OpenSearch 3.3 |
| Network | VPC (Production) |
| Instances | 2x `t3.small.search`, zone-aware |
| EBS | 10GB gp3 (3000 IOPS, 125 MB/s) |
| TLS | Min TLS 1.2 |
| Encryption | KMS at rest + node-to-node |
| KMS Key | `2e15e5f0-c6ee-4946-a0a2-2a4b86e82f47` |
| Security | Fine-grained access control + internal user DB |
| Logging | None |
| Security Group | `sg-0e7cb6a64d4fcc54b` (VPC default, allows `10.254.0.0/16`) |
| Subnets | `subnet-043bc50dc26aeabe4`, `subnet-0a2a3cf53344bb353` |
| Advanced Options | `override_main_response_version: true`, `fielddata.cache.size: 20` |
| AutoTune | Disabled |
| Off-peak window | 00:00 UTC |

## Implementation

### PR 1: OpenSearch Terraform Module + Environment Configuration

**Task 4.1 — Create OpenSearch module** (`modules/opensearch/`)

Following existing module patterns (like `modules/mongodb_atlas/`, `modules/rds_aurora_cluster/`).

**File: `modules/opensearch/versions.tf`**
```hcl
terraform {
  required_version = ">= 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}
```

**File: `modules/opensearch/variables.tf`**

Variables matching the current domain configurations:
- `domain_name` (string, required)
- `engine_version` (string, default `"OpenSearch_3.3"`)
- `instance_type` (string, default `"t3.small.search"`)
- `instance_count` (number, default `2`)
- `zone_awareness_enabled` (bool, default `true`)
- `ebs_volume_size` (number, default `10`)
- `ebs_volume_type` (string, default `"gp3"`)
- `ebs_iops` (number, default `3000`)
- `ebs_throughput` (number, default `125`)
- `vpc_subnet_ids` (list(string), required)
- `vpc_security_group_ids` (list(string), required)
- `kms_key_id` (string, required)
- `tls_security_policy` (string, default `"Policy-Min-TLS-1-2-2019-07"`)
- `advanced_options` (map(string), default with `override_main_response_version`, `fielddata.cache.size`)
- `off_peak_hours` (number, default `0`)
- `off_peak_minutes` (number, default `0`)
- `log_publishing` (map of log type → CloudWatch log group ARN, default `{}`)
- `tags` (map(string), default `{}`)

Note: Credentials are auto-generated by the module (`random_string` for username, `random_password` for password) and stored in SSM Parameter Store as SecureString. Access policy uses `Principal: *` (VPC provides network isolation, fine-grained access control handles auth).

**File: `modules/opensearch/main.tf`**

Single `aws_opensearch_domain` resource with:
- `domain_name = var.domain_name`
- `engine_version = var.engine_version`
- `cluster_config` block (instance type, count, zone awareness, no dedicated master, no warm/cold)
- `ebs_options` block
- `vpc_options` block (subnet_ids, security_group_ids)
- `encrypt_at_rest_options` (KMS)
- `node_to_node_encryption_options` (enabled)
- `domain_endpoint_options` (enforce HTTPS, TLS policy)
- `advanced_security_options` (enabled, internal user DB, auto-generated master user via `random_string` + `random_password`)
- `advanced_options` map
- `off_peak_window_options` block
- `software_update_options` (auto_software_update_enabled = false)
- `access_policies` — JSON policy allowing `es:*` with `Principal: *` (VPC provides network isolation)
- `log_publishing_options` — dynamic block from `var.log_publishing`
- `lifecycle { prevent_destroy = true }`
- `tags`

**File: `modules/opensearch/outputs.tf`**
- `domain_id`
- `domain_arn`
- `domain_endpoint` (the VPC endpoint URL)
- `domain_name`

**Task 4.2 — Add OpenSearch to shared-001** (`app-shared-001/opensearch.tf`)

```hcl
module "opensearch" {
  source = "../modules/opensearch"

  domain_name    = "shared-001"
  engine_version = "OpenSearch_3.3"

  instance_type  = "t3.small.search"
  instance_count = 2

  ebs_volume_size = 10

  vpc_subnet_ids         = ["subnet-043bc50dc26aeabe4", "subnet-0a2a3cf53344bb353"]
  vpc_security_group_ids = ["sg-0e7cb6a64d4fcc54b"]
  kms_key_id             = "arn:aws:kms:us-east-1:405749097490:key/2e15e5f0-c6ee-4946-a0a2-2a4b86e82f47"

  off_peak_hours = 10

  tags = local.tags
}
```

No variables needed — credentials are auto-generated by the module (random_string for username, random_password for password) and stored in SSM Parameter Store as SecureString.

**Task 4.3 — Add OpenSearch to atento-001** (`app-atento-001/opensearch.tf`)

```hcl
module "opensearch" {
  source = "../modules/opensearch"

  domain_name    = "atento-001"
  engine_version = "OpenSearch_3.3"

  instance_type  = "t3.small.search"
  instance_count = 2

  ebs_volume_size = 10

  vpc_subnet_ids         = ["subnet-043bc50dc26aeabe4", "subnet-0a2a3cf53344bb353"]
  vpc_security_group_ids = ["sg-0e7cb6a64d4fcc54b"]
  kms_key_id             = "arn:aws:kms:us-east-1:405749097490:key/2e15e5f0-c6ee-4946-a0a2-2a4b86e82f47"

  tags = local.tags
}
```

No variables needed — same auto-generated credentials approach.

**Task 4.4 — Update CHANGELOG.md**

Add under `[Unreleased] > Added`:
- OpenSearch domains standardized with VPC networking across all environments

### Apply + Migrate (manual, per environment)

**Task 4.5 — `terraform apply` on shared-001 and atento-001**

Creates the new OpenSearch domains. Domain creation takes ~15-20 minutes.

**Task 4.6 — Migrate Shared**

```bash
# === STEP 1: Disable OpenSearch (deploy 1) ===
# Update env var: ELASTIC_INDEX=false
# Deploy shared-001 app
# App continues working with DB queries (no downtime)

# === STEP 2: Enable OpenSearch on new domain (deploy 2) ===
# Update env vars:
#   ELASTICSEARCH_HOST=https://vpc-shared-001-XXXXX.us-east-1.es.amazonaws.com
#   ELASTICSEARCH_USER=<master_user>
#   ELASTICSEARCH_PASSWORD=<master_password>
#   ELASTIC_INDEX=true
# Deploy shared-001 app
# App starts indexing to new domain, metrics use OpenSearch again
```

**Task 4.7 — Migrate Atento**

Same procedure as Shared with `atento-001` domain.

**Task 4.8 — Delete old domains**

After confirming new domains are working:

```bash
# Delete old domains (not managed by Terraform, manual cleanup)
aws opensearch delete-domain --domain-name elastic-index-2 --region us-east-1
aws opensearch delete-domain --domain-name atento-prd-elasticsearch --region us-east-1
```

## Files to create

- `modules/opensearch/versions.tf`
- `modules/opensearch/variables.tf`
- `modules/opensearch/main.tf`
- `modules/opensearch/outputs.tf`
- `app-shared-001/opensearch.tf`
- `app-atento-001/opensearch.tf`

## Files to modify

- `CHANGELOG.md` — new entry

## Execution order

1. Create module `modules/opensearch/` (Task 4.1)
2. Add `opensearch.tf` + variables to both environments (Tasks 4.2, 4.3)
3. Update CHANGELOG (Task 4.4)
4. Commit + PR
5. After merge: `terraform apply` on both environments (Task 4.5 — creates new domains, ~15-20 min)
6. Migrate Shared (Task 4.6 — deploy 1: disable ES → deploy 2: enable on new domain)
7. Migrate Atento (Task 4.7 — same procedure)
8. Delete old domains via AWS CLI (Task 4.8)

## Impact Analysis (post-mortem)

Migration completed with zero downtime. Both environments were migrated with a single deploy (new endpoint + credentials + `ELASTIC_INDEX=true`). No intermediate "disable ES" step was needed — the app connected directly to the new domains. Old domains were deleted after validation.

**Actual degraded performance**: None — direct cutover worked.
**Actual downtime**: Zero.

---

# PART 5: Redis Cloud Import

## Current Situation

The application environments (`app-*`) use **Redis Cloud** (redis.io) for Redis. These databases are currently managed manually via the Redis Cloud console — not in Terraform.

Note: The `integrator-*` environments use **AWS ElastiCache** (already managed in Terraform via `modules/integrator/elasticache.tf`). This part covers only Redis Cloud.

### Authentication

Redis Cloud uses **API Keys** (not OAuth):

| Variable | Description |
|----------|-------------|
| `REDISCLOUD_ACCESS_KEY` | API Account Key |
| `REDISCLOUD_SECRET_KEY` | API User Key |

Keys are generated in: Redis Cloud Console → Access Management → API Keys (tab).

Provider configuration:
```hcl
provider "rediscloud" {}
```

### Terraform Provider

- Provider: `RedisLabs/rediscloud` (v2.11.0, actively maintained)
- Registry: `registry.terraform.io/providers/RedisLabs/rediscloud`

### Key Resources

**IMPORTANT**: All 4Shark subscriptions are **Essentials/Fixed** type, NOT Pro. This requires different Terraform resources:

| Resource | Purpose |
|----------|---------|
| `rediscloud_essentials_subscription` | Manages a Fixed/Essentials subscription |
| `rediscloud_essentials_database` | Manages individual databases within a Fixed/Essentials subscription |

Note: `rediscloud_subscription` and `rediscloud_subscription_database` are for **Pro** subscriptions only and will NOT find Essentials resources.

### Import Workflow

Resources can be imported into Terraform state:

```bash
terraform import rediscloud_essentials_subscription.this <subscription_id>
terraform import rediscloud_essentials_database.this <subscription_id>/<database_id>
```

IDs are numeric, visible in the Redis Cloud Console URL. API endpoint for Essentials: `/v1/fixed/subscriptions` (NOT `/v1/subscriptions` which is Pro-only).

### Import Gotchas

- `password` field causes perpetual diff — use `lifecycle { ignore_changes = [password] }`
- `redis_version` is not settable for Essentials — omit from HCL
- After import, `terraform plan` will show diffs on computed fields — adjust HCL until plan is clean (same workflow as MongoDB Atlas)
- Alerts in HCL must match exactly what exists on the database — extra alerts cause diff

## Strategy: Import as-is, then standardize

Same approach as MongoDB Atlas:
1. **Phase 1**: Discover current Redis Cloud resources (subscriptions, databases, configs)
2. **Phase 2**: Create Terraform module + environment configs matching current state
3. **Phase 3**: Import into Terraform state, validate with `terraform plan`
4. **Phase 4**: Standardize naming and configuration (if applicable)

### Discovery Results (Task 5.1 — DONE)

**Account**: ID 2546083, Payment Method ID 46077 (all subscriptions).

All subscriptions are **Essentials/Fixed** type. 6 subscriptions total, 1 database per subscription. All running Redis 7.4 with AOF every 1 second and replication enabled.

| Environment | Subscription | Sub ID | DB ID | Plan ID | Plan | Protocol | Eviction | Modules | Source IPs |
|---|---|---|---|---|---|---|---|---|---|
| beta | Beta001 | 2857329 | 13447430 | 25696 | RedisFlex 1GB | redis | noeviction | Bloom, JSON | 0.0.0.0/0 |
| demo | Demo001 | 2873292 | 13481226 | 25699 | RedisFlex 2.5GB | redis | noeviction | Bloom, JSON | 0.0.0.0/0 |
| shared | Shared001-Cache | 2873356 | 13481358 | 25702 | RedisFlex 5GB | redis | allkeys-lfu | Bloom, JSON | NAT GW IPs |
| shared | Shared001-Sidekiq | 2882181 | 13500435 | 21516 | Single-Zone 5GB | stack | noeviction | Bloom, JSON, Search, TimeSeries | 0.0.0.0/0 |
| atento | Atento001-Cache | 2873370 | 13481384 | 25702 | RedisFlex 5GB | redis | allkeys-lfu | Bloom, JSON | NAT GW IPs |
| atento | Atento001-Sidekiq | 2882282 | 13500698 | 21516 | Single-Zone 5GB | stack | noeviction | Bloom, JSON, Search, TimeSeries | 0.0.0.0/0 |

**Key observations**:
- Beta and Demo have 1 subscription each (single Redis database)
- Shared and Atento have 2 subscriptions each (Cache + Sidekiq)
- Cache databases use `redis` protocol with `allkeys-lfu` eviction (application cache)
- Sidekiq databases use `stack` protocol with `noeviction` (job queue — RedisStack with Search + TimeSeries)
- 4 out of 6 databases have open access (`0.0.0.0/0`) — only Cache databases on Shared and Atento are restricted to NAT GW IPs

## Implementation

### PR 1: Redis Cloud Module + Environment Configuration + Imports

**Task 5.1 — Discover Redis Cloud resources** — DONE

Inventoried via Redis Cloud API (`/v1/fixed/subscriptions` + `/v1/fixed/subscriptions/{id}/databases`).

**Task 5.2 — Create Redis Cloud module** (`modules/redis_cloud/`) — DONE

Created reusable module with 4 files:
- `versions.tf` — provider requirement (`RedisLabs/rediscloud >= 2.0`)
- `variables.tf` — all configurable parameters (subscription, database, modules, alerts)
- `main.tf` — `rediscloud_essentials_subscription` + `rediscloud_essentials_database` with `prevent_destroy` lifecycle
- `outputs.tf` — subscription_id, database_id, public_endpoint, password (sensitive)

**Task 5.3 — Add Redis Cloud to each environment** — DONE

Updated `providers.tf` (added `rediscloud` provider) and created `redis.tf` in all 4 environments.

**Task 5.4 — Import resources into Terraform state** — DONE

Imported 12 resources (6 subscriptions + 6 databases) across 4 environments.

**Task 5.5 — Validate with `terraform plan` per environment** — DONE

Zero changes on all 4 environments after import. One fix required: Atento Sidekiq had a `connections-limit` alert in HCL that didn't exist on the actual resource — removed to achieve zero diff.

**Task 5.6 — Update CHANGELOG.md** — DONE

### Phase 2: Network Standardization + Alerts — DONE, merged PR #188

Same pattern as MongoDB Atlas Phase 2 — close `0.0.0.0/0` access. Network changes applied via Redis Cloud REST API (`PUT /v1/fixed/subscriptions/{id}/databases/{id}`) due to provider bug (see note below). Alert and `enable_payg_features` changes applied via `terraform apply`.

- [x] **Task 5.7**: Replace `0.0.0.0/0` on Beta with NAT Gateway IP (`3.218.162.113/32`)
- [x] **Task 5.8**: Replace `0.0.0.0/0` on Demo with NAT Gateway IPs (`34.195.63.108/32`, `34.226.84.227/32`)
- [x] **Task 5.9**: Replace `0.0.0.0/0` on Shared-Sidekiq with NAT Gateway IPs (`34.195.63.108/32`, `34.226.84.227/32`)
- [x] **Task 5.10**: Replace `0.0.0.0/0` on Atento-Sidekiq with NAT Gateway IPs (`34.195.63.108/32`, `34.226.84.227/32`)
- [x] **Task 5.11**: Add missing `connections-limit` alert on Atento-Sidekiq
- [x] **Task 5.12**: Fix alert ordering on Demo (datasets-size before connections-limit)
- [x] **Task 5.13**: Set `enable_payg_features = false` explicitly in module, apply on beta and atento to normalize state
- [x] All 4 databases validated via Redis Cloud API — `sourceIps` confirmed restricted, alerts confirmed standardized

#### Provider Bug: `source_ips` DiffSuppressFunc

The `rediscloud` provider (v2.11.0) has a bug in `rediscloud_essentials_database`: the `source_ips` attribute uses a `DiffSuppressFunc` (`suppressIfPaygDisabled`) that suppresses ALL diffs when `enable_payg_features = false` (the default). Since `enable_payg_features = true` is rejected by the API for non-PAYG subscriptions, `source_ips` changes cannot be applied via Terraform. The HCL documents the desired state, but actual enforcement was done via the REST API. The same bug affects: `memory_limit_in_gb`, `support_oss_cluster_api`, `external_endpoint_for_oss_cluster_api`, `enable_database_clustering`, `regex_rules`, `enable_tls`.

---

# Risks and Mitigations

## MongoDB Atlas

| Risk | Mitigation |
|------|-----------|
| **Removing VPC peering on Shared001 disrupts connectivity** | Add IP-based access BEFORE removing peering. Test connectivity. Two-step apply. |
| **Removing `0.0.0.0/0` on Beta/Demo blocks access** | Add correct IPs BEFORE removing open access. Verify NAT GW IPs are stable (EIPs). |
| **Terraform import causes drift detection** | Carefully match HCL to current state. Validate with `terraform plan` per environment. |
| **Service Account permissions too broad** | Service Account scoped to organization with minimal permissions. |
| **Import changes cluster configuration** | Import is read-only. All HCL must match current state exactly. `terraform plan` shows zero changes before any apply. |

## OpenSearch

| Risk | Mitigation |
|------|-----------|
| **New domain creation fails** | No impact — old domains still running, app unchanged |
| **App incompatible with OpenSearch 3.3** | Validated: gem 7.13.3 + `override_main_response_version` is compatible. Both current domains already use this flag |
| **Performance degradation during migration** | Temporary — only while `ELASTIC_INDEX=false`. Deploy happens off-hours, no users accessing |
| **New domain endpoint unreachable from ECS** | Both in same VPC + private subnets + default SG. Test connectivity before deploy 2 |
| **Master user credentials** | Set during `terraform apply`. Store securely, pass via env vars |

## MongoDB Atlas (Cluster Rename via mongosync)

| Risk | Mitigation |
|------|-----------|
| **mongosync fails or lags** | Old cluster still active, app unchanged. Fix mongosync issue and retry. |
| **Data loss during cutover** | mongosync provides continuous sync — cutover only when lag = 0. Verify before switching. |
| **New cluster config mismatch** | Create with identical tier, disk, autoscaling, users, IPs, backup. Validate with `terraform plan`. |
| **Connection string format differs** | Both clusters in same project — SRV format is standard. Update `MONGODB_URI` env var. |
| **Rollback needed after cutover** | Keep old cluster alive until new cluster is validated. Only destroy after confirmation. |

## Redis Cloud

| Risk | Mitigation |
|------|-----------|
| **Import causes drift detection** | Carefully match HCL to current state. Validate with `terraform plan` per environment. **RESOLVED**: All 4 environments validated with zero changes. |
| **Essentials vs Pro resource confusion** | Use `rediscloud_essentials_*` resources, NOT `rediscloud_subscription*`. API endpoint is `/v1/fixed/subscriptions`. **RESOLVED**: Discovered during implementation. |
| **`password` field causes perpetual diff** | Use `lifecycle { ignore_changes = [password] }`. **RESOLVED**: Applied in module. |
| **Alert mismatch causes diff** | Alerts in HCL must exactly match what exists on the database. **RESOLVED**: Atento Sidekiq only had `datasets-size`, not `connections-limit`. |
| **Closing `0.0.0.0/0` blocks Sidekiq access** | Add correct NAT GW IPs BEFORE removing open access. Same approach as MongoDB Atlas. **RESOLVED**: All 4 databases restricted to NAT GW IPs via REST API, validated. |
| **`source_ips` changes not detected by Terraform** | Provider bug: `DiffSuppressFunc` suppresses diffs when `enable_payg_features = false`. Workaround: apply `source_ips` via REST API, keep HCL as documentation of desired state. **RESOLVED**: Applied via API, documented in PLAN.md. |
| **`enable_payg_features` state corruption** | Failed `terraform apply` with `enable_payg_features = true` on beta left `true` in state despite API rejection. **RESOLVED**: Explicitly set `enable_payg_features = false` in module, applied on beta and atento to normalize all states. |

## RDS

| Risk | Mitigation |
|------|-----------|
| **Rename downtime (~13-20 min per DB)** | Schedule during low-traffic windows; order by criticality (least critical first); not all need to be same day |
| **Rename fails mid-way** | No action needed — old identifier still valid, app continues working |
| **Deploy fails after rename** | Must fix forward — old endpoint no longer exists. DB is up with new name, only the app config needs fixing |
| **Endpoint changes** | App must be redeployed with new connection strings AFTER rename completes |
| **`publicly_accessible = false`** | Already applied in PR #177 |
| **State reconciliation errors** | Always run `terraform plan` after import to verify zero changes before proceeding |

---

# Task Summary

## S3 — COMPLETED

- [x] **PR #178** (`feature/standardize-s3-buckets`) — new buckets + replication + IAM
- [x] `terraform apply` on 3 environments
- [x] `aws s3 sync` existing objects (all 3 verified)
- [x] App cutover — all 3 environments deployed with new bucket
- [x] Final `aws s3 sync` — stragglers caught
- [x] **PR #180** (`feature/cleanup-s3-migration`) — replication removed (code + apply), old buckets orphaned, code cleaned up
- [x] **Task 1.7**: Old buckets validated, emptied, and permanently deleted (`4shark-staging`, `4shark-poc`, `4shark-shared`)

## RDS — COMPLETED

### PR 1 (config standardization) — DONE, merged PR #177
- [x] **Task 2.1**: Update RDS module — add monitoring variables
- [x] **Task 2.2**: Standardize beta (deletion protection + monitoring)
- [x] **Task 2.3**: Standardize demo (backup retention)
- [x] **Task 2.4**: Standardize shared (public access + PI retention)
- [x] **Task 2.5**: Standardize atento (monitoring + security + logs)
- [x] **Task 2.6**: Standardize setup (deletion protection + monitoring)
- [x] **Task 2.7**: Update CHANGELOG.md
- [x] `terraform apply` on all 5 environments

### Manual rename (~13-20 min downtime per environment) — ALL DONE
**Order: Beta → Setup → Demo → Shared → Atento**

- [x] Beta: `beta-db` → `beta-001` (RDS standalone) — DONE 2026-02-28
- [x] Setup: `setup-prd-db` → `setup-001` (RDS standalone) — DONE
- [x] Demo: `demo-prd` → `demo-001-cluster`, instance `demo-prd-instance-1` → `demo-001-db-1` (Aurora) — DONE 2026-02-28
- [x] Shared: `production-app-2` → `shared-001-cluster`, instances → `shared-001-db-1`, `shared-001-db-2` (Aurora) — DONE
- [x] Atento: `atento-001-app-cluster-cluster` → `atento-001-cluster`, instances → `atento-001-db-1`, `atento-001-db-2` (Aurora) — DONE

### PR 2 (Terraform code update) — DONE, merged PRs #198, #199
- [x] **Task 2.8**: Update identifiers in Terraform code (Beta + Demo in #198, Shared + Atento + Setup in #199)

## MongoDB Atlas — COMPLETED

### PR 1 (module + environment config + imports) — DONE, merged PR #181
- [x] **Task 3.1**: Create/finalize MongoDB Atlas module (`modules/mongodb_atlas/`)
- [x] **Task 3.2**: Add MongoDB Atlas to each environment (`app-*/mongodb.tf` + `providers.tf`)
- [x] **Task 3.3**: Run `terraform init` on each environment
- [x] **Task 3.4**: Import resources into each environment's state (23 resources across 4 environments)
- [x] **Task 3.5**: Validate with `terraform plan` per environment (zero changes)
- [x] **Task 3.6**: Update CHANGELOG.md

### PR 2 (network standardization) — DONE, merged PR #182
- [x] **Task 3.7**: Remove VPC peering from Shared001 (add IPs first, then remove peering)
- [x] **Task 3.8**: Replace `0.0.0.0/0` on Beta001 with NAT Gateway IP
- [x] **Task 3.9**: Replace `0.0.0.0/0` on Demo001 with NAT Gateway IPs
- [x] **Task 3.10**: Enable termination protection on Atento001
- [x] **Task 3.11**: Final validation — `terraform plan` zero changes on all 4 environments

**Note**: Shared001 VPC peering removal left an orphaned network container in Atlas (ID `5f14a54be475e2633c4dc031`). This is an Atlas platform limitation — containers cannot be deleted while clusters exist in the same region. No cost or impact. Removed from Terraform state via `terraform state rm`.

### PR 3 (backup standardization) — DONE, merged PR #183
- [x] **Task 3.B1**: Simplify backup policies to daily-only 7d retention (Atento001, Beta001, Demo001)
- [x] **Task 3.B2**: Disable Point-in-Time recovery across all environments
- [x] **Task 3.B3**: Delete old snapshots (~2,015 GB / ~$403/month savings)

### Phase 3: Cluster name standardization (via mongosync) — COMPLETED
- [x] **Task 3.12**: Create new clusters via Terraform — DONE (PR #199, all 4 clusters created)
- [x] **Task 3.13a**: Run mongosync Beta + Demo — DONE (committed + stopped)
- [x] **Task 3.13b**: Run mongosync Shared + Atento — DONE (committed + stopped)
- [x] **Task 3.14a**: Cutover Beta + Demo — DONE (MONGO_URL updated, apps deployed)
- [x] **Task 3.14b**: Cutover Shared + Atento — DONE (MONGO_URL updated, apps deployed)
- [x] **Task 3.15a**: Destroy old clusters Beta (Staging) + Demo (Poc) — DONE (deleted via Atlas API)
- [x] **Task 3.15b**: Destroy old clusters Shared + App — DONE (deleted via Atlas API)
- [x] **Task 3.16a**: Terraform cleanup Beta + Demo — DONE (PR #202 merged)
- [x] **Task 3.16b**: Terraform cleanup Shared + Atento — DONE (PR #208 merged, clusters standardized to M10 with M10↔M20 auto-scaling)
- [ ] **Task 3.17**: Update CHANGELOG.md

See separate plan: `mongodb-rename-clusters/PLAN.md` for detailed procedure and progress.

## OpenSearch — COMPLETED

### PR 1 (module + environment config) — DONE, merged PR #185
- [x] **Task 4.1**: Create OpenSearch Terraform module (`modules/opensearch/`)
- [x] **Task 4.2**: Add OpenSearch to shared-001 (`app-shared-001/opensearch.tf`)
- [x] **Task 4.3**: Add OpenSearch to atento-001 (`app-atento-001/opensearch.tf`)
- [x] **Task 4.4**: Update CHANGELOG.md
- [x] `terraform apply` on both environments — domains created

### PR 2 (access policy fix) — DONE, merged PR #186
- [x] Fix access policy to `Principal: *` for VPC + fine-grained access control

### Apply + Migrate (manual) — DONE
- [x] **Task 4.5**: `terraform apply` on shared-001 and atento-001 (domains created + access policy applied)
- [x] **Task 4.6**: Migrate Shared (deploy with new endpoint + credentials, index created)
- [x] **Task 4.7**: Migrate Atento (same procedure, confirmed working)
- [x] **Task 4.8**: Delete old domains (`elastic-index-2`, `atento-prd-elasticsearch`) — deleted via AWS CLI

### Note on SSM credentials
SSM parameters (`/${domain_name}/opensearch/master_user` and `master_password`) are kept intentionally as a credential recovery mechanism. Data is non-sensitive (IDs + monetary values, 2-day TTL), access is internal-only (VPC + IAM), and SSM SecureString provides adequate protection.

## Redis Cloud — COMPLETED

### PR 1 (module + environment config + imports) — DONE, merged PR #187
- [x] **Task 5.1**: Inventory Redis Cloud resources via API (6 Essentials subscriptions, 6 databases)
- [x] **Task 5.2**: Create Redis Cloud Terraform module (`modules/redis_cloud/`)
- [x] **Task 5.3**: Add Redis Cloud to each environment (providers.tf + redis.tf)
- [x] **Task 5.4**: Import resources into Terraform state (12 resources across 4 environments)
- [x] **Task 5.5**: Validate with `terraform plan` per environment (zero changes on all 4)
- [x] **Task 5.6**: Update CHANGELOG.md
- [x] `terraform apply` on all 4 environments — zero changes confirmed

### PR 2 (network standardization + alerts) — DONE, merged PR #188
- [x] **Task 5.7**: Replace `0.0.0.0/0` on Beta with NAT Gateway IP (via REST API)
- [x] **Task 5.8**: Replace `0.0.0.0/0` on Demo with NAT Gateway IPs (via REST API)
- [x] **Task 5.9**: Replace `0.0.0.0/0` on Shared-Sidekiq with NAT Gateway IPs (via REST API)
- [x] **Task 5.10**: Replace `0.0.0.0/0` on Atento-Sidekiq with NAT Gateway IPs (via REST API)
- [x] **Task 5.11**: Add missing `connections-limit` alert on Atento-Sidekiq
- [x] **Task 5.12**: Fix alert ordering on Demo
- [x] **Task 5.13**: Set `enable_payg_features = false` explicitly in module
- [x] `terraform apply` on beta and atento — state normalized
- [x] All 4 databases validated via Redis Cloud REST API

---

# PART 6: KeyCloak (auth-001) Standardization

## Context

The KeyCloak SSO cluster was imported into Terraform via PR #189 as-is, preserving all existing names. The infrastructure runs in **sa-east-1** (unlike all other environments in us-east-1) and uses **ECS Fargate** (unlike other environments that use EC2). All resources use ad-hoc naming (`4shark-keycloak`, `keycloak-*`, camelCase mixed with kebab-case) instead of the standard `{environment}-*` pattern.

This part standardizes naming and configuration to match the patterns established in `app-beta-001`, `app-shared-001`, and the shared modules (`ecs_cluster`, `ecs_service`, `ecr`).

## Current Situation — Naming Inventory

### Resources with non-standard names

| Resource Type | Current Name | Standard Name | File |
|--------------|-------------|---------------|------|
| ECS Cluster | `4shark-keycloak` | `auth-001-cluster` | `ecs.tf` |
| Service Discovery Namespace | `4shark-keycloak` | `auth-001-cluster` | `ecs.tf` |
| Task Definition Family | `auth-001-task` | `auth-001-web` | `ecs.tf` |
| Container Name | `4shark-auth-001` | `auth-001-web` | `ecs.tf` |
| IAM Role | `ecsTaskExecutionRole-keycloak` | `auth-001-ecs-task-execution-role` | `iam.tf` |
| IAM Policy | `keycloak-policy` | `auth-001-ecs-task-policy` | `iam.tf` |
| ECR Repository (standalone) | `4shark-keycloak` | `auth-001-app` or deprecate | `ecr.tf` |
| ECR Repository (clustered) | `4shark-keycloak-clustered` | `auth-001-app` | `ecr.tf` |
| CloudWatch Log Group | `/ecs/4shark-keycloak-task` | `/ecs/auth-001-web` | `logs.tf` |
| Secrets Manager | `auth-001-sm` | OK (already follows pattern) | `secrets.tf` |
| ALB | `auth-001` | OK | `alb.tf` |
| Target Group | `auth-001` | OK | `alb.tf` |
| RDS Identifier | `auth001` | `auth-001` (add hyphen) | `rds.tf` |
| RDS Subnet Group | `default-vpc-0bdc76f3b391694dd` | `auth-001` | `rds.tf` |
| Security Group (ECS) | `auth` | `auth-001-ecs-sg` | `security_groups.tf` |
| Security Group (RDS) | `auth-rds` | `auth-001-rds-sg` | `security_groups.tf` |
| VPC | `management` | OK (standalone VPC, not environment-specific) | `vpc.tf` |

### Resources already following standard

- ALB: `auth-001`
- Target Group: `auth-001`
- ECS Service: `auth-001`
- Secrets Manager: `auth-001-sm`
- Listener tags: `auth-001`

### Configuration issues (non-naming)

| Issue | Current | Standard |
|-------|---------|----------|
| Security Group descriptions | Portuguese (`"Libera acesso ao keycloak"`, `"libera acesso ao postgres"`) | English |
| CloudWatch Log Group retention | Not set (never expires) | Should have retention policy (e.g., 30 days) |
| RDS deletion_protection | `false` | Should be `true` for production |
| RDS performance_insights | `false` | Should evaluate enabling |
| RDS monitoring_interval | `0` (disabled) | Should evaluate Enhanced Monitoring |
| ECS platform_version | `1.4.0` | Should be `LATEST` |
| ECR scan_on_push | `false` | Should be `true` |
| IAM Policy | Overly broad S3 permissions (`s3:*` on resource, wildcard S3 list permissions) | Least privilege |
| ECS assign_public_ip | `true` (in private subnets) | Should be `false` (has NAT gateway) |

## Implementation Strategy

**Key difference from other PARTs**: Most renames here are **not zero-downtime**. Renaming ECS clusters, task definitions, IAM roles, ECR repos, and log groups requires destroy+recreate or migration procedures. The approach is to coordinate all renames in a single maintenance window to minimize total downtime.

### Risk Assessment

| Resource | Rename Method | Downtime | Risk |
|----------|--------------|----------|------|
| ECS Cluster | Destroy + recreate (no rename API) | **YES** — service goes down during migration | HIGH |
| Task Definition Family | Register new family, update service | **Brief** — during deployment | MEDIUM |
| Container Name | Update task definition | **Brief** — during deployment | LOW |
| IAM Role | Create new → update references → delete old | **None** if done correctly | MEDIUM |
| IAM Policy | Create new → attach → detach old → delete old | **None** if done correctly | LOW |
| ECR Repository | Create new → retag images → update references → delete old | **None** — images retagged before switch | MEDIUM |
| CloudWatch Log Group | Create new → update references (old logs remain) | **None** | LOW |
| RDS + DB Subnet Group | Create new DB + subnet group with correct names, sync, cutover | **YES** — sync + cutover | HIGH |
| Security Groups | Cannot rename — create new, migrate references, delete old | **None** if done correctly | MEDIUM |

### Execution Order

Given the dependencies and risk profile, the implementation should follow this order:

1. **PR 1 — Zero-downtime renames** (IAM, ECR, Log Group, Security Groups, Config fixes) ✓
2. **PR 2 — ECS Cluster + Service migration** (zero downtime, blue/green) ✓
3. **PR 3 — RDS + DB Subnet Group standardization** (create new DB + sync + cutover, Sunday maintenance window) ✓

## PR 1: Zero-Downtime Changes — Branch: `feature/standardize-auth-001-phase1`

### Task 6.1: IAM Role and Policy standardization

Create new role and policy with standard names, update references, remove old ones.

**New resources:**
- IAM Role: `auth-001-ecs-task-execution-role`
- IAM Policy: `auth-001-ecs-task-policy`

**Policy cleanup**: Remove overly broad S3 permissions. The KeyCloak task only needs:
- `secretsmanager:GetSecretValue` on its specific secret ARNs
- `kms:Decrypt` on specific KMS keys
- `logs:CreateLogStream`, `logs:PutLogEvents` on its log group
- Standard ECS task execution permissions (via managed policy)

**Procedure:**
1. Create new IAM role + policy in Terraform
2. Update `aws_ecs_task_definition` to reference new role
3. Deploy new task definition revision
4. After service stabilizes, remove old role + policy
5. `terraform state rm` old resources, `terraform apply`

### Task 6.2: ECR Repository standardization

Create new ECR repo with standard name, retag existing images.

**New resource:**
- ECR Repository: `auth-001-app` (replaces `4shark-keycloak-clustered`, the active one)

**Procedure:**
1. Create `auth-001-app` ECR repository in Terraform (with `scan_on_push = true`)
2. Retag latest images from `4shark-keycloak-clustered` to `auth-001-app` using `docker pull` + `docker tag` + `docker push` (or `aws ecr batch-get-image` + `aws ecr put-image` for tagless copy)
3. Update task definition to reference new ECR repo URL
4. Deploy new task definition revision
5. Evaluate if `4shark-keycloak` (standalone, unused) can be deleted
6. Remove old ECR repos from Terraform

### Task 6.3: CloudWatch Log Group standardization

Create new log group with standard name and retention policy.

**New resource:**
- Log Group: `/ecs/auth-001-web` with `retention_in_days = 30`

**Procedure:**
1. Create new log group in Terraform
2. Update task definition `logConfiguration` to reference new log group
3. Deploy new task definition revision
4. Old log group (`/ecs/4shark-keycloak-task`) can be deleted later (or kept for historical logs)

### Task 6.4: Security Group standardization

Create new security groups with standard names and English descriptions.

**New resources:**
- Security Group: `auth-001-ecs-sg` (description: "ECS tasks security group for auth-001")
- Security Group: `auth-001-rds-sg` (description: "RDS access security group for auth-001")

**Procedure:**
1. Create new security groups with same rules
2. Update ECS service `network_configuration` to reference new SG
3. Update RDS `vpc_security_group_ids` to reference new SG
4. Apply — ECS will redeploy tasks with new SG, RDS applies immediately
5. Remove old security groups

### Task 6.5: Configuration fixes (non-naming)

Apply in the same PR:
- Set `assign_public_ip = false` on ECS service (tasks are in private subnets with NAT)
- Set `platform_version = "LATEST"` on ECS service
- Set `deletion_protection = true` on RDS
- Set `retention_in_days = 30` on new log group (done in Task 6.3)
- Set `scan_on_push = true` on new ECR repo (done in Task 6.2)

### Task 6.7: Update CHANGELOG.md

### Task 6.8: `terraform plan` — verify changes before apply

---

## PR 2: ECS Cluster Migration — Branch: `feature/standardize-auth-001-phase2` — COMPLETED

**Completed 2026-03-01 via PR #206. Zero downtime achieved using blue/green approach.**

### What was done

Used a 3-phase blue/green migration instead of the originally planned maintenance window approach:

1. **Phase 1 — Stand up new infra alongside old**: Created new cluster `auth-001-cluster`, namespace, task definition (`auth-001-web`), service, and log group (`/ecs/auth-001-web`) in parallel with old resources. Both services registered targets in the same ALB target group. IAM temporarily allowed both log groups.
2. **Phase 2 — Remove old infra**: Removed old cluster `4shark-keycloak`, service, namespace, task definition, and log group `/ecs/auth-001`. ALB drained old targets gracefully (300s deregistration delay).
3. **Phase 3 — Rename resources + state mv**: Renamed Terraform resource identifiers from `.new` back to original names (`.keycloak`, `.auth_001`, `.web`). Ran `terraform state mv` for all 6 resources. `terraform plan` confirmed zero changes. Committed clean diff.

### Result
- `terraform plan`: no changes
- KeyCloak accessible at `https://auth-001.app4shark.com/auth` (HTTP 303)
- ECS console: `auth-001-cluster` with 2 healthy tasks
- ALB target group: 2/2 healthy targets
- CloudWatch logs flowing to `/ecs/auth-001-web`
- **Zero downtime** — no maintenance window needed

---

## PR 3: RDS + DB Subnet Group Standardization — Branch: `feature/standardize-auth-001-phase3` — COMPLETED

**Completed 2026-03-02 via PR #209.**

### Task 6.12: Create new RDS instance and DB Subnet Group

Create a new RDS instance and DB Subnet Group, both with correct names (`auth-001`). Sync data from the current instance and cutover.

> **Why not just rename?** RDS supports in-place rename of the identifier (used for beta, demo, shared, atento). However, auth-001 also needs to change its DB Subnet Group from `default-vpc-0bdc76f3b391694dd` to `auth-001`. AWS does not allow moving an instance to a different subnet group within the same VPC (`InvalidVPCNetworkStateFault`), so a new instance must be created.

**Current instance:**
- Identifier: `auth001`
- Endpoint: `auth001.c8jdkpg7fpd1.sa-east-1.rds.amazonaws.com`
- Engine: Postgres 15.12, db.t3.small, Multi-AZ
- Storage: 200 GB gp3 allocated, **<1 GB actual data**
- Subnet Group: `default-vpc-0bdc76f3b391694dd` (mixed public/private subnets)
- Security Group: `auth-001-rds-sg` (ingress: VPC 10.255.0.0/16 on 5432)
- Deletion protection: ON
- Connection string in `ecs.tf:94`: `KC_DB_URL = "jdbc:postgresql://auth001.c8jdkpg7fpd1.sa-east-1.rds.amazonaws.com:5432/keycloak"`

**Target instance:**
- Identifier: `auth-001`
- Storage: **20 GB gp3** (minimum, sufficient for <1 GB data)
- Subnet Group: `auth-001` (private subnets: `subnet-03320c13f3efc36ce` sa-east-1a, `subnet-0d7d244e85dcb5afb` sa-east-1b)
- All other settings identical (db.t3.small, Multi-AZ, Postgres 15.12, same SG, same KMS key)

**Procedure:**

Phase 1 — Prepare (zero downtime, old DB still serving):
1. Disable deletion protection on `auth001` via AWS CLI
2. Create new DB Subnet Group `auth-001` with private subnets (sa-east-1a + sa-east-1b)
3. Create new RDS instance `auth-001` (db.t3.small, Multi-AZ, 20 GB gp3, same SG/KMS/params)
4. Wait for instance available (~10-15 min)
5. `pg_dump` from `auth001` → `pg_restore` to `auth-001` (<1 GB, ~2-3 min)

Phase 2 — Cutover (**START OF DOWNTIME**):
6. Update `KC_DB_URL` in `ecs.tf` with new endpoint
7. Deploy (ECS rolling update) — KeyCloak reconnects to new DB
8. Validate KeyCloak accessible at `https://auth-001.app4shark.com/auth`

Phase 3 — Cleanup:
9. Delete old instance `auth001` via AWS CLI
10. Delete old subnet group `default-vpc-0bdc76f3b391694dd`
11. Terraform state manipulation:
    - `terraform state rm aws_db_instance.auth001` (old instance gone)
    - `terraform state rm aws_db_subnet_group.default` (old subnet group gone)
    - `terraform import aws_db_instance.auth001 auth-001` (import new instance)
    - `terraform import aws_db_subnet_group.default auth-001` (import new subnet group)
12. Update Terraform code: identifier, subnet group name, subnet_ids, allocated_storage
13. `terraform plan` — verify zero changes
14. Commit and PR

**Acceptable data loss:** Writes between pg_dump (step 5) and deploy (step 7) — limited to new device registrations on the Setup app. Very low traffic, negligible impact.

### Time estimate

| Step | Estimate | Downtime? |
|------|----------|-----------|
| Disable deletion protection | ~1 min | No |
| Create DB Subnet Group | ~1 min | No |
| Create new RDS instance (db.t3.small, Multi-AZ) | ~10-15 min | No |
| pg_dump/pg_restore (<1 GB) | ~2-3 min | No |
| Update KC_DB_URL + deploy | ~5 min | **YES** |
| Validation | ~2 min | No |
| Delete old instance + cleanup | ~5 min | No |

**Total: ~25-30 min. Downtime: ~5-10 min (deploy only).**

### Task 6.13: Validate RDS standardization
- `terraform plan` shows zero changes
- KeyCloak is accessible and connecting to new database
- RDS console shows `auth-001` identifier with `auth-001` subnet group
- New instance using private subnets only

### Task 6.14: Update CHANGELOG.md

---

## Task Summary

### PR 1 — Zero-downtime (no maintenance window needed) ✓ — merged PR #191
- [x] **Task 6.1**: Standardize IAM role and policy names + least-privilege cleanup
- [x] **Task 6.2**: Standardize ECR repository name + enable scan_on_push
- [x] **Task 6.3**: Standardize CloudWatch Log Group name + set retention
- [x] **Task 6.4**: Standardize Security Group names + English descriptions
- [x] **Task 6.5**: Configuration fixes (assign_public_ip, platform_version, deletion_protection)
- [x] **Task 6.7**: Update CHANGELOG.md
- [x] **Task 6.8**: `terraform plan` — verify all changes

### PR 2 — ECS Cluster migration (zero downtime, blue/green) ✓ — merged PR #206
- [x] **Task 6.9**: Migrate ECS cluster from `4shark-keycloak` to `auth-001-cluster`
- [x] **Task 6.10**: Validate migration (zero drift, app healthy)
- [x] **Task 6.11**: Update CHANGELOG.md

### PR 3 — RDS + DB Subnet Group standardization (Sunday maintenance window)
- [ ] **Task 6.12**: Create new RDS instance `auth-001` + DB Subnet Group `auth-001`, sync and cutover
- [ ] **Task 6.13**: Validate standardization (zero drift, app healthy)
- [ ] **Task 6.14**: Update CHANGELOG.md
