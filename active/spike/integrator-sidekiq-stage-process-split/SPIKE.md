# SPIKE — Splitting the Integrator Sidekiq Pipeline into Per-Stage Processes

## Investigation question

How can the `integrator` Sidekiq pipeline (Extract → Transform → Load) be split into separate ECS processes/services per stage, so each stage scales independently, and so the Loading stage — the one that talks to the client's API — is bounded and never overwhelms that API? Specifically: (a) is two processes (Extract+Transform combined, Load alone) enough, or does Transform's measured cost justify a third, isolated process; (b) what are the options and trade-offs for making a Sidekiq process subscribe to only its stage's queues; (c) how could a stage-completion event scale ECS services up/down from inside the application, what IAM does that need, and what fails if it fails mid-flight; (d) where do mailers and the ancillary queues (`authorization`, `checkup`, `report`, `cold_storage`, `migration`) fit in the new topology; (e) what is the smallest Terraform change that stands this up, and does it belong in a per-client stack or in `modules/integrator`.

This is research and design-options only — no code or Terraform was written, no command was run that changes state. Every finding below is either a direct code citation from `~/Projects/4Shark/integrator` and `~/Projects/4Shark/terraform`, or a verified quote from a fetched external source with its verification block.

## Sources consulted

- `~/Projects/4Shark/integrator/CLAUDE.md` — pipeline stage/stream order, `Computation` coordination summary.
- `~/Projects/4Shark/integrator/app/workers/**/*.rb` (387 `sidekiq_options queue:` declarations, read in full) — the queue map; individual worker files read to trace the real `perform_async` chain between stages (not inferred from the stream-order list alone).
- `~/Projects/4Shark/integrator/config/sidekiq.yml`, `Procfile`, `Procfile.services` — current queue weights and process command.
- `~/Projects/4Shark/integrator/app/models/computation.rb`, `app/models/lock.rb`, `app/workers/job/starter.rb` — the completion-counter and lock mechanics.
- `~/Projects/4Shark/integrator/.github/workflows/deploy.yaml:100-146` — the existing TSTP-quiet mechanism.
- `~/Projects/4Shark/integrator/Gemfile.lock:586`, `Gemfile:51` — pinned `sidekiq (8.1.7)`, OSS gem only (no `sidekiq-ent`/`sidekiq-pro`).
- `~/Projects/4Shark/terraform/modules/integrator/{deployments.tf,deployments_alb.tf,variables.tf,iam_task_role.tf}` — the module's service/schedule abstraction and existing IAM grants.
- `~/Projects/4Shark/terraform/integrator-{almaviva,atento,commcenter,maqnelson}/main.tf` — every client stack's current `services` block (all four are the same shape: one `worker` role, no queue split).
- `~/.claude/docs/DATA-PROCESSING.md` — `Computation` completion guarantee, Producer/Consumer topology naming.
- `~/.claude/docs/DEPLOYMENT-STRATEGY.md` — the existing TSTP-quiet-then-drain deploy mechanism and why interruption is already safe.
- `~/.claude/docs/TERRAFORM-CONVENTIONS.md`, `~/.claude/docs/TERRAFORM-POLICY.md` — apply-before-merge workflow (governs how any of this would ship, not analyzed further here since no change is proposed).
- `~/.claude/CLAUDE.md` § Terraform Module Boundary — the three-question test for module-vs-stack placement, applied in the "Terraform delta" section below.
- Sidekiq wiki `Advanced-Options` (fetched) — queue weights, `-c` concurrency, dedicated-process pattern.
- Sidekiq `docs/capsule.md` (fetched) — `Sidekiq::Capsule` definition, configuration shape, Redis-instance constraint.
- Sidekiq wiki `Signals` (fetched) — TSTP/TERM behavior.
- AWS ECS developer guide, `task_definition_parameters.html` (fetched) — `stopTimeout` default/maximum.
- WebSearch — Sidekiq Enterprise `Limiter` and OSS alternatives (`sidekiq-limit_fetch`, `Sidekiq::Throttled`, etc.) for the "ceiling" question in Finding 1.
- See auxiliary `integrator-sidekiq-stage-process-split_queue-map_1.md` — the full worker→queue→stage table and the verified stage-boundary chain trace.
- See auxiliary `integrator-sidekiq-stage-process-split_terraform-excerpt_1.tf` — the current per-client `services` block, the module's `services` variable schema, and the existing scheduler IAM policy, kept side by side for comparison.

## Findings

### Finding 1: today, one Sidekiq process definition serves every stage and every queue, with no isolation of the Loading stage

