# SPIKE — Detecting Terminal vs Native Desktop App to Nudge Engineers Toward the Desktop App

## Investigation question

Can a 4Shark rule reliably detect that a Claude Code session is running inside a **terminal emulator** (as opposed to the **native Claude desktop app**) and, when it is, proactively nudge the engineer at the start of their next turn to switch to the native app — listing concrete, sourced advantages (rendering/font/eye-strain, and the mobile companion app for Remote Control)?

This is only worth building if **both** hold:
(a) detection of terminal-vs-desktop-app is reliable enough to key a rule on, and
(b) the native desktop app actually exists on the engineer's OS (macOS confirmed by this very session; Windows and Linux/Ubuntu needed verification).

## Ground truth (verified directly from this running session)

This session is running inside the native desktop app. A direct probe of the process environment gave:

- `CLAUDE_CODE_ENTRYPOINT=claude-desktop` — the distinguishing signal
- `__CFBundleIdentifier=com.anthropic.claudefordesktop` — macOS-only corroboration (LaunchServices bundle id)
- `TERM`, `TERM_PROGRAM`, `TERM_PROGRAM_VERSION`, `TERM_SESSION_ID`, `LC_TERMINAL` — all unset in this session; in a real terminal emulator `TERM_PROGRAM` would normally be set (e.g. `iTerm.app`, `Apple_Terminal`, `vscode`, `WezTerm`)
- `CLAUDECODE=1` is set — present in both terminal and desktop-app sessions, confirmed NOT a discriminator by the official docs (see Finding 1)

This is a direct, first-person observation from the live session, not a web-sourced claim — treated as verified per the engineer's brief, and corroborated below rather than re-derived.

## Sources consulted

