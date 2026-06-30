# SPIKE — policy-verifier Agent Design

## Investigation question

How should a new `policy-verifier` subagent be designed to check the CONTENT of planning and behavior-defining documents against 4Shark's internal policy/convention docs, complementing the existing `output-verifier` (which checks only structural integrity: citations, scope, template, references, and auxiliary-file bidirectional integrity)?

Specifically: six open questions about rule inventory, routing, trigger set, anti-recursion guarantee, invocation wiring, and findings-to-action contract.

**Locked design decisions (not re-opened here):**
- Name: `policy-verifier` (not `compliance-verifier` — avoids collision with `COMPLIANCE.md` doc-type)
- Separate from `output-verifier` — not a 7th check bolted onto it
- Scope: PLAN/behavior level only; does NOT gate code/PR level
- "Vazamento B" (code diverges from a good plan at /execute time) is explicitly OUT OF SCOPE
- Definition: conformance check — does a technical decision or code example in the document comply with the governing 4Shark policy doc?

---

## Sources consulted

- `~/.claude/agents/output-verifier.md` — structural analog; the six checks, status enum, false-negative weighting, N_A marking; confirmed main-driven (not hook-wired)
- `~/.claude/docs/SUBAGENT-CONTRACT.md` — exception-tier table (9 agents); verifier role section
- `~/.claude/settings.json` (643 lines) — confirmed output-verifier absent from all hooks; SubagentStart and PreToolUse hook shapes
- `~/.claude/scripts/inject-integration-debug-docs.sh` — Pattern B (full-doc injection at spawn); the anti-recursion model
- `~/.claude/scripts/inject-query-discipline.sh` — Pattern A (keyword-triggered compact reminder); rate-limiting per session
- `~/.claude/scripts/inject-deployment-strategy.sh` — Pattern A variant; line 94 shows full keyword_pattern structure
- `~/.claude/scripts/inject-terraform-context.sh` — Pattern B variant for terraform; reads 3 docs, concatenates
- `~/.claude/scripts/inject-code-pattern-on-write.sh` — precedent: fires on Write/Edit/MultiEdit but skips non-code files via extension regex; SPIKE.md/PLAN.md writes do NOT trigger code pattern priming
- `~/.claude/docs/adr/ADR-001-rules-loading-mechanism.md` — confirmed `paths:` frontmatter only fires on file Read, not during planning-phase markdown drafting; rationale for custom hook mechanism
- `~/.claude/docs/DATA-PROCESSING.md` — topology naming rules
- `~/.claude/docs/TERRAFORM-POLICY.md` — terraform guard rules
- `~/.claude/docs/RAILS-MIGRATIONS.md` — migration conventions
- `~/.claude/docs/BANG-METHOD-WEB-FLOW.md` — bang method prohibition
- `~/.claude/docs/ACTIVE-RECORD-QUERY-DISCIPLINE.md` — AR-first and DB-side shaping rules
- `~/.claude/docs/CODE-PATTERN-DISCIPLINE.md` — anti-pattern catalog
- `~/.claude/docs/OPTIONAL-BELONGS-TO.md` — belongs_to convention
- `~/.claude/docs/BULK-DELETE.md` — destroy_all/delete_all avoidance
- `~/.claude/docs/NO-MULTIPLE-RAISE.md` — validation raise pattern
- `~/.claude/docs/USE-THE-OBJECT.md` — instantiate-then-collapse prohibition
- `~/.claude/docs/DEPLOYMENT-STRATEGY.md` — deploy decision framework
- `~/.claude/agents/plan-researcher.md`, `plan-composer.md`, `task-researcher.md`, `task-composer.md`, `spike.md`, `context-mapper.md`, `domain-modeler.md`, `knowledge-cruncher.md`, `process-modeler.md` — agent file content for trigger set analysis

See auxiliary files:
- `policy_verifier_rule_inventory_1.md` — full rule inventory with verifiability classification and detection methods
- `policy_verifier_routing_table_2.md` — document-section to governing-doc routing table; signal keywords per doc
- `policy_verifier_trigger_set_3.md` — trigger set analysis + script-generating skills sub-finding

