# PLAN — Moving each app database onto its environment's own KMS key

## What this is

The command-level procedure for moving each app environment's DATABASE onto its own KMS key. It has the shape `mongodb-reprovision` has: the script owns the dangerous repetitive half, the engineer owns the Terraform and every apply.

**The databases are one surface of the key-per-environment scheme, not the whole of it.** An environment's SSM SecureString parameters — the secrets the application reads at boot — still encrypt with the shared `alias/4shark-master` in every environment, including the ones whose databases are already migrated, because the `app-*-001` stacks declare their parameters with no `key_id`. That work is scoped in `EXECUTION-LOG.md` finding 41 and starts once the last database is through; nothing in this procedure touches it, and finishing this procedure does not finish the migration.

**The script is the `rds-reprovision` skill**, invoked from its installed path — `bash ~/.claude/skills/rds-reprovision/scripts/rds-reprovision.sh <verb> ...`. The sequence below writes it as `rds-reprovision.sh` for readability; the real invocation is always the full installed path, bare, with no redirection or trailing `echo` (that is what keeps one allow-list entry covering the dozens of calls inside it).

**The procedure is proven — it has carried four migrations across three environments, including one productive.** What each run corrected lives in `EXECUTION-LOG.md` as numbered findings; this document carries the procedure those findings produced. Where something is still unmeasured it says so, and the remaining environment is where it gets measured.

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
- **The schema has no obstacle to logical replication in two of its four documented gaps**: zero views or materialized views, and every table carrying application data has a simple primary key. The two remaining gaps (DDL, sequences) are steps below, not risks.
- **`schema_migrations` is the one table with no primary key, in every environment.** Logical replication cannot apply an UPDATE or a DELETE to a table with no replica identity, so this would be a real gap if the table ever received one — Rails only ever appends a version row, and the schema-migration freeze that runs from `replicate` to `confirm` means it receives nothing at all during the copy. `measure` reports it on every environment; it is the expected output and not a finding to chase.
- **Connectivity for the manual run is the VPN.** Each database security group admits PostgreSQL from the Management VPC, and RDS allows no host access, so the whole procedure runs as `psql` from the engineer's machine over the VPN — there is nothing to SSH into.

## State

**Three of the four environments' DATABASES run on their own key, every predecessor destroyed. `atento-001` is the only database left.** No environment's SSM parameters have moved — that is the second surface, and it is fleet-wide rather than a tail on the last run (finding 41).

`app-beta-001` (single instance, `us-east-1b`) took **two** migrations rather than one. The first moved the data onto the environment's key but had to create the replacement under a suffixed identifier, because the original still held the name. The second corrected the name. An instance's identifier is fixed at creation as far as Terraform is concerned — AWS supports an in-place rename that the provider does not expose — so a name is not editable, it is a second copy. **Name the replacement the way the environment should be named forever, before any data moves.** That rule was paid for here and honoured everywhere since.

`app-demo-001` (writer `app-demo-001-instance001`, `us-east-1a`) was the first Aurora run and migrated **once**. It validated the cluster-shaped half of every phase and moved the direct-connection secret onto the internal record instead of an endpoint, so no future replacement touches it.

`app-shared-001` (writer `app-shared-001-instance001`, `us-east-1b`) was the first **productive** run and the first at real volume: 318 GB across 171 tables, copied in about 45 hours. `verify` found catalog structure and per-table row-id boundaries identical, with the target 1 GB smaller than the source — the source's accumulated bloat, which a fresh copy does not reproduce, and the expected direction rather than missing rows. Its cutover advanced 125 sequences at zero lag and dropped no connection. **Its predecessor's CloudWatch log group survives the cluster deliberately** (see Phase 6).

`app-atento-001` is next and is **small — 34 GB across 167 tables**, measured on the live cluster. It is the last environment, not the largest one: `app-shared-001` was the largest and is through. At the ~7 GB/h shared averaged its copy is a matter of hours rather than days, so its window can be opened rather than scheduled weeks out — but the rate is shared's average and not a guarantee, so the schedule is confirmed from `status` during the run instead of promised before it. Everything below is what the earlier runs produced.

## Paying nothing for the copy is a REQUIREMENT, not an optimization

The replication that fills a replacement is ordinary network traffic and it is billed like any other. Transfer between two instances in the **same** Availability Zone over private addressing is free; crossing zones is metered on **both** ends. A migration is therefore free or expensive depending on one placement decision made at creation, and `availability_zone` is fixed at creation too — there is no correcting it afterwards.

