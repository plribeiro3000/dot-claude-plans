# SPIKE — ShutDownWorker does not shut down ECS after nightly integration

**Date:** 2026-04-10
**Context:** Clients maqnelson and almaviva were found with web/worker ECS running against a stopped Mongo. The integration had run the previous night (reports were delivered), but the ECS services stayed up generating connection-error logs in a loop.

## Question

Why does ECS keep running after the integration shutdown job ends, if Mongo is correctly shut down?

## Investigation

### 1. State observed at session start

Ran `bash ~/.claude/scripts/integrator-instances.sh --state running` and `integrator-services.sh --client <name>`:

| Client | EC2 Mongo | ECS web | ECS worker | ECS runner |
|---|---|---|---|---|
| maqnelson | stopped | 1/1 | 2/2 | 0/0 |
| almaviva | stopped | 1/1 | 2/2 | 0/0 |
| redebrasil | stopped | 0/0 | 0/0 | 0/0 |

Rede Brasil was consistent. Maqnelson and almaviva inconsistent: Mongo off, ECS on.

### 2. ECS logs — symptom

`/ecs/integrator-maqnelson-web` and `/ecs/integrator-maqnelson-worker` (last 24h) show a continuous loop:

```
MONGODB | Error checking 4client-maqnelson-mongo003:27017: SocketTimeoutError
MONGODB | Error checking 4client-maqnelson-mongo004:27017: EHOSTUNREACH (10.1.2.105:27017)
MONGODB | Error checking 4client-maqnelson-mongo005:27017: EHOSTUNREACH (10.1.2.88:27017)
```

Interleaved with `GET /health 200` (ALB health check keeping the task alive). Sidekiq processing jobs without being able to read Mongo.

### 3. GitHub Actions history

Queried via `gh run list`:

- `shutdown.yaml` is `workflow_dispatch` (manual). Last execution for maqnelson: **2026-04-09 23:32 UTC**, status success.
- Last execution for almaviva: **2026-04-07 13:49 UTC** — meaning almaviva had not been run manually for 3 days.
- `startup.yaml` is also manual. Last maqnelson: 2026-04-09 22:45 UTC.

Partial conclusion: the nightly flow is **not** triggered via GitHub Actions. It must be something else.

### 4. EventBridge Scheduler

`aws scheduler list-schedules` shows, per client:

| Schedule | Cron (UTC) |
|---|---|
| `integrator-maqnelson-start-mongodb` | `cron(20 1 * * ? *)` — 01:20 |
| `integrator-maqnelson-scale-up-worker` | `cron(25 1 * * ? *)` — 01:25 |
| `integrator-maqnelson-scale-up-web` | `cron(25 1 * * ? *)` — 01:25 |
| `integrator-almaviva-start-mongodb` | `cron(50 0 * * ? *)` — 00:50 |
| `integrator-almaviva-scale-up-worker/web` | `cron(55 0 * * ? *)` — 00:55 |
| `integrator-redebrasil-start-mongodb` | `cron(50 1 * * ? *)` — 01:50 |
| `integrator-redebrasil-scale-up-worker/web` | `cron(55 1 * * ? *)` — 01:55 |

**Only scale-up schedules exist.** None for scale-down. Scale-down is `ShutDownWorker`'s responsibility — it runs as the last Sidekiq job after the report consumers.

### 5. CloudTrail — who called what

`aws cloudtrail lookup-events` filtered by `userAgent`:

For maqnelson's mongo005 (last 5 days):

| Event | userAgent | Origin |
|---|---|---|
| 2026-04-10 02:51:26 StopInstances | `fog-core/2.6.0` | **ShutDownWorker** (IAM user `integrator-maqnelson`) |
| 2026-04-10 01:20:11 StartInstances | `AmazonEventBridgeScheduler` | scheduler `start-mongodb` |
| 2026-04-09 23:33:30 StopInstances | `aws-cli os/linux#...azure` | shutdown.yaml workflow (GH Actions runner) |
| 2026-04-09 22:46:04 StartInstances | `aws-cli os/linux#...azure` | startup.yaml workflow |
| 2026-04-09 02:42:23 StopInstances | `fog-core/2.6.0` | **ShutDownWorker** (previous night) |

