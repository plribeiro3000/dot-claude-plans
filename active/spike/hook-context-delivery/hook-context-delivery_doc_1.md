# Auxiliary source 1 — Claude Code hooks reference

Source URL: https://code.claude.com/docs/en/hooks
(Canonical as of 2026-07-15. Note: `https://docs.claude.com/en/docs/claude-code/hooks` returns HTTP 301 → `https://code.claude.com/docs/en/hooks`.)

Fetched: 2026-07-15. Excerpts below are verbatim quotes returned by WebFetch against the page.

---

## 1. Output size cap (heading: "JSON output")

> "Hook output strings, including `additionalContext`, `systemMessage`, and plain stdout, are capped at 10,000 characters. Output that exceeds this limit is saved to a file and replaced with a preview and file path, the same way large tool results are handled."

This quote was confirmed on two independent fetches of the same URL (initial extraction + targeted self-check fetch), returning identical wording both times.

## 2. `additionalContext` placement by event

> "SessionStart, Setup, SubagentStart: at the start of conversation, before first prompt"
> "UserPromptSubmit, UserPromptExpansion: alongside the submitted prompt"
> "PreToolUse, PostToolUse, PostToolUseFailure, PostToolBatch: next to tool result"
> "Stop, SubagentStop: at end of turn (conversation continues)"

## 3. stdout handling

> "For most events, stdout is written to the debug log but not shown in the transcript. The exceptions are `UserPromptSubmit`, `UserPromptExpansion`, and `SessionStart`, where stdout is added as context that Claude can see and act on."

## 4. `transcript_path` (common input field, all events)

> "Path to conversation JSON. The transcript file is written asynchronously and may lag the in-memory conversation, so it may not yet include the current turn's most recent messages when a hook fires. Hooks that need the final assistant text of the current turn should use `last_assistant_message` on Stop and SubagentStop instead of reading the transcript"

PreToolUse input example confirming the field is present:

```json
{
  "session_id": "abc123",
  "prompt_id": "550e8400-e29b-41d4-a716-446655440000",
  "transcript_path": "/home/user/.claude/projects/.../transcript.jsonl",
  "cwd": "/home/user/my-project",
  "permission_mode": "default",
  "hook_event_name": "PreToolUse",
  "tool_name": "Bash",
  "tool_input": { "command": "npm test" }
}
```

## 5. PreToolUse JSON output fields

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Database writes are not allowed",
    "updatedInput": { "command": "npm run lint" },
    "additionalContext": "Additional info for Claude"
  }
}
```

`permissionDecision`: `"allow"`, `"deny"`, `"ask"`, or `"defer"`.

## 6. SubagentStart

> "When a subagent is spawned."

- Supports `additionalContext` in `hookSpecificOutput`
- Can't block or make decisions (information only)
- Matches on agent type (e.g. `"general-purpose"`, `"Explore"`, custom names)
- Exit code 2 stderr renders as a hook error notice in the subagent's transcript

## 7. InstructionsLoaded event

Fires when a CLAUDE.md or `.claude/rules/*.md` file is loaded into context — at session start and when files are lazily loaded during a session.

Matchers filter by load reason: `session_start`, `nested_traversal`, `path_glob_match`, `include`, `compact`.

Blocking: **No.**

> `InstructionsLoaded` | No | Exit code is ignored

## 8. Events that CAN block (exit code 2 / decision fields have effect)

PreToolUse, PermissionRequest, UserPromptSubmit, UserPromptExpansion, Stop, SubagentStop, TeammateIdle, TaskCreated, TaskCompleted, ConfigChange, PostToolBatch, PreCompact, Elicitation, ElicitationResult, WorktreeCreate.

`SubagentStart` is NOT in this list.

## 9. Timeout defaults

> "Defaults: 600 for `command`, `http`, and `mcp_tool`; 30 for `prompt`; 60 for `agent`. UserPromptSubmit lowers the `command`, `http`, and `mcp_tool` default to 30, and MessageDisplay lowers it to 10"

A targeted fetch asking what happens to output on timeout returned: the documentation does not contain explicit verbatim statements about what happens to a hook's output or `additionalContext` when a timeout is reached, and contains no SubagentStart-specific timeout behavior.
