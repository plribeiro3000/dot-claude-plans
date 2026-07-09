# SPIKE — Terminal-Only Artifacts Made Redundant by Native App Migration

## Investigation question

4Shark is migrating every engineer from the Claude Code terminal CLI to the native desktop app; the terminal will no longer be used. Which artifacts in the `dot-claude` configuration repository exist solely to serve the terminal experience, and are therefore made redundant (dead weight — context and maintenance cost with no further purpose) by the native app? The engineer already flagged `scripts/statusline.sh` as one candidate. This spike confirms that candidate and searches for the rest, sorting every candidate into three buckets: (A) redundant terminal-only — the native app fully replaces it; (B) migration scaffolding — only meaningful during the terminal→native transition; (C) cross-surface / still needed — works in both surfaces, not terminal-specific.

## Sources consulted

- `/Users/plribeiro3000/.claude/settings.json:1-762` — full read; enumerated every hook block and the `statusLine` wiring.
- `/Users/plribeiro3000/.claude/scripts/statusline.sh:1-58` — full read.
- `/Users/plribeiro3000/.claude/scripts/check-entrypoint.sh:1-40` — full read.
- `/Users/plribeiro3000/.claude/scripts/notify.sh:1-25` — full read.
- `/Users/plribeiro3000/.claude/CLAUDE.md:276-279` — "Native App Recommendation" section, full read.
- `/Users/plribeiro3000/.claude/CLAUDE.md:1085,1092` — repository-structure tree entries for `notify.sh` and `statusline.sh`.
- Grep sweep of `scripts/*.sh` for `CLAUDE_CODE_ENTRYPOINT`, `terminal-notifier`, `osascript`, `notify-send`, `printf '\a'`, ANSI escape codes (`\033[`), `tput`, and the literal word "terminal" — see Finding 4.
- https://code.claude.com/docs/en/desktop — official Anthropic docs; confirms the native context-usage ring and native OS notification. See auxiliary `terminal-only-artifacts-native-migration_doc_1.md` §1.
- https://code.claude.com/docs/en/statusline — official Anthropic docs; confirms the terminal-dependent mechanics `statusLine` relies on (ANSI, OSC 8, `tput`) and that the desktop app is never mentioned as a rendering surface across the full page. See auxiliary §2.
- https://github.com/anthropics/claude-code/issues/33257 — community feature request (closed as not planned); claims `statusLine` is CLI/terminal-only and silently ignored by Desktop. See auxiliary §3.
- https://github.com/anthropics/claude-code/issues/20041 — community feature request (closed as not planned); corroborates the same gap pre-dating the "usage ring" feature. See auxiliary §4.
- https://code.claude.com/docs/en/hooks — official Anthropic docs; `Notification` and `Stop` event definitions. See auxiliary §5.
- https://github.com/anthropics/claude-code/issues/63360 — open feature request about Cowork (not the Code tab) not firing hooks; used only as indirect evidence. See auxiliary §6.
- See auxiliary: `terminal-only-artifacts-native-migration_doc_1.md` — full verbatim excerpts for every external citation above, with page-location notes and caveats.

## Findings

### Finding 1: `scripts/statusline.sh` + `statusLine` wiring — Bucket A (Redundant terminal-only)

**What it is**: a custom Bash script that reads `context_window.used_percentage` (already computed by Claude Code) and renders a colored ASCII progress bar plus remaining-token count in the status bar.

**Evidence — the script itself**:
```bash
# statusline.sh:10-13
# Use pre-calculated used_percentage from Claude Code (source of truth)
# This aligns with the native "Context left until auto-compact" indicator
USED_PCT_RAW=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
TOKENS=$((MAX_TOKENS * USED_PCT_RAW / 100))
```
```bash
# statusline.sh:31-35 — ANSI color codes, meaningless outside a terminal
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'
```
The script's own comment (line 11) already concedes it exists only to visualize a value Claude Code computes natively — it does no independent calculation of context usage, only formatting/coloring/bar-drawing on top of `used_percentage`.

**Evidence — settings.json wiring**:
```json
// settings.json:757-760
"statusLine": {
  "type": "command",
  "command": "$HOME/.claude/scripts/statusline.sh"
}
```

