# PLAN — AWS Identity/Profile Model Standardization

## Objective

Standardize the AWS identity/profile/variable layer so the names describe the **AWS role** each profile plays and the model carries no dead pieces. The change spans the **dot-claude repo**, the **terraform repo**, and each engineer's **local `~/.aws/credentials` / `~/.aws/config` / `settings.local.json`**. Grounded in the redesign spike (`~/Projects/4Shark/dot-claude-plans/active/spike/identity-credential-model-redesign/SPIKE.md`).

The IAM user **account** `ivo@4shark.com.br` is not renamed — renaming the username replaces the account. Only the role/profile/variable layer around it changes.

## Final model (decided)

### AWS profiles (local `~/.aws/credentials` / `~/.aws/config`)

| Current | New | Note |
|---|---|---|
| `default` / `4shark` (baseline read-only) | `engineer` | |
| `4shark-mfa` (Claude Code, GetSessionToken) **+** `4shark-elevated` (CLI role-chaining) | `engineer-elevated` | **Consolidated into one profile.** The surviving mechanism is GetSessionToken (the live one the tooling uses); the `4shark-elevated` role-chaining path in `~/.aws/config` is dropped as superseded — the engineer's terminal uses the same `engineer-elevated` GetSessionToken profile. |
| `ivo` (long-term key, near-zero permission) | `policy-arbiter` | |
| `ivo-elevated` (15-min MFA session, runs identity/audit stacks) | `policy-arbiter-elevated` | The profile name carries the AWS role; the underlying identity stays "break-glass" everywhere else (below). |
| `root` | `root` | Unchanged — AWS-fixed. |

GetSessionToken stays the mechanism for both identities — it is the AWS-documented-correct API for same-account, `aws:MultiFactorAuthPresent`-gated identity policies, and it *requires* a long-term-key profile to mint the session, so the two-profiles-per-identity split is forced, not a naming smell.

### Env-vars

| Current | New | Note |
|---|---|---|
| `AWS_BREAK_GLASS_MFA_SERIAL` (per-engineer `settings.local.json`) | **DROP** | One shared break-glass identity → the MFA serial is identical for everyone and is not secret. Hardcode the ARN as a script constant, mirroring `OP_SECRET_REFERENCE` already in the same script. |
| `AWS_MFA_SERIAL`, `AWS_MFA_ITEM` (per-engineer) | KEEP | Genuinely per-engineer; names already conform. |

### What stays "break-glass" (the identity/concept — NOT renamed to policy-arbiter)

The AWS *profile* is renamed to `policy-arbiter*` because that is the AWS role; the *identity* is break-glass everywhere else, because `ivo` genuinely is 4Shark's cross-service break-glass owner (Redis Cloud, MongoDB Atlas, GCP) and "break-glass" is the established codebase term. These STAY:

- terraform `identity/break_glass.tf`, `policy_break_glass.tf`, `policy_break_glass_portal.tf`, `sso.tf` — resource labels (`break_glass`, `break_glass_identity`, `break_glass_audit`, `break_glass_terraform_state`), IAM policy `name`/`description` strings, prose.
- `identity/guard.tf`, `audit/guard.tf`, `identity/README.md`, `audit/README.md`, ADR-004, ADR-013 — prose.
- `~/.claude/docs/runbooks/engineer-access/BREAK-GLASS.md` — filename + content.
- The account itself: `ivo@4shark.com.br` (username in `break_glass.tf:22`, admin email in `terraform.tfvars`/`variables.tf`, the GCP `member = "user:ivo@..."` grants in `analytics-access`/`workspace-access`).

## Surfaces to change

### terraform repo (only the profile pins — everything `break_glass`/`ivo@` stays)

- `identity/.envrc:8`, `audit/.envrc:7` — `export AWS_PROFILE=ivo-elevated` → `policy-arbiter-elevated` (+ the prose comments in both files that name the profile).

