# SPIKE — Manual Integrator Run Skill

## Investigation question

Today, when a client asks to run the integrator manually, the engineer opens a Claude session and manually raises the ECS services (Mongo, web, worker) and runs `bin/rails integration:start`, answering its interactive Y/n prompt by hand. The engineer wants this collapsed into a single 4Shark skill invocation ("the client asked to run integrator X") that: (1) derives the correct web/worker task counts for the client, (2) raises a client's Mongo EC2 instance if one exists, (3) scales up the web + worker ECS services, (4) triggers the rake task that prints the NUMBERS block, (5) captures those numbers and asks the engineer "these are the numbers, can I run?" WITHOUT accepting on the first pass, (6) on approval, re-invokes with a non-interactive accept, (7) compares a second numbers reading against the first and reports whether they diverged.

This spike enumerates every change needed across the three repos involved (`integrator`, `terraform`, `dot-claude`), surfaces the trade-offs where a design decision exists, and lists open decisions for the engineer. It does **not** design the final solution or write production code — that is the follow-up `PLAN.md`.

## Sources consulted

- `integrator/lib/tasks/integration.rake:1-169` — the two manual rake tasks (`start`, `force_start`), both interactive
- `integrator/app/services/throughput_calculator.rb:1-56` — `COLLECTIONS` constant and the NUMBERS computation
- `integrator/app/workers/job/starter.rb:1-71` — `Job::Starter`, the distributed lock, `skip_throughput` semantics
- `integrator/app/workers/throughput_processor.rb:1-27` — what `skip_throughput` actually gates
- `integrator/app/models/lock.rb:1-28` — the Redis `SETNX` lock backing `Job::Starter`
- `integrator/app/workers/shut_down_worker.rb:1-17` — production self-teardown (major finding, see Finding 5)
- `integrator/app/workers/resource/consumer.rb:1-39` — one of several callers of `ShutDownWorker.perform_async`
- `integrator/app/models/ec2.rb:1-14` and `integrator/app/models/ecs.rb:1-24` — the self-teardown mechanics
- `integrator/lib/application_configuration.rb:145-185` — `AWS_INSTANCE_IDS`, `AWS_ECS_ENVIRONMENT`-derived cluster/service names
- `integrator/bin/ecs:1-417` — the production ECS-exec helper (`connect`, `run`, `cleanup`)
- `integrator/.github/DEPLOY.md:1-54` — the deploy pipeline's PREFLIGHT step and its MongoDB-verify-only behavior
- `integrator/CHANGELOG.md:1-25` — changelog format for the integrator repo
- `terraform/integrator-almaviva/compute.tf:1-426` — read in full; the reference stack for the EventBridge-driven raise/lower pattern
- `terraform/integrator-redebrasil/compute.tf`, `terraform/integrator-commcenter/compute.tf` + `compute_staging.tf`, `terraform/integrator-maqnelson/compute.tf`, `terraform/integrator-atento/compute_{br,mx,co,cl}.tf` — grepped for `desired_count`, `AWS_INSTANCE_IDS`, `aws_scheduler_schedule`; full detail in the auxiliary file
- `terraform/modules/ecs_service/main.tf:75-79` — confirms `desired_count` is a live-mutable resource argument, not tag-exposed
- `~/.claude/skills/integrators/SKILL.md:1-133` — existing skill for scaling integrator ECS services
- `~/.claude/skills/integrators/environments.json:1-166` — per-client metadata (source model, VPN, productive flag)
- `~/.claude/skills/ec2-instances/SKILL.md:1-89` — existing skill for starting/stopping standalone EC2 (Mongo included)
- `~/.claude/skills/harvesters/SKILL.md:1-90` — sibling read-only skill, precedent for skill structure and the "one-off run is out of scope, done directly" convention
- `~/.claude/scripts/ecs-scale.sh:1-63` — the shared wrapper every scale-related skill already calls
- `https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-exec-run.html` — "Amazon ECS only supports initiating interactive sessions, so you must use the `--interactive` flag." (confirmed verbatim on fetch)
- `https://docs.aws.amazon.com/cli/latest/reference/ecs/execute-command.html` — confirms `--interactive | --non-interactive` is a required boolean flag at the CLI-syntax level (the developer guide text above is the operational constraint that matters — ECS itself does not support the non-interactive mode functionally, even though the flag exists in the CLI shape)
- See auxiliary: `manual-integrator-run-skill_terraform-desired-counts_1.md` — full per-client Terraform grep results (desired_count, AWS_INSTANCE_IDS, EventBridge schedules) that back Finding 6 and the cross-cutting observations

## Findings

### Finding 1: the interactive Y/n prompt is not just an inconvenience — it is a hard blocker for automation via Claude's Bash tool

