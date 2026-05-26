# NEXT TASKS — StatementAudit Producer/Consumer — Consumer per Statement

> **Objective of this iteration:** Refactor `StatementAudit::Processor` into Producer/Consumer/Finalizer pattern with intermediate `statement_audit_rows` table, CSV output, and removal of all legacy XLSX code.
> **Reference:** derived from `PLAN.md` (section: Solution — Consumer per Statement).

---

## 0) Pre-conditions

- [x] `PLAN.md` **approved** (option: Consumer per Statement)
- [ ] **Base branch:** `develop` • **Working branch:** `feature/statement-audit-producer-consumer`

---

## 1) Step by Step (atomic tasks)

### Task 1 — Create `statement_audit_rows` table migration
- **Objective:** Create the intermediate rows table for storing denormalized statement audit data
- **Actions (checklist):**
  - [ ] Create migration `create_statement_audit_rows` with columns:
    - `audit_id` (bigint, not null)
    - `statement_id` (bigint, not null)
    - `approver_name` (string, limit: 8000)
    - `plan_name` (string, limit: 8000)
    - `calendar_name` (string, limit: 8000)
    - `period` (string, limit: 8000) — Period object converted to string by Consumer
    - `group_name` (string, limit: 8000)
    - `user_name` (string, limit: 8000)
    - `user_primary_identifier_value` (string, limit: 8000)
    - `user_register_type` (string)
    - `user_unique_register_id` (string)
    - `parent_name` (string, limit: 8000)
    - `parent_primary_identifier_value` (string, limit: 8000)
    - `parent_register_type` (string)
    - `parent_unique_register_id` (string)
    - `accepted` (string, limit: 8000)
    - `accepted_at` (date) — NOT string, matches `plan_statement_audit_rows`
  - [ ] Add index on `audit_id`
  - [ ] Add index on `statement_id`
- **Affected files/areas:** `db/migrate/`
- **Completion criteria:** Migration runs successfully, table exists in schema

### Task 2 — Create unique index migration
- **Objective:** Add unique index for Consumer idempotency
- **Actions (checklist):**
  - [ ] Create migration `add_statement_audit_rows_unique_index`
  - [ ] Use `disable_ddl_transaction!` (required for `algorithm: :concurrently`)
  - [ ] Add unique index on `[audit_id, statement_id]`, named `statement_audit_rows_unique_index`
- **Affected files/areas:** `db/migrate/`
- **Completion criteria:** Unique index exists on the table

### Task 3 — Create `StatementAudit::Row` model
- **Objective:** Create the Row model following the established pattern
- **Actions (checklist):**
  - [ ] Create `app/models/statement_audit/row.rb`
  - [ ] `belongs_to :statement_audit, foreign_key: :audit_id, inverse_of: :rows, optional: true`
  - [ ] `belongs_to :statement, optional: true, inverse_of: :audit_rows`
  - [ ] `validates :audit_id, presence: true`
  - [ ] `validates :statement_id, presence: true`
  - [ ] `rescue_unique_constraint index: :statement_audit_rows_unique_index, field: :statement_id`
  - [ ] `self.table_name = :statement_audit_rows`
  - [ ] Do NOT define `CLEANUP_BATCH_SIZE` — inherited from `ApplicationRecord` (10_000)
- **Affected files/areas:** `app/models/statement_audit/row.rb`
- **Completion criteria:** Model follows exact pattern of `PlanStatementAudit::Row`

### Task 4 — Update `StatementAudit` model
- **Objective:** Add `has_many :rows` association
- **Actions (checklist):**
  - [ ] Add `has_many :rows, class_name: 'StatementAudit::Row', foreign_key: :audit_id, inverse_of: :statement_audit, dependent: :destroy`
- **Affected files/areas:** `app/models/statement_audit.rb`
- **Completion criteria:** `StatementAudit` has the rows association

### Task 5 — Update `Statement` model
- **Objective:** Add `has_many :audit_rows` association (required for `inverse_of` on Row)
- **Actions (checklist):**
  - [ ] Add `has_many :audit_rows, class_name: 'StatementAudit::Row', inverse_of: :statement, dependent: :nullify`
- **Affected files/areas:** `app/models/statement.rb`
- **Completion criteria:** Statement has the audit_rows association, matching the pattern from PlanStatement, User, UserIdentifier models

### Task 6 — Create `StatementAudit::Producer`
- **Objective:** Create the Producer worker that distributes work to Consumers
- **Actions (checklist):**
  - [ ] Create `app/workers/statement_audit/producer.rb`
  - [ ] `sidekiq_options queue: :audit`
  - [ ] Load `StatementAudit` and transition to `process!`
  - [ ] Load company, collect statement IDs following the same chain as `StatementsWorkSheet`:
    - `company.commissions.pluck(:id)` → per commission: `user_commissions.pluck(:id, :user_id)` → filter active users → `Statement.where(user_commission_id:, user_id:).pluck(:id)`
  - [ ] `computation.increment_queue(by: statement_ids.count)`
  - [ ] `Sidekiq::Client.push_bulk('class' => StatementAudit::Consumer, 'args' => arguments)`
- **Affected files/areas:** `app/workers/statement_audit/producer.rb`
- **Completion criteria:** Producer collects statement IDs via commission → user_commission → active users → statements chain

