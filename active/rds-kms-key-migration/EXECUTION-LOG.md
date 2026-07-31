# EXECUTION LOG — first manual run of the database key migration

The engineer's instruction was to execute the procedure by hand, record the commands and the problems as they happen, and build the skill and binary from that record afterwards. This is that record. It is written as it happens, so a wrong turn stays in it — the wrong turns are the point.

Environment: `app-beta-001` (non-productive, plain RDS PostgreSQL 18.4, 20 GB). Source `app-beta-001`, target `app-beta-001-2`, application database `app_beta_001`.

## Findings so far — each one changes the script's design

### 1. The client version must be checked against the server before anything

The machine had PostgreSQL 17.5 client tools; both databases are 18.4. `psql` is version-tolerant and works fine, but `pg_dump` and `pg_dumpall` **refuse** a server newer than themselves, which would have failed mid-procedure at the schema step rather than up front.

Installing the 18 client is blocked for the agent by the local-databases hook (*"one-time machine setup is not Claude's call"*), so the engineer ran `brew install postgresql@18`. Homebrew does not link a versioned formula onto the `PATH`, so the binaries are called by absolute path: `/opt/homebrew/opt/postgresql@18/bin/`.

**For the script**: check `pg_dump --version` against the server's `SELECT version()` as a pre-flight, fail with a clear message naming the install command, and never attempt the install itself.

### 2. Secrets Manager and the database were never reachable at the same time — and it was not the VPN

With the VPN connected, `aws secretsmanager list-secrets` and `get-secret-value` hung indefinitely — no error, no refusal — while `aws rds describe-db-instances` and `aws cloudwatch get-metric-statistics` answered normally. A request that eventually escaped returned `InvalidSignatureException: Signature expired`, which is the symptom of having sat unsent for six minutes, not the cause.

The diagnosis went wrong three times before it went right. It was called a permission prompt, then an expired signature, then a permission prompt again. What settled it was a discriminating test — swapping `get-secret-value` for `list-secrets`, which returns no secret value and hung identically, ruling out anything specific to reading a credential. The attribution to the VPN was then also wrong: the real cause was **the engineer's router advertising a broken IPv6 route**, which the engineer found and fixed. After the fix, `get-secret-value` returned immediately.

**For the script**: a hang with no output on an AWS API call is not a permission prompt and not a credentials problem — bound every AWS call with a timeout and report which endpoint stopped answering, so the next person does not spend three diagnoses on it.

### 3. The RDS secret ARN breaks interactive zsh

The ARN contains `!` (`rds!db-...`), which zsh expands as history. A command carrying it unquoted dies with `zsh: event not found: db` before running at all.

**For the script**: single-quote every secret ARN it emits or embeds.

### 4. `.pgpass` cannot hold an RDS-generated password reliably — use `PGPASSWORD`

`.pgpass` uses `:` as its field separator, and RDS's managed master password is 28 characters including punctuation, so it can contain a colon. It did here.

The failure is quiet and misleading: `libpq` finds the line and reports `password retrieved from file`, then fails authentication, so it reads as a wrong password rather than a malformed file. It was diagnosed structurally without reading any credential — `awk -F: '{print NF}'` showed **6 fields on the target line and 5 on the source line**, which is the whole story.

Escaping the colon as `\:` per the libpq format did **not** fix it, and the reason was not established — the attempt is recorded as failed rather than explained. What worked was abandoning the file entirely and passing `PGPASSWORD` from the secret at invocation time.

**For the script**: never write a `.pgpass`. Take the password into the environment for the single command that needs it. This also happens to be better hygiene — nothing durable on disk.

### 5. The two masters are independent

Source and target each manage their own secret with their own password. Anything that dumps from one into the other needs both, retrieved separately. The target's secret is encrypted under the environment's own key, which was set at creation because it is immutable afterwards.

### 6. `pg_dump --no-owner` was the wrong call, and the source told us so

The plan specified `--no-owner --no-privileges`, reasoning that ownership would be reapplied from the loaded roles. Checking the source first showed all 168 application tables are owned by the application role, not by `postgres`. Loading without ownership would have left every table owned by the master, and the application — which connects as its own role — could not have written after cutover. The dump was redone preserving ownership, and it carries 168 `ALTER TABLE ... OWNER TO` statements the first one lacked.

**For the script**: query `pg_tables.tableowner` on the source before dumping, and never strip ownership on a migration whose purpose is to replace the original.

### 7. A schema load MUST be atomic — an interrupted one leaves a silent half-state

The first load ran as a plain `psql --file`. It was interrupted, and it had already created the first six tables alphabetically before dying. The next run then reported twelve `already exists` errors and created everything else, leaving a database that looked complete and was assembled from two different runs.

The fix is two flags: `--single-transaction --set ON_ERROR_STOP=1`. Together they make the load all-or-nothing, so an interruption — including an operator pressing stop — rolls the database back to empty instead of leaving a state nobody can characterise.

