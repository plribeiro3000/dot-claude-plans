# Auxiliary — Mirror Patterns and Prior Art

## 1. The `migrate-ssh-keys` mirror (the engineer-decided template)

### SessionStart detection hook: `scripts/check-ssh-keys.sh`

Full read: `~/Projects/4Shark/dot-claude/scripts/check-ssh-keys.sh` (103 lines). Structure to mirror:

1. Guard/exit-early when nothing to check (`[[ -d "${SSH_DIR}" ]] || exit 0`, line 29).
2. Detect current (non-compliant) state via a pure read (counts private keys, line 65).
3. Silent when compliant (`[[ "${key_count}" -le 1 ]] && exit 0`, line 68).
4. On violation: print a `=== ... WARNING ===` block naming the problem, then a directive line addressed to the agent:

```
scripts/check-ssh-keys.sh:100
"AGENT: proactively offer to run the migrate-ssh-keys skill. Do not migrate or delete anything without the engineer's explicit OK."
```

5. Wired into `settings.json` SessionStart, `"matcher": "*"` block, alongside the other session-start checks (`settings.json:36`).
6. `exit 0` always (line 25 `set -e` is on, but every exit path is 0 or falls off the end — never blocks the session).

### Guided migration skill: `skills/migrate-ssh-keys/SKILL.md`

Full read: 65 lines. Structure to mirror:

- Frontmatter `description:` states trigger conditions explicitly (`"Use when the session-start check ... flags ... or when the engineer asks to ..."`) — `SKILL.md:3`.
- **"Division of labor"** section (`SKILL.md:12-15`) separates what the agent automates vs. what only the engineer can do manually. For SSH keys the manual step is the 1Password desktop-app import (a hard external constraint). For plans relocation there is no equivalent hard external constraint — a `git mv`-style directory move plus two `git remote`/`.git` operations are all agent-automatable — so this section would either be thin or absent depending on how Option A is resolved (does the physical move happen automatically or does it also wait on an explicit engineer "go"?).
- **"Non-negotiable safety rules"** (`SKILL.md:17-23`): back up first; never destroy until both verify; one step at a time with engineer confirmation; skip protected items (GitHub key ↔ plans: skip if already migrated); never print sensitive material (not applicable to plans directory names, but the general "confirm before every destructive step" shape applies).
- **Numbered flow** — Detect → Back up → Per-item work with confirmation gates → Final verification → Retire the backup (`SKILL.md:35-65`). The final "retire the backup" step (`SKILL.md:62-64`) is a useful mirror for plans: after the relocation is proven to work for a few days, the old `~/.claude/plans/` directory (or its `.git`) could be proposed for removal — but only with explicit engineer confirmation, never automatically.

### Wiring pattern in `settings.json`

```
settings.json:36   "$HOME/.claude/scripts/check-ssh-keys.sh"    (SessionStart, matcher "*")
```

Skills under `skills/<name>/SKILL.md` are auto-approved for invocation via `auto-approve-local-skills.sh` (CLAUDE.md § Git Safety, confirmed generically for "every skill/command defined under `~/.claude/commands/` and `~/.claude/skills/`") — no additional settings.json wiring needed beyond the folder existing.

## 2. Two EXISTING (and per the engineer's diagnosis, ineffective) mitigation attempts already in the codebase

These are directly relevant prior art: two separate hooks already attempt to solve exactly this problem (auto-approving writes under `~/.claude/plans/`) and both are wired into `settings.json` today. The engineer's diagnosis (two open upstream bugs, #66525 and #41615) establishes that Claude Code's sensitive-file gate for `~/.claude/` fires *before* `PreToolUse` hooks are consulted, so an `allow` decision from either hook never has a chance to apply.

### Attempt 1 — `scripts/auto-approve-claude-dir-writes.sh` (broad — all of `~/.claude/`)

Shipped in CHANGELOG `[0.8.0] - 2026-07-07` (`CHANGELOG.md:49`, "Auto-approval for writes under the Claude configuration directory") — three days before this task.

```
scripts/auto-approve-claude-dir-writes.sh:1-59
```

