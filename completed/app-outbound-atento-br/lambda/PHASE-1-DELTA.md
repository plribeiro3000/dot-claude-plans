# Phase 1 — Lambda ASG → Fargate Delta

> Reference reading: `/Users/plribeiro3000/Projects/4Shark/lambda/worker-autoscaling/lambda_function.rb`,
> `/Users/plribeiro3000/Projects/4Shark/lambda/worker-autoscaling/README.md`,
> `/Users/plribeiro3000/Projects/4Shark/terraform/app-atento-001/compute.tf`,
> `/Users/plribeiro3000/Projects/4Shark/terraform/modules/lambda-ecs-autoscaling/`,
> `/Users/plribeiro3000/Projects/4Shark/terraform/modules/lambda-iam/main.tf`.

This document is the deliverable of PLAN.md Phase 1. It freezes the interface of the new
`worker-payroll-autoscaling` Lambda **before** a single line of code is written in Phase 4.

---

## 1. ASG code to remove

All of the following statements in `worker-autoscaling/lambda_function.rb` disappear in the
Fargate variant:

| Line | Statement | Removal reason |
|------|-----------|----------------|
| 6 | `require 'aws-sdk-autoscaling'` | No ASG SDK used |
| 31 | `ENV.fetch('AUTO_SCALING_GROUP_NAME') { ... }` | No ASG exists |
| 50 | `Aws::AutoScaling::Client.new(region: aws_region)` | No ASG client |
| 53–54 | `describe_auto_scaling_groups(...)` + `.first` | No ASG read |
| 56–59 | `if auto_scaling_group.nil?` error branch | Not applicable |
| 61–62 | `auto_scaling_group.min_size` / `.max_size` | Replaced by env vars |
| 63 | `LOGGER.info("Auto Scaling Group: ...")` | Irrelevant in Fargate |
| 106–110 | Scale-up `update_auto_scaling_group(desired_capacity: new_capacity)` | ECS Fargate has no host layer |
| 136–145 | Scale-down `update_auto_scaling_group(desired_capacity: minimum_capacity)` | Same |

