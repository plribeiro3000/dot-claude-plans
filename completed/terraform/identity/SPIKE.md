# SPIKE — Centralized Terraform Stack for Multi-Provider Engineer Access Management

**Conducted by:** Engineering Team
**Date:** 2026-03-03 → 2026-03-09
**Status:** Research complete — decisions made

---

## Goal

Design a single Terraform stack (`identity`) that:

1. Manages engineer access across all infrastructure providers (AWS, MongoDB Atlas, Redis Cloud, Netlify, Rollbar, Cloudflare) so that adding or removing an engineer automatically grants or revokes the right permissions everywhere.
2. Implements a two-tier permission model: minimal baseline for daily operations and temporary elevated access for sensitive/destructive operations, protected by MFA (YubiKey).

Secondary questions investigated:
- Where does this stack live in the existing Terraform project?
- How are engineers defined as a single variable?
- How to solve the bootstrap problem (Terraform needs credentials to manage credentials)?
- Is `sts:AssumeRole` + MFA sufficient for the threat model, or does root-account elevation provide better security?
- Are engineer emails in state a security concern?

---

## Method

- Analyzed the existing Terraform project structure at `/Users/plribeiro3000/Projects/4Shark/terraform`
- Reviewed Terraform Registry documentation and GitHub repositories for each provider
- Searched community articles and AWS prescriptive guidance for IAM patterns
- Reviewed the existing `iam_deploy` and `lambda-iam` modules for project conventions
- Compared `sts:AssumeRole` + MFA against root-account-based elevation for the 4Shark threat model

---

## Part 1 — Elevation Mechanism

### Threat Model

The primary risk is **leaked access keys** — accidentally committed to git, exposed in `.env` files, captured in logs, or stolen from a compromised machine.

Secondary risk: **physical device theft** (laptop stolen with YubiKey attached).

Root account compromise is out of scope — it is protected by a separate YubiKey and is the last-resort break-glass account.

### Option A — `sts:AssumeRole` + MFA condition (CHOSEN)

Engineers have a baseline IAM user with minimal daily permissions. A separate IAM role (`engineers-elevated`) grants destructive/sensitive permissions. The role's trust policy requires MFA to assume it.

**How it works:**
1. Engineer runs `aws sts assume-role` with `--serial-number` (YubiKey ARN) and `--token-code` (OTP)
2. Receives temporary credentials valid for up to 1h
3. Uses those credentials for the sensitive operation
4. Credentials expire automatically — no manual revocation needed

**Conditions on the elevated role's trust policy:**
```hcl
condition {
  test     = "Bool"
  variable = "aws:MultiFactorAuthPresent"
  values   = ["true"]
}

condition {
  test     = "NumericLessThan"
  variable = "aws:MultiFactorAuthAge"
  values   = ["3600"]  # MFA must have been used within the last hour
}
```

**Threat model coverage:**

| Threat | Baseline only | Baseline + AssumeRole + MFA |
|--------|--------------|------------------------------|
| Leaked access key | Exposed to all baseline permissions | Cannot assume elevated role |
| Laptop + YubiKey stolen | Same as below | Vulnerable (same as root) |
| Audit trail | CloudTrail (user actions) | CloudTrail (role assumption + actions) |
| Reversible via Terraform | Yes | Yes |
| Engineer autonomy | Full | Full |

### Option B — Root Account Elevation (REJECTED)

Engineer or account owner logs in as root (with root YubiKey) to perform sensitive operations or temporarily grant permissions.

**Problems:**
- Root actions in CloudTrail are less granular than IAM role actions
- Creates a bottleneck — requires another person to be available
- Cannot be automated even when legitimate
- Root account should be reserved for true break-glass (account recovery, billing-only actions)
- Does not scale as team grows

**Verdict:** Root is the last-resort break-glass, not an operational mechanism.

### Option C — IAM Identity Center (SSO) with Permission Sets (DEFERRED)

AWS-managed SSO with permission sets for baseline and elevated access. MFA enforced at the SSO level.

**Why not chosen now:**
- Adds complexity for a 3-person team
- Requires AWS Organizations setup
- `sts:AssumeRole` achieves the same security with less infrastructure
- Can be migrated to Identity Center later if the team grows

### Decision

**Option A — `sts:AssumeRole` + MFA condition.**

Root account remains protected by YubiKey and is used exclusively for:
- Account recovery
- Billing-only console actions that cannot be delegated
- True emergency access if IAM is entirely compromised

### Permission Split

