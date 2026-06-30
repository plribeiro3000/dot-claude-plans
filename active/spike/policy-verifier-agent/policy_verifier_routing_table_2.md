# policy-verifier Routing Table — Document Section to Governing Policy Doc

## Purpose

Maps the content sections of each planning document type to the specific policy doc
that governs that section. A routing table tells the policy-verifier: "when checking
document X and you find a code example in section S, load and apply governing doc D."

This table is the mechanism for targeted doc injection — the analog of the keyword→doc
mapping already implemented in inject-deployment-strategy.sh and inject-query-discipline.sh,
but at document-section granularity rather than prompt-keyword granularity.

---

## Routing Table

| Document Type | Section / Content Signal | Governing Policy Doc(s) |
|---|---|---|
| PLAN.md / PLAN-SPIKE.md | Worker class code examples | `DATA-PROCESSING.md` |
| PLAN.md / PLAN-SPIKE.md | Migration code examples (`add_column`, `create_table`, `add_index`) | `RAILS-MIGRATIONS.md` |
| PLAN.md / PLAN-SPIKE.md | Controller or GraphQL mutation code examples | `BANG-METHOD-WEB-FLOW.md` |
| PLAN.md / PLAN-SPIKE.md | ActiveRecord query code examples (`where`, `pluck`, `update_all`, `group`) | `ACTIVE-RECORD-QUERY-DISCIPLINE.md` |
| PLAN.md / PLAN-SPIKE.md | Terraform command examples | `TERRAFORM-POLICY.md` |
| PLAN.md / PLAN-SPIKE.md | Deploy/rollout section or deploy strategy decision | `DEPLOYMENT-STRATEGY.md` |
| PLAN.md / PLAN-SPIKE.md | Model code examples with `belongs_to` | `OPTIONAL-BELONGS-TO.md` |
| PLAN.md / PLAN-SPIKE.md | Model/service code examples with `destroy_all` or `delete_all` | `BULK-DELETE.md` |
| PLAN.md / PLAN-SPIKE.md | Validation code examples | `NO-MULTIPLE-RAISE.md` |
| PLAN.md / PLAN-SPIKE.md | Any code example that calls `.to_h` or `.to_a` on an object | `USE-THE-OBJECT.md` |
| PLAN.md / PLAN-SPIKE.md | Technical Decisions or Pattern sections | `CODE-PATTERN-DISCIPLINE.md` |
| TASKS.md / TASKS-SPIKE.md | Same signals as PLAN.md (tasks inherit from validated plan) | Same governing docs as PLAN rows |
| SPIKE.md | Finding sections containing code excerpts | All applicable governing docs per code type |
| CONTEXT-MAP.md | Integration pattern choices between bounded contexts | `DATA-PROCESSING.md`, `DEPLOYMENT-STRATEGY.md` |
| DOMAIN.md | Model code examples with `belongs_to`, `has_many`, validations | `OPTIONAL-BELONGS-TO.md`, `BANG-METHOD-WEB-FLOW.md` |

---

## Signal-to-Doc Keyword Map

This secondary table shows the specific signal keywords that route to each governing doc.
The policy-verifier uses these keywords to decide which governing doc(s) to load for a given
document section.

| Governing Doc | Routing Signal Keywords |
|---|---|
| `DATA-PROCESSING.md` | `class`, `Worker`, `job`, `Sidekiq`, `perform`, `queue`, `enqueue`, `Producer`, `Consumer`, `Processor` |
| `RAILS-MIGRATIONS.md` | `add_column`, `remove_column`, `create_table`, `drop_table`, `add_index`, `remove_index`, `change_column`, `Migration` |
| `BANG-METHOD-WEB-FLOW.md` | `controller`, `GraphQL`, `mutation`, `resolve`, `def create`, `def update`, `def destroy` |
| `ACTIVE-RECORD-QUERY-DISCIPLINE.md` | `where`, `pluck`, `update_all`, `delete_all`, `group_by`, `find_by_sql`, `connection.execute`, `joins` |
| `TERRAFORM-POLICY.md` | `terraform`, `.tf`, `var.`, `resource "`, `module "`, `apply`, `plan`, `init` |
| `DEPLOYMENT-STRATEGY.md` | `deploy`, `rollout`, `zero-downtime`, `blue/green`, `sidekiq`, `maintenance window`, `phased`, `single deploy`, `expand/contract` |
| `OPTIONAL-BELONGS-TO.md` | `belongs_to` |
| `BULK-DELETE.md` | `destroy_all`, `delete_all` |
| `NO-MULTIPLE-RAISE.md` | `raise ArgumentError`, `raise`, `errors.add` |
| `USE-THE-OBJECT.md` | `.to_h`, `.to_a`, `.new(` |
| `CODE-PATTERN-DISCIPLINE.md` | `class`, any structural description in Pattern / Technical Decisions sections |

