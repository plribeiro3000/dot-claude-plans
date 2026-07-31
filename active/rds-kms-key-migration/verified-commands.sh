#!/usr/bin/env bash
#
# Verified command sequence for moving an app database onto its environment's own
# KMS key, recorded from the first manual run.
#
# This is NOT a script to run. It is the raw material for the skill and binary:
# every command here was executed against a real environment and either succeeded
# or failed in a way that taught something, and each is annotated with what it
# actually does and what bites.
#
# Placeholders:
#   SOURCE_HOST   endpoint of the database being replaced
#   TARGET_HOST   endpoint of the encrypted replacement
#   DB            application database name
#   MASTER        master role (postgres on every environment here)
#   SOURCE_SECRET / TARGET_SECRET   Secrets Manager ARNs of the managed master passwords
#
# Two invariants that hold for every command below, both learned the hard way:
#
#   1. Call the PostgreSQL client by absolute path. Homebrew does not link a
#      versioned formula onto PATH, and pg_dump REFUSES a server newer than
#      itself — a 17 client against an 18 server fails at the schema step, after
#      everything before it has already succeeded.
#
#   2. Never write a .pgpass. The RDS-managed master password is 28 characters
#      including punctuation and can contain ':', which is .pgpass's field
#      separator. libpq then reports `password retrieved from file` and fails
#      authentication, which reads as a wrong password rather than a malformed
#      file. Pass PGPASSWORD for the single command that needs it.

PSQL=/opt/homebrew/opt/postgresql@18/bin/psql
PG_DUMP=/opt/homebrew/opt/postgresql@18/bin/pg_dump
PG_DUMPALL=/opt/homebrew/opt/postgresql@18/bin/pg_dumpall

# =============================================================================
# PRE-FLIGHT — cheap checks that each prevent a late, expensive failure
# =============================================================================

# Client version must be >= server version, or pg_dump aborts.
"$PG_DUMP" --version
"$PSQL" --host "$SOURCE_HOST" --username "$MASTER" --dbname "$DB" --no-password \
  --command "SELECT version();"

# rds.logical_replication must be 1. It is a STATIC parameter, so if it is off,
# turning it on requires rebooting the source — a production restart before the
# migration can even begin. It is already 1 in every parameter group in this
# fleet, which is why no reboot is needed. Cluster parameter group for Aurora:
aws rds describe-db-cluster-parameters \
  --db-cluster-parameter-group-name "$CLUSTER_PARAM_GROUP" --region us-east-1 \
  --query "Parameters[?ParameterName=='rds.logical_replication'].[ParameterValue,ApplyType]"

# Instance parameter group for a plain RDS instance:
aws rds describe-db-parameters \
  --db-parameter-group-name "$PARAM_GROUP" --region us-east-1 \
  --query "Parameters[?ParameterName=='rds.logical_replication'].[ParameterValue,ApplyType]"

# Reachability, LEG 1 — the security group must admit ITSELF on 5432, or
# CREATE SUBSCRIPTION times out after every other step has already succeeded.
# The rule is present when a UserIdGroupPairs entry names the group's own id.
#
# Reachability, LEG 2 — the same output must carry the POOLER's group id. The
# application never reaches the database directly: it resolves the pooler, and
# the pooler holds the backend host as a Terraform reference, so the cutover is
# a Terraform edit the app never sees. If the pooler cannot reach the target,
# that is discovered at the repoint — writes stopped, source already out.
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=${ENVIRONMENT}-rds-*" --region us-east-1 \
  --query "SecurityGroups[0].{GroupId:GroupId,Ingress:IpPermissions}"

# Resolve the ingress group ids by their Name tag — the rule descriptions are
# free text and are not evidence of which group is which.
aws ec2 describe-security-groups --group-ids "$POOLER_SG" "$APP_SG" --region us-east-1 \
  --query 'SecurityGroups[].{Id:GroupId,Name:Tags[?Key==`Name`].Value|[0]}'

# Leg 2, the decisive form: describe BOTH databases and compare. Identical VPC +
# subnets + security group means they sit behind one network object, so nothing
# that reaches the source can fail to reach the target. Any difference is a
# Blocker to resolve BEFORE Phase 1, never at cutover time.
aws rds describe-db-instances --db-instance-identifier "$SOURCE_ID" --region us-east-1 \
  --query 'DBInstances[0].{VPC:DBSubnetGroup.VpcId,Subnets:DBSubnetGroup.Subnets[].SubnetIdentifier,SG:VpcSecurityGroups[].VpcSecurityGroupId}'

