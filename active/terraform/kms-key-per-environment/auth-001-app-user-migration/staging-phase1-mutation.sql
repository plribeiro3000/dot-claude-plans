-- =============================================================================
-- Effort 1 (staging) — dedicated least-privilege user for keycloak_staging.
--
-- Target: the `keycloak_staging` database on the SAME auth-001 RDS instance,
-- connected as `postgres`. Structure is identical to production's `keycloak`
-- today (same tables in `public`, owned by `postgres`), but staging is where a
-- new image is tested, so its schema CAN diverge from prod — the transfer below
-- is self-scoping (a loop over public + postgres-owned relations) so it is
-- correct whatever staging actually holds. The pre-flight SELECT shows exactly
-- what it will touch before you run it.
--
-- ROLE: generate an opaque name + strong password, DIFFERENT from the production
--       role (the whole point is isolation — a staging leak must not reach prod).
--       Replace __STAGING_ROLE__ (every occurrence) and __STAGING_PASSWORD__.
--       Create it QUOTED, so the case is preserved; every SQL reference must quote it.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- SECTION A — as `postgres` on keycloak_staging: create the role + baseline grants.
-- LOGIN only; no superuser/createdb/createrole; not a member of rds_superuser.
-- -----------------------------------------------------------------------------
BEGIN;

CREATE ROLE "__STAGING_ROLE__" WITH LOGIN PASSWORD '__STAGING_PASSWORD__';

GRANT CONNECT ON DATABASE keycloak_staging TO "__STAGING_ROLE__";
GRANT USAGE, CREATE ON SCHEMA public TO "__STAGING_ROLE__";

-- postgres must be a member of the target role to run the ownership transfer,
-- and this membership is the rollback path — keep it until staging is confirmed.
GRANT "__STAGING_ROLE__" TO postgres;

COMMIT;


-- -----------------------------------------------------------------------------
-- SECTION B — as `__STAGING_ROLE__` (NEW connection to keycloak_staging): probe.
-- Prove CREATE + ALTER + DROP work under the new role before touching real tables.
-- -----------------------------------------------------------------------------
-- CREATE TABLE public._kc_probe (id int);
-- ALTER TABLE public._kc_probe ADD COLUMN note text;
-- ALTER TABLE public._kc_probe DROP COLUMN note;
-- DROP TABLE public._kc_probe;


-- -----------------------------------------------------------------------------
-- PRE-FLIGHT — as `postgres`: review EXACTLY what SECTION C will transfer.
-- These are the public relations still owned by postgres; SECTION C moves this set.
-- -----------------------------------------------------------------------------
SELECT n.nspname AS schema, c.relkind, c.relname
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND pg_get_userbyid(c.relowner) = 'postgres'
  AND c.relkind IN ('r','p','S','v','m')
ORDER BY c.relkind, c.relname;


-- -----------------------------------------------------------------------------
-- SECTION C — as `postgres`: transfer ownership of the public + postgres-owned
-- relations to the staging role, object by object, scoped to `public` (NOT
-- REASSIGN OWNED — that is database-wide + shared objects). Wrapped in one
-- transaction: all-or-nothing.
-- -----------------------------------------------------------------------------
BEGIN;

DO $$
DECLARE relation record;
BEGIN
  FOR relation IN
    SELECT n.nspname AS schema_name, c.relname AS object_name, c.relkind AS object_kind
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND pg_get_userbyid(c.relowner) = 'postgres'
      AND c.relkind IN ('r','p','S','v','m')
  LOOP
    IF relation.object_kind = 'S' THEN
      EXECUTE format('ALTER SEQUENCE %I.%I OWNER TO %I',
                     relation.schema_name, relation.object_name, '__STAGING_ROLE__');
    ELSE
      EXECUTE format('ALTER TABLE %I.%I OWNER TO %I',
                     relation.schema_name, relation.object_name, '__STAGING_ROLE__');
    END IF;
  END LOOP;
END $$;

COMMIT;


-- -----------------------------------------------------------------------------
-- VERIFICATION — as `postgres`: everything in public now owned by the staging
-- role, nothing left on postgres.
-- -----------------------------------------------------------------------------
SELECT pg_get_userbyid(c.relowner) AS owner, count(*)
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind IN ('r','p','S','v','m')
GROUP BY owner;
