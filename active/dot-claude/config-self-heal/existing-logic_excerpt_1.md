# Auxiliary — Existing Logic Excerpts

Raw, verbatim excerpts backing the citations in `PLAN-SPIKE.md`. Every block below
is quoted exactly from the file at the stated line range (read in full on
2026-07-10).

## 1. `~/.claude/scripts/check-claude-version.sh` — reset + reformat-detection + ff-pull

### 1.1 Branch restriction (only master/develop)

`check-claude-version.sh:38-42`

```bash
[[ -d "${CLAUDE_DIR}/.git" ]] || exit 0

branch=$(git -C "${CLAUDE_DIR}" branch --show-current 2>/dev/null) || exit 0

[[ "${branch}" == "master" || "${branch}" == "develop" ]] || exit 0
```

### 1.2 Once-a-day marker gate

`check-claude-version.sh:35-36`

```bash
CLAUDE_DIR="${HOME}/.claude"
MARKER="/tmp/claude_version_check_$(date +%Y%m%d).done"
```

`check-claude-version.sh:89`

```bash
[[ -f "${MARKER}" ]] && exit 0
```

The marker is date-stamped (`%Y%m%d`), lives in `/tmp/`, and is only touched on
two success paths: local tag already equals remote tag (line 168-171) and a
successful auto-pull (line 318-319). Failure/notice paths deliberately do NOT
touch the marker, so the notice re-fires every UserPromptSubmit until resolved.

### 1.3 Reformat vs real-change detection — `capture_settings_drift`

`check-claude-version.sh:231-247`

```bash
# capture_settings_drift — set ${settings_drift} to the real content difference
# between the working-tree settings.json and HEAD, or leave it empty when the
# only difference is the app's reformat noise. Both sides are normalized with jq
# (recursive key sort + drop the app-managed personal-pref keys); if they match
# after normalization the change is pure noise and nothing is captured. When they
# differ, the normal diff is captured so the engineer is shown what is about to
# be reset. jq is a mandatory tool (verified by check-dependencies.sh).
capture_settings_drift() {
    local drop='del(.theme, .inputNeededNotifEnabled, .agentPushNotifEnabled)'
    local normalized_local normalized_head
    normalized_local=$(jq -S "${drop}" "${CLAUDE_DIR}/settings.json" 2>/dev/null) || return
    normalized_head=$(git -C "${CLAUDE_DIR}" show HEAD:settings.json 2>/dev/null | jq -S "${drop}" 2>/dev/null) || return
    [[ -z "${normalized_local}" || -z "${normalized_head}" ]] && return
    [[ "${normalized_local}" == "${normalized_head}" ]] && return

    settings_drift=$(diff <(printf '%s\n' "${normalized_head}") <(printf '%s\n' "${normalized_local}") 2>/dev/null)
}
```

Key mechanics:
- `jq -S` recursively sorts keys — neutralizes the app's key-reordering.
- `del(.theme, .inputNeededNotifEnabled, .agentPushNotifEnabled)` drops the
  three app-managed personal-pref keys before comparing (these are re-injected
  by the app and are noise, not real content).
- Compares working-tree `settings.json` against `HEAD:settings.json` (the
  committed version), NOT against the remote tag — this only detects local
  drift caused by the app, unrelated to whether a newer tag exists upstream.
- `settings_drift` stays empty (falsy) when normalized content is identical →
  pure reformat. Populated with a real unified-style diff when content differs
  → real change.

### 1.4 Reset gate — `attempt_auto_pull`

`check-claude-version.sh:249-292`

