# Auxiliary source 3 — Claude Code memory (CLAUDE.md) reference

Source URL: https://code.claude.com/docs/en/memory
Fetched: 2026-07-15. Quotes verbatim from the fetched page.

---

## `@path` imports — syntax, depth, and what they cost

Heading: "Import additional files"

> "CLAUDE.md files can import additional files using `@path/to/import` syntax. Imported files are expanded and loaded into context at launch alongside the CLAUDE.md that references them."

> "Both relative and absolute paths are allowed. Relative paths resolve relative to the file containing the import, not the working directory. Imported files can recursively import other files, with a maximum depth of four hops."

> "Import parsing skips Markdown code spans and fenced code blocks. To mention a path in your CLAUDE.md without importing it, wrap it in backticks: writing `` `@README` `` keeps the text literal, while `@README` outside backticks imports the file."

Home-directory import example (works across worktrees):

```text
# Individual Preferences
- @~/.claude/my-project-instructions.md
```

Warning on external imports:

> "The first time Claude Code encounters external imports in a project, it shows an approval dialog listing the files. If you decline, the imports stay disabled and the dialog does not appear again."

## Imports do NOT reduce context

Heading: "My CLAUDE.md is too large"

> "Files over 200 lines consume more context and may reduce adherence. Use path-scoped rules to load instructions only when Claude works with matching files, or trim content that isn't needed in every session. Splitting into `@path` imports helps organization but doesn't reduce context, since imported files load at launch."

Heading: "Write effective instructions"

> "**Size**: target under 200 lines per CLAUDE.md file. Longer files consume more context and reduce adherence. If your instructions are growing large, use path-scoped rules so instructions load only when Claude works with matching files. You can also split content into imports for organization, though imported files still load and enter the context window at launch."

## CLAUDE.md itself has NO size cap

Heading: "How it works" (auto memory section)

> "The first 200 lines of `MEMORY.md`, or the first 25KB, whichever comes first, are loaded at the start of every conversation. Content beyond that threshold is not loaded at session start. Claude keeps `MEMORY.md` concise by moving detailed notes into separate topic files."

> "This limit applies only to `MEMORY.md`. CLAUDE.md files are loaded in full regardless of length, though shorter files produce better adherence."

## CLAUDE.md is context, not enforcement

> "Claude Code has two complementary memory systems. Both are loaded at the start of every conversation. Claude treats them as context, not enforced configuration. To block an action regardless of what Claude decides, use a PreToolUse hook instead. The more specific and concise your instructions, the more consistently Claude follows them."

Heading: "Claude isn't following my CLAUDE.md"

> "CLAUDE.md content is delivered as a user message after the system prompt, not as part of the system prompt itself. Claude reads it and tries to follow it, but there's no guarantee of strict compliance, especially for vague or conflicting instructions."

> "If the instruction is something that must run at a specific point, such as before every commit or after each file edit, write it as a hook instead. Hooks execute as shell commands at fixed lifecycle events and apply regardless of what Claude decides."

> "For instructions you want at the system prompt level, use `--append-system-prompt`. This must be passed every invocation, so it's better suited to scripts and automation than interactive use."

## `.claude/rules/` — path-scoped loading

> "Rules without `paths` frontmatter are loaded at launch with the same priority as `.claude/CLAUDE.md`."

> "Rules can be scoped to specific files using YAML frontmatter with the `paths` field. These conditional rules only apply when Claude is working with files matching the specified patterns."

> "Rules without a `paths` field are loaded unconditionally and apply to all files. Path-scoped rules trigger when Claude reads files matching the pattern, not on every tool use."

Note box:

> "Rules load into context every session or when matching files are opened. For task-specific instructions that don't need to be in context all the time, use skills instead, which only load when you invoke them or when Claude determines they're relevant to your prompt."

## InstructionsLoaded debugging tip

> "Use the `InstructionsLoaded` hook to log exactly which instruction files are loaded, when they load, and why. This is useful for debugging path-specific rules or lazy-loaded files in subdirectories."

## Compaction survival

> "Project-root CLAUDE.md survives compaction: after `/compact`, Claude re-reads it from disk and re-injects it into the session. Nested CLAUDE.md files in subdirectories are not re-injected automatically; they reload the next time Claude reads a file in that subdirectory."
