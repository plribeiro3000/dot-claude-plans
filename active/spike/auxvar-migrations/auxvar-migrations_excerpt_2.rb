# Source: /Users/plribeiro3000/.rvm/gems/ruby-4.0.5@four_shark/gems/strong_migrations-2.7.0/lib/strong_migrations/checks.rb
# Gem version installed and locked: strong_migrations (2.7.0) — see app/Gemfile.lock:715,1190
# Excerpt: #check_add_reference (lines 167-248 of the original file), the method that runs
# when a migration calls add_reference / add_belongs_to. This is the mechanism that decides
# whether the BE-1 M2 shape (t.references with index: { algorithm: :concurrently },
# foreign_key: { validate: false }) is accepted with no safety_assured.

def check_add_reference(method, *args)
  options = args.extract_options!
  table, reference = args

  if postgresql?
    index_value = options.fetch(:index, true)
    concurrently_set = index_value.is_a?(Hash) && index_value[:algorithm] == :concurrently
    index_unsafe = index_value && !concurrently_set

    foreign_key_value = options[:foreign_key]
    validate_false = foreign_key_value.is_a?(Hash) && foreign_key_value[:validate] == false
    foreign_key_unsafe = foreign_key_value && !validate_false

    if index_unsafe || foreign_key_unsafe
      if index_value.is_a?(Hash)
        options = options.merge(index: index_value.merge(algorithm: :concurrently))
      elsif index_value
        options = options.merge(index: {algorithm: :concurrently})
      end

      if StrongMigrations.safe_by_default
        safe_add_reference(*args, **options)
        throw :safe
      end

      if foreign_key_unsafe
        options.delete(:foreign_key)
        headline = "Adding a foreign key blocks writes on both tables."
        append = "\n\nThen add the foreign key in separate migrations."
      else
        headline = "Adding an index non-concurrently locks the table."
      end

      raise_error :add_reference,
        headline: headline,
        command: command_str(method, [table, reference, options]),
        append: append
    end
  elsif mysql? || mariadb?
    if options[:foreign_key]
      raise_error :add_reference,
        headline: "Adding a foreign key blocks writes on both tables.",
        command: command_str(method, [table, reference, options.except(:foreign_key)]),
        append: "\n\nThen add the foreign key in a separate migration."
    end
  end

  check_algorithm_option("add_reference", *args, **options)

  # not necessarily dangerous, but not necessary
  check_lock_option("add_reference", *args, **options)

  if (mysql? || mariadb?) && !new_table?(table)
    index_value = options[:index]
    copy_set = index_value.is_a?(Hash) && index_value[:algorithm] == :copy
    if copy_set
      index_value = index_value.except(:algorithm)
      if index_value.empty?
        options = options.except(:index)
      else
        options = options.merge(index: index_value)
      end
      raise_error :copy_algorithm, command: command_str("add_reference", args + [options])
    end

    if ar_version >= 8.2
      lock = index_value.is_a?(Hash) && index_value[:lock]
      if [:shared, :exclusive].include?(lock)
        index_value = index_value.except(:lock)
        if index_value.empty?
          options = options.except(:index)
        else
          options = options.merge(index: index_value)
        end
        raise_error :lock_option,
          command: command_str(method, args + [options]),
          lock_type: lock.to_s,
          lock_blocks: lock == :shared ? "reads" : "reads and writes"
      end
    end
  end
end

# ---
# Companion excerpt: the gem's own generated remediation text for a flagged add_reference
# (lib/strong_migrations/error_messages.rb:142-151). This is what the gem tells the engineer
# to write instead — it matches the BE-1/TASKS.md-documented safe form exactly (disable_ddl_transaction!
# at the class level, the offending call unchanged inside `change`).
#
#     add_reference:
#     "%{headline} Instead, use:
#
#     class %{migration_name} < ActiveRecord::Migration%{migration_suffix}
#       disable_ddl_transaction!
#
#       def change
#         %{command}
#       end
#     end",
