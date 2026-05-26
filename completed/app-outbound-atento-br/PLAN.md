# PLAN — app-outbound-atento-br Migration (EC2 → ECS Fargate)

> Reference: SPIKE.md at `~/.claude/plans/active/spike/app-atento-br-ec2-to-ecs/SPIKE.md`
> All decisions (#1–#8) are closed. This document covers sequencing and execution only.

---

## Status (as of 2026-05-05)

| Phase | Status | PR / Commit | Notes |
|---|---|---|---|
| 0 — Source-of-truth inventory | ✅ | — | Done via code reads + AWS API; no SSH |
| 1 — Lambda ASG→Fargate delta | ✅ | `PHASE-1-DELTA.md` | Interface documented |
| 2 — Networking rename | ✅ | terraform#349 | 6 SSMs added at new path (coexistence); old `/networking/out-atento-br/*` kept for Phase 2.5 |
| 3 — `modules/app_outbound` + stack rename | ✅ | terraform#349 + docs #350 | 5 legacy EC2s inline in stack (`ec2_legacy.tf`); `modules/app` deprecated, no consumers |
| 4 — Lambda `worker-payroll-autoscaling` | ✅ | lambda#47, release 0.9.0, S3 artifact `worker-payroll-autoscaling/0.9.0_37780e1.zip` | Originally uploaded to `s3://4shark-lambda-artifacts/`; replicated to both regional buckets in 7c |
| 5a — ECR sa-east-1 | ✅ | terraform#351 | Repo `atento-001-app` in sa-east-1 |
| 5b — `build-image.yaml` dual-push | ✅ | app#4953 | Refactored to iterate `ECR_REGISTRIES` list; atento-001 overrides with 2 regions |
| 5b-IAM — extend deploy IAM to sa-east-1 ECR | ✅ | terraform#352 | `ecr_repository_arns` extended via `flatten` over region list |
| 6 — HireFire dyno `worker_payroll_tiger_shark` | ✅ | app#4952 | Dyno added in `config/initializers/hire_fire.rb` |
| 7a — `modules/atento_001_task_config` + refactor `app-atento-001` | ✅ | terraform#354 (commit `ebc8d32`) | Pure-data module exposing `env_vars` + `secrets`; both stacks consume it |
| 7b — Refactor `app-atento-001/compute.tf` | ✅ | terraform#354 | Applied — zero resource changes (verified) |
| 7c — Lambda artifact regional bucket migration | ✅ | terraform#354 + lambda#49 | 2 new buckets created + sync'd; `lambda/bin/publish_lambdas` dual-push; 5 stacks refactored. 3 applied (demo, shared, beta) — drift AMI + PEN_TEST resolved as side effects. 2 pending apply (atento-001, onboarding — deferred; behavior identical either way) |
| 7d — Wire `app-outbound-atento-br` compute stack | ✅ | terraform#354 | 16 resources applied. cpu/memory adjusted from 2048/2048 (invalid Fargate combo) to 1024/2048. Lambda env vars set via CLI. Scale-to-zero verified via CloudWatch logs |
| 7e — Delete legacy `4shark-lambda-artifacts` bucket | ✅ | AWS CLI ops (out-of-code) | 37 versions + 6 delete markers purged; bucket deleted. 404 on HEAD confirmed |
| 8 — Deploy workflow (sibling job + reusable) | ✅ | app#3618a4cbf, app#1283f01b8, app#47eb1ffd9, app#4988 | Reusable `deploy-payroll-worker.yaml`; sibling jobs `deploy-payroll` + `deploy-runner-payroll` in `deploy-atento-001.yaml`; cross-track rollback; cleanup-on-failure recovery. 5 consecutive successful deploys through 2026-04-30. Manual scale-up E2E validation 2026-05-05: task `87680bf4...` came up cleanly, registered in Sidekiq Web on `payroll_tiger_shark` queue |
| 2.5 — Cleanup deprecated SSMs + outputs | ✅ | terraform#395 | 6 deprecated SSMs at `/networking/out-atento-br/*` destroyed (targeted apply due to pre-existing magnatech drift); deprecated `out_atento_br_vpc_id` output removed from code; 14 obsolete `moved` blocks (Phase 3 rename artifacts) cleaned up. Output state cleanup deferred to next clean networking apply (post-magnatech-drift resolution) — benign code-vs-state inconsistency, auto-syncs on next plan |
| 8.5 — Lambda binary-scale refactor (payroll) | ✅ | lambda#53, lambda#54 (tag 0.10.0), terraform#394 | Lambda v0.10.0 (`0.10.0_0989a3e`) live in sa-east-1; binary scale to `MAXIMUM_CAPACITY` on any queued job; scale-down hysteresis preserved. Validation deferred to 2026-05-14 alongside the FPW client integration test |
| 9 — Cutover | ✅ | — | Sidekiq stopped on the 5 EC2s before 2026-05-05; ECS Fargate is the sole consumer of the `payroll_tiger_shark` queue |
| 10 — Decommission | ✅ | terraform#396 | 5 legacy EC2 instances (`app001`-`app005`) terminated; `ec2_legacy.tf` removed. Termination protection lifted ad-hoc via `aws ec2 modify-instance-attribute` before apply. Ansible/Capistrano cleanup + `modules/app` `enable_vpn` audit tracked as separate follow-ups (out of scope) |

### Phase 7 — Final state (delivered via terraform#354, lambda#49, AWS CLI ops)

All five sub-phases closed. Key outcomes:

- **7a** — `modules/atento_001_task_config` module added; `app-atento-001/compute.tf` refactored to consume it. Single source of truth for ECS task env vars + secrets between the two stacks.
- **7b** — `app-atento-001` refactor plan showed zero resource changes (applied confirming state-config match).
- **7c** — Lambda artifact buckets split from legacy `4shark-lambda-artifacts` into `4shark-lambda-artifacts-us-east-1` and `4shark-lambda-artifacts-sa-east-1` (both with versioning + AES256 + PAB). 37 versions + 6 delete markers / 144 MiB content sync'd to both. `lambda/bin/publish_lambdas` dual-pushes going forward (lambda#49). 5 stacks re-pointed to `-us-east-1`; drift (AMI data source, `PEN_TEST` flag, provider-upgrade phantoms) resolved on apply of 3 stacks. `app-atento-001` and `onboarding` have config merged but state not applied — behavior identical to applied peers, deferred to next natural deploy.
- **7d** — `app-outbound-atento-br/` compute stack live. 16 resources: inline ECS Fargate cluster, `modules/ecs_service` service (`desired_count=0`, launch_type=`FARGATE`, 1024 CPU / 2048 MB), `modules/lambda-ecs-autoscaling` Lambda, `modules/eventbridge-scheduler` at rate 1 minute, 4 inline IAM roles/policies (Option A — no ASG perms). Lambda env vars set via AWS CLI (10 vars; `REDIS_URL` points at SSM `REDIS_SIDEKIQ_URL`). CloudWatch logs confirm scale-to-zero steady state.
- **7e** — Legacy `4shark-lambda-artifacts` bucket purged and deleted (AWS CLI; 37 versions + 6 markers removed; `HeadBucket` → 404).

### Phase 7 — Deviations from the original plan

- **Task sizing**: original plan specified 2048 CPU / 2048 MB for parity with t3.small. Invalid Fargate combination (AWS requires 2048 CPU paired with ≥4096 MB). Adjusted to **1024 CPU / 2048 MB** (memory parity, 1 vCPU dedicated vs t3.small's 2 vCPU burstable ≈ 0.4 vCPU sustained — net more compute).
- **Scheduler name length**: module template `Lambda-${environment}-${schedule_name}-schedule` exceeded AWS's 64-char limit when `schedule_name = lambda_name = worker-payroll-autoscaling`. Shortened to `schedule_name = "worker-payroll"` (resulting schedule: `Lambda-app-outbound-atento-br-worker-payroll-schedule` = 53 chars).
- **`REDIS_URL` semantic**: the Lambda env var called `REDIS_URL` is the **Sidekiq queue** Redis (SSM `REDIS_SIDEKIQ_URL` / `REDIS_LOCK_URL`), NOT the app's main Redis (SSM `REDIS_URL` / `REDIS_CACHE_URL`). Confirmed against live `app-atento-001` autoscaling Lambda config.
- **Bucket creation scope**: buckets are shared infra, so they live **outside Terraform** (no `aws_s3_bucket` resource). Created directly via AWS CLI with settings mirrored from the legacy bucket (versioning Enabled, AES256, full PAB).

### Key discoveries that changed the plan

- **HireFire dyno gap** (Phase 6): `config/initializers/hire_fire.rb` had no `worker_payroll_tiger_shark` dyno. Without it, Lambda would fail with `process_not_found` forever. Added.
- **Redis Cloud is public** (not AWS-VPC Redis): endpoint `redis-19904.c263.us-east-1-2.ec2.redns.redis-cloud.com` reachable cross-region without any networking. Cross-region reachability risk is resolved.
- **Procfile is Heroku-legacy**: drop in a separate PR; `Procfile.dev.*` (used by `bin/`) stays.
- **SSM cross-region**: task in sa-east-1 reads SSM params from us-east-1 via full ARN. No need to duplicate.
- **atento-001 deploy IAM was us-east-1-only**: extended to sa-east-1 (Phase 5b-IAM).
- **"ForCheck" was a hallucination** in prior docs. On-prem system is **FPW (LG Lugar de Gente)**.
- **Customer gateway IP `177.22.252.45`**: is the VPN peer public IP (real), not a system IP.

---

## Objective

Migrate the `app-atento-br` stack (5 × t3.small Sidekiq workers in sa-east-1 processing egress jobs
to Atento's on-prem FPW via VPN) from EC2 + Ansible/Capistrano to ECS Fargate with
scale-to-zero coordinated by dedicated autoscaling Lambdas. Rename everything from the `out-`
vocabulary to `app-outbound-atento-br`. Deadline: **2026-05-14**.

---

## Scope

### In Scope

- Inventory of environment variables and Sidekiq configuration on the 5 existing EC2s
- New `modules/app_outbound` Terraform module (VPN, peering, routing, DNS association, ECS
  cluster scaffolding) with `name_prefix = "4client-app-outbound-${var.client_name}"`
- Rename `app-atento-br/` stack to `app-outbound-atento-br/`; migrate Terraform state (S3 key
  rename + `moved` blocks)
- Networking rename: `out-atento-br` VPC/subnets/TGW/peering resource addresses → `app_outbound_atento_br`;
  Name tags updated; SSM paths `/networking/out-atento-br/*` destroyed + recreated as
  `/networking/app-outbound-atento-br/*`
- New ECR repository `atento-001-app` in `sa-east-1`
- Extend `build-image.yaml` to dual-push the `atento-001` image to both us-east-1 and sa-east-1
  ECR repos on every build
- New ECS Fargate cluster `app-outbound-atento-br-cluster` in sa-east-1, attached to the
  (renamed) VPC; single worker service `app-outbound-atento-br-worker-payroll-service`; 5 tasks at
  2048 CPU / 2048 MB; `desired_count = 0` (scale-to-zero baseline)
- New Fargate-native autoscaling Lambda (`worker-payroll-autoscaling`) in `lambda/` repo:
  parameterized copy of `worker-autoscaling/lambda_function.rb` with the EC2 Auto Scaling Group
  calls removed; operates purely via `ecs:UpdateService` on `desired_count`; `MINIMUM_CAPACITY = 0`
- Terraform resources for the autoscaling Lambda: `modules/lambda-ecs-autoscaling` invocation
  in the stack + EventBridge schedule (1-minute interval) + IAM execution role with
  `ecs:UpdateService` scoped to the outbound service ARN + `ecs:DescribeServices` +
  `ecs:ListTasks` + `ecs:ExecuteCommand` as needed
- Extend `deploy-atento-001.yaml` with new jobs targeting the outbound cluster in sa-east-1:
  acquire/release autoscaling lock (lock key `ecs_scaling:lock:app-outbound-atento-br-cluster`),
  send TSTP/CONT to outbound worker tasks, deploy the worker service, rollback on failure
- New GitHub Actions environment `atento-001-outbound` with outbound-specific secrets
- Add dedicated Sidekiq queue in `app/` for outbound egress jobs; configure outbound task to
  consume only that queue
- Cutover: scale ECS to 5 tasks, stop Sidekiq on EC2s, observe, decommission
- Decommission: destroy EC2 resources via Terraform; delete DNS records; remove EC2 path from
  `modules/app` if no other stack uses it

### Out of Scope

- Renaming `app-atento-001` (separate naming problem, separate effort)
- ALB (worker-only stack, no web process)
- New ECR build pipeline (reuses existing `build-image.yaml` job, extended for dual-push)
- Database migrations (worker-only — no migration step on deploy)
- Changes to the main app VPN, TGW, or cross-VPC routing beyond what is needed to attach the
  renamed VPC correctly

---

## Critical Prerequisite — Read the Autoscaling Lambda Code First

**This is Step 0, not Phase 1.** Before any Terraform, Lambda, or CI work is written, read:

- `/Users/plribeiro3000/Projects/4Shark/lambda/worker-autoscaling/lambda_function.rb`
- `/Users/plribeiro3000/Projects/4Shark/lambda/worker-autoscaling/README.md`
- How the `app-atento-001` stack wires the lambda via `modules/lambda-ecs-autoscaling`
  (see `app-atento-001/compute.tf`)

**Why this blocks everything:**

The existing `worker-autoscaling` Lambda drives **EC2 Auto Scaling Groups** (`aws-sdk-autoscaling`,
`describe_auto_scaling_groups`, `update_auto_scaling_group`) in addition to ECS. The outbound stack
is Fargate with no ASG — the Lambda for the outbound cluster must drop all ASG calls and operate
purely via `ecs:UpdateService` with `desired_count`. This architectural difference affects the
Lambda code, the IAM policy shape, and the Terraform wiring. The executor cannot know what to
write until the current Lambda is read in full and the ASG-vs-Fargate delta is documented.

**Output of Step 0:** a concrete list of what changes relative to `worker-autoscaling` before
writing a single line of new Lambda code.

---

## Execution Phases

---

### Phase 0: Source-of-Truth Inventory (code + deployed Lambdas)

**Objective:** Capture the concrete values needed to wire the payroll Fargate stack. The source
of truth is the current `app-atento-001` ECS deploy and the `app/` codebase, **not** the EC2
servers — the EC2 runtime state is known to be out of date (env vars pointing at retired DBs)
and will be discarded at cutover. No SSH work is required.

**Repos affected:** none (read-only code reads + AWS read-only API calls)

**Work (already executed during PLAN review):**

| Value | Source | Confirmed |
|---|---|---|
| Queue name | `app/config/sidekiq_payroll_tiger_shark.yml:5` | `payroll_tiger_shark` |
| Queue composition rule | `app/app/models/tenant_worker/queue.rb:23` | `base_queue_name + company.commission_queue_suffix` |
| Base queue name | `app/app/workers/fpw_integration/*.rb` (all declare `base_queue_name :payroll`) | `payroll` |
| Only 1 Sidekiq config listens to `payroll_tiger_shark` | `grep -l "payroll" app/config/sidekiq*.yml` → single match | Queue dedicated, no cross-listen |
| SIDEKIQ_THREADS | `terraform/app-atento-001/compute.tf:59` | `"10"` |
| METRICS_ENDPOINT (HireFire) | `aws lambda get-function-configuration` on any atento-001 autoscaling Lambda | `https://atento001.app4shark.com/hirefire/191080bf-1429-42d4-8a53-0f8df3e8354a/info` (identical across all 5 atento-001 autoscaling Lambdas) |
| PROCESS_NAME convention | HireFire dyno names in `app/config/initializers/hire_fire.rb` | `worker_<queue>` (underscore). For payroll: `worker_payroll_tiger_shark` |
| REDIS_URL | `aws lambda get-function-configuration` | Redis Cloud public endpoint (`redis-19904.c263.us-east-1-2.ec2.redns.redis-cloud.com:19904`) — reachable cross-region from sa-east-1 without special networking |
| JOBS_PER_PROCESS | atento-001 Lambdas env | `500` (unchanged from standard) |
| Runtime env vars for task definition | `terraform/app-atento-001/compute.tf:9-91` (`locals.env_vars` + `secrets`) | Cloned literally for the payroll service — same Rails image, same app config |

**Gap discovered during Phase 0 (blocks Phase 4 + Phase 7):**

`config/initializers/hire_fire.rb` currently registers 5 dynos: `worker_system`, `worker_user`,
`worker_commission`, `worker_commission_tiger_shark`, `worker_commission_white_shark`. **No
`worker_payroll_tiger_shark` dyno exists.** Without it, the HireFire `/info` endpoint never
reports the payroll queue, and the new Lambda would fail with `process_not_found`. Phase 6
(app-side) now includes a dedicated task for registering this dyno.

**Dependencies:** none

**Success Criteria:**
- [x] Queue name confirmed (`payroll_tiger_shark`)
- [x] PROCESS_NAME confirmed (`worker_payroll_tiger_shark` — must match dyno to be created in Phase 6)
- [x] METRICS_ENDPOINT, REDIS_URL, JOBS_PER_PROCESS confirmed from deployed atento-001 Lambdas
- [x] SIDEKIQ_THREADS and full env_vars/secrets set confirmed as clonable from atento-001
- [x] HireFire dyno gap documented and pushed into Phase 6 as a blocking task

**Effort:** 0.5 day (all work completed during PLAN review; no SSH, no server access)
**Risk:** LOW — every value traced to a file or a deployed Lambda response saved at
`/tmp/aws_lambda_envs_atento-001_*.txt`.

---

### Phase 1: Lambda Reference Read + Fargate Adaptation Design

**Objective:** Read the existing `worker-autoscaling` Lambda in full, document the exact delta
needed for Fargate, and confirm the new Lambda's interface before writing any code.

**Repos affected:** `lambda/` (read-only in this phase)

**Work:**
- Read `lambda/worker-autoscaling/lambda_function.rb` completely
- Identify all ASG calls: `Aws::AutoScaling::Client`, `describe_auto_scaling_groups`,
  `update_auto_scaling_group` — these are removed in the Fargate variant
- Map which env vars change: `AUTO_SCALING_GROUP_NAME` is dropped; `MINIMUM_CAPACITY` and
  `MAXIMUM_CAPACITY` are read directly from env (not from ASG); `AWS_REGION` defaults to
  `sa-east-1` (not `us-east-1`)
- `METRICS_ENDPOINT` + `PROCESS_NAME` polling pattern stays the same. The endpoint is the
  same one used today by the `app-atento-001` autoscaling Lambda (hosted in us-east-1). The
  outbound Lambda runs in **sa-east-1** and reaches the endpoint **cross-region over HTTPS**.
  Same cross-region reachability is assumed for Redis (already required since the outbound
  Fargate tasks in sa-east-1 consume from the shared Sidekiq Redis).
- Document the final Lambda interface (env vars, removed calls, kept logic) as a short note
  before Phase 4 begins

**Dependencies:** Phase 0 complete (queue name needed to confirm `PROCESS_NAME` value)

**Success Criteria:**
- [ ] All ASG-specific calls identified and marked for removal
- [ ] Final env var list for the Fargate Lambda documented
- [ ] No open questions about the Lambda interface remain

**Effort:** 0.5 day

---

### Phase 2: Networking Rename (Terraform — `terraform/`)

**Objective:** Rename all `out-atento-br` resources in the networking stack to
`app-outbound-atento-br` without destroying or recreating any actual AWS resources.

**Repos affected:** `terraform/`

**Files touched:**
- `networking/vpc_out_atento_br.tf` — resource address renames via `moved` blocks + Name tag
  updates
- `networking/peering.tf`, `networking/transit_gateway.tf`, `networking/vpc_egress_sa_east_1.tf`
  — Name tag updates + `moved` blocks where resource addresses contain `out_atento_br`
- `networking/ssm.tf` — destroy SSM parameters at `/networking/out-atento-br/*` and recreate
  them at `/networking/app-outbound-atento-br/*` (SSM names are immutable; this is the only
  actual destroy+create in this phase)

**Work:**
- Add `moved` blocks for every resource whose Terraform address contains `out_atento_br`
- Update all `Name` tags from `out-atento-br` to `app-outbound-atento-br`
- Remove old SSM parameter resources; add new ones at the new paths
- Run `terraform plan` in `networking/`; verify: 0 resources destroyed except the 6 SSM
  parameters, 0 resources recreated for VPC/subnets/routes

**Dependencies:** Phase 0 complete (confirms no EC2 runtime reads these SSM paths directly)

**Success Criteria:**
- [ ] `terraform plan` shows: tag updates only for VPC/subnet/IGW/TGW/peering/route resources
- [ ] `terraform plan` shows: 6 SSM parameters destroyed + 6 created (no other destroys)
- [ ] `terraform apply` succeeds with no downtime to the VPN or existing EC2s
- [ ] AWS console shows no `out-atento-br` Name tags remaining in the networking stack

**Effort:** 1 day
**Risk:** LOW — `moved` blocks are non-destructive; SSM destroy+create has zero runtime impact
(parameters are read only during `terraform plan`).

---

### Phase 3: `modules/app_outbound` + Stack Rename (Terraform — `terraform/`)

**Objective:** Create the new reusable module and rename the stack directory; replace the
`modules/app` invocation with `modules/app_outbound`; migrate Terraform state to the new S3 key.

**Repos affected:** `terraform/`

**Work:**

**3a — Create `modules/app_outbound`:**
- New module at `terraform/modules/app_outbound/`
- Owns: VPN gateway, customer gateway, VPN connection, peering association, route table entries,
  DNS zone association; ECS cluster scaffolding
- Internal `name_prefix = "4client-app-outbound-${var.client_name}"`
- Variables: `client_name`, `vpc_id`, `subnet_ids`, `customer_gateway_ip`, `on_prem_cidrs`,
  plus ECS cluster inputs (cluster name, tags)
- No EC2 resources — the module is Fargate-only from day one

**3b — Rename stack directory + state migration:**
- Rename `terraform/app-atento-br/` → `terraform/app-outbound-atento-br/`
- Update `providers.tf` backend key: `app-atento-br/terraform.tfstate` →
  `app-outbound-atento-br/terraform.tfstate`
- Copy the existing state in S3: `aws s3 cp s3://...app-atento-br/terraform.tfstate s3://...app-outbound-atento-br/terraform.tfstate`
- Run `terraform init -reconfigure` in the new directory
- Verify `terraform plan` shows no unexpected changes (state was copied, not created fresh)

**3c — Replace `modules/app` invocation in `main.tf`:**
- Replace the `source = "../modules/app"` call with `source = "../modules/app_outbound"`
- Remove `enable_vpn = true` (the new module always owns VPN — it is not optional)
- Add `moved` blocks for any resources that change Terraform address due to the module swap
- Run `terraform plan`; verify all address changes are covered by `moved` blocks, zero actual
  resource recreation

**3d — Dead code check in `modules/app`:**
- After 3c, audit `modules/app` for the `enable_vpn` path
- If no other stack passes `enable_vpn = true`, remove the VPN/peering/routing blocks from
  `modules/app` and confirm no other stack is affected

**Dependencies:** Phase 2 complete (networking SSM paths must be updated before the new stack
reads them)

**Success Criteria:**
- [ ] `modules/app_outbound` created with correct `name_prefix` and no EC2 resources
- [ ] Stack renamed; `terraform init -reconfigure` succeeds; `terraform plan` shows no unexpected
  destroy/recreate
- [ ] `modules/app` VPN path removed (or explicitly left with a comment if another stack uses it)
- [ ] All `Name` tags in the stack now use `4client-app-outbound-atento-br` prefix

**Effort:** 2–3 days
**Risk:** MEDIUM — `moved` blocks for module-level resource addresses require care; incorrect
blocks will trigger a destroy+create instead of a rename.

---

### Phase 4: New Autoscaling Lambda (Fargate variant) — `lambda/`

**Objective:** Create `lambda/worker-payroll-autoscaling/` as a Fargate-native variant of
`worker-autoscaling`, with all ASG logic removed.

**Repos affected:** `lambda/`

**Work:**
- Copy `worker-autoscaling/lambda_function.rb` to
  `worker-payroll-autoscaling/lambda_function.rb`
- Remove all `Aws::AutoScaling::Client` calls and the `AUTO_SCALING_GROUP_NAME` env var
- Replace ASG-based capacity reads (`auto_scaling_group.min_size`, `.max_size`,
  `update_auto_scaling_group`) with env-var-based equivalents: `MINIMUM_CAPACITY` and
  `MAXIMUM_CAPACITY` read directly from `ENV`
- Keep the hysteresis / empty-queue counter logic (`ecs_scaling:empty_checks:*` Redis key)
  unchanged
- Keep the `ecs_scaling:lock:*` Redis key check unchanged (deploy workflow sets this lock)
- Update `AWS_REGION` default from `us-east-1` to `sa-east-1`
- Copy `Gemfile` / `Gemfile.lock` from `worker-autoscaling/`; remove `aws-sdk-autoscaling` gem
- Update `README.md`: document the Fargate-only variant, removed env vars, changed defaults
- Package and upload to S3 (same process as existing Lambdas — confirm S3 bucket name and key
  convention from the existing Lambda deploy pipeline or README)

**Dependencies:** Phase 1 complete (interface design documented); Phase 0 complete (queue name
known, confirming `PROCESS_NAME`)

**Success Criteria:**
- [ ] No `Aws::AutoScaling` or ASG references remain in the new Lambda code
- [ ] Lambda runs locally against a test Redis with simulated queue depth (manual smoke test)
- [ ] `MINIMUM_CAPACITY = 0` allows the Lambda to scale to zero (verified in test)
- [ ] Lambda packaged and uploaded to S3 at the correct key
- [ ] `README.md` documents the Fargate-specific env vars and removed ASG vars

**Effort:** 1 day
**Risk:** LOW — the core logic is unchanged; only the ASG calls are removed.

---

### Phase 5: ECR Dual-Push (`app/`)

**Objective:** Create the sa-east-1 ECR repository and extend `build-image.yaml` to push the
`atento-001` image to both us-east-1 and sa-east-1 on every master build.

**Repos affected:** `terraform/` (ECR repo creation), `app/` (workflow change)

**Work:**

**5a — Create ECR repo in sa-east-1 (Terraform):**
- Add an `aws_ecr_repository` resource (or use the existing `modules/ecr` module) in
  `app-outbound-atento-br/` or a shared ECR Terraform file, region-aliased to `sa-east-1`
- Repo name: `atento-001-app` (same name as us-east-1, different region)
- Lifecycle policy: same as the us-east-1 repo (retain last N images, expire untagged)

**5b — Extend `build-image.yaml`:**
- Existing pattern: `build-atento-001` job logs into us-east-1 ECR, builds once, pushes to
  `405749097490.dkr.ecr.us-east-1.amazonaws.com/atento-001-app:latest` and `:<version-sha>`
- Extension: after the existing push, add a second login step for sa-east-1 ECR and push the
  same already-built image to `405749097490.dkr.ecr.sa-east-1.amazonaws.com/atento-001-app:latest`
  and `:<version-sha>` (no rebuild — re-tag and push)
- The `build-atento-001` GitHub environment must have write access to both regions; confirm
  `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` in that environment have `ecr:PutImage` on the
  sa-east-1 repo (or add a dedicated outbound secret pair if IAM scope is per-region)

**Dependencies:** Phase 3 complete (sa-east-1 ECR repo created via Terraform)

**Success Criteria:**
- [ ] ECR repo `atento-001-app` exists in sa-east-1
- [ ] `build-image.yaml` build-atento-001 job pushes `:latest` and `:<version-sha>` to both
  regions after a test trigger
- [ ] No second Docker build — image is built once and pushed twice
- [ ] sa-east-1 ECR shows correct image layers after push

**Effort:** 0.5 day
**Risk:** LOW — re-tagging an already-built image is a trivial Docker operation; IAM is the
only risk (permission to push to a new region).

---

### Phase 6: App-Side HireFire Dyno Registration (`app/`)

**Objective:** Register the `worker_payroll_tiger_shark` dyno in HireFire so the `/hirefire/.../info`
endpoint reports the payroll queue depth. Without this, the new Lambda cannot find the process
and the Fargate cluster never scales.

**Repos affected:** `app/`

**Sidekiq config (already exists):**
- `config/sidekiq_payroll_tiger_shark.yml` already exists in the repo and listens exclusively on
  queue `payroll_tiger_shark` (confirmed in Phase 0: single match across all sidekiq configs)
- `config/deploy/atento-br.rb:4` already points the Capistrano deploy to this file
- No changes needed to Sidekiq config — the ECS task definition in Phase 7 will launch Sidekiq
  with `-C config/sidekiq_payroll_tiger_shark.yml`

**HireFire dyno (gap — must be added):**
- Add a new `config.dyno(:worker_payroll_tiger_shark)` block in
  `app/config/initializers/hire_fire.rb` registering the `payroll_tiger_shark` queue:
  ```ruby
  config.dyno(:worker_payroll_tiger_shark) do
    HireFire::Macro::Sidekiq.queue(:payroll_tiger_shark)
  end
  ```
- Verify on a running atento-001 instance that the `/hirefire/.../info` endpoint now returns an
  entry with `"name": "worker_payroll_tiger_shark"` — this is the exact string the new Lambda
  uses as `PROCESS_NAME`

**Design note:** For future clients with the same shark-suffix pattern, a loop-based registration
(driven by `Company.all.map(&:commission_queue_suffix).uniq`) would be a natural extension.
Out of scope for this PR — one explicit block is enough for atento-br.

**Dependencies:** Phase 0 complete (queue name, dyno name, endpoint URL confirmed)

**Success Criteria:**
- [ ] `worker_payroll_tiger_shark` dyno block added to `config/initializers/hire_fire.rb`
- [ ] After deploy to atento-001, `curl` the HireFire endpoint and confirm the new entry is
  reported (even if queue depth is 0, the name must appear)
- [ ] No changes to existing dyno blocks

**Effort:** 0.5 day
**Risk:** LOW — one block addition, deterministic behavior, verifiable via HTTP GET.

---

### Phase 7: ECS Compute Stack (Terraform — `terraform/`)

**Objective:** Create the ECS Fargate cluster, worker service, task definition, autoscaling
Lambda wiring, and IAM in `app-outbound-atento-br/`. Extract shared env vars and secrets into
a new `modules/atento_001_task_config` module so both stacks share a single source of truth.
Migrate Lambda artifact buckets to region-specific buckets before wiring the sa-east-1 compute stack.

**Repos affected:** `terraform/`, `lambda/`

**Phase 7 is split into five sub-phases:**

---

**7a — Create `modules/atento_001_task_config`** ✅ DONE

New module at `terraform/modules/atento_001_task_config/`.

- **Input:** `cluster_name` (string) — the only value that differs between the two stacks
- **Outputs:** `env_vars` (map of string) and `secrets` (list of objects with `name` and
  `valueFrom`)
- **Source for initial values:** `app-atento-001/compute.tf:9-66` — the full `locals.env_vars`
  block (CLUSTER_NAME driven by the input variable) and the `secret_names` list (21 names) with
  ARNs pointing to `arn:aws:ssm:us-east-1:405749097490:parameter/atento-001/${name}`
- Module contains no AWS resources — it is a pure data/output module

---

**7b — Refactor `app-atento-001/compute.tf` to consume the module** ✅ DONE

- Replace the inline `locals.env_vars` block and `locals.secrets` / `local.secret_names` literals
  in `app-atento-001/compute.tf:9-66` with a call to `module.atento_001_task_config`, passing
  `cluster_name = "app-atento-001-cluster"` (confirm exact cluster name from the deployed stack)
- All downstream references to `local.env_vars` and `local.secrets` remain unchanged — only the
  definition site changes
- Run `terraform plan` in `app-atento-001/`; verify **zero resource changes** (only locals
  reorganized, no infrastructure touched)
- Apply immediately after plan is confirmed clean — the refactor must be live before Phase 7d
  to validate that the module outputs are correct in production

---

**7c — Lambda artifact bucket regional migration** ⏳ NEXT

**Context:** AWS Lambda requires that the S3 bucket storing function code resides in the same
region as the function. The legacy bucket `4shark-lambda-artifacts` lives in `us-east-1`, but
the outbound stack Lambda runs in `sa-east-1`, causing a `PermanentRedirect` error on deploy.

**Decision:** Create two new region-specific buckets, replicate the legacy content, update the
deploy script and existing Terraform stacks, then retire the legacy bucket.

**Work (sequenced — do not reorder):**

1. **Create new buckets via AWS CLI** (out-of-Terraform — these are shared infrastructure, not
   owned by any single stack):
   - `4shark-lambda-artifacts-us-east-1` in `us-east-1`
   - `4shark-lambda-artifacts-sa-east-1` in `sa-east-1`

2. **Replicate legacy content** — one-time migration:
   - `aws s3 sync s3://4shark-lambda-artifacts s3://4shark-lambda-artifacts-us-east-1`
   - `aws s3 sync s3://4shark-lambda-artifacts s3://4shark-lambda-artifacts-sa-east-1`
   - Verify both syncs with `aws s3 ls` before proceeding to any Terraform work

3. **Update `lambda/bin/publish_lambdas`** — dual-push to both new buckets on every release.
   Legacy bucket `4shark-lambda-artifacts` stops receiving new uploads after this change. Verify
   the script by running a dry-run upload for an existing artifact.

4. **Update `lambda/RELEASE.md`** — document the new bucket convention and migration rationale.

5. **Refactor 5 existing Terraform stacks** to reference `4shark-lambda-artifacts-us-east-1`:
   - `app-beta-001/`
   - `app-demo-001/`
   - `app-shared-001/`
   - `app-atento-001/`
   - `onboarding/`
   - Each stack must show **zero resource changes** in `terraform plan` (refactor-only gate,
     same as 7b). Apply each stack after its plan is confirmed clean.

**Dependencies:** None external. Steps 1–2 must complete before steps 3–5 (buckets must exist
and have content before any Terraform plan that reads `aws_s3_object` from the new paths).

**Success Criteria:**
- [ ] `4shark-lambda-artifacts-us-east-1` and `4shark-lambda-artifacts-sa-east-1` created
- [ ] `aws s3 ls` shows identical artifact keys in both new buckets vs the legacy bucket
- [ ] `lambda/bin/publish_lambdas` pushes to both new buckets; legacy bucket receives no new uploads
- [ ] `lambda/RELEASE.md` updated with the new bucket convention
- [ ] Each of the 5 stacks shows zero resource changes in plan after the `s3_bucket` refactor
- [ ] All 5 stacks applied cleanly with no downtime

---

**7d — Wire `app-outbound-atento-br` stack** (formerly 7c)

**Dependencies:** 7c complete (bucket `4shark-lambda-artifacts-sa-east-1` must exist and contain
`worker-payroll-autoscaling/0.9.0_37780e1.zip` before this plan runs)

Files to create in `app-outbound-atento-br/`:

- `locals.tf` — tags only; no inline `env_vars` or `secrets` (those come from the module)
- `iam.tf` — Lambda execution role
  `Lambda-app-outbound-atento-br-worker-payroll-autoscaling-role` inline (Option A of
  PHASE-1-DELTA.md). Attached policies: CloudWatch logs + ECS
  `UpdateService`/`DescribeServices`/`ListTasks` scoped to the outbound cluster and service.
  No ASG permissions.
- `compute.tf` — module call to `atento_001_task_config` passing
  `cluster_name = "app-outbound-atento-br-cluster"`; ECS cluster (inline `aws_ecs_cluster`,
  Fargate-only, no `modules/ecs_cluster`); CloudWatch log group; worker-payroll service via
  `modules/ecs_service` with `launch_type = "FARGATE"`, using `module.atento_001_task_config.env_vars`
  and `module.atento_001_task_config.secrets`; Lambda via `modules/lambda-ecs-autoscaling`;
  EventBridge schedule via `modules/eventbridge-scheduler`

**No `ssm.tf`** — secrets reuse `/atento-001/*` in us-east-1:
- Task in sa-east-1 reads SSM parameters cross-region via full ARN in `secrets.valueFrom`
- `ecsTaskExecutionRole` already has the policy (`atento-001-ssm-read` attached by
  `app-atento-001/ssm.tf:41-56`); works for any caller region
- KMS MRK `mrk-fa0cda243274491784fc7b39bead5a03` already replicated in sa-east-1
  (verified 2026-04-22); decrypt works in both regions
- Single source of truth — rotating a secret in us-east-1 immediately reaches sa-east-1 task
  on next cold start
- Overhead: +~100-300ms on cold start per task (batched `GetParameters` calls). Negligible.

**Compute.tf specifics:**
- Single service `app-outbound-atento-br-worker-payroll-service`; task family
  `app-outbound-atento-br-worker-payroll`; image
  `405749097490.dkr.ecr.sa-east-1.amazonaws.com/atento-001-app:latest`
- `task_cpu = 2048`, `task_memory = 2048`, `desired_count = 0` (scale-to-zero baseline)
- `launch_type = "FARGATE"` — no capacity provider, no ASG
- Subnets: private subnets of the renamed VPC (sa-east-1a / sa-east-1c)
- Security group: `module.this.default_security_group_id` (from `modules/app_outbound`),
  which already allows outbound to on-prem target CIDRs via TGW/VPN
- `enable_execute_command = true` (needed for TSTP/CONT during deploy)
- Task execution role: `arn:aws:iam::405749097490:role/ecsTaskExecutionRole` (global, reused)
- Task role: same as execution role
- CloudWatch log group `/ecs/app-outbound-atento-br-worker-payroll`; retention 30 days
- Sidekiq command: `bundle exec sidekiq -C config/sidekiq_payroll_tiger_shark.yml`

**Autoscaling Lambda wiring:**
- Module `modules/lambda-ecs-autoscaling` with:
  - `environment = "app-outbound-atento-br"`
  - `lambda_name = "worker-payroll-autoscaling"` → function name
    `Lambda-app-outbound-atento-br-worker-payroll-autoscaling`
  - `s3_bucket = "4shark-lambda-artifacts-sa-east-1"`
  - `s3_key = "worker-payroll-autoscaling/0.9.0_37780e1.zip"`
  - `role_arn` = the inline role from `iam.tf`
- EventBridge schedule via `modules/eventbridge-scheduler`: `rate(1 minute)`
- **Lambda env vars are NOT managed by Terraform** (`modules/lambda-ecs-autoscaling/main.tf:44-46`
  has `lifecycle { ignore_changes = [environment] }`). After apply, set via AWS Console or CLI:
  - `ECS_CLUSTER_NAME = app-outbound-atento-br-cluster`
  - `ECS_SERVICE_NAME = app-outbound-atento-br-worker-payroll-service`
  - `METRICS_ENDPOINT = https://atento001.app4shark.com/hirefire/191080bf-1429-42d4-8a53-0f8df3e8354a/info`
  - `PROCESS_NAME = worker_payroll_tiger_shark`
  - `MINIMUM_CAPACITY = 0`
  - `MAXIMUM_CAPACITY = 5`
  - `AWS_REGION = sa-east-1`
  - `REDIS_URL` = Redis Cloud public URL (same as atento-001 Lambdas)
  - `JOBS_PER_PROCESS = 500`
  - `EMPTY_QUEUE_CHECK_THRESHOLD = 3`

**Dependencies:** Phases 3, 4, 5a, 6, and **7c** complete (module exists, Lambda artifact
available in `4shark-lambda-artifacts-sa-east-1`, ECR repo exists, HireFire dyno registered).
Phase 5b (dual-push) + 5b-IAM preferred but not strictly required for apply (task won't start
healthy without image in sa-east-1 ECR, but apply itself succeeds — service just stays with
0 running tasks).

**Success Criteria:**
- [ ] `terraform plan` in `app-outbound-atento-br/` shows: cluster, log group, task definition,
  service, Lambda, EventBridge rule, IAM role — all creates, no unexpected destroys
- [ ] `terraform apply` for `app-outbound-atento-br/` succeeds; ECS service shows
  `desired_count = 0` (scale-to-zero baseline)
- [ ] Lambda env vars set manually via CLI/Console post-apply
- [ ] Lambda invocable manually via CLI; responds with `status: ok` (queue will be empty → 0)
- [ ] EventBridge rule fires every minute; CloudWatch shows Lambda executions
- [ ] Lambda correctly leaves service at 0 when queue is empty

---

**7e — Delete legacy `4shark-lambda-artifacts` bucket** (post-cutover verification)

**Context:** After 7d is applied and confirmed working, the legacy bucket `4shark-lambda-artifacts`
(us-east-1, no region suffix) must be decommissioned to avoid stale references and dual-maintenance.

**Work:**
- Verify no Terraform stack, CI script, or deploy workflow still references `4shark-lambda-artifacts`
  (grep across `terraform/`, `lambda/`, `.github/`)
- Verify `lambda/bin/publish_lambdas` has not uploaded to the legacy bucket since 7c was applied
- Delete the legacy bucket via AWS CLI: `aws s3 rm s3://4shark-lambda-artifacts --recursive`
  followed by `aws s3api delete-bucket --bucket 4shark-lambda-artifacts --region us-east-1`

**Dependencies:** 7d apply confirmed working; no references to legacy bucket remain.

**Success Criteria:**
- [ ] Grep across all repos shows zero references to `4shark-lambda-artifacts` without a region suffix
- [ ] Legacy bucket deleted; `aws s3 ls s3://4shark-lambda-artifacts` returns NoSuchBucket

---

**Phase 7 overall Success Criteria:**
- [ ] `modules/atento_001_task_config` created with `cluster_name` input and `env_vars`/`secrets`
  outputs (7a — done)
- [ ] `terraform plan` in `app-atento-001/` shows zero resource changes after the refactor (7b — done)
- [ ] `terraform apply` for the `app-atento-001` refactor succeeds with no downtime (7b — done)
- [ ] `4shark-lambda-artifacts-us-east-1` and `4shark-lambda-artifacts-sa-east-1` created and
  populated (7c)
- [ ] `lambda/bin/publish_lambdas` dual-pushes to both new buckets (7c)
- [ ] All 5 existing stacks refactored to `4shark-lambda-artifacts-us-east-1` with zero resource
  changes (7c)
- [ ] `app-outbound-atento-br/` compute stack applies cleanly with `desired_count = 0` (7d)
- [ ] Legacy `4shark-lambda-artifacts` bucket deleted (7e)

**Effort:** 5–6 days total (7a + 7b: 1 day done; 7c: 2.25 days; 7d: 2 days; 7e: 0.25 day)
**Risk:** MEDIUM — bucket migration touches 5 live stacks with a zero-change gate each; first
time wiring the Fargate autoscaling Lambda + first cross-region SSM reads for ECS tasks in this
project. See Risks section for specific risks introduced by 7b refactor and bucket migration.

---

### Phase 8 — Prerequisite: extend atento-001 deploy IAM to sa-east-1 ECS cluster (`terraform/`)

**Gap discovered during Phase 8 planning.** The `iam_deploy` module scopes the ECS cluster/service
ARNs to the stack's default provider region (`data.aws_region.current`). `app-atento-001` runs in
us-east-1, so the `aws_iam_user.deploy` credentials only cover `arn:aws:ecs:us-east-1:...:cluster/app-atento-001-cluster`.
The payroll worker service lives in `arn:aws:ecs:sa-east-1:...:cluster/app-outbound-atento-br-cluster` —
out of scope for the current policy. GitHub Actions deploy steps targeting sa-east-1 would fail
with `AccessDenied` on `ecs:UpdateService`.

**Fix (backward-compatible):**

- Add `additional_clusters` input (`list(object({region, name}))`, default `[]`) to
  `modules/iam_deploy`. The existing `cluster_names` input keeps working for the single-region case.
- `app-atento-001/compute.tf` passes `additional_clusters = [{region = "sa-east-1", name = "app-outbound-atento-br-cluster"}]`.
- Plan shows a single `aws_iam_policy.deploy` update-in-place extending the ECSClusterAll
  `Resource` list with 4 sa-east-1 ARNs (cluster + service/* + task/* + container-instance/*).

**Delivered via:** separate terraform PR (merged before the `app/` Phase 8 PR).

---

### Phase 8: Deploy Workflow — Sibling-job sa-east-1 Payroll Deploy (`app/`) ✅ DELIVERED

> **Status (2026-05-05):** delivered and stable. Reusable workflow exists, sibling jobs wired,
> 5 consecutive successful deploys through 2026-04-30. Cross-track rollback exercised via
> rollout iterations.

> **Architectural shape (final, post-execution):**
> - `deploy-atento-001.yaml` triggers a single `workflow_dispatch`. One deploy invocation fans
>   out to: main-app + payroll worker + payroll runner (and any future payroll added by another
>   client) — all sibling jobs running in parallel under the same workflow run.
> - Single GitHub Actions environment `atento-001` is used for every job — main-app, payroll
>   worker, payroll runner. **No per-track environment** (`atento-001-payroll` was considered
>   in the original spec and rejected): credentials and Redis URLs are shared, and the same IAM
>   user has been extended for sa-east-1 ECR + ECS via terraform#352.
> - **Why a single deploy invocation, not separate workflows per track:** version coupling. The
>   payroll worker and main-app must run the exact same code revision — they share the same
>   Rails image, same models, same migrations. A failure in one track must roll back the other
>   so the whole atento-001 fleet stays on the same version. Implemented via
>   `rollback-main-on-payroll-failure` and `rollback-payroll-on-main-failure` (#47eb1ffd9).
>   This pattern scales linearly: when N payroll services exist for atento-001, all N deploy
>   in parallel as siblings — none can drift in version.
> - Trigger remains `workflow_dispatch` (engineer-triggered). **Auto-trigger post-build is not
>   implemented and is no longer planned.**

> **Why not the original "matrix" form:** the main-app flow is 13 interdependent jobs
> (CodeDeploy blue/green, async hook mechanism, per-worker Sidekiq deploy). Gating all 13 with
> `matrix.target == 'main-app'` would lose per-job UI visibility and retry semantics. The sibling
> approach gives the same parallelism with cleaner observability.

**Repos affected:** `app/`

**Scope (explicit):** changes were restricted to `deploy-atento-001.yaml` and the new reusable
workflow file. `deploy-beta-001.yaml`, `deploy-demo-001.yaml`, and `deploy-shared-001.yaml`
were **not touched** in this phase.

**Delivered work:**

**8a — Reusable `deploy-payroll-worker.yaml`** ✅
- File `.github/workflows/deploy-payroll-worker.yaml` (356 lines)
- `on: workflow_call` with inputs: `aws_region`, `cluster_name`, `service_name`, `task_family`,
  `container_name`, `ecr_repo`, `image_tag` (default `latest`), `sidekiq_config_file`,
  `environment_name`
- Output `previous_task_definition` exposed back to the caller — enables cross-track rollback
  from `deploy-atento-001.yaml` when the main-app track fails after payroll has deployed
- Secrets passed via `secrets: inherit`
- Jobs: `acquire-lock` → `quiet-mode` → `deploy` → `release-lock` (success) /
  `cleanup-on-failure` (failure). Lock TTL 15 min. Cleanup-on-failure recovers quieted Sidekiq
  workers by either rolling back the task def (when deploy moved it) or stopping running tasks
  to force ECS to spawn fresh replacements (#4988).

**8b — Sibling jobs in `deploy-atento-001.yaml`** ✅
- Trigger: `workflow_dispatch` (manual, engineer-triggered)
- Job `deploy-payroll` (line 985) — calls `./.github/workflows/deploy-payroll-worker.yaml` with
  the atento-br outbound infra identifiers; `environment_name: atento-001` (single env)
- Job `deploy-runner-payroll` (line 1006) — sibling deploy of the runner service in the same
  outbound cluster (Fargate, `desired_count=0` permanent, task def refreshed every deploy so
  `bin/ecs run app-outbound-atento-br` picks up current code). Mirrors the main-app runner
  pattern in us-east-1.
- `validate` job (line 1031) waits on all tracks: `prepare-and-migrate`, `sidekiq-quiet-mode`,
  `deploy-web`, `deploy-sidekiq`, `register-cron-tasks`, `resume-deployment`, `traffic-shift`,
  `deploy-payroll`, `deploy-runner`, `deploy-runner-payroll`. `if: always()` so cross-track
  rollback can fire on partial failures.
- Cross-track rollback (#47eb1ffd9):
  - `rollback-main-on-payroll-failure` (line 1387) — rolls main-app workers back if main-app
    deployed cleanly but payroll failed
  - `rollback-payroll-on-main-failure` (line 1570) — rolls payroll back to its pre-deploy task
    def if payroll succeeded but main-app failed

**8c — GitHub Actions environment** ✅
- Single environment `atento-001` reused for all jobs (main-app + payroll worker + payroll
  runner). No `atento-001-payroll` was created — credentials and Redis URLs are shared, and
  the same IAM user already has sa-east-1 ECR + ECS access (terraform#352).

**Auto-trigger post-build:** **NOT implemented and not planned.** Merge to master triggers
`build-image.yaml`, which dual-pushes the image to us-east-1 + sa-east-1 ECR (Phase 5b). Deploys
remain manual `workflow_dispatch` per policy.

**Design implications for future payrolls:**
- When a second payroll client (or a non-atento payroll) is added, it joins the same
  `deploy-atento-001.yaml` (or its env equivalent) as another sibling job calling the same
  reusable workflow. All payrolls deploy in parallel under one invocation — no track can drift
  on code version.
- The reusable workflow is `workflow_call`-only; future envs (`deploy-shared-001.yaml`,
  `deploy-beta-001.yaml`) can reuse it by adding sibling jobs without changes to the file.

**Dependencies satisfied:** Phase 7 (ECS service + runner service); Phase 6 (Sidekiq config);
Phase 5b (dual-push to sa-east-1 ECR).

**Success Criteria — all met:**
- [x] `deploy-payroll-worker.yaml` exists as a `workflow_call`-only reusable workflow
- [x] `deploy-atento-001.yaml` runs main-app + payroll worker + payroll runner as siblings; all
  three deploy in parallel
- [x] Trigger remains `workflow_dispatch` (engineer-triggered)
- [x] `deploy-beta-001.yaml`, `deploy-demo-001.yaml`, `deploy-shared-001.yaml` byte-for-byte
  identical to their pre-PR state
- [x] Cleanup-on-failure recovers quieted Sidekiq workers (rollback or force-stop)
- [x] Lock key `ecs_scaling:lock:app-outbound-atento-br-cluster` always released
- [x] Cross-track rollback prevents version drift between main-app and payroll
- [x] 5 consecutive successful deploys through 2026-04-30 (manual smoke test passed multiple
  times; rollback paths exercised during stabilisation)

**Delivered via:** app#3618a4cbf (initial), app#1283f01b8 (runner wiring), app#47eb1ffd9
(cross-track rollback), app#4988 (cleanup recovery hardening).

---

### Phase 8.5: Lambda Binary-Scale Refactor (Payroll-specific) ✅ DELIVERED

> **Status (2026-05-05):** delivered. Lambda v0.10.0 released and live; Terraform stack
> consuming the new artifact key `0.10.0_0989a3e`. Validation (queue-depth-driven scale-up
> observation) deferred to **2026-05-14** alongside the FPW client integration test.
>
> **Delivered via:**
> - lambda#53 — `feat(payroll-autoscaling): scale to max on any queued job`
> - lambda#54 — `[0.10.0] - 2026-05-05` (release PR; tag `0.10.0` created via `git hf release finish`)
> - `bin/publish_lambdas` upload — `worker-payroll-autoscaling/0.10.0_0989a3e.zip` in both
>   `4shark-lambda-artifacts-us-east-1` and `4shark-lambda-artifacts-sa-east-1`
> - terraform#394 — `feat(app-outbound-atento-br): bump worker-payroll-autoscaling to 0.10.0`
>   (1 resource update-in-place; Lambda `lastModified = 2026-05-05T14:36:57Z`)

**Objective:** Change `worker-payroll-autoscaling` from gradual queue-depth-based scaling
(`required = (jobs / JOBS_PER_PROCESS).ceil` clamped to `[MIN, MAX]`) to **binary scaling**:
the moment the queue has any job, the service jumps to `MAXIMUM_CAPACITY`. Scale-down
hysteresis (3 consecutive empty checks → 0) is preserved as-is.

**Motivation:** Payroll integrations are time-sensitive — when a client kicks off a payroll
batch the work must drain as fast as possible. The current per-500-jobs ramp would leave
small bursts (under 500 jobs) running on a single worker, which is too slow for the payroll
SLA. The binary pattern keeps the service at MIN (0) when idle and at MAX during any burst,
never intermediate. Across the fleet of payroll services (one per client) the desired count
is always either 0 or `MAXIMUM_CAPACITY` — never a fractional ramp.

**Per-client tuning:** `MAXIMUM_CAPACITY` is already an env var on the Lambda. atento-001 uses
5 (matching the EC2 fleet size). Future clients pick their own MAX based on payroll volume —
larger client = higher MAX = faster drain — without any code change.

**Behavior delta vs current Lambda (v0.9.0):**

| Aspect | Current (v0.9.0) | New (v0.10.0) |
|---|---|---|
| Scale-up condition | `jobs_in_queue > 0` | Same |
| Scale-up target | `(jobs / JOBS_PER_PROCESS).ceil` clamped to `[MIN, MAX]` | `MAXIMUM_CAPACITY` (always) |
| `JOBS_PER_PROCESS` env var | Used in calculation | No longer read (kept on the Lambda env for compat, ignored by code) |
| Scale-down condition | `jobs == 0` for `EMPTY_QUEUE_CHECK_THRESHOLD` consecutive ticks | Same |
| Scale-down target | `MINIMUM_CAPACITY` (0) | Same |
| Lock check (`ecs_scaling:lock:<cluster>`) | Required for any scaling action | Same |

**Repos affected:** `lambda/`, `terraform/`

**Work:**

1. **`lambda/worker-payroll-autoscaling/lambda_function.rb`** — replace the scale-up branch
   (lines 86-102) with a binary jump to `MAXIMUM_CAPACITY`. Scale-down branch unchanged.
2. **`lambda/worker-payroll-autoscaling/README.md`** — update behavior description; note that
   `JOBS_PER_PROCESS` is no longer used.
3. **`lambda/CHANGELOG.md`** — add `## [0.10.0]` entry under `### Changed`: "Payroll
   autoscaling now scales to MAX immediately on any queued job; scale-down hysteresis preserved".
4. **Release** — run `lambda/bin/publish_lambdas` which dual-pushes the new artifact to
   `4shark-lambda-artifacts-us-east-1` and `4shark-lambda-artifacts-sa-east-1` with key
   `worker-payroll-autoscaling/0.10.0_<sha>.zip`.
5. **`terraform/app-outbound-atento-br/compute.tf`** — bump the `s3_key` on
   `module "worker_payroll_autoscaling"` to the new artifact key. Plan should show only the
   Lambda code source updating; env vars stay untouched
   (`lifecycle { ignore_changes = [environment] }`).
6. **Validation post-apply:**
   - Manually invoke the Lambda with the queue empty → expect `Already at minimum capacity`
   - Manually scale the worker service to 1 (as in 2026-05-05 E2E test) and enqueue at least
     one job in `payroll_tiger_shark` → expect the next 1-min Lambda poll to immediately set
     `desired_count = MAXIMUM_CAPACITY` (5 for atento-001), not gradual
   - Empty the queue → expect scale-down to 0 after 3 polls (~3 min)

**Dependencies:** None — Phase 7d is live and the Lambda is invocable. Can run in parallel
with Phase 2.5 (SSM cleanup).

**Sequencing relative to Phase 9 cutover:** Strongly preferred to land **before** Phase 9 so
day-1 production behavior is the binary pattern the business expects. Not strictly blocking —
the v0.9.0 Lambda would still work post-cutover, just less aggressively. Rollback if needed:
revert `s3_key` to `worker-payroll-autoscaling/0.9.0_37780e1.zip`.

**Effort:** 0.5 day (code change + release + Terraform bump + validation)
**Risk:** LOW — change is in a single conditional branch; the previous artifact stays in S3 as
a one-line rollback path.

---

### Phase 9: Cutover

**Objective:** Switch live traffic from EC2 to ECS Fargate within the monthly maintenance
window (no parallel run — Decision confirmed in SPIKE Open Questions).

**Repos affected:** none (operational procedure)

**Work:**
- Confirm timing: execute within the monthly gap when FPW egress is idle
- Scale ECS service to 5 tasks manually (or trigger a test job to enqueue in the outbound queue
  and let the Lambda scale up)
- Verify all 5 Fargate tasks are healthy and processing; confirm CloudWatch logs show Sidekiq
  starting correctly with the correct queue
- Stop Sidekiq on all 5 EC2s: `sudo systemctl stop sidekiq` (or equivalent Capistrano command)
- Observe for 15–30 minutes: queue depth drains, no errors in Rollbar or CloudWatch
- Confirm EC2 Sidekiq processes are stopped and not restarting

**Dependencies:** Phases 7 and 8 complete (ECS service running; deploy workflow wired)

**Success Criteria:**
- [ ] All 5 Fargate tasks running and processing the outbound queue
- [ ] EC2 Sidekiq processes stopped; no EC2 workers consuming the queue
- [ ] Queue depth drains to zero within expected time
- [ ] No errors in Rollbar or CloudWatch during the observation window
- [ ] VPN connectivity confirmed: Fargate tasks can reach `10.155.0.152/32` and
  `10.189.0.162/32`

**Effort:** 1 day
**Risk:** LOW for VPN (VPC-level, Fargate inherits same routing). HIGH risk window: if an EC2
worker is mid-job when Sidekiq is stopped, the job is requeued — confirm Sidekiq retry behavior
is acceptable.

---

### Phase 10: Decommission EC2 Resources

**Objective:** Remove EC2 instances, DNS records, and dead code after the observation window.

**Repos affected:** `terraform/`, `ansible/` (remove playbooks/vars for `app-atento-br`)

**Work:**
- `terraform destroy` of EC2 instances in `app-outbound-atento-br/` (previously declared via
  `modules/app` — now replaced by `modules/app_outbound`; the EC2 resources no longer exist
  in the new module, so `terraform apply` after Phase 3 would have already planned their
  destruction — confirm this at cutover)
- Delete Route53 internal DNS records `4client-out-atento-br-app00N.*` (destroyed automatically
  when EC2s go away, if records are managed by Terraform)
- Remove Ansible inventory entries and playbooks for `app-atento-br` workers
- Remove Capistrano deploy config for `app-atento-br`
- Audit `modules/app` for remaining `enable_vpn` consumers; remove the VPN path if no other
  stack uses it

**Dependencies:** Phase 9 complete (EC2s idle for observation window)

**Success Criteria:**
- [ ] All 5 EC2 instances terminated; cost dashboard shows t3.small charges gone
- [ ] No `4client-out-atento-br-*` Name tags remain in AWS console
- [ ] `modules/app` either cleaned of VPN dead code or documented as still needed by another
  stack
- [ ] Ansible and Capistrano configs for `app-atento-br` removed

**Effort:** 0.5 day
**Risk:** LOW — instances are already idle; Terraform destroy is isolated to EC2 resources only.

---

## Per-Repo Scope Summary

| Repo | Work |
|------|------|
| `terraform/` | Phase 2: networking rename; Phase 3: `modules/app_outbound` + stack rename + state migration; Phase 5a: ECR sa-east-1 repo; Phase 7a: new `modules/atento_001_task_config`; Phase 7b: refactor `app-atento-001/compute.tf` to consume module; Phase 7c: refactor 5 stacks (`app-beta-001`, `app-demo-001`, `app-shared-001`, `app-atento-001`, `onboarding`) to reference `4shark-lambda-artifacts-us-east-1`; Phase 7d: compute stack (ECS + Lambda + IAM) referencing `4shark-lambda-artifacts-sa-east-1`; Phase 8.5: bump `worker_payroll_autoscaling` `s3_key` to v0.10.0 artifact; Phase 10: EC2 destroy |
| `lambda/` | Phase 4: new `worker-payroll-autoscaling` Lambda (Fargate-native variant of `worker-autoscaling`); Phase 7c: update `bin/publish_lambdas` to dual-push to `4shark-lambda-artifacts-us-east-1` and `4shark-lambda-artifacts-sa-east-1`; update `RELEASE.md`; Phase 8.5: refactor `worker-payroll-autoscaling` to binary scale (v0.10.0) — scale-up jumps to `MAXIMUM_CAPACITY`, scale-down hysteresis preserved |
| `app/` | Phase 5b: `build-image.yaml` dual-push; Phase 6: HireFire dyno; Phase 8: new reusable `deploy-payroll-worker.yaml` + sibling jobs (`deploy-payroll`, `deploy-runner-payroll`) in `deploy-atento-001.yaml` + cross-track rollback; trigger stays manual |
| `ansible/` | Phase 10: remove `app-atento-br` inventory and playbooks |

---

## Technical Decisions

All decisions are closed (SPIKE Decisions #1–#8). Recorded here for reference:

| Decision | Choice | Source |
|----------|--------|--------|
| Stack naming | `app-outbound-atento-br` | SPIKE Decision #1 |
| Module naming | `modules/app_outbound` | SPIKE Decision #2 |
| Launch type | Fargate with scale-to-zero | SPIKE Decision #3 |
| Image source | Dual-push from `build-image.yaml` to sa-east-1 ECR | SPIKE Decision #4 |
| Deploy workflow | Sibling jobs in `deploy-atento-001.yaml` (main-app + payroll worker + payroll runner) calling new reusable `deploy-payroll-worker.yaml`; single GitHub environment `atento-001` for all tracks; trigger stays manual (`workflow_dispatch`); cross-track rollback prevents version drift; other env workflows untouched | SPIKE Decision #5 (revised twice: matrix → sibling during PLAN review; auto-trigger removed during execution) |
| Task sizing | 5 tasks × 2048 CPU / 2048 MB | SPIKE Decision #6 |
| Autoscaling pattern | Queue-depth Lambda (Fargate-native variant of `worker-autoscaling`) | SPIKE Decision #7 |
| IAM | Reuse `ecsTaskExecutionRole` for tasks; new execution role for Lambda scoped to outbound service ARN | SPIKE Decision #8 |

---

## Effort Estimate

| Phase | Effort | Notes |
|-------|--------|-------|
| 0 — Source-of-Truth Inventory | 0.5 day (done) | Read code + deployed Lambdas; no SSH |
| 1 — Lambda Reference Read | 0.5 day | Read + document ASG-vs-Fargate delta |
| 2 — Networking Rename | 1 day | `moved` blocks + tag updates + SSM recreate |
| 3 — `modules/app_outbound` + Stack Rename | 2–3 days | New module + state migration + `main.tf` swap |
| 4 — Fargate Autoscaling Lambda | 1 day | Copy + remove ASG calls + package + upload |
| 5 — ECR Dual-Push | 0.5 day | Terraform ECR repo + `build-image.yaml` extension |
| 6 — HireFire Dyno Registration | 0.5 day | Add `worker_payroll_tiger_shark` dyno to hire_fire.rb |
| 7a — Create `modules/atento_001_task_config` | 0.5 day (done) | New pure-data module; no AWS resources |
| 7b — Refactor `app-atento-001/compute.tf` | 0.5 day (done) | Zero resource changes; apply confirmed |
| 7c — Lambda artifact bucket migration | 2.25 days | Bucket creation (0.5d) + sync + verify (0.25d) + `publish_lambdas` refactor + test (0.5d) + 5 stacks refactor + plans (1d) |
| 7d — Wire `app-outbound-atento-br` | 2 days | Cluster + service + task def + Lambda wiring + IAM; first cross-region SSM read validation |
| 7e — Delete legacy bucket | 0.25 day | Grep verification + bucket deletion |
| 8 — Deploy Workflow (sibling + reusable) | ✅ done (~3 days actual) | Reusable `deploy-payroll-worker.yaml` + sibling jobs in `deploy-atento-001.yaml` + cross-track rollback. Trigger stays manual. |
| 8.5 — Lambda binary-scale refactor | ✅ done (~0.5 day actual) | Lambda v0.10.0 (lambda#53 + lambda#54 release tag) + Terraform `s3_key` bump (terraform#394). Validation deferred to 2026-05-14 |
| 9 — Cutover | 1 day | Scale ECS up; stop EC2 Sidekiq; observe |
| 10 — Decommission | 0.5 day | Destroy EC2s; clean DNS + Ansible + Capistrano |
| Buffer | 2–3 days | |
| **Total** | **~3–4 weeks** | Assumes `modules/ecs_service` Fargate support already merged from integrator work. Add +1 week if not. |

**Note on Lambda effort vs SPIKE estimate:** The SPIKE did not account for the ASG-removal
adaptation in the Lambda (the SPIKE assumed the existing Lambda pattern applied directly). Phase 1
(0.5 day) + Phase 4 (1 day) add 1.5 days vs the SPIKE's implicit assumption.

**Note on Phase 7 effort vs previous estimate:** The original Phase 7 estimate (3–4 days) covered
only the shared module + refactor + single wiring. Phase 7c (bucket migration) adds 2.25 days for
bucket creation, sync verification, publish script update, and 5-stack refactor. Phase 7e (legacy
cleanup) adds 0.25 day. Total Phase 7 is now ~5–6 days vs the original 3–4 days.

---

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| EC2 env vars drift / unknown | Resolved | Not needed — task env vars cloned from `app-atento-001/compute.tf` `locals.env_vars` (same Rails image, same config). EC2 runtime state is discarded at cutover. |
| Sidekiq queue name / isolation | Resolved | Phase 0 confirmed queue is `payroll_tiger_shark`, only `config/sidekiq_payroll_tiger_shark.yml` listens on it; no cross-listen from any other Sidekiq config |
| HireFire dyno not registered for payroll | High | Phase 6 adds the dyno block in `config/initializers/hire_fire.rb`. Phase 4/Phase 7 depend on this being deployed to atento-001 before the new Lambda can resolve `PROCESS_NAME`. |
| `modules/ecs_service` Fargate support not yet merged | Medium | Sequence Phase 7 after at least one integrator stack is live on Fargate; if not possible within deadline, inline Fargate config in `app-outbound-atento-br/compute.tf` as a one-off |
| `moved` blocks in Phase 3 trigger unintended destroy+create | Medium | Run `terraform plan` and review every line before applying; no `terraform apply` until plan is confirmed clean |
| Cross-region reachability (Redis + METRICS_ENDPOINT) from sa-east-1 Lambda | Resolved | REDIS_URL is Redis Cloud public endpoint (`redis-19904.c263.us-east-1-2.ec2.redns.redis-cloud.com`), not AWS VPC-scoped. METRICS_ENDPOINT is public HTTPS (`atento001.app4shark.com`). Both reachable from any region without special networking — confirmed via `aws lambda get-function-configuration` on atento-001 Lambdas. |
| Version drift between main-app and payroll deploys | Resolved | Sibling jobs in `deploy-atento-001.yaml` run in the same workflow invocation; cross-track rollback (`rollback-main-on-payroll-failure`, `rollback-payroll-on-main-failure`) ensures both tracks land on the same code revision or both roll back |
| Sibling-job refactor breaks existing atento-001 deploy | Resolved | Existing main-app jobs were left untouched; payroll added as additional siblings. 5 consecutive successful deploys through 2026-04-30 confirm stability |
| Phase 7b refactor breaks `app-atento-001` deploy | High | Replacing inline locals in a live production stack carries regression risk. Mitigation: `terraform plan` must show zero resource changes before apply; apply is gated on plan review. Roll back by reverting the module call and restoring inline literals if any change is detected. |
| Lambda artifact bucket migration breaks existing stacks (7c) | High | Refactoring 5 live stacks to reference a new S3 bucket name could cause `data "aws_s3_object"` to fail if the artifact is missing from the new bucket. Mitigation: `aws s3 ls` verification of both new buckets after sync, before any `terraform plan` is run; each stack plan must show zero resource changes (refactor-only gate) before apply. |
| `aws s3 sync` incomplete leaves artifacts missing in one of the new buckets (7c) | Medium | If the sync is interrupted or partially applied, the new bucket will have missing keys and Terraform plans or Lambda deploys will fail. Mitigation: run `aws s3 ls s3://4shark-lambda-artifacts-{region} --recursive` and compare object count against the legacy bucket before proceeding to step 5 of 7c. |
| VPN connectivity from Fargate tasks | Low | VPN is VPC-level; Fargate tasks in the private subnet inherit the same routing as EC2s today |
| Deadline 2026-05-14 | Medium | Critical path: Phase 0 → Phase 1 → Phase 3 → Phase 7; Phases 2, 4, 5, 6 can proceed in parallel on separate tracks |

---

## Assumptions

- `modules/ecs_service` Fargate support will be available before Phase 7 (either from the
  integrator migration or inlined as a one-off)
- The shared Redis and `METRICS_ENDPOINT` used by `app-atento-001` are reachable cross-region
  from the sa-east-1 Lambda (consistent with the outbound Fargate tasks, which also consume
  from the shared Redis in sa-east-1)
- The 5 EC2s are accessible via SSH for inventory (Phase 0)
- The `ecsTaskExecutionRole` IAM role already exists globally (confirmed in
  `app-atento-001/compute.tf:125`)
- The site-to-site VPN (customer gateway `177.22.252.45`, target networks `10.155.0.152/32` and `10.189.0.162/32`) will remain operational throughout the migration; no VPN
  changes are in scope
- The monthly execution window for FPW egress is coordinated by the business; the team
  will be notified when the next window opens for cutover scheduling

---

**Status:** ✅ MIGRATION COMPLETE (2026-05-05). All phases (0–10) delivered. Atento BR payroll now runs entirely on ECS Fargate in sa-east-1 with binary-scale Lambda autoscaling (`worker-payroll-autoscaling` v0.10.0). 5 legacy t3.small EC2 instances terminated. Deprecated networking SSMs/outputs cleaned up. Validation against real FPW production traffic deferred to 2026-05-14 alongside the client integration test. Out-of-scope follow-ups: Ansible/Capistrano cleanup, `modules/app` `enable_vpn` audit, `out_atento_br_vpc_id` output state-cleanup (auto-syncs on next clean networking apply post-magnatech-resolution).

> Next step: use `@agent-task-creator` to create TASKS.md.
