# IAM Policies Analysis

> Generated: 2026-01-14 20:55:33

---

## ECS-deploy-beta-001-policy

**Created:** 2026-01-14T18:06:50+00:00
**Attachment Count:** 1

### Attached To

**Users:**
- `app-staging`

### Policy Document

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "ECRLogin",
            "Effect": "Allow",
            "Action": "ecr:GetAuthorizationToken",
            "Resource": "*"
        },
        {
            "Sid": "ECRPushPull",
            "Effect": "Allow",
            "Action": [
                "ecr:BatchCheckLayerAvailability",
                "ecr:BatchGetImage",
                "ecr:CompleteLayerUpload",
                "ecr:DescribeImages",
                "ecr:DescribeRepositories",
                "ecr:GetDownloadUrlForLayer",
                "ecr:InitiateLayerUpload",
                "ecr:ListImages",
                "ecr:PutImage",
                "ecr:UploadLayerPart"
            ],
            "Resource": "arn:aws:ecr:us-east-1:405749097490:repository/beta-001-*"
        },
        {
            "Sid": "ECSTaskDefinition",
            "Effect": "Allow",
            "Action": [
                "ecs:DescribeTaskDefinition",
                "ecs:RegisterTaskDefinition"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ECSServiceDeploy",
            "Effect": "Allow",
            "Action": [
                "ecs:UpdateService",
                "ecs:DescribeServices"
            ],
            "Resource": [
                "arn:aws:ecs:us-east-1:405749097490:cluster/beta-001-cluster",
                "arn:aws:ecs:us-east-1:405749097490:service/beta-001-cluster/*"
            ]
        },
        {
            "Sid": "ECSWaiterSupport",
            "Effect": "Allow",
            "Action": [
                "ecs:ListTasks",
                "ecs:DescribeTasks"
            ],
            "Resource": "*",
            "Condition": {
                "ArnEquals": {
                    "ecs:cluster": "arn:aws:ecs:us-east-1:405749097490:cluster/beta-001-cluster"
                }
            }
        },
        {
            "Sid": "IAMPassRole",
            "Effect": "Allow",
            "Action": "iam:PassRole",
            "Resource": "arn:aws:iam::405749097490:role/ecsTaskExecutionRole"
        }
    ]
}
```

---

## ECS-deploy-demo-001-policy

**Created:** 2026-01-14T18:06:59+00:00
**Attachment Count:** 1

### Attached To

**Users:**
- `app-poc`

### Policy Document

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "ECRLogin",
            "Effect": "Allow",
            "Action": "ecr:GetAuthorizationToken",
            "Resource": "*"
        },
        {
            "Sid": "ECRPushPull",
            "Effect": "Allow",
            "Action": [
                "ecr:BatchCheckLayerAvailability",
                "ecr:BatchGetImage",
                "ecr:CompleteLayerUpload",
                "ecr:DescribeImages",
                "ecr:DescribeRepositories",
                "ecr:GetDownloadUrlForLayer",
                "ecr:InitiateLayerUpload",
                "ecr:ListImages",
                "ecr:PutImage",
                "ecr:UploadLayerPart"
            ],
            "Resource": "arn:aws:ecr:us-east-1:405749097490:repository/demo-001-*"
        },
        {
            "Sid": "ECSTaskDefinition",
            "Effect": "Allow",
            "Action": [
                "ecs:DescribeTaskDefinition",
                "ecs:RegisterTaskDefinition"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ECSServiceDeploy",
            "Effect": "Allow",
            "Action": [
                "ecs:UpdateService",
                "ecs:DescribeServices"
            ],
            "Resource": [
                "arn:aws:ecs:us-east-1:405749097490:cluster/demo-001-cluster",
                "arn:aws:ecs:us-east-1:405749097490:service/demo-001-cluster/*"
            ]
        },
        {
            "Sid": "ECSWaiterSupport",
            "Effect": "Allow",
            "Action": [
                "ecs:ListTasks",
                "ecs:DescribeTasks"
            ],
            "Resource": "*",
            "Condition": {
                "ArnEquals": {
                    "ecs:cluster": "arn:aws:ecs:us-east-1:405749097490:cluster/demo-001-cluster"
                }
            }
        },
        {
            "Sid": "IAMPassRole",
            "Effect": "Allow",
            "Action": "iam:PassRole",
            "Resource": "arn:aws:iam::405749097490:role/ecsTaskExecutionRole"
        }
    ]
}
```

---

## ECS-deploy-shared-001-policy

**Created:** 2026-01-14T18:07:06+00:00
**Attachment Count:** 1

### Attached To

**Users:**
- `app-shared`

