# PLAN — Integration Audit: User

## Status (2026-05-08)

| Phase | What | Status |
|---|---|---|
| 1 — App rake tasks | 3 tasks shipped via PR #5018 → `develop` | ✅ MERGED |
| 2 — Integrator rake tasks | 2 tasks shipped via hotfix `8.4.6` → master + develop | ✅ MERGED + TAGGED + DEPLOYED |
| 3 — dot-claude skill update | Skill `/integration-debug` to invoke the 5 rakes | ⏳ NEXT |

## Objective

Automate Phases 1 (Discovery) and 3 (Verification) of the `integration-debug` skill via rake tasks that dump audit CSVs to S3. Each rake task generates its own timestamp inline and prints the full `s3://...` URI on stdout. Phase 2 (Execution) of the skill stays manual.

## IAM model (no Terraform changes needed)

Per-stack IAM users have S3 read/write on their own bucket by design. Existing static AWS keys (loaded from SSM) cover the Fog connection. No Terraform work was required.

---

## Phase 1 — App (PR #5018, merged into `develop`)

**File:** `app/lib/tasks/integration_audit.rake`

Three tasks, each parameterized by `company_id` (rake task parameter, not env var). Each writes one CSV to `s3://<bucket>/integration-audit/<company_id>/<resource>/<timestamp>.csv` and prints the URI on stdout.

### Task: `integration_audit:user[company_id]`

Hand-selected columns following the `UserAudit::Row` model (`db/schema.rb` lines 1992–2015, `app/workers/user_audit/consumer.rb`). 18 columns:

```
user_id
user_name
user_email
user_register_type
user_unique_register_id
user_created_at
user_updated_at
user_disabled
user_disabled_at
user_disabler_name
user_seat                       (raw seat type, e.g. 'Manager')
user_primary_identifier_value
user_subsidiary                 (subsidiary.external_id of primary_identifier)
user_parent_identifier          (immediate manager's primary_identifier_value)
user_parent_name                (immediate manager's name)
senior_manager_identifier       (top-of-hierarchy manager — nil when user is at top)
senior_manager_name
senior_manager_seat
```

Senior manager walk replicates `UserAudit::Consumer`: `while seat.role.parent_needed?; senior_manager = senior_manager.parent; end`. Senior fields are nil when the user's role doesn't need a parent (i.e., user is already at top).

Devise/session columns intentionally excluded (`encrypted_password`, `reset_password_token`, sign-in trackers, locked_at, etc.).

### Task: `integration_audit:user_identifier[company_id]`

Auto-discovered columns via `UserIdentifier.column_names`. Filter: `where(company_id: company_id)`.

### Task: `integration_audit:seat_history[company_id]`

`SeatHistory.column_names + ['user_id']` — enriched with `seats.user_id` via `joins(seat: :user)` so each row carries the seat's owner. The `seat` task was dropped: SeatHistory's open entry (`ends_at IS NULL`) covers current state; `role_id` is omitted (not load-bearing for reconciliation).

Filter: `joins(seat: :user).where(users: { company_id: company_id })`. Single dual `pluck(*column_names, 'seats.user_id')` — no N+1.

### Cross-CSV joins (within app)

