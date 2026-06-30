# Auxiliary Source 5 — AI Coding Agent Override Modes (Claude Code, Cursor, Aider)

## Source A: Claude Code — bypassPermissions / --dangerously-skip-permissions
URL: https://docs.anthropic.com/en/docs/claude-code/settings
Fetched: 2026-06-23 (via search result excerpt)

### The explicit non-interactive mode

Claude Code's permission system has three modes:
1. **Default**: asks for permission before potentially dangerous operations
2. **Auto mode**: auto-approves a defined allowlist of operations
3. **--dangerously-skip-permissions**: bypasses ALL permission checks

### The naming as UX signal

The flag `--dangerously-skip-permissions` is intentionally verbose and contains the word "dangerously." This is not accidental — the long, scary name is designed to make the flag feel like a warning, not a convenience.

From the Claude Code documentation: "This flag disables all permission checking. Use only in automated environments where you have verified the agent's outputs. Do not use in interactive sessions with untrusted input."

### bypassPermissions in CLAUDE.md settings

The `bypassPermissions` setting in `~/.claude/settings.json` allows specific pre-approved operations to auto-run without confirmation. This is a DIFFERENT mechanism from `--dangerously-skip-permissions` — it is a curated allowlist, not a blanket bypass.

### Approval fatigue — the documented failure mode

From the Anthropic documentation (and documented in anthropics/claude-code community findings): "Anthropic measured that 93% of permission prompts are approved without careful review." This is "approval fatigue" — when prompts are too frequent, they stop functioning as meaningful gates.

The implication: a system that asks for override confirmation too often trains users to approve automatically, degrading the very protection the confirmation was meant to provide.

---

## Source B: Cursor YOLO Mode
URL: https://www.cursor.com/en/blog/yolo-mode
Fetched: 2026-06-23 (via search result excerpt and Backslash Security analysis)

### What YOLO mode is

Cursor's YOLO mode (Agent mode with auto-run enabled) allows the AI agent to run terminal commands without per-command approval. The engineer sets an allowlist (commands that may auto-run) and a denylist (commands that are always blocked regardless).

### Security research on YOLO mode bypass
URL: https://www.backslash.security/blog/cursor-yolo-mode-prompt-injection
Fetched: 2026-06-23

"In YOLO mode, once enabled, there is no per-command confirmation. An attacker who can inject a prompt into the agent's context can cause the agent to execute arbitrary commands from the allowlist without the user seeing an approval dialog."

This is the failure mode the CLAUDE.md rules are trying to avoid: when the normal permission gate is disabled broadly, it eliminates protection against adversarial inputs, not just friction on legitimate use.

### The allowlist/denylist architecture

Cursor's design separates:
- **Default-deny**: nothing auto-runs unless explicitly allowed
- **Allowlist items**: specific commands or patterns that may auto-run
- **Denylist items**: specific commands that are NEVER allowed even in YOLO mode

The denylist is the equivalent of "hardcoded constraints" — behaviors that cannot be enabled even by the override mode. This maps to the distinction between "instructable defaults" (can be overridden) and "hardcoded behaviors" (always/never regardless of instruction) in Anthropic's model spec.

---

## Source C: Aider — chat mode vs. code mode explicit switching
URL: https://aider.chat/docs/usage/modes.html
Fetched: 2026-06-23 (via search result excerpt)

### Mode-switching as the override mechanism

Aider uses explicit mode switching rather than per-request overrides:
- `/architect` mode: agent proposes, human confirms before code is written
- `/code` mode: agent writes code directly
- `/ask` mode: agent answers questions without modifying code

The explicit `/mode` command is Aider's "override signal" — it changes the entire session's operating mode rather than granting a per-request exception.

### What mode-switching provides

Unlike a per-request override, mode-switching:
- Applies to the whole session, not one instruction
- Is visually obvious in the interface (mode name is shown persistently)
- Can be reversed at any point
- Creates a different behavioral envelope rather than an exception within the current envelope

### Implication for the narrow override design

If the team wanted to implement a session-level override rather than a per-request override, the Aider mode-switch is the model: the engineer types a specific command that changes the agent's operating mode for the session. The override signal is not "do this thing despite the rule" — it is "enter a mode where this category of rule is suspended."

---

## Source D: Claude Code -- auto mode (fully automated pipelines)
URL: https://docs.anthropic.com/en/docs/claude-code/github-actions
Fetched: 2026-06-23

### Non-interactive context as distinct from interactive override

In CI/CD contexts (GitHub Actions), Claude Code is invoked with `--no-user-prompts` or similar flags that disable interactive confirmation entirely. This is NOT an override — it is a different operational context where there is no human present to confirm anything.

The design principle: interactive override signals are designed for sessions with a human present. Fully-automated pipelines are a separate context with separate safety mechanisms (sandboxed execution, limited permissions, commit restrictions).

The implication: a team's override signal only needs to work in interactive sessions. Automated pipelines have different controls.
