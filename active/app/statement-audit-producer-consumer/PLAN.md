# PLAN — Refactor StatementAudit Processor to Producer/Consumer

## Current Situation
- `StatementAudit::Processor` is a single monolithic worker that processes the entire audit in one job
- It loads ALL commissions → user_commissions → statements in nested loops, generating an XLSX workbook in memory
- For companies with many commissions/statements, this is a memory-heavy, long-running single job
- Other audits (UserAudit, PlanStatementAudit, CalendarAudit, etc.) already use the Producer/Consumer/Finalizer pattern with intermediate Row tables
- The `StatementsWorkSheet` iterates over `company.commissions → commission.user_commissions → statements`, loading each record individually
- Output is XLSX (single worksheet, confirmed) — direct migration to CSV with no multi-tab complexity

## Objective / Target State
- Refactor `StatementAudit` to use the same Producer/Consumer/Finalizer pattern as other audits
- Create a `statement_audit_rows` table with unique index for idempotency
- Distribute work across many small Consumer jobs instead of one large Processor job
- Generate CSV output (like other Producer/Consumer audits) instead of XLSX
- Remove all legacy code (Processor, WorkBook, WorkSheet) in the same PR

## Challenges, Difficulties and Risks
- **Technical**: The current Processor iterates by commission → statement. The Producer/Consumer pattern needs a flat list of IDs. The natural unit is `statement_id` (one Consumer per Statement)
- **Data**: The `StatementsWorkSheet` conditionally adds an "approver" column when `company.manager_legal_module?` — the Finalizer needs to handle this same conditional
- **Performance**: The unique index must cover `audit_id + statement_id` for idempotency
- **Period is a model, not a string**: `commission.period` returns a `Period` object (with `starts_at`/`ends_at`). The Consumer must convert it to a string representation before storing in the Row
- **accepted_at comes from Acceptment**: `Statement` does not have an `accepted_at` column — it's derived from `statement.acceptment.created_at`. The Consumer must resolve this

## Solution — Consumer per Statement

Producer collects all statement IDs for the company (via commissions → user_commissions → active users → statements). Each Consumer receives `[audit_id, statement_id]`, loads the statement and related data, upserts a Row. Finalizer generates CSV from rows, saves as attachment, and cleans up rows in batches.

## Proposed Steps

1. **Create migration**: `create_statement_audit_rows` table with columns:
   - `audit_id` (bigint, not null)
   - `statement_id` (bigint, not null)
   - `approver_name` (string, limit: 8000)
   - `plan_name` (string, limit: 8000)
   - `calendar_name` (string, limit: 8000)
   - `period` (string, limit: 8000) — stored as string, converted from Period object by Consumer
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
   - `accepted_at` (date) — NOT string, matches `plan_statement_audit_rows` type
   - Index on `audit_id`
   - Index on `statement_id`

2. **Create migration**: Add unique index `[audit_id, statement_id]` with `algorithm: :concurrently`, named `statement_audit_rows_unique_index`

3. **Create model**: `StatementAudit::Row < ApplicationRecord`
   - `belongs_to :statement_audit, foreign_key: :audit_id, inverse_of: :rows, optional: true`
   - `belongs_to :statement, optional: true, inverse_of: :audit_rows`
   - `validates :audit_id, :statement_id, presence: true`
   - `rescue_unique_constraint index: :statement_audit_rows_unique_index, field: :statement_id`
   - `self.table_name = :statement_audit_rows`
   - Note: `CLEANUP_BATCH_SIZE` is inherited from `ApplicationRecord` (defined there as 10_000) — do NOT redefine

4. **Update model**: `StatementAudit` — add `has_many :rows`

5. **Update model**: `Statement` — add `has_many :audit_rows, class_name: 'StatementAudit::Row', inverse_of: :statement, dependent: :nullify` (required for the `inverse_of` on Row's `belongs_to :statement`)

6. **Create worker**: `StatementAudit::Producer`
   - Load company, collect all statement IDs:
     - `company.commissions.pluck(:id)` → for each commission: `commission.user_commissions.pluck(:id, :user_id)` → filter active users → `Statement.where(user_commission_id:, user_id:).pluck(:id)`
   - `computation.increment_queue`
   - `Sidekiq::Client.push_bulk` to Consumer

7. **Create worker**: `StatementAudit::Consumer`
   - Receive `[audit_id, statement_id]`
   - Load statement, user_commission, commission, user, parent, plan, calendar, group, approver
   - Upsert Row with `unique_by: :statement_audit_rows_unique_index`
   - Populate fields, converting:
     - `commission.period` → string via Period's string representation
     - `statement.acceptment.created_at.to_date` → `accepted_at` (only when accepted)
     - `statement.accepted?.humanize` → `accepted` (with company locale)
   - `computation.increment_executions`
   - Call Finalizer when `computation.done?`

8. **Create worker**: `StatementAudit::Finalizer`
   - Generate CSV from rows (conditional `approver_name` column based on `manager_legal_module?`)
   - Uses `CsvExporter` methods (`csv_headers`, `to_csv`) on `rows.select(attributes)` relation
   - UTF-16LE encoding (matching other Finalizers)
   - Save as attachment, transition to `finish!`
   - Cleanup rows in batches, re-enqueue until done

9. **Update GraphQL mutation**: Change `StatementAudit::Processor.perform_async` → `StatementAudit::Producer.perform_async`

10. **Create locale files**: `statement_audit/row.yml` for all 9 locales (en, pt-BR, es, es-AR, es-CL, es-CO, es-MX, es-PA, es-PE)
    - Must include ALL Row attributes that the Finalizer selects (including `approver_name` and `period`)

11. **Delete legacy code**:
    - `app/workers/statement_audit/processor.rb`
    - `app/work_books/statement_audit_work_book.rb`
    - `app/work_books/statement_audit_work_book/statements_work_sheet.rb`
    - No existing specs to delete (confirmed: none exist)

12. **Write tests**: Row model spec, Producer spec, Consumer spec, Finalizer spec

## Internal References
- Current Processor: `app/workers/statement_audit/processor.rb`
- Current WorkBook: `app/work_books/statement_audit_work_book.rb`
- Current WorkSheet: `app/work_books/statement_audit_work_book/statements_work_sheet.rb`
- StatementAudit model: `app/models/statement_audit.rb`
- Statement model: `app/models/statement.rb` (has `acceptment` association, `accepted?` method)
- Audit base model: `app/models/audit.rb`
- GraphQL mutation: `app/graphql_mutations/create_statement_audit_graphql_mutation.rb`
- CLEANUP_BATCH_SIZE: `app/models/application_record.rb:4` (inherited, value: 10_000)
- CsvExporter: `lib/active_record/csv_exporter.rb` (provides `csv_headers`, `to_csv` on relations)
- Commission model: `app/models/commission.rb` (period is a `belongs_to` returning Period object)
- **Reference implementations (Producer/Consumer pattern):**
  - PlanStatementAudit: `app/workers/plan_statement_audit/{producer,consumer,finalizer}.rb`
  - PlanStatementAudit Row: `app/models/plan_statement_audit/row.rb`
  - UserAudit: `app/workers/user_audit/{producer,consumer,finalizer}.rb`
  - UserAudit Row: `app/models/user_audit/row.rb`

## Decision

**APPROVED: Consumer per Statement**
