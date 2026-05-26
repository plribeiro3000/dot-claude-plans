# SPIKE — MongoDB Atlas Management Tools for Terraform Integration

**Conducted by:** Engineering Team
**Date:** 2026-02-25
**Status:** COMPLETE — Decisions made, implementation done as Part 3 of Infrastructure Standardization (`~/.claude/plans/active/terraform/infrastructure-standardization/PLAN.md`)

---

## Goal

The team manages MongoDB clusters on MongoDB Atlas (mongodb.com) and wants to start managing them via Terraform. Before beginning implementation, we need to understand:

1. What Terraform provider exists for MongoDB Atlas, its capabilities, version, and limitations
2. What the Atlas CLI (`atlas`) can do and how it aids Terraform import workflows
3. What the MongoDB Atlas Administration API offers and how to authenticate
4. A practical workflow for importing existing Atlas resources into Terraform state
5. Whether any third-party tools exist to auto-generate Terraform code from Atlas

---

## Method

- Web searches covering official documentation, GitHub repositories, and community sources
- Direct fetch of GitHub release pages, CHANGELOG, and resource directory listings
- Review of official Terraform Registry documentation references
- Review of official MongoDB docs for the Atlas CLI and Administration API

---

## Evidence

### 1. MongoDB Atlas Terraform Provider

**Provider name:** `mongodb/mongodbatlas`
**Registry URL:** https://registry.terraform.io/providers/mongodb/mongodbatlas/latest

**Current version (as of 2026-02-25):** `v2.7.0` (released 2026-02-18)

**Release cadence:**
- Minor and patch versions: biweekly
- Major versions: once per year, maximum two per calendar year
- Since v2.0.0, minor and patch releases do NOT include breaking changes (semantic versioning guarantee)

**Provider configuration block:**

```hcl
terraform {
  required_providers {
    mongodbatlas = {
      source  = "mongodb/mongodbatlas"
      version = "~> 2.7"
    }
  }
}

provider "mongodbatlas" {
  # Recommended: use environment variables
  # MONGODB_ATLAS_PUBLIC_KEY
  # MONGODB_ATLAS_PRIVATE_KEY
  # or Service Account:
  # MONGODB_ATLAS_CLIENT_ID
  # MONGODB_ATLAS_CLIENT_SECRET
}
```

**Complete list of manageable resources (71 resources documented):**

Cluster & Database:
- `mongodbatlas_advanced_cluster` (recommended — replaces legacy `mongodbatlas_cluster`)
- `mongodbatlas_cluster` (legacy, still supported)
- `mongodbatlas_flex_cluster`
- `mongodbatlas_serverless_instance`
- `mongodbatlas_database_user`
- `mongodbatlas_custom_db_role`

Backup & DR:
- `mongodbatlas_cloud_backup_schedule`
- `mongodbatlas_cloud_backup_snapshot`
- `mongodbatlas_cloud_backup_snapshot_export_bucket`
- `mongodbatlas_cloud_backup_snapshot_export_job`
- `mongodbatlas_cloud_backup_snapshot_restore_job`
- `mongodbatlas_backup_compliance_policy`

Networking:
- `mongodbatlas_network_container`
- `mongodbatlas_network_peering`
- `mongodbatlas_privatelink_endpoint`
- `mongodbatlas_privatelink_endpoint_service`
- `mongodbatlas_custom_dns_configuration_cluster_aws`
- `mongodbatlas_encryption_at_rest`
- `mongodbatlas_encryption_at_rest_private_endpoint`
- `mongodbatlas_project_ip_access_list`

Access & Auth:
- `mongodbatlas_api_key`
- `mongodbatlas_api_key_project_assignment`
- `mongodbatlas_access_list_api_key`
- `mongodbatlas_x509_authentication_database_user`
- `mongodbatlas_ldap_configuration`
- `mongodbatlas_ldap_verify`

Organization & Projects:
- `mongodbatlas_organization`
- `mongodbatlas_project`
- `mongodbatlas_org_invitation`
- `mongodbatlas_project_invitation`
- `mongodbatlas_team`
- `mongodbatlas_team_project_assignment`

Additional:
- Search indexes, event triggers, federated databases, stream processing, third-party integrations, and alert configurations are also included.

**Breaking changes in v2.0.0 (released mid-2025):**

Resources removed:
- `mongodbatlas_data_lake_pipeline` and related pipeline data sources
- `mongodbatlas_privatelink_endpoint_serverless`
- `mongodbatlas_teams` data source (replaced by `mongodbatlas_team`)

