# PLAN — Moving each app database onto its environment's own KMS key

## What this is

The command-level procedure for the last surface of the KMS key-per-environment migration. It exists to be executed **manually once on a non-productive environment**, corrected against what actually happens, and only then turned into a skill plus a binary — the same shape `mongodb-reprovision` has, where the script owns the dangerous repetitive half and the engineer owns the Terraform and the gates.

Written before the first manual run, so **every step is a hypothesis until it is executed**. Steps that have already been verified against AWS or the live configuration are marked; the rest are not, and the point of the manual run is to find out where this document is wrong.

## Why one procedure covers all four environments

Three environments run Aurora clusters and one runs a single plain instance. That looked like it would need two procedures and it does not, because **PostgreSQL logical replication is a feature of the engine's SQL layer, not of the managed service**. The same publication/subscription mechanics work on both.

What was ruled out, and why it matters that it was tried rather than reasoned about:

- **Editing the key in place** — impossible on either. AWS: *"Once you have created an encrypted DB cluster, you can't change the KMS key used by that DB cluster."*
- **An extra reader in the existing Aurora cluster, encrypted differently** — impossible. Encryption belongs to the shared cluster volume: *"Each DB instance in the DB cluster shares the same storage encrypted with the same KMS key."*
- **A read replica of the plain instance, encrypted with the new key** — refused by AWS at apply time: `The KMS key parameter isn't required for this DB instance read replica request`. A same-Region replica inherits its source's key; the key option on a replica is for the cross-Region case, where a destination-Region key is mandatory because keys are regional. **This cost one failed apply on the non-productive environment, which is exactly where it should have cost something.**
- **Blue/green deployments** — blocked outright: *"Blue/green deployments don't support managing master user passwords with AWS Secrets Manager"*, and every environment here manages its master password that way.

## Verified before starting

- **`rds.logical_replication` is already `1` in every parameter group in the fleet** (`aurora-postgresql16`, `aurora-postgresql17`, `postgresql18`). The parameter is static, so had it been off, enabling it would have required rebooting a production writer before replication could begin. It is not off. No reboot anywhere.
- **No application resolves a database identifier.** Applications resolve the pooler's internal record; the pooler receives its backend host as a Terraform module reference. So the replacement can keep a new permanent name and the cutover is a pooler repoint.
- **The schema has no obstacle to logical replication in two of its four documented gaps**: 166 tables, every one with a simple primary key, and zero views or materialized views. The two remaining gaps (DDL, sequences) are steps below, not risks.
- **Connectivity for the manual run is the VPN.** Each database security group admits PostgreSQL from the Management VPC, and RDS allows no host access, so the whole procedure runs as `psql` from the engineer's machine over the VPN — there is nothing to SSH into.

## The first run — concrete values

The non-productive single-instance environment, applied 2026-07-30. Both databases are `available` and the target is confirmed on the environment's own key.

| | Source | Target |
|---|---|---|
| Identifier | `app-beta-001` | `app-beta-001-2` |
| Endpoint | `app-beta-001.cvw5l7p4adp1.us-east-1.rds.amazonaws.com` | `app-beta-001-2.cvw5l7p4adp1.us-east-1.rds.amazonaws.com` |
| Master user | `postgres` | `postgres` |
| Master secret | `arn:aws:secretsmanager:us-east-1:405749097490:secret:rds!db-389b3244-2300-47e0-9348-64484f2bcc5a-kiTdaQ` | `arn:aws:secretsmanager:us-east-1:405749097490:secret:rds!db-a8ed4c14-7f58-4841-8c90-1efdb86e2f17-JvRwbd` |
| KMS key | shared master | `alias/app-beta-001` |

Application database: `app_beta_001`. Pooler record the application resolves: `connection-pooler-beta-001.4shark.internal`.

The two masters have **different** passwords — each instance manages its own secret — so a dump-from-source-into-target sequence needs both, retrieved separately.

## The procedure

Placeholders: `<source-host>` and `<target-host>` are the two endpoints, `<dbname>` the application database, `<master-user>` the master role. The master password lives in Secrets Manager and is retrieved by the engineer into their own shell — it is never printed into a session.

### Phase 1 — Prepare the target (no effect on the source)

The target comes up empty. It needs the roles, the database, and the schema before a subscription can attach.

**1.1 Roles first, and this is the step most likely to be forgotten.** Logical replication does not carry roles — they are cluster-level objects, not table data. The application role and the pooler's roles must exist on the target or the schema restore fails on ownership and the pooler cannot authenticate after cutover.

```bash
pg_dumpall --roles-only --host <source-host> --username <master-user> --file /tmp/roles.sql
```

Review that file before loading it: `pg_dumpall` emits the RDS-internal roles too, and loading those either fails or is a no-op. Then load what is genuinely ours:

```bash
psql --host <target-host> --username <master-user> --dbname postgres --file /tmp/roles.sql
```

**1.2 Create the database.** The Terraform modules do not expose `database_name`, so this is deliberate and manual.

```bash
psql --host <target-host> --username <master-user> --dbname postgres --command "CREATE DATABASE <dbname>;"
```