---

## Findings

### Finding 1: Rule inventory — 16 mechanically verifiable rules, 4 subjective

**Evidence:**

After reading all 11 policy docs in scope, the rules divide cleanly:

MECHANICALLY VERIFIABLE (keyword/regex detection in code examples within the document being checked):
- DATA-PROCESSING.md: topology naming (Executor/Runner/Handler forbidden as class name keywords)
- TERRAFORM-POLICY.md: `-auto-approve`, `terraform apply` without saved plan file, chained `&&`/`;`+`terraform`
- RAILS-MIGRATIONS.md: `generate migration` vs hand-created; multiple actions per migration; `statement_timeout`; `disable_ddl_transaction!` with concurrent index; `if_not_exists`/`if_exists`; `safety_assured`
- BANG-METHOD-WEB-FLOW.md: `create!`/`save!`/`update!`/`destroy!`/`find_by!` in controller/mutation code
- ACTIVE-RECORD-QUERY-DISCIPLINE.md (rules 1+2): `update_all`/`delete_all`/`connection.execute`/`find_by_sql`; `pluck` + `group_by`/`sort_by`/`transform_values`
- OPTIONAL-BELONGS-TO.md: `belongs_to` without `optional: true`
- BULK-DELETE.md: `destroy_all`, `delete_all`
- NO-MULTIPLE-RAISE.md: multiple `raise ArgumentError` in same block
- USE-THE-OBJECT.md: `.new(...)` in proximity to `.to_h`/`.to_a`

MIXED (one mechanically verifiable sub-rule, one structural):
- DATA-PROCESSING.md: IDs-only (object-passing vs ID-passing requires structural judgment)

SUBJECTIVE (requires LLM structural analysis — cannot be reduced to keyword matching):
- ACTIVE-RECORD-QUERY-DISCIPLINE.md rule 3: index awareness (requires understanding table size + query shape)
- CODE-PATTERN-DISCIPLINE.md: all 5 anti-patterns (Iceberg Class, Parameter-Passing Pipeline, Extracted Wrapper Methods, Phase Extraction, Per-Branch Delegation)
- DEPLOYMENT-STRATEGY.md: decision framework compliance (requires understanding the change being planned)

**Source:** `policy_verifier_rule_inventory_1.md` (full table with detection methods)

**Significance:** The 16 mechanically verifiable rules are high-confidence checks — the verifier flags them without needing to reason about intent. The 4 subjective rules are where false positives are most likely; the policy-verifier must note these as "requires judgment" and apply the false-negative weighting (default toward flagging rather than clearing when uncertain).

URL fetched: N/A (all local files) / Verbatim quotes checked in source files / Quote substrings confirmed at file:line locations listed in `policy_verifier_rule_inventory_1.md`

---

### Finding 2: Routing table — keyword-injection hook pattern is directly reusable

**Evidence:**

The existing injection hooks already implement document-to-routing-context mapping. The routing mechanism in `inject-deployment-strategy.sh` at line 94 demonstrates the pattern:

```
keyword_pattern='(\bdeploy\b|\bdeployment\b|\bdeploys\b|\brollout\b|zero[ -]?downtime|blue[ /-]?green|\brolling\b|\bcanary\b|\bmigration\b|\bmigrations\b|\bmigrate\b|\bmigrar\b|\brename\b|expand[ /-]?contract|\bbackfill\b|feature[ -]?flag|feature[ -]?toggle|permission[ -]?flag|\bfasear\b|\bfaseado\b|\bphased\b|\bsidekiq\b|\bTSTP\b|\bquiet\b|maintenance window|\bjanela\b)'
```

Source: `~/.claude/scripts/inject-deployment-strategy.sh:94`

