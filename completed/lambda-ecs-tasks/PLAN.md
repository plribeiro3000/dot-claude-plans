# PLAN — ECS Migration: Lambdas + App Workflows

> **Status:** In Progress
> **Scope:** Beta-001 first. Other environments will be addressed after beta validation is complete to avoid rework.

---

## Scope

This plan covers the migration of Lambda functions from EC2 Auto Scaling Groups to ECS Services, plus related workflow changes.

**Workstreams:**

1. App Workflow Restructuring (✅ Complete - PRs #4730, #4731)
2. Lambda Code Migration (✅ Complete - PR #8)
3. Lambda Renaming (✅ Complete - PR #8)
4. AWS IAM Setup (⏳ In Progress - Beta first)
5. Lambda Deployment (⏳ Pending)
6. EC2 Cleanup (⏳ Pending - separate task)

---

## Prerequisites

Before running the setup/validate scripts, ensure:

**AWS Access:**
- AWS CLI v2 installed and configured
- Credentials with permissions to create IAM policies, roles, and Lambda functions
- Profile: Use your standard admin profile or a role with IAM/Lambda/ECS permissions

**Environment:**
- Region: `us-east-1` (default, configurable via `AWS_REGION`)
- Account: `405749097490`

**Local Tools:**
- Bash
- AWS CLI v2 (`aws --version`)

**Required IAM Permissions:**
- `iam:CreatePolicy`, `iam:GetPolicy`, `iam:AttachRolePolicy`
- `iam:CreateRole`, `iam:GetRole`, `iam:PassRole`
- `lambda:CreateFunction`, `lambda:GetFunction`, `lambda:UpdateFunctionCode`
- `scheduler:CreateSchedule`, `scheduler:UpdateSchedule`, `scheduler:GetSchedule`
- `ecs:DescribeClusters`, `ecs:DescribeServices`

---

## 1. App Workflow Restructuring ✅ Complete

Removed migration/cleansing workers from automatic deploy. Created on-demand workflows.

**Changes:**
- Modified 4 deploy workflows (beta, demo, shared, atento) - removed migration, cleansing
- Created `deploy-service.yaml` - deploy and start a service manually
- Created `stop-service.yaml` - stop a service (desired_count=0)
- Standardized GitHub Environment names to kebab-case (beta-001, demo-001, etc.)

**PRs Merged:** #4730, #4731

---

## 2. Lambda Code Migration ✅ Complete

Migrated Lambda functions from ASG to ECS APIs.

**Changes:**
- Replaced `aws-sdk-autoscaling` with `aws-sdk-ecs` in all Gemfiles
- Updated all `lambda_function.rb` to use ECS API
- Created `config.yml` for Commission Balancing Lambda
- Updated `bin/generate_lambda` to include config.yml

**PR:** #8

---

## 3. Lambda Renaming ✅ Complete

Renamed Lambda source code directories from GC-analogy names to domain-meaningful names.

| Old Directory | New Directory | AWS Lambda Names |
|---------------|---------------|------------------|
| `worker-standard-scaling` | `worker-autoscaling` | `Lambda-{env}-worker-user-autoscaling`, `Lambda-{env}-worker-system-autoscaling` |
| `worker-commission-scaling-minor` | `worker-commission-autoscaling` | `Lambda-{env}-worker-commission-autoscaling` |
| `worker-commission-scaling-major` | `worker-commission-balancing` | `Lambda-{env}-worker-commission-balancing` |

**PR:** #8

---

## 4. AWS IAM Setup ⏳ In Progress

Create new IAM resources for ECS-based Lambdas. Beta first, then replicate to other environments.

### Environment Variables

| Variable | Beta | Demo | Shared | Atento |
|----------|------|------|--------|--------|
| `{ENV}` | `beta-001` | `demo-001` | `shared-001` | `atento-001` |
| `{CLUSTER}` | `beta-001-cluster` | `demo-001-cluster` | `shared-001-cluster` | `atento-001-cluster` |
| Has Balancing Lambda? | No | No | No | Yes |

### Account Info

- **Account ID:** `405749097490`
- **Region:** `us-east-1`

### Execution Steps (Beta)

4.1. Create policy `CloudWatch-beta-001-lambda-logs-policy` with logs permissions for `Lambda-beta-001-*`

4.2. Create policy `ECS-beta-001-lambda-worker-policy` with ECS permissions for cluster `beta-001-cluster`

4.3. Create role `Lambda-beta-001-worker-commission-autoscaling-role` with trust policy allowing `lambda.amazonaws.com` to assume it

4.4. Attach policy `CloudWatch-beta-001-lambda-logs-policy` to role `Lambda-beta-001-worker-commission-autoscaling-role`

4.5. Attach policy `ECS-beta-001-lambda-worker-policy` to role `Lambda-beta-001-worker-commission-autoscaling-role`

4.6. Create role `Lambda-beta-001-worker-standard-autoscaling-role` with trust policy allowing `lambda.amazonaws.com` to assume it

4.7. Attach policy `CloudWatch-beta-001-lambda-logs-policy` to role `Lambda-beta-001-worker-standard-autoscaling-role`

4.8. Attach policy `ECS-beta-001-lambda-worker-policy` to role `Lambda-beta-001-worker-standard-autoscaling-role`

4.9. Create Lambda `Lambda-beta-001-worker-commission-autoscaling` using role `Lambda-beta-001-worker-commission-autoscaling-role`

4.10. Create Lambda `Lambda-beta-001-worker-user-autoscaling` using role `Lambda-beta-001-worker-standard-autoscaling-role`

4.11. Create Lambda `Lambda-beta-001-worker-system-autoscaling` using role `Lambda-beta-001-worker-standard-autoscaling-role`

4.12. Create policy `EventBridge-beta-001-lambda-invoke-policy` with lambda:InvokeFunction for `Lambda-beta-001-*`

4.13. Create role `EventBridge-beta-001-scheduler-role` with trust policy allowing `scheduler.amazonaws.com` to assume it

4.14. Attach policy `EventBridge-beta-001-lambda-invoke-policy` to role `EventBridge-beta-001-scheduler-role`

4.15. Create schedule `Lambda-beta-001-worker-commission-autoscaling-schedule` targeting `Lambda-beta-001-worker-commission-autoscaling`

4.16. Create schedule `Lambda-beta-001-worker-user-autoscaling-schedule` targeting `Lambda-beta-001-worker-user-autoscaling`

4.17. Create schedule `Lambda-beta-001-worker-system-autoscaling-schedule` targeting `Lambda-beta-001-worker-system-autoscaling`

4.18. Validate CloudWatch Logs for all 3 new Lambdas (ECS) running in parallel with existing Lambdas (EC2)

### Policy Documents

**CloudWatch-beta-001-lambda-logs-policy:**

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "CreateLogGroup",
            "Effect": "Allow",
            "Action": "logs:CreateLogGroup",
            "Resource": "arn:aws:logs:us-east-1:405749097490:*"
        },
        {
            "Sid": "WriteLogs",
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:us-east-1:405749097490:log-group:/aws/lambda/Lambda-beta-001-*:*"
        }
    ]
}
```

**ECS-beta-001-lambda-worker-policy:**

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "ECSAccess",
            "Effect": "Allow",
            "Action": [
                "ecs:DescribeServices",
                "ecs:UpdateService"
            ],
            "Resource": [
                "arn:aws:ecs:us-east-1:405749097490:cluster/beta-001-cluster",
                "arn:aws:ecs:us-east-1:405749097490:service/beta-001-cluster/*"
            ]
        }
    ]
}
```

