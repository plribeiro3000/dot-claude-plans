# Auxiliary source 2 — Claude Code subagents reference

Source URL: https://code.claude.com/docs/en/sub-agents
Fetched: 2026-07-15. The fetch exceeded the tool-result cap and was persisted verbatim by the harness to:
`/Users/plribeiro3000/.claude/projects/-/105685c2-fe84-4d2e-b98e-c599b05af27d/tool-results/toolu_01SbfiQoE8w1vwRD8tPsueBi.txt` (76.3KB)

All line numbers below refer to that persisted file. Quotes are verbatim.

---

## "What loads at startup" section (lines 829–844) — the load-bearing section

Line 831:

> "Each subagent starts with a fresh, isolated context window. It doesn't see your conversation history, the skills you've already invoked, or the files Claude has already read. Claude composes a delegation message that summarizes the task, and the subagent works from there. The exception is a fork, which inherits the parent conversation instead of starting fresh."

Line 833: "A non-fork subagent's initial context contains:"

Line 835:

> "**System prompt**: the agent's own prompt plus environment details that Claude Code appends, not the full Claude Code system prompt. Custom subagents define theirs in the markdown body or `prompt` field. Built-in agents have predefined prompts."

Line 836:

> "**Task message**: the delegation prompt Claude writes when it hands off the work."

Line 837 — **CLAUDE.md reaches subagents**:

> "**CLAUDE.md and memory**: every level of the memory hierarchy the main conversation loads, including `~/.claude/CLAUDE.md`, project rules, `CLAUDE.local.md`, and managed policy files. The built-in Explore and Plan agents skip this."

Line 838:

> "**Git status**: a snapshot taken at the start of the parent session. Absent when the working directory isn't a Git repository or when `includeGitInstructions` is `false`. Explore and Plan skip it regardless."

Line 839:

> "**Preloaded skills**: full content of any skill named in the agent's `skills` field. Built-in agents don't preload skills."

Line 840:

> "**Sibling roster**: a system reminder listing `main` and every other named agent in the session, each a valid `to` value for SendMessage."

Line 842:

> "Explore and Plan are the only subagents that omit CLAUDE.md and git status. There is no frontmatter field or per-agent setting to change which agents skip them."

Line 844:

> "The main conversation reads Explore and Plan results with full CLAUDE.md context, so most rules don't need to reach the subagent itself. If a rule must, such as \"ignore the `vendor/` directory,\" restate it in the prompt you give Claude when delegating."

## Built-in agents (line 33)

> "Explore and Plan skip your CLAUDE.md files and the parent session's git status to keep research fast and inexpensive. Every other built-in and custom subagent loads both. For the full breakdown of what reaches a subagent, see what loads at startup."

## System prompt composition (line 259)

> "The frontmatter defines the subagent's metadata and configuration. The body becomes the system prompt that guides the subagent's behavior. Subagents receive only this system prompt plus basic environment details like the working directory, not the full Claude Code system prompt."

## `--append-subagent-system-prompt` (line 261)

> "In non-interactive mode, the `--append-subagent-system-prompt` flag appends the text you provide to the end of every subagent's system prompt, including nested subagents. Requires Claude Code v2.1.205 or later."

## Preload skills into subagents (lines 451–469)

Line 453:

> "Use the `skills` field to inject skill content into a subagent's context at startup. This gives the subagent domain knowledge without requiring it to discover and load skills during execution."

```yaml
---
name: api-developer
description: Implement API endpoints following team conventions
skills:
  - api-conventions
  - error-handling-patterns
---

Implement API endpoints. Follow the conventions and patterns from the preloaded skills.
```

Line 467:

> "The full content of each listed skill is injected into the subagent's context at startup. This field controls which skills are preloaded, not which skills the subagent can access: without it, the subagent can still discover and invoke project, user, and plugin skills through the Skill tool during execution. To prevent a subagent from invoking skills entirely, omit `Skill` from the `tools` list or add it to `disallowedTools`."

Line 469:

> "You can't preload skills that set `disable-model-invocation: true`, since preloading draws from the same set of skills Claude can invoke. If a listed skill is missing or disabled, Claude Code skips it and logs a warning to the debug log."

## Supported frontmatter fields (line 275, `tools` row)

> "Tools the subagent can use. Inherits all tools if omitted. If no entry in the list resolves to a tool, the subagent fails to launch with an error naming the entries. To preload Skills into context, use the `skills` field rather than listing `Skill` here"

## Subagent persistent memory (lines 475–502)

Line 501:

> "The subagent's system prompt also includes the first 200 lines or 25KB of `MEMORY.md` in the memory directory, whichever comes first, with instructions to curate `MEMORY.md` if it exceeds that limit."

## `--agent` session-wide (line 701)

> "The subagent's system prompt replaces the default Claude Code system prompt entirely, the same way `--system-prompt` does. `CLAUDE.md` files and project memory still load through the normal message flow. The agent name appears as `@<name>` in the startup header so you can confirm it's active."
