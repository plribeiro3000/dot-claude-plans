# SPIKE — IAM Users and Permissions Management in Terraform for Integrator

**Conducted by:** Engineering Team
**Date:** 2026-03-03
**Status:** Research complete — pending decisions

---

## Goal

The Integrator project currently creates IAM users and S3 buckets manually for each client account (atento-br, atento-mx, commcenter, almaviva, etc.). The goal of this spike is to answer the following questions before automating this with Terraform:

1. Should IAM resources live inside each client's environment directory or in a central module?
2. Should we use IAM users with access keys or IAM roles with instance profiles for EC2 → AWS access?
3. How should IAM policies for S3 (single bucket) and EC2 StopInstances (specific instances) be structured?
4. How should IAM access keys be handled securely in Terraform (state file, rotation, Secrets Manager)?
5. How should the Terraform module be structured — extend the existing `integrator` module or create a separate one?
6. How to handle IAM isolation when multiple client accounts (atento-br, atento-mx) share infrastructure in the same VPC?

---

## Method

- Analyzed the existing Terraform project structure at `/Users/plribeiro3000/Projects/4Shark/terraform`
- Read the integrator module (`modules/integrator/`) and all client environment directories
- Read existing IAM-related modules (`modules/iam_deploy/`, `modules/lambda-iam/`)
- Searched for AWS Well-Architected Framework recommendations on IAM users vs roles
- Researched Terraform community best practices for IAM module design (centralized vs distributed)
- Searched for patterns around secret management in Terraform state files
- Researched EC2 instance profile attachment behavior in Terraform

---

## Evidence

### Current Terraform Project Structure

The project uses Terramate to orchestrate multiple Terraform stacks. Each integrator client has its own environment directory that is a Terraform root module:

```
terraform/
├── integrator-atento-br/      # Root module: calls modules/integrator
├── integrator-commcenter/     # Root module: calls modules/integrator
├── integrator-almaviva/       # Root module: calls modules/integrator
├── integrator-redebrasil/     # Root module: calls modules/integrator
├── integrator-aster-maquinas/ # Root module: calls modules/integrator
├── integrator-maqnelson/      # Root module: calls modules/integrator
└── modules/
    ├── integrator/            # Shared module: EC2, Redis, MongoDB, VPN, DNS
    ├── iam_deploy/            # Existing: IAM for CI/CD deploy users
    ├── lambda-iam/            # Existing: IAM roles for Lambda functions
    └── s3_bucket/             # Existing: S3 bucket with encryption and access blocks
```

The `modules/integrator` module currently manages: EC2 app servers, MongoDB EC2 cluster, ElastiCache Redis, VPN, DNS, and security groups. It does NOT manage IAM or S3.

**Key observation about atento-br/atento-mx:** The `integrator-atento-br` environment manages servers for both atento-br AND atento-mx in the same VPC/stack:
```hcl
app_servers = {
  "app002"    = { instance_type = "t3.medium", subnet_key = "prv-a" }
  "mx-app002" = { instance_type = "t3.medium", subnet_key = "prv-a", name = "4client-atento-mx-app002" }
}
```
This means atento-mx does not have its own Terraform stack — it shares the atento-br infrastructure stack.

**Existing IAM patterns:**
- `modules/iam_deploy/`: Creates IAM policies and attaches them to an existing IAM user (for CI/CD). Creates only policies, not users.
- `modules/lambda-iam/`: Creates IAM roles and policies for Lambda functions — uses trust policies, roles, and role policy attachments.
- Neither module creates IAM users with access keys.

**Existing s3_bucket module:** Creates an S3 bucket with encryption (AES256), versioning, and full public access block. Does not create IAM users/policies scoped to that bucket.

### Q1: Centralized vs Distributed IAM

**Community finding:** HashiCorp's module design guidance recommends keeping IAM resources separate from application infrastructure when those policies exceed ~150 lines or when access controls are managed by a different team. The reasoning is that IAM policies change independently from compute resources and having them in the same module increases churn and risk.

