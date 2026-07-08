# PLAN — `modules/app`: make the connection-pooler mandatory by construction

## Goal

Every 4Shark app must always run behind a connection-pooler — the app's burst/scale access pattern cannot hold up without one. Today nothing enforces that: each `app-<env>-001` stack instantiates `module "ecs_cluster"` and `module "connection_pooler"` as independent siblings, coupled only by an out-of-band SSM `DATABASE_URL`. A new stack could be stood up with no pooler and nothing would complain.

Enforce it **by construction**: a domain module `modules/app` that bundles the app runtime (`ecs_cluster`) **and** its `connection_pooler` into one unit, so declaring the app cluster necessarily creates the pooler. No pooler = no app cluster = plan fails.

## Why this scope (decision, grounded — not effort)

The scope choice (thin cluster+pooler vs the whole 28-module stack) was resolved on domain + community value, not implementation cost:

- **Not a thin single-resource wrapper** — the community guidance is that thin wrappers around single resources should be avoided; a module should encapsulate a well-defined function. `ecs_cluster + connection_pooler` is not thin: it is the domain unit *"app runtime + its mandatory pooler"* — two resources that only make sense together for 4Shark.
- **Not the whole stack** — bundling all ~28 modules is coarse: HashiCorp's composition guidance keeps the module tree flat and injects dependencies; a large module dependency object makes plans conservative and reduces parallelism.
- **Idiomatic granularity** — the most-used community ECS `service` module bundles a *meaningful operational unit* (service + task-def + IAM + SG + autoscaling + LB + log group) and takes cluster/subnets/vpc as **inputs**. `modules/app` mirrors that: it bundles the app-runtime unit and takes vpc / subnets / rds-backend as inputs; the app's **services stay injected** (they reference the module's cluster output), exactly like the service pattern.

Sources: terraform-aws-modules ECS `service` README; Gruntwork ECS Service; HashiCorp Module Composition; oneuptime module-dependency granularity.

## Design — `modules/app`

`modules/app` internally instantiates the two coupled child modules and wires them, exposing the same surface the stack currently reads from the two separate modules.

- **Internally creates (mandatory):**
  - `module "ecs_cluster"` (source `../ecs_cluster`) — the app compute cluster + app SG.
  - `module "connection_pooler"` (source `../connection_pooler`) — created unconditionally; **no `count`/toggle**, so it cannot be omitted.
  - The coupling `connection_pooler.app_security_group_id = ecs_cluster.security_group_id` becomes an **internal** reference (was a stack-level reference).
- **Inputs:** `identifier`, `environment`, `vpc_id`, `subnet_ids`, cluster sizing (instance_type, min/max, ami, etc.), pooler `databases` (backend rds endpoints + per-role db/user/pool), `image`, the 3 pooler secret ARNs, `stats_user`, datadog image/keys, `extra_ingress_cidrs` (atento), `internal_zone_id` / `internal_record_name`, `namespace_name`, `tags`.
- **Outputs (must cover every current consumer):** `cluster_name`, `cluster_arn`, `security_group_id`, `asg_name`, plus pooler `host`/`endpoint`, `cluster_name`, `execution_role_arn`, `cloud_map_hosted_zone_id`, `service_name`. The stack's `ecs_services`, `codedeploy_web`, `iam_deploy`, capacity_* and the atento cross-region zone association read these.
- **Sub-decision (child-module vs inline):** call `ecs_cluster` + `connection_pooler` as sub-modules (DRY, 2 levels deep) **[recommended]** vs inline their resources into `modules/app` (1 level, duplicated code). Recommend sub-modules; the 2-level nest is the accepted, conscious cost of the wrapper the engineer chose (community service modules nest too).

## State migration — the load-bearing risk (no recreation)

Moving `module.ecs_cluster` → `module.app.ecs_cluster` and `module.connection_pooler` → `module.app.connection_pooler` **changes the resource addresses**. Without care terraform reads that as destroy-old + create-new → an ECS-cluster + pooler **outage**. This must be a pure address rename.

