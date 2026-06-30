# PLAN — Daily auto-commit of each engineer's personal `plans` repo, cross-OS

> Derived from `~/.claude/plans/active/spike/plans-autocommit/SPIKE.md` (research + cross-OS verification).
> Implementation lands as a `dot-claude` PR — Configuration Changes Policy: never edit `~/.claude/` directly.

## Objective

Every engineer's personal planning repo at `~/.claude/plans/` (`git@github.com:<github-username>/dot-claude-plans.git`) accumulates high-value business intelligence in its working tree but is rarely committed (Paulo's currently has 88 uncommitted changes). Ship a daily end-of-day job that commits the working tree (no push, no empty commits) on all three engineers' machines, plus a once-a-day SessionStart nudge when the job is not running — so planning data is never silently lost.

## Scope

### In scope
- One OS-independent commit script + a git-ignored health log.
- One OS-independent SessionStart nudge driven by the health log.
- macOS scheduler adapter (launchd) — **validated, ships active**.
- Ubuntu scheduler adapter (systemd user timer) — **validated, ships active**.
- WSL scheduler adapter (Windows Task Scheduler) — **best-guess design, ships as DRAFT for Emerson to validate/correct**.
- An OS-detecting install entry point that dispatches to the right adapter.
- `settings.json` SessionStart wiring for the nudge.

### Out of scope
- `git push` / off-machine backup (engineer-stated: commit only). Optional weekly push *reminder* allowed in the nudge; auto-push is not built.
- Any change to the `dot-claude-plans` repos themselves.
- Linux distros other than Ubuntu (systemd assumed; revisit only if a non-systemd machine appears).

## Chosen approach

**Direction:** one shared, OS-independent "what" (commit script + nudge) + three thin per-OS "how" adapters (schedulers), behind a single OS-detecting install script.

**Rationale (from engineer):** "a gente vai implementar"; commit-only ("não precisa fazer o push, pode só fazer o commit"); and the Windows/WSL adapter goes in as our best guess but **structured so that Emerson — the only one with a Windows+WSL environment — can correct it on pull and update the Windows install documentation accordingly**.

**Source patterns referenced (Pattern Priming targets at `/execute` time):**
- `scripts/check-projects-folder.sh` — SessionStart "silent when healthy, WARNING block when not" shape.
- `scripts/check-claude-version.sh` — once-per-day `/tmp/..._$(date +%Y%m%d).done` marker; SessionStart wiring.
- Existing LaunchAgent on Paulo's machine `~/Library/LaunchAgents/com.plribeiro3000.meeting-hive.plist` — launchd label/plist shape.

## Execution phases

### Phase 1: Shared OS-independent core (validated, all three OSes)

**Objective:** the commit logic and the health signal, identical on macOS / Ubuntu / WSL Ubuntu bash.

**Components:**
- `scripts/plans-autocommit.sh`: guard (`~/.claude/plans/.git` exists; HEAD on `main`; not mid-rebase/merge) → if `git -C ~/.claude/plans status --porcelain` empty, exit 0 (no empty commit) → else `git add -A` + `git commit -m "chore(plans): daily snapshot <YYYY-MM-DD>"` (no push) → append one line to `~/.claude/plans/.autocommit.log` (timestamp + commit hash, or "no changes").
- Add `.autocommit.log` to `~/.claude/plans/.gitignore`.

**Success criteria:**
- [ ] Running the script with a dirty tree produces exactly one commit and one log line; running it again clean produces no commit and a "no changes" log line.
- [ ] Commit subject carries no client/infra data (No Client/Infra Data policy).

### Phase 2: SessionStart nudge (validated, OS-independent — log-based)

**Objective:** nudge once/day when the job is not keeping the repo committed — using the shared log, so no per-OS scheduler API is queried.

**Components:**
- `scripts/check-plans-autocommit.sh`: once-per-day marker `/tmp/claude_plans_autocommit_check_$(date +%Y%m%d).done`; guard (only when `~/.claude/plans/.git` exists with a `dot-claude-plans` remote); read `.autocommit.log` — last success within ~36h → silent + touch marker; stale/missing → print WARNING block with the one-line install command (and optional "consider pushing this week") + touch marker.
- Wire into `settings.json` SessionStart (model: `check-projects-folder.sh`).

**Success criteria:**
- [ ] No log / stale log → nudge fires once, then silent for the rest of the day.
- [ ] Fresh log → silent.
- [ ] Works identically on all three OSes (no scheduler-specific calls).

### Phase 3: macOS adapter — launchd (validated, ships active)

**Components:**
- LaunchAgent plist, fixed label `com.4shark.plans-autocommit`, `StartCalendarInterval` at the chosen end-of-day hour, calling `plans-autocommit.sh`; catch-up on wake is native.

**Success criteria:**
- [ ] `launchctl` shows the agent loaded; it fires at the scheduled time and after a missed wake; `.autocommit.log` updates.

### Phase 4: Ubuntu adapter — systemd user timer (validated, ships active)

