# SPIKE — Vazamento B: Code-Write Enforcement

## Investigation question

How should 4Shark close "vazamento B" — code written at `/execute` time (or any code Edit/Write) that violates a 4Shark convention even when the plan was conforming? The `policy-verifier` (just shipped) gates the DOCUMENT level; this spike scopes enforcement at the CODE-WRITE level.

The specific questions to answer:

1. What write-time enforcement already exists, and exactly what does each hook enforce?
2. Which of the 16 mechanically verifiable + 4 subjective rules from the policy-verifier inventory have no write-time guard?
3. For each uncovered rule: is it deterministically detectable by a bash hook?
4. For each bash-detectable rule: should a new hook BLOCK (PreToolUse) or FLAG (PostToolUse)?
5. What meta-architecture options exist for closing the gap?

## Sources consulted

- `/Users/plribeiro3000/.claude/scripts/validate-bang-method-web-flow.sh` — canonical code-content-scanning hook; establishes the pattern for content-based enforcement
- `/Users/plribeiro3000/.claude/scripts/validate-rails-migration-creation.sh` — PreToolUse BLOCK for hand-creating migration files
- `/Users/plribeiro3000/.claude/scripts/validate-bash-command.sh` — PreToolUse for Bash/Edit/Write/MultiEdit; enforces destructive-command patterns; Edit/Write path only auto-allows plans/ files, does not scan code content
- `/Users/plribeiro3000/.claude/scripts/check-abbreviated-variables.sh` — PostToolUse FLAG for single-letter variable names
- `/Users/plribeiro3000/.claude/scripts/inject-code-pattern-on-write.sh` — PreToolUse INJECT (always allow) for code extensions; injects Pattern Priming as additionalContext
- `/Users/plribeiro3000/.claude/settings.json` — complete hook wiring; source of truth for event + matcher for every hook
- `/Users/plribeiro3000/.claude/plans/active/spike/policy-verifier-agent/SPIKE.md` — establishes the 16+4 rule inventory and the "vazamento B" out-of-scope statement
- See auxiliary: `vazamento_b_coverage_gap_matrix_1.md` — rule-by-rule mapping to existing guards
- See auxiliary: `vazamento_b_detectability_block_flag_2.md` — per-rule detectability and block/flag classification
- `/Users/plribeiro3000/.claude/docs/BULK-DELETE.md` — exception cases: destroy_all ≤15 records; delete_all no callbacks/dependents
- `/Users/plribeiro3000/.claude/docs/OPTIONAL-BELONGS-TO.md` — no exceptions; rule is absolute
- `/Users/plribeiro3000/.claude/docs/ACTIVE-RECORD-QUERY-DISCIPLINE.md` — exception: explicit engineer authorization for raw SQL; customer DB exception

---

## Findings

### Finding 1: Five hooks fire on Edit/Write/MultiEdit — two block on code content, one injects context, one flags after write, one only path-gates

**Evidence:**

From `settings.json` hook wiring (confirmed by reading each script):

| Hook | Event | Matcher | Action on code content |
|---|---|---|---|
| `validate-bang-method-web-flow.sh` | PreToolUse | `Edit\|Write\|MultiEdit` | BLOCK: exits 2 on bang method in controllers/mutations |
| `validate-rails-migration-creation.sh` | PreToolUse | `Write` | BLOCK: exits 2 on hand-creating a new `db/migrate/*.rb` file |
| `inject-code-pattern-on-write.sh` | PreToolUse | `Edit\|Write\|MultiEdit` | INJECT: exits 0 with additionalContext (Pattern Priming); never blocks |
| `check-abbreviated-variables.sh` | PostToolUse | `Edit\|Write\|MultiEdit` | FLAG: exits 2 on single-letter variables AFTER the write completes |
| `validate-bash-command.sh` | PreToolUse | `Bash\|Edit\|Write\|MultiEdit` | PATH-GATE: for Edit/Write/MultiEdit, only auto-allows `~/.claude/plans/` path; does not scan code content |

**Source:** `/Users/plribeiro3000/.claude/scripts/validate-bash-command.sh:29-30` — `tool_name="$(printf '%s' "$hook_input" | jq -r '.tool_name // empty')"` — the script branches on tool_name; for Edit/Write the only action is path-based auto-allow, confirming it does not scan code content for convention violations.

