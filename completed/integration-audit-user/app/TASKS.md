# NEXT TASKS — Integration Audit: User — Phase 1 (App Rake Tasks)

## ✅ STATUS: MERGED (2026-05-08) — PR #5018

**Final shape differs from original objective below.** The single denormalized task evolved to **three per-resource tasks** during review iteration:

- `integration_audit:user[company_id]` — hand-selected columns following `UserAudit::Row` pattern (18 cols: user fields + immediate manager identifier/name + senior manager identifier/name/seat). Devise/session columns excluded.
- `integration_audit:user_identifier[company_id]` — auto-discovered via `UserIdentifier.column_names`.
- `integration_audit:seat_history[company_id]` — `SeatHistory.column_names + ['user_id']`, enriched via `joins(seat: :user)`. Replaces a separate `seat` task (SeatHistory's `ends_at IS NULL` row covers current state).

`company_id` is a **rake parameter** (not env var). Each task generates its own UTC timestamp inline (`%Y%m%d-%H%M%S`) and prints the full `s3://...` URI on stdout. Output paths under `s3://<stack-bucket>/integration-audit/<company_id>/<resource>/<ts>.csv`.

**Canonical reference:** `../PLAN.md § Phase 1` (column lists, cross-CSV joins, lessons).

The original objective and detailed checklist below are kept for historical context — they describe an earlier shape that was replaced.

---

## ORIGINAL OBJECTIVE (superseded — kept for history)

> **Objective of this iteration:** Create one rake task `integration_audit:user` in the `app` project that dumps a denormalized user+identifier+seat CSV to S3 (one row per UserIdentifier, parent User and Seat fields repeated). Output enables automated reconciliation via the `/integration-debug` skill.
> **Reference:** PLAN.md § Phase 1 (App — Rake Task) and § Technical Decisions.

---

## 0) Pre-conditions

- [ ] `PLAN.md` **approved**
- [ ] **Base branch:** `origin/develop` • **Working branch:** `feature/integration-audit-user-app`

---

## 1) Step by Step (atomic tasks)

### Task 1 — Create `integration_audit.rake` with the `:user` task

- **Objective:** Add the new rake file with a single task `integration_audit:user`.
- **Actions (checklist):**
  - [ ] Create file `~/Projects/4Shark/app/lib/tasks/integration_audit.rake` (new file)
  - [ ] Define `namespace :integration_audit do; task user: :environment do; ...; end; end`
  - [ ] Read env vars at task start (abort with clear message if missing):
    - `AUDIT_TIMESTAMP` (format `YYYYMMDD-HHMMSS`, set by the skill)
    - `COMPANY_ID` (multi-tenant scope)
    - `AWS_BUCKET` (resolved via `ApplicationConfiguration.aws_bucket`)
- **Affected files/areas:** `lib/tasks/integration_audit.rake` (new)
- **Completion criteria:** Rake file exists, namespace and task stub are callable, missing-env handling works.

### Task 2 — Implement the query and CSV generation

- **Objective:** Build the denormalized data set and emit a CSV string.
- **Actions (checklist):**
  - [ ] Scope: `UserIdentifier.where(company_id: COMPANY_ID)`
  - [ ] Eager-load to avoid N+1: `.includes(user: :seat)` (User#has_one :seat is the Seat record); also include `.subsidiary` if needed for read access
  - [ ] Iterate over the scope per the 4Shark Data Processing Pattern: pluck IDs first, then `find_each` (or equivalent) to keep memory bounded
  - [ ] For each `UserIdentifier`, build a row with these columns (PLAN.md § Phase 1 column table — verified against `db/schema.rb` and the User/Seat/UserIdentifier models):
    - `user_identifier_id`, `user_identifier_value`, `user_identifier_primary`, `user_identifier_subsidiary_id`, `user_identifier_disabled_at`
    - `user_id`, `user_name`, `user_last_name`, `user_email`, `user_disabled_at`
    - `seat_type`, `seat_parent_id`, `seat_parent_type`
  - [ ] When `User` is nil or `Seat` is nil for an identifier, emit blank fields for that side (do not skip the row)
  - [ ] Use Ruby's `CSV` standard library to build the output as a string in memory
- **Affected files/areas:** `lib/tasks/integration_audit.rake` (task body)
- **Completion criteria:** CSV string contains correct headers and one row per matching `UserIdentifier`; no N+1 queries.

### Task 3 — Implement S3 write and stdout output contract

- **Objective:** Write the CSV to S3 and print the full URI on stdout.
- **Actions (checklist):**
  - [ ] Build S3 key: `integration-audit/#{COMPANY_ID}/user/#{AUDIT_TIMESTAMP}.csv`
  - [ ] Use `Aws.connection` (existing `app/app/models/aws.rb` pattern) to obtain the Fog::Storage adapter
  - [ ] Call `Aws.connection.put_object(bucket, key, csv_string)`
  - [ ] After the `put_object` returns (no exception), `puts "s3://#{bucket}/#{key}"` as the final line of stdout
  - [ ] Let any Fog/AWS exception propagate (non-zero exit; skill detects via task exit code)
- **Affected files/areas:** `lib/tasks/integration_audit.rake` (task body)
- **Completion criteria:**
  - [ ] CSV is uploaded to the correct S3 key
  - [ ] Final stdout line is `s3://<bucket>/integration-audit/<company_id>/user/<ts>.csv`
  - [ ] Task exits 0 on success
  - [ ] Task aborts with a clear message when any required env var (`AUDIT_TIMESTAMP`, `COMPANY_ID`, `AWS_BUCKET`) is missing

### Task 4 — Verify with realistic data

- **Objective:** Smoke-test the rake against a populated database before merging.
- **Actions (checklist):**
  - [ ] Use a staging or local DB with at least one company that has users and identifiers
  - [ ] Set `AUDIT_TIMESTAMP=20260507-120000`, `COMPANY_ID=<id>`, `AWS_BUCKET=<bucket>` in env
  - [ ] Run `bundle exec rake integration_audit:user`
  - [ ] Verify CSV is written to S3 with correct shape (one row per identifier; user + seat fields repeated)
  - [ ] Verify final stdout line is the S3 URI
  - [ ] Verify cross-subsidiary case: a user with identifiers in two subsidiaries produces two rows
- **Affected files/areas:** `lib/tasks/integration_audit.rake`, S3 (test write)
- **Completion criteria:** All checks above pass.

### Task 5 — Verify no existing tests are broken

- **Objective:** Run the test suite to ensure the new file doesn't interfere with anything.
- **Actions (checklist):**
  - [ ] Run `bundle exec rspec` (full suite)
  - [ ] Fix any unexpected failures
- **Affected files/areas:** Full test suite
- **Completion criteria:** All existing tests pass with exit code 0.

### Task 6 — Update CHANGELOG.md

- **Objective:** Document the new rake task.
- **Actions (checklist):**
  - [ ] Open `~/Projects/4Shark/app/CHANGELOG.md`
  - [ ] Add under `## [Unreleased]` → `### Added`:
    - `User audit task for integration reconciliation`
- **Affected files/areas:** `CHANGELOG.md`
- **Completion criteria:** Changelog entry is present and follows 4Shark format (no technical details).

### Task 7 — Commit and open PR

- **Objective:** Land the change.
- **Actions (checklist):**
  - [ ] Create branch `feature/integration-audit-user-app` from `origin/develop`
  - [ ] Stage `lib/tasks/integration_audit.rake` and `CHANGELOG.md`
  - [ ] Commit with Angular-style message (no AI co-authorship)
  - [ ] Push with explicit refspec (per `~/.claude/CLAUDE.md` § Git Push Safety)
  - [ ] Open PR targeting `develop`
- **Affected files/areas:** Git
- **Completion criteria:** PR is open and CI is green.

---

## 2) Items Requiring User Confirmation

- [ ] **Identifiers without an attached user**: emit row with blank user/seat fields (default: yes) or skip them (alternative: skip)?
- [ ] **`includes(user: :seat)` vs raw SQL join**: preference for ActiveRecord eager loading vs hand-written join?

---

## 3) Pending Items After This Iteration (if any arise)

- If the query takes more than a few seconds on the largest tenant, consider batching by `find_each(batch_size: 1000)` and writing CSV in append mode. PLAN.md currently says full dataset in memory is acceptable for an audit tool; revisit if memory pressure shows up.
- If `AccessDenied` on `s3:PutObject`: the static AWS keys for that stack may not have the expected scope. Per-stack isolation places that responsibility on the IAM user behind the keys; investigate the user/policy outside this repo if it ever fails.

---

## Cross-Repository Dependency

This phase has **no upstream dependency**. Existing per-stack IAM users already have S3 read/write on their own buckets by design. After this phase completes, the `/integration-debug` skill (Phase 3, dot-claude) can invoke this task automatically via `aws ecs run-task`.

See PLAN.md § Deploy Order: Phase 1 (app) and Phase 2 (integrator) can run in parallel; Phase 3 (skill update) follows.
