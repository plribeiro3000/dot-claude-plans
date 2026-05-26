# PLAN — DealDocument: Migrate to Producer/Consumer Pattern

## Status: PLANNING

---

## Objective

Migrate DealDocument from Processor pattern to Producer/Consumer/Finalizer pattern, following EXACTLY the existing IndicatorDocument implementation.

---

## Reference: IndicatorDocument Patterns

### Producer Structure

```ruby
class IndicatorDocument < Document
  class Producer < ApplicationWorker
    sidekiq_options queue: :document_processing

    def perform(indicator_document_id)
      # 1. Load document and process
      indicator_document = IndicatorDocument.with_uncached_connection { Document.find(indicator_document_id) }
      IndicatorDocument.with_uncached_connection { indicator_document.process! }
      company = Company.with_uncached_connection { indicator_document.company }
      attachment = Attachment.with_uncached_connection { indicator_document.attachment }
      local_cached_file = attachment.local_cached_file
      column_separator = ACSV::Detect.separator(local_cached_file)

      # 2. Read CSV and create rows
      ACSV::CSV.foreach(local_cached_file, headers: true, col_sep: column_separator).with_index(2) do |row, line|
        next if row.fields.compact.empty?

        # Format-specific logic (vertical vs horizontal)
        # ...
      end

      # 3. Enqueue consumers
      indicator_document_row_ids = IndicatorDocument::Row.with_uncached_connection { indicator_document.rows.pluck(:id) }
      indicator_document.computation.increment_queue(by: indicator_document_row_ids.count)
      arguments = indicator_document_row_ids.zip
      Sidekiq::Client.push_bulk('class' => IndicatorDocument::Consumer, 'args' => arguments)

    # 4. Error handling
    rescue ArgumentError
      DocumentError.with_uncached_connection do
        indicator_document.document_errors.create(resource: 'Document', error_key: 'invalid_file')
      end
      IndicatorDocument.with_uncached_connection { indicator_document.error! }

    rescue *Document::PARSE_EXCEPTIONS => _e
      DocumentError.with_uncached_connection do
        indicator_document.document_errors.create(resource: 'Document', error_key: 'invalid_file_content')
      end
      IndicatorDocument.with_uncached_connection { indicator_document.error! }
    end
  end
end
```

**Key observations:**
- NO constants for column lists
- NO private methods in Producer
- CSV columns accessed by index: `row[0]`, `row[1]`, etc
- Dynamic columns: use `row.delete()` then `row.each_pair`
- Variable naming: `indicator_document_row_ids` (full name, not abbreviated)

### Consumer Structure

```ruby
class IndicatorDocument < Document
  class Consumer < ApplicationWorker
    sidekiq_options queue: :document_processing

    def perform(indicator_document_row_id)
      # 1. Load row and document
      indicator_document_row = IndicatorDocument::Row.with_uncached_connection { IndicatorDocument::Row.find(indicator_document_row_id) }
      indicator_document = IndicatorDocument.with_uncached_connection { indicator_document_row.indicator_document }
      company = Company.with_uncached_connection { indicator_document.company }

      # 2. Lookup IDs using private methods
      user_id = user_id(company, indicator_document_row.subsidiary_external_id, indicator_document_row.user_identifier_value)
      variable_id = variable_id(company, indicator_document_row.variable_key)
      compiled_at = parsed_date(indicator_document_row.compiled_at)
      indicator_id = indicator_id(company.id, compiled_at, user_id, variable_id)

      # 3. Find or create the business object
      indicator = ...

      # 4. Save and handle errors inline
      if indicator.errors.empty?
        Indicator::Processor.perform_async(indicator.id)
      else
        indicator.errors.details.each do |attribute, attribute_errors|
          attribute_errors.each do |error|
            DocumentError.with_uncached_connection do
              indicator_document
                .document_errors
                .create(
                  attribute_key: attribute,
                  error_constraint: error[:value].to_s,
                  error_key: error[:error],
                  line: indicator_document_row.document_line,
                  resource: 'Indicator'
                )
            end
          end
        end
      end

      # 5. Track completion
      indicator_document.computation.increment_executions
      return unless indicator_document.computation.done?
      Finalizer.perform_async(indicator_document.id)
    end

    private

    # Lookup methods with rescue → nil pattern
    def indicator_id(company_id, compiled_at, user_id, variable_id)
      Indicator.with_uncached_connection do
        Indicator.get_id(
          company_id: company_id,
          compiled_at: compiled_at,
          user_id: user_id,
          variable_id: variable_id
        )
      end
    rescue ActiveRecord::RecordNotFound
      nil
    end

    def user_id(company, subsidiary_external_id, user_identifier_value)
      if company.subsidiaries_module?
        UserIdentifier.with_uncached_connection do
          UserIdentifier.get(
            company_id: company.id,
            subsidiary_id: subsidiary_id(company.id, subsidiary_external_id),
            value: user_identifier_value
          )
          .user_id
        end
      else
        UserIdentifier.with_uncached_connection { UserIdentifier.get(company_id: company.id, value: user_identifier_value).user_id }
      end
    rescue ActiveRecord::RecordNotFound
      nil
    end

    def variable_id(company, variable_key)
      Variable.with_uncached_connection { Variable.get_id(company_id: company.id, key: variable_key) }
    rescue ActiveRecord::RecordNotFound
      nil
    end

    def subsidiary_id(company_id, external_id)
      Subsidiary.with_uncached_connection { Subsidiary.get_id(company_id: company_id, external_id: external_id) }
    rescue ActiveRecord::RecordNotFound
      nil
    end

    def parsed_date(date)
      Date.parse(date.to_s)
    rescue ArgumentError
      nil
    end
  end
end
```