**Evidence:**

```ruby
# ~/Projects/4Shark/integrator/config/sidekiq.yml
concurrency: <%= ApplicationConfiguration.sidekiq_threads %>
:queues:
  - [api_extractor, 1]
  - [api_loader_producer, 10]
  - [api_loader_consumer, 1]
  - [authorization, 1]
  - [checkup, 1]
  - [cold_storage, 1]
  - [database_extractor, 1]
  - [database_transformer, 1]
  - [default, 1]
  - [migration, 1]
  - [report, 1]
```

```hcl
# ~/Projects/4Shark/terraform/integrator-almaviva/main.tf:83-88
worker = {
  command       = ["bundle", "exec", "sidekiq"]
  cpu           = 512
  memory        = 2048
  desired_count = 2
}
```

`SIDEKIQ_THREADS = "30"` is set in the same stack's `env_vars` (`main.tf:67`).

**Significance:** the `worker` command carries no `-q` flag, so each of the 2 tasks starts Sidekiq with the queue list and weights from `sidekiq.yml` above and a concurrency of 30 threads. Every queue — `database_extractor`, `database_transformer`, `api_loader_producer`, `api_loader_consumer`, and every ancillary queue — is fetched from the same 30-thread pool per task (60 threads across the fleet). Sidekiq's own documentation states concurrency is a per-process setting that applies across whichever queues that process is told to service, and a queue's weight only changes how *often* it is polled relative to the others, not how many threads it may occupy at once (Finding 4 below has the verified quotes). So nothing in the current configuration prevents all 60 threads from simultaneously running `api_loader_consumer` jobs against the client's API if that is what happens to be queued at a given moment — there is no per-queue ceiling today.

### Finding 2: the three stages are global barriers over all 25 streams, not per-stream — there is exactly one "Extract done" and one "Transform done" moment

