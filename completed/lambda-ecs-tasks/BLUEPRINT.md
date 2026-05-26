# BLUEPRINT — Lambda IAM Migration (Beta-001)

> **Status:** Completed
> **Scope:** Beta-001 first. Other environments follow the same process.
> **Approach:** Define naming convention → Create new resources → Validate → Remove old

---

## Part 1: Naming Convention

### General Principles

**Environment Isolation** — Every resource MUST be scoped to a specific environment. NO global policies. A Lambda in beta-001 cannot affect services in shared-001.

**Environment Numbering** — All environments include instance number to support horizontal scaling.

| Environment | Instance | Full Name |
|-------------|----------|-----------|
| Beta | 001 | `beta-001` |
| Demo | 001 | `demo-001` |
| Shared | 001 | `shared-001` |
| Shared | 002 (future) | `shared-002` |
| Atento | 001 | `atento-001` |

**Consistent Casing**

| Element | Case | Example |
|---------|------|---------|
| AWS Service prefix | PascalCase | `Lambda-`, `CloudWatch-`, `EventBridge-` |
| Environment | lowercase with hyphen | `beta-001`, `shared-001` |
| Description | lowercase with hyphens | `worker-commission-autoscaling` |
| Suffix | lowercase | `-policy`, `-role` |

**Word Choices**

| Term | Format | Reason |
|------|--------|--------|
| Auto Scaling | `autoscaling` (one word) | Consistency — actions are single words |
| Standard | `standard` | Used for generic workers (user, system) vs specialized (commission) |

### Resource Naming Patterns

| Resource Type | Pattern | Example |
|---------------|---------|---------|
| Policy | `{Service}-{env}-{description}-policy` | `CloudWatch-beta-001-lambda-logs-policy` |
| Role | `{Service}-{env}-{description}-role` | `Lambda-beta-001-worker-standard-autoscaling-role` |
| Lambda | `Lambda-{env}-{description}` | `Lambda-beta-001-worker-user-autoscaling` |
| Schedule | `Lambda-{env}-{description}-schedule` | `Lambda-beta-001-worker-user-autoscaling-schedule` |
| Source Directory | (no prefix) | `worker-autoscaling`, `worker-commission-autoscaling` |

No `-lambda` suffix on Lambda names — already starts with `Lambda-`, would be redundant.

### Separation of Concerns

Each policy should have a single responsibility.

Wrong (mixed concerns):
  Lambda-beta-worker-autoscaling-policy
    ecs:DescribeServices
    ecs:UpdateService
    logs:CreateLogGroup
    logs:CreateLogStream
    logs:PutLogEvents

Correct (separated):
  CloudWatch-beta-001-lambda-logs-policy
    logs:CreateLogGroup
    logs:CreateLogStream
    logs:PutLogEvents

  ECS-beta-001-lambda-worker-policy
    ecs:DescribeServices
    ecs:UpdateService

### Policy Documents

**CloudWatch Logs** — `CloudWatch-{env}-lambda-logs-policy`

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "CreateLogGroup",
            "Effect": "Allow",
            "Action": "logs:CreateLogGroup",
            "Resource": "arn:aws:logs:{region}:{account}:*"
        },
        {
            "Sid": "WriteLogs",
            "Effect": "Allow",
            "Action": ["logs:CreateLogStream", "logs:PutLogEvents"],
            "Resource": "arn:aws:logs:{region}:{account}:log-group:/aws/lambda/Lambda-{env}-*:*"
        }
    ]
}
```

**ECS Worker** — `ECS-{env}-lambda-worker-policy`

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "ECSAccess",
            "Effect": "Allow",
            "Action": ["ecs:DescribeServices", "ecs:UpdateService"],
            "Resource": [
                "arn:aws:ecs:{region}:{account}:cluster/{env}-cluster",
                "arn:aws:ecs:{region}:{account}:service/{env}-cluster/*"
            ]
        }
    ]
}
```

**EventBridge Scheduler Invoke** — `EventBridge-{env}-lambda-invoke-policy`

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "InvokeLambda",
            "Effect": "Allow",
            "Action": "lambda:InvokeFunction",
            "Resource": "arn:aws:lambda:{region}:{account}:function:Lambda-{env}-*"
        }
    ]
}
```

**Trust Policy** (same for all Lambda roles)

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": { "Service": "lambda.amazonaws.com" },
            "Action": "sts:AssumeRole"
        }
    ]
}
```

