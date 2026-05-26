# SPIKE — Netlify Terraform Provider: viability and integration strategy

**Conducted by:** Engineering Team
**Date:** 2026-03-03 → 2026-03-12
**Status:** Closed — decisions made, see PLAN.md

> Merged from two spikes: `netlify-terraform-integration` (2026-03-03) and `netlify-terraform` (2026-03-12).

---

## Goal

Evaluate the current state of the Netlify Terraform provider and define the integration strategy for the project. Specific questions:

1. Does the official `netlify/netlify` provider support team member management?
2. Does Netlify have SSO/SAML? Is it configurable via Terraform?
3. What resources are available in the provider?
4. Are there alternatives to the provider if it is insufficient?
5. How should ~47 Netlify sites be organized in the project structure?
6. Can DNS (Cloudflare) and site configuration (Netlify) coexist in separate stacks?
7. What is the import strategy for existing sites?
8. How should environment variables be managed?
9. How to integrate with Terramate?

**Context**: The `identity/` stack already manages engineer access on AWS, MongoDB Atlas, Cloudflare, and GitHub. The original goal was to add Netlify to that stack. There are 4 applications with a total of ~47 frontends: AppBeta 001 (~1), AppDemo 001 (~6), AppAtento 001 (~7), AppShared 001 (~33).

---

## Method

- Web search for current provider state (version, resources, roadmap)
- WebFetch directly on GitHub (`netlify/terraform-provider-netlify`) to list resources and data sources
- WebFetch on Netlify OpenAPI spec (`open-api.netlify.com`) to verify API support
- WebFetch on official Netlify SSO documentation
- Analysis of open issues in the provider repository
- Analysis of existing project structure (stacks, `for_each` patterns, Terramate dependency graph)
- Count and mapping of all 47 Netlify CNAME records in `dns/public_dns_app4shark_com.tf`
- Review of Terraform 1.5+ import block support with `for_each`

---

## Evidence

### 1. Official provider and current version

The official provider is **`netlify/netlify`** (not `hashicorp/netlify`, which is archived).

- **Current version**: `v0.4.1` (released February 12, 2026) — pre-1.0, active development
- **Registry**: `registry.terraform.io/providers/netlify/netlify`
- The HashiCorp provider (`hashicorp/terraform-provider-netlify`) has been **archived** since before 2024 and must not be used
- There is also a community provider `AegirHealth/netlify` in the registry, but it is not maintained by Netlify

**References**:
- https://github.com/netlify/terraform-provider-netlify
- https://registry.terraform.io/providers/netlify/netlify/latest

---

### 2. Resources available in provider v0.4.1

**Resources (12 total):**

| Resource | Description |
|---|---|
| `netlify_deploy_key` | Manages SSH deploy keys |
| `netlify_dns_record` | Manages DNS records (not needed — DNS is on Cloudflare) |
| `netlify_dns_zone` | Manages DNS zones (not needed — DNS is on Cloudflare) |
| `netlify_environment_variable` | Environment variables (site or team-level) |
| `netlify_log_drain` | Log drain configuration |
| `netlify_site_build_settings` | Build command, publish dir, production branch |
| `netlify_site_collaboration_settings` | Enables/disables Netlify Drawer and HUD in previews |
| `netlify_site_domain_settings` | Custom domain assignment (Netlify-side only) |
| `netlify_site_firewall_traffic_rules` | Site-level firewall rules |
| `netlify_site_metrics_settings` | Site metrics settings |
| `netlify_team_firewall_traffic_rules` | Team-level firewall rules |
| `netlify_waf_policy` | WAF policy |

**Data Sources (5 total):**

| Data Source | Description |
|---|---|
| `netlify_dns_zone` | DNS zone lookup |
| `netlify_managed_waf_rules` | Lists managed WAF rules |
| `netlify_site` | Looks up a site by `name` + `team_slug` or by `id` |
| `netlify_sites` | Lists all sites in a team (returns id, name, custom_domain, domain_aliases, team_slug) |
| `netlify_team` | Looks up a team by `id` or `slug` |

