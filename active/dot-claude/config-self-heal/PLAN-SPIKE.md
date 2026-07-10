# PLAN-SPIKE — Config Self-Heal (Daily `~/.claude` Reset + Fast-Forward Pull)

> Reference: no DDD documents exist for this feature (standard workflow). Scope, constraints, and
> several design decisions arrived pre-confirmed from the engineer (see the fixed-constraints list
> below); this draft researches the remaining open sub-decisions.
>
> Auxiliary files: `existing-logic_excerpt_1.md` (full verbatim excerpts backing every codebase
> citation below), `file-inventory_table_1.md` (full file inventory).

## Objective

The installed `~/.claude` config repo accumulates a daily nuisance: the Claude Code app rewrites
`settings.json` on its own (reorders keys, re-injects three personal-pref keys), which leaves the
working tree dirty and blocks any subsequent `git pull` until something resets it. Today that reset
only happens as a side effect of `check-claude-version.sh`, which runs on `SessionStart` /
`UserPromptSubmit` — i.e. only when a session happens to be open, and gated to once per calendar day
by its own marker. A daily, session-independent routine would detect the app's reformat, discard
*only* that reformat (never a real engineer edit), and fast-forward-pull `~/.claude` to `origin`, so
the config repo self-heals without depending on a live session to trigger it.

## Scope

### In scope

- A new daily script (the "what") that: detects a pure `settings.json` app-reformat vs a real
  content change, discards only the pure reformat, surfaces/preserves a real change instead of
  silently discarding it, then runs `git pull --ff-only` on `master`/`develop` only.
- A new per-OS installer (the "how") mirroring `setup-plans-autocommit.sh` — launchd (macOS),
  systemd user timer (Linux), Windows Task Scheduler (WSL).
- The design decision of whether this logic is extracted into a helper shared with
  `check-claude-version.sh`, or duplicated (Sub-decision A).
- Coordination with `check-claude-version.sh`'s existing once-a-day marker so the two mechanisms do
  not thrash `~/.claude` with overlapping pulls (Sub-decision B).
- What the cron does, specifically, when it finds a REAL (non-reformat) `settings.json` change —
  since it has no session to surface into the way `check-claude-version.sh` does (Sub-decision C).
- The reset scope — confirming whether anything beyond `settings.json` is a legitimate reset target
  (Sub-decision D).
- Naming for the new script + installer (Sub-decision F).
- Full file inventory (see `file-inventory_table_1.md`) and the dot-claude PR execution outline.

### Out of scope (open question)