**Evidence — native app replaces it**: `code.claude.com/docs/en/desktop` §"Check usage":
> Click the usage ring next to the model picker to see your current context window usage and your plan usage for the period. Context usage is per session; plan usage is shared across all your Claude Code surfaces.

This is a first-party Anthropic statement that the desktop app has its own native, precise context-usage indicator. Corroborating community evidence (GitHub issue #33257, closed as not planned): the `statusLine` config in `settings.json` is described as CLI/terminal-only —
> "The CLI `statusLine` config in `settings.json` is silently ignored by Desktop"
> "The Desktop app is a GUI — it has no terminal status bar to render into."

This community claim is not an Anthropic maintainer statement (no maintainer comment text was retrievable), but it is corroborated by the shape of Anthropic's actual fix: a native "ring" UI element rather than rendering the CLI script inside the desktop app — consistent with "no rendering surface for `statusLine` in the GUI."

**Significance**: the script's entire purpose (visualize `used_percentage`) is now served by a first-party, always-current UI element in the native app. The nuance for the engineer to weigh: the native indicator is click-to-reveal (a ring next to the model picker), not an always-visible bar the way the terminal statusLine is — a UX difference, not a functional gap, since the underlying data (`context_window.used_percentage`) is confirmed identical in both surfaces per the statusLine docs' own field reference.

**Removal footprint** (if the engineer decides to remove):
- `scripts/statusline.sh` (58 lines)
- `settings.json:757-760` (`statusLine` block)
- Repository-structure tree comment in `CLAUDE.md:1092` (`│   ├── statusline.sh # Status line display`)
- **NOT part of the footprint**: `settings.json:6-8` (`env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`) — this env var independently controls when Claude Code itself triggers autocompact; `statusline.sh` only *reads* it for its own bar math (line 16: `AUTOCOMPACT_PCT="${CLAUDE_AUTOCOMPACT_PCT_OVERRIDE:-90}"`). Removing the script does not require removing the env override.

**Confidence**: High. First-party doc directly confirms a native replacement exists; the script's own header comment concedes it is a pure visualization layer over data Claude Code already surfaces.

### Finding 2: `scripts/notify.sh` + `Notification` hook wiring — Bucket A (Redundant), with a nuance the engineer should weigh

**What it is**: a cross-platform OS-notification script (macOS: `terminal-notifier` or `osascript`; Linux: `notify-send` or terminal bell; other: terminal bell) wired to Claude Code's `Notification` hook event with the fixed message `'Task completed'`.

**Evidence — the script itself**:
```bash
# notify.sh:8-25
case "$(uname -s)" in
  Darwin)
    if command -v terminal-notifier >/dev/null 2>&1; then
      terminal-notifier -title "$TITLE" -message "$MESSAGE" -sound default -ignoreDnD
    else
      osascript -e "display notification \"$MESSAGE\" with title \"$TITLE\" sound name \"Glass\""
    fi
    ;;
  Linux)
    if command -v notify-send >/dev/null 2>&1; then
      notify-send "$TITLE" "$MESSAGE"
    fi
    printf '\a'
    ;;
  *)
    printf '\a'
    ;;
esac
```
Two shapes inside this script are genuinely terminal-only: the `printf '\a'` terminal-bell fallback (lines 20, 23 — meaningless outside a text terminal) and the implicit assumption that the host process (Claude Code) has no notification mechanism of its own, which is what makes `terminal-notifier`/`osascript`/`notify-send` necessary in the first place. The `osascript`/`notify-send` calls themselves are OS-level, not terminal-level — they would technically still fire if the hook ran from a GUI process too.

**Evidence — settings.json wiring**:
```json
// settings.json:10-19
"Notification": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "$HOME/.claude/scripts/notify.sh 'Task completed'"
      }
    ]
  }
]
```

**Evidence — native app has its own built-in notification for the same event class**: `code.claude.com/docs/en/desktop`:
> "The desktop app sends an OS notification when a Code session finishes a task and you aren't currently viewing that session."

This is a first-party confirmation that the desktop app already produces an OS notification on session completion — the same outcome `notify.sh` exists to manufacture via the `Notification` hook.

**Significance / nuance**: unlike `statusline.sh`, `notify.sh` is not intrinsically terminal-only code — it is a general "make an OS notification appear" script, and the `Notification` hook it is wired to (per `code.claude.com/docs/en/hooks`) fires on notification types including `agent_completed`, `permission_prompt`, `idle_prompt`, etc., regardless of which surface (CLI or desktop) is running. If the hook fires identically inside the desktop app's "Code" tab — which was **not** directly confirmed by any source found (see "What remains uncertain") — then keeping `notify.sh` wired after full migration would produce a **duplicate** notification: one from the desktop app natively, one from the custom hook. That is the redundancy this Finding names — not "this code cannot run outside a terminal" (Finding 1's shape), but "this code's output becomes duplicative once every engineer is on a surface that already does the same thing natively."

