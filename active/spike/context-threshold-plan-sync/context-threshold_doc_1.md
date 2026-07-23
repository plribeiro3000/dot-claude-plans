# Auxiliary — verbatim excerpts from official Claude Code documentation

Collected during research for `SPIKE.md` in this directory. Each excerpt is
quoted exactly as fetched, with its source URL and the date of fetch
(2026-07-22). These are preserved so the SPIKE's citations can be re-verified
without re-fetching, and so a revision of the spike can reference or requote
this material without a fresh web round-trip.

## 1. Hook lifecycle table (excerpt) — source: https://code.claude.com/docs/en/hooks

| Event | When it fires |
|---|---|
| `SessionStart` | When a session begins or resumes |
| `UserPromptSubmit` | When you submit a prompt, before Claude processes it |
| `PreToolUse` | Before a tool call executes; can block it |
| `PostToolUse` | After a tool call succeeds |
| `Stop` | When Claude finishes responding |
| `SubagentStop` | When a subagent finishes |
| `PreCompact` | Before context compaction |
| `PostCompact` | After context compaction completes |
| `SessionEnd` | When a session terminates |

## 2. Matcher patterns table (excerpt)

> `PreCompact`, `PostCompact` | what triggered compaction | `manual`, `auto`

## 3. Exit code 2 behavior table (excerpt)

> `PreCompact` | Yes | Blocks compaction
> `PostCompact` | No | Shows stderr to user only
> `Stop` | Yes | Prevents Claude from stopping, continues the conversation

## 4. Decision control table (excerpt)

> UserPromptSubmit, UserPromptExpansion, PostToolUse, PostToolUseFailure, PostToolBatch, Stop, SubagentStop, ConfigChange, PreCompact | Top-level `decision` | `decision: "block"`, `reason`. Stop and SubagentStop also accept `hookSpecificOutput.additionalContext` for non-error feedback that continues the conversation

## 5. Stop decision control — the "system reminder" sentence

> "Claude receives your reason as a system reminder and continues working in the same turn, so you can give Claude feedback without breaking the agentic loop."

## 6. `stop_hook_active` field

> "`stop_hook_active`: boolean, present and `true` when a `Stop` hook has already blocked this turn to prevent infinite loops. If your hook returns `decision: "block"` when `stop_hook_active` is already `true`, Claude Code shows your reason but doesn't block again, and the turn ends. Use this to avoid a scenario where a hook blocks, Claude retries, the hook blocks again, and so on indefinitely."

## 7. Stop event input schema

```json
{
  "session_id": "abc123",
  "prompt_id": "550e8400-e29b-41d4-a716-446655440000",
  "transcript_path": "/home/user/.claude/projects/.../transcript.jsonl",
  "cwd": "/home/user/my-project",
  "permission_mode": "default",
  "effort": { "level": "medium" },
  "hook_event_name": "Stop",
  "last_assistant_message": "..."
}
```

Field description quoted: "`last_assistant_message` | The final assistant
message text of the current turn, useful for hooks that need to evaluate what
Claude produced"

## 8. Hook output size cap

> "Hook output strings, including `additionalContext`, `systemMessage`, and plain stdout, are capped at 10,000 characters. Output that exceeds this limit is saved to a file and replaced with a preview and file path, the same way large tool results are handled."

## 9. Hook context persistence across resume/compaction

> "Claude Code saves the injected text in the session transcript. For mid-session events like `PostToolUse` or `UserPromptSubmit`, when you resume with `--continue` or `--resume`, Claude Code replays the saved text rather than re-running the hook for past turns, so values like timestamps or commit SHAs become stale. `SessionStart` hooks run again on resume with `source` set to `"resume"`, or `"fork"` if you added `--fork-session`, so they can refresh their context."

## 10. `transcript_path` common input field

> "`transcript_path` | Path to conversation JSON. The transcript file is written asynchronously and may lag the in-memory conversation, so it may not yet include the current turn's most recent messages when a hook fires."

## 11. UserPromptSubmit — additionalContext support

> "[UserPromptSubmit](#userpromptsubmit) and [UserPromptExpansion](#userpromptexpansion): alongside the submitted prompt" — listed under the "Add context for Claude" heading, confirming UserPromptSubmit is one of the events whose `hookSpecificOutput.additionalContext` is delivered to the model.

---

## 12. Status line — full JSON schema (excerpt) — source: https://code.claude.com/docs/en/statusline

```json
{
  "context_window": {
    "total_input_tokens": 15500,
    "total_output_tokens": 1200,
    "context_window_size": 200000,
    "used_percentage": 8,
    "remaining_percentage": 92,
    "current_usage": {
      "input_tokens": 8500,
      "output_tokens": 1200,
      "cache_creation_input_tokens": 5000,
      "cache_read_input_tokens": 2000
    }
  }
}
```

Field table quotes:

> "`context_window.context_window_size` | Maximum context window size in tokens. 200000 by default, or 1000000 for models with extended context."
>
> "`context_window.used_percentage` | Pre-calculated percentage of context window used"
>
> "`context_window.remaining_percentage` | Pre-calculated percentage of context window remaining"

Statusline is display-only — it is described throughout the page as: "The
status line is a customizable bar at the bottom of Claude Code that runs any
shell script you configure. It receives JSON session data on stdin and
displays whatever your script prints" — there is no mechanism documented on
this page for a statusLine script's output to feed back into the model's
context; its only documented output is the rendered text shown in the UI row.

Also relevant — the "Notifications share the status line row" troubleshooting
note: "Transient notifications such as the context-low warning also cycle
through this area." This confirms Claude Code has its own native, human-facing
context-low warning distinct from any hook mechanism.

