# PLAN — PgBouncer on ECS (per-stack connection pooler)

**Date:** 2026-06-29 (cutover executed 2026-06-30 UTC) · **Repos:** `terraform`, `pgbouncer`, `app`, `dot-claude` · **Source:** `SPIKE.md` (same folder)

## Objective

Replace the hand-managed EC2 PgBouncer pets (one Puma + one Sidekiq per productive stack) with a Terraform-managed **ECS Fargate pooler** that faithfully reproduces the real DB topology — a **writer/reader split** (two logical databases, two backend users, per-db pools). Apps repoint to the new pooler via their `DATABASE_URL` / `DATABASE_REPLICA_URL` SSM parameters. Scope: productive stacks only — **shared-001** (DONE), then **atento-001**.

> **Credential rotation was DECOUPLED from this migration** (see pivots). The cutover happens with the **current** credentials; scram conversion + username/password rotation is a **separate, later** effort.

## Status (2026-06-30 UTC)

- **shared-001 — MIGRATED, VALIDATED, and DECOMMISSIONED.** App fully on the ECS pooler; both pets terminated; pet SG deleted.
- **atento-001 — not started.**
- **Datadog monitoring on the ECS pooler — not started** (gap: no stats user on the new pooler).
- **Credential rotation — deferred** (separate effort; now also covers a leaked monitor password — see Incidents).

## Final architecture as built (shared-001)

**Decoupled client/backend identity, static userlist, md5 — cutover with current credentials.**

- **One ECS Fargate pooler per stack**, dedicated cluster `app-shared-001-pgbouncer`, tagged `Project=connection-pooler`, `Component=pgbouncer`. Consolidates the two pets (Puma + Sidekiq) into one service (2 tasks).
- **Two logical databases** (the app already speaks these names — it connected to the pet PgBouncers with the same names):
  | Logical DB | Backend endpoint | Backend user (`user=` pin) | `pool_size` | `min_pool_size` |
  |---|---|---|---|---|
  | `shared001_master` | cluster (writer) | `ezmrcJDJeJaPtVuP` | 100 | 10 |
  | `shared001_follower` | cluster-ro (reader) | `DiYtoADDmejVyXhg` | 45 | 5 |
  - Pool sizes are the **exact sum** of the two pets: master 100 = 30 (puma) + 70 (sidekiq); follower 45 = 30 + 15. `max_client_conn = 4000` = 2000 + 2000.
- **Auth = static userlist + `auth_type = md5`.** The pooler's `userlist.txt` (from Secrets Manager `app-shared-001-pgbouncer-userlist`, base64, populated out-of-band) carries 3 users with their md5 secrets: `ezmrcJDJeJaPtVuP` (writer), `DiYtoADDmejVyXhg` (reader), `gjmatrmg7x` (the pet stats/monitor user — see below). `auth_type=md5` accepts md5+scram; `user=` in `[databases]` pins the backend role so the client connects as one identity and the pooler maps to the backend role.
- **The app connects as `ezmrcJDJeJaPtVuP`** (writer) / the reader user via `DATABASE_REPLICA_URL` — **confirmed from the live `DATABASE_URL`** (`//ezmrcJDJeJaPtVuP:...@`). `gjmatrmg7x` is **NOT** in the app data path — it is only the pgbouncer stats/admin user the Datadog agent uses on the pets.
- **DNS:** CNAME `pgbouncer-shared-001.4shark.internal` → the Cloud Map record `pgbouncer.app-shared-001.internal` (Cloud Map auto-registers the tasks). The app connects to the CNAME. The app VPC (`vpc-080577b61da17d948`) had to be **associated with the `4shark.internal` zone** (`Z3PBW9DU61QULB`) for the CNAME to resolve — it was not (added via `aws_route53_zone_association`).
- **Image:** `405749097490.dkr.ecr.us-east-1.amazonaws.com/pgbouncer:4` — thin wrapper `FROM edoburu/pgbouncer@<digest>` + `configured-entrypoint.sh` (decodes `PGBOUNCER_INI_B64` env + `USERLIST_B64` secret into `/etc/pgbouncer/`, then `exec /entrypoint.sh "$@"`). **`:4` is the fixed image** — `:1`–`:3` never booted (CMD bug, see Incidents).
- **Config delivery:** Terraform renders the `.ini` → `base64encode` → `PGBOUNCER_INI_B64` (non-secret env); the userlist comes from Secrets Manager as `USERLIST_B64` (secret). The `.ini` has no passwords (they live in the userlist). The service uses `ignore_changes=[task_definition]` → image/config changes need a manual `update-service --force-new-deployment` (or pointing the service at the new revision).