**Removal footprint** (if the engineer decides to remove):
- `scripts/notify.sh` (25 lines)
- `settings.json:10-19` (`Notification` hook block)
- Repository-structure tree comment in `CLAUDE.md:1085` (`│   ├── notify.sh # Task completion notifications`)

**Confidence**: Medium-high. The native replacement is first-party confirmed for session completion. The residual uncertainty is narrower than it looks: whether the `Notification` hook itself still fires inside the desktop app's Code tab (see below) — if it does not fire there, the script is not "redundant," it is simply inert on that surface already (in which case removal is still safe, just for a different reason: dead code rather than duplicate code).

### Finding 3: `scripts/check-entrypoint.sh` + `Native App Recommendation` CLAUDE.md section — Bucket B (Migration scaffolding, not Bucket A)

**What it is**: a `SessionStart` hook that inspects `CLAUDE_CODE_ENTRYPOINT` and prints a recommendation to install the native app, but **only** when the value is the known terminal value `cli`; it is fail-silent on every other value (including the desktop app's own `claude-desktop`, unset, or unrecognized future values).

**Evidence — the script itself**:
```bash
# check-entrypoint.sh:25-38
case "${CLAUDE_CODE_ENTRYPOINT}" in
    cli)
        echo "=== NATIVE APP RECOMMENDATION ==="
        echo ""
        echo "This session is running in a terminal. 4Shark recommends the Claude Code native"
        echo "desktop app instead — it renders better with a clearer font (less eye strain),"
        ...
        echo "AGENT: proactively surface this recommendation to the engineer, highlighting the mobile/remote angle. It is a suggestion, not an action — do not install anything."
        ;;
esac
```

**Evidence — settings.json wiring**:
```json
// settings.json:34-38 (inside the SessionStart hooks array, settings.json:20-86)
{
  "type": "command",
  "command": "$HOME/.claude/scripts/check-entrypoint.sh",
  "timeout": 5
}
```

**Evidence — CLAUDE.md footprint**, `CLAUDE.md:276-279`:
> "4Shark recommends running Claude Code in the native desktop app, not a terminal. The native app renders better with a clearer font (less eye strain), shows artifacts in a side panel, and pairs with the mobile companion app so a session can be driven remotely via Remote Control. ... download at https://claude.com/download"
> "**Mechanically reinforced**: `scripts/check-entrypoint.sh` (SessionStart hook) reads `CLAUDE_CODE_ENTRYPOINT` and nudges only when it is a known terminal value (`cli`) ... The hook only recommends; it never installs anything"

**Significance**: this is categorically different from Findings 1 and 2. It is not "the native app does the same thing better" — it is "this script's entire job is to detect the exact condition ('someone is still on the terminal') that the migration is designed to eliminate." By its own documented design (fail-silent on every non-`cli` value), once every 4Shark engineer has migrated to the native app, this hook's `case` statement never matches its one active branch again — it becomes a no-op on every session, forever, but still executes on every `SessionStart` (part of `settings.json:20-86`'s hook chain) at a small but nonzero maintenance/context cost. This is the textbook shape of migration scaffolding per the engineer's own framing in the task brief.

**Removal footprint** (if the engineer decides to remove, once migration is verified complete):
- `scripts/check-entrypoint.sh` (40 lines)
- `settings.json:34-38` (the hook entry inside the `SessionStart` array — removing it also means renumbering/re-closing the surrounding JSON array, not just deleting the object)
- `CLAUDE.md:276-279` — the entire "### Native App Recommendation" section (both the recommendation prose and the "Mechanically reinforced" paragraph describing the hook)