- Fixing the residual gap where a MANUAL `git -C ~/.claude pull` (e.g. `/merge-cleanup`'s final step)
  run *between* cron ticks can still hit the same dirty-tree failure the daily cron is built to
  prevent. This is documented as a known limitation (Sub-decision E / Risks), not solved here — the
  engineer did not ask for it, and Scope Discipline treats it as a Blocker candidate only if the
  engineer decides it must be fixed now.
- A parallel freshness-nudge script for config-self-heal (the `check-plans-autocommit.sh` analog,
  which warns once/day if the plans repo hasn't been snapshotted). Not requested; flagged as a
  possible follow-up, not assumed into scope.

## Existing logic — what `check-claude-version.sh` already does

Full excerpts in `existing-logic_excerpt_1.md` § 1. Summary, with citations:

1. **Guard: repo + branch.** Runs only when `~/.claude/.git` exists and the current branch is
   `master` or `develop` (`check-claude-version.sh:38-42`).
2. **Once-a-day marker.** `MARKER="/tmp/claude_version_check_$(date +%Y%m%d).done"`
   (`check-claude-version.sh:36`); the run exits immediately if today's marker already exists
   (`check-claude-version.sh:89`). The marker is touched only on the two success paths (tag already
   current, or pull succeeded) — never on a failure/notice path.
3. **Reformat detection — `capture_settings_drift`** (`check-claude-version.sh:231-247`). Normalizes
   both the working-tree `settings.json` and `HEAD:settings.json` with
   `jq -S 'del(.theme, .inputNeededNotifEnabled, .agentPushNotifEnabled)'` — recursive key sort
   neutralizes reordering, and the `del(...)` drops the three app-managed personal-pref keys before
   comparing. If the normalized forms match, nothing is captured (pure reformat, `settings_drift`
   stays empty). If they differ, the real diff is captured into `${settings_drift}`.
4. **Reset gate — `attempt_auto_pull`** (`check-claude-version.sh:249-292`). The reset trigger is an
   **exact string match** on the full `git status --porcelain=v1` output:
   `status == " M settings.json"`. Any other dirty/untracked path (even alongside a dirty
   `settings.json`) makes the whole run `skipped_dirty` — nothing is reset. When the exact-match
   condition holds, it calls `capture_settings_drift` FIRST (so a real change is captured before
   being discarded), then `git checkout -- settings.json`, then `git pull --ff-only --quiet origin
   "${branch}"`.
5. **Surfacing a real change** (`check-claude-version.sh:296-316`). If `${settings_drift}` is
   non-empty, a block is printed instructing Claude's NEXT chat response to show the engineer exactly
   what was reset (diff included) and where each kind of change belongs (shared config → dot-claude
   PR; personal prefs → `settings.local.json`). This is a session/chat-channel mechanism — it has no
   equivalent surface when no session is open.

**Nuance for scope (Sub-decision D):** the current logic never resets or even inspects any file other
than `settings.json`. A `git ls-files | grep -iE '\.env|settings'` against the `dot-claude` repo
returns only `settings.json` and `settings.local.example.json` — no `.env`-shaped file is tracked at
all (`settings.local.json` itself is git-ignored, `~/.claude/.gitignore:71`). See
`existing-logic_excerpt_1.md` § 4 for the raw command output.

## Scheduler mechanics to mirror — `setup-plans-autocommit.sh` / `plans-autocommit.sh`

Full excerpts in `existing-logic_excerpt_1.md` §§ 2–3. Summary:

- **OS detection order**: WSL is checked FIRST via `grep -qiE 'microsoft|wsl' /proc/version`
  (`setup-plans-autocommit.sh:35`) — necessary because WSL is Linux but needs the Windows-side
  scheduler, so the generic Linux branch must not shadow it.
- **macOS**: writes a `launchd` `LaunchAgent` plist to
  `~/Library/LaunchAgents/com.4shark.<name>.plist` with `StartCalendarInterval` (Hour/Minute),
  `StandardOutPath`/`StandardErrorPath` to `/tmp/`; idempotency via `launchctl bootout` (ignore
  failure) then `launchctl bootstrap` (`setup-plans-autocommit.sh:46-77`).
- **Linux**: writes a `systemd --user` `.service` (`Type=oneshot`) + `.timer`
  (`OnCalendar=*-*-* HH:MM:00`, `Persistent=true` for missed-run catch-up) to
  `~/.config/systemd/user/`; `systemctl --user daemon-reload` +
  `systemctl --user enable --now <timer>`; best-effort `loginctl enable-linger` so the timer fires
  without an open login session (`setup-plans-autocommit.sh:79-108`).
- **WSL**: registers a Windows Task Scheduler task via `schtasks.exe /create ... /f` (force =
  idempotent overwrite) whose trigger command re-enters WSL:
  `wsl.exe -d ${WSL_DISTRO_NAME} -u ${USER} bash -lc '<script>'`
  (`setup-plans-autocommit.sh:110-114`).
- **Unsupported OS**: prints a message and exits 1 — no scheduler installed
  (`setup-plans-autocommit.sh:116-120`).
- **Seed run**: the installer runs the "what" script once at the very end, so the install is verified
  end-to-end immediately rather than waiting for the first scheduled trigger
  (`setup-plans-autocommit.sh:141-143`).
- **`plans-autocommit.sh` structural pattern** to mirror for the new "what" script: a header comment
  block explaining purpose/behavior/idempotency, `set -uo pipefail`, a `log_line()` helper writing
  `epoch  human-time  message` lines, then a strict guard chain (repo exists → correct branch →
  not mid-rebase/merge → do the actual work), each guard `log_line`-ing why it skipped
  (`plans-autocommit.sh:1-64`).

## Candidate approaches — Sub-decision A: shared helper vs duplicated logic

The central architectural fork: `check-claude-version.sh` already implements
detect-reformat → reset → `--ff-only` pull. The new daily script needs the same three steps. Do they
share one implementation, or does the new script carry its own copy?

### Option A: Extract a shared helper

**Approach summary:** Move `capture_settings_drift` and the reset step out of
`check-claude-version.sh` into a small sourced library (e.g.
`scripts/lib/claude-config-reset.sh`, exact naming per Sub-decision F), exposing something like
`claude_config_reset_settings_if_pure_reformat()` that both `check-claude-version.sh` and the new
daily script `source` and call. Each caller keeps its own surrounding flow (marker gating, branch
guard, pull invocation, notice-printing) — only the detect+reset step is shared.

**Pros:**
- Single source of truth for the `jq -S` normalization + the three-key drop list
  (`del(.theme, .inputNeededNotifEnabled, .agentPushNotifEnabled)`,
  `check-claude-version.sh:239`) — if the app ever adds a fourth personal-pref key, one edit fixes
  both callers.
- Removes the risk of the two scripts silently drifting apart on what counts as a "pure reformat"
  (e.g. one script's drop-list gets updated, the other doesn't, and a report of "real change" differs
  between the session-triggered check and the daily cron for the identical working-tree state).

**Cons:**
- `~/.claude/docs/NO-PREMATURE-DRY.md` sets the bar for extraction at "10+ repetitions,
  stable pattern, clear use cases for all consumers, actual pain from duplicates" — with this change
  there are exactly **2** call sites, both introduced/touched in the same PR, and the "pain from
  maintaining duplicates" has not yet been observed (it is hypothetical, pre-emptive). The doc is
  explicit: *"2 repetitions: ❌ Too early - Keep repeating"* and *"Duplication is FAR Better Than Wrong
  Abstraction"* (`NO-PREMATURE-DRY.md:65, 70`). Counter-consideration: the two callers are the ONLY
  consumers this abstraction would ever need to serve, and the boundary itself (one function:
  normalize + diff + checkout) is narrow enough to state in a single sentence — the kind of case
  `NO-PREMATURE-DRY.md` separately warns is worse to get wrong ("Wrong abstraction is WORSE than
  duplication", line 235) than to duplicate. The doc's repetition-count bar and this narrow-boundary
  observation point in opposite directions here — a genuine trade-off, not a clean-cut answer.
- Introduces a new file kind (`scripts/lib/`) with no existing precedent in `~/.claude/scripts/` —
  every current script there is a standalone, directly-invoked shell script; a sourced-only library
  file is a new shape the repo does not currently have.
- Touches `check-claude-version.sh` (an already-shipped, hook-wired script) as part of this feature,
  which is a wider diff than "add two new files" — increases review surface and regression risk on a
  script that already has a documented incident history around auto-pull correctness (CHANGELOG
  `### Changed` entry: "Config version check now auto-updates at session start instead of only
  notifying").

**Cost / effort:** higher — requires refactoring and re-verifying `check-claude-version.sh`'s
existing behavior is unchanged (no regression on the SessionStart/UserPromptSubmit hook path),
in addition to writing the two new files.

**Risk:** a refactor of a hook-wired script carries deploy risk to every open session (the hook fires
on every `SessionStart`/`UserPromptSubmit` across the team) — a bug introduced during extraction
surfaces immediately and broadly, not just in the new cron path.

**Source patterns referenced:**
- `check-claude-version.sh:231-247` — the function that would be extracted
- `~/.claude/docs/NO-PREMATURE-DRY.md:61-68` — the Rule of Three / 10+ repetitions bar
- See auxiliary: `existing-logic_excerpt_1.md` § 1.3–1.4 — full extraction candidate code

### Option B: Duplicate the detect+reset+pull logic in the new script

**Approach summary:** The new daily script re-implements its own version of reformat-detection,
reset, and `--ff-only` pull, self-contained — following the exact structural pattern
`plans-autocommit.sh` already uses (guard chain, `log_line`, no external sourcing). No change to
`check-claude-version.sh` at all.

**Pros:**
- Matches the existing precedent exactly — `plans-autocommit.sh` is fully self-contained (no
  `source` of any shared file exists anywhere in `~/.claude/scripts/` today per the codebase read
  during this research), so duplication is the path with zero new structural precedent to justify.
- Zero risk to `check-claude-version.sh` — the already-shipped, hook-wired script is untouched,
  so there is no regression surface on the SessionStart/UserPromptSubmit path.
- Smaller, more reviewable diff — two new files, no refactor of existing code.
- Aligns with `NO-PREMATURE-DRY.md`'s explicit guidance for exactly this repetition count (2 call
  sites): *"Keep repeating!"* until it "ACTUALLY hurts" (10+ repetitions).

**Cons:**
- The `jq -S` normalization + drop-list becomes two copies; if the app changes its rewrite behavior
  (a fourth personal-pref key, say) both copies need the same fix, and nothing enforces that they're
  kept in sync.
- Two independently-evolving definitions of "pure reformat" could, in principle, diverge and produce
  different verdicts on the identical working-tree state (session check says "real change", daily
  cron says "pure reformat", or vice versa) — a correctness risk specific to this domain (the
  question is exactly "should this be reset or not", so disagreement between the two checkers is a
  data-loss/surfacing-failure risk, not a cosmetic one).

**Cost / effort:** lower — additive only, no refactor of shipped code.

**Risk:** the divergence risk above is real but bounded — both copies derive from the same
documented mechanics (`capture_settings_drift`), and the PR reviewer can diff the two
implementations line-by-line at merge time.

**Source patterns referenced:**
- `plans-autocommit.sh:1-91` (full file) — the self-contained, no-shared-lib precedent
- `~/.claude/docs/NO-PREMATURE-DRY.md:14-30, 61-68` — supports this option at the current repetition
  count
- See auxiliary: `existing-logic_excerpt_1.md` § 3 — full structural excerpt

## Sub-decision B: coordinating two `~/.claude` pull mechanisms

Once the daily cron exists, TWO independent mechanisms pull `~/.claude`: the existing
session-triggered `check-claude-version.sh` (gated by `/tmp/claude_version_check_<date>.done`,
`check-claude-version.sh:36`) and the new daily cron (triggered by the OS scheduler at a fixed
time, independent of any session). Options, not decided here:

- **Option 1 — Separate markers, no coordination.** The daily cron uses its own marker (or none —
  it is inherently once-per-scheduled-tick already, unlike the session hook which can fire many
  times a day). Both mechanisms attempt the reset+pull independently; whichever runs second finds
  the tree already clean/up to date and no-ops harmlessly (a `git pull --ff-only` when already
  current is a no-op, and a clean tree makes `capture_settings_drift`'s comparison trivially match).
  Simple, but two separate scheduled/triggered code paths hit the same repo without awareness of
  each other.
- **Option 2 — Shared marker.** The daily cron checks/sets the SAME
  `/tmp/claude_version_check_<date>.done` marker `check-claude-version.sh` uses, so whichever runs
  first "claims" the day and the second is a pure skip. Reduces duplicate work, but couples the two
  mechanisms' semantics (the marker's name and meaning currently belong to
  `check-claude-version.sh`'s version-check concern specifically, not to "was `~/.claude` reset
  today" generically) — repurposing it changes what the marker means without renaming it.
- **Option 3 — Daily cron subsumes the session check's pull duty.** The daily cron becomes the
  sole owner of the reset+pull mechanics; `check-claude-version.sh` keeps its own version-comparison
  and notice logic but calls into the (now-shared, per Sub-decision A Option A) reset+pull helper
  rather than re-implementing it, OR is left as today's independent safety net for the case where a
  machine's scheduler is not installed/broken. This option only cleanly composes with Sub-decision A
  Option A (shared helper) — under Option B (duplicated logic) "subsuming" would mean deleting
  functionality from `check-claude-version.sh`, which changes its existing, already-shipped
  behavior beyond what the engineer's brief authorized.

No option above causes a race in the git-operation sense (git itself serializes concurrent
operations on the same working tree via `.git/index.lock`); the concern is redundant work and
marker-semantics coupling, not corruption.

## Sub-decision C: real-change handling in a non-interactive cron

`check-claude-version.sh`'s surfacing mechanism (`check-claude-version.sh:296-316`) works by
instructing Claude's NEXT chat response to show the engineer the diff — this requires a live session.
A cron has none. Options, not decided here — **the one invariant that holds across all of them: the
cron must NEVER discard a real (non-reformat) change**, mirroring
`check-claude-version.sh`'s own exact-match gate (`status == " M settings.json"` only, else
`skipped_dirty`, `check-claude-version.sh:274-284`):

- **Option 1 — Skip the pull, log only.** When a real (non-pure-reformat) diff is detected, the
  cron does nothing further this run (no reset, no pull) and appends a line to its own log
  (mirroring `plans-autocommit.sh`'s `log_line` pattern, `plans-autocommit.sh:38-41`) — e.g.
  `real settings.json drift detected, skipping reset+pull`. The next session-triggered
  `check-claude-version.sh` run still handles it normally the way it does today. Simplest; relies
  entirely on the existing session mechanism to eventually surface it (no new surfacing channel).
- **Option 2 — Write a marker file the next session surfaces.** The cron writes a sentinel (e.g.
  `/tmp/claude_config_real_drift_<date>` or a note file under `~/.claude/`) containing the captured
  diff; a NEW check (either added to `check-claude-version.sh` or a new small hook script) reads
  that sentinel at next `SessionStart`/`UserPromptSubmit` and surfaces it via `additionalContext`,
  same shape as `check-claude-version.sh:296-316` does today. More proactive (guarantees the
  engineer sees it at the very next session, even if `check-claude-version.sh` itself has nothing
  new to report that day, e.g. tag already current) but adds a new hook-touching surface and a new
  file kind under `~/.claude/`.
- **Option 3 — OS-native notification.** The cron fires a desktop notification (`osascript`
  on macOS, `notify-send` on Linux — no clean WSL equivalent surfaced in this research) when real
  drift is found. Immediate, session-independent visibility, but platform-fragmented (three
  different mechanisms, one of which — WSL — has no obvious analog), and outside the pattern either
  `check-claude-version.sh` or `plans-autocommit.sh` currently use (neither sends OS notifications
  today; not researched further here — flagging as unresearched rather than asserting either way).

## Sub-decision D: scope of what gets reset

Confirmed by codebase read (`existing-logic_excerpt_1.md` § 4): the `dot-claude` repository tracks
exactly two files matching `settings|\.env` — `settings.json` and `settings.local.example.json`.
`settings.local.example.json` is a static example file with no app-rewrite behavior documented
anywhere in the codebase (`check-claude-version.sh` never references it). No `.env`-shaped file is
tracked at all; `settings.local.json` (the actual personal-prefs file) is git-ignored
(`~/.claude/.gitignore:71`) and therefore never appears in `git status --porcelain` as a tracked-file
diff in the first place — it cannot be a reset target because git has no committed version to reset
it TO.

This narrows the question to: does the new script reset ONLY `settings.json` (mirroring
`check-claude-version.sh`'s current exact-match scope), or does it generalize to "any tracked file
whose ONLY diff from `HEAD` is a normalizable no-op" (a broader mechanism that would apply to
`settings.json` today but could, in principle, cover a future app-rewritten tracked file without a
second engineer request)? Options:

- **Option 1 — `settings.json`-only, exact-match, mirroring today's logic exactly.** Simplest, zero
  new surface, matches the ONLY documented app-rewrite behavior
  (§ Configuration Changes Policy: *"the app's own `settings.json` rewrite"*). No other tracked file
  is known to be app-mutated.
- **Option 2 — Generalize to "any tracked file, normalized-diff-empty."** Would require defining a
  normalization rule per file type (the `jq -S` + drop-list approach is `settings.json`-specific/JSON
  -specific; a different tracked file format would need its own normalizer) — over-engineering for a
  problem that has exactly one known instance today. Not grounded in any evidence of a second
  app-mutated file.

## Naming proposals (Sub-decision F)

Mirroring the `plans-autocommit.sh` / `setup-plans-autocommit.sh` naming shape
(`<subject>-<verb>.sh` for the "what", `setup-<subject>-<verb>.sh` for the installer):

| Candidate pair | Notes |
|---|---|
| `config-self-heal.sh` / `setup-config-self-heal.sh` | Matches the engineer's own naming for the feature ("config-self-heal"); reads as a single self-contained concern |
| `claude-config-reset.sh` / `setup-claude-config-reset.sh` | Emphasizes the reset mechanic over the "self-heal" framing; closer to the existing `capture_settings_drift`/reset vocabulary already in `check-claude-version.sh` |
| `claude-config-autoheal.sh` / `setup-claude-config-autoheal.sh` | Parallels "autocommit" (`plans-autocommit.sh`) directly — "auto-" prefix instead of "self-" |

If Sub-decision A resolves to Option A (shared helper), the helper file itself needs a name distinct
from the "what" script — e.g. `lib/claude-config-reset.sh` (function:
`claude_config_reset_settings_if_pure_reformat`) — see `file-inventory_table_1.md` for the proposed
path.

The LaunchAgent label (macOS), the systemd unit basename (Linux), and the `schtasks.exe` task name
(WSL) would each mirror whichever "what" script name is chosen, following
`setup-plans-autocommit.sh`'s pattern exactly: `LABEL="com.4shark.<name>"`
(`setup-plans-autocommit.sh:22`), `${systemd_dir}/<name>.service` /
`.timer` (`setup-plans-autocommit.sh:82,90`), `schtasks.exe /tn "<name>"`
(`setup-plans-autocommit.sh:112`).

## File inventory

Full table in `file-inventory_table_1.md`. Summary: 2–3 new script files (2 under Option B, 3 under
Option A of Sub-decision A), edits to `CLAUDE.md` (§ Configuration Changes Policy + § Repository
Structure), a `CHANGELOG.md` `[Unreleased]` entry, a `settings.json` `permissions.allow` addition for
the new installer's two invocation forms, and an open question on whether `README.md` gets its
first-ever installer note (no precedent — `setup-plans-autocommit.sh` itself has none there either).

## Risks (cross-cutting)

| Risk | Impact | Possible mitigation |
|------|--------|---------------------|
| Discarding a REAL settings.json change (data loss of an engineer's own local edit) | High — the engineer loses uncommitted config work with no session present to surface/preserve it before the reset | The exact-match gate (`status == " M settings.json"` and normalized-diff-empty) is the existing safety mechanism (`check-claude-version.sh:274-284`) and must be preserved bit-for-bit (or via the shared helper) in whichever option is chosen; Sub-decision C's answer determines HOW a detected real change is preserved for later surfacing rather than silently lost |
| Double-pull thrash / marker-semantics coupling between the session check and the daily cron | Low-to-medium — redundant `git fetch`/`pull` calls, or a repurposed marker whose name no longer matches its meaning | Sub-decision B — pick the coordination model deliberately; do not silently repurpose `check-claude-version.sh`'s marker without renaming or documenting the new shared meaning |
| Residual gap: a MANUAL `git -C ~/.claude pull` between cron ticks still fails the same way | Medium — this is the exact failure mode reported "3x today"; `/merge-cleanup`'s final step runs a bare `git -C ~/.claude pull` with no reset, no `--ff-only` (`~/.claude/commands/merge-cleanup.md:227`, quoted in `existing-logic_excerpt_1.md` § 5) | Explicitly out of scope per the engineer's brief (see § Out of scope) — flagged here as a known limitation only. The alternative noted but not pursued: route `/merge-cleanup`'s manual pull through the same safe reset mechanism this feature builds |
| Extraction risk if Sub-decision A resolves to Option A | Medium — refactoring a hook-wired, already-shipped script (`check-claude-version.sh`) touches the SessionStart/UserPromptSubmit path live for every open session | Careful before/after behavior verification if Option A is chosen; Option B avoids this risk entirely by construction |
| `settings.json` `permissions.allow` matcher is invocation-form-specific | Low — a missed second entry (`$HOME` vs `~` prefix) means the installer prompts for approval on one invocation form | Mirror both lines exactly as `setup-plans-autocommit.sh`'s precedent does (`settings.json:519-520`) |

## Open questions for the engineer

- Sub-decision A: extract a shared helper, or duplicate the detect+reset+pull logic in the new
  script? (Trade-off: correctness-sync risk + new file-kind precedent vs. refactor/regression risk to
  an already-shipped hook script.)
- Sub-decision B: how should the daily cron coordinate with `check-claude-version.sh`'s existing
  once-a-day marker — separate, shared, or subsumed?
- Sub-decision C: what should the cron do, specifically, when it finds a REAL (non-reformat)
  `settings.json` change — skip+log, write a marker for the next session to surface, an OS
  notification, or something else?
- Sub-decision D: confirm the reset scope stays `settings.json`-only (Option 1) — no evidence of a
  second app-mutated tracked file was found.
- Sub-decision F: which naming pair for the new script + installer (and, if Option A, the shared
  helper)?
- README.md: does this feature get the first-ever README installer note, or follow the existing
  precedent of documenting the installer only in `CLAUDE.md` (as `setup-plans-autocommit.sh` does
  today)?
- Confirmed out of scope unless the engineer says otherwise: the residual manual-pull gap
  (`/merge-cleanup`'s `git -C ~/.claude pull`) and a parallel freshness-nudge script.

## Suggested execution outline (once the engineer has chosen)

This is a config change and goes through the standard dot-claude PR workflow per
§ Configuration Changes Policy (`~/.claude/CLAUDE.md:496-505`) — never edited at `~/.claude/`
directly:

1. `cd ~/Projects/4Shark/dot-claude` (the working copy, not the installed `~/.claude`)
2. Create a worktree + feature branch off `develop` per the Worktree Policy
3. Write the new script(s) per the chosen Sub-decision A/B/C/D/F answers
4. Update `CLAUDE.md` § Configuration Changes Policy + § Repository Structure, `CHANGELOG.md`
   `[Unreleased]`, `settings.json` `permissions.allow`, and `README.md` if the engineer opts in
5. `/test`-equivalent for shell scripts: `bash -n <script>` syntax check at minimum (no existing
   shell-test harness was found for `~/.claude/scripts/` during this research — not asserting one
   exists)
6. Commit, push, open PR against `develop` (per Work Through to the Pull Request)
7. After merge, the engineer runs the new installer once per machine, exactly like
   `setup-plans-autocommit.sh`'s documented one-time install step (§ Plans Repository Auto-Commit,
   `~/.claude/CLAUDE.md:282-288`)

This outline is provided for orientation only — the actual TASKS.md decomposition is
`task-researcher`'s job after `PLAN.md` is composed, per the standard two-agent pipeline.

## Sources

- `~/.claude/scripts/check-claude-version.sh` (364 lines, read in full) — the existing
  detect+reset+pull+marker+notice mechanics; see `existing-logic_excerpt_1.md` § 1 for verbatim
  excerpts of every cited range
- `~/.claude/scripts/setup-plans-autocommit.sh` (144 lines, read in full) — the per-OS scheduler
  installer pattern to mirror; see `existing-logic_excerpt_1.md` § 2
- `~/.claude/scripts/plans-autocommit.sh` (91 lines, read in full) — the OS-independent "what"
  script structural pattern to mirror; see `existing-logic_excerpt_1.md` § 3
- `~/.claude/.gitignore:71` — `settings.local.json` is git-ignored
- `~/.claude/commands/merge-cleanup.md:222-230` — the residual manual-pull gap citation (Sub-decision
  E / Risks); see `existing-logic_excerpt_1.md` § 5
- `~/.claude/settings.json:519-520` — the two-invocation-form `permissions.allow` precedent for an
  installer script; see `existing-logic_excerpt_1.md` § 6
- `~/.claude/docs/NO-PREMATURE-DRY.md` (full doc read) — grounds the Option A vs Option B trade-off
  in § Candidate approaches, specifically lines 14-30 ("When NOT to DRY") and 61-68 (Rule of Three)
- `~/.claude/CLAUDE.md` § Configuration Changes Policy (lines 496-505 in the installed copy) — the
  existing description of `check-claude-version.sh`'s auto-update + reformat-discard behavior that
  this feature extends
- `~/.claude/CLAUDE.md` § Plans Repository Auto-Commit (lines 282-288) — the documentation shape to
  mirror for the new feature's CLAUDE.md entry
- `~/.claude/CLAUDE.md` § Repository Structure (line 1001+) — the `scripts/` tree listing to extend
- `~/.claude/README.md:598-621` (§ Contributing to This Configuration) — confirms the dot-claude PR
  workflow (worktree at the working copy, never `~/.claude/` directly) that governs the execution
  outline
- Codebase check: `git -C ~/.claude ls-files | grep -iE '\.env|settings'` → `settings.json`,
  `settings.local.example.json` only — grounds Sub-decision D; see `existing-logic_excerpt_1.md` § 4
- Auxiliary files: `existing-logic_excerpt_1.md` (verbatim code excerpts backing every citation
  above), `file-inventory_table_1.md` (full file inventory table)
