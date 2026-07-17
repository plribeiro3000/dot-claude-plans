<!-- Fetched excerpt — https://code.claude.com/docs/en/hooks — retrieved 2026-07-16 -->
<!-- WebFetch on this page is answered by a summarizing sub-model over converted
     markdown, not a raw page dump — the excerpts below are the verbatim quotes
     the tool returned across four separate targeted fetches on 2026-07-16.
     Sections the tool reported as "not found" after a direct, narrow query are
     recorded as such below; see SPIKE.md "What remains uncertain" for what this
     means for the mechanism question. -->

# Hooks reference (excerpt)

## PreToolUse hookSpecificOutput — schema

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Database writes are not allowed",
    "updatedInput": {
      "command": "npm run lint"
    },
    "additionalContext": "This file is generated. Edit src/schema.ts and run `bun generate` instead."
  }
}
```

Field descriptions, as returned by the fetch tool from the reference table:

| Field | Description |
|---|---|
| `hookEventName` | Name of the event that fired (required for hookSpecificOutput) |
| `permissionDecision` | Control decision: `"allow"`, `"deny"`, `"ask"`, or `"defer"` |
| `permissionDecisionReason` | Explanation for the permission decision |
| `updatedInput` | Directly replaces the tool's arguments before it runs |
| `additionalContext` | String passed into Claude's context window as a system reminder |

## Parallel execution — "Common fields" / "Hook handler fields"

> "All matching hooks run in parallel, and identical handlers are deduplicated automatically. Command hooks are deduplicated by command string and `args`, and HTTP hooks are deduplicated by URL."

The fetch tool was asked explicitly, in a separate targeted query, whether one hook's `updatedInput` feeds into the NEXT hook's input (i.e., sequential chaining) or whether all matched hooks see the same original `tool_input`. Its answer:

> "The document does NOT specify that one hook's `updatedInput` feeds into the next hook's input. Given the parallel execution model, hooks run against the original input, not sequentially rewritten versions. Each hook sees the same original `tool_input`." [tool's own inference from the parallel-execution statement above, not a direct quote of the source]

## The `if` field (conditional hook matching)

> "Permission rule syntax to filter when this hook runs, such as `"Bash(git *)"` or `"Edit(*.ts)"`. The hook command only runs if the tool call matches the pattern."

Example the tool extracted from the reference:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "if": "Bash(rm *)",
            "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/block-rm.sh",
            "args": []
          }
        ]
      }
    ]
  }
}
```

> "The `if` field is optional; without it, every handler in the matched group runs. It uses the same syntax as permission rules and is only evaluated on tool events (`PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `PermissionDenied`)."

## Output character cap

> "Hook output strings, including `additionalContext`, `systemMessage`, and plain stdout, are capped at 10,000 characters. Output that exceeds this limit is saved to a file and replaced with a preview and file path, the same way large tool results are handled."

## Explicitly NOT FOUND despite four separate targeted queries against this page (2026-07-16)

1. Whether multiple PreToolUse hooks matched to the same event/matcher have a documented CONFLICT RESOLUTION rule when they return different `permissionDecision` values. The fetch tool's own words: "the documentation does not describe what happens when multiple PreToolUse hooks match the same tool call and return conflicting decisions [...] There is no section addressing decision prioritization or conflict resolution strategies."
2. Whether a command rewritten via `updatedInput` is re-validated against the `permissions.allow`/`ask`/`deny` rule lists before running, or runs directly without re-matching. Fetch tool's own words: "The documentation does not specify whether: Tool input rewritten by updatedInput in a PreToolUse hook is re-validated against the deny/ask/allow permission rules [...] This represents a gap in the documented behavior for decision control with input modification."
3. A dedicated section titled "PreToolUse decision control" with the full worked example was requested by exact title on two separate attempts; the fetch tool reported it could not locate a section under that exact title in the content the fetch surfaced to it, only the "Decision control" table and the "How a hook resolves" walkthrough (a `deny` example, not an `updatedInput` example).

These three gaps are the crux of the spike's mechanism-feasibility finding — see SPIKE.md Finding A2.
