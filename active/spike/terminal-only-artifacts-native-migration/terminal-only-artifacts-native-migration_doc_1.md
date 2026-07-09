# Auxiliary source material — official Anthropic Claude Code documentation excerpts

Fetched during the terminal-only-artifacts-native-migration spike (2026-07-08). Each excerpt is a verbatim quote from the URL listed, preserved here so the engineer can re-verify without re-fetching.

## 1. Desktop app docs — https://code.claude.com/docs/en/desktop

### "Check usage" section (native context-window indicator)

> ### Check usage
>
> Click the usage ring next to the model picker to see your current context window usage and your plan usage for the period. Context usage is per session; plan usage is shared across all your Claude Code surfaces.

Location on page: under the "Work in parallel with sessions" heading area, anchor `#check-usage`.

### Native OS notification on session completion

> The desktop app sends an OS notification when a Code session finishes a task and you aren't currently viewing that session.

Location on page: directly below the "Check usage" paragraph, in the sessions-sidebar section.

### CI-finish notification (separate feature, PR monitoring)

> Use the **Auto-fix** and **Auto-merge** toggles in the CI status bar to enable either option. Claude Code also sends a desktop notification when CI finishes.

Location on page: PR monitoring section. Cited for completeness — not the same code path as session-completion notification, not directly relevant to the `notify.sh` Notification-hook comparison, included here so the distinction is traceable.

### Dispatch push notification (mobile, different feature)

> Either way, the Code session appears in the Code tab's sidebar with a **Dispatch** badge. You get a push notification on your phone when it finishes or needs your approval.

Location on page: Dispatch section. Cited for completeness — mobile-specific, not a desktop OS notification, not directly relevant to the bucket-A/B decision.

## 2. statusLine docs — https://code.claude.com/docs/en/statusline

### Overview (frames the feature as terminal-rendered)

> The status line is a customizable bar at the bottom of Claude Code that runs any shell script you configure. It receives JSON session data on stdin and displays whatever your script prints, giving you a persistent, at-a-glance view of context usage, costs, git status, or anything else you want to track.

### Terminal-dependent rendering features named explicitly

> **Colors**: use [ANSI escape codes](https://en.wikipedia.org/wiki/ANSI_escape_code#Colors) like `\033[32m` for green (terminal must support them). See the [git status example](#git-status-with-colors).
>
> **Links**: use [OSC 8 escape sequences](https://en.wikipedia.org/wiki/ANSI_escape_code#OSC) to make text clickable (Cmd+click on macOS, Ctrl+click on Windows/Linux). Requires a terminal that supports hyperlinks like iTerm2, Kitty, or WezTerm.

> Claude Code captures your script's output instead of connecting it directly to the terminal, so `tput cols` and language-level width detection cannot read the terminal size from inside the script. Read the `COLUMNS` and `LINES` environment variables instead.

Note: this page does not contain an explicit sentence stating "the desktop app does not render statusLine" — that specific claim comes from the community-authored GitHub issues below (§3), not from this first-party page. The first-party page is cited here only for the terminal-dependent mechanics (ANSI, OSC 8, `tput`) that the feature relies on, and because it never once mentions the desktop app as a rendering surface across ~1090 lines describing the feature end-to-end.

## 3. GitHub issue #33257 — anthropics/claude-code (community feature request, closed as not planned)

URL: https://github.com/anthropics/claude-code/issues/33257
Created: March 11, 2026. Status: Closed as not planned. Labels include `area:desktop`, `area:statusline`, `stale`.

> Claude Code for Desktop has no way to see context window usage. The `statusLine` feature in `settings.json` only renders in the CLI/terminal version. Desktop users have zero visibility into context consumption until auto-compaction happens unexpectedly.

> The CLI `statusLine` config in `settings.json` is silently ignored by Desktop

> The Desktop app is a GUI — it has no terminal status bar to render into. This needs a native UI solution.

Caveat: this is the issue submitter's own claim (a community feature request), not an Anthropic maintainer statement — no maintainer comment text was available in the fetched content. It is corroborated by the "Check usage" ring finding in §1: Anthropic's chosen answer to the same gap was a click-to-reveal ring UI element rather than rendering the CLI `statusLine` script inside the desktop app.

## 4. GitHub issue #20041 — anthropics/claude-code (community feature request, closed as not planned)

URL: https://github.com/anthropics/claude-code/issues/20041

> Claude Desktop provides no visibility into context window usage until auto-compaction occurs, typically around 95% capacity.

Status: Closed as not planned, labeled `invalid` / "Issue doesn't seem to be related to Claude Code" — this closure reasoning is about the issue being filed against the wrong product surface at the time, not a statement that the underlying gap was already resolved. The later "Check usage" ring (§1) postdates this issue and is the feature that addresses the underlying request.

## 5. Hooks reference — https://code.claude.com/docs/en/hooks (fetched via summarized WebFetch, not raw)

Notification event:

> When Claude Code sends a notification

> The `Notification` event does not support matchers and always fires on every occurrence. It filters on notification type: `permission_prompt`, `idle_prompt`, `auth_success`, `elicitation_dialog`, `elicitation_complete`, `elicitation_response`, `agent_needs_input`, `agent_completed`.

Stop event:

> When Claude finishes responding

Caveat: the claim "no differences between desktop app and CLI/terminal for these events... consistent across platforms" was the WebFetch summarizer's own inference, not a verbatim quote from the page — it is NOT treated as a verified fact in the spike and is listed under "What remains uncertain."

## 6. GitHub issue #63360 — anthropics/claude-code (Cowork hooks gap, open feature request)

URL: https://github.com/anthropics/claude-code/issues/63360

> Claude Code supports lifecycle hooks configured in ~/.claude/settings.json (UserPromptSubmit, Stop, PreToolUse, PostToolUse, etc.). Cowork is built on Claude Code, but does not fire these hooks.

> Verified May 28, 2026: two hooks configured in ~/.claude/settings.json with scripts installed at ~/.claude/hooks/ — UserPromptSubmit → inject-datetime.sh ... Stop → record-session-event.sh ... In a fresh Cowork chat after a full quit-and-restart: 1. UserPromptSubmit did not fire ... 2. Stop did not fire — no log file was ever written.

Significance: this issue is about the **Cowork** tab specifically (a different tab from the **Code** tab that runs actual Claude Code coding sessions). It does not directly confirm or deny hook firing inside the Code tab. It is cited because its framing ("Cowork is built on Claude Code, but does not fire these hooks") implies hooks are the expected/normal behavior of Claude Code itself, of which Cowork is a deviation — indirect, not direct, evidence that the Code tab (the surface 4Shark engineers use) fires hooks normally, including `Notification`.

## Note on a discarded search result

A web search surfaced `https://github.com/desktop/desktop/issues/22138` under a title mentioning "Claude Desktop App." Direct verification via WebFetch confirmed this issue is filed against `desktop/desktop`, the **GitHub Desktop** git-client repository — unrelated to Anthropic's Claude Code or Claude Desktop app. It is NOT used as evidence anywhere in the spike. Documented here only so a future reviewer does not re-surface it as if it were relevant.
