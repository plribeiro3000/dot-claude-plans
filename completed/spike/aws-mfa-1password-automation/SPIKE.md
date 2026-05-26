# SPIKE — AWS MFA elevation automation with 1Password CLI in Claude Code

**Conducted by:** Claude Code (research)
**Date:** 2026-03-22
**Status:** Research complete — pending decisions

---

## Goal

Investigate how to automate the AWS STS session-token elevation flow (MFA via 1Password) so that
`aws` and `terraform` commands executed by Claude Code (via Bash tool) use the resulting temporary
credentials without manual copy-paste of the TOTP code each time.

Questions to answer:

1. How to obtain a TOTP from 1Password CLI (`op`) and what is the exact command?
2. Does `op` prompt for biometric authentication automatically, or does it need to be unlocked first?
3. What are the duration limits for `aws sts get-session-token`?
4. Best practices for storing temporary credentials locally.
5. Do tools like `aws-vault` or the 1Password AWS shell plugin solve this out of the box?
6. How can Claude Code Bash tool calls share environment variables set in a previous call?
7. How can a skill/command wire all of this together?

---

## Method

- Researched 1Password CLI official documentation (`developer.1password.com`)
- Researched AWS STS API reference (`docs.aws.amazon.com`)
- Researched Claude Code skills/hooks documentation (`code.claude.com`)
- Researched `aws-vault` GitHub repository
- Researched 1Password AWS shell plugin documentation

---

## Evidence

### 1. 1Password CLI — obtaining a TOTP

**Source:** `developer.1password.com/docs/cli/secret-reference-syntax/`

The `op read` command accepts a *secret reference* with a query parameter:

```bash
# General form
op read "op://Vault/ItemName/section/field?attribute=otp"

# Without section (if OTP field is at the top level)
op read "op://Vault/ItemName/field?attribute=otp"

# Short form alias
op read "op://Vault/ItemName/field?attr=otp"
```

The `attribute=otp` (or `attr=otp`) parameter tells the CLI to generate the current TOTP code from
the stored secret key rather than returning the raw secret.

`op item get` can also retrieve the field, but `op read` is simpler for scripting:

```bash
# Alternative: item get with --fields flag
op item get "AWS" --fields label="one-time password" --otp
```

The exact vault/item/field names depend on how the 1Password item was created. The recommended field
title for MFA is `one-time password` (standard 1Password field type).

**Source:** `developer.1password.com/docs/cli/shell-plugins/aws/#mfa`

The 1Password AWS shell plugin looks for two fields in the AWS item:
- Field titled `one-time password` — stores the TOTP secret key
- Field titled `mfa serial` — stores the MFA device ARN

### 2. 1Password CLI — biometric authentication

**Source:** `developer.1password.com/docs/cli/get-started/`

When the 1Password desktop app integration is enabled (`Settings > Developer > Integrate with
1Password CLI`), any `op` command **automatically prompts for biometric authentication** (Touch ID
on Mac, Windows Hello, etc.). The user does not need to run `op signin` first.

The flow is:
1. User runs an `op` command (e.g., `op read "op://..."`)
2. macOS Touch ID prompt appears automatically
3. After approval, the command returns the result

This means the script will block waiting for biometric input — it cannot run fully unattended, which
is the expected security behavior. The biometric prompt appears on screen even when `op` is called
from inside a Claude Code Bash tool call.

### 3. AWS STS `get-session-token` — duration limits

**Source:** `docs.aws.amazon.com/STS/latest/APIReference/API_GetSessionToken.html`

| Subject | Default | Minimum | Maximum |
|---------|---------|---------|---------|
| IAM user (standard) | 43,200 s (12 h) | 900 s (15 min) | 129,600 s (36 h) |
| AWS account root | 3,600 s (1 h) | 900 s (15 min) | 3,600 s (1 h) |

The response JSON contains:
```json
{
  "Credentials": {
    "AccessKeyId": "ASIA...",
    "SecretAccessKey": "...",
    "SessionToken": "...",
    "Expiration": "2026-03-22T23:00:00Z"
  }
}
```

With the max 36-hour duration (`--duration-seconds 129600`), re-authentication is needed roughly
once a day (or less) for a working session.

### 4. Storing temporary credentials — options

#### Option A: `/tmp` file sourced before each command

Write `export AWS_*=...` lines to a file (e.g., `/tmp/aws_session.env`) and source it before each
`aws`/`terraform` invocation:

```bash
source /tmp/aws_session.env && terraform plan ...
```

Simple, no extra tooling. The file expires with the OS session. Risk: credentials visible in `/tmp`
to the local user (acceptable on a personal workstation).

#### Option B: `~/.aws/credentials` named profile

Write the temporary credentials to a named profile in `~/.aws/credentials`:

```ini
[mfa]
aws_access_key_id = ASIA...
aws_secret_access_key = ...
aws_session_token = ...
```