**Evidence** (each arrow below is a literal `perform_async` call read in the calling worker's source, not inferred from the stream-order list):

```ruby
# ~/Projects/4Shark/integrator/app/workers/client/collection_extractor_producer.rb:36-38
else
  Product::CollectionExtractorProducer.perform_async(job_id)
end
```

Client's Extract-stage producer, finding no more streams ready, calls **Product's** Extract-stage producer — the next STREAM, same STAGE. This repeats through the full stream order.

```ruby
# ~/Projects/4Shark/integrator/app/workers/goal/database_enrichment_extractor_consumer.rb:22-24
job.computation.increment_executions
Subsidiary::TransformerProducer.perform_async(job_id) if job.computation.done?
```

`Goal` is the LAST stream in the fixed order (`integrator/CLAUDE.md`). Its Extract-stage enrichment consumer, on the pipeline-wide `done?` check, calls **Subsidiary's** Transform-stage producer — the FIRST stream, NEXT stage. This is the single "Extract is over, Transform begins" event for the whole job.

```ruby
# ~/Projects/4Shark/integrator/app/workers/goal/transformer_consumer.rb:25-26
job.computation.increment_executions
Goal::EnricherProducer.perform_async(job_id) if job.computation.done?
```

and (traced further)

```ruby
# grep confirms: only subsidiary/loader_producer.rb (self-pagination) and
# goal/enricher_producer.rb, goal/enricher_consumer.rb, goal/transformer_producer.rb
# call Subsidiary::LoaderProducer
```

Goal's Transform-stage completion (through its own internal Transformer→Enricher sequence) calls **Subsidiary's** Load-stage producer — the single "Transform is over, Load begins" event.

```ruby
# ~/Projects/4Shark/integrator/app/workers/goal/loader_consumer.rb:20-24
job.computation.increment_executions
return unless job.computation.done?
Job::Finisher.perform_async(job_id)
```

Goal's Load-stage completion calls `Job::Finisher` — the single "Load is over, job is done" event.

**Significance:** because every stage transition happens at exactly one call site (the last stream's last worker in that stage), the engineer's proposed hand-off — scale Load up / scale Extract+Transform down when Transform finishes, and the reverse at Load's completion — has exactly one place to hook per transition, with no risk of firing once per stream instead of once per stage. The full chain is in the auxiliary queue-map file.

### Finding 3: the completion counters are per-JOB (not per-stage) and are provably retry-safe against a premature scale-down signal

**Evidence:**

```ruby
# ~/Projects/4Shark/integrator/app/models/job.rb:74-75
def computation
  @computation ||= Computation.new("j_#{id}")
end
```

One `Computation` (one Redis `queue:j_<id>` / `executions:j_<id>` counter pair) for the ENTIRE job — all 25 streams, all 3 stages — not one pair per stage. `done?` is `queue.value == executions.value` (`app/models/computation.rb:39-46`).

```ruby
# ~/Projects/4Shark/integrator/app/workers/client/database_collection_extractor_consumer.rb:34-35
rescue Sequel::DatabaseDisconnectError, Sequel::DatabaseConnectionError
  Client::DatabaseCollectionExtractorConsumer.perform_async(job_id, stream_id, collection_last_id)
```

```ruby
# ~/Projects/4Shark/integrator/app/workers/goal/loader_consumer.rb:25-26
rescue *ApplicationLoader::PARSE_EXCEPTIONS
  Goal::LoaderConsumer.perform_in(5.seconds, job_id, goal_id)
```

Both rescue blocks re-enqueue the SAME logical unit of work WITHOUT calling `increment_executions` first (that call happens earlier in the method, before the code that can raise).

**Significance:** because a retried job never inflates `executions` until it truly finishes, `Computation#done?` for a given stage cannot read `true` while any job from that stage — including one currently sleeping on a delayed retry — is still outstanding. A stage-completion signal hooked at the call sites in Finding 2 is therefore safe against the specific race of "the trigger fires while a straggler is still in flight" without any new bookkeeping. What the counters do NOT give for free is a *named* "stage E is done" or "stage T is done" boolean — the signal is only available at the specific `perform_async` call sites already identified in Finding 2, so a scale-down hook has to be code added at exactly those points (or a new explicit stage marker), not something read off an existing generic field.

### Finding 4: CLI-flag queue subscription (`-q`) already IS the pattern in this codebase — the module and every client stack already run different `command`s per ECS service on the same image

**Evidence:**

```hcl
# ~/Projects/4Shark/terraform/integrator-almaviva/main.tf:73-93 (identical shape in atento/commcenter/maqnelson)
services = {
  web = {
    command = ["bundle", "exec", "puma", "-C", "config/puma.rb"]
    ...
  }
  worker = {
    command = ["bundle", "exec", "sidekiq"]
    ...
  }
  runner = { ... }   # no command override — idle, used via bin/ecs run
}
```

```hcl
# ~/Projects/4Shark/terraform/modules/integrator/variables.tf:66-74
services = map(object({
  command                           = optional(list(string), [])
  cpu                               = number
  memory                            = number
  desired_count                     = number
  container_port                    = optional(number)
  attach_to_alb                     = optional(bool, false)
  health_check_grace_period_seconds = optional(number)
}))
```

Verified from Sidekiq's own wiki (fetched):

> "A queue with a weight of 2 will be checked twice as often as a queue with a weight of 1" and can be set "As arguments... sidekiq -q critical,2 -q default"

> "The easiest way is to run two sidekiq processes, each handling different queues: sidekiq -q critical # Only handles jobs on the 'critical' queue"

> "You can tune the amount of concurrency in your Sidekiq process" using "bundle exec sidekiq -c 4"

**Significance:** the `services` map is already an arbitrary-key map, and every existing role (`web`/`worker`/`runner`) is already just a different `command` on the same ECR image. Subscribing a new "Load-only" service to only `api_loader_producer`/`api_loader_consumer` is `command = ["bundle", "exec", "sidekiq", "-q", "api_loader_producer", "-q", "api_loader_consumer", "-c", "<N>"]` in a NEW entry of that same map — no module change, no image change, no new Terraform resource type. This is the cheapest of the three queue-isolation options (see Trade-off Table 2).

### Finding 5: Sidekiq Capsules (v7+/8, available today — 4Shark pins Sidekiq 8.1.7 OSS) are the in-process alternative, at the cost of a code change instead of a Terraform change

Verified from Sidekiq's own docs (fetched, `docs/capsule.md`):

> "`Sidekiq::Capsule` represents the set of resources necessary to process a set of queues."

Configuration shape:

```ruby
Sidekiq.configure_server do |config|
  config.capsule("name") do |cap|
    cap.concurrency = 1
    cap.queues = %w[queue_name]
  end
end
```

> "There is still one iron-clad rule: a Sidekiq process only executes jobs from one Redis instance; all Capsules within a process must use the same Redis instance."

**Significance:** a Capsule gives a NAMED, separately-concurrency-limited thread pool for `api_loader_producer`/`api_loader_consumer` **inside the SAME Sidekiq process** that also runs Extract/Transform's capsule — so the whole fleet could, in principle, run as ONE ECS service with two capsules instead of two ECS services. This does NOT need a new Terraform service or IAM change, but it DOES need a Ruby/Rails code change (a `config/initializers/sidekiq.rb` capsule block) and it does NOT give an independent ECS-level scaling axis — both capsules still live inside the same task, so scaling "Load" independently of "Extract+Transform" (the stated goal) is not possible with Capsules alone; Capsules bound Loading's *concurrency*, not its *task count*. Community sources (WebSearch, not independently fetched — flagged as such) additionally note the OSS gem exposes no way to select which capsules a given process boots by CLI flag; that would need environment-variable-gated logic in the initializer.

### Finding 6: no IAM permission exists today for an in-app worker to call `ecs:UpdateService` — only the EventBridge Scheduler's role has it

**Evidence:**

```hcl
# ~/Projects/4Shark/terraform/modules/integrator/deployments_alb.tf:218-248
resource "aws_iam_role" "deployments_scheduler" {
  assume_role_policy = jsonencode({
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      ...
    }]
  })
}

resource "aws_iam_role_policy" "deployments_scheduler" {
  policy = jsonencode({
    Statement = concat([
      {
        Effect   = "Allow"
        Action   = ["ecs:UpdateService", "ecs:DescribeServices"]
        Resource = "arn:aws:ecs:sa-east-1:405749097490:service/${local.name_prefix}${local.scheduler_cluster_wildcard}-cluster/*"
      },
      ...
```

The assume-role principal is `scheduler.amazonaws.com` — this role can only be assumed BY EventBridge Scheduler, not by an ECS task.

```hcl
# ~/Projects/4Shark/terraform/modules/integrator/iam_task_role.tf:7-91 (full file read)
```

The task's own role (`aws_iam_role.ecs_task_execution`, used as BOTH `execution_role_arn` and `task_role_arn` per `deployments.tf:149-150`) grants only: the AWS-managed `AmazonECSTaskExecutionRolePolicy` (ECR pull + log write), a scoped `ssm:GetParameters` + `kms:Decrypt`, and ECS Exec's `ssmmessages:*` actions. No `ecs:UpdateService`, no `ecs:DescribeServices`.

**Significance:** a Sidekiq worker calling `ecs:UpdateService` from inside the task needs a NEW `aws_iam_role_policy` statement on `aws_iam_role.ecs_task_execution`, scoped the same way the scheduler's is (by cluster/service ARN). Per `~/.claude/CLAUDE.md` § Terraform Module Boundary's three-question test: this is the same shape in every deployment that opts into the split-worker topology (question 2 → module), and the component (the split-worker topology) cannot self-orchestrate without it (question 1 → module) — so this belongs in `modules/integrator/iam_task_role.tf`, most naturally gated behind a new boolean variable (e.g. `enable_worker_self_scaling`) so stacks that keep the single-worker topology are unaffected. This mirrors the existing `github_deploy` variable's shape (`variables.tf:164-173`, `null` default → the module creates nothing).

### Finding 7: ECS's own SIGTERM/`stopTimeout` behavior already gives a graceful landing to a scale-down, PROVIDED the timeout is not raced

Verified from Sidekiq's own wiki (fetched, `Signals`):

> "TERM signals that Sidekiq should shut down within the `-t` timeout option given at start-up. It will stop fetching new jobs, but continue working on current jobs (as with TSTP)."

> "Any jobs that do not finish within the timeout are forcefully terminated and pushed back to Redis to be executed again when Sidekiq starts up. The timeout defaults to 25 seconds."

Verified from the AWS ECS developer guide (fetched, `task_definition_parameters.html`):

> "`stopTimeout` ... Time duration (in seconds) to wait before the container is forcefully killed if it doesn't exit normally on its own. ... If the parameter isn't specified, then the default value of 30 seconds is used. The maximum value is 120 seconds."

No `stopTimeout` is set anywhere in `~/Projects/4Shark/terraform/modules/ecs_service/*.tf` (confirmed by grep — no match), so the integrator's tasks run on the 30-second AWS default.

**Significance:** a plain `ecs:UpdateService --desired-count <lower>` (the "hard" approach) already benefits from Sidekiq's own TERM handling: ECS sends the stop signal, Sidekiq stops fetching and tries to finish in-flight jobs, and with the 30s ECS default comfortably above Sidekiq's 25s default `-t`, the ordinary case is a graceful drain, not an abrupt kill — any job Sidekiq itself times out on is explicitly pushed back to Redis by Sidekiq's own shutdown logic, not silently lost. What this session did **not** verify is OSS Sidekiq's behavior if a process is SIGKILLed with no TERM/TSTP delivered at all (a scenario ECS's normal `stopTimeout` flow is designed to avoid, but which a misconfigured lower `stopTimeout` or a Fargate Spot interruption could still produce) — this is a genuine remaining question, not resolved here (see "What remains uncertain").

### Finding 8: mailers run synchronously inside the `report`-queue Sidekiq job — there is no separate ActiveJob mail queue to route

**Evidence:**

```ruby
# ~/Projects/4Shark/integrator/app/workers/integration_report/consumer.rb:5-18
class Consumer < ApplicationWorker
  sidekiq_options queue: :report

  def perform(job_id, to)
    ...
    IntegrationReportMailer.create(job_id: job_id, to: to, file_path: file_path).deliver_now
    job.computation.increment_executions
    ...
```

`config/environments/production.rb:54` shows `config.active_job.queue_adapter = :resque` commented out — no adapter override, and no `deliver_later` call was found anywhere in the mailer-related workers grepped.

**Significance:** the mail send (including generating the `.xlsx` workbook via `ApiReportWorkBook`) runs inline, on whichever Sidekiq THREAD picked up that one `report`-queue job — there is no second hop through ActiveJob to reroute. This confirms the `report` queue is the correct and only unit to place per the engineer's decision in point 4; the question that decision actually turns on is which PROCESS'S thread pool absorbs a potentially long-running job, which is Trade-off Table 4 below.

### Finding 9: the ancillary queues map to three distinct positions in the pipeline, confirmed by chain trace (not by name alone)

- **`authorization` + `checkup` — strictly pre-Extract.** `Job::Starter` → `HealthCheck::Producer/Consumer/Finalizer` (`checkup`) → `Authorization::Producer/*Consumer/Finalizer` (`authorization`) → `AvailabilityCheck::Producer/*Consumer/Finalizer` (`checkup`) → `ThroughputProcessor` (`authorization`) → `Subsidiary::CollectionExtractorProducer` (Extract stage, stream 1). Every one of these five worker groups runs and finishes before a single Extract-stage job is enqueued (verified: `~/Projects/4Shark/integrator/app/workers/throughput_processor.rb:10,15,24`).
- **`report` — two distinct moments.** Most report producers (`SourceCheckReport`, `MissingStreamsReport`, `InactiveStreamsReport`, `HighThroughputReport`, `StreamCheckReport`) fire on early-exit / failure branches of `Job::Starter`, `ThroughputProcessor`, or `AvailabilityCheck::Finalizer` — i.e. BEFORE or INSTEAD OF the stream pipeline running at all. `IntegrationReport` — the normal end-of-run report — fires from `Job::Finisher`, which only runs after `Goal::LoaderConsumer` (Load stage, last stream) reaches `done?` (`~/Projects/4Shark/integrator/app/workers/goal/loader_consumer.rb:22-24`, `job/finisher.rb:7-9`). So `report` jobs can appear at the very start OR the very end of a run, never in the middle.
- **`cold_storage` — strictly post-report, end of pipeline.** `IntegrationReport::Consumer` calls `job.computation.release_lock` then `Resource::Producer.perform_async(job_id)` (queue `cold_storage`) only after the mail is sent (`integration_report/consumer.rb:13-17`).
- **`migration` — not part of any run at all.** `Job::Migration::*` and `JobMetric::Migration::*` are named and documented (`integrator/CLAUDE.md` § Normalized Database Schema Lifecycle) as deploy-time data migrations, unrelated to `Job::Starter`'s pipeline.

### Finding 10: `api_extractor` is a dead queue entry in `config/sidekiq.yml` — it costs nothing to carry forward or drop

A repo-wide grep of `app/workers/**/*.rb` for `queue: :api_extractor` returns no match, while `config/sidekiq.yml:5` still lists `[api_extractor, 1]`. No worker subscribes to it. This has no bearing on the split design beyond: whichever process(es) keep subscribing to the full ancillary set do not need to carry this entry forward, and dropping it from a new `-q`-flag command list changes nothing observable.

## Trade-offs surfaced

### Table 1 — two processes vs three

| Approach | Pros | Cons | Source |
|---|---|---|---|
| **2 processes**: Process A = Extract+Transform (`database_extractor`+`database_transformer`), Process B = Load (`api_loader_producer`+`api_loader_consumer`) | Matches the engineer's stated default; smallest Terraform diff (one new `services` entry); the ONE thing both stages share today (a shared thread pool) is removed | Extract and Transform still compete for the SAME thread pool inside Process A — the measured 390s/job `NormalizedCollectionConsumer` (Transform, per the engineer's own Sidekiq-metrics measurement) can still starve Extract's much faster jobs (~1.2s/job for the Enricher, per the same source) of threads within Process A, exactly the problem being solved for Load, just one tier up | Engineer-supplied context (this session did not independently verify these two numbers; no per-queue Extract latency was found in this session — see "What remains uncertain") |
| **3 processes**: Extract alone, Transform alone, Load alone | Isolates the measured 390s bottleneck from Extract's presumably-fast DB-cursor jobs; each stage scales on its own cost profile | One more ECS service to run, monitor, and (if self-scaling is adopted) orchestrate through the hand-off in Finding 2/6; Extract's OWN latency profile is not measured anywhere in this session, so the case FOR isolating it rests only on Transform's number, not on evidence that Extract is currently starved | Same as above |

Both shapes reuse the exact same terraform mechanism (Finding 4) — the fork here is a `services` map with 2 vs 3 non-`web`/`runner` entries, not a different kind of change.

### Table 2 — queue-isolation options (how a process is told which queues to run)

| Option | Mechanism | Terraform/code cost | Trade-off |
|---|---|---|---|
| **CLI `-q` flag per ECS service** | `command = ["bundle","exec","sidekiq","-q","database_extractor","-q","database_transformer","-c","<N>"]` in a new `services` map entry | Zero module change; a `terraform.tfvars`/`main.tf` edit per stack (Finding 4) | Each process still reads `config/sidekiq.yml`'s queue weights for the queues it DOES subscribe to (Sidekiq merges CLI queues with the file's weights for those names), so the shared config file stays the single source of relative priority; simplest to reason about and matches the codebase's existing web/worker/runner pattern exactly |
| **A second `config/sidekiq.yml`-equivalent per role** | A `sidekiq-load.yml` (or similar) referenced via `-C config/sidekiq-load.yml`, listing only the Load queues | Zero module change; adds a new file to the Rails repo, plus the same `command` edit as above | No material advantage over the `-q` flag for this fleet's queue count (11 queues, 3 stages) — it duplicates information (the queue list) between a new YAML file and Terraform's own knowledge of which queues exist, and 4Shark's own `sidekiq.yml` today is a single shared file across every role; splitting it is an extra file to keep in sync, for no behavior the `-q` flag doesn't already give |
| **Sidekiq Capsules (v7+/8)** | `config.capsule("load") { cap.concurrency = N; cap.queues = %w[api_loader_producer api_loader_consumer] }` inside ONE Sidekiq process | A Ruby code change (`config/initializers/sidekiq.rb`); no Terraform change, no new ECS service | Bounds Loading's THREAD concurrency inside the same process/task that also runs Extract+Transform's capsule — it does NOT give Loading its own ECS task count, so it cannot be scaled up/down independently of Extract+Transform at the infrastructure level, which is the stated goal. Two capsules still share the SAME Redis instance restriction (verified quote, Finding 5) — not a blocker here since everything already runs on one Redis, but worth naming as the one hard constraint Sidekiq itself imposes |

**The engineer's caveat is confirmed as real, independent of which option is chosen**: horizontally autoscaling a service that ALSO carries the Load queue (i.e., attaching `api_loader_producer`/`api_loader_consumer` to Process A or to any service whose `desired_count` an autoscaler is free to raise) multiplies Load concurrency by however many tasks that autoscaler adds — nothing in Sidekiq's per-process concurrency model limits the AGGREGATE concurrency across tasks (Finding 1's verified quotes: concurrency is per-process, weight only affects polling frequency). So whichever isolation option is picked, the service/capsule that owns `api_loader_producer`/`api_loader_consumer` has to be the one thing in the whole topology that is NEVER auto-scaled — its task count (or its capsule's `concurrency`) has to be a fixed, deliberately-set ceiling.

### Table 3 — self-orchestrating hand-off: how the scale changes actually happen

| Approach | Mechanism | IAM needed | Failure mode |
|---|---|---|---|
| **Hard `ecs:UpdateService --desired-count`** from inside a worker at the Finding 2 call sites | A new small worker (Processor-shaped, per `DATA-PROCESSING.md`'s naming convention — a single bounded unit, no fan-out) calls the AWS SDK directly | `ecs:UpdateService` + `ecs:DescribeServices` on the task role, scoped by ARN (Finding 6) | Relies entirely on Sidekiq's own TERM handling (Finding 7) for the service being scaled DOWN; if the scale-down races the drain (e.g. a retried job re-enters `database_transformer` from a delayed `perform_in` AFTER the `done?` check already read true — Finding 3 shows this specific race is not possible for the counters themselves, but nothing stops an operator-triggered retry or a manually re-run stream from doing the same thing at the wrong moment) the newly-scaled-to-zero service simply has no thread to pick the job up until the NEXT scale-up event |
| **Soft: TSTP-then-drain-then-`UpdateService`**, reusing the exact mechanism `integrator/.github/workflows/deploy.yaml:113-146` already uses for deploys | The same worker sends `kill -TSTP` to the outgoing service's Sidekiq PID via `aws ecs execute-command`, waits a fixed drain window, THEN calls `ecs:UpdateService` | Everything from the row above PLUS `ecs:ExecuteCommand` and the target task's own `ssmmessages:*` (already granted for ECS Exec per `iam_task_role.tf:72-91`, but the CALLING task additionally needs `ecs:ExecuteCommand` on the target) | Strictly safer against the same race (Sidekiq stops FETCHING new jobs before the scale-down even starts, so there is no window where a job is fetched by a thread that is about to disappear), at the cost of the extra IAM surface and of building/testing an in-app equivalent of a mechanism that today only exists as a GitHub Actions step, never as Ruby code |
| **No in-app scaling at all — EventBridge Scheduler on a FIXED time window** (the module's existing `scale_up_schedules`, Finding 6) | Extend the existing cron-based `scale_up_schedules` mechanism to also scale DOWN Extract+Transform and UP Load at a fixed clock time, instead of reacting to `Computation.done?` | None beyond what already exists (`deployments_scheduler` role already has `ecs:UpdateService`) | Zero new IAM, zero new application code — but the hand-off timing is a GUESS (a fixed clock offset from the known start time) rather than an exact signal, so it either wastes idle Load-service capacity waiting for a Transform run that finished early, or scales Load up too late for one that ran long. This does not meet the stated goal of scaling exactly WHEN Transform completes, but it is the cheapest option if the run's duration is predictable enough |

None of these three interacts with `Computation`'s counters (Finding 3) or the `Lock` class beyond READING `Computation#done?` at the same call site the pipeline itself already checks — no new counter, no new lock is needed for any of them. The standalone `Lock` class (key `"integrator"`) is held only for the duration of `Job::Starter#perform` (`app/workers/job/starter.rb:10-70` — acquired at line 10, released in the `ensure` at line 70) and has nothing to do with stage transitions; `Computation#acquire_lock`/`release_lock` is a SEPARATE guard used only around the report-generation step (`IntegrationReport::Producer`, `SourceCheckReport::Producer`, etc. — Finding in the queue-map auxiliary), not a pipeline-wide serialization mechanism. Neither lock needs to be touched by any of the three hand-off approaches above.

### Table 4 — where email/`report` jobs run

| Option | Trade-off |
|---|---|
| **`report` queue subscribed on ALL processes** (the engineer's stated decision) | Simplest — one line added to every process's `-q` list. A long `IntegrationReportMailer` send (Finding 8: synchronous, includes `.xlsx` generation) occupies one thread of WHICHEVER process happens to pick it up. If that process is the deliberately-small Load service, the mail job competes with the small, fixed thread pool that Table 2's caveat says must never be starved — a ~40-minute mail send (the number the engineer is willing to accept) could measurably reduce that service's real Loading throughput for its duration, exactly the resource the whole redesign exists to protect. On Extract+Transform's larger pool the same job is a much smaller percentage hit |
| **`report` on a dedicated (or Extract+Transform-only) process** | Removes the risk above entirely, at the cost of one more subscription decision to keep track of, and it stops being "every process subscribes" — a small deviation from the stated simplicity goal |

This is presented as a trade-off, not a correction — the engineer's proposal (subscribe everywhere) is internally consistent and was independently confirmed safe from a QUEUE-CORRECTNESS standpoint (Finding 8/9: `report` jobs never overlap with active stream processing in a way that would corrupt anything); the residual question is purely about competing for the Load service's deliberately scarce threads during the ~40 minutes such a job can run.

## Ancillary-queue-to-process mapping (from Finding 9, restated as a table for reference)

| Queue | Confirmed position | Natural process |
|---|---|---|
| `authorization`, `checkup` | Strictly pre-Extract (`Job::Starter` → `HealthCheck` → `Authorization` → `AvailabilityCheck` → `ThroughputProcessor` → Extract stage) | Extract+Transform process (or Extract-only, in the 3-process split) — no reason to run on Load |
| `report` | Either pre-Extract (failure/early-exit reports) or strictly post-Load (`IntegrationReport`, fired after `Job::Finisher`) | Per Table 4 — either "all processes" (engineer's decision) or Extract+Transform-only |
| `cold_storage` | Strictly post-report, end of pipeline | Extract+Transform process (it never overlaps with Load's active window — Load is already finished by the time `cold_storage` jobs exist) |
| `migration` | Deploy-time only, unrelated to any run | Any process, or none — since it never fires during a `Job::Starter` run, its presence or absence on a given process's `-q` list has no runtime interaction with the stage split |
| `default` | No worker in this codebase targets it explicitly (confirmed absent from the grep results) | No decision needed |

## What remains uncertain

- **Extract-stage per-job latency was not measured in this session.** Only Transform's `NormalizedCollectionConsumer` (~390s/job) and Enricher (~1.2s/job) numbers were supplied by the engineer as prior context; no Extract-stage equivalent (e.g. `Client::DatabaseCollectionExtractorConsumer`'s typical duration) was found or measured here. The 2-vs-3-process decision in Table 1 depends on this number, which the engineer's own Sidekiq metrics dashboard (the same source cited for the Transform numbers) would need to answer before Table 1 can be closed.
- **Whether the ECS task/container `stopTimeout` should be raised above the AWS default (30s) or Sidekiq's `-t` lowered/raised to coordinate with it** was not checked against the integrator's actual task definitions beyond confirming no override exists anywhere in `modules/ecs_service/` (Finding 7). This is a small, independent tuning question underneath whichever hand-off option (Table 3) is chosen.
- **OSS Sidekiq's recovery behavior when a process is SIGKILLed outright (no TERM/TSTP delivered at all — e.g. a Fargate Spot interruption, or a `stopTimeout` set below what Sidekiq needs)** was not verified in this session beyond the TERM/TSTP quotes in Finding 7. This affects how much residual risk the "hard" scale-down row of Table 3 carries versus the "soft" row.
- **The client API's actual rate/concurrency ceiling** (what triggers the Cloudflare rate-limit the engineer described) was stated by the engineer as context for this spike and was not independently sourced — it would come from the client's own documented API limits, not from anything in `~/Projects/4Shark/integrator` or `~/Projects/4Shark/terraform`.
- **Whether Sidekiq's CLI merges `-q` selections with `config/sidekiq.yml`'s per-queue WEIGHTS, or whether an explicit weight has to be repeated on the `-q` flag itself for each process** (`sidekiq -q api_loader_producer,10 -q api_loader_consumer,1` vs relying on the file) was described in Sidekiq's wiki for the general case but not tested against this repo's specific `sidekiq.yml` structure in this session.

## Suggested options for main and the engineer

- **Option A — 2 processes, CLI `-q` isolation, EventBridge-scheduled hand-off.** Cheapest to build (Finding 4, Table 3's third row): a `terraform.tfvars` edit per stack adding one `services` entry and extending `scale_up_schedules`, zero IAM change, zero Ruby change. Accepts a fixed-clock hand-off rather than a reactive one, and leaves Extract sharing a thread pool with Transform's known 390s bottleneck.
- **Option B — 2 or 3 processes, CLI `-q` isolation, in-app hard `ecs:UpdateService` hand-off.** Reactive to the actual `Computation.done?` signal (Finding 2/3), at the cost of one new module-level IAM statement (Finding 6) and one new small worker per hand-off direction. Carries the residual race named in Table 3's first row.
- **Option C — 2 or 3 processes, CLI `-q` isolation, in-app soft TSTP-then-drain hand-off**, replaying the exact mechanism the deploy pipeline already uses (Finding 7, Table 3's second row) as Ruby code instead of a GitHub Actions step. Safest against the fetch-race, largest IAM/code surface.
- **Option D — Sidekiq Capsules instead of separate ECS services** (Finding 5). Solves the thread-starvation half of the problem with a Ruby-only change and no Terraform/IAM surface at all, but does NOT give Loading an independently-scalable ECS task count, so it does not, on its own, satisfy the stated goal of each stage scaling as its own service. Could be combined with any of A/B/C for the Extract+Transform SIDE of the split (an Extract capsule and a Transform capsule inside one process) if the answer to the still-open Extract-latency question (see "What remains uncertain") shows the two need separating too.

Each option is independent on the 2-vs-3-process axis (Table 1), the queue-isolation axis (Table 2), and the hand-off axis (Table 3) — the engineer can mix a row from each table rather than choosing a single lettered bundle.