**Evidence:**
```ruby
# integrator/lib/tasks/integration.rake:79-90 (task :start; task :force_start is byte-identical at lines 156-167)
puts "\n\nAre you sure you want to continue with integration? (Y/n)"
input = $stdin.gets.strip

case input.to_s.downcase
when 'y'
  Job::Starter.perform_async
  puts "\n\nStarted!"
when 'n'
  puts "\n\nAborted"
else
  puts "\n\nInvalid Option! Aborted"
end
```
And, on how the rake task would actually be invoked in production against a running container:
```bash
# integrator/bin/ecs:151-157 (cmd_connect — attach to a running web/worker task)
aws ecs execute-command \
  --cluster "$CLUSTER" \
  --task "$SELECTED_ARN" \
  --container "$CONTAINER" \
  --command "$COMMAND" \
  --interactive \
  --region "$AWS_REGION"
```
And AWS's own documentation on ECS Exec: *"Amazon ECS only supports initiating interactive sessions, so you must use the `--interactive` flag."* (https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-exec-run.html)

**Significance:** Claude's Bash tool has no pty and cannot supply interactive stdin to a foreground process. A command that calls `$stdin.gets` inside an ECS Exec session will hang until the Bash tool call times out, with no way for the skill to answer "Y" programmatically. This is true independent of AWS CLI's generic `--interactive|--non-interactive` flag syntax — AWS's own guide states ECS itself only supports the interactive shape. Combined, this means: the rake task as it exists today (`integration:start` / `integration:force_start`) **cannot** be driven by an automated skill at all, in either "read numbers" or "accept" mode, without a code change on the integrator side. This elevates the integrator-side rake-task change from "nice to have" to "structurally required for the skill to exist."

### Finding 2: the two existing rake tasks are near-identical copies, differing only in `skip_throughput`

**Evidence:**
```ruby
# integrator/lib/tasks/integration.rake:82-90 (task :start)
case input.to_s.downcase
when 'y'
  Job::Starter.perform_async
  puts "\n\nStarted!"
...

# integrator/lib/tasks/integration.rake:159-167 (task :force_start)
case input.to_s.downcase
when 'y'
  Job::Starter.perform_async(true)
  puts "\n\nStarted! (throughput validation skipped)"
```
```ruby
# integrator/app/workers/throughput_processor.rb:6-26
def perform(job_id)
  job = Job.find(job_id)

  if job.skip_throughput?
    Subsidiary::ExtractorProducer.perform_async(job_id)
    return
  end
  ...
  job_throughput = ThroughputCalculator.call(job_id: job.id)

  if job_throughput > job.metric.ceiling
    HighThroughputReport::Producer.perform_async(job_id, job_throughput)
  else
    Subsidiary::ExtractorProducer.perform_async(job_id)
  end
end
```
**Significance:** `force_start` does not skip the interactive prompt or make the run itself non-interactive — the word "force" refers only to skipping a downstream safety check (`ThroughputProcessor`) that would otherwise halt the pipeline and email a `HighThroughputReport` if the computed record-change volume (`ThroughputCalculator`) exceeds `job.metric.ceiling` (a per-job computed ceiling, distinct from the `MINIMUM_THROUGHPUT` env var). Both tasks share the exact same SOURCES + NUMBERS + prompt block, copy-pasted. Any rake-task change the skill needs (numbers-only mode, non-interactive accept) has to be decided for *both* tasks, or the design has to pick which of the two the skill drives — this is Open Decision 5 below.

### Finding 3: `Job::Starter` is protected by a Redis lock with no TTL — a second invocation while one is in-flight silently no-ops

**Evidence:**
```ruby
# integrator/app/workers/job/starter.rb:7-13
def perform(skip_throughput = false)
  MetricIncrementor.perform_async('integrator.process.count', Time.zone.now.strftime('%Y-%m-%d %H:%M:%S'))

  if Lock.acquire(LOCK_KEY)
    if Stream.none?
      MissingStreamsReport::Producer.perform_async
      return
```
```ruby
# integrator/app/models/lock.rb:4-23 (Lock.acquire — SETNX, no expiry unless a TTL is passed)
def self.acquire(lock_key, lock_ttl = nil)
  Sidekiq.redis_pool.with do |connection|
    if lock_ttl.present?
      connection.call('set', "lock:#{lock_key}", 'true', nx: true, ex: lock_ttl)
    else
      connection.call('set', "lock:#{lock_key}", 'true', nx: true)
    end
  end
end
```
`Job::Starter.perform(skip_throughput = false)` calls `Lock.acquire(LOCK_KEY)` with no TTL argument, so the lock is only released in the `ensure` block (`Lock.delete(LOCK_KEY)`, line 68) once the method returns.

