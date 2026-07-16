# PLAN — Connection Pooler on ECS (per-stack PgBouncer)

**Date:** 2026-06-29 (shared-001 cutover 2026-06-30 UTC) · **Closed:** 2026-07-15 · **Repos:** `terraform`, `pgbouncer`, `app`, `dot-claude` · **Source:** `SPIKE.md` (same folder)

## Objective

Replace the hand-managed EC2 PgBouncer pets (one Puma + one Sidekiq per productive stack) with a Terraform-managed **ECS Fargate connection pooler** that faithfully reproduces the real DB topology — a **writer/reader split** (two logical databases, two backend users, per-db pools). Apps repoint to the new pooler via their `DATABASE_URL` / `DATABASE_REPLICA_URL` SSM parameters.

> **Credential rotation was DECOUPLED from this migration** (see pivots). The cutover happened with the **current** credentials; scram conversion + username/password rotation is a **separate, later** effort.

## Status (2026-07-15 UTC) — COMPLETE

Verified against live AWS on 2026-07-15:

- **All four stacks migrated** — `beta-001`, `demo-001`, `atento-001`, `shared-001`. Each runs one pooler service at **2/2 tasks, ACTIVE**.
- **All pets decommissioned** — zero PgBouncer EC2 instances remain in any region.
- **Datadog monitoring live on all four** — every pooler task runs the `datadog-agent` sidecar alongside `connection-pooler`, with a `stats_users` entry in the `.ini` and the agent's pgbouncer check wired via autodiscovery labels.
- **The pooler is a mandatory piece of the `app` module** — an app stack can no longer be stood up without one.
- **Scope grew beyond the original plan.** This document was written for productive stacks only (shared-001 then atento-001); the work went on to cover the two non-productive stacks and to make the pooler structural in the module.

## Final architecture as built (all four stacks)

**Decoupled client/backend identity, static userlist, md5 — cutover with current credentials.**

- **One ECS Fargate pooler per stack** — cluster `<stack>-connection-pooler`, service `<stack>-connection-pooler`, tagged `Project=connection-pooler`, `Component=pgbouncer`. Consolidates the two pets (Puma + Sidekiq) into one service (2 tasks).
- **Two containers per task** — `connection-pooler` (PgBouncer) + `datadog-agent` (the monitoring sidecar).
- **Two logical databases** per stack (the app already speaks these names — it connected to the pet PgBouncers with the same names): a `<stack>_master` on the cluster writer and a `<stack>_follower` on the cluster reader, each with a `user=` backend pin and its own pool sizes. For shared-001 the pool sizes are the **exact sum** of the two pets it replaced.
- **Auth = static userlist + `auth_type = md5`.** The userlist comes from Secrets Manager (`<stack>-connection-pooler-userlist`, base64, populated out-of-band) and carries the writer, the reader, and the stats user. `auth_type=md5` accepts md5+scram; `user=` in `[databases]` pins the backend role so the client connects as one identity and the pooler maps to the backend role.
- **DNS:** CNAME `connection-pooler-<stack>.4shark.internal` → the Cloud Map record (Cloud Map auto-registers the tasks). The app connects to the CNAME. Each app VPC is associated with the `4shark.internal` zone via `aws_route53_zone_association`.
- **Image:** a thin wrapper `FROM edoburu/pgbouncer@<digest>` + `configured-entrypoint.sh` (decodes `PGBOUNCER_INI_B64` env + `USERLIST_B64` secret into `/etc/pgbouncer/`, then `exec /entrypoint.sh "$@"`).
- **Config delivery:** Terraform renders the `.ini` → `base64encode` → `PGBOUNCER_INI_B64` (non-secret env); the userlist comes from Secrets Manager as `USERLIST_B64` (secret). The `.ini` has no passwords (they live in the userlist). The service uses `ignore_changes=[task_definition]` → image/config changes need a manual `update-service --force-new-deployment`.
- **Rolling deploy is zero-downtime by configuration** — `minimumHealthyPercent=100`, `maximumPercent=200`, deployment circuit breaker enabled: a new task is healthy before an old one is drained, and a bad revision rolls itself back.

### Datadog monitoring (as built)

The pets ran the official Datadog Agent `pgbouncer` integration; the ECS pooler reproduces it as a **sidecar**:

- `stats_users` in the rendered `.ini` (`modules/connection_pooler/main.tf:46`) + the stats user in the userlist — this closed the original gap.
- The `datadog-agent` container (`main.tf:74-96`) reaches PgBouncer at `localhost:6432` (Fargate `awsvpc`).
- The check is wired by **autodiscovery docker labels** (`main.tf:60-72`) rather than a mounted `conf.yaml` — `com.datadoghq.ad.check_names=["pgbouncer"]` plus the instance config carrying the stats username.
- Two secrets per stack: `DD_API_KEY` ← `<stack>-connection-pooler-datadog-api-key`, `PGBOUNCER_STATS_PASSWORD` ← `<stack>-connection-pooler-stats-password`.

## Key decisions & pivots (authoritative — supersede the original SPIKE)

