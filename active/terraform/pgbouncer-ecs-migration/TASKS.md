# TASKS — PgBouncer→ECS migration for **atento-001**

**Date:** 2026-06-30 · **Derived from:** `PLAN.md` (same folder; read it for the architecture + the shared-001 record) · **Repos:** `terraform`, `pgbouncer`, `app`, `dot-claude`

Second (and last) productive stack. Mirrors the **validated** shared-001 flow, with two atento-only differences and the Datadog work folded into the build.

## Settled decisions (baked in)

- **Reuse image `pgbouncer:4`** — it already has the CMD fix. **Do NOT rebuild** unless the image itself changes. (`:1`–`:3` never booted — the CMD-zeroing bug; see PLAN Incidents.)
- **Same model as shared-001** — static userlist + `auth_type=md5` + backend `user=` pinning (decoupled), cutover with **current** credentials, rotation deferred. Two logical DBs `atento001_master` (writer) / `atento001_follower` (reader). Pool sizes = the **sum** of the two atento pets per logical DB.
- **DNS** = CNAME `pgbouncer-atento-001.4shark.internal` → the Cloud Map record, in zone `4shark.internal` (`Z3PBW9DU61QULB`). **The atento app VPC must be associated with that zone** (`aws_route53_zone_association`) — it bit us on shared (NXDOMAIN). Verify + add.
- **Datadog from the start** (engineer decision) — the atento pooler ships **with** monitoring: a `stats_users` (or `admin_users`) entry in the `.ini` + that user in the userlist, a **DD Agent sidecar** in the pooler task, DD API key as a secret. This is a **`modules/pgbouncer` enhancement** (shared didn't have it). Retrofit shared-001 with the same pattern afterward.
- **SSM params** `/atento-001/DATABASE_URL` + `/atento-001/DATABASE_REPLICA_URL` (SecureString, terraform `PLACEHOLDER` + `ignore_changes=[value]`, populated out-of-band) — cutover swaps **only the host**, leak-safe.
- **Deploy** = `gh workflow run deploy-atento-001.yaml -R 4shark/app --ref master` (cluster `app-atento-001-cluster`). Productive → **queue check first**.
- **NO second/BR pooler cluster** (engineer decision) — the sa-east-1 outbound (`app-outbound-atento-br` payroll + runner, on-demand `desired=0`) does NOT get its own pooler. It reaches the **us-east-1 atento pooler** (the one we're building) via **cross-region network connectivity**. Confirmed this session: the outbound already crosses to the us-east-1 atento **pet** successfully today (last run ~May 2026, 541 log events, **zero DB connection errors**) via a **direct cross-region VPC peering** `pcx-08d27a042910be4f1` (live route, under terraform `ignore_changes`). The work is to make it reach the **new** pooler the same way — the peering already reaches the pooler's VPC; only the pooler SG + DNS need replicating (see Open items #1). Not a BR pooler. Consequence: the SSM swap is **intended for both** consumers, **no SSM split**.
- **Confirmed atento topology** (Phase 0, this session): backend writer `seVEbZU7UkcwjcuJM4MH` → cluster (writer), reader `qwwoymczHrJJGG2smfR3` → cluster-ro; dbname `app_atento_001`; stats user `gjmatrmg7x` (same as shared). **Consolidated pools = master 100 (30+70) / follower 45 (30+15) / `max_client_conn` 4000** — identical to shared. atento pet tuning is looser (`server_lifetime 1800`, `server_idle 120`, `reserve_pool_size 20`) — decide at build: reproduce vs standardize on the module values.

## Open items — status

1. **sa-east-1 outbound DB path — RESOLVED, mechanism CONFIRMED.** No BR pooler. **The network already exists:** a direct cross-region VPC peering `pcx-08d27a042910be4f1` connects the outbound VPC (`vpc-0985020bde92bca75`, `10.12.0.0/26`, sa-east-1) ↔ the atento app VPC (`10.100.12.0/22`, us-east-1) — live route `10.100.12.0/22 → pcx-08d27a042910be4f1` in the outbound private RT `rtb-08836ef35bb6b1f8c` (under terraform `ignore_changes`, so invisible in code — the SPIKE missed it; the live route table is authoritative). The atento **pet SG `sg-0d6794f2e53e0265b` already allows `10.12.0.0/26` on 6432** (CIDR-based, since SG refs can't cross regions). The worker reaches the pet via peering today; the **same peering already reaches the new pooler** (same VPC/CIDR). Peering is the recommended + cheap pattern (no hourly cost) → **replicate, don't re-architect.** PrivateLink (spike) is unnecessary. **Replication deltas only:** (a) pooler SG allows `10.12.0.0/26` on 6432 (mirror the pet SG); (b) the outbound VPC resolves the pooler name — confirm how it resolves the pet today and replicate (likely a cross-region `4shark.internal` PHZ association for the outbound VPC). Outbound is `desired=0` now → no live breakage, but both deltas must be in place + validated before its next on-demand run (and before the SSM swap).
2. **atento client DB user — partially confirmed.** The pet `.ini` gives the **backend** users (writer `seVEbZU…`, reader `qwwoymcz…`). The literal **client** user in `/atento-001/DATABASE_URL` is **pending** — the read was blocked (1Password CLI session expired; MFA elevation needs re-auth). On shared the client user equalled the writer backend user (decoupled model). Confirm the atento client user (username only) once MFA is restored.

## Lessons baked in as guardrails (apply at every step)

- **PR open BEFORE any `terraform apply`.** Apply-before-merge ≠ apply-before-PR. (Corrected twice on shared.) Worktree → commit → push → `gh pr create` → then apply from the branch.
- **Never leak a secret.** SSM/userlist values via `--value file://…` / files, never on the command line or chat. To inspect a config with secrets, **redact at the source** with POSIX classes (`sed -E 's/password[[:space:]]*=[[:space:]]*[^[:space:]]*/password = REDACTED/Ig'`) — **never `\s`** (unsupported in macOS grep/sed; that is exactly how the monitor password leaked). Prefer: capture raw to a local file, report only masked structure, delete the file.
- **Validate with REAL app credentials before cutover** — exec into a live atento app task, read `DATABASE_URL`/`DATABASE_REPLICA_URL` from its env, swap **only the host** to the pooler CNAME, `SELECT 1`. Both writer and reader. The pooler client cluster is CPU-packed for `run-task` → use **ECS Exec** (it is enabled on the app tasks). Quote-safe exec: base64 the ruby + `ruby -e 'eval(%(<b64>).unpack1(%(m0)))'`.
- **Update SSM BEFORE triggering the deploy** — the deploy inherits `secrets`/`valueFrom` verbatim; new tasks fetch the current SSM value at start. SSM-first, then deploy.
- **Decommission = stop → observe → terminate.** Confirm pets idle (`ss -tnH state established sport = :6432` → only the loopback DD monitor), `stop-instance.sh` first, observe ~5 min (pooler stays healthy), then `terminate-instances`, then delete the pet SG (check no ENI / no ingress+egress SG references first), then **check for orphaned EBS volumes** (`describe-volumes --filters status=available`) and any snapshots.
- **Reuse the wrappers** — `~/.claude/scripts/stop-instance.sh --region us-east-1 --profile 4shark-mfa` (raw `stop-instances` is blocked). Atomic infra commands only (no `&&`/`|`/`;` chaining with aws; single `2>` redirect).

## Phase 0 — Discovery (read-only)

- [x] Open item #1 (sa-east-1 outbound DB path) — resolved; #2 (client user) — partial. See Open items — status.
- [x] Read both atento pets' `pgbouncer.ini` — done. Topology + sizing captured (see Settled decisions: writer `seVEbZU…`, reader `qwwoymcz…`, dbname `app_atento_001`, pools 100/45, `max_client_conn` 4000, stats user `gjmatrmg7x`, `pool_mode=transaction`).
- [x] atento RDS writer/reader endpoints — `app-atento-001-cluster.cluster-…` (writer) / `.cluster-ro-…` (reader). **Still TODO:** confirm `max_connections` headroom for the summed pools.
- [ ] atento app VPC id + whether it is already associated with `4shark.internal` (`describe-hosted-zone` VPCs vs the app VPC).
- [ ] Confirm the call site shape — atento uses an `atento_001_task_config` module; check how secrets/compute are wired vs shared's flat stack, so the `pgbouncer.tf` + SSM read fit.
- [ ] **Decide the cross-region connectivity mechanism** for the outbound (PrivateLink vs peering+SG+PHZ — see Open items #1) — needed for Phase 1.

## Phase 1 — Build (terraform)

### Core pooler — DONE (PR #573, plan clean: 15 add / 0 change / 0 destroy; apply pending MFA)

- [x] **Call site** `app-atento-001/pgbouncer.tf` — mirror of shared: userlist secret (`atento-001-pgbouncer-userlist`, KMS `mrk-fa0cda…`), module call (writer `seVEbZU…`/reader `qwwoymcz…`, db `app_atento_001`, pools 100/45, `auth_type=md5`, image `pgbouncer:4`, CNAME `pgbouncer-atento-001.4shark.internal`), `aws_route53_zone_association` for the atento app VPC (`vpc-030497c296befc066`, was NOT associated).
- [x] **Module** `extra_ingress_cidrs` input + dynamic SG ingress; call site passes `["10.12.0.0/26"]` (the outbound CIDR — mirrors the pet SG). SG rule confirmed in the plan.
- [ ] **Apply** PR #573 from the branch (needs MFA — 1Password re-auth).

### Remaining in Phase 1

- [ ] **Datadog Agent sidecar** (the DD-from-start piece — greenfield, no 4Shark ECS-sidecar sibling) → `modules/pgbouncer`: a `datadog/agent` sidecar container; DD API key secret (reuse the `DD_API_KEY` SSM pattern); pgbouncer integration via autodiscovery labels reaching `localhost:6432`; a `stats_users`/`admin_users` knob in the `.ini` + the stats user's **plaintext password** as a secret for the agent; decide **new stats user vs reuse `gjmatrmg7x`** (leaked, pending rotation). Untestable until MFA. Own design pass + PR. Retrofit shared with the same module capability after.
- [ ] **Outbound DNS (delta b)** — the outbound VPC `vpc-0985020bde92bca75` already resolves `4shark.internal` (CNAME ✓) but NOT the Cloud Map zone `atento-001.internal` (the CNAME target). Add a cross-region `aws_route53_zone_association` of the outbound VPC to the pooler's Cloud Map zone (needs a module output for its `hosted_zone` id). Validate it resolves. Worker-specific (`desired=0`) → before the next outbound run / the Phase 4 swap. Deferred (validate with MFA).

## Phase 2 — Populate userlist + boot

- [ ] Populate `atento-001-pgbouncer-userlist` (leak-safe) with the atento users + the **stats user** (md5). `put-secret-value --secret-string file://…`, delete the local file.
- [ ] `update-service --force-new-deployment` → confirm the pooler **boots** (`LOG listening on …:6432`, backend SSL established to writer+reader) and the **DD sidecar** reports `pgbouncer.*` metrics.

## Phase 3 — Pre-cutover validation (real credentials)

- [ ] ECS Exec into a live atento web task → real-credential `SELECT 1` through `pgbouncer-atento-001.4shark.internal:6432` for **both** `DATABASE_URL` (writer) and `DATABASE_REPLICA_URL` (reader). Expect `OK result=1`. Leak-safe (only `OK`/`FAIL` printed).

## Phase 4 — Cutover

- [ ] **Queue check** (productive — ~5 min no-processing window). Hold if heavy work is running.
- [ ] **SSM swap (leak-safe)** — `/atento-001/DATABASE_URL` + `/atento-001/DATABASE_REPLICA_URL`: host → pooler CNAME, preserve user/password/dbname/sslmode, `put-parameter --value file://… --overwrite`, delete files. Serves **both** the us-east-1 app and the sa-east-1 outbound (intended — both use the pooler; no split). **Pre-req:** the cross-region connectivity (Phase 1) is in place + validated, so the outbound's next on-demand run reaches the pooler.
- [ ] **Deploy** `gh workflow run deploy-atento-001.yaml -R 4shark/app --ref master` → all jobs green.
- [ ] **Validate** — pooler logs show app client connections (`C-…` from app task IPs), zero auth/db errors.

## Phase 5 — Decommission

- [ ] Pets idle (`ss` on `:6432` = only the loopback DD monitor).
- [ ] `stop-instance.sh` both atento pets → observe ~5 min (pooler healthy) → `terminate-instances`.
- [ ] Delete the pet SG (after confirming no ENI + no ingress/egress SG references).
- [ ] **Check orphaned EBS** (`describe-volumes status=available`) + snapshots → none expected (root `DeleteOnTermination=true`), but verify.

## Post-atento

- [ ] **Retrofit shared-001 with the Datadog sidecar + stats user** (the same module capability built in Phase 1).
- [ ] **Rotate `gjmatrmg7x`** (stats user, includes the leaked value) — monitoring scope, coordinated across both stacks' userlists + DD configs.
- [ ] Move this feature folder `active/` → `completed/` once both stacks are done.

## Completion criteria (atento-001)

- App (us-east-1 services) healthy on **both** writer and reader paths via the pooler; no connection/auth errors (pooler client-connection logs + real-credential `SELECT 1`).
- The **DD sidecar emits `pgbouncer.*`** for atento (pools/stats), tagged `service`/`env`.
- The sa-east-1 outbound (payroll + runner) reaches the us-east-1 pooler via the cross-region connectivity — validated, no SSM split, no BR pooler — confirmed before it next runs on-demand.
- Pets terminated, SG deleted, no orphaned EBS/snapshots.
