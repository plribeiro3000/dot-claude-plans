# Source: /Users/plribeiro3000/.rvm/gems/ruby-4.0.5@four_shark/gems/activerecord-8.1.3/lib/active_record/connection_adapters/abstract/schema_definitions.rb
# Gem version installed and locked: rails (8.1.3.1) — see app/Gemfile.lock:507,877,1122
# Excerpt A: the doc comment on #add_reference (lines 1087-1097 of schema_statements.rb, same gem)
# showing the documented syntax for a reference whose name differs from its target table.
# Excerpt B: ReferenceDefinition (lines 202-305 of schema_definitions.rb) — the class that
# actually builds the foreign key when add_reference is called, showing how the target table
# name defaults when foreign_key: is a Hash with no :to_table key.

# --- Excerpt A: schema_statements.rb:1087-1097 (doc comment + method) ---
#
#       # ====== Create a supplier_id column and appropriate foreign key
#       #
#       #   add_reference(:products, :supplier, foreign_key: true)
#       #
#       # ====== Create a supplier_id column and a foreign key to the firms table
#       #
#       #   add_reference(:products, :supplier, foreign_key: { to_table: :firms })
#       #
#       def add_reference(table_name, ref_name, **options)
#         ReferenceDefinition.new(ref_name, **options).add(table_name, self)
#       end
#       alias :add_belongs_to :add_reference

# --- Excerpt B: schema_definitions.rb:202-305 ---

class ReferenceDefinition # :nodoc:
  def initialize(
    name,
    polymorphic: false,
    index: true,
    foreign_key: false,
    type: :bigint,
    **options
  )
    @name = name
    @polymorphic = polymorphic
    @index = index
    @foreign_key = foreign_key
    @type = type
    @options = options

    if polymorphic && foreign_key
      raise ArgumentError, "Cannot add a foreign key to a polymorphic relation"
    end
  end

  def add(table_name, connection)
    columns.each do |name, type, options|
      connection.add_column(table_name, name, type, **options)
    end

    if index
      connection.add_index(table_name, column_names, **index_options(table_name))
    end

    if foreign_key
      connection.add_foreign_key(table_name, foreign_table_name, **foreign_key_options)
    end
  end

  # add_to omitted — same shape as #add, used by create_table block form

  private
    attr_reader :name, :polymorphic, :index, :foreign_key, :type, :options

    def as_options(value)
      value.is_a?(Hash) ? value : {}
    end

    def conditional_options
      options.slice(:if_exists, :if_not_exists)
    end

    # index_options / polymorphic_options omitted — not relevant to the to_table question

    def foreign_key_options
      as_options(foreign_key).merge(column: column_name, **conditional_options)
    end

    def columns
      result = [[column_name, type, options]]
      if polymorphic
        result.unshift(["#{name}_type", :string, polymorphic_options])
      end
      result
    end

    def column_name
      "#{name}_id"
    end

    # THE DEFAULT-TARGET-TABLE LOGIC.
    # foreign_key_options is `as_options(foreign_key).merge(...)` — when foreign_key is
    # `{ validate: false }` (a Hash with no :to_table key), `.fetch(:to_table)` falls
    # through to the block, which pluralizes the REFERENCE NAME ITSELF (`name`), not the
    # eventual target table. For `add_reference :rules, :output_variable, foreign_key: { validate: false }`,
    # this resolves to "output_variables" — a table that does not exist in this schema
    # (the actual target is `variables`). Passing `foreign_key: { validate: false, to_table: :variables }`
    # is required to reference the correct table.
    def foreign_table_name
      foreign_key_options.fetch(:to_table) do
        Base.pluralize_table_names ? name.to_s.pluralize : name
      end
    end
end