**1.3 Load the schema, structure only.**

```bash
pg_dump --schema-only --no-owner --no-privileges --host <source-host> --username <master-user> --dbname <dbname> --file /tmp/schema.sql
```

```bash
psql --host <target-host> --username <master-user> --dbname <dbname> --file /tmp/schema.sql
```

`--no-owner --no-privileges` is deliberate: ownership is reapplied by the roles loaded in 1.1 rather than baked into the dump, which keeps the restore from failing on a role that has a different OID on the target. **Unverified** — whether this is the right combination for our schema is one of the things the manual run establishes.

### Phase 2 — Start replication

**2.1 Freeze schema migrations for the whole window.** DDL is not replicated: *"Data definition language (DDL) statements, such as CREATE TABLE and CREATE SCHEMA, aren't replicated"*. A migration mid-window desynchronises the target silently — the subscription keeps reporting healthy while the table shapes diverge. This is a deploy-pipeline decision, not a database one.

**2.2 Publication on the source.** Requires `rds_superuser`.

```bash
psql --host <source-host> --username <master-user> --dbname <dbname> --command "CREATE PUBLICATION key_migration FOR ALL TABLES;"
```

**2.3 Subscription on the target.** The connection string carries the master password, so this command is composed and run by the engineer with the value from their own shell — it is the one command in this procedure that cannot be copied verbatim from a document.

```
CREATE SUBSCRIPTION key_migration
  CONNECTION 'host=<source-host> dbname=<dbname> user=<master-user> password=<from-secrets-manager>'
  PUBLICATION key_migration;
```

`copy_data` defaults to true, which is what performs the initial load. That is the whole reason the target was created empty.

### Phase 3 — Watch it catch up

On the target, the per-table state — every table must reach `r` (ready); anything stuck in `d` (initial copy) or `s` is still loading:

```bash
psql --host <target-host> --username <master-user> --dbname <dbname> --command "SELECT srsubstate, count(*) FROM pg_subscription_rel GROUP BY srsubstate;"
```

On the source, the lag in bytes:

```bash
psql --host <source-host> --username <master-user> --dbname <dbname> --command "SELECT application_name, state, pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes FROM pg_stat_replication;"
```

**This is where the first real number gets measured**: how long the initial copy takes. It is unknown, and it is the number that decides whether the productive cutover is scheduled for a quiet hour or can happen any time.

### Phase 4 — Verify the target independently

Before any traffic moves, compare row counts per table between source and target, and exercise the application's own read paths against the target. A subscription reporting `r` on every table is not the same as the data being right.

**Unverified**: the exact comparison query, and whether a count mismatch on a high-write table is real drift or just replication lag caught mid-flight.

### Phase 5 — The cutover

The only phase with a window. Order matters and each step has a reason.

1. **Stop writes.** How is an open question — scaling the application's writers to zero is the blunt version, and whether something gentler exists is worth establishing during the non-productive run.
2. **Confirm zero lag** with the Phase 3 queries. Not "small" — zero.
3. **Advance every sequence on the target past the source's current value.** Sequences are not replicated: *"NEXTVAL operations on sequence objects aren't synchronized"*. AWS performs this step itself during a blue/green switchover, which is precisely the work inherited here. Miss it and the first inserts after cutover collide on primary keys. The SQL to generate this has to be written and is not in this document yet — the manual run is where it gets written.
4. **Repoint the pooler** at the target's endpoint and apply. This changes the pooler's task definition, so its tasks are replaced. **Whether the application's connections survive that replacement is the single least-examined step in the whole migration, and it is identical across all four environments** — which is why the non-productive run matters even though its data is worthless.
5. **Resume writes.**
6. **Drop the subscription and the publication.** Leaving them keeps a replication slot open on a database that is about to be destroyed.

### Phase 6 — Retire the source

Only after a defined period of the target serving without incident. `deletion_protection` is `true` on every database here, so it comes off deliberately as the last step — that is the irreversible one.

## What becomes the binary, and what stays with the engineer

Following `mongodb-reprovision`'s split, which exists because the dangerous half of that procedure is repetitive and easy to get wrong by hand while the Terraform half needs judgment:

**The script owns** the observation and the mechanical SQL — Phase 3's lag and per-table state, Phase 4's row-count comparison, Phase 5's sequence-advancement SQL generation, and the publication/subscription creation and teardown. These are the steps that are identical every time and where a typo is expensive.

**The engineer owns** the Terraform (declaring the target, repointing the pooler, retiring the source), every apply, the migration freeze, the write freeze, and the go/no-go at the cutover gate.

**Phase 5 should be indivisible in the script**, the way `mongodb-reprovision`'s `cutover` is: between stopping writes and repointing the pooler there is a window where the system is neither fully on the source nor on the target, and a checkpoint parked inside it is worse than passing through it.

## Order of execution across the four environments

The non-productive single-instance environment goes first — it is the smallest, its data does not matter, and it exercises the identical pooler repoint. Then the non-productive cluster, which is the first Aurora run and validates the cluster-shaped half. The two productive environments follow, and by then nothing in this document should still be marked unverified.