### Task 7 — Create `StatementAudit::Consumer`
- **Objective:** Create the Consumer worker that processes one statement and upserts a Row
- **Actions (checklist):**
  - [ ] Create `app/workers/statement_audit/consumer.rb`
  - [ ] `sidekiq_options queue: :audit`
  - [ ] Receive `(audit_id, statement_id)`
  - [ ] Load statement → user_commission → commission → plan, calendar, group, approver
  - [ ] Load user, parent
  - [ ] Upsert Row with `unique_by: :statement_audit_rows_unique_index`
  - [ ] Populate all denormalized fields:
    - `approver_name` from `commission.approver.try(:name)`
    - `period` converted to string from Period object
    - `accepted` from `statement.accepted?.humanize` (with company locale)
    - `accepted_at` from `statement.acceptment.created_at.to_date` (only when `statement.accepted?`)
  - [ ] `computation.increment_executions`
  - [ ] Call `Finalizer.perform_async(audit_id)` when `computation.done?`
- **Affected files/areas:** `app/workers/statement_audit/consumer.rb`
- **Completion criteria:** Consumer follows `PlanStatementAudit::Consumer` pattern with upsert + find_by + save!

### Task 8 — Create `StatementAudit::Finalizer`
- **Objective:** Create the Finalizer worker that generates CSV and cleans up rows
- **Actions (checklist):**
  - [ ] Create `app/workers/statement_audit/finalizer.rb`
  - [ ] `sidekiq_options queue: :audit`
  - [ ] Implement two modes: CSV generation (when not final) and cleanup (when final)
  - [ ] CSV generation: select attributes conditionally based on `company.manager_legal_module?` (include `approver_name` or not)
  - [ ] Use `CsvExporter` methods: `rows.select(attributes).csv_headers` and `.to_csv`
  - [ ] Write CSV with UTF-16LE encoding (matching `PlanStatementAudit::Finalizer`)
  - [ ] Save attachment, call `finish!`
  - [ ] Cleanup: delete rows in batches using `CLEANUP_BATCH_SIZE` (inherited from ApplicationRecord), re-enqueue until done
- **Affected files/areas:** `app/workers/statement_audit/finalizer.rb`
- **Completion criteria:** Finalizer follows exact pattern of `PlanStatementAudit::Finalizer`

### Task 9 — Update GraphQL mutation
- **Objective:** Point mutation to Producer instead of Processor
- **Actions (checklist):**
  - [ ] Change `StatementAudit::Processor.perform_async(form.id)` → `StatementAudit::Producer.perform_async(form.id)` in `CreateStatementAuditGraphqlMutation`
- **Affected files/areas:** `app/graphql_mutations/create_statement_audit_graphql_mutation.rb`
- **Completion criteria:** Mutation triggers Producer

### Task 10 — Create locale files
- **Objective:** Add i18n translations for `StatementAudit::Row` attributes (used as CSV headers by `CsvExporter`)
- **Actions (checklist):**
  - [ ] Create `config/locales/en/models/statement_audit/row.yml`
  - [ ] Create `config/locales/pt-BR/models/statement_audit/row.yml`
  - [ ] Create `config/locales/es/models/statement_audit/row.yml`
  - [ ] Create `config/locales/es-AR/models/statement_audit/row.yml`
  - [ ] Create `config/locales/es-CL/models/statement_audit/row.yml`
  - [ ] Create `config/locales/es-CO/models/statement_audit/row.yml`
  - [ ] Create `config/locales/es-MX/models/statement_audit/row.yml`
  - [ ] Create `config/locales/es-PA/models/statement_audit/row.yml`
  - [ ] Create `config/locales/es-PE/models/statement_audit/row.yml`
  - [ ] Include ALL attributes the Finalizer selects: `approver_name`, `plan_name`, `calendar_name`, `period`, `group_name`, `user_name`, `user_primary_identifier_value`, `user_register_type`, `user_unique_register_id`, `parent_name`, `parent_primary_identifier_value`, `parent_register_type`, `parent_unique_register_id`, `accepted`, `accepted_at`
- **Affected files/areas:** `config/locales/*/models/statement_audit/row.yml`
- **Completion criteria:** All 9 locale files exist with translations for ALL Row attributes
- **Observations:** Use `plan_statement_audit/row.yml` as base. Add `approver_name`, `period`, `group_name` keys specific to this audit.

### Task 11 — Delete legacy code
- **Objective:** Remove all old Processor and WorkBook code
- **Actions (checklist):**
  - [ ] Delete `app/workers/statement_audit/processor.rb`
  - [ ] Delete `app/work_books/statement_audit_work_book.rb`
  - [ ] Delete `app/work_books/statement_audit_work_book/statements_work_sheet.rb`
  - [ ] Delete `app/work_books/statement_audit_work_book/` directory
- **Affected files/areas:** `app/workers/statement_audit/`, `app/work_books/statement_audit_work_book*`
- **Completion criteria:** No Processor or WorkBook code remains
- **Observations:** No existing specs to delete (confirmed: none exist for Processor or WorkBook)

### Task 12 — Write tests
- **Objective:** Add specs for all new code
- **Actions (checklist):**
  - [ ] Create `spec/models/statement_audit/row_spec.rb` (associations + validations)
  - [ ] Create `spec/workers/statement_audit/producer_spec.rb`
  - [ ] Create `spec/workers/statement_audit/consumer_spec.rb`
  - [ ] Create `spec/workers/statement_audit/finalizer_spec.rb`
- **Affected files/areas:** `spec/models/`, `spec/workers/`
- **Completion criteria:** All specs pass, following existing test patterns
- **Observations:** Read existing specs (`plan_statement_audit/row_spec.rb`, `user_audit/row_spec.rb`) before writing. No specs for Processor/WorkBook existed, so nothing to migrate.

---

## 2) Items Requiring User Confirmation

- None — all decisions resolved in PLAN.md

---

## 3) Pending Items After This Iteration (if any arise)

- [ ] Verify CSV output matches business expectations (columns, order, encoding)
- [ ] Monitor performance in staging with large companies
