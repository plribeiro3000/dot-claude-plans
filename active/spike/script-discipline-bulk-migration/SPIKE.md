# SPIKE — Script Discipline: Bulk Cross-Database Export/Import

## Investigation question

What canonical techniques, tools, and gotchas should be documented in `~/.claude/docs/SCRIPT-DISCIPLINE.md` as a new "bulk cross-database export/import" section, covering: (1) verification of six specific learnings from a real Azure SQL → Azure SQL migration that used bcp queryout + sqlcmd with DML-only permissions, and (2) canonical tool/identity/encoding patterns for SQL Server/Azure SQL, PostgreSQL, MongoDB, MySQL/MariaDB, and Oracle?

## Sources consulted

- [Microsoft Learn — sqlcmd Utility (ODBC)](https://learn.microsoft.com/en-us/sql/tools/sqlcmd/sqlcmd-utility?view=sql-server-ver17) — flags -I, -W, -y, -Y, -h documented here; see auxiliary: `script-discipline-bulk-migration_excerpt_1.txt`
- [Microsoft Learn — bcp Utility](https://learn.microsoft.com/en-us/sql/tools/bcp-utility?view=sql-server-ver16) — queryout behavior and -E flag for identity; see auxiliary: `script-discipline-bulk-migration_doc_1.txt`
- [PostgreSQL Docs — COPY](https://www.postgresql.org/docs/current/sql-copy.html) — identity column implicit override behavior; see auxiliary: `script-discipline-bulk-migration_doc_2.txt`
- [Oracle Docs — SQL*Loader](https://docs.oracle.com/en/database/oracle/oracle-database/19/sutil/oracle-sql-loader-control-file-contents.html) — GENERATED ALWAYS workaround; see auxiliary: `script-discipline-bulk-migration_doc_2.txt`
- [Oracle Docs — Data Pump](https://docs.oracle.com/en/database/oracle/oracle-database/19/sutil/datapump-export-utility.html) — identity sequence behavior on import; see auxiliary: `script-discipline-bulk-migration_doc_2.txt`
- [MySQL Docs — LOAD DATA INFILE](https://dev.mysql.com/doc/refman/8.0/en/load-data.html) — AUTO_INCREMENT and CHARACTER SET clause; see auxiliary: `script-discipline-bulk-migration_doc_2.txt`
- [GitHub Issue microsoft/linux-package-repositories#305](https://github.com/microsoft/linux-package-repositories/issues/305) — Debian 13 GPG key bug; see auxiliary: `script-discipline-bulk-migration_log_1.txt`
- [GitHub Issue microsoft/mdatp-xplat#198](https://github.com/microsoft/mdatp-xplat/issues/198) — corroborating Debian 13 GPG key bug; see auxiliary: `script-discipline-bulk-migration_log_1.txt`
- [SQLServerCentral — Using COLLATE DATABASE_DEFAULT](https://www.sqlservercentral.com/articles/collations-and-the-collate-database_default-clause) — COLLATE DATABASE_DEFAULT cross-database comparison pattern
- [MongoDB Docs — mongoimport](https://www.mongodb.com/docs/database-tools/mongoimport/) — --mode upsert/merge/delete with --upsertFields
- [MongoDB Docs — mongorestore](https://www.mongodb.com/docs/database-tools/mongorestore/) — BSON binary format, insert-only behavior
- `/Users/plribeiro3000/.claude/docs/SCRIPT-DISCIPLINE.md` — existing Rules 1–4 and S3 retention section; the target document for extension

---

## Findings

### Finding 1: bcp queryout generates flat file rows, not INSERT SQL natively

**Evidence:**
```
bcp "SELECT 'INSERT INTO TargetTable (col1, col2) VALUES (' +
      CAST(col1 AS varchar) + ', ' + CAST(col2 AS varchar) + ');'
     FROM SourceTable" queryout output.sql -S server -d db -T -c
```
The bcp utility's `queryout` mode runs a T-SQL query and writes each result row as a line in the output file. bcp does not natively generate INSERT statements — the trick is writing a SELECT whose result rows are SQL text strings. bcp writes those strings verbatim. Each row in the file is then a complete INSERT statement.

**Source:** Microsoft Learn — bcp Utility; see auxiliary `script-discipline-bulk-migration_doc_1.txt`

**Significance:** The engineer's session learning ("bcp queryout + a SELECT that emits SQL text") is confirmed and explained. This is distinct from saying "bcp generates INSERT statements" — it does not. The SELECT is what generates SQL text; bcp is a transport mechanism. The distinction matters when a new engineer adapts the pattern: the SQL construction logic lives in the T-SQL query, not in a bcp flag.

**Verification block:** URL fetched. Quote from Microsoft Learn bcp docs: "Specifies the file to copy data into and is required when you bulk-copy data from a query." Verbatim quote confirmed: bcp queryout writes query result rows to file.

---

### Finding 2: sqlcmd -I sets QUOTED_IDENTIFIER ON; required for filtered indexes

**Evidence:**
```
-I
Sets the SET QUOTED_IDENTIFIER connection option to ON. The default setting is OFF.
```
Without `-I`, `SET QUOTED_IDENTIFIER` is OFF in the sqlcmd session. Loading data into tables with filtered indexes, indexed views, or computed columns with quoted-identifier-sensitive expressions requires `QUOTED_IDENTIFIER ON`, or the engine throws Msg 1934 ("INSERT failed because the following SET options have incorrect settings").

**Source:** Microsoft Learn — sqlcmd Utility (ODBC variant), quoted in auxiliary `script-discipline-bulk-migration_excerpt_1.txt`

**Significance:** The engineer's learning ("sqlcmd -I is required when the target has filtered indexes") is confirmed. The default-OFF behavior of QUOTED_IDENTIFIER in sqlcmd is a non-obvious pitfall that differs from SSMS (SSMS defaults to ON). Scripts that work in SSMS may fail when run through sqlcmd without -I.

Note: sqlcmd (Go variant) ignores -I; quoted identifiers are always enabled there. The ODBC variant is what ships with mssql-tools18 on Linux.

**Verification block:** URL fetched. Verbatim quote: "Sets the SET QUOTED_IDENTIFIER connection option to ON. The default setting is OFF." Quote confirmed in auxiliary excerpt_1.txt line 12.

---

### Finding 3: sqlcmd -W is mutually exclusive with -y and -Y (vendor-confirmed)

**Evidence:**
```
-W
Removes trailing spaces from a column. Use this option together with the -s option
when preparing data that you want to export to another application. Can't be used
with the -y or -Y options.
```

**Source:** Microsoft Learn — sqlcmd Utility, "Format options" section; quoted in auxiliary `script-discipline-bulk-migration_excerpt_1.txt` line 19–25

**Significance:** The engineer's learning that "sqlcmd formatting flags are mutually exclusive in combinations you need, so driving generation through sqlcmd formatting failed" is partially confirmed. The vendor confirms -W cannot be used with -y or -Y. The -h flag (header row control) has no documented exclusivity with -W — that incompatibility is not vendor-confirmed. The practical failure in the session was the -W/-y conflict specifically: to suppress trailing spaces (-W) and also control display width for varchar columns (-y), you need both flags simultaneously, which the engine rejects. This makes sqlcmd an unreliable vehicle for generating clean fixed-width SQL text — the bcp queryout approach sidesteps this entirely by embedding format decisions in the T-SQL SELECT itself.

**Verification block:** URL fetched. Verbatim quote: "Can't be used with the -y or -Y options." Quote confirmed at auxiliary excerpt_1.txt lines 23–24.

---

### Finding 4: COLLATE DATABASE_DEFAULT resolves cross-database collation conflict

**Evidence:**
The error pattern is:
```
Cannot resolve the collation conflict between "SQL_Latin1_General_CP1_CI_AS"
and "Latin1_General_CI_AI" in the equal to operation.
```
The fix appends `COLLATE DATABASE_DEFAULT` to the collation-sensitive comparison:
```sql
WHERE source.email COLLATE DATABASE_DEFAULT = dest.email COLLATE DATABASE_DEFAULT
```
`DATABASE_DEFAULT` is a meta-collation that resolves to the collation of the database in which the query runs. When two databases have different collations, adding it to both sides of a comparison forces both to the calling database's collation before the comparison.

**Source:** SQL Server documentation (cross-database join collation); SQLServerCentral community article on COLLATE DATABASE_DEFAULT pattern; multiple Stack Overflow threads confirm the mechanism.

**Significance:** The engineer's learning is confirmed. The pattern is a workaround, not a fix — underlying data is still stored in the original collations. When migrating data long-term, aligning collations at the database or column level is cleaner. For ad-hoc migration sessions where re-aligning collations is not feasible, COLLATE DATABASE_DEFAULT is the documented safe approach.

**Verification block:** The COLLATE DATABASE_DEFAULT clause is a standard T-SQL expression documented in the SQL Server T-SQL reference. The specific error message pattern is reproducible and widely confirmed across DBA Stack Exchange and SQLServerCentral.

---

### Finding 5: mssql-tools18 on Debian 13 (trixie) — GPG key EE4D7792F748182B is an open bug

**Evidence:**
GitHub issue microsoft/linux-package-repositories#305 and the corroborating microsoft/mdatp-xplat#198 both document that Microsoft's Debian 13 package repository does not include the GPG key EE4D7792F748182B required to verify mssql-tools18 and MDATP packages. The issue has been open since at least 2024 and has no fix as of 2026-06-26. Known workarounds: (a) install packages-microsoft-prod.deb directly from packages.microsoft.com for the target OS version, (b) use the Debian 12 (bookworm) Microsoft repository, (c) use a pre-built Docker image.

The IPv4-forcing flag `apt-get -o Acquire::ForceIPv4=true` is a separate general apt technique for runners without IPv6, not specific to this bug.

**Source:** See auxiliary `script-discipline-bulk-migration_log_1.txt`

**Significance:** The engineer's learning about the GPG key failure is confirmed as a known open bug with Microsoft's Debian 13 package repository, not an environment-specific misconfiguration. CI/CD pipelines targeting Debian 13 base images should not follow Microsoft's standard installation guide for mssql-tools18 until this is resolved. The workarounds are reliable but non-standard.

**Verification block:** GitHub issues fetched. Issue #305 text confirmed: "NO_PUBKEY EE4D7792F748182B" error pattern on Debian 13. Issue #198 confirms the same key is missing from MDATP packages for Debian 13.

---

### Finding 6: FK remap by natural key — confirmed general cross-engine pattern

**Evidence:**
When IDENTITY_INSERT (SQL Server) or equivalent explicit-PK insert is unavailable, the pattern is:

```
Phase 1: Export source rows WITHOUT the PK column
Phase 2: Import into destination — destination DB assigns new PKs
Phase 3: Build PK mapping table:
         SELECT dest.new_pk, source.old_pk
         FROM dest_table dest
         JOIN source_table_snapshot source ON dest.natural_key = source.natural_key
Phase 4: Update FK columns in child tables using the mapping:
         UPDATE child SET parent_fk = mapping.new_pk
         WHERE child.parent_fk = mapping.old_pk
```

The "natural key" used for phase 3 is a business-level unique identifier that survives the migration (email address, external system ID, document number, etc.).

**Source:** General relational database migration pattern; no single authoritative source — the pattern is derivable from the constraint structure. The bcp docs confirm -E (identity preservation) requires IDENTITY_INSERT permission, and the permission requirement confirms the need for an alternative when DML-only access is the constraint.

**Significance:** The pattern is sound and cross-engine. PostgreSQL's COPY FROM implicitly handles identity values (Finding 9), so the FK-remap pattern is specifically relevant for SQL Server/Azure SQL in DML-only permission scenarios. The trade-off is that the natural key must be truly unique and stable; if it is not, the mapping is ambiguous and the approach fails.

**Verification block:** The bcp -E flag permission requirement is documented in Microsoft Learn bcp docs (auxiliary doc_1.txt). The pattern itself is a logical derivation — it is the standard approach when primary keys cannot be preserved. Not a single-source citation; classified as engineering reasoning from confirmed constraints.

---

### Finding 7: 2-phase rename through temp namespace for overlapping key ranges

**Evidence:**
When source PKs overlap with existing destination PKs (both tables have rows with id=1, id=2, etc.) and there is a UNIQUE constraint on the PK, a direct update of FK columns cannot be done in a single pass — new values collide with existing values mid-update.

The 2-phase rename approach:
```sql
-- Phase 1: Move source FKs to a temporary range (e.g., +1,000,000 offset)
UPDATE child_table
   SET parent_fk = parent_fk + 1000000
 WHERE parent_fk IN (SELECT old_pk FROM migration_mapping);

-- Phase 2: Update to final new PK values
UPDATE child_table
   SET parent_fk = (SELECT new_pk FROM migration_mapping m
                     WHERE m.old_pk + 1000000 = child_table.parent_fk)
 WHERE parent_fk > 1000000;
```

The offset must be chosen so it does not collide with existing values in either the old or new PK space.

**Source:** General SQL migration engineering pattern. No single authoritative source — derivable from uniqueness constraint behavior. Widely documented in DBA community practice.

**Significance:** The engineer's learning is confirmed as a valid and established pattern. The offset approach is brittle if the temporary range collides with real data — a more robust alternative is using negative numbers as the temp namespace (if PKs are positive integers) or using a separate staging table that maps all FKs before touching the production child table.

**Verification block:** Pattern derived from SQL constraint behavior (UNIQUE constraints reject duplicates mid-UPDATE). No single authoritative citation — classified as engineering reasoning. The alternative staging-table approach is noted as more robust.

---

### Finding 8: PostgreSQL COPY FROM implicitly overrides GENERATED ALWAYS AS IDENTITY

**Evidence:**
```
For identity columns, the COPY FROM command will always write the column values
provided in the input data, like the INSERT option OVERRIDING SYSTEM VALUE.
```

**Source:** PostgreSQL 17 COPY documentation; quoted in auxiliary `script-discipline-bulk-migration_doc_2.txt`

**Significance:** PostgreSQL's COPY FROM does not require any special flag or clause to insert explicit values into GENERATED ALWAYS AS IDENTITY columns. This is the opposite behavior from SQL Server (requires IDENTITY_INSERT ON) and Oracle (requires ALTER TABLE to GENERATED BY DEFAULT). After COPY FROM, the sequence is NOT automatically reset — the DBA must run `SELECT setval(pg_get_serial_sequence(...), MAX(col)) FROM table` manually or subsequent INSERTs will collide with imported values.

**Verification block:** URL fetched. Verbatim quote: "the COPY FROM command will always write the column values provided in the input data, like the INSERT option OVERRIDING SYSTEM VALUE." Quote confirmed in auxiliary doc_2.txt.

---

### Finding 9: pg_dump format choice determines restore flexibility

**Evidence:**
PostgreSQL's pg_dump supports three output formats:
- Default (plain SQL): restored via `psql`. No selective restore. Compatible with any psql version.
- `-Fc` (custom, compressed): restored via `pg_restore`. Allows selective table restore, parallel options, and resumability.
- `-Fd -j N` (directory, parallel): highest throughput for large databases; each table is a separate file; restored via `pg_restore`.

**Source:** PostgreSQL pg_dump documentation (https://www.postgresql.org/docs/current/app-pgdump.html)

**Significance:** For cross-database migrations of a subset of tables, `-Fc` with `pg_restore -t tablename` is the canonical approach. For full-database clones, `-Fd -j N` maximizes throughput. Plain SQL is only preferred when the destination psql version differs significantly from pg_dump.

**Verification block:** URL fetched. pg_dump -F format option documented: "-F format — Selects the format of the output. format can be one of: p (plain), c (custom), d (directory), t (tar)." Quote confirmed from PostgreSQL docs.

---

### Finding 10: MongoDB — mongoexport/mongoimport vs mongodump/mongorestore

**Evidence:**
Two tool pairs exist with fundamentally different scopes:

`mongoexport` / `mongoimport`:
- Format: JSON (Extended JSON) or CSV
- Scope: single collection per invocation
- Use case: selective migration, cross-version migration, transforming data during transfer
- `--mode` option: `insert` (default), `upsert`, `merge`, `delete`
- `--upsertFields`: specifies field(s) to use as natural key for upsert matching
- BSON type fidelity: requires Extended JSON format (`--jsonFormat canonical`) to preserve types like ObjectId, Date, Decimal128; relaxed JSON loses type information

`mongodump` / `mongorestore`:
- Format: binary BSON
- Scope: full database or filtered by --collection
- Use case: full database backup/restore, same-version migration
- `mongorestore` is insert-only: it does not update existing documents
- Cross-version: BSON format is stable but Extended JSON format changed between versions

**Source:** MongoDB Documentation — mongoexport (https://www.mongodb.com/docs/database-tools/mongoexport/), mongoimport (https://www.mongodb.com/docs/database-tools/mongoimport/), mongodump/mongorestore.

**Significance:** For 4Shark's integrator (Mongoid/MongoDB), the choice between the two pairs depends on whether data transformation or natural-key matching is needed (use mongoexport/mongoimport with --mode upsert) or whether a full binary clone is needed (use mongodump/mongorestore). The _id field in MongoDB is an ObjectId that is the authoritative PK — unlike SQL Server identity columns, ObjectIds are globally unique and survive cross-database migration without conflict.

**Verification block:** URL fetched. mongoimport --mode option documented: "Describes how to handle existing documents in the destination. Can be 'insert', 'upsert', 'merge', or 'delete'." Quote confirmed from MongoDB docs.

---

### Finding 11: MySQL AUTO_INCREMENT requires no special permission to insert explicit values

**Evidence:**
```
For a column with an AUTO_INCREMENT attribute, any row that has the column set
to 0, NULL, or not set at all causes an automatic value to be generated.
Otherwise, the value is used as-is.
```
After import with explicit values, MySQL automatically adjusts the sequence to MAX(column)+1.

**Source:** MySQL 8.0 Reference Manual — LOAD DATA INFILE; quoted in auxiliary `script-discipline-bulk-migration_doc_2.txt`

**Significance:** Unlike SQL Server (requires IDENTITY_INSERT ON with ddl_admin rights) and Oracle (requires ALTER TABLE to GENERATED BY DEFAULT), MySQL accepts explicit AUTO_INCREMENT values with no special mode and no elevated permissions. This simplifies MySQL cross-database migration significantly. The LOAD DATA INFILE tool supports a CHARACTER SET clause for encoding specification.

**Verification block:** URL fetched. Verbatim quote from MySQL 8.0 docs: "Otherwise, the value is used as-is." Quote confirmed in auxiliary doc_2.txt.

---

### Finding 12: MySQL 8.0 utf8mb4 collation change from 5.7 can break cross-version migrations

**Evidence:**
```
The default character set is utf8mb4 and the default collation for utf8mb4
changed from utf8mb4_general_ci (MySQL 5.7 and earlier) to
utf8mb4_0900_ai_ci (MySQL 8.0.1+).
```

**Source:** MySQL 8.0 Reference Manual; quoted in auxiliary `script-discipline-bulk-migration_doc_2.txt`

**Significance:** A migration from MySQL 5.7 to 8.0 (or across databases with different versions) can produce "Illegal mix of collations" errors on string comparisons. The same pattern as SQL Server's COLLATE DATABASE_DEFAULT applies here: specify the collation explicitly on the comparison or normalize column collations during migration.

**Verification block:** URL fetched. Quote confirmed in auxiliary doc_2.txt (MySQL 8.0 docs section on character set defaults).

---

### Finding 13: Oracle GENERATED ALWAYS AS IDENTITY requires ALTER TABLE before SQL*Loader

**Evidence:**
```sql
-- Step 1: Change to allow explicit values
ALTER TABLE target_table
  MODIFY id_column GENERATED BY DEFAULT AS IDENTITY;

-- Step 2: Load with SQL*Loader

-- Step 3: Revert with high-water mark reset
ALTER TABLE target_table
  MODIFY id_column GENERATED ALWAYS AS IDENTITY (START WITH LIMIT VALUE);
```

**Source:** Oracle Documentation — SQL*Loader and CREATE TABLE reference; quoted in auxiliary `script-discipline-bulk-migration_doc_2.txt`

**Significance:** Oracle is the most restrictive of the five engines — GENERATED ALWAYS cannot be bypassed even with bulk load tools without a DDL change. The ALTER TABLE requires DDL permissions on the table. The `START WITH LIMIT VALUE` syntax (Oracle 12c+) is the clean post-import sequence reset that sets the sequence to MAX(existing)+1 without requiring a manual MAX query.

**Verification block:** URL fetched. The ORA-32795 error behavior for GENERATED ALWAYS is documented in Oracle error reference. The ALTER TABLE ... MODIFY ... GENERATED BY DEFAULT pattern is documented in Oracle CREATE TABLE reference. Quoted in auxiliary doc_2.txt.

---

### Finding 14: Three-script pattern wraps bulk migrations — mutation step is the bulk tool

**Evidence:**
`SCRIPT-DISCIPLINE.md` Rule 2 defines the three-script pattern:
- Script 1 (Pre-flight): validates state without mutating
- Script 2 (Mutation): applies the change, logs per-record
- Script 3 (Verification): re-reads records, compares against expected end-state

From `SCRIPT-DISCIPLINE.md` (`/Users/plribeiro3000/.claude/docs/SCRIPT-DISCIPLINE.md`, lines 43–73):
```
Once a bucket is identified, every mutation goes through three scripts, in order.
No exceptions, no merging steps.
```

**Source:** `/Users/plribeiro3000/.claude/docs/SCRIPT-DISCIPLINE.md` lines 43–44

**Significance:** A bulk migration (bcp, pg_dump/psql, mongodump/mongorestore, etc.) maps onto the three-script pattern as follows: Script 1 validates source row counts, PK conflicts, and encoding; Script 2 IS the bulk tool invocation (bcp in, pg_restore, mongorestore, etc.); Script 3 counts loaded rows and spot-checks representative records. The three-script pattern is not replaced by a bulk tool — it wraps it. This is the key structural insight for the new SCRIPT-DISCIPLINE.md section.

**Verification block:** File read at stated path. Verbatim quote: "Once a bucket is identified, every mutation goes through three scripts, in order. No exceptions, no merging steps." Confirmed at lines 43–44.

---

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| bcp queryout "generate SQL text" | Works with DML-only permissions; no IDENTITY_INSERT needed for the generation phase; output is human-readable SQL | Slow for large volumes; sqlcmd loading of generated SQL has -W/-y flag incompatibility; each row is a separate transaction unless batched | Finding 1, Finding 3 |
| bcp in/out with native format + -E | Fast bulk transfer; preserves identity values | Requires ddl_admin or sysadmin permissions for IDENTITY_INSERT; not available with DML-only access | Finding 1, Finding 6 |
| PostgreSQL COPY FROM | Implicitly handles GENERATED ALWAYS; no special permission needed | Sequence NOT automatically reset post-import; must run setval() manually or subsequent INSERTs collide | Finding 8 |
| pg_dump -Fc + pg_restore | Selective table restore; parallel restore; compressed | Requires compatible pg_dump/pg_restore version pair; more complex than plain SQL | Finding 9 |
| MongoDB mongoimport --mode upsert | Natural-key matching; idempotent reruns; allows data transformation | JSON only (no BSON type fidelity unless Extended JSON); per-collection (not database-level) | Finding 10 |
| MongoDB mongorestore | Full database binary restore; fast; BSON-faithful | Insert-only (no update of existing docs); cross-version BSON format changes | Finding 10 |
| MySQL LOAD DATA INFILE | No special permission for explicit AUTO_INCREMENT; CHARACTER SET clause for encoding | File must be accessible on server (LOCAL modifier for client-side file); potential collation mismatch between 5.7 and 8.0 | Finding 11, Finding 12 |
| Oracle SQL*Loader with DDL workaround | Full control; START WITH LIMIT VALUE is clean post-import reset | Requires DDL permissions; 3-step process with rollback risk if Step 3 is missed | Finding 13 |
| FK remap by natural key | Works with DML-only permissions; cross-engine | Natural key must be truly unique; adds post-import work; fails if no natural key exists | Finding 6 |
| 2-phase rename via temp offset | Handles overlapping PK ranges | Brittle if temp range collides; staging-table alternative is safer | Finding 7 |

---

## What remains uncertain

- Whether the sqlcmd Go variant (`sqlcmd` v1.x CLI, not ODBC) installed as mssql-tools18 behaves differently from the ODBC variant for flags -W, -y, -I. The ODBC variant is the one that ships with mssql-tools on Linux; the Go variant is the newer replacement but docs confirm -I is ignored there.
- Whether there is a Debian 13 workaround from Microsoft that post-dates this spike (the GPG key bug may have been fixed in a Microsoft repo update after 2026-06-26).
- Whether 4Shark's Azure SQL instances run at a permission level where IDENTITY_INSERT is grantable to the migration user — not researched because SCRIPT-DISCIPLINE.md is engine-agnostic.
- Whether the 2-phase rename approach (Finding 7) has an authoritative citation in a SQL Server migration guide; only community sources were found.
- The exact BSON version compatibility matrix across MongoDB versions for mongodump/mongorestore — not fully researched; MongoDB docs note cross-version migration caveats but do not list a complete compatibility matrix.

---

## Suggested options for main and the engineer

### Option A: Add as "Rule 5 — Bulk Cross-Database Export/Import"

Extend SCRIPT-DISCIPLINE.md with a fifth numbered rule under "The Rule" list header (current Rules 1–4), then add a new `## Rule 5 — Bulk Cross-Database Export/Import` section. This places bulk migration on equal footing with the existing rules, implying it is a universal discipline.

Trade-off: Rule 5 only applies when data moves across databases, unlike Rules 1–4 which apply to every production data script. Numbering it as a rule implies the same universality.

### Option B: Add as a new top-level section "## Bulk Cross-Database Export/Import" (not a numbered Rule)

Add the section after the four Rules and before "## Why This Exists". The section header would match the pattern of "## Migration Data Staged to S3 — Retention and Cleanup" (which is also not a numbered Rule). This clearly scopes it as a specialized section that extends the framework rather than a universal principle.

Trade-off: The section is less prominent — engineers scanning the Rules may not reach it. But it is structurally honest about the narrower applicability.

### Option C: Add as a separate document "SCRIPT-DISCIPLINE-BULK-MIGRATION.md" under docs/

Keep SCRIPT-DISCIPLINE.md focused on the interactive console/rake-task flow and create a sibling document for the bulk migration case. SCRIPT-DISCIPLINE.md would link to it.

Trade-off: Avoids bloating SCRIPT-DISCIPLINE.md; easier to find when the engineer searches for "bulk migration". Downside: the three-script wrapping pattern (Finding 14) — which is the critical connection between both documents — must be stated in two places or the link is load-bearing.

### Content for the new section (engine-specific cheat sheet)

Regardless of which option is chosen, the content should include:

**SQL Server / Azure SQL:**
- Export: `bcp queryout` with a SELECT that emits SQL text when IDENTITY_INSERT is unavailable; `bcp out` with `-E` when identity preservation is needed and ddl_admin permission exists
- Import: `sqlcmd -I` for filtered index targets (default QUOTED_IDENTIFIER is OFF); `-W` incompatible with `-y`/`-Y`
- Identity: IDENTITY_INSERT requires ddl_admin; with DML-only permissions, import without PKs and remap FKs by natural key
- Collation: COLLATE DATABASE_DEFAULT on cross-database comparisons
- Tooling on Linux/Debian 13: GPG key EE4D7792F748182B bug — use Debian 12 repo or pre-built Docker image

**PostgreSQL:**
- Export: `pg_dump -Fc` for selective restore; `-Fd -j N` for parallel large-DB dump
- Import: `pg_restore -t tablename` for selective; `psql` for plain SQL
- Identity: COPY FROM implicitly overrides GENERATED ALWAYS; INSERT requires OVERRIDING SYSTEM VALUE
- Sequence reset required post-import: `SELECT setval(pg_get_serial_sequence(...), MAX(col)) FROM table`

**MongoDB:**
- `mongoexport`/`mongoimport` for selective/transforming: use `--mode upsert --upsertFields natural_key_field`; use `--jsonFormat canonical` for BSON type preservation
- `mongodump`/`mongorestore` for full binary clones; mongorestore is insert-only
- _id (ObjectId) is globally unique; no FK remap needed if _id values are preserved

**MySQL / MariaDB:**
- `LOAD DATA INFILE` with `CHARACTER SET utf8mb4`
- AUTO_INCREMENT: accepts explicit values with no special mode
- Collation mismatch between 5.7 and 8.0: utf8mb4_general_ci vs utf8mb4_0900_ai_ci

**Oracle:**
- SQL*Loader: ALTER TABLE ... MODIFY column GENERATED BY DEFAULT AS IDENTITY before load; revert with START WITH LIMIT VALUE after
- Data Pump (expdp/impdp): schema-level binary; new sequence created automatically on import; known 12.1 sequence restart bug fixed in 12.2
