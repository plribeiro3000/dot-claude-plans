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

### 14. An instance identifier is fixed at creation, so a wrong name costs a SECOND full migration

`identifier` is ForceNew in the AWS provider: changing it in configuration destroys and recreates the instance rather than renaming it. AWS itself supports an in-place rename through `ModifyDBInstance`/`NewDBInstanceIdentifier` — a reboot, no data movement — but the provider does not expose it, and the request is old and unresolved upstream.

The consequence is concrete rather than theoretical. The key migration produced a correct database under a suffixed name, and correcting that name required standing up a third instance and copying the data again. Two full migrations for one environment, the second one buying nothing but the name.

**For the script**: name the replacement the way the environment should be named FOREVER, at creation, before any data moves. There is no cheap correction later — and on a large productive environment the second copy is the expensive one.

### 15. Placing the replacement in the source's Availability Zone is what makes the copy free

Transfer between instances in one Availability Zone over private addressing is not billed; crossing zones is metered on **both** ends. A subnet group spanning two zones lets AWS choose, so the placement is left to chance unless it is pinned.

`availability_zone` is also ForceNew, which decides where the argument may be introduced: on the new instance at creation, never on a live one. Declaring it on an existing database risks a destroy-and-create plan for a value that is already correct.

**For the script**: read the source's zone, pin the replacement to it, and refuse to proceed when they differ. On a 350 GB environment this is the difference between a free copy and a metered one, and it cannot be corrected after creation.

### 16. The pooler serves the userlist it read at BOOT — and the task definition is why it never notices

The userlist reaches the container as an environment variable resolved from the secret's **bare ARN**, which always means `AWSCURRENT` *at task start*. Changing the secret's content creates a new version but no new task-definition revision, so ECS never rolls the tasks and the running process keeps serving with the copy it decoded at boot. Nothing reports the divergence.

It surfaced as an authentication failure on the console with the password Terraform's state holds, and it was not a stale task definition: the running tasks were on the only revision that exists. The tasks had started at 13:55, the secret last changed at 16:07, and the admin line differed between the two versions. Measured across the fleet, all four environments were in that state — tasks started around 14:00, secrets changed between 16:07 and 16:32.

The cost is that the console is the only way to `PAUSE`, so a cutover cannot be zero-downtime while it is unreachable, and the only way to hand a running container a new userlist is to replace it — which drops every client connection it holds.

**For the script**: before anything else in the cutover phase, compare each pooler task's `startedAt` against the userlist secret's `LastChangedDate` and prove console access with a real `SHOW DATABASES`. A task older than the secret is a Blocker to resolve on a scheduled window, never inside the pause. The durable repair is pinning the secret's version in the task definition, so a content change produces a revision the service adopts — see finding 21 for what that replacement actually costs, which is less than it sounds.

### 17. A direct-connection secret lives outside SSM and Terraform, and a search of both will miss it

The deploy strips `DATABASE_URL` from the migration task and injects `MIGRATION_DATABASE_URL`, a GitHub **environment** secret holding a direct RDS URL — because PgBouncer's transaction pooling breaks Rails' advisory-lock migrations. It is write-only through the API and declared in neither SSM nor Terraform.

A search of both concluded nothing referenced the old database, and the next deploy broke. The value is reconstructed from the SSM application URL by rewriting the host and database to the direct endpoint — file to file, and with the trailing newline the CLI appends stripped, since it would otherwise be stored inside the connection string.

**For the script**: enumerate the consumers by ASKING each system, not by grepping the two that are easy to search. Rewrite this secret as part of the cutover, before the source can be destroyed — it is the one consumer the CNAME does not cover.

### 18. Retiring the source is two applies, and the order is forced by the provider

`deletion_protection` is only editable while the resource is still declared, so a single apply that both lifts the flag and removes the module fails. The first apply lifts protection and records `skip_final_snapshot`; the second removes the block.

`skip_final_snapshot` is deliberate rather than careless: AWS Backup already holds daily recovery points for the instance, so a final snapshot duplicates a backup that exists. Both it and `final_snapshot_identifier` are destroy-time arguments read from prior state, which means they must be recorded by an **earlier** apply than the one that removes the instance.

**For the script**: emit the teardown as two plans with the order stated, and confirm the vault's recovery points before accepting the skip.

## What the beta run measured

The full cutover ran with clients held and none dropped. The pause window covered the lag check, the sequence advancement (142 statements of 166 sequences), the Terraform apply repointing the record and the backup selection, and `RECONNECT` on both pooler tasks. Immediately after `RESUME` the application role held ten connections on the replacement and zero on the predecessor.

The initial copy of 168 tables on this dataset finished fast enough to be invisible — every table reached `r` before the first status query. That number is a property of beta's size and says nothing about the productive environments; it is the one figure the larger runs still have to produce.

Beta is complete: one instance, the conventional identifier, the environment's own key, the predecessor destroyed through the two applies of finding 18 with its AWS Backup recovery points retained. The application stayed connected across both the cutover and the destroy.

### 19. Aurora's free-transfer statement does NOT cover this migration — pin the zone instead of trusting it

Aurora's pricing page makes exactly three statements about data transfer, and reading any of them as covering a key migration is the trap: *"Data transferred between Aurora and Amazon Elastic Compute Cloud (Amazon EC2) instances in the same Availability Zone is free"*, *"Data transferred between Availability Zones for DB cluster replication is free"*, and *"For data transferred between an Amazon EC2 instance and Aurora DB instance in different Availability Zones of the same Region, Amazon EC2 Regional Data Transfer charges apply."*

The second is the one that looks like an answer and is not. *DB cluster replication* is a cluster replicating to its own members — the storage layer keeping replicas current. A key migration runs **logical replication between two separate clusters**, which is neither of the three cases. AWS's page does not state how that is billed, and no third-party blog is evidence about it.

So the answer is not to find the price, it is to remove the question: place the replacement's writer in the same Availability Zone as the source's writer, and the traffic never crosses a zone. That is what beta did, and it is checkable in one call per side.

