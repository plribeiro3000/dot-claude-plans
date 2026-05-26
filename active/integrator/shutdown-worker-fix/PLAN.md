# PLAN — Fix `ShutDownWorker` to shut down ECS at the end of the integration

**Project:** integrator
**Input:** `SPIKE.md` in this directory
**Date:** 2026-04-10

## Problem

`ShutDownWorker` finishes reporting success, but **never scales ECS to 0**. The `AccessDeniedException` on the `ecs:UpdateService` call is swallowed by a `rescue Fog::AWS::ECS::Error` that only writes a warning. Result: web + worker ECS run day and night against a stopped Mongo, generating a connection-error loop that is invisible to anyone who does not look at the logs. It has been at least 4 days for maqnelson and 3 for almaviva.

Full details in `SPIKE.md`.

## Scope

**In scope for this fix (this PR in the `integrator` repo):**

1. Remove the silent `rescue` in `Ecs.scale_down` — let the error blow up.
2. Split `scale_down` into two steps: **web first, worker last**.
3. Keep the order `Ec2.stop_machine` → `Ecs.scale_down` in `ShutDownWorker` (Mongo first, ECS later).

**Out of scope (split as follow-ups):**

- **IAM `ecs:UpdateService` for `integrator-{client}`** — Terraform fix. Another session is working on Terraform now; this fix goes in afterwards as a separate PR in the `terraform` repo. Cannot be opened here because the error only disappears once the policy is updated.
- **Capitalized `CLIENT_NAME` vs AWS resource slug** — confirm that every task def has `AWS_ECS_ENVIRONMENT` in the correct slug format. Also Terraform. Also a separate PR.
- **Create scale-down schedule in EventBridge** — alternative discussed, but decided NOT to follow this path. See "Decisions made".

## Decisions made

### Decision 1 — Keep the `Mongo → ECS` order, do NOT invert it

**Why:** `ShutDownWorker` itself runs inside a `worker-service` task. If ECS is scaled to 0 first, the container receives SIGTERM and Sidekiq starts a graceful shutdown — the current job (`ShutDownWorker`) may be interrupted before it calls `Ec2.stop_machine`. Then Mongo never shuts down.

The correct order **is**: stop Mongo first (via fog), then ask ECS to shut itself down.

_(A reading correction made mid-session. Paulo corrected me: "Sidekiq is running on ECS. If you take down ECS, you cannot take down Mongo. The first thing to take down is Mongo.")_

### Decision 2 — Remove the `rescue Fog::AWS::ECS::Error` from `Ecs.scale_down`

**Why:** The current rescue guarantees that any error becomes a silent warning and the job finishes successfully. That is worse than not having a rescue:
- If the error is transient (rate limit, glitch), Sidekiq retry would try again automatically — with the rescue, it does not.
- If the error is permanent (permission, config), it needs to be seen — with the rescue, it goes unnoticed indefinitely (4 days in this case).

**Desired policy:** error blows up → Sidekiq retry → if it recovers, great; if it does not, the engineer sees the job in the retry queue in the morning and fixes it manually.

### Decision 3 — Order inside scale_down: `web` first, `worker` last

**Why:** Scaling `worker-service` to 0 kills the very task that is running `ShutDownWorker`. It must be the last step of the job so the execution is not cut in half.

`web-service` can be scaled first without affecting the worker. Resolved: web, then worker.

_(Without the rescue swallowing the error, this order is safe: if web fails, worker is not touched, the error blows up, and nobody sits in a partial silent state.)_

### Decision 4 — Do NOT move shutdown to EventBridge

**Alternative considered:** create `scale-down-web` and `scale-down-worker` schedules in EventBridge, equivalent to the existing `scale-up-*`. That way the shutdown responsibility lives outside the worker.

**Why not:**
- It is impossible to know in advance _when_ processing finishes. A small client finishes in 20 min, a large one in 4h. A fixed cron time either shuts down before processing finishes, or wastes a lot of time running.
- Sidekiq knows exactly when it finishes (the `Consumer.computation.done?`). That signal already exists and works.
- Keeping the logic in `ShutDownWorker` is simpler and does not introduce a new point of failure.

## Planned code changes

### `app/models/ecs.rb`

Split `scale_down` into `scale_down_web` and `scale_down_worker`, remove the rescue:

```ruby
class Ecs
  class << self
    attr_accessor :adapter
  end

  def self.scale_down_web
    adapter.update_service(
      'cluster' => ApplicationConfiguration.aws_ecs_cluster,
      'service' => ApplicationConfiguration.aws_ecs_web_service,
      'desiredCount' => 0
    )
  end

  def self.scale_down_worker
    adapter.update_service(
      'cluster' => ApplicationConfiguration.aws_ecs_cluster,
      'service' => ApplicationConfiguration.aws_ecs_worker_service,
      'desiredCount' => 0
    )
  end
end
```

