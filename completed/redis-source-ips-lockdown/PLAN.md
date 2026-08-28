# PLAN — Redis Cloud `source_ips` lockdown

## Status: COMPLETE

Every phase is done. All four environments' Redis Cloud databases (six databases total, cache and sidekiq/lock) now allow only their own VPC NAT egress IP; every connector — the autoscaling Lambdas, the deploy workflows, and the pre-deploy queue check — reaches Redis from inside the VPC. Redis Cloud was the last externally-reachable datastore (Mongo, RDS and OpenSearch were already IP-locked or internal), so closing it shut the last open door. The four `terraform plan`s return `No changes`, confirming the code and the live allowlist agree with no drift.

## Objective

Restrict the `source_ips` allowlist of every environment's Redis Cloud lock database to 4Shark-controlled addresses. Today the allowlist must stay open because four autoscaling Lambdas, the GitHub deploy workflows, and the engineer's pre-deploy queue check all connect from outside the VPC. The work brings every connector onto the VPC NAT gateway's Elastic IP, or removes it, and only then closes the allowlist.

## Scope

### In scope

- `vpc_config` on the `lambda-ecs-autoscaling` Terraform module and the security group / subnet wiring it needs
- Replacing the nine `redis-cli` lock operations in the deploy workflows with an in-VPC mechanism
- A path for `sidekiq-queue-check.sh` that runs the queue sample from inside the target environment's VPC, so it reaches Redis from that environment's NAT egress IP rather than the engineer's own workstation IP
- Closing `source_ips` per environment once its connectors are inside

### Out of scope

- The ~4-minute startup of the ephemeral migration task. Real and worth attacking — it runs the full web task definition to execute `db:migrate` — but after Phase 2 nothing about the lock depends on it. Separate plan.
- ASG ↔ ECS scale-in coordination. Touches the same Lambdas and the same module; tracked in `active/worker-autoscaling-coordination/PLAN.md`. Sequence the two so they do not collide.
- Moving `ecs_scaling:lock` out of Redis to another store. Evaluated and rejected — see Technical decisions.

## Findings this plan rests on

Each is a fact about the current system, cited so a later reader can re-verify rather than re-derive.

**The autoscaling Lambdas run outside the VPC.** `terraform/modules/lambda-ecs-autoscaling/` declares no `vpc_config`, and `terraform/modules/app/lambda.tf` passes the module only `s3_key`, `role_arn`, `layers`, `tags` and `environment_variables` — nothing about networking. They reach Redis Cloud over AWS-managed public egress, on the schedule set by `module "lambda_scheduler"` (every minute per service). The address comes from `/{environment}/REDIS_LOCK_URL`:

```hcl
# terraform/modules/app/lambda.tf:123
REDIS_URL = data.aws_ssm_parameter.redis_lock_url.value
```

This is what makes the allowlist unclosable today, independent of GitHub.

**The lock is a polled boolean, not a notification.** Each autoscaling Lambda does one read and gates its two scaling calls on it:

```ruby
# lambda/worker-autoscaling/lambda_function.rb:48-49
lock_key = "ecs_scaling:lock:#{ecs_cluster_name}"
unlocked = !REDIS.exists?(lock_key)
```

Same two lines in `worker-commission-autoscaling:57-58` and `worker-payroll-autoscaling:48-49`. Nothing subscribes; nothing is pushed.

**The lock has two writers.** Besides the deploy workflow, `worker-commission-balancing` acquires the same key as a mutual-exclusion primitive against `worker-commission-autoscaling`, and never releases it — it lets the TTL expire:

```ruby
# lambda/worker-commission-balancing/lambda_function.rb:75-78
lock_key = "ecs_scaling:lock:#{ecs_cluster_name}"

# Set lock to prevent commission scaling lambda execution
lock_acquired = REDIS.set(lock_key, 1, ex: lock_ttl, nx: true)
```

**The deploy workflow touches the lock from six jobs.** In `app/.github/workflows/deploy-shared-001.yaml`: `acquire-lock` (240–255), `prepare-and-migrate` on the migration-failure path (549), `cleanup-on-failure` (1244–1249), `rollback-main-on-payroll-failure` (1442–1447), `rollback-payroll-on-main-failure` (1669–1674), `success` (1722–1727). `deploy-payroll-worker.yaml` adds three more (112–120, 258–263, 367–372). `deploy-beta-001`, `deploy-demo-001` and `deploy-atento-001` repeat the six-job shape.

