# Auxiliary — Full File Inventory

Every file the feature is expected to touch, grouped by kind. Paths are given
relative to the `dot-claude` working copy (`~/Projects/4Shark/dot-claude/`) —
the repo the PR is made against, per § Configuration Changes Policy
(`~/.claude/CLAUDE.md:496-505`). None of these are edited at `~/.claude/`
directly.

## New files

| Path (proposed, see naming options in `PLAN-SPIKE.md` § F) | Role | Mirrors |
|---|---|---|
| `scripts/config-self-heal.sh` | OS-independent "what" — detects app reformat, resets it if pure, surfaces + preserves real drift, then `git pull --ff-only` on master/develop | `scripts/plans-autocommit.sh` |
| `scripts/setup-config-self-heal.sh` | OS-detecting installer — launchd / systemd user timer / Windows Task Scheduler, all pointing at `config-self-heal.sh` | `scripts/setup-plans-autocommit.sh` |
| `scripts/lib/claude-config-reset.sh` (Option A only — shared-helper path) | Extracted `capture_settings_drift` + reset step, sourced by both `check-claude-version.sh` and `config-self-heal.sh` | New — no direct precedent; `DATA-PROCESSING.md`-style shared lib is the closest analogy in spirit, not in file shape |

## Modified files

| Path | Change |
|---|---|
| `scripts/check-claude-version.sh` | Option A only: replace the inline `capture_settings_drift` (lines 231-247) and the reset branch inside `attempt_auto_pull` (lines 274-284) with calls into the shared helper. Option B: no change. |
| `CLAUDE.md` § Configuration Changes Policy (`~/.claude/CLAUDE.md:496-505` in the installed copy) | Document the new daily self-heal cron — mirrors how § Plans Repository Auto-Commit (`~/.claude/CLAUDE.md:282-288`) documents `plans-autocommit.sh` + `setup-plans-autocommit.sh` as a paired "what" + installer, including the one-time `bash ~/.claude/scripts/setup-config-self-heal.sh` install instruction |
| `CLAUDE.md` § Repository Structure (`~/.claude/CLAUDE.md:1001+`, the `scripts/` tree listing) | Add the new script(s) to the tree with a one-line description, matching the existing entries for `plans-autocommit.sh` / `setup-plans-autocommit.sh` |
| `README.md` | Open question — see `PLAN-SPIKE.md` § F. No README section documents `setup-plans-autocommit.sh` today (confirmed: `grep -n "setup-plans-autocommit\|plans-autocommit" ~/.claude/README.md` returned no output) — the closest existing installer note lives only in `CLAUDE.md`, not `README.md`. Whether to add a first-ever README installer note or follow the same precedent (CLAUDE.md-only) is for the engineer to decide. |
| `CHANGELOG.md` `## [Unreleased]` → `### Added` | One entry naming the new daily self-heal, per the Changelog Policy (`~/.claude/CLAUDE.md` § Changelog Policy) — succinct, no file/class names, no implementation detail |
| `settings.json` `permissions.allow` | Add both invocation-form entries for the new installer, mirroring `settings.json:519-520` (`Bash(bash $HOME/.claude/scripts/setup-config-self-heal.sh:*)` and the `~`-prefixed twin) |

## Files NOT touched (explicitly out of scope per the engineer's brief)

| Path | Why not |
|---|---|
| `settings.json` `hooks.*` (SessionStart/UserPromptSubmit/SubagentStart) | The new script is invoked by a native OS scheduler (launchd/systemd/Task Scheduler), not a Claude Code hook — `plans-autocommit.sh` is the precedent: it has NO entry under `hooks.*`, only `check-plans-autocommit.sh` (the separate *nudge* script) does (`settings.json:130`). If the engineer wants a parallel freshness-nudge for config self-heal, that is a new, undiscussed scope item — flagged as an open question, not assumed. |
| `.claude/.gitignore` | No new git-ignored artifact is anticipated (no local log file was requested in the brief, unlike `plans-autocommit.sh`'s `.autocommit.log`) — but see Sub-decision C, where a log/marker file may be a candidate design and would need a `.gitignore` entry if added under `~/.claude/`. Flagged, not assumed. |
