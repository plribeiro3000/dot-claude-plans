# SPIKE — Migrating Integrator MongoDB from EC2 to Managed Service

**Conducted by:** Paulo Ribeiro
**Date:** 2026-02-23
**Status:** Abandoned — cost prohibitive
**Project:** terraform (integrator environments)

---

## Goal

Determine whether migrating the Integrator's self-managed MongoDB clusters (6 customer environments on EC2) to a managed service (AWS DocumentDB or MongoDB Atlas) is technically feasible and cost-justified, given that the team has no time for operational tasks (patching, backups, monitoring, upgrades) and the current MongoDB version (4.4, installed via Ansible role `4shark.mongodb` using apt) has been EOL since February 2024.

---

## Method

- Analyzed the current infrastructure setup across all 6 environments (instance types, storage, networking, costs)
- Audited the Integrator application's MongoDB usage (65 models, 10 indexes, 6 aggregation pipelines, operators used)
- Evaluated DocumentDB 5.0 compatibility against the application's actual usage patterns
- Researched MongoDB Atlas pricing, Terraform support, networking options, and migration paths
- Compared costs across all options (EC2, DocumentDB single/HA, Atlas M10/M20)
- Assessed migration feasibility given MongoDB 4.4 version constraints

---

## Evidence

### Current Infrastructure (Per Environment)

All 6 environments use the same Terraform module (`modules/integrator`):

#### MongoDB EC2 ReplicaSet (3 nodes)

| Node | Role | Instance Type | Storage | Subnet |
|------|------|---------------|---------|--------|
| mongo000 | Arbiter | t3.micro | 20 GB gp2 | prv-a (sa-east-1a) |
| mongo001 | Primary | t3.small | 60 GB gp2 | prv-b (variable AZ) |
| mongo002 | Secondary | t3.small | 60 GB gp2 | prv-a (sa-east-1a) |

- **AMI:** Ubuntu (`ami-0bd91caaa9bc42cf3`), shared across all environments
- **Lifecycle:** `ignore_changes = [ami, user_data, user_data_base64]` (Ansible manages post-provisioning)
- **EBS:** `delete_on_termination = false` (volumes persist)
- **Backups:** None configured
- **Monitoring:** None configured
- **DNS:** Route53 internal records at `{client}-mongo00X.4shark.internal` (TTL 60s)

#### Other Components (Per Environment)

- **ElastiCache Redis:** 1 node, Redis 7.1, `cache.t2.small` (atento-br uses `cache.t3.medium`)
- **App Servers:** 1-2 EC2 instances (t3.small or t3.medium), provisioned via Ansible
- **VPN:** Site-to-site IPSec to each customer network
- **VPC Peering:** With management VPC (`vpc-0bdc76f3b391694dd`)

#### Environments

| Environment | VPC CIDR | Zone B | App Servers | Redis |
|-------------|----------|--------|-------------|-------|
| almaviva | 10.1.0.0/24 | sa-east-1a | 2x t3.medium | cache.t2.small |
| aster-maquinas | 10.1.4.0/24 | sa-east-1a | 2x t3.small | cache.t2.small |
| atento-br | 10.12.255.0/24 | sa-east-1c | 1x t3.medium | cache.t3.medium |
| commcenter | 10.1.3.0/24 | sa-east-1c | 2x t3.small | cache.t2.small |
| maqnelson | 10.1.2.0/24 | sa-east-1a | 2x t3.medium | cache.t2.small |
| redebrasil | 10.1.1.0/24 | sa-east-1a | 1x t3.medium | cache.t2.small |

### Application MongoDB Usage Analysis

**Stack:** Ruby 3.4.1, Rails 8.0.4, Mongoid (latest)

#### Models

65 MongoDB models total:
- **Resource** (base class) → Client, User, TableLocks (polymorphic inheritance)
- **Collection** (base class) → 14 specialized collection types with custom `store_in`
- **ExternalApplication**, **ApplicationProgrammingInterface**, **Job**, **ApiRequest**, etc.
- Extensive use of `embeds_many`/`embedded_in` (denormalization)
- `has_many`/`belongs_to` (normalized references)
- State machines via `state_machines-mongoid`

