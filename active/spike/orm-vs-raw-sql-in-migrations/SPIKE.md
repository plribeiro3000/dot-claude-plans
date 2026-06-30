# SPIKE — ORM vs Raw SQL in Rails Migrations

## Investigation question

When a Rails migration includes a data backfill — copying, transforming, or deleting rows alongside or after a schema change — should the migration use the application's ActiveRecord models (ORM-first, per the 4Shark ACTIVE-RECORD-QUERY-DISCIPLINE rule) or raw SQL? The community has a long-standing position that opposes using app models inside migrations. Does this position conflict with 4Shark's rule, and if so, how should the team resolve the tension?

The concrete trigger: `MigrateOldGroupDocumentActions` was rewritten from ORM-based data backfill (`Permission.where(action_id: old.id).find_each { |p| Permission.create!(...) }`) into raw `execute(<<~SQL INSERT INTO permissions ... SELECT ... SQL)`. The engineer considers the raw-SQL rewrite a potential violation of the ORM-first rule.

---

## Sources consulted

- [Rails Guides — Active Record Migrations](https://guides.rubyonrails.org/active_record_migrations.html) — Official guidance on `execute`, data migration caution, maintenance_tasks recommendation. See auxiliary: `orm_doc_1.txt`
- [TestDouble — Optimizing ActiveRecord Migrations](https://testdouble.com/insights/optimizing-activerecord-migrations-for-rails) — Canonical "never reference app models" source with full stub-model pattern. See auxiliary: `orm_doc_2.txt`
- [Jake Yesbeck — Avoid Models in Migrations](https://jakeyesbeck.com/2021/04/10/avoid-models-in-migrations/) — Drift scenario walkthrough; presents both stub models and raw SQL as valid fixes. See auxiliary: `orm_doc_3.txt`
- [Visuality — Rails Migrations Best Practices](https://www.visuality.pl/posts/rails-migrations-best-practices) — "Data manipulation belongs elsewhere" position; recommends after_party gem. See auxiliary: `orm_doc_4.txt`
- [Alexey Shepelev — Data Migrations in Ruby on Rails](https://alexey-shepelev.medium.com/data-migrations-in-ruby-on-rails-8ddf22f9c800) — Comparative survey with matrix; surfaces callbacks-as-side-effects concern. See auxiliary: `orm_doc_5.txt`
- [Jeff Cohen — Why Avoid ActiveRecord in data-migrate](https://medium.com/@jeffcoh23/why-you-should-avoid-activerecord-when-using-ruby-on-rails-data-migrate-gem-2651739395d9) — Raw SQL camp's argument for data-migrate gem; names audit trail gap. See auxiliary: `orm_doc_6.txt`
- [Rails Discuss — Separating Data from Schema Migrations](https://discuss.rubyonrails.org/t/in-the-need-for-separating-data-migration-from-schema-migration/70516) — DHH's canonical statement on migrations as schema-only; community consensus. See auxiliary: `orm_doc_7.txt`
- [Shopify/maintenance_tasks GitHub](https://github.com/Shopify/maintenance_tasks) — Rails Guides-recommended alternative; uses ActiveRecord, not raw SQL. See auxiliary: `orm_doc_8.txt`
- [ankane/strong_migrations GitHub](https://github.com/ankane/strong_migrations) — Safe backfill pattern (uses update_all); reset_column_information guidance; safety_assured. See auxiliary: `orm_doc_9.txt`
- [Global App Testing — Migration Tips Part 1](https://www.globalapptesting.com/engineering/database-migration-tips-in-rails-part-1) — Names stub-model benefits explicitly (drift guard + validation bypass). See auxiliary: `orm_doc_10.txt`
- [Monterail — Rails Data Migration Best Practices](https://www.monterail.com/blog/best-practices-for-ruby-on-rails-data-migrations) — "Skeleton model definitions" framing. See auxiliary: `orm_doc_11.txt`

---

## Findings

### Finding 1: The Rails Guides say "generally not advised" for data in migrations — and recommend maintenance_tasks

**Evidence:**

> "In Rails, it is generally not advised to perform data migrations using migration files."
> "Instead, consider using the maintenance_tasks gem. This gem provides a framework for creating and managing data migrations and other maintenance tasks in a way that is safe and easy to manage without interfering with schema migrations."
> "Modifying data directly in migrations should be approached with caution. Consider if this is the best approach for your use case, and be aware of potential drawbacks such as increased complexity and maintenance overhead, risks to data integrity and database portability."
> "If the helpers provided by Active Record aren't enough, you can use the execute method to execute SQL commands."

**Source:** https://guides.rubyonrails.org/active_record_migrations.html — confirmed in `orm_doc_1.txt`

**Significance:** The official guide does not say "never" and does not say "always use raw SQL." It says the practice is "generally not advised" and suggests a separate tool tier (maintenance_tasks). The guide explicitly acknowledges `execute` as a valid escape hatch. Critically, the guide does not contain any text saying "do not reference application models in migrations" — that specific guidance comes from the community, not the official guide.

URL fetched / Verbatim quote checked / Quote substring confirmed in fetched content

---

### Finding 2: DHH's authoritative position — migrations are for schema, not data

**Evidence:**

> "Migrations are meant to be temporary ways of shipping schema changes between developers and production. Not as a bootstrap method."

DHH emphasized that relying on all historical migrations is "a flawed and unsustainable approach" and recommended `db:schema:load` for bootstrapping.

**Source:** https://discuss.rubyonrails.org/t/in-the-need-for-separating-data-migration-from-schema-migration/70516 — confirmed in `orm_doc_7.txt`

**Significance:** This is the most authoritative Rails-level statement available. DHH frames the migration system as a schema-shipping tool, not a data-transformation tool. Under this framing, the ORM-vs-raw-SQL tension in migrations is secondary to a more fundamental question: whether data backfills belong in migrations at all. DHH's answer is no — data operations should run elsewhere (seeds, tasks, maintenance tasks). The Rails core team did not add native support for separate data migrations.

URL fetched / Verbatim quote checked / Quote substring confirmed in fetched content

---

### Finding 3: The "never reference app models" guidance originates from the community, not Rails core

**Evidence:**

> "never reference your application's ActiveRecord models from your migrations"
> "ActiveRecord models inherit lots of their behavior by interrogating the state of the database schema when they're first loaded."
> "we've inadvertently broken our old migration! If we were to run rake db:drop db:create db:migrate, our data migration would fail because the acts_as_paranoid gem will preclude User from being loaded when a deleted_at column doesn't exist."

**Source:** https://testdouble.com/insights/optimizing-activerecord-migrations-for-rails — confirmed in `orm_doc_2.txt`

**Significance:** The TestDouble article is the widely cited canonical source for this rule. The reasoning is model drift: a model loaded at migration runtime reflects current application code, not the code at the time the migration was written. A model that gains a new callback (`acts_as_paranoid`'s `deleted_at` requirement), a new scope, or a new `belongs_to` foreign key after the migration was written will break the migration when replayed from scratch. The specific failure mode is `db:drop db:create db:migrate` — the standard developer workflow for a clean database rebuild.

URL fetched / Verbatim quote checked / Quote substring confirmed in fetched content

---

### Finding 4: The stub-model pattern — ORM ergonomics without app-code drift

**Evidence:**

From TestDouble:
> "Define a new ActiveRecord::Base subclass that's designed to only be used for the purpose of the migration"

With example:
```ruby
class SplitUserNameFields < ActiveRecord::Migration
  class MigrationUser < ActiveRecord::Base
    self.table_name = :users
  end
  def up
    add_column :users, :first_name, :string
    add_column :users, :last_name, :string
    MigrationUser.find_each do |u|
      u.update!(
        :first_name => u.name.split(" ").first,
        :last_name => u.name.split(" ").last,
      )
    end
    remove_column :users, :name
  end
end
```

From Global App Testing:
> "First of all, it guards against the case where a model is removed from the codebase but is still being called in a migration. Secondly, it prevents validations from being run, as well as eliminates the associations overhead."

From Alexey Shepelev:
> "For these situations, there is a temporary solution that helps override the model class right in the migration. This is a duplication of knowledge and cannot be considered an exemplary solution."

**Source:** `orm_doc_2.txt` (TestDouble), `orm_doc_10.txt` (Global App Testing), `orm_doc_5.txt` (Shepelev)

**Significance:** The stub-model pattern is the community's primary reconciliation between "ORM ergonomics" and "no app-model drift." It achieves three things simultaneously: (1) drift isolation — the local class does not load app callbacks, validations, or scopes; (2) intentional bypass — because no app callbacks fire, the operation is a clean structural copy; (3) ORM-style batching — `find_each`, `update!`, `in_batches` can still be used. The Shepelev critique ("duplication of knowledge") is noted: the stub model re-defines the table name explicitly, which is maintenance overhead if the table is renamed.

URL fetched / Verbatim quote checked / Quote substring confirmed in fetched content

---

### Finding 5: The raw-SQL camp — performance, deliberateness, and drift immunity

**Evidence:**

From Jake Yesbeck:
> "Instead of Book.update_all, writing an update query in SQL and using the base ActiveRecord connection ensures this migration survives model changes like a rename."

From the Rails Discuss thread (Jason FB, nonschema_migrations gem author):
> "if you can write your migration in SQL it is typically many times faster than Ruby, so when I can I prefer writing the migration in raw SQL."

From Visuality:
> "There are valid reasons for performing uncommon operations in migrations — sometimes for performance reasons, sometimes to leverage database-specific features. One such example is executing raw SQL inside a migration."

From Jeff Cohen:
> "Writing data migrations using only SQL...bypasses the Active Record layer to communicate directly with your database."

**Source:** `orm_doc_3.txt` (Yesbeck), `orm_doc_7.txt` (Rails Discuss), `orm_doc_4.txt` (Visuality), `orm_doc_6.txt` (Cohen)

**Significance:** The raw-SQL camp's arguments are: (1) total drift immunity — SQL operates against the schema directly, with no model-load risk; (2) performance — bulk `INSERT ... SELECT ...` is orders of magnitude faster than row-by-row ActiveRecord processing for large tables; (3) deliberateness — bypassing the ORM for a structural copy operation that does not need callbacks is intentional, not accidental. The Visuality article frames raw SQL in migrations as valid for "performance reasons" or "database-specific features." None of these sources say raw SQL is the default — they present it as a valid alternative with specific strengths.

URL fetched / Verbatim quote checked / Quote substring confirmed in fetched content

---

### Finding 6: The audit trail problem when bypassing the ORM — the 4Shark-specific concern

**Evidence:**

From Jeff Cohen:
> "Gems like PaperTrail that 'plug into Active Record code' won't function when using raw SQL, leaving 'an auditing void for that record.'"

From 4Shark `ACTIVE-RECORD-QUERY-DISCIPLINE.md` (file:29–31):
> "Multi-tenant scoping (default_scope, callbacks that set tenant on create)"
> "Audit trail (paper_trail callbacks, created_by / updated_by setters)"
> "Computed associations refresh (after-save callbacks rebuilding caches)"

**Source:** `orm_doc_6.txt` (Cohen); `/Users/plribeiro3000/.claude/docs/ACTIVE-RECORD-QUERY-DISCIPLINE.md:21-31`

**Significance:** This is the critical tension point for 4Shark specifically. The 4Shark rule exists because bypass-the-ORM = bypass-the-callbacks = audit trail gap and multi-tenant scoping gap. The question a data migration author must answer is: does this operation require the callbacks to fire? For a structural copy (rename an action type, reassign FKs) where the old records will be deleted after copy — the callbacks on `Permission.create` may or may not be needed. If the migration creates records that need `paper_trail` version entries, raw SQL creates an auditing void. If the records are ephemeral or the audit trail for migration-time records is not needed, raw SQL is safe.

URL fetched / Verbatim quote checked / Quote substring confirmed in fetched content

---

### Finding 7: The data-migrate / separate-tooling camp dissolves — but does not eliminate — the tension

**Evidence:**

From data-migrate README (https://github.com/ilyakatz/data-migrate):
> "Run data migrations alongside schema migrations" using a dedicated `db/data/` directory.

From Visuality:
> "using the after_party gem ... creates a dedicated database table to track which tasks have already been executed, ensuring that no code is run more than once."

From Shopify/maintenance_tasks:
> "Maintenance tasks are collection-based tasks, usually using Active Record, that update the data in your database."
> "Maintenance tasks can be interrupted, re-enqueued and resumed without any intervention at the end of an iteration."

**Source:** `orm_doc_7.txt` (data-migrate), `orm_doc_4.txt` (Visuality/after_party), `orm_doc_8.txt` (maintenance_tasks)

**Significance:** Separate data-migration tooling (`data-migrate`, `after_party`, `maintenance_tasks`) moves data operations out of schema migrations — which resolves the table-locking and replay-from-scratch problems. However, it does NOT solve the model drift problem: a data migration in `db/data/` that uses `Permission.where(...).find_each` faces the same callback drift risk if the `Permission` model changes after the migration was written. The `maintenance_tasks` approach adds interruptibility and web UI, but also uses ActiveRecord models. Separate tooling changes WHERE the operation lives, not which layer it uses.

URL fetched / Verbatim quote checked / Quote substring confirmed in fetched content

---

### Finding 8: The "does the callback matter for THIS operation?" decision criterion

**Evidence:**

From the search results (callbacks in migrations):
> "A data migration updating 10 million rows should not trigger after_save callbacks that send emails. Always be intentional about which side effects you are bypassing."

From strong_migrations:
> "If backfilling with a method other than update_all, use User.reset_column_information to ensure the model has up-to-date column information."

From Alexey Shepelev:
> "The model may contain callbacks with side effects that the author of the migration code does not expect."

**Source:** WebSearch result; `orm_doc_9.txt` (strong_migrations); `orm_doc_5.txt` (Shepelev)

**Significance:** The community converges on a pragmatic decision test: ask whether the callbacks that would fire are necessary for the data integrity of this specific operation. A structural copy (copy FKs from old action to new action, then delete old) does not need `paper_trail` version entries for the intermediate state — the copied records will exist under the new action. An email notification callback should never fire during a backfill. A multi-tenant scoping callback that sets `company_id` on create IS relevant if the migration is creating new records. The decision is per-callback, per-operation — not a blanket policy.

URL fetched / Verbatim quote checked / Quote substring confirmed in fetched content

---

## Trade-offs surfaced

| Option | What it is | Drift protection | ORM ergonomics | Callbacks fire | Who endorses it |
|--------|-----------|------------------|----------------|----------------|-----------------|
| **A — Real app model** | `Permission.where(...).find_each` using live model | None — model drift breaks replay | Full — validations, scopes, associations | Yes — all callbacks fire (audit trail, notifications, etc.) | No mainstream community source recommends this |
| **B — Stub/local model** | `class MigrationPermission < ActiveRecord::Base; self.table_name = 'permissions'; end` inside migration | Full — isolated from app model changes | Partial — batching, find_each, update! available; no app validations/callbacks | No — only explicit callbacks defined on the stub class | TestDouble (canonical), Global App Testing, Monterail, RuboCop issue #143 |
| **C — Raw SQL via execute** | `execute(<<~SQL INSERT INTO permissions SELECT ... SQL)` | Full — no model dependency | None — pure SQL | No — bypasses ORM entirely | Jake Yesbeck (alternative), Visuality (valid for perf), Jason FB / nonschema_migrations gem author, Jeff Cohen (data-migrate context) |
| **D — Separate data-migration tooling** | `data-migrate` gem (`db/data/`), `after_party`, or Shopify `maintenance_tasks` | Partial — still uses model code; same drift risk for long-lived tasks | Full for `maintenance_tasks` (AR-based); configurable for others | Yes for maintenance_tasks; configurable for data-migrate | Rails Guides (maintenance_tasks), Visuality (after_party), MoneyForward (data-migrate) |

**Secondary dimension — where does the operation run?**

| Option | Runs inside migration transaction | Risk of table lock on large tables | Rollback possible |
|--------|----------------------------------|------------------------------------|-------------------|
| A — Real app model | Yes (unless disable_ddl_transaction!) | High (row-by-row in transaction) | Yes (manual down method) |
| B — Stub/local model | Yes (unless disable_ddl_transaction!) | Moderate (find_each batches, but inside transaction) | Yes (manual down method) |
| C — Raw SQL | Yes (unless disable_ddl_transaction!) | Low for bulk INSERT...SELECT (single DB operation) | Difficult (execute is non-reversible by default) |
| D — Separate tooling | No — runs outside migration | Low (interruptible, resumable) | Depends on tool |

---

## What remains uncertain

1. **Does the `MigrateOldGroupDocumentActions` migration create records that need `paper_trail` entries or multi-tenant callbacks to fire?** The spike cannot answer this without reading the migration and the `Permission` model's callbacks. This is the load-bearing question for the ORM-vs-raw-SQL choice in the specific case.

2. **Does 4Shark's ORM-first rule apply to migrations at all, or is the rule scoped to application-runtime queries?** The rule document (`ACTIVE-RECORD-QUERY-DISCIPLINE.md`) applies to "every query against an application database" and explicitly calls out `connection.execute` as a "hazardous shape." It was written for application code, not migrations. Whether it was intended to govern migration-time data operations is not stated and would need the engineer's clarification.

3. **Does 4Shark's existing migration tooling include `disable_ddl_transaction!` for data backfills?** Both the stub-model and raw-SQL options are safer with batching + no-DDL-transaction. If existing migrations do not use this pattern, the performance and locking risk applies equally to both options.

4. **Is replay-from-scratch tested in 4Shark CI?** The drift argument is only relevant if developers run `db:drop db:create db:migrate` or CI runs it. If `db:schema:load` is used everywhere (the DHH-endorsed approach), historical migrations never replay in full, and model drift in old migrations is never triggered.

5. **How long is the data migration expected to live in the codebase?** A migration that runs once and is never replayed has a different risk profile from one that must remain replayable forever. If 4Shark squashes migrations or discards old ones, the drift concern is moot.

---

## Suggested options for main and the engineer

- **Option A — Declare migrations out of scope for the ORM rule:** The 4Shark `ACTIVE-RECORD-QUERY-DISCIPLINE.md` rule was authored for application-runtime queries. The engineer could clarify that migrations are an exception domain governed by a separate rule — and adopt the stub-model pattern (Option B above) as the migration-specific standard. The ORM-first rule would remain unchanged for controllers, workers, and console scripts.

- **Option B — Adopt stub-model-in-migration as the team's standard for data backfills:** For any migration that needs to touch rows, define a minimal local class (`class MigrationPermission < ActiveRecord::Base; self.table_name = 'permissions'; end`) inside the migration. This gives ORM batching, avoids app-code drift, and intentionally bypasses callbacks/validations — which is the correct behavior for a structural copy. Raw SQL would remain valid for simple bulk operations where the SQL is simpler than the ORM shape.

- **Option C — Allow raw SQL in migrations with an explicit engineer decision gate:** Raw SQL in a migration is acceptable only when the engineer has explicitly answered: "no callback on this model is relevant to this operation." This mirrors the existing `ACTIVE-RECORD-QUERY-DISCIPLINE.md` "explicit engineer authorization" exception. The engineer writes a comment in the migration naming which callbacks were considered and why they are safe to skip.

- **Option D — Extract data backfills from schema migrations entirely:** Adopt `data-migrate` or `maintenance_tasks` so that any operation touching rows lives in a separate, versioned data migration. Schema migrations remain DDL-only (no data). Data migrations are authored with either stub models or raw SQL per the team's preference. This matches DHH's stated intent and the Rails Guides recommendation.
