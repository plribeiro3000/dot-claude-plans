# ANALYSIS — Output Policy under the native desktop app

## Context

The engineer migrated from the terminal to the native Claude Code desktop app two days ago. Much of the current Output Policy (§ Output Policy in `CLAUDE.md`, plus `OUTPUT-EDGE-CASES.md`) was written to work around terminal limitations — most notably indentation/formatting corruption when pasting generated code out of a terminal. The engineer's direct observation: the native app renders a code block with a copy button that copies cleanly, with no indentation problem.

This document classifies every terminal-touching rule, separates the ones that were terminal *workarounds* from the ones that only *look* terminal-related, and recommends the adjustment for each. No config file is edited here — changes to `~/.claude/` go through a dot-claude PR (Configuration Changes Policy).

## The core reframing

The terminal was doing **two different jobs at once**, and the current policy conflates them:

1. **SOURCE surface** — where Claude's output was rendered and copied *from*. The terminal rendered markdown as literal characters, broke long lines at the viewport, and corrupted indentation on copy. **The native app replaces this surface** — rich markdown, per-code-block copy buttons, clean copy at any length.

2. **DESTINATION surface** — where the engineer *pastes* the output *to*: their own shell, an email client, Slack, an IDE editor. **The native app changes none of these.** A shell still evaluates backticks. Outlook still renders `###` literally. Slack still uses mrkdwn. An IDE still auto-formats on paste.

**Nearly every rule that can now relax is one that assumed the terminal was the SOURCE. Nearly every rule that must stay is about a DESTINATION, or about a concern that was never about rendering at all** (security, the permissions matcher, LLM consumption, approval fatigue, data leaving the machine).

Making this axis explicit in the policy is the single highest-value change — it prevents the next rule from being misfiled, and it explains *why* each existing rule moves or stays.

## Classification

### A. Terminal-workaround rules — candidates to relax

| # | Rule (location) | Terminal premise | Under native app | Recommended adjustment |
|---|---|---|---|---|
| A1 | Layer 2: "Long code blocks → File as plain text in /tmp/, opened with `open`" | Pasting long code out of a terminal corrupts indentation, so write to a file | Copy button copies any length cleanly | Code the engineer will **copy** → fenced code block in chat, regardless of length. Keep the /tmp file only for code the engineer will **run** (`open` it), a real deliverable, or code Claude itself executes. The channel split becomes "copy vs run", not "short vs long". |
| A2 | Layer 1: "Terminal — command(s) to run → bare command, no fences" and "IDE / file paste (code) → bare code, no Markdown fences" | Fences render as literal characters and end up in the pasted text | The copy button copies the code block **without** the fences | In the native app chat, a fenced block is now the *correct* shape for copy-paste — the fence is chrome the copy button strips. The "no fences" constraint applies only to what actually lands in the destination, which the copy button already guarantees. Simplify: fenced in chat is fine; the concern is destination semantics (below), not fences. |
| A3 | `OUTPUT-EDGE-CASES.md` § Code paste into IDE: "For more than ~10 lines, write to /tmp/ and `open`" | Same as A1 | Same as A1 | Drop the ">10 lines → file" clause. Keep the "IDE auto-formats on paste" warning — that is a DESTINATION fact, unchanged. |
| A4 | Layer 5 / "destination unknown" default: "If content is more than ~10 lines, write to /tmp/ and `open` regardless" | Same as A1 | Same as A1 | Drop the line-count fallback to file. The safe default becomes a fenced block in chat. |
| A5 | Layer 2: "email drafts > 10 lines → file" | Chat formatting won't survive the paste out of a terminal | Prose selects/copies from chat cleanly | Weaken the length trigger for email drafts. Prose can stay in chat; a file is for genuinely long documents or when the engineer asks for one. (Note: the no-hard-wrap rule for prose is a DESTINATION rule and stays — see B.) |

### B. Rules that look terminal-related but must NOT change