**Trust Policy (same for both roles):**

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
```

### Resources Summary (Beta)

**Create:**

| Type | Name |
|------|------|
| Policy | `CloudWatch-beta-001-lambda-logs-policy` |
| Policy | `ECS-beta-001-lambda-worker-policy` |
| Policy | `EventBridge-beta-001-lambda-invoke-policy` |
| Role | `Lambda-beta-001-worker-commission-autoscaling-role` |
| Role | `Lambda-beta-001-worker-standard-autoscaling-role` |
| Role | `EventBridge-beta-001-scheduler-role` |
| Lambda | `Lambda-beta-001-worker-commission-autoscaling` |
| Lambda | `Lambda-beta-001-worker-user-autoscaling` |
| Lambda | `Lambda-beta-001-worker-system-autoscaling` |
| Schedule | `Lambda-beta-001-worker-commission-autoscaling-schedule` |
| Schedule | `Lambda-beta-001-worker-user-autoscaling-schedule` |
| Schedule | `Lambda-beta-001-worker-system-autoscaling-schedule` |

---

## 5. Lambda Deployment ⏳ Pending

After IAM setup, deploy Lambda code from PR #8.

### Lambda Environment Variables (Beta)

| Lambda | `ECS_CLUSTER_NAME` | `ECS_SERVICE_NAME` | `MINIMUM_CAPACITY` | `MAXIMUM_CAPACITY` | `PROCESS_NAME` |
|--------|-------------------|--------------------|--------------------|-------------------|----------------|
| `Lambda-beta-001-worker-user-autoscaling` | `beta-001-cluster` | `beta-001-worker-user-service` | `1` | `5` | `worker_user` |
| `Lambda-beta-001-worker-system-autoscaling` | `beta-001-cluster` | `beta-001-worker-system-service` | `1` | `5` | `worker_system` |
| `Lambda-beta-001-worker-commission-autoscaling` | `beta-001-cluster` | `beta-001-worker-commission-service` | `1` | `15` | `worker_commission` |

### Lambdas per Environment (Beta-001)

| Environment | Lambdas |
|-------------|---------|
| beta-001 | `worker-user-autoscaling`, `worker-system-autoscaling`, `worker-commission-autoscaling` |

**Note:** Other environments will be addressed after beta-001 validation is complete.

---

## 6. EC2 Cleanup ⏳ Pending (Separate Task)

After ECS validation, remove old EC2-based resources. This is a separate task for another person.

**Note:** The resource names below use `auto-scaling` (hyphenated). These are **legacy names** that don't follow the new naming convention (`autoscaling`, one word). Do not "fix" them — they must match what exists in AWS.

**Resources to remove (per environment):**

| Type | Name |
|------|------|
| Lambda | `Lambda-{env}-worker-auto-scaling-minor` |
| Lambda | `Lambda-{env}-worker-auto-scaling-major` |
| Lambda | `Lambda-{env}-worker-auto-scaling-user` |
| Lambda | `Lambda-{env}-worker-auto-scaling-system` |
| Role | `Lambda-{env}-worker-auto-scaling-minor-role` |
| Policy | `Lambda-{env}-worker-auto-scaling-minor-policy` |
| EventBridge targets | Remove old targets from rule |

**Global resources (remove after all environments migrated):**

| Type | Name |
|------|------|
| Role | `Lambda-worker-auto-scaling-major-role` |
| Role | `Lambda-worker-auto-scaling-standard-role` |
| Policy | `Lambda-worker-auto-scaling-major-policy` |
| Policy | `Lambda-worker-auto-scaling-standard-policy` |

---

## Scripts

| Script | Description |
|--------|-------------|
| `setup-lambda-env.sh <env>` | Creates IAM policies, roles for an environment |
| `validate-lambda-env.sh <env>` | Validates all resources exist and are correctly configured |

**Usage:**
```bash
# Setup Beta environment
./setup-lambda-env.sh beta-001

# Validate Beta environment
./validate-lambda-env.sh beta-001
```

---

## Reference

- **Lambda PR #8:** https://github.com/4shark/lambda/pull/8
- **App PR #4730:** Workflow restructuring
- **App PR #4731:** Environment standardization