**AWS Prescriptive Guidance (Terraform):** Recommends functional separation — networking, compute, IAM should be separate concerns. A separate module for IAM is the recommended pattern for reusable teams.

**Finding:** For this project, a separate `modules/integrator_iam` module is the appropriate approach. Each client's IAM resources (user, policies, S3 bucket) have the same structure but differ only in names and resource ARNs. A module prevents duplication across 6+ client stacks.

**Placement:** IAM resources should be called from each client's environment directory (`integrator-atento-br/main.tf`) alongside the existing `module "this"` call. This follows the existing pattern and keeps each client's state isolated.

### Q2: IAM User vs IAM Role (Instance Profile)

**AWS Well-Architected Framework recommendation (SEC02):** "Rely on temporary credentials instead of IAM users with long-term credentials." For workloads running on EC2, the framework explicitly recommends IAM roles with instance profiles because:
- Credentials are temporary and auto-rotated by the AWS metadata service (no manual rotation needed)
- No credentials stored in files, environment variables, or Terraform state
- Permissions can be updated centrally without touching instances
- If a credential is compromised, it expires automatically (typically in 1 hour)

**IAM User with access keys problems:**
- Long-lived credentials (never expire unless rotated)
- Stored in Terraform state file in plaintext (or encrypted with PGP)
- Must be distributed to the application (environment variables, config files)
- Rotation requires coordinated Terraform apply + application restart
- Terraform state file must be treated as a secret

**IAM Role with instance profile for this use case:**
- EC2 instances call the AWS metadata service (IMDSv2) for temporary credentials
- The AWS SDK (used by the Integrator Ruby app) automatically discovers and uses these credentials — no `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` environment variables needed
- S3 access works: `aws s3 cp` and SDK calls use the instance role automatically
- EC2 StopInstances API works the same way

