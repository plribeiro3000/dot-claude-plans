# PLAN — Monitoring Stack: Centralized Observability Configuration

**Feature:** `monitoring/` stack in the Terraform project
**Branch:** `feature/rollbar-identity` — merged in PR #238 (2026-03-13)
**Status:** Rollbar done — Datadog and New Relic pending

---

## Context

The team uses three SaaS observability tools alongside AWS CloudWatch:

| Tool | Purpose |
|------|---------|
| Rollbar | Error tracking — backend + frontend projects |
| Datadog | Monitors, dashboards, APM, infrastructure metrics |
| New Relic | APM, alerting |
| CloudWatch | Log aggregation (stays in AWS stacks — coupled to specific resources) |

**Why a dedicated `monitoring/` stack?**
- Frontends have no backend stack to live in — `app-webclient` and other frontend Rollbar projects need a home
- SaaS observability config changes on a different cadence than app infrastructure (ECS, RDS)
- `app-shared-001` is already at 201 resources (community warning threshold: 200–300)
- Following the `networking/`, `dns/`, `identity/` naming pattern — generic infrastructure concept, not a technology name
- Community consensus (Rollbar docs, HashiCorp, Sentry, Datadog): centralized observability module is the dominant pattern

**CloudWatch stays in its stack** — it is coupled to specific AWS resources (ECS log groups, RDS parameter groups) and changes when those resources change. Moving it to `monitoring/` would create cross-stack dependencies.

---

## Stack Structure

```
monitoring/
├── stack.tm.hcl
├── providers.tf        # rollbar + datadog + newrelic
├── variables.tf
├── terraform.tfvars
├── rollbar.tf          # Rollbar projects + access tokens
├── datadog.tf          # Datadog monitors, dashboards, services
└── newrelic.tf         # New Relic alerts, APM config
```

---

## Providers

| Provider | Registry ID | Version | Status |
|----------|-------------|---------|--------|
| Rollbar | `rollbar/rollbar` | v1.16.0 | Stable, pre-1.0 |
| Datadog | `DataDog/datadog` | Latest stable | Official, stable |
| New Relic | `newrelic/newrelic` | Latest stable | Official, stable |

**Known issues:**
- Rollbar issue #421: slow refresh for `rollbar_notification` resources when items are deleted via UI — does NOT affect `rollbar_project` or `rollbar_project_access_token`. Avoid managing `rollbar_notification` in Terraform.

**Break glass tokens:**
- Rollbar: `account_access_token` from Ivo's Owner account (same account used in `identity/` for user management)
- Datadog: Admin API key — generate from Ivo's account or a dedicated service account
- New Relic: User API key — generate from Admin account

---

## Rollbar Scope

### What to manage
- `rollbar_project` — one per application/frontend
- `rollbar_project_access_token` — read/write tokens per project (used by app deployments)

### What NOT to manage
- `rollbar_notification` — affected by issue #421 (slow refresh on deleted resources)
- `rollbar_user` / `rollbar_team` — managed in `identity/` stack, not here

### Known existing projects (to be imported)

All projects currently exist in Rollbar and will be imported, not created. Exact project list TBD — requires running `terraform state list` or Rollbar API call to enumerate current projects.

Expected structure: one project per deployable unit (backend app, frontend app, integrator, etc.).

### Resource count estimate
- ~35 Rollbar projects + ~70 tokens = ~105 resources
- Well within 200-resource safe threshold for performance

---

## Datadog Scope

To be defined. Known usage: monitors, dashboards, APM instrumentation.

Pending investigation:
- [ ] What resources are currently configured in Datadog?
- [ ] Are monitors/dashboards already defined as code anywhere, or only via UI?
- [ ] Which API key to use (service account vs. Ivo's account)?

---

## New Relic Scope

To be defined. Known usage: APM, alerting.

Pending investigation:
- [ ] What resources are currently configured in New Relic?
- [ ] Are alert policies already defined as code anywhere, or only via UI?
- [ ] Which API key to use?

---

## Implementation Order

1. **Rollbar first** — clearest scope, provider already researched, token already being set up (via Ivo's account in `identity/` work)
2. **Datadog second** — official provider, investigate current state
3. **New Relic third** — official provider, investigate current state

---

## Pending Items

### Prerequisites
- [x] Ivo's Rollbar `account_access_token` generated
- [ ] Datadog admin API key
- [ ] New Relic admin API key

### Rollbar (DONE — PR #238)
- [x] Create `monitoring/` directory in Terraform project
- [x] Create `stack.tm.hcl` following Terramate conventions
- [x] Create `providers.tf` with rollbar provider
- [x] Create `rollbar.tf` with all 44 projects
- [x] Import all existing Rollbar projects
- [x] Update `CHANGELOG.md`

### Rollbar — Next PR (cross-stack references)
- [ ] Add outputs to `identity/` stack (Backend and Frontend team IDs)
- [ ] Add `team_ids` to each `rollbar_project` in `monitoring/` using `terraform_remote_state`

### Datadog
- [ ] Create `datadog.tf` — scope TBD after investigation
- [ ] What resources are currently configured in Datadog?
- [ ] Are monitors/dashboards already defined as code anywhere, or only via UI?

### New Relic
- [ ] Create `newrelic.tf` — scope TBD after investigation
- [ ] What resources are currently configured in New Relic?
- [ ] Are alert policies already defined as code anywhere, or only via UI?

---

## Decisions Made

| Decision | Choice | Reason |
|----------|--------|--------|
| CloudWatch location | Stays in AWS stacks | Coupled to specific AWS resources, different change cadence |
| Stack name | `monitoring` | Generic infrastructure concept, consistent with `networking`/`dns`/`identity` |
| User management | `identity/` stack | Engineers + teams belong with other access management |
| Project config location | `monitoring/` stack | Centralized — frontends have no backend stack to live in |
| `rollbar_notification` | Not managed | Provider issue #421 causes slow refresh for this resource type |
| Co-location (app stacks) | Rejected | Frontend projects have no home; blast radius concern; `app-shared-001` at resource limit |