The policy-verifier routing problem is the same problem applied at document-section granularity instead of prompt-keyword granularity. The verifier reads the document being checked, scans each code section for routing signal keywords (e.g. `belongs_to` → load `OPTIONAL-BELONGS-TO.md`; `add_column` → load `RAILS-MIGRATIONS.md`), then loads only the governing docs relevant to that document's content.

Full signal-keyword-to-doc mapping: `policy_verifier_routing_table_2.md`.

**Source:** `~/.claude/scripts/inject-deployment-strategy.sh:94` (keyword_pattern line), `~/.claude/scripts/inject-integration-debug-docs.sh:52-78` (full-doc injection loop), `policy_verifier_routing_table_2.md`

**Significance:** No new routing mechanism needs to be invented. The governing-doc mapping already exists implicitly in the keyword patterns of inject-*.sh hooks. The policy-verifier can reuse the same signal→doc association in its own logic, loading governing docs in full before evaluating each code section.

URL fetched: N/A (local files) / Verbatim quote at inject-deployment-strategy.sh:94 confirmed / Quote substring confirmed

---

### Finding 3: Trigger set — 5 HIGH agents, 2 MEDIUM, 2 LOW; script-generating skills need separate gating

**Evidence:**

From reading the 9 exception-tier agent files:

HIGH priority (contain first-class code examples in their canonical output):
- `plan-researcher` — PLAN-SPIKE.md contains Pattern code blocks with file:line citations and a Technical Decisions table with code rationale
- `plan-composer` — PLAN.md carries technical decisions table, migration/worker code examples from the validated draft
- `task-researcher` — TASKS-SPIKE.md contains task options with "Pattern evidence" code blocks
- `task-composer` — TASKS.md carries pattern references and code examples from the validated TASKS-SPIKE.md
- `spike` — SPIKE.md findings contain 10-15 line code excerpts in Evidence blocks sourced from codebase Read operations

MEDIUM priority (may contain policy-relevant architectural/model decisions):
- `context-mapper` — CONTEXT-MAP.md contains integration pattern choices (may reference worker topology)
- `domain-modeler` — DOMAIN.md may contain model code examples (`belongs_to`, `has_many`, validates)

LOW priority (domain concepts only, code examples not first-class):
- `knowledge-cruncher` — KNOWLEDGE.md: domain concepts, glossary, business rules
- `process-modeler` — PROCESS.md: BPMN-style business flow description

**Sub-finding — script-generating skills:**

Three skills emit code as TEXT in the chat response, not as a .md file Write:
- `integration-debug` → Rails console scripts, AR queries (governed by ACTIVE-RECORD-QUERY-DISCIPLINE.md + SCRIPT-DISCIPLINE.md)
- `create-integrator` → Terraform HCL (governed by TERRAFORM-POLICY.md)
- `create-app-webclient` → Terraform HCL + Angular scaffold (governed by TERRAFORM-POLICY.md)

The file-Write hook does NOT fire for these. Three gating options are available:
- **Option A:** PostToolUse hook on Skill tool — fires after the response is already emitted; correction requires a follow-up message; hook payload may not include the full response body (needs investigation)
- **Option B:** Inline policy checklist in each skill's SKILL.md — simple; no new hook; relies on skill's own honesty (same failure mode output-verifier exists to address)
- **Option C:** Main-driven policy-verifier Task call after each skill invocation — mirrors exact output-verifier pattern; adds a round-trip per skill call; passes code text as input rather than a file path

**Source:** `policy_verifier_trigger_set_3.md` (full analysis with source evidence per agent)

**Significance:** The core trigger set (HIGH 5 agents) is clear and bounded. The script-generating skills are a genuinely different problem: the object is a text block, not a file, and the trigger is Skill completion not file Write. These can be deferred to a follow-up decision; the HIGH trigger set can be implemented first.

URL fetched: N/A (local files) / Agent file contents confirmed via Read / Quote substrings confirmed

---

### Finding 4: Anti-recursion guarantee — Pattern B (full-doc injection at spawn) is the proven model

**Evidence:**