For maqnelson's worker-service (UpdateService, 5 days):

```
2026-04-10 01:25:11  AssumedRole  scheduler-role    desiredCount: 2  ← scale-up-worker schedule
2026-04-09 01:25:11  AssumedRole  scheduler-role    desiredCount: 2  ← previous night
2026-04-08 01:25:11  AssumedRole  scheduler-role    desiredCount: 2  ← 2 nights ago
```

**No `UpdateService` via fog-core for scale-down.** `Ecs.scale_down` never reached AWS.

### 6. Integrator code

Sequence `ShutDownWorker#perform` → `Ec2.stop_machine` → `Ecs.scale_down`:

**`app/workers/shut_down_worker.rb`:**
```ruby
class ShutDownWorker < ApplicationWorker
  def perform
    return unless Rails.env.production?

    Ec2.stop_machine
    Ecs.scale_down
  end
end
```

Called from 13 places (all `*/consumer.rb` report consumers and `Resource::Producer`/`Resource::Consumer`) via `ShutDownWorker.perform_async if job.computation.done?`.

**`app/models/ec2.rb`:**
```ruby
def self.stop_machine
  return if ApplicationConfiguration.aws_instance_ids.blank?
  adapter.stop_instances(ApplicationConfiguration.aws_instance_ids)
end
```

**`app/models/ecs.rb`:**
```ruby
def self.scale_down
  adapter.update_service(
    'cluster' => ApplicationConfiguration.aws_ecs_cluster,
    'service' => ApplicationConfiguration.aws_ecs_worker_service,
    'desiredCount' => 0
  )
  adapter.update_service(
    'cluster' => ApplicationConfiguration.aws_ecs_cluster,
    'service' => ApplicationConfiguration.aws_ecs_web_service,
    'desiredCount' => 0
  )
rescue Fog::AWS::ECS::Error => e
  Rails.logger.warn("ECS scale down skipped: #{e.message}")
end
```

`Ecs.adapter` and `Ec2.adapter` are initialized in `config/initializers/fog.rb:16-27` via `Fog::Compute.new` and `Fog::AWS::ECS.new`.

**`lib/application_configuration.rb:169-185`:**
```ruby
def aws_ecs_cluster
  return if aws_ecs_environment.blank?
  "integrator-#{aws_ecs_environment}-cluster"
end

def aws_ecs_web_service
  return if aws_ecs_environment.blank?
  "integrator-#{aws_ecs_environment}-web-service"
end

def aws_ecs_worker_service
  return if aws_ecs_environment.blank?
  "integrator-#{aws_ecs_environment}-worker-service"
end
```

Reads from `ENV['AWS_ECS_ENVIRONMENT']`. In the current task def (`integrator-maqnelson-worker` rev 8) it is set as `maqnelson` (lowercase) — verified via `aws ecs describe-task-definition`.

### 7. Smoking gun — Sidekiq logs

Searched with `aws logs tail /ecs/integrator-maqnelson-worker --filter-pattern "scale down skipped"`:

**4 consecutive days, same error, same task, same time (~02:42–02:51 UTC):**

```
2026-04-07 01:49:01  ECS scale down skipped: AccessDeniedException => User: arn:aws:iam::405749097490:user/integrator-maqnelson
  is not authorized to perform: ecs:UpdateService on resource:
  arn:aws:ecs:sa-east-1:405749097490:service/integrator-Maqnelson-cluster/integrator-Maqnelson-worker-service
  because no identity-based policy allows the ecs:UpdateService action

2026-04-08 03:30:21  ECS scale down skipped: AccessDeniedException => ...integrator-Maqnelson-cluster...
2026-04-09 02:42:23  ECS scale down skipped: AccessDeniedException => ...integrator-Maqnelson-cluster...
2026-04-10 02:51:26  ECS scale down skipped: AccessDeniedException => ...integrator-Maqnelson-cluster...
```

And immediately after:
```
2026-04-10 02:51:25.969  class=ShutDownWorker: start
2026-04-10 02:51:26.756  class=ShutDownWorker elapsed=0.788: done
```

