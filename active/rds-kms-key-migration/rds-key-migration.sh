#!/usr/bin/env bash
# Move an app environment's database onto a replacement instance without
# downtime, one environment at a time.
#
# The replacement exists for one of two reasons — it carries the environment's
# own KMS key, or it carries the identifier the environment should have had.
# Neither is expressible as an edit: both arguments are fixed at creation, so
# both are a new instance plus a data copy.
#
# The Terraform half (declaring the replacement, repointing the record, retiring
# the predecessor) is NOT here — bash does not write Terraform, and an apply is
# gated on the engineer's approval. SKILL.md drives that; this script drives the
# database and the pooler.
#
# That gate is why there is no single `cutover` verb. The apply that repoints the
# record sits INSIDE the window where clients are held, so the window is opened
# by `hold`, the engineer applies, and `release` closes it. Splitting anywhere
# else would park the system between two databases; splitting here is the one
# seam the approval boundary already creates.
#
# Discovery is by identifier. Endpoints, master secrets, pooler tasks and their
# addresses are read from AWS — never passed in, never assumed. An identifier may
# name an Aurora cluster or a standalone instance; the caller does not say which.
#
# Usage:
#   rds-key-migration.sh preflight --source <identifier> --target <identifier> --environment <stack>
#   rds-key-migration.sh prepare   --source <identifier> --target <identifier> --environment <stack>
#   rds-key-migration.sh replicate --source <identifier> --target <identifier>
#   rds-key-migration.sh status    --source <identifier> --target <identifier>
#   rds-key-migration.sh verify    --source <identifier> --target <identifier>
#   rds-key-migration.sh hold      --source <identifier> --target <identifier> --environment <stack> --stack-dir <path>
#   rds-key-migration.sh release   --target <identifier> --environment <stack> --stack-dir <path>
#
# `--stack-dir` is the stack's Terraform directory, and only the two commands
# that drive the pooler console need it: the admin password exists nowhere but
# that state.
#
# Examples:
#   rds-key-migration.sh preflight --source app-beta-001-2 --target app-beta-001 --environment beta-001
#   rds-key-migration.sh prepare --source app-demo-001-cluster --target app-demo-001-cluster-2 --environment demo-001

set -euo pipefail

REGION="us-east-1"

# pg_dump REFUSES a server newer than itself, and the failure lands at the schema
# step after everything before it has already succeeded. Homebrew does not link a
# versioned formula onto PATH, so the client is called by absolute path.
PSQL="/opt/homebrew/opt/postgresql@18/bin/psql"
PG_DUMP="/opt/homebrew/opt/postgresql@18/bin/pg_dump"
PG_DUMPALL="/opt/homebrew/opt/postgresql@18/bin/pg_dumpall"

APPLICATION_DATABASE=""
SOURCE_IDENTIFIER=""
TARGET_IDENTIFIER=""
ENVIRONMENT=""
STACK_DIRECTORY=""

COMMAND="${1:-}"
shift || true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      SOURCE_IDENTIFIER="$2"
      shift 2
      ;;
    --target)
      TARGET_IDENTIFIER="$2"
      shift 2
      ;;
    --environment)
      ENVIRONMENT="$2"
      shift 2
      ;;
    --database)
      APPLICATION_DATABASE="$2"
      shift 2
      ;;
    --stack-dir)
      STACK_DIRECTORY="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

die() {
  echo "$1" >&2
  exit 1
}

require_source() {
  [[ -n "$SOURCE_IDENTIFIER" ]] || die "Missing --source. Usage: rds-key-migration.sh ${COMMAND} --source <identifier> ..."
}

require_target() {
  [[ -n "$TARGET_IDENTIFIER" ]] || die "Missing --target. Usage: rds-key-migration.sh ${COMMAND} --target <identifier> ..."
}

require_environment() {
  [[ -n "$ENVIRONMENT" ]] || die "Missing --environment. Usage: rds-key-migration.sh ${COMMAND} --environment <stack> ..."
}

# --- discovery -------------------------------------------------------------
# Never take an endpoint on faith: an identifier that does not resolve here does
# not exist, and a typo that reaches psql reads as a network problem.

# An identifier is a cluster or a standalone instance, and the caller should not
# have to say which — the single-instance environment and the Aurora ones run the
# same procedure. Try the cluster first, fall back to the instance.
#
# A cluster needs TWO calls, and the reason is not symmetry: the cluster knows its
# endpoint, master and security groups, but the AVAILABILITY ZONE is a property of
# an instance. The cluster spans its subnet group; the writer is the endpoint the
# copy actually flows through, so the writer's zone is the one that decides whether
# the transfer is billed.
describe_database() {
  local identifier="$1" cluster_json writer_identifier writer_json

  cluster_json=$(aws rds describe-db-clusters \
    --db-cluster-identifier "$identifier" \
    --region "$REGION" \
    --query 'DBClusters[0].{Endpoint:Endpoint,Master:MasterUsername,Secret:MasterUserSecret.SecretArn,Status:Status,SecurityGroups:VpcSecurityGroups[].VpcSecurityGroupId,Key:KmsKeyId,Writer:DBClusterMembers[?IsClusterWriter].DBInstanceIdentifier|[0]}' \
    --output json 2>/dev/null) || cluster_json=""

  if [[ -n "$cluster_json" && "$cluster_json" != "null" ]]; then
    writer_identifier=$(echo "$cluster_json" | jq -r '.Writer // empty')
    [[ -n "$writer_identifier" ]] || die "Cluster '${identifier}' reports no writer instance."

    writer_json=$(aws rds describe-db-instances \
      --db-instance-identifier "$writer_identifier" \
      --region "$REGION" \
      --query 'DBInstances[0].{Zone:AvailabilityZone,Vpc:DBSubnetGroup.VpcId}' \
      --output json 2>/dev/null) || die "Writer instance '${writer_identifier}' of cluster '${identifier}' could not be described."

    echo "$cluster_json" "$writer_json" | jq -s '.[0] * .[1]'
    return 0
  fi

  aws rds describe-db-instances \
    --db-instance-identifier "$identifier" \
    --region "$REGION" \
    --query 'DBInstances[0].{Endpoint:Endpoint.Address,Master:MasterUsername,Secret:MasterUserSecret.SecretArn,Zone:AvailabilityZone,Status:DBInstanceStatus,Vpc:DBSubnetGroup.VpcId,SecurityGroups:VpcSecurityGroups[].VpcSecurityGroupId,Key:KmsKeyId}' \
    --output json 2>/dev/null || die "No RDS cluster or instance named '${identifier}' in ${REGION}."
}