The writers today, which are the placements each replacement must match: demo `us-east-1a`, shared `us-east-1b`, atento `us-east-1b`. Note that shared and atento each keep a reader in the *other* zone, so "the cluster's zone" is not a single value — it is the WRITER's zone that matters, because logical replication reads from the writer.

`modules/rds_aurora_cluster` does not expose the argument yet. Its `aws_rds_cluster` has `availability_zones` in `ignore_changes`, which is a different thing — the list of zones the cluster MAY use, not where an instance sits. The one that matters is `availability_zone` on `aws_rds_cluster_instance`, documented by the provider as *"(Optional, Computed, Forces new resource) EC2 Availability Zone that the DB instance is created in."*

**For the script**: read the SOURCE WRITER's zone, require the replacement to match it, and refuse to proceed otherwise — the argument is ForceNew on the cluster instance exactly as on the plain instance, so a mismatch is not correctable and the largest environment would pay for 350 GB on both ends.

### 20. AWS states the pooler failure outright — the fix is a version-pinned reference

Finding 16 was diagnosed from timestamps. AWS documents the behavior directly, which turns it from a discovery into a known property: *"Sensitive data is injected into your container when the container is initially started. If the secret is subsequently updated or rotated, the container will not receive the updated value automatically. You must either launch a new task or if your task is part of a service you can update the service and use the Force new deployment option to force the service to launch a fresh task."*

The reference format carries the escape. The full syntax is `arn:aws:secretsmanager:{{region}}:{{aws_account_id}}:secret:{{secret-name}}:{{json-key}}:{{version-stage}}:{{version-id}}`, and *"If no version ID is specified, the default behavior is to retrieve the secret with the `AWSCURRENT` staging label"* — which is what a bare ARN does, and why a content change leaves the task definition identical. Pinning the version id (`...:secret:name-AbCdEf:::<version-id>`, the empty json-key and version-stage segments still required) makes each content change produce a different task definition, so Terraform shows it and the service rolls deliberately instead of drifting silently.

One prerequisite comes with it: injecting *"a specific JSON key or version of a secret"* requires Fargate platform version `1.4.0` or later. Confirm each pooler service's platform version before pinning — a service pinned to an older version would fail to start rather than drift.

**For the script**: this is a module change rather than a script one, but the `preflight` check stays either way — a task older than the secret is still the thing that removes `PAUSE` from the table, and the check costs two API calls.

### 21. The pooler service adopts every revision Terraform declares — which is what makes the version pin work AND what makes every pooler apply a scheduled event

A version-pinned secret reference only helps if the service actually picks up the revision it produces. Many 4Shark ECS services carry `lifecycle { ignore_changes = [task_definition] }`, because their deploy pipeline registers revisions and Terraform must not fight it. The pooler is deliberately not one of them, and `modules/connection_pooler/main.tf:475-477` says so inline: *"No `ignore_changes = [task_definition]` here: that rule is for a service whose pipeline registers its own task definitions. This one redeploys by family, so Terraform is the only author and the service must adopt what it declares."*

Both halves matter and they point opposite ways. It is why pinning the version fixes the staleness at all — the revision is adopted, not merely registered. It is equally why **any** pooler apply that touches the task definition replaces the running tasks: environment variable, image, secret reference, all of them do.

That replacement is graceful by construction, and the numbers say how graceful. Each pooler runs **two** tasks under `maximumPercent` 200 / `minimumHealthyPercent` 100 (provider defaults — the module sets neither; confirmed live on shared-001), so ECS starts two replacements and gates them on a real listener probe (`pg_isready`, `main.tf:389-398`) before touching the incumbents. The incumbents then get the image's `STOPSIGNAL` — `SIGINT`, declared at `pgbouncer/Dockerfile:25` — which pgbouncer documents as `SHUTDOWN WAIT_FOR_SERVERS`: *"Stop accepting new connections and shutdown after all servers are released."* Under `pool_mode = transaction` a server is released at every transaction boundary, so the drain is as long as the longest in-flight transaction and no longer, with `stopTimeout = 120` as the ceiling before SIGKILL. Cloud Map is MULTIVALUE at TTL 10 (`main.tf:206-210`), so clients follow within about ten seconds.

**So a pooler apply costs no service interruption and no aborted transaction. What it costs is a reconnect** — the idle pooled client connections on the outgoing tasks close when the process exits. Whether the application absorbs that without a user-visible error is a property of the application, not of this module, and beta answered it.

**Measured on beta, applying the version pin.** The service went from revision 5 to 6 with `runningCount` never below the desired 2; a mid-rollout sample caught the exact shape the guarantee predicts — the PRIMARY deployment on revision 6 at 0 running while the ACTIVE deployment on revision 5 still served 2. Both replacement tasks reported `HEALTHY`. The task definition's reference resolved to `...:secret:beta-001-connection-pooler-userlist-a2KXpy:::terraform-ItMhQFdhYiVMcBPiQ2PLHp1EYd`, matching the secret's `AWSCURRENT` version id exactly, and the replacement tasks started 2026-08-06 09:39–09:40 against a secret last changed 2026-08-04 16:07 — the staleness inverted. `SHOW DATABASES` on the console answered, so `PAUSE` is reachable. **The application logged zero connection errors**: the web log group carried 473 events across the rollout window with no `ConnectionBad` / `ConnectionNotEstablished` / `server closed the connection` / `ConnectionFailed` / `could not connect` match, and the system worker carried none either. Beta's app does route through the pooler (its `DATABASE_URL` host is the pooler's convention CNAME on port 6432), so the absence of errors is a real result rather than an untested path.

**The same apply then ran on the other three, and volume did not change the outcome.** Every stack took the identical `1 to add, 1 to change, 1 to destroy` plan touching only the pooler's task definition and service, settled at two running tasks under a single deployment, and pinned its reference to its own secret's `AWSCURRENT` version id. Across the rollout window the web log groups carried **715 events on demo, 11,480 on shared and 31,429 on atento — zero connection errors in any of them**, and atento's system worker likewise. Atento is roughly sixty-six times beta's traffic, so the graceful-replacement property holds at productive volume rather than only in a quiet environment.

