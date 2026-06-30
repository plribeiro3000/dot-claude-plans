# SPIKE — Claude Code Write Permissions for `~/.claude/` Paths

## Investigation question

When a Claude Code subagent writes a file under `~/.claude/plans/` (e.g., `SPIKE.md`, `PLAN.md`) using the `Write` or `Edit` tool, a permission approval prompt appears — blocking unattended sessions. Six questions to answer:

1. What are the path-matching semantics for `permissions.allow` rules — specifically, are `Edit(**)` and `Write(**)` resolved relative to cwd?
2. Does `additionalDirectories` + `acceptEdits` auto-approve writes to `~/.claude/`, or only grant access?
3. Why does `defaultMode: acceptEdits` not suppress this prompt?
4. What literal allow-rule string(s) would suppress the prompt?
5. Community workarounds and open bugs?
6. Is this "by design"?

**Leading hypothesis**: `Edit(**)` and `Write(**)` are resolved relative to cwd (`~/Projects/4Shark/dot-claude`), so they do NOT match `~/.claude/plans/`. `additionalDirectories` is a separate axis from auto-approval.

**Hypothesis verdict**: CONFIRMED — and extended by a deeper bug: even the correct `~/` and `//` allow-rule syntax fails in practice because the path matcher operates on a relative display path, not the canonical absolute path.

## Sources consulted

