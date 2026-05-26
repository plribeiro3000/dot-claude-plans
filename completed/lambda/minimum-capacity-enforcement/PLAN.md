# Plan: Minimum Capacity Enforcement on Autoscaling Lambdas

**Status:** ⛔ ABANDONED — The root cause was identified as an external event (deploy/manual action), not a Lambda responsibility. The Lambdas don't need to handle this scenario; the fix belongs at the infrastructure level.

## Context

The autoscaling Lambdas were designed assuming `current_capacity` would never be below `minimum_capacity`. An external event (deploy, manual action, other automation) caused all three ECS services in `shared-001` to drop to 0 tasks, while `MINIMUM_CAPACITY=1`. The Lambdas couldn't recover because this scenario was never part of the scaling logic.

This is not a bug fix - it's a new scenario that needs to be part of the scaling decision from the ground up. The scaling logic will be restructured so that minimum enforcement is the first check in the decision tree, not a patch added on top.

## Scaling Scenarios (Domain)

The Lambda must handle these scenarios, in this priority order:

| Priority | Scenario | Condition | Action |
|----------|----------|-----------|--------|
| 1 | Below minimum | `current < minimum` | Enforce minimum (ASG + ECS), ignoring lock |
| 2 | Scale up | `jobs > 0`, `new > current`, unlocked | Scale up to calculated capacity |
| 3 | Capacity sufficient | `jobs > 0`, `new <= current` | No action |
| 4 | Scale down (hysteresis) | `jobs == 0`, `current > minimum`, threshold met, unlocked | Scale down to minimum |
| 5 | Scale down (waiting) | `jobs == 0`, `current > minimum`, threshold not met | Increment counter |
| 6 | At minimum | `jobs == 0`, `current == minimum` | No action, clear counter |

Lock behavior: Scenario 1 ignores the lock because the balancing lambda itself clamps to minimum (line 108 of balancing lambda), so `current < minimum` is always an external anomaly.

## Decision Tree

### Current structure (what exists today)

```
if jobs > 0
  calculate new_capacity (clamped to min/max)
  if unlocked AND new > current → scale up
  else → no action
else (jobs == 0)
  if current > minimum
    hysteresis logic → scale down to minimum
  else
    "at minimum" → no action   ← BUG: 0 < 1 falls here
```

### New structure

```
if current < minimum                         ← NEW (scenario 1)
  enforce minimum (ASG + ECS)
elsif jobs > 0                               ← existing (scenarios 2-3)
  calculate new_capacity (clamped to min/max)
  if unlocked AND new > current → scale up
  else → no action
elsif current > minimum                      ← existing (scenarios 4-6)
  hysteresis logic → scale down to minimum
else                                         ← existing (scenario 6)
  "at minimum" → no action
```

The change: one single `if/elsif/elsif/else` tree where boundary enforcement comes first, demand-based scaling second, idle management third. Same structure in both Lambdas.

## Files to Modify

1. `worker-autoscaling/lambda_function.rb` - Restructure scaling decision
2. `worker-commission-autoscaling/lambda_function.rb` - Restructure scaling decision
3. `CHANGELOG.md` - Update entry

## Implementation

### 1. worker-autoscaling/lambda_function.rb

**Revert** the previous patch (lines 89-110 added earlier).

**Restructure** lines 89-152 (the entire scaling decision block) into:

```ruby
if current_capacity < minimum_capacity
  # Scenario 1: Below minimum - enforce immediately
  auto_scaling_client = Aws::AutoScaling::Client.new(region: aws_region)
  auto_scaling_client.update_auto_scaling_group(
    auto_scaling_group_name: auto_scaling_group_name,
    min_size: minimum_capacity,
    max_size: maximum_capacity,
    desired_capacity: minimum_capacity
  )
  LOGGER.info("Auto Scaling Group: #{auto_scaling_group_name} | Set min_size: #{minimum_capacity}, max_size: #{maximum_capacity}, desired_capacity: #{minimum_capacity}")

  ecs_client.update_service(
    cluster: ecs_cluster_name,
    service: ecs_service_name,
    desired_count: minimum_capacity
  )

  REDIS.del(redis_key)
  LOGGER.info("ECS Service: #{ecs_service_name} | Below minimum capacity: #{current_capacity} → #{minimum_capacity}")
elsif jobs_in_queue > 0
  # Scenarios 2-3: Demand-based scaling
  required_capacity = (jobs_in_queue.to_f / jobs_per_process).ceil
  new_capacity = required_capacity.clamp(minimum_capacity, maximum_capacity)

  if unlocked && new_capacity > current_capacity
    auto_scaling_client = Aws::AutoScaling::Client.new(region: aws_region)
    auto_scaling_client.update_auto_scaling_group(...)
    ecs_client.update_service(...)
    REDIS.del(redis_key)
    LOGGER.info("... Scale UP ...")
  else
    LOGGER.info("... No scale up needed ...")
  end
elsif current_capacity > minimum_capacity
  # Scenarios 4-6: Idle management (hysteresis)
  empty_checks = REDIS.incrby(redis_key, 1)
  REDIS.expire(redis_key, redis_ttl)

  if unlocked && empty_checks >= empty_queue_check_threshold
    ecs_client.update_service(desired_count: minimum_capacity)
    # ASG update + logging (existing code)
    REDIS.del(redis_key)
  else
    LOGGER.info("... Downscale skipped ...")
  end
else
  # At minimum capacity, no action needed
  REDIS.del(redis_key)
  LOGGER.info("ECS Service: #{ecs_service_name} | Already at minimum capacity (#{minimum_capacity})")
end
```

The internal logic of each branch stays exactly as it is today. Only the structure of the decision changes.

### 2. worker-commission-autoscaling/lambda_function.rb

**Revert** the previous patch (lines 107-128 added earlier).

**Same restructure** as worker-autoscaling, applied to lines 116-183.

Note: Job history save (lines 97-101) and `empty_checks_key` (line 103) stay BEFORE the decision tree. The aggregated capacity calculation (lines 107-114) moves AFTER the decision tree, or the `current < minimum` branch returns early (skipping aggregated check and balancing trigger - recovery takes priority over balancing).

The below-minimum branch returns early with `{ status: 'below_minimum_enforced', ... }`, skipping the aggregated capacity check and balancing trigger at the end. This is correct because:
- Recovery from below-minimum is the highest priority
- Next invocation (1 min later) will handle normal scaling and balancing
- The job history was already saved to Redis before the decision, so no data is lost

### 3. CHANGELOG.md

Keep the existing `[Unreleased]` entry (already added), adjust wording if needed.

## What Does NOT Change

- `worker-commission-balancing/lambda_function.rb` - Already clamps to minimum at line 108
- Environment variables - No changes
- Lock mechanism - No changes (new scenario ignores lock by design)
- Hysteresis logic - Internal behavior unchanged
- Scale-up logic - Internal behavior unchanged
- Job history save - Stays before the decision tree
- Aggregated capacity check (commission) - Stays after the decision tree

## Verification

1. Code review: Each branch of the if/elsif/else maps to the scenario table above
2. Build: `bin/generate_lambda` generates new artifacts
3. Deploy to shared-001 and verify via CloudWatch logs:
   - Normal operation shows identical behavior to current version
   - When capacity drops below minimum, new log line appears: "Below minimum capacity: X → Y"