```bash
# attempt_auto_pull — fast-forward ${CLAUDE_DIR} to the newer remote tag when it
# is safe. Sets ${pull_result} to one of:
#   pulled         — fast-forward succeeded; the working tree now has the update
#   skipped_dirty  — real local changes are present (beyond the app's own
#                    settings.json rewrite); left untouched, fall back to warn
#   failed         — fetch or fast-forward failed (e.g. diverged history);
#                    fall back to warn
# The Claude Code app continuously rewrites the tracked settings.json (reorders
# keys, re-adds personal prefs that already live in the git-ignored
# settings.local.json), so a lone ` M settings.json` is discarded before the
# pull. When that discarded change carries real content (hooks/permissions/skills
# differ from HEAD, not just the app reformat), capture_settings_drift records it
# into ${settings_drift} FIRST so the engineer is shown what was reset and can
# re-route it. Any other dirty/untracked path is treated as real work and blocks
# the auto-pull.
pull_result=""
settings_drift=""
attempt_auto_pull() {
    if ! git -C "${CLAUDE_DIR}" fetch --quiet origin 2>/dev/null; then
        pull_result="failed"
        return
    fi

    local status
    status=$(git -C "${CLAUDE_DIR}" status --porcelain=v1 2>/dev/null)
    if [[ -n "${status}" ]]; then
        if [[ "${status}" == " M settings.json" ]]; then
            capture_settings_drift
            git -C "${CLAUDE_DIR}" checkout -- settings.json 2>/dev/null || {
                pull_result="skipped_dirty"
                return
            }
        else
            pull_result="skipped_dirty"
            return
        fi
    fi

    if git -C "${CLAUDE_DIR}" pull --ff-only --quiet origin "${branch}" 2>/dev/null; then
        pull_result="pulled"
    else
        pull_result="failed"
    fi
}
```

Critical nuance for scope (Sub-decision D): the reset trigger is an **exact
string match** on the whole porcelain status — `status == " M settings.json"`.
If ANY other file is also dirty (tracked-modified or untracked), the entire
run is treated as `skipped_dirty` and NOTHING is reset — settings.json
included. The logic does not scan/reset any file other than `settings.json`,
and does not partially reset when multiple files are dirty.

The reset mechanism itself is `git checkout -- settings.json` (line 277), not
`git restore` — functionally equivalent (discard working-tree changes to a
tracked path), but this is the exact command already in use in this codebase.

`--ff-only` appears once, on the `git pull` at line 287 — no merge commit is
ever created; a diverged/non-fast-forward state always falls through to
`pull_result="failed"`.

### 1.5 Surfacing a real change before reset

`check-claude-version.sh:296-316`

```bash
if [[ -n "${settings_drift}" ]]; then
    cat <<EOF
=== LOCAL settings.json CHANGES WERE RESET ===

Your ~/.claude/settings.json had real local changes (beyond the Claude Code
app's own reformat) and was reset to the repository version so the config could
update. Lines marked '>' are what you had locally (now lost); lines marked '<'
are the repository value that was restored:

${settings_drift}

Route these deliberately: SHARED config (hooks, permissions, skills) must go
through a dot-claude PR; PERSONAL prefs go in ~/.claude/settings.local.json
(git-ignored). Never hand-edit the installed ~/.claude/settings.json.

YOUR NEXT RESPONSE MUST surface this reset to the engineer (in the language of
the current conversation) — show the reset changes above and where each should
go, so no context is lost. Do this even if the engineer's prompt is about
something else.
EOF
fi
```

This block prints EVEN WHEN `settings_drift` was captured but the reset itself
still happened — i.e. the real change is always surfaced to the engineer via
Claude's next chat response (`additionalContext` channel), never silently
discarded without notice. This mechanism has no equivalent surface in an
unattended daily cron (no session, no chat) — see Sub-decision C in
`PLAN-SPIKE.md`.

### 1.6 Overall call order in the script

1. Guard: `.git` exists, branch is master/develop (§1.1)
2. Guard: marker not already touched today (§1.2), unless `--decline`
3. `gh_check_status` — resolves the latest remote tag (unrelated to the
   reset/pull mechanics; failure modes emit a persistent notice)
