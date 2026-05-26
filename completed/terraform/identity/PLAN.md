# PLAN — Identity Stack: Centralized Engineer Access Management

**Feature:** `identity/` stack in the Terraform project
**Branch:** `develop` (already merged in stages via PRs)
**Status:** In progress — main implementation complete, manual items pending

**Research:** See `SPIKE.md` in this same directory

---

## Managed Engineers

| Handle | Name | Platforms |
|--------|------|-----------|
| `paulo` | Paulo Ribeiro | AWS, MongoDB Atlas, Cloudflare, GitHub |
| `emerson` | Emerson Silva | AWS, MongoDB Atlas, Cloudflare, GitHub |

**Admin (break glass):** Ivo Alves (`ivo@4shark.com.br`)

---

## Objective

Terraform `identity/` stack that manages engineer access across all infrastructure providers from a single source of truth (`engineers` in `terraform.tfvars`). Adding or removing an engineer propagates automatically across all systems.

**Access model:**
- Baseline: read-only on all providers, routine operations via Terraform
- Elevated: `engineers-elevated` role on AWS (requires MFA, 1h session)
- Break glass: separate admin account (`ivo@4shark.com.br`) with full access

---

## What Was Implemented

### AWS
- [x] IAM users per engineer (`engineers.tf`)
- [x] `engineers` group with baseline policies (`group_baseline.tf`, `policies_baseline.tf`)
- [x] `engineers-elevated` role with YubiKey MFA condition (`role_elevated.tf`)
- [x] AWS SSO (Identity Center): users, groups, permission sets, account assignments (`sso.tf`)
- [x] Import of existing IAM users
- [x] Root account MFA replaced with 3 YubiKeys (FIDO2) — TOTP removed, hardware key only

### MongoDB Atlas
- [x] Org assignments per engineer (`mongodb_org.tf`)
- [x] `engineers-baseline` and `engineers-elevated` teams (`mongodb_teams.tf`)
- [x] Google Workspace as federated identity provider (`mongodb_federation.tf`)
- [x] Import of existing users

### Cloudflare
- [x] Account members per engineer (`cloudflare_account_member.tf`)
- [x] Google Workspace as SSO identity provider (SAML) (`cloudflare_sso.tf`)
- [x] Import of existing members

### GitHub
- [x] Org membership per engineer (`github.tf`)
- [x] Teams and memberships (app-back-end, app-front-end, app-sdk, ia, infrastructure, integrator)
- [x] Repositories assigned per team

---

## Pending Items

### Manual configuration (engineers)
- [x] Paulo configured TOTP MFA in AWS Console
- [x] Emerson configured TOTP MFA in AWS Console (1Password, device: `4shark-1Password`, 2026-03-20)
- [x] After Emerson's MFA confirmed: re-enable `aws_iam_group_policy_attachment.mfa_enforcement` in `group_baseline.tf` — done in PR #261 (2026-03-20)

### Cloudflare SSO (manual — not manageable via Terraform)
- [x] Create backup API token with `SSO Connector Edit` permission (token name: "Break Glass — SSO Connector", store in 1Password)
- [x] Enable SSO connector in Cloudflare Dashboard (Manage Account → Members → Settings → `@4shark.com.br`)

### Rollbar — User Management (DECISION REVERSED 2026-03-13)
**Previous decision:** managed in each project's own stack — CANCELLED. Frontends have no backend stack to live in.
**New decision:** Rollbar user management belongs in `identity`, Rollbar project configs belong in `monitoring/`.

**Teams to create:**
- `Backend` → Paulo, Emerson
- `Frontend` → Leandro

**Engineer mapping:**
- `paulo`   → `rollbar_teams = ["backend", "frontend"]`
- `emerson` → `rollbar_teams = ["backend", "frontend"]`
- `leandro` → `rollbar_teams = ["frontend"]`
- `elizier` → no Rollbar access (mobile only, no mobile monitoring yet)

**Break glass:** Ivo as Owner in Rollbar (same pattern as AWS, MongoDB, Cloudflare). Token generated from Ivo's account.

**Implementation checklist:**
- [x] **Manual prerequisite:** Invite Ivo to Rollbar as Owner, Ivo accepts invite and generates `account_access_token`
- [x] Add `rollbar_teams = optional(set(string))` to `variables.tf` engineer type
- [x] Add `rollbar_teams` values to `terraform.tfvars`
- [x] Add `rollbar/rollbar` provider to `providers.tf`
- [x] Create `identity/rollbar.tf` with `rollbar_team` (Backend, Frontend) + `rollbar_user` resources
- [x] Import existing Rollbar users (Paulo, Emerson, Leandro)

**Status: DONE — merged in PR #238 (2026-03-13)**