Sidekiq reports the job as **completed successfully** in 788ms.

For almaviva, same pattern, 3 days:
```
2026-04-08 01:02:52  ...integrator-Almaviva-cluster/integrator-Almaviva-worker-service...
2026-04-09 01:02:24  ...integrator-Almaviva-cluster...
2026-04-10 01:07:48  ...integrator-Almaviva-cluster...
```

## Root cause

Three stacked bugs in the shutdown flow:

### Bug 1 — `Ecs.scale_down` swallows the error silently

```ruby
rescue Fog::AWS::ECS::Error => e
  Rails.logger.warn("ECS scale down skipped: #{e.message}")
end
```

`AccessDeniedException` from fog-aws is a descendant of `Fog::AWS::ECS::Error`. The rescue catches it, logs a warning, and the method returns normally. Sidekiq marks the job as `done`. **No alarm reaches anyone.**

### Bug 2 — IAM user `integrator-{client}` missing `ecs:UpdateService`

The user used by fog (credentials passed via env var to the container) has permission for `ec2:StopInstances`/`StartInstances` but **does not have** `ecs:UpdateService`. That is why the AWS call returns 403.

### Bug 3 — Capitalized cluster name: `integrator-Maqnelson-cluster`

Even if the IAM user had the permission, the resource would be wrong. The error shows `integrator-Maqnelson-cluster` (capital M) and `integrator-Almaviva-cluster` (capital A). The real resource is `integrator-maqnelson-cluster` (lowercase).

Likely origin: `config/deploy/maqnelson.rb:3 → set :environment_name, 'Maqnelson'` (legacy Capistrano). Or an old revision of the task definition with `AWS_ECS_ENVIRONMENT=Maqnelson`. The current revision (8) is correct with `maqnelson`, but the errors show that at some point it was capitalized — could be drift or inheritance from another var.

**Important:** deriving the correct form from `CLIENT_NAME` (used for report titles) **does not work**, because commercial names diverge from resource slugs:
- `CLIENT_NAME=Atento México` → resource slug `atento-mx`, not `atento-mexico`.
- The derivation would need a manual mapping table, which is fragile and unnecessary.

The variable for resource names (`AWS_ECS_ENVIRONMENT`) **already exists** and is separate from `CLIENT_NAME`. What is missing is enforcing consistency across every client in Terraform.

### Why the cycle was perpetuating itself

1. Night 1 — Scheduler 00:55/01:25 UTC brings Mongo and ECS up
2. Integration runs, reports finish, each consumer calls `ShutDownWorker.perform_async`
3. ShutDownWorker: `Ec2.stop_machine` → Mongo stops ✓
4. ShutDownWorker: `Ecs.scale_down` → AccessDenied → rescue → warn → done
5. ECS stays up until an engineer notices (in this case, me/Paulo the next day)
6. Next night the scheduler finds ECS already at 2/1, `update-service desired-count=2` is a no-op
7. Mongo comes up, the integration runs on top of an ECS that **never came down** — reports are delivered, no one notices
8. The cycle repeats

Confirmed: 4 consecutive days for maqnelson, 3 for almaviva.

## Actions taken during the session

Only corrective state actions (no code changes):

- Manual scale down of `integrator-maqnelson-web-service` and `worker-service` to 0
- Manual scale down of `integrator-almaviva-web-service` and `worker-service` to 0
- Redebrasil was already 0/0 — no action

Final state of all three: Mongo stopped + ECS 0/0.

## Artifacts generated

- `/tmp/cloudtrail_maqnelson_20260410_153452.json` — CloudTrail UpdateService maqnelson-worker-service
- `/tmp/cloudtrail_mongo_stops_20260410_*.json` — CloudTrail StartInstances/StopInstances mongo003 maqnelson
- `/tmp/logs_ecs_maqnelson_web_20260410_150234.log` — web maqnelson logs
- `/tmp/logs_ecs_maqnelson_worker_20260410_150438.log` — worker maqnelson logs
- `/tmp/logs_shutdownworker_maqnelson_*.log` — ShutDownWorker filter
