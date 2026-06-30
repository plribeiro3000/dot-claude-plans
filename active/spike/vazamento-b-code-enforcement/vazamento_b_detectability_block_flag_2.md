# Vazamento B — Per-Rule Detectability and Block/Flag Classification

## Purpose

For each uncovered rule in the gap matrix, this table records:
1. **Bash detectability** — whether a bash hook can deterministically detect the violation without LLM involvement
2. **Scope gate** — the file path pattern that narrows false-positive exposure
3. **Block vs Flag** — whether a new hook should BLOCK (PreToolUse exit 2) or FLAG (PostToolUse exit 2) and why
4. **Exception cases that constrain the choice** — documented legitimate uses that would produce false positives on a block

**Block criteria:** the rule is absolute (no documented exceptions in the scope) AND the bash detection is reliable (low false-positive rate). A block prevents the write from happening — the cost of a false positive is a frustrated engineer who can't write correct code without workarounds.

**Flag criteria:** legitimate exceptions exist (documented in the governing doc) OR the detection heuristic is imprecise (multiline proximity, count-based). A flag (PostToolUse exit 2) lets the write proceed but forces Claude to acknowledge and re-examine the violation.

---

## Classification Table

| Rule | Bash Detectability | Scope Gate | Block vs Flag | Exception Case | LLM Pass Needed? |
|---|---|---|---|---|---|
| **Topology naming** — Executor/Runner/Handler/Manager banned in worker class names | HIGH — regex `class .*(Executor\|Runner\|Handler\|Manager)` in worker files | `~/Projects/4Shark/*/app/workers/**/*.rb` and sibling patterns | **BLOCK** — rule is absolute; no documented exception; false positives only on non-worker files mitigated by scope gate | None documented | No |
| **IDs-only** — pass IDs not loaded objects between jobs | LOW — structural; cannot distinguish `ids = X.pluck(:id)` vs `objects = X.all` as job args from text alone | — | FLAG only via LLM pass | N/A | **Yes — LLM only** |
| **One action per migration** | MEDIUM — count multiple `create_table`/`add_column`/`remove_column`/`add_index` in same migration class body | `~/Projects/4Shark/*/db/migrate/*.rb` | **FLAG** — counting multiple schema ops per class body is feasible but regex-based counting across multiline is imprecise; legacy migrations may intentionally combine ops | Intentional multi-step legacy migrations | No (bash feasible) |
| **statement_timeout with ENV.fetch** | HIGH — absence of `statement_timeout` pattern in migration file (negative check) | `~/Projects/4Shark/*/db/migrate/*.rb` | **FLAG** — absence detection works but small/trivial migrations may not need a timeout; a block would prevent valid writes | Fast DDL that completes instantly may not need a timeout | No (bash feasible) |
| **`disable_ddl_transaction!` for concurrent indexes** | HIGH — `algorithm: :concurrently` present in file without `disable_ddl_transaction!` | `~/Projects/4Shark/*/db/migrate/*.rb` | **BLOCK** — this combination always fails at the DB level; the constraint is physical, not stylistic; no false-positive path | None — a concurrent index without `disable_ddl_transaction!` is always invalid in Postgres | No |
| **`if_not_exists`/`if_exists` for retry safety** | MEDIUM — `add_column`/`remove_column` without `if_not_exists`/`if_exists` keyword nearby | `~/Projects/4Shark/*/db/migrate/*.rb` | **FLAG** — not every migration targets a re-entrant environment; blocking would prevent valid older-style migrations | Migrations in dev-only or single-run environments | No (bash feasible) |
| **`safety_assured` presence** | HIGH — keyword `safety_assured` in migration file | `~/Projects/4Shark/*/db/migrate/*.rb` | **FLAG** — `safety_assured` is a documented exception path in RAILS-MIGRATIONS.md; its presence warrants human review, not an automatic block | safety_assured is the explicit "I know this is risky" escape hatch | No |
| **AR-first — `update_all`, `delete_all`, `connection.execute`, `find_by_sql`** | HIGH — keyword presence in Ruby files | `~/Projects/4Shark/*/app/**/*.rb`, `~/Projects/4Shark/*/lib/**/*.rb` | **FLAG** — "raw SQL only on explicit engineer authorization" is a documented exception in ACTIVE-RECORD-QUERY-DISCIPLINE.md; blocking would prevent legitimate authorized use | Explicit engineer authorization is the documented exception | No |
| **DB-side shaping — `pluck` followed by `group_by`/`sort_by`/`transform_values`** | HIGH — regex `\.pluck\b` in proximity (same line or within N lines) to `\.group_by\|\.sort_by\|\.transform_values` | `~/Projects/4Shark/*/app/**/*.rb` | **FLAG** — "acceptable only when the transformation cannot be expressed in SQL" is a documented exception | Transformations that cannot be expressed in SQL are a documented exception path | No |
| **Index awareness before non-trivial queries** | NONE — requires understanding table structure and whether a query targets a non-trivial table | — | N/A | — | **Yes — LLM only** |
| **Code pattern anti-patterns (6 shapes)** | NONE — structural shape analysis | — | N/A | — | **Yes — LLM only** |
| **`optional: true` on `belongs_to`** | MEDIUM — `belongs_to :x` without `optional: true` on same line or within 2 lines | `~/Projects/4Shark/*/app/models/**/*.rb` | **FLAG** — multiline regex is imprecise; a `belongs_to` for a truly optional association may legitimately exist; OPTIONAL-BELONGS-TO.md states the rule is for associations that ARE required (they just skip the SELECT overhead) | Genuinely optional associations that need `optional: true` WITHOUT the manual validation (valid but rare) | No |
| **Avoid `destroy_all` and `delete_all`** | HIGH — keyword presence | `~/Projects/4Shark/*/app/**/*.rb` | **FLAG** — BULK-DELETE.md documents two legitimate exception cases: `destroy_all` for ≤15 records with callbacks needed; `delete_all` for models with no callbacks/dependents | ≤15 records with callbacks (destroy_all); no callbacks/dependents (delete_all) | No |
| **No multiple `raise ArgumentError` in same method** | MEDIUM — count 2+ occurrences of `raise ArgumentError` in same file; approximates same-method scope | `~/Projects/4Shark/*/app/**/*.rb` | **FLAG** — counting within same method scope requires parsing, not text search; a file with two separate methods each with one raise would false-positive | One raise per method is fine; the rule bans multiple in the SAME method | No (bash approximation feasible) |
| **No `.new().to_h` collapse** | MEDIUM — `\.to_h` in proximity to `.new(` (same line or within N lines) | `~/Projects/4Shark/*/app/**/*.rb` | **FLAG** — `to_h` at a genuine serialization boundary is a documented exception in USE-THE-OBJECT.md ("legitimate ONLY at a genuine serialization boundary") | Serialization boundary (.to_h at the edge of the object before HTTP response, DB column, external API) | No |
| **No single-letter variables** | HIGH — already implemented | `~/Projects/4Shark/**` + `/tmp/` | **FLAG** (PostToolUse) — already implemented in check-abbreviated-variables.sh | None documented | No |

