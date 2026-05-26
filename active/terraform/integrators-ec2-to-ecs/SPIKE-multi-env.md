# SPIKE — One client, multiple environments: design for atento and commcenter

**Conducted by:** Engineering team
**Date:** 2026-04-10
**Status:** Research complete — pending decisions

---

## Goal

Define the "one client, multiple environments" pattern before migrating atento-br and commcenter.
Three questions to answer:

1. How does the current `deploy-ecs.yaml` workflow work, and what is the minimum evolution needed to support multi-environment deploys?
2. What is the Terraform design for a `integrator-atento` stack that hosts BR, MX, CO, CL (and later commcenter with prod + staging)?
3. Do the three already-migrated integrators (almaviva, maqnelson, redebrasil) need to be retrofitted to match the new pattern?

---

## Method

- Full read of `.github/workflows/deploy-ecs.yaml` and `.github/actions/deploy-ecs/action.yaml` in the integrator repo
- Full read of `.github/actions/deploy/action.yaml` (legacy action, for contrast)
- Full read of `integrator-almaviva/compute.tf`, `integrator-maqnelson/compute.tf`, `integrator-redebrasil/compute.tf`
- Full read of `modules/ecs_service/main.tf`, `modules/internal_alb/main.tf`, `modules/internal_alb/variables.tf`, `modules/ecs_scheduled_task/main.tf`
- Full read of `integrator-almaviva/ssm.tf`, `integrator-almaviva/main.tf`, `integrator-atento-br/main.tf`
- PLAN.md and TASKS.md read for current migration context

---

## Evidence

### Q1 — How `deploy-ecs.yaml` works today

**File:** `/Users/plribeiro3000/Projects/4Shark/integrator/.github/workflows/deploy-ecs.yaml`

The workflow is triggered via `workflow_dispatch` with a single input:

```yaml
inputs:
  integrator:
    description: 'Integrator to deploy'
    required: true
    type: string
```

It derives all resource names from this single string using the convention
`integrator-{inputs.integrator}-{suffix}`. Examples:

| Resource | Pattern | Example |
|---|---|---|
| GitHub Environment | `${{ inputs.integrator }}` | `almaviva` |
| ECS cluster | `integrator-${{ inputs.integrator }}-cluster` | `integrator-almaviva-cluster` |
| ECS service (web) | `integrator-${{ inputs.integrator }}-web-service` | `integrator-almaviva-web-service` |
| ECS service (worker) | `integrator-${{ inputs.integrator }}-worker-service` | `integrator-almaviva-worker-service` |
| Task family (runner) | `integrator-${{ inputs.integrator }}-runner` | `integrator-almaviva-runner` |
| Cron task prefix | `integrator-${{ inputs.integrator }}-cron-` | `integrator-almaviva-cron-` |
| ECR repo | `integrator-${{ inputs.integrator }}` | `integrator-almaviva` |
| MongoDB tag pattern | `4client-${{ inputs.integrator }}-mongo*` | `4client-almaviva-mongo*` |

Source: `deploy-ecs.yaml` lines 34, 43, 93–94, 143–146, 213–217, 233–237, 263, 295

**What the workflow does (job sequence):**

1. `preflight` — checks that all MongoDB EC2 instances matching `4client-{integrator}-mongo*` are running
2. `quiet-worker` — sends SIGTSTP to Sidekiq in the running worker task (stops fetching new jobs)
3. `migrate` — runs `db:migrate` + mongoid index tasks via an ephemeral `run-task` (reads network config from `runner-service`)
4. `deploy-web` and `deploy-worker` (parallel, after migrate) — register new task definition with latest image via `.github/actions/deploy-ecs/action.yaml`, then call `ecs update-service`
5. `register-cron-tasks` (parallel with migrate) — updates image in all task definitions matching prefix `integrator-{integrator}-cron-*`

**What the `deploy-ecs` action does:**

