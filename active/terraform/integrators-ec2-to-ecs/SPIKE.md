# SPIKE — Viability of migrating integrator application servers from EC2 to ECS

**Conducted by:** Engineering team
**Date:** 2026-03-16
**Status:** Research complete — pending decisions

---

## Goal

Investigate the technical and financial viability of migrating all 6 integrator application servers from
standalone EC2 instances to ECS (Elastic Container Service), with the following motivations:

1. Eliminate manual OS updates on EC2 instances
2. Eliminate manual Ruby version updates (currently requiring SSH + ansible)
3. Replace fragile Capistrano deploys with a container-based deploy pipeline
4. Align the integrators with the deployment model already proven by the app stacks (app-atento-001, app-shared-001)

---

## Method

- Full analysis of the Terraform codebase at `/Users/plribeiro3000/Projects/4Shark/terraform`
- Examined all 6 integrator stacks and the shared `modules/integrator` module
- Studied the existing ECS implementation in `app-atento-001` and `app-shared-001` as reference patterns
- Examined modules: `ecs_cluster`, `ecs_capacity`, `ecs_service`
- Researched current AWS pricing for EC2 (t3.small, t3.medium) and ECS (EC2 launch type vs Fargate)
- Researched community experience deploying Rails + Sidekiq on ECS

---

## Evidence

### 1. Current Integrator Infrastructure

#### 1.1 Six integrators and their EC2 instances

| Integrator | App Servers | Instance Types | Notes |
|---|---|---|---|
| atento-br | `app002`, `mx-app002` | t3.medium each | mx-app002 has custom name `4client-atento-mx-app002` |
| almaviva | `app002`, `app003` | t3.medium each | — |
| aster-maquinas | `app002`, `staging-app001` | t3.small each | Has staging environment |
| commcenter | `app002`, `staging-app001` | t3.small each | Has staging environment |
| maqnelson | `app002`, `app003` | t3.medium each | — |
| redebrasil | `app002` | t3.medium | Smallest — single server |

**Source:** Files `integrator-*/main.tf`, `modules/integrator/app.tf`

#### 1.2 What each EC2 instance runs today

Each EC2 instance runs both processes simultaneously via Ansible + Capistrano:
- **Web process**: Puma (Rails app, listening on a port)
- **Sidekiq process**: Background job processor

Both processes share the same EC2 OS, Ruby installation, and codebase directory. Deploys are managed
by Capistrano, which SSHes into the instance and restarts services.

#### 1.3 Atento BR has multiple tenants

As noted in the investigation context, Atento BR has queues/tenants that require separate task
isolation: Atento México, Colombo, and Chile. This means `atento-br` needs more than 2 ECS tasks.

The Terraform confirms a separate app server `mx-app002` (named `4client-atento-mx-app002`) for
the Mexico tenant, in addition to the main `app002`.

#### 1.4 Infrastructure components per integrator

Each integrator stack includes:
- VPC with public and private subnets (dedicated per integrator)
- Site-to-site VPN (IPSec) to the client's on-premises network
- MongoDB replica set (arbiter + primary + secondary) — 3 EC2 instances NOT being migrated
- ElastiCache Redis (cache.t2.small or cache.t3.medium)
- IAM user per client
- Route53 internal zone association

**Source:** `modules/integrator/` (all .tf files)

#### 1.5 Current secrets/env vars management

There is no Secrets Manager or Parameter Store integration found in the integrator module. Environment
variables are currently managed via Ansible (applied directly to the EC2 instance's environment
or application config files). The `modules/integrator_iam` creates only an IAM user — no
policies are attached in the Terraform for secret access.

**Source:** `modules/integrator_iam/main.tf`, `modules/integrator/`

---

### 2. ECS EC2 vs ECS Fargate — how compute works

This distinction is critical for understanding the cost model.

#### ECS EC2 launch type (current app stack pattern)

```
┌─────────────────────────────────────────────┐
│  ECS Cluster                                │
│                                             │
│  ┌──────────────┐  ┌──────────────┐         │
│  │ EC2 t3.small │  │ EC2 t3.small │  ...    │
│  │  (web svc)   │  │ (worker svc) │         │
│  │              │  │              │         │
│  │  [task]      │  │  [task]      │         │
│  │  uses 0.25   │  │  uses 0.25   │         │
│  │  of 2 vCPU   │  │  of 2 vCPU   │         │
│  └──────────────┘  └──────────────┘         │
└─────────────────────────────────────────────┘
```

