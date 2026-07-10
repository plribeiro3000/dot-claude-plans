<!-- Auxiliary data file for SPIKE.md — manual-integrator-run-skill -->
<!-- Raw per-client Terraform findings gathered during research. Referenced from SPIKE.md Finding 6. -->

# Per-client Terraform automation state (integrator stacks)

Gathered by grep across `~/Projects/4Shark/terraform/integrator-*/compute*.tf` on 2026-07-09. Each row cites the exact file the numbers came from.

## almaviva — `terraform/integrator-almaviva/compute.tf`

- `AWS_INSTANCE_IDS = "${aws_instance.mongo003.id};${aws_instance.mongo004.id};${aws_instance.mongo005.id}"` (line 9) — dedicated Mongo EC2 trio
- `module "web"` → `desired_count = 1` (line 136)
- `module "worker"` → `desired_count = 2` (line 176)
- `module "runner"` → `desired_count = 0` (line 211, always — exists only to provide network config for `ecs run-task`)
- `aws_scheduler_schedule.start_mongodb` — `cron(50 0 * * ? *)` UTC, target `ec2:startInstances` on the three mongo instance IDs (lines 287–311)
- `aws_scheduler_schedule.scale_up_web` — `cron(55 0 * * ? *)` UTC, target `ecs:updateService` with `DesiredCount = 1` (lines 317–339)
- `aws_scheduler_schedule.scale_up_worker` — `cron(55 0 * * ? *)` UTC, target `ecs:updateService` with `DesiredCount = 2` (lines 341–363)
- `module "scheduled_task"` (ecs_scheduled_task) — runs `bin/rails integration:cron` at `cron(0 1 * * ? *)` UTC (lines 369–396)

Sequence: Mongo starts at 00:50 UTC → web/worker scale up at 00:55 UTC → `integration:cron` fires at 01:00 UTC (5 min after scale-up, giving Fargate tasks time to reach RUNNING/healthy).

## redebrasil — `terraform/integrator-redebrasil/compute.tf`

- `AWS_INSTANCE_IDS` — dedicated Mongo EC2 trio (line 9, same shape as almaviva)
- `module "web"` → `desired_count = 1` (line 135)
- `module "worker"` → `desired_count = 1` (line 175) — differs from almaviva's worker count of 2
- `start_mongodb` — `cron(50 1 * * ? *)` UTC (line 291)
- `scale_up_web` / `scale_up_worker` — `cron(55 1 * * ? *)` UTC (lines 321, 345)
- `integration:cron` scheduled task — `cron(0 2 * * ? *)` UTC (line 377)
- Additionally has a SECOND set of schedules — `extra_scale_up_web`, `extra_scale_up_worker`, `extra_start_mongodb` — firing on `cron(55 17 20-27 * ? *)` / `cron(50 17 20-27 * ? *)` UTC, i.e. only on days 20–27 of the month (lines 401–484). A second `integration:cron` fires at `cron(0 18 20-27 * ? *)` (line 484). This is a client with TWO distinct processing windows per month, each potentially with its own desired-count intent (not verified whether the extra schedules use different DesiredCount values than the primary ones — not read in this pass).

## commcenter — `terraform/integrator-commcenter/compute.tf` (production) + `compute_staging.tf`

Production:
- `AWS_INSTANCE_IDS = ""` (line 9) — no dedicated Mongo EC2 for commcenter (uses a different persistence layer or a Mongo not modeled as a stoppable EC2 the app self-manages)
- `module "web_prod"` → `desired_count = 1` (line 88)
- `module "worker_prod"` → `desired_count = 1` (line 128)
- `module "runner_prod"` → `desired_count = 0` (line 159)
- `scheduled_task_start_mongodb` module present (line 183) despite empty `AWS_INSTANCE_IDS` — not read in this pass whether it targets a different resource; flagged as needing follow-up if commcenter is chosen as the first client to wire into the skill
- `prod_scale_up_web` / `prod_scale_up_worker` — `cron(55 3 * * ? *)` UTC (lines 217, 241)
- `integration:cron` scheduled task — `cron(0 4 * * ? *)` UTC (line 269)