The anti-recursion problem: the policy-verifier must read the governing policy docs in full to check code examples against them. If the policy-verifier uses the `Read` tool itself, it is subject to the ~25k-token cap that the Full-Read Discipline exists to address. If it fails to page through a large doc, it may miss the rule it is supposed to enforce.

The existing solution is `inject-integration-debug-docs.sh` (Pattern B), which fires on PreToolUse for the Skill tool when `skill_name == "integration-debug"`, and injects the FULL content of all 4 mandatory docs as `additionalContext`:

```bash
context="=== INTEGRATION-DEBUG MANDATORY DOCS (injected in full) ===

The four mandatory reference docs for the integration-debug skill are inlined below IN FULL, so you do not depend on Read paging (the Read tool's ~25k-token cap truncates the large ones to their first page). Treat the content below as the authoritative full text — you do not need to Read these files again. Per Full-Read Discipline (~/.claude/CLAUDE.md), the obligation was to consume them entirely; this delivers them entirely.${body}"
```

Source: `~/.claude/scripts/inject-integration-debug-docs.sh:76-78`

The mechanism: a PreToolUse Task hook fires when a policy-verifier Task is spawned, identifies the target document path from the agent's input, applies the routing table (Finding 2) to determine which governing docs are needed, and injects those docs in full as `additionalContext`. This removes the Read-paging dependency structurally.

Three options for the injection scope:

**Option A — Inject ALL governing docs at spawn (simple, large):**
Pre-load all 11 policy docs whenever a policy-verifier Task starts. ~30KB+ of content regardless of whether every doc is needed. No routing logic in the hook. The verifier always has everything it needs.

**Option B — Hook parses agent prompt, injects only relevant subset (complex, targeted):**
The PreToolUse Task hook reads the policy-verifier's input, extracts the target document path, scans that document for routing signals (Finding 2 table), and injects only the docs required for that document type. Smaller context injection per call. Requires the hook to read and scan the target document at hook-fire time.

**Option C — Policy-verifier reads docs itself (removes hard guarantee):**
No injection hook; the policy-verifier uses its own Read calls to load governing docs. Risks Read-paging truncation for large docs. The Full-Read Discipline hook (`inject-full-read-reminder.sh`) provides a nudge but not a guarantee. This is structurally weaker than Pattern B.

**Source:** `~/.claude/scripts/inject-integration-debug-docs.sh:52-78`, `~/.claude/docs/adr/ADR-001-rules-loading-mechanism.md:24-45`

**Significance:** Pattern B is the proven approach for the hard guarantee. The ADR-001 finding that `paths:` frontmatter only fires on file Read (not during planning phase) confirms that a hook-injected approach is the right mechanism. The trade-off between Option A (simple, large) and Option B (complex, smaller) is the main open design choice.

URL fetched: N/A / Verbatim quote at inject-integration-debug-docs.sh:76-78 confirmed / Quote substring confirmed

---

### Finding 5: Invocation wiring — output-verifier is main-driven, not hook-wired; policy-verifier follows the same pattern

**Evidence:**

Reading all 643 lines of `~/.claude/settings.json` confirmed: the string `output-verifier` does not appear anywhere in the hooks configuration. The hooks defined are:

SubagentStart hooks (settings.json:63-92): `read-context.sh`, `inject-output-policy-reminder.sh`, `inject-skill-tip.sh`, `inject-query-discipline.sh`, `inject-deployment-strategy.sh`

PreToolUse Skill hooks (settings.json:275-296): `auto-approve-local-skills.sh`, `inject-integration-debug-docs.sh`

The output-verifier is invoked by main as an explicit Task call after each exception-tier write. The verifier-role section of `~/.claude/docs/SUBAGENT-CONTRACT.md` (lines 115-141) describes a separate read-only agent that runs after every exception-tier write and returns a verification status — but it does not wire that "runs after" to any hook event.

The "runs after" is driven by main, not by a hook. Main decides when to spawn the verifier.

**Source:** `~/.claude/settings.json:63-296` (hooks section, searched for `output-verifier`, not present), `~/.claude/docs/SUBAGENT-CONTRACT.md:115-141`