**Source:** `/Users/plribeiro3000/.claude/scripts/inject-code-pattern-on-write.sh:124-131` — `permissionDecision: "allow", additionalContext: $ctx` — always exits 0; injects context but never prevents the write.

**Significance:** The existing write-time enforcement layer is narrow. It covers bang methods (one rule) and migration file creation (one rule). The Pattern Priming injection is preventive (attempts to stop violations before generation) but not detective (cannot catch violations in code Claude produces despite the priming). Single-letter variables are the only PostToolUse detection. Twelve of the 21 rules have no write-time guard at all.

Verification: `/Users/plribeiro3000/.claude/scripts/validate-bang-method-web-flow.sh` read in full (92 lines). `/Users/plribeiro3000/.claude/scripts/validate-rails-migration-creation.sh` read in full (62 lines). `/Users/plribeiro3000/.claude/scripts/check-abbreviated-variables.sh` read in full (64 lines). `/Users/plribeiro3000/.claude/scripts/inject-code-pattern-on-write.sh` read in full (141 lines).

---

### Finding 2: 12 of 21 rules have no write-time guard; 3 more have prompt-level injection but no code-write detection

**Evidence:** See auxiliary `vazamento_b_coverage_gap_matrix_1.md` for the full matrix.

Summary of coverage status:

- **COVERED (4):** migration creation blocked, bang methods blocked, single-letter variables flagged, terraform destructive commands blocked at Bash execution
- **PARTIAL — prompt injection only (3):** AR raw SQL keywords, pluck→Ruby reshaping, code pattern anti-patterns — each has a UserPromptSubmit/SubagentStart injection hook that injects the governing rule before Claude acts, but no hook that detects violations in code Claude actually wrote
- **GAP (12):** topology naming, IDs-only (MIXED), one-action migration, statement_timeout, disable_ddl_transaction!, if_not_exists/if_exists, safety_assured, optional: true on belongs_to, avoid destroy_all/delete_all, no multiple raise ArgumentError, no .new().to_h, index awareness (SUBJECTIVE)

**Source:** `/Users/plribeiro3000/.claude/plans/active/spike/policy-verifier-agent/policy_verifier_rule_inventory_1.md:20-43` — the 16+4 rule inventory used as the starting catalog for this gap analysis.

**Significance:** The gap is not evenly distributed. The three PARTIAL rules already have behavioral prevention in place (Claude is reminded at prompt time); the gap is that a violation reaching code still goes undetected. The 12 full-GAP rules have no prevention or detection at the code-write level.

Verification: auxiliary file `vazamento_b_coverage_gap_matrix_1.md` created from direct analysis of each hook script and the settings.json wiring. Every hook script read in full.

---

### Finding 3: 12 of the 12 uncovered rules are bash-detectable to some degree — but the degree varies and constrains block vs flag

**Evidence:** See auxiliary `vazamento_b_detectability_block_flag_2.md` for the full per-rule table.

Detectability classification:

- **HIGH bash detectability (new BLOCK possible):** 2 rules
  - Topology naming: `class .*(Executor|Runner|Handler|Manager)` in worker files — absolute rule, no exceptions
  - disable_ddl_transaction! for concurrent indexes: `algorithm: :concurrently` without `disable_ddl_transaction!` — physically invalid at DB level; no false-positive path

- **HIGH bash detectability (FLAG appropriate):** 6 rules
  - AR raw SQL keywords (`update_all`, `delete_all`, `connection.execute`, `find_by_sql`) — explicit engineer authorization is a documented exception; block would fire on legitimate authorized use
  - destroy_all/delete_all — ≤15 records exception and no-callbacks exception are documented in BULK-DELETE.md
  - safety_assured presence — it is a legitimate escape hatch; block would prevent its correct use
  - statement_timeout absence — minor DDL may legitimately skip it
  - pluck→group_by chain — SQL-inexpressible transformations are a documented exception

- **MEDIUM bash detectability (FLAG with approximation):** 4 rules
  - One action per migration — multiline counting of schema ops is imprecise
  - if_not_exists/if_exists — presence check is feasible; enforcement strength is debatable
  - optional: true on belongs_to — multiline proximity heuristic; false positives on genuinely optional associations
  - multiple raise ArgumentError — file-level count approximates method-level scope
  - .new().to_h — proximity heuristic; serialization boundary exception is documented in USE-THE-OBJECT.md

