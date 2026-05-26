# ANALYSIS — Which agents still make sense after the research-only contract

**Triggered by:** engineer's observation — "esses agentes, no final das contas, eles não vão escrever e não vão fazer nada. Talvez valha a pena revisar todos eles e ver se não tem mais algum que não faz mais sentido igual esse PR Writer."

**Context:** PR #163 introduces the Subagent Contract (research-only). Subagents cannot write workflow documents, cannot conclude, cannot recommend, cannot execute state-changing commands. Their sole output is structured findings; main composes the deliverable.

**Question:** which of the 10 surviving agents still earns its existence under the new contract?

---

## Criterion — what justifies a subagent under the new contract

A subagent costs ~7x the tokens of a main-session equivalent (Nimbalyst 2026). For that cost to pay off, the agent must deliver at least one of:

1. **Context isolation** — the work would bloat main with file reads/web fetches that main never needs to keep loaded after the job is done. Example: scanning 20 files to find 3 bugs.
2. **Parallelism** — the work can run alongside other unrelated work, finishing faster than serial.
3. **Specialized capability main can't easily replicate** — a focused prompt or tool restriction that's hard to inline.

If none of these apply, the subagent is overhead.

There is also a hard structural constraint: **subagents are one-shot, not conversational**. They get one prompt, return one response. If the agent's job requires back-and-forth Q&A with the engineer, the round-trip cost (main → subagent → engineer → main → re-spawn subagent → ...) burns the savings and then some.

---

## Per-agent verdict

### `orchestrator` — REMOVE

**Purpose today:** read `~/.claude/plans/active/`, detect current workflow phase, tell the engineer "use @agent-X next".

**Problem under the new contract:**
- *"Use @agent-X next"* is a recommendation — forbidden output shape ("the next step is X").
- The work itself (one `ls` of `plans/active/`, one `cat` of a couple of `.md` files) is trivial. No context-isolation value, no parallelism.
- It's a state-detector, not a researcher.

**Better fit:** documented behavior in `CLAUDE.md` ("at session start with no plans/active/<feature>, ask the engineer which workflow") OR a slash command `/orchestrator` if the entry-point affordance is valuable.

### `knowledge-cruncher` — REMOVE

**Purpose today:** interactive Event Storming with the engineer (domain events, commands, policies, hot spots) → returns findings for `KNOWLEDGE.md`.

**Problem under the new contract:**
- Subagents are one-shot. Event Storming is intrinsically interactive (4+ rounds of questions, each depending on previous answer).
- Every round = re-spawn subagent + reload context = ~7x token cost per round × N rounds.
- The Event Storming questions are a prompt template. Main can load the template and run the conversation directly with the engineer at 1x cost.

**Better fit:** `docs/DDD-KNOWLEDGE-CRUNCHING.md` (the Event Storming questions + ubiquitous-language prompts) loaded by main when starting DDD work, OR a slash command `/knowledge-crunching`.

### `context-mapper` — REMOVE

**Purpose today:** read `KNOWLEDGE.md`, identify bounded contexts and their DDD strategic patterns → returns findings for `CONTEXT-MAP.md`.

**Problem under the new contract:**
- One file read + structured analysis. No context-isolation value.
- The DDD strategic-pattern table (Customer-Supplier, Shared Kernel, ACL, etc.) is a reference table — a doc, not a worker.

**Better fit:** `docs/DDD-CONTEXT-MAPPING.md` with the pattern reference table.

### `process-modeler` — REMOVE

Same shape as context-mapper. Reads KNOWLEDGE.md (+ CONTEXT-MAP.md if it exists), returns process model. No context-isolation value; main can do this directly with a doc/template.

### `domain-modeler` — REMOVE

Same shape. Reads KNOWLEDGE.md + PROCESS.md (+ CONTEXT-MAP.md), returns entities/VOs/aggregates. No context-isolation value.

### `planner` — REMOVE

**Purpose today:** read DDD docs (if present) OR talk to engineer (if not) → return options + trade-offs for `PLAN.md`.

