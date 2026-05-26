# PLAN — meeting-context skill (meeting notes + Granola MCP fallback)

## Current Situation

- **Migrated meeting notes**: 378 meetings in `~/.meeting-notes/{scope}/{year}/` as markdown with frontmatter (summary + transcript pairs). Canonical source for pre-Granola history.
- **Granola MCP**: already configured in `~/.claude.json` under scope `~/Projects/4Shark/app` (HTTP type, URL `https://mcp.granola.ai/mcp`). Exposes `mcp__granola__get_meeting_transcript`, `mcp__granola__query_granola_meetings`, `mcp__granola__list_meetings`, `mcp__granola__list_meeting_folders`, `mcp__granola__get_meetings`.
- **Claude Code state**: when the user asks about past meetings, there is no structured behavior — Claude improvises (reads directories, greps without order, or just answers from training).
- **Shared environment**: `~/.claude/` is git-tracked via `~/Projects/4Shark/.claude/` (4Shark team). Changes applied there affect every engineer.
- **Constraint**: only Paulo has `~/.meeting-notes/` and Granola configured. Other devs cannot have anything break due to missing those resources.

## Objective / Target State

- **Desired outcome**: when the engineer asks a question about meetings ("what did client X say?", "when did project Y start?", "alignment history with Z"), Claude:
  1. First runs deterministic grep in `~/.meeting-notes/`
  2. If no result or partial, falls back to Granola MCP
  3. Responds with file citation + date (or Granola meeting ID)
- **Conditional and silent**: if `~/.meeting-notes/` does not exist, the skill does not activate. If Granola MCP is not configured, the skill skips the fallback. No error, no noise.
- **Success criteria**:
  - A 4Shark team engineer running `git pull` in `~/.claude/` sees no new behavior and no error
  - Paulo, when asking about meetings, gets automatic search in meeting notes first and Granola second
  - Answers always cite the source (file `:line` or meeting ID)

## Problem / New Feature

- **Objective description**: create an invokable skill `meeting-context` that structures search across two hierarchical sources (local markdown → Granola MCP), with auto-detection of availability.
- **Current symptoms**: today Claude, when asked "what did client X say in March?", may try WebSearch, list random directories, or answer "I don't have access". No consistency.

## Challenges, Difficulties and Risks

- **Technical**:
  - Invocation: the skill must activate on relevant questions without being invasive (not run on every conversation)
  - Deduplication: new Granola meetings may eventually be mirrored into `~/.meeting-notes/` — the skill must not return duplicates
  - Scale: grep over 755 files is cheap, but Granola MCP may have latency
- **Product/UX**:
  - Filesystem-conditional is fragile — if Paulo deletes `~/.meeting-notes/` by mistake, the skill silently turns off (no warning)
  - Other devs may be confused seeing the skill listed but "doing nothing" on their machine
- **Security/privacy**:
  - Meeting notes contain confidential conversations with clients — the skill must never leak content into commits, PRs, or issues
  - Granola MCP is HTTP — traffic goes through Granola's network
- **Performance**:
  - Grep is local, instantaneous
  - Granola MCP has network roundtrip — use only as fallback, not primary

## Solution Options (comparative)

- **Option 1 — Single skill with environment auto-check**
  - **How it works**: file `~/.claude/skills/meeting-context.md` (via PR in the team repo). First instruction of the skill: check whether `~/.meeting-notes/` exists. If not, the skill exits immediately doing nothing. If yes, proceed with grep → Granola fallback. The skill description triggers auto-match on questions about meetings/history/clients.
  - **Pros**: single file versioned in the team repo; other devs have no adverse effect; explicit invocation flow (`/meeting-context`) or auto-match via description
  - **Cons**: the skill appears in the other devs' skill list even though it does not serve them (low visual noise); auto-match depends on the description quality
  - **When NOT to use**: if the team decides conditional skills are an antipattern

- **Option 2 — Personal skill outside the repo**
  - **How it works**: create the skill outside `~/.claude/` (e.g., `~/my-skills/meeting-context.md`) and reference it via a personal `settings.local.json`. Does not enter the team repo.
  - **Pros**: zero noise for other devs; fully isolated
  - **Cons**: Claude Code by default looks for skills in `~/.claude/skills/` — mechanism for external skills requires custom configuration; divergence between personal and team; if forgotten, I lose it when switching machines
  - **When NOT to use**: when the skill could be useful for the team in the future (e.g., if other devs start using Granola, the skill is already there)

- **Option 3 — Conditional CLAUDE.md reference**
  - **How it works**: add a section to `~/.claude/CLAUDE.md` referencing `@~/.meeting-notes/INSTRUCTIONS.md` (a file that only exists on Paulo's machine). If the file does not exist, the @-include fails silently or emits a warning.
  - **Pros**: loads automatically, no skill invocation needed
  - **Cons**: consumes context every time (not on demand); if the @-include breaks on other devs, CLAUDE.md becomes incompatible; behavior of @-include on missing files is not guaranteed
  - **When NOT to use**: whenever an on-demand skill is possible

## Proposed Steps (high level, don't execute yet)

1. Create branch `feature/meeting-context-skill` in `~/Projects/4Shark/.claude/`
2. Create `~/Projects/4Shark/.claude/skills/meeting-context.md` with:
   - YAML frontmatter (name, description with activation keywords)
   - "Pre-check" section instructing: if `~/.meeting-notes/` does not exist, exit immediately
   - "Primary source" section: instructions to grep in `~/.meeting-notes/{4shark,personal}/{year}/`, filters by frontmatter (client, vendor, internal, date)
   - "Fallback" section: how to invoke `mcp__granola__query_granola_meetings` if the local result is empty/partial
   - "Output contract" section: answers always with citation `file:line` or `granola_meeting_id`
   - "Deduplication" section: if Granola returns meetings with date/title already present in local notes, discard the Granola duplicate
3. Update `~/Projects/4Shark/.claude/README.md` or `CLAUDE.md` (if it makes sense) listing the skill as optional
4. Commit: `feat(skills): add meeting-context skill for history queries`
5. Push + open PR against `develop`
6. After merge: `cd ~/.claude && git pull`
7. Test invocation: "what did we discuss with Atento in March?" → the skill should activate, grep `~/.meeting-notes/`, return matches with citation
8. Test auto-disable on a machine without `~/.meeting-notes/` (or simulating with `mv ~/.meeting-notes /tmp/meeting-notes-bak`)

## Internal References

- Meeting notes: `~/.meeting-notes/{4shark,personal}/{2025,2026}/*.md` (755 files)
- Frontmatter structure: documented in `~/.claude/plans/completed/spike/spark-to-granola-migration/SPIKE.md`
- Granola MCP config: `~/.claude.json` → `projects → ~/Projects/4Shark/app → mcpServers.granola`
- Skills directory convention: `~/.claude/skills/*.md` (team-shared via git)

---

**Question:** Which option do you prefer to follow?
Answer with: `APPROVED: Option 1` **or** `APPROVED: Option 2` **or** `APPROVED: Option 3`.
(Alternative options are welcome, describe if applicable.)