instance_field() {
  echo "$1" | jq -r ".$2 // empty"
}

# The master password reaches psql through the environment for the single
# command that needs it, and never through a file. RDS generates 28 characters
# including punctuation, and a .pgpass built from that fails authentication
# whenever the password contains the field separator — which reads as a wrong
# password rather than a malformed file.
master_password() {
  aws secretsmanager get-secret-value \
    --secret-id "$1" \
    --region "$REGION" \
    --query SecretString \
    --output text 2>/dev/null | jq -r .password
}

# The application database is not derivable from the identifier: the pooler
# exposes a logical name that differs from the real one. Read it from the source
# rather than guessing, unless the caller named it.
resolve_application_database() {
  local endpoint="$1" master="$2" password="$3"

  [[ -z "$APPLICATION_DATABASE" ]] || return 0

  APPLICATION_DATABASE=$(PGPASSWORD="$password" "$PSQL" --host "$endpoint" --username "$master" --dbname postgres --no-password --tuples-only --no-align \
    --command "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('postgres', 'rdsadmin') ORDER BY datname LIMIT 1;")

  [[ -n "$APPLICATION_DATABASE" ]] || die "Could not resolve the application database on ${endpoint}. Pass --database explicitly."
}

# --- pooler ----------------------------------------------------------------
# Every console command is per-process, and an environment runs more than one
# pooler task. Cloud Map round-robins across them, so a command sent to the
# service name reaches exactly one — and the un-paused task keeps writing to the
# predecessor through the whole cutover.

pooler_task_addresses() {
  local cluster="${ENVIRONMENT}-connection-pooler"
  local task_arns

  task_arns=$(aws ecs list-tasks --cluster "$cluster" --service-name "$cluster" --desired-status RUNNING --region "$REGION" --query 'taskArns' --output text)
  [[ -n "$task_arns" ]] || die "No running pooler tasks in cluster ${cluster}."

  aws ecs describe-tasks --cluster "$cluster" --tasks $task_arns --region "$REGION" \
    --query 'tasks[].attachments[].details[?name==`privateIPv4Address`].value' --output text
}

# The pooler decodes its userlist once, at container start, from a secret
# reference that carries no version. A later change to the secret's content
# produces no new task definition, so ECS never rolls the tasks and the running
# process serves forever with the copy it read at boot — including a console
# credential nobody holds any more.
#
# Discovered when the console refused the password Terraform's state held, on
# tasks that were running the only task-definition revision that exists.
pooler_userlist_is_current() {
  local cluster="${ENVIRONMENT}-connection-pooler"
  local secret_changed oldest_task_start task_arns

  secret_changed=$(aws secretsmanager describe-secret --secret-id "${cluster}-userlist" --region "$REGION" --query 'LastChangedDate' --output text)
  task_arns=$(aws ecs list-tasks --cluster "$cluster" --service-name "$cluster" --desired-status RUNNING --region "$REGION" --query 'taskArns' --output text)
  oldest_task_start=$(aws ecs describe-tasks --cluster "$cluster" --tasks $task_arns --region "$REGION" --query 'min_by(tasks, &startedAt).startedAt' --output text)

  echo "  userlist secret last changed: ${secret_changed}"
  echo "  oldest running pooler task:   ${oldest_task_start}"

  [[ "$oldest_task_start" > "$secret_changed" ]]
}

# The console credentials come from the stack's Terraform state, which is the
# only place the admin password exists: the module generates it, publishes the
# user name as an output, and keeps the password nowhere else. `terraform state
# show` redacts it, so the JSON form is what carries it.
#
# Reading it here rather than taking it from the caller is a secrecy decision,
# not a convenience. Every invocation of this script is a fresh shell, so a
# caller could only supply the password as a `VAR=value` prefix — which puts it
# in the process's argv for `ps`, and in the shell history and any session
# transcript of whoever ran it. The value never leaves this process.
require_pooler_console() {
  [[ -n "$STACK_DIRECTORY" ]] || die "Missing --stack-dir. The pooler's console password lives only in that stack's Terraform state."

  local state_json
  state_json=$(bash "${HOME}/.claude/scripts/terraform.sh" "$STACK_DIRECTORY" show -json | head -1)

  POOLER_ADMIN_USER=$(echo "$state_json" | jq -r '[.. | objects | select(.address? | strings | test("connection_pooler.random_string.admin_user$"))][0].values.result // empty')
  POOLER_ADMIN_PASSWORD=$(echo "$state_json" | jq -r '[.. | objects | select(.address? | strings | test("connection_pooler.random_password.admin_user$"))][0].values.result // empty')

  [[ -n "$POOLER_ADMIN_USER" ]] || die "No connection_pooler admin user in the state at ${STACK_DIRECTORY}."
  [[ -n "$POOLER_ADMIN_PASSWORD" ]] || die "No connection_pooler admin password in the state at ${STACK_DIRECTORY}."
}