1. **`auth_query` ABANDONED.** RDS Aurora forbids reading `pg_shadow`/`pg_authid` even for the master (`rds_superuser` is not a true superuser) → `permission denied for view pg_shadow`. → **static userlist** (the pet model, now IaC).
2. **Rotation DEFERRED, cutover with CURRENT credentials.** Because only md5 hashes exist (plaintext unrecoverable), the cutover kept the app connecting with its current credentials. No scram bridge, no rotation in this migration.
3. **DNS = CNAME in `4shark.internal`** (not the module's default Cloud Map namespace, not an NLB ~$20–30/mo). CNAME ~$0, keeps Cloud Map auto-registration. Required the VPC↔zone association fix.
4. **Image CMD fix** (Incidents) — restored the upstream `CMD` that an `ENTRYPOINT` override had zeroed.
5. **`/connection-poolers` skill** created (dot-claude) — mirrors `/authenticators`, discovers by `Project=connection-pooler`.
6. **ADR home = `app` repo** (`docs/adr/0002-writer-reader-database-user-separation.md`).
7. **Renamed `pgbouncer` → `connection_pooler` throughout** — module, per-stack file, cluster, service, secrets. PgBouncer is the implementation; connection pooler is the role. Tracked in `completed/terraform/pgbouncer-connection-pooler-rename/`.
8. **The pooler became a mandatory child of the `app` module** — bundled so an app can never be stood up without one, because the burst/scale access pattern requires it. Tracked in `completed/terraform/app-module-mandatory-pooler/`.
9. **Datadog check wired by autodiscovery labels, not a config file** — the ECS-native equivalent of the pets' `conf.d/pgbouncer.d/conf.yaml`.
10. **BR outbound reaches the pooler over the existing VPC peering, by CIDR** — the "PrivateLink vs peering" question is settled in favour of peering + a cross-region Cloud Map zone association (`app-atento-001/connection_pooler.tf:61-66`). No BR pooler cluster.

## Cutover — the reusable procedure

The `DATABASE_URL` / `DATABASE_REPLICA_URL` SSM Parameters (SecureString) are terraform-created with `value="PLACEHOLDER"` + `ignore_changes=[value]` → **values are out-of-band**. Per stack:

1. **Queue check** (productive env — ~5 min no-processing window during deploy). **The engineer checks the Sidekiq queue; the session does not.**
2. **SSM swap (leak-safe)** — for each param: `get-parameter --with-decryption` to a local file, swap **only the host** (`@…/` → `@connection-pooler-<stack>.4shark.internal:6432/`) preserving user/password/dbname/sslmode, `put-parameter --value file://… --overwrite` (value never on the command line), delete the local file.
3. **Deploy via GitHub Actions** — `gh workflow run deploy-<stack>.yaml -R 4shark/app --ref master`. The workflow inherits `secrets`/`valueFrom` verbatim (only swaps image+command), so new tasks fetch the updated SSM at start.
4. **Validate** — pooler logs show client connections from app task IPs on the expected `db=`/`user=`, zero auth/db errors.

## Decommission — the reusable procedure

The pets were **NOT terraform-managed**, so they were removed via `aws`, not terraform.

1. **Confirm idle** — `ss` on the pet shows only the loopback monitor connection on `:6432`; zero app connections.
2. **Stop first** (reversible) via `~/.claude/scripts/stop-instance.sh` → observation window → pooler stays healthy → no hidden dependency.
3. **Terminate**, then delete the orphaned SG.

## Incidents

- **Image never booted (`:1`–`:3`).** Our Dockerfile set `ENTRYPOINT` but not `CMD`; per Docker semantics, overriding `ENTRYPOINT` zeroes the inherited base `CMD`. So `configured-entrypoint.sh`'s `exec /entrypoint.sh "$@"` ran with empty `$@`, the edoburu entrypoint's `exec "$@"` ran nothing, container exited 0. **Fix:** restore `CMD ["/usr/bin/pgbouncer", "/etc/pgbouncer/pgbouncer.ini"]` (pgbouncer repo #4). The deployment circuit breaker had been rolling back to `:1` (the only ever-stable revision).
- **CNAME unresolvable.** The app VPC was not associated with `4shark.internal`. Fix = `aws_route53_zone_association` (terraform #571).
- **Credential leak (monitor password).** While inspecting the pet Datadog config, a `grep -v` filter using `\s` (unsupported in macOS grep) failed and the pgbouncer monitor password printed to chat. Local copies purged; the value remains in the session transcript. It is a **monitoring-scope** credential, **not** the app DB password. Handled by the engineer outside this plan. Lesson: redact secrets **at the source** with POSIX classes (`[[:space:]]`), never `\s` on macOS; prefer capturing to a local file and reporting only masked structure.

## Rollback

Historical. The pets are gone in every stack — rollback would mean reverting the SSM params to a pooler that no longer exists. All four stacks are committed to the ECS pooler.

## Validation criteria (met on all four stacks)

- App tasks healthy on **both** writer and reader paths; no connection/auth errors (verified via pooler client-connection logs + a real-credential `SELECT 1` through the pooler).
- Pool sizes = the sum of the two pets per logical DB; `max_client_conn` = sum.
- Pets confirmed idle before stop; pooler healthy through a stop-observe window before terminate.
- `pgbouncer.*` metrics arriving in Datadog from the sidecar.

## Follow-ups (outside this plan)

1. **Credential rotation / scram conversion** — deliberately decoupled from this migration (pivot 2); still pending.