- 1 dedicated EC2 per service (capacity provider pattern used in app stacks)
- You pay for the full EC2 instance regardless of task utilization
- A task using 0.25 vCPU on a t3.small (2 vCPU) wastes 87% of the instance's compute
- You manage: AMI updates, ASG config, Launch Templates, capacity providers

#### ECS Fargate

```
┌─────────────────────────────────────────────┐
│  ECS Cluster                                │
│                                             │
│  [task: 0.25vCPU/0.5GB]  ← billed exactly  │
│  [task: 0.5vCPU/1GB]     ← billed exactly  │
│  [task: 0.25vCPU/0.5GB]  ← billed exactly  │
│  ...                                        │
│                                             │
│  No EC2 instances. AWS allocates compute    │
│  invisibly. You never see or manage it.     │
└─────────────────────────────────────────────┘
```

- **Zero EC2 instances.** No AMI, no ASG, no Launch Template, no capacity provider.
- You declare: "I want a task with 0.25 vCPU + 0.5 GB". AWS provisions exactly that.
- You pay per vCPU-second and GB-second the task actually runs — nothing more.
- No overprovisioning possible. No idle compute to pay for.

**The $348.66/month Fargate cost is the complete compute cost** — there are no EC2 instances
underneath. Each line in the cost table is the exact charge for that task's allocated resources.

#### Existing ECS pattern reference (app stacks)

The app stacks use ECS EC2 launch type:
- 1 capacity provider (EC2 ASG) per service — `modules/ecs_capacity`
- Bridge network mode, `requires_compatibilities = ["EC2"]`
- CodeDeploy blue/green for web; rolling for workers
- `lifecycle { ignore_changes = [container_definitions] }` — CI/CD manages image + env vars

For integrators on **Fargate**, the capacity provider layer is removed entirely. The `ecs_service`
module needs to support `launch_type = FARGATE` + `network_mode = awsvpc` as a new mode.

**Source:** `app-atento-001/compute.tf`, `app-shared-001/compute.tf`, `modules/ecs_service/main.tf`

---

### 3. ECS Service Mapping and Naming Convention

#### 3.1 Naming convention (derived from existing app stacks)

The app stacks (`app-atento-001`, `app-shared-001`) establish the following patterns:

| Resource | Pattern | Example |
|---|---|---|
| ECS cluster | `{stack}-cluster` | `integrator-almaviva-cluster` |
| Service (web) | `{stack}-web-service` | `integrator-almaviva-web-service` |
| Service (worker) | `{stack}-worker-{queue}-service` | `integrator-almaviva-worker-service` |
| Service (runner) | `{stack}-runner` | `integrator-almaviva-runner` |
| Task family | `{stack}-web` / `{stack}-worker-{queue}` | `integrator-almaviva-web` |
| Container name | same as task family | `integrator-almaviva-web` |
| CloudWatch log group | `/ecs/{stack}-web` / `/ecs/{stack}-worker-{queue}` | `/ecs/integrator-almaviva-web` |
| Capacity provider | `{stack}-web` / `{stack}-worker-{queue}` | (ECS EC2 only — not needed on Fargate) |

**Stack name convention for integrators**: `integrator-{client-name}` (e.g., `integrator-almaviva`,
`integrator-atento-br`, `integrator-redebrasil`)

#### 3.2 Atento BR — VPN and multi-country architecture

All Atento BR countries (México, Colômbia, Chile) share a **single VPN** and single VPC. This is
by design: all client databases are in the same network, so one VPN is both cheaper and simpler
than one per country. Each country gets separate ECS services with different environment variables
(database URLs, API keys, etc.) but they all run within the same stack.

#### 3.3 Service mapping per integrator (confirmed)