### Policy Document

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "ECRLogin",
            "Effect": "Allow",
            "Action": "ecr:GetAuthorizationToken",
            "Resource": "*"
        },
        {
            "Sid": "ECRPushPull",
            "Effect": "Allow",
            "Action": [
                "ecr:BatchCheckLayerAvailability",
                "ecr:BatchGetImage",
                "ecr:CompleteLayerUpload",
                "ecr:DescribeImages",
                "ecr:DescribeRepositories",
                "ecr:GetDownloadUrlForLayer",
                "ecr:InitiateLayerUpload",
                "ecr:ListImages",
                "ecr:PutImage",
                "ecr:UploadLayerPart"
            ],
            "Resource": "arn:aws:ecr:us-east-1:405749097490:repository/shared-001-*"
        },
        {
            "Sid": "ECSTaskDefinition",
            "Effect": "Allow",
            "Action": [
                "ecs:DescribeTaskDefinition",
                "ecs:RegisterTaskDefinition"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ECSServiceDeploy",
            "Effect": "Allow",
            "Action": [
                "ecs:UpdateService",
                "ecs:DescribeServices"
            ],
            "Resource": [
                "arn:aws:ecs:us-east-1:405749097490:cluster/shared-001-cluster",
                "arn:aws:ecs:us-east-1:405749097490:service/shared-001-cluster/*"
            ]
        },
        {
            "Sid": "ECSWaiterSupport",
            "Effect": "Allow",
            "Action": [
                "ecs:ListTasks",
                "ecs:DescribeTasks"
            ],
            "Resource": "*",
            "Condition": {
                "ArnEquals": {
                    "ecs:cluster": "arn:aws:ecs:us-east-1:405749097490:cluster/shared-001-cluster"
                }
            }
        },
        {
            "Sid": "IAMPassRole",
            "Effect": "Allow",
            "Action": "iam:PassRole",
            "Resource": "arn:aws:iam::405749097490:role/ecsTaskExecutionRole"
        }
    ]
}
```

---

## ECS-deploy-atento-001-policy

**Created:** 2026-01-14T18:07:07+00:00
**Attachment Count:** 1

### Attached To

**Users:**
- `app-atento-001`

### Policy Document

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "ECRLogin",
            "Effect": "Allow",
            "Action": "ecr:GetAuthorizationToken",
            "Resource": "*"
        },
        {
            "Sid": "ECRPushPull",
            "Effect": "Allow",
            "Action": [
                "ecr:BatchCheckLayerAvailability",
                "ecr:BatchGetImage",
                "ecr:CompleteLayerUpload",
                "ecr:DescribeImages",
                "ecr:DescribeRepositories",
                "ecr:GetDownloadUrlForLayer",
                "ecr:InitiateLayerUpload",
                "ecr:ListImages",
                "ecr:PutImage",
                "ecr:UploadLayerPart"
            ],
            "Resource": "arn:aws:ecr:us-east-1:405749097490:repository/atento-001-*"
        },
        {
            "Sid": "ECSTaskDefinition",
            "Effect": "Allow",
            "Action": [
                "ecs:DescribeTaskDefinition",
                "ecs:RegisterTaskDefinition"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ECSServiceDeploy",
            "Effect": "Allow",
            "Action": [
                "ecs:UpdateService",
                "ecs:DescribeServices"
            ],
            "Resource": [
                "arn:aws:ecs:us-east-1:405749097490:cluster/atento-001-cluster",
                "arn:aws:ecs:us-east-1:405749097490:service/atento-001-cluster/*"
            ]
        },
        {
            "Sid": "ECSWaiterSupport",
            "Effect": "Allow",
            "Action": [
                "ecs:ListTasks",
                "ecs:DescribeTasks"
            ],
            "Resource": "*",
            "Condition": {
                "ArnEquals": {
                    "ecs:cluster": "arn:aws:ecs:us-east-1:405749097490:cluster/atento-001-cluster"
                }
            }
        },
        {
            "Sid": "IAMPassRole",
            "Effect": "Allow",
            "Action": "iam:PassRole",
            "Resource": "arn:aws:iam::405749097490:role/ecsTaskExecutionRole"
        }
    ]
}
```

---

## Eventbridge-beta-invoke-minor-policy

**Created:** 2025-09-09T18:43:32+00:00
**Attachment Count:** 1

### Attached To

**Roles:**
- `Eventbridge-beta-invoke-minor-role`

### Policy Document

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "lambda:InvokeFunction"
            ],
            "Resource": [
                "arn:aws:lambda:us-east-1:405749097490:function:Lambda-beta-worker-auto-scaling-minor"
            ]
        }
    ]
}
```

---

## Eventbridge-beta-invoke-system-policy

**Created:** 2025-09-09T18:43:55+00:00
**Attachment Count:** 1

### Attached To

**Roles:**
- `Eventbridge-beta-invoke-system-role`

### Policy Document

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "lambda:InvokeFunction"
            ],
            "Resource": [
                "arn:aws:lambda:us-east-1:405749097490:function:Lambda-beta-worker-auto-scaling-system"
            ]
        }
    ]
}
```