# Same query on the target, plus the state and key checks it is the only place for.
aws rds describe-db-instances --db-instance-identifier "$TARGET_ID" --region us-east-1 \
  --query 'DBInstances[0].{VPC:DBSubnetGroup.VpcId,Subnets:DBSubnetGroup.Subnets[].SubnetIdentifier,SG:VpcSecurityGroups[].VpcSecurityGroupId,Status:DBInstanceStatus,Endpoint:Endpoint.Address,Key:KmsKeyId}'

# =============================================================================
# PHASE 1 — prepare the target
# =============================================================================

# 1.1 Roles. Logical replication does not carry roles; they are cluster-level
# objects. The application role must exist on the target or the schema restore
# fails on ownership and the pooler cannot authenticate after cutover.
#
# --no-role-passwords is MANDATORY on RDS: the master is not a superuser, so a
# plain roles dump dies with `permission denied for table pg_authid`.
"$PG_DUMPALL" --roles-only --no-role-passwords \
  --host "$SOURCE_HOST" --username "$MASTER" --no-password \
  --file /tmp/roles.sql

# Triage that file rather than loading it. It carries every RDS-internal role
# (rds_ad, rds_extension, rds_iam, rds_password, rds_replication, rds_reserved,
# rds_superuser, rdsadmin) which already exist on the target, plus the master.
# What is ours is what remains:
"$PSQL" --host "$SOURCE_HOST" --username "$MASTER" --dbname "$DB" --no-password \
  --command "SELECT rolname, rolcanlogin, rolsuper, rolcreatedb FROM pg_roles WHERE rolname NOT LIKE 'pg\_%' AND rolname NOT LIKE 'rds%' ORDER BY rolname;"

# Create only ours, with the attributes the dump reported for it.
PGPASSWORD="$TARGET_PASSWORD" "$PSQL" --host "$TARGET_HOST" --username "$MASTER" --dbname postgres \
  --command "CREATE ROLE ${APP_ROLE} WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN NOREPLICATION NOBYPASSRLS;"

# The master needs membership to manage objects the app role owns.
PGPASSWORD="$TARGET_PASSWORD" "$PSQL" --host "$TARGET_HOST" --username "$MASTER" --dbname postgres \
  --command "GRANT ${APP_ROLE} TO ${MASTER} WITH INHERIT TRUE;"

# 1.1a The app role's PASSWORD — COPY the md5 verifier, never set it from the
# plaintext. password_encryption is scram-sha-256, so ALTER ROLE with a plaintext
# stores a SCRAM verifier; the pooler runs auth_type=md5 and can only answer md5,
# so the server would demand SCRAM and the pooler could not connect. That failure
# surfaces at the repoint — writes stopped, source already out.
#
# The verifier is md5(password || rolename), bound to the role name, which is
# identical on both sides, so it transplants exactly. PostgreSQL 18 accepts a
# pre-hashed md5 string with a deprecation warning.
#
# File to file — the verifier never enters a terminal or a session.
aws secretsmanager get-secret-value --secret-id "${ENVIRONMENT}-connection-pooler-userlist" \
  --region us-east-1 --query SecretString --output text > /tmp/userlist_b64.txt

base64 --decode -i /tmp/userlist_b64.txt -o /tmp/userlist.txt

sed -n "s/^\"${APP_ROLE}\" \"\(md5[0-9a-f]\{32\}\)\".*/ALTER ROLE \"${APP_ROLE}\" PASSWORD '\1';/p" \
  /tmp/userlist.txt > /tmp/set_app_role_password.sql

PGPASSWORD="$TARGET_PASSWORD" "$PSQL" --host "$TARGET_HOST" --username "$MASTER" --dbname "$DB" \
  --set ON_ERROR_STOP=1 --file /tmp/set_app_role_password.sql

rm -f /tmp/userlist_b64.txt /tmp/userlist.txt /tmp/set_app_role_password.sql

# PROVE it with a real login rather than reasoning about hash equality. The
# application's plaintext lives in SSM, which is what makes this test possible.
# A successful login proves the verifier; the privilege count matching the table
# count proves the schema load carried the grants.
aws ssm get-parameter --name "/${ENVIRONMENT}/DATABASE_URL" --with-decryption \
  --region us-east-1 --query 'Parameter.Value' --output text > /tmp/database_url.txt

sed -n 's#^[a-z]*://[^:]*:\([^@]*\)@.*#\1#p' /tmp/database_url.txt > /tmp/app_pw.txt

PGPASSWORD="$(cat /tmp/app_pw.txt)" "$PSQL" --host "$TARGET_HOST" --username "$APP_ROLE" --dbname "$DB" \
  --no-password \
  --command "SELECT current_user, current_database();" \
  --command "SELECT count(*) FROM information_schema.table_privileges WHERE grantee = current_user AND privilege_type = 'SELECT';"