- **NOT bash-detectable (LLM-only):** 3 rules
  - IDs-only (MIXED) — structural; cannot distinguish id vs object passing from text alone
  - Index awareness — requires understanding table structure; cannot be keyword-reduced
  - Code pattern anti-patterns (6 shapes) — structural shape analysis

**Source:** `/Users/plribeiro3000/.claude/docs/BULK-DELETE.md:40-48` — `"destroy_all is acceptable ONLY when: The collection has 15 or fewer records"` and `"delete_all is acceptable ONLY when: The model has no before_destroy/after_destroy callbacks"` — two documented exceptions that prevent a BLOCK on these keywords.

**Source:** `/Users/plribeiro3000/.claude/docs/ACTIVE-RECORD-QUERY-DISCIPLINE.md:41` — `"Raw SQL is acceptable only when the engineer explicitly authorizes it for a specific operation"` — documented exception to AR-first that prevents a BLOCK on raw SQL keywords.

**Significance:** Exception cases are the primary constraint on block vs flag. When a rule has no documented exceptions and the detection heuristic is reliable, a PreToolUse BLOCK is safe. When exceptions exist (even documented ones), a PostToolUse FLAG forces Claude to re-examine the code without preventing legitimate uses. The distinction between block and flag is not about confidence in the detection — it is about whether the rule admits exceptions.

Verification: BULK-DELETE.md read in full (84 lines). OPTIONAL-BELONGS-TO.md read in full (65 lines). ACTIVE-RECORD-QUERY-DISCIPLINE.md first 80 lines read; exception at line 41 confirmed.

---

### Finding 4: The inject-code-pattern-on-write.sh hook establishes a prevention layer but not a detection layer — and violations occur despite it

**Evidence:**

From `/Users/plribeiro3000/.claude/scripts/inject-code-pattern-on-write.sh:74-122`:

```
=== CODE PATTERN DISCIPLINE — PER-WRITE CHECK (injected) ===
...
BEFORE proceeding with this write, the Pattern Priming applies:
1. If you have NOT already done it for this file in this session:
   - List the sibling files ...
   - Read 2-3 of them
   - Identify the established pattern
   - Present findings to the engineer via AskUserQuestion
   - Wait for confirmation
...
Anti-patterns to specifically avoid: Iceberg Class, Parameter-Passing Pipeline ...
```

The hook: exits 0 with `permissionDecision: "allow"` and the priming as `additionalContext`. The write is never blocked — the injection is a context signal, not a gate.

**Source:** `/Users/plribeiro3000/.claude/scripts/inject-code-pattern-on-write.sh:125` — `permissionDecision: "allow"` — unconditional allow.

**Source:** `/Users/plribeiro3000/.claude/plans/active/spike/policy-verifier-agent/SPIKE.md:13` (policy-verifier spike) — `"Vazamento B" (code diverges from a good plan at /execute time) is explicitly OUT OF SCOPE` — the policy-verifier spike acknowledges this gap exists and defers it to this spike.

**Significance:** The prevention model (inject priming before write) relies on the model reading the injected context and applying it before generating code. The model may produce code despite the priming if the pattern is subtle, the context window is congested, or the structural judgment required is beyond keyword-matching. This gap is architectural — context injection cannot substitute for a detection-and-correction loop.

Verification: inject-code-pattern-on-write.sh read in full (141 lines). Policy-verifier SPIKE.md line 13 confirmed from prior read.

---

### Finding 5: The canonical hook pattern (from validate-bang-method-web-flow.sh) is reusable for all new deterministic guards

**Evidence:**

From `/Users/plribeiro3000/.claude/scripts/validate-bang-method-web-flow.sh`:

```bash
# Line 28: tool_name from hook JSON
tool_name="$(printf '%s' "$hook_input" | jq -r '.tool_name // empty')"
# Line 30: skip non-write tools
[ "$tool_name" = "Edit" ] || [ "$tool_name" = "Write" ] || [ "$tool_name" = "MultiEdit" ] || exit 0
# Lines 36-56: extract new content per tool_name
#   Write: .tool_input.content
#   Edit:  .tool_input.new_string
#   MultiEdit: .tool_input.edits[].new_string
# Lines 58-75: scope gate by file path pattern
# Lines 78-88: regex match on new content
# Line 91: exit 2 with stderr on violation
```

