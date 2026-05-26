# NEXT TASKS — Integration Audit: User — Phase 3 (dot-claude Skill Update)

> **Objective:** Update `~/Projects/4Shark/dot-claude/skills/integration-debug/SKILL.md` so Phase 1 (Discovery) and Phase 3 (Verification) automatically invoke the 5 rake tasks via `aws ecs run-task` and read CSVs from S3. Phase 2 (Execution) stays manual.
>
> **Reference:** `PLAN.md § Phase 3` (canonical) — column lists, S3 path conventions, cross-CSV joins, MFA handling.

---

## 0) Pre-conditions

- [x] **Phase 1 (App)** — PR #5018 merged into `develop`. 3 rake tasks live: `integration_audit:user[company_id]`, `integration_audit:user_identifier[company_id]`, `integration_audit:seat_history[company_id]`.
- [x] **Phase 2 (Integrator)** — hotfix `8.4.6` merged + tagged + deployed. 2 rake tasks live: `integration_audit:mongo:user`, `integration_audit:normalized:user`.
- [ ] **Base branch:** `origin/develop` of `dot-claude` repo • **Working branch:** `feature/integration-audit-skill-automation` (or similar)

---

## 1) Step by Step

### Task 1 — Read current `SKILL.md`

- [ ] `~/Projects/4Shark/dot-claude/skills/integration-debug/SKILL.md`
- Identify: Phase 1 (Discovery) section, Phase 3 (Verification) section, "Division of Labor" section.

### Task 2 — Replace Phase 1 (Discovery) with automation

- [ ] Skill asks engineer for: `company_id` (app), `integrator-slug`, scenario context (unchanged from current skill).
- [ ] Skill resolves the 5 task invocations:
  - **App** (region `us-east-1`, profile `4shark-ecs`, cluster `<env>-cluster`, runner task definition `<env>-runner`):
    - `bundle exec rake 'integration_audit:user[<company_id>]'`
    - `bundle exec rake 'integration_audit:user_identifier[<company_id>]'`
    - `bundle exec rake 'integration_audit:seat_history[<company_id>]'`
  - **Integrator** (region `sa-east-1`, default profile, cluster `integrator-<slug>-cluster`, runner `integrator-<slug>-runner`):
    - `bundle exec rake integration_audit:mongo:user`
    - `bundle exec rake integration_audit:normalized:user`
- [ ] For each: `aws ecs run-task` with command override pointing at the rake invocation. All 5 fire in parallel.
- [ ] Poll each via `aws ecs wait tasks-stopped`.
- [ ] Capture stdout of each task (CloudWatch logs); extract the `s3://...` URI line (last line of stdout for successful runs; absent for the `normalized:user` no-op branch).
- [ ] For each captured URI, read the CSV via `aws s3 cp <uri> -`.

### Task 3 — Replace Phase 3 (Verification) with automation

- [ ] Same shape as Phase 1; new timestamps naturally produce a different S3 prefix per invocation.
- [ ] Skill diffs the Phase 3 CSVs against Phase 1 to surface what changed during Phase 2 (manual mutations).

### Task 4 — Document cross-CSV joins for the skill's reconciliation logic

- [ ] Within app:
  - `user.user_id` ↔ `user_identifier.user_id`
  - `user.user_id` ↔ `seat_history.user_id`
  - `user.user_primary_identifier_value` ↔ `user_identifier.value` (filter `primary=true`)
  - `user.user_parent_identifier` ↔ `user.user_primary_identifier_value` (self-join)
  - `seat_history.parent_id` (when `parent_type='Seat'`) ↔ `seat_history.seat_id`
- [ ] Within integrator: `mongo.external_id` ↔ `normalized.<pk>` (customer schema dependent)
- [ ] App ↔ integrator: `app.user_identifier.value` (or `user.user_primary_identifier_value`) ↔ `integrator.mongo.external_id` — **strip `4sk_` prefix in non-managed mode** (per `integrator/app/models/import.rb#identifier`); no prefix in managed mode

### Task 5 — Update "Division of Labor" section

- [ ] "Skill runs Phases 1 and 3 automatically (queries + S3 reads via `aws ecs run-task`). Engineer runs Phase 2 by hand (mutation scripts pasted into `bin/ecs run` console). The Phase 2 division is a safety decision — human review is the only gate against a wrong filter mass-mutating production."

### Task 6 — MFA / AccessDenied handling

- [ ] On `AccessDenied` from `aws ecs run-task` or `aws s3 cp`: skill instructs `/aws-elevate`, then retries the failed call.

### Task 7 — Update CHANGELOG.md (dot-claude)

- [ ] Add under `## [Unreleased]` → `### Changed`:
  - `Automated Phases 1 and 3 of integration-debug skill via per-resource rake tasks and direct S3 reads`

### Task 8 — Commit + PR

- [ ] Single commit: `feat(integration-debug): automate Phases 1 and 3 via app + integrator rake tasks`
- [ ] Push with explicit refspec (first push of new branch — see `~/.claude/CLAUDE.md` § Git Push Safety).
- [ ] Open PR against `develop` of dot-claude.

---

## 2) Out of scope for this phase

- `mongo:user_identifier`, `mongo:hierarchy`, `normalized:user_identifier`, etc. are **deferred** until the continuous-feeding skill workflow is built. The current audit covers the **setup migration** scenario only — engineer's explicit scope decision (2026-05-08).
- Adapt the integrator rake to develop's API (`Source.where(normalized: true)` instead of `ApplicationConfiguration.non_database_integration?`, per-source `connect!` instead of `Database.connect!`). **Track separately**; the develop runtime is broken until done, but production (master) is fine.

---

## 3) Skill behavior reminders not to break

- The skill stays the same on Phase 2 (Execution) — Claude generates mutation scripts as text; engineer reviews and pastes them into `bin/ecs run` console. **Do not automate Phase 2.**
- `aws ecs run-task` is a write operation — skill always operates with explicit MFA elevation flow.
- Each rake generates its own timestamp inline — skill does NOT pass `AUDIT_TIMESTAMP` env var (deprecated approach from earlier iteration; reverted).

---

## See also

- `PLAN.md` (parent dir) — full canonical reference: column lists, S3 paths, joins, hard-won lessons.
- `~/Projects/4Shark/app/lib/tasks/integration_audit.rake` — App rake source (PR #5018 merged).
- `~/Projects/4Shark/integrator/lib/tasks/integration_audit.rake` — Integrator rake source (8.4.6 tag).
- `~/Projects/4Shark/app/app/workers/user_audit/consumer.rb` — `UserAudit::Row` reference pattern the user task follows.
