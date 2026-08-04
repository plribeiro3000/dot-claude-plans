# SPIKE — Full Bash Command Visibility in the Native Desktop App

## Investigation question

`~/.claude/CLAUDE.md` § Bash Single-Line Policy (line 47) carries this rule:

> "**Best-effort transparency, not a security boundary**: before executing a long command, the agent SHOULD print it explicitly so the engineer can read it before approving (format: `Executando o comando completo: <full command>`). This is advisory only — per Claude Code's own documentation, permission rules are enforced by Claude Code, not by the model, and prompt-level instructions do not change what Claude Code allows. The actual mechanical guarantee against an opaque or unreadable command is the PreToolUse block in `scripts/validate-bash-command.sh` — see § Command Safety Policy"

This rule was written for a **terminal** session, where the permission prompt truncated long commands. The engineer has moved to the **native desktop app** (`CLAUDE_CODE_ENTRYPOINT=claude-desktop`, engine v2.1.220, desktop shell v1.24012.9) and raised two points:

1. **Readability** — the current format is a single prose line with the command in inline backticks; a long command (300+ characters) wraps across many visual lines and is hard to read. The engineer wants a fenced code block instead.
2. **Guarantee** — the model does not always print the command. Is there a mechanical hook that can guarantee visibility, given the two hard hook constraints (10,000-character output cap; `hookSpecificOutput.hookEventName` must match the firing event) and the fact that a `PreToolUse` hook on `Task` cannot reach a subagent?

Six sub-questions were asked (see the original brief): (1) is the terminal-truncation premise still true in the desktop app; (2) which hook field reaches the user's eyes and is it Markdown-rendered; (3) is there a model-independent channel (e.g. rewriting the Bash tool's `description`); (4) what is the strongest available reinforcement tier, ranked, given a `Stop` hook fires only after the command already ran; (5) what should the prescribed format be, and is there a defensible length threshold; (6) what does the community/upstream say.

## Sources consulted