**Critical limitation**: The provider **cannot create sites** — sites must be created via UI or CLI and then imported. GitHub issue #39 tracks this — Netlify cited OAuth integration complexity as the blocker.

**References**:
- https://github.com/netlify/terraform-provider-netlify/tree/main/docs/resources
- https://github.com/netlify/terraform-provider-netlify/tree/main/docs/data-sources

---

### 3. Open issues in the provider

Of the 7 open issues, **none** address team members or SSO:

- `#126` — Incomplete Azure log drain
- `#95` — Custom SSL certificates
- `#62` — Community provider migration
- `#49` — Runtime configuration in `site_build_settings`
- `#40` — Deploy key creation
- `#39` — Site creation support (the current provider does not create sites, only manages configuration of existing ones)
- `#2` — Dependency updates (automated)

**Conclusion**: Team member management via Terraform **is not on the visible roadmap** of the provider.

**Reference**: https://github.com/netlify/terraform-provider-netlify/issues

---

### 4. Team member management

**Critical conclusion**: No `team_member`, `member`, `user`, or equivalent resource exists in the provider. The provider does not support engineer access management.

The Netlify OpenAPI spec (`open-api.netlify.com`) exposes member endpoints via REST API:

| Method | Endpoint | Action |
|---|---|---|
| `GET` | `/{account_slug}/members` | List team members |
| `GET` | `/{account_slug}/members/{member_id}` | Get member details |
| `POST` | `/{account_slug}/members` | Add member (email + role) |
| `PUT` | `/{account_slug}/members/{member_id}` | Update role and site access |
| `DELETE` | `/{account_slug}/members/{member_id}` | Remove member |

The `PUT` endpoint supports granular access control:
- `site_access: all` — access to all sites
- `site_access: none` — no site access
- `site_access: selected` — access only to specific sites (via `site_ids`)

**Roles available via API**: Owner, Developer, Billing Admin, Reviewer.

**Reference**: https://open-api.netlify.com/

---

### 5. SSO/SAML in Netlify

Netlify supports **SAML 2.0** (not native OIDC for platform login) in two scopes:

- **Team SSO**: configured per team individually (Team Settings > Access & Security > Authentication > Single sign-on)
- **Organization SSO**: configured at the organization level and applies to all teams (recommended by Netlify)

**Natively supported Identity Providers**: ADP, Auth0, Azure AD SAML, Duo, Google, LastPass, Okta, OpenID.

**Google Workspace as IdP**: Yes, Google is on the list of supported IdPs.

**Configuration via Terraform**: No `netlify_sso` or similar resource exists in the provider. SSO configuration is done **exclusively via the Netlify dashboard UI**. The documentation does not mention an API for SSO.

**Required plan**: **Enterprise** (custom pricing). Neither the Pro plan ($20/member/month) nor Personal include SSO/SAML.

**References**:
- https://docs.netlify.com/security/secure-netlify-access/configure-organization-saml-sso/
- https://docs.netlify.com/manage/security/secure-netlify-access/configure-team-saml-sso/
- https://www.netlify.com/pricing/

---

### 6. Provider alternatives

| Alternative | Assessment |
|---|---|
| `hashicorp/netlify` | Archived — do not use |
| `AegirHealth/netlify` | Old fork, not maintained by Netlify — do not use |
| `terraform-provider-http` / `null_resource + local-exec` | Functional for team members via REST API, but no proper Terraform state management |
| Pulumi | Wrapper of the same provider — inherits the same limitations |
| Netlify CLI | Supports basic operations but not member management |

**Conclusion**: No active, more complete community provider alternative exists. The Netlify REST API is the only option for managing members programmatically.

---

### 7. Site inventory and organization by stack

47 unique Netlify CNAMEs found in `dns/public_dns_app4shark_com.tf`, mapping to ~43 unique Netlify sites (some domains share the same site, e.g., `operador`, `vendedor`, `www`, and root all point to `fourshark-app-client.netlify.app`).