**Significance:** if a job is already running (e.g. the nightly `integration:cron` fired independently, or the engineer's skill races with itself), the accept-mode invocation will NOT error — `Job::Starter.perform_async` enqueues fine, but inside `perform`, `Lock.acquire` returns falsy and the whole body (including `Job.start`) is skipped silently; only `MetricIncrementor` fires. The rake task's "Started!" message would print regardless (it does not check the lock's outcome), which is a latent misleading-output risk independent of this skill. Relevant to Open Decision 6 (double-invocation handling) and to why the second numbers-reading comparison matters — if a job silently didn't start, comparing before/after numbers would show no divergence yet nothing is actually running.

### Finding 4: `ThroughputCalculator::COLLECTIONS` is the exact NUMBERS content — 14 named collections, each counted since the job's `fetch_since` watermark

**Evidence:**
```ruby
# integrator/app/services/throughput_calculator.rb:10-26
COLLECTIONS =
  {
    clients: :updated_at,
    deals: :updated_at,
    deal_extra_fields: :updated_at,
    goals: :updated_at,
    groups: :updated_at,
    groupifications: :created_at,
    hierarchy: :created_at,
    modifiers: :updated_at,
    products: :updated_at,
    subsidiaries: :updated_at,
    users: :updated_at,
    user_activity: :created_at,
    user_fields: :created_at,
    user_identifiers: :updated_at
  }.freeze
```
This is the same constant `integration.rake` iterates directly (`ThroughputCalculator::COLLECTIONS.each { |collection, column| ... }`, lines 66-70 and 143-147) rather than calling `ThroughputCalculator.call` — the rake task re-implements the per-collection count inline against `Job.ne(ends_at: nil).order_by(starts_at: :asc).last.ends_at` as the watermark, not against `job.fetch_since` (the two watermarks are computed differently: the rake task's preview uses the *last completed job's* `ends_at`, while `ThroughputCalculator` — invoked later, inside `ThroughputProcessor`, against the *new* job's `fetch_since` — which itself derives from the same `last_job.ends_at` minus `ApplicationConfiguration.fetch_days`, per `job/starter.rb:25-30`). The two numbers should be very close but are not computed by the identical code path.

**Significance:** whatever "numbers-only" mode is added to the integrator has a ready-made source of truth (`ThroughputCalculator::COLLECTIONS`) for the labels; whether the *values* should come from the rake task's existing inline computation (against `last_job.ends_at`) or from actually calling `ThroughputCalculator.call` (against the new job's `fetch_since`, which requires a job to already exist) is a design choice for the follow-up PLAN, not decided here.

### Finding 5: the integrator already self-scales-down in production — `ShutDownWorker` stops the Mongo EC2 and scales web+worker to 0 once the job's async pipeline is fully done

**Evidence:**
```ruby
# integrator/app/workers/shut_down_worker.rb:5-17
class ShutDownWorker < ApplicationWorker
  def perform
    return unless Rails.env.production?

    stats = Sidekiq::Stats.new
    total_jobs = stats.enqueued + stats.scheduled_size + stats.retry_size + stats.workers_size

    return ShutDownWorker.perform_in(5.seconds) if total_jobs > 1

    Ec2.stop_machine
    Ecs.scale_down
  end
end
```
```ruby
# integrator/app/models/ec2.rb:8-12
def self.stop_machine
  return if ApplicationConfiguration.aws_instance_ids.blank?

  adapter.stop_instances(ApplicationConfiguration.aws_instance_ids)
end
```
```ruby
# integrator/app/models/ecs.rb:8-19
def self.scale_down
  adapter.update_service('cluster' => ApplicationConfiguration.aws_ecs_cluster, 'service' => ApplicationConfiguration.aws_ecs_worker_service, 'desiredCount' => 0)
  adapter.update_service('cluster' => ApplicationConfiguration.aws_ecs_cluster, 'service' => ApplicationConfiguration.aws_ecs_web_service, 'desiredCount' => 0)
```
`ShutDownWorker.perform_async` is called from several terminal consumers once `job.computation.done?` (e.g. `integrator/app/workers/resource/consumer.rb:34-36`, and identically from `high_throughput_report/consumer.rb`, `missing_streams_report/consumer.rb`, `source_check_report/consumer.rb`, `inactive_streams_report/consumer.rb`, `resource/producer.rb`).

Confirmed that this fires even for non-productive/staging environments: `terraform/integrator-commcenter/compute_staging.tf:37` sets `RAILS_ENV = "production"` for the staging stack too (only `ENVIRONMENT`/naming differ), so `Rails.env.production?` is true there as well.

**Significance:** this directly resolves one of the cross-cutting open questions posed in the task briefing — **the skill does not need to scale services (or Mongo) back down after the run**, at least for any client where `Rails.env.production?` is true (which appears to be every deployed environment, prod and staging alike, per the `RAILS_ENV` values read). The self-teardown is conditioned on `Sidekiq::Stats` showing no more enqueued/scheduled/retrying/active jobs — i.e., it waits for the full async pipeline (not just the initial `Job::Starter` call) to drain. `Ec2.stop_machine` is a no-op when `AWS_INSTANCE_IDS` is blank (true for commcenter and all four Atento countries — see Finding 6), so those clients' Mongo (where applicable) is never touched by this mechanism.

### Finding 6: the per-client "normal" web/worker task counts and whether a client has a stoppable Mongo EC2 both live in Terraform, mirrored into EventBridge Scheduler resources — not exposed as an AWS tag

**Evidence (almaviva, the fullest-featured example):**
```hcl
# terraform/integrator-almaviva/compute.tf:120-136 (module "web")
module "web" {
  source = "../modules/ecs_service"
  ...
  desired_count  = 1
  ...
}

# terraform/integrator-almaviva/compute.tf:161-176 (module "worker")
module "worker" {
  source = "../modules/ecs_service"
  ...
  desired_count = 2
  ...
}

# terraform/integrator-almaviva/compute.tf:317-339 (EventBridge Scheduler target mirrors the same value)
resource "aws_scheduler_schedule" "scale_up_web" {
  ...
  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ecs:updateService"
    role_arn = aws_iam_role.ecs_scheduler.arn
    input = jsonencode({
      Cluster      = aws_ecs_cluster.this.name
      Service      = module.web.service_name
      DesiredCount = 1
    })
  }
}
```
Confirmed no tag carries this: `terraform/modules/ecs_service/main.tf:75-79` shows `aws_ecs_service.this.desired_count = var.desired_count` is a plain resource argument, and the module's `tags = var.tags` (line 146) is an unrelated tag map — no "baseline desired count" tag exists on the ECS service.

Per-client values (full detail in the auxiliary file `manual-integrator-run-skill_terraform-desired-counts_1.md`):

| Client | web | worker | Dedicated Mongo EC2 (`AWS_INSTANCE_IDS`) |
|---|---|---|---|
| almaviva | 1 | 2 | yes (3 instances) |
| redebrasil | 1 | 1 | yes (3 instances) + a second monthly-window schedule pair |
| maqnelson | 1 | 2 | yes (3 instances) |
| commcenter (prod) | 1 | 1 | no (`AWS_INSTANCE_IDS = ""`) |
| commcenter-staging | 0 | 0 | no, and no scheduler at all (on-demand only) |
| atento-br | 1 | 1 | no (shares a group Mongo not wired through `AWS_INSTANCE_IDS`) |
| atento-mx | 1 | 1 | no (same shared-Mongo note; harvester-fed) |
| atento-co | 1 | 1 | no (same shared-Mongo note; harvester-fed) |
| atento-cl | 0 | 0 | no, though `cl_scale_up_web`/`cl_scale_up_worker` schedule resources exist (their `DesiredCount` payload was not read in this pass) |

**Significance:** two independent read-only sources exist for "what is the normal count for this client", each with different trade-offs (see Trade-offs table). Whether a client needs a Mongo raised is answered by whether `AWS_INSTANCE_IDS` is non-empty for that client's stack — equivalently, whether `/ec2-instances --client <name> --role database` returns anything (the `ec2-instances` skill's own tag model, `~/.claude/skills/ec2-instances/SKILL.md:12-17`). Atento's Mongo is shared across all four countries and is not wired through `AWS_INSTANCE_IDS` at all in any of the four country sub-stacks — the skill must not assume every client maps 1:1 onto a start/stop-able Mongo.

### Finding 7: the `integrators` skill's own documentation for MongoDB start is already slightly inaccurate relative to `DEPLOY.md`

**Evidence:**
```
# ~/.claude/skills/integrators/SKILL.md:130-132
### If the engineer asked to start MongoDB instances

Some clients have MongoDB EC2 instances managed outside ECS. The deploy workflow handles MongoDB startup via the preflight job. For manual start, use the `/ec2-instances` skill...
```
```
# integrator/.github/DEPLOY.md:51-53
## MongoDB Startup

Some integrators have MongoDB instances that start via EventBridge schedule before processing time. Running a deploy before MongoDB is up will cause the migrate job to fail with `Mongo::Error::NoServerAvailable`. The preflight job checks MongoDB status and aborts early if instances are not running.
```
**Significance:** `DEPLOY.md` is explicit that the deploy's PREFLIGHT job only *verifies* MongoDB is running and aborts the deploy early if not — it does not *start* MongoDB. MongoDB startup is exclusively the EventBridge `start_mongodb` schedule (Finding 6). The `integrators` skill's line "The deploy workflow handles MongoDB startup via the preflight job" overstates what preflight does. This is a pre-existing minor documentation inaccuracy in a file outside this spike's requested scope — noted per Scope Discipline, not fixed here, but the engineer may want it corrected as part of (or alongside) whatever PR implements this skill, since the new skill will need to state MongoDB-start behavior correctly in its own doc regardless.

### Finding 8: `bin/ecs` gives two different ways to reach a container able to run the rake task — `connect` (existing running task) and `run` (ephemeral runner task) — with different prerequisites

**Evidence:**
```bash
# integrator/bin/ecs:6-8 (usage header)
#   bin/ecs connect <integrator> <web|worker> [command]   Connect to a running container (default: rails console)
#   bin/ecs run <integrator> [command] [timeout]          Spin up an ephemeral Fargate task and connect interactively (default: rails console)
```
`cmd_connect` (`bin/ecs:73-158`) lists RUNNING tasks for `integrator-{name}-{web|worker}-service` and executes into one of them — it fails outright if none are running (`bin/ecs:96-99`: `if [ -z "$TASK_ARNS" ] ... echo "[ERROR] No running tasks found"`). `cmd_run` (`bin/ecs:163-332`) instead spins up its own ephemeral task on the pre-existing `integrator-{name}-runner-service`'s network config (`desired_count = 0` always, per Finding 6's table — it exists purely to hold the VPC/subnet/security-group configuration for `run-task`, per the comment at `terraform/integrator-almaviva/compute.tf:193-194`).

