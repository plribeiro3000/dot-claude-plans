# PLAN — Identity Stack Phase 2: Elevated Role Expansion + Engineer Setup Runbook

**Feature**: `identity/` stack — Phase 2
**Project**: terraform (single-project)
**Branch**: to be created from `develop`
**Status**: Planned

---

## Objective

Two independent but related improvements to the identity stack:

1. **Expanded Elevated Role**: The `engineers-elevated` role covers security group management,
   RDS operations, KMS key policy, S3 bucket policy, and OpenSearch management. As engineers
   run Terraform across more stacks, additional operations — KMS inspection, SSM parameter
   management, and IAM policies on `ecsTaskExecutionRole` — require elevated access. These
   should be added to the elevated role so engineers can apply stacks without workarounds.

2. **Engineer Setup Runbook + Simplified Elevation Workflow**: The previous role elevation
   workflow required manual `sts get-session-token` output, copying JSON, exporting three
   env vars in a separate terminal tab, and managing a `.envvar` file — error-prone and
   slow. AWS CLI named profiles with `source_profile` + `mfa_serial` handle all of this
   automatically. Engineers get an MFA prompt and cached credentials for 1h with no manual
   steps. This needs to be documented so both engineers configure their local environments
   consistently.

---

## Scope

### In Scope

- Add three new IAM statements to `aws_iam_role_policy.elevated_permissions` in
  `identity/role_elevated.tf`
- Create `docs/runbooks/AWS-ENGINEER-SETUP.md` with profile configuration and daily workflow
- Update `CHANGELOG.md` with a user-facing entry
- `terraform plan` + `terraform apply` in `identity/`

### Out of Scope

- Changes to the baseline group policies (`group_baseline.tf`, `policies_baseline.tf`)
- Any SSM resources themselves — those belong to each application stack's `ssm.tf`
- Changes to `.envrc` — Paulo already updated it; this plan only documents what was done
- Changes to provider configuration or state backend

---

## Execution Phases

### Phase 1: Expand `engineers-elevated` Role Permissions

**Objective**: Add permissions that engineers need when applying Terraform stacks involving
KMS keys, SSM parameters, and IAM policies on `ecsTaskExecutionRole`. These operations require
elevated access because they touch sensitive infrastructure — they are not specific to any
particular migration or feature.

**Components**:

- `identity/role_elevated.tf` — add three statements to `aws_iam_role_policy.elevated_permissions`:

  **Statement 1 — `KMSReadAndCrypto`** (`Resource = "*"`)
  Allows key inspection and SecureString encryption/decryption. The `*` scope is intentional:
  key ARNs are not known at policy authoring time and vary per region.
  ```
  kms:DescribeKey, kms:ListKeys, kms:ListAliases,
  kms:GenerateDataKey, kms:Decrypt, kms:CreateGrant
  ```

  **Statement 2 — `SSMManagement`** (`Resource = "*"`)
  Allows Terraform to create, update, delete, and tag SSM parameters across all stacks and
  regions. Parameter ARNs are dynamic (created during apply), so `*` is required here.
  ```
  ssm:PutParameter, ssm:DeleteParameter, ssm:GetParameter, ssm:GetParameters,
  ssm:DescribeParameters, ssm:AddTagsToResource, ssm:ListTagsForResource
  ```

  **Statement 3 — `IAMForECSTaskRole`**
  Allows Terraform to manage inline and managed policies attached to `ecsTaskExecutionRole`.
  Scoped to the specific role ARN and its managed policies to avoid broad IAM write access.
  ```
  Resource = [
    "arn:aws:iam::405749097490:role/ecsTaskExecutionRole",
    "arn:aws:iam::405749097490:policy/*"
  ]

  Actions:
  iam:CreatePolicy, iam:DeletePolicy, iam:GetPolicy, iam:GetPolicyVersion,
  iam:ListPolicyVersions, iam:AttachRolePolicy, iam:DetachRolePolicy,
  iam:CreateRolePolicy, iam:DeleteRolePolicy, iam:GetRolePolicy
  ```

**Dependencies**: None (standalone change to an existing resource)

**Success Criteria**:
- [ ] `terraform plan` shows exactly 1 resource to change: `aws_iam_role_policy.elevated_permissions`
- [ ] No unexpected changes to other resources
- [ ] `terraform apply` completes successfully
- [ ] Validation: assume elevated role and run `aws kms describe-key --key-id <any-key-arn>` —
      command must succeed (not return `AccessDenied`)
- [ ] Validation: run `aws ssm describe-parameters` with elevated profile — must return without error

---

### Phase 2: Create AWS Engineer Setup Runbook

**Objective**: Document the AWS CLI named profile setup so engineers can configure their local
environment once and use `AWS_PROFILE=4shark-elevated` when running Terraform with the elevated
role. This eliminates the previous manual `sts get-session-token` + `export` workflow.

**Components**:

