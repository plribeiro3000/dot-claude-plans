# PLAN — GitHub Actions ECS Deploy Permissions

> **Status:** Ready for Review
> **Project:** app
> **Created:** 2026-01-14

## Summary

Replace overly permissive inline policy `EcsMaster` with environment-specific managed policies following the principle of least privilege.

## Decisions Made

| Decision | Value |
|----------|-------|
| Naming pattern | `ECS-deploy-{env}-001-policy` (following existing `S3-bucket-*` pattern) |
| Case | Uppercase prefix (ECS), lowercase rest |
| Environments | beta-001, demo-001, shared-001, atento-001 |
| Excluded | `app-development` (local development only, no deploy) |

## User → Policy Mapping

| IAM User | Environment | New Policy |
|----------|-------------|------------|
| `app-staging` | beta-001 | `ECS-deploy-beta-001-policy` |
| `app-poc` | demo-001 | `ECS-deploy-demo-001-policy` |
| `app-shared` | shared-001 | `ECS-deploy-shared-001-policy` |
| `app-atento-001` | atento-001 | `ECS-deploy-atento-001-policy` |

## Current State

### Users with `EcsMaster` inline policy (to be removed)

| User | Has `EcsMaster` |
|------|-----------------|
| `app-staging` | Yes |
| `app-poc` | Need to verify |
| `app-shared` | No |
| `app-atento-001` | No |

---

## Implementation Plan

### CRITICAL RULES

1. **Any unexpected error → STOP and report to user for evaluation**
2. **Never delete inline policy before confirming new policy works**
3. **Follow exact order specified below**
4. **Verify each step before proceeding to next**

---

### Phase 1: Create Managed Policies

Create 4 new managed policies. Order does not matter within this phase as they are independent.

#### Step 1.1: Create `ECS-deploy-beta-001-policy`

**Command:**
```bash
aws iam create-policy \
  --policy-name ECS-deploy-beta-001-policy \
  --description "GitHub Actions ECS deploy permissions for beta-001 environment" \
  --policy-document file:///tmp/ecs-deploy-beta-001-policy.json
```

**Policy document (`/tmp/ecs-deploy-beta-001-policy.json`):**
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

**Expected output:**
```json
{
    "Policy": {
        "PolicyName": "ECS-deploy-beta-001-policy",
        "PolicyId": "ANPA...",
        "Arn": "arn:aws:iam::405749097490:policy/ECS-deploy-beta-001-policy",
        "Path": "/",
        "DefaultVersionId": "v1",
        "AttachmentCount": 0,
        "IsAttachable": true,
        "CreateDate": "2026-01-14T..."
    }
}
```

**Possible errors:**
| Error | Meaning | Action |
|-------|---------|--------|
| `EntityAlreadyExists` | Policy already exists | STOP - verify if it's the correct policy, report to user |
| `MalformedPolicyDocument` | JSON syntax error | STOP - report to user |
| `LimitExceeded` | Too many policies | STOP - report to user |
| `AccessDenied` | No permission to create policy | STOP - report to user |

**Verification:**
```bash
aws iam get-policy --policy-arn arn:aws:iam::405749097490:policy/ECS-deploy-beta-001-policy
```

---

#### Step 1.2: Create `ECS-deploy-demo-001-policy`

**Command:**
```bash
aws iam create-policy \
  --policy-name ECS-deploy-demo-001-policy \
  --description "GitHub Actions ECS deploy permissions for demo-001 environment" \
  --policy-document file:///tmp/ecs-deploy-demo-001-policy.json
```

**Policy document (`/tmp/ecs-deploy-demo-001-policy.json`):**
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

**Expected output:** Same structure as Step 1.1 with `ECS-deploy-demo-001-policy`.

**Possible errors:** Same as Step 1.1.

**Verification:**
```bash
aws iam get-policy --policy-arn arn:aws:iam::405749097490:policy/ECS-deploy-demo-001-policy
```

---

#### Step 1.3: Create `ECS-deploy-shared-001-policy`

**Command:**
```bash
aws iam create-policy \
  --policy-name ECS-deploy-shared-001-policy \
  --description "GitHub Actions ECS deploy permissions for shared-001 environment" \
  --policy-document file:///tmp/ecs-deploy-shared-001-policy.json
```

**Policy document (`/tmp/ecs-deploy-shared-001-policy.json`):**
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

**Expected output:** Same structure as Step 1.1 with `ECS-deploy-shared-001-policy`.

**Possible errors:** Same as Step 1.1.

**Verification:**
```bash
aws iam get-policy --policy-arn arn:aws:iam::405749097490:policy/ECS-deploy-shared-001-policy
```

---

#### Step 1.4: Create `ECS-deploy-atento-001-policy`

