# SPIKE — Migrate app-atento-br (→ app-outbound-atento-br) from EC2 to ECS

**Conducted by:** Paulo Ribeiro
**Date:** 2026-04-15
**Status:** Research complete — pending decisions
**Deadline:** 2026-05-14 (~1 month)

---

## Goal

The `app-atento-br` stack is a dedicated Rails replica of the main app, deployed exclusively to process egress Sidekiq jobs that reach Atento's on-prem ForCheck payroll system via VPN. It runs today on **5 EC2 instances provisioned with Ansible + Capistrano** — the same legacy pattern we are phasing out on the integrators.

This spike investigates migration to ECS, answering:

1. **Feasibility** — is the pattern used by the integrator EC2→ECS migration directly applicable here?
2. **Region constraint** — is the VPC actually in Brazil (required by the VPN endpoint)?
3. **Reuse the existing main app ECS cluster?** — or is a dedicated cluster mandatory?
4. **Version parity** — how do we guarantee this stack runs the same app version as the main atento deployment?
5. **Effort and risks** — what is the scope and what can go wrong, given the 1-month deadline?
6. **Naming cleanup** — the current `out-` naming convention (`out-atento-br` VPC, `4client-out-*` tags, hardcode inside `modules/app`) leaks implementation detail ("egress direction") into the public infrastructure vocabulary. The migration is the right moment to retire it.

---

## Method

- Read the completed SPIKE/PLAN for `integrators-ec2-to-ecs` (`~/.claude/plans/active/terraform/integrators-ec2-to-ecs/`) to reuse its findings.
- Inspected the `app-atento-br` stack: `main.tf`, `providers.tf`, uses `modules/app`.
- Inspected the networking VPC definition `networking/vpc_out_atento_br.tf`.
- Inspected the `app-atento-001` ECS stack (`compute.tf`, `providers.tf`) as the reference pattern.
- Cross-checked against the `app-atento-br-pattern` and `integrator-ecs-migration-context` memory notes.

---

## Evidence

### 1. Current infrastructure — app-atento-br

- **File:** `app-atento-br/main.tf` — uses `modules/app` with `client_name = "atento-br"`.
- **Instances:** 5 × t3.small named `app001` … `app005`, all in subnet `prv-a`.
- **AMI:** Ubuntu `ami-0bd91caaa9bc42cf3` (same as integrators/legacy apps).
- **VPN:** `enable_vpn = true`, customer gateway `177.22.252.45`, on-prem CIDRs `10.155.0.152/32`, `10.189.0.162/32` — the ForCheck endpoints.
- **Provisioning:** Ansible + Capistrano (same as legacy integrators — no Dockerfile, SSH-based deploys).
- **Workload:** per the `app-atento-br-pattern` memory, this deployment runs **only Sidekiq workers** processing egress jobs for atento-br. No web process, no other clients.

### 2. Region confirmation — VPN must stay in Brazil ✅

- `app-atento-br/providers.tf:2` → `region = "sa-east-1"` (São Paulo).
- `networking/vpc_out_atento_br.tf` → VPC CIDR `10.12.0.0/26`, subnets in AZs `sa-east-1a` / `sa-east-1c`.
- The customer gateway IP (`177.22.252.45`) is reachable from Brazilian IPSec endpoints with minimal latency; keeping the workload in `sa-east-1` avoids adding a transatlantic hop to every ForCheck call.

**Conclusion:** the workload must stay in `sa-east-1`. Same as today.

### 3. Reuse the app-atento-001 cluster? ❌ Not viable

- `app-atento-001/providers.tf:2` → `region = "us-east-1"`.
- The existing ECS cluster (`app-atento-001-cluster`) lives in us-east-1, inside a different VPC with no path to the `out-atento-br` VPC nor to the on-prem ForCheck network.
- ECS tasks must run in subnets attached to the VPN (via TGW + VPN attachment in `sa-east-1`). Running them from us-east-1 would require cross-region TGW peering + redesigning the VPN attachment — far more complex than a dedicated sa-east-1 cluster.