rm -f /tmp/database_url.txt /tmp/app_pw.txt

# 1.2 The application database. Neither Terraform module exposes database_name,
# so this is a deliberate manual step.
PGPASSWORD="$TARGET_PASSWORD" "$PSQL" --host "$TARGET_HOST" --username "$MASTER" --dbname postgres \
  --command "CREATE DATABASE ${DB};"

# 1.3 The schema, WITH ownership. Check who owns the tables first — on this
# application every table is owned by the app role, so a --no-owner dump would
# leave them all owned by the master and the application could not write after
# cutover.
"$PSQL" --host "$SOURCE_HOST" --username "$MASTER" --dbname "$DB" --no-password \
  --command "SELECT tableowner, count(*) FROM pg_tables WHERE schemaname='public' GROUP BY tableowner;"

"$PG_DUMP" --schema-only \
  --host "$SOURCE_HOST" --username "$MASTER" --dbname "$DB" --no-password \
  --file /tmp/schema.sql

# The load is ATOMIC, and this is not optional. Without these two flags an
# interrupted load leaves a half-built schema that a later run silently completes
# around, producing a database assembled from two runs whose only visible symptom
# is a handful of `already exists` errors that look harmless.
PGPASSWORD="$TARGET_PASSWORD" "$PSQL" --host "$TARGET_HOST" --username "$MASTER" --dbname "$DB" \
  --single-transaction --set ON_ERROR_STOP=1 --file /tmp/schema.sql

# 1.4 Verify structure against the CATALOG, never information_schema. The
# information_schema views are permission-filtered — they show only what the
# connecting user may see — and report differences that do not exist whenever the
# master's privileges differ between the two databases.
STRUCTURE_QUERY="SELECT 'tables', count(*) FROM pg_tables WHERE schemaname='public'
UNION ALL SELECT 'sequences', count(*) FROM pg_sequences WHERE schemaname='public'
UNION ALL SELECT 'indexes', count(*) FROM pg_indexes WHERE schemaname='public'
UNION ALL SELECT 'constraints', count(*) FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace WHERE n.nspname='public'
UNION ALL SELECT 'columns', count(*) FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r' AND a.attnum>0 AND NOT a.attisdropped;"

"$PSQL" --host "$SOURCE_HOST" --username "$MASTER" --dbname "$DB" --no-password \
  --tuples-only --command "$STRUCTURE_QUERY"

PGPASSWORD="$TARGET_PASSWORD" "$PSQL" --host "$TARGET_HOST" --username "$MASTER" --dbname "$DB" \
  --tuples-only --command "$STRUCTURE_QUERY"

# =============================================================================
# PHASE 2 — start replication
# =============================================================================

# Freeze schema migrations for the whole window first. DDL is not replicated, so
# a migration mid-window desynchronises the target while the subscription keeps
# reporting healthy.

"$PSQL" --host "$SOURCE_HOST" --username "$MASTER" --dbname "$DB" --no-password \
  --command "CREATE PUBLICATION key_migration FOR ALL TABLES;"

# The subscription's connection string carries the source password, so build it
# into a file rather than onto a command line. copy_data defaults to true, and
# that initial copy is the whole reason the target was created empty.
#
# The secret ARN contains '!' (rds!db-...), which interactive zsh expands as
# history — always single-quote it.
aws secretsmanager get-secret-value --secret-id "$SOURCE_SECRET" \
  --region us-east-1 --query SecretString --output text > /tmp/source_secret.json

jq -r '"CREATE SUBSCRIPTION key_migration CONNECTION '"'"'host='"$SOURCE_HOST"' port=5432 dbname='"$DB"' user='"$MASTER"' password=" + .password + " sslmode=require'"'"' PUBLICATION key_migration;"' \
  /tmp/source_secret.json > /tmp/create_subscription.sql

PGPASSWORD="$TARGET_PASSWORD" "$PSQL" --host "$TARGET_HOST" --username "$MASTER" --dbname "$DB" \
  --set ON_ERROR_STOP=1 --file /tmp/create_subscription.sql

rm -f /tmp/create_subscription.sql /tmp/source_secret.json

# =============================================================================
# PHASE 3 — watch it catch up
# =============================================================================

# Per-table state on the target. Every table must reach 'r' (ready); 'd' is the
# initial copy still running.
PGPASSWORD="$TARGET_PASSWORD" "$PSQL" --host "$TARGET_HOST" --username "$MASTER" --dbname "$DB" \
  --command "SELECT srsubstate, count(*) FROM pg_subscription_rel GROUP BY srsubstate;"