On beta this was settled by pinning the replacement to the source's zone and confirming both reported `us-east-1b` before any data moved. The same guarantee has to be **established** for each remaining environment rather than assumed, and two things make that harder than repeating the beta step:

The first is size, and it is why the rule was written before the largest environment ran rather than after. `app-shared-001` holds 317 GB, so a cross-zone copy of it would have been metered on both ends of 317 GB — and because a wrong identifier forces a second full copy, the exposure doubles. The remaining environment is far smaller (34 GB), which lowers the money at stake without changing the rule: the placement is still proven by describing both sides, because the cost of proving it is one API call and the cost of being wrong is not recoverable after creation.

The second is that **Aurora's pricing statements do not transfer to this case, and reading them as though they do is the trap.** Aurora documents that data transferred between Availability Zones for *DB cluster replication* is free — that covers a cluster replicating to its own members, not logical replication between two separate clusters, which is what a key migration runs. Nothing verified so far establishes how the second case is billed, so the placement is arranged so the answer does not matter — same zone, proven by describing both sides, exactly as on beta.

Arranging it needed a module change: `modules/rds_aurora_cluster` did not pass `availability_zone` to `aws_rds_cluster_instance` at all, so an Aurora replacement's writer could not be pinned. That input exists as an optional per-instance attribute, merged in terraform PR #913. The zones each replacement must match, read from the live clusters: **demo `us-east-1a`**, **shared `us-east-1b`**, **atento `us-east-1b`**. Those are the writers; a stack with a second instance places it wherever it already sits, since only the copy's two endpoints decide the bill.

## The pooler console is reachable in every environment, and staying that way is structural

The cutover is zero-downtime only because the pooler can be told to hold clients, and that requires authenticating to its console. Each of the four poolers was tested directly — connecting with the admin credentials Terraform generates and issuing a real `SHOW DATABASES` — and all four answered, so `PAUSE` is available for every remaining cutover. The test is worth repeating rather than inferring from the task definition: the pin proves the container booted with the current userlist, while only the console answering proves the credential in that userlist is the one Terraform state holds.

**The failure that made this a section of its own is worth keeping, because it is silent and it recurs.** A container receives its injected secrets once, when it starts. A task definition that names a secret by bare ARN resolves to `AWSCURRENT` at that moment and never again, and because the reference text is identical whether or not the content changed, changing the content produces no new task definition — so the service never rolls and the process serves forever with what it read at boot. Terraform reports everything applied. Nothing surfaces the divergence until someone needs the console, which in this migration is the worst possible moment: inside the pause window. All four environments were in exactly that state, their pooler tasks having started hours before their userlist secrets were last written.

The repair is structural rather than procedural: `modules/connection_pooler` names the secret's **version id** in the reference, so any content change necessarily produces a different task definition, which the service adopts and rolls deliberately. There is no drift left to detect, which is why no recurring check is prescribed here. ECS Exec was considered as a companion — it would let a drifted container be repaired in place with SIGHUP — and deliberately left out, because the pin makes that drift impossible for anything Terraform manages and Exec would pull task-role IAM into the change. A userlist written outside Terraform is the case that would earn it.

**Replacing a pooler's tasks costs no downtime and no aborted transaction, and this is designed rather than incidental.** Each pooler runs two tasks under `maximumPercent` 200 / `minimumHealthyPercent` 100, so ECS starts the replacements and gates them on a real `pg_isready` probe before touching the incumbents — two healthy tasks answer throughout. The incumbents then receive the image's `STOPSIGNAL`, SIGINT, which pgbouncer defines as `SHUTDOWN WAIT_FOR_SERVERS`: *"Stop accepting new connections and shutdown after all servers are released."* Under `pool_mode = transaction` a server is released at every transaction boundary, so the drain lasts as long as the longest in-flight transaction and no longer, with `stopTimeout = 120` as the ceiling. Cloud Map is MULTIVALUE at TTL 10, so clients follow within about ten seconds.

What it does cost is a reconnect: the idle pooled client connections on the outgoing tasks close, and clients open new ones. Applying the pin across the fleet exercised this at every scale — the application logged **zero** connection errors on all four stacks, against 715 log events on demo, 11,480 on shared and 31,429 on atento. **The one consumer never exercised is the outbound payroll worker**, which reaches shared's pooler across a region boundary and rests at zero replicas by design; its reconnect path is the longest in the fleet and the first run after a pooler replacement is the first real observation of it.