# The logical name the pooler exposes differs from the real database name, and it
# is read from the console rather than passed in — the pooler is the authority on
# what it serves. `pgbouncer` is its own administrative database and never the
# application's.
resolve_pooler_database() {
  local address="$1"

  POOLER_DATABASE=$(pooler_console "$address" "SHOW DATABASES;" --tuples-only --no-align --field-separator='|' \
    | awk -F'|' '$1 != "pgbouncer" && $1 != "" { print $1; exit }')

  [[ -n "$POOLER_DATABASE" ]] || die "The pooler at ${address} exposes no application database."
}

pooler_console() {
  local address="$1" statement="$2"
  shift 2

  PGPASSWORD="$POOLER_ADMIN_PASSWORD" "$PSQL" --host "$address" --port 6432 \
    --username "$POOLER_ADMIN_USER" --dbname pgbouncer --no-password "$@" --command "$statement"
}

# --- commands --------------------------------------------------------------

command_preflight() {
  require_source
  require_target
  require_environment

  local source_json target_json

  source_json=$(describe_database "$SOURCE_IDENTIFIER")
  target_json=$(describe_database "$TARGET_IDENTIFIER")

  echo "Client and server versions"
  "$PG_DUMP" --version

  echo
  echo "Placement — transfer between instances in one Availability Zone over"
  echo "private addressing is free; crossing zones is metered on both ends."
  local source_zone target_zone
  source_zone=$(instance_field "$source_json" Zone)
  target_zone=$(instance_field "$target_json" Zone)
  echo "  source: ${source_zone}"
  echo "  target: ${target_zone}"
  [[ "$source_zone" == "$target_zone" ]] || die "Zones differ — the copy would be billed on both ends. Recreate the target in ${source_zone}; availability_zone is fixed at creation."

  echo
  echo "Network — identical VPC and security groups mean the two databases sit"
  echo "behind one object, so nothing that reaches one can fail to reach the other."
  local source_vpc target_vpc source_groups target_groups
  source_vpc=$(instance_field "$source_json" Vpc)
  target_vpc=$(instance_field "$target_json" Vpc)
  source_groups=$(echo "$source_json" | jq -r '.SecurityGroups | sort | join(",")')
  target_groups=$(echo "$target_json" | jq -r '.SecurityGroups | sort | join(",")')
  echo "  source: ${source_vpc} / ${source_groups}"
  echo "  target: ${target_vpc} / ${target_groups}"
  [[ "$source_vpc" == "$target_vpc" ]] || die "Different VPCs — resolve routing before starting, not at cutover."
  [[ "$source_groups" == "$target_groups" ]] || die "Different security groups — the pooler's path to the target is unproven."

  echo
  echo "Pooler console — PAUSE is the only thing that makes the cutover"
  echo "zero-downtime, and it is unreachable when the tasks predate the userlist."
  if pooler_userlist_is_current; then
    echo "  tasks are newer than the secret: console credentials should be current"
  else
    die "Pooler tasks predate the userlist secret. They serve the copy read at boot, so no console credential works. Roll the pooler service on a scheduled window BEFORE the cutover — never inside the pause."
  fi
}