- [`~/.claude/scripts/validate-bash-command.sh`](file:///Users/plribeiro3000/.claude/scripts/validate-bash-command.sh) — read in full (744 lines); confirms the mechanical block layer exists but only rejects specific bad *shapes*, never renders the command back to the user.
- [`~/.claude/scripts/inject-output-policy-reminder.sh`](file:///Users/plribeiro3000/.claude/scripts/inject-output-policy-reminder.sh) — read in full (95 lines); the working template for a multi-event hook that reads `.hook_event_name` and echoes it back, and for emitting `additionalContext` only (no `permissionDecision`).
- `~/.claude/settings.json` — read in full; confirms **no currently-registered hook emits `systemMessage`** anywhere in the repo (grepped across all `scripts/*.sh`), and enumerates every `PreToolUse(Bash)` hook already firing per command.
- [Hooks reference](https://code.claude.com/docs/en/hooks) — fetched three times (self-check re-fetch per Citation Discipline rule 5) for: the `systemMessage`/`additionalContext` cap statement, the `additionalContext` timing table, and the full PreToolUse decision-control section.
- [Tools reference](https://code.claude.com/docs/en/tools-reference) — fetched and read in full (465 lines, confirmed via `wc -l`) for the Bash tool behavior section and the `description` field.
- [Settings reference](https://code.claude.com/docs/en/settings) — fetched; confirmed it does not document the Bash tool `description` field or permission-dialog truncation.
- GitHub issues #37235, #16289, #40380, #17356, #32624 (`anthropics/claude-code`) — each fetched directly, quotes verified against the fetched text.
- See auxiliary: `bash-visibility_log_1.txt` — raw `strings`/`grep` evidence extracted directly from the installed `/Applications/Claude.app/Contents/Resources/app.asar` on this machine (the only channel used to check installed-binary behavior, since a headless `stream-json` probe was already tried by the engineer and found inconclusive — no `PreToolUse` hook events appeared in that transcript at all).

## Findings

### Finding 1: the ~100-character truncation premise is documented only for Remote Control (mobile), never for the desktop app's own dialog

**Evidence:** GitHub issue #37235, "[FEATURE] Remote Control: allow expanding permission prompts on iOS to see the full command before approving," closed as not planned. Verbatim from the problem statement:

> "When using the Claude Code Remote Control feature from the Claude iOS app, permission approval prompts (Allow / Deny) only display approximately the first 100 characters of the command that Claude Code wants to execute. There is no way to expand, scroll, or otherwise view the full command text."

and:

> "This is especially important for long or complex bash commands, multi-line file edits, and any command involving paths or arguments that extend beyond the visible ~100 characters."

**Source:** https://github.com/anthropics/claude-code/issues/37235

**Significance:** The only documented, quotable truncation-length figure (~100 characters) in the entire research is scoped explicitly to the **iOS Remote Control** surface — a phone driving a session remotely — not the native desktop app running locally on the engineer's own Mac. No issue, doc, or binary-string evidence found in this research describes the desktop app's own local permission dialog truncating a command to any specific length. This means the "terminal truncated, so does the phone" chain the original rule assumed does NOT extend cleanly to "so does the desktop app" — that link has no direct evidence either way. This is the central open question the test plan below is built to close.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed via direct fetch of https://github.com/anthropics/claude-code/issues/37235 (two separate quoted sentences, both present in the returned issue body).

### Finding 2: `systemMessage` is documented as user-facing, but multiple confirmed reports say it silently fails to render for tool-related hook events

**Evidence:** The hooks reference states, verbatim, in its field table:

> "`systemMessage` | none | Warning message shown to the user"

Against that documented behavior, three separate GitHub issues report it not reaching the user:

- Issue #16289, "SubagentStop hook systemMessage not displayed in UI," closed as not planned: *"When a `SubagentStop` hook returns JSON with a `systemMessage` field, the message is not displayed in the Claude Code UI, despite documentation suggesting it should be shown to the user."* Reproduction confirmed the hook fires ("confirmed by testing with file logging") but nothing appears.
- Issue #40380, "[BUG] PreToolUse/PostToolUse warn hook systemMessage silently dropped without hookSpecificOutput," closed as not planned: *"`systemMessage` returned from a PreToolUse or PostToolUse hook without `hookSpecificOutput` is silently dropped — not shown to the user in the terminal and not injected into the model context."* Its stated root cause: *"Claude Code appears to require `hookSpecificOutput` to be present for tool hook events in order to process (and display) a response. Without it, the JSON output from the hook is parsed but the `systemMessage` has no rendering path."*
- Issue #32624 (referenced from #40380) shows the ACTUAL rendering format when `systemMessage` does display (for a `SessionStart` hook, a non-tool event): a terminal line prefixed `SessionStart:startup says: <message>` — plain text, not Markdown.

**Source:** https://code.claude.com/docs/en/hooks (field table); https://github.com/anthropics/claude-code/issues/16289; https://github.com/anthropics/claude-code/issues/40380; https://github.com/anthropics/claude-code/issues/32624

**Significance:** Two of the three reports concern *tool-related* events (`PreToolUse`/`PostToolUse`/`SubagentStop`) — exactly the event class that would carry a "here is the full command" message. All three are closed "not planned," meaning Anthropic did not commit to fixing the display gap. The one confirmed rendering format found (`<Event>:<matcher> says: <message>`) is plain text with a fixed prefix, not a Markdown-rendered block — so even where it works, a fenced ```bash block inside a `systemMessage` would not render as a code block; it would print literally with backticks. None of these reports are platform-scoped to "desktop app only" or "terminal only" in their titles, but #16289's environment is the desktop app on Linux/WSL2, and #40380's is Windows 11 — both non-macOS, non-terminal-CLI platforms, which weakens (but does not eliminate) applicability to a macOS terminal session specifically.

**Verification:** URL fetched / Verbatim quote checked / Quote substrings confirmed at: hooks reference field table (systemMessage row); issue #16289 body; issue #40380 body and "Root Cause" section; issue #32624 body (format string).

### Finding 3: direct binary inspection of the installed desktop app (v2.1.220-adjacent) shows zero occurrences of the literal string `systemMessage`, while sibling hook-field names are present

**Evidence:** `strings /Applications/Claude.app/Contents/Resources/app.asar` (252,211 extracted string lines) was searched for four hook JSON field names. Full command list and counts:

```
additionalContext         -> 4 occurrences
hookEventName              -> 5 occurrences
hookSpecificOutput          -> 5 occurrences
permissionDecisionReason     -> 3 occurrences
systemMessage (case-sensitive) -> 0 occurrences
"systemMessage" (quoted form)  -> 0 occurrences
```

The two case-insensitive hits for "systemmessage" are a distinct, unrelated internal option `includeSystemMessages` (conversation/transcript filtering, unrelated to the hooks contract) — confirmed by reading the surrounding minified code, reproduced in the auxiliary file.

**Source:** local file `/Applications/Claude.app/Contents/Resources/app.asar` on this machine; full command transcript and context snippets in `bash-visibility_log_1.txt` (this spike's auxiliary file).

**Significance:** JavaScript minifiers preserve object-key and string-literal tokens verbatim unless a property is accessed exclusively through a separately-mangled computed/bracket-notation variable — and the fact that `additionalContext`, `hookEventName`, and `hookSpecificOutput` all survive as literal, greppable strings in this exact bundle demonstrates the extraction method *would* have found `systemMessage` if the app's parsing code referenced it by that literal name anywhere. It does not appear even once, in any casing. This is independent, primary evidence (not a repeated GitHub-issue claim) that corroborates Finding 2: this specific installed build very likely does not read a `systemMessage` key off hook output at all. It cannot prove a negative with total certainty (a build-time constant or dead-code-eliminated path is theoretically possible), which is exactly why the test plan below includes a live, on-machine confirmation step.

**Verification:** Not a URL-based finding — reproducible local command evidence. Every count above was re-run and matches the auxiliary file's transcript exactly (self-check: re-ran `grep -c "systemMessage"` a second time before writing this Finding; same result, 0).

### Finding 4: `permissionDecisionReason` visibility is documented per decision value, but a platform-scoped bug report contradicts the documented `ask` behavior

**Evidence:** The hooks reference, PreToolUse decision-control section, verbatim:

> "`\"allow\"`: Approves the tool call. ... When you return `\"allow\"`, the `permissionDecisionReason` is ignored and not shown to the user."

> "`\"deny\"`: Blocks the tool call. The `permissionDecisionReason` is required and shown to the user as the reason the tool was blocked."

> "`\"ask\"`: Escalates to the user with a permission dialog. The `permissionDecisionReason` is shown in the dialog as the reason permission is needed."

Against that documented `ask` behavior, GitHub issue #17356, "CLI: permissionDecisionReason not displayed in permission prompt for PreToolUse 'ask' decisions" (labels `area:tui`, `bug`, `has repro`, `platform:linux`; environment "Claude Code CLI (not VS Code extension), Linux (WSL2)"; closed as not planned), reports the opposite result for a live repro:

> "The permission prompt appears but does not display the `permissionDecisionReason` or `systemMessage` fields. Users have no visibility into why the hook triggered the ask."

The issue itself quotes the hooks documentation as stating that, for `"ask"` decisions, the reason should be *"shown to user only, not to Claude"* — wording this investigation's own fetch of the current hooks reference did not turn up verbatim, so the two may reflect different documentation revisions; the discrepancy is noted rather than resolved.

The installed binary itself carries six live usage sites of `permissionDecisionReason` paired with `permissionDecision:"ask"` or `permissionDecision:"deny"`, all belonging to Claude Code's OWN internal/managed-policy gates (organization-policy approval, unattended-session denial, workflow-consent), e.g.:

```
{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:"This tool requires explicit approval regardless of permission mode."}}
```

**Source:** https://code.claude.com/docs/en/hooks (PreToolUse decision control section); https://github.com/anthropics/claude-code/issues/17356; local binary evidence in `bash-visibility_log_1.txt`.

**Significance:** The binary confirms the app's OWN internal features are BUILT on the ask/deny contract (six live call sites), which shows the code path for rendering an ask/deny reason exists in principle — but existence of the code path is not the same claim as "rendering succeeds for a user-authored hook," and issue #17356 reports it failing outright, not merely truncating or rendering as plain text, for a `PreToolUse` `ask` decision on the CLI (Linux/WSL2, explicitly not the VS Code extension). That report is unfavorable evidence against treating this channel as reliable: at minimum on one platform, the dialog appeared but the reason text was absent entirely. Whether the native desktop app on macOS shares this failure is untested by this research — the report's platform scope (CLI, Linux) does not extend automatically to a different interface (desktop app) on a different OS. Separately, every 4Shark command already covered by an `allow`-list entry never reaches this dialog at all (it auto-approves silently), so a hook returning `permissionDecisionReason` on an already-allowed command buys nothing regardless — the field is documented as "ignored and not shown" on `allow`. Even setting #17356 aside, the field would only have a plausible rendering path for the subset of commands that are NOT already allow-listed (roughly: `terraform apply/destroy/import/taint/untaint`, `terraform state rm/mv`, `aws ecs run-task`, `git tag`, `git rm`, `gh release create`, per `emit_ask()` calls in `validate-bash-command.sh`), or for a compound/opaque command the write-time guards escalate to `ask` via `emit_ask`. Whether the dialog, where it does show the reason, renders it as Markdown, plain text, or truncates it, remains unknown from any documentation (see Finding 6).

**Verification:** URL fetched / Verbatim quotes checked / Quote substrings confirmed at the hooks reference "PreToolUse decision control" section (all three quoted sentences present verbatim); issue #17356 (title, labels, environment, and the "does not display" quote present in the fetched issue body); local binary evidence re-confirmed via a second independent `grep -o` pass (see auxiliary file, "Site 1" through "Site 6").

### Finding 5: `additionalContext` from a `PreToolUse` hook reaches the model only on its NEXT request — after the current tool call already ran

**Evidence:** Hooks reference, verbatim:

> "Claude Code wraps the string in a system reminder and inserts it into the conversation at the point where the hook fired. Claude reads the reminder on the next model request, but it doesn't appear as a chat message in the interface."

and, on timing per event:

> "[PreToolUse](#pretooluse), [PostToolUse](#posttooluse), [PostToolUseFailure](#posttoolusefailure), and [PostToolBatch](#posttoolbatch): next to the tool result"

**Source:** https://code.claude.com/docs/en/hooks

**Significance:** This directly answers sub-question 4(a). A `PreToolUse` `additionalContext` injection about the command about to run is placed in context "next to the tool result" — i.e., it lands alongside the OUTCOME of the very call it was attached to, and the model only reads it on its next request. It is also explicitly "not a chat message in the interface," so the engineer never sees it rendered at all — it is a model-facing channel only, never a user-facing one. It is structurally unable to serve as "show the engineer the command before they approve it": by the time the reminder is inserted, the tool has already been dispatched (for an already-allowed command) or the dialog has already appeared with whatever the normal permission flow shows (for an `ask` command). This channel is useful for shaping the MODEL's future behavior (which is exactly how 4Shark's other `inject-*` hooks use it), not for improving what the ENGINEER sees at approval time.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed at the hooks reference `additionalContext` section and its event-timing table.

### Finding 6: no source found — whether the desktop app's `ask`/`deny` permission dialog Markdown-renders `permissionDecisionReason`, or truncates a long one, is undocumented and unreported

**Evidence:** Not found. Searches performed and their results:
- WebSearch for desktop-app-specific screenshots or issues describing the Bash permission dialog's command-rendering or line-wrapping behavior: no relevant issue or doc located (see Sources).
- Settings reference (https://code.claude.com/docs/en/settings) and Tools reference (https://code.claude.com/docs/en/tools-reference, read in full) were both fetched and neither documents the Bash tool's `description` input field being shown in any UI chip, nor any permission-dialog rendering/truncation behavior for a long command.
- Binary `strings` search for the actual dialog copy (e.g. "Allow Claude to run", "want to allow") and for a numeric truncation constant near command-rendering code returned no hits (see auxiliary file, "Search attempts that found nothing relevant" section) — most likely because the Electron renderer-process UI bundle is not the same asar segment searched, or the copy is composed from fragments at runtime.

**Source:** Absence confirmed across https://code.claude.com/docs/en/hooks, https://code.claude.com/docs/en/settings, https://code.claude.com/docs/en/tools-reference, and the local binary; WebSearch queries recorded in the session.

**Significance:** This is the load-bearing gap in the whole investigation, and it is the correct place to say "I don't know" rather than infer from training data. Sub-questions 2 (is the field Markdown-rendered) and 5 (what should the prescribed format be, format-wise) both terminate here: nobody — not the docs, not a GitHub issue, not the binary — states whether the desktop app's own permission dialog (distinct from the iOS Remote Control surface in Finding 1) truncates a long command or renders Markdown inside a reason/message field. This is exactly the kind of question the engineer's own house rule (`~/.claude/CLAUDE.md` § Bash Single-Line Policy, same section as the rule under investigation) says to settle by direct, isolated, live measurement rather than continued research — see the Test Plan below, which is built to close precisely this gap.

**Verification:** Absence-of-evidence Finding — no single URL sustains it; it is the conjunction of four searches, each individually re-run once to confirm no result was missed (hooks reference fetched three times total across this investigation; settings and tools-reference fetched once each and cross-checked against each other's "not found" language).

### Finding 7: the Bash tool's `description` field is a documented tool input, but nothing documents it being shown to the user as a UI summary/chip

**Evidence:** The hooks reference's own example `PreToolUse` payload shows the field existing on the tool call:

```json
"tool_input": {
  "command": "npm test",
  "description": "Run test suite",
  ...
}
```

The Tools reference's full "Bash tool behavior" section (https://code.claude.com/docs/en/tools-reference, read in full — 465 lines confirmed via `wc -l` against the fetched, persisted copy) documents "What persists between commands," "Timeout and output limits," and "Background commands" for the Bash tool, and contains no sentence describing the `description` field, what it is used for, or whether/how it is surfaced in the UI.

**Source:** https://code.claude.com/docs/en/hooks (example payload); https://code.claude.com/docs/en/tools-reference (full Bash tool section, absence confirmed)

**Significance:** This answers sub-question 3's `updatedInput`-on-`description` idea only partially: the field demonstrably exists as a tool-input parameter a hook's `updatedInput` COULD rewrite (the mechanism the hooks reference documents for `updatedInput` generally — "replaces a tool's arguments before it runs when you return `\"allow\"`"), but there is no documented evidence that doing so would change anything the engineer sees, because there is no documented evidence the field is shown to the engineer at all in either the terminal or the desktop app. Proposing to overwrite it on the theory that it "is shown in a UI chip" (as the original brief speculated) is not supported by anything found in this research; it is also the field 4Shark's own single-line-command convention already asks the model to fill with a human-readable summary (5-10 words per the `Bash` tool's own guidance quoted in the environment info, not independently re-verified here), so rewriting it with the full command text would destroy that existing, working use rather than add a new one.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed at the hooks reference example payload (`"description": "Run test suite"`); absence confirmed by full read of the Tools reference Bash section (`wc -l` = 465, matching the persisted fetched file exactly).

### Finding 8: the 10,000-character hook-output cap is confirmed verbatim and applies identically to `systemMessage`, `additionalContext`, and plain stdout

**Evidence:** Hooks reference, verbatim (re-fetched and re-confirmed a second time in this session, matching the text already quoted at `~/.claude/CLAUDE.md:198`):

> "Hook output strings, including `additionalContext`, `systemMessage`, and plain stdout, are capped at 10,000 characters. Output that exceeds this limit is saved to a file and replaced with a preview and file path, the same way large tool results are handled."

**Source:** https://code.claude.com/docs/en/hooks; cross-referenced against `~/.claude/CLAUDE.md:198` (already-established 4Shark fact, same wording).

**Significance:** Not new information — this closes sub-question 4 by confirming the cap is real and applies to every candidate output channel discussed above equally. It is not the reason `systemMessage` fails to render in Findings 2–3 (a 300-character command is nowhere near 10,000 characters); the cap only matters if a future design tried to inject a large batch of commands or a full doc body through one of these channels.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed at the hooks reference "JSON output" section (identical wording to the existing CLAUDE.md citation, confirming CLAUDE.md's own citation of this doc is accurate).

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Keep current rule as-is (prose line, inline backticks, model-driven) | Zero engineering cost; already exists | Readability complaint stands (long commands wrap badly in inline-code styling); "not always" reliability complaint stands — nothing enforces it (Findings 2, 5) | Engineer's own complaint; `~/.claude/CLAUDE.md:47` |
| Reformat the SAME model-driven echo as a fenced ```bash block instead of inline backticks | Directly answers the readability complaint; the native app's per-block copy button already makes a fenced block the "right shape" for this per 4Shark's own established Output Policy finding (`~/.claude/CLAUDE.md:887`, `:930`); zero new mechanism, pure prompt-text change | Does NOT touch the reliability complaint — the model still "does not always" do it, because nothing enforces it (still advisory, per Finding 5's model-only channel) | 4Shark's own Output Policy (already-established); Finding 5 |
| `PreToolUse` hook returns `permissionDecision:"ask"` + `permissionDecisionReason` containing the full command, for long/opaque commands specifically | Genuinely mechanical and model-independent for the subset of commands that reach `ask`, and the app's own internal features rely on the same ask/deny contract (Finding 4) | Does nothing for the vast majority of 4Shark commands, which are already `allow`-listed and never show a dialog at all (Finding 4 — `permissionDecisionReason` is "ignored and not shown" on `allow`); would newly force manual approval on commands that currently auto-approve, reintroducing the exact "approval fatigue" 4Shark's Command Safety Policy fights; a platform-scoped bug report (issue #17356, CLI/Linux) found the reason text failing to display at all for an `ask` decision, not just rendering as plain text or truncating (Finding 4) — untested whether the desktop app on macOS shares that failure; even where it displays, whether it Markdown-renders or truncates is unknown (Finding 6) | Findings 4, 6; `~/.claude/docs/COMMAND-SAFETY.md` (approval-fatigue framing already in CLAUDE.md) |
| `PreToolUse` hook rewrites the Bash tool's `description` field via `updatedInput` to carry the full command | Mechanically guaranteed to change what field the tool call carries, regardless of what the model chose to write in prose | No evidence found that `description` is shown to the engineer anywhere (Finding 7) — could be pure engineering cost for zero visibility gain; overwrites the field's one KNOWN, documented purpose (a short human-readable action summary) with something it was not designed to hold | Finding 7 |
| Do nothing mechanical; strengthen the per-turn `UserPromptSubmit`/`SubagentStart` prose reminder only | Cheap; matches the established pattern (`inject-output-policy-reminder.sh` already re-injects Output Policy every turn) | Still advisory — a reminder the model can and (per the engineer's own report) sometimes does ignore; does not close the reliability gap the engineer explicitly asked about | `inject-output-policy-reminder.sh` (read in full); engineer's own complaint |
| Accept that "full visibility" is now a solved problem for AUTO-APPROVED commands specifically, because the native app already shows the actual `tool_input.command` in the (collapsed or expanded) tool-call UI regardless of any hook, and re-scope the rule to only the OPAQUE/long-and-actually-approval-gated case | Matches the SOURCE-vs-DESTINATION framing 4Shark already uses (`~/.claude/CLAUDE.md:887`) — the terminal-truncation problem may simply not exist in the native app for the ordinary case; would eliminate the rule's cost entirely for the common case | Rests on Finding 1's gap — nobody has actually confirmed the native app's own tool-call UI (as opposed to the ask-dialog) shows a long command untruncated; this is exactly what the Test Plan below must confirm before this option can be taken | Finding 1; Finding 6 |

## What remains uncertain

- **Whether the desktop app's own local permission dialog (for an `ask`/`deny` decision) truncates a long command or the `permissionDecisionReason` text at any length.** The only truncation figure found (~100 characters) is explicitly scoped to the iOS Remote Control surface (Finding 1), not the local native app.
- **Whether `permissionDecisionReason` renders at all on an `ask` decision in the desktop app.** Issue #17356 reports it failing to display entirely — not merely truncating — for a `PreToolUse` `ask` decision on the CLI (Linux/WSL2). That report's platform scope is narrower than the desktop-app/macOS case this investigation is about, so it neither confirms nor rules out the same failure there (Finding 4). This is a distinct question from the truncation question above: the CLI/Linux report is about the field never appearing, not about how much of it appears.
- **Whether the desktop app Markdown-renders `permissionDecisionReason` or `systemMessage` where either does display**, or shows it as plain text (the one confirmed rendering format, from issue #32624, is a plain-text `Event:matcher says: message` prefix for a non-tool `SessionStart` hook — untested for `PreToolUse`/`ask`).
- **Whether the collapsed/expanded tool-call UI chip for an ALREADY-AUTO-APPROVED Bash command in the native app shows the full `tool_input.command` untruncated.** This is arguably the most important unresolved point, because it is where the vast majority of 4Shark's commands live (allow-listed, no dialog at all) — if the chip already shows the full command on demand (e.g. via expand), the entire rule may be solving a problem the native app no longer has.
- **Whether `systemMessage`'s absence from the installed binary (Finding 3) is a permanent architectural fact of this build or an artifact of the specific asar segment searched** (the interactive dialog may be rendered by a separate, unsearched renderer-process bundle).

## Suggested options for main and the engineer

- **Option A — reformat only.** Keep the rule model-driven and advisory (unchanged reliability profile), but change the prescribed format from an inline-backtick prose line to a fenced ```bash block, matching 4Shark's own already-adopted Output Policy reasoning that a fenced block is now the correct shape for the native app. Zero new mechanism. Does not address "the model does not always do it."
- **Option B — targeted `ask` escalation for opaque commands only.** Add a `PreToolUse` hook that returns `permissionDecision:"ask"` with the full command in `permissionDecisionReason` ONLY for commands that are long (a threshold TBD) AND not already covered by an `allow` rule — i.e., commands that would already stop and prompt. This is mechanically guaranteed to at least trigger a dialog for that subset (Finding 4), but issue #17356 reports the reason text can fail to display at all on at least one platform (CLI/Linux) rather than merely rendering plainly or truncating, and its actual on-screen shape on the desktop app/macOS (whether it displays, and if so Markdown or not, truncated or not) is unverified until the Test Plan below is run.
- **Option C — run the Test Plan first, then decide.** Treat Findings 1, 4, and 6 as genuinely unresolved and use the concrete test plan below to establish, empirically, whether the native app's ordinary tool-call UI already shows a long auto-approved command in full, and whether an `ask` dialog's reason text displays at all on this platform. If the chip already shows the full command, the rule may need no mechanical change at all — only the reformat in Option A. If not, and if Test 2 shows the reason text displays reliably, Option B (or a variant) becomes the candidate to prototype; if Test 2 replicates #17356's failure, Option B is not viable as designed.
- **Option D — combine A + C.** Ship the low-cost reformat (Option A) immediately since it has no dependency on the open questions, and treat the reliability/mechanism question (Options B/C) as a separate, follow-on decision gated on the Test Plan's result.

(No recommendation among these — the evidence shows the trade-offs above; main and the engineer choose.)

## Test Plan — concrete, runnable, empirical

Purpose: close Findings 1, 4, and 6 (the genuinely open questions) with direct observation on the engineer's own machine, in the native desktop app, mirroring the methodology 4Shark already used to settle the `$HOME`-vs-`~` allow-list question (a throwaway hook loaded via `claude --settings <file>`, one variable changed at a time against a live control).

### Test 1 — does the native app's ordinary (auto-approved) Bash tool-call chip show a long command in full?

1. In the native desktop app, ask the session to run a bash command with a genuinely long, harmless, already-allow-listed shape, e.g.:
   `echo "AAAAAAAAAA...[300+ characters, easy to eyeball]...ZZZZZZZZZZ"`
   (use `echo`, which is in `permissions.allow` — see `~/.claude/settings.json:174` — so no dialog appears at all; this test is specifically about the collapsed/expanded tool-call CHIP, not a permission dialog).
2. Observe the collapsed tool-call chip in the transcript. Record: does it show a truncated preview, or the full command?
3. Click/expand the chip (if the UI supports expansion). Record: does the expanded view show the full 300+ character command untruncated?
4. **Falsification**: if step 3 shows the full command untruncated, Finding 1's gap is closed in the DIRECTION of "the native app already solves this for auto-approved commands" — supporting Option C's "may need no mechanical change" branch. If the expanded view is STILL truncated or there is no expand affordance, the gap remains open in the other direction — supporting Option B.

### Test 2 — does the native app's `ask` dialog display `permissionDecisionReason` at all, does it render Markdown, and does it truncate?

This test has three questions, not one, because Finding 4 surfaced a prior report (issue #17356) that the reason text can fail to display AT ALL on `ask` — a different failure than truncation or plain-text rendering. Steps 3(a)–3(c) below test each question separately so a result on one does not get conflated with the others.

1. Create a throwaway hook file (not committed to `~/.claude/`, per Configuration Changes Policy — use a scratch settings file the way the `$HOME`-vs-`~` test did):
   ```json
   {
     "hooks": {
       "PreToolUse": [
         {
           "matcher": "Bash",
           "hooks": [
             {
               "type": "command",
               "command": "echo '{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"ask\",\"permissionDecisionReason\":\"TEST — full command follows:\\n\\n\\u0060\\u0060\\u0060bash\\necho hello-world-visibility-test\\n\\u0060\\u0060\\u0060\"}}'"
             }
           ]
         }
       ]
     }
   }
   ```
   (the ``` sequences are backticks — a fenced ```bash block inside the JSON string value.)
2. Launch a throwaway session with this settings file layered in (`claude --settings <scratch-file-path>`) and trigger any Bash command.
3. Observe the resulting dialog. Record separately: (a) does the reason text appear ANYWHERE in the dialog — this is the #17356 replication check, answered yes/no before looking at formatting; (b) if it appears, is the fenced ```bash block rendered as a visually distinct code block, or does it show literal backtick characters; (c) if it appears, is the reason text cut off at any visible character count.
4. Repeat with a `permissionDecisionReason` string of ~500 characters (comfortably under the 10,000-character hook cap from Finding 8) to specifically probe for a UI-level truncation independent of the hook-output cap.
5. **Falsification**: if 3(a) is NO, this platform (desktop app/macOS) replicates issue #17356's failure and Option B is not viable as designed — the whole approach needs a different mechanism, not a format tweak. If 3(a) is YES and 3(b) shows a rendered code block, Option B's format proposal (fenced block in the ask reason) is validated as achieving the readability goal for the subset of commands it covers. If 3(a) is YES and 3(b) shows literal backticks, the format inside `permissionDecisionReason` must stay plain text regardless of which mechanism is chosen. If 3(c)/step 4 shows truncation at some length under 10,000, record the exact length observed — that becomes the only defensible, MEASURED length threshold for sub-question 5 (nothing else in this research grounds a number; per the citation-discipline rule, do not invent one).

### Test 3 — does `systemMessage` genuinely never render for a `PreToolUse` hook in the desktop app (confirming Finding 2/3 empirically, not just from GitHub reports and binary silence)

1. Same throwaway-settings mechanism as Test 2, but the hook emits ONLY:
   ```json
   {"systemMessage": "TEST — if you can read this, systemMessage renders on PreToolUse in the desktop app."}
   ```
   with no `hookSpecificOutput` at all (matching the exact repro shape from issue #40380).
2. Trigger a Bash command in the native desktop app session.
3. **Falsification**: if the message appears anywhere in the UI, Findings 2 and 3 are wrong for this build/platform and must be corrected — the binary-silence finding would then need re-examination (likely meaning the renderer-process bundle that handles this was not the segment searched). If nothing appears, Findings 2 and 3 are empirically confirmed, not merely inferred from third-party bug reports and static analysis.

Each test is a single isolated variable, matches the "one variable at a time against a live control" method `~/.claude/CLAUDE.md` already establishes as the team's standard for this exact class of question, and produces a falsifiable, recordable observation — not a subjective impression.