| # | Rule (location) | Why it is NOT a terminal-source rule | Verdict |
|---|---|---|---|
| B1 | **Bash Single-Line Policy** (whole section) | It exists because the permissions matcher does a string-prefix match against `permissions.allow` and fails on line continuations ([#11932]). Independent of app vs terminal. | **Stays, unchanged.** Easy to mistakenly lump into "terminal stuff" — it isn't. |
| B2 | `OUTPUT-EDGE-CASES.md` § Terminal: "backticks render as command substitution", "escape `$VAR`", "one command per line" | These fire when text is pasted **into a shell** — a DESTINATION. The app changed the source, not the shell. | **Stays.** Reframe the section heading from "output the engineer will paste into a terminal" (source-flavored) to "output destined for a shell" (destination-flavored). |
| B3 | Layer 1: email / Slack → plain text; the whole `OUTPUT-EDGE-CASES.md` email + chat sections | Outlook/Gmail/Slack still don't render markdown. The app the engineer reads Claude in is irrelevant to how Outlook renders a paste. | **Stays.** |
| B4 | Layer 1: "No hard-wrapping of prose" | About the destination client soft-wrapping (email/Slack). Not a terminal-width rule despite the punch-card lineage note. | **Stays.** |
| B5 | Layer 0: never emit a credential value | Security. | **Stays.** |
| B6 | Layer 3: /tmp vs ~/Downloads | About whether the file leaves the machine. | **Stays.** |
| B7 | Layer 4: markdown for LLM-consumed docs | About the *reader being a model*, not the render surface. | **Stays.** |
| B8 | Command Safety (no chaining infra, output preservation, Rule 5) | About approval fatigue and non-idempotent command output — Claude's own Bash, not the engineer's paste. | **Stays.** |
| B9 | Remote/mobile mode | Unchanged, and *more* relevant now: native app pairs with the mobile companion. | **Stays** (and gains importance). |

### C. New capabilities the native app unlocks (enhancements, not relaxations)

The migration is not only about removing workarounds — the app exposes delivery channels the terminal never had. These are additive options for Layer 2/Layer 4.

| # | Capability | What it enables | Trade-off / caveat |
|---|---|---|---|
| C1 | **SendUserFile** (`display: 'render'` / `'attach'`) | A first-class "here is a file" channel — render inline in the side panel (charts, HTML, images, PDFs) or attach as a download card (source, spreadsheets). Replaces some "write to /tmp/ and `open`" flows with a surfaced deliverable. | None major; it sends local files, so the file still gets written first. |
| C2 | **Artifact** (HTML/Markdown → hosted side-panel page) | Engineer-visual HTML (comparison boards, decision matrices, reports) rendered in the claude.ai side panel instead of launching a browser via `open`. Shareable, versioned. | **Strict CSP: no external CDN.** The current `templates/html/*` depend on Mermaid + Chart.js via CDN → they would **not** render as Artifacts as-is. Either keep those on `/tmp/` + `open`, or rework templates to inline everything. This is a genuine decision, not a slam-dunk. |
| C3 | **visualize / show_widget** (inline SVG, diagrams, charts, interactive HTML) | Diagrams and small dashboards rendered *inline in the chat*, no file, no browser. | Good for one-off visuals; not a replacement for the full report templates. |

## Impact map — which documents change

- **`CLAUDE.md` § Output Policy** — the primary edit. Add the SOURCE-vs-DESTINATION framing (the core reframing above); rewrite Layer 1 and Layer 2 per A1–A5; optionally extend Layer 2/Layer 4 with the C1–C3 channels.
- **`OUTPUT-EDGE-CASES.md`** — reframe § Terminal and § Code-paste-into-IDE per B2/A3 (source → destination language; drop the line-count-to-file clause; keep the shell/IDE destination warnings).
- **`inject-output-policy-reminder.sh`** (UserPromptSubmit hook) — its injected text mirrors the policy; update it in lockstep so the reminder doesn't re-teach the old workaround every turn.
- **Not touched:** Bash Single-Line Policy, Command Safety, Layer 0/3/4-LLM, the email/Slack edge cases, no-hard-wrap. (Section B.)

## Decision — single unified, native-first policy (engineer, this session)

The engineer evaluated three architectures for a client-conditional policy (shared-base + injected delta; two full variants; single unified) and chose **one unified policy, native-first, with terminal caveats inline** — no conditional loading, no dependency on `CLAUDE_CODE_ENTRYPOINT`.

Rationale accepted: conditional delivery would have to fork behavior on an internal, undocumented, fail-silent env var (fragile), and two full variants would duplicate the ~90% shared rules and drift. The unified policy keeps a single source of truth; a terminal user simply reads native-default rules plus an inline "Terminal caveat" — the terminal rules stay correct when they apply, and nothing is duplicated.

**Consequence for the SOURCE/DESTINATION axis:** the policy now *defaults* to the native app as the SOURCE surface (rich markdown, per-block copy buttons). Each former terminal source-workaround is rewritten as a native default plus an inline `Terminal caveat:` note. DESTINATION rules (email/Slack/shell/IDE) are client-independent and stay as-is.

## Concrete edit plan (single unified rewrite)

- **`CLAUDE.md` § Output Policy** — add the SOURCE-vs-DESTINATION framing up top. Layer 1: keep the destination table; note that a fenced block is correct in the native-app chat (copy button strips it); `Terminal caveat:` bare/no-fences. Layer 2: rewrite the channel split from "short vs long" to **"copy vs run"** — copy-destined code → fenced chat block of any length (native default); run-destined/deliverable code → file; `Terminal caveat:` long copy-destined code → `/tmp/` + `open`.
- **`OUTPUT-EDGE-CASES.md`** — reframe § Terminal and § Code-paste-into-IDE from source-flavored to destination-flavored; drop the ">10 lines → file" clauses (A3/A4); keep the shell-semantics and IDE-auto-format warnings (B2, destination facts).
- **`inject-output-policy-reminder.sh`** — update the injected reminder text in lockstep so it stops re-teaching the old "long code → /tmp" workaround every turn.
- **Deferred (Section C):** SendUserFile-render, Artifacts side panel, inline widgets. C2 (Artifacts) is entangled with a template rework — the current `templates/html/*` use Mermaid/Chart.js via CDN, which the Artifact CSP blocks. Separate, later effort.

## Open sub-decisions (remaining)

1. **Section C mention** — in this unified rewrite, add a lightweight note that the native channels exist (SendUserFile render/attach, inline widgets) as available options, or defer *all* of Section C to the separate effort and keep this pass purely about relaxing the source-workarounds?