# Lag in bytes, from the source.
"$PSQL" --host "$SOURCE_HOST" --username "$MASTER" --dbname "$DB" --no-password \
  --command "SELECT application_name, state, pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes FROM pg_stat_replication;"

# =============================================================================
# PHASE 4 — verify the target, WITHOUT scanning a single table
# =============================================================================
#
# SELECT count(*) is FORBIDDEN on either side. Productive tables hold hundreds of
# millions of rows and a count is a full scan — against the source that is a full
# scan of the database serving customers, to re-prove something the engine already
# guarantees:
#
#   "The subscriber applies the data in the same order as the publisher so that
#    transactional consistency is guaranteed for publications within a single
#    subscription."
#
# So verification proves the MECHANISM is healthy, then samples cheaply.

# Health — four constant-cost checks. The third is the one that matters most: an
# apply error halts replication while every other indicator still looks plausible.
PGPASSWORD="$TARGET_PASSWORD" "$PSQL" --host "$TARGET_HOST" --username "$MASTER" --dbname "$DB" \
  --command "SELECT srsubstate, count(*) FROM pg_subscription_rel GROUP BY srsubstate;"

"$PSQL" --host "$SOURCE_HOST" --username "$MASTER" --dbname "$DB" --no-password \
  --command "SELECT application_name, state, pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes FROM pg_stat_replication;"

PGPASSWORD="$TARGET_PASSWORD" "$PSQL" --host "$TARGET_HOST" --username "$MASTER" --dbname "$DB" \
  --command "SELECT subname, apply_error_count, sync_error_count, confl_insert_exists, confl_update_origin_differs, confl_delete_missing FROM pg_stat_subscription_stats;"

PGPASSWORD="$TARGET_PASSWORD" "$PSQL" --host "$TARGET_HOST" --username "$MASTER" --dbname "$DB" \
  --command "SELECT subname, pid, received_lsn, latest_end_lsn FROM pg_stat_subscription;"

# Sampling — min(id)/max(id) per table. A primary-key btree answers these by index
# scan rather than by reading the table, so the cost is logarithmic per table.
# Run against both and diff; an empty diff is the pass.
BOUNDS_QUERY="SELECT c.relname||'='||coalesce((xpath('/row/lo/text()', x))[1]::text,'-')||':'||coalesce((xpath('/row/hi/text()', x))[1]::text,'-') FROM (SELECT c.oid, c.relname, query_to_xml(format('SELECT min(id) AS lo, max(id) AS hi FROM public.%I', c.relname), false, true, '') AS x FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_attribute a ON a.attrelid=c.oid AND a.attname='id' AND NOT a.attisdropped WHERE n.nspname='public' AND c.relkind='r') c ORDER BY c.relname;"

"$PSQL" --host "$SOURCE_HOST" --username "$MASTER" --dbname "$DB" --no-password \
  --tuples-only --no-align --command "$BOUNDS_QUERY" > /tmp/bounds_source.txt

PGPASSWORD="$TARGET_PASSWORD" "$PSQL" --host "$TARGET_HOST" --username "$MASTER" --dbname "$DB" \
  --tuples-only --no-align --command "$BOUNDS_QUERY" > /tmp/bounds_target.txt

diff /tmp/bounds_source.txt /tmp/bounds_target.txt

# NOT a substitute: pg_stat_user_tables.n_live_tup. It is the statistics
# collector's ESTIMATE, and no ANALYZE has run on a freshly-loaded target, so it
# reports a difference on nearly every table while the data is identical — the
# same family of trap as information_schema.

# =============================================================================
# PHASE 5 — the cutover, with NO downtime and NO "stop writes" step
# =============================================================================
#
# Clients are HELD, never disconnected: "New client connections to a paused
# database will wait until RESUME is called". PAUSE returns in milliseconds only
# because pool_mode is `transaction` — each server connection is released at the
# end of its transaction. Under `session` it would wait for long-lived Rails
# connections to close, i.e. never.
#
# BLOCKED until two module changes land (see PLAN.md 5.0a / 5.0b):
#   a) modules/connection_pooler renders `admin_users` — stats_users may only
#      "run read-only queries on the console", so PAUSE is unreachable today.
#   b) the pooler's backend `host` points at a CNAME in 4shark.internal, not the
#      RDS endpoint — otherwise repointing rewrites the task definition, ECS
#      replaces the tasks, and the paused process dies holding every client
#      connection. Moving host onto the CNAME is itself a task-replacing deploy
#      and belongs on an ordinary day, never on cutover day.
#
# PAUSE IS PER-PROCESS. Cloud Map round-robins across the pooler tasks, so
# connecting to the service name reaches ONE of them. Resolve each task's IP and
# issue the command to every task, or the un-paused one keeps writing to the
# source through the whole cutover.
aws ecs list-tasks --cluster "${ENVIRONMENT}-connection-pooler" \
  --service-name "${ENVIRONMENT}-connection-pooler" --region us-east-1 \
  --query 'taskArns' --output text > /tmp/pooler_task_arns.txt