**Key observations:**
- Private methods for lookups (rescue ActiveRecord::RecordNotFound → nil)
- Private methods for type conversion (parsed_date)
- Error recording INLINE in perform, not in separate methods
- Method chaining: `.user_id` on NEW LINE, aligned with the method call (not with parenthesis)

### Finalizer Structure

```ruby
class IndicatorDocument < Document
  class Finalizer < ApplicationWorker
    sidekiq_options queue: :document_processing

    def perform(indicator_document_id)
      indicator_document = IndicatorDocument.with_uncached_connection { IndicatorDocument.find(indicator_document_id) }
      IndicatorDocument::Row.with_uncached_connection { indicator_document.rows.destroy_all }

      if IndicatorDocument.with_uncached_connection { indicator_document.enrollments.any? }
        IndicatorDocument.with_uncached_connection { indicator_document.finish! }
      else
        IndicatorDocument.with_uncached_connection { indicator_document.error! }
      end
    end
  end
end
```

**Key observations:**
- Simple `destroy_all` (no batch delete in current implementation)
- Check enrollments to decide finish vs error
- NO private methods

---

## DealDocument Implementation Plan

### 1. Model: DealDocument::Row

**File:** `app/models/deal_document/row.rb`

```ruby
class DealDocument < Document
  class Row < ApplicationRecord
    belongs_to :deal_document, foreign_key: :document_id, inverse_of: :rows, optional: true

    validates :document_id, presence: true

    self.table_name = :deal_document_rows
  end
end
```

### 2. Migration: Create deal_document_rows

**Columns needed (based on DealDocument CSV format):**
- document_id (FK)
- document_line (integer)
- user_identifier_value (string)
- client_external_id (string)
- product_external_id (string)
- sold_price (decimal)
- quantity (integer)
- status_key (string)
- date (date)
- description (string)
- external_id (string)
- deal_type (string)
- originated_at (date)
- installment (integer)
- work_hours (decimal)
- subsidiary_external_id (string)
- fields (jsonb) - for dynamic variables

**Unique index:** `[document_id, document_line]`

### 3. Producer

**File:** `app/workers/deal_document/producer.rb`

Following IndicatorDocument pattern:
- NO constants
- NO private methods
- Read CSV columns by index: `row[0]`, `row[1]`, etc
- For dynamic fields: use `row.each_pair` after reading static columns
- Error handling: ArgumentError → invalid_file, PARSE_EXCEPTIONS → invalid_file_content

### 4. Consumer

**File:** `app/workers/deal_document/consumer.rb`

Following IndicatorDocument pattern:
- Private methods for lookups: `user_id`, `subsidiary_id`, `client_id`, `product_id`, `status_id`, `variable_id`
- Private method for date parsing: `parsed_date`
- Error recording INLINE
- Method chaining: `.user_id` on new line, aligned with method call

### 5. Finalizer

**File:** `app/workers/deal_document/finalizer.rb`

Following IndicatorDocument pattern:
- destroy_all rows
- Check `deals.any? || deal_fields.any?` to decide finish vs error

### 6. Update GraphQL Mutation

**File:** `app/graphql_mutations/create_deal_document_attachment_graphql_mutation.rb`

Change from `Processor.perform_async` to `Producer.perform_async`

### 7. Delete Processor

**File to delete:** `app/workers/deal_document/processor.rb`

---

## Code Style Rules (from IndicatorDocument)

1. **NO constants for column lists** - read directly from row
2. **NO variables for column lists** - read directly from row
3. **Producer has NO private methods** - everything inline
4. **Consumer HAS private methods** - for lookups and conversions
5. **Error recording is INLINE** - not in separate methods
6. **Method chaining on new line:**
   ```ruby
   UserIdentifier.get(
     company_id: company.id,
     subsidiary_id: subsidiary_id(company.id, subsidiary_external_id),
     value: user_identifier_value
   )
   .user_id  # ← NEW LINE, aligned with UserIdentifier
   ```
7. **Variable naming:** Full names like `deal_document_row_ids`, not `row_ids`

---

## Changelog Entry

```markdown
### Added
- Deal document parallel processing
```

---

## Files to Create/Modify

| Action | File |
|--------|------|
| CREATE | `app/models/deal_document/row.rb` |
| CREATE | `app/workers/deal_document/producer.rb` |
| CREATE | `app/workers/deal_document/consumer.rb` |
| CREATE | `app/workers/deal_document/finalizer.rb` |
| CREATE | `db/migrate/TIMESTAMP_create_deal_document_rows.rb` |
| CREATE | `db/migrate/TIMESTAMP_add_unique_index_to_deal_document_rows.rb` |
| CREATE | `spec/models/deal_document/row_spec.rb` |
| MODIFY | `app/models/deal_document.rb` (add has_many :rows) |
| MODIFY | `app/graphql_mutations/create_deal_document_attachment_graphql_mutation.rb` |
| DELETE | `app/workers/deal_document/processor.rb` |
| MODIFY | `CHANGELOG.md` |