**What is possible via Terraform**:
- `data.netlify_sites` lists all sites in a team
- `data.netlify_site` looks up a specific site by name or ID
- `netlify_site_build_settings` manages build configuration of an existing site (importable by site_id)
- `netlify_environment_variable` manages environment variables, both per site and per team

**What is not possible via Terraform**:
- Creating a new site (issue #39 open; the provider has no `netlify_site` resource)
- Existing sites must be **imported** by `site_id` to be managed
- No tag, label, or native grouping of sites by application in Netlify

**Native organization in Netlify**: Sites are organized only by **team**. There is no concept of "project" or grouping by application. The only way to group is by naming convention (e.g., `fourshark-app-client-*`).

**Three organization options evaluated:**

**Option A: Inside existing `app-*` stacks (CHOSEN)**
- Add `netlify.tf` to each `app-*` stack
- Follows the existing pattern (each stack = complete environment)
- Uses `for_each` over a map in `terraform.tfvars` (same pattern as ECS services and RDS instances)
- No new directories
- `app-shared-001` would have ~33 sites but manageable with the map pattern

**Option B: Single `netlify/` stack**
- One state for all frontends
- Loses the frontend↔backend association
- Does not follow project conventions

**Option C: Separate `webclient-*` stacks**
- 4 new top-level directories
- Isolated states but more operational overhead

**Site distribution by stack:**

| Stack | Sites | Examples |
|---|---|---|
| `app-atento-001` | 7 | atento-ar, atento-cl, atento-co, atento-gt, atento-mx, atento-pe, atento-br |
| `app-beta-001` | 1 | beta |
| `app-demo-001` | 6 | demo, next, next-cl, next-co, next-mx, next-en |
| `app-shared-001` | ~33 | almaviva, bostonscientific, brisanet, hapvida, goodyear, and others |

**Viable HCL structure with `for_each` over site_ids per application:**

```hcl
# Per-application variables — manual mapping required
locals {
  sites_by_app = {
    appbet_001 = [
      "site-id-appbet-frontend-1"
    ]
    appdemo_001 = [
      "site-id-appdemo-frontend-1",
      "site-id-appdemo-frontend-2",
      # ...
    ]
    appatento_001 = [
      "site-id-atento-frontend-1",
      # ... up to 7 sites
    ]
    appshared_001 = [
      "site-id-shared-frontend-1",
      # ... 33+ sites
    ]
  }

  # Flatten for for_each: key = "app/site_id"
  all_sites_flat = merge([
    for app, site_ids in local.sites_by_app : {
      for site_id in site_ids : "${app}/${site_id}" => {
        app     = app
        site_id = site_id
      }
    }
  ]...)
}

# Example: apply environment variable to all sites of an application
resource "netlify_environment_variable" "api_url" {
  for_each = local.all_sites_flat

  team_id = data.netlify_team.main.id
  site_id = each.value.site_id
  key     = "API_URL"

  values = [{
    value   = var.api_url_by_app[each.value.app]
    context = "production"
  }]
}

# Example: import build settings of each site
resource "netlify_site_build_settings" "sites" {
  for_each = local.all_sites_flat

  site_id           = each.value.site_id
  production_branch = "main"
  build_command     = "npm run build"
  publish_directory = "dist"
}
```

**Critical limitation**: The `site_id` values must be obtained manually (via UI or Netlify CLI) and inserted as values in Terraform. There is no way to discover them automatically by application name, since grouping by application is not native to Netlify.

**Semi-automated alternative**: Use `data.netlify_sites` to list all sites and filter by name prefix (works if a consistent naming convention exists):

```hcl
data "netlify_sites" "all" {
  team_slug = "4shark"
}

locals {
  appshared_sites = {
    for s in data.netlify_sites.all.sites :
    s.name => s.id
    if startswith(s.name, "fourshark-app-client-")
  }
}
```

---

### 8. DNS (Cloudflare) vs Netlify configuration separation

`netlify_site_domain_settings` **configures the Netlify side only** — it tells Netlify "respond on this domain." It does NOT create DNS records. The Cloudflare CNAME in `dns/` is a completely independent resource.

This means:
- `app-*/netlify.tf` manages: build settings, env vars, domain assignment (Netlify-side)
- `dns/public_dns_app4shark_com.tf` manages: CNAME records (Cloudflare-side)
- No data dependency between the two — each configures its own side

The existing CNAME records have `proxied = false` (grey cloud), which is correct for Netlify (two CDNs in series cause SSL/caching issues).

---

### 9. Import strategy

- `data "netlify_site"` (read-only) **does not need import**
- `netlify_site_domain_settings` needs import only if the custom domain is already configured on the Netlify side
- Terraform 1.5+ supports `import` blocks with `for_each` for bulk import:

```hcl
# import.tf (temporary — remove after first apply)
import {
  for_each = local.netlify_site_ids
  to       = netlify_site_domain_settings.this[each.key]
  id       = each.value  # site UUID
}
```

- Site UUIDs can be discovered via the Netlify API:

```bash
curl -H "Authorization: Bearer $NETLIFY_TOKEN" \
  https://api.netlify.com/api/v1/sites | jq '.[] | {name, id}'
```

- `-generate-config-out` **does not work** with `for_each` import blocks (confirmed limitation)
- Import blocks are idempotent and can be safely removed after the first apply

---

### 10. Environment variables

The `netlify_environment_variable` resource supports context-specific values (production, deploy-preview, branch-deploy, dev).

**Proposed structure in `terraform.tfvars`:**

```hcl
netlify_sites = {
  "almaviva" = {
    domain = "almaviva.app4shark.com"
    env_vars = {
      "API_URL"   = { production = "https://api-shared.app4shark.com" }
      "TENANT_ID" = { production = "almaviva" }
      "LOCALE"    = { production = "pt-BR" }
    }
  }
}
```

**HCL pattern with `for_each` over nested env vars:**

```hcl
locals {
  netlify_env_vars = merge([
    for site_key, site in var.netlify_sites : {
      for var_key, var_val in site.env_vars :
        "${site_key}:${var_key}" => {
          site_key = site_key
          key      = var_key
          values   = var_val
        }
    }
  ]...)
}

resource "netlify_environment_variable" "this" {
  for_each = local.netlify_env_vars
  site_id  = data.netlify_site.this[each.value.site_key].id
  key      = each.value.key
  values   = [
    for ctx, val in each.value.values : {
      value   = val
      context = ctx
    }
  ]
}
```

**Sensitive variables**: The only potentially sensitive value is the Rollbar client-side token (`post_client_item` scope). This token can only send error events — it cannot read data or access server-side information. The worst case is an attacker sending fake errors. Rollbar provides rate limiting and IP blocklisting as mitigation. **Decision: all env vars (including the Rollbar token) go in `terraform.tfvars` — no external secret management needed.**

Env vars vary per site — there is a common base set, but some sites have additional optional vars. All must be imported.

---

### 11. Terramate integration

Current dependency graph:
```
shared-resources → app-atento-001, app-shared-001, app-beta-001, app-demo-001, setup
integrators + app-atento-br + vpn → dns
```

`dns/` currently does **not depend** on the `app-*` stacks. To make `terramate run terraform apply` work end-to-end (Netlify before DNS), add dependencies:

```hcl
# dns/stack.tm.hcl — add to existing after list
after = [
  # ... existing entries ...
  "/app-atento-001",
  "/app-beta-001",
  "/app-demo-001",
  "/app-shared-001",
]
```

---

### 12. Day-to-day workflow for a new frontend

```
1. Create site in Netlify          → Manual (UI or `netlify sites:create`)
2. Add entry to terraform.tfvars   → In the corresponding app-* stack
3. Add CNAME to dns/ stack         → In public_dns_app4shark_com.tf
4. terramate run terraform apply   → Applies app-* first, then dns/
```

---

## Conclusions

1. **The provider is viable** for managing site configuration (build settings, env vars, domains, firewall), but **not for site creation** — that remains manual.
2. **Team member management is not possible via Terraform** — no member resource in the provider and no roadmap indication.
3. **SSO requires Enterprise plan** — not available on the current plan; configuration exclusively via UI, no Terraform or API support.
4. **Option A (inside `app-*` stacks) is the right choice** — frontends go inside the `app-*` stack of their corresponding backend; no new stack needed.
5. **DNS and Netlify config are cleanly separable** — `netlify_site_domain_settings` configures the Netlify side only; Cloudflare CNAMEs remain in `dns/`.
6. **Bulk import is feasible** using Terraform 1.5+ `import` blocks with `for_each`, requiring a one-time API call to collect site UUIDs.
7. **All env vars go in `terraform.tfvars`** — no sensitive values require external management. Rollbar client token is post-only scope.
8. **Env vars vary per site** — there is a common base set but some sites have additional optional vars. All must be imported.
9. **Terramate dependency graph needs a minor update** to ensure `dns/` runs after `app-*` stacks.
10. **Migration approach: all at once** — not phased by environment.
11. **Netlify does not enter the `identity/` stack** — no member support via Terraform; members are managed via the Netlify Dashboard UI.

**Summary by need:**

| Need | Solution |
|---|---|
| Manage team members | Netlify REST API (`POST/DELETE /{account_slug}/members`) — or Dashboard UI |
| Configure SSO | Netlify Dashboard UI (once per organization) |
| Create new sites | UI or CLI (`netlify sites:create`) — then import into Terraform |
| Configure existing sites | Provider `netlify/netlify` v0.4.1 — adequate support |
| Organize sites by app | Local map with `site_id` + `for_each` in Terraform |

**Decisions evaluated before being made:**

**Team members (Decision 2):**
- A) Manage via REST API using `null_resource + local-exec` in the `identity/` stack — functional but no proper Terraform state management
- B) Exclude Netlify from the `identity/` stack and manage members manually via the Netlify Dashboard UI ← **chosen**
- C) Wait — monitor whether the provider will add member support (no signal in the current roadmap)

