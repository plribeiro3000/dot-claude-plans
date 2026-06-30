# Codebase Evidence: How Style Attributes Are Consumed

## File: app/app/work_books/application_work_book/typed_cell.rb (full content)

```ruby
# frozen_string_literal: true

class ApplicationWorkBook
  class TypedCell
    attr_reader :value, :type, :style

    def initialize(variable, value, style)
      @value, @type, @style =
        case variable.data_type
        when 'NumberDataType' then [value.to_f, :float, style.table_number]
        when 'PercentDataType' then [value.to_f, :float, style.table_percent]
        when 'DateDataType' then [variable.format(value), :date, style.table_date]
        when 'BooleanDataType' then [variable.format(value), :boolean, style.table_value]
        else [variable.output(value), :string, style.table_value]
        end
    end
  end
end
```

Significance: This is the ONLY caller of `style.table_number`, `style.table_percent`, and
`style.table_date`. The `variable.data_type` returns one of the DataType class name strings
(e.g., `'NumberDataType'`, `'PercentDataType'`, `'DateDataType'`). The mapping is strictly
one-to-one between the data type class name and the style attribute name — the style names
mirror the DataType class hierarchy, not a business concept.

---

## File: app/app/work_books/application_work_book/style.rb (full content — the file under review)

```ruby
# frozen_string_literal: true

class ApplicationWorkBook
  class Style
    attr_reader :result_title, :result_value, :result, :table_title, :table_value,
                :table_number, :table_percent, :table_date

    def initialize(workbook)
      @workbook = workbook
      @styles = @workbook.styles
    end

    def add
      @result_title = @styles.add_style(sz: 10, b: true)
      @result_value = @styles.add_style(sz: 10)
      @result = [@result_title, @result_value]
      @table_title = @styles.add_style(sz: 10, b: true, border: Axlsx::STYLE_THIN_BORDER, alignment: { horizontal: :center })
      @table_value = @styles.add_style(border: Axlsx::STYLE_THIN_BORDER)
      @table_number = @styles.add_style(border: Axlsx::STYLE_THIN_BORDER, format_code: '0.00')
      @table_percent = @styles.add_style(border: Axlsx::STYLE_THIN_BORDER, format_code: '0.00\%')
      @table_date = @styles.add_style(border: Axlsx::STYLE_THIN_BORDER, format_code: 'yyyy-mm-dd')
    end
  end
end
```

What `table_number`, `table_percent`, `table_date` describe:
- `table_number` — Axlsx cell style with decimal format `'0.00'`
- `table_percent` — Axlsx cell style with percent format `'0.00\%'`
- `table_date` — Axlsx cell style with date format `'yyyy-mm-dd'`

These names describe the Excel presentation format of the value (the "how it renders"), not the
business concept stored in the cell (the "what it is").

---

## File: app/app/data_types/application_data_type.rb (domain model context)

```ruby
# frozen_string_literal: true

class ApplicationDataType
  DEAL_TYPES = %w[NumberDataType StringDataType BooleanDataType PercentDataType DurationDataType DateDataType].freeze
  INDICATOR_TYPES = %w[NumberDataType StringDataType BooleanDataType PercentDataType DurationDataType].freeze
  EASY_TYPES = %w[NumberDataType PercentDataType].freeze

  def format(value)
    value
  end

  def output(value)
    value
  end

  def number?
    instance_of?(NumberDataType)
  end

  def percent?
    instance_of?(PercentDataType)
  end

  def date?
    instance_of?(DateDataType)
  end
end
```

Significance: The domain names `number`, `percent`, and `date` already exist as DATA TYPE NAMES
in the domain model (`NumberDataType`, `PercentDataType`, `DateDataType`). The Style attributes
`table_number`, `table_percent`, `table_date` mirror the DataType class names — they name the
style after the data-type-class dimension, NOT after the business meaning of what that column
represents in a commission report (e.g., what "a number variable's measured value" means to the
business vs what format it renders in Excel).

---

## Other callers of style attributes — all use the pre-existing non-typed names

All work_sheet callers use only `@style.table_title`, `@style.table_value`, `@style.result_title`,
`@style.result_value`, `@style.result` — confirmed by grep across work_books directory:

- `group_audit_work_book/groups_work_sheet.rb:21` — `@style.table_title`
- `group_audit_work_book/groups_work_sheet.rb:33` — `@style.table_value`
- `commission_work_book/indicator_work_sheet.rb:36` — `@style.table_title`
- `commission_work_book/indicator_work_sheet.rb:53` — `@style.table_value`
- `commission_work_book/summary_work_sheet.rb:32` — `@style.result_title`
- `commission_work_book/summary_work_sheet.rb:180` — `@style.table_title`
- (and many more — all use non-typed names)

No file other than `typed_cell.rb` references `table_number`, `table_percent`, or `table_date`.
