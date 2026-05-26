# PLAN — Dedicated VPC per Environment in us-east-1

## Current Situation

- **Production VPC** (10.254.0.0/16, us-east-1): shared by 4 environments — shared-001, demo-001, atento-001, setup
- **Beta VPC** (10.154.0.0/16, us-east-1): dedicated to beta-001
- **4app-atento VPC** (10.2.1.0/24, us-east-1): legacy, likely unused
- All environments use SSM parameters from `networking/` to discover VPC resources
- `networking_environment` in each `terraform.tfvars` determines which VPC is used
- No network-level blast radius containment between shared environments

### Impacted components

- `networking/` — new VPC files, SSM parameters, peering connections
- `setup/` — `networking_environment` change: `production` → `setup`
- `app-demo-001/` — `networking_environment` change: `production` → `app-demo-001`
- `app-beta-001/` — `networking_environment` change: `beta` → `app-beta-001`
- `app-atento-001/` — `networking_environment` change: `production` → `app-atento-001`
- `app-shared-001/` — `networking_environment` change: `production` → `app-shared-001`

## Objective / Target State

Each environment gets its own dedicated VPC with /22 CIDR, proper subnets, NAT Gateway, and cross-region peering to Management VPC.

### Success criteria

- All 5 environments running in dedicated VPCs
- Minimal downtime during migration — Strategy A (~10-15 min maintenance window) or Strategy B (zero downtime) per environment
- Old Production VPC and Beta VPC decommissioned (after PgBouncer migration)
- VPN access working to all new VPCs via Management peering
- All SSM parameters updated to new naming convention
- **All RDS instances with `publicly_accessible = false`** (atento-001 and shared-001 currently have `true`)

## Decisions Made

| Decision | Value |
|---|---|
| VPC CIDR size | /22 (1024 IPs) |
| Public subnet size | /27 (30 IPs) per AZ |
| Private subnet size | /24 (251 IPs) per AZ |
| Connectivity | VPC Peering (no Transit Gateway) |
| Hub in us-east-1 | No — direct peering from each VPC to Management |
| RDS migration | PostgreSQL Logical Replication (zero downtime) |
| RDS master password | `manage_master_user_password = true` (AWS Secrets Manager, auto-rotation every 7 days) |
| KMS encryption | Multi-Region key `4shark-master` (mrk-fa0cda243274491784fc7b39bead5a03) — primary us-east-1, replica sa-east-1 |
| ECS migration | In-place update (change subnets, Terraform apply) |
| MongoDB Atlas IP whitelist | Dynamic via SSM param `nat_gateway_eips` from `networking_data` module |
| RDS replication connectivity | Temporary same-region VPC Peering (new VPC ↔ old VPC) via Terraform — kept until PgBouncer is migrated to new VPC (Phase 5) |
| PgBouncer migration | AMI-based: snapshot existing EC2, launch in new VPC, update DATABASE_URL |
| Timeline | 1 environment per day |

### CIDR Allocation

| VPC Name | CIDR | Environment |
|---|---|---|
| `app-shared-001` | `10.100.0.0/22` | shared-001 |
| `app-beta-001` | `10.100.4.0/22` | beta-001 |
| `app-demo-001` | `10.100.8.0/22` | demo-001 |
| `app-atento-001` | `10.100.12.0/22` | atento-001 |
| `setup` | `10.100.128.0/24` | setup |

### Subnet Layout (per VPC, example for app-shared-001 — 10.100.0.0/22)

| Subnet | CIDR | AZ | IPs |
|---|---|---|---|
| pub_a | 10.100.0.0/27 | us-east-1a | 30 |
| pub_b | 10.100.0.32/27 | us-east-1b | 30 |
| prv_a | 10.100.1.0/24 | us-east-1a | 251 |
| prv_b | 10.100.2.0/24 | us-east-1b | 251 |

### RDS Name Mapping

| Current Identifier | New Identifier | Type |
|---|---|---|
| `shared-001-cluster` | `app-shared-001-cluster` | Aurora PostgreSQL |
| `demo-001-cluster` | `app-demo-001-cluster` | Aurora PostgreSQL |
| `atento-001-cluster` | `app-atento-001-cluster` | Aurora PostgreSQL |
| `beta-001` | `app-beta-001` | PostgreSQL standalone |
| `setup-001` | `setup` | PostgreSQL standalone |

### Database Name Standardization

Database names inside each RDS are being standardized during the migration. Old names are Heroku legacy (random strings). New names follow snake_case pattern: `app_{environment}_001` (except setup which has no `app_` prefix).

| Environment | Current DB Name | New DB Name |
|---|---|---|
| beta-001 | `beta` | `app_beta_001` |
| demo-001 | `dffadv994f5eph` | `app_demo_001` |
| shared-001 | `dk2016j8l9blr` | `app_shared_001` |
| atento-001 | `dk2016j8l9blr` | `app_atento_001` |
| setup | (verify) | `setup` |

**Impact**: The application's DATABASE_URL must be updated with both the new host AND the new database name during cutover (Phase 3). Since we're already changing the host, changing the database name adds no extra deployment — it's a single DATABASE_URL update.

**Why snake_case**: PostgreSQL convention — hyphens require double-quoting in SQL contexts, underscores don't.

### Temporary VPC Peering for RDS Logical Replication

Each new VPC needs a **temporary same-region peering** to the old VPC where the current RDS lives. This enables the new RDS (subscriber) to connect to the old RDS (publisher) for logical replication. Managed via Terraform — created in Phase 1, removed in Phase 4.

| New VPC | Old VPC | Old VPC CIDR | Notes |
|---|---|---|---|
| `app-beta-001` (10.100.4.0/22) | Beta (10.154.0.0/16) | Same-region, us-east-1 | Done |
| `app-demo-001` (10.100.8.0/22) | Production (10.254.0.0/16) | Same-region, us-east-1 | Done — Removed after PgBouncer migration |
| `app-atento-001` (10.100.12.0/22) | Production (10.254.0.0/16) | Same-region, us-east-1 | Done — Fully migrated, temporary peering removed, old VPC destroyed |
| `app-shared-001` (10.100.0.0/22) | Production (10.254.0.0/16) | Same-region, us-east-1 | Active — needed for DB replication (old RDS still in Production VPC) |
| `setup` (10.100.16.0/22) | Production (10.254.0.0/16) | Same-region, us-east-1 | Done — Created temporarily for ECS migration, removed after cutover |

**Requirements per peering:**
- `aws_vpc_peering_connection` + `aws_vpc_peering_connection_accepter` (same-region, both `provider = aws.us_east_1`)
- Routes in both VPCs (new VPC route tables → old VPC CIDR, old VPC route tables → new VPC CIDR)
- Security group rule on old RDS SG: allow port 5432 from new VPC CIDR

### RDS VPN Access (permanent)

Every new RDS security group must allow port 5432 from Management VPC (`10.255.0.0/16`) to enable database access via VPN. This is permanent — not a migration-only requirement.

- VPN (Pritunl) is in Management VPC (sa-east-1, `10.255.0.0/16`)
- Cross-region peering (new VPC ↔ Management) already provides connectivity
- SG rule: ingress port 5432, CIDR `10.255.0.0/16`, description "PostgreSQL from VPN (Management VPC)"
- Pritunl route push: add `10.100.0.0/20` to cover all 5 new VPCs (replaces individual old VPC routes after Phase 5)

### Pritunl Access Procedure (needed each migration day)

Updating Pritunl routes requires stopping the VPN server, which disconnects VPN access. Must access Pritunl panel via public IP.

**Port 443 is already open to `0.0.0.0/0`** on the Pritunl SG (`sg-002eb6f58e769e6b0`, sa-east-1) — no temporary SG rule needed.

1. Access Pritunl panel: `https://18.228.109.20` (accept self-signed certificate warning)
2. Stop VPN server, add/modify routes, restart VPN server
3. Reconnect VPN, verify new routes work

**If locked out ("Too many authentication attempts"):**

The Pritunl rate limiter stores attempt counts in MongoDB collection `auth_limiter`. Current settings: `auth_limiter_count_max = 2` (blocks after 2 attempts), `auth_limiter_ttl = 604800` (7 days lockout). A TTL index auto-expires entries after 7 days, but the settings are very aggressive — browser reloads on the self-signed cert warning can easily exhaust the 2-attempt limit.

Fix via SSM:
```
aws ssm start-session --target i-081c9edd7aa737bfd --region sa-east-1
sudo mongosh pritunl --eval "db.auth_limiter.deleteMany({})"
```

After clearing, retry login in the browser immediately.

### What Does NOT Change

- ECS cluster names for Strategy A environments (logical, not VPC-bound): `setup-cluster`, `demo-001-cluster`, etc.
- `environment` variable in terraform.tfvars for Strategy A environments (stays `setup`, `demo-001`, etc.)
- S3 buckets, ECR repositories, CloudWatch log groups
- MongoDB Atlas cluster names (only IP whitelist updates)
- Cloudflare DNS names (same domain, just point to new ALB)

**Note**: Strategy B environments (atento-001, shared-001) DO change the `environment` variable — see "Strategy B — Naming Convention" section below.

## Security Fixes Included

### RDS Public Access Removal

Both `atento-001` and `shared-001` currently have `publicly_accessible = true` on all Aurora instances. This is a security risk — RDS should never be publicly accessible when behind a VPC.

| Environment | Current `publicly_accessible` | After Migration |
|---|---|---|
| shared-001 (db-1, db-2) | `true` | `false` |
| atento-001 (db-1, db-2) | `true` | `false` |
| demo-001 (db-1) | not set (default `false`) | `false` |
| beta-001 | `false` | `false` |
| setup-001 | `false` | `false` |

This is resolved as part of the migration: new RDS clusters are created with `publicly_accessible = false` from the start. No separate fix needed.

## Challenges, Difficulties and Risks

### Technical

- **RDS migration timing**: Logical replication setup time depends on database size. Small DBs (setup, beta, demo) = minutes. Large DBs (shared-001, atento-001) = hours for initial sync
- **NAT Gateway IP change**: New VPC = new NAT Gateway = new public IP. MongoDB Atlas whitelist must be updated before cutover
- **ALB recreation**: Terraform will destroy old ALB and create new one. DNS must be updated before old ALB is gone
- **Security groups**: All SG IDs change. Any hardcoded SG references in application config need updating

### RDS Reboot Downtime (required per environment for logical replication)

Logical replication requires `rds.logical_replication = 1` — a static parameter that only takes effect after reboot. Each environment's old RDS (publisher) must be rebooted before replication can start. The parameter is managed in `shared-resources/rds-parameter-groups.tf` and should be enabled per parameter group as each environment's migration begins.

| Environment | Type | Instances | Class | Reboot Strategy | Est. Downtime |
|---|---|---|---|---|---|
| beta-001 | Standalone PG 17.6 | 1 | db.t3.micro | Full reboot | ~1-3 min |
| demo-001 | Aurora PG 16.9 | 1 (writer only) | db.t3.medium | Full reboot | ~1-2 min |
| atento-001 | Aurora PG 15.13 | 2 (writer+reader) | db.t4g.large | Failover → reboot writer | ~15-30s |
| shared-001 | Aurora PG 15.13 | 2 (writer+reader) | db.t4g.large | Failover → reboot writer | ~15-30s |
| setup-001 | Standalone PG 16.9 | 1 | db.t3.micro | Full reboot | ~1-3 min |