One consumer was NOT exercised and should not be read as having passed: the outbound payroll worker that reaches shared's pooler across the region boundary logged nothing at all in the window, because that project rests at zero replicas by design. Its reconnect path is the longest in the fleet and remains untested; the first time it runs after a pooler replacement is the first real observation of it.

**For the script**: unchanged. The scheduling rule is weaker than it first looks — a pooler apply is not a downtime window, and on a productive stack the Sidekiq queue check it rides is about not interrupting in-flight background work, not about the pooler itself.

### 22. `terraform init` inside a module directory writes a lock file that does not belong to the repository

Validating or formatting a module in place (`terraform.sh <repo>/modules/<name> validate`) runs `init` there, which creates `modules/<name>/.terraform.lock.hcl`. Modules in this repository do not carry lock files — only stacks do — so it shows up as an untracked file and would be committed by an `add .`. Delete it after the check; stage files by name rather than by wildcard.

**For the script**: nothing. This is a working-practice note for module edits.

### 23. `pg_dumpall` writes ONE ALTER ROLE per role, and the RDS master cannot execute it — the application role arrives unable to log in

The roles dump emits a `CREATE ROLE` followed by a single `ALTER ROLE` carrying every attribute at once:

```sql
CREATE ROLE <app-role>;
ALTER ROLE <app-role> WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN NOREPLICATION NOBYPASSRLS;
```

PostgreSQL refuses that whole statement when the caller does not hold an attribute it names — *"Only roles with the SUPERUSER attribute may change the SUPERUSER attribute"*, and the same sentence for REPLICATION. The RDS master holds none of SUPERUSER, REPLICATION or BYPASSRLS, so the `ALTER` fails, the role exists from the `CREATE` alone, and **`LOGIN` is never applied**. The role is then present with the right name and the right password verifier and still cannot authenticate: `FATAL: role "<app-role>" is not permitted to log in`.

Nothing upstream of the login attempt reports this. The dump succeeds, the load's per-statement errors look like the expected RDS-internal noise, and the schema loads normally because ownership only needs the role to EXIST.

**The three tokens must be stripped before loading**, and stripping them is lossless — all three are already off for a role created here, and the master could not grant any of them:

```
sed -e 's/ NOSUPERUSER//g' -e 's/ NOREPLICATION//g' -e 's/ NOBYPASSRLS//g'
```

Stripping only `NOSUPERUSER` is not enough and is the trap inside the trap: the statement then fails on REPLICATION instead, with a near-identical message, which reads like the first fix not having taken.

**For the script**: `prepare` filters the dump through that `sed` before loading it. It also counts errors with `grep -c 'ERROR:'` rather than `'^ERROR'` — psql prefixes every diagnostic with `psql:<file>:<line>: `, so the anchored form matches nothing and reports a clean load over a failed one. That false zero is what let the broken load pass unnoticed on the first run.

### 24. Prove the application role by logging in as it, because every cheaper check passes on a broken target

The verification the plan prescribes is not ceremony. On demo the role existed, owned all 168 tables, and carried the correct md5 verifier, and it still could not connect. A catalog query about the role, a check that the schema loaded, and a check that the verifier matched would each have reported success.

```
psql service=<target-as-app-role> --command "SELECT current_user, current_database();"
```

Then the grants, in the same connection — the count of tables against the count the role can `SELECT`. On demo both were **168**, which is what proves the schema load carried ownership and privileges rather than merely creating the tables.

**For the script**: not yet automated. It needs the application's own password, which lives in `/<env>/DATABASE_URL` in SSM, and `prepare` deliberately never reads that — the md5 transplant works from the pooler's userlist precisely so the plaintext is never touched. The login test is the engineer's, or a separate verb that takes the SSM read explicitly.

### 25. `psql --command` does not interpolate psql variables, and the obvious workarounds put the password where `ps` can read it

The subscription is the one statement that carries a live password inside SQL. Passing the connection string as a psql variable and referencing it as `:'conninfo'` is the idiomatic way to get correct SQL quoting — and it does nothing under `--command`, which sends its argument to the server verbatim. The failure is a bare parse error, `syntax error at or near ":"`, which reads like a typo rather than a mode restriction.

The two obvious repairs are both worse than the problem. Passing the conninfo as an argument — to `--set`, or interpolated straight into `--command` — places the password in the process's argv, where `ps` shows it to every user on the machine for as long as the command runs. Writing the statement to a file puts it on disk, where a failure between write and cleanup leaves it.

**The statement goes through STDIN, written by a shell builtin.** A builtin forks nothing, so no process carrying the value ever appears in the process table, and nothing is written for a failure to leave behind. Both quoting layers are handled explicitly: inside the conninfo the password is single-quoted with `'` and `\` backslash-escaped, and the whole conninfo becomes a SQL literal with every `'` doubled. RDS permits any printable ASCII except `/ " @` and space, so an apostrophe in a generated password is possible rather than theoretical.

**For the script**: `replicate` owns Phase 2 — publication on the source, subscription on the target — and composes the connection string internally. The plan's original framing, that this is the one command an operator must compose by hand, was reasoning about a document: a document cannot hold a password, so it delegated. A script that already reads master passwords from Secrets Manager for every other command has no such limit, and pasting a live credential into a terminal to keep a document self-contained is the worse of the two options.

### 26. The fleet spans two PostgreSQL major versions, so a catalog query must not assume the newer one

The single-instance environment runs PostgreSQL 18 and the three Aurora environments run 17. A query naming the per-conflict counters of `pg_stat_subscription_stats` — `confl_insert_exists` and its siblings, which exist only from 18 — therefore succeeds on the environment it was written against and fails on every other with `column "confl_insert_exists" does not exist`.

The failure is not proportional to what is lost. PostgreSQL rejects the whole statement, so the columns that actually matter go with it: `apply_error_count` and `sync_error_count` are what reveal a halted subscription, and an apply error stops replication while every other indicator still looks healthy. A monitoring query that dies on a version difference is worse than one that reports less.

**For the script**: `status` selects `*` from that view in expanded form, so each server returns whatever it has and the counters that exist everywhere are always present.

