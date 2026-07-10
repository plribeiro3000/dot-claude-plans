# Auxiliary — File Inventory: References to `claude/plans` in dot-claude

Source: `grep -rln "claude/plans" ~/Projects/4Shark/dot-claude` (working copy), run 2026-07-10.
Total: 33 files. Matches the count given in the task briefing exactly (scripts 9, agents 8, docs 7, tests 3, root 3, commands 2, skills 1).

Every row below is classified along two axes:

- **Kind** — `LIVE` (a functional path used by a script/hook/agent at runtime, or a glob the language-policy verifier evaluates against) vs `PROSE` (documentation describing the convention, read by an engineer or an LLM subagent, not executed) vs `CITATION` (a historical pointer to a specific, already-existing SPIKE/PLAN/ADR document — most of these predate the relocation and live in `completed/` already).
- **Needs repoint?** — whether the literal path must change for the new convention to hold.

## Root (3)

| File | Lines | Kind | Needs repoint? |
|---|---|---|---|
| `README.md` | 33, 90, 406–407, 409–419, 421–434, 476–489 (migration-script example), 690–691 | PROSE + one code example | Yes — all prose occurrences describe the standing convention |
| `CHANGELOG.md` | 429–431 | CITATION (historical, dated changelog entry from initial release) | No — Changelog Policy: entries are about the past, never rewritten |
| `CLAUDE.md` | 283, 286, 624, 759, 1094, 1191, 1239, 1280, 1371 (+ full "Plans Storage" tree section, "Repository Structure" tree) | PROSE — governs every session's mental model of where plans live | Yes |

## Scripts (9)

| File | Lines | Kind | Needs repoint? |
|---|---|---|---|
| `scripts/plans-autocommit.sh` | 32 (`PLANS_DIR="${HOME}/.claude/plans"`) | LIVE | Yes |
| `scripts/check-plans-autocommit.sh` | 26 (`PLANS_DIR="${HOME}/.claude/plans"`), plus doc comment at 12/17 | LIVE | Yes |
| `scripts/setup-plans-autocommit.sh` | 128 (`plans_dir="${HOME}/.claude/plans"`) | LIVE | Yes |
| `scripts/validate-bash-command.sh` | 10, 95 (`plans_prefix="$HOME/.claude/plans/"`), 114, 582 | LIVE — the plans-specific auto-approve carve-out (see mirror-patterns aux) | Yes — path AND, per Option A/dead-code note, this carve-out may become moot post-relocation |
| `scripts/auto-approve-claude-dir-writes.sh` | 5 (doc comment only, references `~/.claude/plans/` as the primary example) | PROSE comment inside a script | No functional change needed (its match is `${claude_dir}/*` broad, not plans-specific) — comment mentions plans as illustrative example only |
| `scripts/read-context.sh` | 171 | PROSE (injected reminder text) | Yes |
| `scripts/inject-output-policy-reminder.sh` | 35 | PROSE (injected reminder text) | Yes |
| `scripts/migrations/20251128200000_create_active_completed_dirs.sh` | 6, 10, 11, 18 | LIVE but HISTORICAL — already-executed migration (tracked in `.migrations_executed`), re-running is a no-op by design | No — never edit an already-shipped migration; see Sources § migrate.sh mechanism |
| `scripts/migrations/20251128200001_rename_project_dirs.sh` | 19 | LIVE but HISTORICAL (same as above) | No |

## Agents (8)