**For the script**: no schema load ever runs outside a transaction. This matters far more on the Aurora environments, where the same half-state would be expensive rather than merely confusing.

### 8. `information_schema` is permission-filtered — verify structure against the CATALOG

Comparing source and target with `information_schema.columns` reported 1715 against 1721, a difference of six that survived dropping the database and reloading it atomically with zero errors. The partial-execution theory was wrong; the measurement was.

`information_schema` views show only the columns the connecting user is allowed to see, and the master's privileges differ between the two databases. Counting from `pg_attribute` — the catalog, which is not permission-filtered — returns **1655 on both**. Tables, sequences, indexes and constraints had matched all along from `pg_tables`, `pg_sequences`, `pg_indexes` and `pg_constraint`, which are catalog views; `information_schema` was the only one of the five that lied.

**For the script**: every structural comparison reads the catalog. A verification step that reports a false difference is worse than none, because it burns the operator's trust in the one check that is supposed to be authoritative — and here it nearly cost a second rebuild.

### 9. `count(*)` is forbidden on both sides — verify the mechanism, then sample by index

Comparing row counts table by table is the obvious verification and it is unusable here: `count(*)` is a full scan, productive tables hold hundreds of millions of rows, and the scan on the SOURCE runs against the database serving customers. It passes harmlessly on a small non-productive environment, which is exactly what makes it dangerous — it survives the rehearsal and costs on the run that matters.

The reframe is that the engine already guarantees what the count would re-derive: *"The subscriber applies the data in the same order as the publisher so that transactional consistency is guaranteed for publications within a single subscription."* So verification proves the **mechanism is healthy** and then samples cheaply.

Health is four constant-cost queries touching no table data — `pg_subscription_rel` (every table in state `r`), `pg_stat_replication` (`streaming`, zero lag), `pg_stat_subscription_stats` (zero apply/sync errors, zero conflicts) and `pg_stat_subscription`. The third carries the most weight: an apply error **halts** replication while every other indicator still looks plausible.

Sampling is `min(id)`/`max(id)` per table. A primary-key btree answers both by index scan instead of reading the table, so the cost is logarithmic per table rather than linear. The technique matches `pg-replica-auditor`, which audits a replica with MinMax plus random sampling for the same reason.

**For the script**: no `count(*)` anywhere, and `n_live_tup` is not the substitute — it is the statistics collector's estimate, and no `ANALYZE` has run on a freshly-loaded target, so it reports a difference on nearly every table while the data is identical. Same family of trap as finding 8: the measurement lies, not the database.

### 10. Reachability is TWO legs, and the second one fails inside the cutover window

Phase 0 began as one rule — the target must reach the source for replication. The application's path to the **target** is a second, independent leg, and it is the one whose failure is expensive: it surfaces at the repoint, with writes stopped and the source already out of service.

On beta both legs hold, and the reason is worth writing down because it is what makes the check cheap: source and target share the `aws_db_subnet_group` and the `aws_security_group`, so `describe-db-instances` returns the **same** VPC, subnets and security group id for both. They are behind one network object; nothing that reaches one can fail to reach the other. The party that actually needs the path is the **pooler**, not the app — the app resolves the pooler, and the pooler holds the backend host as a Terraform reference, so the cutover is a Terraform edit the application never observes.

**For the script**: run the comparison unconditionally at Phase 0, on both instances, and treat any difference in VPC / subnets / security group as a Blocker rather than something to resolve at cutover. It is one API call, and "the replacement is obviously in the same place" is precisely the assumption a migration exists to invalidate — a future one that crosses a VPC, a subnet group or an account will not announce itself.

### 11. The app role's password must be COPIED as an md5 verifier — setting it from plaintext breaks the pooler at cutover

`pg_dumpall --roles-only` carries no passwords (finding 5 and the `--no-role-passwords` requirement), so the application role lands on the target able to do everything except log in. The obvious repair is to set it from the plaintext the application already uses, which sits in `/<env>/DATABASE_URL` in SSM. That repair is wrong, and its failure lands in the worst possible place.

`password_encryption` is `scram-sha-256`, so `ALTER ROLE ... PASSWORD '<plaintext>'` stores a **SCRAM** verifier. The pooler runs `auth_type = md5` and its userlist holds an **md5** verifier — the only thing it can answer with. A server holding a SCRAM verifier demands SCRAM, and an md5 hash cannot produce a SCRAM response. Nothing detects this until the repoint, and by then writes are stopped and the source is out of service.

That the source role carries an md5 verifier is not read from `pg_authid` (unreadable) — it is read from the running system: the pooler's two tasks hold five backend connections each as the app role, matching `min_pool_size = 5` exactly, and md5 authentication succeeds only when the server's stored verifier equals the hash the client holds. The source's verifier therefore **is** the userlist's hash.

