-- =============================================================================
-- COLOMBIA SIMPLEX SOURCE VALIDATION — ROUND 1 (METADATA ONLY)
-- =============================================================================
-- Purpose: validate the Simplex Colombia source BEFORE configuring
--          appsettings.json or running the .NET ETL.
--
-- IMPORTANT — this is Round 1. Every query in this file touches ONLY system
-- catalogs (sys.*, information_schema.*) or metadata functions
-- (fn_my_permissions). NO query reads from vDatosTotal or
-- CA_Asignacion_Empleados. Cost on the customer DB is effectively zero —
-- these all hit in-memory catalog pages.
--
-- Round 2 (data queries — empresa_codigo / volume / responsable scan / root
-- admin candidates) will be authored AFTER we read the index list produced
-- by Block 4 below. Without knowing the indexes, any JOIN on these views is
-- a coin flip between "instant" and "table scan on a multi-million-row
-- denormalized view".
--
-- Target DB: CO_4Shark_DB_SIMPLEX (or equivalent — confirm name in Block 1)
-- Connect as: 4Shark user
--
-- How to run: open in SSMS or feed to sqlcmd. Run block by block, top to
--             bottom. Each block is independent. Capture the output of every
--             block and bring it back so we can author Round 2.
--
-- Reference: ANALYSIS.md and PLAN.md (Phase 16 source-data investigation)
--            for Mexico used "4 indexed queries" — we replicate the same
--            discipline here.
-- =============================================================================


-- =============================================================================
-- BLOCK 1 — Connectivity + identity
-- =============================================================================
-- Confirms server, database, and login. If any field is wrong, stop here.

SELECT
    @@VERSION                AS sql_server_version,
    @@SERVERNAME             AS server_name,
    DB_NAME()                AS current_database,
    SUSER_SNAME()            AS current_login,
    USER_NAME()              AS current_user_name,
    SYSDATETIMEOFFSET()      AS server_time;


-- =============================================================================
-- BLOCK 2 — Database-level permissions for the 4Shark user
-- =============================================================================
-- Mexico baseline: CONNECT + db_datareader + EXECUTE/VIEW DEFINITION on
-- sp_reporte_jeraquia_4shark. Missing in Mexico: CREATE PROCEDURE +
-- ALTER ON SCHEMA::dbo (needed to upload sp_reporte_cesados_4shark). Same
-- check applies to Colombia.

-- 2.a — Database-scope permissions
-- fn_my_permissions returns: entity_name, subentity_name, permission_name only
SELECT
    permission_name,
    subentity_name
FROM fn_my_permissions(NULL, 'DATABASE')
ORDER BY permission_name;

-- 2.b — Role memberships (filter by USER_ID() — the DB-level principal id
-- of the current user; SUSER_SNAME() is the server login and may not match
-- the DB user name, which produced a false-empty result in earlier draft)
SELECT
    database_role.name        AS role_name,
    database_principal.name   AS member_name
FROM sys.database_role_members AS members
JOIN sys.database_principals   AS database_role
    ON members.role_principal_id = database_role.principal_id
JOIN sys.database_principals   AS database_principal
    ON members.member_principal_id = database_principal.principal_id
WHERE database_principal.principal_id = USER_ID();

-- 2.c — Object-level permissions on sp_reporte_jeraquia_4shark (if it exists).
-- Returns 0 rows if the SP does not exist or 4Shark has no rights on it.
SELECT
    permission_name,
    subentity_name
FROM fn_my_permissions('sp_reporte_jeraquia_4shark', 'OBJECT');

-- 2.d — Object-level permissions on the tables/views we need to read
SELECT 'vDatosTotal'              AS object_name, permission_name FROM fn_my_permissions('vDatosTotal', 'OBJECT')
UNION ALL
SELECT 'CA_Asignacion_Empleados', permission_name FROM fn_my_permissions('CA_Asignacion_Empleados', 'OBJECT')
ORDER BY object_name, permission_name;


-- =============================================================================
-- BLOCK 3 — Object inventory (procedures, views, tables)
-- =============================================================================
-- Reports PRESENT / MISSING for every object the .NET ETL depends on.

-- 3.a — Stored procedures
SELECT
    expected.expected_object,
    status = CASE WHEN source_object.name IS NULL THEN 'MISSING' ELSE 'PRESENT' END,
    source_object.create_date,
    source_object.modify_date
FROM (
    VALUES
        ('sp_reporte_jeraquia_4shark'),
        ('sp_reporte_cesados_4shark')
) AS expected(expected_object)
LEFT JOIN sys.objects AS source_object
    ON source_object.name = expected.expected_object
   AND source_object.type = 'P'
ORDER BY expected.expected_object;

-- 3.b — Views
SELECT
    expected.expected_object,
    status = CASE WHEN view_object.name IS NULL THEN 'MISSING' ELSE 'PRESENT' END,
    view_object.create_date,
    view_object.modify_date
FROM (
    VALUES
        ('vDatosTotal'),
        ('vw_empresa_area_codigo_jeraquia')
) AS expected(expected_object)
LEFT JOIN sys.views AS view_object
    ON view_object.name = expected.expected_object