**Confidence**: High that this is scaffolding, not a native-app-replaces-it case — this is the engineer's own documented design intent, not an inference. The only open question is a timing one (has migration actually completed for every engineer?), which is a process fact outside this spike's evidence, not a technical uncertainty.

### Finding 4: Sweep of every other hook and script in `settings.json` — no further Bucket A/B candidates found

**Method**: enumerated all hook blocks in `settings.json:9-407` (`Notification`, `SessionStart`, `SubagentStart`, `UserPromptSubmit`, `PostToolUse`, `PreToolUse`) and the `statusLine` block; grepped `scripts/*.sh` for `CLAUDE_CODE_ENTRYPOINT`, `terminal-notifier`, `osascript`, `notify-send`, `printf '\a'`, ANSI escape sequences (`\033[`), `tput`, and the literal word "terminal".

**Evidence**:
```
$ grep -rln "CLAUDE_CODE_ENTRYPOINT" scripts/ CLAUDE.md docs/
scripts/check-entrypoint.sh
CLAUDE.md
```
Only one script reads this variable — no other hidden entrypoint-gated script exists.

```
$ grep -rlI "terminal\|CLI-only\|cli only" scripts/*.sh
check-entrypoint.sh
notify.sh
read-context.sh
```
`read-context.sh`'s only hit is a doc-index description string (`"Per-destination edge cases for Output Policy (Slack mrkdwn, Outlook, Gmail, IDE auto-format, terminal escaping, HTML report destinations)"` — `read-context.sh:198`), not terminal-only scaffolding; it is a pointer to `OUTPUT-EDGE-CASES.md`, a cross-surface doc unrelated to this investigation.

The `\033[` (ANSI color) grep matched 13 additional scripts (`inject-full-read-reminder.sh`, `inject-query-discipline.sh`, `inject-code-pattern-on-write.sh`, `validate-bash-command.sh`, `inject-output-policy-reminder.sh`, `read-context.sh`, `inject-code-pattern-rule.sh`, `inject-terraform-context.sh`, `ecs-scale.sh`, `inject-output-preservation-reminder.sh`, `inject-deployment-strategy.sh`, plus `statusline.sh` and `notify.sh` already covered). These use ANSI color codes for readability in tool-output / hook-context text, not for a terminal-only rendering surface — per the desktop docs (`code.claude.com/docs/en/desktop`), the desktop app ships an "integrated terminal" and the Bash tool's output pane renders the same way in both surfaces; this is cross-surface formatting, not a terminal-only artifact. They are **not** classified as Bucket A or B.

No other `SessionStart`/`Notification`/`Stop`-equivalent hook in `settings.json` reads an entrypoint/surface-detection variable, and no other script matched the terminal-notification or terminal-bell shapes.

**Significance**: the sweep did not surface a fourth candidate beyond the three the engineer's brief anticipated (one flagged, two to investigate). This narrows the removal decision to Findings 1–3 rather than leaving an open-ended list.

**Confidence**: High for the negative claim ("no other script reads `CLAUDE_CODE_ENTRYPOINT` or uses terminal-notification commands") — this is a mechanical grep result, not an inference. Medium for completeness of the ANSI-code review — 13 scripts were identified as using ANSI codes but only spot-checked for context (SessionStart/UserPromptSubmit hook text), not individually read start-to-end; a deeper per-script read is out of this spike's scope but is unlikely to change the classification given the desktop app's documented "integrated terminal."

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Remove `statusline.sh` + `statusLine` wiring now | Native app already shows context % via the usage ring (Finding 1); removes 58 lines + JSON block + doc line | Native indicator is click-to-reveal, not always-visible — UX regression for anyone who liked the ambient bar; if any engineer still runs CLI intermittently during transition, they lose the bar entirely | `code.claude.com/docs/en/desktop` §Check usage |
| Remove `notify.sh` + `Notification` hook wiring now | Native app already sends an OS notification on session completion (Finding 2); avoids duplicate notifications once fully migrated | Unconfirmed whether the `Notification` hook fires inside the desktop app's Code tab at all — if it does not, removal is safe but for the "dead code" reason, not "duplicate" reason; if some engineers still use CLI during transition, they lose ALL notification since CLI has no native equivalent | `code.claude.com/docs/en/desktop`, `code.claude.com/docs/en/hooks`, GH issue #63360 (indirect) |
| Remove `check-entrypoint.sh` + CLAUDE.md section now | Its own documented design is fail-silent once nobody uses `cli` — literally built to become a no-op | Removing it before migration is verified 100% complete removes the nudge for any straggler still on the terminal | `CLAUDE.md:276-279`, `check-entrypoint.sh:25-38` |
| Keep all three until migration is formally confirmed complete for every engineer | No risk of losing a signal (notification, context visibility, migration nudge) for anyone still transitioning | Continues paying the small context/maintenance cost the investigation was asked to quantify | Engineer's framing of the investigation question |
| Remove statusline/notify but keep check-entrypoint.sh | Retires the two purely-duplicative artifacts immediately while the migration-tracking nudge keeps working for stragglers | Asymmetric — the engineer has to track two different removal timelines instead of one | Derived from Findings 1–3 |

