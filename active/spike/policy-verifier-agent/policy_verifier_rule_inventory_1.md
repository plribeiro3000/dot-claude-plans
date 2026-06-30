# policy-verifier Rule Inventory — Verifiability Classification

## Purpose

This table inventories every 4Shark policy doc whose rules are relevant to planning documents
(PLAN.md, PLAN-SPIKE.md, TASKS.md, TASKS-SPIKE.md, SPIKE.md, CONTEXT-MAP.md, DOMAIN.md).

For each doc it records: the specific rule(s) that appear in code examples inside planning docs,
how verifiable each rule is for an LLM agent, and the detection method.

**Verifiability classes:**
- **MECHANICALLY VERIFIABLE** — keyword or regex matching against code examples in the document being checked; no contextual reasoning required
- **MIXED** — some sub-rules are mechanically verifiable, others require structural judgment
- **SUBJECTIVE** — requires LLM structural/shape analysis; cannot be reduced to keyword matching

---

## Rule Inventory

| Policy Doc | Rule(s) | Verifiability | Detection Method |
|---|---|---|---|
| `DATA-PROCESSING.md` | Topology naming: worker class must be named Processor, Producer, Consumer, Sower, or Grower — never Executor, Runner, Handler, Manager | MECHANICALLY VERIFIABLE | keyword regex on class names: /\b(Executor\|Runner\|Handler\|Manager)\b/ on worker class names |
| `DATA-PROCESSING.md` | IDs-only: never pass loaded objects between jobs; pass IDs | MIXED | structural: check if code examples show object passing vs id passing; partially reducible to detecting `.where(id: some_array)` vs `.find(ids).each` |
| `TERRAFORM-POLICY.md` | Never `-auto-approve` | MECHANICALLY VERIFIABLE | keyword: `-auto-approve` in any terraform command example |
| `TERRAFORM-POLICY.md` | Never apply without a saved plan file | MECHANICALLY VERIFIABLE | keyword: `terraform apply` without a `.tfplan` file argument |
| `TERRAFORM-POLICY.md` | Never chain terraform commands | MECHANICALLY VERIFIABLE | keyword: `&&` or `;` adjacent to `terraform` |
| `RAILS-MIGRATIONS.md` | Generate migrations (never hand-create) | MECHANICALLY VERIFIABLE | the verifier checks that code examples show `bin/rails generate migration`, not raw `create_table` outside a migration file |
| `RAILS-MIGRATIONS.md` | One action per migration | MECHANICALLY VERIFIABLE | structural: multiple `create_table`/`add_column`/`add_index` calls in one migration block |
| `RAILS-MIGRATIONS.md` | `statement_timeout` with `ENV.fetch` pattern | MECHANICALLY VERIFIABLE | keyword: migration code that lacks `statement_timeout` |
| `RAILS-MIGRATIONS.md` | `disable_ddl_transaction!` for concurrent indexes | MECHANICALLY VERIFIABLE | keyword: `add_index ... algorithm: :concurrently` without `disable_ddl_transaction!` |
| `RAILS-MIGRATIONS.md` | `if_not_exists`/`if_exists` for retry safety | MECHANICALLY VERIFIABLE | keyword: `add_column`/`remove_column` without `if_not_exists`/`if_exists` |
| `RAILS-MIGRATIONS.md` | `safety_assured` only as last resort | MECHANICALLY VERIFIABLE | keyword: `safety_assured` in migration code |
| `BANG-METHOD-WEB-FLOW.md` | Never use `create!`, `save!`, `update!`, `destroy!`, `find_by!` in controller or GraphQL mutation code examples | MECHANICALLY VERIFIABLE | regex: `(create!\|save!\|update!\|destroy!\|find_by!)` in code examples labeled as controller/mutation context |
| `ACTIVE-RECORD-QUERY-DISCIPLINE.md` | AR-first: no `update_all`, `delete_all`, `connection.execute`, `find_by_sql` without explicit "use raw SQL for this" authorization | MECHANICALLY VERIFIABLE | keyword: `update_all`, `delete_all`, `connection.execute`, `find_by_sql` |
| `ACTIVE-RECORD-QUERY-DISCIPLINE.md` | DB-side shaping: no `pluck` followed immediately by Ruby reshaping (`group_by`, `sort_by`, `transform_values`, `each_with_object`) | MECHANICALLY VERIFIABLE | regex: `pluck.*\.group_by\|pluck.*\.sort_by\|pluck.*\.transform_values` |
| `ACTIVE-RECORD-QUERY-DISCIPLINE.md` | Index awareness before non-trivial queries | SUBJECTIVE | context-dependent — requires understanding whether a `where`/`joins`/`order` targets a non-trivial table; cannot be mechanically detected |
| `CODE-PATTERN-DISCIPLINE.md` | Anti-patterns: Iceberg Class, Parameter-Passing Pipeline, Extracted Wrapper Methods, Phase Extraction, Per-Branch Delegation, Convention Drift | SUBJECTIVE | structural shape analysis (6-dimension pattern priming); requires LLM judgment |
| `OPTIONAL-BELONGS-TO.md` | Every `belongs_to` must have `optional: true` AND a companion `validates :x_id, presence: true` | MECHANICALLY VERIFIABLE | regex: `belongs_to` without `optional: true` on the same line or adjacent |
| `BULK-DELETE.md` | Avoid `destroy_all` and `delete_all` (default: pluck IDs + individual destroy) | MECHANICALLY VERIFIABLE | keyword: `destroy_all`, `delete_all` |
| `NO-MULTIPLE-RAISE.md` | No multiple `raise ArgumentError` for validation; use `errors.add` + `return false` | MECHANICALLY VERIFIABLE | regex: two or more `raise ArgumentError` occurrences in the same method/block |
| `USE-THE-OBJECT.md` | No instantiate-then-collapse: never `.new(...).to_h` immediately; read through named methods instead | MECHANICALLY VERIFIABLE | regex: `\.new\(.*\)\.to_h\|\.to_h` in proximity to a `.new` call |
| `DEPLOYMENT-STRATEGY.md` | Present both paths (phased + single deploy) with the deciding condition; do not default to safest | SUBJECTIVE | requires understanding of the deploy decision context; cannot be keyword-matched |