4. Version comparison / classification (MAJOR/MINOR/PATCH + security detection)
5. `attempt_auto_pull()` (§1.4), which internally calls `capture_settings_drift()`
   (§1.3) only when the sole dirty file is `settings.json`
6. Surface `settings_drift` if non-empty (§1.5)
7. Surface pull result (`pulled` → auto-updated notice; otherwise → manual
   update notice, marker NOT touched)

Full file: `~/.claude/scripts/check-claude-version.sh` (364 lines).

---

## 2. `~/.claude/scripts/setup-plans-autocommit.sh` — per-OS scheduler installer

### 2.1 Header / purpose

`setup-plans-autocommit.sh:1-19`

```bash
#!/usr/bin/env bash
#
# Install the per-OS scheduler that runs plans-autocommit.sh daily at midnight.
#
# Detects the operating system and installs the right native scheduler, all
# pointing at the same OS-independent commit script
# (~/.claude/scripts/plans-autocommit.sh):
#
#   macOS  -> a launchd LaunchAgent (com.4shark.plans-autocommit), runs at
#             00:00, catches up on the next wake natively.
#   Linux  -> a systemd --user timer (Persistent=true, single catch-up on a
#             missed run) + loginctl enable-linger so it fires without a login.
#   WSL    -> a Windows Task Scheduler task via schtasks.exe. A scheduler inside
#             WSL does not fire when WSL is shut down, so the trigger is
#             registered on the Windows side and invokes the script through
#             wsl.exe.
#
# Run once after pulling the dot-claude update. Idempotent.

set -uo pipefail
```

### 2.2 OS detection order (WSL before generic Linux)

`setup-plans-autocommit.sh:33-43`

```bash
# Detect the operating system. WSL must be checked before the generic Linux
# branch — it is Linux but needs the Windows-side scheduler.
if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
    operating_system="wsl"
elif [[ "$(uname -s)" == "Darwin" ]]; then
    operating_system="macos"
elif [[ "$(uname -s)" == "Linux" ]]; then
    operating_system="linux"
else
    operating_system="unknown"
fi
```

### 2.3 macOS — launchd LaunchAgent

`setup-plans-autocommit.sh:46-77`

```bash
    macos)
        plist_path="${HOME}/Library/LaunchAgents/${LABEL}.plist"
        cat > "${plist_path}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${COMMIT_SCRIPT}</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>${SCHEDULE_HOUR}</integer>
        <key>Minute</key>
        <integer>${SCHEDULE_MINUTE}</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/tmp/plans-autocommit.out</string>
    <key>StandardErrorPath</key>
    <string>/tmp/plans-autocommit.err</string>
</dict>
</plist>
EOF
        launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
        launchctl bootstrap "gui/$(id -u)" "${plist_path}"
        echo "Installed launchd LaunchAgent ${LABEL} (runs daily at 00:00)."
        ;;
```

`bootout` before `bootstrap` is the idempotency mechanism for macOS — it
unregisters any existing agent with the same label (ignoring failure when
none is registered) before re-registering, so re-running the installer is
safe.

### 2.4 Linux — systemd user timer + linger

`setup-plans-autocommit.sh:79-108`

```bash
    linux)
        systemd_dir="${HOME}/.config/systemd/user"
        mkdir -p "${systemd_dir}"
        cat > "${systemd_dir}/plans-autocommit.service" <<EOF
[Unit]
Description=4Shark plans repo daily auto-commit

[Service]
Type=oneshot
ExecStart=/bin/bash %h/.claude/scripts/plans-autocommit.sh
EOF
        cat > "${systemd_dir}/plans-autocommit.timer" <<EOF
[Unit]
Description=Daily 4Shark plans auto-commit

[Timer]
OnCalendar=*-*-* ${SCHEDULE_HOUR}:$(printf '%02d' "${SCHEDULE_MINUTE}"):00
Persistent=true

[Install]
WantedBy=timers.target
EOF
        systemctl --user daemon-reload
        systemctl --user enable --now plans-autocommit.timer
        if ! loginctl enable-linger "${USER}" 2>/dev/null; then
            echo "Note: could not enable linger automatically. To let the timer run"
            echo "without an open session, run: sudo loginctl enable-linger ${USER}"
        fi
        echo "Installed systemd user timer plans-autocommit.timer (runs daily at 00:00)."
        ;;
```