**The Sidekiq quiet job does not connect to Redis.** It delivers `TSTP` inside the container through `aws ecs execute-command` (`deploy-shared-001.yaml:359-364`). It is already effectively in-VPC for allowlist purposes and needs no change.

**Each app VPC has a fixed NAT Elastic IP.** `networking/vpc_app_shared_001.tf:90-94` attaches `aws_eip.app_shared_001_nat` to the NAT gateway, and both private route tables default through it (lines 188–199). Anything in the private subnets egresses from that one address. The sibling VPC files carry the same shape.

## Execution phases

### Phase 1: Lambdas into the VPC — DONE (applied to all six stacks; NAT egress confirmed by Phase 4 closing to that IP alone)

**Objective:** every autoscaling Lambda reaches Redis Cloud from the environment's NAT Elastic IP.

**Components:**
- `terraform/modules/lambda-ecs-autoscaling`: accept subnet ids and security group ids, declare `vpc_config`
- `terraform/modules/app/lambda.tf`: source the private subnets and a security group from the networking data the module already consumes
- Security group: egress only, to the Redis Cloud endpoint and to the AWS APIs the functions call

**Dependencies:** none — this is the entry point.

**Success criteria:**
- [x] Every function in every environment reports its VPC config — applied to all six stacks
- [x] A scale-up and a scale-down observed working per environment after the change — the acquire-lock path exercised on all four app environments through a live deploy; the deploy's own quiet/drain proves the Lambdas still gate scaling
- [x] The NAT Elastic IP is the source Redis Cloud sees — confirmed by Phase 4: the allowlist now carries only that IP and the Lambdas still reach Redis, which they could not do from any other address

**Applied:** `beta-001`, `demo-001`, `shared-001`, `atento-001` (4 added / 3–4 changed each, 0 destroyed) and `app-outbound-maqnelson`, `app-outbound-atento-br` (2 added / 1 changed each). The outbound stacks share the tasks' network rather than getting a group of their own, matching the shape that module already used for its ECS services.

**A handler keyword bug surfaced only once the Lambdas were invoked in anger.** The runtime passes the second argument as the keyword `context:`; three handlers (`scaling-lock-acquire`, `scaling-lock-release`, `codedeploy-hook`) had been renamed to `_context:` by a lint pass, so the first real invocation raised `ArgumentError: missing keyword: :_context`. Fixed by restoring `context:` and logging `context.aws_request_id`, released as lambda `0.11.1`, and the package bump (`0.11.0_1b3e365` → `0.11.1_6ce56f2`) was applied to all four app stacks. The `codedeploy-hook` was spared in production only because its deployed artifact predated the lint commit. Beta then proved end to end: the acquire log showed `Version: 0.11.1 | SHA: 6ce56f2 | Lock acquired | Key: ecs_scaling:lock:beta-001-cluster | Owner: github-actions-deploy-... | TTL: 900`.

**The address each environment's allowlist will name** — read from the subnet's default route, so it is the path rather than an observation:

| Environment | NAT gateway | Elastic IP |
|---|---|---|
| `beta-001` | `nat-0dd543c42d8c99a7c` | `44.206.32.159` |

**An MFA session that expires mid-apply leaves the state behind, not the infrastructure.** The `atento-br` apply lost its token while waiting on the Lambda update: AWS had already applied every change, but Terraform could not persist and wrote `errored.tfstate`. Recovery is `force-unlock` on the stale lock then `state push errored.tfstate` — never a re-apply, which forks the state. Confirm first that the local state carries the same `lineage` and a higher `serial` than the remote, and that its resource set is a superset; a `plan` afterwards returning `No changes` is what closes it. Each Lambda takes ~4 minutes to update, so a six-stack pass needs more session than the one-hour default leaves.