---

## Summary Counts

- **MECHANICALLY VERIFIABLE**: 16 rules across 8 policy docs
- **MIXED**: 1 rule (DATA-PROCESSING.md IDs-only)
- **SUBJECTIVE**: 4 rules (index awareness, all CODE-PATTERN anti-patterns, deploy strategy)

---

## Source citations

| Claim | Source | Verbatim evidence |
|---|---|---|
| Topology naming rule | `~/.claude/docs/DATA-PROCESSING.md:1-174` | "pick by the shape of the work, and name the worker for its topology (never invent names like Executor / Runner / Handler)" |
| Terraform -auto-approve | `~/.claude/docs/TERRAFORM-POLICY.md:1-11` | "never -auto-approve" |
| Rails migration — generate | `~/.claude/docs/RAILS-MIGRATIONS.md:1-25` | "NEVER hand-create a migration file. Always generate it" |
| Bang method rule | `~/.claude/docs/BANG-METHOD-WEB-FLOW.md:1-57` | "NEVER use ActiveRecord persistence bang methods (create!, save!, update!, destroy!, find_by!, ...) in web flows — controllers and GraphQL mutations" |
| AR-first rule | `~/.claude/docs/ACTIVE-RECORD-QUERY-DISCIPLINE.md:1-264` | "ActiveRecord-first by default; raw SQL only on explicit engineer authorization" |
| DB-side shaping rule | `~/.claude/docs/ACTIVE-RECORD-QUERY-DISCIPLINE.md:1-264` | "pluck followed by Ruby group_by / sort_by / transform_values / each_with_object is the anti-pattern this rule names" |
| Code pattern anti-patterns | `~/.claude/docs/CODE-PATTERN-DISCIPLINE.md:1-241` | "Forbidden anti-patterns (language-agnostic shapes): Iceberg Class, Parameter-Passing Pipeline, Extracted Wrapper Methods, Phase Extraction, Per-Branch Delegation" |
| Optional belongs_to | `~/.claude/docs/OPTIONAL-BELONGS-TO.md:1-65` | "ALWAYS use optional: true on belongs_to + manual validates :x_id, presence: true" |
| Bulk delete | `~/.claude/docs/BULK-DELETE.md:1-84` | "Avoid both destroy_all and delete_all. Default is to pluck IDs and destroy each individually" |
| No multiple raise | `~/.claude/docs/NO-MULTIPLE-RAISE.md:1-67` | "DO NOT use multiple raise ArgumentError statements for validation. Use errors.add(...) + return false" |
| Use the object | `~/.claude/docs/USE-THE-OBJECT.md:1-159` | "If you instantiate a real object (class with constructor + behavior), USE it through named methods — NEVER immediately collapse it into a primitive Hash/Array (to_h / to_a)" |
| Deployment strategy | `~/.claude/docs/DEPLOYMENT-STRATEGY.md:169-174` | "Do not default to the most conservative option... Present both options to the engineer — the safe path and the simpler path, each with the condition that makes it valid" |