---

## 13. Environment variables — auto-compact threshold controls (excerpt) — source: https://code.claude.com/docs/en/env-vars

> "`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`: Set the percentage (1-100) of the auto-compaction window at which auto-compaction triggers. Use lower values like `50` to compact earlier. This variable only causes earlier compaction when Claude Code compacts proactively: when `CLAUDE_CODE_AUTO_COMPACT_WINDOW` is set, in cloud sessions, and on Sonnet 4.6 and Opus 4.6 without extended context, which compact at the 200K boundary by default. On Sonnet 5, proactive compaction applies at the model's default threshold. In other cases, such as a local session on Opus 4.8, auto-compaction triggers when the conversation reaches the model's context limit. The override can only lower the threshold, so values above the default have no effect. Applies to both main conversations and subagents"

> "`CLAUDE_CODE_AUTO_COMPACT_WINDOW`: Set the context capacity in tokens used for auto-compaction calculations. Defaults to the model's context window, 200K for standard models or 1M for extended context models, except on Sonnet 5, which has its own default threshold. Use a lower value like `500000` on a 1M model to treat the window as 500K for compaction purposes. The value is capped at the model's actual context window. `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` is applied as a percentage of this value. Setting this variable decouples the compaction threshold from the status line's `used_percentage`, which always uses the model's full context window"

---

## 14. Model configuration — Sonnet 5 context window (excerpt) — source: https://code.claude.com/docs/en/model-config

> "### Extended context
>
> Fable 5, Sonnet 5, Opus 4.6 and later, and Sonnet 4.6 support a 1 million token context window for long sessions with large codebases."

> "#### Sonnet 5 context window
>
> On the Anthropic API, Sonnet 5 always runs with the 1M context window. There is no 200K variant, no `[1m]` suffix to select, and no usage credits required on any plan. Sessions auto-compact before the window fills, at about 967K tokens by default; set `CLAUDE_CODE_AUTO_COMPACT_WINDOW` to choose a different threshold."

This is the primary source for the ~96.7%-of-1M default auto-compact point on
Sonnet 5 (967,000 / 1,000,000 = 96.7%), fetched and read directly (not through
a summarizing pass) via the Read tool against the persisted WebFetch output at
`/Users/plribeiro3000/.claude/projects/-/570d2df6-8feb-474c-863e-8acbc38f3481/tool-results/toolu_01EebYSRW4p9PUHvHh2T8qGt.txt`,
lines 553-555.

---

## 15. GitHub issue excerpts

### #34340 — "Expose context window usage to hooks via environment variable"

> "Currently it approximates context usage by counting heavy tool calls (Read, Bash, WebFetch, WebSearch, Agent) and firing at a hardcoded threshold. This breaks when the context window size changes. I recently got upgraded from 200K to 1M context (Opus 4.6) and my hook started firing at ~25% instead of ~60% because the threshold was calibrated for the old window size."

Status: Closed as not planned.

### #25689 — "Context usage threshold hook event with plan-and-continue workflow"

> "`PreCompact` hook fires too late and cannot block compaction" (author's stated problem, as summarized/quoted by the fetch)

Proposed a new `ContextThreshold` hook event with `context_usage_pct`,
`context_used_tokens`, `context_max_tokens` in its payload, and a
`contextThresholds` setting (e.g. `[60, 80, 90]`), each firing once per
session. Status: Closed as not planned.

### #46695 — "context_threshold setting for auto-compact in settings.json"

> "A `context-monitor.sh` runs on every `PreToolUse` hook, counting tool calls as a proxy for context usage. At estimated 80%, it prints a warning that agent rules tell it to act on. However, the actual `/compact` still requires user input." (current workaround described by the issue author)

Status: Closed as duplicate.

### #66475 — "autoCompactThreshold setting"

> "In multi-worker Claude Code setups (multiple sessions working in parallel on the same repository), sessions regularly reach 100% context window utilization. At that point, the `/compact` command itself fails because there is no context space remaining for the compaction operation to execute." (problem statement)

Status: labeled `duplicate`, `stale`.

### #39099 — "Feature request: PreCompact / PostCompact hook events"

Requested exactly the `PreCompact`/`PostCompact` events that now exist in the
shipped hooks reference (see excerpt 1 above), listing "Writing a progress
summary to a file" as a motivating use case. Status shown as: "Closed as not
planned" — no maintainer reasoning was present in the fetched page. Whether
this issue has any causal link to the PreCompact/PostCompact events later
shipped could not be established from the fetched content; flagged as
uncertain in `SPIKE.md`.

---

## 16. Community implementation — claudefa.st context-recovery-hook

> "PreCompact hooks fire right before compaction happens - your last chance to capture state."

Checkpointing cadence described: 50K tokens used (initial checkpoint), every
10K tokens thereafter, and percentage thresholds (30%, 15%, 5% remaining) as
a safety net — token counts are derived from a **StatusLine** payload
(`context_window.remaining_percentage`), not from any hook payload:

> "StatusLine is different. It receives a JSON payload on every turn with `context_window.remaining_percentage`" ... "Most Claude Code hooks don't receive context metrics. PreToolUse, PostToolUse, Stop - none of them know how much context you've consumed."

Recovery workflow quoted: "Run /clear: Start a fresh session (cleaner than
continuing with compacted context). Load the backup: Read the markdown file
to restore context."

No explicit "reconcile against a plan document" step is described in this
implementation — it is a backup/restore pattern, not a plan-reconciliation
pattern.