#### Baseline Group (`engineers-baseline`)
Daily operations — always available via access key:
- `ReadOnlyAccess` (AWS managed policy) as foundation
- Write permissions limited to: ECS deploys, ECR push, SSM parameters (own namespace), CloudWatch logs
- `sts:AssumeRole` on `engineers-elevated` (MFA condition enforced on the role itself)

#### Elevated Role (`engineers-elevated`)
Sensitive operations — requires MFA assumption (1h session max):
- RDS modifications (snapshots, parameter groups, instance class changes)
- KMS key policy changes
- IAM changes (outside of the `identity` stack Terraform role)
- S3 bucket policy changes
- Security group modifications
- EC2 instance termination
- VPC and networking changes
- CloudTrail and CloudWatch alarm modifications

#### Terraform Execution Role (separate — not managed here)
Used by Terraform runs only — not by engineers directly:
- Scoped permissions per stack
- Assumed by CI/CD or local Terraform with dedicated credentials

### Engineer Workflow for Elevation

```bash
# Add to ~/.aws/config
[profile elevated]
role_arn       = arn:aws:iam::ACCOUNT_ID:role/engineers-elevated
source_profile = default
mfa_serial     = arn:aws:iam::ACCOUNT_ID:mfa/paulo.ribeiro

# Use when a sensitive operation is needed
AWS_PROFILE=elevated terraform apply   # prompts for MFA OTP
```

---

## Part 2 — Multi-Provider Research

### Current Project Structure

The existing Terraform project at `/Users/plribeiro3000/Projects/4Shark/terraform` uses **Terramate** for stack orchestration. Each environment is a separate stack with its own `stack.tm.hcl`, `providers.tf`, and `backend "s3"` pointing to `4shark-terraform-state`.

Key observations:
- Backend: S3 bucket `4shark-terraform-state` in `us-east-1`, state key per stack
- Providers already in use: `hashicorp/aws >= 5.0`, `mongodb/mongodbatlas ~> 2.0`, `RedisLabs/rediscloud ~> 2.0`
- No existing stack manages human engineer access — only service accounts (ECS task roles, deploy users, CI/CD)
- The `modules/iam_deploy` module creates CI/CD deploy users; no equivalent for humans exists

---

### Provider 1: AWS IAM (`hashicorp/aws`)

**Terraform support:** Full and mature.

| Resource | Purpose |
|---|---|
| `aws_iam_user` | Creates a human IAM user |
| `aws_iam_user_login_profile` | Enables AWS Console access with initial password |
| `aws_iam_access_key` | Creates programmatic access keys (CLI/Terraform) |
| `aws_iam_group` | Creates a group to attach policies to |
| `aws_iam_group_membership` | Adds users to a group |
| `aws_iam_group_policy_attachment` | Attaches a managed policy to a group |
| `aws_iam_role` | Creates the elevated role |
| `aws_iam_role_policy` | Attaches policy to the elevated role |

**MFA enforcement note:** Terraform does NOT enforce MFA setup directly. An IAM policy that denies all actions when MFA is absent must be attached to the baseline group. Without MFA, the user can only call `iam:CreateVirtualMFADevice` and `iam:EnableMFADevice` on themselves.

```hcl
# MFA enforcement policy attached to engineers-baseline group
{
  "Effect": "Deny",
  "NotAction": [
    "iam:CreateVirtualMFADevice",
    "iam:EnableMFADevice",
    "iam:GetUser",
    "iam:ListMFADevices",
    "sts:GetSessionToken"
  ],
  "Resource": "*",
  "Condition": {
    "BoolIfExists": { "aws:MultiFactorAuthPresent": "false" }
  }
}
```