### 27. The pooler console's password is only in Terraform state, and every way of handing it to a script leaks it

`hold` and `release` are the two commands that drive the pooler console, and the admin password exists nowhere but the stack's state: the module generates it, publishes the user name as an output, and `terraform state show` redacts the value, so only the JSON form carries it.

Taking it from the caller's environment sounds like the clean separation — the script then needs no knowledge of a stack's directory — and it does not survive contact with how the script is invoked. Every invocation is a fresh shell, so a caller can only supply it as a `VAR=value` prefix, which puts the password in that process's argv for `ps`, in shell history, and in the transcript of whoever ran it.

**The script reads the state itself, via `--stack-dir`, and the value never leaves the process.** Only the two console commands take that argument.

The **logical database name** is discovered rather than passed: it differs from the real database name, and the pooler is the authority on what it serves. `SHOW DATABASES` returns it alongside `pgbouncer`, which is the console's own administrative database and never the application's.

**For the script**: `require_pooler_console` resolves both credentials from `--stack-dir`; `resolve_pooler_database` reads the logical name from the console.

### 28. A pooler's task addresses come back one per line, and the first field of every line is not the first address

`aws ecs describe-tasks` with a `--query` projecting one value per task returns them **newline-separated**, not tab-separated on a single line. Taking `awk '{print $1}'` over that output yields one field per line — every address, not the first — and the result reaches `psql --host` as a single string containing a newline: `could not translate host name "10.100.10.220\n10.100.9.212"`.

The failure is benign only by luck of ordering. It happened inside `hold`, in the step that resolves the logical database name, which runs BEFORE the PAUSE loop — so it exited with the window still closed. Had the same expression been used one step later, it would have failed with clients already held.

**For the script**: `awk '{print $1; exit}'`. The loop that iterates every address was always correct, since word splitting treats newlines as separators; only the take-the-first expression was wrong.

### 29. The database's OWNER is the application role's ability to migrate, and a target created by the master silently loses it

Since PostgreSQL 15 the `public` schema grants `USAGE` and `CREATE` to **`pg_database_owner`** — an implicit role whose only member is whoever owns the database. So the owner is not bookkeeping: it *is* the application role's `CREATE` privilege.

A target whose database was created by the master therefore matches the source on every count `verify` compares, matches it on the schema ACL **text** (`public=pg_database_owner=UC/pg_database_owner,=U/pg_database_owner` on both), and still refuses the application role's DDL. `has_schema_privilege(<app-role>,'public','CREATE')` answers `t` on the source and `f` on the target while `nspacl` is byte-identical, because the ACL names a role whose membership differs.

Nothing surfaces this until a deploy runs `db:migrate`, which is long after the migration has been declared finished.

**For the script**: `prepare` creates the database `OWNER <application-role>` and then asserts it with an `ALTER DATABASE ... OWNER TO`, so a database that already existed is corrected rather than accepted. `verify` compares ownership alongside the counts — database, schema, and the per-owner table and sequence totals — since that comparison is the one that fails when everything else passes.

**The requirement this serves is broader than the migration.** Every object belongs to the environment's single application role on the non-productive environments, and to the write-capable role on the productive ones, where a separate read-only role also exists. Copying ownership from the source carries this automatically for tables and sequences, because `pg_dump` preserves it — the database itself is the one object no dump covers.

### 30. The value of a GitHub environment secret is not recoverable from anywhere

`MIGRATION_DATABASE_URL` is a GitHub environment secret, injected as a container override onto the ephemeral task that runs `db:migrate`. Three places might plausibly hold its value and none does: GitHub secrets are write-only; a stopped ECS task is retained only briefly, and none survived; and **CloudTrail does not record `RunTask` overrides at all** — the `requestParameters` of a `RunTask` event stop at `taskDefinition`, with no `overrides` key, so the value never reaches the audit log.

It does not need to be recovered. Every field is derivable from the system: the host and database from the environment's own records, and the credential from `/<env>/DATABASE_URL` in SSM, because `db:migrate` creates tables as the role that connects and every public table on the source is owned by the application role.

**Two traps sit in that derivation, and both are caught by connecting with the constructed URL before writing it.** The database name in the pooler URL is the pooler's LOGICAL name (`demo001_master`), not the real one (`app_demo_001`) — a direct connection with the logical name fails outright. And the connection is what revealed finding 29: it succeeded, and then `has_schema_privilege` reported the role could not create.

**The host is the internal record, not the endpoint.** `database-primary-<env>.4shark.internal` is maintained by Terraform, points at the database directly on 5432 rather than at the pooler on 6432, and is repointed by the cutover — so the secret follows every future database replacement instead of needing a manual edit each time.

### 31. A stale IPv6 prefix hangs the migration halfway, and the sharpest tell is that an INVALID secret answers while a valid one does not

The workstation-side failure documented in `runbooks/engineer-access/IPV6-STALE-PREFIX.md` lands squarely on this procedure, because almost every verb starts by reading a master password from Secrets Manager. When the ISP renumbers the prefix and the router keeps advertising the old one, the machine holds valid non-deprecated addresses on a dead return path and keeps selecting them as the source — so dual-stack AWS endpoints hang while everything else works.

**The discriminator that identifies it fastest here is not in the runbook.** `describe-secret` on a NON-EXISTENT id answers immediately with `ResourceNotFoundException`, while `get-secret-value` on a REAL secret hangs — because only the second has to decrypt through KMS, one more dual-stack endpoint. A probe with a deliberately wrong id therefore proves nothing about reachability, and reading it as "Secrets Manager is fine" sends the diagnosis in the wrong direction.

Confirmation is two commands and thirty seconds: `ifconfig en0 | grep inet6` (two global prefixes is the tell), then `ping6 -c 3 -S <address-from-each-prefix> 2606:4700:4700::1111` — the dead prefix returns 100% loss while the live one answers in tens of milliseconds. The fix removes **every** address on the dead prefix, since the OS simply selects the next eligible one, and it needs `sudo` — so it is the engineer's to run.

**For the script**: nothing to change. The failure is upstream of it and every verb inherits it; what this note buys is not re-diagnosing it from scratch mid-migration.