| Integrator | ECS Services | Running tasks | Notes |
|---|---|---|---|
| atento-br | web-br, web-mx, web-co, web-cl, worker-br, worker-mx, worker-co, worker-cl | 8 | 4 countries, all defined |
| almaviva | web (d=1), worker (d=2) | 3 | One queue, 2 tasks for throughput |
| aster-maquinas | web-prod, worker-prod, web-staging, worker-staging | 4 | Active staging clients |
| commcenter | web-prod, worker-prod, web-staging, worker-staging | 4 | Active staging clients |
| maqnelson | web (d=1), worker (d=2) | 3 | One queue, 2 tasks for throughput |
| redebrasil | web (d=1), worker (d=1) | 2 | Simplest — start here |
| **TOTAL** | | **22 tasks** | |

`d=N` = `desired_count` — number of running containers for that service.

All integrators also get a **runner** task definition (on-demand, not a long-running service) — named
`{stack}-runner` — for isolated one-off executions (migrations, rake tasks) via `ecs run-task`.

---

### 4. Cost Analysis

#### 4.1 Current EC2 costs (on-demand pricing, sa-east-1)

| Integrator | Servers | Instance Type | Monthly Cost |
|---|---|---|---|
| atento-br | 2x | t3.medium | 2 × $38.54 = $77.08 |
| almaviva | 2x | t3.medium | 2 × $38.54 = $77.08 |
| aster-maquinas | 2x | t3.small | 2 × $19.27 = $38.54 |
| commcenter | 2x | t3.small | 2 × $19.27 = $38.54 |
| maqnelson | 2x | t3.medium | 2 × $38.54 = $77.08 |
| redebrasil | 1x | t3.medium | 1 × $38.54 = $38.54 |
| **TOTAL** | **11 instances** | | **$346.86/month** |

*Prices: t3.small = $0.0264/hr ($19.27/mo), t3.medium = $0.0528/hr ($38.54/mo). On-demand, Linux, sa-east-1.*

#### 4.2 Final service mapping (all questions answered)

| Integrator | ECS Services | Running tasks | Runner (on-demand) |
|---|---|---|---|
| atento-br | web-mx, web-co, worker-mx (d=2), worker-co (d=2) | 6 | 1 task def |
| almaviva | web (d=1), worker (d=2) | 3 | 1 task def |
| aster-maquinas | web-prod, worker-prod, web-staging, worker-staging | 4 | 1 task def |
| commcenter | web-prod, worker-prod, web-staging, worker-staging | 4 | 1 task def |
| maqnelson | web (d=1), worker (d=2) | 3 | 1 task def |
| redebrasil | web (d=1), worker (d=1) | 2 | 1 task def |
| **TOTAL** | **18 services** | **22 tasks** | **6 on-demand** |

**Runner**: on-demand isolated task (migrations, rake tasks) — `ecs run-task` via ECS Exec.
Billed per-second on Fargate (~$0.02 per execution). Does not disturb running web or worker services.

#### 4.3 ECS EC2 launch type costs

ECS EC2 launch type requires one dedicated EC2 instance per service (one capacity provider per service,
as used in app stacks). Even if the container uses only 20% of the instance, the full instance is billed.

One EC2 instance per ECS service (capacity provider pattern). Multiple tasks (`desired_count > 1`)
from the same service share that one instance.

| Integrator | ECS Services | EC2 instances (t3.small each) | Monthly Cost |
|---|---|---|---|
| atento-br | web-mx, web-co, worker-mx, worker-co | 4 × $19.27 | $77.08 |
| almaviva | web, worker | 2 × $19.27 | $38.54 |
| aster-maquinas | web-prod, worker-prod, web-staging, worker-staging | 4 × $19.27 | $77.08 |
| commcenter | web-prod, worker-prod, web-staging, worker-staging | 4 × $19.27 | $77.08 |
| maqnelson | web, worker | 2 × $19.27 | $38.54 |
| redebrasil | web, worker | 2 × $19.27 | $38.54 |
| **TOTAL** | **18 services** | **18 EC2 instances** | **$346.86/month** |

**Result**: 18 t3.small instances costs exactly the same as the current 11 EC2 instances.
Zero savings, added operational complexity. ECS EC2 is ruled out.

#### 4.4 ECS Fargate costs

Fargate pricing (sa-east-1): vCPU = $0.05056/hr, Memory = $0.00553/GB/hr.
Fargate bills only for the exact vCPU + memory allocated to each task — no wasted capacity.