## Key decisions & pivots (authoritative — supersede the original SPIKE)

1. **`auth_query` ABANDONED.** RDS Aurora forbids reading `pg_shadow`/`pg_authid` even for the master (`rds_superuser` is not a true superuser) → `permission denied for view pg_shadow`. The `pgbouncer` role/schema/function from the first attempt were dropped (DB clean). → **static userlist** (the pet model, now IaC).
2. **Rotation DEFERRED, cutover with CURRENT credentials.** Because only md5 hashes exist (plaintext unrecoverable), the cutover keeps the app connecting with its current credentials. The pooler's userlist carries the current md5 secrets; backend `user=` pinning maps to `ezmrc`/`DiYto`. No scram bridge, no rotation in this migration.
3. **DNS = CNAME in `4shark.internal`** (not the module's default Cloud Map namespace, not an NLB ~$20–30/mo). CNAME ~$0, keeps Cloud Map auto-registration. Required the VPC↔zone association fix.
4. **Image CMD fix** (Incidents) — restored the upstream `CMD` that an `ENTRYPOINT` override had zeroed.
5. **`/connection-poolers` skill** created (dot-claude) — mirrors `/authenticators`, discovers by `Project=connection-pooler`.
6. **ADR home = `app` repo** (`docs/adr/0002-writer-reader-database-user-separation.md`).

## What was built / merged

| Repo | Change | PR / artifact |
|---|---|---|
| `pgbouncer` | thin image (Dockerfile + `configured-entrypoint.sh`); **CMD fix** | merged (#4 = CMD fix); image `pgbouncer:4` in ECR |
| `terraform` | `modules/pgbouncer` (userlist/md5/`user=`/CNAME); `app-shared-001/pgbouncer.tf` (module call + userlist secret); **image bump `:3`→`:4`**; **VPC↔zone association** | #568, #569, #570 (image), #571 (zone assoc) — all merged & applied |
| `app` | ADR — writer/reader user separation (Heroku at-scale lineage) | #5188 (+ #5189 sanitize) merged |
| `dot-claude` | `/connection-poolers` skill (`Project=connection-pooler`) | #311 (+ #314 sanitize) merged |

All operational/credential/migration narrative was **scrubbed** from code comments + PR bodies (security remediation across all repos).

## Cutover — how it was done (shared-001, the reusable procedure)

The secrets `/shared-001/DATABASE_URL` and `/shared-001/DATABASE_REPLICA_URL` are **SSM Parameters** (SecureString), terraform-created with `value="PLACEHOLDER"` + `ignore_changes=[value]` → **values are out-of-band**. The cutover:

1. **Queue check** (productive env — ~5 min no-processing window during deploy). RDS load proxy: ~23–33 connections, off-peak → clear.
2. **SSM swap (leak-safe)** — for each of the two params: `get-parameter --with-decryption` to a local file, swap **only the host** (`@…/` → `@pgbouncer-shared-001.4shark.internal:6432/`) preserving user/password/dbname/sslmode, `put-parameter --value file://… --overwrite` (value never on the command line), delete the local file. Both went to Version 3.
3. **Deploy via GitHub Actions** — `gh workflow run deploy-shared-001.yaml -R 4shark/app --ref master`. The workflow inherits `secrets`/`valueFrom` verbatim (only swaps image+command), so new tasks fetch the updated SSM at start. Orchestrated: validate → Redis lock → Sidekiq TSTP quiet → migration → web CodeDeploy blue/green → Sidekiq rolling → traffic shift. **Run 28415454356 — all jobs success.**
4. **Validated** — pooler logs showed 41 client connections from app task IPs as `db=shared001_master user=ezmrcJDJeJaPtVuP`, zero auth/db errors. Pre-cutover the client→pooler path was tested end-to-end (both `DATABASE_URL` and `DATABASE_REPLICA_URL`, real app credentials read live from a running web container, only host swapped → `result=1`).

## Decommission — how it was done (shared-001)

The pets are **NOT terraform-managed** (the only `aws_instance` resources are MongoDB/windows/pritunl). So they are removed via `aws`, not terraform.

1. **Confirmed idle** — `ss` on each pet showed only 1 connection on `:6432`, a loopback (the local Datadog monitor); zero app connections.
2. **Stopped first** (reversible) via `~/.claude/scripts/stop-instance.sh --region us-east-1 --profile 4shark-mfa` → ~4.5 min observation window → pooler stayed healthy (14 client conns, no errors) → no hidden dependency.
3. **Terminated** `i-0dd0d5c92ec9daf66` (puma) + `i-09821249b0c9d18fb` (sidekiq).
4. **Deleted SG** `sg-02c09ac26801f8eee` (orphaned — no ENIs, no ingress/egress references).

## Remaining work

1. **Datadog monitoring on the ECS pooler.** The pets ran the **official Datadog Agent `pgbouncer` integration** (`/etc/datadog-agent/conf.d/pgbouncer.d/conf.yaml`): connects to the admin DB (`dbname: pgbouncer`) as `gjmatrmg7x` (the stats user), `collect_database_metrics: true`, tags `service:puma|sidekiq` + `env:shared001`, emits `pgbouncer.*`. No custom checks (`checks.d/` empty). **Gap:** the ECS pooler `.ini` has **no `admin_users`/`stats_users`** (removed during sanitization). To replicate: add a stats user to the `.ini` + userlist, run the **DD Agent as a sidecar** in the pooler task (Fargate awsvpc → reach pgbouncer at `localhost:6432`), DD API key as a secret.
2. **Replicate on `atento-001`** — same end-to-end flow. Detailed runbook in `TASKS.md` (same folder). Productive — queue check + off-peak. Its pets are the rollback fallback until validated. **Atento-only twist (decided):** the sa-east-1 outbound worker (`app-outbound-atento-br`, on-demand) shares `/atento-001/DATABASE_URL` and already crosses to the us-east-1 atento pooler cross-region. **No BR pooler cluster** — the outbound reaches the us-east-1 pooler via cross-region connectivity (mechanism TBD: PrivateLink vs peering+SG+PHZ). Network spike: `~/.claude/plans/active/spike/br-pooler-network-topology/SPIKE.md`.
3. **Credential rotation (`gjmatrmg7x` stats user)** — separate effort. Now **urgent for `gjmatrmg7x`** because its password leaked (Incidents). Monitoring-scope only (not the app data path). Coordinated across: pet/pooler userlists + the DD agent configs (and any other stack that reuses it).
4. **`atento-001` Datadog** — same sidecar pattern once #1 is designed.

## Incidents

- **Image never booted (`:1`–`:3`).** Our Dockerfile set `ENTRYPOINT` but not `CMD`; per Docker semantics, overriding `ENTRYPOINT` zeroes the inherited base `CMD`. So `configured-entrypoint.sh`'s `exec /entrypoint.sh "$@"` ran with empty `$@`, the edoburu entrypoint's `exec "$@"` ran nothing, container exited 0 — "Starting ..." then dead. **Fix:** restore `CMD ["/usr/bin/pgbouncer", "/etc/pgbouncer/pgbouncer.ini"]` (pgbouncer repo #4) → image `:4`. The deployment circuit breaker had been rolling back to `:1` (the only ever-stable revision).
- **CNAME unresolvable.** The app VPC was not associated with `4shark.internal`. Fix = `aws_route53_zone_association` (terraform #571). The Cloud Map target resolved; only the convention CNAME name was missing the zone association.
- **Credential leak (monitor password).** While inspecting the pet Datadog config, a `grep -v` filter using `\s` (unsupported in macOS grep) failed and the **`gjmatrmg7x` pgbouncer monitor password printed to chat**. Local copies purged; the value remains in the session transcript. It is a **monitoring-scope** credential (pgbouncer admin stats), **not** the app DB password (the app uses `ezmrc`/`DiYto`). → rotate `gjmatrmg7x` (Remaining #3). Lesson: redact secrets **at the source** with POSIX classes (`[[:space:]]`), never `\s` on macOS; prefer capturing to a local file and reporting only masked structure.

## Rollback (now mostly historical for shared-001)

The pets were the fallback; they are **gone**. shared-001 rollback would now mean reverting the two SSM params to a pgbouncer that no longer exists — so shared-001 is committed. For **atento-001**, keep the pets until validated: rollback = revert the `DATABASE_URL`/`DATABASE_REPLICA_URL` SSM params to the pet host + redeploy (one change).

## Validation criteria (per stack)

- App tasks healthy on **both** writer and reader paths; no connection/auth errors (verified via pooler client-connection logs + a real-credential `SELECT 1` through the pooler).
- Pool sizes = the sum of the two pets per logical DB; `max_client_conn` = sum.
- Pets confirmed idle (`ss` on `:6432` = only the local monitor) before stop; pooler healthy through a stop-observe window before terminate.