Fargate platform version is a prerequisite for the pinned form (1.4.0+) and every pooler service runs on `LATEST`, so nothing else is owed.

## The copy wants a quiet window; the cutover wants a STAFFED one

These are different windows and they pull in opposite directions, so scheduling them as one event gets one of them wrong.

**The copy is background and belongs on the quiet days.** It runs with the source serving normally, its cost is I/O on both clusters, and nothing about it touches the application. A weekend is the right place for it — not because it must finish there, but because that is when the heavy I/O competes with the least.

**The cutover belongs at the START of a working week.** It is seconds long and engineered not to drop a connection, so the risk is not in the operation — it is in the hours and days after, when the application is running against a database it has never run against before. That is when a missing grant, a sequence, or a performance characteristic surfaces, and the thing that bounds the damage is people being available to see it and act. A Sunday-night cutover buys the quietest traffic and the emptiest on-call; a Monday or Tuesday morning cutover buys the opposite, and the opposite is what this risk needs.

**So the copy finishing outside the weekend is not a failure of the plan.** Once the initial copy completes, the subscription stays in streaming mode and holds the target current indefinitely — completion and cutover are independent events, and the target can sit in sync for as long as the schedule wants.

What bounds that waiting is the **migration freeze**: DDL is not replicated, so no schema migration may ship between `replicate` and `confirm`, and a migration that ships anyway diverges the target while replication keeps reporting healthy. The freeze is the reason the wait cannot be indefinite — it is not the two clusters' cost, which is minor.

**Expect a cold cache after the cutover, and do not read it as a regression.** The replacement has never served this workload, so its buffer cache is empty against a working set far larger than the instance's memory; the first queries go to disk and latency is elevated until the cache fills. It resolves on its own. The reader instance is cold for the same reason. Reverting on this signal would trade a transient for a second full cutover.

## The copy's cost is index maintenance, and the rate that follows from it

The initial copy's cost is not moving rows — it is maintaining indexes while the rows land. A table carrying more index than heap pays that on every row, so index weight rather than table size predicts which tables dominate the copy. `measure` reports heap, index weight and index count per table before anything moves, so those tables are known in advance rather than discovered at the tail.

**The rate to plan with is 7 GB/h**, from a full copy that moved 318 GB in about 45 hours on a `db.t4g.large` with every index in place. Read it as an average and not as a rate: the first hours run far faster because the small tables finish first, so an early extrapolation predicts a completion that never arrives, and the index-heavy tables are the tail.

## The sequence, end to end

One environment, in order. `<env>` is the stack (`shared-001`), `<source>` its existing cluster, `<target>` the replacement named per ADR-012. Everything up to `hold` is reversible.

```
S=app-<env>-cluster ; T=app-<env> ; E=<env>
D=~/Projects/4Shark/terraform/app-<env>

rds-reprovision.sh measure   --source $S            # size, index weight, WAL rate — before anything

# PR 1 — declare the replacement (writer pinned to the source writer's zone,
#        environment's own KMS key, `self` ingress on the database SG)
rds-reprovision.sh preflight --source $S --target $T --environment $E
rds-reprovision.sh prepare   --source $S --target $T --environment $E
rds-reprovision.sh certify   --target $T --environment $E
rds-reprovision.sh replicate --source $S --target $T
rds-reprovision.sh status    --source $S --target $T     # until every table reads 'r'
rds-reprovision.sh verify    --source $S --target $T

# PR 2 — the cutover: repoint the internal record AND the backup selections
rds-reprovision.sh hold      --source $S --target $T --environment $E --stack-dir $D
#   ... engineer applies PR 2 here, inside the window, with -replace on each
#       restore-testing selection ...
rds-reprovision.sh release   --target $T --environment $E --stack-dir $D
rds-reprovision.sh confirm   --target $T --environment $E --stack-dir $D
#   ... verify the repointed selections against AWS, per region ...

# Retirement — only after the environment has run on the replacement
rds-reprovision.sh detach    --source $S --target $T
# PR 3 — deletion_protection = false, skip_final_snapshot = true
# PR 4 — remove the module block (the predecessor's log group stays)
```