#### Indexes (10 declared)

All indexes use `background: true`. One unique index on `ExternalApplication.identifier`. Multiple compound indexes including dotted notation for nested fields (e.g., `imports.job_id`).

#### Aggregation Pipelines (6 total)

| Location | Stages Used | Purpose |
|----------|-------------|---------|
| Collection.job_resource_quantity | $match, $unwind, $group, $sum | Count resources per job |
| Collection.find_raw_object | $match, $project, $filter, $unwind, $replaceRoot | Find single raw object without loading full array |
| Collection.pair_ids_for | $match, $unwind, $project, $toString | Extract (collection_id, raw_object_id) pairs |
| Resource::StatisticAggregator | $match, $unwind, $project, $group, $sum, $push, $cond | Calculate success/failure statistics (uses `allow_disk_use: true`) |
| Resource::ErrorsAggregator | $match, $unwind, $project, $group, $addToSet, $nin | Aggregate failed requests by error pattern |
| Import.find_request | $match, $unwind, $project | Find specific request in nested imports |

#### Operators Used

`$match`, `$unwind`, `$project`, `$group`, `$filter`, `$replaceRoot`, `$sum`, `$push`, `$addToSet`, `$cond`, `$eq`, `$ne`, `$nin`, `$and`, `$not`, `$map`, `$arrayElemAt`, `$toString`

#### Features NOT Used

Text search, geospatial queries, change streams, transactions, map-reduce, `$lookup` (joins), capped collections, TTL indexes, wildcard indexes, `$expr`, `$where`

### Option 1: Keep on EC2 (Current)

#### Cost Per Environment

| Component | Type | Monthly Cost |
|-----------|------|-------------|
| Arbiter | t3.micro | $12.26 |
| Primary | t3.small | $24.53 |
| Secondary | t3.small | $24.53 |
| EBS Arbiter | 20 GB gp2 | $3.80 |
| EBS Primary | 60 GB gp2 | $11.40 |
| EBS Secondary | 60 GB gp2 | $11.40 |
| **Total** | | **~$88/month** |

**Total (6 environments): ~$528/month**

#### Pros

- Cheapest option by far
- Already working and configured
- Full MongoDB compatibility (it IS MongoDB)
- No migration effort needed

#### Cons

- MongoDB 4.4 is EOL (since Feb 2024) — security risk
- No automated backups — risk of data loss
- No monitoring — blind to issues until they explode
- Manual patching and upgrades via Ansible
- Operational burden on a team with no time for it
- Single point of failure (no automatic failover beyond basic replica set)

### Option 2: AWS DocumentDB

#### What It Is

DocumentDB is an AWS-managed database that implements the MongoDB wire protocol on a proprietary storage engine (Aurora-based). It is NOT MongoDB — it reimplements the API with known limitations.

#### Compatibility with Integrator

All aggregation operators used by the Integrator are supported in DocumentDB 5.0+. The application would work, but requires one mandatory change:

**`retryWrites=false` must be configured in the connection string.**

Retryable writes is a MongoDB 3.6+ mechanism where the driver automatically retries a write operation once if it fails due to a network error. Modern MongoDB drivers (4.2+) enable this by default. DocumentDB does not support the underlying `txnNumber` tracking mechanism — if `retryWrites` is not explicitly disabled, every write operation fails with: `"Unrecognized field: 'txnNumber'"`.

Setting `retryWrites=false` has no impact on normal operation (performance, data integrity). The risk is during network failures or DocumentDB failover (~30 seconds): without automatic retry, the application receives the error and must handle it. For the Integrator's batch processing model, this is acceptable — failed jobs can be reprocessed.

Configuration in `mongoid.yml`:
```yaml
options:
  retry_writes: false
```

#### Instance Types

DocumentDB does NOT offer `db.t3.small`. The smallest available instances are:
- `db.t3.medium` (2 vCPU, 4 GiB RAM) — $0.16/hr in sa-east-1
- `db.t4g.medium` (2 vCPU, 4 GiB RAM, Graviton2) — $0.1552/hr in sa-east-1

#### Cost Per Environment