### 32. A guard is worth writing wherever a command's FAILURE becomes another command's INPUT

`require_pooler_console` reads the pooler's admin credentials out of `terraform show -json`. That command does not install providers, so a stack directory never initialised in this checkout returns an error message **on stdout** — which flowed straight into `jq` and produced `Invalid numeric literal`, a message that names neither Terraform nor the missing init.

The shape generalises past this one call: whenever output is piped from a command that can fail into a parser that cannot know better, the parser's error replaces the real one. The guard is one line — assert the text parses before using it — and it converts a confusing failure into the exact remedy.

**For the script**: `require_pooler_console` validates the state JSON and names the `init` to run.

### 33. `pg_dumpall` records the GRANTOR of a role membership, and the target's master cannot act as it

`pg_dumpall --roles-only` emits role memberships with the grantor preserved: `GRANT "<app-role>" TO postgres WITH INHERIT TRUE GRANTED BY rdsadmin`. On the source that membership was created by RDS's own internal role, so the dump says so — and on the target the master cannot grant privileges *as* `rdsadmin`, so the statement fails with `permission denied to grant privileges as role "rdsadmin"`.

**What that costs is the database itself, not a privilege detail.** PostgreSQL requires whoever creates a database to be able to `SET ROLE` to the owner it names. The failed grant is exactly what would have made the master a member of the application role, so `CREATE DATABASE ... OWNER` dies with `must be able to SET ROLE`. The same dropped clause silently removes every other membership in the dump, and only this one announces itself.

This is finding 23's family — `pg_dumpall` emitting statements the RDS master has no standing to execute — on a third attribute. It did not appear on the first Aurora migration because that environment's ownership was repaired by hand with `ALTER DATABASE`, so the `CREATE DATABASE ... OWNER` path added as the fix had never actually run against a target.

**For the script**: the roles sed strips ` GRANTED BY <role>` alongside the three privileged attribute tokens. Lossless — the master created those roles moments earlier in the same load, so it holds admin over them and grants as itself; only the recorded grantor changes, and nothing reads it.

### 34. The dump carries session settings that postdate the TARGET, and the newest client is a deliberate choice

`pg_dump` refuses a server newer than itself, so the client is pinned to the newest version in the fleet — that is what makes one client able to read every environment. The cost lands on restore: the dump's header carries `SET transaction_timeout = 0`, a parameter PostgreSQL 17 introduced, and a 16 target rejects it with `unrecognized configuration parameter`.

The first Aurora migration had a 17 target and accepted it. Both remaining environments are 16, so both meet it.

**For the script**: the schema is filtered through a sed that drops that `SET` before the load. Removing it is lossless — these are restore-session settings, and a parameter the server does not implement has no behaviour to preserve. Anything else in the header that postdates the target fails identically, so a message naming a different parameter is this same case rather than a new one. Installing an older client instead was considered and rejected: it would not replace the newest one (the fleet still holds an 18 server), so it would mean maintaining three clients plus a rule selecting between them, against one line whose failure mode is loud and named.

### 35. Two counts of "the same thing" were counting two different populations

`certify` compared `count(*) FROM pg_tables WHERE schemaname='public'` against `count(DISTINCT table_name) FROM information_schema.table_privileges WHERE grantee = current_user` and required equality. The second is not scoped to a schema and includes views, so it legitimately exceeded the first — 174 against 171 — and the check reported a missing grant on a target where nothing was missing.

The first Aurora migration passed this at 168 = 168, which was a property of that database rather than of the check: no views, nothing outside `public` granted to that role. A comparison that agrees by coincidence is indistinguishable from one that agrees by construction until a database differs.

**For the script**: the check asks for the SET rather than two counts — the public base tables the role cannot read, which is empty on a healthy target and names the offenders on a broken one. `has_table_privilege` is also the right primitive over any privilege catalog, because it answers the question the application actually asks, counting grants held through role membership, through `PUBLIC`, and through ownership — none of which appear as a direct row for the grantee.

### 36. A privilege function given a CONSTRUCTED NAME can be evaluated on rows the `WHERE` was meant to exclude

The first version of that set-based check called `has_table_privilege(current_user, format('public.%I', t.tablename), 'SELECT')` while filtering `t.schemaname = 'public'`. It failed with `relation "public.pg_statistic" does not exist`: PostgreSQL does not guarantee the evaluation order of `WHERE` conditions, so the function ran against catalog rows before the schema filter removed them, with `public.` prepended to a name that lives elsewhere.

**For the script**: the check passes the OID (`has_table_privilege(c.oid, 'SELECT')`) rather than a constructed name. An OID comes from the catalog row itself, so early evaluation on a row destined to be filtered returns a boolean instead of raising — the hazard disappears rather than being worked around. The general shape is worth carrying: a function over a name assembled from column values can be handed values the surrounding filter never intended.

### 37. Sync workers run at wildly different speeds, and INDEX WEIGHT explains it — the lever is free before `replicate` and expensive after

Initial sync copies a bounded number of tables at once, so at any moment a couple of workers hold a table each. Those two workers can differ by more than an order of magnitude, and the reason is not the worker: it is how much index the table carries per byte of heap.

Measured on the productive cluster while both were in flight:

```
 commissionings     | 11 GB heap | 18 GB indexes | 10 indexes
 accumulated_deals  | 29 GB heap | 11 GB indexes |  5 indexes
```

The first landed ~1 GiB/hour, the second ~4.5. Every row `commissionings` receives forces ten random index writes against more index than table, while its partner maintains half as many indexes over nearly three times the data. **A table count in `status` hides this entirely** — the number sits still for hours and reads like a stall. Naming the tables in flight, and profiling index weight in `measure`, is what turns it back into readable progress.

**The lever is dropping secondary indexes on the TARGET and recreating them after the copy**, and its cost depends entirely on when it is taken. A table still queued (`srsubstate = 'i'`) is empty on the target with no sync running, so dropping its indexes conflicts with nothing. A table mid-copy (`'d'`) needs a lock that the running `COPY` holds, so the same action stalls or restarts that table's sync — discarding everything it has landed. **So the decision is nearly free before `replicate` and costs hours once the copy is running.** Raising `max_sync_workers_per_subscription` has the same shape for a different reason: it needs the subscription restarted, which aborts every in-flight table.

