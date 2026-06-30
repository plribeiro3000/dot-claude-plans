# policy-verifier Trigger Set Analysis

## Purpose

Defines which agent writes trigger policy verification and at what priority,
plus the separate sub-finding on script-generating skills which emit code as
text (not as .md file writes) and need different gating.

---

## Part 1 — Exception-Tier Agent Trigger Set

The policy-verifier is analogous to the output-verifier. It runs after
exception-tier agents write their designated file. The question is: which
of the 9 exception-tier agent writes have enough policy-relevant code content
to warrant a policy-verification pass?

### Classification

| Agent | Writes | Policy-Relevant Code Content | Priority |
|---|---|---|---|
| `plan-researcher` | `PLAN-SPIKE.md` | YES — Pattern code blocks with file:line citations; Technical Decisions table with code rationale; code examples in findings | HIGH |
| `plan-composer` | `PLAN.md` | YES — Technical decisions table; architecture code examples carried from validated draft; migration/worker patterns | HIGH |
| `task-researcher` | `TASKS-SPIKE.md` | YES — Pattern references with code excerpts; implementation task steps that may reference concrete code patterns | HIGH |
| `task-composer` | `TASKS.md` | YES — Pattern references carried from validated TASKS-SPIKE.md draft; steps naming specific patterns | HIGH |
| `spike` | `SPIKE.md` | YES — Code excerpts inline in Finding sections (Finding Evidence blocks); code from codebase analysis | HIGH |
| `context-mapper` | `CONTEXT-MAP.md` | MEDIUM — Integration pattern choices that imply architectural patterns; may reference worker patterns, data flows | MEDIUM |
| `domain-modeler` | `DOMAIN.md` | MEDIUM — Model code examples (belongs_to, has_many, validates); Gap Analysis sections may reference existing code | MEDIUM |
| `knowledge-cruncher` | `KNOWLEDGE.md` | LOW — Domain concepts and business rules only; rarely contains executable code examples | LOW |
| `process-modeler` | `PROCESS.md` | LOW — Business process flows (BPMN-style); rarely contains executable code | LOW |

### Source Evidence

Agent files read to determine policy relevance:

`~/.claude/agents/plan-researcher.md`: Contains "Pattern N: file:lines code blocks" structure
and a Technical Decisions table — code examples are a first-class artifact of this document.
Code excerpts appear in the findings body and in the Comparison Board.

`~/.claude/agents/plan-composer.md`: Writes PLAN.md from the validated PLAN-SPIKE.md draft.
Carries technical decisions table, migration step code examples, worker class naming into PLAN.md.

`~/.claude/agents/task-researcher.md`: Writes TASKS-SPIKE.md with task options, each
option carrying "Pattern evidence" code blocks sourced from the codebase.

`~/.claude/agents/task-composer.md`: Writes TASKS.md with concrete task steps; pattern
references and code examples are carried from the validated TASKS-SPIKE.md.

`~/.claude/agents/spike.md`: SPIKE.md findings contain inline code excerpts (10-15 lines
per Finding) sourced from codebase Read operations. The Evidence block of each finding is
typically a code block.

`~/.claude/agents/context-mapper.md`: CONTEXT-MAP.md contains system interaction patterns;
less frequently contains executable code but may reference worker topology choices.

`~/.claude/agents/domain-modeler.md`: DOMAIN.md may include model code examples for
`belongs_to`, `has_many`, `validates` — all of which have governing policy rules.

`~/.claude/agents/knowledge-cruncher.md`: KNOWLEDGE.md focuses on domain concepts, glossary,
business rules, constraints. Code examples are rare and not first-class.

`~/.claude/agents/process-modeler.md`: PROCESS.md focuses on process flows, BPMN-style
description. Executable code examples are not a design element of this document.

### Recommended Trigger Set

Run policy-verifier for: plan-researcher, plan-composer, task-researcher, task-composer, spike
Optionally run for: context-mapper, domain-modeler
Skip for: knowledge-cruncher, process-modeler

The HIGH-priority 5 agents collectively cover the phases where code examples are both
most likely to appear and most consequential for implementation quality (they guide /execute).

---

## Part 2 — Script-Generating Skills Sub-Finding