Then use `AWS_PROFILE=mfa` or `--profile mfa`. Native AWS tooling, but credentials persist on disk
until overwritten.

#### Option C: `credential_process` in `~/.aws/config`

**Source:** `docs.aws.amazon.com/cli/latest/userguide/cli-configure-sourcing-external.html`

Configure a profile that calls an external script to produce credentials on demand:

```ini
[profile mfa]
credential_process = /path/to/get-aws-creds.sh
```

The script must output JSON:
```json
{
  "Version": 1,
  "AccessKeyId": "ASIA...",
  "SecretAccessKey": "...",
  "SessionToken": "...",
  "Expiration": "2026-03-22T23:00:00Z"
}
```

If `Expiration` is present, the AWS CLI treats the credentials as temporary and refreshes them
automatically when expired. **This is the most robust approach** — no manual re-run needed once the
profile is set up. The script runs every time credentials are needed (or when they expire).

**Caveat**: The AWS CLI does NOT cache `credential_process` output internally. The script must
implement its own caching (e.g., write to a temp file and check expiry) to avoid calling 1Password
on every `aws` command.

#### Option D: `CLAUDE_ENV_FILE` hook (Claude Code native)

**Source:** `code.claude.com/docs/en/hooks`

Claude Code's `SessionStart` hook can write to `$CLAUDE_ENV_FILE`. Variables written there persist
across **all** subsequent Bash tool calls in the session:

```bash
#!/bin/bash
# ~/.claude/hooks/aws-mfa-session.sh
if [ -n "$CLAUDE_ENV_FILE" ]; then
  # Read TOTP from 1Password (will prompt Touch ID once)
  TOTP=$(op read "op://Private/AWS 405749097490/one-time password?attribute=otp")
  CREDS=$(aws sts get-session-token \
    --serial-number arn:aws:iam::405749097490:mfa/1Password \
    --token-code "$TOTP" \
    --duration-seconds 129600 \
    --output json)
  echo "export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r '.Credentials.AccessKeyId')" >> "$CLAUDE_ENV_FILE"
  echo "export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r '.Credentials.SecretAccessKey')" >> "$CLAUDE_ENV_FILE"
  echo "export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r '.Credentials.SessionToken')" >> "$CLAUDE_ENV_FILE"
fi
```

This approach requires Touch ID once per Claude Code session startup, then all `aws` and `terraform`
calls use the injected env vars automatically — no `source` needed, no file path to remember.

**Problem**: `SessionStart` runs at every session open, even for unrelated sessions. If the token
already has 30+ hours left, re-authenticating is unnecessary friction.

### 5. `aws-vault` — capabilities and MFA handling

**Source:** `github.com/99designs/aws-vault`

`aws-vault` stores base credentials in the OS keychain and calls STS to generate temporary
credentials on demand. When MFA is configured in `~/.aws/config`, it prompts for the TOTP at
execution time.

```bash
aws-vault exec my-profile -- terraform plan
```

- Credentials are never written to disk (passed as env vars to the subprocess)
- Session caching: avoids re-prompting MFA until the token expires
- Does NOT integrate with 1Password TOTP by default — it prompts a text input for the code
- Can be combined with `op read` via `--mfa-token` flag or a custom MFA prompt:
  `aws-vault exec --mfa-token $(op read "op://...?attr=otp") my-profile -- terraform plan`

**Verdict**: `aws-vault` is excellent for interactive use but adds friction for Claude Code
automation because each `exec` spawns a subprocess (not compatible with persisting env vars between
Bash tool calls).

### 6. 1Password AWS shell plugin

**Source:** `developer.1password.com/docs/cli/shell-plugins/aws/`