**Significance:** Policy-verifier follows the same main-driven invocation pattern. No hook wiring needed at launch. The invocation sequence for each HIGH-priority agent becomes:
1. Exception-tier agent writes its file (e.g. plan-researcher writes PLAN-SPIKE.md)
2. Main spawns output-verifier (structural check)
3. Main spawns policy-verifier (policy content check)
4. Main presents both reports to the engineer

The policy-verifier is a second Task call after the output-verifier, not a replacement or extension of it.

URL fetched: N/A / settings.json search for "output-verifier" confirmed absent / Quote from SUBAGENT-CONTRACT.md:115-141 confirmed

---

### Finding 6: Findings-to-action contract — mirror output-verifier exactly

**Evidence:**

From `~/.claude/agents/output-verifier.md:125-136`:

```
- ACCEPT — all applicable checks passed. Confidence c > 0.85.
- ACCEPT_WITH_WARNINGS — all applicable checks passed but some had minor concerns.
  Confidence 0.70 ≤ c ≤ 0.85.
- PARTIAL — checks passed for some sections but failed for others; the target file
  can be revised section-by-section rather than redone from scratch.
  Confidence 0.50 ≤ c < 0.70.
- REJECT — one or more applicable checks failed in a way that requires the author
  agent to redo work. Confidence c < 0.50.
```

From `~/.claude/agents/output-verifier.md:13`:
"False negatives (accepting bad work) are more dangerous than false positives (rejecting good work). When in doubt, return REJECT or PARTIAL, never ACCEPT_WITH_WARNINGS."

From `~/.claude/agents/output-verifier.md:175`:
"You do not decide. The per-check sections above carry every factual observation main needs; do not add a closing recommendation, 'next steps' paragraph, or summary verdict."

Policy-verifier applies the same contract:
- Read-only tools (Read, Grep, Glob, WebFetch)
- Returns structured report with per-check breakdown + confidence score + status enum
- False-negative weighting (default toward REJECT over ACCEPT_WITH_WARNINGS when uncertain)
- Main decides — policy-verifier never makes a workflow decision

The policy-verifier replaces "6 structural checks" with "N policy checks" (one per governing doc section that applies to the target document), but the report shape, status enum, and false-negative weighting are identical to output-verifier.

**Source:** `~/.claude/agents/output-verifier.md:13`, `~/.claude/agents/output-verifier.md:125-136`, `~/.claude/agents/output-verifier.md:175`

**Significance:** No new contract design needed. The output-verifier's contract is proven and understood by main. Reusing it exactly means main can apply the same handling logic for both verifiers. The only design work is mapping the 6 structural checks to N policy checks.

URL fetched: N/A / Verbatim quotes at output-verifier.md:13, :125-136, :175 confirmed / Quote substrings confirmed

---

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|----------|------|------|--------|
| Inject ALL governing docs at spawn (Option A for Q4) | Simple hook logic; guaranteed coverage; no routing needed in hook | ~30KB+ context per invocation; most docs irrelevant for any given document type | inject-integration-debug-docs.sh pattern |
| Inject only relevant docs via routing (Option B for Q4) | Smaller context injection; only loads what's needed | Complex hook logic: hook must read and scan the target document at fire time; routing errors = silent gaps | policy_verifier_routing_table_2.md |
| Policy-verifier reads docs itself (Option C for Q4) | No hook needed; minimal complexity | Subject to Read-paging truncation; Full-Read Discipline is a nudge not a guarantee; known failure mode | ADR-001-rules-loading-mechanism.md:24-45 |
| Policy-verify HIGH agents only | Clear scope; covers the phases where code examples are most consequential | MEDIUM agents (context-mapper, domain-modeler) may slip through with policy violations | policy_verifier_trigger_set_3.md |
| Policy-verify all 9 agents | Complete coverage | knowledge-cruncher and process-modeler rarely emit code; adds two low-value verification calls per workflow cycle | policy_verifier_trigger_set_3.md |
| Script-generating skills: Option A (PostToolUse hook) | Automatic; no main effort | Hook fires after code already emitted; correction is a follow-up; payload may not contain response body | policy_verifier_trigger_set_3.md |
| Script-generating skills: Option B (inline checklist) | Simple; no new hook | Relies on skill's own honesty — the exact failure mode verifiers exist to prevent | policy_verifier_trigger_set_3.md |
| Script-generating skills: Option C (main-driven Task) | Mirrors output-verifier pattern; structurally cleanest | Round-trip cost per skill call; text not a file path (different input shape) | policy_verifier_trigger_set_3.md |
| Mechanically verifiable rules only | High precision; low false-positive rate | 4 subjective rules (code patterns, index awareness, deploy strategy) are never checked | policy_verifier_rule_inventory_1.md |
| All rules including subjective | Complete policy coverage | False-positive rate higher for subjective rules; more noisy verifier output | policy_verifier_rule_inventory_1.md |

