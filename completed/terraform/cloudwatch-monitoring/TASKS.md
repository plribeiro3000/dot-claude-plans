# TASKS — CloudWatch Monitoring and Alerting

> **Reference:** `PLAN.md` (Phases 1–6).

---

## Completed Tasks

### Phase 1 — Notification Infrastructure
- [x] **Task 1** — Create SNS Topic (`monitoring/sns.tf`, `monitoring/outputs.tf`, `monitoring/providers.tf`). Applied 2026-03-27. PR #283.

### Phase 2 — Terraform Module
- [x] **Task 3** — Create CloudWatch monitoring module (`modules/cloudwatch_app_monitoring/`). 11 alarm types, all thresholds as variables. PR #283.
- [x] **Task 4** — Lambda alarms implemented (`alarms_lambda.tf`)
- [x] **Task 5** — ECS alarms implemented (`alarms_ecs.tf`)
- [x] **Task 6** — RDS alarms implemented (`alarms_rds.tf`)
- [x] **Task 7** — OpenSearch alarms implemented (`alarms_opensearch.tf`)
- [x] **Task 8** — EventBridge Scheduler alarms implemented (`alarms_scheduler.tf`)
- [x] **Task 9** — Module variables and outputs finalized

### Phase 3 — Container Insights
- [x] **Task 10** — Container Insights enabled on all 4 ECS clusters (`modules/ecs_cluster/main.tf`). Applied 2026-03-27. PR #283. Note: causes task definition recreation due to `depends_on = [module.ecs_cluster]` — services unaffected (`ignore_changes = [task_definition]`).

### Phase 4 — Atento Pilot
- [x] **Task 11** — Module instantiated for Atento. Applied 2026-03-27. PR #283.

### Phase 5 — Remaining Environments
- [x] **Task 12** — Module instantiated for Shared. Applied 2026-03-27. PR #283.
- [x] **Task 13** — Module instantiated for Demo. Applied 2026-03-27. PR #283.
- [x] **Task 14** — Module instantiated for Beta. Applied 2026-03-27. PR #283.

### Bug Fix — Resource naming mismatch (Atento/Shared)
- [x] **Fix** — Correct resource names in Atento/Shared monitoring.tf. Applied 2026-03-27. PR #284.

Atento and Shared have `app-` prefix on all AWS resources due to VPC migration, but `var.environment` is `atento-001`/`shared-001` (without `app-`). Fixed by hardcoding `app-` prefix in Lambda names, ECS service names, ECS cluster name, and OpenSearch domain name for these two environments. Demo and Beta were not affected.

---

### Phase 6 — Dashboard + Notifications
- [x] **Task 2** — Configure AWS Chatbot manually (Slack integration). Configured 2026-04-04 via AWS Console. Configuration name: `4shark-cloudwatch-alerts`, IAM role: `AWSChatbotCloudWatchRole` (Notification permissions), guardrail: ReadOnlyAccess. Tested with forced alarm — notifications arriving in Slack.
- [x] **Task 15** — Create CloudWatch Dashboard (`monitoring/dashboard.tf`). Applied 2026-04-04. PR #289. 14 widgets: ECS web/worker CPU+memory, OpenSearch CPU, RDS CPU+connections+memory, ALB latency+requests+4xx+5xx, Lambda duration+errors. T3a credit balance deferred (EC2 metrics use InstanceId which changes on replacement).
- [x] **Task 17** — Add CloudWatch read permissions to Engineers IAM policy (`identity/policies_baseline.tf`). Applied 2026-04-04. PR #289. Added `CloudWatchReadOnly` statement with 7 actions (dashboards, metrics, alarms).

### Orphaned resource cleanup
- [x] **Cleanup** — Deleted orphaned `Atento-VPN` dashboard. VPN `vpn-0233f54f1495ae261` in sa-east-1 no longer exists. Deleted manually via console 2026-04-04.

---

## Current State (2026-04-04)

**78 alarms active across 4 environments.** All alarms in OK state (verified 2026-04-04).

| Environment | Alarms | OpenSearch | Scheduler | RDS Replica Lag |
|---|---|---|---|---|
| Atento | 20 | Yes | No | Yes |
| Shared | 20 | Yes | No | Yes |
| Demo | 19 | No | Yes | No |
| Beta | 19 | No | Yes | No |

**Notification chain:** SNS → AWS Chatbot → Slack. Fully operational. Tested with forced alarm 2026-04-04.

**Dashboard:** `4shark-app-monitoring` — 14 widgets covering ECS, OpenSearch, RDS, ALB, Lambda across all 4 environments.

**IAM:** Engineers have read access to dashboards, metrics, and alarms.

---

## Remaining Tasks

- [x] **Task 16** — Final validation. All 78 alarms in OK state. Zero false positives in 8 days of operation (2026-03-27 to 2026-04-04). Notification chain tested end-to-end. Thresholds validated by production data.

## Future Improvements (out of scope)

- T3a CPU credit balance dashboard widget (requires SEARCH expressions or custom metrics — EC2 InstanceId dimension changes on replacement)
- Monitoring for VPN (Pritunl), integrators, onboarding, and setup environments
- Rollbar provider token renewal (currently expired — blocks full `terraform plan` on monitoring stack)