Task sizing:
- **Web (Puma)**: 0.5 vCPU + 1 GB → $0.03081/hr → **$22.49/mo per task**
- **Sidekiq**: 0.25 vCPU + 0.5 GB → $0.01541/hr → **$11.25/mo per task**
- **Run (on-demand)**: billed per-second at execution time — negligible (a 3-minute migration ≈ $0.02)

Fargate bills per running task. Task sizes: web = 0.5 vCPU + 1 GB ($22.49/mo), worker = 0.25 vCPU + 0.5 GB ($11.25/mo).

Staging tasks can use the same sizing as production (Rails requires memory regardless of traffic).

| Integrator | Tasks | Cost breakdown | Monthly Cost |
|---|---|---|---|
| atento-br | web-mx(1) + web-co(1) + worker-mx(2) + worker-co(2) = 6 | 2×$22.49 + 4×$11.25 | $89.98 |
| almaviva | web(1) + worker(2) = 3 | 1×$22.49 + 2×$11.25 | $44.99 |
| aster-maquinas | web-prod(1) + worker-prod(1) + web-stg(1) + worker-stg(1) = 4 | 2×$22.49 + 2×$11.25 | $67.48 |
| commcenter | web-prod(1) + worker-prod(1) + web-stg(1) + worker-stg(1) = 4 | 2×$22.49 + 2×$11.25 | $67.48 |
| maqnelson | web(1) + worker(2) = 3 | 1×$22.49 + 2×$11.25 | $44.99 |
| redebrasil | web(1) + worker(1) = 2 | 1×$22.49 + 1×$11.25 | $33.74 |
| **TOTAL** | **22 tasks** | | **$348.66/month** |

#### 4.5 Three-way cost comparison (final numbers)

| Option | Monthly Cost | vs Current |
|---|---|---|
| **Current EC2** (11 instances) | $346.86 | baseline |
| **ECS EC2 launch type** (18 instances) | $346.86 | **$0 (0%)** — zero savings |
| **ECS Fargate** (22 tasks) | $348.66 | **+$1.80/month (+0.5%)** |

**Key finding**: with staging environments included, the final cost of ECS Fargate is essentially
the same as today (~+$1.80/month, within rounding). ECS EC2 offers zero savings.

This means the migration is **cost-neutral** — we are paying roughly the same but eliminating all
operational toil (manual OS/Ruby updates, fragile Capistrano deploys, SSH key management).

**Optional staging optimization**: if staging tasks are sized smaller (0.25 vCPU + 0.5 GB each),
the two staging web services for aster-maquinas and commcenter drop from $22.49 to $11.25 each,
saving $22.48/month — bringing Fargate to $326.18/month (-$20.68/month, -6% vs current).
This is viable if Rails staging instances run with fewer Puma workers and lower memory limits.

---

### 5. Technical Changes Required

#### 5.1 Application changes (integrator application)

The integrator application (Ruby on Rails) must be containerized:

| Requirement | Details |
|---|---|
| **Dockerfile** | Multi-stage build: install Ruby, gems, copy app code |
| **Entrypoint script** | Differentiate between `web` (Puma) and `worker` (Sidekiq) process at container startup |
| **Health check endpoint** | Rails app must expose `/health` or similar (used by ECS health check) |
| **ECR repository** | One ECR repo per integrator (or one shared with different tags) |
| **Signal handling** | Rails/Puma and Sidekiq must handle SIGTERM gracefully for ECS task draining |
| **No local filesystem state** | No files written to disk that need to persist (already likely true for Rails apps) |

**Source:** Pattern observed in `app-atento-001/compute.tf` — all app services use the same image
with different commands/entrypoints.

#### 5.2 Environment variables and secrets

Current state: Ansible manages env vars on EC2. This must move to:
- **AWS Systems Manager Parameter Store** (SSM) — for secrets (DB passwords, API keys)
- **ECS task definition environment variables** — for non-sensitive config
- The CI/CD pipeline injects actual env vars at deploy time (pattern from `ecs_service/main.tf`:
  `ignore_changes = [container_definitions]`)

This is a significant operational change: all current env vars on each EC2 must be catalogued
and migrated to SSM or task definition environment variables.

#### 5.3 Terraform changes required

**For ECS Fargate** (preferred option), per integrator stack:

