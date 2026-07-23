# PLAN — Effort 1: move Keycloak (auth-001) off the RDS master onto a least-privilege DB user

Part of `active/terraform/kms-key-per-environment/` (the auth surface). This is **Effort 1** of the auth
work: a security fix, done in place on the current RDS instance, decoupled from and BEFORE the RDS re-key
(Effort 2). No Terraform, no RDS replacement — SQL the engineer runs + one Secrets Manager value update +
a rolling restart.

Grounded by `active/spike/keycloak-least-privilege-db-user/SPIKE.md` (read in full). Every non-obvious step
below traces to a numbered Finding there. Do not re-derive; if a step looks wrong, check the Finding first.

## STATUS — 2026-07-22

**DB steps DONE and validated; the cutover, Phase 3, and the staging user are PENDING.** The engineer ran
Section A + the ownership transfer. The dedicated role is named **`EVKcRQtsJsyxzQDaNaphGu`** — NOT `keycloak_app`;
the engineer chose an opaque, case-preserving name, created quoted, so **every SQL reference to it MUST be
double-quoted** (`"EVKcRQtsJsyxzQDaNaphGu"`) or Postgres folds it and fails to match. Validated live: all 91
`public` tables owned by it (0 left on `postgres`); `rolsuper/rolcreatedb/rolcreaterole = false`,
`rolcanlogin = true` (least-privilege); the role is a member of nothing (not `rds_superuser`); `postgres` is a
member of the role (the rollback membership, kept until Phase 3).

**Pending:** (1) the cutover — set `auth-001-sm` `KC_DB_USERNAME`→`EVKcRQtsJsyxzQDaNaphGu` and `KC_DB_PASSWORD`→its
password, rolling-restart `auth-001`, verify clean Liquibase boot + login; (2) Phase 3 `REVOKE` after
stabilization; (3) **the staging user, a hard prerequisite for the cutover.**

**Staging coupling.** `auth-001-staging` (`modules/auth/auth_001_staging.tf`) runs on the SAME RDS instance, a
SEPARATE database `keycloak_staging`, but reads the SAME `KC_DB_USERNAME`/`KC_DB_PASSWORD` keys from the SAME
`auth-001-sm` secret as production. So the production secret cutover repoints staging too, and
`EVKcRQtsJsyxzQDaNaphGu` has CONNECT on `keycloak` only — staging (desired_count 0) breaks on its next scale-up.
**DECIDED 2026-07-22 — Option A (dedicated staging user).** Rationale (engineer): if staging leaks, it cannot
reach productive — the same isolation logic as the beta/demo role split earlier in this effort. So staging gets
its OWN dedicated least-privilege user on `keycloak_staging`, and the staging task-def reads NEW secret keys
(`KC_DB_STAGING_USERNAME`/`KC_DB_STAGING_PASSWORD`, mirroring the existing `KEYCLOAK_STAGING_ADMIN` convention) so
its credential is fully decoupled from production's `KC_DB_USERNAME`/`KC_DB_PASSWORD`. Sequence, all BEFORE the
production secret cutover: (1) create the dedicated staging role + transfer ownership of the `keycloak_staging`
objects to it (same three-script pattern, run on `keycloak_staging`); (2) add the two new keys to `auth-001-sm`
with the staging role's credentials; (3) Terraform PR on `auth_001_staging.tf` repointing the staging task-def's
`KC_DB_USERNAME`/`KC_DB_PASSWORD` `valueFrom` to the new keys — apply. This decouples staging from the shared keys,
so the production cutover then affects only production. Staging is `desired_count 0`, so it adopts the change on
its next scale-up — no rolling restart needed.