`Persistent=true` is the systemd catch-up-on-missed-run equivalent to
launchd's native wake-catchup. `enable --now` both enables (survives reboot)
and starts the timer immediately; `daemon-reload` picks up the two new unit
files. `enable-linger` lets the user's systemd instance run without an active
login session — best-effort (failure only prints a manual fallback, does not
abort the install).

### 2.5 WSL — Windows Task Scheduler via schtasks.exe

`setup-plans-autocommit.sh:110-114`

```bash
    wsl)
        task_command="wsl.exe -d ${WSL_DISTRO_NAME} -u ${USER} bash -lc '${COMMIT_SCRIPT}'"
        schtasks.exe /create /tn "plans-autocommit" /sc daily /st "$(printf '%02d:%02d' "${SCHEDULE_HOUR}" "${SCHEDULE_MINUTE}")" /tr "${task_command}" /f
        echo "Installed Windows Task Scheduler task plans-autocommit (runs daily at 00:00)."
        ;;
```

`/f` (force) on `schtasks.exe /create` is the idempotency mechanism — silently
overwrites an existing task of the same name. The task is registered
Windows-side (not inside WSL) because a scheduler inside WSL does not fire
when the WSL VM is not running; the task re-enters WSL via `wsl.exe` at
trigger time.

### 2.6 Unsupported OS fallback

`setup-plans-autocommit.sh:116-120`

```bash
    *)
        echo "Unsupported operating system: $(uname -s)" >&2
        echo "Install a daily scheduler for ${COMMIT_SCRIPT} manually." >&2
        exit 1
        ;;
```

### 2.7 Seed run at the end of install

`setup-plans-autocommit.sh:141-143`

```bash
# Seed the log with a first run, so the install is confirmed end to end and the
# health-check nudge goes silent immediately instead of nagging until midnight.
bash "${COMMIT_SCRIPT}"
```

The installer runs the "what" script once immediately after registering the
scheduler, so the install is verified end-to-end without waiting for the
first scheduled trigger.

Full file: `~/.claude/scripts/setup-plans-autocommit.sh` (144 lines).

---

## 3. `~/.claude/scripts/plans-autocommit.sh` — OS-independent "what" script pattern

### 3.1 Header block style

`plans-autocommit.sh:1-33`

```bash
#!/usr/bin/env bash
#
# Plans Repository Daily Auto-Commit
#
# Each engineer's personal planning repo lives at ~/Projects/4Shark/dot-claude-plans/
# (a separate git repo, by convention git@github.com:<github-username>/dot-claude-plans.git).
# It holds high-value planning intelligence but is rarely committed by hand, so
# the working tree accumulates uncommitted work that one disk failure can erase.
#
# This script is the OS-independent "what": it commits the working tree once and
# pushes the snapshot to the private remote.
# It is invoked by a per-OS scheduler (the "how") installed by
# setup-plans-autocommit.sh — launchd on macOS, a systemd user timer on Linux,
# Windows Task Scheduler on WSL — at midnight, with catch-up on the next wake.
#
# Behaviour:
#   - No changes        -> no commit (never an empty commit), logs "no changes".
#   - Has changes       -> git add -A + git commit + git push, logs the hash.
#   - Wrong branch / mid-rebase/merge / not a repo -> skips, logs why.
#
# Push IS done here (engineer decision): after each commit the snapshot is pushed
# to the private remote for off-machine backup. There is no pull step — this is
# single-machine backup, nothing external mutates the repo, so push alone
# suffices. A push failure is logged but never fails the run (the local commit
# already preserved the work).
#
# Every run appends one line to ~/Projects/4Shark/dot-claude-plans/.autocommit.log (git-ignored).
# The line starts with an epoch timestamp so check-plans-autocommit.sh can read
# the freshness portably across macOS/Linux/WSL.
#
# Idempotent and safe to run by hand at any time.

set -uo pipefail
```

