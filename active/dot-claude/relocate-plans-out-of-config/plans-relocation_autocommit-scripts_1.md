# Auxiliary — Autocommit Scheduler: What "Reinstall at the New Path" Requires

Three scripts, each with a hardcoded `${HOME}/.claude/plans` that must repoint to `${HOME}/Projects/4Shark/dot-claude-plans`. All three stay physically located in `~/.claude/scripts/` (they are dot-claude tooling, not plans content) — only the *target directory they operate on* changes.

## `scripts/plans-autocommit.sh` (the "what" — commits once)

```
scripts/plans-autocommit.sh:32   PLANS_DIR="${HOME}/.claude/plans"
```

Everything else in the script (`LOG_FILE="${PLANS_DIR}/.autocommit.log"` at line 33, all `git -C "${PLANS_DIR}"` calls) derives from `PLANS_DIR`, so this is a single-line change once the constant is updated. No other coupling to the literal `.claude` segment — the guard logic (branch must be `main`, no mid-rebase, no-changes-no-commit) is path-agnostic.

## `scripts/setup-plans-autocommit.sh` (the "how" — installs the per-OS scheduler)

```
scripts/setup-plans-autocommit.sh:23   COMMIT_SCRIPT="${HOME}/.claude/scripts/plans-autocommit.sh"
```

This line does NOT need to change — it points at the *script*, which stays in `~/.claude/scripts/` (only `plans-autocommit.sh`'s internal `PLANS_DIR` constant changes, per above). The three per-OS installers (macOS launchd plist, Linux systemd timer, WSL Task Scheduler) all just schedule `bash ${COMMIT_SCRIPT}` — they carry no direct reference to the plans path themselves, so the scheduler installation itself is unaffected by the relocation as long as `plans-autocommit.sh` (the target of the schedule) is updated.

The one place this script DOES reference `~/.claude/plans` directly is the `.gitignore` self-heal block:

```
scripts/setup-plans-autocommit.sh:128   plans_dir="${HOME}/.claude/plans"
```

This needs the same repoint — it manages the `.autocommit.log` gitignore entry inside the plans repo itself.

**Reinstall requirement**: because this script re-runs `launchctl bootstrap` / `systemctl --user enable --now` / `schtasks.exe /create ... /f` idempotently (the `/f` and `bootout`-then-`bootstrap` pattern already handle "already installed, replace"), running `bash ~/.claude/scripts/setup-plans-autocommit.sh` again after the repoint is sufficient to move the schedule onto the corrected `plans-autocommit.sh`. No separate "uninstall old, install new" step is needed — the existing idempotent install logic already overwrites its own prior registration (`launchctl bootout ... || true` at line 74, `systemctl --user enable --now` at line 102 which is idempotent by systemd design, `schtasks.exe .../f` which force-overwrites at line 112). This is per-machine and manual (confirmed ground truth: each engineer has their own plans repo/fork), so each engineer runs this once after pulling the dot-claude update.

## `scripts/check-plans-autocommit.sh` (the nudge — warns when stale)

```
scripts/check-plans-autocommit.sh:26   PLANS_DIR="${HOME}/.claude/plans"
scripts/check-plans-autocommit.sh:27   LOG_FILE="${PLANS_DIR}/.autocommit.log"
```

Same single-constant repoint. Also worth noting for the transition-window design (Technical Decision A): this hook already has a **remote-URL-based safety check** that is directly reusable for detecting "has this engineer migrated yet?":

```
scripts/check-plans-autocommit.sh:37-41
remote_url="$(git -C "${PLANS_DIR}" remote get-url origin 2>/dev/null || echo '')"
case "${remote_url}" in
    *dot-claude-plans*) : ;;
    *) exit 0 ;;
esac
```

If `PLANS_DIR` is repointed to the new path but the engineer has not yet physically moved their plans repo there, `git -C "${PLANS_DIR}" remote get-url origin` fails (empty), the `case` falls to `exit 0` (silent) — meaning this specific hook degrades gracefully (no false warning) during the transition window, it just goes quiet rather than nagging about the right thing. This is relevant evidence for whichever transition-safety option is chosen: this hook alone will NOT surface "you haven't migrated yet" — a dedicated new detection hook (mirroring `check-ssh-keys.sh`) is needed for that signal, this one only detects "autocommit is stale," a different condition.

## Cross-cutting: `.autocommit.log` and `.migrations_executed`-style state

`plans-autocommit.sh` writes `${PLANS_DIR}/.autocommit.log` (line 33, git-ignored inside the plans repo itself per `setup-plans-autocommit.sh:130-134`). This file is part of the plans repo's own working tree, so it moves naturally with a `git mv`-of-directory / re-clone style migration — no separate handling needed beyond ensuring the new location's `.gitignore` still carries the `.autocommit.log` entry (already handled by the self-heal block in `setup-plans-autocommit.sh:129-139`, which runs again on reinstall).
