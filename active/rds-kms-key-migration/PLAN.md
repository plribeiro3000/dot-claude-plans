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

## State

The non-productive single-instance environment is **done**. It runs on one database, `app-beta-001`, in `us-east-1b`, encrypted under the environment's own key, with the predecessor destroyed and its AWS Backup recovery points retained.

Reaching that took **two** migrations rather than one. The first moved the data onto the environment's key but had to create the replacement under a suffixed identifier, because the original still held the name. The second corrected the name. An instance's identifier is fixed at creation as far as Terraform is concerned — AWS supports an in-place rename that the provider does not expose — so a name is not editable, it is a second copy. **Name the replacement the way the environment should be named forever, before any data moves.**

Three environments remain: the non-productive cluster, then the two productive ones. Each is Aurora, so each is also the first test of the cluster-shaped half of the procedure.

## Paying nothing for the copy is a REQUIREMENT, not an optimization

The replication that fills a replacement is ordinary network traffic and it is billed like any other. Transfer between two instances in the **same** Availability Zone over private addressing is free; crossing zones is metered on **both** ends. A migration is therefore free or expensive depending on one placement decision made at creation, and `availability_zone` is fixed at creation too — there is no correcting it afterwards.

On beta this was settled by pinning the replacement to the source's zone and confirming both reported `us-east-1b` before any data moved. The same guarantee has to be **established** for each remaining environment rather than assumed, and two things make that harder than repeating the beta step:

The first is size. The largest productive environment holds roughly 350 GB, so a cross-zone copy there is metered on both ends of 350 GB — and the identifier correction means the copy can happen twice. That is the whole reason the naming rule above is stated as a rule.

The second is that **Aurora's pricing statements do not transfer to this case, and reading them as though they do is the trap.** Aurora documents that data transferred between Availability Zones for *DB cluster replication* is free — that covers a cluster replicating to its own members, not logical replication between two separate clusters, which is what a key migration runs. Nothing verified so far establishes how the second case is billed. **Before the first Aurora copy starts, that question has to be answered from AWS's own pricing documentation, and the placement has to be arranged so the answer does not matter** — same zone, proven by describing both sides, exactly as on beta.

## Every environment needs its pooler checked BEFORE its cutover

The cutover is zero-downtime only because the pooler can be told to hold clients, and that requires console access. The pooler decodes its userlist once, at container start, from a secret reference that carries no version — so a later change to the secret produces no new task definition, ECS never rolls the tasks, and the running process serves forever with the credentials it read at boot. Nothing reports the divergence; it surfaces as an authentication failure at the moment the console is needed.

Measured across the fleet, all four environments were in that state: pooler tasks started around 14:00 and userlist secrets last changed between 16:07 and 16:32 the same day. Beta was resolved by rolling its pooler service, which drops the client connections the tasks hold — acceptable there, and the reason it must never be discovered inside a pause window.

So each remaining environment needs, as a scheduled step of its own: compare each pooler task's `startedAt` against the userlist secret's `LastChangedDate`, prove console access with a real `SHOW DATABASES`, and roll the service if the tasks are older. On the productive environments that roll rides the existing Sidekiq queue check, the same window a deploy uses.

The durable repairs — pinning the secret's version in the task definition so a content change produces a revision the service adopts, and enabling ECS Exec so a stale container is repairable in place with SIGHUP instead of a restart — are their own change to `modules/connection_pooler`, and they land before the productive environments.

## The procedure

### Phase 0 — Reachability, on both legs, before anything downstream

**A migration introduces two network paths that did not exist before, and each one is confirmed before the step that depends on it — never assumed and never discovered by the step failing.**

The two legs, and where each is needed:

| Leg | Needed at | Consequence if missing |
|---|---|---|
| target → source, 5432 | Phase 2, `CREATE SUBSCRIPTION` | replication never starts; discovered after a cluster exists and a full schema is loaded |
| application → target, 5432 | Phase 5, the repoint | the application cannot connect after the cutover — inside the write window, with the source already stopped |

