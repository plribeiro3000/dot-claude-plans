# Engineer Offboarding — AWS Access Reduction

Record of the access reduction applied to a departing engineer's AWS identity ahead of the
formal account removal. Written so the work can be understood, verified, undone, or completed
by someone who was not in the session where it was executed.

**Subject**: IAM user `emerson.silva@4shark.com.br`, AWS account `405749097490`.
**Executed**: 2026-07-31, by `paulo@4shark.com.br` via AWS CLI with the `4shark-mfa` profile.
**State**: applied and verified. Final removal pending — see `TASKS.md`.

---

## Context

The engineer has been terminated and paid for the remaining notice period, so he is not
expected to work. Formal account removal happens at the cut, roughly a week out. Until then he
remains reachable on Slack and GitHub, and the goal was to reduce what his AWS identity can do
without producing a signal he would read as distrust.

---

## What the identity actually granted

All of the engineer's power came through one path: the IAM user is placed in the `engineers`
IAM group by derivation from `identity/terraform.tfvars`, and the group carries ten managed
policies. Nothing was attached directly to the user — `aws iam list-attached-user-policies`
returned an empty list before this work started.

Four of those policies condition every statement on `aws:MultiFactorAuthPresent = true`. They
carry the whole `terraform apply` surface: `EngineerWriteAccess`, `EngineerTerraformNetwork`,
`EngineerTerraformServices`, `EngineerTerraformIdentity`.

The load-bearing finding is that **the baseline is not read-only**. The `ECSRemoteAccess`
policy is attached to the same group with no MFA condition at all, and grants:

- `ecs:ExecuteCommand` on `task/*` and `cluster/*` — a Rails console on any production task,
  meaning read, write and delete across the whole production database and all customer data
- `ecs:UpdateService` with `Resource = "*"` — scale any production service to zero
- `ecs:RunTask`, `ecs:StopTask`
- `autoscaling:SetDesiredCapacity` on the runner ASGs
- `ssm:StartSession`

Source: `identity/policies_baseline.tf:96-142` (Sids `ECSExecuteCommand`, `ECSRunStopTask`,
`ECSScalingService`), verified against the deployed policy document, not only the Terraform.

The consequence drove the whole decision: removing MFA — the intuitive move — would have left
the platform-destruction and data-exfiltration surface completely intact, while producing a
false sense of closure.

A second fact ruled MFA deactivation out as a standalone control. `IAMSelfService` v2 (the
deployed version) grants `iam:EnableMFADevice` on the engineer's own user and
`iam:CreateVirtualMFADevice` on `Resource: "*"`, both unconditionally — so he could re-enrol a
device in seconds.

Other platforms were checked and need no action: MongoDB Atlas is `GROUP_READ_ONLY`
(`mongodb_teams.tf:76-78`), Cloudflare is `Administrator Read Only`, the AWS SSO permission set
is `ReadOnlyAccess` (`sso.tf:38-42`), and GitHub is org `member`, not admin.

---

## What was applied

Three changes, in this order. The order matters: the boundary must precede the MFA
deactivation, because the boundary is what prevents re-enrolment.

### 1. Managed policy `DestructiveActionGuardrail`, attached to the user

ARN `arn:aws:iam::405749097490:policy/DestructiveActionGuardrail`, created 2026-07-31T16:02:21Z.
Two Deny statements: irreversible verbs across EC2/RDS/ECS/ELB/ElastiCache/OpenSearch/Lambda/
Logs/Route53/S3/ECR/SecretsManager/KMS/ServiceDiscovery/SNS/CodeDeploy/AutoScaling/Scheduler/
EventBridge, and all identity writes (`iam:Create*`/`Delete*`/`Attach*`/`Detach*`/`Put*`/
`Update*`/`Tag*`/`Untag*`, `sso:*`, `identitystore:Create*|Delete*|Update*`) via `NotResource`
scoped so the engineer's own user and MFA ARNs stay carved out.

`iam:PassRole` is deliberately absent from the Deny — the baseline needs it for `ecs:RunTask`.

The policy document is preserved alongside this plan as `destructive-action-guardrail.json`.

### 2. Permissions boundary `arn:aws:iam::aws:policy/ReadOnlyAccess`

This is the control that does the real work. A permissions boundary caps effective permissions
to the intersection with the identity policies, so everything that is not a read disappears at
once — including `ecs:ExecuteCommand`, `ecs:UpdateService`, `ssm:StartSession`, the entire MFA
tier, and the MFA re-enrolment path (`iam:EnableMFADevice` is not a read action).