---

## How the Routing Mechanism Reuses the Existing Hook Pattern

The keyword-injection hooks already map signals to doc injections. The existing design:

```
inject-deployment-strategy.sh (line 94):
  keyword_pattern='(\bdeploy\b|\bdeployment\b|\bdeploys\b|\brollout\b|zero[ -]?downtime|...)'
  → injects compact DEPLOYMENT-STRATEGY.md reference
```

The routing table above is the same idea applied to document-section content instead of
prompt text. The policy-verifier agent reads the document being checked, applies these
routing signals to identify which governing docs are needed, then loads those docs in full
(Pattern B — `inject-integration-debug-docs.sh` model, lines 52-78) before evaluating
each code section.

**Key difference from the prompt-keyword pattern:**
- Prompt-keyword hooks fire on the engineer's input text (single string match)
- Policy-verifier routing fires on the content of the planning document being verified
  (section-by-section analysis, not a single string)

---

## Option A vs Option B for Governing Doc Injection

Two delivery options exist for how the governing docs reach the policy-verifier:

**Option A — Inject ALL governing docs at spawn:**
Pre-load all 11 policy docs as additionalContext when any policy-verifier Task is spawned.
Simple. Large (~30KB+ of combined doc content). The verifier never needs to Read any doc.
Mirrors inject-integration-debug-docs.sh but with a larger doc set.

**Option B — Hook parses agent prompt, injects only the relevant subset:**
A PreToolUse Task hook reads the policy-verifier's input, extracts the document path being
verified, scans the document for routing signals, and injects only the docs required for that
document type. Complex hook logic. Smaller context injection per call.

The routing table above is the input to Option B's signal-matching step.

---

## Verification blocks

Source for inject-deployment-strategy.sh line 94 (routing keyword pattern):

File: `/Users/plribeiro3000/.claude/scripts/inject-deployment-strategy.sh`
Line 94: `keyword_pattern='(\bdeploy\b|\bdeployment\b|\bdeploys\b|\brollout\b|zero[ -]?downtime|blue[ /-]?green|\brolling\b|\bcanary\b|\bmigration\b|\bmigrations\b|\bmigrate\b|\bmigrar\b|\brename\b|expand[ /-]?contract|\bbackfill\b|feature[ -]?flag|feature[ -]?toggle|permission[ -]?flag|\bfasear\b|\bfaseado\b|\bphased\b|\bsidekiq\b|\bTSTP\b|\bquiet\b|maintenance window|\bjanela\b)'`
URL fetched: N/A (local file) / Verbatim quote checked: confirmed above / Quote substring confirmed at line 94 of inject-deployment-strategy.sh

Source for inject-integration-debug-docs.sh Pattern B (lines 52-78):

File: `/Users/plribeiro3000/.claude/scripts/inject-integration-debug-docs.sh`
Lines 52-78: `docs=(... API_DOMAIN.md ... API_PATTERNS.md ... INTEGRATOR_DOMAIN.md ... SCRIPT-DISCIPLINE.md ...)` + loop reading each doc via `cat` + `context="=== INTEGRATION-DEBUG MANDATORY DOCS (injected in full) === ... Treat the content below as the authoritative full text"`
URL fetched: N/A (local file) / Verbatim quote checked: confirmed above / Quote substring confirmed at lines 52-78 of inject-integration-debug-docs.sh