- Use native **`moved {}` blocks** (module-level moves, TF ≥1.1) in each stack:
  ```
  moved { from = module.ecs_cluster,       to = module.app.ecs_cluster }
  moved { from = module.connection_pooler, to = module.app.connection_pooler }
  ```
  Module `moved` relocates the whole child-module subtree in state at plan time — no destroy.
- **Hard gate:** the plan MUST show **0 to destroy, 0 to add** for these (only moves + the harmless provider-drift task-def "replaced" noise seen throughout this migration). If any `module.app.*` shows create or any legacy address shows destroy, STOP — the move block is wrong.
- Backends per stack are independent → migrate one stack at a time.

## Reference rewiring (the bulk of the per-stack diff)

After the move, every `module.ecs_cluster.*` / `module.connection_pooler.*` reference in the stack (`main.tf`, `compute.tf`, `connection_pooler.tf`, atento `compute.tf`) must become `module.app.*`. This is mechanical but wide; it is the real diff. The `connection_pooler.tf` file collapses into the `module "app"` call; the standalone `module "ecs_cluster"` block is replaced by `module "app"`.

## Zero-downtime rollout

Because the change is a terraform-structure refactor with pure state moves (no AWS create/destroy), a correct apply is a **no-op at the AWS layer** — no downtime by construction. The risk is entirely "did the `moved` blocks + rewiring keep every address and value identical". Mitigation = read every plan, beta first.

Per stack (order **beta → demo → shared → atento**, non-prod first to prove the move shape):
1. PR (per stack, or grouped — apply is per-stack regardless).
2. `terraform plan` → confirm **only moves**, 0 destroy / 0 add on the pooler + cluster; services/codedeploy/iam show no change (same underlying resources).
3. Apply → engineer-gated on shared/atento.
4. Validate app + pooler healthy (services running, pooler serving) — same checks used across this migration.
5. Merge → `/merge-cleanup`.

## Enforcement result

After all 4 migrate, the standalone `module "ecs_cluster"` / `module "connection_pooler"` usage is gone; the only way to get an app cluster is `module "app"`, which always creates the pooler. A new stack **cannot** declare the app runtime without the pooler → the guardrail is structural, no fake data dependency, no app change.

## Options considered and rejected (for the record)

- **B — policy-as-code guardrail** (OPA/Conftest/`check`): enforces "stack must declare a pooler" in CI. Rejected: the engineer wants it structural, not a side-channel check.
- **C — real dependency injection via splitting `DATABASE_URL`** (host from pooler output as a dynamic, used env var; app builds the URL from host + secret parts): the only *genuinely-used* injection, but it is a cross-repo change on the app's most critical path (DB connection) requiring its own zero-downtime rollout. Rejected as disproportionately complex "just to create a dependency".
- **Dummy required var** (env var / redundant SG egress rule referencing the pooler output): rejected — the app already has egress-all and reads `DATABASE_URL`, so any injected value would be unused = fake enforcement.

## Risks

- **Wrong `moved` block → recreation → outage.** Primary risk. Mitigation: module-level `moved`, plan gate (0 destroy), beta-first.
- **Missed reference** → a stack file still points at the old address → plan error (caught before apply).
- **Output surface gap** → `modules/app` must expose every attribute the stack consumers read, or the rewiring breaks. Enumerate consumers from `main.tf`/`compute.tf` before writing outputs.
- **2-level module nesting** — conscious deviation from HashiCorp's flat-tree preference, accepted as the cost of construction-time enforcement (the chosen path).

## Open sub-decisions for execution

1. Child-module vs inline inside `modules/app` (recommend child-module).
2. One PR spanning 4 stacks vs one PR per stack (recommend per stack for a destructive-adjacent refactor; apply is per-stack anyway).
3. Whether to also fold the app's `ecs_services` into `modules/app` later (out of scope here — services stay injected per the community pattern; revisit only if desired).