# Brings the target from empty to subscribable: roles, then the application
# role's password, then the database, then the schema. The order is forced —
# roles are cluster-level and must exist before a schema that assigns ownership
# to them, and the password is a cluster-level ALTER that cannot wait for a
# database that does not exist yet.
command_prepare() {
  require_source
  require_target
  require_environment

  local source_json target_json source_endpoint target_endpoint source_master target_master source_password target_password
  local application_role owners existing

  source_json=$(describe_database "$SOURCE_IDENTIFIER")
  target_json=$(describe_database "$TARGET_IDENTIFIER")
  source_endpoint=$(instance_field "$source_json" Endpoint)
  target_endpoint=$(instance_field "$target_json" Endpoint)
  source_master=$(instance_field "$source_json" Master)
  target_master=$(instance_field "$target_json" Master)
  source_password=$(master_password "$(instance_field "$source_json" Secret)")
  target_password=$(master_password "$(instance_field "$target_json" Secret)")

  resolve_application_database "$source_endpoint" "$source_master" "$source_password"

  # --- roles ---------------------------------------------------------------
  # Logical replication carries table data and nothing else. Roles are
  # cluster-level objects, so without this step the schema load fails on
  # ownership and the pooler cannot authenticate after cutover.
  #
  # --no-role-passwords is mandatory rather than cautious: the RDS master is not
  # a superuser, so reading verifiers fails with `permission denied for table
  # pg_authid` and the dump comes out EMPTY instead of partial.
  echo "Dumping roles from the source"
  PGPASSWORD="$source_password" "$PG_DUMPALL" --roles-only --no-role-passwords \
    --host "$source_endpoint" --username "$source_master" --no-password \
    --file /tmp/rds_migration_roles.sql

  # The privileged attribute tokens are stripped, and without this the
  # application role silently arrives unable to log in.
  #
  # pg_dumpall writes ONE ALTER ROLE carrying every attribute at once — `WITH
  # NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN NOREPLICATION NOBYPASSRLS`
  # — and PostgreSQL refuses the WHOLE statement when it mentions an attribute
  # the caller does not itself hold: "Only roles with the SUPERUSER attribute may
  # change the SUPERUSER attribute", then the same for REPLICATION. The RDS
  # master holds none of the three, so the role is created by the preceding
  # CREATE ROLE and then never receives LOGIN — and nothing about that reads as a
  # failure until an application tries to authenticate.
  #
  # Dropping the tokens is lossless: all three are already off for a role created
  # here, and the master could not grant any of them anyway.
  sed -e 's/ NOSUPERUSER//g' -e 's/ NOREPLICATION//g' -e 's/ NOBYPASSRLS//g' \
    /tmp/rds_migration_roles.sql > /tmp/rds_migration_roles_loadable.sql

  # Deliberately NOT ON_ERROR_STOP: pg_dumpall emits the RDS-internal roles too,
  # and those either already exist or are protected. Those errors are expected;
  # the count below is what separates them from a real failure.
  echo "Loading roles into the target"
  PGPASSWORD="$target_password" "$PSQL" --host "$target_endpoint" --username "$target_master" \
    --dbname postgres --no-password --file /tmp/rds_migration_roles_loadable.sql \
    > /tmp/rds_migration_roles_load.log 2>&1 || true

  # psql prefixes every diagnostic with `psql:<file>:<line>: `, so an anchored
  # `^ERROR` matches nothing and reports a clean load over a failed one.
  echo "  errors reported: $(grep -c 'ERROR:' /tmp/rds_migration_roles_load.log || true) (RDS-internal roles are expected here — see /tmp/rds_migration_roles_load.log)"

  # --- the application role's password -------------------------------------
  # Discovered, not passed: on this application every public table is owned by
  # the application role, so ownership IS the answer. More than one owner means
  # the assumption no longer holds and the caller must decide.
  owners=$(PGPASSWORD="$source_password" "$PSQL" --host "$source_endpoint" --username "$source_master" --dbname "$APPLICATION_DATABASE" --no-password --tuples-only --no-align \
    --command "SELECT DISTINCT tableowner FROM pg_tables WHERE schemaname='public';")
  [[ $(echo "$owners" | grep -c .) -eq 1 ]] || die "Public tables on the source have more than one owner, so the application role is ambiguous: ${owners}"
  application_role="$owners"
  echo "Application role, from table ownership on the source: ${application_role}"

  # The verifier is COPIED, never set from plaintext. password_encryption is
  # scram-sha-256, so ALTER ROLE ... PASSWORD '<plaintext>' stores a SCRAM
  # verifier — and the pooler authenticates with md5 and cannot compute SCRAM
  # from it. Everything looks right until the repoint, and then the pooler cannot
  # reach the target from INSIDE the cutover window.
  #
  # md5 is md5(password || rolename), bound to a role name identical on both
  # sides, so the transplant is exact. The value moves file to file and never
  # through this session.
  aws secretsmanager get-secret-value --secret-id "${ENVIRONMENT}-connection-pooler-userlist" --region "$REGION" \
    --query SecretString --output text > /tmp/rds_migration_userlist_b64.txt
  base64 --decode -i /tmp/rds_migration_userlist_b64.txt -o /tmp/rds_migration_userlist.txt
  sed -n "s/^\"${application_role}\" \"\(md5[0-9a-f]\{32\}\)\".*/ALTER ROLE \"${application_role}\" PASSWORD '\1';/p" \
    /tmp/rds_migration_userlist.txt > /tmp/rds_migration_set_role_password.sql

  [[ -s /tmp/rds_migration_set_role_password.sql ]] || die "No md5 verifier for '${application_role}' in the ${ENVIRONMENT} userlist. Without it the pooler cannot authenticate to the target after cutover."

  PGPASSWORD="$target_password" "$PSQL" --host "$target_endpoint" --username "$target_master" \
    --dbname postgres --no-password --set ON_ERROR_STOP=1 --file /tmp/rds_migration_set_role_password.sql > /dev/null
  rm -f /tmp/rds_migration_userlist_b64.txt /tmp/rds_migration_userlist.txt /tmp/rds_migration_set_role_password.sql
  echo "  md5 verifier transplanted onto the target"

  # --- the database --------------------------------------------------------
  # The modules do not expose database_name, so the database is created here.
  # Skipping when it exists is what makes a re-run after an interrupted schema
  # load possible.
  existing=$(PGPASSWORD="$target_password" "$PSQL" --host "$target_endpoint" --username "$target_master" --dbname postgres --no-password --tuples-only --no-align \
    --command "SELECT 1 FROM pg_database WHERE datname = '${APPLICATION_DATABASE}';")

  if [[ -n "$existing" ]]; then
    echo "Database ${APPLICATION_DATABASE} already present on the target"
  else
    echo "Creating database ${APPLICATION_DATABASE} on the target, owned by ${application_role}"
    PGPASSWORD="$target_password" "$PSQL" --host "$target_endpoint" --username "$target_master" --dbname postgres --no-password \
      --set ON_ERROR_STOP=1 --command "CREATE DATABASE \"${APPLICATION_DATABASE}\" OWNER \"${application_role}\";"
  fi

  # Ownership is asserted rather than assumed, because a database created by the
  # master and left that way silently strips the application role of DDL — and
  # nothing before a deploy's migration reveals it.
  #
  # Since PostgreSQL 15 the public schema grants USAGE and CREATE to
  # `pg_database_owner`, an implicit role whose only member is whoever owns the
  # database. So the owner is not bookkeeping: it IS the application role's
  # CREATE privilege. A schema-level GRANT would not substitute for it, and
  # comparing schema ACLs between the two databases shows them identical while
  # the privilege differs.
  PGPASSWORD="$target_password" "$PSQL" --host "$target_endpoint" --username "$target_master" --dbname postgres --no-password \
    --set ON_ERROR_STOP=1 --command "ALTER DATABASE \"${APPLICATION_DATABASE}\" OWNER TO \"${application_role}\";" > /dev/null
  echo "  database owned by ${application_role}"

  # --- the schema ----------------------------------------------------------
  # Ownership is PRESERVED (pg_dump's default). A --no-owner dump would leave
  # every table owned by the master, and the application connects as its own role
  # and could not write after cutover.
  echo "Dumping the schema from the source"
  PGPASSWORD="$source_password" "$PG_DUMP" --schema-only \
    --host "$source_endpoint" --username "$source_master" --dbname "$APPLICATION_DATABASE" --no-password \
    --file /tmp/rds_migration_schema.sql

  # Atomic, and this is not optional: without both flags an interrupted load
  # leaves a half-built schema that the next run silently completes around,
  # producing a database assembled from two runs. With them, an interruption
  # rolls back to empty and the operator simply runs it again.
  echo "Loading the schema into the target"
  PGPASSWORD="$target_password" "$PSQL" --host "$target_endpoint" --username "$target_master" \
    --dbname "$APPLICATION_DATABASE" --no-password --single-transaction --set ON_ERROR_STOP=1 \
    --file /tmp/rds_migration_schema.sql > /dev/null

  echo
  echo "Target prepared. Confirm the application role can actually log in before"
  echo "starting replication — a successful login proves the verifier, and the"
  echo "privilege count proves the schema load carried the grants."
  echo "Then create the publication on the source and the subscription on the target."
}