**Three things sit outside the script and each one has bitten.** The **MFA session is renewed BEFORE `hold`, never inside the window** — an apply needs a 15-minute margin, and discovering an expired session with clients held turns a window into an outage. The **schema-migration freeze** holds from `replicate` to `confirm`, because DDL is not replicated and a migration mid-window desynchronises the target silently while the subscription keeps reporting healthy. And **the backup resources name the predecessor** — the plan's backup selection and, where the stack declares them, the restore-testing selections — so PR 2 repoints all of them alongside the record, rather than deferring it to the teardown. A predecessor that stops being backed up the moment it stops serving is the wrong trade; the replacement is what needs protecting from the cutover onward.

**Verify a repoint against AWS, never against terraform's own report.** A backup selection is force-new, so terraform destroys and recreates it and the new value lands at creation; a restore-testing selection updates in place, and that update has been observed to report success without persisting. `Modifications complete after 0s` against a remote API is the tell — a change that reached AWS takes measurable time. Apply the cutover with `-replace` on each restore-testing selection so it takes the recreate path, then read the live value back per region, because the cross-region selection is a separate resource and a check that covers only the local one passes while half the repoint is missing:

```bash
aws backup get-restore-testing-selection --restore-testing-plan-name <plan> --restore-testing-selection-name <selection> --region <region> --query 'RestoreTestingSelection.ProtectedResourceArns'
```

Left unrepointed, restore testing targets a cluster that is about to be destroyed: the validation that proves the backups are restorable stops being real without failing loudly. Only `app-shared-001` declares restore testing today — check whether the environment being migrated does before assuming this step is empty.

**Before accepting `skip_final_snapshot`, confirm the backups exist** — `aws backup list-recovery-points-by-resource --resource-arn <cluster-arn>`. That is what makes the skipped snapshot a duplicate rather than a loss, and it is checked per environment rather than assumed from the backup plan.

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

**`pg_dumpall` records the GRANTOR of every role membership, and the target's master cannot act as it.** The dump emits `GRANT "<app-role>" TO postgres WITH INHERIT TRUE GRANTED BY rdsadmin`, and the target master is not `rdsadmin`, so that statement fails with `permission denied to grant privileges as role "rdsadmin"`. The failure is quiet in its consequence rather than in its message: the master never becomes a member of the application role, and `CREATE DATABASE ... OWNER <app-role>` in step 1.2 is then refused with `must be able to SET ROLE`. Strip the grantor, along with the privileged attribute tokens the master also cannot set:

```bash
sed -e 's/ NOSUPERUSER//g' -e 's/ NOREPLICATION//g' -e 's/ NOBYPASSRLS//g' -e 's/ GRANTED BY [^;]*//g' /tmp/roles.sql > /tmp/roles_loadable.sql
```

Review the file before loading it: `pg_dumpall` emits the RDS-internal roles too, and loading those either fails or is a no-op. Then load what is genuinely ours:

```bash
psql --host <target-host> --username <master-user> --dbname postgres --file /tmp/roles.sql
```

**1.1a Every role the pooler authenticates with arrives on the target with no password, and how you restore them decides whether the pooler works after cutover.**

Setting one from the plaintext the application uses is the obvious move and it is **wrong**. `password_encryption` is `scram-sha-256`, so `ALTER ROLE ... PASSWORD '<plaintext>'` stores a **SCRAM** verifier. The pooler's userlist holds an **md5** verifier for that role (`auth_type = md5`), and md5 is all it can answer with — a server holding a SCRAM verifier demands SCRAM, and the pooler cannot compute SCRAM from an md5 hash. The pooler then reports `cannot do SCRAM authentication: wrong password type` on every attempt to open a server connection.