| Resource | Description |
|---|---|
| `aws_ecs_cluster` | One cluster per integrator (via `ecs_cluster` module, with `create_asg = false`) |
| `aws_ecs_service` (Fargate) | One per process type (web, worker-X, runner) — `launch_type = FARGATE` |
| `aws_ecs_task_definition` (Fargate) | One per service — `requires_compatibilities = ["FARGATE"]`, `network_mode = "awsvpc"` |
| `aws_ecr_repository` | One per integrator (via `ecr` module, already exists in integrator stacks) |
| `aws_iam_role` (execution + task) | ECS task execution role — `ecsTaskExecutionRole` already exists globally |
| **Internal ALB** | Only for web service — internal-facing (client connects via VPN) |

**Module changes needed**:
- `modules/ecs_service`: currently hard-coded for EC2 launch type (`requires_compatibilities = ["EC2"]`,
  `network_mode = "bridge"`). Must support Fargate mode (`FARGATE`, `awsvpc`). Best done as a new
  variable/mode in the existing module to avoid duplication.
- `modules/integrator/app.tf`: EC2 instance resources replaced by the ECS services above.
  The rest of the module (VPC, VPN, MongoDB, Redis, IAM user) remains unchanged.

**No `ecs_capacity` module needed** — Fargate has no capacity providers or EC2 instances to manage.

Existing networking (VPC, subnets, security groups, VPN, Redis, MongoDB) **remains unchanged**.

#### 5.4 Deploy pipeline changes

| Before | After |
|---|---|
| Capistrano via SSH | GitHub Actions pushing Docker image to ECR + updating ECS task definition |
| Manual Ruby/OS updates | New ECS-optimized AMI rolled via ASG instance refresh |
| Manual restart of Puma/Sidekiq | ECS service rolling deployment or CodeDeploy blue/green |

The `iam_deploy` module already exists and supports ECS deployments (seen in app stacks). A
similar IAM user + policy needs to be created per integrator for the CI/CD pipeline.

#### 5.5 Networking: internal ALB for web service

The integrators' web process likely receives HTTP traffic only from the client's network via
VPN or from internal 4Shark services. An internal ALB (not public) would handle routing
to web containers. The `modules/internal_alb` module exists and can be reused.

---

### 6. Migration Complexity Assessment

#### 6.1 Effort estimate

| Phase | Effort | Description |
|---|---|---|
| Dockerize the integrator app | **Medium** (1–2 weeks) | Dockerfile, entrypoint, health check, signal handling |
| Migrate env vars to SSM | **High** (1–2 weeks) | Catalogue all env vars per integrator, create SSM parameters |
| Build CI/CD pipeline (GitHub Actions) | **Medium** (1 week) | ECR push + ECS deploy, reuse pattern from app stacks |
| Terraform: new ECS module + per-integrator stacks | **Medium** (1–2 weeks) | New `integrator_ecs` module modeled on existing pattern |
| Migration + cutover per integrator | **Medium per client** (0.5–1 day each) | 6 integrators × 1 day = ~1 week |
| **Total estimated effort** | **6–8 weeks** | For a single engineer, with testing |

#### 6.2 Risk areas

| Risk | Severity | Notes |
|---|---|---|
| Unknown env vars on EC2 instances | **High** | Current EC2 env vars are managed by Ansible; inventory may be incomplete |
| Atento BR multi-tenant complexity | **Medium** | 5 services, queues must be correctly mapped |
| Sidekiq queue configuration per tenant | **Medium** | Each Sidekiq service must be started with the correct `--queue` flags |
| VPN connectivity | **Low** | VPN is at VPC level — unaffected by EC2→ECS migration |
| MongoDB connectivity | **Low** | MongoDB stays on EC2; containers connect via private IP/hostname |
| Redis connectivity | **Low** | ElastiCache stays unchanged |
| Staging environments (aster-maquinas, commcenter) | **Medium** | Staging EC2 servers need separate ECS services or a decision to decommission them |
| Capistrano-specific deploy hooks | **Medium** | Any `after deploy` hooks in the Capistrano config must be reimplemented (DB migrations, etc.) |

#### 6.3 Dependencies on other stacks

- **`dns` stack**: Internal Route53 zone is already shared — ECS services would register internal
  DNS names the same way EC2 does (or via ALB DNS name). No structural dependency change.
- **`networking` stack**: VPCs and subnets are managed by a separate networking stack per integrator.
  No changes needed there.
