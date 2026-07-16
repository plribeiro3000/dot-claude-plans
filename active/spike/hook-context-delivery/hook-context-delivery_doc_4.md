# Auxiliary source 4 — Skills, progressive disclosure, and context degradation

Three distinct sources. Kept in one auxiliary file because each contributed a small number of quotes.

---

## Source 4a — Claude Code Skills reference

URL: https://code.claude.com/docs/en/skills
Fetched: 2026-07-15. Exceeded the tool-result cap; persisted verbatim by the harness to:
`/Users/plribeiro3000/.claude/projects/-/105685c2-fe84-4d2e-b98e-c599b05af27d/tool-results/toolu_01TYw4oGJMR3wecC8dWmZY5F.txt` (63.7KB)

Line numbers refer to that persisted file.

Line 11 — on-demand loading vs CLAUDE.md:

> "Create a skill when you keep pasting the same instructions, checklist, or multi-step procedure into chat, or when a section of CLAUDE.md has grown into a procedure rather than a fact. Unlike CLAUDE.md content, a skill's body loads only when it's used, so long reference material costs almost nothing until you need it."

Line 212 — recurring token cost once loaded:

> "Keep the body itself concise. Once a skill loads, its content stays in context across turns, so every line is a recurring token cost. State what to do rather than narrating how or why, and apply the same conciseness test you would for CLAUDE.md content."

Line 322 — stated size guidance:

> "Keep `SKILL.md` under 500 lines. Move detailed reference material to separate files."

Line 234 — description truncation:

> "Put the key use case first: the combined `description` and `when_to_use` text is truncated at 1,536 characters in the skill listing to reduce context usage."

Line 367 — skills after compaction:

> "Auto-compaction carries invoked skills forward within a token budget. When the conversation is summarized to free context, Claude Code re-attaches the most recent invocation of each skill after the summary, keeping the first 5,000 tokens of each. Re-attached skills share a combined budget of 25,000 tokens. Claude Code fills this budget starting from the most recently invoked skill, so older skills can be dropped entirely after compaction if you have invoked many in one session."

---

## Source 4b — Anthropic engineering blog: "Equipping agents for the real world with Agent Skills"

URL: https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills
Fetched: 2026-07-15. This is Anthropic's engineering blog (a blog post, not reference documentation).

> "Like a well-organized manual that starts with a table of contents, then specific chapters, and finally a detailed appendix, skills let Claude load information only as needed"

> "Agents with a filesystem and code execution tools don't need to read the entirety of a skill into their context window when working on a particular task."

> "This means that the amount of context that can be bundled into a skill is effectively unbounded."

The targeted fetch reported: the document does not provide specific numerical guidance on context window sizes or stated maximum token limits for Agent Skills.

---

## Source 4c — Anthropic engineering blog: "Effective context engineering for AI agents"

URL: https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
Fetched: 2026-07-15. Anthropic engineering blog (a blog post, not reference documentation).

On context rot:

> "as the number of tokens in the context window increases, the model's ability to accurately recall information from that context decreases."

On attention degradation:

> "As its context length increases, a model's ability to capture these pairwise relationships gets stretched thin, creating a natural tension between context size and attention focus."

On the attention budget:

> "LLMs have an 'attention budget' that they draw on when parsing large volumes of context. Every new token introduced depletes this budget by some amount."

On just-in-time loading vs pre-loading:

> "Rather than pre-processing all relevant data up front, agents built with the 'just in time' approach maintain lightweight identifiers (file paths, stored queries, web links, etc.) and use these references to dynamically load data into context at runtime using tools."

> "This approach mirrors human cognition: we generally don't memorize entire corpuses of information, but rather introduce external organization and indexing systems like file systems, inboxes, and bookmarks to retrieve relevant information on demand."

---

## Source 4d — GitHub issues (anthropics/claude-code)

Both fetched 2026-07-15.

### Issue #24176 — "[FEATURE] Native support for dynamic, composable context injection into subagents and teammates"
URL: https://github.com/anthropics/claude-code/issues/24176
Status: **Closed as not planned.**

> "The `SubagentStart` hook's `additionalContext` field injects content as a `<system-reminder>` tag in the message stream, not in the system prompt."

Describes the same shape 4Shark uses, as a workaround:

> "Works as a workaround but requires external shell scripts, manual YAML parsing, and a hand-rolled module composition system"

> "A `SubagentStart` hook runs a bash script that reads `agent_type`, looks it up in a `roles.yaml` file, composes context from module files, and injects via `hookSpecificOutput.additionalContext`"

The issue does not specify any size limits for `additionalContext`.

### Issue #23885 — "feature: SubagentStart hook should support updatedPrompt for direct prompt injection"
URL: https://github.com/anthropics/claude-code/issues/23885
Status: **Closed as duplicate.**

Problem statement, verbatim bullets:

> "*   additionalContext appends to user context, not system prompt
> *   During context pruning, critical rules may be dropped
> *   Subagents still need to discover and interpret rules from CLAUDE.md"

The issue does not mention hard size limits or specific content-delivery failures.

### Issues located but NOT fetched (listed for completeness; UNVERIFIED)
- #16538 — "Plugin SessionStart hooks don't surface hookSpecificOutput.additionalContext to Claude"
- #19432 — "[BUG] PreToolUse hook `additionalContext` is received but not injected into model context"
- #20062 — "[BUG] PreToolUse hooks with additionalContext not working in VSCode extension"
- #49063 — "UserPromptSubmit hook additionalContext not injected into model context in VSCode extension"
- #37559 — "Hook documentation is misleading — Stop hooks broken, prompt hooks can't inject context, capabilities undocumented per event type"
- #19170 — "[DOCS] Missing definition and input schema for `SubagentStart` hook event"

These titles come from web-search result listings only. Their contents were not fetched and they may NOT sustain any option or conclusion in SPIKE.md.

---

## Source 4e — Third-party gist (LOW CONFIDENCE, contradicted)

URL: https://gist.github.com/EmanuelFaria/64914bf2f4fbb9e7b9262aff2383a122
This is a community gist (not documentation, not an issue). Fetched 2026-07-15.

Claims, verbatim:

> "Claude Code silently truncates files loaded internally at ~28KB (28,672 bytes)"

> "truncates to a 2KB preview and saves the rest to a temp file — but the model often ignores the saved file"

It attributes a "~70% failure rate" and cites GitHub #28783.

**Assessment**: the ~28KB / ~30KB figure **contradicts** the official documented 10,000-character cap and is contradicted by 4Shark's own measurement (a ~20.5KB block WAS truncated, which a 28KB threshold would not predict). The fetch reported: "No external authoritative sources are cited—the claims rest on the gist author's observations and the single GitHub issue reference, without official Anthropic documentation quoted verbatim to validate the 28KB or 2KB figures." Treated as unreliable; not used to sustain any finding.