Copy the verifier instead. PostgreSQL accepts a pre-hashed md5 string verbatim, and the md5 verifier is `md5(password || rolename)` — bound to the role name, which is identical on both sides, so the transplant is exact. PostgreSQL 18 accepts it with a deprecation warning; support runs through v20 ([release notes](https://www.postgresql.org/docs/18/release-18.html)).

**The transplant covers EVERY role in the pooler's `[databases]` section, not the application role alone — and a productive stack has more than one.** A stack with a read follower declares two pools, a master pool and a follower pool, each with its own distinct role; the follower's role owns no tables, so the `prepare` step that resolves "the application role" from table ownership never sees it. Transplanting only what that resolution returns leaves the second role holding a SCRAM verifier, and the consequence is **partial and therefore quiet**: the master pool authenticates and the application serves, while the follower pool fails to open server connections and every read routed to it errors. Read the roles from the pooler's own configuration rather than assuming how many there are:

```bash
aws ecs describe-task-definition --task-definition <env>-connection-pooler --region us-east-1 --query 'taskDefinition.containerDefinitions[0].environment[?name==`PGBOUNCER_INI_B64`].value' --output text > /tmp/pgbouncer_ini_b64.txt
base64 --decode -i /tmp/pgbouncer_ini_b64.txt -o /tmp/pgbouncer.ini
sed -n 's/.*[[:space:]]user=\([^[:space:]]*\).*/\1/p' /tmp/pgbouncer.ini | sort -u > /tmp/pooler_roles.txt
```

`stats_users` and `admin_users` are deliberately excluded by that extraction — they are PgBouncer console accounts, not database roles, and an `ALTER ROLE` naming one fails. Then emit one statement per pooler role and confirm the count matches the number of pools before loading anything:

```bash
aws secretsmanager get-secret-value --secret-id <env>-connection-pooler-userlist --region us-east-1 --query SecretString --output text > /tmp/userlist_b64.txt
base64 --decode -i /tmp/userlist_b64.txt -o /tmp/userlist.txt
awk -F'"' 'NR==FNR { pooler_role[$1] = 1; next } pooler_role[$2] && $4 ~ /^md5/ { printf "ALTER ROLE \"%s\" PASSWORD '\''%s'\'';\n", $2, $4 }' /tmp/pooler_roles.txt /tmp/userlist.txt > /tmp/set_pooler_role_passwords.sql
wc -l /tmp/pooler_roles.txt /tmp/set_pooler_role_passwords.sql
psql --host <target-host> --username <master-user> --dbname <dbname> --set ON_ERROR_STOP=1 --file /tmp/set_pooler_role_passwords.sql
```

A statement count below the role count means a pooler role is missing from the userlist or is not stored as md5 — stop there, because loading the short file leaves exactly the silent half-failure described above.

The verifier never passes through a terminal or a session — it moves file to file. Delete `/tmp/userlist*.txt`, `/tmp/pgbouncer*`, `/tmp/pooler_roles.txt` and the generated `.sql` as soon as the `ALTER ROLE` statements return.

**`pg_authid` cannot confirm this afterwards — RDS denies it to the master, so there is no SQL check of a role's credential type.** What confirms it is the pooler's own log: `aws logs tail /ecs/<env>-connection-pooler --since 30m --filter-pattern "wrong password type"` returning nothing once the tasks have recycled their server connections (`server_lifetime = 600`, so within ten minutes). A run that skips this check discovers the gap only when a user hits a read.

**Then prove it, rather than reasoning about it.** The application's plaintext password lives in `/<env>/DATABASE_URL` (SSM, `SecureString`), which is what makes a real end-to-end login test possible:

```bash
psql --host <target-host> --username <app-role> --dbname <dbname> --command "SELECT current_user; SELECT count(*) FROM information_schema.table_privileges WHERE grantee = current_user AND privilege_type = 'SELECT';"
```

A successful login proves the verifier; the privilege count matching the table count proves the schema load carried the grants. Delete the extracted password file afterwards.

**1.2 Create the database.** The Terraform modules do not expose `database_name`, so this is deliberate and manual.

```bash
psql --host <target-host> --username <master-user> --dbname postgres --command "CREATE DATABASE <dbname>;"
```

**1.3 Load the schema in one atomic pass, preserving ownership.**

Check who owns the application tables on the source first. The answer decides whether the dump may strip ownership, and on this application it may not:

```bash
psql --host <source-host> --username <master-user> --dbname <dbname> --command "SELECT tableowner, count(*) FROM pg_tables WHERE schemaname='public' GROUP BY tableowner;"
```

Every application table is owned by the application role, not by the master. A dump taken with `--no-owner` would leave them all owned by the master on the target, and the application — which connects as its own role — could not write after cutover. So the dump preserves ownership, which is `pg_dump`'s default.

Take the schema, then load it:

```bash
pg_dump --schema-only --host <source-host> --username <master-user> --dbname <dbname> --file /tmp/schema.sql
```

**The load is atomic, and this is not optional**:

```bash
psql --host <target-host> --username <master-user> --dbname <dbname> --single-transaction --set ON_ERROR_STOP=1 --file /tmp/schema.sql
```

Without those two flags an interrupted load leaves a half-built schema that the next run silently completes around, producing a database assembled from two runs and reporting `already exists` errors that look harmless. With them, an interruption rolls back to empty and the operator simply runs it again.

**The dump carries session settings that can postdate the target, and the newest client is a deliberate choice.** `pg_dump` emits `SET` statements for the server it was built against; a client newer than the target emits settings the target rejects outright, failing the load on its first line. The client must be at least as new as the newest server in the fleet, so it is newer than the older ones by construction — the settings are stripped rather than the client downgraded. `prepare` deletes the known offender before loading; a manual run does the same:

```bash
sed -e '/^SET transaction_timeout = /d' /tmp/schema.sql > /tmp/schema_loadable.sql
```

### Phase 2 — Start replication

**2.1 Freeze schema migrations for the whole window.** DDL is not replicated: *"Data definition language (DDL) statements, such as CREATE TABLE and CREATE SCHEMA, aren't replicated"*. A migration mid-window desynchronises the target silently — the subscription keeps reporting healthy while the table shapes diverge. This is a deploy-pipeline decision, not a database one.

**2.2 Publication on the source.** Requires `rds_superuser`.

```bash
psql --host <source-host> --username <master-user> --dbname <dbname> --command "CREATE PUBLICATION reprovision FOR ALL TABLES;"
```

**2.3 Subscription on the target.** The connection string carries the master password, so this command is composed and run by the engineer with the value from their own shell — it is the one command in this procedure that cannot be copied verbatim from a document.

```
CREATE SUBSCRIPTION reprovision
  CONNECTION 'host=<source-host> dbname=<dbname> user=<master-user> password=<from-secrets-manager>'
  PUBLICATION reprovision;
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

**Read the progress as tables finished, not as elapsed time against a percentage.** The small tables finish first, so the early hours look far faster than the copy will average and an extrapolation taken there predicts a completion that never arrives. A full copy against a fully-indexed target moved 318 GB in about 45 hours; the index-heavy tables are the tail. `pg_subscription_rel` naming the tables still in state `d` is what tells you which ones are holding the copy — the ones `measure` flagged for index weight are the ones you expect to see there.

**Nothing about a long copy needs intervening on.** The subscription streams once the initial copy finishes and holds the target current indefinitely, so a copy that runs past the window it started in has not failed — completion and cutover are independent (see *The copy wants a quiet window*).

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

**The predecessor must be RUNNING for either apply — do not stop it to save money before the teardown.** AWS refuses both `ModifyDBCluster` and `DeleteDBCluster` on a stopped cluster, so a stopped predecessor has to be started and waited back to `available` before anything can proceed. Stopping it is legitimate as a *test* — it answers "does anything still reach the old database?" the way nothing else does — but it is then undone, and the test costs a start plus the wait. **The cheaper test is the connection metric**, which answers the same question without touching the cluster:

```bash
aws cloudwatch get-metric-statistics --namespace AWS/RDS --metric-name DatabaseConnections --dimensions Name=DBClusterIdentifier,Value=<predecessor> --start-time <iso> --end-time <iso> --period 300 --statistics Maximum --region us-east-1
```

A predecessor that has held zero connections since the cutover is a predecessor nothing points at. Leaving it running and idle for that observation window is the shape that costs nothing but time.

Skipping the final snapshot is deliberate and needs its evidence each time: AWS Backup already holds daily recovery points for these instances, so the snapshot would duplicate a backup that exists. Confirm the recovery points before accepting the skip — `aws backup list-recovery-points-by-resource --resource-arn <instance-arn>` answers it in one call.

**On a productive environment the predecessor's CloudWatch log group is KEPT, and its declaration stays in the stack.** The cluster is destroyed; the group is not. Its retention window then runs out on its own, which leaves the collected records readable for as long as a problem traceable to the period that database served can still surface — the destroy would otherwise discard them at the moment they become most useful. Nothing writes there afterwards, so the group is retained rather than orphaned, and the declaration comes out in a later change once the window has passed. Say so in a comment at the declaration, because a log group whose cluster no longer exists reads as leftover to anyone who was not there.

Each apply is its own PR, which keeps one commit per pull request and makes each apply match a state a reviewer can read.

## What the binary owns, and what stays with the engineer

The `rds-reprovision` skill follows `mongodb-reprovision`'s split: the script owns the dangerous repetitive half, the engineer owns the Terraform and every apply. Its `SKILL.md` carries the invocation rules, the invariants and the traps; this table is the phase mapping for this migration.

| Verb | Phase | What it does |
|---|---|---|
| `measure` | before 0 | Logical size and table count, the largest tables with their index weight and index count, WAL rate, tables without a primary key |
| `preflight` | 0 | Client-versus-server version, zone match, network comparison, pooler-console currency |
| `prepare` | 1 | Roles, the md5 verifier transplant for **the single role table ownership resolves**, the database with its owner asserted, the atomic schema load — a productive stack's second pooler role is NOT covered and is transplanted by hand before the cutover (finding 43) |
| `certify` | 1 | Connects AS the application: login, DDL privilege, grant completeness |
| `replicate` | 2 | Publication on the source, subscription on the target |
| `status` | 3 | Per-table state, stream and lag, error counters |
| `verify` | 4 | Structure and ownership by catalog, row-id boundaries per table |
| `hold` / `release` | 5 | Opens and closes the cutover window around the engineer's apply |
| `confirm` | 5 | Asks the pooler where its backend connections go — the conclusive proof |
| `detach` | 6 | Drops the subscription and publication, verifies the slot was released |

**The engineer owns** the Terraform — declaring the replacement, repointing the record, retiring the predecessor — every apply, and the migration freeze. **Rotating the migration secret is theirs too and sits outside this procedure**: it is a credential change with its own consumers, so it is done separately rather than folded into a step here — the procedure never leaves a rotation owed to itself.

**The cutover is NOT one indivisible verb, and that is forced rather than chosen.** The apply that repoints the record sits inside the window where clients are held, and an apply is the engineer's approval — so the window opens with `hold` and closes with `release`, with the apply between them. Every other seam would park the system between two databases; this one already exists because the approval boundary creates it.

**`certify` is the verb that earns its place most.** It connects AS the application, and every cheaper check passes on a target the application cannot use: a role can exist, own every table, carry the correct verifier, and match the source on schema-ACL text, and still be unable to log in (finding 23) or run a migration (finding 29). It reads the plaintext from `/<env>/DATABASE_URL` for that one connection — the md5 transplant still works from the pooler's userlist, so the plaintext is read to *verify*, never to *set*.

Three things the script resolves for itself rather than accepting as arguments, because each is a fact about the system that a caller could get wrong:

**The application role**, from table ownership on the source — and it refuses when public tables have more than one owner, since that is the assumption breaking rather than a value to guess. **The logical database name**, from the pooler's own console, because the name the pooler exposes differs from the real one and the pooler is the authority on what it serves. **The pooler's console credentials**, from the stack's Terraform state via `--stack-dir`, because that state is the only place the admin password exists and every way of handing it in leaks it — each invocation is a fresh shell, so a caller could only pass it as a `VAR=value` prefix, which puts it in argv for `ps`, in shell history and in a session transcript (finding 27).

**Discovery accepts an Aurora cluster or a standalone instance without being told which.** A cluster costs two API calls, and the reason is not symmetry: the cluster knows its endpoint, master secret and security groups, but the **Availability Zone belongs to an instance**. The cluster spans its subnet group while the writer is the endpoint the copy actually flows through, so the writer's zone is the one that decides whether the transfer is billed.

## Order of execution across the four environments

The order ran smallest and cheapest to fail first: the non-productive single instance, then the non-productive cluster, then the productive ones. **Three are through, `atento-001` is the last**, and it inherits a procedure that has been corrected against a real productive run rather than only a rehearsal.

**Everything the remaining migration structurally depends on is in place.** `modules/rds_aurora_cluster` takes the `availability_zone` input that lets a replacement's writer be pinned to its source's zone (ADR-012's naming and PR #913). Every pooler's task definition names its userlist secret's version, so the console credentials cannot drift again and `PAUSE` is reachable in all four environments (PR #912, applied to each stack before merging, since the module it changes is shared by all of them).

**What the earlier runs cost, and what they bought**, is the reason the last one should be cheap: the privileged attribute tokens and the recorded grantor that each make `pg_dumpall`'s output unloadable, leaving the application role unable to log in or the database unable to be created with the right owner (23, 33); the anchored error count that reported a clean load over a failed one (23); `--command`'s lack of variable interpolation, whose obvious workarounds put the password in argv (25); the two PostgreSQL major versions in the fleet, which made a catalog query die on the environments it was not written against (26); a dump carrying a session setting the target rejects (34); two counts of "the same thing" that counted different populations (35); a privilege function evaluated on rows its `WHERE` meant to exclude (36); a repoint terraform reported as applied that never reached AWS (39); and a verifier transplant scoped to the single role table ownership resolves, which leaves a productive stack's second pooler role unable to authenticate while the first one serves normally (40). Every one is fixed in the script or in this document.

**Before the last migration begins, five things are settled in this order.** Its replacement's zone placement and the billing question above, because both are fixed at creation. Its pooler's console access, because the check is cheap and the failure is only discoverable when the window is already open. **How many roles its pooler authenticates with**, read from the `[databases]` section of its own configuration, because that number is what step 1.1a's transplant must produce and a short transplant fails silently on the pools it missed. Its replacement's identifier, which is the name the environment keeps forever — `app-<env>-001` with `app-<env>-001-instance<NNN>`, free because what the existing databases occupy is `app-<env>-001-cluster`. And **whether the stack declares restore testing**, because that decides if the cutover PR carries the `-replace` of finding 39 or has nothing to repoint.

**The five settled items each have an answer for the remaining environment**, read from the live infrastructure rather than carried forward: the writer sits in `us-east-1b`, so the replacement's writer is pinned there; the pooler's `[databases]` section defines **two** pools, so the verifier transplant must produce two `ALTER ROLE` statements and a count of one means it missed the follower; the replacement is `app-atento-001` with `app-atento-001-instance001` and `-instance002`, free because the source occupies `app-atento-001-cluster`; and **the stack declares no restore testing**, so the cutover PR repoints the internal records and the backup selection and has no restore-testing selection to `-replace`.

**Volume changes timing and nothing else, and for this environment it barely changes that.** 34 GB against shared's 317 GB means the copy is measured in hours, so the window can be opened rather than scheduled weeks out. No step changes. The WAL rate makes retention a non-issue as well: 1232 kB/h, or 87 MB across a three-day window, so the source has nothing to strain to retain while the copy runs.

**The identifier is decided, and it is what makes each remaining migration a single copy rather than two.** A database is named `app-<env>-001` and a member instance `app-<env>-001-instance<NNN>` — the application, the environment, the environment's version, and nothing about the engine (ADR-012 in the terraform repository). The names that hold that shape are free today, because what the existing databases occupy is `app-<env>-001-cluster`, so a replacement is born with its permanent name instead of taking a suffix and needing a second migration to shed it. `app-beta-001` already satisfies the rule.

The concrete targets: **demo** `app-demo-001` with `app-demo-001-instance001`; **shared** `app-shared-001` with `app-shared-001-instance001` and `-instance002`; **atento** `app-atento-001` with the same pair.

**One PR per environment, not one PR for all four.** A PR that declares every environment's replacement cannot be merged until every environment has been migrated, because 4Shark applies before merging — so the first environment's work would sit unmerged behind three that have not started, and every branch cut afterwards would have to stack on it or plan against infrastructure its own base does not describe. Scoping the PR to the environment being migrated keeps each one mergeable the moment its own apply is confirmed. The cutover, and each of the two teardown applies, are their own PRs for the same reason.

The three environments still waiting have **no replacement declared anywhere**. Each gets its own PR when its migration starts, shaped like the completed one's — same arguments, `rds_aurora_cluster` instead of `rds_instance`, one instance, the encryption key and the identifier and the zone all set at creation because none of them is editable afterwards, and the self-ingress rule on the security group so the replacement can be filled by replication.

**The pooler indirection is the exception to that split, and deliberately so.** The records and the admin user are the *mechanism* the cutover runs on rather than a per-environment resource, so they land once for all four.

**Any pooler apply that changes the task definition replaces that stack's tasks, and there is no version of it that does not.** `modules/connection_pooler/main.tf:475-477` states the reason inline — the service deliberately carries no `ignore_changes = [task_definition]`, because Terraform is the only author of its revisions and the service must adopt what it declares. The replacement is the graceful one described above: no interruption of service, no aborted transaction, only a reconnect on the idle pooled connections the outgoing tasks held. The new DNS records themselves resolve nothing until the cutover repoints them.