**Nothing here can lose data, and that is worth stating because it is the first thing anyone asks.** The source is only ever read during the copy. Every target-side action risks redoing work, never losing any.

**The lever is NOT taken on any environment — the target keeps every index through the whole copy.** The reason is the cutover, not the copy: dropping indexes puts a manual recreation step between a finished copy and a productive cutover, and a step that is forgotten or fails there promotes an unindexed database into production. That failure is far more expensive than the hours the drop would save, and it lands at the worst possible moment. A slow copy costs waiting; an unindexed productive database costs an outage.

**What is NOT known, and stays unknown because the lever is not being taken**: whether `CREATE INDEX` after the copy actually beats the inline row-by-row maintenance on a `db.t4g.large`. The community consensus favours the bulk build, but with that instance's memory the sort spills to disk.

**The index-weight profile is still worth reading before `replicate`** — not to decide whether to drop anything, but because it is what predicts the copy's duration. A table carrying more index than heap is where the hours go, and knowing that in advance is the difference between scheduling a window and discovering one.

**One correction that keeps resurfacing**: the drop under discussion was always on the TARGET — the new database, still empty, serving no traffic. The SOURCE keeps every index for the entire migration and never stops serving; the copy only reads from it. Nothing in this procedure removes an index from a database in use, and no target-side action can duplicate data on the source.

### 38. The error counters go NON-ZERO on a healthy copy, and the log is what separates a dropped connection from a broken one

`status` reported `apply_error_count: 6` and `sync_error_count: 5` at the end of a copy that had shown `0/0` at every earlier reading. Both counters are cumulative for the life of the subscription, so they record what happened, never what is happening — a number above zero says an error occurred at some point, not that anything is wrong now.

The cluster's PostgreSQL log resolved it in one query, and the messages fell into three groups that look alike in a counter and are unrelated in cause:

```
could not receive data from WAL stream: SSL SYSCALL error: EOF detected
could not receive data from WAL stream: server closed the connection unexpectedly
could not send data to WAL stream: SSL connection has been closed unexpectedly
```

Those are **connection drops between subscriber and publisher**, clustered in the hours when the last large tables finished and their sync workers disconnected. Logical replication reconnects on its own and resumes from the last confirmed LSN; a table sync interrupted mid-`COPY` restarts that table from scratch. Nothing is lost and nothing is duplicated — which is why all 171 tables still reached `r`. The other two groups were not replication at all: the roles load's expected `role "X" already exists` / `cannot alter "rdsadmin"` (finding 23's family, before the subscription existed) and one `relation "public.pg_statistic" does not exist` from the `certify` defect of finding 36.

**A non-zero counter is therefore not a verdict, and neither is a zero one.** What settles the question is `verify`, which compares catalog structure and per-table row-id boundaries between the two databases independently of anything the subscription reports. Here it returned identical on both, against 317 GB on the target and 318 GB on the source — the gap being absent bloat on a freshly written volume, not missing rows.

**For the environment still to migrate**: read the counters as a pointer into the log, never as a result. The query that classifies them is `aws logs filter-log-events` against the target cluster's `/aws/rds/cluster/<target>/postgresql` group with an `ERROR` filter pattern, and the three groups above are what to expect. **And confirm the stream is connected with zero lag immediately before `hold`** — the drops prove the connection is not permanent, and the cutover assumes a caught-up target.

### 39. A repoint that terraform reports as applied can silently not persist — the restore-testing selection is the case, and "Modifications complete after 0s" is the tell

The cutover apply repoints three things at the replacement: the backup selection, and the two restore-testing selections (local and cross-region). All three reported success. **Only the backup selection actually changed in AWS.**

The discriminator is the resource's update mechanics, and it is visible in the apply output before any verification. `aws_backup_selection.resources` is force-new, so terraform destroys and recreates the resource and the new ARN enters at creation — the log shows `Destroying...` then `Creation complete`. `aws_backup_restore_testing_selection.protected_resource_arns` updates in place, and the log shows `Modifications complete after **0s**`. A modification that takes no measurable time against a remote API did not reach it. For contrast, the same stack's `aws_rds_cluster` modification in a later apply took 32s.

**Verify a repoint against AWS, never against terraform's own report** — `aws backup get-restore-testing-selection --restore-testing-plan-name <plan> --restore-testing-selection-name <selection> --region <region>`, once per region, because the cross-region selection is a separate resource in a separate region and a check that only covers the local one passes while half the repoint is missing.

**The fix is to force the mechanics that work**: `terraform plan -replace='module.restore_test_local.aws_backup_restore_testing_selection.this' -replace='module.restore_test_dr.aws_backup_restore_testing_selection.this'`, which recreates each selection so the ARN lands at creation. Re-running the plain apply repeats the same silent no-op.

The mechanism behind the in-place failure is not established — the module declares only `protected_resource_arns` with no `lifecycle` block, so the one conflict AWS documents for this call (a selection carrying `ProtectedResourceConditions` cannot be updated through `ProtectedResourceArns`) does not apply here. What is established is the behaviour and the working alternative.

**What it costs if it is missed**: restore testing is what proves the backups are restorable. Left pointing at a destroyed cluster, it targets a resource that no longer exists — the validation stops being real without failing loudly. Nothing else in the migration surfaces it, because the backups themselves are correct.

**Only `app-shared-001` declares restore testing**, so this finding has no reach into the environments migrated before it — `app_demo_001_local` does not exist as a plan. `app-atento-001` is the next environment to check.

### 40. The md5 transplant must cover every pooler role, and a productive stack has two — the one it misses fails quietly because the other one serves

`prepare` resolves "the application role" from table ownership on the source, and the verifier transplant of finding 11 follows that resolution. **A productive stack's pooler declares two pools** — a master pool against the writer and a follower pool against the read replica — **each with its own distinct role**, and the follower's role owns no tables. Table ownership therefore never returns it, the transplant never reaches it, and it arrives on the replacement holding whatever `ALTER ROLE ... PASSWORD` produced under `password_encryption = scram-sha-256`: a SCRAM verifier the pooler's `auth_type = md5` userlist cannot answer.