**Reboot strategies:**
- **Full reboot** (single instance): database unavailable during entire reboot
- **Failover → reboot** (2 instances): failover to reader (~15-30s downtime), then reboot old writer (now reader) with zero additional downtime

**Parameter group mapping:**
- `postgresql17`: beta-001, app-beta-001 — `rds.logical_replication = 1` already enabled
- `postgresql16`: setup-001 — enable when setup migration starts
- `aurora-postgresql15` (cluster): atento-001-cluster, shared-001-cluster — enable when each migration starts
- `aurora-postgresql16` (cluster): demo-001-cluster — enable when demo migration starts

**Note:** Aurora clusters already use the custom cluster parameter groups (`aurora-postgresql15`, `aurora-postgresql16`) — not defaults. No parameter group switch needed, only the parameter addition + reboot.

### Sequence risk

- **shared-001 is highest risk**: largest DB, most services running, real production traffic. Must be last
- **setup has no MongoDB**: simplest migration, scheduled last since shared-001 must be validated before moving the simplest environment

### Rollback

- Old VPCs remain intact until explicitly decommissioned
- If migration fails mid-way, just revert `networking_environment` in tfvars and apply
- RDS: old instance stays alive until we manually delete it after verification

## Migration Order

| Day | Environment | Complexity | RDS Type | Services | Rationale |
|---|---|---|---|---|---|
| 1 | app-beta-001 | Medium | Standalone (beta-001 → app-beta-001) | 1 web + 7 workers + 4 crons | **DONE** (2026-03-03) — PR #211 |
| 2 | app-demo-001 | Medium | Aurora cluster (1 instance) | 1 web + 7 workers + 4 crons | **DONE** (2026-03-04) — PR #211 |
| 3 | app-atento-001 | High | Aurora cluster (2 instances) | 1 web + 7 workers + 7 crons | **DONE** (2026-03-05) — PR #211. Old 4app-atento VPC destroyed. DB went from 365 GB (bloat) to ~26 GB. |
| 4 | app-shared-001 | Highest | Aurora cluster (2 instances) | 1 web + 7 workers + 7 crons | **FULLY MIGRATED** (2026-03-08) — DB cutover complete. Sequences fixed. PgBouncers updated (new cluster + new dbname) and physically migrated to new VPC (puma: 10.100.1.42, sidekiq: 10.100.2.105, vpc-080577b61da17d948). MIGRATION_DATABASE_URL updated. Temporary VPC peering removed. Old cluster (shared-001-cluster) deleted — final snapshot `shared-001-cluster-final-20260308` retained, automated backups kept (7-day expiry). Production VPC decommissioned (2026-03-08). |
| 5 | setup | Low | Standalone (setup-001 → setup) | 1 web | **DONE** (2026-03-07) — Downtime approach. Old RDS destroyed. |

## Proposed Steps Per Environment

### Phase 1 — Create VPC Infrastructure (~1h, Terraform only)

1. Create `networking/vpc_{name}.tf` with:
   - VPC, 4 subnets (pub_a, pub_b, prv_a, prv_b)
   - IGW, NAT Gateway (1, in pub_a), EIP
   - Route tables (1 public, 2 private per AZ)
   - Route table associations
   - Default routes (IGW for public, NAT for private)
   - S3 VPC endpoint (gateway type, free)

2. Add peering to `networking/peering.tf`:
   - **Cross-region peering (permanent)**: Management (requester, sa-east-1) → new VPC (accepter, us-east-1)
     - **Must use** `peer_region = "us-east-1"` on the connection
     - **Must add** `aws_vpc_peering_connection_accepter` with `provider = aws.us_east_1`
     - Routes: new VPC (pub + prv_a + prv_b) → Management (10.255.0.0/16)
     - Routes: Management (pub + prv) → new VPC CIDR
   - **Same-region peering (temporary, for RDS logical replication)**: new VPC ↔ old VPC (us-east-1)
     - Both sides use `provider = aws.us_east_1`
     - Routes: new VPC private route tables → old VPC CIDR
     - Routes: old VPC private route tables → new VPC CIDR
     - Security group rule on old RDS: allow port 5432 from new VPC CIDR
     - **Remove in Phase 4** after logical replication is complete

3. Add SSM parameters to `networking/ssm.tf`:
   - `/networking/{name}/vpc_id`
   - `/networking/{name}/vpc_cidr`
   - `/networking/{name}/private_subnet_ids`
   - `/networking/{name}/public_subnet_ids`
   - `/networking/{name}/route_table_private_id` — **required by `modules/networking_data`**, points to prv_a
   - `/networking/{name}/route_table_private_a_id`
   - `/networking/{name}/route_table_private_b_id`
   - `/networking/{name}/route_table_public_id`
   - `/networking/{name}/nat_gateway_eips` — **NAT Gateway public IP(s)**, used by MongoDB Atlas whitelist

4. `terraform plan` + `terraform apply` on networking/

### Phase 2 — Create New RDS + Prepare MongoDB (Terraform, all environments)

**CRITICAL: Old and new RDS coexist. Old stays alive until Phase 4.**

1. Verify and add VPN access rule on old RDS SG if needed: ingress port 5432 from `10.255.0.0/16`
   - **Why**: Old VPN was inside the old VPC — SG may allow access via SG-reference, not CIDR. The current VPN (Pritunl/Management VPC) uses CIDR `10.255.0.0/16`, which may not be allowed on old RDS SGs.
   - **Purpose**: Enables pgAdmin access to old RDS during migration (monitoring replication, running SQL commands)
   - **Remove in Phase 4** alongside other temporary resources (if added)
2. Add NEW RDS resource to `rds.tf` alongside the existing one:
   - New `identifier` / `cluster_identifier` (e.g., `app-beta-001`)
   - New `aws_db_subnet_group` in the new VPC
   - New security group referencing new VPC
   - `manage_master_user_password = true` — AWS manages password in Secrets Manager
   - `master_user_secret_kms_key_id` + `kms_key_id` + `performance_insights_kms_key_id` = `4shark-master` KMS key
   - `publicly_accessible = false` (fixes security for atento-001 and shared-001)
   - New RDS security group must include **three ingress rules**: own VPC CIDR + Management VPC (`10.255.0.0/16`) for VPN access + PgBouncer IP/32 from old VPC (see "PgBouncer Security Group" section for details)
   - **Do NOT remove or modify the old RDS resource yet**
   - **gp3 < 400 GB**: do NOT specify `iops` or `storage_throughput` (AWS rejects explicit values, uses defaults 3000/125 automatically)
   - Add `module "new_vpc_data"` reading from new VPC SSM params (temporary — needed because `networking_environment` still points to old VPC)
3. Update `mongodb.tf` (if exists):
   - Add new NAT Gateway IP dynamically via `module.new_vpc_data.nat_gateway_eips` with key `"nat-gateway-new-{idx}"`
   - **Keep old entry with the SAME key name** (e.g., `"nat-gateway"`) — changing the key causes Terraform to destroy + recreate the MongoDB Atlas IP whitelist entry, which briefly removes the IP and can break active connections in production
4. `terraform plan` — must show only additions to existing RDS, plus MongoDB Atlas whitelist update
5. `terraform apply` — creates new RDS in new VPC, old one untouched, MongoDB accepts traffic from both VPCs
6. Enable `rds.logical_replication = 1` on the environment's parameter group in `shared-resources/rds-parameter-groups.tf`
   - `terraform plan -out=tfplan` + `terraform apply tfplan` on `shared-resources/`
   - Reboot the OLD RDS instance (publisher) — see "RDS Reboot Downtime" section for estimates
   - Reboot the NEW RDS instance to clear pending-reboot state (no impact — empty database)
   - Verify both show `ParameterApplyStatus: in-sync`
7. Create application roles on new RDS — via pgAdmin Query Tool
   - Roles are cluster-level objects — NOT included in database schema backups
   - Must be created BEFORE schema restore so ownership can be transferred
   - Passwords must use **MD5 encoding** (not SCRAM) due to PgBouncer compatibility

   **IMPORTANT — pgAdmin database context**: PostgreSQL does NOT allow switching databases within a session. Each pgAdmin Query Tool tab is a separate connection to a specific database. Steps 7 and 8b use the `postgres` database. Steps 8d onwards use the NEW application database. When the plan says to switch, you must **open a new Query Tool tab** (right-click the target database → Query Tool).

   - **Steps 7, 8b**: Query Tool on `postgres` database (cluster-level operations: CREATE ROLE, CREATE DATABASE)
   - **Steps 8d, 8e, 8f, 8g, 9, 10**: Query Tool on the NEW application database (e.g., `app_beta_001`)

   **Role structure per environment:**
   - **beta-001**: 1 role (read/write + owner)
   - **demo-001**: 1 role (read/write + owner) — verify before migration
   - **atento-001, shared-001**: 2 roles (write/owner + read-only) — verify before migration
   - **setup**: verify before migration

   **Step 7-pre-a — Create write user (run on NEW RDS, `postgres` database):**
   ```sql
   SET password_encryption = 'md5';
   CREATE ROLE {write_user} LOGIN PASSWORD '{write_password}';
   GRANT {write_user} TO postgres;
   ```
   The `SET password_encryption = 'md5'` must be in the **same session** as the CREATE ROLE — it forces the password to be stored as MD5 instead of SCRAM-SHA-256 (PostgreSQL 17 default). This is required for PgBouncer compatibility. The write user does NOT need `rds_superuser` — ownership of objects (step 8d) is sufficient for ALTER TABLE during migrations. The `GRANT {write_user} TO postgres` allows `postgres` to SET ROLE to the write user, which is required to create the database with the write user as owner.

   **Step 7-pre-b — Create read user (only for environments with separate read user):**
   ```sql
   SET password_encryption = 'md5';
   CREATE ROLE {read_user} LOGIN PASSWORD '{read_password}';
   ```

   **Step 7-pre-c — Verify roles were created with MD5:**
   ```sql
   SELECT rolname, rolpassword LIKE 'md5%' AS is_md5
   FROM pg_authid
   WHERE rolname NOT LIKE 'pg_%' AND rolname NOT LIKE 'rds%' AND rolname != 'postgres';
   ```
   All roles must show `is_md5 = true`. If `pg_authid` is restricted, verify by testing PgBouncer connection after migration.

   **Important — passwords**: The passwords must be the same as on the old RDS. Get them from the application's environment variables / secrets (DATABASE_URL, etc.). The engineer must provide the passwords — Claude does not have access to production secrets.