# Starts the copy: a publication on the source, a subscription on the target.
# `copy_data` is left at its default of true — that initial load is the whole
# reason the target was created empty.
#
# The subscription's connection string carries the source master's password, and
# it is composed HERE rather than handed to an operator to paste. The value is
# read from Secrets Manager into a variable the same way every other command in
# this script reads it, so it never reaches a terminal, a document or a session
# transcript. Pasting a live credential to make a document self-contained is the
# worse of the two options, not the safer one.
command_replicate() {
  require_source
  require_target

  local source_json target_json source_endpoint target_endpoint source_master target_master source_password target_password
  local existing escaped_password connection_string

  source_json=$(describe_database "$SOURCE_IDENTIFIER")
  target_json=$(describe_database "$TARGET_IDENTIFIER")
  source_endpoint=$(instance_field "$source_json" Endpoint)
  target_endpoint=$(instance_field "$target_json" Endpoint)
  source_master=$(instance_field "$source_json" Master)
  target_master=$(instance_field "$target_json" Master)
  source_password=$(master_password "$(instance_field "$source_json" Secret)")
  target_password=$(master_password "$(instance_field "$target_json" Secret)")

  resolve_application_database "$source_endpoint" "$source_master" "$source_password"

  existing=$(PGPASSWORD="$source_password" "$PSQL" --host "$source_endpoint" --username "$source_master" --dbname "$APPLICATION_DATABASE" --no-password --tuples-only --no-align \
    --command "SELECT 1 FROM pg_publication WHERE pubname = 'key_migration';")

  if [[ -n "$existing" ]]; then
    echo "Publication already present on the source"
  else
    echo "Creating the publication on the source"
    PGPASSWORD="$source_password" "$PSQL" --host "$source_endpoint" --username "$source_master" --dbname "$APPLICATION_DATABASE" --no-password \
      --set ON_ERROR_STOP=1 --command "CREATE PUBLICATION key_migration FOR ALL TABLES;"
  fi

  # Two layers of quoting sit between the password and the server, and both are
  # handled rather than hoped over. Inside the conninfo the value is single-quoted
  # with `'` and `\` backslash-escaped; the whole conninfo then becomes a SQL
  # literal, where every `'` is doubled. RDS permits any printable ASCII character
  # except / " @ and space, so an apostrophe in a generated password is possible.
  escaped_password=$(printf '%s' "$source_password" | sed "s/[\\\\']/\\\\&/g")
  connection_string="host=${source_endpoint} port=5432 dbname=${APPLICATION_DATABASE} user=${source_master} password='${escaped_password}' sslmode=require"
  quoted_connection_string=$(printf '%s' "$connection_string" | sed "s/'/''/g")

  # The statement reaches psql through STDIN, written by a shell builtin. The
  # alternatives both leak: `--command` cannot interpolate a psql variable at all
  # (its argument must be parseable by the server as-is), and passing the conninfo
  # as an argument would place the password in a process's argv, where `ps` shows
  # it to every user on the machine for as long as the command runs. A builtin
  # forks nothing, so nothing appears in the process table, and no file is
  # written for a failure to leave behind.
  echo "Creating the subscription on the target — this begins the initial copy"
  printf "CREATE SUBSCRIPTION key_migration CONNECTION '%s' PUBLICATION key_migration;\n" "$quoted_connection_string" \
    | PGPASSWORD="$target_password" "$PSQL" --host "$target_endpoint" --username "$target_master" --dbname "$APPLICATION_DATABASE" --no-password \
      --set ON_ERROR_STOP=1

  echo
  echo "Replication started. Watch it with:"
  echo "  rds-key-migration.sh status --source ${SOURCE_IDENTIFIER} --target ${TARGET_IDENTIFIER}"
  echo
  echo "Schema migrations must stay frozen for the whole window: DDL is not"
  echo "replicated, so a migration here desynchronises the target silently while"
  echo "the subscription keeps reporting healthy."
}