ORDER BY expected.expected_object;

-- 3.c — Tables
SELECT
    expected.expected_object,
    status = CASE WHEN table_object.name IS NULL THEN 'MISSING' ELSE 'PRESENT' END,
    table_object.create_date,
    table_object.modify_date
FROM (
    VALUES
        ('CA_Asignacion_Empleados')
) AS expected(expected_object)
LEFT JOIN sys.tables AS table_object
    ON table_object.name = expected.expected_object
ORDER BY expected.expected_object;


-- =============================================================================
-- BLOCK 4 — Indexes on CA_Asignacion_Empleados + base tables of vDatosTotal
-- =============================================================================
-- Round 2's JOINs will be designed around what this block returns. Without
-- knowing which columns are indexed, any data query is a gamble.
--
-- vDatosTotal is a denormalized view; indexes live on its base tables
-- (4.b lists them). 4.a targets CA_Asignacion_Empleados directly.

-- 4.a — Indexes on CA_Asignacion_Empleados — one row per (index, column).
-- Read the output by grouping rows that share index_name: that's the index's
-- column list, in key_ordinal order.
SELECT
    index_metadata.name           AS index_name,
    index_metadata.type_desc      AS index_type,
    index_metadata.is_unique,
    index_metadata.is_primary_key,
    column_metadata.name          AS column_name,
    index_columns.key_ordinal,
    index_columns.is_included_column
FROM sys.indexes AS index_metadata
JOIN sys.index_columns AS index_columns
    ON index_columns.object_id = index_metadata.object_id
   AND index_columns.index_id = index_metadata.index_id
JOIN sys.columns AS column_metadata
    ON column_metadata.object_id = index_columns.object_id
   AND column_metadata.column_id = index_columns.column_id
WHERE index_metadata.object_id = OBJECT_ID('CA_Asignacion_Empleados')
ORDER BY index_metadata.index_id, index_columns.key_ordinal, index_columns.index_column_id;

-- 4.b — Base tables that vDatosTotal reads from. Tells us which underlying
-- tables we will actually need indexes on (vDatosTotal is a denormalized
-- reporting view; indexes live on the tables it joins).
SELECT
    referenced_object.name        AS referenced_object,
    referenced_object.type_desc   AS referenced_type
FROM sys.sql_expression_dependencies AS dependencies
JOIN sys.objects AS referencing_object
    ON referencing_object.object_id = dependencies.referencing_id
JOIN sys.objects AS referenced_object
    ON referenced_object.object_id = dependencies.referenced_id
WHERE referencing_object.name = 'vDatosTotal'
ORDER BY referenced_object.name;


-- =============================================================================
-- BLOCK 5 — Schema (column lists) of the views and the table
-- =============================================================================
-- Tells us (a) whether Colombia's columns match Mexico's, and (b) the depth
-- of vw_empresa_area_codigo_jeraquia (Mexico: nivel00 → nivel05; the .NET
-- supports up to nivel07).

-- 5.a — Columns of vDatosTotal
SELECT
    column_name,
    data_type,
    character_maximum_length,
    is_nullable,
    ordinal_position
FROM information_schema.columns
WHERE table_name = 'vDatosTotal'
ORDER BY ordinal_position;

-- 5.b — Columns of CA_Asignacion_Empleados
SELECT
    column_name,
    data_type,
    character_maximum_length,
    is_nullable,
    ordinal_position
FROM information_schema.columns
WHERE table_name = 'CA_Asignacion_Empleados'
ORDER BY ordinal_position;


-- =============================================================================
-- BLOCK 7 — Hunt for empresa_codigo and the base tables of vDatosTotal
-- =============================================================================
-- vDatosTotal is a view; its projection does not include empresa_codigo, but
-- the base tables it joins MAY have it. Three angles, all metadata-only.

-- 7.a — Definition of vDatosTotal (requires VIEW DEFINITION permission on the
-- view; may return NULL if denied). Reveals which base tables it reads and
-- which columns it projects vs hides.
SELECT definition
FROM sys.sql_modules
WHERE object_id = OBJECT_ID('vDatosTotal');

-- 7.b — Every column named like "empresa" across the whole DB. Cheap scan of
-- information_schema.columns. If empresa_codigo lives anywhere, this finds it.
SELECT
    table_schema,
    table_name,
    column_name,
    data_type
FROM information_schema.columns
WHERE column_name LIKE '%empresa%'
ORDER BY table_name, column_name;

-- 7.c — Tables/views named like "empresa" (master table, lookup, etc.)
SELECT
    name,
    type_desc,
    create_date,
    modify_date
FROM sys.objects
WHERE name LIKE '%empresa%'
  AND type IN ('U', 'V')
ORDER BY name;


-- =============================================================================
-- END OF ROUND 1
-- =============================================================================
-- Bring the output of all six blocks back. We will then author Round 2 with:
--   - empresa_codigo + volume scan (filtered by primary key if possible)
--   - responsables-without-classification (designed around the indexes found
--     in Block 4)
--   - root admin candidates (limited by TOP N and aligned with an index)
--   - optional dry-run of sp_reporte_jeraquia_4shark (separate decision)
-- =============================================================================