8. Create database and schema on new RDS (subscriber) — via pgAdmin
   - The new RDS is empty — need to replicate the schema (structure only, no data) from old to new
   - Both old and new RDS must be connected in pgAdmin via VPN

   **Step 8a — Backup schema from old RDS (pgAdmin)**

   Right-click on the database (e.g., `beta`) on the OLD server → **Backup...**

   | Tab | Field | Value |
   |---|---|---|
   | **General** | Filename | `schema_{environment}.backup` (e.g., `schema_beta.backup`) |
   | **General** | Format | **Custom** |
   | **General** | Encoding, Compression, Number of jobs, Role name | Leave default (empty) |
   | **Data Options** | Only schemas | **ON** |
   | **Data Options** | Only data | OFF |
   | **Data Options** | Blobs | **OFF** |
   | **Data Options** | Owner (Do not save) | **ON** |
   | **Data Options** | Privileges (Do not save) | **ON** |
   | **Data Options** | All other "Do not save" toggles | OFF (default) |
   | **Query Options** | All toggles | OFF (default) |
   | **Table Options** | All toggles | OFF (default) |
   | **Options** | Verbose messages | ON (default) |
   | **Options** | All other toggles/fields | OFF / empty (default) |
   | **Objects** | Nothing selected | Leave all unchecked — exports everything |

   Click **Backup**. Check the pgAdmin notifications (bell icon) for success/errors.

   **Step 8b — Create database on new RDS (pgAdmin)**

   1. Connect to the NEW RDS server in pgAdmin
   2. Right-click **Databases** → **Create** → **Database...**
   3. Name: **new standardized name** (see "Database Name Standardization" table — e.g., `app_beta_001`, `app_demo_001`)
   4. Owner: **{write_user}** (the role created in step 7, NOT `postgres` — this ensures new objects created by migrations will be owned by the write user)
   5. Click **Save**

   **Note**: The database name changes from old to new (e.g., `beta` → `app_beta_001`). This is intentional — see "Database Name Standardization" section. The DATABASE_URL update in Phase 3 will include both the new host and the new database name.

   **Step 8c — Restore schema on new RDS (pgAdmin)**

   Right-click on the NEW database (e.g., `app_beta_001`) on the NEW server → **Restore...**

   | Tab | Field | Value |
   |---|---|---|
   | **General** | Format | Custom or tar (default — keep) |
   | **General** | Filename | `schema_{environment}.backup` (file from step 8a) |
   | **General** | Number of jobs | empty (default) |
   | **General** | Role name | empty (default) |
   | **Data Options** | Only data | OFF (default) |
   | **Data Options** | Only schema | **ON** |
   | **Data Options** | Owner (Do not save) | **ON** |
   | **Data Options** | Privilege (Do not save) | **ON** |
   | **Data Options** | All other toggles | OFF (default) |
   | **Query Options** | Include CREATE DATABASE | OFF (default) |
   | **Query Options** | Clean before restore | OFF (default) |
   | **Query Options** | Include IF EXISTS | OFF (default) |
   | **Query Options** | Single transaction | OFF (default) |
   | **Table Options** | Enable row security | OFF (default) |
   | **Table Options** | No data for failed tables | OFF (default) |
   | **Options** | Triggers | OFF (default) |
   | **Options** | Verbose messages | ON (default — keep) |
   | **Options** | Use SET SESSION AUTHORIZATION | OFF (default) |
   | **Options** | Exit on error | OFF (default) |
   | **Options** | Exclude schema | empty (default) |

   **Summary**: 3 changes from defaults — **Only schema ON**, **Owner (Do not save) ON**, **Privilege (Do not save) ON**. Everything else stays default.

   Click **Restore**. Check pgAdmin notifications (bell icon) for success/errors.

   **Step 8d — Transfer ownership to write user**

   **→ Open a NEW Query Tool tab on the `app_{env}_001` database** (right-click `app_beta_001` in the tree → Query Tool). Do NOT use the `postgres` tab.

   Since the schema was restored by `postgres` (no-owner flag), all objects are owned by `postgres`. Transfer ownership to the write user:
   ```sql
   REASSIGN OWNED BY postgres TO {write_user};
   ```
   The `postgres` role is admin only — it should NOT own application objects. The write user owns everything and is the only role used day-to-day. No ALTER DEFAULT PRIVILEGES needed — all application operations (migrations, queries) run as the write user.

   **IMPORTANT — Logical replication grants (learned from atento-001):**
   After the subscription copies data, tables are accessed via the `postgres` role (subscription owner). The write user needs explicit grants, otherwise the application gets `PG::InsufficientPrivilege: permission denied for table`. Run this **after** REASSIGN and **before** switching PgBouncer:
   ```sql
   GRANT ALL ON ALL TABLES IN SCHEMA public TO {write_user};
   GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO {write_user};
   ```
   Also grant read user access (if separate read user exists):
   ```sql
   GRANT SELECT ON ALL TABLES IN SCHEMA public TO {read_user};
   GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO {read_user};
   ```

   Verify ownership was transferred:
   ```sql
   SELECT tablename, tableowner FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename LIMIT 20;
   ```
   All tables should show `{write_user}` as owner.

   **Step 8e — Grant read access (only for environments with separate read user)**

   Run on the NEW database:
   ```sql
   -- Grant read access on all existing tables
   GRANT USAGE ON SCHEMA public TO {read_user};
   GRANT SELECT ON ALL TABLES IN SCHEMA public TO {read_user};
   GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO {read_user};

   -- Grant read access on future tables automatically
   ALTER DEFAULT PRIVILEGES FOR ROLE {write_user} IN SCHEMA public GRANT SELECT ON TABLES TO {read_user};
   ALTER DEFAULT PRIVILEGES FOR ROLE {write_user} IN SCHEMA public GRANT SELECT ON SEQUENCES TO {read_user};
   ```

   **Step 8f — Verify schema matches**

   Run this query on BOTH old and new databases (via Query Tool in pgAdmin) and compare the results:
   ```sql
   SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';
   ```
   The counts must match. If they don't, check the Messages tab from step 8c for errors.

   **Step 8g — Check tables without PRIMARY KEY**

   Run on the OLD database (publisher):
   ```sql
   SELECT t.table_name
   FROM information_schema.tables t
   LEFT JOIN information_schema.table_constraints c
     ON t.table_name = c.table_name AND c.constraint_type = 'PRIMARY KEY'
   WHERE t.table_schema = 'public' AND t.table_type = 'BASE TABLE' AND c.constraint_name IS NULL;
   ```
   If any tables are returned, they need `REPLICA IDENTITY FULL` on the publisher before creating the publication:
   ```sql
   ALTER TABLE {table_name} REPLICA IDENTITY FULL;
   ```
   Tables without primary keys use the entire row for identity during replication, which is slower but functional.
9. Set up PostgreSQL logical replication: old (publisher) → new (subscriber)
   - **On old RDS (publisher)** — create publication for all tables:
     ```sql
     CREATE PUBLICATION {env}_pub FOR ALL TABLES;
     ```
   - **On new RDS (subscriber)** — create subscription pointing to old RDS:
     ```sql
     CREATE SUBSCRIPTION {env}_sub
       CONNECTION 'host={old_host} port=5432 dbname={db_name} user=postgres password={old_password}'
       PUBLICATION {env}_pub;
     ```
   - The subscription automatically starts initial data copy (all existing rows), then switches to streaming replication
   - For Aurora clusters: same approach — Aurora supports logical replication as both publisher and subscriber
10. Verify replication is in sync
   - **On old RDS (publisher)** — check replication slots are active:
     ```sql
     SELECT slot_name, active, restart_lsn, confirmed_flush_lsn FROM pg_replication_slots;
     ```
   - **On new RDS (subscriber)** — check subscription status:
     ```sql
     SELECT subname, subenabled, subconninfo FROM pg_subscription;
     SELECT * FROM pg_stat_subscription;
     ```
   - **Compare row counts** on key tables to confirm data consistency:
     ```sql
     SELECT schemaname, relname, n_live_tup FROM pg_stat_user_tables ORDER BY n_live_tup DESC LIMIT 20;
     ```
   - **Check LSN lag** — difference between publisher's current LSN and subscriber's confirmed flush LSN should be near zero
11. **Fix sequences** — logical replication does NOT replicate sequences. After cutover, all sequences on the new database are at their initial values (from schema restore). The application will get primary key conflicts on the first INSERT if not fixed.

   **Run on the NEW database after replication is synced and before (or immediately after) switching PgBouncer:**
   ```sql
   DO $$
   DECLARE
     rec RECORD;
     max_val BIGINT;
   BEGIN
     FOR rec IN
       SELECT
         t.table_name,
         c.column_name,
         pg_get_serial_sequence('public.' || quote_ident(t.table_name), c.column_name) AS seq_name
       FROM information_schema.tables t
       JOIN information_schema.columns c
         ON c.table_schema = t.table_schema AND c.table_name = t.table_name
       WHERE t.table_schema = 'public'
         AND t.table_type = 'BASE TABLE'
         AND c.column_default LIKE 'nextval%'
     LOOP
       IF rec.seq_name IS NOT NULL THEN
         EXECUTE format('SELECT COALESCE(max(%I), 0) FROM public.%I', rec.column_name, rec.table_name) INTO max_val;
         PERFORM setval(rec.seq_name, GREATEST(max_val, 1));
         RAISE NOTICE '% -> % (col: %)', rec.seq_name, GREATEST(max_val, 1), rec.column_name;
       END IF;
     END LOOP;
   END $$;
   ```

   **Alternative — via Rails console** (simpler, recommended):
   ```ruby
   ActiveRecord::Base.connection.tables.each do |table|
     ActiveRecord::Base.connection.reset_pk_sequence!(table)
   end
   ```

   **Verify** by checking any high-traffic table: `SELECT last_value FROM {sequence_name};` should match `SELECT max(id) FROM {table_name};`

### Phase 3 — Migrate Application (Terraform + Deploy)

**CRITICAL: The application deploy with new DATABASE_URL is what cuts over. Not Terraform.**

There are two migration strategies depending on whether downtime is acceptable:

#### Strategy A — Accept Downtime (maintenance window)

Change `networking_environment`, terraform apply triggers a cascade: TG replaced (vpc_id is ForceNew) → ALB replaced (`replace_triggered_by`) → ECS services replaced (`replace_triggered_by` via `terraform_data`). All infrastructure is destroyed and recreated in the new VPC. **Total estimated downtime: ~10-15 minutes** (terraform apply ~5-10 min + warm-up ~3-5 min). Requires a maintenance window where the application can be unavailable.

1. **Pre-check: clean non-Terraform SGs that could block replacement** (via AWS CLI):
   - List all SGs in the old VPC that reference ECS or ALB resources for this environment:
     ```bash
     aws ec2 describe-security-groups --filters "Name=vpc-id,Values=<old-vpc-id>" "Name=group-name,Values=*{env}*" \
       --query "SecurityGroups[*].[GroupId,GroupName,Description]" --output table --region us-east-1
     ```
   - If any SGs exist that are NOT managed by Terraform (created by Ansible, AWS CLI, or manually), delete them before proceeding — they will block the replacement of Terraform-managed SGs (circular dependency: old SG can't be deleted while referenced, new SG can't be created until old is deleted)
   - **Lesson from beta-001**: partial apply failures caused deposed SGs that couldn't be cleaned up because non-Terraform SGs referenced them. Clean first, apply once.
2. Update `terraform.tfvars`:
   - `networking_environment = "{new_name}"` (e.g., `app-beta-001`)
3. Update `mongodb.tf` (if exists):
   - Change `module.new_vpc_data.nat_gateway_eips` → `module.vpc_data.nat_gateway_eips`
   - Old hardcoded NAT Gateway IP stays temporarily (remove in Phase 4)