**Conclusion:** a **new dedicated ECS cluster in sa-east-1**, attached to the `out-atento-br` VPC, is the right move. This matches the integrator migration pattern (one cluster per stack).

### 4. Version parity with app-atento-001 ✅ Solvable

`app-atento-001/compute.tf:113` pulls the image `405749097490.dkr.ecr.us-east-1.amazonaws.com/atento-001-app:latest`. That ECR repo is populated by the existing `app` repo GitHub Actions build pipeline — same image, same tag, every merge.

Two options to ensure parity:

- **Option A — Cross-region pull (simple):** `app-atento-br` tasks pull the same image from us-east-1 ECR. Works out of the box (ECS supports cross-region pulls). Pay a one-time cross-region data transfer per image pull (~15 MB image × a few pulls/day = negligible, cents/month).
- **Option B — ECR Pull-Through Cache or Replication (robust):** enable ECR replication from us-east-1 → sa-east-1 for the `atento-001-app` repo. Tasks pull locally from `405749097490.dkr.ecr.sa-east-1.amazonaws.com/atento-001-app:latest`. Slightly lower latency on task start, no cross-region charges.

Either way, **parity is automatic** — both stacks reference the same image tag. No separate build pipeline, no version drift, no duplicate ECR push job.

### 5. What changes vs the integrator migration

The integrator spike already covers Fargate vs ECS EC2, task sizing, CI/CD pattern, env var strategy, module changes, etc. The differences for `app-atento-br` are narrower:

| Aspect | Integrators | app-atento-br |
|---|---|---|
| Processes | web (Puma) + worker (Sidekiq) | worker (Sidekiq) only |
| Image source | new ECR per integrator, new GHA build | reuse existing `atento-001-app` image |
| CI/CD build workflow | must be created in integrator repo | **none needed** — reuse `app` repo pipeline |
| ECR repositories | 6 new repos | **zero new repos** (reuse or replicate) |
| Env vars migration | catalogue Ansible vars, move to GH secrets | catalogue Ansible vars, move to GH secrets |
| ALB | internal ALB per integrator (web) | **no ALB needed** (worker-only) |
| ECS services | web + worker(s) per stack | worker(s) only |
| Task sizing | web 0.5/1 GB; worker 0.25/0.5 GB | worker only — sizing options analyzed in Section 6 (recommended: 3 × 0.5 vCPU / 1 GB, -30% cost) |

### 6. Cost analysis

**Current (EC2 + Ansible):**
- 5 × t3.small sa-east-1 = 5 × $19.27 = **$96.35/month**

**ECS Fargate — minimum size (0.25 vCPU, 0.5 GB per task):**
- 5 worker tasks × $11.25 = **$56.25/month** (-42%)
- Adequate only if each current EC2 is running a Sidekiq process with `SIDEKIQ_THREADS ≤ ~5` and low memory footprint.

**ECS Fargate — matched sizing (0.5 vCPU, 1 GB per task, same as integrator worker spec):**
- 5 worker tasks × $22.49 = **$112.45/month** (+17%)

**ECS Fargate — consolidated (fewer, larger tasks):**
- 2 × (1 vCPU, 2 GB) worker tasks = 2 × $44.98 = **$89.96/month** (-7%). Single-task failure halves capacity — thin redundancy.
- 3 × (0.5 vCPU, 1 GB) = **$67.47/month** (-30%). Likely the sweet spot if Sidekiq concurrency scales per task.

**Key observation:** today we pay for 5 t3.small VMs (2 vCPU, 2 GB each) = 10 vCPU, 10 GB total provisioned, almost certainly underused since Sidekiq is I/O-bound waiting on ForCheck API. ECS Fargate lets us right-size based on real concurrency. Starting smaller (e.g., 2–3 tasks at 0.5 vCPU / 1 GB) and scaling up if queue latency grows is the cheapest credible path.

### 7. Renaming `out-` out of the vocabulary

**Current footprint of `out-` in AWS console and Terraform state:**