**ECS Deploy** — `ECS-{env}-deploy-policy`

Permissions: ECR GetAuthorizationToken, Push/Pull images; ECS RegisterTaskDefinition, UpdateService, DescribeServices; IAM PassRole (for task execution role).

### Resources per Environment

| Resource | Count | Names |
|----------|-------|-------|
| Policies | 3 | `CloudWatch-{env}-lambda-logs-policy`, `ECS-{env}-lambda-worker-policy`, `EventBridge-{env}-lambda-invoke-policy` |
| Roles | 3 | `Lambda-{env}-worker-commission-autoscaling-role`, `Lambda-{env}-worker-standard-autoscaling-role`, `EventBridge-{env}-scheduler-role` |
| Lambdas | 3 | `Lambda-{env}-worker-commission-autoscaling`, `Lambda-{env}-worker-user-autoscaling`, `Lambda-{env}-worker-system-autoscaling` |
| Schedules | 3 | `Lambda-{env}-worker-commission-autoscaling-schedule`, `Lambda-{env}-worker-user-autoscaling-schedule`, `Lambda-{env}-worker-system-autoscaling-schedule` |

### EventBridge Scheduler (replaces legacy Rules)

AWS recommends EventBridge Scheduler for new scheduled invocations. Benefits: configurable retry policies, dead-letter queue support, timezone support, flexible time windows, higher scale.

Schedule naming: `Lambda-{env}-{description}-schedule`
Scheduler IAM role: `EventBridge-{env}-scheduler-role`

### Source Code Directories

| Directory | AWS Lambda Names | Description |
|-----------|------------------|-------------|
| `worker-autoscaling/` | `Lambda-{env}-worker-user-autoscaling`, `Lambda-{env}-worker-system-autoscaling` | Standard autoscaling for user/system workers |
| `worker-commission-autoscaling/` | `Lambda-{env}-worker-commission-autoscaling` | Commission-specific autoscaling logic |
| `worker-commission-balancing/` | `Lambda-{env}-worker-commission-balancing` | Commission task balancing |

Building packages:

```bash
cd ~/Projects/4Shark/lambda
./bin/generate_lambda --lambda-name worker-autoscaling
./bin/generate_lambda --lambda-name worker-commission-autoscaling
```

### Non-Compliant Policies (Legacy)

| Policy | Issue | Correct Name |
|--------|-------|--------------|
| `ECS-deploy-beta-001-policy` | Wrong order (deploy before env) | `ECS-beta-001-deploy-policy` |
| `ECS-deploy-demo-001-policy` | Wrong order | `ECS-demo-001-deploy-policy` |
| `ECS-deploy-shared-001-policy` | Wrong order | `ECS-shared-001-deploy-policy` |
| `ECS-deploy-atento-001-policy` | Wrong order | `ECS-atento-001-deploy-policy` |
| `Eventbridge-*` | Deprecated — replaced by EventBridge Scheduler | Delete |
| `Lambda-{env}-worker-auto-scaling-minor-policy` | Mixed concerns, missing `-001` | Delete |
| `Lambda-worker-auto-scaling-major-policy` | Global, no environment isolation | Delete |
| `Lambda-worker-auto-scaling-standard-policy` | Global, no environment isolation | Delete |

### Decision Log

| Decision | Rationale |
|----------|-----------|
| Use `autoscaling` (one word) | Actions should be single words for consistency |
| No `-lambda` suffix on Lambda names | Already starts with `Lambda-`, would be redundant |
| Always include environment number (`-001`) | Supports future horizontal scaling |
| Separate logs policy from service policy | Separation of concerns, easier to audit and reuse |
| No global policies | Environment isolation for security |
| Use `standard` for generic workers | Distinguishes from specialized `commission` workers |
| Use EventBridge Scheduler with IAM role | AWS recommended approach for scheduled invocation |

### Notes

- Convention applies to customer-managed policies only
- AWS managed policies follow AWS naming conventions
- Integrator-related policies follow a separate convention (out of scope)
- Keycloak policies are managed by third-party (out of scope)

---

## Part 2: Migration

### Executive Summary

