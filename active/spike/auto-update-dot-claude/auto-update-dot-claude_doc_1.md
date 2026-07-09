# Auxiliary — Claude Code official docs excerpts (config load/reload lifecycle)

Fetched via WebFetch during the `auto-update-dot-claude` spike. Each block below is a
verbatim quote confirmed present on the source page (self-checked with a second
targeted fetch asking "does substring X appear verbatim").

## Source: https://code.claude.com/docs/en/settings

> Claude Code watches your settings files and reloads them when they change, so edits
> to most keys apply to the running session without a restart. This includes
> `permissions`, `hooks`, and credential helpers like `apiKeyHelper`. The reload
> covers user, project, local, and managed settings, and the `ConfigChange` hook
> fires for each detected change.

> A few keys are read once at session start and apply on the next restart instead:
>
> * `model`: use `/model` to switch mid-session
> * `outputStyle`: part of the system prompt, which is rebuilt on `/clear` or restart

## Source: https://code.claude.com/docs/en/debug-your-config

> Edits to `settings.json` take effect in the running session after a brief
> file-stability delay. You don't need to restart. If `/hooks` still shows the old
> definition a few seconds after saving, run `/hooks` again to refresh the view.

> Subdirectory `CLAUDE.md` instructions seem ignored | Subdirectory files load on
> demand, not at session start | They load when Claude reads a file in that directory
> with the Read tool, not at launch and not when writing or creating files there.

## Source: https://code.claude.com/docs/en/memory

> Each Claude Code session begins with a fresh context window. [...] CLAUDE.md files:
> instructions you write to give Claude persistent context.

> CLAUDE.md files are markdown files that give Claude persistent instructions for a
> project, your personal workflow, or your entire organization. You write these files
> in plain text; Claude reads them at the start of every session.

> CLAUDE.md and CLAUDE.local.md files in the directory hierarchy above the working
> directory are loaded in full at launch. Files in subdirectories load on demand when
> Claude reads files in those directories.

> Instructions seem lost after `/compact` — Project-root CLAUDE.md survives
> compaction: after `/compact`, Claude re-reads it from disk and re-injects it into
> the session. Nested CLAUDE.md files in subdirectories are not re-injected
> automatically; they reload the next time Claude reads a file in that subdirectory.

Note: this page's `/compact` guarantee is stated specifically for "project-root
CLAUDE.md". The page does not make the same explicit claim for the **user-level**
`~/.claude/CLAUDE.md` (the "User instructions" scope in its own table, loaded at
launch alongside project CLAUDE.md). Whether `~/.claude/CLAUDE.md` is also re-read
from disk on `/compact` is not stated either way on this page — flagged as an open
question in SPIKE.md.

> CLAUDE.md content is delivered as a user message after the system prompt, not as
> part of the system prompt itself. Claude reads it and tries to follow it, but
> there's no guarantee of strict compliance, especially for vague or conflicting
> instructions.

## Source: https://code.claude.com/docs/en/hooks

> All matching hooks run in parallel, and identical handlers are deduplicated
> automatically. Command hooks are deduplicated by command string and `args`, and
> HTTP hooks are deduplicated by URL.

> `additionalContext`: String added to Claude's context at the start of the
> conversation, before the first prompt. [for SessionStart]

## Source: https://code.claude.com/docs/en/skills

> Live change detection — Claude Code watches skill directories for file changes.
> Adding, editing, or removing a skill under `~/.claude/skills/`, the project
> `.claude/skills/`, or a `.claude/skills/` inside an `--add-dir` directory takes
> effect within the current session without restarting. Creating a top-level skills
> directory that did not exist when the session started requires restarting Claude
> Code so the new directory can be watched.

> Live change detection covers `SKILL.md` text only. For a skill folder that is also
> a plugin, changes to `hooks/`, `.mcp.json`, `agents/`, and `output-styles/` need
> `/reload-plugins` to take effect.

> In a regular session, skill descriptions are loaded into context so Claude knows
> what's available, but full skill content only loads when invoked.

## Source: https://code.claude.com/docs/en/sub-agents

> Claude Code watches `~/.claude/agents/` and `.claude/agents/`. When you add or edit
> a subagent file on disk, or ask Claude to write one for you, Claude Code detects
> the change within a few seconds and the next delegation uses the updated
> definition, with no restart needed.
>
> Two cases still need a restart:
> * The watcher covers only directories that existed when the session started, so
>   after creating a scope's first agent file in a new `agents` directory, restart to
>   load it.
> * Sessions started with `--disable-slash-commands` don't watch these directories at
>   all.

> CLAUDE.md and memory: every level of the memory hierarchy the main conversation
> loads, including `~/.claude/CLAUDE.md`, project rules, `CLAUDE.local.md`, and
> managed policy files. [listed under what a freshly-spawned subagent loads at its
> own startup, mid-session relative to the parent]

## Source: https://agentpatterns.ai/tools/claude/reload-skills-mid-session/ (third-party, not an Anthropic property — lower authority than code.claude.com)

> Claude Code can re-scan skill directories mid-session, making edited or newly
> installed skills available without a restart that discards accumulated context.

This third-party claim is consistent with (and superseded in authority by) the
official "Live change detection" section quoted above from code.claude.com. Kept for
completeness only; the code.claude.com quote is the one relied upon in SPIKE.md.