This pattern handles all three write-tool variants (Write, Edit, MultiEdit), extracts new content from each, applies a scope gate, and then regex-matches the content. It is self-contained (no external deps beyond `jq` and `grep`) and exits deterministically.

**Source:** `/Users/plribeiro3000/.claude/scripts/validate-bang-method-web-flow.sh:18-91` — full implementation of the pattern.

**Significance:** Every new deterministic hook can follow this pattern verbatim, changing only the scope gate (file path regex) and the detection regex. The infrastructure is already in place; adding a new rule requires one new script and one settings.json entry. No architectural change is needed for Option A (deterministic hooks only) or the deterministic tier of Option C.

Verification: validate-bang-method-web-flow.sh read in full (92 lines). Pattern confirmed as described.

---

### Finding 6: Three meta-architecture options exist, each with distinct coverage ceiling and cost profile

**Evidence:**

All three options are surfaced from the prior findings. No external source is consulted for the option framing — the options are derived from the mechanical constraints found in Findings 1–5.

**Option A: Deterministic bash hooks only**

Add new hooks for the 12 bash-detectable uncovered rules. The two absolute rules (topology naming, disable_ddl_transaction!) get PreToolUse BLOCKs; the remaining 10 get PostToolUse FLAGs. No LLM involvement in code-write enforcement.

*Coverage ceiling:* 16 of 21 rules covered (the 3 LLM-only rules — IDs-only, index awareness, code anti-patterns — remain uncovered; the 2 already covered by inject-* hooks remain prevention-only).

*Cost:* Zero token cost per write. Near-zero latency. Each new hook is a PR to dot-claude.

*Implementation surface:* 10 new scripts + 10 settings.json entries (following the bang-method hook pattern).

*Failure mode:* A hook fires on a legitimate exception (e.g., destroy_all for ≤15 records). Claude sees the FLAG and must evaluate whether it is a real violation or a justified exception — this requires contextual judgment it may or may not apply correctly.

**Option B: LLM post-write conformance pass**

An LLM agent evaluates the accumulated diff against the full rule catalog. Trigger options:

- *Per-write PostToolUse:* fires after every Edit/Write/MultiEdit → highest coverage cadence; highest token cost (~200–500 tokens per evaluation × N writes per session)
- *Checkpoint (/test or pre-commit):* fires once per feature after the diff is accumulated → moderate cost; one-time; may miss intra-session violations that get masked by later edits
- *Main-driven on demand:* engineer or main session explicitly invokes → zero automation; selective; no interruptions on green code

*Coverage ceiling:* All 21 rules, including the 3 subjective ones (IDs-only structural check, index awareness, code anti-patterns). The LLM can apply contextual reasoning that bash cannot — it can distinguish a destroy_all for 5 records from one for 10,000 without a count.

*Cost:* Token cost per pass (scales with diff size and rule count). Latency at checkpoint. If per-write: session cost multiplies with write count.

*Failure mode:* LLM false positives on legitimate exception cases (same risk as Option A FLAGs, but now the LLM surfaces the "violation" as a finding). LLM false negatives (misses a subtle structural anti-pattern). Neither failure mode is blocked by the same mechanism that catches it.

**Option C: Tiered (A + B)**

Tier 1: Deterministic hooks cover all 12 bash-detectable rules (2 BLOCKs + 10 FLAGs). Cheap, always fires, zero token cost.

Tier 2: LLM conformance pass at a defined checkpoint (e.g., at /test time) covers the 3 subjective rules + provides contextual resolution for the 10 FLAGged rules that have exception cases.

*Coverage ceiling:* All 21 rules. Tier 1 provides immediate feedback per write; Tier 2 provides comprehensive review once per feature before the PR.

*Cost:* Tier 1 cost is the same as Option A. Tier 2 cost is one LLM pass per test run (not per write). The total per-feature cost is lower than Option B per-write, comparable to Option B checkpoint.

*Failure mode:* Two failure mechanisms to maintain (bash hooks + LLM pass). A rule caught by Tier 1 may also appear in Tier 2's report — requiring deduplication logic or clear scope separation. Tier 2 implementation requires defining the LLM pass prompt, the diff format, and the governing doc injection strategy.

