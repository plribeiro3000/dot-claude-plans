# TASKS — Document Processing: Idempotent Producer/Consumer Pattern

**Base:** `develop`

---

## PR 1: GroupDocument Fixes

**Branch:** `feature/group-document-idempotent`

- [ ] **1.1** Add `CLEANUP_BATCH_SIZE = 10_000` to `app/models/application_record.rb`
- [ ] **1.2** Create migration `add_unique_index_to_group_document_rows`
  - Index: `[document_id, document_line]`
  - `disable_ddl_transaction!`, `algorithm: :concurrently`, `index_exists?` checks
- [ ] **1.3** Run `bin/rails db:migrate`
- [ ] **1.4** Update `app/workers/group_document/producer.rb`:
  - Add `raise RaceConditionException unless computation.done?`
  - Add `computation.reset_queue` + `reset_executions`
  - Add `rows.delete_all` before processing
  - Change `create` to `find_or_initialize_by(document_id:, document_line:)`
- [ ] **1.5** Update `app/workers/group_document/finalizer.rb`:
  - Change to batch delete pattern (10k at a time)
- [ ] **1.6** Run tests: `bundle exec rspec spec/workers/group_document/`
- [ ] **1.7** Update `CHANGELOG.md`:
  ```markdown
  ### Fixed

  - Group document processing
  ```

---

## PR 2: IndicatorDocument Fixes

**Branch:** `feature/indicator-document-idempotent`

- [ ] **2.1** Create migration `drop_old_indicator_document_rows_index`
  - Drop index on business fields: `[company_id, user_identifier_value, subsidiary_external_id, variable_key, compiled_at]`
- [ ] **2.2** Create migration `add_correct_unique_index_to_indicator_document_rows`
  - Index: `[document_id, document_line, variable_key]`
  - `disable_ddl_transaction!`, `algorithm: :concurrently`, `index_exists?` checks
- [ ] **2.3** Run `bin/rails db:migrate`
- [ ] **2.4** Update `app/workers/indicator_document/producer.rb`:
  - Add `raise RaceConditionException unless computation.done?`
  - Add `computation.reset_queue` + `reset_executions`
  - Add `rows.delete_all` before processing
  - Change `find_or_initialize_by` to use `document_id, document_line, variable_key`
- [ ] **2.5** Update `app/workers/indicator_document/finalizer.rb`:
  - Change `destroy_all` to batch delete pattern
- [ ] **2.6** Run tests: `bundle exec rspec spec/workers/indicator_document/`
- [ ] **2.7** Update `CHANGELOG.md`:
  ```markdown
  ### Fixed

  - Indicator document processing
  ```

---

## PR 3: DealDocument Producer/Consumer

**Branch:** `feature/deal-document-producer-consumer`

### Database

- [ ] **3.1** Create migration `create_deal_document_rows`
- [ ] **3.2** Create migration `add_unique_index_to_deal_document_rows`
  - Index: `[document_id, document_line]`
- [ ] **3.3** Run `bin/rails db:migrate`
- [ ] **3.4** Verify `db/schema.rb` has new table and index

### Model

- [ ] **3.5** Create `app/models/deal_document/row.rb`
- [ ] **3.6** Add `has_many :rows` to `app/models/deal_document.rb`
- [ ] **3.7** Create `spec/models/deal_document/row_spec.rb`
- [ ] **3.8** Run `bundle exec rspec spec/models/deal_document/`

### Workers

- [ ] **3.9** Create `app/workers/deal_document/producer.rb`
- [ ] **3.10** Create `app/workers/deal_document/consumer.rb`
- [ ] **3.11** Create `app/workers/deal_document/finalizer.rb`

### Integration

- [ ] **3.12** Update `app/graphql_mutations/create_deal_document_attachment_graphql_mutation.rb`: `Processor` → `Producer`

### Cleanup

- [ ] **3.13** Delete `app/workers/deal_document/processor.rb`
- [ ] **3.14** Delete `spec/workers/deal_document/processor_spec.rb` (if exists)
- [ ] **3.15** Update `CHANGELOG.md`:
  ```markdown
  ### Added

  - Deal document parallel processing
  ```

---

## Validation (after all PRs merged)

- [ ] **4.1** Run full test suite
- [ ] **4.2** Test GroupDocument reprocessing (should be idempotent)
- [ ] **4.3** Test IndicatorDocument reprocessing (should be idempotent)
- [ ] **4.4** Test DealDocument with small CSV (10 rows)
- [ ] **4.5** Test DealDocument with large CSV (1000+ rows)

---

## Files Summary

### PR 1: GroupDocument

| Action | File |
|--------|------|
| Modify | `app/models/application_record.rb` |
| Create | `db/migrate/*_add_unique_index_to_group_document_rows.rb` |
| Modify | `app/workers/group_document/producer.rb` |
| Modify | `app/workers/group_document/finalizer.rb` |

### PR 2: IndicatorDocument

| Action | File |
|--------|------|
| Create | `db/migrate/*_drop_old_indicator_document_rows_index.rb` |
| Create | `db/migrate/*_add_correct_unique_index_to_indicator_document_rows.rb` |
| Modify | `app/workers/indicator_document/producer.rb` |
| Modify | `app/workers/indicator_document/finalizer.rb` |

### PR 3: DealDocument

| Action | File |
|--------|------|
| Create | `db/migrate/*_create_deal_document_rows.rb` |
| Create | `db/migrate/*_add_unique_index_to_deal_document_rows.rb` |
| Create | `app/models/deal_document/row.rb` |
| Create | `app/workers/deal_document/producer.rb` |
| Create | `app/workers/deal_document/consumer.rb` |
| Create | `app/workers/deal_document/finalizer.rb` |
| Create | `spec/models/deal_document/row_spec.rb` |
| Modify | `app/models/deal_document.rb` |
| Modify | `app/graphql_mutations/create_deal_document_attachment_graphql_mutation.rb` |
| Delete | `app/workers/deal_document/processor.rb` |

---

## Quick Reference: Correct Pattern

### Producer
```ruby
raise RaceConditionException unless document.computation.done?

document.process!
document.computation.reset_queue
document.computation.reset_executions
document.rows.delete_all

ACSV::CSV.foreach(file, headers: true).with_index(2) do |row, line|
  document.rows.find_or_initialize_by(
    document_id: document.id,
    document_line: line
  ).tap do |doc_row|
    doc_row.assign_attributes(...)
    doc_row.save
  end
end

row_ids = document.rows.pluck(:id)
document.computation.increment_queue(by: row_ids.count)
Sidekiq::Client.push_bulk('class' => Consumer, 'args' => row_ids.zip)
```

### Finalizer (Batch Delete)
```ruby
if document.final?
  ids = document.rows.limit(ApplicationRecord::CLEANUP_BATCH_SIZE).ids
  DocumentRow.where(id: ids).delete_all if ids.any?
  Finalizer.perform_async(document_id) if ids.size == ApplicationRecord::CLEANUP_BATCH_SIZE
else
  document.records.any? ? document.finish! : document.error!
  Finalizer.perform_async(document_id)
end
```

---

**Status:** READY FOR IMPLEMENTATION