- `user.user_id` ↔ `user_identifier.user_id`
- `user.user_id` ↔ `seat_history.user_id`
- `user.user_primary_identifier_value` ↔ `user_identifier.value` (filtered to `primary=true`)
- `user.user_parent_identifier` ↔ `user.user_primary_identifier_value` (self-join — find immediate manager's row)
- `seat_history.parent_id` (when `parent_type='Seat'`) ↔ `seat_history.seat_id` of the parent seat (`WHERE ends_at IS NULL` for current state)

---

## Phase 2 — Integrator (hotfix `8.4.6`, merged into master + develop, tagged, deployed)

**File:** `integrator/lib/tasks/integration_audit.rake`

Two tasks. No `company_id` parameter (integrator stack is per-customer, single-tenant by deployment).

### Task: `integration_audit:mongo:user`

Dumps `User` Mongoid resources (Resource STI, `_type='User'`). Columns: `resource_id`, `external_id`, `integration_status`, `primary_identifier_subsidiary_id`, `created_at`, `updated_at`, `imports_count`. Pluck `_id`, iterate via `User.find` per record.

### Task: `integration_audit:normalized:user`

Page-based dump of customer's `<table_prefix>users` table via `Database.connect!.page(:users, '', last_id)` with cursor (same pattern as `app/workers/user/database_extractor.rb:13`). Loops until empty.

Guard: no-op (`puts SKIPPED; next`) when `ApplicationConfiguration.non_database_integration?` returns true (managed/api/self_service modes have no normalized DB to query). Predicate added to `lib/application_configuration.rb` to satisfy NO-UNLESS-CONVENTION (`if !` is last-resort per the doc).

Output paths: `s3://<bucket>/integration-audit/mongo/user/<ts>.csv` and `s3://<bucket>/integration-audit/normalized/user/<ts>.csv`. Timestamps generated inline. Stdout prints the full `s3://...` URI; for the no-op branch, no `s3://` line is printed (skill detects absence as "no file produced").

### KNOWN ISSUE (develop only, master is fine)

Develop branch of integrator removed the `integration_mode` system as part of `Source`-driven refactor. After back-merge of hotfix 8.4.6 into develop, the rake on develop references methods that no longer exist there:

- `ApplicationConfiguration.non_database_integration?` — removed on develop with the rest of the integration_mode predicates
- `Database.connect!` — replaced by per-source `Source#connect!` on develop

The rake LOADS fine in `rake -T` (lazy-evaluated body), but explodes at runtime when invoked on develop. **No production impact** — production runs from master, which has the methods.

**Follow-up needed on develop release:** adapt the rake to develop's API:
- Replace `non_database_integration?` guard with `Source.where(normalized: true).none?`
- Replace `Database.connect!.page(:users, ...)` with `normalized_source.connect!.page(:users, ...)` or equivalent

### Integrator splits NOT done (engineer scope decision)

`mongo:user_identifier`, `mongo:hierarchy`, `normalized:user_identifier`, etc. are **out of scope** for this iteration. They're for hierarchy/identifier corrections and updates. This first audit is for **setup migration** only. Continuous-feeding scope expands later.

---

## Phase 3 — dot-claude skill update (NEXT)

**File:** `~/Projects/4Shark/dot-claude/skills/integration-debug/SKILL.md`

The skill's Phase 1 (Discovery) and Phase 3 (Verification) become automated:

1. Skill asks the engineer for company_id (app multi-tenant scope) and integrator slug
2. For each phase invocation, skill fires **5 rake tasks via `aws ecs run-task` in parallel**:
   - **App** (us-east-1, profile `4shark-ecs`):
     - `bundle exec rake 'integration_audit:user[<company_id>]'`
     - `bundle exec rake 'integration_audit:user_identifier[<company_id>]'`
     - `bundle exec rake 'integration_audit:seat_history[<company_id>]'`
   - **Integrator** (sa-east-1, default profile):
     - `bundle exec rake integration_audit:mongo:user`
     - `bundle exec rake integration_audit:normalized:user`
3. Skill polls each task via `aws ecs wait tasks-stopped`
4. Skill captures stdout of each task; extracts the `s3://...` URI line
5. Skill reads each CSV via `aws s3 cp <uri> -` (stdout)
6. Skill performs reconciliation diff inline using the cross-CSV join graph (see § Phase 1 Cross-CSV joins + Phase 2 cross-side joins below)

### Cross-side joins (app ↔ integrator) for the skill

- `app.user.user_primary_identifier_value` (`4sk_<X>`) ↔ `integrator.mongo.external_id` (`<X>`) — strip `4sk_` prefix in non-managed mode; no prefix in managed mode (the `Source` config decides)
- `app.user_identifier.value` ↔ `integrator.mongo.external_id` (same prefix transformation)
- `integrator.mongo.external_id` ↔ `integrator.normalized.<pk>` (depends on customer schema, typically `id`)

### Skill behavior changes

- Phase 1 (Discovery) — old: "generate snapshot scripts, engineer pastes". NEW: skill orchestrates the 5 run-task calls, reads CSVs from S3, builds reconciliation report
- Phase 3 (Verification) — same shape as Phase 1, with new timestamp prefix
- Phase 2 (Execution) — UNCHANGED. Mutation scripts still hand-written by skill, hand-pasted by engineer in `bin/ecs run` console. Safety: human review remains the only gate against bad mutations
- "Division of Labor" section reworded: "skill runs Phases 1 and 3 automatically; engineer runs Phase 2 by hand"

### MFA / profiles

`aws ecs run-task` is a write op. On `AccessDenied`, skill instructs `/aws-elevate`. App tasks need `4shark-ecs` profile after elevation; integrator tasks use default profile (no explicit profile in `integrator/bin/ecs`).

### S3 path conventions for skill consumption

```
# App (per company)
s3://<app-stack-bucket>/integration-audit/<company_id>/user/<ts>.csv
s3://<app-stack-bucket>/integration-audit/<company_id>/user_identifier/<ts>.csv
s3://<app-stack-bucket>/integration-audit/<company_id>/seat_history/<ts>.csv

# Integrator (per stack — already per-customer)
s3://<integrator-stack-bucket>/integration-audit/mongo/user/<ts>.csv
s3://<integrator-stack-bucket>/integration-audit/normalized/user/<ts>.csv
```

Each timestamp `YYYYMMDD-HHMMSS` (UTC), generated inline at task execution. Phase 1 and Phase 3 of the skill produce different timestamps naturally. No env-var coordination needed.

---

## Hard-won lessons from the integrator hotfix iteration

These caused multiple correction cycles. Recorded so the dot-claude phase doesn't repeat them.

1. **Read all convention docs before writing code.** Run rubocop locally before every push. Squash mid-branch iterations before pushing (one-commit-per-PR rule).
2. **Validate against the branch's actual code** — develop and master can diverge significantly. Never reuse models read on a different branch.
3. **Follow Data Processing Pattern** — pluck IDs first, iterate. For SQL, page-based via cursor (`connection.page(...)`). Never load full result sets.
4. **`Time.now.utc.strftime(...)` inline, not env var** — timestamps come from the rake itself, not from outside.
5. **Rake parameters, not env vars** — `task :user, [:company_id] => :environment do |_t, args|`. Invoke with `rake 'integration_audit:user[123]'`.
6. **Read access to env vars goes through `ApplicationConfiguration`** — not direct `ENV.fetch`.
7. **`x.blank?` not `x.nil? || x.empty?`** — ActiveSupport, used throughout the codebase.
8. **Multi-line assignment breaks the line:** `csv_string =\n  CSV.generate do |csv|\n    ...\n  end`.
9. **No safe navigation (`&.`)** — explicit conditionals. Per `~/.claude/docs/NO-SAFE-NAVIGATION.md`.
10. **NO-UNLESS Strategy 2 over Strategy 4** — create opposite predicate (`non_database_integration?`) instead of `if !x.predicate?`.
11. **HubFlow procedure for hotfix conflict mid-finish:** resolve conflict on develop → `git add` + `git commit` the merge → SWITCH BACK TO `hotfix/<version>` → re-run `git hf hotfix finish <version>`. Do NOT do manual push + manual delete.
12. **Branch name = version for releases/hotfixes.** `hotfix/8.4.6`, not `hotfix/<descriptive-name>`. Hook blocks plain branch creation; use `git hf hotfix start X.Y.Z`.
13. **`config/version.rb` bumps** as part of the hotfix commit when applicable.
14. **PR title for hotfix = `[X.Y.Z] - YYYY-MM-DD`** per `~/.claude/docs/PULL-REQUEST-CONVENTIONS.md`.