No `rescue`. No unified `scale_down` method (the ordering logic moves to the worker).

### `app/workers/shut_down_worker.rb`

```ruby
class ShutDownWorker < ApplicationWorker
  def perform
    return unless Rails.env.production?

    Ec2.stop_machine        # 1. stop Mongo
    Ecs.scale_down_web      # 2. scale web to 0
    Ecs.scale_down_worker   # 3. scale worker to 0 — kill the container itself last
  end
end
```

Fixed order, no rescue, no intermediate abstraction.

## Execution phases

### Phase 1 — Code fix (this PR)

1. Create branch `fix/shutdown-worker-scale-down` from `develop`
2. Apply the changes in `app/models/ecs.rb` and `app/workers/shut_down_worker.rb`
3. Update `CHANGELOG.md` (entry `### Fixed` — "Integration shutdown")
4. Open PR against `develop`

**Important:** Another session is active on the integrator right now. This phase only begins after it finishes — **check beforehand** for conflicting changes in `app/models/ecs.rb`, `app/workers/shut_down_worker.rb`, or `lib/application_configuration.rb`.

### Phase 2 — IAM fix (separate PR, different repo)

After this PR lands on develop, the fix **still does not work in production** because the IAM user lacks `ecs:UpdateService`. Open a PR in the `terraform` repo adding the permission. Coordinate merge order: **terraform first, integrator deploy after** — if reversed, `ShutDownWorker` will blow up in production the next night and leave Mongo up.

Or: merge the integrator fix but **do not deploy** until Terraform is applied. Whichever is easier to coordinate at the time.

### Phase 3 — `AWS_ECS_ENVIRONMENT` audit (Terraform)

Separately: confirm every client has `AWS_ECS_ENVIRONMENT` set to the correct lowercase slug in every task definition. Look where the capitalized `Maqnelson`/`Almaviva` may be coming from:

- `config/deploy/maqnelson.rb:3` (legacy Capistrano — could be a forgotten source)
- Old task definitions still active
- Variables accidentally inherited from `CLIENT_NAME` in some Terraform module

This is a separate PR/investigation in the `terraform` repo.

## Risks

- **Risk 1 — Phase 1 without Phase 2:** if this PR goes to production before IAM is fixed, the first `ShutDownWorker` execution will blow up with `AccessDeniedException`, Sidekiq will enter a retry loop, and Mongo stays up (because `Ec2.stop_machine` already ran before). The state is the **opposite** of the current bug — visible, but a false problem. Mitigation: coordinate deploy with Phase 2, or ignore (the alert will draw attention, which is the goal).
- **Risk 2 — `AWS_ECS_ENVIRONMENT` drift:** even with IAM correct, if some client still has the var capitalized, `UpdateService` will fail against the wrong cluster. Phase 3 should clean this up before trusting Phase 1 100%. Mitigation: after deploy, monitor `ShutDownWorker` logs for 2-3 nights across the active clients.
- **Risk 3 — Another session touching the same files:** if the active integrator session edits `ecs.rb` or `shut_down_worker.rb` right now, there will be a conflict. Mitigation: check `git status`/`git log` on the integrator before starting.

## Validation

How to know the fix worked (after Phase 1 + Phase 2 in production):

1. Logs in `/ecs/integrator-maqnelson-worker` the night after the deploy must NOT contain `scale down skipped`
2. CloudTrail must show 2 `UpdateService` events via `fog-core` per client per night: one on `web-service`, one on `worker-service`, both with `desiredCount: 0`
3. `aws ecs describe-services` right after the expected integration end time must show `runningCount: 0` and `desiredCount: 0`
4. The next day, before the `scale-up-*` schedule runs, every service must be 0/0 and every Mongo must be `stopped`

## Operational notes

- Current state (end of this session): maqnelson, almaviva, redebrasil — all ECS 0/0 + Mongo stopped. Manually corrected during the investigation.
- Next night without the fix: scheduler will bring ECS back up at 00:55/01:25/01:55 UTC. If nothing is done by then, maqnelson and almaviva go back to the bug state (Sidekiq running against a stopped Mongo). Redebrasil also enters the same state because the bug is the same.
- If a PR cannot be opened today, at least disable the `scale-up-*` schedules for the 3 clients until the fix is in production, to avoid accumulating one more day of errors.