- **`identity` stack**: IAM management is separate. The ECS task execution role (`ecsTaskExecutionRole`)
  already exists (used in app stacks). Integrators can reuse it.

---

### 7. Advantages and Disadvantages

#### 7.1 Three-way comparison

| Dimension | EC2 (current) | ECS EC2 launch type | ECS Fargate |
|---|---|---|---|
| **Monthly cost** | $346.86 | $289.05 (-17%) | $303.67 (-12%) |
| **OS updates** | Manual via SSH | AMI update + ASG instance refresh | None — AWS managed |
| **Ruby updates** | Manual via Ansible | New Docker image | New Docker image |
| **Deploy mechanism** | Capistrano (fragile) | GitHub Actions + ECR + ECS rolling | GitHub Actions + ECR + ECS rolling |
| **EC2 instances to manage** | 11 | 15 (one per service) | Zero |
| **Scaling** | Manual | Auto (ASG per service) | Auto (Fargate native) |
| **Shell access** | SSH key required | `ecs exec` | `ecs exec` |
| **Rollback** | Manual | ECS circuit breaker | ECS circuit breaker |
| **Logs** | SSH + tail | CloudWatch | CloudWatch |
| **Consistent with app stacks** | — | Yes (identical pattern) | New pattern for this org |
| **Terraform boilerplate per integrator** | Low | High (cluster + capacity + service + ASG) | Medium (cluster + service) |

#### 7.2 Advantages shared by both ECS options (vs current EC2)

| Advantage | Impact |
|---|---|
| **No more manual Ruby updates** | Ruby version is baked into the Docker image — update by rebuilding and redeploying |
| **Reliable deploys** | GitHub Actions + ECR + ECS rolling deploy replaces fragile Capistrano over SSH |
| **Independent process scaling** | Web and Sidekiq scale independently; current EC2 couples both |
| **Shell access without SSH keys** | `ecs exec` replaces SSH — no key rotation, no bastion |
| **Deployment rollback** | ECS circuit breaker provides automatic rollback on health check failure |
| **Centralized logging** | CloudWatch log groups per service |

#### 7.3 ECS EC2 launch type — specific pros and cons

| | Detail |
|---|---|
| **+ Proven pattern in org** | app-atento-001 and app-shared-001 already use this exact setup |
| **+ Reuses all existing Terraform modules** | `ecs_cluster`, `ecs_capacity`, `ecs_service`, `iam_deploy` — no new patterns needed |
| **+ Proven pattern in production** | app-atento-001 and app-shared-001 already run this way |
| **− Still manages EC2 instances** | 15 instances — AMI updates, Launch Templates, ASG configs, capacity provider per service |
| **− OS patching not fully eliminated** | Need to refresh ECS-optimized AMI periodically via instance refresh |
| **− More Terraform resources** | One capacity provider + ASG per service = significant boilerplate per integrator |

#### 7.4 ECS Fargate — specific pros and cons

| | Detail |
|---|---|
| **+ Zero EC2 management** | No AMIs, no ASGs, no Launch Templates — AWS provisions compute automatically |
| **+ Simplest operational model** | Manage only task definitions and desired counts — nothing else |
| **+ Less Terraform boilerplate** | No `ecs_capacity` module needed — fewer resources per integrator |
| **+ OS patching fully eliminated** | No EC2 layer at all |
| **− Slightly more expensive** | $303.67/month — $14.62 more than ECS EC2, but still -12% vs current EC2 |
| **− New pattern for this org** | App stacks use ECS EC2 — integrators would be first Fargate workloads |
| **− `ecs_service` module needs changes** | Current module uses `requires_compatibilities = ["EC2"]` + bridge network mode; needs Fargate mode + `awsvpc` |

#### 7.5 Disadvantages shared by all ECS migrations (vs current EC2)

| Disadvantage | Impact |
|---|---|
| **Requires containerization** | The integrator app must have a working Dockerfile — prerequisite before any infra work |
| **Env var migration** | All Ansible-managed env vars must be catalogued and moved to SSM — highest risk item |
| **Initial effort** | 6–8 weeks total engineering work |
| **Multi-tenant complexity (atento-br)** | 5 ECS services regardless of launch type — most complex integrator |
| **Staging decision** | aster-maquinas and commcenter have staging EC2 instances — migrate or decommission |
| **Capistrano deploy hooks** | Any `after deploy` hooks must be reimplemented (DB migrations, etc.) |

