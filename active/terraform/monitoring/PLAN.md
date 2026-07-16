# PLAN — Monitoring Stack: Centralized Observability Configuration

**Feature:** `monitoring/` stack in the Terraform project
**Branch:** `feature/rollbar-identity` — merged in PR #238 (2026-03-13)
**Status:** Rollbar done · **Datadog CLOSED — keys only, deliberately** (2026-07-15) · New Relic blocked on a credential that does not exist

| Tool | State |
|---|---|
| Rollbar | **Done** — 44 projects imported, PR #238. One follow-up PR open (cross-stack `team_ids`). |
| Datadog | **Closed as out of scope for this stack** — engineer's decision, 2026-07-15. The 11 monitors and 6 dashboards stay in the UI. The only Datadog resources in Terraform are the four `datadog_api_key`, and they live in the **app** stacks, not here. See § Datadog Scope. |
| New Relic | **Blocked** — no `NEW_RELIC_*` credential exists anywhere. Not a scope question; nothing can be planned until the key is created. See § New Relic Scope. |

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
- Datadog: **a dedicated service account — never a person's account.** Settled by `~/.claude/docs/THIRD-PARTY-KEY-STANDARD.md`; this line previously left it open ("Ivo's account or a dedicated service account"). The provider authenticates with an APP key, and Datadog revokes a person's APP keys when their account is disabled (*"If a user's account is disabled, any application keys that the user created are revoked"*) — so a personal APP key means one HR event breaks every Datadog apply, including rotation. Use `datadog_service_account_application_key`, scoped `api_keys_write` + `api_keys_read` + `api_keys_delete` (the delete is what makes rotation possible; the provider's own example role omits it)
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

**CLOSED — this stack manages no Datadog resources. Engineer's decision, 2026-07-15 (option C of three presented).**

The two "pending investigation" questions were answered against the live API before the decision, so this is a closure on evidence, not on fatigue:

| Resource | Count | State | What they cover |
|---|---|---|---|
| Monitors | 11 | **UI only** | 4 PgBouncer (unavailable, pool saturation, client wait queue, overprovisioned) · 4 integrator alerts (Maqnelson, RedeBrasil, Almaviva, Unimaq) · 2 Redis memory (redis001, redis002) · 1 NTP clock sync (Datadog's own `[Auto]`) |
| Dashboards | 6 | **UI only** | PgBouncer Metrics (Extended) · API Throughput · API Throughput (Luiz Hohl) · Integrations · Sidekiq Overview · Commissions — three different authors |
| API keys | 4 | Terraform, **in the app stacks** | Done in the key-standard plan, phases 1–3 |

- [x] **What resources are currently configured in Datadog?** — the table above. Enumerated read-only via `GET /api/v1/monitor` and `GET /api/v1/dashboard`.
- [x] **Are monitors/dashboards already defined as code anywhere, or only via UI?** — **only via UI.** A repo-wide grep for `datadog_monitor`, `datadog_dashboard`, `datadog_synthetics`, `datadog_service_definition` and `newrelic_*` across every `.tf` returns zero matches.
- [x] ~~Which API key to use (service account vs. Ivo's account)?~~ — **service account**, per the key standard (see Break glass tokens above). Already the case; the provider authenticates as the `Terraform` service account.

**What "closed" means, and what it does NOT mean.** It means nobody is adopting the 11 monitors or the 6 dashboards into Terraform, and that is a decision rather than an omission — do not re-open it as a gap. It does **not** mean Datadog is unmanaged: the key lifecycle (create / rotate / revoke) is fully Terraform-managed and governed by `~/.claude/docs/THIRD-PARTY-KEY-STANDARD.md`; it just lives in the app stacks, one key per stack, by option A2 of the key-standard plan (blast-radius isolation).

**The cost accepted, stated plainly so it is not rediscovered as a surprise.** The 11 monitors remain exactly what the key standard names as the failure mode for keys: configuration nobody declared, that nobody can reason about deleting. An alert retuned or removed in the UI leaves no reviewable trace. That was weighed and accepted — the alternative (option A: adopt the monitors, leave the dashboards) was recommended and declined.

**If this is ever re-opened**, the unverified item to settle first: **whether `datadog_monitor` imports cleanly is NOT known.** What was verified is that `datadog_api_key` import is deprecated (*"Import functionality for this resource is deprecated and will be removed in a future release with prior notice."*) — that finding was deliberately **not** extended to monitors. Confirm against a real `plan` before any adoption PR.

**Loose end noticed, not investigated:** the `Integrator - (Unimaq)` monitor has no matching integrator stack in Terraform — possibly an alert for a client that no longer exists. Out of scope for this decision; recorded so it is not lost.

---

## New Relic Scope

**BLOCKED on a credential that does not exist — this is not a scope question and no amount of investigation moves it.**

Verified 2026-07-15: the shared `Terraform ENV` 1Password item (Employee vault) has **no `NEW_RELIC_*` field**. Its fields are `ANTHROPIC_API_KEY`, `CLOUDFLARE_API_TOKEN`, `DATADOG_API_KEY`, `DATADOG_APP_KEY`, `GITHUB_TOKEN`, `MONGODB_ATLAS_PRIVATE_KEY`, `MONGODB_ATLAS_PUBLIC_KEY`, `REDISCLOUD_ACCESS_KEY`, `REDISCLOUD_SECRET_KEY`, `ROLLBAR_API_KEY`. So the provider cannot authenticate, and the two questions below cannot be answered read-only the way the Datadog ones were.

**New Relic is live, so this is a real gap rather than a dead tool:** every integrator stack ships a `NEW_RELIC_LICENSE_KEY` SSM parameter and a `NEW_RELIC_APP_NAME`, and the integrator's own code carries New Relic instrumentation (`add_method_tracer` across the loaders, adapters and `Computation`). Note the distinction — a **license key** (ingest, per app) is not an **API key** (management, org-wide); the license keys existing does not unblock the provider.

**The one prerequisite, and it is the engineer's to do:** create a New Relic User API key **owned by a service account, not a person** (`THIRD-PARTY-KEY-STANDARD.md` § Ownership — the asymmetry that makes a personal key wrong applies to any vendor, not just Datadog), and add it to `Terraform ENV`. The bootstrap-credential exception applies to its naming: it is the credential the provider authenticates *with*, so it has no `<ENTITY>` and takes the `<SERVICE>_<TYPE>` form (`NEWRELIC_API_KEY`), created out of band — same shape as `ROLLBAR_API_KEY` and `DATADOG_API_KEY`.

Still open, unanswerable until the key exists:
- [ ] What resources are currently configured in New Relic?
- [ ] Are alert policies already defined as code anywhere, or only via UI? *(Partial answer already: a repo-wide grep for `newrelic_*` across every `.tf` returns zero — so nothing is code **in this repo**. Whether anything is defined as code elsewhere is unknown.)*
- [x] ~~Which API key to use?~~ — reframed: **none exists**. The question was never "which", it was "create one".

---

## Implementation Order

The original order was Rollbar → Datadog → New Relic. **It no longer holds:** Datadog was investigated and then closed out of scope, so the sequence collapses to what is actually left.

1. ~~**Rollbar first**~~ — **DONE**, PR #238. One follow-up remains (cross-stack `team_ids`), independent of the rest.
2. ~~**Datadog second**~~ — **investigated, then CLOSED as out of scope** (2026-07-15). Not deferred, not pending: decided. See § Datadog Scope.
3. **New Relic** — the only tool left for this stack, and it cannot start until its API key exists. See § New Relic Scope.

---

## Pending Items

### Prerequisites
- [x] Ivo's Rollbar `account_access_token` generated
- [x] ~~Datadog admin API key~~ — **moot.** The `Terraform` service account's `DATADOG_API_KEY` / `DATADOG_APP_KEY` exist in `Terraform ENV`, but this stack needs no Datadog credential at all now that Datadog is closed out of scope.
- [ ] **New Relic API key — the single blocker for everything left in this stack.** Does not exist; service-account-owned; engineer to create. See § New Relic Scope.

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

### Datadog — nothing pending; the section is closed

- [x] ~~Create `datadog.tf` — scope TBD after investigation~~ — **not being created.** The investigation ran, the scope came back as 11 UI monitors + 6 UI dashboards, and the engineer chose to adopt neither. No `datadog.tf`, no Datadog provider in this stack.
- [x] What resources are currently configured in Datadog? — answered, § Datadog Scope.
- [x] Are monitors/dashboards already defined as code anywhere, or only via UI? — UI only; zero `.tf` matches repo-wide.

### New Relic — everything pending, all behind one prerequisite

- [ ] **Create the New Relic API key (service-account-owned) and add it to `Terraform ENV`** — engineer's task; gates all three items below.
- [ ] Create `newrelic.tf` — scope TBD, genuinely: unlike Datadog, the current state could not be enumerated (no credential to read it with).
- [ ] What resources are currently configured in New Relic?
- [ ] Are alert policies already defined as code anywhere, or only via UI? *(Repo-wide grep for `newrelic_*` is zero — nothing is code here; elsewhere unknown.)*

---

## Decisions Made

| Decision | Choice | Reason |
|----------|--------|--------|
| CloudWatch location | Stays in AWS stacks | Coupled to specific AWS resources, different change cadence |
| Stack name | `monitoring` | Generic infrastructure concept, consistent with `networking`/`dns`/`identity` |
| User management | `identity/` stack | Engineers + teams belong with other access management |
| Project config location | `monitoring/` stack | Centralized — frontends have no backend stack to live in |
| `rollbar_notification` | Not managed | Provider issue #421 causes slow refresh for this resource type |
| **Datadog monitors + dashboards** | **Not managed — closed out of scope (2026-07-15)** | Engineer's call, taken with the live state enumerated (11 monitors, 6 dashboards, all UI-made, zero as code) and three options on the table. Option A (adopt the 11 monitors, leave the dashboards) was recommended and **declined**; the accepted cost is that an alert retuned or deleted in the UI leaves no reviewable trace. **This is a decision, not a gap — do not re-open it as pending work.** |
| Datadog API keys | App stacks, not `monitoring/` | Option A2 of the key-standard plan: one key per stack, so a leak or rotation reaches one environment instead of all. Fully Terraform-managed — just not here. |
| Co-location (app stacks) | Rejected | Frontend projects have no home; blast radius concern; `app-shared-001` at resource limit |