| Source | Where | Rename cost |
|---|---|---|
| VPC Name tag | `networking/vpc_out_atento_br.tf` | Tag update, instant |
| Subnets, IGW, route tables, TGW attachment, peering — all Name tags | `networking/vpc_out_atento_br.tf`, `peering.tf`, `transit_gateway.tf`, `vpc_egress_sa_east_1.tf` | Tag updates, instant |
| Terraform resource addresses (all `*.out_atento_br*`) | same files | `moved` blocks, no resource recreation |
| SSM parameter paths `/networking/out-atento-br/*` (6 parameters) | `networking/ssm.tf:758–793` | SSM name is immutable → destroy + create. Zero runtime impact (read only during `terraform plan`). |
| Module hardcode `name_prefix = "4client-out-${var.client_name}"` | `modules/app/main.tf:2` | **This is the real leak.** Every EC2, VPN gateway, customer gateway, VPN connection, and SG in the stack inherits `4client-out-*` from the module itself, not from the stack. Fixed by replacing the `modules/app` invocation with the new `modules/app_outbound`, whose internal `name_prefix` is `4client-app-outbound-${var.client_name}`. |
| EC2 Name tags `4client-out-atento-br-app00N` | inherited from module | Go away with the migration (EC2s destroyed) |
| Route53 internal DNS records `4client-out-atento-br-app00N.*` | `dns/internal_dns_app.tf` | Go away with the migration (EC2s destroyed → records destroyed) |

**Net result after the migration is complete**: zero occurrences of `out-` in the AWS console, in SSM, or in Terraform state. All new ECS resources (cluster, services, task definitions, log groups) are named cleanly from day zero under the `app-outbound-atento-br` prefix.

**Module cleanup scope (part of the migration work):**
- Create `modules/app_outbound` — owns VPN, peering, routing, DNS association, ECS cluster scaffolding for the outbound app pattern. Internal `name_prefix` is `4client-app-outbound-${var.client_name}`.
- Replace the `modules/app` invocation in the stack with `modules/app_outbound`. Since only this stack uses `modules/app` with `enable_vpn=true`, no other stack is affected.
- Delete the EC2 path in `modules/app` once no stack consumes it. The remaining `modules/app` EC2 logic, if any stack still needs it, stays untouched; only the dead code goes.
- This module refactoring is explicit scope of this migration — not a "future cleanup". The goal is: migrate the stack correctly, rename everything, end with a clean reusable module so the next client (atento-mx, atento-co, etc.) can adopt the pattern trivially (`app-outbound-atento-mx` = 1 new stack directory + 1 module invocation).

### 8. Terraform changes required

- **Rename stack directory:** `app-atento-br/` → `app-outbound-atento-br/`. State backend key (`app-atento-br/terraform.tfstate` in `providers.tf:18`) updated to `app-outbound-atento-br/terraform.tfstate` via S3 copy + reconfigure.
- **New files in `app-outbound-atento-br/`:** `compute.tf` (ECS cluster + services + task definitions), `ssm.tf` (secrets), `iam.tf` (task/execution roles if not reusing the global `ecsTaskExecutionRole`).
- **`main.tf`:** replace the `modules/app` call with `modules/app_outbound` (see Section 7). No fallback path — the new module is created as part of this work.
- **New `modules/app_outbound`:** created from scratch, owning VPN, peering, routing, DNS association, and ECS cluster scaffolding. Internal `name_prefix = "4client-app-outbound-${var.client_name}"`.
- **`modules/app`:** EC2 path stays untouched for any other stack still using it; the `enable_vpn` / VPN / peering / routing blocks become dead code **for this stack** but not for the module. If no other stack uses the VPN path of `modules/app`, remove it after this migration lands.
- **`modules/ecs_service`:** same module change required by the integrator spike (add Fargate launch type support). If the integrator migration lands first, this is **already done** — we benefit for free.
- **`modules/ecs_cluster` / `ecs_capacity`:** integrator spike chose Fargate → no capacity provider needed. Same decision applies here.
- **SSM parameters:** secrets catalogued and created, same pattern as `app-atento-001/ssm.tf`.
- **Networking stack:** VPC/subnets/route tables/TGW/peering resource addresses renamed from `*.out_atento_br*` to `*.app_outbound_atento_br*` via `moved` blocks; Name tags updated; SSM paths `/networking/out-atento-br/*` destroyed and recreated as `/networking/app-outbound-atento-br/*`.

