# SPIKE — Daily auto-commit of each engineer's personal `plans` repo, across three operating systems

**Conducted by:** Paulo Ribeiro
**Date:** 2026-06-30
**Status:** Research complete — pending decisions

---

## Goal

The shared `dot-claude` config is versioned and shared across the three 4Shark engineers, but `plans/` is git-ignored from it (`~/.claude/.gitignore:85` → `plans/`) because how each engineer plans with Claude Code is personal. To preserve that planning content — which is high-value business intelligence — each engineer has a **separate personal git repo nested at `~/.claude/plans/`**, by convention `git@github.com:<github-username>/dot-claude-plans.git` (Paulo's is `plribeiro3000/dot-claude-plans`).

The problem: nobody is actually committing. **Right now Paulo's `plans` repo has 88 uncommitted changes** (`git -C ~/.claude/plans status --porcelain | wc -l` → `88`). The intelligence accumulates only in the working tree and is one disk failure away from being lost.

Three questions:

1. **(Simple)** A daily end-of-day job that does `git add` + `git commit` (no push) on `~/.claude/plans` — and produces **no commit when there is nothing to commit**.
2. **(Harder)** Ship it to Emerson and Leandro, and nudge an engineer — once per day — when the job is **not** active on their machine.
3. **(The complication)** The three engineers run **three different operating systems**, each with a different native scheduler:
   - **Paulo — macOS** → `launchd`
   - **Leandro — Ubuntu** → `systemd` user timer (or cron)
   - **Emerson — Windows + WSL** → the hard case: `~/.claude/plans` lives *inside* WSL, but WSL only runs while a session is open.

Implementation is a separate `dot-claude` PR (Configuration Changes Policy: never edit `~/.claude/` directly).

---

## Method

- Inspected the live state of `~/.claude/plans` (real git repo: remote `plribeiro3000/dot-claude-plans`, branch `main`, 88 dirty entries).
- Surveyed the existing SessionStart / UserPromptSubmit hook machinery for the "nudge once" and "once-per-day marker" patterns to reuse.
- Verified the macOS scheduler reality on Paulo's machine directly (`launchctl`, existing LaunchAgents).
- **Web-researched the two facts that cannot be checked from Paulo's machine**: systemd user-timer catch-up semantics (Ubuntu) and scheduling reliability inside WSL2 (Emerson).

No prototype built — design spike.

---

## Evidence

### Current state (Paulo's machine)

| Fact | Evidence |
|---|---|
| `plans/` is a nested personal git repo | `git -C ~/.claude/plans rev-parse --is-inside-work-tree` → `true` |
| Remote follows a per-user convention | `origin git@github.com:plribeiro3000/dot-claude-plans.git` |
| Branch | `main` |
| The problem is real and large | `git -C ~/.claude/plans status --porcelain | wc -l` → `88` |
| `plans/` excluded from `dot-claude` | `~/.claude/.gitignore:85` `plans/` |
| Commit identity set at repo level | `user.name = Paulo Ribeiro`, `user.email = plribeiro3000@gmail.com` |
| launchd already in use here | `~/Library/LaunchAgents/com.plribeiro3000.meeting-hive.plist` (label convention `com.<user>.*`) |

### Reusable hook patterns found

- **SessionStart nudge model** — `scripts/check-projects-folder.sh`: silent when healthy, prints a `=== WARNING ===` block when a precondition is missing.
- **Once-per-day marker** — `scripts/check-claude-version.sh`: `MARKER="/tmp/claude_version_check_$(date +%Y%m%d).done"`; touch on success, skip if present.

### Cross-OS scheduler reality (web-verified)

| OS / engineer | Native scheduler | Catch-up if machine was off/asleep at trigger | Caveat |
|---|---|---|---|
| **macOS — Paulo** | `launchd` LaunchAgent, `StartCalendarInterval` | **Yes** — runs at next wake | None; already in use here |
| **Ubuntu — Leandro** | `systemd --user` timer, `OnCalendar=` + `Persistent=true` | **Yes**, but a *single* catch-up activation, not one per missed day | Needs `loginctl enable-linger` to run without an open session |
| **Windows+WSL — Emerson** | cron / systemd **inside** WSL | **No** — WSL isn't running, so nothing fires | systemd "will NOT keep your WSL instance alive" |
| **Windows+WSL — Emerson (robust)** | **Windows Task Scheduler** → `wsl.exe -d <distro> bash <script>` | **Yes** — "run task as soon as possible after a missed start" | Scheduler lives Windows-side; script + repo stay WSL-side |

Verified findings:

- **systemd `Persistent=true` catches up a missed run, once.** "When the timer is activated, the service unit is triggered immediately if it would have been triggered at least once during the time when the timer was inactive" — and "Persistent=true catches up a missed calendar event with a single activation, not one activation per missed interval." User timers live in `~/.config/systemd/user/`; `loginctl enable-linger` lets them run when the user is not logged in. ([ArchWiki — systemd/Timers](https://wiki.archlinux.org/title/Systemd/Timers))
- **Inside WSL, a Linux-side scheduler is unreliable for a daily job.** "WSL's cron daemon stops when WSL shuts down, and WSL can shut down if Windows goes to sleep or you close all WSL terminals." Enabling systemd does not change this: "systemd services will NOT keep your WSL instance alive — your WSL instance will stay alive in the same way it did previous to this update." ([Microsoft Learn — systemd in WSL](https://learn.microsoft.com/en-us/windows/wsl/systemd), [HowToGeek](https://www.howtogeek.com/746532/how-to-launch-cron-automatically-in-wsl-on-windows-10-and-11/))
- **The WSL-robust path is Windows Task Scheduler driving `wsl.exe`.** A Windows-native scheduled task runs regardless of WSL state and boots the distro to run the script; it can keep WSL alive (`wsl.exe -d <distro> --exec sleep infinity` at startup) or just invoke the commit script on a daily trigger. ([XDA](https://www.xda-developers.com/automate-windows-with-wsl-cron/), [HowToGeek](https://www.howtogeek.com/746532/how-to-launch-cron-automatically-in-wsl-on-windows-10-and-11/))

---

## Conclusions

The cross-OS constraint does **not** fragment the design — it isolates the OS-specific part into a thin adapter. Split the system into **one OS-independent "what"** and **three thin "how" adapters**.

### The "what" — one shared, OS-independent commit script

`scripts/plans-autocommit.sh` in `dot-claude`, pure POSIX/bash, runs *identically* on macOS bash, Ubuntu bash, and WSL Ubuntu bash:

1. Guard: `~/.claude/plans/.git` exists; HEAD on `main`; not mid-rebase/merge. Else log + exit 0.
2. `git -C ~/.claude/plans status --porcelain` empty → exit 0 (**no empty commits**).
3. Else `git add -A` + `git commit -m "chore(plans): daily snapshot <YYYY-MM-DD>"` (no push).
4. Append one line to `~/.claude/plans/.autocommit.log` (git-ignored): timestamp + commit hash, or "no changes".

**Commit-message safety**: generic `daily snapshot <date>` carries no client/infra data, even though the *contents* are sensitive (No Client/Infra Data policy). Never template filenames/clients into the subject.

### The "how" — three thin scheduler adapters (the only OS-specific code)

| OS | Adapter artifact | Catch-up parity |
|---|---|---|
| macOS | LaunchAgent plist `com.4shark.plans-autocommit`, `StartCalendarInterval` at end-of-day | native |
| Ubuntu | `plans-autocommit.{timer,service}` in `~/.config/systemd/user/`, `OnCalendar=*-*-* HH:MM`, `Persistent=true`, + `enable-linger` | native (single catch-up) |
| WSL | Windows Task Scheduler task → `wsl.exe -d <distro> -u <user> bash -lc '~/.claude/scripts/plans-autocommit.sh'`, daily trigger + "run after missed start" | via Task Scheduler |

A single **install script** `scripts/install-plans-autocommit.sh` detects the OS (`uname`; WSL via `grep -qi microsoft /proc/version`) and branches to the right adapter. One entry point, three branches, idempotent.

**Commit-only fits Emerson best of all**: no push means no SSH agent/keychain has to cross the WSL→Windows boundary. The Task Scheduler path stays simple.

### The cross-OS constraint actually *improves* the nudge — make detection log-based

Three OSes mean three different "is the scheduler registered?" APIs (`launchctl list` / `systemctl --user is-active` / `schtasks.exe /query`). Instead of maintaining three detection branches, **detect health from the shared `.autocommit.log`**: "was there a successful snapshot in the last ~36h?" That single check is OS-independent and *also* catches the silent-failure case the scheduler-registration check misses (registered but broken). The OS-specific "is it installed?" check becomes a secondary nicety, not the primary signal.

`scripts/check-plans-autocommit.sh`, wired into SessionStart (model: `check-projects-folder.sh` + once-per-day marker from `check-claude-version.sh`):
1. Marker `/tmp/claude_plans_autocommit_check_$(date +%Y%m%d).done` — nudge at most once/day.
2. Guard: only when `~/.claude/plans/.git` exists with a `dot-claude-plans` remote.
3. Read `.autocommit.log`: last success within threshold → silent, touch marker. Stale or missing → nudge with the one-line install command, touch marker.

### Distribution

Normal `dot-claude` flow: shared script + OS-detecting install script + SessionStart check + settings.json wiring, all in one PR. After merge + `git pull`, each engineer runs the install script once; the nudge makes "run it once" unmissable.

### Known limitation to surface (not solved here)

**Commit-only ≠ off-machine backup.** `commit` without `push` preserves history *locally* only; until a manual push, the BI is still single-machine. Auto-push is feasible on macOS/Ubuntu (keychain/agent SSH) but adds the SSH-across-the-boundary complication on WSL. Out of the stated scope ("commit only") — flagged as a decision, not assumed. Mitigation if staying commit-only: the nudge can also remind to push weekly.

---

## Next Steps

Generates a **PLAN.md** for one `dot-claude` PR, pending engineer decisions:

1. **Per-OS schedulers** — confirm launchd (macOS) + systemd user timer (Ubuntu) + Windows Task Scheduler (WSL). *Recommended; WSL-internal cron/systemd rejected on the verified "WSL not alive" evidence.*
2. **Detection strategy** — log-based health check (OS-independent, recommended) vs three OS-specific scheduler-registration checks.
3. **Nudge cadence** — SessionStart once/day (recommended) vs persistent-until-fixed (like `check-claude-version.sh`).
4. **Push scope** — commit-only as stated (+ optional weekly push reminder) vs auto-push.

No code written in this spike — implementation is a separate PR per the Configuration Changes Policy.
