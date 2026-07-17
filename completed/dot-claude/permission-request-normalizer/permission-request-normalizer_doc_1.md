<!-- Fetched excerpts — https://code.claude.com/docs/en/hooks — retrieved 2026-07-16 -->
<!-- WebFetch on this page is answered by a summarizing sub-model over converted
     markdown, not a raw page dump. Multiple targeted queries against the SAME
     URL on the SAME day returned DIFFERENT slices of the page (see the
     "Self-check instability" note at the bottom) — this is a tool limitation,
     not a claim that the page content changed intra-day. Excerpts below are
     the highest-confidence extraction obtained per topic; instability is
     flagged inline where it occurred. -->

# Hooks reference — PermissionRequest-specific excerpts

## Hook lifecycle — full event table (ordering evidence)

Quoted section preamble:

> "Hooks fire at specific points during a Claude Code session. When an event fires and a matcher matches, Claude Code passes JSON context about the event to your hook handler. [...] Events fall into three cadences: once per session: `SessionStart` and `SessionEnd`; once per turn: `UserPromptSubmit`, `Stop`, and `StopFailure`; on every tool call inside the agentic loop: `PreToolUse` and `PostToolUse`"

Relevant rows from the full lifecycle table, in the order the table lists them (table order, not a separately-stated execution-order guarantee):

| Event | When it fires |
|---|---|
| `PreToolUse` | Before a tool call executes. Can block it |
| `PermissionRequest` | When a permission dialog appears |
| `PermissionDenied` | When a tool call is denied by the auto mode classifier. Return `{retry: true}` to tell the model it may retry the denied tool call |
| `PostToolUse` | After a tool call succeeds |

**No sentence found anywhere on the page, after five separate targeted queries, that explicitly states "if a PreToolUse hook blocks the call, PermissionRequest never fires."** This is an inference from combining two independently-quoted facts (see SPIKE's Finding A body): (1) `PermissionRequest` fires only "When a permission dialog appears" (this table); (2) "A hook that exits with code 2 stops the tool call before permission rules are evaluated" (Configure permissions doc, quoted in the sibling spike's `command-form-redirect-hook_doc_1.md`). A dialog is part of permission-rule evaluation, so a call stopped BEFORE that evaluation cannot reach the point where a dialog — and therefore `PermissionRequest` — would fire. Presented as an inference, not a direct quote.

## PermissionRequest decision control (full section, one high-confidence fetch)

> "`PermissionRequest` fires when a permission dialog appears. Your hook can allow or deny the permission on behalf of the user, optionally modifying the tool's input or applying permission rules so the user isn't prompted again for similar calls."
>
> "Return a JSON object with `hookSpecificOutput` containing `hookEventName: "PermissionRequest"` and a `decision` object:"

Field table (as extracted):

| Field | Required | Description |
|---|---|---|
| `behavior` | yes | `"allow"` or `"deny"`. Use `"allow"` to approve the tool call on behalf of the user, or `"deny"` to reject it |
| `updatedInput` | no | Tool input object that replaces the original before the tool runs. Only applies when `behavior` is `"allow"`. For a Bash tool, this is an object with a `command` field. For file edit tools, this is an object with fields like `file_path`, `file_content`, etc. See the tool's input schema for details |
| `addPermissionRules` | no | Array of permission rule strings to add to the session's permission rules. Each rule uses permission rule syntax, such as `"Bash(npm *)"` or `"Write(src/*.ts)"`. Rules added this way are remembered for the rest of the session, so the user won't be prompted again for matching tool calls |
| `message` | no | Message shown to the user explaining why the permission was allowed or denied |

The load-bearing paragraph on re-validation (quoted in full):

> "When `behavior` is `"allow"` and you provide `updatedInput`, Claude Code re-validates the updated input against your project's permission rules. If the updated input matches a deny rule, the tool call is rejected and the user sees the denial reason, not your hook's message. This safety check prevents hooks from accidentally circumventing security policies. To avoid re-validation, omit `updatedInput` and only modify the tool call if it already matches an allow rule."

Two worked examples given on the page:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow",
      "message": "npm is an approved package manager",
      "addPermissionRules": ["Bash(npm *)"]
    }
  }
}
```

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "deny",
      "message": "Database writes require manual approval in production"
    }
  }
}
```

