# NEXT TASKS — Integration Audit: User — Phase 2 (Integrator Rake Tasks)

## ✅ STATUS: MERGED, TAGGED, DEPLOYED (2026-05-08) — Hotfix `8.4.6`

- `integration_audit:mongo:user` — dumps Mongoid `User` resources (Resource STI). Columns: `resource_id`, `external_id`, `integration_status`, `primary_identifier_subsidiary_id`, `created_at`, `updated_at`, `imports_count`. Pluck-IDs + `User.find` per record.
- `integration_audit:normalized:user` — page-based dump of `<table_prefix>users` via `Database.connect!.page(:users, '', last_id)` cursor. No-op when `ApplicationConfiguration.non_database_integration?` (managed/api/self_service modes — no normalized DB to query).

`non_database_integration?` predicate added to `lib/application_configuration.rb` to satisfy NO-UNLESS-CONVENTION (Strategy 2). Output paths: `s3://<bucket>/integration-audit/{mongo,normalized}/user/<ts>.csv`. Stdout prints `s3://...` URI; no-op branch prints no `s3://` line.

Tag `8.4.6` pushed. Master + develop in sync. Image built and deployed to all 12 integrator ECS clusters (almaviva, atento-{br,cl,co,mx} + 3 atento stagings, commcenter, commcenter-staging, maqnelson, redebrasil). Web services scaled back up after deploy.

### ⚠️ KNOWN ISSUE on develop (no production impact)

Develop branch removed the `integration_mode` system (per the `Source`-driven refactor in CHANGELOG `[Unreleased]`). After back-merge of 8.4.6 into develop, the rake references methods that **don't exist on develop**:

- `ApplicationConfiguration.non_database_integration?` — removed
- `Database.connect!` — replaced by per-source `Source#connect!`

The rake LOADS fine (`rake -T` works — body is lazy-evaluated). It explodes at runtime when invoked on develop. **Production runs from master**, which has the methods, so production is fine.

**Follow-up at next develop release:** adapt to develop's API (`Source.where(normalized: true)` for guard; per-source `connect!` for the page query). Track as separate PR.

### Out of scope (engineer scope decision, 2026-05-08)

`mongo:user_identifier`, `mongo:hierarchy`, `normalized:user_identifier`, etc. are **not part of this iteration**. They're for hierarchy/identifier corrections, used in continuous-feeding scenarios. This first audit is for **setup migration only**.

**Canonical reference:** `../PLAN.md § Phase 2`.

The original objective and detailed checklist below are kept for historical context.

---

## ORIGINAL OBJECTIVE (superseded — kept for history)

> **Objective of this iteration:** Create two rake tasks in the `integrator` project that dump user audit data from MongoDB to CSV files in S3, enabling automated verification via the `/integration-debug` skill. **This phase is deployed as a hotfix off `master`, not a feature branch off `develop`.**
> **Reference:** PLAN.md § Phase 2 (Integrator — Rake Tasks), § Deploy Order, and § Technical Decisions.

---

## 0) Pre-conditions

- [ ] `PLAN.md` **approved**
- [ ] **Base branch:** `origin/master` (hotfix pattern) • **Working branch:** Created via `git hf hotfix start integration-audit-user`
- [ ] **IMPORTANT:** This is a hotfix, not a feature branch. See PLAN.md § Deploy Order for the rationale.

---

## 1) Step by Step (atomic tasks)

### Task 1 — Create integration_audit.rake file with namespace structure

- **Objective:** Create the new rake file and define the namespace structure for both audit tasks.
- **Actions (checklist):**
  - [ ] Create file `~/Projects/4Shark/integrator/lib/tasks/integration_audit.rake` (new file)
  - [ ] Define two nested namespaces: `namespace :integration_audit` containing `namespace :mongo` and `namespace :normalized`
  - [ ] Within `mongo`, define task stub `:user`
  - [ ] Within `normalized`, define task stub `:user`
  - [ ] Both stubs should log a placeholder message
  - [ ] Run `bundle exec rake integration_audit:mongo:user` and `bundle exec rake integration_audit:normalized:user` locally to verify the tasks are discoverable
- **Affected files/areas:** `lib/tasks/integration_audit.rake` (new)
- **Completion criteria:** Both rake tasks are callable without error; placeholder logs appear when invoked.
- **Observations:** This mirrors the structure from the `app` phase but with two separate namespaces: one for integrator-side data, one for normalized-source data.

### Task 2 — Implement `integration_audit:mongo:user` task