When installed (`op plugin init aws`), the plugin wraps the `aws` CLI: each invocation retrieves
credentials from 1Password and injects `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and
`AWS_SESSION_TOKEN` as env vars. MFA is handled if `one-time password` and `mfa serial` fields
exist in the 1Password item.

**Limitation for Terraform**: The plugin wraps the `aws` CLI binary, but Terraform uses the AWS SDK
directly — it does not call `aws`. The plugin does not intercept Terraform.

**Verdict**: Works for `aws` CLI commands but not for Terraform. Partial solution.

### 7. Environment variable persistence in Claude Code Bash tool calls

**Source:** `code.claude.com/docs/en/hooks`

Each Bash tool call runs in a fresh subprocess shell. `export` in one call does NOT carry to the
next. Two confirmed mechanisms exist for persistence:

| Mechanism | How | Scope |
|-----------|-----|-------|
| `CLAUDE_ENV_FILE` | `SessionStart` hook writes `export VAR=value` lines to the file | All Bash calls in the session |
| Skill with `!` bash injection | `!`command`` in SKILL.md pre-populates context with output, but not env vars | Context only, not env |
| File on disk + `source` | Write to `/tmp/aws_session.env`, prepend `source /tmp/aws_session.env &&` to each command | Requires explicit sourcing |

The `CLAUDE_ENV_FILE` mechanism is the cleanest for this use case.

### 8. Claude Code skills — what they can and cannot do

**Source:** `code.claude.com/docs/en/slash-commands`

A skill (`~/.claude/skills/<name>/SKILL.md` or `~/.claude/commands/<name>.md`) is a markdown file
with instructions Claude follows. Key properties:

- Skills **can** instruct Claude to run Bash commands via the Bash tool
- Skills **can** use `!`command`` syntax for **preprocessing** (runs before Claude sees anything)
- Skills **cannot** directly set env vars that persist — they run inside the same session shell
  context rules as any other Bash call
- Skills **can** write to `/tmp/` and instruct subsequent commands to source that file
- `disable-model-invocation: true` prevents Claude from triggering the skill automatically
- `allowed-tools` lets the skill use certain tools without per-use approval

A `/aws-mfa` skill could:
1. Call `op read` to get the TOTP (biometric prompt fires)
2. Call `aws sts get-session-token` with the TOTP
3. Write the resulting credentials to `/tmp/aws_session.env`
4. Inform Claude that all subsequent `aws`/`terraform` commands must be prefixed with
   `source /tmp/aws_session.env &&`

This works but requires Claude (and the engineer) to remember to source the file every time.

---

## Conclusions

### Finding 1 — `op read` is the correct command for TOTP

```bash
op read "op://Vault/ItemName/one-time password?attribute=otp"
```

The field name must match exactly what exists in the 1Password item. If the item uses the standard
1Password OTP field type, the field label is `one-time password`. The `attribute=otp` parameter
generates the current 6-digit code from the stored secret.

### Finding 2 — Biometric prompt is automatic and unavoidable

No pre-unlock step is needed. The `op` CLI will trigger Touch ID automatically when called from any
terminal or subprocess, including Claude Code's Bash tool. This is a deliberate security boundary:
the user must approve each session's credential access.

### Finding 3 — 36-hour token duration minimizes re-authentication friction

With `--duration-seconds 129600`, a single MFA approval covers a full working day (and overnight).

### Finding 4 — `CLAUDE_ENV_FILE` is the best integration point for Claude Code

The `SessionStart` hook writing to `$CLAUDE_ENV_FILE` is the only mechanism that makes env vars
available to ALL subsequent Bash tool calls without requiring `source` prefixes. This is the correct
hook to use for injecting temporary AWS credentials at session start.

The downside is that this runs on every session open. A caching check (read expiry from a state
file) can avoid unnecessary MFA prompts.

### Finding 5 — `credential_process` is the best standalone solution

For use outside Claude Code (or as a complement), configuring `credential_process` in
`~/.aws/config` makes the automation transparent to all AWS tooling including Terraform. The script
must implement caching to avoid calling 1Password on every SDK call.

### Finding 6 — `aws-vault` and the 1Password AWS shell plugin are partial solutions

- `aws-vault`: great UX for interactive terminal use, but does not integrate with 1Password TOTP
  natively and its subprocess model does not persist env vars between Claude Code Bash calls.
- 1Password AWS shell plugin: works for `aws` CLI only, not for Terraform SDK calls.
- Neither is a complete solution for the Claude Code + Terraform use case.

### Recommended approach

**Hybrid: `SessionStart` hook + `/tmp` cache + `/aws-mfa` skill**

1. `SessionStart` hook checks if `/tmp/aws_session.env` exists and credentials are still valid
   (parse the `Expiration` field). If valid, sources the file into `CLAUDE_ENV_FILE`. If expired or
   missing, runs the full `op read` + `aws sts get-session-token` flow, writes the new credentials
   to `/tmp/aws_session.env`, and also exports to `CLAUDE_ENV_FILE`.
2. `/aws-mfa` skill provides a manual trigger: forces credential refresh on demand, regardless of
   the cache state. Useful when starting a new session without restarting Claude Code.
3. `credential_process` in `~/.aws/config` (optional) ensures `aws`/`terraform` also work outside
   Claude Code sessions with the same credentials.

---

## Next Steps

- **Decision needed**: Which approach to implement — `SessionStart` hook only, `/aws-mfa` skill
  only, or the hybrid? The hybrid is recommended but adds setup complexity.
- **Action required**: Identify the exact 1Password vault name and item name for the AWS MFA item,
  so the `op read` reference can be finalized.
- **Implementation**: If the hybrid approach is approved, use `@agent-planner` to create a PLAN.md
  for the implementation of the hook script, the cache logic, and the skill file.
- **Scope**: This investigation covers only the current AWS account (405749097490) and MFA device
  `arn:aws:iam::405749097490:mfa/1Password`. If other accounts/roles need to be added, the script
  design should accommodate multiple profiles.

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