---

## Eventbridge-beta-invoke-user-policy

**Created:** 2025-09-09T18:44:16+00:00
**Attachment Count:** 1

### Attached To

**Roles:**
- `Eventbridge-beta-invoke-user-role`

### Policy Document

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "lambda:InvokeFunction"
            ],
            "Resource": [
                "arn:aws:lambda:us-east-1:405749097490:function:Lambda-beta-worker-auto-scaling-user"
            ]
        }
    ]
}
```

---

## Eventbridge-demo-invoke-minor-policy

**Created:** 2025-09-09T18:05:41+00:00
**Attachment Count:** 1

### Attached To

**Roles:**
- `Eventbridge-demo-invoke-minor-role`

### Policy Document

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "lambda:InvokeFunction"
            ],
            "Resource": [
                "arn:aws:lambda:us-east-1:405749097490:function:Lambda-demo-worker-auto-scaling-minor"
            ]
        }
    ]
}
```

---

## Eventbridge-demo-invoke-system-policy

**Created:** 2025-09-09T18:06:02+00:00
**Attachment Count:** 1

### Attached To

**Roles:**
- `Eventbridge-demo-invoke-system-role`

### Policy Document

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "lambda:InvokeFunction"
            ],
            "Resource": [
                "arn:aws:lambda:us-east-1:405749097490:function:Lambda-demo-worker-auto-scaling-system"
            ]
        }
    ]
}
```

---

## Eventbridge-demo-invoke-user-policy

**Created:** 2025-09-09T18:06:22+00:00
**Attachment Count:** 1

### Attached To

**Roles:**
- `Eventbridge-demo-invoke-user-role`

### Policy Document

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "lambda:InvokeFunction"
            ],
            "Resource": [
                "arn:aws:lambda:us-east-1:405749097490:function:Lambda-demo-worker-auto-scaling-user"
            ]
        }
    ]
}
```

---

## Eventbridge-shared-invoke-minor-policy

**Created:** 2025-09-09T17:54:02+00:00
**Attachment Count:** 1

### Attached To

**Roles:**
- `Eventbridge-shared-invoke-minor-role`

### Policy Document

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "lambda:InvokeFunction"
            ],
            "Resource": [
                "arn:aws:lambda:us-east-1:405749097490:function:Lambda-shared-worker-auto-scaling-minor"
            ]
        }
    ]
}
```

---

## Eventbridge-shared-invoke-system-policy

**Created:** 2025-09-09T17:55:10+00:00
**Attachment Count:** 1

### Attached To

**Roles:**
- `Eventbridge-shared-invoke-system-role`

### Policy Document

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "lambda:InvokeFunction"
            ],
            "Resource": [
                "arn:aws:lambda:us-east-1:405749097490:function:Lambda-shared-worker-auto-scaling-system"
            ]
        }
    ]
}
```

---

## Eventbridge-shared-invoke-user-policy

**Created:** 2025-09-09T17:55:53+00:00
**Attachment Count:** 1

### Attached To

**Roles:**
- `Eventbridge-shared-invoke-user-role`

### Policy Document

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "lambda:InvokeFunction"
            ],
            "Resource": [
                "arn:aws:lambda:us-east-1:405749097490:function:Lambda-shared-worker-auto-scaling-user"
            ]
        }
    ]
}
```

---

## Eventbridge-atento-invoke-minor-policy

**Status:** NOT FOUND

---

## Eventbridge-atento-invoke-system-policy

**Status:** NOT FOUND

---

## Eventbridge-atento-invoke-user-policy

**Status:** NOT FOUND

---

## Lambda-beta-worker-auto-scaling-minor-policy

**Created:** 2025-09-10T15:41:49+00:00
**Attachment Count:** 1

### Attached To

**Roles:**
- `Lambda-beta-worker-auto-scaling-minor-role`

### Policy Document

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "autoscaling:DescribeAutoScalingGroups",
                "autoscaling:UpdateAutoScalingGroup",
                "autoscaling:SetDesiredCapacity",
                "autoscaling:DescribeScalingActivities"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": "logs:CreateLogGroup",
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": [
                "arn:aws:logs:us-east-1:405749097490:log-group:/aws/lambda/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": "lambda:InvokeFunction",
            "Resource": "arn:aws:lambda:us-east-1:405749097490:function:Lambda-beta-worker-auto-scaling-major"
        }
    ]
}
```

---

## Lambda-demo-worker-auto-scaling-minor-policy

**Created:** 2025-09-10T15:42:30+00:00
**Attachment Count:** 2

### Attached To

**Roles:**
- `Lambda-demo-worker-auto-scaling-minor-role`
- `Lambda-atento-worker-auto-scaling-minor-role`