4. `terraform plan` — review carefully (ECS, ALB, security groups will be recreated in new VPC)
5. `terraform apply` — ECS instances replaced, ALB recreated in new VPC (~5-10 min downtime)

   **KNOWN ISSUE — Deposed ECS SG `DependencyViolation` (happened in beta-001 and demo-001):**

   The apply WILL fail at the end trying to delete the old ECS security group (deposed). This is expected and unavoidable with the current architecture. The sequence is:
   1. Terraform replaces the ECS SG (vpc_id change → force new) — old SG becomes **deposed**
   2. ASGs are updated with new subnets and new SG — old EC2 instances start terminating
   3. ECS managed draining lifecycle hook (`ecs-managed-draining-termination-hook`) holds instances in `Terminating:Wait`
   4. While instances are in `Terminating:Wait`, their ENIs still reference the old SG
   5. Terraform tries to delete the deposed SG → fails with `DependencyViolation`

   **All other resources (ALB, listeners, TGs, ECS service, ASGs, CodeDeploy) complete successfully.** Only the deposed SG cleanup fails.

   **Resolution — execute immediately after the failed apply:**
   ```bash
   # 1. Find ENIs still attached to the old SG
   aws ec2 describe-network-interfaces --filters "Name=group-id,Values=<old-sg-id>" \
     --query "NetworkInterfaces[*].[NetworkInterfaceId,Attachment.InstanceId]" --output table --region us-east-1

   # 2. For each instance, check it's in Terminating:Wait
   aws autoscaling describe-auto-scaling-instances --instance-ids <instance-id> \
     --query "AutoScalingInstances[0].{ASG:AutoScalingGroupName,LifecycleState:LifecycleState}" --output json --region us-east-1

   # 3. Complete the lifecycle action (forces termination)
   aws autoscaling complete-lifecycle-action \
     --lifecycle-hook-name ecs-managed-draining-termination-hook \
     --auto-scaling-group-name <asg-name> \
     --instance-id <instance-id> \
     --lifecycle-action-result CONTINUE --region us-east-1

   # 4. Wait for instance to reach 'terminated' state
   aws ec2 describe-instances --instance-ids <instance-id> \
     --query "Reservations[0].Instances[0].State.Name" --output text --region us-east-1

   # 5. Verify no more ENIs on old SG
   aws ec2 describe-network-interfaces --filters "Name=group-id,Values=<old-sg-id>" \
     --query "NetworkInterfaces[*].NetworkInterfaceId" --output text --region us-east-1

   # 6. Re-run terraform plan + apply to clean up the deposed SG
   terraform plan -out=tfplan && terraform apply tfplan
   ```

   **Repeat steps 1-5 for each instance** if multiple ASGs had running instances.

6. Update Cloudflare DNS CNAME to point to new ALB:
   - Edit `dns/public_dns_app4shark_com.tf` — change `content` of the environment's CNAME record to new ALB DNS
   - `terraform apply -target='cloudflare_dns_record.{env}_cname'` in `dns/` project
   - Propagation is instant (proxied + TTL 1)
   - **Note**: DNS values are currently hardcoded — see "Future Improvement" section
7. Update PgBouncer security group (old VPC, via AWS CLI — managed by Ansible):
   - Add ingress port 6432 from new VPC CIDR (ECS → PgBouncer traffic)
   - Add ingress port 22 from `10.255.0.0/16` (VPN SSH access for config updates)
   - Identify PgBouncer instance: `aws ec2 describe-instances --filters "Name=tag:Name,Values=pgbouncer-*-puma" --query 'Reservations[].Instances[].[PrivateIpAddress,Tags[?Key==Name].Value|[0],SecurityGroups[0].GroupId]'`
8. Update PgBouncer config (SSH into PgBouncer instance):
   - Update `[databases]` section: change `host=` to new RDS endpoint, change `dbname=` to new database name (e.g., `app_beta_001`)
   - Restart PgBouncer: `sudo systemctl restart pgbouncer` (reload alone may not clear cached connection errors)
   - **Important**: This step must be done **before** the application deploy. PgBouncer must point to the new RDS before app traffic arrives
9. **Deploy application** with updated environment variables:
   - `DATABASE_URL` goes through PgBouncer (e.g., `@{pgbouncer_ip}:6432/{pool_name}`) — usually only the pool config changes, not the URL itself
   - `MIGRATION_DATABASE_URL` must point directly to the new RDS (bypasses PgBouncer for DDL operations)
   - This is the cutover moment — app starts writing to new RDS
   - Old RDS stops receiving writes (logical replication can be stopped)
10. Wait for services to stabilize, verify application is working

#### Strategy B — Parallel Infrastructure, Zero Downtime

For production and production-like environments, new infrastructure is created **alongside** the old before any switchover. No downtime.

1. Create NEW infrastructure in new VPC as **separate Terraform resources** (alongside old):
   - New ALB (`module "new_public_alb"`) in new VPC
   - New ECS security group in new VPC
   - New capacity providers / ASGs pointing to new VPC subnets
   - New ECS services registered with new ALB
   - Reference new VPC via `module.new_vpc_data` (already exists from Phase 2)
2. `terraform plan` + `terraform apply` — new infra comes up alongside old, both running
3. Verify new ALB is healthy, new ECS services are running
4. **Deploy application** to new ECS services with new `DATABASE_URL` pointing to new RDS
5. Switch Cloudflare DNS from old ALB to new ALB — **this is the zero-downtime cutover**:
   - Edit `dns/public_dns_app4shark_com.tf` — change `content` of the environment's CNAME record to new ALB DNS
   - `terraform apply -target='cloudflare_dns_record.{env}_cname'` in `dns/` project
6. Verify application is working on new infra
7. Remove old infrastructure:
   - Remove old ALB, old SGs, old capacity providers, old ECS services
   - Update `terraform.tfvars`: `networking_environment = "{new_name}"`
   - Update `mongodb.tf`: switch to `module.vpc_data.nat_gateway_eips`
   - Remove `module "new_vpc_data"` (now redundant)
8. `terraform plan` + `terraform apply` — clean up, single set of infra remains
9. Wait for services to stabilize

#### Strategy B — Naming Convention for Parallel Infrastructure

**Problem**: Strategy B creates new ECS/ALB infrastructure **alongside** the old. All resource names in `app-atento-001/main.tf` are derived from `${var.environment}` (currently `atento-001`). If we create new resources with the same `environment` value, Terraform will try to modify existing resources instead of creating new ones. We need a different name prefix to avoid conflicts.

**Solution**: Add `app-` prefix to the `environment` variable for Strategy B environments. This only applies to the two production environments that use Strategy B:

| Environment | Old `var.environment` | New `var.environment` | Rationale |
|---|---|---|---|
| atento-001 | `atento-001` | `app-atento-001` | Production — Strategy B |
| shared-001 | `shared-001` | `app-shared-001` | Production — Strategy B |

Strategy A environments (beta-001, demo-001, setup) keep their existing `environment` values unchanged.

**Resource Name Changes (atento-001 example):**

| Resource | Old Name (`atento-001`) | New Name (`app-atento-001`) |
|---|---|---|
| ECS Cluster | `atento-001-cluster` | `app-atento-001-cluster` |
| ECS Security Group | `atento-001-ecs` | `app-atento-001-ecs` |
| ALB | `atento-001-pub-lb` | `app-atento-001-pub-lb` |
| ALB Security Group | `atento-001-pub-lb` | `app-atento-001-pub-lb` |
| Target Groups | `atento-001-{svc}-tg` | `app-atento-001-{svc}-tg` |
| ASGs (capacity providers) | `atento-001-{type}` | `app-atento-001-{type}` |
| ECS Services | `atento-001-{service}` | `app-atento-001-{service}` |
| IAM Role/Profile | `atento-001-ecs` | `app-atento-001-ecs` |
| CodeDeploy App | `atento-001-{service}` | `app-atento-001-{service}` |

**Terraform State Management Challenge:**

Changing `var.environment` from `atento-001` to `app-atento-001` causes Terraform to see all existing resources as "must be destroyed" (old name) and "must be created" (new name). We need both to coexist during the migration.

**Approach — `terraform state rm` old resources before apply:**

1. Change `var.environment` to `app-atento-001` in `terraform.tfvars`
2. Change `networking_environment` to `app-atento-001`
3. Run `terraform plan` — will show destroy old + create new for all ECS/ALB resources
4. `terraform state rm` all ECS/ALB resources that would be destroyed (cluster, SGs, ALB, TGs, ASGs, services, IAM, CodeDeploy)
5. Run `terraform plan` again — now shows only "create" (no destroy, old resources are no longer in state)
6. `terraform apply` — creates new infrastructure alongside old (old is still running in AWS, just not in Terraform state)
7. Verify new infrastructure is healthy
8. Switch DNS to new ALB
9. Destroy old infrastructure via AWS CLI (not in Terraform state anymore)

**Why not separate workspace/backend**: The RDS, MongoDB, and other non-ECS resources are in the same state file. A separate workspace would require moving ALL resources, not just ECS/ALB. The `state rm` approach is more surgical — only removes the resources that need to coexist temporarily.

**Consistent with existing naming**: The new VPCs already use the `app-` prefix (`app-atento-001`, `app-shared-001`). The new RDS clusters also use it (`app-atento-001-cluster`). Adding `app-` to ECS/ALB makes all infrastructure follow the same naming pattern.

### Phase 4 — Verification + Cleanup

**Only after confirming everything works in new VPC.**

1. Verify application is working on new VPC (health checks, test flows)
2. Verify VPN access via Management peering
3. Stop logical replication (drop subscription on new, drop publication on old)
4. Remove old RDS from Terraform and AWS (Aurora clusters — full procedure):

   **Pre-requisite**: cluster must be in `available` state (start it if stopped — takes ~3-5 min).

   **Step 4a — Disable deletion protection**:
   ```bash
   aws rds modify-db-cluster \
     --db-cluster-identifier {old_cluster_id} \
     --no-deletion-protection \
     --apply-immediately \
     --region us-east-1
   ```

   **Step 4b — Delete instances one by one** (mandatory before deleting the cluster — AWS rejects cluster deletion if instances exist):
   - Delete reader first, then writer; wait for each before proceeding:
   ```bash
   aws rds delete-db-instance \
     --db-instance-identifier {old_reader_id} \
     --skip-final-snapshot \
     --region us-east-1
   # Wait until deleted:
   aws rds describe-db-instances --db-instance-identifier {old_reader_id} \
     --query "DBInstances[0].DBInstanceStatus" --output text --region us-east-1

   aws rds delete-db-instance \
     --db-instance-identifier {old_writer_id} \
     --skip-final-snapshot \
     --region us-east-1
   # Wait until deleted:
   aws rds describe-db-instances --db-instance-identifier {old_writer_id} \
     --query "DBInstances[0].DBInstanceStatus" --output text --region us-east-1
   ```

   **Step 4c — Delete the cluster with final snapshot** (snapshot is created as part of deletion; `--no-delete-automated-backups` retains automated backups so they expire naturally over 7 days):
   ```bash
   aws rds delete-db-cluster \
     --db-cluster-identifier {old_cluster_id} \
     --no-skip-final-snapshot \
     --final-db-snapshot-identifier {old_cluster_id}-final-$(date +%Y%m%d) \
     --no-delete-automated-backups \
     --region us-east-1
   ```

   **Note on automated backups**: Default behavior (without the flag) deletes them immediately. `--no-delete-automated-backups` keeps the last 7 days of automated backups, which expire naturally — no further action needed.
   **Note on final snapshot**: `--final-db-snapshot-identifier` (without "cluster" in the name) is the correct parameter — confirmed in AWS CLI docs.

   **Step 4e — Remove old RDS from Terraform state** (prevents Terraform from managing a resource that no longer exists):
   ```bash
   terraform state rm module.rds_aurora_cluster_old  # or whatever the old module name is
   ```
