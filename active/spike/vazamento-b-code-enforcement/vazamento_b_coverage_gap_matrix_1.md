# Vazamento B — Coverage Gap Matrix

## Purpose

Maps each 4Shark policy rule that applies at code-write time to its existing write-time guard (if any). "Write-time" means the guard fires during or immediately after an Edit/Write/MultiEdit tool call — not at prompt injection time (UserPromptSubmit) and not at Bash execution time.

**Events** (used throughout this table):
- **PreToolUse BLOCK** — hook runs before the write; exits 2 to prevent the write from executing
- **PreToolUse INJECT** — hook runs before the write; exits 0 with additionalContext (always allows)
- **PostToolUse FLAG** — hook runs after the write; exits 2 to force Claude to acknowledge the violation (write already occurred)
- **Bash BLOCK** — hook fires on actual Bash execution (not on Edit/Write); blocks the command

Source: settings.json hook wiring at `/Users/plribeiro3000/.claude/settings.json`

---

## Matrix

| Rule | Governing Doc | Existing Write-Time Guard | Event | Gap Status |
|---|---|---|---|---|
| Topology naming — worker class must be named Processor, Producer, Consumer, Sower, or Grower; never Executor, Runner, Handler, Manager | DATA-PROCESSING.md | None | — | **GAP** |
| IDs-only — pass IDs between jobs, not loaded objects (MIXED verifiability) | DATA-PROCESSING.md | None | — | **GAP** |
| Never `-auto-approve` in terraform | TERRAFORM-POLICY.md | validate-bash-command.sh | Bash BLOCK | COVERED for Bash execution; not applicable to code-write (.tf files do not contain apply commands) |
| terraform apply requires a saved plan file | TERRAFORM-POLICY.md | validate-bash-command.sh | Bash BLOCK | COVERED for Bash execution; not applicable to code-write |
| Never chain terraform commands | TERRAFORM-POLICY.md | validate-bash-command.sh | Bash BLOCK | COVERED for Bash execution; not applicable to code-write |
| Generate migrations with `bin/rails generate migration` — never hand-create | RAILS-MIGRATIONS.md | validate-rails-migration-creation.sh | PreToolUse Write BLOCK | **COVERED** |
| One action per migration | RAILS-MIGRATIONS.md | None | — | **GAP** |
| `statement_timeout` with `ENV.fetch` pattern in migrations | RAILS-MIGRATIONS.md | None | — | **GAP** |
| `disable_ddl_transaction!` required for concurrent indexes | RAILS-MIGRATIONS.md | None | — | **GAP** |
| `if_not_exists`/`if_exists` for retry safety | RAILS-MIGRATIONS.md | None | — | **GAP** |
| `safety_assured` only as last resort (flag its presence) | RAILS-MIGRATIONS.md | None | — | **GAP** |
| No bang methods in controllers or GraphQL mutations | BANG-METHOD-WEB-FLOW.md | validate-bang-method-web-flow.sh | PreToolUse Edit\|Write\|MultiEdit BLOCK | **COVERED** |
| AR-first: no `update_all`, `delete_all`, `connection.execute`, `find_by_sql` without explicit authorization | ACTIVE-RECORD-QUERY-DISCIPLINE.md | inject-query-discipline.sh (prompt injection only) | UserPromptSubmit / SubagentStart INJECT | **GAP** — prompt-level prevention only; no code-write detection |
| DB-side shaping: no `pluck` followed by Ruby reshaping (`group_by`, `sort_by`, `transform_values`, `each_with_object`) | ACTIVE-RECORD-QUERY-DISCIPLINE.md | inject-query-discipline.sh (prompt injection only) | UserPromptSubmit / SubagentStart INJECT | **GAP** — prompt-level prevention only; no code-write detection |
| Index awareness before non-trivial queries (SUBJECTIVE) | ACTIVE-RECORD-QUERY-DISCIPLINE.md | None | — | **GAP** (not deterministically detectable) |
| Code pattern anti-patterns — Iceberg Class, Parameter-Passing Pipeline, Extracted Wrapper Methods, Phase Extraction, Per-Branch Delegation, Convention Drift (SUBJECTIVE) | CODE-PATTERN-DISCIPLINE.md | inject-code-pattern-on-write.sh | PreToolUse Edit\|Write\|MultiEdit INJECT | **GAP** — context injection is preventive priming, not detection; violations still possible |
| `optional: true` on every `belongs_to` + companion `validates :x_id, presence: true` | OPTIONAL-BELONGS-TO.md | None | — | **GAP** |
| Avoid `destroy_all` and `delete_all` (default: pluck IDs + individual destroy) | BULK-DELETE.md | None | — | **GAP** |
| No multiple `raise ArgumentError` for validation; use `errors.add` + `return false` | NO-MULTIPLE-RAISE.md | None | — | **GAP** |
| No instantiate-then-collapse: never `.new(...).to_h` immediately | USE-THE-OBJECT.md | None | — | **GAP** |
| No single-letter variable names or SQL aliases | CODE-STYLE-RULES.md / CLAUDE.md | check-abbreviated-variables.sh | PostToolUse Edit\|Write\|MultiEdit FLAG | **COVERED** |
| Deploy strategy: present both paths (phased + single) with deciding condition; do not default to safest (SUBJECTIVE) | DEPLOYMENT-STRATEGY.md | inject-deployment-strategy.sh (prompt injection) | UserPromptSubmit / SubagentStart INJECT | N/A — this is a planning-doc rule, not a code-write rule |