aws ecs describe-tasks --cluster "${ENVIRONMENT}-connection-pooler" \
  --tasks <arn> <arn> --region us-east-1 \
  --query 'tasks[].attachments[].details[?name==`privateIPv4Address`].value' --output text \
  > /tmp/pooler_task_ips.txt

# Step 1 — hold the clients, on EVERY task. From here the source receives nothing
# from the application, which is what makes steps 2 and 3 well-defined.
PGPASSWORD="$POOLER_ADMIN_PASSWORD" "$PSQL" --host <pooler-task-ip> --port 6432 \
  --username "$POOLER_ADMIN" --dbname pgbouncer --no-password --command "PAUSE ${POOLER_DB};"

# Step 2 — lag must be ZERO, not small. The source is quiescent, so it converges
# immediately. Use the Phase 3 queries.

# Step 3 — advance the sequences (below).

# Step 4 — point the CNAME at the target. A DNS record change: no terraform apply
# against the app stack, no task definition, no task replacement.

# Step 5 — force fresh resolution rather than waiting out the DNS cache.
# RECONNECT closes each open server connection "after it is released", and there
# are none open at this point because step 1 already released them.
PGPASSWORD="$POOLER_ADMIN_PASSWORD" "$PSQL" --host <pooler-task-ip> --port 6432 \
  --username "$POOLER_ADMIN" --dbname pgbouncer --no-password --command "RECONNECT ${POOLER_DB};"

# Step 6 — release the held clients against the target. They never saw a
# disconnect, only the latency of steps 2 through 5. THAT duration is the entire
# client-visible cost and is the number the non-productive run exists to measure.
PGPASSWORD="$POOLER_ADMIN_PASSWORD" "$PSQL" --host <pooler-task-ip> --port 6432 \
  --username "$POOLER_ADMIN" --dbname pgbouncer --no-password --command "RESUME ${POOLER_DB};"

# --- Step 3 in detail: sequence advancement -----------------------------------
#
# Sequences are not replicated. Miss this and the first inserts after cutover
# collide on primary keys.
#
# Two conditions make the EXACT value correct rather than a value plus a margin,
# and both are checked rather than assumed.
#
# Condition 1 — last_value must not run ahead of what was issued, which it does
# when a sequence caches. Confirm every sequence has cache_size 1:
"$PSQL" --host "$SOURCE_HOST" --username "$MASTER" --dbname "$DB" --no-password \
  --command "SELECT cache_size, count(*) FROM pg_sequences WHERE schemaname='public' GROUP BY cache_size;"

# Condition 2 — generation happens AFTER writes are stopped and lag is confirmed
# zero. That ordering is what makes the source's last_value final. A margin would
# not buy safety, it would only paper over a broken ordering while leaving gaps
# in every id column.
#
# last_value IS NOT NULL is a filter with teeth: a never-used sequence reports
# NULL and is already at its start value on the target, because the schema load
# created it there. setval(..., true) on one would make its first nextval return
# 2 and silently burn the value 1.
"$PSQL" --host "$SOURCE_HOST" --username "$MASTER" --dbname "$DB" --no-password \
  --tuples-only --no-align \
  --command "SELECT 'SELECT setval(' || quote_literal(quote_ident(schemaname) || '.' || quote_ident(sequencename)) || ', ' || last_value || ', true);' FROM pg_sequences WHERE schemaname = 'public' AND last_value IS NOT NULL ORDER BY sequencename;" \
  > /tmp/advance_sequences.sql

PGPASSWORD="$TARGET_PASSWORD" "$PSQL" --host "$TARGET_HOST" --username "$MASTER" --dbname "$DB" \
  --set ON_ERROR_STOP=1 --file /tmp/advance_sequences.sql

# =============================================================================
# PHASE 5 REMAINDER, PHASE 6 — not yet executed
# =============================================================================
#
# Row-count comparison per table, the cutover (stop writes, confirm zero lag,
# advance every sequence past the source's value, repoint the pooler, resume),
# and the teardown are still unwritten here because they have not been run. The
# sequence-advancement SQL in particular is generated during the first cutover,
# not before it.
