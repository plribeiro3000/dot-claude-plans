# SPIKE — Auxiliary Variables: Schema and Migration Validation (M1–M4)

> Reference: `~/Projects/4Shark/dot-claude-plans/active/app/auxiliary-variables/TASKS.md` (BE-1,
> BE-9) and `PLAN.md` (Phase 1, Phase 8). Repository: `~/Projects/4Shark/app`, branch `develop`.
> Language classification: internal engineering doc → English (`LANGUAGE-POLICY.md`, category 1).

## Investigation question

Validate, step by step, the schema-and-migration work of the auxiliary-variables feature — BE-1's
three migrations (M1: `role` on `incentive_variables`; M2: `output_variable` reference on `rules`;
M3: unique index on `incentive_variables`) and BE-9's M4 (the `incentive_output_variable_binding`
permission) — against real vendor/community documentation and the actual gem/database versions
this repository runs, so the work can be broken into micro-steps and estimated. For each mechanism
the tasks rely on (`strong_migrations`, Postgres `CONCURRENTLY`, `NOT NULL DEFAULT`, `enumerize`,
the 4Shark `statement_timeout` convention): does it do what the task assumes, for *our* versions,
and what constraints come with it?

## Sources consulted

- `app/Gemfile.lock:507,715,877,904,996,1122,1190` — pins the exact versions this spike verifies
  against: `rails (8.1.3.1)`, `pg (1.6.3)`, `strong_migrations (2.7.0)`, `enumerize (2.8.1)`,
  `dentaku (3.5.7)`.
- `terraform/app-shared-001/rds.tf:86`, `app-atento-001/rds.tf:52`, `app-demo-001/rds.tf:50`,
  `app-beta-001/rds.tf:50` — the four stacks run Postgres `16.13`, `16.13`, `17.9`, `18.4`
  respectively; all are above the PostgreSQL 11 threshold this spike's findings depend on.
- `app/db/schema.rb:950-955,1951-1962` — current `incentive_variables` and `rules` table
  definitions, confirming the base shape M1–M3 build on.
- `app/db/migrate/20260722215726_add_plan_id_to_plan_statement_portable_batches.rb` — the
  `safety_assured { add_reference ... }` precedent `PLAN.md:78` cites for M2.
- `app/db/migrate/20260729113429_add_unique_index_to_user_update_document_enrollments.rb` — the
  concurrent-unique-index precedent M3 is modelled on.
- `app/db/migrate/20260729113439_user_update_document_actions.rb` — the `Action.create!` precedent
  M4 is modelled on. **Carries no `statement_timeout` method** (see Finding 6).
- `app/app/models/incentive.rb:149-175` — `Incentive#update_variables`, confirming the exact
  `incentive_variables.create(variable_id: variable.id)` call sites with no role, which is the
  premise for M1's default being load-bearing.
- `app/app/models/variable.rb:66,92-93`, `app/app/models/plan.rb:98-107` — the house `enumerize`
  pattern (`Plan#status`, quoted in full) that M1's `role` column is modelled on.
- `app/app/models/action.rb:3-15`, `app/db/schema.rb:70-78` — `Action` has no model-level
  uniqueness validation on `key`; uniqueness is enforced only by the DB unique index
  `actions_uniqueness`, confirming M4's `Action.create!` raises `ActiveRecord::RecordNotUnique` on
  a re-run precisely because there is no earlier validation to catch it.