**SSO (Decision 3):**
- SSO requires Enterprise plan (custom pricing with Netlify)
- Configuration exclusively via UI, no Terraform
- Decision: do not upgrade to Enterprise — keep manual login/GitHub OAuth

**Sites via Terraform (Decision 4):**
- Manage existing sites inside `app-*` stacks (not in `identity/`)
- Obtain `site_id` per site via API or CLI (`netlify sites:list`)
- Define a consistent naming convention if not already in place (e.g., `{app}-{role}`, like `appshared-checkout`)

---

## Decisions Made

| # | Decision | Chosen |
|---|---|---|
| 1 | Provider | `netlify/netlify` v0.4.1 — official, maintained by Netlify |
| 2 | Team members | Manage via Netlify Dashboard UI — no provider support; Netlify excluded from `identity/` stack |
| 3 | SSO | Do not use — requires Enterprise. Keep manual login/GitHub OAuth |
| 4 | Organization | Option A — frontends inside `app-*` stacks |
| 5 | Env vars | All in `terraform.tfvars`, variable set per site (common base + optional) |
| 6 | Sensitive vars | None needed — Rollbar token is safe in tfvars (post_client_item scope only) |
| 7 | Migration | All sites at once, not incrementally |

---

## Next Steps

- **Action**: Add `netlify/netlify` provider to `app-atento-001`, `app-beta-001`, `app-demo-001`, `app-shared-001`
- **Action**: Create `netlify.tf` in each stack
- **Action**: Collect site UUIDs via Netlify API (`curl` + `jq`)
- **Action**: Collect current env vars from each Netlify site for the tfvars maps
- **Action**: Update Terramate dependency graph in `dns/stack.tm.hcl`

See full PLAN.md at `~/.claude/plans/active/terraform/netlify/PLAN.md`.

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
>
> **Further reading:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/technical-spike/)