| File | Lines | Kind | Needs repoint? |
|---|---|---|---|
| `agents/knowledge-cruncher.md` | 67–68 | PROSE (prompt text — hardcoded path, agent cannot call a resolver) | Yes |
| `agents/spike.md` | 60 | PROSE | Yes |
| `agents/task-researcher.md` | 15, 17 | PROSE | Yes |
| `agents/process-modeler.md` | 18–19 | PROSE | Yes |
| `agents/orchestrator.md` | 88, 92, 106, 129, 400 | PROSE | Yes |
| `agents/plan-researcher.md` | 26, 79–80 | PROSE (this very agent's own write-location instructions) | Yes |
| `agents/context-mapper.md` | 16–17 | PROSE | Yes |
| `agents/pr-review.md` | 119 | PROSE | Yes |

Not found in the 33-file grep (confirmed absent): `agents/plan-composer.md`, `agents/task-composer.md`, `agents/domain-modeler.md`, `agents/output-verifier.md`, `agents/policy-verifier.md`, `agents/code-policy-verifier.md` — these either describe their write location in relative/generic terms or inherit it from the calling agent's briefing.

## Docs (7)

| File | Lines | Kind | Needs repoint? |
|---|---|---|---|
| `docs/WORKTREE-POLICY.md` | 92 | CITATION (points to a specific completed spike) | Open question — see Option D discussion |
| `docs/adr/ADR-004-code-write-policy-enforcement.md` | 87–88 | CITATION | Open question |
| `docs/LANGUAGE-POLICY.md` | 3 (prose), 58 (citation example), **176** (`~/.claude/plans/{active,completed}/**/*.md` — a live glob the language-policy verifier evaluates paths against) | PROSE + **LIVE glob** | Yes for line 3 and 176; line 58 is a citation (see below) |
| `docs/DEPLOYMENT-STRATEGY.md` | 196 | CITATION | Open question |
| `docs/adr/ADR-003-policy-verifier.md` | 85–86 | CITATION | Open question |
| `docs/adr/ADR-001-rules-loading-mechanism.md` | 114–115 | CITATION | Open question |
| `docs/runbooks/terraform-operations/AMI-VERSION-UPGRADE.md` | 158 | CITATION | Open question |

Every docs `CITATION` row points at a **specific, named spike/plan folder** (e.g. `spike/claude-code-worktrees/`, `spike/vazamento-b-code-enforcement/`) that documents a past design decision. These are historical footnotes, not the standing convention.

## Tests (3)

| File | Lines | Kind | Needs repoint? |
|---|---|---|---|
| `tests/cases/validate-bash-command.cases.sh` | 60 (`run_case "write under plans allows" ...`) | LIVE (test fixture asserting the old path is auto-approved) | Yes, if `validate-bash-command.sh`'s plans-carve-out is kept/repointed (see Option A) |
| `tests/cases/auto-approve-claude-dir-writes.cases.sh` | 5 (`run_case "write under .claude/plans allows" ...`) | LIVE (test fixture) | No path change needed — this hook matches broad `${claude_dir}/*`, so the case still exercises the hook correctly with any `~/.claude/*` path; could optionally be reworded but is not path-dependent |
| `tests/cases/inject-code-pattern-on-write.cases.sh` | (uses a `~/.claude/plans/...` path as a generic example file) | LIVE (test fixture, illustrative path) | Optional — any `~/.claude/*` path exercises the same hook logic |

## Commands (2)

| File | Lines | Kind | Needs repoint? |
|---|---|---|---|
| `commands/execute.md` | 10, 19, 22–24, 27–29 | PROSE | Yes |
| `commands/cleanup-memories.md` | 3, 37, 41, 116, 125–126, 158, 166, 174, 202, 234, 247, 257, 270, 315, 432 | PROSE — extensive, this skill's entire run-folder convention lives under `~/.claude/plans/active/memories/` | Yes (largest single-file edit in the set) |

## Skills (1)

| File | Lines | Kind | Needs repoint? |
|---|---|---|---|
| `skills/post-mortem/SKILL.md` | 119 | PROSE | Yes |

## Summary counts

- **LIVE functional paths requiring repoint**: `plans-autocommit.sh`, `check-plans-autocommit.sh`, `setup-plans-autocommit.sh`, `validate-bash-command.sh` (4 scripts) + `docs/LANGUAGE-POLICY.md:176` (1 glob) + 1 test fixture (`validate-bash-command.cases.sh:60`, conditional on Option A) = **5–6 files**
- **PROSE requiring repoint** (agents, commands, skill, CLAUDE.md, README.md, 2 injected-reminder scripts): **20 files**
- **HISTORICAL, do not touch**: `CHANGELOG.md`, the 2 already-executed migration scripts = **3 files**
- **CITATION, open question (Option D)**: 6 docs files (WORKTREE-POLICY, ADR-001, ADR-003, ADR-004, DEPLOYMENT-STRATEGY, AMI-VERSION-UPGRADE) = **6 files**
- **No change needed** (broad-match hook comment, illustrative test path): `auto-approve-claude-dir-writes.sh`, `inject-code-pattern-on-write.cases.sh` = **2 files**

5–6 + 20 + 3 + 6 + 2 = 36–37 counted-rows vs 33 files because several files appear in more than one bucket (e.g. `LANGUAGE-POLICY.md` has both a PROSE line and a LIVE glob line; `validate-bash-command.sh` and its test fixture are linked).