Source: `/Users/plribeiro3000/Projects/4Shark/integrator/.github/actions/deploy-ecs/action.yaml`

The action receives `task-family`, `service-name`, `ecs-cluster`, `ecs-service`, `ecr-repo`, and `image-tag`.
It performs three operations:
1. Fetches the current task definition from ECS (`describe-task-definition`)
2. Replaces only the container image (and command) — all other fields (env vars, secrets, memory, cpu) come from the existing task definition as stored in ECS
3. Registers the new task definition revision
4. Calls `ecs update-service --task-definition` to deploy it

**Critical design fact:** env vars are NOT passed by the workflow. They live in the ECS task definition (managed by Terraform via SSM). The action is truly image-only.

Source: `deploy-ecs/action.yaml` line 58–93 — the only mutation is `(.containerDefinitions[] | select(.name == $NAME)).image = $IMAGE`

**Contrast with legacy `deploy` action:**

Source: `/Users/plribeiro3000/Projects/4Shark/integrator/.github/actions/deploy/action.yaml`

The legacy action accepts `vars-json` and `secrets-json` (full GitHub Environment contents) and injects them into the task definition. This is the old pattern (env vars in GitHub Environments). The new pattern (SSM) eliminates these inputs.

---

### Q1 — Evolution needed for multi-environment

The current workflow assumes **one service named `web-service` and one named `worker-service`** per integrator. For atento with BR/MX/CO/CL, the services would be named differently — e.g., `integrator-atento-web-br-service`, `integrator-atento-worker-br-service`, etc.

**Option A — Add `environment` input to `deploy-ecs.yaml`**

```yaml
inputs:
  integrator:
    description: 'Client name (e.g., atento)'
    required: true
    type: string
  environment:
    description: 'Environment suffix (e.g., br, mx, co — empty for single-env clients)'
    required: false
    default: ''
    type: string
```

Then the naming convention becomes:

```bash
ENV_SUFFIX="${{ inputs.environment }}"
SVC_SUFFIX=$([ -n "$ENV_SUFFIX" ] && echo "-${ENV_SUFFIX}" || echo "")

web_service="integrator-${{ inputs.integrator }}-web${SVC_SUFFIX}-service"
worker_service="integrator-${{ inputs.integrator }}-worker${SVC_SUFFIX}-service"
```

- Single-env clients (almaviva, maqnelson, redebrasil): `environment = ""` → `integrator-almaviva-web-service` (unchanged)
- Multi-env clients (atento BR): `environment = "br"` → `integrator-atento-web-br-service`

The `quiet-worker` job targets one specific worker service. For multi-env deploys, the job would need to be parameterized or called once per environment.

The `preflight` MongoDB check uses tag pattern `4client-{integrator}-mongo*`. For `atento` (renamed from `atento-br`), the pattern would become `4client-atento-mongo*` — works as-is since it uses a wildcard.

**Option B — One workflow call per environment (matrix)**

Call `deploy-ecs.yaml` once per environment using a calling workflow with a matrix strategy. The called workflow remains unchanged (still takes `integrator` as single input), but the resource naming convention would need to be built differently.

This option requires a wrapper workflow and is harder to maintain.

**Option A is the minimal evolution.** The change is one new optional input and a conditional suffix in service/task names. Single-env clients pass no environment, multi-env clients pass the environment code.

---

### Q1 — GitHub Environment strategy for multi-env

**Current state:** Each integrator has one GitHub Environment (e.g., `almaviva`) containing `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`. SSM holds all application secrets.

**For atento with multiple environments:** The IAM credentials are per-client (one IAM deploy user per integrator, managed by `modules/iam_deploy`). All environments (BR, MX, CO, CL) share the same AWS IAM user and same cluster. Therefore:

- **One GitHub Environment per client** is sufficient: `atento` with one pair of AWS credentials
- The workflow uses `environment: ${{ inputs.integrator }}` (e.g., `atento`) regardless of which country is being deployed
- Application secrets per country live in SSM under `/integrator-atento/br/*`, `/integrator-atento/mx/*`, etc.