| Setup | Compute | Storage | I/O | Backup | Total |
|-------|---------|---------|-----|--------|-------|
| 1 instance (no HA) | 1x db.t4g.medium = $113 | ~$2 | ~$5-20 | included | **~$120-135** |
| 2 instances (with HA) | 2x db.t4g.medium = $227 | ~$2 | ~$5-20 | included | **~$234-249** |

#### Total (6 environments)

| Setup | Monthly Cost | vs EC2 |
|-------|-------------|--------|
| 1 instance (no HA) | ~$720-810 | +37% to +54% |
| 2 instances (with HA) | ~$1,404-1,494 | +166% to +183% |

#### Pros

- Fully managed (patches, backups, monitoring included)
- Automatic failover (with 2+ instances)
- Point-in-time recovery (PITR) included
- Storage auto-scales, replicated 6x across 3 AZs
- No application code changes needed (only connection config)

#### Cons

- **Not real MongoDB** — API emulation with known gaps
- Requires `retryWrites=false` configuration
- Smallest instance (t3.medium) is larger than current t3.small
- 1 instance setup: +37% cost with no HA
- 2 instance setup: +166% cost — nearly 3x
- TLS mandatory (additional config needed)
- No `db.t3.small` available — forced upsize

#### Additional Limitations (Not Affecting Integrator)

- No capped collections, map-reduce, GridFS
- `$lookup` limited to equality matches only
- No `$expr`, `$where`, `$text` operators
- No causal consistency, no retryable writes
- Index builds: only 1 per collection at a time

### Option 3: MongoDB Atlas (mongodb.com)

#### What It Is

MongoDB Atlas is the official managed MongoDB service from MongoDB Inc. It runs real MongoDB on cloud infrastructure. The 4Shark `app` project already uses Atlas (managed outside Terraform, likely via the Atlas UI).

#### Terraform Support

Official provider maintained by MongoDB Inc.:
- **Provider:** `mongodb/mongodbatlas` v2.7.0 (Feb 2026)
- **Maturity:** High — 71 resources, verified by HashiCorp
- **Authentication:** Programmatic API keys (public_key + private_key)

Available resources include: `mongodbatlas_advanced_cluster`, `mongodbatlas_network_peering`, `mongodbatlas_privatelink_endpoint`, `mongodbatlas_database_user`, `mongodbatlas_cloud_backup_schedule`, `mongodbatlas_project_ip_access_list`, `mongodbatlas_alert_configuration`, and 64 more.

#### Equivalent Tier

The current t3.small (2 GiB RAM) maps to Atlas **M10** (2 GB RAM, 2 vCPU, 10 GB storage included, up to 120 GB).

**Key difference:** Atlas does not use arbiters. A replica set has 3 data-bearing nodes, all managed automatically. The price is per node.

#### Cost Per Environment