**CORRECTION 2026-07-22 — the `GRANT CONNECT` alone does NOT isolate; PUBLIC's default CONNECT must be REVOKED.**
The engineer found the staging role could connect to BOTH `keycloak` and `keycloak_staging`. Cause: PostgreSQL's
`PUBLIC` role holds `CONNECT` on every database by default, so granting a role CONNECT on its own DB does not stop
it reaching the other. This was a gap in the Effort-1 design (it covered ownership + role attributes but not the
database-level CONNECT ACL) and it applies to BOTH app roles. Required fix, run as `postgres` on both databases:
`GRANT CONNECT ON DATABASE <db> TO "<its role>";` (explicit, quoted) then `REVOKE CONNECT ON DATABASE <db> FROM
PUBLIC;`. Safe for current operations (both Keycloak envs connect as `postgres`/master today, which connects via
its own privilege, not PUBLIC). Verify by attempting a cross-connect (staging role → `keycloak` must fail; prod
role → `keycloak_staging` must fail). Prod role = `EVKcRQtsJsyxzQDaNaphGu`, staging role = `iDdssfbZVDcejjYwjpkuhBuF`.

**STAGING STATUS 2026-07-22 (CORRECTED — full isolation).** The first #809 approach (staging reading
`KC_DB_STAGING_*` keys from the SHARED `auth-001-sm` secret) was rejected by the engineer, correctly: sharing one
secret AND one task role between staging and production is not real isolation — the single shared role holds
`GetSecretValue` on the whole shared secret, so a staging task could read production's credentials and vice versa;
the `valueFrom` remap only picks which key is injected, it does not restrict access. **#809 was corrected in place**
(force-push, edit-in-place, NOT close/reopen) to full isolation: staging gets its OWN secret `auth-001-staging-sm`
and its OWN task role `auth-001-staging-ecs-task-execution-role` (scoped to read ONLY the staging secret and
decrypt only via `alias/auth-001`); the staging task-def points at both; the deploy user gains PassRole on the new
role. Secret key names go back to plain (`KC_DB_PASSWORD`/`KC_DB_USERNAME`/`KEYCLOAK_ADMIN`/`KEYCLOAK_ADMIN_PASSWORD`)
since the secret is now staging-specific. Plan: `6 add, 1 change, 1 destroy` (secret + role + policy + 2 attachments
+ task-def revision; deploy policy in-place; old task-def revision destroyed); service not in plan
(`ignore_changes = [task_definition]` + desired 0). Roles: prod `EVKcRQtsJsyxzQDaNaphGu`, staging
`iDdssfbZVDcejjYwjpkuhBuF` (both created, PUBLIC CONNECT revoked on both DBs). KMS-policy prereq PR **#807** also open.

**LESSON (do NOT re-derive):** environment isolation on a shared RDS is NOT achieved by different SECRET KEYS in a
shared secret read by a shared role — that role can read the whole secret. Real isolation = a SEPARATE secret per
environment AND a SEPARATE (or scoped) task role per environment, so the environment's role can read only its own
secret. Applies to any future staging/prod split on a shared instance.

**Ordered remaining steps (all before Effort 2):**
1. Staging DB — run `staging-phase1-mutation.sql` Section C (transfer the 91 `keycloak_staging` tables to the
   staging role) and verify; the isolation fix touched only CONNECT, not ownership.
2. Apply PR #809 — **DONE (applied 2026-07-22: `6 add, 1 change, 1 destroy`).** Created the staging secret
   `auth-001-staging-sm` (empty), the staging role + scoped policy, and repointed the task-def; deploy PassRole
   updated. Service untouched (desired 0). **PR #809 MERGED 2026-07-22** (into develop; branch + worktree cleaned up).
3. Populate `auth-001-staging-sm` with the staging credentials: `KC_DB_USERNAME` = `iDdssfbZVDcejjYwjpkuhBuF`,
   `KC_DB_PASSWORD`, `KEYCLOAK_ADMIN`, `KEYCLOAK_ADMIN_PASSWORD`. Staging adopts on next scale-up (desired 0, no restart).