This is consistent with how the IAM deploy module works: one IAM user per cluster, permissions scoped to `arn:aws:ecs:...:service/integrator-atento-cluster/*`.

Source: `integrator-almaviva/compute.tf` lines 397–420 — `module "iam_deploy"` creates one IAM user per cluster.

---

### Q1 — ECR: 1-per-client vs 1-per-client-per-environment

All current integrators have one ECR repo per client: `integrator-almaviva`, `integrator-maqnelson`, `integrator-redebrasil`. The image is the same binary for all services — the container command (Puma vs Sidekiq) and environment variables differentiate them.

Source: `integrator-almaviva/compute.tf` lines 125, 165, 203 — all three services (web, worker, runner) reference `integrator-almaviva:latest`.

For atento, all four environments (BR, MX, CO, CL) would share one ECR repo `integrator-atento:latest`. This is the correct pattern — they run the same application code with different env vars.

---

### Q2 — Terraform design: current pattern

Every migrated integrator has exactly the same file structure:

```
integrator-{client}/
├── compute.tf    — ECS cluster, ALB, services, schedules, IAM deploy
├── ecr.tf        — ECR repository
├── main.tf       — VPC data, integrator module, IAM module
├── mongodb.tf    — mongo003/004/005 instances
├── ssm.tf        — SSM parameters + IAM policy for ecsTaskExecutionRole
└── ...
```

**Pattern in `compute.tf`:**

All services share one `locals` block with `env_vars` (map) and `secrets` (list) that are passed identically to all modules. The cluster, ALB, security group, and IAM role are each declared once. Services are separate `module "web"`, `module "worker"`, `module "runner"` calls.

Source: `integrator-almaviva/compute.tf` lines 5–60 (locals), 66–68 (cluster), 115–221 (three service modules), 227–275 (IAM role), 282–391 (schedules), 397–420 (iam_deploy).

**Pattern in `ssm.tf`:**

One `aws_ssm_parameter.secrets` resource using `for_each` over a `toset` of secret names. All parameters have the path prefix `/integrator-{client}/`. One `aws_iam_role_policy` grants `ecsTaskExecutionRole` access to the entire `arn:aws:ssm:...:parameter/integrator-{client}/*` path.

Source: `integrator-almaviva/ssm.tf` lines 16–43 (parameters), 49–70 (IAM policy).

**Key structural fact:** The `ecs_service` module already accepts `environment_variables` as a map and `secrets` as a list. There is no structural barrier to passing different maps to different service module calls.

Source: `modules/ecs_service/main.tf` line 33 — `environment = local.environment_list` where `environment_list` is derived from `var.environment_variables`.

---

### Q2 — Proposed design: `integrator-atento/`

**Folder name:** `integrator-atento/` (renamed from `integrator-atento-br/`).

**Environments (services) within the cluster:**

| Service | Task family | Count |
|---|---|---|
| `integrator-atento-web-br-service` | `integrator-atento-web-br` | 1 |
| `integrator-atento-worker-br-service` | `integrator-atento-worker-br` | 2 |
| `integrator-atento-web-mx-service` | `integrator-atento-web-mx` | 1 |
| `integrator-atento-worker-mx-service` | `integrator-atento-worker-mx` | 2 |
| `integrator-atento-web-co-service` | `integrator-atento-web-co` | 1 |
| `integrator-atento-worker-co-service` | `integrator-atento-worker-co` | 2 |
| `integrator-atento-runner-service` | `integrator-atento-runner` | 0 (on-demand) |

Chile (CL) services are defined with `desired_count = 0` and no active schedules.

**ECS cluster:** One `aws_ecs_cluster.this` named `integrator-atento-cluster`. The `modules/ecs_service` module takes `cluster_name` as an input — all service modules point to the same cluster resource.