The second leg is the more dangerous of the two even though it is usually the one that already holds. Its failure lands *inside the cutover window*, when writes are stopped and the fallback is a second repoint under time pressure. **The check costs one API call and is not conditional on suspicion** — run it whenever a database is being replaced, including when the replacement "is obviously in the same place", because *obviously* is the assumption a migration exists to invalidate. A future migration that crosses a VPC, a subnet group or an account will not announce itself.

**Leg 1 — target reaches source.** Each environment's database security group admits PostgreSQL from the application cluster, from the connection pooler, and from the Management VPC. It does not admit itself. That was correct for as long as an environment had exactly one database — nothing else ever needed to reach it. A migration creates a second database in the same group, and logical replication requires that second database to connect back to the first, which no existing rule allows. The failure is late and expensive: everything up to and including the schema load succeeds, and only `CREATE SUBSCRIPTION` fails, with `could not connect to the publisher ... Connection timed out`.

The rule to add, in each environment's `rds.tf`, inside the database security group:

```hcl
  ingress {
    description = "PostgreSQL between databases in this group (logical replication during a key migration)"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    self        = true
  }
```

`self = true` lets any member of the group reach any other on 5432 and opens nothing to anything outside it. Source and target already share the group, so no second group is needed.

**Leg 2 — the application reaches the target.** The application does not connect to the database directly: it resolves the connection pooler, and the pooler holds the backend host as a Terraform reference (`host = module.rds_instance.address` in each stack's pooler `databases` block). So the party whose reachability matters is the **pooler's** security group, and the repoint is a Terraform edit the application never sees.

The check is a comparison, not a judgement — describe both instances and confirm the target's network is the same object as the source's:

```bash
aws rds describe-db-instances --db-instance-identifier <target> --region us-east-1 --query 'DBInstances[0].{SG:VpcSecurityGroups[].VpcSecurityGroupId,Subnets:DBSubnetGroup.Subnets[].SubnetIdentifier,VPC:DBSubnetGroup.VpcId}'
```

Run it for source and target. **Identical VPC + subnets + security group is the pass** — the two databases are then behind the same network object and nothing that reaches one can fail to reach the other. For an Aurora target the same question is asked of `describe-db-clusters` plus its instances.

Any difference is a Blocker, not a detail to work around at cutover time: a different security group needs the pooler's group added to the target's ingress, and a different VPC or subnet group needs routing and a Cloud Map zone association resolved before Phase 1 is worth starting.

**Confirm both legs at once** before proceeding, by reading the target group's ingress:

```bash
aws ec2 describe-security-groups --group-ids <target-sg-id> --region us-east-1 --query "SecurityGroups[0].IpPermissions"
```

Leg 1 passes when a `UserIdGroupPairs` entry names the group's **own** id. Leg 2 passes when another entry names the **pooler's** group id — resolve that id by name rather than trusting the description text:

```bash
aws ec2 describe-security-groups --group-ids <id> <id> --region us-east-1 --query 'SecurityGroups[].{Id:GroupId,Tags:Tags[?Key==`Name`].Value|[0]}'
```

Placeholders: `<source-host>` and `<target-host>` are the two endpoints, `<dbname>` the application database, `<master-user>` the master role. The master password lives in Secrets Manager and is retrieved by the engineer into their own shell — it is never printed into a session.

### Phase 1 — Prepare the target (no effect on the source)

The target comes up empty. It needs the roles, the database, and the schema before a subscription can attach.

**1.1 Roles first, and this is the step most likely to be forgotten.** Logical replication does not carry roles — they are cluster-level objects, not table data. The application role and the pooler's roles must exist on the target or the schema restore fails on ownership and the pooler cannot authenticate after cutover.

```bash
pg_dumpall --roles-only --no-role-passwords --host <source-host> --username <master-user> --file /tmp/roles.sql
```

`--no-role-passwords` is mandatory, not a preference: the RDS master is not a superuser, so reading password verifiers fails with `permission denied for table pg_authid` and the dump produces nothing at all.

Review that file before loading it: `pg_dumpall` emits the RDS-internal roles too, and loading those either fails or is a no-op. Then load what is genuinely ours:

```bash
psql --host <target-host> --username <master-user> --dbname postgres --file /tmp/roles.sql
```

**1.1a The application role arrives with no password, and how you restore it decides whether the pooler works after cutover.**

Setting it from the plaintext the application uses is the obvious move and it is **wrong**. `password_encryption` is `scram-sha-256`, so `ALTER ROLE ... PASSWORD '<plaintext>'` stores a **SCRAM** verifier. The pooler's userlist holds an **md5** verifier for that role (`auth_type = md5`), and md5 is all it can answer with — a server holding a SCRAM verifier demands SCRAM, and the pooler cannot compute SCRAM from an md5 hash. Everything looks correct until the repoint, and then the pooler cannot reach the target **inside the cutover window**.

Copy the verifier instead. PostgreSQL accepts a pre-hashed md5 string verbatim, and the md5 verifier is `md5(password || rolename)` — bound to the role name, which is identical on both sides, so the transplant is exact. PostgreSQL 18 accepts it with a deprecation warning; support runs through v20 ([release notes](https://www.postgresql.org/docs/18/release-18.html)).

```bash
aws secretsmanager get-secret-value --secret-id <env>-connection-pooler-userlist --region us-east-1 --query SecretString --output text > /tmp/userlist_b64.txt
base64 --decode -i /tmp/userlist_b64.txt -o /tmp/userlist.txt
sed -n "s/^\"<app-role>\" \"\(md5[0-9a-f]\{32\}\)\".*/ALTER ROLE \"<app-role>\" PASSWORD '\1';/p" /tmp/userlist.txt > /tmp/set_app_role_password.sql
psql --host <target-host> --username <master-user> --dbname <dbname> --set ON_ERROR_STOP=1 --file /tmp/set_app_role_password.sql
```

The verifier never passes through a terminal or a session — it moves file to file. Delete `/tmp/userlist*.txt` and the generated `.sql` as soon as the `ALTER ROLE` returns.

**Then prove it, rather than reasoning about it.** The application's plaintext password lives in `/<env>/DATABASE_URL` (SSM, `SecureString`), which is what makes a real end-to-end login test possible:

```bash
psql --host <target-host> --username <app-role> --dbname <dbname> --command "SELECT current_user; SELECT count(*) FROM information_schema.table_privileges WHERE grantee = current_user AND privilege_type = 'SELECT';"
```

A successful login proves the verifier; the privilege count matching the table count proves the schema load carried the grants. Delete the extracted password file afterwards.

**1.2 Create the database.** The Terraform modules do not expose `database_name`, so this is deliberate and manual.

```bash
psql --host <target-host> --username <master-user> --dbname postgres --command "CREATE DATABASE <dbname>;"
```

**1.3 Load the schema, structure only — preserving ownership, inside a transaction.**

Check who owns the application tables on the source first. The answer decides whether the dump may strip ownership, and on this application it may not:

```bash
psql --host <source-host> --username <master-user> --dbname <dbname> --command "SELECT tableowner, count(*) FROM pg_tables WHERE schemaname='public' GROUP BY tableowner;"
```

Every application table is owned by the application role, not by the master. A dump taken with `--no-owner` would leave them all owned by the master on the target, and the application — which connects as its own role — could not write after cutover. So the dump preserves ownership, which is `pg_dump`'s default:

```bash
pg_dump --schema-only --host <source-host> --username <master-user> --dbname <dbname> --file /tmp/schema.sql
```

The load is **atomic, and this is not optional**:

```bash
psql --host <target-host> --username <master-user> --dbname <dbname> --single-transaction --set ON_ERROR_STOP=1 --file /tmp/schema.sql
```

Without those two flags an interrupted load leaves a half-built schema that the next run silently completes around, producing a database assembled from two runs and reporting `already exists` errors that look harmless. With them, an interruption rolls back to empty and the operator simply runs it again.

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

**`SELECT count(*)` is forbidden here, on either side.** Some productive tables hold hundreds of millions of rows, and a count is a full scan — run against the source, that is a full scan of the database serving customers, to prove something the engine already guarantees. It is affordable on the smallest environment and catastrophic on the largest, which makes it exactly the kind of step that passes a rehearsal and then hurts.

What replaces it rests on the guarantee PostgreSQL actually makes:

> "The subscriber applies the data in the same order as the publisher so that transactional consistency is guaranteed for publications within a single subscription."

Consistency is a property of the mechanism, not something to be re-established by comparing every row. So verification proves the **mechanism is healthy** — all constant-cost — and then samples cheaply for gross error.

**Health, four checks, none of which touch table data.** Every table finished its initial copy (`r`); the stream is live and caught up; and nothing has failed silently — that last one is the check that matters most, because an apply error stops replication while every other indicator still looks plausible:

```bash
psql --host <target> --dbname <db> --command "SELECT srsubstate, count(*) FROM pg_subscription_rel GROUP BY srsubstate;"
psql --host <source> --dbname <db> --command "SELECT application_name, state, pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes FROM pg_stat_replication;"
psql --host <target> --dbname <db> --command "SELECT subname, apply_error_count, sync_error_count, confl_insert_exists, confl_update_origin_differs, confl_delete_missing FROM pg_stat_subscription_stats;"
psql --host <target> --dbname <db> --command "SELECT subname, pid, received_lsn, latest_end_lsn FROM pg_stat_subscription;"
```

**Sampling — `min(id)`/`max(id)` per table, which a primary-key btree answers by index scan rather than by reading the table.** Identical boundaries on both sides across every table is strong evidence against gross divergence, at logarithmic cost per table instead of linear:

```bash
psql --host <host> --dbname <db> --tuples-only --no-align --command "SELECT c.relname||'='||coalesce((xpath('/row/lo/text()', x))[1]::text,'-')||':'||coalesce((xpath('/row/hi/text()', x))[1]::text,'-') FROM (SELECT c.oid, c.relname, query_to_xml(format('SELECT min(id) AS lo, max(id) AS hi FROM public.%I', c.relname), false, true, '') AS x FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_attribute a ON a.attrelid=c.oid AND a.attname='id' AND NOT a.attisdropped WHERE n.nspname='public' AND c.relkind='r') c ORDER BY c.relname;"
```

Run it against both and `diff` the two outputs. An empty diff is the pass.

**`pg_stat_user_tables.n_live_tup` is NOT a substitute.** It is the statistics collector's estimate, and on a freshly-loaded target no `ANALYZE` has run yet — it reports differences on nearly every table while the data is identical. It belongs to the same family of traps as `information_schema`: a measurement that lies rather than a database that is wrong.

Then exercise the application's own read paths against the target. A subscription reporting `r` on every table is not the same as the application being able to use it.

**Every structural comparison reads the catalog, never `information_schema`.** The `information_schema` views are permission-filtered — they show only what the connecting user is allowed to see — so they report differences that do not exist whenever the master's privileges differ between the two databases. Counting columns through `information_schema.columns` reports a false mismatch here; counting them through `pg_attribute` reports equality:

```bash
psql --host <host> --username <master-user> --dbname <dbname> --tuples-only --command "SELECT count(*) FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r' AND a.attnum>0 AND NOT a.attisdropped;"
```

`pg_tables`, `pg_sequences`, `pg_indexes` and `pg_constraint` are catalog views and are safe for the same comparison.

**Unverified**: whether a row-count mismatch on a high-write table is real drift or replication lag caught mid-flight.

### Phase 5 — The cutover, with no downtime

**There is no maintenance window and no "stop writes" step.** Zero downtime at 4Shark is functional — no failed request, no dropped connection — so a cutover that pauses the application is not a shorter outage, it is an outage. The cutover holds clients instead of disconnecting them, and the pooler is what makes that possible.

Two properties of the running system are what the design rests on, and both are already true. The application never addresses the database — it resolves the pooler, which holds the backend host on its own. And the pooler runs `pool_mode = transaction`, so a server connection is released at the end of **each transaction** rather than when the client goes away.

That second one is the load-bearing fact. `PAUSE` *"tries to disconnect from all servers"*, and each disconnect *"waits for that server connection to be released according to the server pool's pooling mode"* — under transaction pooling that is the end of the current transaction, so `PAUSE` completes in milliseconds. Under session pooling it would wait for long-lived Rails connections to close, which is never. Meanwhile *"New client connections to a paused database will wait until RESUME is called"* — they block, they do not error, and that is precisely the difference between a pause and an outage.

**Two properties of the pooler are what the cutover runs on, and both are worth restating because losing either one silently removes the zero-downtime option.**

The console has an `admin_users` entry, generated per environment by `modules/connection_pooler`. Only that user can issue `PAUSE` — a `stats_users` entry is *"allowed to connect and run read-only queries on the console. That means all SHOW commands"*, which is not enough. Whether the running tasks still accept that credential is the check in the pooler section above; a task older than the userlist secret does not, and that is the failure that takes `PAUSE` away exactly when it is needed.

The pooler's backend `host` is a CNAME in the shared `4shark.internal` private zone, not an RDS endpoint. That is what keeps the repoint out of the task definition: naming the endpoint directly would make a repoint a new task-definition revision, ECS would replace the tasks, and the paused PgBouncer process would die holding every client connection — the pause would buy nothing. PgBouncer closes the loop natively, marking a server connection for recycling *"because a configuration file reload or DNS update changed the connection information or RECONNECT was issued"*, so a DNS change is a first-class trigger rather than a trick.

**Moving a pooler's `host` onto a CNAME is itself a task-replacing deploy**, so an environment that does not yet have one lands that change on an ordinary day, confirms the pooler is serving through the record, and lets cutover day change nothing but the record's target.

The cutover itself:

1. **`PAUSE <dbname>` on every pooler task.** Clients block and stay connected; in-flight transactions finish first. From this moment the source receives nothing from the application, which is what makes the next two steps well-defined — and it is a *hold*, not a stop.
2. **Confirm zero lag** with the Phase 3 queries. Not "small" — zero. The source is quiescent, so this converges immediately.
3. **Advance every sequence on the target to the source's current value.** Sequences are not replicated: *"NEXTVAL operations on sequence objects aren't synchronized"*. AWS performs this step itself during a blue/green switchover, which is precisely the work inherited here. Miss it and the first inserts after cutover collide on primary keys.

   Generate the statements from the source and run them on the target:

   ```bash
   psql --host <source-host> --username <master-user> --dbname <dbname> --tuples-only --no-align --command "SELECT 'SELECT setval(' || quote_literal(quote_ident(schemaname) || '.' || quote_ident(sequencename)) || ', ' || last_value || ', true);' FROM pg_sequences WHERE schemaname = 'public' AND last_value IS NOT NULL ORDER BY sequencename;" > /tmp/advance_sequences.sql
   psql --host <target-host> --username <master-user> --dbname <dbname> --set ON_ERROR_STOP=1 --file /tmp/advance_sequences.sql
   ```

   Two conditions make the exact value correct rather than a value plus a safety margin, and both are worth checking rather than assuming. **`last_value` must not be running ahead of what was issued** — it does when a sequence caches, so confirm `cache_size` is 1 everywhere with `SELECT cache_size, count(*) FROM pg_sequences WHERE schemaname='public' GROUP BY cache_size;`. And **generation must happen while the pooler is paused and lag is confirmed zero** — that ordering is what makes the source's `last_value` final. A margin would not buy safety here, it would only paper over a broken ordering while leaving gaps in every id column.

   **`last_value IS NOT NULL` is a filter, not an optimization.** A sequence that has never been used reports `NULL`, and it is already at its start value on the target because the schema load created it there. Calling `setval(..., true)` on one would make its first `nextval` return 2 and silently burn the value 1.
4. **Point the CNAME at the target.** A DNS record change — no `terraform apply` against the app stack, no task definition, no task replacement. Phase 0's leg 2 must already be confirmed, since this is the step it protects.
5. **`RECONNECT <dbname>`**, so resolution is fresh rather than left to the DNS cache expiring on its own. Its documented effect is to *"Close each open server connection for the given database, or all databases, after it is released"* — and the pooler holds no server connections at this point, because step 1 already released them.
6. **`RESUME <dbname>`.** The clients held since step 1 continue, now against the target. They never saw a disconnect — only latency, bounded by how long steps 2 through 5 took.
7. **Drop the subscription and the publication.** Leaving them keeps a replication slot open on a database that is about to be destroyed.

**What this design removes is the step that had no answer.** With the backend behind a CNAME the pooler's tasks are never replaced, so the question of whether the application's connections survive a task replacement stops being on the critical path — it is designed out rather than tested and hoped for. What the non-productive run still has to establish is the *duration* of the pause: steps 2 through 5 are the entire time clients spend blocked, and how long that is on a real dataset is the number that decides whether the productive environments need anything further.

### Phase 6 — Retire the source

Only after a period of the replacement serving without incident, and it is **two applies whose order the provider forces**. The first sets `deletion_protection = false` and `skip_final_snapshot = true`; the second removes the module block. Both arguments reach AWS only at deletion, and the protection is editable only while the resource is still declared, so a single apply that lifted it and deleted the declaration fails.

Skipping the final snapshot is deliberate and needs its evidence each time: AWS Backup already holds daily recovery points for these instances, so the snapshot would duplicate a backup that exists. Confirm the recovery points before accepting the skip — `aws backup list-recovery-points-by-resource --resource-arn <instance-arn>` answers it in one call.

Each apply is its own PR, which keeps one commit per pull request and makes each apply match a state a reviewer can read.

## What the binary owns, and what stays with the engineer

`rds-key-migration.sh`, alongside this document, follows `mongodb-reprovision`'s split: the script owns the dangerous repetitive half, the engineer owns the Terraform and every apply. It carries `preflight`, `status`, `verify`, `hold` and `release`.

**The script owns** the pre-conditions (client-versus-server version, logical replication, the network comparison, the zone match that keeps the copy free, the pooler-staleness check), the replication health queries, the catalog-and-boundaries verification, and the mechanical SQL of the window — the lag confirmation and the sequence advancement.

**The engineer owns** the Terraform (declaring the replacement, repointing the record, retiring the predecessor), every apply, and the migration freeze.

**The cutover is NOT one indivisible verb, and that is forced rather than chosen.** The apply that repoints the record sits inside the window where clients are held, and an apply is the engineer's approval — so the window opens with `hold` and closes with `release`, with the apply between them. Every other seam would park the system between two databases; this one already exists because the approval boundary creates it.

What is owed in the script: `prepare` — the roles, the application database, the md5 verifier transplant and the schema load, which beta ran by hand.

## Order of execution across the four environments

The order runs smallest and cheapest to fail first: the non-productive single-instance environment, then the non-productive cluster, then the two productive ones. The single-instance environment is complete. The non-productive cluster is next, and it is the first Aurora run — it validates the cluster-shaped half of every phase, and nothing in this document should still be unverified by the time a productive environment starts.

**Before an environment's migration begins, three things are settled in this order.** Its replacement's zone placement and the billing question above, because both are fixed at creation. Its pooler's console access, because the check is cheap and the failure is only discoverable when the window is already open. And its replacement's identifier, which is the name the environment keeps forever.

**One PR per environment, not one PR for all four.** A PR that declares every environment's replacement cannot be merged until every environment has been migrated, because 4Shark applies before merging — so the first environment's work would sit unmerged behind three that have not started, and every branch cut afterwards would have to stack on it or plan against infrastructure its own base does not describe. Scoping the PR to the environment being migrated keeps each one mergeable the moment its own apply is confirmed. The cutover, and each of the two teardown applies, are their own PRs for the same reason.

The three environments still waiting have **no replacement declared anywhere**. Each gets its own PR when its migration starts, shaped like the completed one's — same arguments, `rds_aurora_cluster` instead of `rds_instance`, one instance, the encryption key and the identifier and the zone all set at creation because none of them is editable afterwards, and the self-ingress rule on the security group so the replacement can be filled by replication.

**The pooler indirection is the exception to that split, and deliberately so.** The records and the admin user are the *mechanism* the cutover runs on rather than a per-environment resource, so they land once for all four. Applying that PR touches no running task — the records are new and resolve nothing yet, and the pooler's service ignores task-definition changes, so the new revision is registered without being adopted.