5. Remove old DB subnet group
6. Remove `module "new_vpc_data"` from `rds.tf` (no longer needed — `module.vpc_data` now reads from new VPC)
7. Remove old hardcoded NAT Gateway IP from `mongodb.tf`
8. Remove temporary SG rules on old RDS:
   - Remove VPN access rule (`10.255.0.0/16`)
   - Remove replication access rule (new VPC CIDR)
9. **Keep** temporary VPC peering — PgBouncer still in old VPC, removed in Phase 5
10. `terraform plan` + `terraform apply` on both `networking/` and `app-{env}/` — clean up old resources

### Phase 5 — PgBouncer Migration via AMI

**Migrates PgBouncer from old VPC to new VPC using AMI snapshots. After this phase, the temporary VPC peering and old VPC can be fully removed.**

Each environment has 2 PgBouncer instances (puma + sidekiq). The approach: create AMI from existing instance → launch new instance in new VPC → update ECS to point to new PgBouncer → terminate old instance.

**Pre-requisite**: Phases 1-4 completed, application running in new VPC, PgBouncer still in old VPC with cross-VPC peering.

1. Create AMIs from both PgBouncer instances (no reboot — no impact on running traffic):
   ```bash
   aws ec2 create-image \
     --instance-id {puma_instance_id} \
     --name "pgbouncer-{env}-puma-$(date +%Y%m%d)" \
     --description "PgBouncer {env}-puma before VPC migration" \
     --no-reboot --region us-east-1

   aws ec2 create-image \
     --instance-id {sidekiq_instance_id} \
     --name "pgbouncer-{env}-sidekiq-$(date +%Y%m%d)" \
     --description "PgBouncer {env}-sidekiq before VPC migration" \
     --no-reboot --region us-east-1
   ```
   Wait for AMIs to reach `available` state.

2. Create security group for PgBouncer in new VPC:
   - Ingress port **6432** (PgBouncer) from new VPC CIDR — ECS task connections
   - Ingress port **22** (SSH) from `10.255.0.0/16` — VPN maintenance access
   - Egress all traffic (default)

3. Launch new PgBouncer instances from AMIs:
   - **Subnet**: private subnet in new VPC (prv_a or prv_b)
   - **Security group**: the one created in step 2
   - **Instance type**: same as original (check with `describe-instances`)
   - **Key pair**: same as original
   - **Tags**: `Name = pgbouncer-{env}-puma` / `pgbouncer-{env}-sidekiq`
   - **No public IP** (private subnet, accessed via VPN or from ECS in same VPC)

4. Verify PgBouncer config on new instances (SSH via VPN):
   - `pgbouncer.ini` should already point to new RDS endpoint and new database name (updated during Phase 3)
   - If not, update `host=` and `dbname=` in `[databases]` section
   - Verify `userlist.txt` has correct credentials
   - Restart PgBouncer: `sudo systemctl restart pgbouncer`
   - Test connection: `psql -h 127.0.0.1 -p 6432 -U {user} {pool_name}`

5. Update ECS `DATABASE_URL` to point to new PgBouncer IPs:
   - The `DATABASE_URL` contains the PgBouncer private IP (e.g., `@10.154.131.93:6432/...`)
   - Update to new IP in the same VPC (e.g., `@10.100.x.x:6432/...`)
   - **Sidekiq** `DATABASE_URL` also needs updating (points to sidekiq PgBouncer)
   - **IMPORTANT**: This step requires a full **GitHub deploy** of the application (not just Terraform). The deploy updates the ECS task definitions with the new environment variables, triggering a rolling restart of all ECS tasks to pick up the new PgBouncer IPs.

6. Verify application health after ECS tasks restart with new PgBouncer IPs

7. Update RDS security group — replace old PgBouncer IP/32 rule with new VPC CIDR (or new PgBouncer IP/32):
   - Remove: ingress port 5432 from old PgBouncer IP/32 (e.g., `10.154.131.93/32`)
   - The new PgBouncer is in the same VPC as the RDS — already covered by the VPC CIDR ingress rule
   - Update in Terraform (`rds.tf`) and apply

8. Remove temporary VPC peering from `networking/peering.tf`:
   - Remove peering connection + accepter + routes (new VPC ↔ old VPC)
   - `terraform plan` + `terraform apply` on `networking/`

9. Terminate old PgBouncer instances in old VPC:
   ```bash
   aws ec2 terminate-instances --instance-ids {old_puma_id} {old_sidekiq_id} --region us-east-1
   ```

10. Clean up old PgBouncer SG rules (manual rules added via AWS CLI during Phase 3):
    - These SGs belong to the old VPC — will be removed when old VPC is deleted in Phase 6

11. Delete AMIs and associated snapshots (no longer needed):
    ```bash
    aws ec2 deregister-image --image-id {puma_ami_id} --region us-east-1
    aws ec2 deregister-image --image-id {sidekiq_ami_id} --region us-east-1
    # Then delete orphaned snapshots
    ```

**PgBouncer Instance Mapping:**

| Environment | Puma Instance | Sidekiq Instance | Old VPC |
|---|---|---|---|
| beta-001 | `i-077d3c08becaf18ca` (`10.154.131.93`) | `i-08cba0c0dbeb8a311` (`10.154.129.189`) | Beta (`10.154.0.0/16`) |
| demo-001 | `i-0e3ea81dda473f90b` (`10.100.9.222`) | `i-0f8040d65a2410272` (`10.100.10.38`) | app-demo-001 (`10.100.8.0/22`) — migrated |
| atento-001 | (puma `10.254.11.185`, SG `sg-0d40db569f5088ef9`) | (sidekiq `10.254.9.233`) | Production (`10.254.0.0/16`) |
| shared-001 | (identify before migration) | (identify before migration) | Production (`10.254.0.0/16`) |
| setup | (identify before migration) | (identify before migration) | Production (`10.254.0.0/16`) |

**AMIs Created:**

| AMI | Name | Source Instance | Date |
|---|---|---|---|
| `ami-07f42d7a4b38cdb72` | `pgbouncer-beta-puma-20260304` | `i-077d3c08becaf18ca` | 2026-03-04 |
| `ami-0ae7c28aa1b1cc6b6` | `pgbouncer-beta-sidekiq-20260304` | `i-08cba0c0dbeb8a311` | 2026-03-04 |

### Phase 6 — After All Environments Done

**Pre-step: Clean non-Terraform security groups before VPC deletion.**
Before running `terraform apply` to destroy an old VPC, check for and delete non-Terraform managed security groups (created by Ansible, AWS CLI, or manually). Terraform cannot delete a VPC while non-default SGs exist. The default SG is deleted automatically with the VPC.

```bash
# List all non-default SGs in the target VPC
aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=<vpc-id>" \
  --query 'SecurityGroups[?GroupName!=`default`].[GroupId,GroupName]' \
  --output table --region us-east-1

# Verify no ENIs are attached (safe to delete)
aws ec2 describe-network-interfaces \
  --filters "Name=group-id,Values=<sg-id>" \
  --query 'NetworkInterfaces[].NetworkInterfaceId' --region us-east-1

# Delete each non-default SG
aws ec2 delete-security-group --group-id <sg-id> --region us-east-1
```

Also check for and remove any unmanaged NLBs, ALBs, or other VPC-bound resources not in Terraform state.

1. Remove old Production VPC (after shared-001 migrated) — **DONE** (2026-03-08) — VPC destroyed, 2 manual SGs deleted (PGBouncer-sg, production-rds-app-2), peering Production↔Management removed, SSM params deleted via Terraform
2. Remove old Beta VPC (after beta-001 migrated) — **DONE** (2026-03-04)
3. Remove old 4app-atento VPC (if confirmed unused) — **DONE** (2026-03-05) — VPC destroyed, 2 manual SGs deleted (pgbouncer-atento-sg, 4app-atento-br-teste-rds-sg)
4. Remove old peering connections — **DONE** — no leftover peerings (all 5 active peerings are the permanent Management↔new VPC ones)
5. Remove old SSM parameters — **DONE** — no leftover `/networking/production/*` or `/networking/beta/*` params (destroyed with Terraform)
6. Add `nat_gateway_eips` SSM parameters for old VPCs — **N/A** — no remaining consumers of old VPCs
7. Update Pritunl VPN route push — **DONE**
8. Migrate old RDS instances to `4shark-master` KMS key — **moved to separate project**
9. Import `4shark-master` KMS key into Terraform — **moved to separate project**
11. Delete PgBouncer AMIs — **DONE** (2026-03-08) — beta AMIs already deleted; atento AMIs (`ami-0b5ec35e86b136def` pgbouncer-atento-sidekiq, `ami-0f72f0c5ee66b4b61` pgbouncer-atento-puma) deregistered, no orphaned snapshots

## Effort Estimate Per Environment

| Phase | Time |
|---|---|
| Phase 1 — VPC infrastructure (Terraform) | ~30min |
| Phase 2 — New RDS + logical replication | ~1-2h (depends on DB size) |
| Phase 3 — App migration + deploy | ~1-2h |
| Phase 4 — Verification + cleanup | ~30min |
| Phase 5 — PgBouncer migration via AMI | ~1h |
| **Total per environment** | **~4-6h** |

Day 1 (beta) took longer because we established the VPC template pattern. Subsequent days will be faster (copy VPC file + adjust CIDRs/names).

## Lessons Learned (from beta-001 migration)

### Cross-region VPC Peering
- Management VPC (sa-east-1) must be the **requester** — default provider is sa-east-1
- **Must use** `peer_region = "us-east-1"` on the connection
- **Must add** `aws_vpc_peering_connection_accepter` with `provider = aws.us_east_1` and `auto_accept = true`

### RDS gp3 < 400 GB
- AWS rejects explicit `iops` and `storage_throughput` values for gp3 with < 400 GB storage
- Do NOT pass these parameters — AWS applies defaults (3000 IOPS, 125 MiBps) automatically
- Old imported RDS instances have these values in state but were never validated by the create API

### RDS Master Password
- Old RDS instances were created manually — no password in Terraform
- Module had `ignore_changes = [password]` but no `password` variable
- New instances use `manage_master_user_password = true` — AWS Secrets Manager handles creation and rotation (every 7 days)
- Cost: $0.40/month per secret (negligible)

### KMS Key — `4shark-master`
- Created as Multi-Region key: primary us-east-1, replica sa-east-1
- Key ID: `mrk-fa0cda243274491784fc7b39bead5a03`
- Alias: `alias/4shark-master`
- Key policy allows: `rds.{region}.amazonaws.com` + `secretsmanager.{region}.amazonaws.com`
- Old KMS key (`64b7af79-...`) didn't have Secrets Manager permission — caused `KMSKeyNotAccessibleFault`
- Created via CLI, not yet in Terraform state — import in Phase 5

### Temporary VPC Peering for RDS Replication
- New RDS (subscriber) needs to reach old RDS (publisher) on port 5432
- New and old VPCs are in the same region (us-east-1) but have no connectivity by default
- Solution: temporary same-region VPC peering, managed via Terraform
- Simpler than cross-region: both sides use same provider (`aws.us_east_1`), auto-accept works natively
- Must also add SG rule on old RDS to allow ingress from new VPC CIDR
- Created in Phase 1, removed in Phase 4 cleanup
- For beta-001: app-beta-001 ↔ Beta VPC
- For all others (demo, atento, shared, setup): new VPC ↔ Production VPC