---

## What remains uncertain

- **PostToolUse hook payload shape for Skill tool**: it is unclear whether the PostToolUse hook for the Skill tool receives the full response body of the skill's output or only metadata (skill name, exit status). If the payload does not include the response body, Option A for script-generating skills cannot be implemented as a hook — only Option C (main-driven) would work. Needs a test invocation or Anthropic documentation check.

- **Task tool input size limit**: if the policy-verifier receives code text (not a file path) for script-generating skill verification, the text may exceed the Task tool's input string size. The limit is not documented in settings.json or in any accessed doc. Relevant only if Option C is chosen for script-generating skills.

- **Whether inject-code-pattern-on-write.sh should be extended to cover .md writes**: currently it explicitly skips non-code files (lines 50-63 of inject-code-pattern-on-write.sh) — SPIKE.md and PLAN.md writes do not trigger code pattern priming. If the policy-verifier is run after the write instead of before, this is fine. But if the verifier is to be a pre-write gate (at write time), the code-pattern-on-write hook's file-extension filter is a precedent to consider.

- **Governing doc completeness**: the 11 policy docs inventoried represent what was read during this spike. Other docs in `~/.claude/docs/` that were NOT read (e.g. DATA-ACCESS.md, NO-SAFE-NAVIGATION.md, NO-UNLESS-CONVENTION.md) may also have mechanically verifiable rules relevant to planning documents. The inventory in `policy_verifier_rule_inventory_1.md` should be treated as a starting set, not a complete catalog.

- **"Vazamento B" gap remains open**: code that diverges from a policy-compliant plan at /execute time is not addressed by the policy-verifier or by the existing mechanical hooks. This is a documented known gap, not in scope for this spike.

---

## Suggested options for main and the engineer

**Option A — Implement policy-verifier for HIGH-priority agents only, with Option A injection (all docs at spawn):**
Start with the 5 HIGH agents (plan-researcher, plan-composer, task-researcher, task-composer, spike). Use Pattern B full-doc injection: a PreToolUse Task hook injects all 11 policy docs in full as additionalContext whenever a policy-verifier Task is spawned. Mirror output-verifier's status enum and contract exactly. Defer script-generating skills and MEDIUM agents to a follow-up.

**Option B — Implement policy-verifier for HIGH-priority agents only, with Option B injection (routing-targeted):**
Same 5 agents, but use targeted injection: the PreToolUse Task hook reads the target document, applies the routing table to identify which governing docs are needed, and injects only those. Smaller context cost. More complex hook. Defer script-generating skills and MEDIUM agents to a follow-up.

**Option C — Implement policy-verifier for all 9 agents + script-generating skills (Option C, main-driven):**
Full coverage from launch. Policy-verify all 9 exception-tier writes AND run a main-driven policy-verifier Task after each script-generating skill invocation (passing the response text as input). Highest coverage. Highest round-trip cost. Most complex agent briefing (must handle file-path inputs AND text-block inputs).

(No recommendation — the evidence shows trade-offs; main and the engineer choose.)
