# SPIKE — Output Policy Unification

**Conducted by:** Paulo Ribeiro
**Date:** 2026-05-14
**Status:** Closed — decisions taken (revision 3), implementation merged + follow-up fix in flight

---

## Goal

### Why

Output rules in this configuration are spread across 5+ sections of `~/.claude/CLAUDE.md` and one Tier 2 doc, with inconsistent framing and no single entry point. A recurring failure mode: after a research phase (multiple `Read`/`Grep`/`WebFetch`), the agent produces a chat response with many findings but no code excerpts, mixing informational items with items requiring decision, ignoring the `>3 gate`. The engineer is then forced to re-read the code to evaluate the suggestions — exactly what delegating to the agent was supposed to avoid.

Concrete incident (2026-05-14): engineer asked the main session to "study the current code and plan the next phase". Agent performed 6+ Reads/Greps then dropped a 7-section chat message with `file:line` references but zero excerpts, mixing an informational table of stored procedures with five "proposed architecture" paragraphs and an `AskUserQuestion` at the end. The engineer's complaint: *"voce me traz uma lista com 7 itens, de onde alguns eu nao tenho nada para fazer, outros eu nao faco ideia do problema e outros voce deu uma solucao que na consigo avaliar"*.

### Questions

1. Why does the "Delegation Context Principle" rule exist but not fire at the moment of the research output?
2. Which other output rules exist and where are they spread? Where are the gaps?
3. What structure unifies all output rules so that (a) the correct rule fires at the right moment, (b) maintenance stays manageable?
4. Is `PostToolUse` + `additionalContext` technically viable as an active trigger?

---

## Method

1. Full read of `~/.claude/CLAUDE.md` — scope: `Output Formatting and Delivery`, `Delegation Context Principle`, `Research-First Policy`, `Communication Style`, `Questions Are Just Questions`, `Bash Single-Line Policy`, `Plans Storage`, `Command Safety Policy`.
2. Read of `~/.claude/docs/` — `OUTPUT-FORMATTING.md`, `adr/ADR-001-rules-loading-mechanism.md`.
3. Implementation audit in `~/.claude/agents/` (`planner.md`, `spike.md`, `code-reviewer.md`) and `~/.claude/commands/` (`triage-pr.md`) — where the principle is already hardcoded successfully.
4. Technical verification via `WebFetch` of `https://code.claude.com/docs/en/hooks` — confirmed `PostToolUse` and `PostToolBatch` accept `hookSpecificOutput.additionalContext`.

---

## Evidence

### 1. Where output rules already live (audit)

| Output type | Rule location | Status |
|---|---|---|
| Findings after research | `CLAUDE.md` § Delegation Context Principle | Rule exists (excerpt + `>3 gate`); **missing**: "default destination is a document, not chat" |
| Pattern comparison | `CLAUDE.md` § Delegation Context Principle + `agents/planner.md` | OK in agent persona, gap in main session |
| Email draft | `CLAUDE.md` § Output Formatting and Delivery + `docs/OUTPUT-FORMATTING.md` | OK (≤10 lines chat, >10 → `/tmp/` + `open`) |
| Code block to paste | `CLAUDE.md` § Output Formatting and Delivery | OK (`/tmp/` + `open`, no markdown fences) |
| Single terminal command | `CLAUDE.md` § Output Formatting and Delivery | OK (bare, no fences) |
| Complex/multi-line command | `CLAUDE.md` § Bash Single-Line Policy | OK (script in `/tmp/` + single-line invocation) |
| External tool output (terraform/aws/db) | `CLAUDE.md` § Output Formatting + § Command Safety | OK (`/tmp/`, never piped) |
| Short chat response | system prompt + `CLAUDE.md` § Communication Style | OK |
| Answer to engineer question | `CLAUDE.md` § Questions Are Just Questions | OK |
| Source citation | `CLAUDE.md` § Research-First Policy | OK |

### 2. Current implementation of the Delegation Context Principle (DCP)

DCP is reinforced in four places:

- `CLAUDE.md` (Tier 1) — passive text loaded at SessionStart
- `agents/planner.md` lines 180–198 — hardcoded persona, decision-ready block + `>3 gate`
- `agents/spike.md` lines 38, 70 — hardcoded, references DCP by name
- `agents/code-reviewer.md` lines 92–100 + 104–150 — explicit pacing gate before generating the report
- `commands/triage-pr.md` lines 85–94 — explicit pacing gate before Step 1.4