### Old RDS VPN Access During Migration
- Old VPNs were **inside** the old VPCs — RDS SGs allowed access via SG-reference rules, not CIDR
- The current VPN (Pritunl in Management VPC, `10.255.0.0/16`) is NOT in those SG-reference rules
- **Only affects beta-001**: Beta VPC had its own VPN (SG `sg-01689947e4f5c6e53`). The other environments are in Production VPC, which already has Management VPC peering and the old Production VPN may already have CIDR-based access — verify before each migration
- Fix: temporary SG rule on old RDS — ingress port 5432 from `10.255.0.0/16`, removed in Phase 4

### MongoDB Atlas IP Whitelist
- All environments had hardcoded NAT Gateway IPs — fragile, manual process
- Added `nat_gateway_eips` SSM parameter to `networking_data` module contract
- During migration: both old (hardcoded) and new (dynamic) IPs coexist
- After migration: old hardcoded IP removed in Phase 4 cleanup
- Temporary pattern: `module.new_vpc_data` used in Phase 2 (before `networking_environment` changes), switched to `module.vpc_data` in Phase 3

### ALB VPC Migration — Known AWS Provider Bug (Phase 3)

This is a **known, unresolved bug** in `terraform-provider-aws` ([issue #18317](https://github.com/hashicorp/terraform-provider-aws/issues/18317), open since 2021). The provider does NOT mark `subnets` as `ForceNew` on `aws_lb`, so when subnets from a different VPC are provided, Terraform tries to update in-place and AWS rejects it.

**The root problem**: When changing `networking_environment`, three things change simultaneously:
1. Security groups → new VPC SG (ALB can't use SGs from a different VPC)
2. Subnets → new VPC subnets (ALB can't switch VPCs in-place)
3. Target group `vpc_id` → ForceNew, TG is correctly replaced

**Approaches that FAILED during beta-001:**

1. `replace_triggered_by = [aws_security_group.alb[0].id]` — Works on clean state, but **fails in partial state** (if a previous apply already replaced the SG, the trigger sees no change and doesn't fire). This happened: first apply replaced SGs but failed on ALB/TG → SGs became deposed → second plan saw no SG change → ALB stayed "update in-place".

2. `terraform_data` tracking `var.vpc_id` — Failed because the `terraform_data` resource was being **created** (first time in state), not changed. `replace_triggered_by` only fires on CHANGE, not CREATE.

3. `create_before_destroy = true` on target groups — Failed because AWS doesn't allow two target groups with the same `name`. The new TG tries to create before the old one is destroyed → `ELBv2 Target Group (name) already exists`. See [issue #35717](https://github.com/hashicorp/terraform-provider-aws/issues/35717).

**Working solution — `replace_triggered_by` on the Target Group ID:**

```hcl
resource "aws_lb" "this" {
  # ... existing config ...

  # Force ALB replacement when target group is replaced (e.g., VPC migration).
  # ALBs cannot change subnets/SGs across VPCs in-place — AWS rejects it.
  # TG has vpc_id as ForceNew, so VPC change → TG replaced → ALB replaced.
  lifecycle {
    replace_triggered_by = [aws_lb_target_group.this.id]
  }
}

# Target groups use default lifecycle (destroy-then-create).
# Do NOT add create_before_destroy — causes name collision.
resource "aws_lb_target_group" "this" {
  name   = local.target_group_name
  vpc_id = var.vpc_id  # ForceNew — triggers replacement on VPC change
  # ...
}
```

**Why this works**: `aws_lb_target_group.this` has `vpc_id` as ForceNew → TG is replaced → TG ID changes → `replace_triggered_by` fires on ALB → ALB is also replaced. Without `create_before_destroy` on the TG, Terraform uses the default destroy-then-create order. Since the ALB is ALSO being replaced (destroyed first), the listeners are destroyed with it, freeing the TG references. Full sequence:

1. Destroy old listeners (part of old ALB)
2. Destroy old ALB (~19s)
3. Destroy old TG (now unreferenced)
4. Create new TG
5. Create new ALB (~2m24s)
6. Create new listeners

**This fix is permanent in `modules/public_alb/main.tf`** and handles all future VPC migrations automatically. No manual `-replace` flags needed.

**TODO**: Apply the same fix to `modules/internal_alb/main.tf` before migrating environments that use internal ALBs.

### ECS Service — Task Set Desync After TG Replacement (Phase 3)

When the ALB target group is replaced (VPC migration), the ECS service's PRIMARY task set retains the **old TG ARN** (now destroyed). This happens because `load_balancer` is in `ignore_changes` (CodeDeploy manages it during blue/green). The service cannot place tasks — it tries to register targets in a non-existent TG.

CodeDeploy deployments also fail with `INVALID_ECS_SERVICE`: *"The target ECS service must be configured using one of those two target groups."* Since CodeDeploy controls task sets, you cannot create/update task sets manually via `aws ecs create-task-set` either.

**Working solution — `replace_triggered_by` via `terraform_data` tracking TG ARNs:**

```hcl
# In modules/ecs_service/main.tf
resource "terraform_data" "lb_config" {
  input = length(var.load_balancers) > 0 ? jsonencode([for lb in var.load_balancers : lb.target_group_arn]) : null
}

resource "aws_ecs_service" "this" {
  # ... existing config ...

  lifecycle {
    ignore_changes = [desired_count, task_definition, load_balancer]

    # Force service replacement when TG is replaced (VPC migration).
    # TG replaced → TG ARN changes → terraform_data changes → service replaced.
    replace_triggered_by = [terraform_data.lb_config]
  }
}
```

**Why `terraform_data` and not direct TG reference**: The `ecs_service` module doesn't have access to the TG resource — it receives the TG ARN via `var.load_balancers`. The `terraform_data` bridges this gap by tracking the ARN value.

**First-time bootstrap**: On the first environment (beta-001), the `terraform_data` was **created** (not changed), so `replace_triggered_by` did not fire. A one-time `terraform apply -replace` was needed. For subsequent environments, the `terraform_data` already exists in state → when TG is replaced → ARN changes → `terraform_data` changes → service is automatically replaced. **No manual `-replace` needed after the first environment.**

**Post-replacement behavior**: After the service is recreated with the correct TG, ECS places tasks using the task definition revision in Terraform state. Under normal circumstances, this revision has all environment variables and the application starts correctly — **no GitHub deploy needed**.

**beta-001 exception**: In beta-001, the task definition in Terraform state (`:102`) was a broken revision with only `ALB_HOSTNAME`, likely from a previous misconfigured apply. This caused tasks to fail with exit code 1 after service recreation. A GitHub deploy was needed to bring the correct task definition. This is NOT expected in other environments — their Terraform state references task definitions that are actively running with full env vars.

The full sequence after terraform (normal case):

1. Terraform destroys old service (~52s)
2. Terraform creates new service with correct TG (~1s)
3. ECS places task using task definition in state (immediate — shows as "pending")
4. Task starts, passes ALB health checks (~2-3 min)
5. Application is available

**A GitHub deploy is only needed to update environment variables** — specifically `MIGRATION_DATABASE_URL` to point to the new RDS endpoint (bypass PgBouncer for migrations). The main `DATABASE_URL` goes through PgBouncer — that update is done in PgBouncer config, not via deploy.

**Key insight**: The combination of `replace_triggered_by` on `public_alb` (TG → ALB) and on `ecs_service` (TG ARN → service) creates a complete cascade: VPC change → TG replaced → ALB replaced + service replaced → everything in sync.

### Terraform Deposed Objects (Partial Apply Recovery)

When `terraform apply` partially succeeds (some resources replaced, others fail), the old replaced resources become **deposed** in state. On the next successful apply, Terraform destroys the deposed objects automatically. This happened during beta-001 Phase 3: the first apply replaced the SGs but failed on the ALB and TG. The old SGs became deposed and were cleaned up on the subsequent apply.

**Key takeaway**: If an apply fails mid-way, do NOT panic. Fix the root cause in code, re-plan, and apply again. Terraform's deposed object tracking ensures the old resources are properly cleaned up.

### ASG Instances Stuck in `Terminating:Wait` After VPC Migration

After terraform replaces the ASG configuration (new subnets), old EC2 instances enter `Terminating:Wait` state. This is caused by ECS lifecycle hooks that wait for tasks to drain. The instances prevent the old ECS security group (deposed) from being deleted (`DependencyViolation: has a dependent object`).

**Resolution**: Wait for the lifecycle hook timeout (default 1-3 hours) or complete the lifecycle action manually via AWS CLI. The old SG cleanup will succeed on the next `terraform apply` after the instances are fully terminated.

### PgBouncer Security Group — Manual CIDR Update Required (Phase 3)

PgBouncer instances live in the **old VPC** and their security groups only allow connections from the old VPC CIDR (e.g., `10.154.0.0/16`). After VPC migration, ECS tasks run in the new VPC (e.g., `10.100.0.0/16`) and connect to PgBouncer via VPC peering. The peering routes traffic correctly, but the PgBouncer SG **blocks** it — resulting in `/health` returning 500 with connection timeouts.

**Fix**: Before or during Phase 3, add **two rules** to the PgBouncer security group:

1. **Port 6432** (PgBouncer) — new VPC CIDR, so ECS tasks can connect to the database
2. **Port 22** (SSH) — VPN CIDR (`10.255.0.0/16`), so engineers can SSH into PgBouncer for maintenance

```bash
# Allow ECS tasks from new VPC to connect to PgBouncer
aws ec2 authorize-security-group-ingress \
  --group-id <pgbouncer-sg-id> \
  --protocol tcp --port 6432 \
  --cidr <new-vpc-cidr>/16

# Allow SSH from VPN for maintenance access
aws ec2 authorize-security-group-ingress \
  --group-id <pgbouncer-sg-id> \
  --protocol tcp --port 22 \
  --cidr 10.255.0.0/16
```

**This must be done for every environment.** Each environment has its own PgBouncer instances with their own SGs. Check the PgBouncer SG before migrating each environment to avoid health check failures after terraform apply.

Additionally, the **new RDS security group** must allow connections from the old VPC where PgBouncer lives:

3. **Port 5432** (PostgreSQL) on the **new RDS SG** — PgBouncer IP/32, so PgBouncer can reach the new database

**Use the specific PgBouncer IP/32, not the entire old VPC CIDR.** This minimizes the blast radius. To find the PgBouncer IP:
```bash
aws ec2 describe-instances --filters "Name=tag:Name,Values=pgbouncer-*-puma" \
  --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`].Value|[0],IP:PrivateIpAddress,VpcId:VpcId}' --output table
```

```bash
# Allow PgBouncer from old VPC to connect to new RDS
aws ec2 authorize-security-group-ingress \
  --group-id <new-rds-sg-id> \
  --protocol tcp --port 5432 \
  --cidr <old-vpc-cidr>/16
```

**This must be done for every environment.** Each environment has its own PgBouncer instances in the old VPC and a new RDS in the new VPC. Both SGs need cross-VPC rules.

### PgBouncer Configuration — Update Endpoint AND Database Name (Phase 3)

When updating PgBouncer to point to the new RDS, **two things must change** in `pgbouncer.ini`:

1. **Host**: old RDS endpoint → new RDS endpoint
2. **Database name**: old name → new standardized name (see "Database Name Standardization" table above)

| Environment | Old dbname | New dbname | New RDS endpoint |
|---|---|---|---|
| beta-001 | `beta` | `app_beta_001` | `app-beta-001.cvw5l7p4adp1.us-east-1.rds.amazonaws.com` |
| demo-001 | `dffadv994f5eph` | `app_demo_001` | (created during Phase 2) |
| shared-001 | `dk2016j8l9blr` | `app_shared_001` | (created during Phase 2) |
| atento-001 | `dk2016j8l9blr` | `app_atento_001` | `app-atento-001-cluster.cluster-cvw5l7p4adp1.us-east-1.rds.amazonaws.com` |
| setup | (verify) | `setup` | (created during Phase 2) |

**If you only change the host but keep the old dbname, PgBouncer will connect to the new RDS but fail to find the database** — resulting in 500 errors with connection timeouts (~11-26s).

Update **both** PgBouncer instances (puma and sidekiq) and restart each after the change.

**Note**: These are manual, temporary steps because PgBouncer is managed via Ansible, not Terraform. After full migration, PgBouncer should be moved to the new VPC (managed via Terraform) and all cross-VPC rules become unnecessary — see "Future Improvements" section.

### Non-Terraform Security Groups Block VPC Deletion (Phase 6)

When deleting a VPC via Terraform, non-default security groups that were NOT created by Terraform (e.g., created by Ansible, AWS CLI, or manually) block the VPC deletion. Terraform only manages resources in its state — it cannot delete SGs it doesn't know about.

**Symptoms**: `terraform apply` hangs for 10+ minutes trying to destroy the VPC, or fails with dependency errors.

**Root cause (beta-001)**: The Beta VPC had 8 non-default SGs created by Ansible for PgBouncer, ECS, RDS, etc. These SGs had 0 ENIs attached (all resources were already terminated/migrated) but still existed in the VPC, preventing deletion.

**Fix**: Before running `terraform apply` to destroy a VPC:
1. List all non-default SGs in the VPC
2. Verify each has 0 ENIs (safe to delete — SGs are VPC-scoped, cannot be used from other VPCs)
3. Delete them via AWS CLI
4. Then run `terraform apply`

Also check for other non-Terraform VPC-bound resources: NLBs, ALBs, NAT Gateways, VPC endpoints, etc.

**This step is now documented in Phase 6 as a mandatory pre-step.**

### MongoDB Atlas / Redis Cloud Credentials

The `.envrc` file at the terraform project root contains provider credentials (MongoDB Atlas, Redis Cloud, Cloudflare). These must be sourced before running terraform commands. `direnv` auto-loads them, but in contexts where direnv is not active (e.g., Claude Code sessions), you must run `source /path/to/.envrc` first. If you see `HTTP 401 Unauthorized` from MongoDB Atlas, this is the cause — the plan generates as "incomplete" and cannot be applied.

### Post-Terraform Application Availability (Phase 3)

After `terraform apply` completes for Strategy A (downtime), the application is **NOT immediately available**. The sequence after terraform finishes:

1. **Terraform replaces ALB + TG + ECS service** (~3-5 min)
2. **ASG already has instances** in the new VPC (if `desired_capacity >= 1`)
3. **ECS service places tasks immediately** after recreation — no GitHub deploy needed
4. **Task starts + ALB health checks** pass (~2-3 min)

Total warm-up after terraform: **~3-5 minutes** before the application starts receiving traffic. This is in addition to the terraform apply time itself (~5-10 min for ALB replacement). **Total estimated downtime: ~10-15 minutes.**

**Important — ASG `desired_capacity`**: The ASG must have at least 1 instance running for tasks to be placed immediately. If `desired_capacity = 0` (as happened in beta-001 due to external autoscaler scaling down), you must scale up the ASG before or after terraform apply. Consider adding `desired_capacity` to terraform config for environments where min_size is 0 to ensure instances are available post-migration.

**No GitHub deploy needed for service startup**: The ECS service recreation picks up the task definition from Terraform state automatically. After terraform completes, the app comes up on its own. A deploy is only needed to update env vars (e.g., `MIGRATION_DATABASE_URL`).

For **Strategy B** (parallel infrastructure), there is no downtime because the old infrastructure continues serving traffic until DNS is switched.

### Phase 3 Migration Strategies — Updated Decision

After beta-001 experience, **all environments can use Strategy A (accept downtime)** if there is a maintenance window available (e.g., nighttime when no one is using). Strategy B (parallel infrastructure) is only needed if there is **no viable maintenance window** (e.g., 24/7 integrations).

| Environment | Strategy | Rationale |
|---|---|---|
| beta-001 | A (downtime) | Test environment, done |
| setup | A (downtime) | Low traffic, no integrations |
| demo-001 | A (downtime) | Night window viable |
| atento-001 | B (zero downtime) | Production environment, DB already migrated, ECS/ALB migration pending |
| shared-001 | A (downtime) | Night window — verify no 24/7 integrations first |

## Internal References

- Spike: `~/.claude/plans/active/spike/4shark-network-architecture/SPIKE.md`
- Beta migration spike (superseded): deleted 2026-03-04
- Completed networking plan: `~/.claude/plans/completed/centralize-networking/PLAN.md`
- Current VPC files: `networking/vpc_production.tf`, `networking/vpc_4app_atento.tf`, `networking/vpc_app_beta_001.tf`
- Peering: `networking/peering.tf`
- SSM: `networking/ssm.tf`
- ECS cluster module: `modules/ecs_cluster/main.tf` (line 25: `name = "${var.environment}-cluster"`)
- RDS modules: `modules/rds_aurora_cluster/`, `modules/rds_instance/`

## Future Improvements (post-migration)

### Dynamic DNS — Replace Hardcoded ALB DNS in Cloudflare Records

Tracked separately in spike: `~/.claude/plans/active/spike/dns-centralization/SPIKE.md`

### PgBouncer Under Terraform Management

PgBouncer instances are migrated to the new VPCs via AMI in Phase 5, but remain managed via **Ansible** (not Terraform). A future improvement is to bring PgBouncer under Terraform management (EC2 instances, security groups, NLB) for consistency with the rest of the infrastructure.

## Execution Status

### app-beta-001 — COMPLETED (2026-03-03)

**PR**: https://github.com/4shark/terraform/pull/211 (pending merge)

Phases 1-4 executed successfully. Phase 5 (PgBouncer migration) pending:

| Phase | Status | Notes |
|---|---|---|
| Phase 1 — VPC infrastructure | Done | VPC, peering (Management + temporary Beta), SSM params |
| Phase 2 — New RDS + replication | Done | RDS `app-beta-001` created, logical replication synced |
| Phase 3 — Application migration | Done | Strategy A (downtime). ALB, ECS, DNS cutover. App 100% |
| Phase 4 — Cleanup | Done | Old RDS destroyed, temp SG rules removed, old NAT IP removed from MongoDB. Sequences fixed via Rails `reset_pk_sequence!` (2026-03-05). |
| Phase 5 — PgBouncer migration | Done | New instances: `i-0be93fb6331d2476f` (puma, `10.100.5.204`), `i-0c4a9a7f589dc9e04` (sidekiq, `10.100.6.147`). SG `sg-0f7827e1109614a90`. Deploy GH run 22665040530 successful. Old instances terminated. AMIs deregistered + snapshots deleted. |
| Phase 6 — Old VPC removal | Done | Beta VPC (`10.154.0.0/16`) destroyed via Terraform. Temp peering, SSM params, outputs removed. 8 non-Terraform SGs cleaned via CLI before VPC deletion. NLB `pgbouncer-beta` deleted (never used). |

**What was cleaned up:**
- Old RDS `beta-001` — removed from state + deleted via AWS CLI (skip final snapshot)
- Temporary SG rules on old RDS (VPN access + new VPC replication access)
- Old hardcoded NAT Gateway IP from MongoDB Atlas whitelist
- `module "new_vpc_data"` — replaced by `module.vpc_data` after `networking_environment` switch
- Old PgBouncer instances terminated (`i-077d3c08becaf18ca`, `i-08cba0c0dbeb8a311`)
- AMIs deregistered (`ami-07f42d7a4b38cdb72`, `ami-0ae7c28aa1b1cc6b6`) + orphaned snapshots deleted
- Old Beta VPC (`10.154.0.0/16`) destroyed — `vpc_beta.tf` deleted, peering/SSM/outputs cleaned from code
- 8 non-Terraform SGs in Beta VPC (Ansible-managed) deleted via CLI before VPC deletion
- NLB `pgbouncer-beta` deleted (unused, not in Terraform)
- Hevo RDS `fourshark-hevo-2` (SQL Server Express) deleted — unrelated to migration, freed VPC slot
- S3 bucket `hevo-data-4shark` deleted (empty, unused)

**Incident — PgBouncer connectivity (2026-03-03):**
After Phase 4 cleanup, the application returned 500 on all requests. Root cause: the new RDS security group did not include the PgBouncer IP. Additionally, the PgBouncer config had `dbname=beta` (old name) instead of `dbname=app_beta_001` (new name), causing `FATAL: database "beta" does not exist` even after the SG was fixed. Both issues were resolved: SG rule added via AWS CLI + Terraform, PgBouncer config updated and restarted. **Lesson**: the PgBouncer SG rule on the new RDS must be in place from Phase 2 (when the RDS is created), and the PgBouncer `dbname` must be updated during Phase 3 cutover.

**Note on other environments:** beta-001's PgBouncer is in the old Beta VPC (`10.154.0.0/16`). For demo-001, atento-001, shared-001, and setup — the PgBouncer instances are in the old Production VPC (`10.254.0.0/16`). Since those environments currently share the same VPC with their PgBouncer, the cross-VPC SG rule will be needed per-environment after migration. However, a single `aws ec2 describe-instances` query with tag filter `pgbouncer-*` will identify all PgBouncer IPs upfront.

### app-demo-001 — COMPLETED (2026-03-04)

**Commit**: `feat(demo-001): migrate app-demo-001 to dedicated VPC` (PR #211)

| Phase | Status | Notes |
|---|---|---|
| Phase 1 — VPC infrastructure | Done | VPC `10.100.8.0/22`, peering (Management + temporary Production), SSM params |
| Phase 2 — New RDS + replication | Done | RDS `app-demo-001-cluster` created, logical replication synced |
| Phase 3 — Application migration | Done | Strategy A (downtime). ALB, ECS, DNS cutover. App 100%. ASG scaling issue (desired_capacity=0, instances stuck in Terminating:Wait — resolved with complete-lifecycle-action + set-desired-capacity). |
| Phase 4 — Cleanup | Done | Old RDS `demo-001-cluster` destroyed, replication stopped, state cleaned. Sequences fixed via Rails `reset_pk_sequence!` (2026-03-05). |
| Phase 5 — PgBouncer migration | Done | New instances: `i-0e3ea81dda473f90b` (puma, `10.100.9.222`), `i-0f8040d65a2410272` (sidekiq, `10.100.10.38`). SG `sg-0a80b90660ca6a0dd`. Deploy GH run 22690691135 successful. Old instances terminated. AMIs deregistered + snapshots deleted. VPC peering demo-001 ↔ Production destroyed. |

**What was cleaned up:**
- Old RDS `demo-001-cluster` — deletion protection disabled via CLI, destroyed via Terraform, state cleaned
- Temporary VPC peering app-demo-001 ↔ Production (`pcx-0f0dee09a8c9ce925`) destroyed
- Old PgBouncer instances terminated (`i-0d94ee11d885895be`, `i-04af861d35a147a24`)
- Cross-VPC SG rules removed from old PgBouncer SG (`sg-027773fe5068c6ab4`)
- AMIs deregistered + orphaned snapshots deleted
- Old PgBouncer IP/32 rules removed from new RDS SG

**Incident — Deploy JSON parse error (2026-03-04):**
First deploy failed (GH run 22688809257) because MIGRATION_DATABASE_URL had a newline in the database name (`app_demo\n_001`). Caused by copy-paste line break. Fix: wrote URL to `/tmp/` file to avoid terminal line wrapping.

**Incident — ASG not scaling (2026-03-04):**
ASG had `desired_capacity=0` with 6 instances stuck in `Terminating:Wait` (lifecycle hook `ecs-managed-draining-termination-hook`). Fix: `complete-lifecycle-action` on all 6 instances, then `set-desired-capacity 1`. **Lesson**: after Terraform recreates ECS service, check ASG state and complete pending lifecycle actions before expecting the service to scale.

### app-atento-001 — IN PROGRESS (2026-03-05)

| Phase | Status | Notes |
|---|---|---|
| Phase 1 — VPC infrastructure | Done | VPC `10.100.12.0/22`, peering (Management + temporary Production), SSM params. NAT Gateway created after quota increase (5 → 10 approved). |
| Phase 2 — New RDS + replication | Done | RDS `app-atento-001-cluster` created (Aurora PG 15.13, 2x db.t4g.large). Double failover on old cluster for `rds.logical_replication=1` (zero-downtime reboot). Roles created, schema restored via pgAdmin, logical replication synced (LSN lag = 0). |
| Phase 2.5 — Database cutover (early) | Done | PgBouncer (puma `10.254.11.185` + sidekiq `10.254.9.233`) updated to point to new RDS (`10.100.14.220`). DB name changed: `dk2016j8l9blr` → `app_atento_001`. MIGRATION_DATABASE_URL updated. Sequences fixed post-cutover. Replication stopped (subscription + publication dropped). Old cluster `atento-001-cluster` stopped (removed public internet access). |
| Phase 3 — Application migration | Not started | Strategy B (zero downtime) chosen. ECS/ALB still in Production VPC. |
| Phase 4 — Cleanup | Partial | Old RDS stopped (not yet destroyed). Replication cleaned up. Full cleanup after Phase 3. |
| Phase 5 — PgBouncer migration | Not started | |

**Incidents:**

- **PG::InsufficientPrivilege after PgBouncer cutover**: Application got `permission denied for table users`. Cause: logical replication subscription runs as `postgres`, so data was inserted by `postgres`. Write user `seVEbZU7UkcwjcuJM4MH` needed explicit `GRANT ALL ON ALL TABLES/SEQUENCES`. Fix applied, lesson added to Step 8d for future environments.

- **Sequences not replicated**: After cutover, sequences were at initial values from schema restore. Fixed with `setval()` script on all sequences. Lesson added as Step 11 in Phase 2 for future environments.

- **Shell escaping with Secrets Manager ARN**: The `!` in `rds!cluster-...` was expanded by bash/zsh. Multiple escape attempts failed. Fix: used `python3 << 'PYEOF'` heredoc to avoid all shell escaping.

**PgBouncer details:**
- Puma: `10.254.11.185`, SG `sg-0d40db569f5088ef9` (SSH rule added from VPN `10.255.0.0/16`)
- Sidekiq: `10.254.9.233`
- Write user: `seVEbZU7UkcwjcuJM4MH`
- Read user: `qwwoymczHrJJGG2smfR3`
- Pool names unchanged: `atento001_master` / `atento001_follower`

**Key difference from previous environments:** Database was cut over early (Phase 2.5) via PgBouncer config change, before ECS/ALB migration. This eliminated the publicly-accessible old RDS sooner. The ECS/ALB infrastructure still runs in the Production VPC and will be migrated in Phase 3 using Strategy B (parallel infrastructure, zero downtime).

### app-shared-001 — IN PROGRESS (2026-03-06)

| Phase | Status | Notes |
|---|---|---|
| Phase 1 — VPC infrastructure | Done | VPC `10.100.0.0/22`, peering (Management + temporary Production), SSM params. |
| Phase 2 — New RDS + replication | In progress | RDS `app-shared-001-cluster` created (Aurora PG 15.13, 2x db.t4g.large). Roles created (write: `ezmrcJDJeJaPtVuP`, read: `DiYtoADDmejVyXhg`). Schema restored, logical replication running (~20h estimated, started 15:55 UTC). Pending: replication sync, sequence fix, GRANTs, PgBouncer cutover to new RDS. |
| Phase 5 — PgBouncer migration (early) | Done | AMIs created. New instances launched in new VPC: puma `i-0dd0d5c92ec9daf66` (`10.100.1.42`, t3a.micro), sidekiq `i-09821249b0c9d18fb` (`10.100.2.105`, t3a.small). SG `sg-02c09ac26801f8eee`. Deploy updated DATABASE_URL + DATABASE_REPLICA_URL. Old instances terminated. |
| Phase 3 — Application migration | Done | Strategy B (zero downtime). New ECS cluster `app-shared-001-cluster` created (72 resources). DNS switched to new ALB (`app-shared-001-lb-247694779.us-east-1.elb.amazonaws.com`). Old cluster `shared-001-cluster` fully decommissioned via CLI. Deploy workflow fixed (PR #4858 — SIDEKIQ_SERVICES names). GitHub env vars updated. |
| Phase 4 — Cleanup | Partial | Old cluster destroyed (all resources: 8 services, 9 ASGs, 9 CPs, 9 LTs, 1 ALB + 2 listeners + 2 TGs, 1 CodeDeploy app, 4 Lambdas, 10 schedules, IAM role + instance profile, 1 ALB SG). 7 orphaned SGs in Production VPC deleted. 2 SGs pending (referenced by old RDS and OpenSearch default SG). Old RDS `shared-001-cluster` still running — cleanup after DB cutover. Terraform changes committed on `feature/vpc-app-beta-001`. |

**Phase 3 details:**
- Deploy workflow fix: `shared-001-*` → `app-shared-001-*` in SIDEKIQ_SERVICES (PR #4858 in app repo)
- GitHub env vars updated: CLUSTER_NAME, CODEDEPLOY_APP_NAME, CODEDEPLOY_DEPLOYMENT_GROUP, CODEDEPLOY_HOOK_LAMBDA_ARN, WEB_SERVICE_NAME (rollback values saved in memory)
- Successful deploy: GH run 22783059054
- Old cluster services scaled to 0, lifecycle hooks completed manually, all EC2 instances terminated

**Phase 5 early migration — temporary SG rule:**
- New PgBouncer SG (`sg-02c09ac26801f8eee`) — temporary ingress port 6432 from old VPC CIDR (`10.254.0.0/16`) can now be removed (ECS is in new VPC)
- **CLEANUP**: Remove this rule in next terraform apply

**Remaining for DB cutover (Phase 2 completion + Phase 4):**
1. Wait for logical replication to finish syncing
2. Fix sequences on new RDS (logical replication does NOT replicate sequences)
3. Apply GRANTs on new RDS for write/read users
4. Update PgBouncer config: point to new RDS (`app-shared-001-cluster`) + dbname `app_shared_001`
5. Deploy application (picks up new DB connection)
6. Stop replication (drop subscription + publication)
7. Destroy old RDS `shared-001-cluster` (disable deletion_protection, delete via CLI)
8. Remove old RDS SG `sg-05ff12e712f05682f` (production-rds-app-2) — blocked until old RDS deleted
9. Remove old PgBouncer SG `sg-027773fe5068c6ab4` (PGBouncer-sg) — blocked by RDS SG reference, delete after RDS SG
10. Remove temporary PgBouncer SG rule (old VPC CIDR ingress)
11. Commit terraform changes on `feature/vpc-app-beta-001`
12. Deregister AMIs (`ami-06b868450789fbba5`, `ami-004f31f3987f7971c`) + delete orphaned snapshots

**PgBouncer details:**
- New puma: `i-0dd0d5c92ec9daf66` (`10.100.1.42`)
- New sidekiq: `i-09821249b0c9d18fb` (`10.100.2.105`)
- AMIs: `ami-06b868450789fbba5` (puma), `ami-004f31f3987f7971c` (sidekiq)
- Pool names: `shared001_master` (write), `shared001_follower` (read)
- Currently pointing to old RDS (`shared-001-cluster`). After replication completes, update to new RDS (`app-shared-001-cluster`) + dbname `app_shared_001`.

**Production VPC — remaining resources:**
- RDS `shared-001-cluster` (2 ENIs) — delete after DB cutover
- 2 NAT Gateways (`nat-03a84a02d1e0337cd`, `nat-0cf6c4c14802c0e38`) — remove when VPC is decommissioned
- SG `sg-05ff12e712f05682f` (production-rds-app-2) — delete after old RDS destroyed
- SG `sg-027773fe5068c6ab4` (PGBouncer-sg) — delete after old RDS SG removed
- SG `sg-0e7cb6a64d4fcc54b` (default) — VPC default SG, removed with VPC
- SG `sg-0e57cacbcc2424568` (4Shark-Setup-prd-db) — **DELETED** (2026-03-07), old setup RDS no longer exists
- Zero EC2 instances, zero ALBs, zero ECS clusters — VPC is nearly empty

### setup — COMPLETED (2026-03-07)

| Phase | Status | Notes |
|---|---|---|
| Phase 1 — VPC infrastructure | Done | VPC `10.100.128.0/24` (smaller /24 block, not /22), peering (Management), SSM params. |
| Phase 2 — New RDS | Done | RDS `setup` created (standalone PG 16.9, db.t3.micro). `manage_master_user_password = true`. No logical replication needed — downtime approach used. |
| Phase 3 — Application migration | Done | Downtime approach. Temporary peering setup ↔ Production created for DB connectivity during transition. ECS/ALB migrated to setup VPC. DNS updated in Cloudflare (`setup-pub-lb-1905299106`). CodeDeploy deployment `d-RK377FP7I` successful (td :10). |
| Phase 4 — Cleanup | Done | Old RDS `setup-001` destroyed (final snapshot `setup-001-final`). Temporary peering setup ↔ Production removed (5 resources). Temporary SG ingress from Production VPC removed. Deposed SG `sg-047f7c07002d96530` destroyed. Code cleaned: old RDS module removed, `rds_instance_new` renamed to `rds_instance`, `new_vpc_data` removed. All committed on `feature/vpc-app-beta-001`. |
| Phase 5 — PgBouncer migration | N/A | Setup has no PgBouncer. |

**Key notes:**
- Setup used a smaller /24 CIDR (`10.100.128.0/24`) instead of /22 — smaller environment, separated from /22 app environment slots
- No logical replication was needed — simple downtime approach (create new RDS, migrate via app deploy)
- Temporary peering to Production VPC was needed because ECS was initially in Production VPC while RDS was already in setup VPC (VPC peering is not transitive — ECS couldn't reach setup RDS through Management VPC)
- CodeDeploy `CODE_DEPLOY` deployment controller required `aws deploy create-deployment` with AppSpec (not `aws ecs update-service --task-definition`)