Verified against the deployed `ReadOnlyAccess` v188: it does **not** contain
`secretsmanager:GetSecretValue`, `kms:Decrypt`, or `ecs:ExecuteCommand`, so the boundary closes
those on its own. It **does** contain `s3:Get*` and `ssm:Get*`, which is why step 3 was needed.

### 3. MFA device deactivated

Serial `arn:aws:iam::405749097490:mfa/4shark-1Password`, enrolled 2026-03-20.

Without MFA present, every MFA-conditioned Allow stops firing. That closes the two sensitive
reads the boundary alone would have left reachable: `s3:GetObject` (customer files) and
`ssm:GetParameter` (parameters that may hold secrets), both of which the engineer's identity
policies grant only under MFA.

The device is now an unassigned virtual MFA device in the account inventory. He still holds its
seed in 1Password, which is harmless while the boundary blocks re-enrolment, but it should be
deleted at the cut.

---

## Verified end state

Checked with `aws iam simulate-principal-policy` against the user, with
`aws:MultiFactorAuthPresent=false`, after all three changes.

Denied: `ecs:ExecuteCommand` (tested against the real `shared-001-cluster` ARN),
`ecs:UpdateService`, `ecs:StopTask`, `s3:GetObject`, `s3:PutObject`,
`secretsmanager:GetSecretValue`, `ssm:GetParameter`, `ssm:StartSession`,
`autoscaling:SetDesiredCapacity`, `iam:EnableMFADevice`, `iam:CreateVirtualMFADevice`.

Allowed: `ec2:DescribeInstances`, `logs:GetLogEvents`. Read only.

`aws iam get-user` confirms the boundary is attached; `aws iam list-mfa-devices` returns empty.

The engineer's `PasswordLastUsed` is 2026-03-20 — he has not signed into the console since
March and works exclusively through access key `AKIAV46EH4QJB5QNOWER`, which remains active and
is now read-only. That is why the change carries almost no chance of being noticed.

---

## How to undo

Each change reverses independently and immediately. Run with the `4shark-mfa` profile.

Remove the boundary:

    aws iam delete-user-permissions-boundary --user-name emerson.silva@4shark.com.br --profile 4shark-mfa

Detach and delete the guardrail policy:

    aws iam detach-user-policy --user-name emerson.silva@4shark.com.br --policy-arn arn:aws:iam::405749097490:policy/DestructiveActionGuardrail --profile 4shark-mfa
    aws iam delete-policy --policy-arn arn:aws:iam::405749097490:policy/DestructiveActionGuardrail --profile 4shark-mfa

MFA cannot be re-activated from the outside — the engineer re-enrols a device himself, which
requires the boundary to be removed first.

---

## Decisions

- **Permissions boundary over a broader Deny policy.** A boundary caps everything in one call
  and cannot be enumerated wrong; a Deny policy has to list every action and silently misses
  whatever it forgets. The boundary's known drawback — it is visible in `aws iam get-user`,
  which the engineer can call on himself — stopped mattering once he was no longer working.
- **The surgical guardrail was kept after the boundary made it redundant.** It costs nothing
  and remains the second layer if the boundary is ever removed without the rest being
  reconsidered.
- **Changes applied via CLI rather than the `identity/` Terraform stack.** Deliberate: a PR
  naming a departing engineer is visible to him on GitHub while he is still an org member.
  Drift is accepted and self-resolves at the cut, when he is removed from `terraform.tfvars`
  and the user — with its boundary and attachment — ceases to exist.
- **`ecs:ExecuteCommand` was left open in the first, surgical iteration and closed only by the
  boundary.** While he was still expected to work, closing it would have broken his daily tool
  and been unmistakable. Once he was confirmed not working, that constraint disappeared.

---

## Open item

Both `iam:PutUserPermissionsBoundary` and `iam:DeactivateMFADevice` against **another** user
succeeded from `paulo@4shark.com.br`, yet neither action was found in the deployed documents of
any policy attached to the `engineers` group — `EngineerTerraformIdentity` v2, `IAMSelfService`
v2 (which scopes `DeactivateMFADevice` to `user/${aws:username}` only), no inline group
policies, and no wildcard `Action` anywhere.

An engineer being able to set a permissions boundary on a peer, or deactivate a peer's MFA, is
broader than the least-privilege model `docs/adr/ADR-004-identity-model.md` describes. Whether
that grant is intentional or drift is unresolved and should be traced against the deployed
policy versions, which are known to have drifted from the Terraform source (several are at v2
or v3).

Note also that `simulate-principal-policy` does not resolve `${aws:username}` reliably — it
reported `allowed` for `iam:PutUserPermissionsBoundary`, an action with no Allow anywhere. Treat
its `explicitDeny` results as trustworthy and its `allowed` results on variable-scoped policies
as unverified.