**Critical constraint:** Changing `iam_instance_profile` on an existing `aws_instance` resource in Terraform forces instance replacement by default. This is a known Terraform behavior (GitHub issue #11992). However, AWS itself supports attaching an IAM role to an existing instance via `aws ec2 associate-iam-instance-profile` without stopping the instance.

**Workaround for existing instances:** Add `lifecycle { ignore_changes = [iam_instance_profile] }` to existing EC2 resources, then attach the role out-of-band using AWS CLI, and gradually migrate.

**Alternative: IAM Users are still needed when:**
- The application runs outside AWS (on-premises client VPN machines need to push to S3)
- Third-party software requires static credentials and does not support instance metadata
- Cross-account access is needed without STS AssumeRole

**Finding for Integrator:** The EC2 instances ARE on AWS. The Integrator Ruby application runs on these EC2 instances. **IAM roles with instance profiles are the correct long-term approach.** However, since the existing instances were provisioned without `iam_instance_profile`, adding it to Terraform will trigger recreation unless `ignore_changes` is used or instances are migrated carefully.

**If credentials are also needed as environment variables** (e.g., for legacy code paths or non-SDK calls), SSM Parameter Store can be used: Terraform stores the keys in SSM, the instance reads them at boot via user_data or a startup script.

### Q3: Least Privilege IAM Policies

**S3 — Single bucket per client:**

```hcl
statement {
  sid    = "S3ColdStorageAccess"
  effect = "Allow"
  actions = [
    "s3:GetObject",
    "s3:PutObject",
    "s3:DeleteObject",
    "s3:ListBucket"
  ]
  resources = [
    "arn:aws:s3:::${var.bucket_name}",
    "arn:aws:s3:::${var.bucket_name}/*"
  ]
}
```

Note: `s3:ListBucket` applies to the bucket ARN (without `/*`), while object actions apply to `bucket/*`. Both must be listed.

**EC2 StopInstances — specific instance IDs:**

EC2 resource-level permissions support restricting `StopInstances` to specific instance ARNs. The recommended approach is using tags as conditions (more maintainable than hardcoded instance IDs):

```hcl
# Option A: Restrict by instance ARN (hardcoded, requires ARN list as input)
statement {
  sid     = "EC2StopOwnInstances"
  effect  = "Allow"
  actions = ["ec2:StopInstances"]
  resources = [for arn in var.instance_arns : arn]
}

# Option B: Restrict by tag (preferred, self-service)
statement {
  sid     = "EC2StopTaggedInstances"
  effect  = "Allow"
  actions = ["ec2:StopInstances"]
  resources = ["arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:instance/*"]
  condition {
    test     = "StringEquals"
    variable = "ec2:ResourceTag/Client"
    values   = [var.client_name]
  }
}

# Describe actions do NOT support resource-level permissions — must be separate statement with "*"
statement {
  sid     = "EC2DescribeInstances"
  effect  = "Allow"
  actions = ["ec2:DescribeInstances", "ec2:DescribeInstanceStatus"]
  resources = ["*"]
}
```

**Finding:** The tag-based condition is preferable because the `Client` tag is already applied to all EC2 instances by the integrator module (via `local.common_tags`). This means the policy is self-maintaining as new instances are added.

**Important note:** `ec2:DescribeInstances` and similar Describe actions do not support resource-level permissions and must always use `"Resource": "*"`. This is an AWS API limitation, not a Terraform one.

### Q4: Secret Management for IAM Access Keys

**The core problem:** When Terraform creates `aws_iam_access_key`, both the `id` (access key ID) and `secret` (secret access key) are stored in the Terraform state file in plaintext. The state file is already in an encrypted S3 bucket (`4shark-terraform-state`), but any team member with state access can read the secrets.

**Options researched:**

**Option A: Terraform creates keys, outputs as sensitive, stored in state**
- Terraform manages the full lifecycle
- State file contains plaintext secrets (encrypted at rest in S3)
- Easy to implement, no extra infrastructure
- Rotation requires `terraform taint aws_iam_access_key.this` + apply + update application env vars
- Risk: state file is a secret; compromised state = compromised credentials

**Option B: Terraform creates keys, stores in AWS Secrets Manager**
- Terraform creates the access key, then stores it in Secrets Manager via `aws_secretsmanager_secret_version`
- State file still contains the plaintext secret (unavoidable with `aws_iam_access_key`)
- Application reads credentials from Secrets Manager at runtime
- Built-in rotation via Lambda functions in Secrets Manager
- Higher cost (~$0.40/secret/month + API calls)
- More operational complexity

**Option C: Terraform creates keys, stores in SSM Parameter Store (SecureString)**
- Same as Option B but uses SSM instead of Secrets Manager
- Cheaper ($0.05/parameter/month for SecureString standard tier)
- No built-in rotation, but simpler
- Application or Ansible can pull parameters at boot time
- State file still contains plaintext secrets

**Option D: Terraform creates IAM user only, access keys created out-of-band**
- Terraform manages `aws_iam_user`, `aws_iam_policy`, `aws_iam_user_policy_attachment`
- Access keys are created manually or via AWS CLI and stored in Secrets Manager/SSM by another process
- Keys never appear in Terraform state
- Rotation is manual (but doesn't require Terraform)
- Clean separation of concerns

**Option E: Skip IAM users, use IAM roles (instance profiles)**
- No access keys at all
- No state file secrets
- AWS handles credential rotation automatically
- Application must use AWS SDK (not raw env vars like `AWS_ACCESS_KEY_ID`)
- Cannot be used if the application is running outside EC2

**Finding:** Options D and E are the most secure. Option E is the best long-term approach for EC2-hosted workloads. If IAM users are truly required (legacy compatibility), Option D avoids exposing secrets in state.

**Key constraint on Terraform access key resource:** The `aws_iam_access_key` resource's `secret` attribute is marked as `sensitive` in Terraform but is still stored in the state file in plaintext. There is no way to avoid this with the current Terraform AWS provider. PGP encryption is the only built-in mitigation (`pgp_key` input), but it requires a PGP key setup and complicates the workflow.

### Q5: Module Design Recommendation

**Current project conventions observed:**
- Separate modules in `modules/` directory for each logical concern
- Modules are thin wrappers: they accept variables, create resources, output values
- Client environments call `module "this"` (the integrator module) and `module "networking_data"` separately
- The `s3_bucket` module and `iam_deploy` module are already separate reusable modules

**Proposed design:** A new `modules/integrator_iam` module that creates:
- `aws_iam_role` + `aws_iam_instance_profile` (for the EC2 instance to assume)
- `aws_iam_policy` (S3 bucket access + EC2 StopInstances for tagged instances)
- `aws_iam_role_policy_attachment`
- Optionally: `aws_iam_user` + `aws_iam_access_key` (if IAM users are decided upon)

The S3 bucket itself should remain a separate call to `modules/s3_bucket` (already exists), consistent with the existing pattern.

**Integration in client environment directories:**
```hcl
# integrator-atento-br/main.tf
module "s3_cold_storage" {
  source      = "../modules/s3_bucket"
  bucket_name = "4client-atento-br-cold-storage"
}

module "iam" {
  source       = "../modules/integrator_iam"
  client_name  = "atento-br"
  bucket_name  = module.s3_cold_storage.bucket_name
  region       = "sa-east-1"
}
```

**Should IAM be inside the existing `integrator` module?**
- Argument for: single module call, less boilerplate per client
- Argument against: IAM is a global AWS resource (not regional), follows a different change cadence, and IAM module composition allows opt-in adoption without force-recreating existing infrastructure
- Community consensus (HashiCorp guidance): keep IAM separate
- Project precedent: `iam_deploy` module is already separate

**Finding:** Create a new `modules/integrator_iam` module. Do NOT add IAM into the existing `modules/integrator` module. Call it separately from each client's environment directory.

### Q6: Multi-Account IAM Isolation (atento-br vs atento-mx)

**Observed situation:** atento-br and atento-mx share the same Terraform stack (`integrator-atento-br/`), the same VPC, and the same Redis/MongoDB cluster. They have separate EC2 instances (`app002` for atento-br, `mx-app002` for atento-mx).

**IAM isolation requirements:**
- Each logical client needs its own IAM principal (role or user)
- atento-br's IAM role should only access the atento-br S3 bucket
- atento-mx's IAM role should only access the atento-mx S3 bucket
- atento-br instances should only stop atento-br instances; atento-mx should only stop atento-mx instances

**With IAM roles (instance profiles):** Each EC2 instance has exactly one instance profile. Since atento-br and atento-mx have separate EC2 instances (different `aws_instance` resources with different names), they can each have their own IAM role with appropriate permissions. The tag-based EC2 StopInstances condition works naturally because the `Client` tag differs between the two.

**With IAM users:** Two separate IAM users (`integrator-atento-br`, `integrator-atento-mx`), two separate policies scoped to their respective S3 buckets, and the EC2 stop policy scoped to their respective instance tags.

**Key challenge for atento-mx:** atento-mx has no dedicated Terraform stack. Its resources are managed inside `integrator-atento-br/`. If we need to create separate IAM resources for atento-mx, they would be defined in `integrator-atento-br/main.tf` with explicit configuration for the `atento-mx` client name.

---

## Conclusions

### 1. IAM User vs IAM Role

**Recommendation: IAM roles with instance profiles** for EC2-based access (S3 and EC2 StopInstances). This is the AWS Well-Architected Framework's explicit recommendation for workloads running on EC2. It eliminates long-lived credentials, eliminates secrets in the Terraform state file, and eliminates manual rotation.

**If the application requires static credentials** (e.g., environment variables are hardcoded in the app and cannot be changed to use SDK auto-discovery), IAM users are acceptable short-term but must be treated as technical debt. Access keys should be created outside of Terraform (Option D above) and stored in SSM Parameter Store.

**Migration risk:** Adding `iam_instance_profile` to existing Terraform-managed EC2 instances triggers instance replacement. To avoid disruption, add `lifecycle { ignore_changes = [iam_instance_profile] }` to the existing `aws_instance.app` resource in the integrator module and attach the role via AWS CLI for existing instances. New instances created by Terraform will have the profile automatically.

### 2. IAM Placement — Centralized or Distributed

**Recommendation: Distributed — one call per client environment directory**, implemented via a shared reusable module (`modules/integrator_iam`). This follows the existing project pattern, maintains state isolation between clients, and allows each client's IAM resources to evolve independently.

### 3. Module Design

**Recommendation: New `modules/integrator_iam` module** with the following resources:
- `aws_iam_role` + `aws_iam_instance_profile` (EC2 identity)
- `aws_iam_policy` (S3 bucket access scoped to the client's bucket + EC2 stop scoped by `Client` tag)
- `aws_iam_role_policy_attachment`

The S3 bucket is created via the existing `modules/s3_bucket` module, separately from IAM. Both are called from the client's environment directory.

### 4. Least Privilege Policies

**S3:** Use both `arn:aws:s3:::bucket-name` (for ListBucket) and `arn:aws:s3:::bucket-name/*` (for object operations). Do not use wildcards on the bucket name.

**EC2 StopInstances:** Use tag-based condition `ec2:ResourceTag/Client = "atento-br"` instead of hardcoded instance ARNs. The `Client` tag is already applied by the integrator module. `ec2:DescribeInstances` requires `Resource: "*"` (AWS limitation — Describe actions don't support resource-level permissions).

### 5. Secret Management

**For IAM roles (recommended path):** No secrets to manage. The instance metadata service provides temporary credentials automatically.

**If IAM users are used:**
- Do NOT create `aws_iam_access_key` via Terraform (secrets appear in state file)
- Create IAM users via Terraform, create access keys via AWS CLI, store in SSM Parameter Store as SecureString
- Ansible can retrieve SSM parameters at deployment time and inject them as environment variables

### 6. atento-mx IAM Isolation

**With IAM roles:** Create two separate instance profiles within the `integrator-atento-br` stack — one for atento-br instances, one for atento-mx instances. Each role has its own S3 bucket policy and the EC2 stop policy is scoped by the respective `Client` tag value.

**This works because:** atento-br and atento-mx have separate EC2 instances (`aws_instance.app["app002"]` vs `aws_instance.app["mx-app002"]`), so each can have a distinct `iam_instance_profile`.

---

## Next Steps

This investigation reveals two decision points that require engineer input before implementation can begin:

**Decision 1 — IAM Role vs IAM User:**
- **Option A (recommended):** Migrate to IAM roles with instance profiles. Requires modifying the EC2 instance resource in `modules/integrator/app.tf` to accept an `iam_instance_profile` variable, and handling the migration of existing instances carefully (lifecycle ignore_changes + manual attach).
- **Option B (short-term):** Keep IAM users. Create IAM users via Terraform, create access keys out-of-band (AWS CLI), store in SSM Parameter Store. Less disruption but leaves technical debt.

**Decision 2 — Scope of first implementation:**
- Implement for all client accounts at once, or start with one (e.g., commcenter) as a pilot?

**If engineer approves the recommended path (IAM roles):**
- Use `@agent-planner` to create a PLAN.md for implementing `modules/integrator_iam`
- The plan must address: module creation, EC2 instance profile variable addition, migration strategy for existing instances, atento-mx isolation approach

**If engineer chooses IAM users (short-term):**
- Plan is simpler: `modules/integrator_iam` creates user + policies only, access keys created via separate runbook

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
>
> **Further reading:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/technical-spike/)