# Severs the replication link once the application is off the source, which is
# the first step of retiring it and the only reversible one — everything after
# this destroys.
#
# Order is forced: the subscription goes first, because dropping it is what
# releases the replication slot on the publisher. Dropping the publication first
# would leave the slot behind with nothing feeding it.
#
# An orphaned slot is the reason this verb verifies rather than assumes. A slot
# with no consumer pins WAL on the source indefinitely, and the source fills up
# quietly — a failure that surfaces days later as a full disk on a database
# nobody is watching any more.
command_detach() {
  require_source
  require_target

  local source_json target_json source_endpoint target_endpoint source_master target_master source_password target_password
  local remaining_slots application_connections

  source_json=$(describe_database "$SOURCE_IDENTIFIER")
  target_json=$(describe_database "$TARGET_IDENTIFIER")
  source_endpoint=$(instance_field "$source_json" Endpoint)
  target_endpoint=$(instance_field "$target_json" Endpoint)
  source_master=$(instance_field "$source_json" Master)
  target_master=$(instance_field "$target_json" Master)
  source_password=$(master_password "$(instance_field "$source_json" Secret)")
  target_password=$(master_password "$(instance_field "$target_json" Secret)")

  resolve_application_database "$target_endpoint" "$target_master" "$target_password"

  # Refuse while the application still reaches the source. Dropping the
  # subscription there would strand every write that had not yet replicated.
  application_connections=$(PGPASSWORD="$source_password" "$PSQL" --host "$source_endpoint" --username "$source_master" --dbname "$APPLICATION_DATABASE" --no-password --tuples-only --no-align \
    --command "SELECT count(*) FROM pg_stat_activity WHERE datname = '${APPLICATION_DATABASE}' AND usename <> '${source_master}';")

  [[ "$application_connections" == "0" ]] || die "${application_connections} non-master connections are still open on the source. The cutover has not finished; detaching now would strand their writes."

  echo "Dropping the subscription on the target"
  PGPASSWORD="$target_password" "$PSQL" --host "$target_endpoint" --username "$target_master" --dbname "$APPLICATION_DATABASE" --no-password \
    --set ON_ERROR_STOP=1 --command "DROP SUBSCRIPTION key_migration;"

  echo "Dropping the publication on the source"
  PGPASSWORD="$source_password" "$PSQL" --host "$source_endpoint" --username "$source_master" --dbname "$APPLICATION_DATABASE" --no-password \
    --set ON_ERROR_STOP=1 --command "DROP PUBLICATION key_migration;"

  remaining_slots=$(PGPASSWORD="$source_password" "$PSQL" --host "$source_endpoint" --username "$source_master" --dbname "$APPLICATION_DATABASE" --no-password --tuples-only --no-align \
    --command "SELECT count(*) FROM pg_replication_slots WHERE slot_name = 'key_migration';")

  [[ "$remaining_slots" == "0" ]] || die "The replication slot 'key_migration' survives on the source. It pins WAL with nothing consuming it — drop it with pg_drop_replication_slot before the source is left unattended."

  echo "  replication slot released on the source"
}

command_status() {
  require_source
  require_target

  local source_json target_json source_endpoint target_endpoint source_master target_master source_password target_password

  source_json=$(describe_database "$SOURCE_IDENTIFIER")
  target_json=$(describe_database "$TARGET_IDENTIFIER")
  source_endpoint=$(instance_field "$source_json" Endpoint)
  target_endpoint=$(instance_field "$target_json" Endpoint)
  source_master=$(instance_field "$source_json" Master)
  target_master=$(instance_field "$target_json" Master)
  source_password=$(master_password "$(instance_field "$source_json" Secret)")
  target_password=$(master_password "$(instance_field "$target_json" Secret)")

  resolve_application_database "$source_endpoint" "$source_master" "$source_password"

  # Four constant-cost checks touching no table data. The error counters carry
  # the most weight: an apply error HALTS replication while every other
  # indicator still looks plausible.
  echo "Per-table state on the target — every table must reach 'r'"
  PGPASSWORD="$target_password" "$PSQL" --host "$target_endpoint" --username "$target_master" --dbname "$APPLICATION_DATABASE" --no-password \
    --command "SELECT srsubstate, count(*) FROM pg_subscription_rel GROUP BY srsubstate;"

  echo "Stream and lag, from the source"
  PGPASSWORD="$source_password" "$PSQL" --host "$source_endpoint" --username "$source_master" --dbname "$APPLICATION_DATABASE" --no-password \
    --command "SELECT application_name, state, pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes FROM pg_stat_replication;"

  # `SELECT *` rather than a column list, because the fleet is not on one server
  # version: the single-instance environment runs PostgreSQL 18 and the Aurora
  # ones run 17, and the per-conflict counters (`confl_insert_exists` and its
  # siblings) exist only from 18. Naming them makes the whole query fail on 17
  # with `column does not exist` — losing the apply and sync error counters too,
  # which are the ones that carry the weight, since an apply error HALTS
  # replication while every other indicator still looks plausible.
  echo "Error counters on the target"
  PGPASSWORD="$target_password" "$PSQL" --host "$target_endpoint" --username "$target_master" --dbname "$APPLICATION_DATABASE" --no-password \
    --expanded --command "SELECT * FROM pg_stat_subscription_stats;"
}