4. **Production cutover** (only AFTER #809, so it affects prod alone): set `auth-001-sm`
   `KC_DB_USERNAME`/`KC_DB_PASSWORD` → the prod role's credentials, rolling-restart `auth-001`, verify clean
   Liquibase boot + login.
5. Phase 3 — after stabilization, `REVOKE <role> FROM postgres` on both roles (the rollback membership).
6. Apply PR #807 (independent; needed for Effort 2's RDS re-key).
7. Cleanup (non-blocking) — remove the now-unused `KEYCLOAK_STAGING_ADMIN`/`KEYCLOAK_STAGING_ADMIN_PASSWORD` keys
   from `auth-001-sm` once staging is confirmed running on its own secret.

## Why

Keycloak connects to its RDS PostgreSQL as the master user `postgres` (full privilege). An application
running as the database master is a security defect on its own, and it also blocks Effort 2: adopting
managed master password rotates `postgres`, which would strand Keycloak's stored credential. Fix: give
Keycloak a dedicated least-privilege login and move it onto that.

## The load-bearing facts (from the spike — do not re-litigate)

- Keycloak's docs prescribe **no** minimum privilege set (only an optional `SELECT` on `pg_class`/`pg_namespace`
  for faster upgrades — Finding 1). The least-privilege set is derived from Postgres ownership rules.
- Keycloak runs Liquibase on **every** boot, issuing `ALTER TABLE` against existing objects (Finding 2).
- `GRANT` cannot substitute for ownership — *"You must own the table to use ALTER TABLE"* (Finding 3). So the
  existing Keycloak objects (owned by `postgres` today) **must have their ownership transferred** to the new
  role, or Keycloak stops booting. This is mechanical, not hardening.
- To run `ALTER ... OWNER TO`: the executor (`postgres`) must be a **member of the new role**, and the new
  role must already hold `CREATE` on the schema — **both before** the transfer (Finding 4).
- `postgres` on RDS is `NOSUPERUSER` (Finding 8) so it gets no ownership bypass, but it has `CREATEROLE`, which
  lets it `GRANT keycloak_app TO postgres` on its own authority (Finding 9).
- **Do NOT use `REASSIGN OWNED BY postgres`** — it is database-wide + shared objects, unscopable to Keycloak,
  too broad a blast radius on a shared RDS master (Finding 7). Transfer **object by object**, scoped to the
  confirmed inventory.
- **Keep `GRANT keycloak_app TO postgres` in place through the whole cutover window** — it is the rollback
  path (after transfer, `postgres` can only administer the objects via this membership; Finding 8 + the
  transfer approach). Revoke it only after the cutover is declared stable.
- The dedicated role gets `LOGIN` and nothing else — no `SUPERUSER`/`CREATEDB`/`CREATEROLE`, not a member of
  `rds_superuser` (Finding 10).

## Scope