### 9. Deploy pipeline

- **No new build workflow.** The `app` repo already publishes `atento-001-app:latest` on every merge to master (pattern confirmed by `app-atento-001/compute.tf:113`). The ECR repo name `atento-001-app` is the existing image identifier — it is not renamed as part of this work, only consumed.
- **Deploy workflow:** needs a new target. The integrator migration is creating a parameterized deploy script (`deploy <integrator>` → updates that ECS service). The cleanest path is to extend the `app` repo's deploy script to also target the `app-outbound-atento-br` ECS services after deploying `app-atento-001`. **This is the mechanism that guarantees version parity operationally.**
- **Alternative (acceptable, clearly documented gap):** separate `deploy-app-outbound-atento-br` workflow, manually triggered after `app-atento-001` deploys. Simpler to ship in 1 month, costs us manual coordination.

### 10. Risks

| Risk | Severity | Notes |
|---|---|---|
| Env vars on 5 EC2s are Ansible-managed and undocumented | **High** | Must be SSH'd into and catalogued before cutover. Same risk as integrators. |
| Sidekiq queue names / concurrency configuration | **Medium** | Must inspect the running Sidekiq config on the EC2s to replicate `--queue` flags and `SIDEKIQ_THREADS`. |
| Version drift if deploy pipeline is not wired to both stacks | **Medium** | Mitigate by extending the `app` repo deploy to target both ECS clusters. |
| VPN connectivity from ECS tasks to ForCheck | **Low** | VPN is at VPC level — tasks in the private subnet reach on-prem the same way EC2s do today. |
| `modules/ecs_service` Fargate support not yet merged | **Medium** | Depends on integrator migration timing. Cheapest mitigation: sequence this migration **after** at least one integrator lands on Fargate. |
| Cross-region ECR pull latency on cold starts | **Low** | Negligible in practice; replication is a tactical hedge if Fargate task starts become a problem. |
| Deadline: 2026-05-14 | **Medium** | ~1 month. Feasible if we piggyback on the integrator work; tight if we must do module changes from scratch. |

### 11. Effort estimate

| Phase | Effort | Notes |
|---|---|---|
| Env var + Sidekiq config inventory on 5 EC2s | 1–2 days | SSH each box, capture running config, document queues and thread counts |
| VPC/networking rename (SSM, tags, `moved` blocks) | 1 day | Pure Terraform bookkeeping, no runtime impact |
| Create `modules/app_outbound` (VPN, peering, routing, DNS, ECS scaffolding) and replace the `modules/app` invocation in this stack | 2–3 days | Fixes the `out-` hardcode at the source; new module uses `4client-app-outbound-${var.client_name}` prefix |
| SSM parameters + Terraform secrets | 1 day | Same pattern as main atento stack |
| New `compute.tf` (cluster + worker services + task defs) | 2–3 days | Only workers — simpler than the main app stack |
| Wire deploy pipeline to target the new cluster | 1–2 days | Extend `app` repo deploy workflow |
| ECR cross-region pull vs replication decision + config | 0.5 day | Cheapest wins — cross-region is fine |
| Parallel run + cutover (ECS drains Sidekiq from EC2) | 1 day | Scale ECS up, stop Sidekiq on EC2s, decommission EC2s after observation window |
| Decommission EC2 resources and DNS records | 0.5 day | `terraform destroy` of just the EC2 block |
| Buffer for unknowns | 2–3 days | |
| **Total** | **~2.5–3 weeks** | Assumes Fargate support in `modules/ecs_service` already exists from the integrator migration. Add +1 week if not. Module refactor is the main addition vs the previous estimate. |

### 12. Scale-to-zero on-demand pattern (Lambda-based queue autoscaler)