---

## Feasibility Summary

| Category | Count | Action |
|---|---|---|
| Bash-feasible BLOCK (new hooks needed) | 2 | topology naming, disable_ddl_transaction! concurrent index |
| Bash-feasible FLAG (new hooks needed) | 10 | one-action migration, statement_timeout, if_not_exists, safety_assured, AR raw SQL, pluck chain, belongs_to optional, destroy_all/delete_all, multiple raise, .new().to_h |
| Already COVERED | 4 | migration creation, bang methods, single-letter vars, terraform Bash |
| LLM-only (no bash path) | 3 | IDs-only, index awareness, code pattern anti-patterns |
| N/A for code-write | 1 | deploy strategy presentation |

---

## Hook Pattern for New Deterministic Guards

Each new code-content hook follows the shape established by `validate-bang-method-web-flow.sh`:

```bash
# 1. Read tool_name from hook JSON
tool_name="$(printf '%s' "$hook_input" | jq -r '.tool_name // empty')"
[ "$tool_name" = "Edit" ] || [ "$tool_name" = "Write" ] || [ "$tool_name" = "MultiEdit" ] || exit 0

# 2. Extract new content from tool_input
#    Write: .tool_input.content
#    Edit: .tool_input.new_string
#    MultiEdit: .tool_input.edits[].new_string (requires jq array iteration)

# 3. Apply scope gate on file path
case "$file_path" in
  "$HOME"/Projects/4Shark/<scoped-path>/*.rb) ;;
  *) exit 0 ;;
esac

# 4. Regex match on new content
# 5. exit 2 with stderr for BLOCK; or exit 2 from PostToolUse for FLAG
```

Source: `/Users/plribeiro3000/.claude/scripts/validate-bang-method-web-flow.sh:1-92` — establishes the canonical hook pattern for code-content scanning.

---

## Source Citations

| Claim | Source | Verbatim evidence |
|---|---|---|
| Topology naming rule — absolute, no exceptions | `/Users/plribeiro3000/.claude/docs/DATA-PROCESSING.md` (via policy_verifier_rule_inventory_1.md:22) | "never invent names like Executor / Runner / Handler" |
| disable_ddl_transaction! rule — always invalid without it | `/Users/plribeiro3000/.claude/plans/active/spike/policy-verifier-agent/policy_verifier_rule_inventory_1.md:30` | "add_index ... algorithm: :concurrently without disable_ddl_transaction!" |
| AR exception: explicit engineer authorization | `/Users/plribeiro3000/.claude/docs/ACTIVE-RECORD-QUERY-DISCIPLINE.md:41` | "Raw SQL is acceptable only when the engineer explicitly authorizes it for a specific operation" |
| pluck→Ruby exception | `/Users/plribeiro3000/.claude/docs/ACTIVE-RECORD-QUERY-DISCIPLINE.md:79` | "Falling back to Ruby is acceptable only when the transformation cannot be expressed in SQL" |
| destroy_all exception: ≤15 records | `/Users/plribeiro3000/.claude/docs/BULK-DELETE.md:40-43` | "destroy_all is acceptable ONLY when: The collection has 15 or fewer records (small enough that memory is not a concern) AND you need callbacks/cascades to run" |
| delete_all exception: no callbacks/dependents | `/Users/plribeiro3000/.claude/docs/BULK-DELETE.md:44-48` | "delete_all is acceptable ONLY when: The model has no before_destroy/after_destroy callbacks AND the model has no dependent: associations that need cascading" |
| .to_h serialization boundary exception | CLAUDE.md § Use the Object — "to_h is legitimate ONLY at a genuine serialization boundary" |
| safety_assured as explicit escape hatch | CLAUDE.md § Rails Migrations — "safety_assured as a known-risk override" |
| belongs_to rule — absolute with no SELECT overhead | `/Users/plribeiro3000/.claude/docs/OPTIONAL-BELONGS-TO.md:7` | "ALWAYS use optional: true in belongs_to associations + manual validation" |
| Hook canonical pattern | `/Users/plribeiro3000/.claude/scripts/validate-bang-method-web-flow.sh:18-30` | scope gate + new_content extraction + regex match + exit 2 |