This migration replaces EC2 Auto Scaling Group-based Lambda functions with ECS Service-based ones in beta-001.

### Current State (Beta-001)

**Resources to Remove (After Validation)**

EventBridge IAM Policies and Roles (Deprecated):

| Policy | Role |
|--------|------|
| `Eventbridge-beta-invoke-minor-policy` | `Eventbridge-beta-invoke-minor-role` |
| `Eventbridge-beta-invoke-system-policy` | `Eventbridge-beta-invoke-system-role` |
| `Eventbridge-beta-invoke-user-policy` | `Eventbridge-beta-invoke-user-role` |

Lambda Execution Policy and Role (ASG-based):

| Policy | Role | Issues |
|--------|------|--------|
| `Lambda-beta-worker-auto-scaling-minor-policy` | `Lambda-beta-worker-auto-scaling-minor-role` | Mixed concerns, ASG-based, missing `-001` |

Lambda Functions (Old Names):

| Old Lambda | New Lambda |
|------------|------------|
| `Lambda-beta-worker-auto-scaling-minor` | `Lambda-beta-001-worker-commission-autoscaling` |
| `Lambda-beta-worker-auto-scaling-user` | `Lambda-beta-001-worker-user-autoscaling` |
| `Lambda-beta-worker-auto-scaling-system` | `Lambda-beta-001-worker-system-autoscaling` |

Summary: 4 policies + 4 roles + 3 Lambdas to remove.

Global Policies and Roles (After ALL Environments):

| Policy | Role |
|--------|------|
| `Lambda-worker-auto-scaling-major-policy` | `Lambda-worker-auto-scaling-major-role` |
| `Lambda-worker-auto-scaling-standard-policy` | `Lambda-worker-auto-scaling-standard-role` |

Do NOT remove these until demo-001, shared-001, and atento-001 are also migrated.

**Known Legacy Issues**

| Issue | Environment | Description | Impact |
|-------|-------------|-------------|--------|
| Cross-invocation permission | beta | grants InvokeFunction to another Lambda | Low — will be deleted |
| Cross-invocation permission | demo | grants invoke to itself (typo?) | Low — will be deleted |
| Shared policy | demo, atento | same policy attached to both roles | Medium — verify atento dependencies |
| Missing resources | atento | `Eventbridge-atento-invoke-*` NOT FOUND | None — never created |

When migrating demo/shared/atento, verify dependencies before deleting shared policies.

### New Resources to Create (Beta-001)

| Type | Name | Purpose |
|------|------|---------|
| Policy | `CloudWatch-beta-001-lambda-logs-policy` | CloudWatch Logs permissions |
| Policy | `ECS-beta-001-lambda-worker-policy` | ECS DescribeServices, UpdateService |
| Policy | `EventBridge-beta-001-lambda-invoke-policy` | Lambda InvokeFunction for Scheduler |
| Role | `Lambda-beta-001-worker-commission-autoscaling-role` | Execution role for commission Lambda |
| Role | `Lambda-beta-001-worker-standard-autoscaling-role` | Execution role for user/system Lambdas |
| Role | `EventBridge-beta-001-scheduler-role` | Scheduler role to invoke Lambdas |
| Lambda | `Lambda-beta-001-worker-commission-autoscaling` | Commission worker autoscaling |
| Lambda | `Lambda-beta-001-worker-user-autoscaling` | User worker autoscaling |
| Lambda | `Lambda-beta-001-worker-system-autoscaling` | System worker autoscaling |
| Schedule | `Lambda-beta-001-worker-commission-autoscaling-schedule` | Triggers commission Lambda |
| Schedule | `Lambda-beta-001-worker-user-autoscaling-schedule` | Triggers user Lambda |
| Schedule | `Lambda-beta-001-worker-system-autoscaling-schedule` | Triggers system Lambda |

Total: 3 policies + 3 roles + 3 Lambdas + 3 schedules.

### Lambda Environment Variables (Beta)

| Lambda | ECS_CLUSTER_NAME | ECS_SERVICE_NAME | MINIMUM_CAPACITY | MAXIMUM_CAPACITY | PROCESS_NAME |
|--------|------------------|------------------|------------------|------------------|--------------|
| worker-user-autoscaling | beta-001-cluster | beta-001-worker-user-service | 1 | 5 | worker_user |
| worker-system-autoscaling | beta-001-cluster | beta-001-worker-system-service | 1 | 5 | worker_system |
| worker-commission-autoscaling | beta-001-cluster | beta-001-worker-commission-service | 1 | 15 | worker_commission |

