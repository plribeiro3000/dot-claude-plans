# ECS Scheduled Tasks for beta-001

## Context

The cron ECS service approach (dedicated container running `crond`) was removed because the Docker image `ruby:3.4.1` lacked the `crond` binary. The 4 crontab commands from beta-001 now need to run as ECS Scheduled Tasks — one-off Fargate tasks triggered by EventBridge Scheduler on a cron schedule.

**Crontab commands to migrate:**
```
0 4 * * * /usr/bin/rails cron:attachment:expirator
0 4 * * * /usr/bin/rails cron:plan_participation:expirator
0 5 * * * /usr/bin/rails cron:anonymization:company
0 5 * * * /usr/bin/rails cron:anonymization:user
```

## Approach

Use **EventBridge Scheduler** (`aws_scheduler_schedule`) with ECS targets on **Fargate**. This is consistent with the existing EventBridge Scheduler pattern already used for Lambda autoscaling (`beta-001/lambda.tf`).

**Why Fargate instead of EC2:**
- beta-001 worker ASGs have `min_size=0` and `enable_managed_scaling=false` — no guarantee an EC2 instance exists when cron fires
- Fargate starts tasks on-demand, no capacity management needed
- Pay only for the ~seconds/minutes each cron task runs

**Docker image:** `web` (`beta-001-web:latest`) — the only image guaranteed to always be up to date, since the web service is the primary service that always runs. Workers have `min_size=0` and their images may not always be current.

## Files to Create

### 1. `modules/ecs_scheduled_task/main.tf`

New reusable module with 3 resources:
- `aws_cloudwatch_log_group` — `/ecs/{environment}-cron-{name}`
- `aws_ecs_task_definition` — Fargate, `awsvpc` network mode, specific command
- `aws_scheduler_schedule` — EventBridge Scheduler with `ecs_parameters` target

Naming: `ECS-{environment}-cron-{name}` for the schedule (consistent with `Lambda-{environment}-*` pattern).

### 2. `modules/ecs_scheduled_task/variables.tf`

Input variables: environment, name, description, image, command, schedule_expression, cluster_arn, execution_role_arn, task_role_arn, scheduler_role_arn, subnets, security_groups, cpu (default 512), memory (default 1024), log_retention_days (default 7), timezone (default "UTC"), state (default "ENABLED"), tags.

### 3. `beta-001/scheduled-tasks.tf`

New file containing:

**IAM role** for EventBridge Scheduler → ECS:
- Trust: `scheduler.amazonaws.com` (same principal as existing Lambda scheduler)
- Policy: `ecs:RunTask` scoped to cluster + `iam:PassRole` for `ecsTaskExecutionRole`

**Module invocation** with `for_each = var.scheduled_tasks`:
- Common values derived from existing modules: cluster ARN, subnets, security groups, image
- Per-task values from the variable: name, command, schedule_expression

## Files to Modify

### 4. `modules/ecs_cluster/outputs.tf`

Add `ecs_cluster_arn` output (`aws_ecs_cluster.cluster.arn`). Currently only exports `ecs_cluster_name` — the scheduler needs the ARN.

### 5. `beta-001/variables.tf`

Add `scheduled_tasks` variable:
```hcl
variable "scheduled_tasks" {
  description = "Map of ECS scheduled tasks (cron jobs)"
  type = map(object({
    description         = string
    command             = list(string)
    schedule_expression = string
  }))
  default = {}
}
```

### 6. `beta-001/terraform.tfvars`

Add the 4 scheduled tasks:
```hcl
scheduled_tasks = {
  "attachment-expirator"         = { description = "Expire old attachments",        command = ["rails", "cron:attachment:expirator"],          schedule_expression = "cron(0 4 * * ? *)" }
  "plan-participation-expirator" = { description = "Expire old plan participations", command = ["rails", "cron:plan_participation:expirator"], schedule_expression = "cron(0 4 * * ? *)" }
  "anonymization-company"        = { description = "Anonymize company data",         command = ["rails", "cron:anonymization:company"],        schedule_expression = "cron(0 5 * * ? *)" }
  "anonymization-user"           = { description = "Anonymize user data",            command = ["rails", "cron:anonymization:user"],           schedule_expression = "cron(0 5 * * ? *)" }
}
```

Note: cron syntax `0 4 * * *` → EventBridge `cron(0 4 * * ? *)` (day-of-week uses `?`).

## Verification

1. `terraform plan` in `beta-001/` — expect ~13 new resources (4 × log group + task def + schedule, plus IAM role + policy)
2. `terraform apply` — create resources
3. Validate in AWS console: EventBridge Scheduler shows 4 schedules, ECS cluster shows 4 task definitions
4. Optional: manually trigger a schedule to verify the Fargate task runs and logs appear in CloudWatch