The outbound stack runs on **Fargate with scale-to-zero** between executions, coordinated by **dedicated autoscaling Lambdas watching a dedicated Sidekiq queue in the shared Redis**. This reuses the exact pattern already in production for `app-atento-001` (the Redis lock key `ecs_scaling:lock:${CLUSTER_NAME}` and the "autoscaling lambdas monitor services and adjust capacity" references in `deploy-atento-001.yaml` attest to this pattern being live).

The market name for this pattern is **queue-depth-based event-driven autoscaling** (KEDA-style); the AWS-native implementation in this codebase is a Lambda watching Sidekiq queue depth + busy workers, acting on the ECS service.

**Lifecycle:**

1. **Trigger:** user clicks "Integrate" in the UI. The app enqueues the work job in the **dedicated outbound Sidekiq queue** (same Redis used by the main app — queue is new/dedicated, Redis is shared). Nothing else happens on the trigger path. No ECS call, no shutdown-check scheduling, no state machine.

2. **Scale-up (Lambda):** the dedicated scale-up Lambda polls the outbound queue on a schedule. When `depth > 0` and ECS `desiredCount == 0`, it calls `UpdateService` to scale 0 → N (target: 5, matching today's EC2 count).

3. **Processing:** tasks boot, pick up the queue, process normally. No changes to Sidekiq configuration vs today's EC2 behavior. All 5 tasks share a single service (queues are uniform — engineer confirmed).

4. **Scale-down (Lambda):** the dedicated scale-down Lambda polls the queue + Sidekiq API. When `queue == 0` AND `busy workers == 0` for the configured idle window, it:
   - Sends TSTP to all tasks (Sidekiq quiet mode). Same pattern as `deploy-atento-001.yaml`.
   - Waits 30s to let any in-flight job complete.
   - Calls `UpdateService` to scale N → 0.

5. **Concurrent triggers:** handled naturally by queue depth — no special logic. A new trigger while the cluster is up just enqueues; the Lambda keeps the cluster up because depth > 0. A new trigger during drain: the scale-down Lambda re-checks depth before the final scale-to-zero; if the queue filled again, it aborts the drain. (Exact semantics inherit from the existing `app-atento-001` Lambda implementation.)

**Why this supersedes the earlier self-scheduling design (trigger enqueues 8h shutdown-check):** the Lambda pattern already exists, is battle-tested on `app-atento-001`, and removes custom orchestration from the Rails layer. The trigger becomes a one-liner (enqueue), and the coordination logic lives in the Lambda where it belongs.

**Cost implication:** assuming ~10h of compute per month (1 execution, 8h window + buffer), 5 tasks at 2 vCPU / 2 GB in sa-east-1:
- 5 × (2 vCPU × $0.04048 + 2 GB × $0.004445) = $0.449/hr
- $0.449 × 10h = **~$4.50/month** vs $96/month today (~95% reduction).
- Lambda execution cost: negligible (a few invocations per minute × milliseconds of runtime).

If the workload ever grows to continuous operation, Fargate stops winning on cost — we'd revisit launch type at that point. The decision stands as long as the monthly-trigger profile holds.

**Why this supersedes the earlier Fargate sizing analysis (Section 6):** Section 6 compared sizing options assuming 24/7 Fargate. Scale-to-zero changes the math fundamentally: sizing is optimized for throughput during the window, not for continuous cost. 5 tasks at matched `app-atento-001` sizing is the natural choice — replicates today's capacity, no guesswork.

---

## Conclusions

1. **Migration is viable and scope-smaller than the integrator migration.** No ALB, no new ECR, no new build pipeline, fewer services.
2. **VPC must stay in sa-east-1** (confirmed). Cannot reuse the main atento ECS cluster (us-east-1, wrong VPC).
3. **Preferred design:** new ECS Fargate cluster in this stack, dedicated to worker tasks, pulling the **same app image** used by the main atento deployment. Same image = guaranteed version parity; the only gap is the deploy trigger, which we close by extending the `app` repo deploy workflow to target both clusters.
4. **Version parity is achievable automatically** because the main atento stack already tags its image on every merge. The real question is whether the **deploy** (ECS service update) is also synchronized.
5. **Start Fargate-minimal** (2–3 tasks at 0.5 vCPU / 1 GB). Sidekiq on Atento is I/O-bound; provisioned 5 × t3.small is almost certainly overprovisioned. Right-size by observing queue latency after cutover.
6. **The `out-` naming is fixable end-to-end** — nothing in AWS physically blocks the rename. The module hardcode in `modules/app/main.tf:2` is the real source of the leak and must be fixed inside the module, not worked around.
7. **Module refactor is part of this migration's scope**, not a follow-up. Since only this stack uses `modules/app` with `enable_vpn=true`, this is the right moment to: fix the hardcode, extract the non-EC2 pieces into a dedicated reusable module, delete the EC2 path once unused. Next client that needs this pattern (atento-mx, atento-co, etc.) inherits a clean module.
8. **Critical path:** env var inventory + Sidekiq queue mapping. Everything else is cookie-cutter Terraform once the integrator migration has paved the way.
9. **Deadline is realistic (~2.5–3 weeks of work for 1 engineer)** if the `modules/ecs_service` Fargate changes are already in. If not, sequence this after at least one integrator has landed on Fargate.

---

## Decisions

1. **Stack naming — DECIDED: `app-outbound-<client>`.** Convention: `app-` prefix keeps the "this is a replica of the main app" signal; `outbound-` describes the business concept (outbound integration — sending data out to a client's system); client suffix identifies the specific deployment. Scales to future clients (`app-outbound-atento-mx`, `app-outbound-atento-co`) without renaming. Rejected alternatives and their reasoning are preserved in the Evidence section.
2. **Module name — DECIDED: `modules/app_outbound`.** Aligns with the stack naming — a stack named `app-outbound-atento-br` is "an instance of `app_outbound` for the atento-br client". The module owns the non-EC2 pieces (VPN, peering, routing, DNS association) plus the ECS cluster/service scaffolding that all `app-outbound-*` stacks will share.
3. **Launch type — DECIDED: Fargate with scale-to-zero.** Workload triggers ~once/month with an 8h window. Running EC2 24/7 wastes ~95% of compute cost. Operational paridade with `app-atento-001` (EC2 + capacity providers) is sacrificed deliberately — the cost and simplicity gain is larger than the ergonomic cost of a second pattern. See Section 12 for the full lifecycle.
4. **Image source — DECIDED: dual-push from `build-image.yaml`.** Create a new ECR repo `atento-001-app` in sa-east-1. The build workflow logs into both regions and pushes the same image to both. Deploy in sa-east-1 reads from the local sa-east-1 ECR. No replication rule, no cross-region pull.
5. **Deploy workflow — DECIDED: extend `deploy-atento-001.yaml` (not a new workflow).** The outbound cluster is part of the `atento-001` environment (same tenant, different region) — it is not a new environment. The repo's pattern is "1 workflow per environment", so extending the existing workflow with new jobs targeting sa-east-1 and the outbound cluster, after the main deploy, is consistent with that pattern.
6. **Task sizing — DECIDED: 5 tasks at 2 vCPU / 2 GB (2048/2048).** Matches `app-atento-001` worker task sizing. Single worker service (engineer confirmed queues are uniform — no per-queue isolation needed). Replicates today's 5-EC2 footprint without guessing. Revisit only if queue latency is observed after cutover.
7. **Operational pattern — DECIDED: queue-depth-based event-driven autoscaling via dedicated Lambdas (KEDA-style).** Two Lambdas (scale-up and scale-down) watch a **dedicated Sidekiq queue** in the shared Redis, plus the Sidekiq API for busy workers. Trigger becomes a one-liner: enqueue in the dedicated queue. No scale-up call, no shutdown-check scheduling, no state machine in the Rails layer. Reuses the exact pattern already in production for `app-atento-001`. Full lifecycle in Section 12.
8. **IAM — DECIDED: reuse `app-atento-001` worker task role as the outbound task role; `ecs:UpdateService` lives on the autoscaling Lambdas' execution role, not on task roles.** Since scaling is done by Lambdas (not Sidekiq), task roles don't need `ecs:UpdateService`. The outbound task definition references the same task role ARN as the atento-001 worker — same app, same secrets, same log-group permissions pattern; a single addition on region-scoped resources (sa-east-1 log group ARN) covers the delta. Zero new IAM roles for tasks. The new autoscaling Lambdas get their own execution role with `ecs:UpdateService` scoped to the outbound service ARN, following the existing atento-001 autoscaling Lambda pattern.

Concrete naming after the migration:

| Resource | Name |
|---|---|
| Terraform stack directory | `app-outbound-atento-br/` |
| Terraform module | `modules/app_outbound` |
| VPC Name tag | `4client-app-outbound-atento-br` |
| SSM parameter paths | `/networking/app-outbound-atento-br/*` |
| ECS cluster | `app-outbound-atento-br-cluster` |
| ECS worker services | `app-outbound-atento-br-worker-*-service` |
| Task families | `app-outbound-atento-br-worker-*` |
| CloudWatch log groups | `/ecs/app-outbound-atento-br-*` |
| VPN gateway / customer gateway / connection Name tags | `4client-app-outbound-atento-br` |

The main atento stack (`app-atento-001`) is **not renamed** as part of this work — it carries a separate naming problem (it is a multi-client shard, not atento-specific) that is out of scope for this migration.

## Open Questions (for planning)

All 5 original spike questions are **RESOLVED** by Decisions #3–#7 above, plus the engineer's confirmation on decommission strategy (no parallel window; cutover and destroy within the monthly gap).

Implementation questions surfaced during the refinement — all resolved by Decisions #7 (Lambda-based autoscaling) and #8 (IAM reuse):

1. **Trigger ownership — RESOLVED:** trigger is a one-liner — enqueue the work job in the dedicated outbound Sidekiq queue. No intermediate Sidekiq-on-atento-001 job, no ECS calls from the app. The scale-up Lambda reacts to queue depth.
2. **Shutdown-check enqueueing — RESOLVED (superseded):** no application-layer shutdown-check. The scale-down Lambda owns the drain decision based on queue depth + Sidekiq busy workers. Removed from scope.
3. **Recheck interval — RESOLVED:** Lambda polling interval, inheriting the existing `app-atento-001` autoscaling Lambda configuration.
4. **Safety cap — RESOLVED:** not needed. Lambda logic trusts queue depth + busy workers, same as the live pattern on `app-atento-001`.
5. **Permissions model — RESOLVED:** `ecs:UpdateService` lives on the **autoscaling Lambdas' execution role**, scoped to the outbound service ARN. Task roles do not need it. The outbound task definition reuses the `app-atento-001` worker task role directly; the only region-scoped delta (sa-east-1 log group) is added to the existing policy. See Decision #8.
6. **Concurrent triggers — RESOLVED:** Pattern 1 (queue-depth autoscaler) handles this naturally. Multiple triggers just enqueue; the scale-up Lambda keeps the cluster up while `depth > 0`. A trigger during drain is handled by the scale-down Lambda's re-check before final scale-to-zero. Exact semantics inherit from the existing `app-atento-001` autoscaling Lambda — to be confirmed by reading its code during planning.
7. **Observability — RESOLVED:** same stack as the main `app` today, same environment variables (Rollbar, whatever logging/metrics `app-atento-001` uses). Lambdas emit CloudWatch metrics following the existing pattern.

**No open questions remaining. Ready for `@agent-planner`.**

**Note for planning:** the existing `app-atento-001` autoscaling Lambda code (in the `lambda/` repo) is the reference implementation. Planning should start by reading that code to understand: polling interval, queue/busy-worker thresholds, race semantics during drain, Terraform wiring, and IAM policy shape — then replicate/parameterize for the outbound service.

---

## Next Steps

- Decide on the 5 open questions above.
- If green-lit, promote to `@agent-planner` to produce a PLAN.md with phased migration (inventory → Terraform → cutover → decommission).
- Coordinate timing with the integrator EC2→ECS migration to maximize module reuse.

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making.