Runtime: `ruby3.4`

### Migration Phases

**Phase 1: Create New Resources**

Run setup script:

```bash
./setup-lambda-env.sh beta-001
```

The script creates all policies, roles, Lambdas, and schedules. It generates Lambda zip packages, validates ECS cluster exists, waits for IAM propagation, and is idempotent.

Validate:

```bash
./validate-lambda-env.sh beta-001
```

**Phase 2: Parallel Operation (24-48 hours)**

Old Lambdas triggered by legacy EventBridge Rules (scale EC2 ASGs — no effect on ECS). New Lambdas triggered by EventBridge Scheduler (scale ECS Services).

Monitor CloudWatch Logs:
- /aws/lambda/Lambda-beta-001-worker-commission-autoscaling
- /aws/lambda/Lambda-beta-001-worker-user-autoscaling
- /aws/lambda/Lambda-beta-001-worker-system-autoscaling

Success Criteria: No errors in new Lambda logs, ECS services scale correctly, no performance impact.

**Phase 3: Disable Old Lambdas**

List current targets:

```bash
aws events list-targets-by-rule --rule Lambda-beta-worker-auto-scaling-rule \
    --query "Targets[*].[Id,Arn]" --output table
```

Remove old targets:

```bash
aws events remove-targets --rule Lambda-beta-worker-auto-scaling-rule --ids \
    "<old-minor-target-id>" "<old-user-target-id>" "<old-system-target-id>"
```

Monitor 24 hours. Rollback if needed:

```bash
# Disable new schedules
aws scheduler update-schedule \
    --name Lambda-beta-001-worker-commission-autoscaling-schedule \
    --schedule-expression "rate(1 minute)" \
    --flexible-time-window '{"Mode":"OFF"}' \
    --target '{"Arn":"arn:aws:lambda:us-east-1:405749097490:function:Lambda-beta-001-worker-commission-autoscaling","RoleArn":"arn:aws:iam::405749097490:role/EventBridge-beta-001-scheduler-role"}' \
    --state DISABLED

aws scheduler update-schedule \
    --name Lambda-beta-001-worker-user-autoscaling-schedule \
    --schedule-expression "rate(1 minute)" \
    --flexible-time-window '{"Mode":"OFF"}' \
    --target '{"Arn":"arn:aws:lambda:us-east-1:405749097490:function:Lambda-beta-001-worker-user-autoscaling","RoleArn":"arn:aws:iam::405749097490:role/EventBridge-beta-001-scheduler-role"}' \
    --state DISABLED

aws scheduler update-schedule \
    --name Lambda-beta-001-worker-system-autoscaling-schedule \
    --schedule-expression "rate(1 minute)" \
    --flexible-time-window '{"Mode":"OFF"}' \
    --target '{"Arn":"arn:aws:lambda:us-east-1:405749097490:function:Lambda-beta-001-worker-system-autoscaling","RoleArn":"arn:aws:iam::405749097490:role/EventBridge-beta-001-scheduler-role"}' \
    --state DISABLED

# Re-add old targets to legacy rule
aws events put-targets --rule Lambda-beta-worker-auto-scaling-rule --targets '[
    {"Id": "<old-minor-id>", "Arn": "arn:aws:lambda:us-east-1:405749097490:function:Lambda-beta-worker-auto-scaling-minor"},
    {"Id": "<old-user-id>", "Arn": "arn:aws:lambda:us-east-1:405749097490:function:Lambda-beta-worker-auto-scaling-user"},
    {"Id": "<old-system-id>", "Arn": "arn:aws:lambda:us-east-1:405749097490:function:Lambda-beta-worker-auto-scaling-system"}
]'
```

**Phase 4: Remove Old Resources**

Order matters — remove in this order:

1. Delete old Lambda functions:

```bash
aws lambda delete-function --function-name Lambda-beta-worker-auto-scaling-minor
aws lambda delete-function --function-name Lambda-beta-worker-auto-scaling-user
aws lambda delete-function --function-name Lambda-beta-worker-auto-scaling-system
```

2. Detach policies and delete roles:

