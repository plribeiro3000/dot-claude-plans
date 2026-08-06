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
# addresses are read from AWS — never passed in, never assumed.
#
# Usage:
#   rds-key-migration.sh preflight --source <identifier> --target <identifier> --environment <stack>
#   rds-key-migration.sh status    --source <identifier> --target <identifier>
#   rds-key-migration.sh verify    --source <identifier> --target <identifier>
#   rds-key-migration.sh hold      --source <identifier> --target <identifier> --environment <stack>
#   rds-key-migration.sh release   --target <identifier> --environment <stack>
#
# Examples:
#   rds-key-migration.sh preflight --source app-beta-001-2 --target app-beta-001 --environment beta-001
#   rds-key-migration.sh hold --source app-beta-001-2 --target app-beta-001 --environment beta-001

set -euo pipefail

REGION="us-east-1"

# pg_dump REFUSES a server newer than itself, and the failure lands at the schema
# step after everything before it has already succeeded. Homebrew does not link a
# versioned formula onto PATH, so the client is called by absolute path.
PSQL="/opt/homebrew/opt/postgresql@18/bin/psql"
PG_DUMP="/opt/homebrew/opt/postgresql@18/bin/pg_dump"

APPLICATION_DATABASE=""
SOURCE_IDENTIFIER=""
TARGET_IDENTIFIER=""
ENVIRONMENT=""

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

describe_instance() {
  aws rds describe-db-instances \
    --db-instance-identifier "$1" \
    --region "$REGION" \
    --query 'DBInstances[0].{Endpoint:Endpoint.Address,Master:MasterUsername,Secret:MasterUserSecret.SecretArn,Zone:AvailabilityZone,Status:DBInstanceStatus,Vpc:DBSubnetGroup.VpcId,SecurityGroups:VpcSecurityGroups[].VpcSecurityGroupId,Key:KmsKeyId}' \
    --output json 2>/dev/null || die "No RDS instance named '$1' in ${REGION}."
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

# The console credentials arrive through the environment because the module
# generates them and publishes only half: the user name is a Terraform output,
# and the password exists nowhere but the state — `terraform state show` redacts
# it, so it comes from the state's JSON form. Neither belongs on a command line,
# and the script has no business knowing a stack's directory.
require_pooler_console() {
  [[ -n "${POOLER_ADMIN_USER:-}" ]] || die "POOLER_ADMIN_USER is not set. It is the connection_pooler module's admin_user output."
  [[ -n "${POOLER_ADMIN_PASSWORD:-}" ]] || die "POOLER_ADMIN_PASSWORD is not set. It lives only in Terraform state — read it from 'terraform show -json' rather than 'state show', which redacts sensitive values."
  [[ -n "${POOLER_DATABASE:-}" ]] || die "POOLER_DATABASE is not set. It is the logical name the pooler exposes, which differs from the real database name."
}

pooler_console() {
  local address="$1" statement="$2"

  PGPASSWORD="$POOLER_ADMIN_PASSWORD" "$PSQL" --host "$address" --port 6432 \
    --username "$POOLER_ADMIN_USER" --dbname pgbouncer --no-password --command "$statement"
}

# --- commands --------------------------------------------------------------

command_preflight() {
  require_source
  require_target
  require_environment

  local source_json target_json

  source_json=$(describe_instance "$SOURCE_IDENTIFIER")
  target_json=$(describe_instance "$TARGET_IDENTIFIER")

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

command_status() {
  require_source
  require_target

  local source_json target_json source_endpoint target_endpoint source_master target_master source_password target_password

  source_json=$(describe_instance "$SOURCE_IDENTIFIER")
  target_json=$(describe_instance "$TARGET_IDENTIFIER")
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

  echo "Error counters on the target"
  PGPASSWORD="$target_password" "$PSQL" --host "$target_endpoint" --username "$target_master" --dbname "$APPLICATION_DATABASE" --no-password \
    --command "SELECT subname, apply_error_count, sync_error_count, confl_insert_exists, confl_update_origin_differs, confl_delete_missing FROM pg_stat_subscription_stats;"
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

  source_json=$(describe_instance "$SOURCE_IDENTIFIER")
  target_json=$(describe_instance "$TARGET_IDENTIFIER")
  source_endpoint=$(instance_field "$source_json" Endpoint)
  target_endpoint=$(instance_field "$target_json" Endpoint)
  source_master=$(instance_field "$source_json" Master)
  target_master=$(instance_field "$target_json" Master)
  source_password=$(master_password "$(instance_field "$source_json" Secret)")
  target_password=$(master_password "$(instance_field "$target_json" Secret)")

  resolve_application_database "$source_endpoint" "$source_master" "$source_password"

  local structure_query bounds_query
  structure_query="SELECT 'tables', count(*) FROM pg_tables WHERE schemaname='public' UNION ALL SELECT 'sequences', count(*) FROM pg_sequences WHERE schemaname='public' UNION ALL SELECT 'indexes', count(*) FROM pg_indexes WHERE schemaname='public' UNION ALL SELECT 'constraints', count(*) FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace WHERE n.nspname='public' UNION ALL SELECT 'columns', count(*) FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r' AND a.attnum>0 AND NOT a.attisdropped;"
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

  source_json=$(describe_instance "$SOURCE_IDENTIFIER")
  target_json=$(describe_instance "$TARGET_IDENTIFIER")
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

  for address in $(pooler_task_addresses); do
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

  target_json=$(describe_instance "$TARGET_IDENTIFIER")
  target_endpoint=$(instance_field "$target_json" Endpoint)
  target_master=$(instance_field "$target_json" Master)
  target_password=$(master_password "$(instance_field "$target_json" Secret)")

  resolve_application_database "$target_endpoint" "$target_master" "$target_password"

  require_pooler_console

  for address in $(pooler_task_addresses); do
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
  status)    command_status ;;
  verify)    command_verify ;;
  hold)      command_hold ;;
  release)   command_release ;;
  *)         die "Usage: rds-key-migration.sh {preflight|status|verify|hold|release} --source <identifier> --target <identifier> --environment <stack>" ;;
esac