---

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Option A: Deterministic hooks only | Zero token cost; always fires; no LLM involvement; each hook is independently auditable; follows established pattern | Cannot cover IDs-only, index awareness, or structural anti-patterns (3 rules); FLAGs require Claude's contextual judgment to distinguish violations from exceptions | Findings 1, 3, 5 |
| Option B: LLM pass (per-write) | Full coverage including subjective rules; contextual exception resolution | High token cost per write; latency on every write; adds a second LLM call to every code edit | Finding 6 |
| Option B: LLM pass (checkpoint) | Full coverage; lower cost than per-write; natural gate at /test | One-time check; violations from early writes may be masked by later edits; no immediate feedback | Finding 6 |
| Option B: LLM pass (main-driven) | Zero automation overhead; selective application | No automatic coverage; depends on engineer or main remembering to invoke | Finding 6 |
| Option C: Tiered A+B | Best coverage; low per-write cost (Tier 1 is free); Tier 2 catches what Tier 1 misses | Most complex to maintain; two failure modes to diagnose; deduplication needed between tiers | Findings 1–6 |
| Block (PreToolUse exit 2) for any rule | Hard stop before violation is written | False positive = engineer cannot proceed without workaround; only safe when rule has no documented exceptions and detection is reliable | Findings 3, 5 |
| Flag (PostToolUse exit 2) for any rule | Write proceeds; Claude is forced to re-examine; graceful handling of exception cases | Write is already on disk; Claude may not correct the violation or may dismiss the flag incorrectly | Findings 3, 5 |

---

## What remains uncertain

- **Whether inject-code-pattern-on-write.sh actually reduces violations in practice.** The spike cannot measure this without session-level data. If the prevention injection is already effective, the gap in the 3 PARTIAL rules may be smaller than it appears from the architecture alone.

- **Token cost of Option B/C Tier 2 at checkpoint.** The cost scales with diff size and the number of governing docs injected. A feature with 20 modified files and 16 governing docs could require a very large context. The policy-verifier's injection model (Option A: inject all docs at spawn vs Option B: targeted injection) from the routing-table spike directly applies here.

- **Whether bash FLAGs are actually handled correctly by Claude after the write.** PostToolUse exit 2 forces Claude to see the violation, but does not guarantee it acts on it. A session under context pressure may dismiss the FLAG without revision.

- **The LLM pass trigger point for Option C Tier 2.** The /test checkpoint is natural but is controlled by the engineer (they invoke /test). A pre-commit hook is automatic but requires git hooks in every repo. Neither is perfectly automatic.

- **Whether the IDs-only rule can be approximated.** The auxiliary detectability table marks it LOW bash detectability. A narrow heuristic — detecting Sidekiq `perform_async` calls with non-integer arguments, or checking for `.where(id: some_variable).each` vs `.all.each` in worker files — might reduce false negatives without requiring full structural analysis. This was not investigated.

---

## Suggested options for main and the engineer

The findings surface three primary options and several sub-decisions. No recommendation is made — main and the engineer decide.

**Option A: Deterministic hooks only**
Implement 12 new bash hooks (2 BLOCKs + 10 FLAGs) following the `validate-bang-method-web-flow.sh` pattern. Accept that IDs-only, index awareness, and code structural anti-patterns remain uncovered. Estimated: 12 PRs to dot-claude, each small (one script + one settings.json entry).

**Option B: LLM conformance pass**
Implement a code-write conformance agent (analogous to the policy-verifier but operating on the produced code diff). Choose one trigger point: per-write PostToolUse (highest coverage, highest cost), checkpoint at /test (balanced), or main-driven on demand (minimal automation). Covers all 21 rules but requires the governing doc injection strategy from the policy-verifier routing table to be adapted for code content.

**Option C: Tiered (A + B at checkpoint)**
Implement Option A's deterministic hooks for immediate per-write feedback, and Option B's LLM conformance pass at /test time for the 3 subjective rules + contextual exception resolution for the 10 FLAGged rules. Best coverage profile; requires both efforts.

**Sub-decision: block vs flag for existing PARTIAL rules (AR raw SQL, pluck→group_by, code patterns)**
The three PARTIAL rules already have prompt-level injection. A natural next step would be to promote them to code-write detection without changing the injection layer. For AR raw SQL and pluck→group_by: add PostToolUse FLAGs (bash-detectable, exception cases preclude BLOCK). For code patterns: only an LLM pass can detect these.
