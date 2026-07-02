# Auxiliary — Local 4Shark tooling excerpts consulted

Curated excerpts from `~/.claude/` read during this spike, preserved so the SPIKE.md claims about
existing 4Shark machinery can be re-verified without re-reading the full files. Read-only reads;
nothing was modified.

---

## 1. `~/.claude/settings.json` — hooks and permissions shape

Full file read on 2026-07-01. Key structural facts used in SPIKE.md:

- `PreToolUse` hooks matched on `Bash` include, among others:
  `auto-approve-aws-readonly.sh`, `inject-working-dir-reminder.sh`,
  `inject-output-preservation-reminder.sh`, `inject-pr-commit-data-policy.sh`,
  `inject-commit-policy-reminder.sh`, and the universal
  `validate-bash-command.sh` matched on `Bash|Edit|Write|MultiEdit`.
- `PreToolUse` hooks matched on `Skill`:
  ```json
  {
    "matcher": "Skill",
    "hooks": [
      { "command": "$HOME/.claude/scripts/auto-approve-local-skills.sh" },
      { "command": "$HOME/.claude/scripts/inject-integration-debug-docs.sh" }
    ]
  }
  ```
- `permissions.allow` contains explicit per-script allow-list entries for every skill's wrapper
  script, e.g.:
  ```
  "Bash(bash $HOME/.claude/skills/integrators/scripts/integrator-services.sh:*)"
  "Bash(bash $HOME/.claude/scripts/ecs-scale.sh:*)"
  "Bash(bash $HOME/.claude/skills/elevate-aws-access/scripts/elevate-aws-access.sh:*)"
  ```
  and broad read-only AWS allow entries:
  ```
  "Bash(aws * describe-*:*)"
  "Bash(aws * get-*:*)"
  "Bash(aws * list-*:*)"
  "Bash(aws logs tail:*)"
  ```
- `permissions.ask` contains `terraform apply`/`destroy`, `docker push`, `ssh`, `curl`, `sudo`,
  and several destructive `gh` subcommands — these require interactive confirmation regardless
  of the allow-list above.
- `defaultMode: "acceptEdits"` — file edits inside the working tree are pre-approved; Bash
  commands still go through the allow/ask/deny lists.

**Significance for this spike**: the entire safety model (what may run without a human
confirming) is expressed as **Bash command allow-list rules** evaluated by Claude Code's
permission matcher, not as **per-operator identity checks**. The rules say "this shape of
command is safe to run without asking" — they say nothing about *who* is asking. A second human
(the ops person) triggering the exact same Claude Code process on the exact same machine would
inherit the exact same allow-list — there is no per-operator scoping built into this layer today.

---

## 2. `~/.claude/docs/AWS-MFA.md` — full file read on 2026-07-01

Already quoted in full detail in the main conversation; key lines re-preserved here:

> "The `/elevate-aws-access` skill automates the MFA elevation flow using 1Password and Windows
> Hello — the engineer never types a TOTP code manually."

> "1Password item with your AWS MFA TOTP, named `"Amazon AWS - <Your Name>"`. The item must have
> a TOTP field configured."

> "MFA device registered on your IAM user."

> "Do NOT set `AWS_PROFILE` in `settings.local.json`. The default profile must remain active so
> that read-only operations work without MFA."

**Significance**: the elevation path that unlocks AWS *write* operations (`4shark-mfa` profile)
is anchored to (a) a named 1Password item scoped to one named engineer, (b) an MFA device
registered to that engineer's own IAM user, and (c) a Windows Hello prompt on that engineer's own
desktop. This is a personal-identity mechanism by construction — it cannot be handed to a second
person without either sharing the engineer's own MFA device/vault (defeats non-impersonation) or
building an equivalent elevation path scoped to a different principal.

---

## 3. `~/.claude/skills/integrators/SKILL.md` — read on 2026-07-01 (full file, 133 lines)

Key excerpt (scale-up flow):

```
### If the engineer asked to scale up

1. Identify the cluster and service names from the Client tag
2. Update the desired count using the `ecs-scale.sh` script — never call `aws ecs update-service` directly:

bash ~/.claude/scripts/ecs-scale.sh --region sa-east-1 --cluster integrator-{client}-cluster --service integrator-{client}-{type}-service --desired-count {N}

3. If `AccessDenied` or `UnauthorizedAccess`, run `/elevate-aws-access` to elevate and retry
4. Report: "Serviço {type} do {client} escalado para {N} tasks."
```

And the confirmation policy for scale-down:

> "Engineer named a specific service categorically... → execute immediately, no confirmation...
> Engineer used a bulk or ambiguous phrase... → confirm before proceeding."

**Significance**: this is a representative example of the "candidate to become a self-service
skill" class named in the investigation question. The skill's own text encodes the *procedure*
(tag discovery → `ecs-scale.sh` → elevate-on-`AccessDenied` → report) independently of who is
running it — confirming that the skill logic itself is operator-agnostic; only the underlying
AWS credential path (finding #2 above) is engineer-specific.

---

## 4. `~/.claude/scripts/ecs-scale.sh` — read in full on 2026-07-01 (63 lines)

The script takes `--region --cluster --service --desired-count` and runs a single
`aws ecs update-service ...` call. **It has no `--profile` parameter of its own** — it inherits
whatever AWS profile/credentials are active in the ambient environment when invoked. This
confirms the script itself carries no identity logic; identity is entirely a property of how/
where it is invoked (which profile is active, which IAM principal that profile resolves to).

---

## 5. `~/.claude/skills/integration-debug/SKILL.md` — partial read (first 80 of a larger file)
on 2026-07-01, for structural shape only (not a full-read — this spike is not executing that
skill's workflow, only citing its documented human-in-the-loop division of labor as a design
precedent)

> "Division of labor (per-phase): Phase 1 (Discovery) and Phase 3 (Verification) — fully
> automated by you... Phase 2 (Execution) — manual, non-negotiable. Mutations to integrator
> MongoDB and app RDS always go through the engineer pasting hand-written scripts into
> `bin/ecs run`... Human review is the only gate against a wrong filter mass-mutating production
> data — never automate Phase 2."

**Significance**: 4Shark already has a documented precedent for splitting an ops workflow into
an automatable read/verify phase and a human-gated write/mutation phase within a single skill.
This is a directly reusable design shape for a self-service permission model (see SPIKE.md
§ Finding 5).

---

## 6. Line counts confirmed (not read in full — existence/scale check only)

```
588 ~/.claude/scripts/validate-bash-command.sh
 59 ~/.claude/scripts/auto-approve-local-skills.sh
155 ~/.claude/scripts/auto-approve-aws-readonly.sh
```

Confirms these are substantial, actively maintained guard scripts (consistent with the
CLAUDE.md description of `validate-bash-command.sh` as the PreToolUse hook blocking destructive
git/terraform/AWS shapes), not stubs.
