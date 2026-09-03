# Tasks — Engineer Offboarding

Companion to `PLAN.md`. Subject: `emerson.silva@4shark.com.br` / GitHub `eoliveiramg`, AWS
account `405749097490`. Run AWS commands with `--profile 4shark-mfa`.

## Done

- [x] Interim containment: `DestructiveActionGuardrail` attached, `ReadOnlyAccess` permissions
      boundary set, MFA device deactivated
- [x] PR [#893](https://github.com/4shark/terraform/pull/893) opened, applied and merged —
      including the `github.tf` team-membership fix without which the apply fails
- [x] Blockers to `DeleteUser` cleared: policy detached, access key deleted, boundary removed
- [x] Second apply completed — IAM user destroyed, `get-user` returns `NoSuchEntity`
- [x] `/merge-cleanup` — worktree removed, branch `feature/identity-offboard-engineer` deleted
- [x] Manual revocations: Pritunl VPN, Redis Cloud, Datadog, Netlify, 1Password, Slack, Clockify,
      Figma
- [x] `app` user account deactivated in all four environments
- [x] Claude Code — personal account, cancelled by the engineer himself

## Pending — access

- [ ] **Google Workspace** — the last identity system. While the account exists he keeps the
      corporate mailbox and the federated identity, even with no authorization anywhere.

- [ ] Confirm whether he held a person account in **`integrator`** (Rails with its own internal
      web) and in **`setup`**. Neither was checked. Keycloak and `onboarding` are already ruled
      out — see `PLAN.md` § Per-system record.

## Pending — AWS residue

Both are orphaned objects, confirmed unused (`AttachmentCount: 0`,
`PermissionsBoundaryUsageCount: 0`).

- [ ] Delete the guardrail policy

      aws iam delete-policy --policy-arn arn:aws:iam::405749097490:policy/DestructiveActionGuardrail --profile 4shark-mfa

- [ ] Delete the orphaned virtual MFA device

      aws iam delete-virtual-mfa-device --serial-number arn:aws:iam::405749097490:mfa/4shark-1Password --profile 4shark-mfa

## Pending — decision

- [ ] **Credential rotation.** Revoking access does not undo what was already read or copied.
      Decide whether to rotate what he could reach in 1Password — the shared `Terraform ENV`
      item holding the org-wide third-party credentials, database passwords, VPN and MongoDB
      keys — and in what order of risk. `THIRD-PARTY-KEY-STANDARD.md` carries the rotation path:
      Terraform-managed keys via `apply -replace`, the bootstrap credential by hand.

## Pending — the deliverable this case exists to produce

- [ ] Write the offboarding runbook at `~/.claude/docs/runbooks/engineer-access/OFFBOARDING.md`
      with an entry in `runbooks/INDEX.md`. None exists: the only written guidance is one line in
      ADR-004 covering the six systems the identity stack manages and silent on everything else.
      Organize it **by category, not by system list** — see `PLAN.md` § What this case taught.
      This is a PR to `dot-claude`.

- [ ] Remove the departed engineer's MFA serial from the table in
      `~/.claude/docs/runbooks/engineer-access/AWS-ENGINEER-SETUP.md`. Same repository, can ride
      along with the runbook PR.

## Pending — unrelated to the offboarding

- [ ] On 2026-09-04, confirm the GitHub seat count actually dropped to 5. A scheduled task
      (`github-seat-downgrade-check`) and a calendar event both fire that day. If it is still 9,
      open a support ticket — see `PLAN.md` § Open.