---

## Summary Counts

- **COVERED** (existing write-time guard): 4 rules
  - migration creation blocked (validate-rails-migration-creation.sh)
  - bang methods in controllers/mutations blocked (validate-bang-method-web-flow.sh)
  - single-letter variables flagged (check-abbreviated-variables.sh)
  - Terraform `-auto-approve` / apply / chain blocked at Bash execution (validate-bash-command.sh)
- **PARTIAL** (prompt-level prevention only; no code-write detection): 3 rules
  - AR-first (inject-query-discipline.sh prevents but does not detect after write)
  - DB-side shaping (inject-query-discipline.sh prevents but does not detect)
  - Code pattern anti-patterns (inject-code-pattern-on-write.sh primes but does not detect)
- **GAP** (no guard at all): 12 rules
  - Topology naming
  - IDs-only (MIXED)
  - One action per migration
  - statement_timeout pattern
  - disable_ddl_transaction! for concurrent indexes
  - if_not_exists/if_exists
  - safety_assured presence
  - optional: true on belongs_to
  - Avoid destroy_all/delete_all
  - No multiple raise ArgumentError
  - No .new().to_h collapse
  - Index awareness (SUBJECTIVE — not deterministically detectable)

---

## Source Citations

| Script | File:line | Verbatim evidence |
|---|---|---|
| validate-rails-migration-creation.sh scope | `/Users/plribeiro3000/.claude/scripts/validate-rails-migration-creation.sh:36-38` | `case "$file_path" in "$HOME"/Projects/4Shark/*/db/migrate/*.rb) ;; *) exit 0 ;; esac` |
| validate-bang-method-web-flow.sh scope | `/Users/plribeiro3000/.claude/scripts/validate-bang-method-web-flow.sh:18-30` | path gate + `patterns="(create|save|...destroy|find_by|...)\!"` |
| check-abbreviated-variables.sh PostToolUse event | `/Users/plribeiro3000/.claude/scripts/check-abbreviated-variables.sh:1-5` | `# PostToolUse hook for Edit|Write|MultiEdit. Blocks single-letter variable names and single-letter SQL aliases` |
| inject-code-pattern-on-write.sh always-allow | `/Users/plribeiro3000/.claude/scripts/inject-code-pattern-on-write.sh:124-131` | `permissionDecision: "allow", additionalContext: $ctx` |
| inject-query-discipline.sh fires on UserPromptSubmit | `/Users/plribeiro3000/.claude/settings.json` hook wiring for `inject-query-discipline.sh` |
| validate-bash-command.sh terraform / infra Bash only | `/Users/plribeiro3000/.claude/scripts/validate-bash-command.sh:29-30` | `tool_name="$(printf '%s' "$hook_input" | jq -r '.tool_name // empty')"` — Bash path distinct from Edit/Write path |