## What remains uncertain

- **Whether the `Notification` hook fires inside the Claude Code Desktop app's "Code" tab.** No source found directly confirms or denies this for the Code tab specifically. The only related evidence is GitHub issue #63360, which documents hooks (`UserPromptSubmit`, `Stop`) failing to fire in **Cowork** — a different tab from Code — with the issue's own framing implying Code-tab hook support is the normal/expected baseline that Cowork deviates from. This is indirect, not direct, evidence. **Recommended before removal**: the engineer can verify empirically — configure a harmless `Notification` hook (e.g. one that writes a timestamp to a file) and trigger a permission prompt inside a desktop-app Code-tab session, then check whether the file was written.
- **Whether "closed as not planned" on GitHub issues #33257 and #20041 means "Anthropic decided not to build a fix" versus "the underlying request was later satisfied by a different feature (the usage ring) and the issue was closed for that reason without an explicit closing comment."** No maintainer comment text was retrievable from either issue via WebFetch. The usage-ring feature (§1 of the auxiliary doc) is documented on the current desktop docs page independent of these issues, so the practical conclusion (a native indicator exists) does not depend on resolving this ambiguity — but the specific reason the two feature requests were closed is not confirmed.
- **Full ANSI-escape-code review of the 13 other flagged scripts** was spot-checked, not exhaustively read line-by-line (Finding 4). Given the desktop app's documented "integrated terminal" (same docs page), these are assessed as cross-surface (Bucket C) with high but not certain confidence.
- **Migration completeness** — this spike investigated the artifacts; it did not investigate or confirm what fraction of 4Shark engineers have actually completed the terminal→native migration. That is a process fact, not a codebase fact, and is outside a codebase spike's evidence base.

## Suggested options for main and the engineer

- **Option A — Remove all three now.** Delete `scripts/statusline.sh`, `scripts/notify.sh`, `scripts/check-entrypoint.sh`; remove the `statusLine` block (`settings.json:757-760`), the `Notification` hook block (`settings.json:10-19`), and the `check-entrypoint.sh` entry inside `SessionStart` (`settings.json:34-38`); remove the `### Native App Recommendation` section (`CLAUDE.md:276-279`) and the two repository-structure tree lines (`CLAUDE.md:1085,1092`). Fastest cleanup; assumes migration is effectively complete and accepts the residual notification-gap risk for any straggler still on CLI.
- **Option B — Two-phase removal.** Remove `statusline.sh` and `notify.sh` now (Findings 1–2, native app confirmed to cover both use cases); keep `check-entrypoint.sh` + its CLAUDE.md section until the engineer explicitly confirms every engineer has migrated (Finding 3's own logic: it is self-silencing scaffolding, so keeping it a while longer costs only the small per-session no-op check, not a functional cost).
- **Option C — Verify the `Notification`-hook-in-Code-tab open question first, then decide.** Run the empirical check described in "What remains uncertain" before removing `notify.sh`; if the hook does not fire in the desktop Code tab, `notify.sh` is dead weight for a different reason (inert, not duplicative) but the removal conclusion is the same — this option only changes the confidence level attached to Finding 2, not the recommended action.
- **Option D — Keep everything until a formal migration-complete milestone**, then execute Option A in one cleanup PR. Lowest risk, defers the benefit (context/maintenance savings) the investigation was requested to identify.

(No recommendation given — per the Subagent Contract and this spike's engineer's request, the removal decision belongs to the engineer.)
