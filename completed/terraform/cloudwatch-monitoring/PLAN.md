# PLAN - CloudWatch Monitoring and Alerting

> Reference: SPIKE.md at ~/.claude/plans/active/spike/cloudwatch-monitoring/SPIKE.md

## Objective

Implement CloudWatch monitoring and alerting for the 4 production app environments (app-atento-001, app-shared-001, app-demo-001, app-beta-001). The platform currently has zero notification coverage for silent infrastructure failures. This plan delivers a reusable Terraform module with 11 alarm types, a shared notification chain (SNS → AWS Chatbot → Slack), Container Insights enablement, and a CloudWatch Dashboard covering all environments.

## Scope

### In Scope
- SNS Topic (shared, all environments publish to it)
- AWS Chatbot + Slack channel integration (manual step — not Terraform-managed)
- Reusable Terraform module `modules/cloudwatch_app_monitoring` with all 11 alarm types
- Container Insights enablement on all 4 ECS clusters
- Module instantiation for all 4 app environments (app-atento-001, app-shared-001, app-demo-001, app-beta-001)
- CloudWatch Dashboard covering all 4 environments
- All alarm thresholds exposed as module variables with validated defaults

### Out of Scope
- VPN (Pritunl) monitoring
- Integrator monitoring (EC2 + ECS)
- Onboarding and Setup app monitoring
- Custom metrics (all alarms use native AWS metrics)
- PagerDuty, OpsGenie, or any third-party alerting
- Slack bot commands or two-way integrations

## Architecture

```
CloudWatch Alarm (per environment) → SNS Topic (shared) → AWS Chatbot → Slack #alerts channel
```

**SNS Topic**: single topic `4shark-cloudwatch-alerts`, placed in the `monitoring/` Terraform stack (already exists for Rollbar, same state file).

**AWS Chatbot**: created manually via AWS Console or CLI (not supported by AWS Terraform provider). Subscribes to the SNS topic.

**Module location**: `modules/cloudwatch_app_monitoring/`

**Module instantiation**: one call per environment, inside each environment's own Terraform stack (e.g., `app-atento-001/monitoring.tf`).

**Dashboard**: single resource in the `monitoring/` stack, using CloudWatch cross-account composite widget — references all 4 environments.

## Execution Phases

### Phase 1: Notification Infrastructure

**Objective**: Create the SNS topic and document the manual AWS Chatbot setup step.

**Components**:
- `monitoring/sns.tf`: `aws_sns_topic.cloudwatch_alerts` — topic `4shark-cloudwatch-alerts` with a display name for Slack readability
- `monitoring/outputs.tf` update: export `sns_topic_arn` so environment stacks can reference it via `terraform_remote_state`
- Manual step: Configure AWS Chatbot in the console — create Slack channel configuration, authorize the Slack workspace, subscribe to the SNS topic, set alarm notification format

**Dependencies**: None — this is the foundation.

**Success Criteria**:
- [ ] SNS topic exists in AWS with ARN `arn:aws:sns:us-east-1:405749097490:4shark-cloudwatch-alerts`
- [ ] `monitoring` state exports `sns_topic_arn`
- [ ] AWS Chatbot configured and connected to the Slack channel
- [ ] Test SNS publish reaches Slack (manual validation via `aws sns publish`)

---

### Phase 2: Terraform Module — `modules/cloudwatch_app_monitoring`

**Objective**: Create a reusable module that accepts environment-specific inputs and creates all applicable alarms.

**Module interface**:

```hcl
variable "environment"          # e.g., "app-atento-001"
variable "cluster_name"         # ECS cluster name
variable "sns_topic_arn"        # alarm destination
variable "web_service_name"     # name of the web ECS service
variable "lambda_function_names" # list of Lambda function names to monitor
variable "rds_instance_id"      # RDS cluster/instance identifier
variable "rds_is_aurora"        # bool — Aurora uses FreeLocalStorage, instance uses FreeStorageSpace
variable "opensearch_domain_name" # optional — empty string = OpenSearch alarms disabled
variable "has_scheduled_tasks"  # bool — enables EventBridge Scheduler alarms
variable "active_services"      # list of ECS service names with desired_count > 0

# Thresholds (all have validated defaults)
variable "lambda_error_eval_periods"       # default: 3
variable "lambda_not_invoked_eval_periods" # default: 10
variable "ecs_task_placement_eval_periods" # default: 10
variable "ecs_service_down_eval_periods"   # default: 5
variable "ecs_cpu_threshold"               # default: 80
variable "ecs_memory_threshold"            # default: 80
variable "ecs_cpu_eval_periods"            # default: 5
variable "ecs_memory_eval_periods"         # default: 5
variable "rds_storage_threshold_gb"        # default: 10 (override to 5 for demo/beta)
variable "rds_replication_lag_threshold_ms" # default: 1000 (Aurora only)
variable "scheduled_task_eval_periods"     # default: 2
```

**Alarm files inside the module**:

| File | Alarms |
|------|--------|
| `alarms_lambda.tf` | #1 Lambda errors sustained, #2 Lambda not invoked |
| `alarms_ecs.tf` | #3 ECS unable to place tasks, #4 ECS service down, #10 ECS web CPU, #11 ECS web memory |
| `alarms_rds.tf` | #7 RDS storage critical, #8 RDS replication lag (Aurora only) |
| `alarms_opensearch.tf` | #5 OpenSearch cluster RED, #6 OpenSearch cluster YELLOW |
| `alarms_scheduler.tf` | #9 Scheduled tasks not running |
| `variables.tf` | All inputs with validated defaults |
| `outputs.tf` | Alarm ARNs for reference |

**Implementation notes**:
- Lambda alarms use `for_each` over `var.lambda_function_names`
- ECS service down (#4) and unable to place tasks (#3) use `for_each` over `var.active_services`
- ECS web CPU/memory (#10, #11) target `var.web_service_name` only
- OpenSearch alarms guarded by `count = var.opensearch_domain_name != "" ? 1 : 0`
- RDS replication lag guarded by `count = var.rds_is_aurora ? 1 : 0`
- Scheduled tasks alarms guarded by `count = var.has_scheduled_tasks ? 1 : 0`
- All alarm names follow pattern: `{environment}-{alarm-type}` (e.g., `app-atento-001-lambda-errors`)
- Container Insights must be enabled before alarms #3 and #4 are useful (see Phase 3)

**Dependencies**: Phase 1 complete (SNS topic ARN available).

**Success Criteria**:
- [ ] Module exists at `modules/cloudwatch_app_monitoring/`
- [ ] `terraform validate` passes on the module
- [ ] All 11 alarm types present with correct metric names, namespaces, dimensions, thresholds, and evaluation periods
- [ ] All thresholds are variables — no hardcoded values in alarm resources
- [ ] OpenSearch, Aurora replication lag, and scheduled task alarms are correctly gated by their respective variables
- [ ] Module outputs all alarm ARNs

---

### Phase 3: Container Insights Enablement

**Objective**: Enable Container Insights on all 4 ECS clusters. This is a prerequisite for alarms #3 (ECS unable to place tasks) and #4 (ECS service down), which rely on `ECS/ContainerInsights` namespace metrics.

**Where to apply**: Each cluster is created via `modules/ecs_cluster`. The `aws_ecs_cluster` resource supports a `setting` block for Container Insights.

**Change required**: Add to `modules/ecs_cluster/main.tf`:

```hcl
setting {
  name  = "containerInsights"
  value = "enabled"
}
```

This is a non-destructive change to the existing cluster resource. Enabling Container Insights on a running cluster does not restart tasks or cause downtime.

**Cost**: Container Insights adds metrics storage cost. At the scale of 4 environments with ~8 services each, the additional cost is negligible (<$2/month estimated).

**Dependencies**: None — can be done in parallel with Phase 2.

**Success Criteria**:
- [ ] `setting { name = "containerInsights", value = "enabled" }` added to `modules/ecs_cluster/main.tf`
- [ ] `terraform plan` for each of the 4 environments shows only the cluster `setting` change (no unexpected destroy/recreate)
- [ ] `terraform apply` applied to all 4 environments without downtime
- [ ] Container Insights metrics visible in CloudWatch console for at least one cluster before proceeding to Phase 4

---

### Phase 4: Module Instantiation — Atento (Pilot)

**Objective**: Instantiate the module for `app-atento-001` only. Validate that alarms fire correctly and thresholds are appropriate before rolling out to other environments.

**New file**: `app-atento-001/monitoring.tf`

**Atento-specific configuration**:
- `rds_is_aurora = true` (Aurora PostgreSQL cluster)
- `rds_storage_threshold_gb = 10` (default — current free storage: 12.1 GB)
- `opensearch_domain_name = "app-atento-001"` (OpenSearch present)
- `has_scheduled_tasks = false` (no scheduled tasks in Atento)
- `active_services`: list the services with `desired_count > 0` (web + active workers)
- `lambda_function_names`: list of Lambda names in Atento (Lambda-app-atento-001-*)

**SNS ARN reference**:
```hcl
data "terraform_remote_state" "monitoring" {
  # already exists in app-atento-001/monitoring_data.tf
}

module "cloudwatch_monitoring" {
  source        = "../modules/cloudwatch_app_monitoring"
  environment   = var.environment
  sns_topic_arn = data.terraform_remote_state.monitoring.outputs.sns_topic_arn
  # ...
}
```

**Validation steps after apply**:
1. Confirm ~10-12 alarms appear in CloudWatch console for app-atento-001
2. Confirm all alarms start in OK state (no false positives)
3. Monitor for 24 hours — validate no spurious alerts
4. If any alarm triggers unexpectedly, adjust threshold variable in `terraform.tfvars` before proceeding

**Dependencies**: Phases 1, 2, and 3 complete.

**Success Criteria**:
- [ ] `app-atento-001/monitoring.tf` created
- [ ] `terraform plan` shows expected alarms with no unexpected changes
- [ ] All alarms in OK state after apply (no immediate false positives)
- [ ] 24-hour observation window with no spurious alerts
- [ ] Team confirms Slack notifications are received in the correct channel format

---

### Phase 5: Module Instantiation — Remaining Environments

**Objective**: Roll out to app-shared-001, app-demo-001, and app-beta-001 after Atento validation.

**New files**:
- `app-shared-001/monitoring.tf`
- `app-demo-001/monitoring.tf`
- `app-beta-001/monitoring.tf`

**Environment-specific overrides**:

| Setting | Atento | Shared | Demo | Beta |
|---------|--------|--------|------|------|
| `rds_is_aurora` | true | true | false | false |
| `rds_storage_threshold_gb` | 10 | 10 | 5 | 5 |
| `opensearch_domain_name` | "app-atento-001" | "app-shared-001" | "" | "" |
| `has_scheduled_tasks` | false | false | true | true |

**Dependencies**: Phase 4 complete and validated.

**Success Criteria**:
- [ ] `monitoring.tf` created for all 3 remaining environments
- [ ] `terraform apply` applied to each environment without errors
- [ ] All new alarms in OK state
- [ ] No spurious alerts in first 24 hours across all environments

---

### Phase 6: CloudWatch Dashboard

**Objective**: Create a single dashboard in the `monitoring/` stack covering all 4 environments. Tier 2 metrics only — observation without notification.

**New file**: `monitoring/dashboard.tf`

**Dashboard sections per environment**:
- ECS CPU and memory utilization (all active services)
- OpenSearch CPU utilization (Atento and Shared only)
- RDS CPU, connections, and freeable memory
- ALB latency, 4xx, and 5xx counts
- Lambda invocation duration and success rate
- T3a CPU credit balance and surplus credits charged (worker instances)

**Implementation**: `aws_cloudwatch_dashboard` resource with a JSON body. The JSON is generated using Terraform `jsonencode()` for maintainability.

**Dependencies**: Phases 1–5 complete (all alarms exist — dashboard can reference them for alarm status widgets).

**Success Criteria**:
- [ ] Dashboard created in CloudWatch console
- [ ] All 4 environments visible on the dashboard
- [ ] Dashboard renders without errors (no missing metrics or broken widgets)
- [ ] T3a CPU credit balance widget present for worker instances

---

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Module location | `modules/cloudwatch_app_monitoring/` | Consistent with all other reusable modules in this repo |
| SNS Topic placement | `monitoring/` stack | Already exists, already referenced by all environment stacks via `terraform_remote_state` |
| AWS Chatbot | Manual (console/CLI) | Not supported by AWS Terraform provider — cannot be managed as code |
| Dashboard placement | `monitoring/` stack | Single cross-environment view; no environment-specific state needed |
| Container Insights | Added to `modules/ecs_cluster` | Affects all users of the module uniformly; non-breaking change |
| Lambda alarm scope | All 4 environments | Lambdas are present in every environment; Lambda silent failures were the known incident vector |
| Worker CPU/memory | No alarms | Validated by 30-day production data + Brendan Gregg USE Method — workers using all CPU is correct behavior for Sidekiq |
| Rollout order | Atento first | Most critical environment; validates thresholds before wider rollout |
| Alarm naming | `{environment}-{alarm-type}` | Consistent, searchable, immediately identifies source environment |

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| False positives on launch | Medium | 24-hour observation window after Atento pilot before rolling out; all thresholds validated against 30-day production data |
| Container Insights changes cluster resource | Low | Non-destructive `setting` block addition; confirmed by AWS docs — does not restart tasks |
| RDS storage alarm triggers on Atento immediately | Medium | Current free storage is 12.1 GB vs 10 GB threshold — 2.1 GB headroom; monitor closely; threshold is adjustable via `terraform.tfvars` |
| AWS Chatbot manual setup creates dependency | Low | Well-documented step; SNS topic can receive messages independently — alarms still work even if Chatbot is misconfigured (messages queue in SNS) |
| OpenSearch CPU spikes trigger alerts | Low | OpenSearch CPU is in dashboard only (Tier 2), not in alarms — existing spike behavior does not generate noise |
| T3a credit depletion over time | Low | Dashboard widget for credit balance provides visibility; no alarm needed based on current data |

## Assumptions

- AWS Chatbot Slack integration will be configured manually by the engineer before Phase 4 apply
- Lambda function names in each environment follow the pattern `Lambda-{environment}-{function-name}` (confirmed from `modules/lambda-ecs-autoscaling/main.tf`)
- ECS service names in each environment follow the pattern `{environment}-{service-name}-service` (confirmed from `app-atento-001/compute.tf`)
- The `monitoring/` stack already has an AWS provider configured (to be confirmed — currently only `rollbar` provider is in `monitoring/providers.tf`; AWS provider must be added)
- All 4 app environments use the same `modules/ecs_cluster` module, so Container Insights changes apply uniformly
- OpenSearch domain names match the environment name prefix (to be confirmed during Phase 4)
- `app-demo-001` and `app-beta-001` use EventBridge Scheduler for scheduled tasks (confirmed from SPIKE)
- `app-atento-001` and `app-shared-001` have no scheduled tasks (confirmed from SPIKE)

---

**Status:** READY FOR TASK CREATION
