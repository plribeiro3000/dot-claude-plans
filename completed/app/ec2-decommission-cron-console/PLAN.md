# PLAN — Decommission EC2: ECS Scheduled Tasks + ECS Exec Console

## Current Situation

- **Infrastructure**: ECS on EC2 Launch Type (not Fargate) across 4 environments
- **Cluster**: Each environment has a dedicated cluster with multiple ASGs (web, worker-system, worker-user, worker-commission, tiger-shark, white-shark, cleansing, migration)
- **ECS Exec**: Enabled on web, worker-commission, worker-system, worker-user
- **Cron**: Running via ECS Scheduled Tasks (EventBridge Scheduler + Fargate RunTask) on all 4 environments
- **Console**: `bin/ecs` CLI tool with `connect` and `run` subcommands

### The Problem (original)

Old EC2 instances (pre-migration) were still running for two purposes:

1. **Cron jobs** — `crontab` entries calling `rake cron:*` tasks
2. **Rails console** — SSH into EC2 for production debugging

Both have been replaced:
- Cron → ECS Scheduled Tasks via EventBridge Scheduler on Fargate
- Console → `bin/ecs connect` (attach to running task) and `bin/ecs run` (ephemeral task)

### Cron Jobs per Environment

| Environment | Tasks | Schedule Highlights |
|-------------|-------|-------------------|
| shared-001 | 7 | attachment-expirator, deal-elastic-index-expirator, plan-participation-expirator, anonymization-company, anonymization-user, partial-commissions-generator, monthly-usage-processor |
| atento-001 | 7 | Same as shared-001 |
| beta-001 | 4 | attachment-expirator, plan-participation-expirator, anonymization-company, anonymization-user |
| demo-001 | 4 | Same as beta-001 |

Configured in `terraform/{env}/terraform.tfvars` under `scheduled_tasks` variable.

---

## Completed Phases

### Phase 0: Collect Current Crontabs — DONE

Crontab data collected from all 4 environments and converted to `scheduled_tasks` Terraform configuration.

### Phase 1: ECS Scheduled Tasks — DONE

Implemented via Terraform module `modules/ecs_scheduled_task/`:
- EventBridge Scheduler (`aws_scheduler_schedule`) triggers ECS RunTask on Fargate
- Each task uses the web image with a command override (`bundle exec rails cron:*`)
- IAM role for EventBridge Scheduler → ECS RunTask
- CloudWatch log groups for task output

Deployed to all 4 environments. Deploy workflows updated to register cron task definitions on each deploy (PR #4818).

### Phase 2: CLI Tools (`bin/ecs`) — DONE

Created `bin/ecs` shell script with two subcommands:

| Subcommand | Use Case | Mechanism |
|------------|----------|-----------|
| `bin/ecs connect <env> --service <name>` | Day-to-day console | ECS Exec into a running task |
| `bin/ecs run <env>` | Debug / break-glass | `ecs run-task` → ephemeral container → ECS Exec → `stop-task` on exit |

Commit: `49abbe324`

---

## Remaining Phase

### Phase 3: EC2 Decommission

1. **Wait for first scheduled execution cycle** — most tasks fire at 4-5 AM UTC daily. Validate via CloudWatch Logs.
2. **Audit EC2 resources** — identify what is dedicated to cron vs shared with other services (SGs, IAM roles, EBS volumes)
3. **Disable old crontabs** on EC2 instances across all 4 environments
4. **Terminate old EC2 cron instances**
5. **Clean up dedicated resources** (SGs, IAM roles, EBS volumes that were only used by cron EC2)

### Success Criteria

- All scheduled tasks execute on schedule without the old EC2 instances
- Task output visible in CloudWatch Logs
- `bin/ecs connect` and `bin/ecs run` working on all 4 environments
- Old EC2 instances terminated, no orphaned resources

---

## Internal References

- Cron tasks: `app/lib/tasks/cron.rake`
- Scheduled tasks config: `terraform/{env}/terraform.tfvars` → `scheduled_tasks`
- Scheduled task module: `terraform/modules/ecs_scheduled_task/`
- CLI tool: `app/bin/ecs`
- Deploy workflows: `app/.github/workflows/deploy-*.yaml`

---

## Environments

| Environment | Nature | Scheduled Tasks | Status |
|-------------|--------|----------------|--------|
| `shared-001` | Production (multi-tenant) | 7 tasks | Deployed |
| `atento-001` | Production (dedicated) | 7 tasks | Deployed |
| `beta-001` | Pre-production | 4 tasks | Deployed |
| `demo-001` | Demo/staging | 4 tasks | Deployed |