### Policy Document

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "autoscaling:DescribeAutoScalingGroups",
                "autoscaling:UpdateAutoScalingGroup",
                "autoscaling:SetDesiredCapacity",
                "autoscaling:DescribeScalingActivities"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": "logs:CreateLogGroup",
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": [
                "arn:aws:logs:us-east-1:405749097490:log-group:/aws/lambda/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": "lambda:InvokeFunction",
            "Resource": "arn:aws:lambda:us-east-1:405749097490:function:Lambda-demo-worker-auto-scaling-minor"
        }
    ]
}
```

---

## Lambda-shared-worker-auto-scaling-minor-policy

**Created:** 2025-09-10T15:43:30+00:00
**Attachment Count:** 1

### Attached To

**Roles:**
- `Lambda-shared-worker-auto-scaling-minor-role`

### Policy Document

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "autoscaling:DescribeAutoScalingGroups",
                "autoscaling:UpdateAutoScalingGroup",
                "autoscaling:SetDesiredCapacity",
                "autoscaling:DescribeScalingActivities"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": "logs:CreateLogGroup",
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": [
                "arn:aws:logs:us-east-1:405749097490:log-group:/aws/lambda/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": "lambda:InvokeFunction",
            "Resource": "arn:aws:lambda:us-east-1:405749097490:function:Lambda-shared-worker-auto-scaling-major"
        }
    ]
}
```

---

## Lambda-worker-auto-scaling-major-policy

**Created:** 2025-09-02T20:54:19+00:00
**Attachment Count:** 1

### Attached To

**Roles:**
- `Lambda-worker-auto-scaling-major-role`

### Policy Document

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "autoscaling:DescribeAutoScalingGroups",
                "autoscaling:UpdateAutoScalingGroup",
                "autoscaling:SetDesiredCapacity",
                "autoscaling:DescribeScalingActivities"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": "logs:CreateLogGroup",
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": [
                "arn:aws:logs:us-east-1:405749097490:log-group:/aws/lambda/*"
            ]
        }
    ]
}
```

---

## Lambda-worker-auto-scaling-standard-policy

**Created:** 2025-09-02T21:23:20+00:00
**Attachment Count:** 1

### Attached To

**Roles:**
- `Lambda-worker-auto-scaling-standard-role`

### Policy Document

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "autoscaling:DescribeAutoScalingGroups",
                "autoscaling:UpdateAutoScalingGroup",
                "autoscaling:SetDesiredCapacity",
                "autoscaling:DescribeScalingActivities"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": "logs:CreateLogGroup",
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": [
                "arn:aws:logs:us-east-1:405749097490:log-group:/aws/lambda/*"
            ]
        }
    ]
}
```

---

## github-actions-ecs-deploy-policy

**Status:** ❌ DELETED (2026-01-14)

**Reason:** Unused (AttachmentCount: 0), overly permissive (`Resource: *`), superseded by environment-specific `ECS-deploy-{env}-policy` policies.

**Associated role also deleted:** `github-actions-ecs-deploy-role`

---

## Replacement Mapping (ECS Migration)

The following table shows the mapping between old (EC2/ASG-based) and new (ECS-based) resources.

### Old → New Resources (Beta-001)

| Old Resource | New Resource | Notes |
|--------------|--------------|-------|
| `Lambda-beta-worker-auto-scaling-minor-policy` | `CloudWatch-beta-001-lambda-logs-policy` + `ECS-beta-001-lambda-worker-policy` | Separated concerns |
| `Eventbridge-beta-invoke-*-policy` | `EventBridge-beta-001-lambda-invoke-policy` | Single policy for Scheduler |
| `Eventbridge-beta-invoke-*-role` | `EventBridge-beta-001-scheduler-role` | Single role for all schedules |
| `Lambda-beta-worker-auto-scaling-minor-role` | `Lambda-beta-001-worker-commission-autoscaling-role` | Commission Lambda |
| `Lambda-worker-auto-scaling-standard-role` | `Lambda-beta-001-worker-standard-autoscaling-role` | User/System Lambdas |

### New Resources to Create (Beta-001)

| Type | Name | Purpose |
|------|------|---------|
| Policy | `CloudWatch-beta-001-lambda-logs-policy` | CloudWatch Logs permissions |
| Policy | `ECS-beta-001-lambda-worker-policy` | ECS DescribeServices, UpdateService |
| Policy | `EventBridge-beta-001-lambda-invoke-policy` | Lambda InvokeFunction for Scheduler |
| Role | `Lambda-beta-001-worker-commission-autoscaling-role` | Execution role for commission Lambda |
| Role | `Lambda-beta-001-worker-standard-autoscaling-role` | Execution role for user/system Lambdas |
| Role | `EventBridge-beta-001-scheduler-role` | Scheduler role to invoke Lambdas |

---

