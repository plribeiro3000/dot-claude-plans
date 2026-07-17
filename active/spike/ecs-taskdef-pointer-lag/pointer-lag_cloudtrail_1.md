# Raw CloudTrail evidence — `terraform` #711 incident reconstruction

All queries run via `aws cloudtrail lookup-events` (default read-only profile, `us-east-1`, `--region us-east-1`) on 2026-07-16, one day after the incident (2026-07-15) — well inside the 90-day `lookup-events` window, so no S3 fallback was needed. Every timestamp below is reproduced exactly as returned by the CLI (`EventTime` in the account's local offset, `-03:00` = BRT; `eventTime` inside `CloudTrailEvent` in UTC). PR #711 merged at `2026-07-15T19:02:47Z` per `gh pr view 711 --json mergedAt` (= `16:02:47 -03:00`), confirmed against the merge commit `c582d7c01ef8f944a072c823eb72dd3265ca6c03` (`git show -s --format=%cd --date=iso-strict`) → `2026-07-15T16:02:46-03:00`.

## 1. `DeleteParameter` — all four stacks, one query

Command: `aws cloudtrail lookup-events --start-time 2026-07-15T18:30:00Z --end-time 2026-07-15T21:00:00Z --lookup-attributes AttributeKey=EventName,AttributeValue=DeleteParameter --max-results 50 --region us-east-1`

Four events returned, no pagination needed (`Events` array exhausted, no `NextToken` inspected on this call but the four-stack set is exactly what the incident record describes). Each is a `terraform-provider-aws/6.53.0` call by `paulo@4shark.com.br`, MFA-authenticated (`"mfaAuthenticated":"true"`), same source IP `189.69.28.7`, same session (`"creationDate":"2026-07-15T18:43:18Z"`):

| Stack | `eventTime` (UTC) | `EventTime` (BRT, `-03:00`) | `requestParameters.name` |
|---|---|---|---|
| beta-001 | `2026-07-15T18:43:45Z` | `2026-07-15T15:43:45-03:00` | `/beta-001/DD_API_KEY` |
| demo-001 | `2026-07-15T18:46:04Z` | `2026-07-15T15:46:04-03:00` | `/demo-001/DD_API_KEY` |
| atento-001 | `2026-07-15T18:46:30Z` | `2026-07-15T15:46:30-03:00` | `/atento-001/DD_API_KEY` |
| shared-001 | `2026-07-15T18:56:23Z` | `2026-07-15T15:56:23-03:00` | `/shared-001/DD_API_KEY` |

Full `userAgent` string (identical on all four): `"APN/1.0 HashiCorp/1.0 Terraform/1.13.0 (+https://www.terraform.io) terraform-provider-aws/6.53.0 (+https://registry.terraform.io/providers/hashicorp/aws) aws-sdk-go-v2/1.42.0 ua/2.1 os/macos lang/go#1.26.4 md/GOOS#darwin md/GOARCH#arm64 api/ssm#1.69.4 m/n"`.

Full raw event for beta-001 (representative, others identical shape with stack name substituted):

```json
{
  "EventId": "24e15244-85e1-4c10-8ea9-c57c1e6a536b",
  "EventName": "DeleteParameter",
  "ReadOnly": "false",
  "AccessKeyId": "***REMOVED***",
  "EventTime": "2026-07-15T15:43:45-03:00",
  "EventSource": "ssm.amazonaws.com",
  "Username": "paulo@4shark.com.br",
  "CloudTrailEvent": {
    "eventVersion": "1.11",
    "userIdentity": {
      "type": "IAMUser",
      "arn": "arn:aws:iam::405749097490:user/paulo@4shark.com.br",
      "userName": "paulo@4shark.com.br",
      "sessionContext": { "attributes": { "creationDate": "2026-07-15T18:43:18Z", "mfaAuthenticated": "true" } }
    },
    "eventTime": "2026-07-15T18:43:45Z",
    "eventSource": "ssm.amazonaws.com",
    "eventName": "DeleteParameter",
    "awsRegion": "us-east-1",
    "sourceIPAddress": "189.69.28.7",
    "userAgent": "APN/1.0 HashiCorp/1.0 Terraform/1.13.0 (+https://www.terraform.io) terraform-provider-aws/6.53.0 ...",
    "requestParameters": { "name": "/beta-001/DD_API_KEY" },
    "resources": [{ "accountId": "405749097490", "ARN": "arn:aws:ssm:us-east-1:405749097490:parameter/beta-001/DD_API_KEY" }],
    "eventType": "AwsApiCall",
    "managementEvent": true,
    "recipientAccountId": "405749097490",
    "eventCategory": "Management"
  }
}
```

## 2. `RegisterTaskDefinition` — narrowed to the same window, by `paulo@4shark.com.br` (the Terraform identity)

Command: `aws cloudtrail lookup-events --start-time 2026-07-15T18:40:00Z --end-time 2026-07-15T19:00:00Z --lookup-attributes AttributeKey=EventName,AttributeValue=RegisterTaskDefinition --max-results 50 --region us-east-1`, paginated once (`--next-token`) to exhaust the full result set for this 20-minute window. 61 total events returned across both pages, every one attributed to `paulo@4shark.com.br` via the same Terraform user agent as above (`api/ecs#...` instead of `api/ssm#...`).

Full per-family breakdown, `EventTime` (BRT) and `requestParameters.family`:

**beta-001** (14 families, all at `2026-07-15T15:43:45-03:00`): `beta-001-worker-cleansing`, `beta-001-runner`, `beta-001-cron-attachment-expirator`, `beta-001-cron-plan-participation-expirator`, `beta-001-worker-system`, `beta-001-worker-user`, `beta-001-web`, `beta-001-cron-anonymization-company`, `beta-001-worker-commission-tiger-shark`, `beta-001-worker-commission-white-shark`, `beta-001-worker-commission`, `beta-001-worker-migration`, `beta-001-cron-anonymization-user`.

**demo-001** (13 families, all at `2026-07-15T15:46:05-03:00`, one entry at `:04`): `demo-001-cron-attachment-expirator`, `demo-001-worker-user`, `demo-001-worker-migration`, `demo-001-worker-commission-tiger-shark`, `demo-001-web`, `demo-001-worker-cleansing`, `demo-001-worker-commission`, `demo-001-runner`, `demo-001-worker-system`, `demo-001-worker-commission-white-shark`, `demo-001-cron-anonymization-company`, `demo-001-cron-anonymization-user`, `demo-001-cron-plan-participation-expirator`.

**atento-001** (14 families, `2026-07-15T15:46:30-03:00`/`:31`): `atento-001-worker-cleansing`, `atento-001-worker-migration`, `atento-001-worker-user`, `atento-001-cron-monthly-usage-processor`, `atento-001-web`, `atento-001-worker-system`, `atento-001-worker-commission-tiger-shark`, `atento-001-worker-commission-white-shark`, `atento-001-cron-deal-search-index-expirator`, `atento-001-cron-partial-commissions-generator`, `atento-001-cron-anonymization-user`, `atento-001-runner`, `atento-001-cron-anonymization-company`, `atento-001-cron-plan-participation-expirator`, `atento-001-worker-commission`, `atento-001-cron-attachment-expirator`.

**shared-001** (18 families, all at `2026-07-15T15:56:21-03:00`): `shared-001-worker-commission-white-shark`, `shared-001-cron-anonymization-company`, `shared-001-cron-partial-commissions-generator`, `shared-001-worker-user`, `shared-001-worker-deal-indexation`, `shared-001-cron-monthly-usage-processor`, `shared-001-connection-pooler`, `shared-001-cron-plan-participation-expirator`, `shared-001-worker-cleansing`, `shared-001-worker-commission-tiger-shark`, `shared-001-worker-commission`, `shared-001-worker-migration`, `shared-001-cron-deal-search-index-expirator`, `shared-001-web`, `shared-001-runner`, `shared-001-cron-attachment-expirator`, `shared-001-cron-anonymization-user`, `shared-001-worker-system`.

**Cross-reference against the `DeleteParameter` table above**: each stack's entire `RegisterTaskDefinition` batch lands within 1–2 seconds of that same stack's `DeleteParameter` call (beta-001: register and delete both at `15:43:45`; demo-001: register at `15:46:05`, delete at `15:46:04`, 1 second apart; atento-001: register at `15:46:30`/`:31`, delete at `15:46:30`; shared-001: register at `15:56:21`, delete at `15:56:23`, 2 seconds apart). Terraform's default parallelism (`-parallelism=10`) executes independent graph nodes concurrently, which is the mechanical reason unrelated resources (an `aws_ecs_task_definition` create and an `aws_ssm_parameter` destroy) land within the same 1–2 second window inside one `apply` invocation.

**A wider search for GitHub-Actions-registered revisions in the same 18:40–19:00Z window found none** — the unfiltered `RegisterTaskDefinition` dump for the broader `18:30Z`–`21:00Z` range (461 total lines, 341KB, too large for one `Read`) shows the FIRST `app-<stack>` (GHA) registration only from `2026-07-15T16:48:19-03:00` onward (`beta-001-web`), roughly 65 minutes after the earliest Terraform registration (`beta-001`, `15:43:45`) — i.e. no GHA activity overlaps the destroy window; GHA registrations begin only once the recovery deploys (below) start.

## 3. `UpdateService` — same window, to check whether Terraform (or anything else) moved a service pointer during the destroy

Command: `aws cloudtrail lookup-events --start-time 2026-07-15T18:40:00Z --end-time 2026-07-15T19:00:00Z --lookup-attributes AttributeKey=EventName,AttributeValue=UpdateService --max-results 50 --region us-east-1`

Exactly **one** event in the entire 20-minute window:

```json
{
  "cluster": "shared-001-cluster",
  "service": "shared-001-worker-system-service",
  "desiredCount": 1,
  "forceNewDeployment": false,
  "dryrun": false
}
```

`EventTime`: `2026-07-15T15:48:50-03:00`. `Username`: `Lambda-shared-001-worker-system-autoscaling` (the Application Auto Scaling Lambda, not Terraform, not GHA). The `requestParameters` carry **no `taskDefinition` key at all** — this call only changes `desiredCount`; it cannot and does not move the service's task-definition pointer. No other `UpdateService` call — by Terraform, GHA, or anything else — occurred anywhere in the four-stack destroy window.

## 4. `RunTask` — same window, extended to the recovery point, checking for logged placement failures

Command: `aws cloudtrail lookup-events --start-time 2026-07-15T18:43:00Z --end-time 2026-07-15T19:50:00Z --lookup-attributes AttributeKey=EventName,AttributeValue=RunTask --max-results 50 --region us-east-1`

Three events, all `errorCode` absent (i.e. the API call itself succeeded — CloudTrail's `RunTask` entry records whether the *request* was accepted, not whether the launched task later failed `ResourceInitializationError` when the agent tried to resolve the SSM secret). None carry a `NextToken`. Summary (`EventTime`, `Username`, `EventSource`):

| EventTime (BRT) | Username | EventSource |
|---|---|---|
| `2026-07-15T16:48:39-03:00` | `app-shared-001` | `ecs.amazonaws.com` |
| `2026-07-15T16:00:19-03:00` | `a75eae4164b039888ba9503cd3ec8240` (assumed role session ID) | `ecs.amazonaws.com` |
| `2026-07-15T16:00:00-03:00` | `61d1e2448b3f3c989b2a1e739bc452ca` | `ecs.amazonaws.com` |

**[VERIFIED-HERE, negative result]**: no `RunTask` call in this window carries an error code or error message, and there is no CloudTrail event visible for the actual placement failures (`ResourceInitializationError: unable to place a task ... Fetching secret data from SSM Parameter Store`). This is consistent with that failure occurring inside the ECS agent's task-startup sequence, downstream of a successfully-accepted `RunTask`/scheduler-internal task-start call — a data-plane failure, not a distinct failed management-event API call, so CloudTrail's Event History does not surface it directly. The `terraform` PLAN.md's own incident record (`~/Projects/4Shark/dot-claude-plans/active/terraform/datadog-key-standard/PLAN.md`) is the source for the actual error text, not CloudTrail.

## 5. Timestamp discrepancy — the incident record's stated destroy time does not match the raw CloudTrail timestamps

The `terraform/datadog-key-standard/PLAN.md` incident record states: *"Duration ≈ 1h05 (parameters destroyed 16:40, last stack recovered 17:45 BRT)."* The CloudTrail `DeleteParameter` events above show the four destroys spread across `15:43:45`–`15:56:23` BRT — 44 to 57 minutes **earlier** than the PLAN.md's stated "16:40". **[VERIFIED-HERE]**: this is a real, sourced discrepancy between the incident record's narrative and the raw CloudTrail log; this document does not attempt to resolve which value is correct, only to flag that they diverge by roughly an hour.

## 6. Task-definition revision content — `beta-001-worker-user` family, revisions 210 and 211

Command: `aws ecs describe-task-definition --task-definition beta-001-worker-user:210 --region us-east-1 --query 'taskDefinition.{registeredAt:registeredAt,registeredBy:registeredBy,status:status,secrets:containerDefinitions[0].secrets,command:containerDefinitions[0].command}'`

**Revision `:210`** (the revision immediately preceding Terraform's `:211`):

```json
{
  "registeredAt": "2026-07-15T07:18:30.241000-03:00",
  "registeredBy": "arn:aws:iam::405749097490:user/app-beta-001",
  "status": "ACTIVE",
  "secrets": [
    "... 16 secrets total, including ...",
    { "name": "DD_API_KEY", "valueFrom": "arn:aws:ssm:us-east-1:405749097490:parameter/beta-001/DD_API_KEY" }
  ],
  "command": ["bundle", "exec", "sidekiq", "-C", "config/sidekiq_user.yml"]
}
```

(Full secret list, verbatim from the command's JSON output: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `CURRENCY_API_KEY`, `DATA_DOG_API_KEY`, `DATA_DOG_APPLICATION_KEY`, `DATABASE_URL`, `DD_API_KEY`, `GRAPHQL_INTROSPECTION_TOKEN`, `HIREFIRE_TOKEN`, `MONGO_URL`, `NEW_RELIC_LICENSE_KEY`, `RAILS_MASTER_KEY`, `REDIS_LOCK_URL`, `REDIS_URL`, `ROLLBAR_CLIENT_ACCESS_TOKEN`, `ROLLBAR_SERVER_ACCESS_TOKEN`, `SECRET_KEY_BASE`.)

**Revision `:211`** (registered by Terraform at the exact moment of the destroy):

```json
{
  "registeredAt": "2026-07-15T15:43:45.452000-03:00",
  "registeredBy": "arn:aws:iam::405749097490:user/paulo@4shark.com.br",
  "status": "ACTIVE",
  "secretNames": ["AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "CURRENCY_API_KEY", "DATA_DOG_API_KEY", "DATA_DOG_APPLICATION_KEY", "DATABASE_URL", "GRAPHQL_INTROSPECTION_TOKEN", "HIREFIRE_TOKEN", "MONGO_URL", "NEW_RELIC_LICENSE_KEY", "RAILS_MASTER_KEY", "REDIS_LOCK_URL", "REDIS_URL", "ROLLBAR_CLIENT_ACCESS_TOKEN", "ROLLBAR_SERVER_ACCESS_TOKEN", "SECRET_KEY_BASE"],
  "command": null
}
```

`:211`'s secret list is `:210`'s list minus exactly `DD_API_KEY` — confirming Terraform's revision is clean of the parameter reference it was about to destroy. `:211.command` is `null` (confirmed directly, not inferred) — the container would run the image's default `CMD`, not sidekiq, if this revision were ever the one a service actually launched tasks from.

## 7. Module code — confirming `command = null` is not incidental but the module's designed behavior, and where a service's initial pointer comes from

`~/Projects/4Shark/terraform/modules/ecs_service/main.tf:30`:
```hcl
      command     = length(var.command) > 0 ? var.command : null
```

`~/Projects/4Shark/terraform/modules/ecs_service/variables.tf:132-136`:
```hcl
variable "command" {
  description = "Container command"
  type        = list(string)
  default     = []
}
```

`~/Projects/4Shark/terraform/modules/ecs_service/main.tf:71-79`:
```hcl
resource "terraform_data" "lb_config" {
  input = length(var.load_balancers) > 0 ? jsonencode([for lb in var.load_balancers : lb.target_group_arn]) : null
}

resource "aws_ecs_service" "this" {
  name                 = var.service_name
  cluster              = var.cluster_name
  desired_count        = var.desired_count
  task_definition      = aws_ecs_task_definition.this.arn
```

`~/Projects/4Shark/terraform/modules/ecs_service/main.tf:152-163`:
```hcl
  lifecycle {
    ignore_changes = [
      desired_count,
      task_definition, # CodeDeploy gerencia a task definition durante deployments
      load_balancer,   # CodeDeploy gerencia os target groups durante blue/green deployments
    ]

    replace_triggered_by = [terraform_data.lb_config]
  }
```

`~/Projects/4Shark/terraform/app-beta-001/main.tf:429-450` (the stack's call site for the module, `for_each = local.services`):
```hcl
module "ecs_services" {
  source      = "../modules/ecs_service"
  for_each    = local.services
  ...
  command                            = lookup(each.value, "command", [])
```

Grep for `command` inside `app-beta-001/terraform.tfvars` shows the key is present **only** on the four `cron-*` entries (e.g. `command = ["bundle", "exec", "rails", "cron:attachment:expirator"]`, line 247). No `command` key exists anywhere in the `beta-001-worker-user-service`, `beta-001-worker-system-service`, or any other worker/web service block in `terraform.tfvars`. So `lookup(each.value, "command", [])` returns `[]` for every worker and web service, and `main.tf:30` renders `command = null` on every Terraform-registered revision for those services — this is not specific to the #711 incident, it is the permanent, current state of every worker/web service's Terraform configuration. The sidekiq/puma/rails startup command exists **only** inside the GHA deploy workflow, never inside Terraform.

`terraform_data.lb_config`'s `input` is `null` whenever `var.load_balancers` is empty — true for every worker service (workers have no load balancer). A `null` input never changes value, so `replace_triggered_by = [terraform_data.lb_config]` has no live trigger surface for worker services under normal operation; it is a live trigger only for load-balanced (web) services, whose target-group ARNs can change (e.g. during a VPC migration, per the code comment at `main.tf:73-74`: *"Track load balancer target group ARNs to force service replacement when target groups are recreated (e.g., VPC migration)."*).