Source: `integrator-almaviva/compute.tf` line 66–68, `modules/ecs_service/main.tf` line 78.

**Internal ALB:** One ALB per client is the correct pattern. For atento, all web services (BR, MX, CO) share one ALB using **host-based routing**. Each country gets its own DNS name and target group.

The current `modules/internal_alb` creates one ALB with one target group and one listener. To support multiple target groups on the same ALB:

**Option A — Multiple ALBs (one per environment):** Simple, no module changes. Adds cost (~$16/month each for internal ALBs). For 4 environments = ~$64/month extra. Naming: one ALB named `integrator-atento-br`, another `integrator-atento-mx`, etc.

**Option B — One ALB, multiple target groups, host-based routing:** The `modules/internal_alb` module creates one target group and one listener. To support multiple target groups, either:
  - Instantiate the module multiple times with different `name_prefix` values (creates multiple ALBs — same as Option A)
  - Extend `modules/internal_alb` to accept multiple target groups with host-based listener rules
  - Declare the additional target groups and listener rules directly in `compute.tf` without the module

**Option C — One ALB, path-based routing:** The `modules/internal_alb` already supports `listener_rules` with path patterns. All countries could share one DNS name and use URL path prefixes (e.g., `/br/*`, `/mx/*`). This requires application-level routing support.

DNS today is `integrator-{client}.4shark.internal` (single record pointing to the ALB). For multi-env, the DNS would need to be either:
- `integrator-atento.4shark.internal` (one name, path-based routing)
- `integrator-atento-br.4shark.internal`, `integrator-atento-mx.4shark.internal`, etc. (host-based routing, separate DNS per env)

**Note:** The ALB listener rules in `modules/internal_alb` are path-based (`path_pattern`), not host-based. Adding host-based routing requires either module changes or direct resource declarations in `compute.tf`.

**SSM namespace:** `/integrator-atento/{br,mx,co,cl}/{SECRET_NAME}`.

The current `ssm.tf` pattern uses a flat `for_each` over one set of secret names. For multi-env, two approaches:

**Approach A — Per-environment SSM resources:**
```hcl
locals {
  envs = ["br", "mx", "co", "cl"]
  ssm_secret_names = ["SECRET_KEY_BASE", "CLIENT_PASSWORD", ...]
}

resource "aws_ssm_parameter" "secrets" {
  for_each = toset([
    for pair in setproduct(local.envs, local.ssm_secret_names) : "${pair[0]}/${pair[1]}"
  ])
  name  = "/integrator-atento/${each.key}"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}
```

The IAM policy uses a wildcard path: `arn:aws:ssm:...:parameter/integrator-atento/*` — this already covers all sub-paths.

Source: `integrator-almaviva/ssm.tf` line 60 — `"arn:aws:ssm:sa-east-1:405749097490:parameter/integrator-almaviva/*"`. A wildcard at this level covers nested paths.

**Approach B — Separate `ssm.tf` per environment** (separate `locals.ssm_secret_names` per env): Verbose but explicit. Easier to have different secret sets per country.

**Services parametrization:** Rather than one `module "web"` call, atento needs multiple calls — one per environment. Each call passes a different `environment_variables` map (containing country-specific vars like `CLIENT_HOST`, `MONGODB`, etc.) and a different `secrets` list pointing to the env-specific SSM paths.

The existing pattern supports this directly without any module changes:

```hcl
module "web_br" {
  source       = "../modules/ecs_service"
  service_name = "integrator-atento-web-br-service"
  task_family  = "integrator-atento-web-br"
  ...
  environment_variables = local.env_vars_br
  secrets               = local.secrets_br
}

module "web_mx" {
  source       = "../modules/ecs_service"
  service_name = "integrator-atento-web-mx-service"
  task_family  = "integrator-atento-web-mx"
  ...
  environment_variables = local.env_vars_mx
  secrets               = local.secrets_mx
}
```