Key excerpt (lines 9-25, the hook's own documented rationale — note it targets a DIFFERENT bug than the sensitive-file gate: the relative-path permission-matcher bug, anthropics/claude-code#25137):

```bash
# Why:
#   - permissions.allow has `Edit(**)` and `Write(**)`, but those patterns are
#     resolved RELATIVE TO the current working directory. ...
#   - `~/.claude` is in permissions.additionalDirectories, but that axis grants
#     ACCESS to the path (so the write is legal at all), it does NOT auto-approve
#     the tool — the prompt still fires.
#   - The correct `~/...` and `//...` allow-rule forms do not help either: the
#     permission matcher compares against the relative DISPLAY path the prompt
#     shows (`../../../.claude/...`), and no allow pattern can match a string
#     that starts with `../`. Tracked in anthropics/claude-code#25137 (and its
#     duplicates #16800, #15499, #21397) — closed as duplicate, no fix shipped.
#   - A PreToolUse hook returning `permissionDecision: "allow"` runs BEFORE the
#     path matcher, so the relative-path bug never enters the equation.
```

This hook's premise — "a PreToolUse hook returning allow runs BEFORE the path matcher" — describes the ordinary **permission-matcher** path, not the **sensitive-file** gate. The two are apparently different subsystems in Claude Code: #41615's title is literally *"permissions.allow AND PreToolUse hooks cannot override .claude/ sensitive-file prompt"* — a stronger, earlier gate that this hook's own rationale does not address. Wired at `settings.json:249`.

Wired hook is exercised in `tests/cases/auto-approve-claude-dir-writes.cases.sh:5`.

### Attempt 2 — `scripts/validate-bash-command.sh` plans-carve-out (narrow — only `~/.claude/plans/**`)

```
scripts/validate-bash-command.sh:10-14
# 2. AUTO-APPROVE operations on ~/.claude/plans/** (engineer-owned working
#    directory for planning documents). Claude Code's hardcoded sensitive-file
#    matcher protects everything under ~/.claude/, but plans/ is not config —
#    it is git-ignored personal work. The hook returns an explicit allow
#    decision that overrides the sensitive matcher.
```

This comment (unlike Attempt 1's) explicitly names the "hardcoded sensitive-file matcher" as the target — i.e. this IS the attempt aimed at the exact bug this feature works around. The carve-out:

```bash
scripts/validate-bash-command.sh:95        plans_prefix="$HOME/.claude/plans/"
scripts/validate-bash-command.sh:109-116   case "$tool_name" in
                                              Edit|Write|MultiEdit)
                                                file_path="$(...)"
                                                case "$file_path" in
                                                  "$plans_prefix"*)
                                                    emit_allow "Path under ~/.claude/plans/ — engineer-owned planning directory, not config."
                                                    ;;
                                                esac
                                                ;;
scripts/validate-bash-command.sh:580-584   case "$command" in
                                              mkdir*"$plans_prefix"*|touch*"$plans_prefix"*|"cp "*"$plans_prefix"*|"mv "*"$plans_prefix"*|"rm "*"$plans_prefix"*)
                                                emit_allow "Bash write operation under ~/.claude/plans/ — engineer-owned planning directory."
                                                ;;
                                            esac
```

Exercised by `tests/cases/validate-bash-command.cases.sh:60` (`"write under plans allows"`).

**Implication for scope**: per the engineer's already-verified diagnosis, both of these carve-outs are provably ineffective for the sensitive-file gate (that is the stated reason this relocation task exists at all). Post-relocation, the `validate-bash-command.sh` plans-specific carve-out (lines 95, 109-116, 580-584) becomes dead code for its original purpose once the plans path is `~/Projects/4Shark/dot-claude-plans/` (which is NOT under `~/.claude/` and therefore was never subject to the sensitive-file gate to begin with — see Sources § additionalDirectories finding). Whether to remove this carve-out, repoint it to the new path, or leave it as a defensive no-op is an open scope question — see Technical Decisions table.

## 3. The existing silent auto-migration mechanism: `scripts/migrate.sh` + `scripts/migrations/*.sh`

A DIFFERENT existing mechanism in this same codebase already performs unattended, idempotent, tracked migrations of the `~/.claude/plans/` directory structure — this is relevant alternate prior art to the engineer-chosen guided-skill pattern.

```
scripts/migrate.sh:1-57
```

Key mechanics:
- Runs automatically every `SessionStart` (`settings.json:61`, `"$HOME/.claude/scripts/migrate.sh"`).
- Scans `scripts/migrations/*.sh`, sorted by filename timestamp (line 26-54).
- Tracks completed migrations in `~/.claude/.migrations_executed` (one 14-digit timestamp per line, line 16, 39, 47).
- Executes each pending migration via `bash "$migration"` with no engineer confirmation (line 45).
- Two existing migrations already touch the plans directory structure directly and unattended: `20251128200000_create_active_completed_dirs.sh` (creates `active/`/`completed/`) and `20251128200001_rename_project_dirs.sh`.

This mechanism is a **candidate alternative** to the engineer-chosen SessionStart-hook + skill pattern, but it differs in a load-bearing way: it runs unattended, with no per-step confirmation and no explicit "does the destination already have content?" merge check. The engineer's chosen pattern (mirroring `migrate-ssh-keys`) is explicitly guided and confirmed at each step — appropriate here because the destination (`~/Projects/4Shark/dot-claude-plans/`) is a *different git repository* with its own remote, and a wrong blind move risks silently overwriting or losing content if the destination already has files (see Technical Decision B). `migrate.sh`'s design assumes idempotent, harmless-to-retry filesystem operations (`mkdir -p`), not a git-repo-level relocation with a possible content collision — the class of operation the SSH-key pattern is built for.

## 4. `additionalDirectories` — no settings.json permission change needed for the new path

```
settings.json:401
"additionalDirectories": ["~/Projects", "~/.claude", "~/Downloads", "/tmp"],
```

`~/Projects` is already present. `~/Projects/4Shark/dot-claude-plans/` is a subdirectory of `~/Projects`, so it is already covered — no `settings.json` edit is needed to grant file-system access to the new location. This also means the new location was never subject to the `~/.claude/` sensitive-file gate in the first place (the gate is scoped to `~/.claude/`, confirmed by every hook comment cited above referring to it as "Claude Code's hardcoded sensitive-file matcher" for `~/.claude/`), which is the entire premise of why relocation is a structural fix rather than another hook attempt.

## 5. No harness-level (Claude Code native) coupling to `~/.claude/plans` found

Searched: `settings.json` for any built-in schema key referencing "plans" — none found beyond the 4Shark-authored hook commands and additionalDirectories entries already covered above. Every hook comment that explains the sensitive-file gate (Attempt 1 and Attempt 2 above) describes it as a generic `~/.claude/*` protection, never as something that specifically recognizes a `plans/` subdirectory. Combined with the absence of any other reference, this supports "plans lives under `~/.claude/` is a pure 4Shark convention, not a Claude Code built-in concept" — i.e. relocating it is not fighting anything the harness itself expects.