Staging (`compute_staging.tf`):
- `AWS_INSTANCE_IDS = ""` (line 9)
- `RAILS_ENV = "production"` (line 37) — staging still runs the Rails app in the `production` Rails environment; only `ENVIRONMENT`/infra naming distinguishes it
- `desired_count = 0` for web, worker, and runner (lines 88, 128, 159) and NO scheduler resources — confirms staging is on-demand only, matching `environments.json`'s `"deploy_policy": "Non-productive — runs on-demand (desired_count=0, no schedules), free to deploy."`

## maqnelson — `terraform/integrator-maqnelson/compute.tf`

- `AWS_INSTANCE_IDS` — dedicated Mongo EC2 trio (line 9)
- `module "web"` → `desired_count = 1` (line 136)
- `module "worker"` → `desired_count = 2` (line 176)
- `start_mongodb` — `cron(20 1 * * ? *)` UTC (line 292)
- `scale_up_web` / `scale_up_worker` — `cron(25 1 * * ? *)` UTC (lines 322, 346)
- `integration:cron` scheduled task — `cron(30 1 * * ? *)` UTC (line 378)

## atento (BR / MX / CO / CL) — `terraform/integrator-atento/compute_{br,mx,co,cl}.tf` + `mongodb.tf`

- Every country sub-stack has `AWS_INSTANCE_IDS = ""` (compute_br.tf, compute_mx.tf, compute_co.tf, compute_cl.tf, all line 9) — none of the four countries wires the shared Mongo replica set through `AWS_INSTANCE_IDS`, so `Ec2.stop_machine` (integrator app model) always no-ops for every Atento country (`return if ApplicationConfiguration.aws_instance_ids.blank?`, `integrator/app/models/ec2.rb:9`)
- `mongodb.tf` defines a SINGLE shared Mongo replica set (`aws_instance.mongo003/004/005`) reused by all four countries (per `environments.json`: `"multi-country single stack: BR/MX/CO/CL share one VPC, VPN, MongoDB replica set"`) — no start/stop schedule was found for this shared Mongo in the grep pass, consistent with it staying up continuously rather than following the almaviva/redebrasil/maqnelson stop-when-idle pattern
- BR: `desired_count = 1` / `1` / `0` (web/worker/runner, lines 88/128/159); `br_scale_up_web` / `br_scale_up_worker` at `cron(55 1 * * ? *)` UTC; `integration:cron`-equivalent scheduled task at `cron(0 2 * * ? *)` UTC (line 237)
- MX: `desired_count = 1` / `1` / `0` (lines 89/129/160); `mx_scale_up_web` / `mx_scale_up_worker` present (lines 181, 205) — this is the harvester-fed country, so its own `integration:cron`-equivalent trigger is chained after the harvester, not read in this pass
- CO: `desired_count = 1` / `1` / `0` (lines 89/129/160); `co_scale_up_web` / `co_scale_up_worker` present (lines 181, 205)
- CL: `desired_count = 0` / `0` / `0` for web/worker/runner (lines 89/129/160) even though `cl_scale_up_web` / `cl_scale_up_worker` scheduler resources exist (lines 181, 205) — the Terraform-declared resting state is 0, and the schedule presumably scales it up to some value at run time (the schedule's own `DesiredCount` payload was not read in this pass — flagged as a gap)

## Cross-cutting observations

1. **Terraform `desired_count` is not always a single, unambiguous "the pattern" value** — redebrasil has two independent schedule pairs (primary + a days-20–27-of-month "extra" pair) that may carry different `DesiredCount` payloads; this was not fully resolved (see `extra_scale_up_web`/`extra_scale_up_worker` above).
2. **`AWS_INSTANCE_IDS` (and therefore whether a client's Mongo is a stoppable EC2 at all) is entirely absent for commcenter and all four Atento countries** — a skill deriving "does this client need a Mongo raised" cannot assume every integrator has one; must branch on whether `AWS_INSTANCE_IDS`/the EC2-instances tag lookup returns anything.
3. **No AWS tag on the ECS service itself carries the "normal" desired count** — confirmed by reading `terraform/modules/ecs_service/main.tf:75-79` (the `aws_ecs_service` resource sets `desired_count = var.desired_count` directly, and the module's `tags = var.tags` block is a separate, unrelated tag map). The only two places the "normal" count is recorded are (a) the Terraform HCL literal, and (b) the mirrored `DesiredCount` value inside the `aws_scheduler_schedule` target's `input` JSON, which IS independently readable via `aws scheduler get-schedule` without touching Terraform.
