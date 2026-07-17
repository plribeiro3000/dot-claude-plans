# PLAN — MongoDB Atlas permissioning

Derived from `active/spike/mongodb-atlas-permissioning/SPIKE.md` plus the engineer's decisions
recorded in the session of 2026-07-16.

## Goal

Bring Atlas access in line with least privilege, and make the beta MongoDB pull self-service
for an engineer who is not an infrastructure engineer — without granting him AWS.

## Decisions already taken (do not re-open)

| Decision | Rationale |
|---|---|
| No Atlas MFA configuration | Atlas bypasses its own 2FA for federated users; Google Workspace is the enforcement point (`identity/mongodb_federation.tf`). Nothing to configure in Atlas. |
| No PrivateLink for beta | MongoDB recommends private endpoints for *"all new staging and production projects"* and states *"you may not need private endpoints in lower environments"* on cost. Beta is non-productive. |
| Keep static role assignment (`cloud_user_*`) | MongoDB's docs recommend IdP-group role mapping, but its own Terraform modules omit it and the provider is actively investing in the `cloud_user_*` family — which 4Shark already uses. No community consensus either way. Not worth churning. |
| Self-service network access via native temporary IP entries | MongoDB's own documented pattern for this exact case, with a 7-day max expiry. |
| Two levels via team membership, not via MFA | `engineers-baseline` / `engineers-elevated` already exist. Elevation is a Terraform PR. |
| Decouple Atlas access from AWS access | Least privilege — the engineer who needs Atlas does not need an AWS IAM user. |

## Current state

- `identity/engineers.tf:2-6` — `platform_engineers` filters on `email != null && given_name != null`
  and gates **AWS IAM user** (`engineers.tf:16`), **AWS SSO** (`sso.tf:65,107`) *and* **Atlas**
  (`mongodb_org.tf:2`, `mongodb_teams.tf:22-28`). One filter, three systems.
- `identity/mongodb_teams.tf:33-40` — `engineers-baseline` holds
  `["GROUP_READ_ONLY", "GROUP_DATA_ACCESS_READ_WRITE"]` on **all four** projects, including the
  productive `app-shared-001` and `app-atento-001`. No elevation step.
- `identity/mongodb_teams.tf:42-49` — `engineers-elevated` holds `["GROUP_CLUSTER_MANAGER"]` on all
  four projects but has **no `mongodbatlas_cloud_user_team_assignment`** — zero members.
- `identity/terraform.tfvars` — Leandro has an `email` but no `given_name` and no `atlas_role`, so he
  exists in no Atlas, AWS or SSO resource.
- `app-beta-001/mongodb.tf:60-84` — one shared database user (`readWriteAnyDatabase`), credential
  seeded in SSM, consumed by the application.

## Design

### Phase 1 — `identity/` stack

This stack is guarded by `guard.tf`: only the break-glass account may plan/apply. 4Shark opens the
PR; the break-glass owner applies.

**1.1 — Decouple Atlas from AWS** (`engineers.tf`)

Add a local mirroring the existing `rollbar_engineers` shape (`rollbar.tf:2-8`):

```hcl
atlas_engineers = {
  for key, engineer in var.engineers :
  key => engineer
  if engineer.email != null && engineer.atlas_role != null
}
```

`platform_engineers` keeps gating AWS + SSO and is left untouched. `atlas_role` is already
`optional(string)` in `variables.tf:11`, so no type change is needed.

**1.2 — Point Atlas resources at the new local**

- `mongodb_org.tf:2` — `for_each = local.atlas_engineers`
- `mongodb_teams.tf:23` — membership derived from a per-engineer `atlas_teams` field (below)

**1.3 — Add `atlas_teams` to the engineer object** (`variables.tf`)

```hcl
atlas_teams = optional(set(string))
```

Mirrors `rollbar_teams = optional(set(string))` (`variables.tf:12`) — the established shape for
per-engineer team membership in this stack.

**1.4 — Re-scope the teams** (`mongodb_teams.tf`)

| Team | Projects | Roles | Members |
|---|---|---|---|
| `engineers-baseline` | all four | `["GROUP_READ_ONLY"]` | paulo, emerson |
| `engineers-elevated` | all four | `["GROUP_CLUSTER_MANAGER", "GROUP_DATA_ACCESS_READ_WRITE"]` | none by default |
| `engineers-beta-readonly` | `app-beta-001` only | `["GROUP_READ_ONLY", "GROUP_NETWORK_ACCESS_MANAGER"]` | leandro |