---

## Conclusions

### Key Findings

1. **ECS migration is technically viable.** The infrastructure pattern is already proven by the
   app stacks. All required Terraform modules exist. No new AWS services need to be introduced.

2. **ECS Fargate is the preferred choice** for integrators. Although ECS EC2 launch type saves
   an additional $14.62/month, Fargate eliminates all EC2 compute management (no AMI updates,
   no capacity providers, no Launch Templates). Given that eliminating operational toil is the
   primary motivation for this migration, Fargate's operational simplicity justifies the marginal
   cost difference. Note: the existing app stacks use ECS EC2 — integrators would be the first
   stacks on Fargate, establishing a new pattern.

3. **The migration is cost-neutral** (with full staging). Final numbers:
   - ECS Fargate: $348.66/month (+$1.80 vs current $346.86) — essentially the same cost
   - ECS EC2: $346.86/month — identical cost, zero savings, added EC2 management overhead
   - Optional: staging tasks at minimum size → Fargate drops to ~$326/month (-6%)
   The migration pays for itself not through cost savings but through elimination of operational toil.

4. **The biggest migration risk is not infrastructure — it is env vars.** The current state of
   Ansible-managed environment variables on each EC2 instance is opaque from Terraform. This must
   be fully inventoried before migration begins.

5. **Atento BR requires special handling.** With 5 ECS services (web + sidekiq-main + sidekiq-mx +
   sidekiq-colombo + sidekiq-chile), it is the most complex integrator and should be migrated last.

6. **Almaviva and Maqnelson** each have 2 app servers. Before migration, the team needs to confirm
   whether these are for redundancy (`desired_count = 2`) or separate tenants/queues (separate services).

7. **Staging environments** (aster-maquinas, commcenter) must be addressed: either migrate them
   as additional ECS services or decommission them.

8. **The integrator application must be containerized first.** All other infrastructure work
   depends on having a working Docker image with a correct entrypoint, health check, and
   graceful signal handling.

---

## Next Steps

### Questions status — all answered

1. **Does the integrator application already have a Dockerfile?**
   **✅ ANSWERED** — No Dockerfile exists. One must be created as the first deliverable.
   CI/CD pattern defined: GitHub Actions build workflow triggers on every merge to `master`,
   builds and pushes the Docker image for **all integrators** to ECR. A separate deploy workflow
   receives an integrator name as parameter (e.g., `almaviva`) and deploys that integrator to ECS.
   No per-integrator build scripts — one build script, one deploy script with a parameter.

2. **Almaviva and Maqnelson: redundancy or separate tenants?**
   **✅ ANSWERED** — Neither separate tenants nor redundancy. Both run the **same queue with 10
   threads per server**; the second server was added purely for more throughput. Solution: one
   `worker` ECS service with `desired_count = 2` (2 tasks, same queue, more parallelism).

3. **Staging environments (aster-maquinas, commcenter): migrate or decommission?**
   **✅ ANSWERED** — Must be migrated. These clients are actively developing integrations and use
   staging in parallel with production (same VPN, same MongoDB cluster, separate database).
   Each of these integrators needs 4 ECS services: web-prod, worker-prod, web-staging, worker-staging.

4. **Atento BR: service structure per country.**
   **✅ ANSWERED** — Each country gets `web` + `worker` services with separate env vars, all sharing
   one VPN and one VPC.

5. **Env var inventory.**
   **✅ ANSWERED** — Env vars are not documented anywhere. They will be migrated to GitHub Actions
   secrets (same model as the app). The deploy script will read secrets from GH Actions and inject
   them into the ECS task definition at deploy time.

### Recommended next action

All questions are answered. This spike is sufficient to proceed to implementation planning.
Use `@agent-planner` to create a PLAN.md that:

- Uses ECS Fargate (recommended — see cost analysis)
- Phases the migration integrator by integrator (start with the simplest: redebrasil)
- Plans Dockerfile creation and CI/CD pipeline as Phase 1 (prerequisite for all migrations)
- Plans env var catalogue per integrator as part of Phase 1
- Deploy script: one script, receives integrator name as parameter, deploys to ECS

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