Attribute removals from `mongodbatlas_advanced_cluster`:
- `advanced_configuration.default_read_concern`
- `advanced_configuration.fail_index_key_too_long`
- `id`, `disk_size_gb`, replication spec-related legacy fields

Other changes:
- `mongodbatlas_advanced_cluster`: `delete_on_create_timeout` default changed from `false` to `true`
- `mongodbatlas_cloud_backup_schedule`: `export` and `auto_export_enabled` now optional-only
- `mongodbatlas_custom_db_role`: `actions` attribute now treated as order-insensitive
- Full migration from SDKv2 to the new Terraform Plugin Framework

**Known limitations and gotchas:**

- **Autoscaling drift**: When Atlas autoscaling changes cluster size, Terraform's `lifecycle.ignore_changes` cannot accept dynamic expressions or variables — the ignore list must be hardcoded. This is a Terraform limitation, not Atlas-specific.
- **Backup import gap**: Importing existing clusters does not always populate the backup status correctly (GitHub issue #768 — historical, status unclear for v2.x).
- **API key permissions**: Terraform import requires at minimum `Project Read Only` for reads, but some operations require `Organization Owner`.
- **IP access list requirement**: Atlas enables the API IP access list by default. API calls from unlisted IPs return HTTP 403. This applies to Terraform operations as well.
- **Cluster creation time**: Creating or importing clusters can take 10–15 minutes. Terraform `apply` will block during provisioning.
- **Deprecated resource `mongodbatlas_cluster`**: Still functional but the recommendation is to migrate all configurations to `mongodbatlas_advanced_cluster`.

---

### 2. MongoDB Atlas CLI (`atlas`)

**What it is:** The official MongoDB CLI for managing Atlas resources from the terminal. Fully separate from `mongocli` (which targets Cloud Manager and Ops Manager, not Atlas).

**mongocli vs atlas CLI:**
- `mongocli` manages Cloud Manager and Ops Manager
- `atlas` CLI manages MongoDB Atlas
- Since `mongocli` v2.0, Atlas subcommands were fully removed from `mongocli` — these are completely separate tools
- The correct tool for Atlas management is `atlas` CLI

**Installation:**
```bash
# macOS (Homebrew) — installs atlas CLI and mongosh
brew install mongodb-atlas-cli

# Or download binary from:
# https://www.mongodb.com/try/download/atlas-cli
```

**Authentication methods:**

| Method | Command | Best for |
|--------|---------|---------|
| User Account | `atlas auth login` | Interactive/developer use, valid 12h |
| Service Account | `atlas auth login` (ServiceAccounts option) | Programmatic/automated use |
| API Keys | `atlas auth login` (APIKeys option) | Legacy programmatic use |

Environment variables for non-interactive:
```bash
export MONGODB_ATLAS_PUBLIC_KEY="<public-key>"
export MONGODB_ATLAS_PRIVATE_KEY="<private-key>"
# or for Service Accounts:
export MONGODB_ATLAS_CLIENT_ID="<client-id>"
export MONGODB_ATLAS_CLIENT_SECRET="<client-secret>"
```

**Main command categories:**

| Category | Description |
|----------|-------------|
| `atlas auth` | Login, logout, authentication state |
| `atlas clusters` | Create, list, update, delete, pause, start clusters |
| `atlas projects` | Create, list, update, delete projects |
| `atlas organizations` | List organizations, manage org settings |
| `atlas dbusers` | Manage database users |
| `atlas accessLists` | Manage IP access lists |
| `atlas backups` | Snapshots, exports, restores |
| `atlas networking` | Network peering |
| `atlas privateEndpoints` | Private endpoint management |
| `atlas security` | Encryption, LDAP, X.509 |
| `atlas customDbRoles` | Custom database roles |
| `atlas metrics` | Cluster and process metrics |
| `atlas logs` | Download host logs |
| `atlas alerts` | Alert configuration and management |
| `atlas maintenanceWindows` | Maintenance window settings |
| `atlas liveMigrations` | Live migrations to Atlas |
| `atlas local` | Local Atlas instances |
| `atlas api` | Direct API access (full coverage) |

**Key commands for Terraform import discovery:**

```bash
# List all organizations (get org IDs)
atlas organizations list

# List all projects in an org
atlas projects list --orgId <org-id>

# List all clusters in a project
atlas clusters list --projectId <project-id>

# Get cluster details (includes cluster name for import)
atlas clusters describe <cluster-name> --projectId <project-id>

# List all database users
atlas dbusers list --projectId <project-id>

# List all IP access list entries
atlas accessLists list --projectId <project-id>

# List all network peering connections
atlas networking peering list --projectId <project-id>

# List all private endpoints
atlas privateEndpoints list --projectId <project-id>

# List backup snapshots
atlas backups snapshots list --clusterName <name> --projectId <project-id>
```

The Atlas CLI is the most practical tool for discovering existing resource IDs before running `terraform import`.

---

### 3. MongoDB Atlas Administration API

**Base URL:** `https://cloud.mongodb.com/api/atlas/v2`
**Full reference:** https://www.mongodb.com/docs/api/doc/atlas-admin-api-v2/

**Authentication methods:**

| Method | Status | How it works |
|--------|--------|--------------|
| Service Accounts (OAuth 2.0) | Recommended | Client ID + Secret, scoped to organization |
| API Keys (HTTP Digest) | Legacy (still functional) | Public key + Private key, Digest auth |

Service accounts are preferred over API keys for new integrations. Each service account belongs to one organization and can be granted access to multiple projects within it.

**IP access list requirement:** Atlas enforces an IP allowlist for all API calls by default. Requests from non-allowlisted IPs return HTTP 403. This must be configured before any API or Terraform usage.

**Rate limits:** ~100 requests per minute per project. Exceeding the limit returns HTTP 429 (Too Many Requests).

**Key endpoints for resource discovery:**

```bash
# List all projects in an organization
GET /api/atlas/v2/orgs/{orgId}/groups

# List all clusters in a project
GET /api/atlas/v2/groups/{groupId}/clusters

# List all flex clusters in a project
GET /api/atlas/v2/groups/{groupId}/flexClusters

# List all database users
GET /api/atlas/v2/groups/{groupId}/databaseUsers

# List all IP access list entries
GET /api/atlas/v2/groups/{groupId}/accessList

# List all network peering containers
GET /api/atlas/v2/groups/{groupId}/containers

# List all private endpoints
GET /api/atlas/v2/groups/{groupId}/privateEndpoint

# Return all organizations (requires org-level key)
GET /api/atlas/v2/orgs
```

**curl example (API key with Digest auth):**
```bash
curl --user "{PUBLIC-KEY}:{PRIVATE-KEY}" \
  --digest \
  --header "Accept: application/vnd.atlas.2025-03-12+json" \
  -X GET "https://cloud.mongodb.com/api/atlas/v2/orgs/{orgId}/groups?pretty=true"
```

**API versioning:** The API uses date-based versioning in the Accept header (e.g., `application/vnd.atlas.2025-03-12+json`). Using the correct version is required.

---

### 4. Practical Import Workflow

**Import ID formats by resource type:**

| Resource | Import ID format | Example |
|----------|-----------------|---------|
| `mongodbatlas_project` | `{project_id}` | `5d09d6a59ccf6445652a444a` |
| `mongodbatlas_advanced_cluster` | `{project_id},{cluster_name}` | `5d09d6a59ccf6445652a444a,MyCluster` |
| `mongodbatlas_database_user` | `{project_id}-{username}-{auth_db}` | `5d09...–myuser–admin` |
| `mongodbatlas_database_user` (with dashes) | `{project_id}/{username}/{auth_db}` | `5d09.../my-user/admin` |
| `mongodbatlas_project_ip_access_list` | `{project_id}-{entry}` | `5d09...-10.0.0.1/32` |
| `mongodbatlas_network_peering` | `{project_id}-{peering_id}` | `5d09...-5e69...` |

**Step-by-step import workflow:**

1. **Discover all resources using Atlas CLI or API**
   ```bash
   atlas organizations list                         # get org IDs
   atlas projects list --orgId <org-id>             # get project IDs and names
   atlas clusters list --projectId <project-id>     # get cluster names
   atlas dbusers list --projectId <project-id>      # get database users
   atlas accessLists list --projectId <project-id>  # get IP access list entries
   ```

2. **Write Terraform resource blocks (empty, to receive state)**
   ```hcl
   resource "mongodbatlas_project" "main" {}
   resource "mongodbatlas_advanced_cluster" "production" {}
   resource "mongodbatlas_database_user" "app_user" {}
   ```

3. **Run `terraform import` for each resource**
   ```bash
   terraform import mongodbatlas_project.main <project-id>
   terraform import mongodbatlas_advanced_cluster.production <project-id>,<cluster-name>
   terraform import mongodbatlas_database_user.app_user <project-id>/<username>/admin
   ```

4. **Run `terraform plan` to identify configuration drift**
   After import, Terraform compares state with the empty resource blocks. The plan output shows all attributes that need to be added to the HCL to match the real state.

5. **Fill in the HCL configuration**
   Copy the values from `terraform show` output to build accurate resource configurations.

6. **Validate with `terraform plan`**
   Goal: a plan showing "No changes. Your infrastructure matches the configuration."

**Autoscaling consideration:**
For clusters with autoscaling enabled, add `lifecycle.ignore_changes` with the auto-managed attributes:
```hcl
lifecycle {
  ignore_changes = [
    replication_specs[0].region_configs[0].electable_specs[0].instance_size,
    replication_specs[0].region_configs[0].electable_specs[0].disk_iops,
  ]
}
```

---

### 5. Third-Party Tools and Auto-Generation

**Terraformer (GoogleCloudPlatform/terraformer):**
- A popular open-source tool that reverse-engineers existing infrastructure into Terraform code
- MongoDB Atlas support was requested (GitHub issue #589) but **was never officially implemented** as of the investigation date
- Terraformer does NOT support MongoDB Atlas

**MongoDB Atlas official tooling:**
- No official tool exists to auto-generate Terraform HCL from existing Atlas resources
- The recommended workflow is manual: discover via CLI/API → write empty resource blocks → `terraform import` → `terraform show` → fill in config

**Other tools found:**
- `atlascli` (Python, github.com/jdrumgoole/atlascli): Unofficial Python client for the Atlas API — useful for scripting discovery, not HCL generation
- HashiCorp Vault Atlas Secrets Engine: Manages Atlas API keys through Vault, not relevant for import
- VS Code MongoDB extension: Can generate cluster templates for Terraform, but only for new clusters — not import

**Conclusion on automation:**
No mature tool auto-generates Terraform HCL from existing Atlas resources. The process is manual but well-documented through the provider's import documentation for each resource.

---

## Conclusions

1. **The official provider is `mongodb/mongodbatlas` at v2.7.0** — actively maintained, biweekly releases, 71 managed resources, full Atlas Admin API coverage.

2. **The Atlas CLI (`atlas`)** is the most practical tool for pre-import discovery. It can list all organizations, projects, clusters, database users, IP access lists, and network resources — exactly what is needed to gather import IDs before running `terraform import`.

3. **`mongocli` is not the right tool** for Atlas. It manages Cloud Manager and Ops Manager. Atlas management requires the `atlas` CLI specifically.

4. **The Admin API provides full programmatic access** but requires proper authentication setup (IP allowlist + API key or Service Account). The CLI wraps this API and is easier to use for discovery tasks.

5. **No tool auto-generates Terraform HCL** from existing Atlas resources. Terraformer does not support Atlas. The workflow is manual: discover → import → inspect state → write config.

6. **The import workflow is well-supported** but labor-intensive for large deployments. Each resource requires a separate `terraform import` command with a resource-type-specific ID format.

7. **Key gotchas to plan for:**
   - IP allowlist must be configured before any API/Terraform usage
   - Autoscaling clusters need `lifecycle.ignore_changes` to prevent Terraform drift
   - Cluster creation/modification operations take 10–15 minutes
   - Use `mongodbatlas_advanced_cluster` — the legacy `mongodbatlas_cluster` is deprecated
   - Pin provider version to `~> 2.7` to avoid unexpected breaking changes in future majors

---

## Decisions Made

1. **Authentication method**: API Keys (HTTP Digest). Service Account (OAuth 2.0) was tried first but access tokens expire, causing 401 errors. API Keys don't expire — valid until manually revoked.
   - Public Key: `pvgxbddy`
   - Role: Organization Owner
   - Credentials in `.envrc` (gitignored), loaded via `direnv`

2. **Scope of import**: Full import — projects, clusters, database users, IP access lists, network peering, and backup schedules. Phased approach: import as-is first, then standardize.

3. **Implementation**: Done as Part 3 of Infrastructure Standardization (`~/.claude/plans/active/terraform/infrastructure-standardization/PLAN.md`). Module created at `modules/mongodb_atlas/`, 4 environments configured.

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
>
> **Further reading:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/technical-spike/)