**EventBridge schedules:** The current pattern has one set of schedules (scale-up web + scale-up worker + cron RunTask) per integrator. For atento with multiple countries, there are two sub-questions:

1. Do all countries run at the same time? (single schedule triggers scale-up of all services)
2. Or does each country have its own independent schedule?

The TASKS.md specifies atento schedule: `cron(55 1 * * ? *)` for scale-up and `cron(0 2 * * ? *)` for cron — these are listed once, with no per-country differentiation. This suggests all countries run on the same schedule window. If that is the case:

- Scale-up schedules: one per service type per country (i.e., 6 `UpdateService` calls at 01:55: web-br, worker-br, web-mx, worker-mx, web-co, worker-co)
- Cron schedules: one per country (BR, MX, CO each gets a separate `ecs_scheduled_task` module call with country-specific env vars)

Alternatively, if all countries run the same rake task and the application differentiates internally, there could be a single cron trigger per integrator. This is a design question for the application layer.

**`terraform state mv` scope for the rename:**

The current `integrator-atento-br/` terraform stack would become `integrator-atento/`. The rename affects:

- Stack folder: `integrator-atento-br/` → `integrator-atento/`
- All `aws_` resource names in state (they embed `atento-br` in their names)
- SSM parameters under `/integrator-atento-br/*` → `/integrator-atento/*`
- ECS cluster name: `integrator-atento-br-cluster` → `integrator-atento-cluster` (currently does not exist — this is a new resource)
- Networking stack: `vpc_atento_br.tf` → rename to `vpc_atento.tf`, update all resource names and tags
- DNS record: `integrator-atento-br.4shark.internal` → `integrator-atento.4shark.internal` (or per-env records)
- Tags: `4client-atento-br-*` → `4client-atento-*`
- GitHub Environment: `atento-br` → `atento`

**Important:** The current `integrator-atento-br/` stack has NO `compute.tf` or `ssm.tf` yet — it has not been migrated. The EC2 app servers (`app002`, `mx-app002`, `co-app002`, `cl-app002`) are still running.

Source: `integrator-atento-br/` directory listing shows only `ecr.tf`, `main.tf`, `monitoring_data.tf`, `output.tf`, `providers.tf`. No `compute.tf` or `ssm.tf` exist yet.

The rename must happen **before** creating `compute.tf`, so there is no state to migrate for ECS resources. State migration only applies to the existing resources: VPC, subnets, MongoDB, ElastiCache, VPN, EC2 app servers.

---

### Q3 — Retrofitting almaviva, maqnelson, redebrasil

**Current state:**
- All three are single-environment clients
- Service names: `integrator-{client}-web-service`, `integrator-{client}-worker-service`
- SSM paths: `/integrator-{client}/{SECRET_NAME}` (no environment sub-path)
- GitHub Environment: `{client}` (e.g., `almaviva`)

**What the new pattern would require:**
If the new pattern forces every client to have ≥1 environment suffix, single-env clients would need:
- Service names: `integrator-almaviva-web-prod-service`
- SSM paths: `/integrator-almaviva/prod/{SECRET_NAME}`
- GitHub Environment: still `almaviva` (no change needed)
- DNS: `integrator-almaviva-prod.4shark.internal` or remain `integrator-almaviva.4shark.internal`

**Retrofit cost:**

For each of the three clients, retrofitting requires:
1. Rename all ECS services and task definitions (recreate — ECS services cannot be renamed in-place)
2. Move SSM parameters to new paths
3. Update `compute.tf` naming conventions
4. Update `ssm.tf` paths
5. Update DNS records
6. Re-trigger GitHub Actions deploy to register the new task definitions
7. Update the `deploy-ecs.yaml` GitHub Environment name if it changes

This is non-trivial for production clients. Almaviva and maqnelson are actively running daily cycles.

**Alternative: Optional `environment` input in the workflow**