**The failure is continuous on the pooler and rare for the user, which is what makes it survive a cutover unnoticed.** PgBouncer logs `cannot do SCRAM authentication: wrong password type`, naming the pool and the role, every time it tries to open a server connection for that pool — 1,980 events across three days on `shared-001`, every one of them the follower pool and not one the master pool. That asymmetry is the diagnosis: a transplant that had missed both roles would have taken the application down at cutover. What reaches a user is only a read the pooler could not route, so it surfaces as an occasional `ActiveRecord::ConnectionNotEstablished` rather than an outage.

**No SQL check exists for it.** RDS denies `pg_authid` to the master (`permission denied for table pg_authid`), so a role's credential *type* cannot be read back at all — `pg_shadow` is denied for the same reason. The check is the pooler's log going quiet after the server connections recycle, bounded by `server_lifetime = 600`.

**The repair needs no plaintext and no downtime.** The userlist's md5 string is exactly what PostgreSQL stores, so `ALTER ROLE "<role>" PASSWORD '<md5-string-from-userlist>'` restores the expected type in place; open server connections are untouched and only new ones authenticate differently. Deriving the role list from the pooler's `[databases]` section rather than from table ownership is what makes the statement count checkable before it runs — `PLAN.md` § 1.1a carries the commands.

### 41. Migrating a database moves the DATABASE's key and nothing else — an environment's SSM parameters are a separate surface, and the cutover's own write is what disguises that

The key-per-environment scheme covers more than the databases, and only the databases have been migrated. Every environment's SSM SecureString parameters — the secrets the application reads at boot — still encrypt with the shared `alias/4shark-master`, in all four environments including the three whose databases are already on their own key. Read from `beta-001`, whose migration is furthest behind it: 16 of its 18 parameters carry `mrk-fa0cda243274491784fc7b39bead5a03` (the shared key), the remaining two carry `alias/aws/ssm`, and the environment's own `mrk-39829cff7af444f9b38a425833645f58` appears zero times. Fleet-wide the count is 68 on the shared key (atento 18, shared 18, beta 16, demo 16) plus 17 OpenSearch and Mongo parameters on `alias/aws/ssm`.

**What makes this read as already done is that the migration DID touch these parameters.** Every environment's `DATABASE_URL` was rewritten at its cutover to name the replacement, so its `LastModifiedDate` sits alone in the middle of a block dated at stack creation — beta's is `2026-07-04` against `2026-03-21` for everything else. The write changed the value and left the key, which is the expected behaviour of a `put-parameter` that names no `--key-id`; that mechanism has not been confirmed by a test, but the observable state is unambiguous either way.

The cause is in the code rather than in the procedure. The four `app-*-001` stacks declare their parameters with no `key_id` at all, while the two modules that already own their keys set it explicitly:

```
app-shared-001/ssm.tf:25-35     resource "aws_ssm_parameter" "secrets" — no key_id
modules/setup/ssm.tf:32         key_id = aws_kms_alias.this.name
modules/onboarding/ssm.tf:44    key_id = aws_kms_alias.this.name
```

**Adding `key_id` is not obviously safe, and the reason is `ignore_changes`.** Each parameter is declared with `value = "PLACEHOLDER"` and `lifecycle { ignore_changes = [value] }`, so Terraform's state holds the placeholder while the real secret was written out of band. A `key_id` change is an in-place update, and an in-place update re-sends the resource with the value Terraform has — which would overwrite every secret in the environment with the placeholder. That is the expected semantics rather than a measured outcome, so it is settled by reading a plan on `beta-001` before any productive stack is touched; if it holds, the migration path is recreating each parameter with its known value, not editing its key.

### 42. An environment's size is MEASURED per run, never carried across from another environment — one wrong attribution inverted the schedule for a whole migration

The volume that drives the copy's duration, the retention the source must hold, and the money at risk if the zones differ are all per-environment facts, and `measure` returns all three in one read-only call. Carrying a figure forward instead costs a schedule built on the wrong environment: `app-shared-001` holds 317 GB and `app-atento-001` holds 34 GB, so the two are an order of magnitude apart, and attributing shared's volume to atento turns a copy of a few hours into a planned two-day operation with a window scheduled weeks out.

**The check that settles it is running `measure` against an environment whose size is already known.** Measuring `app-shared-001` returns 317 GB across 170 tables, which matches what its own migration recorded — so the metric is sound and the attribution was the error. Do that comparison whenever a measured number contradicts a written one, rather than choosing between them: one read-only call decides which of the two is wrong, and it also protects against the opposite mistake of discarding a correct plan on the strength of a misread tool.

### 43. `prepare` transplants ONE verifier, resolved from table ownership — so finding 40's rule is the operator's to apply, not the binary's

Finding 40 established that the transplant must cover every role in the pooler's `[databases]` section. The binary does not do that. It resolves a single role and transplants a single verifier:

```
rds-reprovision.sh:513-516
  --command "SELECT DISTINCT tableowner FROM pg_tables WHERE schemaname='public';"
  application_role="$owners"
  echo "Application role, from table ownership on the source: ${application_role}"
```

Table ownership returns the role that owns the application's tables, which is the pooler's **master** pool role. A productive stack's **follower** pool authenticates as a different role that owns nothing, so it is invisible to that query and receives no verifier. `prepare` then reports success — one role named, one transplant confirmed — and the gap surfaces only when the pooler authenticates against the replacement at the cutover, on the follower pool alone, while the master pool serves normally. That is finding 40's signature exactly, and finding 40's fix lives in the procedure rather than in the script.

**The check is the count, and it is read from the pooler rather than from the database.** Decode the pooler's `PGBOUNCER_INI_B64`, count the pools in `[databases]`, and require one transplanted verifier per pool. A `prepare` run that names one role on a stack with two pools has not failed — it has done half the work, and the other half is a hand-run `ALTER ROLE` carrying the userlist's md5 hash, taken before the cutover and never after it.

