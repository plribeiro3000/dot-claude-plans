-- VKPI source structure capture — SQL Server catalog queries
--
-- Run these against any Atento VKPI database to produce a structure dump
-- comparable line by line with vkpi-schema-2026-08-03.txt (Colombia).
-- Run each one separately and keep the results in order.
--
-- Scope: STRUCTURE only. No data queries — sample rows on these servers
-- prove nothing about production.

-- QUERY 0 — SERVER AND DATABASE IDENTITY (for the dump header)
SELECT @@SERVERNAME AS server_name, DB_NAME() AS database_name, @@VERSION AS sql_server_version;

-- QUERY 1 — TABLES AND VIEWS
SELECT table_schema, table_name, table_type
FROM INFORMATION_SCHEMA.TABLES
ORDER BY table_schema, table_name;

-- QUERY 2 — COLUMNS
SELECT table_schema,
       table_name,
       ordinal_position AS position,
       column_name,
       data_type,
       character_maximum_length AS max_length,
       numeric_precision,
       numeric_scale,
       is_nullable,
       column_default
FROM INFORMATION_SCHEMA.COLUMNS
ORDER BY table_schema, table_name, ordinal_position;

-- QUERY 3 — INDEXES, PRIMARY KEYS, UNIQUE CONSTRAINTS
SELECT SCHEMA_NAME(tables.schema_id) AS table_schema,
       tables.name AS table_name,
       indexes.name AS index_name,
       indexes.type_desc,
       indexes.is_unique,
       indexes.is_primary_key,
       indexes.is_unique_constraint,
       COL_NAME(index_columns.object_id, index_columns.column_id) AS column_name,
       index_columns.key_ordinal
FROM sys.indexes AS indexes
JOIN sys.tables AS tables
  ON tables.object_id = indexes.object_id
JOIN sys.index_columns AS index_columns
  ON index_columns.object_id = indexes.object_id
 AND index_columns.index_id = indexes.index_id
ORDER BY table_schema, table_name, index_name, index_columns.key_ordinal;

-- QUERY 4 — FOREIGN KEYS
SELECT foreign_keys.name AS constraint_name,
       OBJECT_NAME(foreign_keys.parent_object_id) AS table_name,
       COL_NAME(foreign_key_columns.parent_object_id, foreign_key_columns.parent_column_id) AS column_name,
       OBJECT_NAME(foreign_keys.referenced_object_id) AS referenced_table,
       COL_NAME(foreign_key_columns.referenced_object_id, foreign_key_columns.referenced_column_id) AS referenced_column
FROM sys.foreign_keys AS foreign_keys
JOIN sys.foreign_key_columns AS foreign_key_columns
  ON foreign_key_columns.constraint_object_id = foreign_keys.object_id
ORDER BY table_name, constraint_name;

-- QUERY 5 — ROW COUNTS
SELECT SCHEMA_NAME(tables.schema_id) AS table_schema,
       tables.name AS table_name,
       SUM(partitions.rows) AS row_count
FROM sys.tables AS tables
JOIN sys.partitions AS partitions
  ON partitions.object_id = tables.object_id
 AND partitions.index_id IN (0, 1)
GROUP BY SCHEMA_NAME(tables.schema_id), tables.name
ORDER BY table_schema, table_name;