- **Objective:** Query Resource (User type) data from all active streams across MongoDB, generate CSV, write to S3.
- **Actions (checklist):**
  - [ ] In the `integration_audit:mongo:user` task body, read environment variable `AUDIT_TIMESTAMP` (required; abort if not set)
  - [ ] Query workflow (from PLAN.md § Phase 3, lines 214–221):
    - `ResourceType.where(resource: 'User')` → get all user resource types
    - `Stream.where(resource_type: user_resource_types, disabled: false)` → active streams
    - `Resource.where(stream: active_streams)` → all user resources across those streams
  - [ ] Generate CSV with columns (from PLAN.md § Phase 3, lines 192–203):
    - `resource_id`, `external_id`, `stream_id`, `source_id`, `resource_type_name`, `integration_status`, `integration_id`
  - [ ] For `source_id`, use `Stream#source_id` from the stream associated with each resource
  - [ ] For `resource_type_name`, use `ResourceType#name`
  - [ ] Use `S3.adapter.put_object` directly (not `S3.store`) to target the `integration-audit/` prefix (reference: PLAN.md § Phase 2)
  - [ ] S3 key: `integration-audit/mongo/user/#{audit_timestamp}.csv`
  - [ ] Error handling: abort on missing `AWS_BUCKET`; propagate S3 exceptions (reference: PLAN.md § Phase 2)
  - [ ] Write CSV to string buffer in memory; pass full string to `put_object` in one call
  - [ ] After successful S3 write, print the full S3 URI as the final line of stdout: `puts "s3://#{bucket}/integration-audit/mongo/user/#{audit_timestamp}.csv"` (reference: PLAN.md § Stdout output contract)
- **Affected files/areas:** `lib/tasks/integration_audit.rake` (update the task body)
- **Completion criteria:**
  - [ ] Task queries Resource records with User type across all active streams
  - [ ] CSV is generated with correct column headers and data
  - [ ] S3 write uses `S3.adapter.put_object` and targets correct key
  - [ ] Task exits 0 when `AWS_BUCKET` is set and S3 is reachable
  - [ ] Task aborts with clear message when `AWS_BUCKET` is not set
  - [ ] Manual test: `AUDIT_TIMESTAMP=20260507-120000 bundle exec rake integration_audit:mongo:user` writes a file to S3 and exits 0
- **Observations:** The query pattern is specific to Mongoid associations. Use `.to_a` only if necessary (should be lazy evaluated). Avoid loading all records into memory at once; if the query is large, consider batching.

### Task 3 — Implement `integration_audit:normalized:user` task

- **Objective:** Query User-type Resources from the normalized source only; no-op if normalized source does not exist.
- **Actions (checklist):**
  - [ ] In the `integration_audit:normalized:user` task body, read environment variable `AUDIT_TIMESTAMP` (required; abort if not set)
  - [ ] Guard clause (from PLAN.md § Phase 3, lines 209–212): check `Source.where(normalized: true).exists?`
  - [ ] If no normalized source exists, log "No normalized User source found. Skipping." and exit 0 (no S3 file written)
  - [ ] If normalized source exists, query workflow (similar to Task 2, but filtered):
    - `ResourceType.where(resource: 'User')` → user resource types
    - `Source.where(normalized: true)` → normalized source (should be exactly one)
    - `Stream.where(resource_type: user_resource_types, source: normalized_source, disabled: false)` → active normalized streams
    - `Resource.where(stream: active_normalized_streams)` → all user resources on normalized streams
  - [ ] Generate CSV with same columns as Task 2 (same structure; different data)
  - [ ] Use `S3.adapter.put_object` with S3 key: `integration-audit/normalized/user/#{audit_timestamp}.csv`
  - [ ] Error handling: same as Task 2 (abort on missing bucket, propagate S3 errors)
  - [ ] After successful S3 write, print the full S3 URI on stdout (same contract as Task 2)
  - [ ] When the no-op branch is taken (no normalized source), do NOT print an `s3://` URI; skill detects absence as "no file produced"
- **Affected files/areas:** `lib/tasks/integration_audit.rake` (add task body)
- **Completion criteria:**
  - [ ] Task logs and exits 0 when no normalized source exists (no file written)
  - [ ] Task queries Resource records from normalized source only when it exists
  - [ ] CSV is generated with correct column headers and data
  - [ ] S3 write succeeds with correct key format
  - [ ] Task exits 0 when bucket is set and S3 is reachable
  - [ ] Manual test with no normalized source: `AUDIT_TIMESTAMP=20260507-120000 bundle exec rake integration_audit:normalized:user` logs "No normalized..." and exits 0
- **Observations:** This task is conditional on the existence of a normalized source. Not all integrators have one; this is normal. The guard clause prevents errors and makes the task idempotent across all integrators.

### Task 4 — Verify both tasks with realistic MongoDB data

- **Objective:** Test both rake tasks against a staging or local MongoDB with realistic data to ensure correct queries and no performance issues.
- **Actions (checklist):**
  - [ ] Use a staging environment or local MongoDB with representative data (at least 10+ User-type resources, ideally multiple streams)
  - [ ] Test with a normalized source present (Task 3 should write a CSV)
  - [ ] Test on an integrator without a normalized source (Task 3 should log and skip)
  - [ ] Run both tasks with a valid `AUDIT_TIMESTAMP` set
  - [ ] Verify CSVs are written to S3 with correct structure
  - [ ] Verify task execution time is reasonable (<1 minute for staging volumes)
  - [ ] Verify no MongoDB connection leaks
  - [ ] Verify no memory bloat