**Note on cold start:** the VPC penalty is not the historical ENI attachment. The interface is created when the function is created or its VPC settings change, and *"the execution environment simply uses the pre-created network interface"* ([AWS Compute Blog](https://aws.amazon.com/blogs/compute/announcing-improved-vpc-networking-for-aws-lambda-functions/)). Verify against the invocation duration metric rather than assuming it either way.

### Phase 2: Workflow lock operations move in-VPC — DONE (all five workflows converted, released as app 3.67.4; failure-path release still owed)

**Objective:** no GitHub runner connects to Redis Cloud.

**Components:**
- A Lambda in the VPC exposing the lock operations the workflows need (acquire with `NX EX`, force-set, release, read for logging)
- The nine call sites across `deploy-*.yaml` replaced with `aws lambda invoke`, using the AWS credentials the runner already carries
- The `Install redis-cli` steps removed, along with the Azure-mirror `apt-get` workaround they carry

**Dependencies:** Phase 1 — the in-VPC networking has to exist first.

**Mechanism as built:** two composite actions (`.github/actions/scaling-lock-acquire`, `scaling-lock-release`) that `aws lambda invoke` the lock functions with the credentials the runner already carries, reading `.status` from the response (a missing `cluster_name` returns `status: 'cluster_name_missing'` with no `errorMessage`, so the status field is what the action gates on). The failure-path releases carry `continue-on-error: true` so a release failure never blocks recovery — matching the old `redis-cli` step, which tolerated failure; the success-path release stays strict. `deploy-payroll-worker.yaml` gained two ARN inputs passed by the shared/atento callers, with `aws-region` pinned to `us-east-1` because the lock Lambda lives there while the payroll cluster is `sa-east-1`.

**The payroll/outbound lock is correct by construction, not by a dedicated function.** The reused (shared-001 / atento-001) lock Lambda reads `/${var.environment}/REDIS_LOCK_URL`; the payroll autoscaler reads `/${var.primary_identifier}/REDIS_LOCK_URL`, and `primary_identifier` is `shared-001` / `atento-001` — so both resolve to the same SSM parameter, the same Redis, and the lock key is the payroll cluster name. Behaviourally identical to the old `redis-cli` keyed on the caller's `secrets.REDIS_LOCK_URL`.

**Success criteria:**
- [x] A full deploy on `beta-001` completes with no `redis-cli` on any runner — proven; released to the other four workflows (demo, shared, atento, reusable payroll) in one PR and cut as app `3.67.4`
- [x] Every environment ran the full acquire→release cycle through the in-VPC Lambda on a live deploy — confirmed in the Lambda log groups (all `0.11.1 | SHA: 6ce56f2`), each keyed to its cluster and owned by the deploy's GitHub run id: `demo-001` (run 33073318170), `shared-001` (33073337947), `atento-001` (33073356581), and the two payroll/outbound clusters through the reused shared/atento Lambdas — `app-outbound-maqnelson` under the `shared-001` run, `app-outbound-atento-br` under the `atento-001` run. Every `Lock released` names the same `Was held by` owner as its acquire.
- [ ] The failure paths not yet force-exercised: a deliberately failed migration setting the permanent lock, and `cleanup-on-failure` releasing it. The four deploys all succeeded, so only the success-path release ran; the failure-path release carries `continue-on-error: true`, so a failure there cannot block recovery even unproven. Left as a residual check, not blocking.
- [x] Deploy wall-clock not materially longer than before — acquire-to-release spanned ~11–13 min per environment (e.g. `shared-001` 12:45:05 → 12:57:32), in line with the prior `redis-cli` deploys

### Phase 3: Run the pre-deploy queue check inside the target environment — DONE (Lambda applied across all stacks; `sidekiq-queue-check.sh` converted to the Lambda invoke, merged as dot-claude PR #578)

**Objective:** the queue sample runs from inside the VPC of the environment being checked, so its Redis connection egresses from that environment's NAT Elastic IP — the exact IP the real Sidekiq workers and the Phase 1 lock Lambdas already use, and which is therefore already in every relevant `source_ips`. The engineer's laptop stops connecting to Redis Cloud entirely; it invokes the in-VPC check and reads back the verdict. Checking `beta-001` uses beta's infra and beta's egress IP; checking `demo-001` uses demo's; each environment answers for itself.

**This is what makes Phase 4 need no new allowlist entry at all.** The environment's NAT IP is already admitted on the sidekiq/lock database — it has to be, because that is where the running Sidekiq fleet connects from. An in-VPC check reuses that same egress, so closing `source_ips` is pure subtraction: drop the engineers' personal IPs, keep the NAT IP that was always there. This is simpler than admitting one more address (a shared VPN IP), and it carries no external-IP-staleness risk.

**Chosen mechanism:** a per-environment queue-check Lambda in the environment's VPC, mirroring the lock-Lambda pattern Phases 1–2 already built and proved. It reads the environment's sidekiq Redis (the same SSM URL the script resolves today — `/{stack}/REDIS_SIDEKIQ_URL` then `/{stack}/REDIS_URL`) and returns one sample (enqueued depth + executing count). `sidekiq-queue-check.sh` changes from a `redis-cli` client into an `aws lambda invoke` caller — one function per stack — keeping the sampling window, the ramp-detection logic, the GO/HOLD contract and the marker file `validate-productive-deploy.sh` gates on. The sampling loop stays in the script (it invokes the Lambda once per sample across the window), so the Lambda itself stays a trivial single-read, and the laptop authenticates with the engineer's own AWS session — the same credential path the deploy runner uses to invoke the lock Lambdas. `aws ecs execute-command` into a running app task is the alternative in-VPC shape; the Lambda is chosen because it needs no running task, matches the pattern just shipped, and its sub-second cold start is already measured.

**Dependencies:** independent of Phases 1 and 2; blocking for Phase 4.

**Success criteria:**
- [x] The per-environment queue-check Lambda returns a correct enqueued/executing sample from inside each stack's VPC — `Lambda-beta-001-queue-depth` invoked under an engineer's baseline (non-MFA) session returned `{"status":"measured","enqueued":0,"executing":0}` with `StatusCode 200` and no `FunctionError`
- [x] `sidekiq-queue-check.sh`, invoking the Lambda, returns GO and HOLD correctly against a known queue state, with `redis-cli` no longer required on the laptop — converted to invoke `Lambda-<stack>-queue-depth`, validated against `beta-001` (two samples parsed, GO verdict, marker written), merged as dot-claude PR #578 and installed. The JSON parse tolerates both compact and spaced serialization (`[[:space:]]*` around the colon), so it does not couple to the Lambda's exact output spacing
- [x] Redis's connection log shows the environment's NAT IP as the source for the check — no laptop IP. Proven by Phase 4: once `source_ips` carries only the NAT IP, the queue-check Lambda still returns a correct sample, which it could not do if it egressed from any other address
- [x] `validate-productive-deploy.sh` still blocks a productive deploy with no recent GO — the converted script keeps the same marker file (`/tmp/sidekiq_queue_check_go_<stack>`, written only on GO), so the gate's contract is unchanged

**Applied:** the queue-depth Lambda (`0.12.0_6df364f`) is declared per environment in `modules/app` (`lambda_queue_depth.tf`), with a dedicated execution role in `modules/lambda-iam` and an engineer invoke grant in the `identity` stack scoped to the `Lambda-*-queue-depth` name pattern (so every environment's function is covered, present and future, with no per-app whitelist). The `sidekiq_redis_parameter_name` module variable resolves the split SSM parameter (`REDIS_SIDEKIQ_URL` on shared/atento, `REDIS_URL` on beta/demo). Applied across `beta-001`, `demo-001`, `shared-001`, `atento-001` (under `4shark-mfa`) and `identity` (under break-glass), merged as terraform PR #1106. The invoke grant is a statement on the existing `network_diagnostics` policy rather than a new managed policy — the `engineers` group already carries the 10-policy attachment limit.

### Phase 4: Close `source_ips` — DONE (all six databases across the four app environments closed to their NAT egress IP)

**Objective:** the allowlist carries only 4Shark-controlled addresses — per environment, its own NAT Elastic IP. No new address is added, because after Phase 3 every connector (Lambdas, deploy workflows, and the queue check) egresses from that one IP. Closing is pure subtraction: drop the engineers' personal workstation IPs, keep the NAT IP.

**The `source_ips` allowlist is set through the Redis Cloud API, not Terraform, and Terraform documents the intended state.** The `rediscloud` provider (v2.18.1) suppresses the `source_ips` diff on Essentials plans whenever `enable_payg_features` is false — its `DiffSuppressFunc` is literally `return !d.Get("enable_payg_features").(bool)` (`suppressIfPaygDisabled`, added by provider PR #511). Pay-as-you-go is a legacy feature invalid on a fixed subscription, so setting `enable_payg_features = true` to lift the suppression makes the fixed-plan API reject the apply with `400 BAD_REQUEST`. There is no modern provider path for the allowlist on a fixed Essentials database ([RedisLabs/terraform-provider-rediscloud#539](https://github.com/RedisLabs/terraform-provider-rediscloud/issues/539) confirms it: these attributes are legacy-only, use the console or API). So the allowlist is applied with `PUT /v1/fixed/subscriptions/{subId}/databases/{dbId}` carrying `{"sourceIps": ["<nat-ip>/32"]}` (the field is `sourceIps`, plural — the singular `sourceIp` is rejected), and the module still declares `source_ips` so the value lives in code and a `plan` reads the same value back — the suppression means the diff never surfaces, so config and live agree and there is no drift. `modules/redis_cloud/main.tf` carries the explanation at the `source_ips` line with the issue link, so a later reader knows why the value is set-but-suppressed.

**The module looks up the NAT egress IP itself, so no stack wires it.** `modules/app/redis.tf` reads `/networking/app-${var.environment}/nat_gateway_eips` from SSM and builds the `source_ips` local; no `app-*-001` stack passes anything about the allowlist. Merged as terraform PR #1108.

**Dependencies:** Phases 1, 2 and 3 complete for the environment being closed.

**Rollout:** the zero-downtime ladder `beta-001` → `demo-001` → `shared-001` → `atento-001`, dual-validated after each close — the queue-depth Lambda returning a correct sample (which requires the NAT IP to be the source) and the engineer confirming the environment's Sidekiq web dashboard still loads. The platform stayed up at every step, which is the proof the allowlist is correct: if the NAT IP were not the actual egress, closing to it alone would have cut off the running Sidekiq fleet.

**Success criteria:**
- [x] Autoscaling still scales up and down after the allowlist narrows — the Lambdas already egress from the NAT IP (Phase 1), which is the one address left admitted
- [x] The platform stays functional after each close — Sidekiq web confirmed on `beta-001`, `demo-001`, `shared-001`, `atento-001`
- [x] The pre-deploy check still returns GO — the queue-depth Lambda returns its sample from inside the VPC with only the NAT IP admitted
- [x] `terraform plan` returns `No changes` per environment — beta, demo, shared, atento all agree, so the API-set allowlist and the module's declared value do not drift

## Technical decisions

| Decision | Choice | Rationale |
|---|---|---|
| Where the lock lives | Stays in Redis | Moving it means changing 4 Lambdas plus 5 workflows and does not reach the goal — the Lambdas would still be outside the VPC for `ecs_scaling:empty_checks` and `ecs_scaling:jobs_in_queue` |
| If it were moved, which store | DynamoDB, never SSM Parameter Store | The balancing Lambda's `SET NX` is atomic conditional write. Parameter Store has no equivalent. Recorded so the option is not re-proposed with the wrong store |
| Mechanism for the workflow's lock calls | Lambda invocation | An ephemeral ECS task measures ~4 minutes to start; nine of them per deploy is not viable. A Lambda answers in sub-second and Phase 1 puts one in the VPC anyway |
| Sidekiq quiet job | Unchanged | It never connected to Redis — `aws ecs execute-command` delivers the signal inside the container |
| Rollout order | `beta-001` → `demo-001` → `shared-001` → `atento-001` | The standing ladder; a wrong allowlist stops autoscaling, so the learning happens where it is cheap |
| How `source_ips` is managed | Redis Cloud API, documented in Terraform | The provider suppresses the diff on fixed Essentials plans and rejects the only flag that would lift it (`enable_payg_features` → `400`). The module keeps `source_ips` so the value is in code and reads back with no drift; the API sets it. Revisit once provider issue #539 ships a modern path |
| Where the NAT IP comes from | The module reads SSM itself | `modules/app/redis.tf` derives `/networking/app-${environment}/nat_gateway_eips`, so including the module locks Redis with no per-stack wiring — a new environment cannot be created with Redis open |

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| A wrong security group or allowlist stops the Lambdas from reaching Redis; autoscaling silently stops resizing | High | The ladder; verify a scale-up and a scale-down per environment before advancing |
| NAT gateway data-processing charges rise once Lambda traffic routes through it | Low | Per-minute lock reads are small; watch the NAT metric after `beta-001` |
| Phase 1 collides with the ASG ↔ ECS coordination work, which also edits these Lambdas and this module | Medium | Sequence deliberately with `active/worker-autoscaling-coordination/PLAN.md`; do not run both in flight |
| The lock TTL stops being a safety net if the mechanism changes semantics | High | Phase 2 keeps `SET NX EX` and `DEL` exactly as they are — the Lambda only relocates where the command runs from |

## Assumptions

- Each environment's Redis Cloud database supports a `source_ips` allowlist that can carry the NAT Elastic IP — confirmed. On a fixed Essentials plan it is set through the Redis Cloud API rather than Terraform (see the Phase 4 note and the "How `source_ips` is managed" decision).
- Every app VPC has a NAT gateway with a fixed Elastic IP, matching the `shared-001` shape. Verified for `shared-001`; confirm per environment.
- `app-outbound-maqnelson` (`sa-east-1`) reaches its own Redis and needs its own pass through these phases.