- [code.claude.com/docs/en/permissions](https://code.claude.com/docs/en/permissions) — official path pattern type table, `acceptEdits` docs; key content saved to `write-perm_doc_1.txt`
- [code.claude.com/docs/en/settings](https://code.claude.com/docs/en/settings) — `additionalDirectories` description ("grant file access only"), `defaultMode` options
- [code.claude.com/docs/en/hooks](https://code.claude.com/docs/en/hooks) — `permissionDecision: "allow"` format, exit code semantics; key content saved to `write-perm_doc_2.txt`
- [github.com/anthropics/claude-code/issues/25137](https://github.com/anthropics/claude-code/issues/25137) — path-matching bug (relative vs absolute display path); quotes saved to `write-perm_log_1.txt`
- [github.com/anthropics/claude-code/issues/52822](https://github.com/anthropics/claude-code/issues/52822) — regression in v2.1.119: `permissionDecision: "allow"` stops suppressing Write/Edit prompts; quotes saved to `write-perm_log_1.txt`
- `/Users/plribeiro3000/.claude/scripts/auto-approve-local-skills.sh` — existing working hook pattern (Skill tool); full copy in `write-perm_excerpt_1.sh`
- `/Users/plribeiro3000/.claude/scripts/auto-approve-aws-readonly.sh` — existing working hook pattern (Bash tool); read in session
- `/Users/plribeiro3000/.claude/settings.json` — current configuration; read in session

See auxiliary: `write-perm_doc_1.txt` — permissions page path pattern table and acceptEdits definition
See auxiliary: `write-perm_doc_2.txt` — hooks page permissionDecision format and exit code semantics
See auxiliary: `write-perm_log_1.txt` — GitHub issue key quotes (#25137, #52822) and observation about Skills hook
See auxiliary: `write-perm_excerpt_1.sh` — full copy of `auto-approve-local-skills.sh` for structural reference

## Findings

### Finding 1: `Edit(**)` and `Write(**)` are cwd-relative — leading hypothesis confirmed

The official permissions documentation at `code.claude.com/docs/en/permissions` defines four path pattern types:

| Syntax | Resolves to | Example |
|--------|-------------|---------|
| `//path` | Absolute from filesystem root | `Read(//Users/alice/secrets/**)` |
| `~/path` | Relative to home directory | `Read(~/Documents/*.pdf)` |
| `/path` | Relative to project root | `Edit(/src/**/*.ts)` |
| `path` / `./path` | Relative to current directory | `Read(src/**)` |

The docs include an explicit warning: *"A pattern like `/Users/alice/file` isn't an absolute path. It's relative to the project root. Use `//Users/alice/file` for absolute paths."*

The current `settings.json` has `"Edit(**)"` and `"Write(**)"` — bare patterns with no prefix. These resolve to cwd (`~/Projects/4Shark/dot-claude`) and match only files under that directory tree. A file written to `/Users/plribeiro3000/.claude/plans/active/spike/…/SPIKE.md` is outside that tree, so neither rule fires.

**Source:** `code.claude.com/docs/en/permissions` — path pattern type table
**Verification block:** URL fetched / Verbatim quote checked / Quote substring *"A pattern like `/Users/alice/file` isn't an absolute path. It's relative to the project root. Use `//Users/alice/file` for absolute paths."* confirmed in fetched permissions documentation.

---

### Finding 2: The deeper bug — even correct `~/` and `//` syntax fails in practice

GitHub issue #25137 (closed as duplicate, no fix shipped) documents a bug where the permission matcher operates on the **relative display path** instead of the canonical absolute path:

> "The permission matcher appears to check against this **relative display path** rather than the canonical absolute path `/Users/username/.claude/mydata/data.json`. Since `../../../../../../../.claude/mydata/data.json` doesn't match any of [the defined rules]...the rule never triggers and the user is prompted every time."

The reporter had tried all of these allow rules — none worked:
- `Edit(/Users/username/.claude/mydata/*)` — project-root-relative, wrong
- `Edit(~/.claude/mydata/*)` — correct `~/` syntax, but fails at matching
- `Edit(**/.claude/mydata/data.json)` — glob traversal, but fails at matching

The path displayed in the permission prompt for outside-cwd files is always a `../` traversal form relative to cwd. For the 4Shark setup (cwd = `~/Projects/4Shark/dot-claude`), a write to `~/.claude/plans/…/SPIKE.md` would appear as `../../../../../../../.claude/plans/…/SPIKE.md`. The matcher checks this relative form — and no allow rule pattern can match a string beginning with `../`.

This bug has been filed multiple times: #16800, #15499, #21397 — all closed as duplicates. No fix shipped as of this spike.

**Source:** GitHub issue #25137 — [https://github.com/anthropics/claude-code/issues/25137](https://github.com/anthropics/claude-code/issues/25137)
**Verification block:** URL fetched / Verbatim quote checked / Quote substring *"The permission matcher appears to check against this relative display path rather than the canonical absolute path"* confirmed in fetched issue content.

---

### Finding 3: `additionalDirectories` grants access, not auto-approval

The official settings documentation describes `additionalDirectories` as providing *"grant file access only"* — a distinct axis from permission prompt suppression.

The current `settings.json` has `"~/.claude"` in `additionalDirectories`. This allows the model to read and write there at all (without it, the tool call would be blocked outright). But the presence of a path in `additionalDirectories` does not suppress the approval prompt — it merely makes the operation legal rather than illegal.

**Source:** `code.claude.com/docs/en/settings` — `additionalDirectories` description
**Verification block:** URL fetched / Verbatim quote checked / Quote substring *"grant file access only"* confirmed in fetched settings documentation.

---

### Finding 4: `acceptEdits` defaultMode does not suppress `~/.claude/` write prompts

The documentation defines `acceptEdits` as: *"Automatically accepts file edits and common filesystem commands such as `mkdir`, `touch`, `mv`, and `cp` for paths in the working directory or `additionalDirectories`."*

Two compounding reasons this does not help for `~/.claude/` writes:

1. **Path-matching bug (Finding 2)**: The `acceptEdits` check uses the same relative display path comparison. A write to `~/.claude/plans/…` appears as `../../../.claude/plans/…` — which does not resolve as "in additionalDirectories" when the check is done against the relative form rather than the canonical absolute path.

2. **Access vs approval distinction (Finding 3)**: The `additionalDirectories` value in `settings.json` was designed to grant access (vs block outright), not to qualify paths for the `acceptEdits` automatic-approval shortcut. The documentation language "working directory or additionalDirectories" appears to cover paths that resolve cleanly to either location — the `../` relative form does not.

**Consequence**: The current `settings.json` with `"defaultMode": "acceptEdits"` and `"~/.claude"` in `additionalDirectories` is the intended correct configuration — but a bug in the path matcher prevents it from working as documented.

**Source:** `code.claude.com/docs/en/settings` — `acceptEdits` definition
**Verification block:** URL fetched / Verbatim quote checked / Quote substring *"Automatically accepts file edits and common filesystem commands such as mkdir, touch, mv, and cp for paths in the working directory or additionalDirectories"* confirmed in settings documentation.

---

### Finding 5: No allow-rule pattern reliably suppresses the prompt today

Synthesizing Findings 1–4, the full picture of static allow-rule options:

| Pattern | Root cause of failure |
|---------|----------------------|
| `Write(**)` (current) | cwd-relative — only matches `~/Projects/4Shark/dot-claude/**` |
| `Write(~/.claude/**)` | Correct `~/` syntax, but path-matching bug: matcher sees `../../../.claude/…` |
| `Write(//Users/plribeiro3000/.claude/**)` | Correct `//` absolute syntax, but same path-matching bug |
| `Write(**/.claude/**)` | Glob traversal, but `../` path form still doesn't match |

No static rule in `permissions.allow` can match a path that the matcher presents in `../` relative form. This is not a configuration error — it is a bug in the Claude Code permission system (#25137 and its family of duplicates).

**Source:** Synthesized from Findings 1, 2, 3, 4 — no new source consulted for this synthesis.

---

### Finding 6: PreToolUse hook `permissionDecision: "allow"` is the documented bypass mechanism

The hooks documentation at `code.claude.com/docs/en/hooks` confirms the exact JSON output format for auto-approval:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "<reason string>"
  }
}
```

A hook returning this JSON with exit code 0 bypasses the permission rule matching entirely for that specific tool call. Crucially, this bypass happens before the path-matcher runs — so the relative-path bug in Finding 2 does not affect it.

This pattern is already operational in the harness for two tool types:
- `auto-approve-local-skills.sh` — `Skill` tool; confirmed working per CLAUDE.md ("the 'Use skill X?' prompt never fires for our own tooling")
- `auto-approve-aws-readonly.sh` — `Bash` tool; operational for read-only AWS commands

For `Write|Edit|MultiEdit`, the relevant tool input field is `.tool_input.file_path` (same for all three tool types, including MultiEdit which has a single `file_path` alongside an `edits` array).

**Source:** `code.claude.com/docs/en/hooks` — `permissionDecision` field, exit code semantics
**Verification block:** URL fetched / Verbatim JSON structure confirmed in hooks documentation.

---

### Finding 7: Regression in v2.1.119 — `permissionDecision: "allow"` broken for Write/Edit in interactive mode

GitHub issue #52822 documents a regression introduced in Claude Code v2.1.119:

> "A PreToolUse hook (`type: 'command'`) that exits with code 0 and emits a well-formed `hookSpecificOutput` with `permissionDecision: 'allow'` on stdout does **not** suppress the native `Do you want to X?` permission prompt in interactive mode."

Key facts from the issue:
- Last confirmed working version: v2.1.59
- Broken in: v2.1.119 and later (at the time of filing)
- The hook executes and its JSON is parsed correctly — only the prompt suppression is broken
- `exit 2` (deny) still works correctly — only the allow path is affected
- The issue is marked **Closed** — resolution details are not stated in the visible content

**Observation from the harness**: The existing `auto-approve-local-skills.sh` hook for the `Skill` tool is documented in CLAUDE.md as operational ("the prompt never fires for our own tooling"). This suggests the regression is either:
- Fixed in a release after v2.1.119, OR
- Specific to Write/Edit/Bash tool types (the Skill tool takes a different code path), OR
- Present only in certain session modes

**Risk implication**: A new `auto-approve-claude-dir-writes.sh` hook targeting `Write|Edit|MultiEdit` may silently fail to suppress the prompt if the regression is still active in the currently installed version. The hook would execute, parse correctly, and return `allow` — but the prompt would still appear.

**Source:** GitHub issue #52822 — [https://github.com/anthropics/claude-code/issues/52822](https://github.com/anthropics/claude-code/issues/52822)
**Verification block:** URL fetched / Verbatim quote checked / Quote substring *"A PreToolUse hook (type: 'command') that exits with code 0 and emits a well-formed hookSpecificOutput with permissionDecision: 'allow' on stdout does not suppress the native 'Do you want to X?' permission prompt in interactive mode"* confirmed in fetched issue content.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|----------|------|------|--------|
| **Option A: PreToolUse hook `auto-approve-claude-dir-writes.sh`** | Bypasses broken path-matcher entirely; proven pattern already in harness for Skill + Bash; scoped to `~/.claude/` prefix (not overly broad) | Risk of v2.1.119 regression (#52822) for Write/Edit tool type — hook returns allow but prompt may still appear; adds one more hook to maintain | Findings 5, 6, 7; `write-perm_excerpt_1.sh` |
| **Option B: `Write(~/.claude/**)` + `Edit(~/.claude/**)` allow rules** | Documented correct `~/` syntax per official docs; simple to add | Fails silently due to path-matching bug (#25137) — no path in `../` form can match; ALREADY effectively attempted (the existing `Edit(**)` should match everything in cwd, and `~/.claude` is in `additionalDirectories`) | Findings 1, 2, 5 |
| **Option C: `bypassPermissions` defaultMode** | Fully suppresses all prompts including for `~/.claude/` writes; no hook needed; explicitly covers `.claude` dir (docs mention it in the context of full bypass) | Skips ALL permission rules including all `deny` entries — `~/.ssh/**`, `~/.aws/**`, `.env`, `master.key`, credentials files lose their deny protection; too broad for production use | Findings 3, 4; official docs |
| **Option D: `--add-dir ~/.claude/plans` CLI flag** | CLI `--add-dir` may use a different code path than settings `additionalDirectories` — potentially avoids the path-matching bug for `acceptEdits` coverage | Not verified to fix the relative-path bug; requires changing session startup; not automatable without a wrapper script; and only applies if the `acceptEdits` + additionalDirectories path-matching failure is the sole cause | Finding 3; official docs |

## What remains uncertain

- **Whether the v2.1.119 regression (#52822) is fixed in the current installed version.** The issue is closed but the resolution is not visible. A 5-minute test — write one file to `~/.claude/plans/test.txt` via a hook returning `allow` and observe whether the prompt still appears — resolves this definitively.
- **Whether the `--add-dir` CLI flag uses a different path-comparison code path** than settings-based `additionalDirectories`, such that `acceptEdits` works correctly with it but not with the settings form.
- **Whether Anthropic intends to fix the path-matching bug.** Issues #25137, #16800, #15499, #21397 are all closed as duplicates. The root may be tracked internally. No public roadmap item is visible.
- **Whether MultiEdit's `file_path` field is always populated** in the hook input, or whether some MultiEdit invocations omit it when the tool works across multiple files. The docs imply a single `file_path` per MultiEdit call, but this should be confirmed by inspecting a real hook invocation.

## Suggested options for main and the engineer

**Option A (PreToolUse hook — highest confidence, pending regression verification)**

Create `~/.claude/scripts/auto-approve-claude-dir-writes.sh` as a PreToolUse hook on `Write|Edit|MultiEdit`. The hook checks `.tool_input.file_path` against the `~/.claude/` absolute prefix and returns `permissionDecision: "allow"` for matched paths. This bypasses the broken path-matcher entirely — the `../` relative path form never enters the equation.

Exact script template (pattern from `write-perm_excerpt_1.sh`):

```bash
#!/bin/bash
# auto-approve-claude-dir-writes.sh
#
# PreToolUse hook for Write, Edit, MultiEdit.
# Auto-approves file writes to ~/.claude/ so subagent writes to
# ~/.claude/plans/ (SPIKE.md, PLAN.md, TASKS.md, etc.) do not
# prompt when the engineer is away.
#
# Why: permissions.allow patterns (even ~/... and //... forms) are
# matched against the relative display path (../../../.claude/...),
# not the canonical absolute path. No static rule can match a ../
# traversal. This hook bypasses the broken path matcher entirely.
# Bug: anthropics/claude-code#25137 (closed as duplicate, no fix shipped).
#
# Scope: only ~/.claude/ — does not widen to ~/Projects/ or /tmp/.
# The existing deny rules for ~/.ssh/, ~/.aws/, etc. take precedence
# (deny > ask > allow), so this hook does not override them.
#
# Always exits 0. Any non-match or failure defers to the normal prompt.

set -euo pipefail

hook_input="$(cat)"
tool_name="$(printf '%s' "$hook_input" | jq -r '.tool_name // empty')"

case "$tool_name" in
  Write|Edit|MultiEdit) ;;
  *) exit 0 ;;
esac

file_path="$(printf '%s' "$hook_input" | jq -r '.tool_input.file_path // empty')"

if [ -z "$file_path" ]; then
  exit 0
fi

claude_dir="${HOME}/.claude"
case "$file_path" in
  "${claude_dir}/"*)
    reason="write to ~/.claude/ directory; authorized by 4Shark dot-claude configuration"
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"%s"}}\n' "$reason"
    exit 0
    ;;
esac

exit 0
```

Register in `settings.json` PreToolUse section with matcher `"Edit|Write|MultiEdit"` — placed BEFORE the existing validate-* hooks so approve fires first (deny hooks at exit 2 still override it per Claude Code's deny > ask > allow precedence).

**Prerequisite before shipping**: Test one write to `~/.claude/plans/test.txt` from a subagent with this hook active. If the prompt still appears, the v2.1.119 regression (#52822) is present in the current build — escalate to a Claude Code version upgrade or contact Anthropic.

**Option B (Allow rules — belt-and-suspenders, not functional today)**

Add `"Write(~/.claude/**)"` and `"Edit(~/.claude/**)"` to `permissions.allow`. These do not work today due to the path-matching bug, but they:
- Document the intent for future readers
- Will start working automatically if Anthropic ships a fix for #25137

Costs nothing to add alongside Option A.

**Option C (`bypassPermissions` — only if A is broken and there is no other path)**

Switch `"defaultMode"` to `"bypassPermissions"`. This suppresses all prompts for all paths including `~/.claude/`. The consequence is that every `deny` rule in `settings.json` loses its enforcement — `~/.ssh/**`, `~/.aws/**`, `.env`, `master.key`, and all credentials deny rules become purely advisory. This is a significant security regression and should only be considered if Option A is confirmed broken and a Claude Code upgrade is not feasible.

(NO recommendation — surface options, let main and the engineer choose)