# Structure reads the CATALOG, never information_schema — those views are
# permission-filtered, so they report differences that do not exist whenever the
# master's privileges differ between the two databases.
#
# Data is sampled by min(id)/max(id), which a primary-key btree answers by index
# scan. count(*) is forbidden on either side: it is a full scan, and on the
# source that is a full scan of the database serving customers.
command_verify() {
  require_source
  require_target

  local source_json target_json source_endpoint target_endpoint source_master target_master source_password target_password

  source_json=$(describe_database "$SOURCE_IDENTIFIER")
  target_json=$(describe_database "$TARGET_IDENTIFIER")
  source_endpoint=$(instance_field "$source_json" Endpoint)
  target_endpoint=$(instance_field "$target_json" Endpoint)
  source_master=$(instance_field "$source_json" Master)
  target_master=$(instance_field "$target_json" Master)
  source_password=$(master_password "$(instance_field "$source_json" Secret)")
  target_password=$(master_password "$(instance_field "$target_json" Secret)")

  resolve_application_database "$source_endpoint" "$source_master" "$source_password"

  local structure_query bounds_query
  # Ownership is compared alongside the counts, and it is not decoration. Since
  # PostgreSQL 15 the public schema grants CREATE to `pg_database_owner`, so the
  # database's owner IS the application role's ability to run a migration. A
  # target created by the master matches the source on every count and on the
  # schema ACL text, and still cannot accept a deploy's `db:migrate`.
  structure_query="SELECT 'tables', count(*) FROM pg_tables WHERE schemaname='public' UNION ALL SELECT 'sequences', count(*) FROM pg_sequences WHERE schemaname='public' UNION ALL SELECT 'indexes', count(*) FROM pg_indexes WHERE schemaname='public' UNION ALL SELECT 'constraints', count(*) FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace WHERE n.nspname='public' UNION ALL SELECT 'columns', count(*) FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r' AND a.attnum>0 AND NOT a.attisdropped UNION ALL SELECT 'owner:database:'||pg_get_userbyid(datdba), 1 FROM pg_database WHERE datname=current_database() UNION ALL SELECT 'owner:schema:'||pg_get_userbyid(nspowner), 1 FROM pg_namespace WHERE nspname='public' UNION ALL SELECT 'owner:table:'||tableowner, count(*) FROM pg_tables WHERE schemaname='public' GROUP BY tableowner UNION ALL SELECT 'owner:sequence:'||sequenceowner, count(*) FROM pg_sequences WHERE schemaname='public' GROUP BY sequenceowner ORDER BY 1;"
  bounds_query="SELECT c.relname||'='||coalesce((xpath('/row/lo/text()', x))[1]::text,'-')||':'||coalesce((xpath('/row/hi/text()', x))[1]::text,'-') FROM (SELECT c.oid, c.relname, query_to_xml(format('SELECT min(id) AS lo, max(id) AS hi FROM public.%I', c.relname), false, true, '') AS x FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_attribute a ON a.attrelid=c.oid AND a.attname='id' AND NOT a.attisdropped WHERE n.nspname='public' AND c.relkind='r') c ORDER BY c.relname;"

  PGPASSWORD="$source_password" "$PSQL" --host "$source_endpoint" --username "$source_master" --dbname "$APPLICATION_DATABASE" --no-password --tuples-only --command "$structure_query" > /tmp/rds_migration_structure_source.txt
  PGPASSWORD="$target_password" "$PSQL" --host "$target_endpoint" --username "$target_master" --dbname "$APPLICATION_DATABASE" --no-password --tuples-only --command "$structure_query" > /tmp/rds_migration_structure_target.txt

  echo "Structure, by catalog"
  diff /tmp/rds_migration_structure_source.txt /tmp/rds_migration_structure_target.txt && echo "  identical"

  PGPASSWORD="$source_password" "$PSQL" --host "$source_endpoint" --username "$source_master" --dbname "$APPLICATION_DATABASE" --no-password --tuples-only --no-align --command "$bounds_query" > /tmp/rds_migration_bounds_source.txt
  PGPASSWORD="$target_password" "$PSQL" --host "$target_endpoint" --username "$target_master" --dbname "$APPLICATION_DATABASE" --no-password --tuples-only --no-align --command "$bounds_query" > /tmp/rds_migration_bounds_target.txt

  echo "Row-id boundaries per table"
  diff /tmp/rds_migration_bounds_source.txt /tmp/rds_migration_bounds_target.txt && echo "  identical"
}