## Where this stands

**Both non-productive environments run on their own key, both predecessors destroyed.** The cluster one migrated in a single copy — its replacement was born with the conventional identifier because `app-<env>-001` was free while `app-<env>-001-cluster` was the name in use, which is the whole payoff of settling the identifier before any data moves.

**The first productive environment runs on its own key.** Its 318 GB across 171 tables copied in about 45 hours of wall clock — **roughly 7 GB/h averaged over the whole copy**, which is the number to plan the next one with. Read it as an average and not as a rate: the first hours run far faster because the small tables finish first, so an early extrapolation predicts a completion that never arrives, and the index-heavy tables are the tail. `verify` returned identical on both catalog structure and per-table row-id boundaries, with the target at 317 GB against the source's 318 GB: the gap is the source's accumulated bloat, which a fresh copy does not reproduce, and it is the expected direction rather than missing rows. The cutover advanced 125 sequences with replication lag at zero, and after it the predecessor held only its own master's connections — no application-role connection at all — which is what let `detach` drop the subscription and release the slot. **Its predecessor is destroyed**, through the two-apply teardown of finding 18. **Both of its pooler roles hold md5 verifiers**, the follower's restored from the userlist after the cutover (finding 40), and its pooler's log carries no `wrong password type`.

**Its predecessor's CloudWatch log group outlives the cluster, deliberately.** The declaration stays so the 180-day retention runs out on its own, leaving the collected records readable while a problem traceable to the period the old database served can still surface. Nothing writes there any more; the declaration comes out once the window has passed, and until then the group is not orphaned — it is retained. This differs from the environments migrated before it, whose predecessor log groups were removed with their clusters.

**The fleet-wide prerequisites are done.** Every pooler's task definition names its userlist secret's version, so the console credentials cannot drift again (findings 16, 20, 21). `modules/rds_aurora_cluster` accepts `availability_zone`, so a replacement's writer can be pinned to its source's zone (finding 19). Both were applied to every stack before merging.

**The script has run all seven verbs against real infrastructure**, and the four traps the first Aurora migration surfaced are fixed in it: the privileged attribute tokens in the roles dump (23), the anchored error count that hid the failed load (23), `--command`'s missing interpolation (25), and the two PostgreSQL major versions in the fleet (26).

## Still to do

**`atento-001` is the last environment, and it is the SMALL one — 34 GB across 167 tables, measured on the live cluster.** The largest was `app-shared-001` at 317 GB, and it is through; reading atento as the big one inverts the schedule, because at shared's ~7 GB/h average a 34 GB copy runs in hours and its window can be opened rather than scheduled weeks out. Its WAL rate is 1232 kB/h — 87 MB across a three-day window — so retention on the source is a non-issue. Its pooler declares **two** pools, `atento001_master` and `atento001_follower`, so two verifiers are owed and `prepare` transplants one (finding 43) — the follower's is a hand-run `ALTER ROLE` from the userlist, taken before the cutover. Its stack declares **no** restore testing, so the cutover PR has no restore-testing selection to `-replace`. Two further things are decided for it ahead of time: its restore-testing declaration is checked before the cutover, because finding 39's silent no-op reaches any environment that has one; and **the verifier transplant is driven from its pooler's `[databases]` section with the statement count confirmed against the pool count**, because it is a productive stack and therefore has a follower role table ownership will not return (finding 40). After the cutover, its pooler's log is read for `wrong password type` — that is the only available proof, since RDS denies `pg_authid`.

**A copy belongs on quiet days; the CUTOVER belongs at the start of a working week, and the two are independent.** The subscription keeps streaming once the initial copy finishes, so a copy that completes on a Sunday does not force a Sunday cutover — the target simply stays current until the window opens. What bounds the wait is the schema-migration freeze, since DDL is not replicated. The risk of a cutover is not in the operation, which holds clients rather than dropping them; it is in the hours after, when the replacement meets real traffic on a cold cache and anything that surfaces needs people at their desks.

**The md5 verifier is a debt this migration carries rather than creates, and it is paid AFTER the last environment — never during one.** Every pooler runs `auth_type = md5`, so each replacement's roles must arrive holding md5 verifiers (finding 11, finding 40); PostgreSQL 18 accepts a pre-hashed md5 string with a deprecation warning and support runs through v20, so the mechanism has a horizon rather than a deadline. Moving the fleet to SCRAM means changing the poolers' `auth_type` and their userlist contents alongside the roles' stored verifiers, and doing that mid-migration would mean the source and the replacement disagreeing about credential type at the exact moment the cutover repoints between them. So it waits: once `atento-001` is through and every environment runs on its own key, the poolers and the roles move to SCRAM together, per stack, with the pooler's log as the check — the same check finding 40 uses.

**The SSM parameters are the next surface, and they start once `atento-001` is through — the same placement the md5 debt has, for a different reason.** The md5 work waits because doing it mid-migration breaks a cutover; this waits because it competes for the same attention and touches the same stacks, and a migration in flight is the worst moment to be rewriting the secrets the application boots with. The scope is finding 41: 68 parameters on the shared key across all four environments, 17 more on `alias/aws/ssm`, and a `key_id` change whose safety turns on what `ignore_changes = [value]` does to an in-place update. The first step is not a change — it is a plan on `beta-001` that answers whether adding `key_id` would rewrite the values, because the answer decides whether the path is an edit or a recreate. **The three environments whose databases are already migrated are in scope too**, so this is fleet-wide work rather than a tail on the atento run.

**The billing question of finding 19 remains formally unanswered, and is made moot rather than resolved.** Neither AWS pricing page addresses logical replication between two separate clusters; both speak only of RDS↔EC2. What the account's own billing shows is that **no metered usage type exists for same-Availability-Zone RDS transfer**, while cross-zone appears as its own type (`USE1-DataTransfer-xAZ-*`). Pinning both sides to one zone therefore costs nothing and removes the variable, which is why the placement rule exists. The exposure if it were ever crossed is small — 317 GB metered on both ends, the largest environment, is roughly US$6 — so the rule earns its place on certainty, not on the money.