**Command:**
```bash
aws iam create-policy \
  --policy-name ECS-deploy-atento-001-policy \
  --description "GitHub Actions ECS deploy permissions for atento-001 environment" \
  --policy-document file:///tmp/ecs-deploy-atento-001-policy.json
```

**Policy document (`/tmp/ecs-deploy-atento-001-policy.json`):**
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

**Expected output:** Same structure as Step 1.1 with `ECS-deploy-atento-001-policy`.

**Possible errors:** Same as Step 1.1.

**Verification:**
```bash
aws iam get-policy --policy-arn arn:aws:iam::405749097490:policy/ECS-deploy-atento-001-policy
```

---

### Phase 2: Attach Policies to Users

Attach the new managed policies to users. This phase MUST come after Phase 1 (policies must exist before attaching).

Order within this phase does not matter as operations are independent.

#### Step 2.1: Attach `ECS-deploy-beta-001-policy` to `app-staging`

**Command:**
```bash
aws iam attach-user-policy \
  --user-name app-staging \
  --policy-arn arn:aws:iam::405749097490:policy/ECS-deploy-beta-001-policy
```

**Expected output:** No output (exit code 0).

**Possible errors:**
| Error | Meaning | Action |
|-------|---------|--------|
| `NoSuchEntity` | User or policy doesn't exist | STOP - verify user/policy names, report to user |
| `LimitExceeded` | Too many policies attached to user | STOP - report to user |
| `AccessDenied` | No permission | STOP - report to user |

**Verification:**
```bash
aws iam list-attached-user-policies --user-name app-staging
```

**Expected verification output:**
```json
{
    "AttachedPolicies": [
        {
            "PolicyName": "S3-bucket-4shark-staging",
            "PolicyArn": "arn:aws:iam::405749097490:policy/S3-bucket-4shark-staging"
        },
        {
            "PolicyName": "ECS-deploy-beta-001-policy",
            "PolicyArn": "arn:aws:iam::405749097490:policy/ECS-deploy-beta-001-policy"
        }
    ]
}
```

---

#### Step 2.2: Attach `ECS-deploy-demo-001-policy` to `app-poc`

**Command:**
```bash
aws iam attach-user-policy \
  --user-name app-poc \
  --policy-arn arn:aws:iam::405749097490:policy/ECS-deploy-demo-001-policy
```

**Expected output:** No output (exit code 0).

**Possible errors:** Same as Step 2.1.

**Verification:**
```bash
aws iam list-attached-user-policies --user-name app-poc
```

---

#### Step 2.3: Attach `ECS-deploy-shared-001-policy` to `app-shared`

**Command:**
```bash
aws iam attach-user-policy \
  --user-name app-shared \
  --policy-arn arn:aws:iam::405749097490:policy/ECS-deploy-shared-001-policy
```

**Expected output:** No output (exit code 0).

**Possible errors:** Same as Step 2.1.

**Verification:**
```bash
aws iam list-attached-user-policies --user-name app-shared
```

---

#### Step 2.4: Attach `ECS-deploy-atento-001-policy` to `app-atento-001`

**Command:**
```bash
aws iam attach-user-policy \
  --user-name app-atento-001 \
  --policy-arn arn:aws:iam::405749097490:policy/ECS-deploy-atento-001-policy
```

**Expected output:** No output (exit code 0).

**Possible errors:** Same as Step 2.1.

**Verification:**
```bash
aws iam list-attached-user-policies --user-name app-atento-001
```

---

### Phase 3: Test Deployments (Manual)

**IMPORTANT:** This phase is manual. User must trigger GitHub Actions deploys and verify they work.

#### Step 3.1: Test Beta Deploy
- Trigger GitHub Actions workflow for beta-001
- Verify deploy succeeds
- Check CloudWatch logs for any permission errors

#### Step 3.2: Test Demo Deploy
- Trigger GitHub Actions workflow for demo-001
- Verify deploy succeeds
- Check CloudWatch logs for any permission errors

#### Step 3.3: Test Shared Deploy
- Trigger GitHub Actions workflow for shared-001
- Verify deploy succeeds
- Check CloudWatch logs for any permission errors

#### Step 3.4: Test Atento Deploy
- Trigger GitHub Actions workflow for atento-001
- Verify deploy succeeds
- Check CloudWatch logs for any permission errors

**If any test fails:** STOP - Do not proceed to Phase 4. Report to user for evaluation.

---

### Phase 4: Remove Old Inline Policies

This phase MUST come after Phase 3 (only after confirming new policies work).

**WHY THIS ORDER:** If we remove inline policies before testing, and the new policies have issues, deploys will break with no rollback option.

#### Step 4.1: Check which users have `EcsMaster` inline policy

