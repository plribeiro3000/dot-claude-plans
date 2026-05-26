# Community Research: Terraform + Netlify at Scale (40+ Sites)

**Date:** 2026-03-12
**Scope:** Community best practices for organizing Terraform when managing 40+ Netlify sites alongside backend infrastructure, with Terramate orchestration.
**Decision context:** Option A (add `netlify.tf` + `rollbar.tf` to existing `app-*` backend stacks) vs. Option B (create separate `webclient-*` stacks).

---

## 1. Terraform State Isolation — Community Guidance

### What is "too many resources" in one state file?

No single authoritative number exists, but multiple sources converge on practical thresholds:

| Source | Threshold | What Happens |
|---|---|---|
| HashiCorp Help Center | **5,000 objects** | "Terraform runs may become significantly slower" |
| Community benchmark | **300 resources** | Warning threshold — consider splitting |
| Community benchmark | **200 resources** | Recommended max per state for good performance |
| Real-world data | **1,600 resources** | `terraform plan` takes ~8 minutes |
| Real-world data | **2,900 resources** | `terraform plan` takes 20–25 minutes |
| State file size | **>10 MB** | Noticeable performance degradation |

**Sources:** [HashiCorp Help Center — Best Practices for HCP Terraform Workspace Size](https://support.hashicorp.com/hc/en-us/articles/38056391267091-Best-Practices-for-HCP-Terraform-Workspace-size), [Terraform GitHub Issue #16375](https://github.com/hashicorp/terraform/issues/16375), [Terraform GitHub Issue #18981](https://github.com/hashicorp/terraform/issues/18981)

### How does this apply to our scenario?

A single `app-shared-001` stack with ~33 Netlify sites + their Rollbar projects would add:
- ~33 `netlify_environment_variable` resources (per site, possibly multiple)
- ~33 Rollbar project resources
- ~33 Rollbar token resources
- Plus existing ECS, RDS, MongoDB, etc.

The resource count from the 33 Netlify sites alone would likely push `app-shared-001` toward or past the 200-resource warning threshold when combined with existing backend infrastructure.

### Key principle from Gruntwork (authoritative source)

> "If you manage the infrastructure for both the VPC component and the web server component in the same set of Terraform configurations, you are unnecessarily putting your entire network topology at risk due to frequent deployment changes."

The recommendation is that **resources with different change frequencies should be in separate state files**. Backend infrastructure (ECS, RDS, MongoDB) changes on a different cadence than Netlify site configuration.

**Source:** [Gruntwork — How to Manage Terraform State](https://gruntwork.io/blog/how-to-manage-terraform-state)

---

## 2. Critical Finding: `netlify_site` Resource Does NOT Exist in v0.4.1

**This is the most operationally significant finding of this research.**

The official `netlify/netlify` provider v0.4.1 does **not** include a `netlify_site` resource for creating sites. The supported resources are:

| Resource | Purpose |
|---|---|
| `netlify_deploy_key` | Deployment key management |
| `netlify_dns_record` | DNS record management |
| `netlify_dns_zone` | DNS zone configuration |
| `netlify_environment_variable` | Site environment variables |
| `netlify_log_drain` | Log drainage |
| `netlify_site_build_settings` | Build configuration |
| `netlify_site_collaboration_settings` | Team collaboration |
| `netlify_site_domain_settings` | Domain management |
| `netlify_site_firewall_traffic_rules` | Per-site firewall rules |
| `netlify_site_metrics_settings` | Metrics configuration |
| `netlify_team_firewall_traffic_rules` | Team-wide firewall |
| `netlify_waf_policy` | WAF policies |

**No `netlify_site` resource exists.** Sites can only be referenced as data sources (`data.netlify_site`). Site creation must happen outside Terraform.

**Issue #39** ("Support for creating site") has been open since August 2024 and had a community comment as recently as January 3, 2026 asking for updates. The Netlify maintainers identified a blocker:

> "The way that the non-official provider creates websites breaks several collaboration features that are enabled by the Netlify<->GitHub/Bitbucket/GitLab integration."

A draft PR (#56) was opened September 2024 but never merged.

**Implication for our decision:** All resources managed by Terraform for Netlify are configuration resources against **existing** sites, identified by `site_id`. This means `for_each` over sites is possible for config management (env vars, build settings, etc.) but not for site creation.

**Sources:** [GitHub — netlify/terraform-provider-netlify Issues](https://github.com/netlify/terraform-provider-netlify/issues), [Issue #39 — Support for creating site](https://github.com/netlify/terraform-provider-netlify/issues/39)

---

## 3. Netlify's Own Guidance on IaC at Scale

Netlify does not publish specific recommendations for managing 30+ sites via Terraform at scale. Their documentation covers:
- Provider setup and authentication
- Resources available (see section 2 above)
- Terraform 1.0+ and OpenTofu 1.0+ compatibility

No guidance exists on `for_each` patterns, state organization, or multi-site management strategies.

**Source:** [Netlify Terraform Provider Docs](https://docs.netlify.com/terraform-provider/)

---

## 4. `for_each` with 30+ Netlify Sites — Known Issues

No GitHub issues or community reports were found documenting specific problems with `for_each` across 30+ Netlify sites in the `netlify/netlify` provider.

The 7 open issues in the provider repository are:
1. Log drain Azure incomplete (#126)
2. Custom SSL certificates (#95)
3. Migration from community provider (#62)
4. Runtime through `netlify_site_build_settings` (#49)
5. `netlify_deploy_key` resource (#40)
6. Site creation resource (#39) — most significant
7. Renovate dependency dashboard (#2)

**No issues related to `for_each` performance, rate limiting, or large-scale usage exist.**

However, a general Terraform concern applies: when running `terraform plan` or `terraform apply` with `for_each` across many resources that call an external API (Netlify's API), each resource triggers API calls. Netlify's API rate limiting applies at the API level, not the provider level. No provider-level rate limiting implementation was found in the open issues.

**Source:** [GitHub — netlify/terraform-provider-netlify Issues](https://github.com/netlify/terraform-provider-netlify/issues)

---

## 5. Terramate Community — Frontend/Backend Stack Separation

### Official Terramate documentation

Terramate does not prescribe a specific "frontend vs. backend" separation pattern. It recommends organizing stacks around:
- **Logical service grouping**: "A stack should encompass a logical grouping of resources that work together to serve a specific purpose"
- **Change frequency**: "Frequently modified sections benefit from smaller stacks"
- **Team ownership**: "Creating separate stacks for each team may make sense if different teams or individuals are responsible for different parts of your infrastructure"

**Tagging pattern** (from Terramate docs): Teams tag stacks with `backend`, `frontend`, `prod`, `staging`, `aws`, `datastores` to selectively apply changes.

**Source:** [Terramate — Stacks Docs](https://terramate.io/docs/cli/stacks/), [Terramate — How to Structure and Size Terraform Stacks](https://terramate.io/rethinking-iac/how-to-structure-and-size-terraform-stacks/)

### Terramate Quickstart AWS reference architecture

The official Terramate quickstart organizes stacks as **environment first, then infrastructure component**:

```
stacks/terraform/envs/
├── stg/
│   ├── vpc/
│   ├── eks/
│   └── eks/apps/
│       ├── app1/
│       └── app2/
└── prd/
    └── (identical structure)
```

The quickstart separates by service type within an environment (VPC, EKS, apps), not by infrastructure layer (cloud vs. SaaS). The key insight: **services with different change cadences and different providers live in separate stacks.**

**Source:** [Terramate Quickstart AWS](https://github.com/terramate-io/terramate-quickstart-aws)

### Why separation matters for execution time

Terramate's own blog states: "Stacks with 10+ minute runtimes create bottlenecks. Smaller stacks reduce CI/CD delays and allow parallel deployments across different stack units."

A single plan/apply against `app-shared-001` with 33 Netlify sites would require hitting Netlify's API for every `netlify_environment_variable` resource on every run, even when the change is only in ECS or RDS.

**Source:** [Terramate — Why You Should Break Down Your Terraform into Stacks](https://terramate.io/rethinking-iac/why-you-should-break-down-your-terraform-into-stacks/)

---

## 6. Community Pattern: "Frontend Infra Stack" vs. "Backend Infra Stack"

### HashiCorp's own stack design documentation

> "Components are typically groups of related resources, such as an application's backend, frontend, or database layer, deployed and scaled together. You can create a dedicated Stack for shared services, such as networking infrastructure for VPCs, subnets, or routing tables, and separate Stacks for application components that consume those shared services."

This directly validates separating frontend configuration (Netlify) from backend infrastructure (ECS, RDS, MongoDB).

**Source:** [HashiCorp — Design a Stack](https://developer.hashicorp.com/terraform/language/stacks/design)

### Gruntwork's component separation principle

Gruntwork recommends separating infrastructure by **component type** (vpc, services, data-storage) within each environment. The principle that "changes to one component should not block changes to another" is their core state isolation driver.

Applied to our scenario: Netlify site configuration and ECS/RDS/MongoDB are clearly different components with different change rates and different risk profiles.

**Source:** [Gruntwork — How to Manage Terraform State](https://gruntwork.io/blog/how-to-manage-terraform-state)

### Taccoform's workspace-per-service recommendation

> "Putting multiple services in the same workspace creates unintentional dependencies between services and increases the blast radius when things go wrong."

Recommended: 1:1 mapping between Terraform workspaces (or in our case, Terramate stacks) and service deployments.

**Source:** [Taccoform — Multiple Provider Orchestration](https://www.taccoform.com/posts/tfg_p6/)

---

## 7. Mixing SaaS Provider + Cloud Provider in Same State

No community consensus explicitly labels this an anti-pattern, but the **rate-of-change principle** indirectly rules against it:

- Backend stack resources (ECS tasks, RDS parameter groups, MongoDB clusters) change rarely and have high blast-radius risk
- Netlify resources (environment variables, build settings) change frequently and have low individual blast radius
- A `terraform plan` against a mixed state must refresh **all** resources from all providers, including calling Netlify's API for each site on every run — even when the change is only in ECS

The community pattern for SaaS providers (Datadog, Cloudflare, Netlify) is to manage them in **dedicated stacks** or workspaces, separate from cloud infrastructure.

**Sources:** Multiple sources cited above

---

## 8. Summary Table: Evidence Matrix for Option A vs. Option B

| Criterion | Option A (add to `app-*` stacks) | Option B (separate `webclient-*` stacks) |
|---|---|---|
| **State isolation** | Mixed: backend + SaaS in one state | Clean: each concern in its own state |
| **Blast radius** | Higher: Netlify change could block backend deploy | Lower: isolated failure domains |
| **Plan performance** | Slower: refresh hits Netlify API on every backend plan | Faster: backend plans don't touch Netlify API |
| **Change frequency alignment** | Mismatched: high-churn Netlify + low-churn ECS | Aligned: each stack changes at its own rate |
| **HashiCorp guidance** | Against: components should be separated | Aligns: "backend, frontend, database" as separate stacks |
| **Gruntwork guidance** | Against: different change rates = different states | Aligns: component-level state separation |
| **Terramate guidance** | Against: stack should be "logical grouping serving specific purpose" | Aligns: frontend config is a distinct logical grouping |
| **Resource count (app-shared-001)** | Risk: adds ~100+ resources to already-large stack | Safe: distributes load across dedicated stacks |
| **Provider maturity** | Pre-1.0 provider risk concentrated in backend state | Same risk, but isolated from backend stability |
| **Operational coupling** | Netlify outage/API rate limit could block backend changes | Decoupled: backend changes unaffected |

---

## 9. Unanswered Questions (What Remains Unknown)

1. **How many resources are currently in `app-shared-001`?** The current resource count determines whether adding Netlify resources would cross a performance threshold. This requires running `terraform state list | wc -l` against the existing stack.

2. **Will the `netlify_site` resource ever be added to the provider?** The draft PR (#56) exists but is blocked on API design questions. If sites are created outside Terraform today, this may not matter for the current decision.

3. **Does Netlify's API have a documented rate limit for Terraform operations?** No specific documentation was found. With 33+ sites, a `terraform refresh` could trigger many parallel API calls.

4. **How often does the team need to change Netlify configuration vs. backend infrastructure?** The answer directly determines how much the change-frequency mismatch matters in practice.

---

## Sources

- [HashiCorp Help Center — Best Practices for HCP Terraform Workspace Size](https://support.hashicorp.com/hc/en-us/articles/38056391267091-Best-Practices-for-HCP-Terraform-Workspace-size)
- [Gruntwork — How to Avoid Large OpenTofu/Terraform State Files](https://www.gruntwork.io/blog/how-to-manage-large-opentofu-terraform-state-files)
- [Spacelift — Managing Terraform State: Best Practices & Examples](https://spacelift.io/blog/terraform-state)
- [Terramate — How to Structure and Size Terraform Stacks](https://terramate.io/rethinking-iac/how-to-structure-and-size-terraform-stacks/)
- [Terramate — Stacks Documentation](https://terramate.io/docs/cli/stacks/)
- [Terramate — Why You Should Break Down Your Terraform into Stacks](https://terramate.io/rethinking-iac/why-you-should-break-down-your-terraform-into-stacks/)
- [Terramate Quickstart AWS](https://github.com/terramate-io/terramate-quickstart-aws)
- [HashiCorp — Design a Stack](https://developer.hashicorp.com/terraform/language/stacks/design)
- [GitHub — netlify/terraform-provider-netlify](https://github.com/netlify/terraform-provider-netlify)
- [GitHub — netlify/terraform-provider-netlify — Issue #39](https://github.com/netlify/terraform-provider-netlify/issues/39)
- [GitHub — hashicorp/terraform Issue #16375](https://github.com/hashicorp/terraform/issues/16375)
- [GitHub — hashicorp/terraform Issue #18981](https://github.com/hashicorp/terraform/issues/18981)
- [Taccoform — Multiple Provider Orchestration](https://www.taccoform.com/posts/tfg_p6/)
- [Netlify — Terraform Provider Docs](https://docs.netlify.com/terraform-provider/)
- [Rollbar — Terraform Provider Registry](https://registry.terraform.io/providers/rollbar/rollbar/latest/docs)