### 3.2 Guard structure (repo exists → branch → mid-rebase/merge → no-op)

`plans-autocommit.sh:43-64`

```bash
# Guard: plans must be a git repository.
[[ -d "${PLANS_DIR}/.git" ]] || exit 0

# Guard: only commit on the main branch — never snapshot a detached/feature HEAD.
branch="$(git -C "${PLANS_DIR}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
if [[ "${branch}" != "main" ]]; then
    log_line "skipped — HEAD is on '${branch}', not main"
    exit 0
fi

# Guard: never commit into a half-finished rebase/merge state.
git_dir="$(git -C "${PLANS_DIR}" rev-parse --git-dir 2>/dev/null || echo '')"
if [[ -n "${git_dir}" ]]; then
    case "${git_dir}" in
        /*) abs_git_dir="${git_dir}" ;;
        *)  abs_git_dir="${PLANS_DIR}/${git_dir}" ;;
    esac
    if [[ -d "${abs_git_dir}/rebase-merge" || -d "${abs_git_dir}/rebase-apply" || -f "${abs_git_dir}/MERGE_HEAD" ]]; then
        log_line "skipped — repository is mid-rebase/merge"
        exit 0
    fi
fi
```

### 3.3 Logging helper

`plans-autocommit.sh:38-41`

```bash
# log_line <message> — append "<epoch>  <human-time>  <message>" to the log.
log_line() {
    printf '%s  %s  %s\n' "$(date +%s)" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "${LOG_FILE}"
}
```

Epoch-first line format so a freshness check (`check-plans-autocommit.sh`) can
read the timestamp portably across macOS/Linux/WSL without parsing the
human-readable date.

Full file: `~/.claude/scripts/plans-autocommit.sh` (91 lines).

---

## 4. Repository tracking check — `.env`-like files

Command run: `git -C ~/.claude ls-files | grep -iE '\.env|settings'`

Output:

```
settings.json
settings.local.example.json
```

No `.env`-shaped file is tracked in the `dot-claude` repository — only
`settings.json` (the mutable, app-rewritten file) and
`settings.local.example.json` (a static example file, not app-managed) match.
`settings.local.json` itself is git-ignored (`~/.claude/.gitignore:71`:
`settings.local.json`) and is never a target of any reset logic. This grounds
Sub-decision D in `PLAN-SPIKE.md`.

---

## 5. Residual manual-pull gap — `/merge-cleanup` citation

`~/.claude/commands/merge-cleanup.md:222-230`

```markdown
## Final step — Pull `~/.claude` if working on the `dot-claude` repository

If the merged repo is the `dot-claude` configuration repository, also update the active config installed at `~/.claude`:

\```bash
git -C ~/.claude pull
\```

This applies to all three branch types.
```

This is a bare `git -C ~/.claude pull` — no `capture_settings_drift`, no
`--ff-only`, no reset step. It runs at the end of every `/merge-cleanup`
invocation for the `dot-claude` repository, independent of
`check-claude-version.sh`'s marker gate or any daily cron. Grounds
Sub-decision E (residual gap) in `PLAN-SPIKE.md`.

---

## 6. settings.json permission-allow precedent for an installer script

`~/.claude/settings.json:519-520`

```
      "Bash(bash $HOME/.claude/scripts/setup-plans-autocommit.sh:*)",
      "Bash(bash ~/.claude/scripts/setup-plans-autocommit.sh:*)",
```

Both the `$HOME`-prefixed and `~`-prefixed invocation forms are allow-listed
separately — the matcher does not normalize between them. A new installer
script needs the same two-line pattern.