If the `deploy-ecs.yaml` workflow adds an optional `environment` input (defaulting to empty), then:
- Single-env clients: call `deploy-ecs.yaml` with `integrator: almaviva` (no environment) → names stay as-is
- Multi-env clients: call with `integrator: atento, environment: br` → names get the `-br` suffix

This means single-env clients keep their current naming convention and **do not need to be retrofitted**. The pattern is "environment suffix is optional — only multi-env clients use it."

SSM paths would remain `/integrator-almaviva/{SECRET_NAME}` for single-env clients. The new multi-env clients would use `/integrator-atento/br/{SECRET_NAME}`. This is a naming inconsistency but not a functional problem.

---

## Conclusions

### Q1 — `deploy-ecs.yaml` evolution

The current workflow takes one input (`integrator`) and derives all resource names from it using the convention `integrator-{client}-{service_type}-service`. This works for single-env clients.

**Minimum evolution for multi-env:** Add an optional `environment` input to `deploy-ecs.yaml`. When provided, it inserts a suffix in service names: `integrator-atento-web-br-service`. When absent, behavior is identical to today: `integrator-almaviva-web-service`.

The `deploy-ecs` action itself does not need changes — it receives explicit cluster, service, task-family, and ECR names as inputs.

The `quiet-worker` and `migrate` jobs target one specific service. For multi-env deploys, a separate workflow run per environment is the simplest approach (call `deploy-ecs.yaml` once for `br`, once for `mx`). An alternative is to scope `quiet-worker` and `migrate` to the specific environment being deployed, which Option A already handles.

**ECR:** One repo per client (`integrator-atento`), shared across all environments. No changes needed.

**GitHub Environment:** One per client (`atento`), not per country. No changes needed at the GitHub level.

### Q2 — Terraform design

**Cluster:** One `integrator-atento-cluster` per client — identical to the existing pattern. No design change needed at the cluster level.

**Services:** Multiple `module` calls in `compute.tf`, one per (service type × environment): `module "web_br"`, `module "worker_br"`, `module "web_mx"`, etc. Each call receives environment-specific `env_vars` and `secrets` locals. The `modules/ecs_service` module needs no changes.

**ALB:** This is the main open question. Three options exist (see Q2 evidence). The simplest that avoids module changes is to instantiate `modules/internal_alb` once per environment (one ALB per country). This is the same pattern as separate clients — each environment gets its own DNS record and ALB. Cost: ~$16/month per additional ALB (3 extra for MX, CO, CL).

Alternatively, if host-based routing is acceptable, one ALB with multiple target groups and per-country listener rules can be declared directly in `compute.tf` without the module. This requires new `aws_lb_listener_rule` resources pointing different `Host` headers to different target groups.

**SSM:** The wildcard IAM policy `parameter/integrator-atento/*` covers nested paths. Using `for_each` with a cross-product of environments × secret names is a clean approach.

**EventBridge schedules:** If all countries run on the same window, the scale-up schedules need one `UpdateService` call per service (6 calls at 01:55 for web-br, worker-br, web-mx, worker-mx, web-co, worker-co). Each cron task (`ecs_scheduled_task` module) needs its own environment-specific env vars.

**Module changes:** No module changes are required for the core design. The `ecs_service`, `ecs_scheduled_task`, and `internal_alb` modules all support the multi-env pattern through repeated instantiation with different parameters.

**terraform state mv scope:** The rename from `integrator-atento-br` to `integrator-atento` must happen before `compute.tf` is created. For the networking stack, all resource names and SSM parameters that contain `atento-br` must be renamed. For the integrator stack, only MongoDB and EC2 app server resources exist today — the rename of those resources does not require state mv if done carefully (Terraform can track them by resource address, not by the AWS resource name).

### Q3 — Retrofit recommendation

**Do not retrofit almaviva, maqnelson, or redebrasil now.**

The reason is that retrofitting requires recreating ECS services in production (ECS services cannot be renamed in-place). Each recreation creates a deployment event on an actively running client. The operational risk is non-trivial.