- `~/.claude/docs/RAILS-MIGRATIONS.md` (read in full) — the 4Shark migration conventions the tasks
  cite, including the `def self.statement_timeout` convention (§ "`def self.statement_timeout` for
  per-migration timeout control", lines 139–188).
- `strong_migrations` gem source, installed version 2.7.0 (matching the lockfile), read directly
  from `~/.rvm/gems/ruby-4.0.5@four_shark/gems/strong_migrations-2.7.0/lib/`:
  - `strong_migrations/checker.rb` (whole file, 298 lines) — see auxiliary
    `auxvar-migrations_excerpt_1.rb`.
  - `strong_migrations/checks.rb:167-248` (`#check_add_reference`) — see auxiliary
    `auxvar-migrations_excerpt_2.rb`.
  - `strong_migrations/checks.rb:30-70` (`#check_add_column`).
  - `strong_migrations/error_messages.rb:142-151` (the gem's own generated remediation for a
    flagged `add_reference`).
- [strong_migrations README (GitHub, `ankane/strong_migrations`, branch `master`)](https://raw.githubusercontent.com/ankane/strong_migrations/master/README.md)
  — fetched directly; confirms the gem documents only a *global* `StrongMigrations.statement_timeout`
  initializer setting, no per-migration class method.
- `activerecord` gem source, installed version 8.1.3 (matching the lockfile):
  - `connection_adapters/abstract/schema_statements.rb:1055-1097` (`#add_reference` doc comment +
    method body) — see auxiliary `auxvar-migrations_excerpt_3.rb`.
  - `connection_adapters/abstract/schema_definitions.rb:202-305` (`ReferenceDefinition`,
    `#foreign_table_name`) — see auxiliary `auxvar-migrations_excerpt_3.rb`.
- [PostgreSQL 16 docs — `CREATE INDEX`](https://www.postgresql.org/docs/16/sql-createindex.html) —
  fetched directly; `CONCURRENTLY` transaction-block and `INVALID`-index failure behaviour.
- [PostgreSQL 16 docs — `ALTER TABLE`](https://www.postgresql.org/docs/16/sql-altertable.html) —
  fetched directly; `ADD COLUMN ... DEFAULT` metadata-only behaviour, `SET NOT NULL` table-scan
  behaviour.
- [PostgreSQL 11 release notes](https://www.postgresql.org/docs/11/release-11.html) — fetched
  directly; the exact release note that introduced the metadata-only `ADD COLUMN` default.
- [PostgreSQL current docs — Constraints §5.5.5 Foreign Keys](https://www.postgresql.org/docs/current/ddl-constraints.html)
  — fetched directly; confirms a nullable FK column's `NULL` values are not checked against the
  referenced table, which is the premise for M2 needing no follow-up `validate_foreign_key`.
- [enumerize README (GitHub, `brainspec/enumerize`, branch `master`)](https://raw.githubusercontent.com/brainspec/enumerize/master/README.md)
  — fetched directly; confirms the symbol↔integer storage mapping and that `:default` is a
  Ruby-level (not DB-level) concept.
- `app/config/initializers/strong_migrations.rb` — the app's own initializer sets only
  `StrongMigrations.auto_analyze = true`; it does **not** set `StrongMigrations.statement_timeout`.
- Repo-wide `grep` across `app/lib`, `app/config`, `app/.github/workflows` for `statement_timeout`
  and `MIGRATION_` — no wiring found anywhere outside the migration files themselves and the
  unrelated `pg_statement_timeout` / `MIGRATION_DATABASE_URL` / `MIGRATION_SERVICE_NAME` names.
- See auxiliary: `auxvar-migrations_excerpt_1.rb` — full `strong_migrations/checker.rb`, the only
  place any "statement_timeout" concept is applied during a migration run.
- See auxiliary: `auxvar-migrations_excerpt_2.rb` — `#check_add_reference` plus the gem's own
  generated remediation text for a flagged `add_reference`.
- See auxiliary: `auxvar-migrations_excerpt_3.rb` — `add_reference`'s doc comment and
  `ReferenceDefinition#foreign_table_name`, showing the default-target-table inference.

## Findings

### Finding 1: M1's DB-level default reasoning is sound, and the old-code call sites are confirmed

**Evidence:**

```ruby
# app/app/models/incentive.rb:149-175 (Incentive#update_variables)
def update_variables
  incentive_variables.delete_all

  if company.easy?
    company.variables.easy.enabled.each do |variable|
      next if variable.key == 'deals'
      incentive_variables.create(variable_id: variable.id) if rules.pluck(:value).map(&:downcase).grep(variable.key_regex).any?
    end
  elsif deal?
    ...
```

**Source:** `app/app/models/incentive.rb:149-175`, read directly.

**Significance:** every branch of `update_variables` calls `incentive_variables.create(variable_id:
variable.id)` (or `find_or_create_by`) with no `role` argument. During the deploy window this method
runs on the *old* `IncentiveVariable` model class (no `enumerize :role` declaration, because the
class is loaded from the pre-deploy code still in memory on containers that have not yet been
replaced). An `enumerize`-level default therefore cannot apply to that INSERT — only a database
column default can. This is exactly what `PLAN.md:77` and `TASKS.md:56-66` claim, and it is
confirmed against the real call sites rather than assumed.

### Finding 2: M1's constant integer default does not trigger a `strong_migrations` check — no `safety_assured` needed, and correctly so

**Evidence:**

```ruby
# strong_migrations-2.7.0/lib/strong_migrations/checks.rb:30-51 (#check_add_column)
if !default.nil? && (!adapter.add_column_default_safe? || (volatile = (postgresql? && type.to_s == "uuid" && default.to_s.include?("()") && adapter.default_volatile?(default))))
  ...
  raise_error :add_column_default, ...
```

**Source:** `strong_migrations-2.7.0/lib/strong_migrations/checks.rb:30-70`, read directly from the
installed gem (matches `Gemfile.lock:715,1190`).

**Significance:** the check only raises for a *volatile* default (e.g. `random()`, `clock_timestamp()`)
or an unsafe adapter state. A literal integer default (`default: 0`) is not volatile, and
`adapter.add_column_default_safe?` is true on PostgreSQL 11+ — confirmed for all four app stacks
(`16.13`–`18.4`, all above the threshold — see Finding 9). So `add_column :incentive_variables,
:role, :integer, default: 0, null: false` (or the equivalent inline `t.integer` shape) passes with
no `safety_assured` wrapper, matching what TASKS.md's own criteria imply (M1 is listed with no
`safety_assured` requirement, unlike M2).

### Finding 3: M2's documented safe form for `add_reference` is exactly what `strong_migrations` checks for — confirmed against the gem's own logic

**Evidence:**

```ruby
# strong_migrations-2.7.0/lib/strong_migrations/checks.rb:171-178
if postgresql?
  index_value = options.fetch(:index, true)
  concurrently_set = index_value.is_a?(Hash) && index_value[:algorithm] == :concurrently
  index_unsafe = index_value && !concurrently_set

  foreign_key_value = options[:foreign_key]
  validate_false = foreign_key_value.is_a?(Hash) && foreign_key_value[:validate] == false
  foreign_key_unsafe = foreign_key_value && !validate_false

  if index_unsafe || foreign_key_unsafe
    ...  # raises
```

**Source:** `strong_migrations-2.7.0/lib/strong_migrations/checks.rb:167-217` (full method in
auxiliary `auxvar-migrations_excerpt_2.rb`).

**Significance:** the gem raises only when `index_unsafe` (index present and not concurrently) or
`foreign_key_unsafe` (foreign key present and not `validate: false`) is true. TASKS.md's prescribed
shape — `index: { algorithm: :concurrently }` **and** `foreign_key: { validate: false }` — makes
both flags false, so `check_add_reference` falls straight through with no error and no
`safety_assured` needed. This directly confirms BE-1's claim that this is "the documented safe form
named for exactly this operation." The gem's own generated remediation text
(`error_messages.rb:142-151`, quoted in auxiliary excerpt 2) independently corroborates the same
shape: it tells an engineer who *does* trigger the check to wrap the call in
`disable_ddl_transaction!` inside `def change` — the exact shape TASKS.md prescribes.

### Finding 4 (contradiction): M2's prescribed shape is missing `to_table: :variables` — as written, the migration references a table that does not exist

**Evidence:**

```ruby
# activerecord-8.1.3/.../schema_statements.rb:1091-1093 (doc comment on #add_reference)
# ====== Create a supplier_id column and a foreign key to the firms table
#
#   add_reference(:products, :supplier, foreign_key: { to_table: :firms })

# activerecord-8.1.3/.../schema_definitions.rb:300-304 (ReferenceDefinition#foreign_table_name)
def foreign_table_name
  foreign_key_options.fetch(:to_table) do
    Base.pluralize_table_names ? name.to_s.pluralize : name
  end
end
```

**Source:** `activerecord-8.1.3/lib/active_record/connection_adapters/abstract/schema_statements.rb:1091-1097`
and `schema_definitions.rb:202-305` (full excerpt in auxiliary `auxvar-migrations_excerpt_3.rb`),
read directly from the installed gem matching `Gemfile.lock:507,877,1122`.

**Significance:** `Rule#output_variable` (per `PLAN.md:81`/`TASKS.md:109`) is
`belongs_to :output_variable, class_name: 'Variable', optional: true` — the reference name
(`output_variable`) intentionally differs from its target table (`variables`), by the same
role-vs-name principle `~/.claude/docs/ASSOCIATION-NAMING.md` and `RAILS-MIGRATIONS.md:52` state for
the model side. On the migration side, `foreign_table_name` defaults to `to_table.fetch(:to_table) {
name.to_s.pluralize }` — when `foreign_key:` is `{ validate: false }` with no `:to_table` key, this
resolves to `"output_variable".pluralize` = `"output_variables"`, a table that does not exist in
this schema (`app/db/schema.rb` has no `output_variables` table; the real target is `variables`).
Rails' own doc comment shows the exact fix for this exact shape:
`add_reference(:products, :supplier, foreign_key: { to_table: :firms })`. **Neither `PLAN.md:78` nor
`TASKS.md:73-82` mentions `to_table:`** — as currently written, the safe form both documents would
raise `ActiveRecord::StatementInvalid` (relation `"output_variables"` does not exist) the moment M2
runs. The corrected shape is:

```ruby
add_reference :rules, :output_variable,
  null: true,
  index: { algorithm: :concurrently },
  foreign_key: { validate: false, to_table: :variables }
```

This is a real gap in the task list, not a style nit — the migration as documented does not run.

### Finding 5: M2's "no follow-up `validate_foreign_key`" reasoning is correct, per Postgres's own documented FK semantics

**Evidence:** *"Normally, a referencing row need not satisfy the foreign key constraint if any of
its referencing columns are null."* — [PostgreSQL docs, Constraints §5.5.5 Foreign Keys](https://www.postgresql.org/docs/current/ddl-constraints.html)

**Source:** PostgreSQL current documentation, `ddl-constraints.html`, fetched directly.

**Significance:** `add_foreign_key ..., validate: false` creates the constraint marked `NOT VALID` —
existing rows are not checked at creation time, but every row inserted or updated *after* the
constraint exists is still enforced. Since every pre-existing `rules` row will hold `NULL` in the
new `output_variable_id` column (it does not exist before M2 runs), and NULL values are exempt from
FK checking by Postgres's own rule quoted above, there are zero rows a `validate_foreign_key` pass
could find in violation — running one would be a full-table scan that changes nothing. TASKS.md's
claim ("no row can violate the constraint — there is nothing for a validation pass to check") is
correct and matches documented Postgres behaviour, not just repo convention.

### Finding 6 (contradiction, the most significant finding of this spike): `def self.statement_timeout` is not read by `strong_migrations` 2.7.0, by ActiveRecord, or by anything else in this repository

**Evidence:**

```ruby
# strong_migrations-2.7.0/lib/strong_migrations/checker.rb:190-201 (#set_timeouts, private)
def set_timeouts
  return if @timeouts_set

  if StrongMigrations.statement_timeout
    adapter.set_statement_timeout(StrongMigrations.statement_timeout)
  end
  if StrongMigrations.lock_timeout
    adapter.set_lock_timeout(StrongMigrations.lock_timeout)
  end

  @timeouts_set = true
end
```

**Source:** `strong_migrations-2.7.0/lib/strong_migrations/checker.rb:190-201` (full file in
auxiliary `auxvar-migrations_excerpt_1.rb`), read directly from the installed gem. Corroborated by:

- The [official strong_migrations README](https://raw.githubusercontent.com/ankane/strong_migrations/master/README.md),
  fetched directly, which documents only a global setting: *"Create `config/initializers/strong_migrations.rb`
  with: `StrongMigrations.lock_timeout = 10.seconds` / `StrongMigrations.statement_timeout = 1.hour`"* —
  no per-migration class method of any name is documented anywhere in the README.
- `app/config/initializers/strong_migrations.rb` — the app's own initializer sets only
  `StrongMigrations.auto_analyze = true`. It never sets `StrongMigrations.statement_timeout`, so
  even the global mechanism this method reads is inert today.
- Repo-wide search: no file under `app/lib`, `app/config`, or `app/.github/workflows` reads
  `.statement_timeout` on a migration, calls `respond_to?(:statement_timeout)`, or sets a
  `MIGRATION_<timestamp>` environment variable in CI. The only `MIGRATION_`-prefixed names that
  exist anywhere in the deploy workflows are `MIGRATION_SERVICE_NAME` and `MIGRATION_DATABASE_URL`
  (`app/.github/workflows/deploy-shared-001.yaml:72,151-152,461`), both unrelated to per-migration
  timeouts.
- `strong_migrations-2.7.0/lib/strong_migrations/checker.rb:36-121` (`#perform`) — the method that
  intercepts schema-statement calls (`case method when :add_column, :add_reference, ...`) never
  intercepts a plain ActiveRecord model call like `Action.create!`. This means a data-only migration
  such as M4 is never even routed through a check that could read a per-migration timeout, even in
  principle.

**Significance:** `~/.claude/docs/RAILS-MIGRATIONS.md:141` states *"The `strong_migrations` gem
detects this method and applies the value automatically"* — this claim does not hold for the
installed version (2.7.0, matching `Gemfile.lock:715,1190`). Every one of BE-1's three migrations
and BE-9's M4 carries an acceptance criterion requiring its own `def self.statement_timeout`, worded
as load-bearing ("M1 declares its own `def self.statement_timeout`... `set_statement_timeout(...)`
is the older convention and is deprecated"). As written and as verified against the actual code, this
method has **no observable effect** in this application today: it is not read by the gem, not read
by Rails, not read by any custom code, and the environment variable it names is never set anywhere
in the deploy pipeline. This does not mean the convention is harmful — declaring the method costs
nothing and 340 existing migrations already carry it — but the acceptance criteria's framing (that
omitting it is unsafe, or that including it changes behaviour) is not supported by evidence. It is,
today, a documentation/consistency convention, not an operational safety control.

### Finding 7: the cited precedent migration for M4 itself carries no `statement_timeout` method, consistent with Finding 6

**Evidence:**

```ruby
# app/db/migrate/20260729113439_user_update_document_actions.rb (whole file)
class UserUpdateDocumentActions < ActiveRecord::Migration[8.1]
  def up
    Action.create!(key: 'user_update_document_listing', level: 'module', resource: 'user_update_document')
    Action.create!(key: 'user_update_document_creation', level: 'module', resource: 'user_update_document')
    Action.create!(key: 'user_update_document_destruction', level: 'resource', resource: 'user_update_document')
    Action.create!(key: 'user_update_document_download', level: 'resource', resource: 'user_update_document')
  end

  def down
    Action.get(key: 'user_update_document_listing').destroy
    Action.get(key: 'user_update_document_creation').destroy
    Action.get(key: 'user_update_document_destruction').destroy
    Action.get(key: 'user_update_document_download').destroy
  end
end
```

**Source:** `app/db/migrate/20260729113439_user_update_document_actions.rb`, read in full — the
exact file `PLAN.md:268` and `TASKS.md:509` cite as M4's precedent.

**Significance:** this file has no `statement_timeout` method at all, even though every recent
DDL-bearing migration in the same batch (`20260729113332`, `20260729113408`, `20260729113420`, all
checked directly) does carry one. The difference lines up with Finding 6's operational read:
`Action.create!` is a single-row `INSERT` through ActiveRecord, wrapped in Rails' default migration
transaction, never routed through any of `strong_migrations`'s intercepted schema methods — there is
no long-running statement or lock for a timeout to bound. TASKS.md's own precedent migration
therefore does not follow the criterion TASKS.md imposes on M4. Either the precedent is
non-conformant with the convention, or the convention (as literally worded, "each migration must
declare its own") is broader than what the actual risk (and the gem's actual behaviour) calls for.

### Finding 8: `CREATE INDEX CONCURRENTLY` constraints (M2's index, M3) are as documented, with a defined recovery path

**Evidence:** *"A regular `CREATE INDEX` command can be performed within a transaction block, but
`CREATE INDEX CONCURRENTLY` cannot."* ... *"If a problem arises while scanning the table ... the
`CREATE INDEX` command will fail but leave behind an 'invalid' index ... The recommended recovery
method in such cases is to drop the index and try again to perform `CREATE INDEX CONCURRENTLY`."*

**Source:** [PostgreSQL 16 docs, `CREATE INDEX`](https://www.postgresql.org/docs/16/sql-createindex.html),
fetched directly.

**Significance:** confirms two things TASKS.md relies on without spelling out the failure mode: (1)
`disable_ddl_transaction!` is not stylistic — Postgres physically refuses `CONCURRENTLY` inside a
transaction, and Rails wraps every migration in one by default, so the combination is mandatory, not
optional (`~/.claude/scripts/validate-concurrent-index-migration.sh`, read directly, mechanically
blocks the write otherwise — confirmed this hook matches on `algorithm:\s*:concurrently` anywhere in
the new content, so it fires whether the shape is `add_index` or `t.references ..., index: {
algorithm: :concurrently }`). (2) If M2's index build or M3's unique index build fails partway
(deadlock, or — for M3 specifically — a uniqueness violation), Postgres leaves an `INVALID` index
that must be **dropped and recreated**, not repaired in place; `REINDEX INDEX CONCURRENTLY` is the
one alternative Postgres names. Neither `PLAN.md` nor `TASKS.md` states this recovery step; it should
be part of the runbook for whoever executes these migrations against a productive stack.

### Finding 9: `ADD COLUMN ... DEFAULT` is metadata-only since PostgreSQL 11, and every app stack is above that floor

**Evidence:** *"Allow `ALTER TABLE` to add a column with a non-null default without doing a table
rewrite (Andrew Dunstan, Serge Rielau). This is enabled when the default value is a constant."*

**Source:** [PostgreSQL 11 release notes](https://www.postgresql.org/docs/11/release-11.html),
§E.23.3.3 Utility Commands, fetched directly. Corroborated by [PostgreSQL 16 docs, `ALTER TABLE`](https://www.postgresql.org/docs/16/sql-altertable.html):
*"When a column is added with `ADD COLUMN` and a non-volatile `DEFAULT` is specified, the default is
evaluated at the time of the statement and the result stored in the table's metadata ... In neither
case is a rewrite of the table required."*

**Significance:** M1's whole safety argument (BE-1's "load-bearing constraint" framing) rests on
adding `role` with a default being cheap even on a large table. This is confirmed for every app
stack: `terraform/app-shared-001/rds.tf:86` → `16.13`; `app-atento-001/rds.tf:52` → `16.13`;
`app-demo-001/rds.tf:50` → `17.9`; `app-beta-001/rds.tf:50` → `18.4` — all at or above the PostgreSQL
11 floor, all four confirmed directly rather than assumed from one stack.

### Finding 10: `enumerize`'s own `:default` is a Ruby-level concept, distinct from (and irrelevant to) the DB-level default M1 needs

**Evidence:**

```ruby
# app/app/models/plan.rb:98-107 (Plan#status, the house pattern PLAN.md:361 cites)
enumerize :status,
          in: {
            initial: 0,
            final: 1,
            review: 2,
            canceled: 3,
            processing: 4,
            approving: 5
          },
          default: :initial,
          scope: true
```

*"enumerize :status, in: [:student, :employed, :retired], default: lambda { |user| ... }"* — quoted
from the [enumerize README](https://raw.githubusercontent.com/brainspec/enumerize/master/README.md),
fetched directly, showing `:default` as a value/lambda evaluated at the Ruby layer.

**Source:** `app/app/models/plan.rb:98-107`, read directly; enumerize README, fetched directly.

**Significance:** confirms Finding 1's reasoning holds even if the *new* `IncentiveVariable` model
also declares `enumerize :role, in: {...}, default: :input` for defensive symmetry with the house
pattern — that `default:` is applied by enumerize's Ruby code on an unsaved/new record missing the
attribute, and it only ever runs on model classes that have the `enumerize :role` declaration loaded.
During the deploy window the *old* code's `IncentiveVariable` class has no such declaration at all
(pre-deploy source), so enumerize's own default mechanism cannot reach it regardless of whether the
new model declares one. The DB column default is the only mechanism that reaches an INSERT issued by
code that has never heard of `enumerize`.

### Finding 11: gem and database versions, confirmed rather than assumed

| Component | Version | Source |
|---|---|---|
| Rails | `8.1.3.1` | `app/Gemfile.lock:507,1122` |
| `pg` | `1.6.3` | `app/Gemfile.lock:434-436,1089-1091` |
| `strong_migrations` | `2.7.0` | `app/Gemfile.lock:715,1190` |
| `enumerize` | `2.8.1` | `app/Gemfile.lock:217,996` |
| `dentaku` | `3.5.7` | `app/Gemfile.lock:180,986` |
| Postgres (`shared-001`) | `16.13` | `terraform/app-shared-001/rds.tf:86` |
| Postgres (`atento-001`) | `16.13` | `terraform/app-atento-001/rds.tf:52` |
| Postgres (`demo-001`) | `17.9` | `terraform/app-demo-001/rds.tf:50` |
| Postgres (`beta-001`) | `18.4` | `terraform/app-beta-001/rds.tf:50` |

**Significance:** every finding above is checked against these exact versions, not the latest
upstream release or training-data defaults. All four Postgres versions are well above the PostgreSQL
11 floor Finding 9 depends on, and `strong_migrations` 2.7.0 is the version whose source is quoted
throughout Findings 2–4 and 6.

### Finding 12: row counts for `incentive_variables` and `rules` — not found

**Evidence:** none available. `db/schema.rb` carries no row-count information (it is a schema, not
data); no committed data reference, fixture, or documentation in `app/docs/` states either table's
size; Claude Code's AWS access is read-only infrastructure access (§ Production Access,
`~/.claude/CLAUDE.md`) and does not extend to querying application database contents, so a `SELECT
count(*)` against a productive or staging database was not run.

**Significance:** this matters concretely for two steps — M2's `CREATE INDEX CONCURRENTLY` on
`rules.output_variable_id` and M3's `CREATE UNIQUE INDEX CONCURRENTLY` on
`incentive_variables (incentive_id, variable_id, role)` both scan the full table being indexed.
Whether either build takes seconds or minutes on a productive stack depends entirely on these two
tables' current row counts, which this spike could not determine. **This is a genuine open item for
the engineer** — either provide the counts, or have whoever runs the migration check
`SELECT count(*) FROM incentive_variables;` / `SELECT count(*) FROM rules;` against the target
environment before scheduling the deploy window.

## Migration-by-migration execution plan

Each step below states the exact command/code shape, what could go wrong specifically at that step
(with the evidence backing it, cross-referenced to the Findings above), how to verify success, and a
rough size signal. "Risk" is rated relative to the other steps in this same plan, not in absolute
terms — see Finding 12 for why the ratings involving table scans are qualified.

### M1 — `role` on `incentive_variables`

| # | Step | Command / shape | What could go wrong | Verify | Size |
|---|---|---|---|---|---|
| 1 | Generate | `bin/rails generate migration AddRoleToIncentiveVariables` | Hand-writing the file instead is mechanically blocked (`validate-rails-migration-creation.sh`) | Generated file has the correct `ActiveRecord::Migration[8.1]` header | Seconds |
| 2 | Fill in `add_column` with an integer, non-volatile, `null: false` default | `add_column :incentive_variables, :role, :integer, null: false, default: 0` (0 = input role, matching M1's enumerize convention) | None specific to `strong_migrations` — Finding 2 confirms a constant default never triggers `check_add_column`'s volatile-default branch | Read the generated migration back | Seconds |
| 3 | Declare `def self.statement_timeout` per convention | `ENV.fetch('MIGRATION_<M1 timestamp>', 250)` at the bottom of the class | **Finding 6: this method has no observable effect today** — declare it for consistency with the other 340 migrations, but do not treat its presence/absence as a safety property | — | Seconds |
| 4 | Run | `bin/rails db:migrate` | Per Finding 9, `ADD COLUMN ... DEFAULT` with a constant is metadata-only on Postgres 16.13–18.4 — no table rewrite regardless of `incentive_variables` row count | `db/schema.rb` shows `t.integer "role", default: 0, null: false` on `incentive_variables` | Seconds-to-low-minutes, independent of table size (Finding 9) |
| 5 | Commit migration + schema | — | A migration written but never run, or run but not committed with `schema.rb`, is not done (`RAILS-MIGRATIONS.md:11-12`) | `git status` shows both files | — |
| 6 | Functional verification | Ruby console (or a spec): `IncentiveVariable.create(incentive_id: ..., variable_id: ...)` with no `role` argument | This is the criterion that actually matters — Finding 1 confirms the reasoning, but the migration only *enables* it; nothing exercises it until the model changes land | Confirm the resulting row's `role` column reads `0` | Minutes |

**Overall risk for M1**: low. The one real dependency (Finding 9, metadata-only default) is
independently confirmed for every app stack. The declared-but-inert `statement_timeout` (Finding 6)
costs nothing to include and is worth keeping for consistency even though it has no measured effect.

### M2 — output-variable reference on `rules`

| # | Step | Command / shape | What could go wrong | Verify | Size |
|---|---|---|---|---|---|
| 1 | Generate | `bin/rails generate migration AddOutputVariableToRules` (after M1's timestamp) | — | Timestamp is later than M1's | Seconds |
| 2 | Fill in the corrected safe form | `disable_ddl_transaction!` at class level; inside `change`: `add_reference :rules, :output_variable, null: true, index: { algorithm: :concurrently }, foreign_key: { validate: false, to_table: :variables }` | **Finding 4: `to_table: :variables` is required and is missing from both `PLAN.md` and `TASKS.md`.** Without it, `add_foreign_key` targets a non-existent `output_variables` table and the migration raises `ActiveRecord::StatementInvalid` | Read the migration back and confirm `to_table: :variables` is present | Minutes to write |
| 3 | Confirm `disable_ddl_transaction!` is present | — | `validate-concurrent-index-migration.sh` mechanically blocks the write otherwise (confirmed: it matches `algorithm:\s*:concurrently` anywhere in the new content, including inside a `t.references`/`add_reference` call) | Hook does not fire | Seconds |
| 4 | Declare `def self.statement_timeout` | Same shape as M1 | Finding 6 applies identically here | — | Seconds |
| 5 | Run | `bin/rails db:migrate` | Two independent risks, both from Postgres's own documented `CONCURRENTLY` behaviour (Finding 8): (a) the concurrent index build on `rules.output_variable_id` scans the full `rules` table — cost unknown, see Finding 12; (b) if the build fails partway (deadlock, lock contention), it leaves an `INVALID` index that is **not** self-healing | `\d rules` in `psql` (or `db/schema.rb`) shows no `INVALID` marker on the new index | Depends on `rules` row count — **not measured, see Finding 12** |
| 6 | Recovery path, if step 5's index build fails | `DROP INDEX CONCURRENTLY <name>;` then retry the migration | Retrying without dropping first raises "relation already exists" (mitigated by `if_not_exists: true` on `add_index`, but `add_reference`'s generated index does not expose that flag directly — worth adding `index: { algorithm: :concurrently }` is what Rails builds; confirm behaviour on a non-productive stack first) | Re-run confirms a valid index | — |
| 7 | Verify FK is `NOT VALID`, not validated | `\d rules` shows the constraint marked `NOT VALID` | Per Finding 5, this is expected and correct — every existing row has `NULL` in the new column, which Postgres never checks against the referenced table | — | — |

**Overall risk for M2**: medium, and higher than TASKS.md's own framing suggests. The *strategy*
(concurrently, `validate: false`, no `safety_assured`) is confirmed correct by Finding 3 and Finding
5. The *exact shape written down* is incomplete (Finding 4) and would fail on first run. Table-scan
cost for the concurrent index build is unquantified (Finding 12).

### M3 — unique index on `incentive_variables (incentive_id, variable_id, role)`

| # | Step | Command / shape | What could go wrong | Verify | Size |
|---|---|---|---|---|---|
| 1 | Generate, after M1's timestamp | `bin/rails generate migration AddUniqueIndexToIncentiveVariables` | M3 reads the `role` column M1 creates — must run after M1 in the same deploy, confirmed by TASKS.md's own dependency note and by the precedent's shape | Migration timestamp after M1's | Seconds |
| 2 | Fill in, following the precedent exactly | `disable_ddl_transaction!`; `up`: `add_index :incentive_variables, %i[incentive_id variable_id role], unique: true, algorithm: :concurrently, if_not_exists: true`; `down`: mirrored `remove_index` with `if_exists: true` | Matches `db/migrate/20260729113429_add_unique_index_to_user_update_document_enrollments.rb` line for line | Diff against the precedent | Minutes |
| 3 | Declare `def self.statement_timeout` | Same shape | Finding 6 applies identically | — | Seconds |
| 4 | Run | `bin/rails db:migrate` | Same `CONCURRENTLY` risks as M2 (Finding 8): scan cost unknown (Finding 12) for the `incentive_variables` table, and a genuine duplicate `(incentive_id, variable_id, role)` triple would make the build fail with a uniqueness violation, leaving an `INVALID` index | `\d incentive_variables` shows no `INVALID` marker | Depends on `incentive_variables` row count — **not measured, see Finding 12** |
| 5 | Pre-flight check for existing duplicates (recommended, not currently in TASKS.md) | `SELECT incentive_id, variable_id, role, count(*) FROM incentive_variables GROUP BY 1,2,3 HAVING count(*) > 1;` on the target environment, run once M1 has landed and before M3 runs | TASKS.md's own reasoning ("duplicates cannot arise through the normal path" because `update_variables` always `delete_all`s first) is plausible from reading `incentive.rb`, but was not independently verified against live data — this spike has no DB access to run the query itself | Query returns zero rows | Seconds, if access is available |
| 6 | Recovery path, if step 4 fails on a duplicate | `DROP INDEX CONCURRENTLY <name>;`, resolve the duplicate data, retry | — | — | — |

**Overall risk for M3**: low-to-medium. The migration shape itself is a byte-for-byte match to an
existing, working precedent — the residual risk is entirely in Finding 12 (unknown table size) and
in the untested (though logically sound) duplicate-freedom assumption.

### M4 — `incentive_output_variable_binding` permission

| # | Step | Command / shape | What could go wrong | Verify | Size |
|---|---|---|---|---|---|
| 1 | Generate | `bin/rails generate migration IncentiveOutputVariableBindingAction` | — | — | Seconds |
| 2 | Fill in, following the precedent | `up`: `Action.create!(key: 'incentive_output_variable_binding', level: 'module', resource: 'incentive')`; `down`: `Action.get(key: 'incentive_output_variable_binding').destroy` | This is a plain ActiveRecord call, not a schema-statement `strong_migrations` intercepts (Finding 6) — no concurrency, no lock, no long scan | Diff against `db/migrate/20260729113439_user_update_document_actions.rb` | Seconds to write |
| 3 | `def self.statement_timeout`? | TASKS.md's criterion says yes; **Finding 6 and Finding 7 both show the cited precedent migration for this exact shape carries no such method, and the method would be inert even if added (nothing to bound — a single-row INSERT)** | Declaring it costs nothing, but treating its absence as a defect contradicts the precedent this task itself cites | — | — |
| 4 | Run | `bin/rails db:migrate` | `Action.create!` raises on a re-run (`ActiveRecord::RecordNotUnique`, confirmed by the DB unique index `actions_uniqueness` on `actions.key`, `db/schema.rb:77` — there is no earlier model-level uniqueness validation to catch it first, `app/app/models/action.rb:8-10`) | New `actions` row exists with the exact key | Milliseconds — single-row insert |
| 5 | Deploy-ordering constraint | M4 must land in the **same deploy** as the `MODULE_KEYS` entry in `app/workers/company/admin/processor.rb:15-52` | If the key is added to `MODULE_KEYS` without the `Action` row existing, `ACTION_KEYS.each { Action.get(key) }` (`processor.rb:77-83`) hits `Action.get` → `find_by!` (`app/app/models/application_record.rb:161-167`) and raises `RecordNotFound`, breaking the whole admin-permission-sync worker | Both changes present in the same PR diff | — |
| 6 | Post-migration | Permission granted to nobody by default (ROLLOUT-1's job, not this migration's) | — | — | — |

**Overall risk for M4**: very low mechanically (a single-row insert, milliseconds). The one real
constraint is the deploy-ordering one in step 5, which is a code-coupling risk, not a migration risk.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Keep `def self.statement_timeout` on every migration (M1–M4), as TASKS.md prescribes | Consistent with 340 existing migrations; costs nothing; if the global `StrongMigrations.statement_timeout` is ever set in the initializer, or a future gem version starts reading a per-migration override, the value is already there | Currently has zero effect (Finding 6); the acceptance criteria's framing overstates what it does, which could mislead a reviewer into thinking it is a live safety control | Findings 6, 7 |
| Drop the per-migration `statement_timeout` requirement for genuinely low-risk migrations (M4-shaped, no DDL) | Matches the actual precedent (`20260729113439` has none) and the actual risk (nothing to bound) | Breaks uniformity across the 4Shark migration convention; a future migration in the same file could add a DDL statement without anyone re-adding the timeout | Finding 7 |
| Add `to_table: :variables` to M2 as this spike found it should be | The migration runs; matches Rails' own documented pattern for a reference name that differs from its target table | None — this is a correctness gap, not a trade-off | Finding 4 |
| Run a pre-flight duplicate check before M3 (not currently in TASKS.md) | Catches a real failure mode (`CREATE UNIQUE INDEX CONCURRENTLY` failing and leaving an `INVALID` index) before it happens in production | Extra step, needs DB access this spike does not have | Finding 8, Finding 12 |

## What remains uncertain

- **Row counts for `incentive_variables` and `rules`** — not found by this spike (Finding 12); needed
  to size the risk of M2's and M3's concurrent index builds on a productive stack.
- **Whether a genuine `(incentive_id, variable_id, role)` duplicate already exists** in any
  productive `incentive_variables` table — TASKS.md's reasoning that it cannot happen was checked
  against `Incentive#update_variables`'s code path (Finding 1) but not against live data.
- **Whether `null: false` or `null: true` is intended for M1's `role` column** — neither `PLAN.md` nor
  `TASKS.md` states this explicitly; `RAILS-MIGRATIONS.md:55` requires `null:` to always be explicit.
  Given the column always has a default, `null: false` is the more natural fit, but this was not
  stated as a decision in either document.
- **Whether the `def self.statement_timeout` convention is intentionally aspirational** (e.g. built
  in anticipation of a future strong_migrations version, or a planned monkey-patch not yet written)
  or simply carried forward from a misunderstanding of what the gem does. This spike found no
  evidence either way — only that, as of `strong_migrations` 2.7.0 and the current app codebase, the
  method is inert.

## Suggested options for main and the engineer

- Option A: keep the `statement_timeout` criterion for M1–M4 exactly as written (uniformity with the
  other 340 migrations), and separately raise the Finding 6/7 contradiction as a follow-up
  documentation question for `RAILS-MIGRATIONS.md` itself — outside this feature's scope.
- Option B: correct BE-1's M2 criterion to include `to_table: :variables` before implementation
  starts, since Finding 4 shows the migration as currently documented does not run.
- Option C: add a pre-flight duplicate-check step to BE-1's M3 criteria (Finding 8), and/or request
  the actual row counts for `incentive_variables` and `rules` from whoever has DB access (Finding
  12), before scheduling the migration window on a productive stack.
- Option D: relax the `statement_timeout` requirement specifically for M4 (data-only, no DDL),
  matching its own cited precedent (Finding 7), while keeping it for M1–M3 (all of which are DDL).

(No recommendation — surface options, let main and the engineer choose.)