**Command:**
```bash
aws iam list-user-policies --user-name app-staging
aws iam list-user-policies --user-name app-poc
```

**Expected output for app-staging:**
```json
{
    "PolicyNames": [
        "EcsMaster"
    ]
}
```

**Note:** Only proceed with deletion for users that have `EcsMaster` listed.

---

#### Step 4.2: Remove `EcsMaster` from `app-staging`

**Only execute if Step 4.1 confirmed `EcsMaster` exists on this user.**

**Command:**
```bash
aws iam delete-user-policy \
  --user-name app-staging \
  --policy-name EcsMaster
```

**Expected output:** No output (exit code 0).

**Possible errors:**
| Error | Meaning | Action |
|-------|---------|--------|
| `NoSuchEntity` | Policy doesn't exist | OK - already removed or never existed |
| `AccessDenied` | No permission | STOP - report to user |

**Verification:**
```bash
aws iam list-user-policies --user-name app-staging
```

**Expected verification output:**
```json
{
    "PolicyNames": []
}
```

---

#### Step 4.3: Remove `EcsMaster` from `app-poc` (if exists)

**Only execute if Step 4.1 confirmed `EcsMaster` exists on this user.**

**Command:**
```bash
aws iam delete-user-policy \
  --user-name app-poc \
  --policy-name EcsMaster
```

**Expected output:** No output (exit code 0).

**Possible errors:** Same as Step 4.2.

**Verification:**
```bash
aws iam list-user-policies --user-name app-poc
```

---

### Phase 5: Final Verification

#### Step 5.1: List all attached policies for all users

**Command:**
```bash
for user in app-staging app-poc app-shared app-atento-001; do
  echo "=== $user ==="
  echo "Attached policies:"
  aws iam list-attached-user-policies --user-name $user --query 'AttachedPolicies[*].PolicyName' --output text
  echo "Inline policies:"
  aws iam list-user-policies --user-name $user --query 'PolicyNames' --output text
  echo ""
done
```

**Expected output:**
```
=== app-staging ===
Attached policies:
S3-bucket-4shark-staging	ECS-deploy-beta-001-policy
Inline policies:

=== app-poc ===
Attached policies:
S3-bucket-4shark-poc	ECS-deploy-demo-001-policy
Inline policies:

=== app-shared ===
Attached policies:
S3-bucket-4shark-shared	ECS-deploy-shared-001-policy
Inline policies:

=== app-atento-001 ===
Attached policies:
S3-bucket-4shark-atento-001	ECS-deploy-atento-001-policy
Inline policies:

```

---

## Execution Checklist

| Step | Description | Status |
|------|-------------|--------|
| 1.1 | Create `ECS-deploy-beta-001-policy` | ⬜ |
| 1.2 | Create `ECS-deploy-demo-001-policy` | ⬜ |
| 1.3 | Create `ECS-deploy-shared-001-policy` | ⬜ |
| 1.4 | Create `ECS-deploy-atento-001-policy` | ⬜ |
| 2.1 | Attach beta policy to `app-staging` | ⬜ |
| 2.2 | Attach demo policy to `app-poc` | ⬜ |
| 2.3 | Attach shared policy to `app-shared` | ⬜ |
| 2.4 | Attach atento policy to `app-atento-001` | ⬜ |
| 3.1 | Test Beta deploy (manual) | ⬜ |
| 3.2 | Test Demo deploy (manual) | ⬜ |
| 3.3 | Test Shared deploy (manual) | ⬜ |
| 3.4 | Test Atento deploy (manual) | ⬜ |
| 4.1 | Check inline policies exist | ⬜ |
| 4.2 | Remove `EcsMaster` from `app-staging` | ⬜ |
| 4.3 | Remove `EcsMaster` from `app-poc` | ⬜ |
| 5.1 | Final verification | ⬜ |

---

## Rollback Plan

If something goes wrong after Phase 2:

1. **Deploy failing with new policy:** Keep the old `EcsMaster` inline policy (don't delete in Phase 4)
2. **Need to remove new policy:**
   ```bash
   aws iam detach-user-policy --user-name <USER> --policy-arn <POLICY_ARN>
   aws iam delete-policy --policy-arn <POLICY_ARN>
   ```
3. **Need to recreate inline policy:** Use the JSON from "Current State" section and:
   ```bash
   aws iam put-user-policy --user-name <USER> --policy-name EcsMaster --policy-document file://ecsMaster.json
   ```

---

## Notes

- `ecs:DescribeTaskDefinition` and `ecs:RegisterTaskDefinition` require `Resource: "*"` (AWS limitation - task definitions are account-level, not cluster-scoped)
- `ecr:GetAuthorizationToken` requires `Resource: "*"` (AWS limitation)
- `app-development` is excluded - only used for local development S3 bucket access
