# SPIKE — Claude Code Auto Memory: community sentiment and mitigation options

**Conducted by:** Research agent (Claude Sonnet 4.6)
**Date:** 2026-05-15
**Status:** Research complete — pending decisions

---

## Goal

Answer the following questions before deciding whether 4Shark should disable, keep, or replace Claude Code's native auto-memory:

1. When and how was auto-memory introduced? What did Anthropic communicate officially?
2. What issues exist in the official repository, and what is their sentiment?
3. What is the community saying (Reddit, HN, X, blogs)?
4. What workarounds are being adopted?
5. What are 4Shark's concrete mitigation options, with trade-offs?

**Context:** 4Shark built the `/cleanup-memories` skill as a local mitigation — low-value memories being saved without control are polluting the system. The question is whether to disable the feature or whether a better alternative exists.

---

## Method

- Extensive web research (~90 min): official documentation (`code.claude.com`), GitHub releases (`gh api`), issues from the `anthropics/claude-code` repo, technical articles, developer blogs, HN threads, comparative analyses
- Direct access to the repo CHANGELOG via `gh api` for exact dates
- Reading the auto-memory system prompt via the `Piebald-AI/claude-code-system-prompts` repo (exposed after the March 2026 source leak)
- Reddit not directly accessible via WebFetch — coverage via aggregations and articles that cite threads

---

## Evidence

### 1. Official timeline

#### v2.1.32 — February 5, 2026 (introduction)

Source: `gh api repos/anthropics/claude-code/releases`, CHANGELOG entry:

> "Claude now automatically records and recalls memories as it works"
> — Release notes v2.1.32, 2026-02-05T17:47:50Z

This version also introduced Agent Teams (preview). Auto-memory was introduced without a separate announcement, as part of a larger release that brought Opus 4.6.

#### v2.1.59 — February 26, 2026 (refinement + /memory command)

> "Claude automatically saves useful context to auto-memory. Manage with /memory"
> — Release notes v2.1.59, 2026-02-26T00:59:24Z

This version added the `/memory` command and made the feature more visible. Official docs (`code.claude.com/docs/en/memory`) mention v2.1.59 as the minimum auto-memory requirement, suggesting v2.1.32 was an experimental/incomplete version.

#### v2.1.63 — February 28, 2026 (shared across worktrees)

> "Project configs & auto memory now shared across git worktrees of the same repository"
> — Release notes v2.1.63, 2026-02-28T03:45:37Z

#### March–April 2026: auto-dream (closed preview)

Anthropic internally tested "Auto Dream" — a nightly consolidation process that cleans and reorganizes MEMORY.md. Visible in the `/memory` menu but server-side feature-flagged, not available to the general public. Third parties created open-source alternatives (see workarounds).

---

### 2. What Anthropic communicated officially