The naming inconsistency (single-env clients use `integrator-almaviva-web-service`, multi-env clients use `integrator-atento-web-br-service`) is a documentation concern, not a functional one. Both naming styles work correctly with the proposed optional `environment` input in `deploy-ecs.yaml`.

If a future decision is made to standardize all clients to the multi-env naming, it can be done after all migrations are complete (lower urgency, no active migrations at risk).

---

## Decisions required before updating PLAN.md

The following decisions must be made explicitly. None are purely technical — each has tradeoffs.

**Decision 1 — ALB design for atento** ✅ DECIDED (2026-04-10)

**Answer:** Option B — one ALB with host-based routing.

Design:
- 1 `aws_lb` (internal ALB) named `integrator-atento`
- 1 `aws_lb_listener` on port 80
- N `aws_lb_listener_rule` with `host_header` condition, one per environment
- N `aws_lb_target_group` with `target_type = "ip"` (one per environment)
- N DNS records in `dns/internal_dns_integrator.tf` all pointing to the same ALB: `integrator-atento-br.4shark.internal`, `integrator-atento-mx.4shark.internal`, `integrator-atento-co.4shark.internal`, `integrator-atento-cl.4shark.internal`
- The `internal_alb` module will NOT be used for atento — resources declared directly in `compute.tf`
- Each `module "web_{country}"` receives its target group ARN as input

Tradeoff accepted: ~$48/month savings (1 ALB vs 4), at the cost of more complex Terraform and single-ALB blast radius. The centralized topology fits the multi-environment pattern better than four parallel ALBs.

**Decision 2 — Deploy workflow: one call per environment or one call with matrix** ✅ DECIDED (2026-04-10)

**Answer:** One dispatch per country. Each country has its own deploy window and upgrade cadence, so coupling them into a matrix would force synchronized releases that don't match operational reality.

**Decision 3 — Schedule design: same window for all countries, or per-country schedules** ✅ DECIDED (2026-04-10)

**Answer:** Each country has its own schedule — countries are in different timezones and processing windows are independent. This means separate EventBridge rules per environment (Schedule 1 + Schedule 2 per country).

**Decision 4 — Rename scope: what exactly changes from `atento-br` to `atento`** ✅ DECIDED (2026-04-10)

**Answer:** Rename everything renameable, including MongoDB EC2 tags (`4client-atento-br-mongo*` → `4client-atento-mongo*`). Ordering: update MongoDB tags BEFORE the first deploy so the preflight check keeps working.

The list includes:
- Terraform stack folder: `integrator-atento-br/` → `integrator-atento/`
- Networking vpc file: `vpc_atento_br.tf` → `vpc_atento.tf`
- All AWS resource names (tags, SSM paths, security group names, route table names)
- GitHub Environment: `atento-br` → `atento`
- DNS record: `integrator-atento-br.4shark.internal` → `integrator-atento.4shark.internal`
- ECR repo: `integrator-atento-br` → `integrator-atento` (already exists — needs terraform rename)

**What cannot be renamed without recreating:** ECS cluster (does not exist yet — first time creation), ALB (does not exist yet), VPC (cannot rename ID, only tags), subnets (cannot rename IDs, only tags).

**Decision 5 — Runner: one per client or one per environment** ✅ DECIDED (2026-04-10)

**Answer:** One runner per environment (per country for atento). Reason: each country has its own MongoDB connection string and the runner task definition needs those env vars baked in. A shared runner would force runtime overrides or task-def swaps, both of which add complexity. Per-country runners are symmetric with web/worker, cost zero at runtime (`desired_count = 0`), and let `bin/ecs run atento br <cmd>` vs `bin/ecs run atento co <cmd>` resolve to different services naturally.

Services to create for atento: `runner-br`, `runner-mx`, `runner-co`, `runner-cl`. The `deploy.sh` migration step picks the runner for the specific country being deployed.

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