**Stay on the schema Keycloak uses today (confirmed `public` — no `KC_DB_SCHEMA` in the task-def).** Adopting
a dedicated `keycloak_app`-owned schema (Postgres's own secure pattern, Finding 6) is a larger change
(`KC_DB_SCHEMA` config + object relocation) beyond "migrate the app to a new user" — **deferred, explicitly
out of scope here**, revisit as a separate hardening if wanted. Ownership transfer of the existing objects is
required either way.

## Execution — three scripts (SCRIPT-DISCIPLINE), the engineer runs them; no direct DB access here

The exact `ALTER ... OWNER TO` list cannot be written until the object inventory is enumerated, so Phase 0
(Discovery, read-only) runs first and its output feeds Phase 1. All SQL runs against the `keycloak` database
connected as `postgres` (the engineer's connection path — private RDS, via VPN/bastion).

### Phase 0 — Discovery (read-only, no mutation)

Confirm the schema, enumerate every `postgres`-owned relation to transfer, and check whether `postgres` owns
anything else in the database (informs risk). Output pasted back to main to generate Phase 1's transfer
statements. SQL:

```sql
-- 0.1 Where do the Keycloak tables live, and who owns them?
SELECT schemaname, tableowner, COUNT(*)
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog','information_schema')
GROUP BY schemaname, tableowner
ORDER BY schemaname, tableowner;

-- 0.2 Full inventory of postgres-owned relations to transfer (tables r, partitioned p,
--     sequences S, views v, matviews m) outside system schemas — this list becomes the
--     per-object ALTER ... OWNER TO statements in Phase 1.
SELECT n.nspname AS schema, c.relkind, c.relname
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE pg_get_userbyid(c.relowner) = 'postgres'
  AND n.nspname NOT IN ('pg_catalog','information_schema')
  AND c.relkind IN ('r','p','S','v','m')
ORDER BY n.nspname, c.relkind, c.relname;

-- 0.3 Does postgres own anything else in this DB (other schemas / the database itself)?
--     Informs collateral risk; the object-by-object approach avoids it regardless.
SELECT 'database' AS kind, datname AS name, pg_get_userbyid(datdba) AS owner
FROM pg_database WHERE datname = current_database()
UNION ALL
SELECT 'schema', nspname, pg_get_userbyid(nspowner)
FROM pg_namespace WHERE pg_get_userbyid(nspowner) = 'postgres'
  AND nspname NOT IN ('pg_catalog','information_schema','pg_toast');

-- 0.4 Confirm postgres has CREATEROLE (needed to self-grant membership in Phase 1) and its role set.
SELECT rolname, rolsuper, rolcreatedb, rolcreaterole, rolinherit, rolcanlogin
FROM pg_roles WHERE rolname = 'postgres';

-- 0.5 Confirm the dedicated role does not already exist.
SELECT rolname FROM pg_roles WHERE rolname = 'keycloak_app';
```

**Checkpoint:** the inventory (0.2) is non-empty and includes `databasechangelog` / `databasechangeloglock`;
0.4 shows `rolcreaterole = t`; 0.5 returns no row.

**Phase 0 RESULT — 2026-07-22 (engineer ran it):** 91 tables, ALL in schema `public`, ALL owned by
`postgres`; **no sequences, views, or matviews** (Keycloak's current schema uses none). `postgres` owns the
`keycloak` database object but no non-system schema (so `public` itself is not `postgres`-owned — only its
tables are). `postgres` confirmed `rolcreaterole = true`, `rolsuper = false`. `keycloak_app` does not exist.
So the transfer is exactly 91 `ALTER TABLE ... OWNER TO` statements, no `ALTER SEQUENCE`. The concrete SQL is
`phase1-mutation.sql` in this directory.

### Phase 1 — Mutation (create role, grant, transfer ownership, cut over)

Generated from Phase 0's output. The password is generated out of band and never printed into the session
(stored in the Secrets Manager secret). Shape (final `ALTER` list filled from the 0.2 inventory):

```sql
-- 1.1 Create the dedicated login role — LOGIN only (Findings 8, 10).
CREATE ROLE keycloak_app WITH LOGIN PASSWORD '<generated>';

-- 1.2 Schema + DB grants the new role needs BEFORE the ownership transfer (Finding 4).
--     Explicit CREATE even if PUBLIC may already have it on an inherited-PG15 DB (Finding 5) — harmless if
--     redundant, load-bearing if not.
GRANT CONNECT ON DATABASE keycloak TO keycloak_app;
GRANT USAGE, CREATE ON SCHEMA public TO keycloak_app;

-- 1.3 Make postgres a member of the new role so it may run ALTER ... OWNER TO (Findings 4, 7, 9).
--     KEEP THIS through the cutover window — it is the rollback path. Revoked only in Phase 3.
GRANT keycloak_app TO postgres;

-- 1.4 Ownership transfer — object by object, from the 0.2 inventory. NOT REASSIGN OWNED (Finding 7).
--     One statement per object; ALTER SEQUENCE/VIEW/MATERIALIZED VIEW for those relkinds.
ALTER TABLE public.<each_table> OWNER TO keycloak_app;
ALTER SEQUENCE public.<each_sequence> OWNER TO keycloak_app;
-- ... (full list generated from Phase 0)
```

Then, before touching production objects, **pre-verify the new role on a throwaway probe** (spike cutover
step 3) — connected as `keycloak_app`:

```sql
CREATE TABLE public._kc_probe (id int);
ALTER TABLE public._kc_probe ADD COLUMN note text;
ALTER TABLE public._kc_probe DROP COLUMN note;
DROP TABLE public._kc_probe;
```

**Checkpoint:** all four probe statements succeed under `keycloak_app` (proves CREATE+ALTER+DROP work) BEFORE
running 1.4 against the real objects. Then run 1.4, and re-query owners (Phase 2) before cutting over.

**Cutover (after ownership transfer verified):**
1. Update the `auth-001-sm` Secrets Manager secret values: `KC_DB_USERNAME` → `keycloak_app`,
   `KC_DB_PASSWORD` → the generated password (MFA-gated write; the task-def is unchanged — it reads the same
   keys from the same secret). No `KC_DB_SCHEMA` change (staying on `public`, Finding 11).
2. Rolling-restart the Keycloak ECS service (`auth-001`, desired 2) so new tasks pick up the new secret
   values — a full task cycle forces new DB connections under the new user (Finding 13 from the RDS spike:
   Keycloak's pool does not self-heal a credential change without a restart).

### Phase 2 — Verification

```sql
-- 2.1 Every transferred object now owned by keycloak_app, none left on postgres.
SELECT n.nspname, c.relkind, c.relname, pg_get_userbyid(c.relowner) AS owner
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind IN ('r','p','S','v','m')
ORDER BY owner, c.relkind, c.relname;
```

**Checkpoints:** 2.1 shows `keycloak_app` for every Keycloak object incl. `databasechangelog`/`...lock`, none
on `postgres`; the new Keycloak tasks' boot logs show a **clean Liquibase pass** (lock acquired/released, no
change-set error — Finding 2); a **login through the front end succeeds** (auth + DB end to end). The
built-in DB health check (Finding 12) is only available if `metrics-enabled` is on — the task-def does not set
it, so rely on the boot log + a real login as the checkpoints, not the health endpoint.

### Phase 3 — Stabilization, then cleanup

After the cutover has run clean for an agreed window, revoke the rollback membership as a **separate, later**
step:

```sql
REVOKE keycloak_app FROM postgres;
```

## Rollback

Because `postgres` stays a member of `keycloak_app` through the window (Phase 1.3, not revoked until Phase 3),
reverting is: set `auth-001-sm` `KC_DB_USERNAME`/`KC_DB_PASSWORD` back to `postgres`'s credentials and
rolling-restart. `postgres` can still administer the transferred objects via the retained membership, so
Keycloak boots clean under the old user. (If Phase 1.4 partially ran, ownership is mixed but both `postgres`
— via membership — and `keycloak_app` can ALTER, so Liquibase works either way; finish or reverse the
transfer deliberately, not mid-incident.)

## Risks

| Risk | Mitigation |
|---|---|
| A Keycloak object is missed in the 0.2 inventory and stays owned by `postgres` | 0.2 enumerates ALL postgres-owned relations in the schema, not a hardcoded list; Phase 2.1 re-checks that none remain on `postgres` before cutover is declared done |
| The membership is revoked too early, breaking rollback | Phase 3 revoke is explicitly a separate step AFTER the stabilization window — never in Phase 1 |
| `postgres` owns non-Keycloak objects in the DB | 0.3 surfaces this; the object-by-object transfer touches only the confirmed inventory, so unrelated objects are untouched regardless |
| Liquibase attempts DDL on the next boot and the new owner lacks a privilege | The probe (Phase 1) proves CREATE+ALTER+DROP under `keycloak_app` before any real transfer; ownership (not GRANT) is what ALTER needs, and 1.4 transfers it |
| Migration-strategy unknown (update/validate/manual) | Confirm before cutover; default `update` means the boot attempts DDL, which the probe already proved works — if `validate`/`manual` it does even less |

## Open discovery to confirm at Phase 0 (from the spike)

- The active Liquibase `migration-strategy` (task-def does not set it → default `update`) — confirm.
- Whether `metrics-enabled` is on (it is not in the task-def command) — if off, the DB health-check checkpoint
  is unavailable; use boot log + login instead.