**Components:**
- `plans-autocommit.service` + `plans-autocommit.timer` for `~/.config/systemd/user/`, `OnCalendar=*-*-* HH:MM`, `Persistent=true` (single catch-up on a missed run); install enables the timer and runs `loginctl enable-linger <user>` so it fires without an open session.

**Success criteria:**
- [ ] `systemctl --user is-active plans-autocommit.timer` is active; a missed run is caught up once on next activation; `.autocommit.log` updates.

### Phase 5: WSL adapter — Windows Task Scheduler — **DRAFT, owned by Emerson**

**Objective:** schedule the commit from the Windows side (the only reliable place — a Linux-side scheduler inside WSL does not fire when WSL is shut down; verified in the SPIKE). This phase ships as our **best guess**, explicitly flagged for Emerson to validate and correct on a real Windows+WSL machine.

**Components (best-guess, to be validated):**
- A Windows Task Scheduler task (daily trigger + "run task as soon as possible after a missed start") whose action is `wsl.exe -d <distro> -u <user> bash -lc '~/.claude/scripts/plans-autocommit.sh'`.
- `docs/WINDOWS-PLANS-AUTOCOMMIT-INSTALL.md` — **DRAFT** install/validation guide (how to register the task: `schtasks.exe` command or the GUI steps), to be completed and corrected by Emerson.

**Containment (so Emerson's correction is isolated and the rest is unaffected):**
- The WSL branch of the install script does **not** silently register a possibly-wrong task. On detecting WSL it prints: *"WSL adapter is DRAFT and unvalidated — follow `docs/WINDOWS-PLANS-AUTOCOMMIT-INSTALL.md`, validate, then correct this branch and the doc via a follow-up PR."* It does not fail; it defers.
- The shared core (Phases 1–2) already works on Emerson's machine: the commit script runs by hand and the nudge will (correctly) keep nudging him until the scheduler is genuinely active — which is the desired behavior while the adapter is DRAFT.

**Success criteria (owned by Emerson, in a follow-up PR):**
- [ ] Task Scheduler entry fires daily on a real Windows+WSL machine and updates `.autocommit.log`.
- [ ] The DRAFT marker is removed from the install-script WSL branch and from `WINDOWS-PLANS-AUTOCOMMIT-INSTALL.md`; the doc reflects the actually-working steps.

### Phase 6: OS-detecting install entry point

**Components:**
- `scripts/install-plans-autocommit.sh`: detect OS (`uname`; WSL via `grep -qi microsoft /proc/version`) → dispatch to the macOS / Ubuntu / WSL-DRAFT branch. Idempotent (re-running re-syncs the adapter without duplicating it).

**Success criteria:**
- [ ] On macOS installs the LaunchAgent; on Ubuntu installs+enables the timer; on WSL prints the DRAFT-deferral message.

## Technical decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Push scope | **Commit only**, no push | Engineer-stated ("pode só fazer o commit"); push needs interactive permission. Off-machine backup left as a manual/weekly action; nudge may remind. |
| Per-OS schedulers | launchd (macOS) / systemd user timer (Ubuntu) / Windows Task Scheduler (WSL) | SPIKE-verified: a scheduler inside WSL does not fire when WSL is down ("systemd services will NOT keep your WSL instance alive"). |
| Nudge detection | **Log-based** (read `.autocommit.log`), not per-OS scheduler queries | One OS-independent check; also catches "installed but broken", which a registration check misses. |
| Nudge cadence | **Once per day** at SessionStart | A convenience, not a safety block; reversible to persistent later if needed. |
| LaunchAgent / task label | Fixed `com.4shark.plans-autocommit` (engineer-independent) | Uniform across machines; would also allow an OS-specific registration check as a secondary signal if ever wanted. |
| Windows adapter delivery | **Ships as DRAFT, Emerson validates & corrects** | Only Emerson has a Windows+WSL environment to validate against; isolated so his fix is contained and the rest ships now. |

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| WSL adapter unvalidated at first merge | Med | Ships DRAFT; install script defers instead of registering a wrong task; nudge keeps reminding Emerson until he activates it; correction is a contained follow-up PR. |
| Commit-only = local-only backup | Med | Accepted per stated scope; optional weekly push reminder in the nudge; auto-push deferrable later. |
| systemd single catch-up (not per missed interval) | Low | Daily snapshot only needs "commit today's changes once" — single catch-up is sufficient. |
| Implementation drifts from `scripts/` conventions | Low | `/execute` applies Pattern Priming against `check-projects-folder.sh` / `check-claude-version.sh` before writing. |
| A Claude session writes `plans` exactly as the job commits | Low | `git add -A` is effectively atomic for this use; accepted. |

## Assumptions

- All three engineers keep `~/.claude/plans/` as a git repo on the `dot-claude-plans` per-user convention, branch `main`.
- Ubuntu and WSL-Ubuntu both have systemd available; bash is the shell on all three.
- The personal repos already have commit identity configured (Paulo's does, at repo level).

---

> **Authoring:** composed by the main session from the validated SPIKE plus the engineer's explicit direction (promote to plan; implement; ship the Windows adapter as a correctable DRAFT owned by Emerson). Implementation is a separate `dot-claude` PR; scripts get Pattern Priming at `/execute` time.
