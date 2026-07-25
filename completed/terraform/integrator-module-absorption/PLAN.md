# Integrator Module Absorption — thin stacks like setup/onboarding/vpn/auth

**Status: COMPLETE — 2026-07-24.** All four active integrator stacks are thin: the shared
`modules/integrator` owns the entire runtime, and each stack is a `terraform.tfvars` plus a
`main.tf` that declares only configuration. The four stacks now carry an identical set of files.
The frozen cancelled-contract stack (`integrator-redebrasil`) was excluded throughout — its freeze
blocks even a plan, so zero-diff could not be verified there; it goes at teardown.

## What shipped

| PR | Change | Result |
|---|---|---|
| #838 | Runtime of all four stacks moved into the module | Applied `0 added, 0 changed, 0 destroyed` on each; 64 / 64 / 96 / 274 pure state moves |
| #839 | Removed the settled `moved.tf` blocks | `No changes` — code-only |
| #840 | Direct-source ETLs (harvester) moved into the module | Applied `0 added, 2 changed, 0 destroyed` (two accepted metadata corrections) |
| #841 | Removed the settled ETL `moved` blocks + fixed a description divergence | `No changes` — code-only |
| #842 | Folded the last two stack files into `main.tf` | `No changes` — file layout only |

## The final interface

A stack declares three things and nothing else:

- `client_name` — the single identifier every `integrator-<client>` name derives from
- `deployments` — a map of the environments it runs, keyed by short name, each entry carrying its
  env vars, services, schedules, cron tasks, cache database and a **REQUIRED** `staging` flag
- `harvesters` — a map of its direct-source ETLs when the client has one, same shape

Everything else the module derives: cluster, services, load balancer, MongoDB, SSM secrets, task
role, image repositories, buckets, schedulers, deploy permissions and the KMS key.

**The ALB shape is derived, not configured.** One deployment with no staging is a single
environment and gets the simple internal ALB (one target group, path-routed). More than one
deployment — or one that mirrors into staging — means several environments behind ONE shared,
host-routed ALB with a target group per environment. A separate ALB per environment would be the
expensive way to say the same thing, so the module never builds one. The per-deployment name
segment follows the same rule: absent with a single environment, the map key when there are
several.

**No "create it" flags survived.** Two intermediate designs (`create_runtime`, `create_staging`)
were removed once every stack was migrated: what the module builds follows from what the stack
declares. Two escape-hatch inputs the harvester needed (`scheduler_passrole_arns`,
`extra_deploy_*`) died with it — the module derives the ETL cluster, images and roles from the
same declaration.

## Per-stack mapping as shipped

| Stack | `deployments` | `harvesters` | ALB shape |
|---|---|---|---|
| maqnelson | 1 entry, `staging = false` | none | single internal, path-routed |
| almaviva | 1 entry, `staging = false` | none | single internal, path-routed |
| commcenter | 1 entry, `staging = true` | none | shared, host-routed (2 environments) |
| atento | 4 entries (br/mx/co/cl); mx, co, cl with `staging = true` | 2 entries (mx, co), both with staging | shared, host-routed (7 environments) |

## What the zero-downtime guarantee rested on

Moving a resource from a stack into a module changes its Terraform state address. Without a
`moved` block that reads as destroy + create — a destroyed production Mongo, ECS cluster or VPN.
So every relocated resource carried a `moved` block, and the gate before any apply was a plan
showing **0 to add / 0 to destroy** (moves and no-ops only). Any destroy in a plan meant stop.
That held on all four stacks.

**The moved blocks could only be removed AFTER the applies.** Removing them while the state still
held the old addresses would have read as destroy + create for all 498 relocations — which is why
#839 and #841 are separate PRs rather than part of the refactor.

## Deliberate exceptions kept in the stack

- **An engineer Windows workstation** (one stack) — being decommissioned shortly; it is the only
  resource resolving an image by lookup, which is why that stack still calls the shared
  `ami_versions` module. Both go together when the machine does.
- **`ami_versions` stays a shared module** — five stacks consume it and a scheduled job bumps the
  pinned image names in one place. Nothing inside the integrator module needs it: the database
  nodes take an explicitly pinned image with `ignore_changes`.

## Lessons recorded

- **A saved plan must be generated from committed code.** The ETL apply (#840) was run from a plan
  built on uncommitted local edits, so what was applied diverged from what was merged: two
  schedule descriptions disagreed between code and state, and a plan on `develop` asked for two
  updates nobody wanted. Fixed in #841. The apply and the merge must describe the same code.
- **A metadata-only diff is still a diff and still the engineer's call.** Two corrections surfaced
  by the ETL move (an inconsistent ownership tag, a hand-written pass-role list missing two roles)
  were presented before applying rather than shipped silently, even though neither touches a
  running task.