`GROUP_DATA_ACCESS_READ_WRITE` moves from baseline to elevated. That is the whole point: routine
state is read-only; write access to data on productive projects requires joining `engineers-elevated`
via a PR.

**Deliberately NOT refactored into a data-driven team map.** Three teams is exactly the Rule of Three
floor, and `NO-PREMATURE-DRY.md` says three is the minimum, not the trigger. The third team is added
explicitly, mirroring the two that exist. Revisit if a fourth appears.

**1.5 — Add Leandro** (`terraform.tfvars`)

```hcl
"leandro" = {
  github_username = "leandroalmeida27"
  email           = "leandro.almeida@4shark.com.br"
  atlas_role      = "ORG_MEMBER"
  atlas_teams     = ["beta-readonly"]
  rollbar_teams   = ["frontend"]
}
```

No `given_name` → stays out of `platform_engineers` → **no AWS IAM user, no AWS SSO**. He reaches
Atlas through Google Workspace federation, which is independent of AWS.

Paulo and Emerson get `atlas_teams = ["baseline"]`.

### Phase 2 — `app-beta-001` stack

Not guarded. Paulo applies.

**2.1 — Seed the read-only credential in SSM (manual pre-step)**

Create `/beta-001/MONGO_READONLY_USERNAME` and `/beta-001/MONGO_READONLY_PASSWORD` (SecureString),
following the existing convention at `mongodb.tf:60-67`. Values are chosen by the engineer and never
pass through this plan, the session, or the repository.

**2.2 — Add the read-only database user** (`mongodb.tf`)

A second entry in the module's `database_users` map, scoped to the beta database only rather than
`readWriteAnyDatabase`:

```hcl
roles = [{ role_name = "read", database_name = var.mongo_database }]
```

The existing shared application user is **not touched** — it is what the running app authenticates
with, and changing it is out of scope.

## Sequence

1. Phase 1 PR → review → break-glass applies.
2. Confirm Paulo/Emerson lost Data Explorer write on productive projects, and that nothing in the
   application broke (the app uses the database credential, not an Atlas user role — expected to be
   unaffected; confirm rather than assume).
3. Phase 2 manual SSM seed → Phase 2 PR → Paulo applies.
4. Leandro verifies the whole path end-to-end (below).

## Verification

- Leandro can log in to Atlas via Google and sees **only** `app-beta-001`.
- Leandro can add a temporary IP entry with an expiry on `app-beta-001`, and **cannot** on any other
  project.
- Leandro has **no** AWS IAM user and **no** AWS SSO entry (`aws iam list-users`, identity store).
- Leandro runs `bin/mongodb_pull` successfully against beta with the read-only credential.
- Paulo/Emerson: read-only on productive by default; joining `engineers-elevated` via PR restores
  data write.

## Risks

| Risk | Mitigation |
|---|---|
| Demoting baseline breaks an unnoticed workflow that relied on Data Explorer write | Elevation path exists and is a one-line PR. Reversible. |
| `GROUP_NETWORK_ACCESS_MANAGER` is broader than "manage the IP list" — it also covers VPC peering and PrivateLink | Scoped to `app-beta-001` only, which is non-productive. Named explicitly so it is a known grant, not a surprise. |
| The `role_names` change on an existing `team_project_assignment` may force replacement rather than update | Read the plan output before applying. Non-productive projects first if the plan shows replacement. |
| Leandro's Atlas org assignment requires his Google Workspace account to be active in the allow-listed domain | `domain_allow_list = ["4shark.com.br"]` already covers it (`mongodb_federation.tf:21`). |

## Out of scope

- The shared application database credential and its lack of per-person attribution. Real, and the
  audit ceiling it creates is documented in the SPIKE — but it is the application's credential and a
  separate decision.
- Private endpoints for the productive projects. MongoDB recommends them for staging/production; that
  is a separate plan, not this one.
- Migrating the Terraform provider from the classic Programmatic API Key
  (`MONGODB_ATLAS_PUBLIC_KEY`/`PRIVATE_KEY`, confirmed in `identity/.envrc:10-11`) to the OAuth
  service-account flow.
- The `mongodbatlas_federated_settings_org_role_mapping` JIT pattern. It does support project-level
  roles via `role_assignments { group_id = ... }` — confirmed against the provider registry and
  Pulumi's schema mirror — but grants and revocations apply only at next login, and MongoDB's own
  Terraform modules do not implement it. Revisit only if manual elevation PRs become a burden.