**Significance:** the skill's step "raise web+worker, then run the rake task" (engineer's step 3-4) implicitly assumes the rake task is invoked via `connect` into the now-running web or worker task. But `Job::Starter.perform_async` only *enqueues* a Sidekiq job — the actual processing (Extract→Transform→Load pipeline, per `integrator/CLAUDE.md`) executes on whatever worker service instances are running with `desired_count > 0`. This means the container used to *issue* the rake command does not strictly have to be the same one that *processes* the job — a `bin/ecs run` ephemeral runner task (independent of whether web/worker are up yet) could issue the trigger command, as long as the worker service is scaled up before the job actually needs to be dequeued. This is a real design fork, not resolved here (see Open Decision 3).

## Trade-offs surfaced

### How the skill derives "the normal count" for a client

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Grep/read the client's Terraform `compute*.tf` (`module "web"`/`module "worker"` desired_count) | Single, authoritative, human-readable source; matches what `terraform apply` would (re-)enforce | Requires the skill to know which `.tf` file(s) belong to a client (not uniform — almaviva is one file, atento is split into `compute_{br,mx,co,cl}.tf`); reading raw HCL from a skill script is more brittle than a tag/API call; no live drift detection (Terraform value could be stale relative to what was last manually applied) | `terraform/integrator-almaviva/compute.tf:120-136,161-176`; per-client detail in the auxiliary file |
| `aws scheduler get-schedule --name integrator-<client>-scale-up-web` (read the EventBridge Scheduler target's `DesiredCount` JSON payload) | Pure AWS read-only API call, no Terraform tooling/parsing needed, symmetric with how `/integrators` and `/ec2-instances` already discover resources by AWS API | Only works for clients that HAVE this schedule wired (commcenter-staging and any future on-demand-only client would return nothing); naming of the schedule resource is not 100% uniform across clients (compare `scale_up_web` vs `prod_scale_up_web` vs `br_scale_up_web` in the auxiliary file) — the skill would need a per-client name pattern or a tag-based discovery step first | `terraform/integrator-almaviva/compute.tf:317-339` (schedule shape); auxiliary file's per-client schedule-name column |
| Hardcode counts in the new skill's own `environments.json`-style metadata (mirroring how `integrators/environments.json` already carries non-tag metadata) | Fast, no runtime AWS/Terraform call, consistent with the existing `integrators` skill pattern of curated per-client metadata | Duplicates a value Terraform already owns — the two can drift silently if Terraform changes and the skill's file is not updated; reintroduces a manual-sync burden the other two options avoid | `~/.claude/skills/integrators/environments.json:1-166` (the precedent for this pattern) |

### Where the numbers-only / non-interactive-accept logic lives

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Add two new rake tasks (or task arguments) to `integration.rake` — one prints SOURCES+NUMBERS and exits cleanly without touching `$stdin`, one accepts a flag that skips the prompt and starts the job directly | Keeps the existing `integration:start`/`integration:force_start` untouched for any other manual/human use; new tasks are purpose-built for scripted invocation | Two (or four, counting `force_start`'s variant) new task names to maintain; the SOURCES+NUMBERS block is currently duplicated between `start` and `force_start` (Finding 2) — adding more copies without addressing the duplication compounds it (Scope Discipline flags this as a follow-up, not something to fix silently mid-change given the duplication predates this work) | `integrator/lib/tasks/integration.rake:16-91,93-168` |
| Modify `integration:start`/`integration:force_start` in place to accept a rake argument (e.g. `rake integration:start[skip_prompt]`) that branches around the `$stdin.gets` block | No new task names; one task, one behavior, parameterized | Changes the existing manual (human) invocation contract — anyone running `rake integration:start` by hand today would need to learn the new argument shape or trust the default stays interactive; higher blast radius for a change whose primary consumer is the new skill | `integrator/lib/tasks/integration.rake:18,95` (task signatures) |
| Do not touch the rake tasks; have the skill pipe `n\n` then `y\n` into a *non*-interactive ECS Exec invocation | Zero integrator-side code change | Contradicted by Finding 1 — AWS's own documentation states ECS Exec "only supports initiating interactive sessions"; piping stdin into a command run through `--interactive` ECS Exec is not confirmed to work reliably outside a real pty, and was not validated in this spike. Marked HIGH RISK, not a clean alternative | `https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-exec-run.html` |

### Which container issues the rake command

| Approach | Pros | Cons | Source |
|---|---|---|---|
| `bin/ecs connect <client> web` (or `worker`) into the now-running scaled-up service | Matches the engineer's description literally ("execute on a running ECS task"); reuses the exact tool the engineer already uses by hand | Requires web/worker to already be RUNNING and pass ECS health checks before the connect step — adds a "wait for readiness" dependency the skill must implement (Open Decision 2); `cmd_connect` fails hard with no fallback if zero tasks are RUNNING (`bin/ecs:96-99`) | `integrator/bin/ecs:73-158` |
| `bin/ecs run <client>` (ephemeral runner task, independent of web/worker scale state) | Does not depend on web/worker being scaled up yet to issue the enqueue command; the runner service already exists at `desired_count = 0` purely for this purpose | Two moving pieces to reconcile: the runner task enqueues the job, but the *worker* service still must be scaled up (separately) before Sidekiq actually processes it — a race is possible if the runner task's command runs before the worker service reaches RUNNING; not the mechanism the engineer described using today | `integrator/bin/ecs:163-332`; `terraform/integrator-almaviva/compute.tf:193-194` (runner service comment) |

## What remains uncertain

- Whether `aws ecs execute-command --interactive` invoked through Claude's non-tty Bash tool can reliably capture clean stdout for a command that does NOT block on stdin (e.g. a future numbers-only rake task). AWS's docs confirm ECS Exec is interactive-only at the service level, but do not describe SSM Session Manager plugin behavior when the *local* client (the Bash tool's subprocess) has no real terminal attached. This was not tested in this spike and is a prerequisite technical validation before any implementation.
- Whether redebrasil's "extra" monthly-window schedules (`extra_scale_up_web`/`extra_scale_up_worker`, days 20–27) carry different `DesiredCount` values than the primary schedules — not read in this pass (see auxiliary file, Cross-cutting observation 1).
- Why `commcenter`'s production `compute.tf` includes a `scheduled_task_start_mongodb` module (line 183) despite `AWS_INSTANCE_IDS = ""` — not investigated; could target a different resource type or be dead/unused config.
- Atento CL's `cl_scale_up_web`/`cl_scale_up_worker` schedules exist but `desired_count` in the Terraform resource itself rests at 0 for web/worker/runner — the schedule's own `DesiredCount` payload (which would reveal the "active" count) was not read.
- Whether `ThroughputCalculator::COLLECTIONS`' per-collection counts should be computed against `last_job.ends_at` (matching the rake task's current inline logic) or `job.fetch_since` (matching `ThroughputCalculator`'s own logic, which needs a `Job` record to already exist) — these differ subtly per Finding 4 and affect what the skill's "first numbers reading" vs "second numbers reading" actually compare.
- Whether the engineer's manual workflow today uses `integration:start` or `integration:force_start` — i.e., whether throughput validation should stay active or be bypassed by default in the new skill's accept step. Not something the codebase can answer; this is Open Decision 5 for the engineer directly.
- What "the engineer says go" is exactly — does approval come from a chat reply in the same skill invocation, or could there be a meaningful time gap (e.g. engineer steps away) during which the first numbers reading goes stale in a way that matters beyond the second-reading comparison already planned?

## Suggested options for main and the engineer

Framed as open decisions — no option is recommended here.

**Open Decision 1 — how the skill derives per-client web/worker counts.** Terraform-grep vs `aws scheduler get-schedule` vs a curated `environments.json`-style file in the new skill (see the first Trade-offs table). A hybrid is also possible: curated file as the primary source (fast, consistent with the `integrators` skill precedent), with a fallback read of Terraform or the EventBridge schedule when a client is not yet in the file.

**Open Decision 2 — readiness signal after scaling up.** The skill needs to know web/worker are not just RUNNING but actually able to reach Mongo/the normalized base before invoking the rake task. Options include: polling `aws ecs describe-services` for `runningCount == desiredCount` (task-level only, does not confirm app-level readiness), polling the ALB target group health check (`/health` path, confirmed present at `terraform/integrator-almaviva/compute.tf:112`), or a fixed sleep mirroring the EventBridge pattern's own 5-minute gap between scale-up and `integration:cron` firing (Finding 6's schedule timestamps).

**Open Decision 3 — which container issues the rake trigger command.** `bin/ecs connect` into the scaled-up web/worker service (matches current manual practice, but requires readiness first) vs `bin/ecs run` ephemeral runner task (available immediately, but is a mechanism the engineer does not currently use for this purpose and needs the worker service's own readiness reconciled separately). See the third Trade-offs table.

**Open Decision 4 — shape of the integrator-side rake task change.** New dedicated tasks vs parameterizing the existing `start`/`force_start` tasks vs (not viable per Finding 1, listed only for completeness) leaving the rake tasks untouched and attempting stdin-piping through ECS Exec. See the second Trade-offs table.

**Open Decision 5 — `integration:start` vs `integration:force_start` semantics for the skill's accept step.** Should the skill's non-interactive accept always skip throughput validation (mirroring `force_start`), always keep it (mirroring `start`, which would mean the skill's accept step could itself trigger a `HighThroughputReport` email and NOT start the job — a case the "compare numbers, report divergence" flow in the engineer's design does not currently account for), or expose the choice to the engineer per invocation?

**Open Decision 6 — does the skill need to guard against a race with the existing nightly `integration:cron` automation?** Finding 3 shows a concurrent `Job::Starter` invocation silently no-ops rather than erroring, and the rake task's own "Started!" message does not reflect whether the lock was actually acquired. Whether the skill needs its own check (e.g. query `Job` for one already in-flight before triggering) or can rely on the existing silent-no-op behavior is undecided.

**Open Decision 7 — does the skill need to scale anything back down after the run?** Per Finding 5, production (and staging, since `RAILS_ENV=production` there too) already self-scales worker+web to 0 and stops Mongo (when `AWS_INSTANCE_IDS` is set) once the full async pipeline drains. This appears to make explicit teardown in the skill unnecessary for the clients read in this spike, but the engineer should confirm this covers every case they intend to support (e.g. commcenter and Atento, where `AWS_INSTANCE_IDS` is empty, will never have their Mongo touched by this mechanism even if it needed raising — Finding 6 shows Atento's Mongo is not modeled as a stop/start-able resource per this env var at all).

**Open Decision 8 — skill naming and placement.** Whether this becomes a new action on the existing `/integrators` skill (e.g. "run integration for client X") or a standalone new skill (e.g. `/integrator-run`) in `~/.claude/skills/`. The existing `/harvesters` skill's convention is to explicitly punt one-off triggers ("a one-off run is a deliberate `aws ecs run-task`... run it directly, not through this skill", `~/.claude/skills/harvesters/SKILL.md:85-89`) — this new capability would be the first skill in the catalog to actually *drive* a production business action end-to-end rather than only inspect or scale infrastructure, which the engineer may want to weigh when deciding whether it belongs inside `/integrators` or stands alone.

## Resolved decisions (engineer, 2026-07-09)

All eight open decisions were resolved with the engineer in review. This section supersedes "Suggested options for main and the engineer" above and is the input for the follow-up `PLAN.md`.

**RD1 (was OD1) — count derivation → Terraform.** The skill derives the per-client web/worker counts from the Terraform `module "web"` / `module "worker"` `desired_count` values (e.g. almaviva 1/2, redebrasil 1/1, maqnelson 1/2, commcenter 1/1, atento-* 1/1 — full table in Finding 6 / auxiliary file). This is what the engineer already does by hand ("if you don't know, look at the pattern in Terraform"). The `aws scheduler get-schedule` and curated-file alternatives are not chosen.

**RD2 (was OD2) — readiness signal → ECS task-level.** After scaling up, the skill waits on `aws ecs describe-services` until `runningCount == desiredCount` before issuing the trigger — mirroring what the engineer does manually (wait for the task to come up). App-level readiness (Mongo/base reachability) is not separately gated; if connectivity fails the run fails, same as today.

**RD3 (was OD3) — trigger container → runner.** The skill issues the rake command through `bin/ecs run` (ephemeral runner task, `integrator/bin/ecs:163-332`), NOT `bin/ecs connect`. Rationale: the trigger only *enqueues* the Sidekiq job (`Job::Starter.perform_async` — `job/starter.rb`), so the issuing container only needs Rails + DB connectivity; the ephemeral runner gives clean captured stdout and does not depend on web/worker already being RUNNING to issue the command. The worker service is still scaled up separately so Sidekiq actually processes the enqueued job.

**RD4 (was OD4) — rake surface → single `integration:start`, non-interactive via two env vars (FINAL, revised 2026-07-09).** The engineer collapsed the surface further than the earlier "add `preview` + rename `force_start`" shape. Final decision:
- **No `integration:preview` task.** The numbers-only first pass IS `integration:start` — it already prints SOURCES + NUMBERS (`integration.rake:31-70`) before the prompt. Its `$stdin.gets` (`integration.rake:80`) is made EOF-aware: run without a tty and without the accept env, it prints the numbers and aborts cleanly WITHOUT starting the job. Today that same non-interactive run crashes at `nil.strip` on EOF (`$stdin.gets` returns `nil`); the change makes it graceful. This is exactly the engineer's original "capture the numbers, it dies, doesn't start" idea — clean instead of a crash.
- **`integration:start` name unchanged** — the engineer's call ("the name is perfect"); no external callers, no churn.
- **`integration:force_start` is REMOVED**, folded into a flag (not renamed). It has no callers, so removal is safe.
- **Two env vars on `integration:start`:** `AUTO_ACCEPT` (skip the `Y/n` prompt and start non-interactively) and `SKIP_THROUGHPUT` (bypass the throughput guard — what `force_start` did via `Job::Starter.perform_async(true)`, `integration.rake:161`). The skill's accept step sets both: `AUTO_ACCEPT=1 SKIP_THROUGHPUT=1 bundle exec rake integration:start`.
- **Moots the SOURCES+NUMBERS duplication concern entirely** — one task, no third copy of the block.
- **Delivery: this integrator change ships as a HOTFIX** (engineer's instruction) via HubFlow off `master` (`git hf hotfix start X.Y.Z`), run in the main working tree (NOT a worktree), version bump + dated CHANGELOG section, `git hf hotfix finish` back-merging to master + develop. The dot-claude skill change stays a normal feature PR.

**RD5 (was OD5) — throughput guard in the skill's accept step → skip it (derived, flag for confirmation).** The throughput guard computes an execution-average ceiling (average + deviation + a buffer, per the engineer; realized as `job.metric.ceiling` in `throughput_processor.rb:23`) and halts + emails a `HighThroughputReport` instead of starting when the volume is abnormal. In the skill flow the human reviews the previewed NUMBERS and approves — the human IS the throughput judgment. Therefore the skill's non-interactive accept uses the skip-throughput path (the renamed `force_start` equivalent). Using the guarded `start` would risk the accept silently NOT starting the job (guard halts, emails a report), which the engineer's "approve → it runs → compare numbers" flow does not account for. Recorded as resolved-by-derivation; engineer to confirm on PLAN review. The engineer also flagged that the guard's own naming (currently surfaced as "force") is worth revisiting — folded into RD4.

**RD6 (was OD6) — race with nightly `integration:cron` → rely on the existing lock.** `Job::Starter`'s Redis `SETNX` lock (`lock.rb`, no TTL) already makes a concurrent invocation a silent no-op (Finding 3), so data integrity is protected without a new guard. The skill MAY add a courtesy pre-check (query for an in-flight `Job`) purely for a clearer message, since the rake task's "Started!" text does not reflect whether the lock was actually acquired — but this is optional polish, not a correctness requirement.

**RD7 (was OD7) — teardown → none.** The skill does not scale anything back down. `ShutDownWorker` (`shut_down_worker.rb:5-17`) already stops the Mongo EC2 (when `AWS_INSTANCE_IDS` is set) and scales web+worker to 0 once the async pipeline drains, in every deployed environment (prod and staging both run `RAILS_ENV=production`). For clients with empty `AWS_INSTANCE_IDS` (commcenter, all four Atento) the Mongo is never touched by this mechanism — but those clients also do not have a stop/start-able dedicated Mongo to raise in the first place (Finding 6), so it is consistent.

**RD8 (was OD8) — placement → new action inside `/integrators`.** This is a new action on the existing `/integrators` skill, not a standalone skill. It composes the skill's existing scale logic (`ecs-scale.sh`) with the Mongo-raise step (via the `ec2-instances` model, keyed on whether the client has a non-empty `AWS_INSTANCE_IDS` / a `role=database` EC2), the runner trigger (RD3), and the preview/accept/compare flow.

### Prerequisite technical validation for the PLAN

One item from "What remains uncertain" survives as a hard prerequisite regardless of the decisions above: whether `bin/ecs run` (which itself connects via `aws ecs execute-command --interactive`, `bin/ecs:151-157`) can, through Claude's non-tty Bash tool, reliably capture clean stdout for the non-blocking numbers pass and reliably run the accept. This was validated early — see the Phase 0 outcome below.

## Phase 0 outcome (executed 2026-07-09)

The probe ran against `commcenter-staging` (non-productive, `desired_count=0`, no schedules — safe target). Full capture: `/tmp/phase0_probe_capture_20260709.txt`.

**Result — the core premise holds, but `bin/ecs run` is not usable as-is for automation:**
- ✅ **Clean stdout capture works** through the non-tty Bash tool — `PHASE0_PROBE_OK` and `production` came back uncorrupted.
- ✅ **No MFA needed** — the default (read-only) profile successfully ran `run-task` and `stop-task` on this stack; the skill's trigger will not need `/elevate-aws-access`.
- ⚠️ **`bin/ecs run` is unclean non-interactively:** the `execute-command --interactive` session ends with `Cannot perform start session: EOF` (no tty to hold the session), the script exits 1 even though the command succeeded (so the exit code cannot distinguish real failure from the EOF artifact), and `cleanup()` crashes on `set -u` (`TASK_ARN: unbound variable`, `bin/ecs:194`) so the ephemeral task is not stopped by the trap (it self-dies when its `sleep TIMEOUT` expires; the probe task was stopped manually via `aws ecs stop-task`).

**→ Execution model decided = Fallback A (from the PLAN-SPIKE).** The skill does NOT drive `bin/ecs run`. It uses raw `aws ecs run-task` with a container command override — the runner container runs `bundle exec rake integration:start` (numbers pass) or `AUTO_ACCEPT=1 SKIP_THROUGHPUT=1 bundle exec rake integration:start` (accept pass) directly as a batch task, no ECS Exec / no interactive session — then polls `aws ecs describe-tasks` until `STOPPED` and reads the NUMBERS output from CloudWatch Logs. This sidesteps the interactive-session constraint (Finding 1) entirely and is deterministic. It still honors RD3 ("the runner issues the command") — only the HOW changes. This closes the PLAN's one contingent decision (execution model for skill steps 6/8/9).