The `.envrc` change is a profile REFERENCE, not the break-glass concept. No resource labels, no policy names, no `moved {}` blocks, no apply on the identity stack — the profile pin is read at `direnv` time, not stored in state. This makes the terraform half a docs+`.envrc` PR with no infrastructure apply. (Confirm no other `.tf`/`.tfvars` carries `ivo-elevated`/`4shark-mfa` before the PR — inventory showed only the two `.envrc`.)

### dot-claude repo

- **Scripts (functional — write/read the profile names):** `skills/elevate-aws-access/scripts/elevate-aws-access.sh` (writes `4shark-mfa` → `engineer-elevated`), `skills/elevate-break-glass-access/scripts/elevate-break-glass-access.sh` (`AWS_SOURCE_PROFILE="ivo"` → `policy-arbiter`, `AWS_PROFILE_NAME="ivo-elevated"` → `policy-arbiter-elevated`, **drop the `AWS_BREAK_GLASS_MFA_SERIAL` read + hardcode the ARN constant**), `scripts/terraform.sh` (`AWS_PROFILE=4shark-mfa` → `engineer-elevated`), `scripts/start-instance.sh`, `scripts/stop-instance.sh`, `scripts/inject-terraform-context.sh`, `scripts/validate-bash-command.sh`, `skills/integration-debug/scripts/*.sh`, `skills/mongodb-reprovision/scripts/mongodb-reprovision.sh`.
- **Docs (rewrite, not find-replace):** `docs/AWS-MFA.md` (drop the dead `4shark-elevated` comparison table; document the single consolidated `engineer-elevated`), `docs/runbooks/engineer-access/AWS-ENGINEER-SETUP.md` (already stale — references a non-existent script path; rewrite regardless), `docs/IDENTITY-STACK.md`, `CLAUDE.md` §§ AWS Policy / Terraform Command Execution / Identity Stack, `docs/TERRAFORM-CONVENTIONS.md`, `docs/TERRAFORM-POLICY.md`, `docs/WORKTREE-POLICY.md`, `docs/runbooks/INDEX.md`, the `SKILL.md` prose in `ec2-instances`/`integrators`/`runbook`/`terraform-policies`, `CHANGELOG.md`.
- **The elevate-break-glass-access skill name stays** — it elevates the break-glass identity (which stays break-glass); only the profile it writes changes to `policy-arbiter-elevated`.

### local (engineer, per-machine — not in any PR)

- `~/.aws/credentials` / `~/.aws/config`: rename profile headers; remove the `4shark-elevated` role-chaining entry.
- `~/.claude/settings.local.json`: remove the `AWS_BREAK_GLASS_MFA_SERIAL` entry (now a script constant); keep `AWS_MFA_SERIAL` / `AWS_MFA_ITEM`.

## Execution order (zero-downtime)

Invariant: the tooling never references a profile that does not yet exist locally. Profiles are minted fresh on each elevation, so cutover is a re-elevation.

**Phase 1 — dot-claude PR.** All script + doc + `settings.json` changes. On merge, the scripts write/read the new names.

**Phase 2 — terraform PR.** The two `.envrc` pins + their prose. Plan-only in the PR; no identity-stack apply (the pin is a direnv-time reference, not state). Lands together with the local `~/.aws/credentials` rename so terraform never reads a missing profile.

**Phase 3 — local cutover (engineer).** Re-run the renamed elevate skills → new profile sections appear; remove the `4shark-elevated` entry and the `AWS_BREAK_GLASS_MFA_SERIAL` env-var; delete the old sections.

## Deferred (not this change)

Migrating engineer CLI access from IAM-user + GetSessionToken to IAM Identity Center (SSO) federation — AWS's own recommended posture (SEC02-BP02 lists the IAM-user long-term-key shape as an anti-pattern), but no verified headless/Touch-ID-equivalent flow exists, so it is a separate architecture decision, not folded in here.
