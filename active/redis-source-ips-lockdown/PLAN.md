# PLAN — Redis Cloud `source_ips` lockdown

## Objective

Restrict the `source_ips` allowlist of every environment's Redis Cloud lock database to 4Shark-controlled addresses. Today the allowlist must stay open because four autoscaling Lambdas, the GitHub deploy workflows, and the engineer's pre-deploy queue check all connect from outside the VPC. The work brings every connector onto the VPC NAT gateway's Elastic IP, or removes it, and only then closes the allowlist.

## Scope

### In scope

- `vpc_config` on the `lambda-ecs-autoscaling` Terraform module and the security group / subnet wiring it needs
- Replacing the nine `redis-cli` lock operations in the deploy workflows with an in-VPC mechanism
- A path for `sidekiq-queue-check.sh` that does not connect to Redis Cloud from the engineer's workstation
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

### Phase 1: Lambdas into the VPC

**Objective:** every autoscaling Lambda reaches Redis Cloud from the environment's NAT Elastic IP.

**Components:**
- `terraform/modules/lambda-ecs-autoscaling`: accept subnet ids and security group ids, declare `vpc_config`
- `terraform/modules/app/lambda.tf`: source the private subnets and a security group from the networking data the module already consumes
- Security group: egress only, to the Redis Cloud endpoint and to the AWS APIs the functions call

**Dependencies:** none — this is the entry point.

**Success criteria:**
- [x] Every function in every environment reports its VPC config — applied to all six stacks
- [ ] A scale-up and a scale-down observed working per environment after the change
- [ ] The NAT Elastic IP observed as the source in the Redis Cloud connection log

**Applied:** `beta-001`, `demo-001`, `shared-001`, `atento-001` (4 added / 3–4 changed each, 0 destroyed) and `app-outbound-maqnelson`, `app-outbound-atento-br` (2 added / 1 changed each). The outbound stacks share the tasks' network rather than getting a group of their own, matching the shape that module already used for its ECS services.

**The address each environment's allowlist will name** — read from the subnet's default route, so it is the path rather than an observation:

| Environment | NAT gateway | Elastic IP |
|---|---|---|
| `beta-001` | `nat-0dd543c42d8c99a7c` | `44.206.32.159` |

**An MFA session that expires mid-apply leaves the state behind, not the infrastructure.** The `atento-br` apply lost its token while waiting on the Lambda update: AWS had already applied every change, but Terraform could not persist and wrote `errored.tfstate`. Recovery is `force-unlock` on the stale lock then `state push errored.tfstate` — never a re-apply, which forks the state. Confirm first that the local state carries the same `lineage` and a higher `serial` than the remote, and that its resource set is a superset; a `plan` afterwards returning `No changes` is what closes it. Each Lambda takes ~4 minutes to update, so a six-stack pass needs more session than the one-hour default leaves.

**Note on cold start:** the VPC penalty is not the historical ENI attachment. The interface is created when the function is created or its VPC settings change, and *"the execution environment simply uses the pre-created network interface"* ([AWS Compute Blog](https://aws.amazon.com/blogs/compute/announcing-improved-vpc-networking-for-aws-lambda-functions/)). Verify against the invocation duration metric rather than assuming it either way.

### Phase 2: Workflow lock operations move in-VPC

**Objective:** no GitHub runner connects to Redis Cloud.

**Components:**
- A Lambda in the VPC exposing the lock operations the workflows need (acquire with `NX EX`, force-set, release, read for logging)
- The nine call sites across `deploy-*.yaml` replaced with `aws lambda invoke`, using the AWS credentials the runner already carries
- The `Install redis-cli` steps removed, along with the Azure-mirror `apt-get` workaround they carry

**Dependencies:** Phase 1 — the in-VPC networking has to exist first.

**Success criteria:**
- [ ] A full deploy on `beta-001` completes with no `redis-cli` on any runner
- [ ] The failure paths exercised: a deliberately failed migration still sets the permanent lock, and `cleanup-on-failure` still releases it
- [ ] Deploy wall-clock not materially longer than before

### Phase 3: The pre-deploy queue check

**Objective:** `sidekiq-queue-check.sh` stops connecting to Redis Cloud from the engineer's workstation.

**Components:**
- Queue depth and busy count served from inside the VPC — the app already holds both and already talks to Redis
- `~/.claude/scripts/sidekiq-queue-check.sh` reads that instead of `redis-cli`, keeping its GO/HOLD contract and the marker file `validate-productive-deploy.sh` gates on

**Dependencies:** independent of Phases 1 and 2; blocking for Phase 4.

**Success criteria:**
- [ ] The check returns GO and HOLD correctly against a known queue state
- [ ] `validate-productive-deploy.sh` still blocks a productive deploy with no recent GO
- [ ] `redis-cli` no longer required on an engineer's machine

### Phase 4: Close `source_ips`

**Objective:** the allowlist carries only 4Shark-controlled addresses.

**Components:**
- Per environment, `source_ips` narrowed to that environment's NAT Elastic IP
- Rollout follows the zero-downtime ladder: `beta-001` → `demo-001` → `shared-001` → `atento-001`

**Dependencies:** Phases 1, 2 and 3 complete for the environment being closed.

**Success criteria:**
- [ ] Autoscaling still scales up and down after the allowlist narrows
- [ ] A deploy completes end to end
- [ ] The pre-deploy check still returns GO

## Technical decisions

| Decision | Choice | Rationale |
|---|---|---|
| Where the lock lives | Stays in Redis | Moving it means changing 4 Lambdas plus 5 workflows and does not reach the goal — the Lambdas would still be outside the VPC for `ecs_scaling:empty_checks` and `ecs_scaling:jobs_in_queue` |
| If it were moved, which store | DynamoDB, never SSM Parameter Store | The balancing Lambda's `SET NX` is atomic conditional write. Parameter Store has no equivalent. Recorded so the option is not re-proposed with the wrong store |
| Mechanism for the workflow's lock calls | Lambda invocation | An ephemeral ECS task measures ~4 minutes to start; nine of them per deploy is not viable. A Lambda answers in sub-second and Phase 1 puts one in the VPC anyway |
| Sidekiq quiet job | Unchanged | It never connected to Redis — `aws ecs execute-command` delivers the signal inside the container |
| Rollout order | `beta-001` → `demo-001` → `shared-001` → `atento-001` | The standing ladder; a wrong allowlist stops autoscaling, so the learning happens where it is cheap |

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| A wrong security group or allowlist stops the Lambdas from reaching Redis; autoscaling silently stops resizing | High | The ladder; verify a scale-up and a scale-down per environment before advancing |
| NAT gateway data-processing charges rise once Lambda traffic routes through it | Low | Per-minute lock reads are small; watch the NAT metric after `beta-001` |
| Phase 1 collides with the ASG ↔ ECS coordination work, which also edits these Lambdas and this module | Medium | Sequence deliberately with `active/worker-autoscaling-coordination/PLAN.md`; do not run both in flight |
| The lock TTL stops being a safety net if the mechanism changes semantics | High | Phase 2 keeps `SET NX EX` and `DEL` exactly as they are — the Lambda only relocates where the command runs from |

## Assumptions

- Each environment's Redis Cloud database supports a `source_ips` allowlist that can carry the NAT Elastic IP. Confirm against `terraform/modules/redis_cloud/` before Phase 4.
- Every app VPC has a NAT gateway with a fixed Elastic IP, matching the `shared-001` shape. Verified for `shared-001`; confirm per environment.
- `app-outbound-maqnelson` (`sa-east-1`) reaches its own Redis and needs its own pass through these phases.
