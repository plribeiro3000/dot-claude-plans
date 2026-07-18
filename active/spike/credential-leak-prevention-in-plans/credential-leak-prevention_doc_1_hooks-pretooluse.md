# Auxiliary — Claude Code hooks reference, PreToolUse decision control section (verbatim excerpt)

Source: https://code.claude.com/docs/en/hooks (fetched 2026-07-17, via WebFetch after a 301
redirect from https://docs.claude.com/en/docs/claude-code/hooks)

This is the full "PreToolUse decision control" section through "PreToolUse input rewriting",
preserved verbatim because it is the primary source for SPIKE.md Finding 2 (hook feasibility
for rewriting Write/Edit content). Only the sections relevant to PreToolUse / input rewriting
are kept; the full document also covers ~25 other hook events not relevant to this spike.

---

## PreToolUse decision control

The `PreToolUse` event supports these decision fields inside `hookSpecificOutput`:

| Field                      | Description                                                                                                                                                |
| :------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `permissionDecision`       | One of `"allow"`, `"deny"`, `"ask"`, or `"defer"`. `"allow"` approves the tool call; `"deny"` blocks it. `"ask"` escalates to the user with a permission dialog. `"defer"` runs the normal permission flow as if the hook had no decision |
| `permissionDecisionReason` | Explanation shown to the user when the decision is `"deny"` or `"ask"`. Ignored for `"allow"` and `"defer"`                                                |
| `updatedInput`             | Modified tool input. Replace all or part of `tool_input` before the tool runs. See [PreToolUse input rewriting](#pretooluse-input-rewriting)               |
| `additionalContext`        | String added to Claude's context next to the tool result. Useful for warnings about tool calls that will proceed, like "This command will deploy to production" |

This example denies a destructive command:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Destructive command blocked by hook"
  }
}
```

#### PreToolUse input rewriting

The `updatedInput` field inside `hookSpecificOutput` lets you transform a tool's arguments
before it runs. For most tools, `updatedInput` is a flat object containing the modified input
fields. For Bash, `updatedInput` can contain a modified `command` string.

The hook receives the full `tool_input` and can return a partial `updatedInput` with only the
fields to change. Fields omitted from `updatedInput` keep their original values. This example
replaces a Bash command:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "updatedInput": {
      "command": "npm run lint -- --fix"
    }
  }
}
```

For tools with nested input, update only the fields you need to change. This example modifies
a single argument to the `Edit` tool:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "updatedInput": {
      "language": "javascript"
    }
  }
}
```

The input rewriting applies to the tool call Claude Code executes. It does not change what
Claude sees or knows about the tool call. If you rewrite `rm file.txt` to `echo file.txt`,
Claude still thinks it called `rm`; only the actual execution runs the `echo`. Use this for
sandboxing, enforcement, or safe substitution. Use `additionalContext` to inform Claude about
transformations it should know about.

Input rewriting does not apply to `PermissionDenied` hooks because the tool call was already
denied. Use `PostToolUse` hooks to transform results, or `PermissionRequest` hooks to modify
input when approving a permission.

---

## NOTE on the `Edit` tool example above (analysis, not part of the verbatim quote)

The illustrative example uses a field named `language` for the `Edit` tool. The Edit tool's
actual documented input schema (as used elsewhere in this codebase, e.g.
`~/.claude/scripts/validate-bang-method-web-flow.sh` matching on `Edit|Write|MultiEdit`) takes
`file_path`, `old_string`, `new_string`, `replace_all` — it has no `language` field. This means
the docs' own example does not demonstrate rewriting a REAL Edit tool field (`new_string`), only
that the mechanism accepts an arbitrary key in the `updatedInput` object. Whether the harness
then applies that key when it does not correspond to a real parameter of the Edit tool's schema,
and specifically whether `new_string`/`content` can be rewritten this way, is not demonstrated
by this documentation page.

## Cross-reference — reported reliability issue

GitHub issue https://github.com/anthropics/claude-code/issues/15897 ("[BUG] updatedInput
PreToolUse response does not work when multiple PreToolUse hooks are executed"), closed as
not-planned, reports:

> "PreToolUse hooks that return `permissionDecision: "allow"` with `updatedInput` have the
> `updatedInput` field completely ignored. The original tool input is executed instead of the
> modified input. Blocking (exit code 2) works correctly. Only `updatedInput` with allow is
> broken."

The reproduction in that issue used the Bash tool. This is worth noting because 4Shark's own
CLAUDE.md documents a throwaway-hook test (`redirect-home-path.sh`) confirming `updatedInput`
DOES work for Bash in the tested scenario — so reliability may be scenario/version-dependent
rather than uniformly broken or uniformly working.