Atlas pricing for sa-east-1 has a ~40% premium over us-east-1 (estimated, exact values should be confirmed via [MongoDB Pricing Calculator](https://www.mongodb.com/pricing/calculator)).

| Tier | Per Node/month | 3-Node Replica Set/month |
|------|---------------|-------------------------|
| M10 (2 GB RAM) | ~$82 | **~$245** |
| M20 (4 GB RAM) | ~$204 | **~$613** |

#### Total (6 environments)

| Tier | Monthly Cost | vs EC2 |
|------|-------------|--------|
| M10 | ~$1,470 | +$942/month (~2.8x) |
| M20 | ~$3,678 | +$3,150/month (~7x) |

#### Networking

Two options for connecting Atlas to existing integrator VPCs:

**VPC Peering** (simpler):
- Atlas creates its own VPC, peers with your VPC
- Terraform resources: `mongodbatlas_network_container`, `mongodbatlas_network_peering`, `aws_vpc_peering_connection_accepter`, `aws_route`
- Limitation: same-region only, CIDRs cannot overlap

**AWS PrivateLink** (recommended for production):
- Unidirectional connection, no CIDR management
- Terraform resources: `mongodbatlas_privatelink_endpoint`, `aws_vpc_endpoint`, `mongodbatlas_privatelink_endpoint_service`

#### Migration

MongoDB 4.4 is too old for Atlas Live Migration (requires 6.0.8+). The `mongomirror` tool (supports 2.6+) reached EOL in July 2025.

**Recommended approach:** `mongodump`/`mongorestore` — works with all MongoDB versions, suitable for datasets under 300 GB, requires downtime window.

#### Pros

- **Real MongoDB** — full compatibility, zero application changes
- Consistency with the `app` project (already on Atlas)
- No `retryWrites` or TLS workarounds needed
- Automated backups, monitoring, patching, scaling included
- Performance Advisor with automatic index recommendations
- Upgrade path to MongoDB 7.0/8.0 built-in
- Mature Terraform provider (71 resources)

#### Cons

- **~2.8x more expensive** than EC2 (M10 tier)
- Atlas charges per data node (3 nodes vs current 2 data + 1 arbiter)
- New Terraform provider to configure (API keys, org setup)
- sa-east-1 pricing has ~40% regional premium
- Exact pricing requires confirmation via pricing calculator

### Cost Comparison Summary

| Option | Per Environment | 6 Environments | vs Current |
|--------|----------------|----------------|------------|
| **EC2 (current)** | ~$88 | **~$528** | baseline |
| **DocumentDB (1 inst, no HA)** | ~$128 | ~$768 | +$240 (+45%) |
| **DocumentDB (2 inst, HA)** | ~$241 | ~$1,446 | +$918 (+174%) |
| **Atlas M10** | ~$245 | ~$1,470 | +$942 (+178%) |
| **Atlas M20** | ~$613 | ~$3,678 | +$3,150 (+596%) |

### Terraform Files Reference

#### Module (shared across all environments)

- `modules/integrator/main.tf` — VPC, subnets, internet gateway, NAT gateway
- `modules/integrator/mongodb.tf` — 3 EC2 instances (arbiter, primary, secondary)
- `modules/integrator/elasticache.tf` — Redis cluster
- `modules/integrator/app.tf` — Application servers
- `modules/integrator/security.tf` — Security groups
- `modules/integrator/dns.tf` — Route53 internal records
- `modules/integrator/peering.tf` — VPC peering with management
- `modules/integrator/routing.tf` — Route tables
- `modules/integrator/vpn.tf` — Site-to-site VPN
- `modules/integrator/variables.tf` — All variables with defaults
- `modules/integrator/outputs.tf` — Exported values

#### Environments (each contains `main.tf` + `providers.tf`)

- `integrator-almaviva/`
- `integrator-aster-maquinas/`
- `integrator-atento-br/`
- `integrator-commcenter/`
- `integrator-maqnelson/`
- `integrator-redebrasil/`

#### Application Config

- `integrator/config/mongoid.yml` — MongoDB connection (URI from env var `MONGODB`)
- `integrator/lib/application_configuration.rb` — Reads `MONGODB` env var

#### Ansible

- `ansible/roles/4shark.mongodb/` — Installs MongoDB 4.4 via apt

---

## Conclusions

- **The cost is prohibitive.** All managed options at minimum nearly double the infrastructure cost, with Atlas and DocumentDB HA setups approaching 3x. For 6 environments running a batch integration workload that does not require 99.99% uptime, paying an extra $900+/month for managed services is not justified.
- **DocumentDB is technically compatible** with the Integrator — all aggregation operators are supported, and the only required change is setting `retryWrites=false`. However, it is not real MongoDB and introduces API emulation risks.
- **Atlas is the cleanest option technically** (real MongoDB, zero code changes, consistent with the `app` project) but is the most expensive at ~2.8x current costs.
- **MongoDB 4.4 EOL is the real urgent problem.** The version has been unsupported for over 2 years. This is a security risk regardless of hosting choice.

**Decision: Stay on EC2.** The immediate priority should be upgrading MongoDB 4.4 to a supported version and implementing basic operational hygiene (automated backups, monitoring) on the existing EC2 infrastructure.

---

## Next Steps

1. Upgrade MongoDB from 4.4 (EOL) to a supported version on the existing EC2 infrastructure
2. Implement automated backups for all 6 environments
3. Add basic monitoring/alerting for MongoDB health
4. No action needed on managed service migration — cost prohibitive at current scale