This is a separate gating problem. Three skills emit code (Terraform, Ruby/Rails, shell)
as TEXT in the chat response, not as a .md file write. The file-Write hook does not fire.

### Skills in scope

| Skill | What it emits | Code type |
|---|---|---|
| `integration-debug` | Rails console scripts, rake tasks, ActiveRecord queries | Ruby/AR code, MySQL SQL |
| `create-integrator` | Full Terraform module files, variable definitions, ECS task definition JSON | Terraform HCL, JSON |
| `create-app-webclient` | Angular project scaffolding, Netlify config, Cloudflare DNS Terraform | TypeScript, Terraform HCL |

### Why these are high-value for policy gating

- `integration-debug` emits AR queries that are governed by ACTIVE-RECORD-QUERY-DISCIPLINE.md
  and SCRIPT-DISCIPLINE.md — e.g. `pluck + group_by` or `destroy_all` in a script is a
  direct policy violation, and the script runs on production data
- `create-integrator` emits terraform code governed by TERRAFORM-POLICY.md — e.g. no
  `-auto-approve`, no unguarded `terraform apply` without saved plan
- `create-app-webclient` emits terraform code (same TERRAFORM-POLICY.md) + frontend scaffold

### Gating Options

**Option A — PostToolUse hook on the Skill tool:**
A PostToolUse hook fires after each Skill tool invocation. The hook reads the skill name
and the skill's response text (if the hook payload includes it), applies keyword/regex
matching against the response body, and injects a policy-compliance reminder as
additionalContext for the next turn.

Trade-off: the hook fires AFTER the code is already in the response. It is a correction
prompt, not a pre-generation gate. The code has already been emitted; correction requires
a follow-up message to regenerate or patch. Also: PostToolUse hook payload shapes may
not include the full response body — investigation needed (see "What remains uncertain").

**Option B — Inline policy checks in each skill's SKILL.md:**
Add a policy-compliance checklist to the end of each skill's instruction document. The
skill self-checks before presenting code to the engineer.

Example for integration-debug SKILL.md:
"Before presenting any script, verify:
 - No `pluck` followed by Ruby group_by/sort_by/transform_values (AR-QUERY-DISCIPLINE)
 - No `destroy_all` or `delete_all` (BULK-DELETE.md)
 - No multiple `raise ArgumentError` (NO-MULTIPLE-RAISE.md)"

Trade-off: relies on the skill's own honesty (same failure mode output-verifier exists to
address). No structural guarantee that the policy was actually consulted. Simple to implement.
No new hook required.

**Option C — Main-driven check after each skill invocation:**
After a script-generating skill completes, main explicitly runs a policy-verifier Task
against the output text, passing it as input (not as a file path). The policy-verifier
analyzes the text, returns a structured findings report, and main presents it to the
engineer before the scripts are used.

This mirrors the main-driven output-verifier pattern exactly. The policy-verifier's input
is a code text block instead of a file path. The status enum (ACCEPT/REJECT/etc.) applies
the same way.

Trade-off: adds a round-trip for every skill invocation. Text passed as a string to the
Task is subject to the Task tool's input size limits. Structurally the cleanest — mirrors
the exact pattern output-verifier uses for documents.

### Key Difference From Document Gating

For exception-tier agent writes, the trigger is a file Write and the object is a .md file.
For script-generating skills, the trigger is a Skill tool invocation and the object is
the text content of the skill's response. The structural shape is different even if the
policy rules being applied are the same.

---

## Part 3 — Known Out-of-Scope Gap ("Vazamento B")

Per the locked design decisions in the investigation briefing: code diverging from a
good plan at /execute time is explicitly OUT OF SCOPE. This is "Vazamento B."

The policy-verifier runs at PLAN/SPIKE write time, not at code-write time. If a plan
passes policy-verification but /execute generates code that violates those same policies,
the policy-verifier does not catch it. The existing mechanical hooks (validate-bash-command.sh,
validate-bang-method-web-flow.sh, validate-rails-migration-creation.sh, check-abbreviated-variables.sh)
provide partial coverage at code-write time, but the gap between "policy-compliant plan"
and "policy-compliant execution" remains open.

This gap is noted here as a known limitation, not a problem to solve in this spike.