- **New file**: `docs/runbooks/AWS-ENGINEER-SETUP.md`

  Sections to cover:

  1. **Prerequisites** — AWS CLI installed, IAM user credentials in `~/.aws/credentials`

  2. **Profile configuration (`~/.aws/config`)**
     Show the full block each engineer must add. Concrete values:
     ```ini
     [profile 4shark]
     region = us-east-1
     output = json

     [profile 4shark-elevated]
     source_profile = 4shark
     role_arn = arn:aws:iam::405749097490:role/engineers-elevated
     mfa_serial = arn:aws:iam::405749097490:mfa/<username>
     duration_seconds = 3600
     region = us-east-1
     ```
     The `mfa_serial` value differs per engineer:
     - Paulo: `arn:aws:iam::405749097490:mfa/1Password`
     - Emerson: `arn:aws:iam::405749097490:mfa/4shark-1Password`
     (Each engineer must use their own ARN — show how to find it: IAM Console → Users →
     Security credentials → MFA devices)

  3. **How `.envrc` integrates**
     The project sets `AWS_PROFILE=4shark` via `.envrc` (direnv), so all routine Terraform runs
     (read-only plans, baseline operations) use the `4shark` profile automatically.
     No action needed for day-to-day work.

  4. **When to use elevated profile**
     - Running `terraform apply` in any stack that manages SSM parameters
     - Running `terraform apply` in `identity/`
     - Running `terraform apply` in any stack that modifies IAM policies on `ecsTaskExecutionRole`
     - Security group changes (already covered by `security_group_management` policy on elevated role)

  5. **How to invoke elevated profile**
     Two options:
     - Per-command: `AWS_PROFILE=4shark-elevated terraform apply <planfile>`
     - Shell-scoped (for a sequence of commands):
       ```bash
       export AWS_PROFILE=4shark-elevated
       terraform apply <planfile>
       unset AWS_PROFILE   # restore to .envrc default
       ```
     AWS CLI will prompt for the MFA token code automatically on first use within the session.
     Credentials are cached in `~/.aws/cli/cache/` for the duration of `duration_seconds`.

  6. **Where to find your MFA serial ARN**
     IAM Console → Users → `<your-username>` → Security credentials tab → Multi-factor
     authentication (MFA) → copy the ARN of the registered device.

**Dependencies**: Phase 1 must be merged before the runbook is tested end-to-end, but the
runbook can be written in the same PR.

**Success Criteria**:
- [ ] Runbook exists at `docs/runbooks/AWS-ENGINEER-SETUP.md`
- [ ] Paulo follows the runbook and confirms `4shark-elevated` profile works with MFA prompt
- [ ] Emerson follows the runbook and confirms `4shark-elevated` profile works with MFA prompt
- [ ] Document references correct MFA ARNs for both engineers

---

### Phase 3: Changelog + PR

**Objective**: Update `CHANGELOG.md` and open the PR.

**Components**:

- `CHANGELOG.md` entry under `[Unreleased]`:
  - Engineers can now assume the elevated role with a single `AWS_PROFILE` flag — MFA prompt
    and credential caching handled automatically by AWS CLI, replacing the manual credential
    export workflow.
  - AWS CLI setup runbook added at `docs/runbooks/AWS-ENGINEER-SETUP.md` with step-by-step
    profile configuration and daily workflow for both engineers.
  - Elevated role now covers KMS, SSM, and ECS task role IAM operations.

**Dependencies**: Phases 1 and 2 complete.

**Success Criteria**:
- [ ] `CHANGELOG.md` updated with a user-facing entry (no technical implementation details)
- [ ] PR opened against `develop`
- [ ] PR title follows Angular convention: `feat(identity): add SSM permissions and AWS setup runbook`

---

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| IAM statement scope for KMS and SSM | `Resource = "*"` | Key and parameter ARNs are dynamic — known only after apply. Restricting by path prefix (`arn:aws:ssm:*:405749097490:parameter/*`) is an acceptable alternative but adds no meaningful security since the role already requires MFA |
| IAM statement scope for IAM actions | Scoped to `ecsTaskExecutionRole` ARN + `policy/*` | IAM write actions are high-risk; scoping to the specific role prevents privilege escalation to other roles |
| `mfa_serial` in named profile vs. manual export | Named profile with `mfa_serial` | AWS CLI handles token caching automatically; engineers only enter the 6-digit code once per session |
| Runbook location | `docs/runbooks/AWS-ENGINEER-SETUP.md` | Consistent with existing runbook structure (`BREAK-GLASS.md`, `STATE-RECOVERY.md`, etc.) |
| Both changes in one PR | Yes | Small, coherent surface area; permissions and runbook are causally related (runbook documents how to use the permissions) |

---

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| IAM statement for `iam:*` on `policy/*` is broader than intended | Medium | Resource is scoped to account `405749097490` only; cannot affect other accounts. Accept as minimum viable scope for Terraform IAM management |
| Engineer forgets to `unset AWS_PROFILE` after elevated session | Low | direnv resets `AWS_PROFILE` on directory re-entry (next terminal or `direnv reload`); no persistent state leak |
| `kms:CreateGrant` is a write action on `Resource = "*"` | Low | Grant creation requires the key to already exist and the role to have `kms:Decrypt` — no new keys can be created. The risk is acceptable given the MFA requirement on role assumption |

---

## Assumptions

- Both engineers already have TOTP MFA configured in AWS (confirmed: Paulo and Emerson, as of 2026-03-20)
- `ecsTaskExecutionRole` is the only ECS task execution role in the account (single account, `405749097490`)
- Paulo's MFA device ARN is `arn:aws:iam::405749097490:mfa/1Password` (already in use)
- Emerson's MFA device ARN is `arn:aws:iam::405749097490:mfa/4shark-1Password` (confirmed 2026-03-20)
- The `4shark` profile in `~/.aws/config` already exists for Paulo — Emerson must configure it if not done yet
- `.envrc` with `AWS_PROFILE=4shark` is already committed to the repo