The hardcoded reinforcement works reliably when the engineer **invokes** the agent/skill. It does **not** apply when the same kind of work happens in the main session without an explicit agent invocation.

### 3. Why the rule failed today

- (a) Engineer did not invoke `@agent-spike` / `@agent-planner` → the hardcoded reinforcement in those personas did not load.
- (b) The CLAUDE.md text sits 30k+ tokens upstream from the point of response generation, competing with `Research-First Policy` immediately below it (which actively encourages `Read`/`Grep`).
- (c) Framing of the rule: *"Where this applies: every agent and skill that presents..."* — the literal wording suggests it covers **delegated** work, not the main session doing the same kind of work.
- (d) No default of "after research, write to a document". The path of least resistance is `chat`, and nothing pushes back on it.

### 4. PostToolUse + additionalContext — technical validation

Source: https://code.claude.com/docs/en/hooks (verified via `WebFetch`).

- `PostToolUse` accepts `hookSpecificOutput.additionalContext`.
- The injected reminder appears **next to the tool result** — i.e., immediately after the read completes, in the next generation step. Exact moment of the failure mode.
- Events that support `additionalContext` injection: `SessionStart`, `Setup`, `SubagentStart`, `UserPromptSubmit`, `UserPromptExpansion`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PostToolBatch`.
- `PostToolBatch` is potentially cleaner than per-tool `PostToolUse`: when several `Read`s run in parallel in the same turn, `PostToolBatch` fires once rather than N times.

### 5. Precedent — `inject-terraform-context.sh`

`ADR-001-rules-loading-mechanism.md` documents the strategy. `paths:` frontmatter in `~/.claude/rules/` does not fire for Bash commands, so `scripts/inject-terraform-context.sh` is wired as a `PreToolUse` hook with `if: "Bash(terraform *)"` and injects `TERRAFORM-POLICY.md` + `IDENTITY-STACK.md` + `TERRAFORM-CONVENTIONS.md` before every terraform invocation. The same pattern applies here for research output.

---

## Conclusions

### Diagnosis

1. **The problem is structural, not textual**: output rules exist, but they are (a) spread across 5+ sections of `CLAUDE.md`, (b) passive (read at SessionStart, never re-injected), (c) inconsistently framed across sections, (d) lacking a single entry point.
2. **DCP does not fire in the main session** because (a) framing implicitly excludes that case, (b) there is no active trigger, (c) it competes with `Research-First Policy` 30k+ tokens upstream of the response.
3. **The fix has two sides**: textual (cohesion + wording) AND mechanical (active hook at the moment of output).

### Proposed decision

**Unify all output rules into an "Output Policy" section — inline master table in CLAUDE.md, edge cases stay in Tier 2 (`docs/OUTPUT-FORMATTING.md`).**

The "Output Policy" section in CLAUDE.md replaces the current `Output Formatting and Delivery` section and absorbs the output-related portions of: `Delegation Context Principle`, `Bash Single-Line Policy`, `Research-First Policy` (citation part), and `Command Safety Policy` (preserve-external-output part). The non-output portions of those sections stay in place with a cross-reference to Output Policy.

#### Master table draft (refined during PLAN.md)

| Output type | Channel | Format | Where |
|---|---|---|---|
| Research findings, ≤3 items | Chat | Code excerpt 10–15 lines fenced + `file:line` + flow narrative (1 sentence) + verdict/question | Chat inline |
| Research findings, >3 items | File (default) + chat summary | Same per-item format; chat carries only items requiring immediate decision | `~/.claude/plans/active/<topic>/ANALYSIS.md` |
| Pattern comparison for plan decision | Chat or file (`>3 gate`) | Per-pattern: name + `file:line` + ~10–15 line excerpt + "what it does" sentence + choice prompt | Chat or `ANALYSIS.md` |
| Email draft ≤10 lines | Chat | Plain text, no markdown | Chat |
| Email draft >10 lines | File | Plain text, no markdown | `/tmp/email_*_{timestamp}.txt` + `open` |
| Code block to paste into IDE | File | Bare code, no markdown fences | `/tmp/{lang}_*_{timestamp}.{ext}` + `open` |
| Single terminal command | Chat | Bare command, no fences, no inline backticks around values | Chat |
| Complex/multi-line command logic | File-invoked | Script body in file + single-line invocation in chat | `/tmp/{command}_*_{timestamp}.sh` |
| External tool output (terraform/aws/db/HTTP) | File | As emitted | `/tmp/{tool}_{env}_*_{timestamp}.{ext}` + `open` |
| Engineer asked a question | Chat | Direct answer, no expansion into adjacent topics | Chat |
| Source citation (code) | Chat inline | `file:line` + verbatim quote from the file | Chat |
| Source citation (external) | Chat inline | URL + key quote | Chat |
| End-of-turn summary | Chat | 1–2 sentences: what changed + what is next | Chat |

**Anchor rules around the table**:

- **Pacing gate (`>3 gate`)**: when more than 3 items require engineer judgment, STOP and ask *"Bring them one at a time, or all at once?"* before presenting. Engineer explicit invocation overrides the gate.
- **Default after a research phase**: write `ANALYSIS.md` first, then summarize in chat. Chat carries only items that need immediate decision.
- **Engineer should not have to clean up the output**: if they would strip fences, dewrap lines, or escape characters before using it — the output is in the wrong shape.
- **Edge cases per destination**: Slack mrkdwn, Outlook quirks, IDE auto-format, terminal escaping → see `docs/OUTPUT-FORMATTING.md` (or rename to `OUTPUT-EDGE-CASES.md` — decide in PLAN).

### Hook — initial proposal (counter-based, abandoned in revision 3)

The original spike proposed a counter-based hook on `PostToolUse` (`Read|Grep|Glob|WebFetch`). Implemented and merged in PR #157, then found broken in production: the script used `${CLAUDE_SESSION_ID:-$$}` for the counter filename, but that env var **does not exist** in Claude Code (verified via [hooks docs](https://code.claude.com/docs/en/hooks) — `session_id` lives in the JSON stdin payload, not as an env var). Fallback `$$` resolved to the subshell PID, which is different each hook fire — so every Read created a new counter file with value `1`, and the threshold was never reached.

Beyond the bug, the counter approach was architecturally weak: each hook invocation is process-isolated, so any "counting" requires external state (file in `/tmp/`), which then needs session-id correlation, then cleanup — layers of plumbing to simulate state the process does not have.

### Hook — revised approach (stateless, `UserPromptSubmit`)

- **Trigger**: `UserPromptSubmit` (matcher `*`) — fires once per engineer turn.
- **State**: none. The script always emits the same reminder. Stateless, deterministic.
- **Logic**: emit `additionalContext`:

    ```
    === RESEARCH OUTPUT REMINDER ===

    You have performed 3+ research reads in a row. Before producing chat output:

    1. Default — write to a document first (~/.claude/plans/active/<topic>/ANALYSIS.md
       or SPIKE.md), then summarize in chat. Chat carries only items requiring
       immediate decision from the engineer.
    2. Inline format (when chat is the right channel): every item for decision
       needs code excerpt (10-15 lines fenced + file:line) + flow narrative
       (1 sentence "where in the system, what it does there") + verdict/question.
    3. >3 items for decision: STOP and ask "Bring them one at a time, or all at
       once?" BEFORE presenting any item.

    See § Output Policy in ~/.claude/CLAUDE.md.
    ```

- **Always exit 0** so the hook never blocks tool use.
- **Threshold = 3** rationale: ≤2 reads is a normal lookup; 3+ reads signals investigation.
- **Cleanup**: counter files removed by `cleanup-sessions.sh` at SessionStart (already cleans `/tmp/`-style state).

### Textual migration map (CLAUDE.md sections that lose content)

| Section | What moves to "Output Policy" | What stays |
|---|---|---|
| `Output Formatting and Delivery` | Entire table → master table; entire "File naming for /tmp/ outputs" → kept inline under master table | Section absorbed |
| `Delegation Context Principle` | "code excerpt + flow narrative", "`>3 gate`" rules → master table anchors | Motivation ("delegating = engineer should not re-read"), "Where this applies" list of agents/skills |
| `Bash Single-Line Policy` | "`/tmp/` script for complex commands" → master table row | Permissions-matcher bug rationale, `Executando o comando completo:` print rule |
| `Command Safety Policy` | "/tmp/ + open" for external command output → master table row, "never pipe into text processing" → kept under master table | No-chaining rules, atomic infrastructure commands |
| `Research-First Policy` | Citation requirement → master table rows | "Never answer from training data", "I don't know is preferred" |
| `Communication Style` | (no content moves) | Stays. Add link to Output Policy at the top. |
| `Questions Are Just Questions` | (no content moves) | Stays. Add link to Output Policy at the top. |
| `Plans Storage` | (no content moves) | Stays. Add note: "`ANALYSIS.md` is the default destination for research output (see Output Policy)." |

### Risks and caveats

1. **Hook false positives**: quick lookups (≤3 reads to answer a simple question) also dispatch reads. Mitigation: threshold at 3, reset on `Edit`/`Write`/`AskUserQuestion`, reminder is advisory not blocking.
2. **State in `/tmp/`**: must be cleaned at SessionStart. Confirm `cleanup-sessions.sh` covers the pattern or extend it.
3. **Cross-references break with migration**: several CLAUDE.md sections cite each other by section name. PLAN.md must audit cross-references before the rewrite.
4. **`OUTPUT-FORMATTING.md` rename**: if we rename to `OUTPUT-EDGE-CASES.md`, `scripts/read-context.sh` and any pointer must be updated. Decision in PLAN.md.
5. **Agent/skill personas already reference DCP by name**: `planner.md`, `spike.md`, `code-reviewer.md`, `triage-pr.md`, `task-creator.md`, `security-reviewer.md`, `meeting-context.md` — all need to point to "Output Policy" after migration. Audit list in PLAN.md.
6. **Future hooks**: same pattern (active injection) likely applies to other output classes — e.g., detect generation of long shell commands in chat and remind to use `/tmp/`. Out of scope here; flag as follow-up.

---

## Decisions taken (2026-05-14)

| Decision | Outcome |
|---|---|
| PR strategy | Single PR covering all phases |
| `docs/OUTPUT-FORMATTING.md` rename | Rename to `OUTPUT-EDGE-CASES.md` — the doc holds only per-destination edge cases after migration; the new name reflects what is actually there |
| "Delegation Context Principle" term | Removed. All references (in `CLAUDE.md` and across `agents/`, `commands/`) are replaced by `Output Policy`. DCP mechanics (excerpt + flow narrative + `>3 gate`) become anchor rules under Output Policy, not a separate concept |

## Scope expansion (revision 2, 2026-05-14)

The original SPIKE focused on consolidating existing rules under "Output Policy". During execution review (Task 3 hold point), the engineer expanded the scope substantially based on community evidence and concrete failure cases. The expansion is summarized below; the original SPIKE content remains valid as the baseline.

### Why expanded

Two concrete failures made the original scope insufficient:

1. **Markdown wall after research** (the original failure) — addressed by Output Policy + hook.
2. **Wrong file destination for deliverables** — engineer asked for a spreadsheet; agent generated `.xlsx` in `/tmp/`; engineer reported "I can't grab files from there easily" and asked to move to `~/Downloads/`. Reveals a missing axis in the destination rule.

### Community evidence (verified via WebFetch and WebSearch)

| Finding | Source |
|---|---|
| *"If your reader is a model, use Markdown. If your reader is you, use HTML."* Canonical rule by Thariq Shihipar (Anthropic Claude Code team), post viral with 750k views in May 2026 | Simon Willison's analysis [simonwillison.net/2026/May/8/unreasonable-effectiveness-of-html/](https://simonwillison.net/2026/May/8/unreasonable-effectiveness-of-html/) |
| HTML beats Markdown for human consumption: SVG diagrams, color-coded severity, interactive filters, sortable tables, tabs. Markdown beats HTML for LLM consumption (60.7% vs 53.6% table extraction accuracy) | Multiple — BeAM, anycap, BigGo Finance |
| Mermaid: 10 tokens vs 55 ASCII for diagrams; renders natively in GitHub/Notion/markdown | `mermaid-js/mermaid` GitHub, DEV Community |
| 9 canonical HTML output patterns already mapped by community | `ghoulvspol/html-effectiveness-skill` GitHub (no license — names/concepts are public-domain ideas, the code is not copyable) |
| MIT-licensed HTML report skill with reusable `base.html` template (Tailwind + Chart.js + Mermaid + KaTeX via CDN) | `voidful/claude-html-report-skill` GitHub — useful as conceptual reference, but the publish-to-GitHub-Pages workflow does not fit our `/tmp/`-based flow |
| Anti-pattern in Claude Code system prompts: *"avoid a big soup of Dos and Don'ts as they are harder to keep track and maintain mutual exclusivity"* | sankalp's blog, Piebald-AI claude-code-system-prompts repo |

### Decision: do not adopt any third-party skill directly

- `ghoulvspol` has no LICENSE — adopting CSS, HTML examples, or skill text verbatim is not legal. The **9 pattern names and structures** (Comparison Board, Code Review Board, Decision Matrix, etc) are conceptual and freely usable.
- `voidful` is MIT but its workflow targets GitHub Pages publishing, not local-machine `/tmp/`/`~/Downloads/` deliverables. Its template `base.html` is heavy on CDN dependencies (Tailwind + 5 other libraries).
- **Build our own templates from scratch**, inspired by both — self-contained CSS inline (no Tailwind), single Mermaid CDN as the only external dependency, file destination per Output Policy rules. Cite both sources in the templates as inspiration.

### Decision: skill is the wrong primitive for this

The original SPIKE proposed a skill. On review, this introduces friction: the engineer should not need to invoke `/html-output` to get a Code Review Board from `@agent-code-reviewer`. The Code Review Board should be the **natural default output** of that agent.

The correct primitives are:

- **`~/.claude/templates/html/`** — reusable HTML templates
- **CLAUDE.md § Output Policy** — when each template applies
- **Agent personas** — reference their default template directly

Skills exist for `voidful` and `ghoulvspol` because they are generic standalone projects without their own agent ecosystem. 4Shark already has agents and a universal CLAUDE.md — using a skill on top is duplication.

### Decision: destination axis — `/tmp/` vs `~/Downloads/`

The original Output Formatting rule sent everything to `/tmp/`. The engineer flagged this is too coarse:

- `/tmp/` — **default** for everything: working files, intermediate scripts, tool output (terraform/aws), email drafts, code blocks for the engineer's own use, HTML reports for local review, logs, dumps.
- `~/Downloads/` — **only when the file is meant to leave the engineer's machine**: formats whose intrinsic function is distribution (`.xlsx`, `.csv`, `.pdf`, `.pptx`, `.docx`), or when the engineer explicitly says "downloads".

The agent does not try to guess intent — default stays `/tmp/`. Override only on explicit format or explicit engineer instruction.

This requires `~/Downloads/` in `settings.json` `additionalDirectories`.

### Decision: HTML patterns — 5 mapped + 3 optional

**Mapped to existing agents (always the default output):**

| Pattern | Agent / context |
|---|---|
| Code Review Board | `code-reviewer`, `security-reviewer` |
| Comparison Board | `planner` (pattern comparison) |
| Decision Matrix | `spike` (options analysis), `planner` (technical decisions) |
| Interactive Report | findings after multi-Read research (main session output via the hook) |
| Annotated Timeline | `integration-debug`, audit trails |

**Optional templates (used when engineer explicitly asks):**

- Knowledge Explorer — when engineer asks "me explica X" with multiple aspects
- Kanban Board — when engineer asks to visualize task state
- Slide Deck — replaces PPT for client presentations

`Design Token Sheet` (the 9th pattern in `ghoulvspol`) is not adopted — no design system context in 4Shark.

### Decision: Mermaid default for diagrams in markdown

Mermaid syntax (`graph TD; A-->B`) is 10 tokens vs ~55 for equivalent ASCII art, and renders natively in GitHub PR descriptions, GitHub issues, Notion, and Claude chat. Default for any diagram inside markdown (PLAN.md, SPIKE.md, ANALYSIS.md, PROCESS.md, DOMAIN.md, etc). HTML templates import Mermaid via CDN.

### Decision: Charts and images in HTML reports (added during execution)

Engineer raised during Task 6: HTML templates need to support **charts of quantitative data** (bar, line, pie, scatter) and **embedded images** (screenshots, externally-generated plots), not just Mermaid diagrams. Solution:

- **Chart.js** (MIT, ~60KB) added as a second optional CDN dependency in `base.html`. Auto-loaded only when the report contains `<canvas class="chart">` — same conditional pattern as Mermaid. Covers ~80% of charting needs.
- **Images** embedded either by `<img src="file:///tmp/...">` reference, or by inline base64 for self-contained portability (< 50KB recommended). Always wrapped in `<figure>` with `<figcaption>`.
- **Inline SVG** documented as the zero-dep fallback for custom diagrams Mermaid cannot express.

`base.html` and `interactive-report.html` ship with the loader hooks and CSS classes (`.chart-container`, `figure`, `figcaption`) so every pattern that extends them gets charts/images "for free". Documented under § Output Policy → "Visual elements — diagrams, charts, images" in `CLAUDE.md`.

### Output Policy — final structure (5 layers)

**Layer 1 — Format by destination** (existing, kept):
Email plain text, Slack plain text, terminal bare command, IDE code without fences, PR/issue/doc Markdown, chat Markdown.

**Layer 2 — Channel: chat vs file** (existing, kept):
Short inline → chat. Long content → file.

**Layer 3 — File destination: `/tmp/` vs `~/Downloads/`** (new):
Default `/tmp/`. `~/Downloads/` only for distribution formats (`.xlsx`, `.csv`, `.pdf`, `.pptx`, `.docx`) or explicit engineer request.

**Layer 4 — File format: who consumes it** (new):

| Consumer | Format |
|---|---|
| Another LLM (KNOWLEDGE/DOMAIN/PROCESS/PLAN/TASKS, planning docs) | Markdown |
| Engineer reviewing visually (code review, comparisons, findings, timelines) | HTML self-contained from `~/.claude/templates/html/<pattern>.html` |
| External tool (terraform plan, aws describe, db query) | Raw text |

**Layer 5 — Workflow rules** (absorbed from DCP, Research-First, Bash Single-Line, Command Safety):
- Pacing gate `>3 items` for decision → STOP and ask
- After research phase with 3+ reads → write document/HTML first, chat carries summary only (hook reminder)
- Every item for decision needs code excerpt + flow narrative + verdict/question
- Citation requirement
- Complex command logic → script in `/tmp/`, single-line invocation in chat
- Tool output → file, never piped into text processing

**File naming** (existing pattern, kept): `{location}/{command}_{environment}_{parameters}_{timestamp}.{ext}`

---

## Next Steps

Generate `~/.claude/plans/active/dot-claude/output-policy-unification/PLAN.md` covering:

1. **Phase 1** — Cross-reference audit in CLAUDE.md (all "see § X" / "in the Y section" pointers, plus pointers from `agents/` and `commands/` to DCP and Output Formatting).
2. **Phase 2** — Author the "Output Policy" section (master table + anchor rules + cross-link to `OUTPUT-FORMATTING.md` / renamed equivalent).
3. **Phase 3** — Textual migration: extract output-related text from `Output Formatting and Delivery`, `Delegation Context Principle`, `Bash Single-Line Policy`, `Research-First Policy`, `Command Safety Policy`. Leave back-references where useful.
4. **Phase 4** — `docs/OUTPUT-FORMATTING.md` — decide rename vs. keep, prune content that moved to CLAUDE.md, expand remaining edge cases.
5. **Phase 5** — `scripts/inject-research-output-context.sh` — implement, register in `settings.json`, manual test.
6. **Phase 6** — `scripts/cleanup-sessions.sh` — extend to clear `claude-research-counter-*` files.
7. **Phase 7** — Update agent/skill personas to reference "Output Policy" instead of "Delegation Context Principle" (or both, with the latter as nested concept under the former).
8. **Phase 8** — `CHANGELOG.md` + PR. Decide single PR vs. one per phase in PLAN.md.

Implementation goes through PR workflow on the `dot-claude` repo at `~/Projects/4Shark/dot-claude/`. Direct edits to `~/.claude/` are forbidden by `CLAUDE.md`.