# Opens the window. Clients are HELD, never disconnected — a paused database
# makes new connections wait rather than fail, and PAUSE returns in milliseconds
# only because pool_mode is transaction, which releases each server connection at
# the end of its transaction.
#
# Stops before the Terraform apply on purpose: an apply is the engineer's, and
# the record change belongs inside this window.
command_hold() {
  require_source
  require_target
  require_environment

  local source_json target_json source_endpoint target_endpoint source_master target_master source_password target_password address

  source_json=$(describe_database "$SOURCE_IDENTIFIER")
  target_json=$(describe_database "$TARGET_IDENTIFIER")
  source_endpoint=$(instance_field "$source_json" Endpoint)
  target_endpoint=$(instance_field "$target_json" Endpoint)
  source_master=$(instance_field "$source_json" Master)
  target_master=$(instance_field "$target_json" Master)
  source_password=$(master_password "$(instance_field "$source_json" Secret)")
  target_password=$(master_password "$(instance_field "$target_json" Secret)")

  resolve_application_database "$source_endpoint" "$source_master" "$source_password"

  # A caching sequence hands out values ahead of what it records, which would
  # make last_value an underestimate and the first inserts after cutover collide.
  local cached
  cached=$(PGPASSWORD="$source_password" "$PSQL" --host "$source_endpoint" --username "$source_master" --dbname "$APPLICATION_DATABASE" --no-password --tuples-only --no-align \
    --command "SELECT count(*) FROM pg_sequences WHERE schemaname='public' AND cache_size <> 1;")
  [[ "$cached" == "0" ]] || die "${cached} sequences cache values, so last_value is not the last value issued. Resolve before holding clients."

  require_pooler_console

  local addresses
  addresses=$(pooler_task_addresses)
  resolve_pooler_database "$(echo "$addresses" | awk '{print $1; exit}')"
  echo "Pooler serves the application as '${POOLER_DATABASE}'"

  for address in $addresses; do
    echo "Holding clients on ${address}"
    pooler_console "$address" "PAUSE ${POOLER_DATABASE};"
  done

  echo "Lag must be zero, not small — the source is quiescent now"
  PGPASSWORD="$source_password" "$PSQL" --host "$source_endpoint" --username "$source_master" --dbname "$APPLICATION_DATABASE" --no-password \
    --command "SELECT application_name, state, pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes FROM pg_stat_replication;"

  # last_value IS NOT NULL is a filter with teeth: a sequence never used reports
  # NULL and already sits at its start value on the target, so setval(..., true)
  # on one would make its first nextval return 2 and burn the value 1.
  PGPASSWORD="$source_password" "$PSQL" --host "$source_endpoint" --username "$source_master" --dbname "$APPLICATION_DATABASE" --no-password --tuples-only --no-align \
    --command "SELECT 'SELECT setval(' || quote_literal(quote_ident(schemaname) || '.' || quote_ident(sequencename)) || ', ' || last_value || ', true);' FROM pg_sequences WHERE schemaname = 'public' AND last_value IS NOT NULL ORDER BY sequencename;" > /tmp/rds_migration_advance_sequences.sql

  PGPASSWORD="$target_password" "$PSQL" --host "$target_endpoint" --username "$target_master" --dbname "$APPLICATION_DATABASE" --no-password --set ON_ERROR_STOP=1 --file /tmp/rds_migration_advance_sequences.sql > /dev/null
  echo "Sequences advanced: $(wc -l < /tmp/rds_migration_advance_sequences.sql | tr -d ' ') statements"

  echo
  echo "Clients are held. Apply the Terraform change that repoints the record, then run:"
  echo "  rds-key-migration.sh release --target ${TARGET_IDENTIFIER} --environment ${ENVIRONMENT}"
}

# Closes the window. RECONNECT is what makes resolution deterministic rather than
# left to a DNS cache expiring, and it costs nothing here because PAUSE already
# released every server connection.
command_release() {
  require_target
  require_environment

  local target_json target_endpoint target_master target_password address

  target_json=$(describe_database "$TARGET_IDENTIFIER")
  target_endpoint=$(instance_field "$target_json" Endpoint)
  target_master=$(instance_field "$target_json" Master)
  target_password=$(master_password "$(instance_field "$target_json" Secret)")

  resolve_application_database "$target_endpoint" "$target_master" "$target_password"

  require_pooler_console

  local addresses
  addresses=$(pooler_task_addresses)
  resolve_pooler_database "$(echo "$addresses" | awk '{print $1; exit}')"

  for address in $addresses; do
    echo "Reconnecting and releasing on ${address}"
    pooler_console "$address" "RECONNECT ${POOLER_DATABASE};"
    pooler_console "$address" "RESUME ${POOLER_DATABASE};"
  done

  echo
  echo "Where the application is connected now — the replacement should carry the"
  echo "application role, and the predecessor should carry none of it."
  PGPASSWORD="$target_password" "$PSQL" --host "$target_endpoint" --username "$target_master" --dbname "$APPLICATION_DATABASE" --no-password \
    --command "SELECT usename, count(*) AS connections FROM pg_stat_activity WHERE datname='${APPLICATION_DATABASE}' GROUP BY usename;"

  echo
  echo "Still owed, and neither is covered by the record change:"
  echo "  - drop the subscription on the target and the publication on the source"
  echo "  - rewrite MIGRATION_DATABASE_URL, a GitHub environment secret holding a"
  echo "    direct RDS URL, before the predecessor can be destroyed"
}

case "$COMMAND" in
  preflight) command_preflight ;;
  prepare)   command_prepare ;;
  replicate) command_replicate ;;
  detach)    command_detach ;;
  status)    command_status ;;
  verify)    command_verify ;;
  hold)      command_hold ;;
  release)   command_release ;;
  *)         die "Usage: rds-key-migration.sh {preflight|prepare|status|verify|hold|release} --source <identifier> --target <identifier> --environment <stack>" ;;
esac
