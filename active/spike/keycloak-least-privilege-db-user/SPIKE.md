# SPIKE — Least-Privilege PostgreSQL User for Productive Keycloak

## Investigation question

Grounded in official Keycloak and PostgreSQL (plus AWS RDS for PostgreSQL) documentation: what is the least-privilege PostgreSQL database user a productive Keycloak needs, and what is the safe way to migrate a running Keycloak off the RDS master user (`postgres`) onto that dedicated user, in place, without breaking Keycloak's Liquibase-driven startup — given that the existing `keycloak` database's schema objects are currently owned by `postgres`?

## Sources consulted

- [keycloak.org/server/db](https://www.keycloak.org/server/db) — official "Configuring the database" guide; the "Permissions of the database user", "db-schema", and JPA migration-strategy sections
- [github.com/keycloak/keycloak — docs/updating-database-schema.md](https://github.com/keycloak/keycloak/blob/main/docs/updating-database-schema.md) — Keycloak's own contributor doc confirming Liquibase-based automatic schema migration
- [keycloak.org/observability/health](https://www.keycloak.org/observability/health) — health-check reference, database connection-pool check
- [postgresql.org/docs/15/ddl-priv.html](https://www.postgresql.org/docs/15/ddl-priv.html) — object ownership and privilege model
- [postgresql.org/docs/15/sql-altertable.html](https://www.postgresql.org/docs/15/sql-altertable.html) — ALTER TABLE ownership requirement
- [postgresql.org/docs/15/sql-grant.html](https://www.postgresql.org/docs/15/sql-grant.html) — GRANT semantics, ownership vs privilege, role-membership GRANT
- [postgresql.org/docs/15/sql-reassign-owned.html](https://www.postgresql.org/docs/15/sql-reassign-owned.html) — REASSIGN OWNED scope and membership requirement
- [postgresql.org/docs/15/sql-alterdefaultprivileges.html](https://www.postgresql.org/docs/15/sql-alterdefaultprivileges.html) — ALTER DEFAULT PRIVILEGES scope (future objects only)
- [postgresql.org/docs/15/sql-createschema.html](https://www.postgresql.org/docs/15/sql-createschema.html) — CREATE SCHEMA privilege requirement
- [postgresql.org/docs/15/ddl-schemas.html](https://www.postgresql.org/docs/15/ddl-schemas.html) — the public schema and recommended secure schema usage patterns
- [postgresql.org/docs/15/role-attributes.html](https://www.postgresql.org/docs/15/role-attributes.html) — SUPERUSER, CREATEDB, CREATEROLE, LOGIN semantics
- [postgresql.org/docs/15/release-15.html](https://www.postgresql.org/docs/15/release-15.html) — PG15 public-schema CREATE-privilege default change
- [docs.aws.amazon.com — RDS master user account privileges](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.MasterAccounts.html) — AWS's own best-practice statement against using the master user in applications
- [docs.aws.amazon.com — Understanding PostgreSQL roles and permissions](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.PostgreSQL.CommonDBATasks.Roles.html) — confirms the RDS master user is `rds_superuser`, not a true superuser
- [docs.aws.amazon.com — Understanding the rds_superuser role](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.PostgreSQL.CommonDBATasks.Roles.rds_superuser.html) — the exact `CREATE ROLE postgres ...` definition and what `rds_superuser` confers
- UNVERIFIED: [repost.aws/knowledge-center/rds-postgresql-drop-user-role](https://repost.aws/knowledge-center/rds-postgresql-drop-user-role) — returned HTTP 403 on fetch; not used to sustain any finding, referenced only as a pointer for main to re-check manually if desired
- UNVERIFIED: [github.com/keycloak/keycloak/discussions/25750](https://github.com/keycloak/keycloak/discussions/25750) — community discussion confirming the absence of official guidance ("I cannot find anything about it in the current documentation"); used only to corroborate Finding 1's negative result, not to sustain a positive claim

## Findings

### Finding 1: Keycloak's official docs do not state a general minimum DB-user privilege set

**Evidence:** The "Configuring the database" guide has a section literally titled "Permissions of the database user". Its entire content is:

> "Ensure that the database user has `SELECT` permissions to the following tables to ensure an efficient upgrade: `pg_class`, `pg_namespace`."

This is followed by an explanation that this access "enables Keycloak to determine row counts during schema updates. Without these permissions, the system logs a warning and employs a less efficient counting method." No table or list of baseline CREATE/ALTER/DROP/INSERT/UPDATE/DELETE requirements exists anywhere else on the page (verified by requesting a full heading-by-heading and section-by-section quote of the page).

**Source:** [keycloak.org/server/db](https://www.keycloak.org/server/db), section "Permissions of the database user"

**Significance:** Keycloak's official documentation does not prescribe a minimum privilege grant set for its database user — it only documents one *optional* SELECT grant that improves upgrade performance. This means the least-privilege set has to be *derived* from what Keycloak's Liquibase-driven schema management actually does (Finding 2) combined with PostgreSQL's own ownership/privilege model (Findings 3–5), not read off a Keycloak table. A community discussion on the Keycloak GitHub org (`keycloak/keycloak#25750`) independently confirms this gap — a participant states "I cannot find anything about it in the current documentation" — corroborating the negative result without being needed to establish it.

**Verification:** URL fetched: `https://www.keycloak.org/server/db`. Verbatim quote checked: "Ensure that the database user has `SELECT` permissions to the following tables to ensure an efficient upgrade: `pg_class`, `pg_namespace`." Quote substring confirmed present in the section titled "Permissions of the database user" on re-fetch.

---

### Finding 2: Keycloak automatically runs Liquibase migrations against the existing schema on every startup

**Evidence:** Keycloak's own contributor documentation states:

> "Keycloak supports automatically migrating the database to a new version. This is done by applying one or more change-sets to the existing database."

and that Liquibase is the underlying mechanism, with change-sets organized as `jpa-changelog-<version>.xml` files. Separately, the server guide documents the JPA migration-strategy SPI option that controls this behavior:

> "To setup the JPA migrationStrategy (manual/update/validate) you should setup JPA provider as follows: Setting the `migration-strategy` for the `quarkus` provider of the `connections-jpa` SPI"

**Source:** [github.com/keycloak/keycloak — docs/updating-database-schema.md](https://github.com/keycloak/keycloak/blob/main/docs/updating-database-schema.md); [keycloak.org/server/db](https://www.keycloak.org/server/db), "Setting JPA provider configuration option for migrationStrategy"

**Significance:** Every Keycloak boot (not just upgrades) goes through Liquibase, which reads/writes the `DATABASECHANGELOG` and `DATABASECHANGELOGLOCK` bookkeeping tables and — whenever the running Keycloak version's changelog is ahead of what has been applied — issues DDL (`ALTER TABLE`, `CREATE TABLE`, `CREATE INDEX`, etc.) against the existing schema. The dedicated DB user must be able to do all of this against objects that already exist and are currently owned by `postgres`, not just against newly-created objects. This is the load-bearing requirement the rest of the findings resolve.

**Verification:** URL fetched: `https://github.com/keycloak/keycloak/blob/main/docs/updating-database-schema.md`. Verbatim quote checked: "Keycloak supports automatically migrating the database to a new version." Quote substring confirmed present in the document body on re-fetch. Second URL fetched: `https://www.keycloak.org/server/db`. Verbatim quote checked: "Setting the `migration-strategy` for the `quarkus` provider of the `connections-jpa` SPI." Quote substring confirmed present in the migration-strategy section on re-fetch.

---

### Finding 3: PostgreSQL's ownership model — GRANT alone cannot support Liquibase's ALTER statements on existing objects

**Evidence:** The PostgreSQL privileges chapter states:

> "When an object is created, it is assigned an owner. The owner is normally the role that executed the creation statement. For most kinds of objects, the initial state is that only the owner (or a superuser) can do anything with the object. To allow other roles to use it, privileges must be granted."

and, critically:

> "The right to modify or destroy an object is inherent in being the object's owner, and cannot be granted or revoked in itself. (However, like all privileges, that right can be inherited by members of the owning role...)"

The `ALTER TABLE` reference page states this even more directly:

> "You must own the table to use `ALTER TABLE`."

and the GRANT reference confirms `GRANT ALL PRIVILEGES` never substitutes for ownership:

> "The right to drop an object, or to alter its definition in any way, is not treated as a grantable privilege; it is inherent in the owner, and cannot be granted or revoked. (However, a similar effect can be obtained by granting or revoking membership in the role that owns the object; see below.) The owner implicitly has all grant options for the object, too."

**Source:** [postgresql.org/docs/15/ddl-priv.html](https://www.postgresql.org/docs/15/ddl-priv.html); [postgresql.org/docs/15/sql-altertable.html](https://www.postgresql.org/docs/15/sql-altertable.html); [postgresql.org/docs/15/sql-grant.html](https://www.postgresql.org/docs/15/sql-grant.html)

**Significance:** This directly answers the "option (c): grant privileges without ownership" branch of Question 2 — it is not viable. `ALTER TABLE` (which Liquibase issues on every schema-changing upgrade) requires table ownership; no combination of `GRANT SELECT/INSERT/UPDATE/DELETE/…` privileges makes a non-owner able to run it. Ownership transfer (or membership in the owning role, per the parenthetical) is not an optional hardening step here — it is the mechanical precondition for Liquibase to keep working against the *existing* tables. This resolves the "is ownership unavoidable" sub-question in Question 2 as: yes, for any table Liquibase might ALTER, which in practice is the whole Keycloak schema.

**Verification:** URL fetched: `https://www.postgresql.org/docs/15/sql-altertable.html`. Verbatim quote checked: "You must own the table to use `ALTER TABLE`." Quote substring confirmed present in the page on re-fetch.

---

### Finding 4: Ownership-vs-membership nuance for the target role, and the schema-level CREATE requirement to alter ownership

**Evidence:** The `ALTER TABLE` page, describing the owner-change sub-case, states:

> "To alter the owner, you must also be a direct or indirect member of the new owning role, and that role must have `CREATE` privilege on the table's schema. (These restrictions enforce that altering the owner doesn't do anything you couldn't do by dropping and recreating the table. However, a superuser can alter ownership of any table anyway.)"

Separately, on schema-level CREATE:

> "For schemas, [CREATE] allows new objects to be created within the schema. To rename an existing object, you must own the object *and* have this privilege for the containing schema."

**Source:** [postgresql.org/docs/15/sql-altertable.html](https://www.postgresql.org/docs/15/sql-altertable.html); [postgresql.org/docs/15/ddl-priv.html](https://www.postgresql.org/docs/15/ddl-priv.html)

**Significance:** Two operational preconditions fall out of this, in order: (1) the executing role (in this environment, the RDS master `postgres`) must become a member of the new dedicated role *before* running `ALTER TABLE ... OWNER TO`, and (2) the new dedicated role must already hold `CREATE` privilege on the schema housing the tables (e.g. `public`) before the ownership transfer runs — the ALTER-owner check verifies the *new* owner could have created an equivalent object itself. Both must be granted ahead of the ownership-transfer step, not after.

**Verification:** URL fetched: `https://www.postgresql.org/docs/15/sql-altertable.html`. Verbatim quote checked: "you must also be a direct or indirect member of the new owning role, and that role must have `CREATE` privilege on the table's schema." Quote substring confirmed present in the "Notes" area of the ALTER TABLE description on re-fetch.

---

### Finding 5: PostgreSQL 15 changed the default CREATE privilege on the `public` schema, but only for new databases

**Evidence:** The PostgreSQL 15 release notes state, under "Migration to Version 15":

> "Remove PUBLIC creation permission on the public schema (Noah Misch) ... The change applies to new database clusters and to newly-created databases in existing clusters. Upgrading a cluster or restoring a database dump will preserve public's existing permissions. For existing databases, especially those having multiple users, consider revoking CREATE permission on the public schema to adopt this new default."

**Source:** [postgresql.org/docs/15/release-15.html](https://www.postgresql.org/docs/15/release-15.html), "Migration to Version 15"

**Significance:** Whether the dedicated Keycloak role automatically has `CREATE` on `public` today, or needs it granted explicitly, depends on *when* the `keycloak` database on this RDS PG15 instance was created (a fresh PG15-native database vs. one carried over from an earlier major-version upgrade or restored dump) — the release note explicitly says existing databases "preserve public's existing permissions" (i.e. `PUBLIC` may still implicitly have CREATE there). This is listed as a Discovery point below: do not assume either state — grant `CREATE` on the target schema to the dedicated role explicitly regardless, since an explicit grant is a harmless no-op if the privilege already exists via `PUBLIC`, but is load-bearing if it does not (per Finding 4, the new role needs schema `CREATE` before ownership transfer can succeed).

**Verification:** URL fetched: `https://www.postgresql.org/docs/15/release-15.html`. Verbatim quote checked: "The change applies to new database clusters and to newly-created databases in existing clusters. Upgrading a cluster or restoring a database dump will preserve public's existing permissions." Quote substring confirmed present under "Migration to Version 15" on re-fetch.

---

### Finding 6: PostgreSQL's own documented "secure schema usage pattern" is a dedicated, role-owned schema

**Evidence:** Section 5.9.6, "Usage Patterns", of the DDL chapter states:

> "To implement this pattern, first ensure that no schemas have public CREATE privileges. Then, for every user needing to create non-temporary objects, create a schema with the same name as that user, for example `CREATE SCHEMA alice AUTHORIZATION alice`. ... This pattern is a secure schema usage pattern unless an untrusted user is the database owner or holds the CREATEROLE privilege, in which case no secure schema usage pattern exists. In PostgreSQL 15 and later, the default configuration supports this usage pattern."

**Source:** [postgresql.org/docs/15/ddl-schemas.html](https://www.postgresql.org/docs/15/ddl-schemas.html), section 5.9.6

**Significance:** This grounds Question 2's option (a) — a dedicated schema owned by the dedicated user — as PostgreSQL's own documented, named secure pattern (`CREATE SCHEMA <name> AUTHORIZATION <name>`), not an invented convention. Important qualifier, directly from the same passage: it explicitly ceases to be a secure pattern "unless an untrusted user is the database owner or holds the CREATEROLE privilege" — i.e. if the RDS master (`postgres`, which per Finding 8 does hold CREATEROLE) is considered part of the trust boundary, this pattern's security guarantee is scoped accordingly. Also important: schema ownership is a distinct fact from *table* ownership (a schema's owner controls the namespace — who may create objects in it, per Finding 4 — but does not thereby own tables already sitting inside that schema). So adopting a dedicated schema does not, by itself, replace the object-by-object ownership transfer established as necessary in Findings 3–4 for *existing* tables; it only governs *new* objects created after the schema exists. This is my own inference from the definitions in Findings 3, 4, and 6 combined — not a directly quoted claim.

**Verification:** URL fetched: `https://www.postgresql.org/docs/15/ddl-schemas.html`. Verbatim quote checked: "create a schema with the same name as that user, for example `CREATE SCHEMA alice AUTHORIZATION alice`." Quote substring confirmed present in section 5.9.6 "Usage Patterns" on re-fetch.

---

### Finding 7: `REASSIGN OWNED BY` reassigns everything the source role owns in the database, plus shared objects — not scoped to one schema

**Evidence:**

> "REASSIGN OWNED instructs the system to change the ownership of database objects owned by any of the old_roles to new_role."

and, on scope:

> "Because REASSIGN OWNED does not affect objects within other databases, it is usually necessary to execute this command in each database that contains objects owned by a role that is to be removed."

and on membership:

> "REASSIGN OWNED requires membership on both the source role(s) and the target role."

and on what it does *not* touch:

> "The REASSIGN OWNED command does not affect any privileges granted to the old_roles on objects that are not owned by them. Likewise, it does not affect default privileges created with ALTER DEFAULT PRIVILEGES."

**Source:** [postgresql.org/docs/15/sql-reassign-owned.html](https://www.postgresql.org/docs/15/sql-reassign-owned.html)

**Significance:** `REASSIGN OWNED BY postgres TO <newrole>` is a database-wide, role-wide operation — it reassigns *every* object `postgres` owns in the `keycloak` database (and shared objects like tablespaces, and per the PostgreSQL 15 documentation's own definition of "objects", potentially the database itself if `postgres` is its owner) to the new role, not only the Keycloak application tables. On an RDS instance where the master user is used broadly (extensions, other schemas, the database object itself), this command cannot be scoped to "just Keycloak's schema" — it is all-or-nothing per source role. This is the central caveat Question 3 asked to establish, and it argues for the object-by-object `ALTER ... OWNER TO` alternative scoped explicitly to the Keycloak schema's inventory, rather than `REASSIGN OWNED`, precisely because the blast radius of the latter cannot be bounded to "just Keycloak."

**Verification:** URL fetched: `https://www.postgresql.org/docs/15/sql-reassign-owned.html`. Verbatim quote checked: "REASSIGN OWNED requires membership on both the source role(s) and the target role." Quote substring confirmed present in the page's Description/Notes on re-fetch.

---

### Finding 8: The RDS PostgreSQL master user is explicitly `NOSUPERUSER` — it does not get the ownership/ALTER superuser bypass

**Evidence:** AWS's own documentation states the master user's exact role definition:

> "The `postgres` user is the most highly privileged database user on your RDS for PostgreSQL DB instance. It has the characteristics defined by the following CREATE ROLE statement. `CREATE ROLE postgres WITH LOGIN NOSUPERUSER INHERIT CREATEDB CREATEROLE NOREPLICATION VALID UNTIL 'infinity'` ... By default, postgres has privileges granted to the rds_superuser role, and permissions to create roles and databases."

and, separately, on why:

> "RDS for PostgreSQL is a managed service, so you can't access the host OS, and you can't connect using the PostgreSQL superuser account. Many of the tasks that require superuser access on a stand-alone PostgreSQL are managed automatically by Amazon RDS."

**Source:** [docs.aws.amazon.com — Understanding the rds_superuser role](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.PostgreSQL.CommonDBATasks.Roles.rds_superuser.html)

**Significance:** This closes the loop on Question 3's "is the ownership-transfer mechanism safe when the source role is the RDS master" sub-question. Because `postgres` is `NOSUPERUSER`, none of the PostgreSQL "a superuser can alter ownership of any table anyway" or "superusers bypass all permission checks" carve-outs (quoted in Findings 3–4 and the `sql-createrole.html` fetch) apply to it — `postgres` is bound by the same ownership/membership rules as any other role. Concretely: the `REASSIGN OWNED` "membership on both roles" requirement (Finding 7) is not something RDS's `postgres` gets to skip; it must be satisfied with an explicit `GRANT <newrole> TO postgres` beforehand, exactly like a non-master role would need.

**Verification:** URL fetched: `https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.PostgreSQL.CommonDBATasks.Roles.rds_superuser.html`. Verbatim quote checked: "CREATE ROLE postgres WITH LOGIN NOSUPERUSER INHERIT CREATEDB CREATEROLE NOREPLICATION VALID UNTIL 'infinity'". Quote substring confirmed present on re-fetch.

---

### Finding 9: `postgres`'s `CREATEROLE` attribute is what lets it self-grant membership in the new role — closing the loop on Finding 7/8's membership requirement

**Evidence:** The PostgreSQL role-attributes documentation states:

> "A role with CREATEROLE privilege can alter and drop other roles, too, as well as grant or revoke membership in them."

and the GRANT (role membership) reference states:

> "Roles having CREATEROLE privilege can grant or revoke membership in any role that is not a superuser."

with an explicit warning about the scope of this power:

> "Because the CREATEROLE privilege allows a user to grant or revoke membership even in roles to which it does not (yet) have any access, a CREATEROLE user can obtain access to the capabilities of every predefined role in the system... Therefore, regard roles that have the CREATEROLE privilege as almost-superuser-roles."

**Source:** [postgresql.org/docs/15/role-attributes.html](https://www.postgresql.org/docs/15/role-attributes.html); [postgresql.org/docs/15/sql-grant.html](https://www.postgresql.org/docs/15/sql-grant.html)

**Significance:** Because `postgres` (per Finding 8) has `CREATEROLE`, it can run `GRANT <newrole> TO postgres;` on its own authority to satisfy the "membership in target role" precondition that both `REASSIGN OWNED` (Finding 7) and `ALTER TABLE ... OWNER TO` (Finding 4) require — no separate `rdsadmin`-mediated grant dance is documented as necessary in the primary PostgreSQL/AWS sources fetched for this spike. (A community/support article claiming a more involved `GRANT rdsadmin TO ...` sequence was found via search but returned HTTP 403 on fetch and is marked UNVERIFIED — it is not needed to reach this conclusion and is not used to sustain it.) The same quoted warning ("almost-superuser-roles") is itself the reason `CREATEROLE` belongs on the "must NOT have" list for the new dedicated Keycloak role (Question 4) — the dedicated role must never carry `CREATEROLE`, or it inherits comparable reach.

**Verification:** URL fetched: `https://www.postgresql.org/docs/15/role-attributes.html`. Verbatim quote checked: "A role with CREATEROLE privilege can alter and drop other roles, too, as well as grant or revoke membership in them." Quote substring confirmed present on re-fetch.

---

### Finding 10: PostgreSQL role attribute definitions establish the explicit "must NOT have" list for the dedicated Keycloak role

**Evidence:**

> "SUPERUSER / NOSUPERUSER — These clauses determine whether the new role is a 'superuser', who can override all access restrictions within the database. Superuser status is dangerous and should be used only when really needed."

> "CREATEDB / NOCREATEDB — These clauses define a role's ability to create databases."

> "CREATEROLE / NOCREATEROLE — These clauses determine whether a role will be permitted to create, alter, drop, comment on, change the security label for, and grant or revoke membership in other roles."

> "LOGIN / NOLOGIN — These clauses determine whether a role is allowed to log in... A role having the LOGIN attribute can be thought of as a user."

Separately, on RDS's cluster-wide privileged role:

> "The rds_superuser role allows the postgres user to do the following: Add extensions... Create roles for users and grant privileges to users... Create databases... Grant rds_superuser privileges to user roles... Obtain status information about all database connections... [and] stop any connections."

**Source:** [postgresql.org/docs/15/role-attributes.html](https://www.postgresql.org/docs/15/role-attributes.html); [docs.aws.amazon.com — Understanding the rds_superuser role](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.PostgreSQL.CommonDBATasks.Roles.rds_superuser.html)

**Significance:** Directly answers Question 4. The dedicated Keycloak role needs `LOGIN` (it is an application connection, not a group role) and nothing else from this list: not `SUPERUSER` (bypasses all access restrictions — clearly wrong for an application user), not `CREATEDB` (Keycloak connects to one already-provisioned database), not `CREATEROLE` (per Finding 9, "almost-superuser"), and it must not be a member of `rds_superuser` (which on RDS additionally confers ability to create/alter roles and databases, manage extensions, and terminate arbitrary connections cluster-wide — none of which Keycloak's own documented needs, Findings 1–2, call for).

**Verification:** URL fetched: `https://www.postgresql.org/docs/15/role-attributes.html`. Verbatim quote checked: "Superuser status is dangerous and should be used only when really needed." Quote substring confirmed present on re-fetch.

---

### Finding 11: Keycloak's `db-schema` option and its default — relevant only if a dedicated schema is adopted

**Evidence:**

> "By default, no schema is explicitly set and Keycloak uses the default schema of the chosen database. You can override this by using the `db-schema` configuration option."

The option's exact keys, from the configuration reference table: CLI `--db-schema`, environment variable `KC_DB_SCHEMA`, description "The database schema to be used."

**Source:** [keycloak.org/server/db](https://www.keycloak.org/server/db)

**Significance:** If the cutover stays on the schema Keycloak already uses today (its "default schema" — almost certainly `public`, to be confirmed per the Discovery points below), no `db-schema`/`KC_DB_SCHEMA` change is needed at all — only `KC_DB_USERNAME`/`KC_DB_PASSWORD` change, per the context given. If the cutover *also* adopts a dedicated schema (Finding 6's pattern), `KC_DB_SCHEMA` must be added to the Keycloak configuration/secret alongside the credential change, or Keycloak will keep looking in its old default schema and find nothing (or find the old owner's copies, if left in place) — this is a Keycloak-specific gotcha the question explicitly asked to flag.

**Verification:** URL fetched: `https://www.keycloak.org/server/db`. Verbatim quote checked: "By default, no schema is explicitly set and Keycloak uses the default schema of the chosen database." Quote substring confirmed present on re-fetch.

---

### Finding 12: Keycloak's health check reports database connection-pool status — usable as a cutover verification checkpoint

**Evidence:** The observability/health reference's "Available Checks" table describes the database check as:

> "Returns the status of the database connection pool."

**Source:** [keycloak.org/observability/health](https://www.keycloak.org/observability/health)

**Significance:** This is a documented, built-in signal (gated behind `metrics-enabled`, per the same page) that can serve as one of the cutover verification checkpoints (Question 5) — after the rolling restart under the new credentials, the health endpoint reporting the database connection pool as healthy is one machine-checkable confirmation that Keycloak actually established a working connection under the new user, in addition to reading the boot log for a clean Liquibase pass.

**Verification:** URL fetched: `https://www.keycloak.org/observability/health`. Verbatim quote checked: "Returns the status of the database connection pool." Quote substring confirmed present in the "Available Checks" table on re-fetch.

## Recommended least-privilege grant set (SQL shape — NOT executed)

Grounded in Findings 1–11. This is the shape of the statements, for the engineer to review and run — no SQL was executed as part of this spike.

```sql
-- 1. Create the dedicated role. LOGIN only — no SUPERUSER, CREATEDB, CREATEROLE,
--    and it must not be granted rds_superuser (Findings 8, 10).
CREATE ROLE keycloak_app WITH LOGIN PASSWORD '<generated>';

-- 2. Grant it CREATE + USAGE on the schema Keycloak actually uses today
--    (confirm the schema name — see Discovery points). This must happen
--    BEFORE the ownership transfer below (Finding 4: the new owner must
--    already hold CREATE on the schema before ALTER ... OWNER TO succeeds).
--    Explicit even if PUBLIC may already have it (Finding 5) — harmless if
--    redundant, load-bearing if not.
GRANT USAGE, CREATE ON SCHEMA <keycloak_schema> TO keycloak_app;

-- 3. Grant DB-level CONNECT so the role can open a session against `keycloak`.
GRANT CONNECT ON DATABASE keycloak TO keycloak_app;

-- 4. Make the executing role (the RDS master, postgres) a member of the new
--    role. Both REASSIGN OWNED and ALTER ... OWNER TO require the executor
--    to be a member of the TARGET role (Findings 4, 7); postgres's CREATEROLE
--    lets it do this on its own authority (Finding 9).
GRANT keycloak_app TO postgres;

-- 5. Transfer ownership of the EXISTING objects, scoped to the Keycloak
--    schema only — object by object, NOT REASSIGN OWNED BY postgres
--    (Finding 7: REASSIGN OWNED is database-wide plus shared objects, not
--    scopable to one schema; too broad a blast radius on a shared RDS master).
--    The exact object list must be enumerated first (Discovery points) and
--    fed into statements of this shape, one per object:
ALTER TABLE <keycloak_schema>.<table_name> OWNER TO keycloak_app;
ALTER SEQUENCE <keycloak_schema>.<sequence_name> OWNER TO keycloak_app;
-- (repeat for every table/sequence/view Liquibase created in this schema,
--  including DATABASECHANGELOG and DATABASECHANGELOGLOCK)
```

## Recommended ownership-transfer approach, with caveats

- **Object-by-object `ALTER ... OWNER TO`, scoped to the Keycloak schema — not `REASSIGN OWNED BY postgres`.** Finding 7 establishes `REASSIGN OWNED` reassigns *every* object `postgres` owns in the database plus shared objects; on an RDS instance where the master user is the default owner for everything provisioned on the instance, this cannot be bounded to "just Keycloak," and running it risks silently moving ownership of unrelated objects/schemas/the database itself. The per-object form contains the blast radius to exactly the inventory the engineer confirms belongs to Keycloak.
- **Sequencing matters** (Finding 4): the new role needs schema `CREATE` privilege, and the executor (`postgres`) needs membership in the new role, both *before* the `ALTER ... OWNER TO` statements run — not after.
- **Keep `postgres`'s membership in the new role in place through the cutover window, not just for the duration of the transfer.** Per Finding 3's parenthetical ("that right can be inherited by members of the owning role") and `postgres`'s `INHERIT` attribute (Finding 8's quoted `CREATE ROLE` definition), `postgres` — no longer the object owner after transfer, and (per Finding 8) not a true superuser that bypasses ownership checks — retains the ability to `ALTER`/administer the transferred objects only *through* that membership. This is what preserves a working rollback path (reverting Keycloak's credentials to `postgres`) if the cutover needs to be undone before it is declared stable. Revoking `GRANT keycloak_app TO postgres` is a separate, later cleanup step, only after the cutover is confirmed stable.
- **`ALTER DEFAULT PRIVILEGES` does not help here** (its own docs: "It does not affect privileges assigned to already-existing objects") — it only shapes ownership/grants for objects created *after* it is set, so it is a nice-to-have for whatever Liquibase creates on a *future* Keycloak upgrade, not a substitute for the one-time transfer of what already exists.

## Cutover ordering, with verification checkpoints

1. **Discovery** (no mutation) — confirm the actual schema Keycloak uses today, the actual object inventory owned by `postgres` in that schema (tables, sequences, views — including `DATABASECHANGELOG`/`DATABASECHANGELOGLOCK`), and whether the target RDS PG15 instance/database predates PG15 or is PG15-native (Finding 5). See Discovery points below.
2. **Provision the role and its baseline grants** — `CREATE ROLE`, schema `USAGE`/`CREATE`, DB `CONNECT`, and the `GRANT keycloak_app TO postgres` membership grant (SQL shape above, steps 1–4). No object ownership changes yet. **Checkpoint:** confirm role attributes with a read of `pg_roles` show no `SUPERUSER`/`CREATEDB`/`CREATEROLE` and no membership in `rds_superuser`.
3. **Pre-verify the new role on a disposable object, not a Keycloak table** — connect as `keycloak_app` and run a throwaway `CREATE TABLE`, an `ALTER TABLE ... ADD COLUMN`/`DROP COLUMN` round-trip, and `DROP TABLE` against a probe table in the target schema, confirming CREATE+ALTER+DROP all work under the new role before touching production objects. **Checkpoint:** all three DDL operations succeed and the probe table is fully removed afterward.
4. **Transfer ownership of the real Keycloak object inventory** to `keycloak_app`, object by object (SQL shape above, step 5). **Checkpoint:** re-query the schema's object-owner catalog (e.g. `pg_tables`/`pg_class` owner columns) and confirm every relevant table/sequence/view — including `DATABASECHANGELOG`/`DATABASECHANGELOGLOCK` — now shows `keycloak_app`, not `postgres`.
5. **Update the Secrets Manager secret** — set `KC_DB_USERNAME`/`KC_DB_PASSWORD` to the new role's credentials (and, only if a dedicated schema is being adopted in the same effort, add/update `KC_DB_SCHEMA`, per Finding 11). No mutation on the running Keycloak yet at this step.
6. **Rolling restart** the ECS Fargate Keycloak tasks so the new tasks pick up the updated secret values.
7. **Post-restart verification** — read the new tasks' boot logs for a clean Liquibase pass (no lock-acquisition or change-set errors, per Finding 2's description of the changelog/lock mechanism), and confirm the database health check (Finding 12: "Returns the status of the database connection pool") reports healthy once `metrics-enabled` is on. **Checkpoint:** both signals green before considering the cutover complete.
8. **Stabilization window, then cleanup** — only after the cutover has run clean for an agreed period, revoke `GRANT keycloak_app TO postgres` (the rollback safety net from the "Recommended ownership-transfer approach" section) as a separate, later step.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Object-by-object `ALTER ... OWNER TO`, scoped to Keycloak's schema | Blast radius contained to the confirmed Keycloak inventory; no risk to unrelated objects `postgres` owns elsewhere in the database | Requires an accurate, complete object inventory up front; more statements to generate/run | Finding 7 (REASSIGN OWNED scope), Finding 3 (ownership is what ALTER needs) |
| `REASSIGN OWNED BY postgres TO keycloak_app` | One statement, no inventory needed | Reassigns *everything* `postgres` owns in the database plus shared objects (Finding 7) — cannot be scoped to just Keycloak; on a shared RDS master this risks collateral ownership changes outside the task's scope | Finding 7 |
| Stay on the existing (`public`, to be confirmed) schema | Minimal change: ownership transfer only, no `KC_DB_SCHEMA` change, no object relocation | Does not adopt PostgreSQL's own documented secure schema pattern (Finding 6); if PG15's default was inherited from before PG15 (Finding 5), `PUBLIC` may still implicitly hold `CREATE` on that schema unless separately revoked | Finding 5, Finding 6 |
| Adopt a dedicated, `keycloak_app`-owned schema (`CREATE SCHEMA ... AUTHORIZATION keycloak_app`) | Matches PostgreSQL's own documented secure schema usage pattern (Finding 6); new objects going forward are owned by the dedicated role by construction | Existing objects still need object-by-object ownership transfer regardless (schema ownership ≠ table ownership, Finding 6); adds a `KC_DB_SCHEMA` config change and a schema-move step to an otherwise user-only cutover; broadens the scope of "this effort" as framed in the context given | Finding 6, Finding 11 |

## What remains uncertain

- Whether the specific `keycloak` RDS database was created before or after adopting PostgreSQL 15 defaults (i.e., whether `PUBLIC` currently still holds implicit `CREATE` on its schema) — Finding 5 shows this is knowable only by checking the instance's history/actual grants, not by reading the docs.
- Whether `postgres` on this instance owns objects outside Keycloak's own tables within the `keycloak` database (other schemas, extensions, the database object itself) — this determines how much collateral risk a `REASSIGN OWNED` would actually carry in practice, versus the object-by-object alternative recommended here regardless.
- The exact AWS-recommended mechanics for reassigning ownership ahead of a role drop on RDS (a support-article shape describing `GRANT rdsadmin TO ...` prerequisites) could not be verified — the source returned HTTP 403 on fetch. The primary PostgreSQL/AWS documentation fetched in this spike (Findings 7–9) independently establishes a working, narrower path (`GRANT keycloak_app TO postgres` on `postgres`'s own `CREATEROLE` authority) without needing that article, but the article's exact recommended sequence was not able to be checked against it.
- Keycloak's official docs do not state whether the Liquibase migration-strategy default (`update` vs `validate` vs `manual`) is active in this environment today — this affects whether a boot under the new user will attempt DDL at all on the next restart, or only validate. This is a Discovery point, not something resolved by the docs consulted.

## Discovery points for main

- **Confirm the actual schema Keycloak is configured against today** — read the running task's `KC_DB_SCHEMA`/`--db-schema` value (or its absence) from the current ECS task definition/Secrets Manager secret to confirm it is `public` (Keycloak's "default schema" per Finding 11) and not something already overridden.
- **Confirm whether a dedicated schema is in scope for this effort or a later one** — the context given frames this as "no RDS replacement... done in place," which reads as user-only; Finding 6's dedicated-schema pattern is presented as an option, not assumed.
- **Enumerate the exact object inventory to transfer** — every table, sequence, view, and the `DATABASECHANGELOG`/`DATABASECHANGELOGLOCK` bookkeeping tables, in the confirmed schema, currently owned by `postgres`, before generating the per-object `ALTER ... OWNER TO` statements.
- **Confirm whether `postgres` owns anything else in the `keycloak` database beyond Keycloak's own objects** — informs how much risk a `REASSIGN OWNED` shortcut would actually carry, even though the object-by-object approach is recommended regardless.
- **Confirm the currently-active Liquibase `migration-strategy`** (`update`/`validate`/`manual`) for this Keycloak deployment, since it determines whether the next restart under the new user will attempt DDL at all.
- **Confirm whether `metrics-enabled` is already on** for this Keycloak deployment, since Finding 12's health-check verification checkpoint depends on it.