So the verifier transplants directly: PostgreSQL accepts a pre-hashed `md5...` string verbatim, and the verifier is `md5(password || rolename)` — bound to the role name, identical on both sides. PostgreSQL 18 accepts it with a deprecation warning and keeps md5 through v20.

**For the script**: build the `ALTER ROLE` from the userlist with `sed`, file to file, so the verifier never enters a terminal; delete the intermediates immediately. Then **prove it with a real login** as the app role using the SSM plaintext — reasoning about hash equality is not the same as watching the connection succeed, and this is the one step whose failure cannot be recovered cheaply.

### 12. Sequence advancement is exact — but only because two conditions hold, and both are checked

`setval` to the source's `last_value` is correct only when `last_value` is the last value actually issued. A caching sequence hands out values ahead of what it records, so the check comes first: all 166 sequences report `cache_size = 1`, which makes `last_value` exact and a safety margin unnecessary. A margin would not add safety anyway — it would only mask a broken ordering while leaving gaps in every id column. What *does* make the value final is the ordering: generate after writes are stopped and lag is confirmed zero.

`last_value IS NOT NULL` is a filter with teeth, not an optimization. 24 of the 166 sequences have never been used and report `NULL`; each is already at its start value on the target because the schema load created it there. `setval(..., true)` on one of those would make its first `nextval` return 2 and silently burn the value 1.

**For the script**: profile `cache_size` before trusting `last_value`, filter the nulls, and generate the statements from the source rather than hand-writing them — 142 statements here, and the count is a property of the data, not of the environment.

## Verified state at this point

Beta's target carries the full schema and is replicating. Structure matched the source by catalog on every dimension — 168 tables, 166 sequences, 823 indexes, 1259 constraints, 1655 columns — and the subscription reached `r` on all 168 tables with zero apply errors, zero sync errors, zero conflicts and zero lag. The 166 tables carrying an `id` compared identical on `min`/`max` boundaries.

Both legs of Phase 0 are confirmed on beta: the group admits itself (replication) and it admits the pooler's group `beta-001-connection-pooler` and the app cluster's `beta-001-ecs-sg`, with source and target on the same VPC, subnets and security group.

Connection shape that works, and the one the script should use:

```
PGPASSWORD=<from secret> psql --host <endpoint> --username postgres --dbname <db> --command "<sql>"
```

### 13. The cutover holds clients, it never stops them — and two module changes are what make that possible

A cutover that stops writes is an outage, not a short one. Zero downtime here is functional: no failed request, no dropped connection. The pooler is the only place that can deliver it, because the application never addresses the database — it resolves the pooler, which owns the backend host.

`PAUSE` is the primitive: held clients *"wait until RESUME is called"* rather than erroring, and each server disconnect *"waits for that server connection to be released according to the server pool's pooling mode"*. `pool_mode` is `transaction` across the fleet, so release happens at the end of each transaction and `PAUSE` returns in milliseconds. Under `session` it would wait for long-lived Rails connections to close — never — so this design is contingent on the pool mode, not universal.

Two things block it today. The console lists only `stats_users`, which may *"run read-only queries on the console"*, so `PAUSE` is unreachable without an `admin_users` entry. And the backend host is the raw RDS endpoint, so repointing rewrites the task definition — ECS replaces the tasks, and the paused process dies holding every client connection, which makes the pause worthless. Putting a CNAME in the already-associated `4shark.internal` zone in front of the database turns the cutover into a DNS change that never touches the task definition; PgBouncer treats it as a first-class trigger, marking server connections for recycling *"because a configuration file reload or DNS update changed the connection information"*.

**For the script**: the pause window is steps 2 through 5 — lag check, sequence advancement, DNS change, `RECONNECT` — and that duration is the entire client-visible cost. It is the one number the non-productive run exists to measure, and it is what decides whether the productive environments need anything beyond this.

**What is designed out rather than tested**: whether the application survives a pooler task replacement. Behind a CNAME the tasks are never replaced during a cutover, so the question leaves the critical path. Moving `host` from the endpoint onto the CNAME *is* a task-replacing deploy — it lands on an ordinary day, well before any cutover.

## Still to do

Beta's cutover is blocked on two module changes to `modules/connection_pooler`: an `admin_user` variable rendered as `admin_users` (with the user added to the userlist secret), and the backend `host` moved onto a CNAME in the `4shark.internal` zone. The CNAME move is itself a task-replacing deploy and belongs on an ordinary day, not on cutover day.

Then Phase 5 in full — pause, confirm zero lag, regenerate and run the sequence advancement, repoint the CNAME, reconnect, resume. The sequence statements must be **regenerated** at that moment; the ones produced during preparation are proof the generator works, not values to reuse.

Then Phase 6 (retire the source), followed by demo, then shared and atento.
