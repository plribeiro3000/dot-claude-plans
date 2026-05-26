# Worker Autoscaling — ASG ↔ ECS coordination

## Status

**Open** — diagnosis concluded on 2026-05-08, implementation decision pending. Resume when there's a window.

## Problem

When the worker autoscaling Lambda decreases the ASG desired (scale-in), the ASG picks which instances to terminate using its own policy, without consulting ECS about task placement. Result: instances with active tasks may be terminated, killing workers in the middle of processing.

The Lambda sends two independent commands:
1. `set ECS service desired = N` (app-level, based on Hirefire queue depth)
2. `set ASG desired = N` (infra-level, lockstep with the above)

ASG and ECS do not talk to each other: the ASG picks which instances to kill on its own, and ECS places tasks on its own. On scale-in, it is a lottery — the ASG may happen to kill exactly the host where the active task lives.

## Evidence

Incident on 2026-05-08 at 18:51 UTC, in `shared-001-worker-commission-service`:

```
18:46:21 UTC — Lambda scale UP 1→3, Jobs: 1081
18:51:22 UTC — Lambda scale DOWN 3→1
18:51:28 UTC — ASG (shared-001-worker-commission-asg) terminated:
                 - i-0da6526579af3bd1b  (was running task 294971a48b2941bcbe46f9416e0e4dc4)
                 - i-0071a4e70e95cdbb7
              Survivor: i-0b5778babe5d8e088
19:02:01 UTC — Alarm `shared-001-ecs-service-down-shared-001-worker-commission-service` fired
19:16:19 UTC — ECS marked task 294971 as STOPPED
              StoppedReason: "Host EC2 (instance i-0da6526579af3bd1b) terminated."
              StopCode:      TerminationNotice
```

Cross-check: the replacement task `5894af20d95144fba5fee10b87ba6729` was placed on the surviving instance and Sidekiq registered normally on the dashboard. That is, **Sidekiq is not stuck** — what was missing is ASG/ECS coordination.

Same pattern observed earlier in `shared-001-worker-system-service` at 18:13 UTC: scale 8→1, 3 tasks with `ExitCode=null` (force-killed when the host was terminated under them).

## Impact

- Active tasks die ungracefully → jobs in processing may be silently lost (Sidekiq OSS without `reliable_fetch` does not re-enqueue jobs from the processing set after SIGKILL)
- `RunningTaskCount=0` window during task replacement → alarms fire
- Recurrence: happens on every burst that ends in scale-in (i.e., every day)

## Options considered

### 1. ECS ASG Capacity Provider with Managed Scaling — VIABLE

ECS takes control of the ASG `desired` via the `CapacityProviderReservation` metric. Enabling `managedTerminationProtection: ENABLED`, ECS marks `protectFromScaleIn=true` on the instances **that have active tasks**, forcing the ASG to only kill empty instances.

**No Fargate migration required** — keeps using the same current EC2 instances.

Required changes:
- Wrap the ASG (`shared-001-worker-*-asg`) in a capacity provider
- Enable `NewInstancesProtectedFromScaleIn` on the ASG
- Associate the capacity provider with the ECS service (in `defaultCapacityProviderStrategy`)
- **Remove from the Lambda the part that sets `ASG desired_capacity`** — ECS takes over
- Lambda keeps only `ECS service desiredCount` (app-level decision via Hirefire)

Canonical doc: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/asg-capacity-providers.html (sections "Auto Scaling group capacity providers" + "Managed termination protection").

Trade-offs:
- ✅ Solves the coordination at the source
- ✅ AWS-recommended pattern
- ✅ No additional cost
- ⚠️ Touches ASG, capacity provider, service and Lambda — not trivial
- ⚠️ Protection only applies to scale-in via ASG. Manual termination or spot interruption still kill (no spot in use today, OK)

### 2. Lambda picks which instance to terminate — DISCARDED

Lambda would use `terminate-instance-in-auto-scaling-group --should-decrement-desired-capacity` on a specific instance.

**Why discarded**: the Lambda has no way to know at runtime which instance is drained (with no active task).

### 3. Mark `protectFromScaleIn=true` on drained instances — DISCARDED

Same reason as #2: no mechanism to detect Sidekiq drain at runtime.

## Pending follow-ups

- [ ] Map the current state of the 3 `shared-001` ASGs (`worker-system-asg`, `worker-user-asg`, `worker-commission-asg`) — active termination policy, health-check configuration, lifecycle hooks
- [ ] Read the autoscaling Lambda code — identify where it touches the ASG, and why the `commission` Lambda has an extra layer `Aggregated capacity desired | Threshold for balancing lambda: 10.0` that does not appear in the `system` Lambda. May be a version/logic difference that needs separate handling
- [ ] Decide rollout: the 3 `shared-001` workers at once, or one by one (commission first, since that is where the original incident happened)
- [ ] Decide effect on the other environments (`beta-001`, `demo-001`, `app-atento-001`) — all have the same autoscaling Lambda pattern, so the change propagates

## Out of scope for this plan

The JVM pressure on the `app-shared-001` OpenSearch during a burst (504s → Sidekiq retries) is a **separate** problem. Mitigations already discussed (throttle the `deal_indexation` queue, tune the `deals` index `refresh_interval`) do not depend on this decision. If we want to address it, plan in a separate file.
