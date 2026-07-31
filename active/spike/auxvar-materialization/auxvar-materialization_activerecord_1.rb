# Auxiliary file — verbatim excerpt of ActiveRecord 8.1.3's own upsert/insert doc comments
#
# Source: app/vendor/bundle/ruby/4.0.0/gems/activerecord-8.1.3/lib/active_record/relation.rb:658-934
# Copied verbatim (comments + method signatures only) because the spike's claim about
# callback/validation bypass rests on this exact text, not on a paraphrase or on training-data
# memory of what upsert_all does in some other Rails version.

# Inserts a single record into the database in a single SQL INSERT
# statement. It does not instantiate any models nor does it trigger
# Active Record callbacks or validations. Though passed values
# go through Active Record's type casting and serialization.
#
# See #insert_all for documentation.
def insert(attributes, returning: nil, unique_by: nil, record_timestamps: nil)
  insert_all([ attributes ], returning: returning, unique_by: unique_by, record_timestamps: record_timestamps)
end

# Inserts multiple records into the database in a single SQL INSERT
# statement. It does not instantiate any models nor does it trigger
# Active Record callbacks or validations. Though passed values
# go through Active Record's type casting and serialization.
#
# ...
#
# [:unique_by]
#   (PostgreSQL and SQLite only) By default rows are considered to be unique
#   by every unique index on the table. Any duplicate rows are skipped.
#
#   To skip rows according to just one unique index pass :unique_by.
#
#   Consider a Book model where no duplicate ISBNs make sense, but if any
#   row has an existing id, or is not unique by another unique index,
#   ActiveRecord::RecordNotUnique is raised.
#
#   Unique indexes can be identified by columns or name:
#
#     unique_by: :isbn
#     unique_by: %i[ author_id name ]
#     unique_by: :index_books_on_isbn
#
# Because it relies on the index information from the database
# :unique_by is recommended to be paired with
# Active Record's schema_cache.
def insert_all(attributes, returning: nil, unique_by: nil, record_timestamps: nil)
  InsertAll.execute(self, attributes, on_duplicate: :skip, returning: returning, unique_by: unique_by, record_timestamps: record_timestamps)
end

# Updates or inserts (upserts) a single record into the database in a
# single SQL INSERT statement. It does not instantiate any models nor does
# it trigger Active Record callbacks or validations. Though passed values
# go through Active Record's type casting and serialization.
#
# See #upsert_all for documentation.
def upsert(attributes, **kwargs)
  upsert_all([ attributes ], **kwargs)
end

# Updates or inserts (upserts) multiple records into the database in a
# single SQL INSERT statement. It does not instantiate any models nor does
# it trigger Active Record callbacks or validations. Though passed values
# go through Active Record's type casting and serialization.
#
# ...
#
# By default, +upsert_all+ will update all the columns that can be updated when
# there is a conflict. These are all the columns except primary keys, read-only
# columns, and columns covered by the optional +unique_by+.
#
# ...
#
# [:on_duplicate]
#   Configure the behavior that will be used in case of conflict. Use `:skip`
#   to ignore any conflicts or provide a safe SQL fragment wrapped with
#   `Arel.sql`.
#
#   NOTE: If you use this option you must provide all the columns you want to update
#   by yourself.
#
#   Example:
#
#     Commodity.upsert_all(
#       [
#         { id: 2, name: "Copper", price: 4.84 },
#         { id: 4, name: "Gold", price: 1380.87 },
#         { id: 6, name: "Aluminium", price: 0.35 }
#       ],
#       on_duplicate: Arel.sql("price = GREATEST(commodities.price, EXCLUDED.price)")
#     )
#
#   See the related +:update_only+ option. Both options can't be used at the same time.
def upsert_all(attributes, on_duplicate: :update, update_only: nil, returning: nil, unique_by: nil, record_timestamps: nil)
  InsertAll.execute(self, attributes, on_duplicate: on_duplicate, update_only: update_only, returning: returning, unique_by: unique_by, record_timestamps: record_timestamps)
end