Source: [official documentation](https://code.claude.com/docs/en/memory)

**Design intent (stated):**

> "Auto memory lets Claude accumulate knowledge across sessions without you writing anything. Claude saves notes for itself as it works: build commands, debugging insights, architecture notes, code style preferences, and workflow habits. Claude doesn't save something every session. It decides what's worth remembering based on whether the information would be useful in a future conversation."

**Official announcement on X** (Thariq Shihipar, Anthropic staff):

> "We've rolled out a new auto-memory feature. Claude now remembers what it learns across sessions — your project context, debugging patterns, preferred approaches — and recalls it later without you having to write anything down."
> — [@trq212](https://x.com/trq212/status/2027109375765356723)

**Product positioning:** Anthropic positions CLAUDE.md as "your instructions to Claude" and MEMORY.md as "Claude's notebook about your project" — complementary systems, not substitutes.

---

### 3. Auto-memory system prompt (revealed by the source leak)

Source: [`Piebald-AI/claude-code-system-prompts`](https://github.com/Piebald-AI/claude-code-system-prompts/blob/main/system-prompts/system-prompt-memory-instructions.md) (391 tokens)

The system instructs Claude to maintain files with structured frontmatter. Categories:

- **`user`** — who the person is, role, expertise, preferences
- **`feedback`** — corrections and guidance on work approaches
- **`project`** — goals and constraints not visible in code or git history
- **`reference`** — external pointers (URLs, dashboards, tickets)

**Saving criteria (extracted from the system prompt):**

> "Before creating new memories, check existing files to avoid duplicates — update instead. Remove memories proven incorrect. Don't save information the repository already records (code structure, past fixes, git history, documentation files) or details relevant only to the current conversation."
>
> "When asked to remember repository-level content, instead ask what insight was non-obvious and save that analysis."

**Recall criterion:**

> "Memories appearing in background context blocks reflect their creation time — if one references a file, function, or flag, verify it still exists before recommending it."

**Important observation:** the system prompt tells the agent to be selective, but does not define a quantitative quality threshold. "Worth remembering based on whether the information would be useful in a future conversation" is subjective model judgment — hence the variability reported by the community.

---

### 4. Issue mapping in the official repository

| Issue | Title | Status | Problem category |
|-------|-------|--------|------------------|
| [#23544](https://github.com/anthropics/claude-code/issues/23544) | Need ability to disable auto-memory (MEMORY.md) | Closed | No disable flag, shadow state, context bloat |
| [#23750](https://github.com/anthropics/claude-code/issues/23750) | [FEATURE] Option to disable auto-memory | Closed | Conflict with `--no-memory` which disables everything including CLAUDE.md |
| [#28276](https://github.com/anthropics/claude-code/issues/28276) | [FEATURE] Configurable auto-memory storage location | Open (duplicate) | Does not sync across machines nor in git |
| [#28960](https://github.com/anthropics/claude-code/issues/28960) | [FEATURE] time-based reminders/triggers in auto-memory | Closed as not planned | Missing temporal triggers, memories go stale |
| [#34776](https://github.com/anthropics/claude-code/issues/34776) | [FEATURE] Memory system governance for long-running users | Closed as not planned | Structural degradation in projects with 30+ sessions |
| [#37847](https://github.com/anthropics/claude-code/issues/37847) | Claude Code repeatedly ignores its own auto-memory feedback | Closed as not planned | Memories saved but not applied in practice |
| [#43393](https://github.com/anthropics/claude-code/issues/43393) | Auto-memory feedback not reliably applied | Closed | Same corrections recurring even with saved memory |
| [#44820](https://github.com/anthropics/claude-code/issues/44820) | [FEATURE] PreMemoryWrite / PostMemoryWrite hook events | Open (stale) | No hooks to intercept/filter before saving |
| [#48416](https://github.com/anthropics/claude-code/issues/48416) | [FEATURE] Auto-memory should support user-scoped entries | Closed (duplicate) | Memory not shared across different projects |
| [#48465](https://github.com/anthropics/claude-code/issues/48465) | [FEATURE] Allow MCP servers to replace auto memory backend | Open (stale) | MCP ignored when auto-memory is active |
| [#57574](https://github.com/anthropics/claude-code/issues/57574) | Auto-memory MEMORY.md silently truncated at ~25KB | Closed (duplicate) | Silent truncation removes the MOST RECENT entries |

**Patterns in the complaints:**

1. **Zero reliability** — Memories saved but not followed in practice (issues #37847, #43393)
2. **Context bloat** — Every session loads MEMORY.md in the first 200 lines or 25KB, even when CLAUDE.md already has rules covering the same ground
3. **No expiration mechanism** — Memories go stale, contradict themselves, reference renamed files
4. **Silent truncation** — In long projects, MEMORY.md grows and the 25KB limit truncates the MOST RECENT entries (chronological), exactly the most relevant ones
5. **Wrong scope** — User preferences (e.g., "I prefer Shell to Python") are saved per project, not following the user to other projects

**Anthropic's response:** none of the issues above received a public response from Anthropic. Most were closed as "not planned" or "duplicate" without comment. Issue #44820 (PreMemoryWrite hooks) went "stale" with no feedback.

---

### 5. Sentiment by channel

#### GitHub (observed behavior)

The pattern is clear: issues closed as "not planned" with no comment, requests for granular disabling closed as "duplicates". Anthropic is not publicly responding to auto-memory criticism in the repository.

Representative quote from issue #23544:

> "Auto-memory creates a parallel memory system outside user control that's difficult to view, audit, or understand. MEMORY.md lives in ~/.claude/projects/ (outside the repo), preventing version control, PR review, and codebase synchronization."

#### HN (Hacker News)

Thread [#47878905](https://news.ycombinator.com/item?id=47878905) on Claude Code quality reports (732 comments, April 2026):

> "Silent changes without disclosure — users expressed frustration that behavioral modifications occurred without announcement, violating expectations of product consistency."

General sentiment thread: developers frustrated with "silent optimizations" that change behavior with no announcement — auto-memory fits this category of changes that affect context opaquely.

#### Technical blogs and Medium

**Brent W. Peterson** ([source](https://medium.com/@brentwpeterson/automatic-memory-is-not-learning-4191f548df4c)):

> "Claude doesn't learn anything from auto memory the way you or I learn from experience...That's not learning. That's configuration."

After months of use across 13 projects, he found only 12 lines in MEMORY.md — the system saved less than expected. The conclusion is that auto-memory captures "what" but not "why".

**Comparison analysis** ([ddewhurst.com](https://ddewhurst.com/blog/claude-mem-vs-auto-memory/)):

Three positions emerge in the community:

- **Minimalists** (40-50%): "A well-crafted CLAUDE.md handles 80-90% of the memory problem with zero dependencies" — tolerate or disable auto-memory
- **Pragmatists** (30-40%): want auto-memory improved but acknowledge current limitations — keep it on, audit periodically
- **Power users** (10-20%): report meaningful gains and accept the maintenance overhead

**Dev.to** ([source](https://dev.to/gonewx/i-tried-3-different-ways-to-fix-claude-codes-memory-problem-heres-what-actually-worked-30fk)):

> "None offer perfect solutions: 'You can't have perfect memory in a tool that was designed session-by-session.'"

#### Reddit

Direct access blocked (reddit.com and old.reddit.com blocked for WebFetch). Indirect coverage via aggregations indicates r/ClaudeAI has 4,200+ weekly contributors, with memory being one of the most discussed topics. Sentiment is split: developers who invest time in configuration report gains, those who treat it as autocomplete get frustrated.

Indirect evidence from issue #23544 mentioning "workarounds the community tried":
- Manually deleting `~/.claude/projects/*/memory/` (ineffective — files are recreated)
- Adding "do not use auto-memory" to CLAUDE.md (unreliable, conflicts with the system prompt)
- **No viable workaround reported as actually working** before `autoMemoryEnabled: false` was implemented

#### X/Twitter

Anthony Kroeger ([source](https://x.com/kr0der/status/2036235321780621738)) about auto-dream (found on Reddit before the official announcement):

> "just found out Claude Code has a new (unreleased?) feature called 'Auto-dream' under /memory... this basically runs a subagent periodically to consolidate Claude's memory files for better long-term storage. this is pretty crazy because that's basically how [human memory works]"

---

### 6. Documented technical limitations

#### Silent truncation (issue #57574)

MEMORY.md is capped at 200 lines or 25KB. Because the file is chronological, silent truncation removes the **most recent entries** — exactly the most relevant ones. The warning exists but lives in the system prompt, not visible to the user:

> "WARNING: MEMORY.md is 34.3KB (limit: 24.4KB) — index entries are too long."

One user with 60+ sessions reached 34.3KB and lost the last weeks of memory without noticing.

#### Memories saved but not applied (issues #37847, #43393)

Quote from issue #43393:

> "The memories load as part of a large system context (CLAUDE.md, rules files, memory files). With many rules and memories competing for attention, behavioral memories may not have sufficient 'weight' compared to the immediate task context."

Concrete examples from issue #37847:
- Memory: "Use `&&` not newlines for chaining bash commands" → violated 8 times in the same session
- Memory: "Always invoke available skills via the Skill tool" → Claude ignored it and proceeded manually

#### MCP conflict (issue #48465)

When MCP memory tools are configured, the system-prompt auto-memory has **higher priority**. The agent uses MEMORY.md and ignores MCP tools — replacing the backend without disabling auto-memory completely is impossible.

---

### 7. How other tools handle memory

| Tool | Approach | Characteristic |
|------|----------|----------------|
| **Cursor** | Codebase indexing via AST + vector embeddings (Turbopuffer) | "Memory is your codebase, and your codebase doesn't lie" — no LLM-written summaries |
| **Aider** | No native auto-memory; manual CONVENTIONS.md | 4.2× fewer tokens than Claude Code; no memory overhead |
| **Cline** | Optional MCP-based memory; no auto-memory | Lets the user decide whether and how |
| **Claude Code** | Markdown files + MEMORY.md index | Auto-saving with model judgment; subject to noise |

Anthropic chose the plain-text approach (markdown) instead of vectors or code indexing — simpler, cheaper, more transparent, but less precise and more prone to degradation over time.

---

### 8. Community projects that emerged as a response

**claude-mem** ([github.com/thedotmack/claude-mem](https://github.com/thedotmack/claude-mem)):
- 75.9k stars, 6.5k forks
- SQLite + ChromaDB + semantic search + web UI
- Emerged in August 2025 (before native auto-memory) as a heavy alternative
- Risks: instability (7 releases in 3 days with reverts), process leaks with hundreds of zombies, 641 Python processes consuming 75% CPU in older versions

**dream-skill** ([github.com/grandamenium/dream-skill](https://github.com/grandamenium/dream-skill)):
- 60 stars, 13 forks
- Replicates Anthropic's unreleased auto-dream
- 4 phases: Orient → Gather → Consolidate → Prune
- Auto trigger via Stop hook every 24h

---

## Conclusions

### Dominant sentiment

**Structural frustration with pragmatic workarounds** — the community is not asking to remove auto-memory, it is asking for more control over it. The sentiment is "it has potential, but in practice it does not fulfill the promise due to lack of governance".

Evidence supporting that:
1. Issues about **disabling** were closed as "done" when `autoMemoryEnabled: false` was added — Anthropic read it as "give control, don't remove"
2. Issues about **governance** (expiration, priority, audit) were closed as "not planned" — Anthropic is not investing in making the system more sophisticated
3. The community built alternatives (dream-skill, claude-mem) instead of abandoning the feature

### The real problem is reliability, not volume

Paulo identified "a LOT of low-value content is saved". The research finds a complementary problem that compounds it: **memories are saved but frequently ignored in practice**. The system creates a false sense of security — you see "Writing memory" and assume the behavior will change, but issues #37847 and #43393 document that the same correction needs to be made repeatedly even with the memory saved.

The root cause is that memories in MEMORY.md compete with immediate task context in the context window, and the model prioritizes task context.

### Auto-memory is a `feedback` system more than an `instructions` one

The system prompt categorizes memories as: `user`, `feedback`, `project`, `reference`. For 4Shark, which has sophisticated rules in the global CLAUDE.md, the biggest overlap with `feedback` is the problem — a correction that is already codified in CLAUDE.md as an explicit rule should not enter MEMORY.md as feedback. But the agent has no way to know the rule already exists and saves anyway.

---

## Next Steps

### Mitigation options for 4Shark

| Option | Viability | Trade-off | Evidence it works |
|--------|-----------|-----------|--------------------|
| **A: Disable globally** (`"autoMemoryEnabled": false` in `~/.claude/settings.json`) | Easy — 1 line of config | Lose any value auto-memory offers; `/cleanup-memories` has no inbox to process | Yes — documented in the [official docs](https://code.claude.com/docs/en/memory); env var `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` as alternative |
| **B: Keep + instruct higher threshold in CLAUDE.md** | Easy — text instruction | Unreliable — the system prompt has priority over CLAUDE.md; the community reports "do not use auto-memory in CLAUDE.md" does not work consistently | Partially — works as a hint, not a constraint |
| **C: PreToolUse hook blocking Writes in `~/.claude/projects/*/memory/`** | Medium — needs path regex in the hook | Fragile — undocumented internal naming may change between releases; the community classifies it as "unreliable workaround" | Partially — possible but issue #44820 documents the fragility |
| **D: Keep `/cleanup-memories` as is** | Easy — already exists | Recurring time cost; treats the symptom, not the cause | Yes — already works for 4Shark |
| **E: Disable + use only global CLAUDE.md + rules/** | Easy — settings.json + rule organization | Loses automatic learning; requires discipline to update CLAUDE.md manually | Yes — "minimalist" approach validated by the community |
| **F: PreMemoryWrite hook** (filters before saving) | Hard — does not exist yet | Issue #44820 proposes this but it is "stale" with no response from Anthropic | No — feature not available |

### Evidence-based recommendation

**For 4Shark's specific case** (sophisticated global CLAUDE.md, `/cleanup-memories` skill, rules already explicit):

Option **A (disable globally)** solves the structural problem. 4Shark already has:
- Global CLAUDE.md with detailed rules
- Tier system (Tier 1/2/3 docs)
- Hooks to inject situational context
- `/cleanup-memories` as the curation workflow

Auto-memory would add value in projects without that structure. In 4Shark, the memory system is already explicit and well managed — auto-memory is additional noise competing with already-codified rules.

**Less radical alternative:** Option **E** — disable globally but with an instruction in CLAUDE.md to save explicitly when the engineer asks ("remember this"). This preserves on-demand behavior without automatic saving.

**What NOT to do:** Option B (rely on a CLAUDE.md instruction to restrict) — the research documented that the auto-memory system prompt takes priority and the instruction is unreliable.

### Decision the engineer needs to make

Before any implementation, the engineer needs to answer: **does the value `/cleanup-memories` extracts from memories (by routing them to CLAUDE.md or Tier 2 docs) compensate for the recurring cost of running it periodically?**

- If **no** → Option A: disable globally; quality memories enter CLAUDE.md manually
- If **yes, but I want to reduce noise** → Option E: disable auto-save, preserve explicit saving via `/memory`
- If **yes, and the current workflow is fine** → Option D: keep as is, accept the cost as part of the process

---

> **What is a Spike?** Time-boxed research task to reduce uncertainty. The goal is to find facts, not make decisions. This spike may generate a PLAN.md (if the decision is to implement a mitigation) or simply document knowledge for future reference.
>
> **Further reading:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/technical-spike/)