**Problem under the new contract:**
- When DDD docs exist: read+synthesize. Trivial; no isolation value.
- When DDD docs don't exist: interactive Q&A with the engineer. Same broken model as knowledge-cruncher.
- The "find existing patterns first" rule is valuable — but it's a *rule*, belongs in `CLAUDE.md` or a doc.

**Better fit:** `docs/PLANNING-GUIDE.md` carrying the pattern-finding rule and the options-not-recommendations discipline. Main composes `PLAN.md` directly.

### `task-creator` — REMOVE

**Purpose today:** read `PLAN.md`, derive `TASKS.md`.

**Problem under the new contract:**
- One file read + mechanical decomposition. No context-isolation value, no specialized capability.
- Main reads PLAN.md anyway to drive execution — splitting into a subagent burns ~7x for nothing.

**Better fit:** `templates/TASKS.template.md` (already exists) + main composes directly.

### `spike` — KEEP

**Purpose today:** time-boxed research using web + codebase, return findings for `SPIKE.md`.

**Why this still earns the cost:**
- Long research that bloats main with 5–15 file reads + 3–6 web fetches + 2–4 read-only bash commands. Classic context-isolation use case.
- The output (structured findings) is consumed once by main when composing `SPIKE.md`. Main doesn't need the 25 sources loaded afterward.
- This was the only agent in the failed May 15 incident that had a legitimate reason to exist — the failure was about how it concluded, not about whether to use it.

### `code-reviewer` — KEEP

**Purpose today:** read git diff (often 10+ files), find issues, return list.

**Why this still earns the cost:**
- Scanning a 10-file diff plus convention docs plus existing tests = real context burn. Isolation value: high.
- Can run in parallel with `security-reviewer` on the same diff. Parallelism value: real.
- Main consumes the findings once when composing the HTML review board.

### `security-reviewer` — KEEP

Same shape as code-reviewer with security focus. Same justification.

---

## Summary

| Agent | Verdict | Primary reason |
|---|---|---|
| orchestrator | REMOVE | Trivial state read + recommendation (verdict-shaped, forbidden) |
| knowledge-cruncher | REMOVE | Interactive Q&A broken by one-shot subagent model |
| context-mapper | REMOVE | One file read + analysis, no isolation value |
| process-modeler | REMOVE | Same as context-mapper |
| domain-modeler | REMOVE | Same |
| planner | REMOVE | Interactive Q&A or trivial synthesis, no isolation value |
| task-creator | REMOVE | Mechanical transformation main does at 1x cost |
| **spike** | **KEEP** | Long web+code research, classic context-isolation case |
| **code-reviewer** | **KEEP** | Multi-file diff scan, parallel with security-reviewer |
| **security-reviewer** | **KEEP** | Same as code-reviewer |

**Net change:** 10 → 3 agents.

## Downstream changes needed if approved

1. **Delete 7 agent files** under `agents/`
2. **Update `CLAUDE.md`**:
   - Repository Structure agents block (drop 7)
   - Available Agents section (drop 7)
   - Standard Workflow phases (replace agent steps with "main session")
   - Extended Workflow (DDD) phases (same)
   - Plans Storage → How Agents Use It note
   - Three Workflows table (the DDD workflow is still a valid sequence — main just executes it instead of agents)
3. **Update `README.md`** — same workflow tables
4. **Update `CHANGELOG.md`** — add Removed entries
5. **Optionally** — create `docs/DDD-WORKFLOW.md` consolidating the prompts/templates from the removed DDD agents so main can replicate the structured conversations. Defer to a follow-up PR if scope is getting large.

## Open questions for the engineer

1. **Verdicts** — agree with the 7 removals? Any keeps?
2. **Slash-command conversions** — for the removed DDD agents, convert to slash commands (e.g., `/knowledge-crunching`) that load a prompt template into main, OR consolidate into a single `docs/DDD-WORKFLOW.md` reference, OR drop entirely?
3. **Scope of this PR** — bundle the removal here or open a follow-up PR? Current PR is already substantial; bundling makes review harder but keeps the contract+cleanup together as one logical unit (the engineer's stated preference: "tudo de uma vez só nesse mesmo PR").