**Self-check instability (Citation Discipline rule 5).** Two subsequent re-fetches of the same URL, asked to confirm the exact substrings `"Claude Code re-validates the updated input against your project's"` and `"Rules added this way are remembered for the rest of the session, so the user won't be prompted again for matching tool calls"`, both failed to reproduce them — one explicitly stated "the documentation content cuts off before reaching the ... section", the other returned a flat "No" with no explanation. This is consistent with the fetch tool serving a summarized/truncated slice of the page per query rather than the full raw HTML every time (the tool's own behavior note in `command-form-redirect-hook_doc_2.md` from the prior spike already documented this: "WebFetch on this page is answered by a summarizing sub-model over converted markdown, not a raw page dump"). The positive fetch above was a single, internally consistent, detailed extraction (full field table + two matching JSON examples, structurally consistent with the known `hookSpecificOutput.decision.*` shape and independently corroborated by the shape mismatch reported in `anthropics/claude-code#19298`, see `permission-request-normalizer_doc_2.md`) — treated as high-but-not-certain confidence. **The engineer should view `code.claude.com/docs/en/hooks` § "PermissionRequest decision control" directly before the safety design is finalized**, given this instability.

## Exit-code-2 behavior for PermissionRequest

| Hook event | Can block? | What happens on exit 2 |
|---|---|---|
| `PermissionRequest` | Yes | Denies the permission |

## Fail-open error handling (general, applies to PermissionRequest as "most hook events")

> "Any other exit code is a non-blocking error for most hook events. The transcript shows a `<hook name> hook error` notice followed by the first line of stderr, so you can identify the cause without `--debug`. Execution continues and the full stderr is written to the debug log."

Only `WorktreeCreate` is documented as failing closed:

> "`WorktreeCreate` | Yes | Any non-zero exit code causes worktree creation to fail"

**Significance for this spike**: a broken/malformed PermissionRequest hook (crash, bad JSON) does not silently auto-approve anything. Per the table above, exit 2 explicitly denies; per the fail-open quote, any other error is non-blocking and "execution continues" — which, in context, means the call falls through to the normal permission flow (the dialog the hook was supposed to intercept). Both failure modes are safe-by-default: deny or prompt, never silent allow.

## Debugging / testing surface

> "Type `/hooks` in Claude Code to open a read-only browser for your configured hooks. The menu shows every hook event with a count of configured hooks, lets you drill into matchers, and shows the full details of each hook handler. Use it to verify configuration, check which settings file a hook came from, or inspect a hook's command, prompt, or URL."

> "Selecting a hook opens a detail view showing its event, matcher, type, source file, and the full command, prompt, or URL. The menu is read-only: to add, modify, or remove hooks, edit the settings JSON directly or ask Claude to make the change."

Hook source locations listed by the menu: `User` (`~/.claude/settings.json`), `Project` (`.claude/settings.json`), `Local` (`.claude/settings.local.json`), `Plugin`, `Session` (registered in memory for the current session), `Built-in`.

No dedicated "dry-run" or "would this be allowed" test command was found for hooks specifically (consistent with the sibling spike's Finding B2, which found no first-party pre-flight query mechanism at all).

## Parallel execution / deduplication (general, re-confirms the sibling spike's Finding A3)

> "All matching hooks run in parallel, and identical handlers are deduplicated automatically. Command hooks are deduplicated by command string and `args`, and HTTP hooks are deduplicated by URL."

## `async` / `asyncRewake` — scope unresolved for PermissionRequest specifically

Both fields were found ONLY inside the generic "Command hook fields" table (a table describing fields available on any `type: "command"` hook registration, not scoped to one event):

| Field | Required | Description |
|---|---|---|
| `async` | no | If `true`, runs in the background without blocking. See "Run hooks in the background" |
| `asyncRewake` | no | If `true`, runs in the background and wakes Claude on exit code 2. Implies `async`. The hook's stderr, or stdout if stderr is empty, is shown to Claude as a system reminder so it can react to a long-running background failure |

**No sentence was found, after a targeted query, either confirming or excluding `async`/`asyncRewake` specifically for the `PermissionRequest` event.** A separate, less-targeted fetch (not reproduced here because it could not be re-confirmed) asserted "The event does not support async or asyncRewake fields... PermissionRequest is a synchronous blocking event" — this was a synthesized inference from the fetch tool, not a directly quoted sentence, and is DROPPED per Citation Discipline rule 1 (quote-or-drop). Treated as unresolved, not as fact in either direction.

## `hookEventName` requirement (re-confirms ADR-001's general rule for this specific event)

Every worked example above echoes `"hookEventName": "PermissionRequest"` inside `hookSpecificOutput`. Consistent with the general rule already documented in `~/.claude/docs/adr/ADR-001-rules-loading-mechanism.md`'s citation elsewhere in this repo's CLAUDE.md: "`hookSpecificOutput.hookEventName` must name the event that actually fired, or the harness discards the block."

## Minimum version — not found on this page

No sentence stating a minimum Claude Code version specifically for the `PermissionRequest` event was found on `code.claude.com/docs/en/hooks`. See `permission-request-normalizer_doc_2.md` for the (unverified) external claim and why it could not be independently confirmed.
