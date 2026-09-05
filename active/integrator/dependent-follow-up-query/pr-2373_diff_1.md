<!-- Auxiliary file for PLAN-SPIKE.md — verbatim diff of 4shark/integrator#2373, fetched via `gh pr diff 2373` on 2026-09-04. -->

# PR 4shark/integrator#2373 — full diff

Title: `fix(adapters): run the given query instead of building a table name from it`
State: OPEN
URL: https://github.com/4shark/integrator/pull/2373

Body (verbatim):

> Database-sourced streams read no records because the SQL adapters' `fetch` treated its argument as a table name and prefixed it, while every caller passes a full query. The availability probe then failed for every database stream, gating off all extraction. `fetch` now runs the given query directly. Applied identically to both the MSSQL and PostgreSQL adapters.

Diff:

```diff
diff --git a/CHANGELOG.md b/CHANGELOG.md
index 7ae08c775..710dfbc68 100644
--- a/CHANGELOG.md
+++ b/CHANGELOG.md
@@ -95,6 +95,7 @@ Entries from previous years are archived in the [changelogs](changelogs) folder.
 - Multi-stream resource producers halting the normalized flow
 - Integration report failing to render the source summary
 - Report email layout not adapting to the screen width
+- Database streams reading no records from their configured query

 ### Removed

diff --git a/app/adapters/microsoft_sql_adapter.rb b/app/adapters/microsoft_sql_adapter.rb
index dc38566a3..91d2e6126 100644
--- a/app/adapters/microsoft_sql_adapter.rb
+++ b/app/adapters/microsoft_sql_adapter.rb
@@ -83,9 +83,8 @@ def insert(collection, fields = {})
     connection[collection].insert(fields.keys, fields.values).is_a?(Integer)
   end

-  def fetch(collection, conditions = '')
-    table = ApplicationConfiguration.table_prefix + collection.to_s
-    dataset = connection[Sequel.identifier(table)].select_all(Sequel.identifier(table))
+  def fetch(query, conditions = '')
+    dataset = connection.fetch(query)
     dataset = dataset.where(conditions) if conditions.present?
     dataset.to_a
   end
diff --git a/app/adapters/postgres_sql_adapter.rb b/app/adapters/postgres_sql_adapter.rb
index 8b8f65a13..174ed5697 100644
--- a/app/adapters/postgres_sql_adapter.rb
+++ b/app/adapters/postgres_sql_adapter.rb
@@ -28,9 +28,8 @@ def insert(collection, fields = {})
     connection[collection].insert(fields.keys, fields.values).is_a?(Integer)
   end

-  def fetch(collection, conditions = '')
-    table = ApplicationConfiguration.table_prefix + collection.to_s
-    dataset = connection[Sequel.identifier(table)].select_all(Sequel.identifier(table))
+  def fetch(query, conditions = '')
+    dataset = connection.fetch(query)
     dataset = dataset.where(conditions) if conditions.present?
     dataset.to_a
   end
```

## Why this matters for the dependent-query plan

Both `MicrosoftSqlAdapter#fetch` and `PostgresSqlAdapter#fetch` are a SINGLE overloaded method serving two incompatible call shapes today:

1. **Extract path** (`app/workers/*/database_extractor_consumer.rb:14`, e.g. `app/workers/subsidiary/database_extractor_consumer.rb:14`): `connection.fetch(Sequel.lit(query))` — passes a full rendered SQL string as the first argument, no `conditions`.
2. **Transform-time enrichment path** (the ~20 call sites this feature replaces, e.g. `app/workers/hierarchy/transformer_consumer.rb:20`): `connection.fetch(:users, { id: record['user_id'] })` — passes a bare table name (a Symbol) as the first argument, plus a Sequel condition Hash as the second.

The `develop` implementation (pre-#2373) always treats the first argument as a table name (`table = ApplicationConfiguration.table_prefix + collection.to_s`) — correct for shape 2, wrong for shape 1 (a `Sequel::LiteralString` gets `.to_s`'d and re-prefixed as a nonsense "table name", producing the 0-records bug PR #2373 describes).

PR #2373 flips the method to always treat the first argument as a query to execute directly (`connection.fetch(query)`) — correct for shape 1, but it removes the table-name-lookup behavior shape 2 depends on. If PR #2373 merges as written WITHOUT the ~20 enrichment call sites also changing, every one of them breaks (`connection.fetch(:users, ...)` would attempt to execute the bare symbol `:users` as SQL text via `Sequel::Database#fetch`, which is not valid SQL).