**Sources:**
- [aws_iam_user — Terraform Registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user)
- [aws_iam_access_key — Terraform Registry](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_access_key)
- [Enforcing MFA for AWS IAM Users with Terraform — Medium](https://varunmanik1.medium.com/enforcing-mfa-for-aws-iam-users-with-cloudformation-terraform-2be6cb67a68c)

---

### Provider 2: MongoDB Atlas (`mongodb/mongodbatlas`)

**Terraform support:** Partial — org-level assignment supported, with known limitations.

| Resource | Status | Purpose |
|---|---|---|
| `mongodbatlas_cloud_user_org_assignment` | **Current (recommended)** | Assign/remove a user to/from an org with org-level roles |
| `mongodbatlas_org_invitation` | **Deprecated** | Replaced by `cloud_user_org_assignment` |

**Critical limitation:** The user must **already have a MongoDB Atlas account** before this resource can be applied. `cloud_user_org_assignment` does NOT send an invitation — it directly assigns an existing user. If the user does not have an Atlas account, Terraform will fail.

**Available org-level roles:** `ORG_OWNER`, `ORG_MEMBER`, `ORG_GROUP_CREATOR`, `ORG_BILLING_ADMIN`, `ORG_BILLING_READ_ONLY`, `ORG_READ_ONLY`

**Credentials needed:** Atlas API key with `Organization Owner` role.

**Sources:**
- [mongodbatlas_cloud_user_org_assignment — GitHub docs](https://github.com/mongodb/terraform-provider-mongodbatlas/blob/master/docs/resources/cloud_user_org_assignment.md)
- [Invitation handling broken after user accepted — GitHub issue #945](https://github.com/mongodb/terraform-provider-mongodbatlas/issues/945)

---

### Provider 3: Redis Cloud (`RedisLabs/rediscloud`)

**Terraform support for portal/team access:** NOT available.

The `rediscloud_acl_user` resource manages **database-level ACL users** (application credentials), not portal team members. These are entirely different concepts.

**Available portal roles (UI-only, no Terraform):** Owner, Billing Admin, Manager, Member, Viewer, Logs Viewer.

**Conclusion:** Terraform **cannot** manage Redis Cloud portal/team access. Management must be done through the Redis Cloud Console UI.

**Sources:**
- [Redis Cloud Terraform provider resources — GitHub](https://github.com/RedisLabs/terraform-provider-rediscloud/tree/master/docs/resources)
- [Access management — Redis docs](https://redis.io/docs/latest/operate/rc/security/access-control/access-management/)

---

### Provider 4: Netlify (`netlify/netlify`)

**Terraform support for team members:** NOT available.

The Netlify Terraform provider (v2) has 12 resources, none of which manage team members or user invitations. The Netlify REST API does support full team member management endpoints (`POST`, `PUT`, `DELETE` on `/{account_slug}/members`), but the provider does not expose them.

**Conclusion:** Terraform **cannot** manage Netlify team members. Management must be done through the UI.

**Sources:**
- [netlify/terraform-provider-netlify resources — GitHub](https://github.com/netlify/terraform-provider-netlify/tree/main/docs/resources)
- [Manage team members — Netlify docs](https://docs.netlify.com/manage/accounts-and-billing/team-management/manage-team-members/)

---

### Provider 5: Rollbar (`rollbar/rollbar`)

**Terraform support:** Full — users and teams are manageable.

| Resource | Purpose |
|---|---|
| `rollbar_team` | Create/manage a team |
| `rollbar_team_user` | Add a user to a team; sends invite if user doesn't exist |
| `rollbar_user` | Manage a user (requires email and team_ids) |
| `rollbar_project_access_token` | Manage project tokens |

**Invitation model:** After `terraform apply`, the engineer receives an email invitation and must accept it. Terraform marks the user as `invited` until they register. Re-applies are idempotent.

**Credentials needed:** Rollbar account-level API token via `ROLLBAR_API_KEY` environment variable.

**Sources:**
- [rollbar_team_user resource — GitHub docs](https://github.com/rollbar/terraform-provider-rollbar/blob/master/docs/resources/team_user.md)

---

### Provider 6: Cloudflare (`cloudflare/cloudflare`)

**Terraform support:** Full via API tokens — zone-scoped permissions manageable.

The `cloudflare_api_token` resource creates scoped API tokens per engineer. Each token can be limited to specific zones and specific permissions (DNS read/write, etc.).

**Note:** Cloudflare does not have a concept of "team members" in the same way as other providers — access is managed via API tokens, not user accounts per engineer.

**Sources:**
- [cloudflare-terraform spike](../cloudflare-terraform/SPIKE.md) — detailed provider research

---

## Part 3 — Supporting Decisions

### Project Structure

**Recommendation: New Terramate stack inside the existing project, named `identity`**

The name `identity` is preferred over `iam` or `terraform-iam` because:
- `iam` is AWS-specific; this stack manages access across multiple providers
- `terraform-` prefix is redundant in a Terraform repository
- `identity` is the term used by AWS (IAM Identity Center), HashiCorp Vault, and the industry broadly — provider-agnostic and conceptually accurate

```
/Users/plribeiro3000/Projects/4Shark/terraform/
└── identity/
    ├── stack.tm.hcl         # Terramate stack definition — no dependencies on other stacks
    ├── providers.tf         # aws + mongodbatlas + rollbar + cloudflare
    ├── variables.tf         # engineers map variable + provider config variables
    ├── outputs.tf
    ├── aws_users.tf         # aws_iam_user per engineer (imported from existing)
    ├── aws_groups.tf        # engineers-baseline group + policy attachments
    ├── aws_roles.tf         # engineers-elevated role + trust policy with MFA condition
    ├── aws_policies.tf      # Baseline policy doc, MFA enforcement policy, elevated policy doc
    ├── mongodb.tf           # mongodbatlas_cloud_user_org_assignment per engineer
    ├── rollbar.tf           # rollbar_team + rollbar_team_user per engineer
    ├── cloudflare.tf        # cloudflare_api_token per engineer
    └── terraform.tfvars     # engineers = { ... }
```

Redis Cloud and Netlify are excluded — they require manual management through their UIs until providers add support.

### Engineer Variable Definition

```hcl
# variables.tf
variable "engineers" {
  description = "Map of engineers and their access configuration"
  type = map(object({
    email              = string
    aws_console_access = bool
    atlas_role         = optional(string, "ORG_MEMBER")
  }))
}

# terraform.tfvars
engineers = {
  "paulo" = {
    email              = "paulo.ribeiro@4shark.com.br"
    aws_console_access = true
    atlas_role         = "ORG_MEMBER"
  }
  "elisio" = {
    email              = "elisio.filho@4shark.com.br"
    aws_console_access = true
    atlas_role         = "ORG_MEMBER"
  }
  "emerson" = {
    email              = "emerson.silva@4shark.com.br"
    aws_console_access = true
    atlas_role         = "ORG_MEMBER"
  }
}
```

When an engineer leaves: remove their entry from `terraform.tfvars` and run `terraform apply`. All resources for that key are destroyed across all providers.

### Bootstrap Problem

**Standard two-phase approach:**

Phase 1 — Manual one-time setup (by account owner with `AdministratorAccess`):
1. Account owner creates a dedicated IAM user or uses existing admin credentials to run this stack
2. Bootstrap credentials are NOT managed by `identity` itself — stored in 1Password
3. Bootstrap credentials used only for `identity/`, not for general development

Phase 2 — Ongoing operation:
- After first `terraform apply`, all engineers have their IAM users and access keys
- Engineers use their own credentials for all other stacks
- Bootstrap user credentials remain with the account owner

### Sensitive Data in State

| Data | Sensitivity | How to handle |
|---|---|---|
| Engineer emails | Low (PII, not secret) | Acceptable in state; ensure S3 bucket is not public |
| AWS access key IDs | Low | Not secret by itself |
| AWS secret access keys | HIGH | Must use `pgp_key` encryption in `aws_iam_access_key` |
| AWS initial console passwords | HIGH | Must use `pgp_key` encryption in `aws_iam_user_login_profile` |
| Rollbar API key (provider auth) | HIGH | Store in environment variable, never in `.tfvars` |
| MongoDB Atlas API key (provider auth) | HIGH | Store in environment variable, never in `.tfvars` |

---

## Conclusions

### What IS possible via Terraform

| Provider | Resource | Notes |
|---|---|---|
| AWS IAM | Groups, users, roles, policies, access keys | Full support — baseline + elevated model |
| MongoDB Atlas | `mongodbatlas_cloud_user_org_assignment` | User must have existing Atlas account |
| Rollbar | `rollbar_team_user`, `rollbar_team` | Sends invitation if user doesn't exist |
| Cloudflare | `cloudflare_api_token` | Zone-scoped API tokens per engineer |

### What is NOT possible via Terraform (manual + documented)

| Provider | Reason | Action |
|---|---|---|
| Redis Cloud (portal access) | No Terraform resource for team members | Redis Cloud Console UI — document in runbook |
| Netlify (team members) | Provider has no team member resource | Netlify Console UI — document in runbook |

### Manual Steps That Will Always Be Required

- Engineers must create their MongoDB Atlas account before Terraform can assign them
- Engineers must accept the Rollbar email invitation after `terraform apply`
- Engineers must set up TOTP MFA (via 1Password) in the AWS console after first login
- The account owner must run the first `terraform apply` with bootstrap credentials

---

## Next Steps

1. Audit current IAM state — list existing users (paulo, elisio, emerson), their current permissions, and what needs to be imported vs created
2. Define exact permission lists for `engineers-baseline` and `engineers-elevated` based on audit
3. Create `identity/` stack following the structure above
4. Import existing engineer IAM users into Terraform state
5. Create groups, elevated role with MFA conditions, and provider access
6. Document Redis Cloud and Netlify manual procedures in a runbook
7. Create PLAN.md for implementation (`@agent-planner`)