**Pending (future PR — cross-stack references):**
- [x] Add `team_ids` to each `rollbar_project` in `monitoring/` stack — done with hardcoded IDs in `monitoring/rollbar.tf` (backend: 1208696, frontend: 1208697)

### Google Workspace (manual — no official provider)
- [x] Register 3 YubiKeys on Ivo's Google account (`myaccount.google.com` → Security → Passkeys & security keys)
- [x] 2SV enabled on Ivo's account — hardware security key only
- [x] Authenticator and phone removed from Ivo's account
- [x] Backup codes generated and saved in 1Password
- [x] Create `/break-glass` OU in Google Workspace Admin Console
- [x] Move Ivo to `/break-glass` OU
- [x] Configure enforcement on `/break-glass` OU: 2SV required, security key only, no trusted devices, no backup codes
- [x] Restrict passkeys on `/break-glass` OU to hardware FIDO2 only
- [x] Ivo has full Admin Console access as Super Admin (via YubiKey)
- [x] Transfer Google Workspace ownership to Ivo (remove Super Admin from Paulo, Ivo set as primary administrator)
- [x] Create `/staff` OU and move human users
- [x] Create `/service-accounts` OU and move non-human accounts
- [x] Configure enforcement on `/staff` OU: 2SV required, any method
- [x] Create `/partners` OU (unplanned) for Danilo and Sérgio (partners who do not use MFA/password rotation — separate enforcement policy)

### Not manageable via Terraform (document in runbook)
- Redis Cloud: access via console UI

---

## Phase 2 — Permissions for SSM Migration (pending)

Required to support the GitHub Environments → Terraform SSM migration.
See spike: `~/.claude/plans/active/spike/github-envs-to-terraform-ssm/SPIKE.md`

### Problem

The `MFAEnforcement` policy blocks all actions without an MFA session. Even with MFA active,
`kms:DescribeKey` is not in any policy (baseline or elevated), blocking KMS inspection.
Additionally, the elevated role lacks SSM and IAM permissions needed for Terraform to apply
stacks that manage these resources.

### Changes needed in `identity/role_elevated.tf`

Add to `aws_iam_role_policy.elevated_permissions`:

**KMS read (needed for key validation and SecureString operations):**
- `kms:DescribeKey`
- `kms:ListKeys`
- `kms:ListAliases`
- `kms:GenerateDataKey`
- `kms:Decrypt`
- `kms:CreateGrant`

**SSM management (needed for Terraform to create/update SSM parameters):**
- `ssm:PutParameter`
- `ssm:DeleteParameter`
- `ssm:GetParameter`
- `ssm:GetParameters`
- `ssm:DescribeParameters`
- `ssm:AddTagsToResource`
- `ssm:ListTagsForResource`

**IAM management scoped to ecsTaskExecutionRole (needed for ssm.tf IAM policies):**
- `iam:CreatePolicy`
- `iam:DeletePolicy`
- `iam:GetPolicy`
- `iam:GetPolicyVersion`
- `iam:ListPolicyVersions`
- `iam:AttachRolePolicy`
- `iam:DetachRolePolicy`
- `iam:CreateRolePolicy`
- `iam:DeleteRolePolicy`
- `iam:GetRolePolicy`

### Role assumption workflow (how to get an elevated session)

```bash
# Step 1 — get session token with MFA (replaces current shell credentials)
aws sts get-session-token \
  --serial-number arn:aws:iam::405749097490:mfa/<username> \
  --token-code <6-digit-code> \
  --duration-seconds 3600

# Step 2 — export temporary credentials from step 1
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...

# Step 3 — assume elevated role
aws sts assume-role \
  --role-arn arn:aws:iam::405749097490:role/engineers-elevated \
  --role-session-name paulo-elevated

# Step 4 — export elevated credentials
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...
```

### Implementation checklist

See full plan at `~/.claude/plans/active/terraform/identity-phase2/PLAN.md`.

---

## Providers Outside Terraform Scope

| Provider | Reason | Action |
|----------|--------|--------|
| Google Workspace | No official provider — researched and discarded | Manual Admin Console |
| Redis Cloud | No resource for team members | Console UI — document runbook |

## Providers Not Manageable via Terraform

| Provider | Reason | Action |
|----------|--------|--------|
| Redis Cloud | Provider does not support console members, only DB ACL users | Console UI — document in runbook |
| 1Password | Official provider manages vault items only, not account members | Console UI |
| Slack | Community provider requires Enterprise Grid for user invite | Console UI |

## Providers Managed via Terraform in Other Stacks

| Provider | Stack | Notes |
|----------|-------|-------|
| Rollbar projects | `monitoring/` (new stack) | Centralized project configs for all apps and frontends |
| Netlify | CANCELLED — provider pre-1.0, no site creation, `app-shared-001` at 201 resources | See `~/.claude/plans/active/terraform/netlify/PLAN.md` |
