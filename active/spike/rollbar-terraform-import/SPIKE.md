# SPIKE — Rollbar projects import via Terraform provider

**Conducted by:** Engineer
**Date:** 2026-03-03
**Status:** Research complete — pending decisions

---

## Goal

Investigate how to import all existing Rollbar projects into Terraform, considering:
- Each backend app has its own Rollbar project
- Each frontend also has its own Rollbar project
- Frontends are being imported via Netlify in a parallel session
- The Terraform project uses independent stacks per environment

---

## Method

- Researched the Rollbar Terraform provider on the Terraform Registry and GitHub
- Analyzed the existing Terraform project structure and conventions
- Reviewed community best practices and known issues
- Examined the official import tooling

---

## Evidence

### Provider Overview

| Attribute | Value |
|-----------|-------|
| Registry | `rollbar/rollbar` (official, verified by HashiCorp) |
| Version | `1.16.0` (April 2025) |
| GitHub | `rollbar/terraform-provider-rollbar` |
| Maturity | Production-ready, maintained by Rollbar |

### Available Resources

| Resource | Description | Import |
|----------|-------------|--------|
| `rollbar_project` | Create/manage projects | Yes — by `project_id` |
| `rollbar_project_access_token` | Project access tokens | Yes — by `project_id/public_id` |
| `rollbar_team` | Create/manage teams | Yes — by `team_id` |
| `rollbar_notification` | Notification rules (email, Slack, PagerDuty, webhook) | Yes — by `channel,id` |

### Available Data Sources

| Data Source | Description |
|-------------|-------------|
| `rollbar_project` | Read project by ID or name |
| `rollbar_projects` | List all projects |
| `rollbar_project_access_token` | Read token by `project_id` + `name` |
| `rollbar_team` | Read team by ID or name |

### Authentication

Two tokens required:

```hcl
provider "rollbar" {
  api_key         = var.rollbar_account_token   # Account Access Token (read/write)
  project_api_key = var.rollbar_project_token   # Project Access Token (for notifications)
}
```

Environment variables: `ROLLBAR_API_KEY`, `ROLLBAR_PROJECT_API_KEY`

### Official Import Tool

Rollbar maintains [`rollbar-terraform-importer`](https://github.com/rollbar/rollbar-terraform-importer) — a Go utility that:
- Takes an account token
- Queries Rollbar API and generates `.tf` files (projects.tf, teams.tf, access_tokens.tf)
- Generates import commands
- Requires manual review after generation

### Known Issues (Critical)

**Issue #437 (Feb 2026) — Token creation non-idempotent**: `rollbar_project_access_token` create returns success but subsequent Read fails. Each `terraform apply` creates duplicate tokens. **No workaround documented.** Recommendation: import existing tokens as data sources instead of creating new ones via resource.

**Issue #432 (Aug 2025) — Built-in team drift**: Assigning the built-in "Everyone" team to a project via `team_ids` causes perpetual drift. Workaround: use only custom teams.

### Key Architectural Facts

- **Environments are NOT Terraform resources** — they're auto-created when SDKs send errors with an `environment` field. Nothing to manage in Terraform.
- **One Rollbar project can serve multiple environments** — production/staging/development are just labels on errors within the same project.
- **Token scopes `post_client_item` and `post_server_item` cannot be combined** with other scopes in the same token.

### Current Project Structure Analysis

The Terraform project uses independent stacks. Relevant patterns:
- `dns/` — centralized DNS management (Cloudflare + Route53)
- `networking/` — centralized VPC management
- `app-{env}/` — per-environment ECS stacks
- Cross-stack references via SSM Parameter Store
- Auth via environment variables in `.envrc`

Rollbar projects are **organization-level resources**, not environment-specific. A single Rollbar project like "app" serves all environments (prod, staging, beta). This means Rollbar does NOT fit the per-environment stack pattern.

---

## Conclusions

### 1. Provider is production-ready for projects

The `rollbar/rollbar` provider is official, verified, and well-maintained. The `rollbar_project` resource works correctly for creating and importing projects.

### 2. Token management has a critical bug

The `rollbar_project_access_token` resource has a non-idempotent creation bug (#437). For existing projects, **use the data source** to read tokens instead of the resource to create them. New tokens should be created manually or with caution.

### 3. Centralized stack is the right pattern

Since Rollbar projects are organization-level (not per-environment), a single `rollbar/` stack managing all projects is the correct approach. This follows the same pattern as `dns/` and `networking/`.

### 4. Recommended structure

```
rollbar/
├── providers.tf          # rollbar provider + AWS (for SSM)
├── projects.tf           # all rollbar_project resources
├── frontends.tf          # frontend rollbar projects (linked to Netlify apps)
├── tokens.tf             # data sources for existing tokens (avoid resource due to bug)
├── teams.tf              # rollbar_team resources (if managing team access)
├── variables.tf
├── terraform.tfvars
└── output.tf             # export token values to SSM Parameter Store
```

### 5. Frontend projects belong in the Rollbar stack, not Netlify

Even though frontends are deployed via Netlify, their Rollbar projects are Rollbar resources. The Rollbar stack should manage them and export tokens that the Netlify stack can reference (via SSM Parameter Store or Terraform remote state).

### 6. Import workflow

1. Use `rollbar-terraform-importer` to generate initial `.tf` files and import commands
2. Review and restructure generated code to match project conventions
3. Run `terraform import` commands
4. Validate with `terraform plan` (should show no changes)
5. Export tokens to SSM Parameter Store for consumption by app stacks

---

## Next Steps

- **Decision needed**: confirm the centralized `rollbar/` stack approach
- **Decision needed**: define the naming convention for projects (e.g., `app`, `integrator-atento-br`, `app-webclient`)
- **Decision needed**: whether to manage teams and notifications via Terraform or only projects
- **Action**: generate a PLAN.md for implementation once decisions are made