```bash
delete_role_completely() {
    local role_name="$1"
    echo "Cleaning up role: $role_name"
    for policy_arn in $(aws iam list-attached-role-policies --role-name "$role_name" --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null); do
        echo "  Detaching managed policy: $policy_arn"
        aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn"
    done
    for policy_name in $(aws iam list-role-policies --role-name "$role_name" --query 'PolicyNames[*]' --output text 2>/dev/null); do
        echo "  Deleting inline policy: $policy_name"
        aws iam delete-role-policy --role-name "$role_name" --policy-name "$policy_name"
    done
    echo "  Deleting role: $role_name"
    aws iam delete-role --role-name "$role_name"
}

delete_role_completely "Lambda-beta-worker-auto-scaling-minor-role"
delete_role_completely "Eventbridge-beta-invoke-minor-role"
delete_role_completely "Eventbridge-beta-invoke-user-role"
delete_role_completely "Eventbridge-beta-invoke-system-role"
```

3. Delete policies:

```bash
aws iam delete-policy --policy-arn arn:aws:iam::405749097490:policy/Lambda-beta-worker-auto-scaling-minor-policy
aws iam delete-policy --policy-arn arn:aws:iam::405749097490:policy/Eventbridge-beta-invoke-minor-policy
aws iam delete-policy --policy-arn arn:aws:iam::405749097490:policy/Eventbridge-beta-invoke-user-policy
aws iam delete-policy --policy-arn arn:aws:iam::405749097490:policy/Eventbridge-beta-invoke-system-policy
```

### Cleanup Checklist (Beta-001)

| Step | Resource | Done |
|------|----------|------|
| 3.1 | List old targets | [ ] |
| 3.2 | Remove old targets | [ ] |
| 3.3 | Monitor 24h | [ ] |
| 4.1a | Delete Lambda-beta-worker-auto-scaling-minor | [ ] |
| 4.1b | Delete Lambda-beta-worker-auto-scaling-user | [ ] |
| 4.1c | Delete Lambda-beta-worker-auto-scaling-system | [ ] |
| 4.2a | Delete Lambda-beta-worker-auto-scaling-minor-role | [ ] |
| 4.2b | Delete Eventbridge-beta-invoke-minor-role | [ ] |
| 4.2c | Delete Eventbridge-beta-invoke-user-role | [ ] |
| 4.2d | Delete Eventbridge-beta-invoke-system-role | [ ] |
| 4.3a | Delete Lambda-beta-worker-auto-scaling-minor-policy | [ ] |
| 4.3b | Delete Eventbridge-beta-invoke-minor-policy | [ ] |
| 4.3c | Delete Eventbridge-beta-invoke-user-policy | [ ] |
| 4.3d | Delete Eventbridge-beta-invoke-system-policy | [ ] |
| 4.4 | Delete Lambda-beta-worker-auto-scaling-rule | [ ] |

### Risk Mitigation

| Risk | Mitigation |
|------|------------|
| New Lambdas fail to scale ECS | Parallel operation phase; old Lambdas still active |
| Wrong ECS service names | Validation script checks ECS services exist |
| IAM propagation delay | 15-second wait in setup script; retry if Lambda creation fails |
| EventBridge not triggering | Validate targets and permissions with validation script |
| Rollback needed | Old Lambdas remain until Phase 4; re-add EventBridge targets if needed |

### Timeline (Beta-001)

| Phase | Duration |
|-------|----------|
| Phase 1: Create | ~30 minutes |
| Phase 2: Parallel | 24-48 hours |
| Phase 3: Disable old | 24 hours monitoring |
| Phase 4: Cleanup | ~30 minutes |

Total: 3-4 days

### Applying to Other Environments

1. Replace `beta-001` with the target environment in all commands
2. Run `setup-lambda-env.sh <env>`
3. Create Lambdas with environment-specific variables
4. Follow Phases 2-4

Global resources cleanup: Only delete `Lambda-worker-auto-scaling-major-*` and `Lambda-worker-auto-scaling-standard-*` after ALL environments are migrated.

---

## Reference

- **Setup Script:** `setup-lambda-env.sh`
- **Validation Script:** `validate-lambda-env.sh`
- **Execution Plan:** `PLAN.md`
- **Task List:** `TASKS.md`
