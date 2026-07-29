# Integrator — develop images deployed to productive environments (2026-07-28)

Handoff record for the incident of 2026-07-28. Written so a cold reader (or a new session) can pick up the open items without re-deriving anything.

## What happened

The integration of a productive integrator environment stopped with `NoMethodError: undefined method 'none?' for class Stream`, raised in `app/workers/job/starter.rb:11`.

`Job::Starter` is the first worker of the whole pipeline. It raises on line 11, which is *before* `Job.start` on line 32 — so no `Job` document, no `SourceCheck`/`StreamCheck` rows, and no extractor was ever enqueued. The `ensure Lock.delete(LOCK_KEY)` block ran on every attempt, so no integration lock was ever left held. **No partial data, nothing to unwind.**

## Root cause — two independent defects

**1. The code defect.** `Stream.none?` does not exist. Mongoid delegates `none` (the empty-criteria builder) at the model class level — `mongoid-9.1.0/lib/mongoid/findable.rb:45` — but never `none?`. The only `none?` in the whole gem is an `Array` call in `association/accessors.rb:165`. Same on 9.0.11, so this is not an upgrade regression. `none?` works on a `Criteria` (which includes `Enumerable`), which is why `Source.normalized.none?` in `app/workers/throughput_processor.rb:14` never broke and the shape looked plausible in review.

The line was introduced by commit `5c0aee45` (2026-05-06, `refactor(integrator): drive database config from Source`), which created the file. It lives **only on develop** — `origin/master` has no `app/workers/job/starter.rb` at all; its entry points are still `database_integrator.rb` / `managed_integrator.rb`.

**2. The delivery defect — why develop code reached a productive environment.** `.github/workflows/build.yaml` builds `on: push: branches: [master]` plus `workflow_dispatch`. On 2026-07-28 between 13:11 and 13:28 UTC, eleven `workflow_dispatch` runs of `build.yaml` were fired **from branch `develop`**, one per integrator, overwriting `:latest` in eleven of the twelve integrator ECR repositories with `8.4.23-18fdf25` (SHA = `origin/develop` HEAD). Only `integrator-redebrasil` was untouched and stayed on `8.4.23-5efc1f5` (SHA = `origin/master` HEAD).

No deploy ran that day. The task definitions pin `:latest`, so the ECS scale-up schedule alone was enough to launch tasks on the new image.

**Trap worth remembering:** both branches report VERSION `8.4.23` (develop's `config/version.rb` is never bumped outside a release), so the image tag `8.4.23-<sha>` looks identical at a glance. **Only the SHA distinguishes master from develop.**

## What was done

Rebuilt `:latest` from `master` for all eleven affected integrators (`build.yaml --ref master -f integrator=<slug>`), then ran `deploy.yaml` for each. The deploy's composite action pins `<ecr-repo>:latest` (`.github/actions/deploy/action.yaml:56`) and calls `aws ecs update-service --force-new-deployment` (line 105) — the ref passed at dispatch never decides the code, only the image tag does, so build-then-deploy is the required order.

Two deploys (`almaviva`, `maqnelson`) failed at the preflight step `Check MongoDB instances are running` because their three MongoDB nodes each were stopped outside the integration window. The workflow aborts there before touching anything. The six instances were started with `~/.claude/scripts/start-instance.sh`, `aws ec2 wait instance-status-ok` was awaited on all six, and both deploys were re-dispatched and succeeded.

Verified afterwards: all twelve ECR repositories carry `:latest` = `8.4.23-5efc1f5`. For the affected productive environment specifically, the two running worker tasks report image digest `sha256:f5d481940bb5fea79d7584584a170779b347b64efd31b7920bd83e52f975c5ce`, identical to what ECR reports for that tag — digest-level proof, not trust in a mutable tag.

The Sidekiq retry entry left over from the develop-code failure was deleted manually via Sidekiq Web. It had flipped from `NoMethodError: undefined method 'none?' for class Stream` to `NameError: uninitialized constant Job::Starter` — the payload stores the class *name* as a string, so once the container ran master the constant no longer resolved. That transition is itself independent confirmation the running code changed from develop to master.

The integration was then restarted manually via the runner task, since the EventBridge schedule (`cron(0 10 * * ? *)`, timezone `America/Santiago`) fires once a day and had already fired:

```
aws ecs run-task --cluster integrator-<slug>-cluster --task-definition integrator-<slug>-runner --launch-type FARGATE --network-configuration 'awsvpcConfiguration={subnets=[...],securityGroups=[...],assignPublicIp=DISABLED}' --overrides '{"containerOverrides":[{"name":"integrator-<slug>-runner","command":["bin/rails","integration:cron"]}]}' --count 1 --region sa-east-1
```

Use `integration:cron`, never `integration:start` — on master the latter reads `$stdin.gets` when `auto_accept?` is off and hangs the Fargate task.

## Open items

**1. The code fix is not merged and no longer exists anywhere.** PR #2285 carried it and was closed; its branch was deleted locally and remotely. Nothing on develop today fixes `Stream.none?`. **The next release of develop to master ships this bug straight to every productive environment.** The fix that was validated:

```ruby
streams_count = Stream.count

if streams_count.zero?
  MissingStreamsReport::Producer.perform_async
  return
end
```

The count goes into a local variable rather than inline `Stream.count.zero?` because RuboCop's `Style/CollectionQuerying` autocorrects that inline chain to `none?` — the exact call that does not exist on a Mongoid model class, and the likely origin of the bug. The local variable also matches `enabled_streams_count` three lines below. No lint config was changed and no inline disable was used.

**2. `Style/CollectionQuerying` will recreate this bug.** The cop treats any `.count.zero?` as a Ruby collection and rewrites it to `none?`. Against a Mongoid model class that is always wrong. Scoping it away from Mongoid receivers (`AllowedReceivers`) belongs in `rubocop-fourshark`, and is the engineer's call per the Linting Policy.

**3. `build.yaml` has no guard and no develop trigger.** The intended rule — staging builds on merge to develop, productive builds only from master — is not implemented on either branch. There is no develop trigger at all, and `workflow_dispatch` accepts any ref combined with any integrator, productive included. That is the door this incident walked through, and it is still open.

**4. Not investigated: the other ten integrators.** The affected productive environment crashed before writing anything, so its data is untouched. The other ten run on their own schedules and were not checked for whether any of them executed develop code far enough to write. The engineer judged this unnecessary because two of them ran that day without incident.

## Reference

A rendered timeline of the incident was written to `/tmp/annotated_timeline_integrator_develop_build_incident_20260728_1145.html`. It is in `/tmp` and will not survive a reboot — this document is the durable record.