- [code.claude.com/docs/en/env-vars](https://code.claude.com/docs/en/env-vars) — official environment-variable reference; does NOT document `CLAUDE_CODE_ENTRYPOINT`. See auxiliary `detect-terminal-vs-desktop-app_doc_1.txt`.
- Four third-party community gists (`mculp`, `jedisct1`, `yi`, `unkn0wncode`) — unofficial, contradictory descriptions of `CLAUDE_CODE_ENTRYPOINT`. See auxiliary `detect-terminal-vs-desktop-app_doc_2.txt`.
- [code.claude.com/docs/en/desktop-quickstart](https://code.claude.com/docs/en/desktop-quickstart), [desktop-linux](https://code.claude.com/docs/en/desktop-linux), [desktop](https://code.claude.com/docs/en/desktop), [claude.com/download](https://claude.com/download) — official OS availability matrix. See auxiliary `detect-terminal-vs-desktop-app_doc_3.txt`.
- [github.com/anthropics/claude-code/issues/28144](https://github.com/anthropics/claude-code/issues/28144) — open community feature request confirming there is no official runtime-detection mechanism today. See auxiliary `detect-terminal-vs-desktop-app_doc_4.txt`.
- [code.claude.com/docs/en/remote-control](https://code.claude.com/docs/en/remote-control) — official doc for the mobile-companion / Remote Control capability (the emotional hook). See auxiliary `detect-terminal-vs-desktop-app_doc_5.txt`.
- `~/.claude/scripts/check-ssh-keys.sh` and `~/.claude/scripts/check-push-default.sh` — read directly to describe the existing SessionStart detect-and-nudge hook shape (Finding 5).

## Findings

### Finding 1: `CLAUDECODE` is documented and is explicitly NOT a discriminator

**Evidence:**
```
"Set to 1 in subprocesses Claude Code spawns (Bash and PowerShell tools,
tmux sessions, hook commands, status line commands, stdio MCP server
subprocesses). IDE extensions also set this in their integrated
terminals. Use to detect when a script is running inside a subprocess
spawned by Claude Code."
```
**Source:** [code.claude.com/docs/en/env-vars](https://code.claude.com/docs/en/env-vars), quoted via WebFetch; full excerpt in `detect-terminal-vs-desktop-app_doc_1.txt`.

**Significance:** confirms the ground-truth observation that `CLAUDECODE=1` is set identically whether Claude Code is a terminal CLI session or a desktop-app session (and even in IDE-integrated terminals) — it marks "any Claude Code subprocess", not "which surface". Any rule based on `CLAUDECODE` alone would misfire.

### Finding 2: `CLAUDE_CODE_ENTRYPOINT` is undocumented on the official reference page

**Evidence:** the same official env-vars page, fetched and searched specifically for `CLAUDE_CODE_ENTRYPOINT`, returned: "there is no mention of a `CLAUDE_CODE_ENTRYPOINT` environment variable" (full page content quoted in `detect-terminal-vs-desktop-app_doc_1.txt`). The page does document three other environment-detection variables (`CLAUDECODE`, `CLAUDE_CODE_CHILD_SESSION`, `CLAUDE_CODE_BRIDGE_SESSION_ID`) — none of which distinguish desktop-app from terminal.

**Source:** [code.claude.com/docs/en/env-vars](https://code.claude.com/docs/en/env-vars).

**Significance:** the variable this session observed directly (`CLAUDE_CODE_ENTRYPOINT=claude-desktop`) is real (it is present in this session's actual environment) but is **not part of Anthropic's published, supported environment-variable surface**. It is an internal/telemetry variable, not a documented public API.

### Finding 3: Community documentation of `CLAUDE_CODE_ENTRYPOINT` is contradictory across four independent sources

**Evidence:** four different community gists were asked the identical question. Results:
- `mculp` gist: "Entrypoint type (local-agent, remote…)"
- `jedisct1` gist: "Custom application entrypoint... Values: file paths or module names" — does not match observed reality at all
- `yi` gist: does not mention the variable
- `unkn0wncode` gist: "Identifies how Claude Code was launched (e.g., cli, sdk-ts/sdk-py/sdk-cli, mcp, claude-vscode, claude-desktop, remote_*, local-agent, claude-in-slack/teams, claude-code-github-action)"

Full quotes in `detect-terminal-vs-desktop-app_doc_2.txt`.

**Source:** gist.github.com/mculp/…, gist.github.com/jedisct1/…, gist.github.com/yi/…, gist.github.com/unkn0wncode/… (URLs in the auxiliary file).

**Significance:** only the `unkn0wncode` gist's value catalog (`cli`, `sdk-ts`, `sdk-py`, `sdk-cli`, `mcp`, `claude-vscode`, `claude-desktop`, `remote_*`, `local-agent`, `claude-in-slack`, `claude-in-teams`, `claude-code-github-action`) is consistent with this session's ground-truth value (`claude-desktop`) and lists `cli` as the plain-terminal value — matching the working hypothesis. The other three sources actively disagree with each other and with observed reality, which is itself evidence that this variable is being reverse-engineered/guessed by the community rather than read from an Anthropic specification. A WebSearch pass additionally surfaced (unattributed to a specific fetchable page, so treated as directional only, not a citable Finding) a claim that `CLAUDE_CODE_ENTRYPOINT` feeds OpenTelemetry metric labels for "how Claude Code was invoked" — consistent with an internal-use variable that happens to also gate a Linux retry-watchdog and label telemetry, not a documented user-facing contract.

### Finding 4: Anthropic has an open, unresolved community request for exactly this capability — no official mechanism ships today

**Evidence:**
```
"Claude Code does not know which interface it is running in. When asked,
it cannot distinguish between the Desktop App, the CLI/Terminal, or the
Web interface. This leads to incorrect assumptions and confusing guidance
for users."
```
and the suggested fix:
```
"Add the runtime environment identifier to the system context that Claude
receives at session start, alongside existing fields like platform, shell,
and OS version."
```
**Source:** [github.com/anthropics/claude-code/issues/28144](https://github.com/anthropics/claude-code/issues/28144) (closed as duplicate, filed 2026-02-24). Full text in `detect-terminal-vs-desktop-app_doc_4.txt`.

**Significance:** this is independent, corroborating evidence — from a member of the Claude Code community, not from this spike's own probing — that (a) the need this spike investigates is real and felt by other users, and (b) no official, first-class runtime-identification mechanism exists as of this filing. The issue being "closed as duplicate" indicates the underlying request is tracked elsewhere in Anthropic's system, but there is no evidence in the fetched content that it has shipped.

### Finding 5: a `SessionStart` hook CAN read `CLAUDE_CODE_ENTRYPOINT` — it is a normal process environment variable

**Evidence:** the `CLAUDECODE` variable's documented behavior — "Set to 1 in subprocesses Claude Code spawns (Bash and PowerShell tools, tmux sessions, **hook commands**, status line commands, stdio MCP server subprocesses)" — establishes that hook commands run as ordinary subprocesses of the Claude Code process and therefore inherit its process environment, exactly like the Bash tool does. `CLAUDE_CODE_ENTRYPOINT` is exported the same way (it was readable via this session's own environment probe, itself run through a subprocess mechanism). There is nothing exotic required to read it from a hook — it is `echo "$CLAUDE_CODE_ENTRYPOINT"` in a bash script.

**Source:** [code.claude.com/docs/en/env-vars](https://code.claude.com/docs/en/env-vars) (quote above); corroborated by this session's own direct environment probe (ground truth, § above).

**Significance:** technically, nothing blocks building the hook mechanism itself. The risk is entirely in Finding 2/3 (undocumented, could change silently) — not in whether a hook can access the variable.

### Finding 6: the native desktop app officially exists on macOS, Windows, and Linux/Ubuntu (Linux in beta)

**Evidence:**
```
"Download for macOS ... Universal build for Intel and Apple Silicon"
"Download for Windows ... For x64 processors"
"Get Claude for Linux (beta) ... apt or .deb for Ubuntu and Debian"
```
and, for Linux specifically:
```
"Requirements
* Ubuntu 22.04 or later, or Debian 12 or later
* x86_64 or arm64"
```
and:
```
"Linux support for the Claude desktop app is in beta. The Chat, Cowork,
and Code tabs are all available."
```
**Source:** [code.claude.com/docs/en/desktop-quickstart](https://code.claude.com/docs/en/desktop-quickstart), [code.claude.com/docs/en/desktop-linux](https://code.claude.com/docs/en/desktop-linux). Full quotes in `detect-terminal-vs-desktop-app_doc_3.txt`.

**Significance:** this is the gating question the engineer flagged, and the answer is favorable for a team-wide rule — no OS is excluded outright. Linux is beta with two named gaps (Computer Use, Dictation — neither relevant to the "Code" tab core coding workflow) and is limited to Debian-based distributions (Ubuntu/Debian only; explicitly "Fedora and RHEL... not supported today"). The engineer's own environment (this session) is macOS, where the app is fully GA.

### Finding 7: the macOS bundle id corroborates the ground truth from an independent official source

**Evidence:** "macOS: configure via `com.anthropic.claudefordesktop` preference domain using tools like Jamf or Kandji" (from the enterprise device-management section of the desktop reference doc).

**Source:** [code.claude.com/docs/en/desktop](https://code.claude.com/docs/en/desktop) (full page persisted at `~/.claude/projects/-/c28dba9f-85fc-4f0c-a6d4-a1204cb75578/tool-results/toolu_01LTgFhrzfkZC2s6rqTERuQq.txt`; excerpt in `detect-terminal-vs-desktop-app_doc_3.txt`).

**Significance:** this independently confirms, from Anthropic's own documentation (not a probe of this session), that `com.anthropic.claudefordesktop` is the desktop app's macOS bundle identifier — matching the `__CFBundleIdentifier` observed in ground truth. As the engineer's brief noted, this signal is macOS-only by construction (a Windows/Linux build has no `__CFBundleIdentifier`, since it is a macOS LaunchServices concept), so it cannot be the cross-platform discriminator — `CLAUDE_CODE_ENTRYPOINT` remains the only candidate that is OS-agnostic.

### Finding 8: sourced, concrete advantages for the nudge — including the mobile/Remote-Control hook

**Evidence (rendering/UI):**
```
"The desktop app gives you Claude Code with a graphical interface built
for running multiple sessions side by side: a sidebar for managing
parallel work, a drag-and-drop layout with an integrated terminal and
file editor, visual diff review, live app preview, GitHub PR monitoring
with auto-merge, and scheduled tasks. No terminal required."
```
**Source:** [code.claude.com/docs/en/desktop-quickstart](https://code.claude.com/docs/en/desktop-quickstart).

**Evidence (mobile / Remote Control — the emotional hook):**
```
"Remote Control connects claude.ai/code or the Claude app for iOS and
Android to a Claude Code session running on your machine. Start a task at
your desk, then pick it up from your phone on the couch or a browser on
another computer."
```
and:
```
"Use your full local environment remotely: your filesystem, MCP servers,
tools, and project configuration all stay available"
```
and, on the Desktop-specific angle:
```
"In the Desktop app, you can also toggle this from Settings -> Claude
Code -> Enable remote control by default."
```
and the related Desktop-exclusive "Dispatch" capability, from the feature-comparison table:
```
"Dispatch — Message a task from the Claude mobile app — Claude runs on:
Your machine (Desktop) — Setup: Pair the mobile app with Desktop — Best
for: Delegating work while you're away, minimal setup."
```
**Source:** [code.claude.com/docs/en/remote-control](https://code.claude.com/docs/en/remote-control). Full quotes in `detect-terminal-vs-desktop-app_doc_5.txt`.

**Significance:** Remote Control itself is available from BOTH the CLI (`claude remote-control` / `claude --remote-control` / `/remote-control`) and the Desktop app — it is not desktop-exclusive. What IS desktop-specific is: (a) a one-click toggle to enable it by default ("Settings → Claude Code → Enable remote control by default"), and (b) **Dispatch**, which the comparison table documents as running "on your machine (Desktop)" specifically — i.e., messaging a brand-new task from the phone that spawns a Desktop session is a Desktop-app capability, not something the bare CLI offers on its own. This is the sourced basis for the "agora eu consigo usar remoto" framing: the CLI has Remote Control too, but the richer phone-first workflow (Dispatch) is Desktop's alone.

**Not found:** no source was located that makes a font-rendering or eye-strain comparison in Anthropic's own words — that part of the engineer's motivation is the engineer's own subjective experience, not something to attribute to a fetched source. The SPIKE surfaces the UI/GUI capabilities Anthropic documents (multi-session sidebar, diff view, integrated editor, "No terminal required") as the closest sourced proxy; the font/eye-strain framing itself should be phrased as the engineer's own stated reason, not attributed to Anthropic.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Key the rule on `CLAUDE_CODE_ENTRYPOINT != claude-desktop` | Only known signal that is OS-agnostic; readable by a plain SessionStart hook (Finding 5); matches this session's ground truth exactly | Undocumented by Anthropic (Finding 2); community sources disagree on its exact value catalog (Finding 3); could change or be renamed without notice in a future Claude Code release, silently breaking the hook | `detect-terminal-vs-desktop-app_doc_1.txt`, `_doc_2.txt` |
| Key the rule on `__CFBundleIdentifier` | Simple, and directly corroborated by an official Anthropic doc (Finding 7) | macOS-only — a Windows or Linux desktop-app session never sets this, so it cannot detect "terminal vs desktop" on those OSes; would require an OS-specific companion check the engineer explicitly wants to avoid ruling out | `detect-terminal-vs-desktop-app_doc_3.txt` |
| Wait for an official runtime-identifier field (per the open GitHub issue) | Would be documented, stable, and supported — no silent-breakage risk | No committed timeline found; issue is closed as duplicate with no shipped feature evident in the fetched content; blocks the rule indefinitely | `detect-terminal-vs-desktop-app_doc_4.txt` |
| Do not build a detection-based rule; rely on the engineer to say "I'm on my phone" / manually toggle a setting (as 4Shark's own Output Policy already does for Remote/mobile mode — see CLAUDE.md § Output Policy Layer 2, "Remote/mobile mode... The trigger is a manual signal from the engineer, not auto-detection") | No silent-breakage risk at all; consistent with 4Shark's own stated precedent of preferring an explicit engineer signal over unreliable auto-detection for a very similar terminal-vs-mobile distinction | Loses the "proactive nudge" behavior the engineer specifically asked for; the engineer would have to remember to say something instead of Claude noticing on its own | 4Shark's own CLAUDE.md (already-adopted precedent, not an external source) |

## What remains uncertain

- Whether `CLAUDE_CODE_ENTRYPOINT` is stable across Claude Code versions — no Anthropic changelog entry or versioning note was found for this variable specifically (searched but not found: a dedicated changelog entry documenting its introduction or its value catalog).
- Whether IDE extensions (VS Code, JetBrains) set `CLAUDE_CODE_ENTRYPOINT` to a distinct value (e.g. something IDE-specific) that would need its own branch in the nudge logic, or whether they fall under a generic non-`claude-desktop` bucket that the nudge would incorrectly treat as "terminal, please switch to desktop" when the engineer is already inside an IDE and switching may not make sense. Not found: an authoritative value for the VS Code extension case (the `unkn0wncode` gist lists `claude-vscode` as a distinct value, but that gist is unofficial per Finding 3).
- Whether Anthropic will ship the officially requested runtime-identifier (GitHub issue #28144) before this variable's shape changes — timing not found.
- The font-rendering / eye-strain claim is the engineer's own subjective motivation; no Anthropic source substantiates a rendering-quality comparison between a terminal emulator and the desktop app (this is expected — it is a UX opinion, not a documented fact — and is flagged here so the eventual nudge text does not attribute it to Anthropic).

## Suggested options for main and the engineer

- **Option A — build the hook now, keyed on `CLAUDE_CODE_ENTRYPOINT`, accept the undocumented-variable risk.** A `SessionStart` hook in the same shape as `~/.claude/scripts/check-ssh-keys.sh` / `check-push-default.sh` (silent-when-compliant, warns once, never blocks, tells the agent to "proactively offer" — see the pattern excerpts these two files already show: both read a piece of state, `case`/`if` against known-bad values, print a `=== ... WARNING ===` block only on mismatch, and end with an explicit "AGENT: proactively offer..." instruction) would read `$CLAUDE_CODE_ENTRYPOINT`, treat any value other than `claude-desktop` as "not the desktop app", and print the nudge with the sourced advantages from Finding 8. Risk: if Anthropic changes or removes this variable, the hook goes silent (fails safe) or, worse, could start firing incorrectly if the value catalog shifts — this would need to be monitored, e.g. re-checked on Claude Code version bumps the way `check-claude-version.sh` already tracks version state.
- **Option B — build it, but scope the "always nudge" behavior to macOS/Windows only and treat Linux specially.** Since Linux is beta with a narrower distro list (Finding 6), the nudge copy could note "beta, Ubuntu/Debian only" for Linux users so the recommendation is precise rather than overselling GA status.
- **Option C — do not build an auto-detecting hook; instead rely on an explicit one-time setting/CLAUDE.md preference the engineer sets once ("I use the desktop app" / "I use the terminal"), mirroring the precedent 4Shark already uses for Remote/mobile-mode detection (CLAUDE.md § Output Policy, Layer 2: "Remote Control does not expose a reliable local-vs-remote flag, so do not infer the mode; wait for the signal").** No detection-reliability risk at all, but no proactive nudge either — someone already on the terminal never gets the nudge unless they interact with the setting.
- **Option D — hybrid: build the hook per Option A, but design it to fail silent (no output) rather than fail loud whenever `CLAUDE_CODE_ENTRYPOINT` is unset, empty, or an unrecognized value outside the known catalog** (`cli`, `claude-desktop`, `claude-vscode`, `sdk-*`, `mcp`, `remote_*`, `local-agent`, per the one gist whose values matched ground truth) — so an unexpected future value degrades gracefully into "say nothing" instead of misfiring a wrong nudge.

No recommendation is made between these — the reliability/undocumented-variable trade-off (Options A/B/D) versus the zero-risk/no-proactivity trade-off (Option C) is the engineer's call.
</content>