- **Affected files/areas:** `lib/tasks/integration_audit.rake`, S3 buckets (test write), MongoDB (read-only)
- **Completion criteria:**
  - [ ] Both tasks complete successfully with realistic data
  - [ ] CSV files are readable and contain all expected columns and rows
  - [ ] `normalized:user` task correctly logs and skips when no normalized source exists
  - [ ] No performance warnings or memory issues
- **Observations:** If either task is slow, consider lazy evaluation or batching for very large datasets. The expectation is that these are one-off audit invocations, not scheduled jobs, so some latency is acceptable.

### Task 5 — Verify no existing tests are broken

- **Objective:** Run the full test suite to ensure the new rake file and tasks do not break any existing functionality.
- **Actions (checklist):**
  - [ ] Run `bundle exec rspec` (full suite) or equivalent per project convention
  - [ ] Fix any test failures caused by the new rake file
  - [ ] Verify test coverage is adequate (no new rake task coverage required)
- **Affected files/areas:** Full test suite
- **Completion criteria:** All existing tests pass with exit code 0; no new failures related to the rake tasks.
- **Observations:** Rake tasks are tested via the `/integration-debug` skill invocation (Phase 4), not via unit tests. No new test files are required.

### Task 6 — Update CHANGELOG.md

- **Objective:** Document the new rake tasks in the changelog under the `Added` section.
- **Actions (checklist):**
  - [ ] Open `~/Projects/4Shark/integrator/CHANGELOG.md`
  - [ ] Add entry under `## [Unreleased]` → `### Added`:
    - Entry: "User audit tasks for integration reconciliation (`integration_audit:mongo:user`, `integration_audit:normalized:user`)"
  - [ ] Keep entry brief; no technical details per 4Shark conventions
- **Affected files/areas:** `CHANGELOG.md`
- **Completion criteria:** Changelog entry is present and describes the feature in user-facing language.
- **Observations:** This hotfix will be released immediately after merging (via `git hf hotfix finish`), so the changelog entry becomes the release notes. Keep it concise.

### Task 7 — Create hotfix branch and commit

- **Objective:** Formally start and complete the hotfix branch using HubFlow pattern.
- **Actions (checklist):**
  - [ ] Verify you are on `origin/master` or have pulled it recently
  - [ ] Run `git hf hotfix start integration-audit-user` (creates `hotfix/integration-audit-user` off `master`)
  - [ ] Implement all tasks above on this branch
  - [ ] Commit changes: `git add lib/tasks/integration_audit.rake CHANGELOG.md`
  - [ ] Follow Angular commit guidelines (see `~/.claude/docs/PULL-REQUEST-CONVENTIONS.md` for hotfix format):
    - Commit message: `feat(integration-audit): add user audit tasks for integrator and normalized sources`
    - Or if desired, match the CHANGELOG entry structure for consistency
  - [ ] Do NOT commit with `git hf hotfix finish` yet — wait for engineer approval after PR merge
- **Affected files/areas:** Git branch, commits
- **Completion criteria:** Hotfix branch exists and contains all rake code and changelog updates.
- **Observations:** The hotfix branch will be merged back to `master` and `develop` automatically when `git hf hotfix finish` is run (which happens after PR merge and approval).

---

## 2) Items Requiring User Confirmation

- [ ] **Normalized source handling:** Confirm that exiting with status 0 (no file written) when no normalized source exists is the correct behavior. (default: yes, per PLAN.md § Phase 3, lines 209–212)
- [ ] **Query optimization:** Should queries use eager loading (`.includes`) or lazy evaluation? (default: lazy for large datasets; eager if dataset is small and predictable)
- [ ] **S3 adapter access:** Confirm that `S3.adapter` is available in the rake context when the initializer runs. (expected: yes, per PLAN.md Assumptions, line 355)
- [ ] **Hotfix timing:** This is a hotfix off `master`. Confirm this is the correct branch choice per your deployment strategy. (default: yes, per PLAN.md § Deploy Order, lines 315–318)

> **Expected response (example):**
> `APPROVED: no-op on missing normalized source is correct; use lazy evaluation; hotfix branch is correct; proceed with implementation.`

---

## 3) Pending Items After This Iteration (if any arise)

- If the `S3.adapter.put_object` call fails with `NoMethodError`, verify that the `S3` model is initialized before the rake executes. The rake file should require `:environment` dependency at the top.
- If either query returns zero records but the database has User resources, the query predicate may be incorrect. Debug by logging intermediate query results.
- If `normalized:user` task writes an empty CSV when a normalized source exists but has no User resources, that is correct behavior. Log "No resources found on normalized source." for clarity.

---

## Cross-Repository Dependency

This phase has **no upstream dependency**. Existing per-stack IAM users already have S3 read/write on their own buckets by design. This phase is independent of Phase 1 (app tasks) — they can proceed in parallel.

**Important:** This is a **hotfix**, not a feature branch. It is released independently of `develop` and back-merges to both `master` and `develop` via `git hf hotfix finish`. This ensures the integrator audit tasks are available in production without bundling unrelated `develop` work.

See PLAN.md § Deploy Order: Phase 1 (app) and Phase 2 (integrator) in parallel → Phase 3 (dot-claude skill update).