Fargate tasks schedule directly via `ecs:UpdateService(desired_count)` — there is no host
capacity to pre-provision and no ASG ordering concern (the comment at line 105 — "Update Auto
Scaling Group first to ensure EC2 capacity is available" — does not apply).

---

## 2. Final environment variable interface

| Variable | Required | Default | Source | Notes |
|----------|----------|---------|--------|-------|
| `ECS_CLUSTER_NAME` | Yes | — | Terraform | `app-outbound-atento-br-cluster` |
| `ECS_SERVICE_NAME` | Yes | — | Terraform | `app-outbound-atento-br-worker-payroll-service` |
| `METRICS_ENDPOINT` | Yes | — | Terraform | Same endpoint used by `app-atento-001`; reached cross-region over HTTPS |
| `PROCESS_NAME` | Yes | — | Phase 0 (blocked) | Sidekiq outbound process name reported by the metrics endpoint |
| `REDIS_URL` | Yes | — | SSM | Same Redis as `app-atento-001`; cross-region from sa-east-1 |
| `MINIMUM_CAPACITY` | **Yes (new)** | — | Terraform | `0` — scale-to-zero baseline |
| `MAXIMUM_CAPACITY` | **Yes (new)** | — | Terraform | `5` — mirrors EC2 count |
| `AWS_REGION` | No | **`sa-east-1`** (was `us-east-1`) | Terraform | Outbound cluster region |
| `EMPTY_QUEUE_CHECK_THRESHOLD` | No | `3` | Terraform | Unchanged |
| `JOBS_PER_PROCESS` | No | `500` | Terraform | Unchanged |
| `REDIS_KEY_TTL` | No | `600` | Terraform | Unchanged |
| `REDIS_TIMEOUT` | No | `5` | Terraform | Unchanged |

**Removed:** `AUTO_SCALING_GROUP_NAME` (the only variable gone from the original interface).

**Important Terraform note:** `modules/lambda-ecs-autoscaling/main.tf:44–46` uses
`lifecycle { ignore_changes = [environment] }`. Env vars are **not** managed by Terraform — they
must be set on the Lambda via AWS Console or CLI after the Lambda is created. This is already
how `app-atento-001` works. Phase 7 must document this as part of the deploy procedure, not
as a Terraform resource.

---

## 3. Logic preserved (no changes needed)

- Redis lock check: `lock_key = "ecs_scaling:lock:#{ecs_cluster_name}"` → lock key is
  `ecs_scaling:lock:app-outbound-atento-br-cluster` for the outbound cluster
- Empty-queue hysteresis counter: `ecs_scaling:empty_checks:#{ecs_service_name}`
- Metrics polling via `Net::HTTP` against `METRICS_ENDPOINT`
- Scale-up formula: `ceil(jobs_in_queue / JOBS_PER_PROCESS)` clamped to
  `[MINIMUM_CAPACITY, MAXIMUM_CAPACITY]`
- Scale-down only after `EMPTY_QUEUE_CHECK_THRESHOLD` consecutive empty checks
- `desired_count = 0` path works for free because `MINIMUM_CAPACITY = 0`

---

## 4. Gemfile delta

Remove `gem 'aws-sdk-autoscaling'`. Resulting Gemfile for `worker-payroll-autoscaling`:

```ruby
# frozen_string_literal: true

source 'https://rubygems.org'

gem 'aws-sdk-ecs'
gem 'bigdecimal'
gem 'redis'
```

Rebuild `Gemfile.lock` locally with `bundle install` before packaging.

---

## 5. IAM delta (affects Phase 7)

The existing `modules/lambda-iam` exposes three role ARNs (see
`terraform/modules/lambda-iam/main.tf:156–244`):

- `lambda_commission_autoscaling` — CloudWatch + ECS + ASG (+ invoke balancing)
- `lambda_commission_balancing` — same three
- `lambda_standard_autoscaling` — CloudWatch + ECS + ASG

All three attach `autoscaling_lambda_worker` (lines 61–84), which grants
`autoscaling:DescribeAutoScalingGroups` and `autoscaling:UpdateAutoScalingGroup`. The outbound
Lambda does not need these.

**Phase 7 must create a new, outbound-specific IAM role** (for example
`Lambda-app-outbound-atento-br-worker-payroll-autoscaling-role`) with only:

- `CloudWatch-${env}-lambda-logs-policy` (reusable — same pattern)
- `ECS-${env}-lambda-worker-policy` (reusable — scoped to the outbound cluster)

Do **not** reuse `lambda_standard_autoscaling` from `modules/lambda-iam`: that role is wired
against the `atento-001` cluster and carries ASG privileges the outbound Lambda should not hold.

Two implementation options for Phase 7 (decide then):

- **Option A:** inline the role + ECS policy + CloudWatch policy in
  `app-outbound-atento-br/iam.tf` (simpler, one-off stack)
- **Option B:** extend `modules/lambda-iam` with an optional `outbound_autoscaling_role = true`
  flag that creates a Fargate-only role (CloudWatch + ECS, no ASG)

Option A is cheaper unless a second outbound stack appears; Option B earns its keep when the
pattern is repeated. Flag for decision in Phase 7.

---

## 6. Packaging / upload (Phase 4)

The existing `worker-autoscaling` Lambda is uploaded to S3 at
`s3://4shark-lambda-artifacts/worker-autoscaling/<version>_<sha>.zip` — confirmed from
`app-atento-001/main.tf:5–6` (`lambda_s3_bucket = "4shark-lambda-artifacts"`,
`lambda_version = "0.7.1_736733c"`).

The new Lambda follows the same convention:
`s3://4shark-lambda-artifacts/worker-payroll-autoscaling/<version>_<sha>.zip`. The
`<version>_<sha>` key format is used by the Terraform `modules/lambda-ecs-autoscaling` via
`s3_key = "${each.value.package}/${local.lambda_version}.zip"` (compute.tf:907).

Confirm the exact release workflow with the first real build in Phase 4 — there is likely a
GitHub Actions job in `lambda/` that builds and uploads; reuse it (or extend it) for the new
package directory.

---

## 7. Open questions gated on Phase 0

- `PROCESS_NAME` value — comes from the outbound Sidekiq process name reported by the metrics
  endpoint. Confirmed in Phase 0 EC2 inventory.
- Sidekiq queue name — confirmed in Phase 0; consumed in Phase 6 (app-side).
- `SIDEKIQ_THREADS` / concurrency for the task definition — confirmed in Phase 0; consumed in
  Phase 7.

Phase 4 can proceed as soon as `PROCESS_NAME` is known; the queue name and thread count are
consumed later.

---

**Status:** Phase 1 complete. No blocking questions about the Lambda interface remain. Phase 4
is unblocked for everything except the `PROCESS_NAME` default value (waits on Phase 0).
