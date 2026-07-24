# PLAN — Effort 2: re-key the auth-001 RDS onto the dedicated KMS key (alias/auth-001)

Part of `active/terraform/kms-key-per-environment/` (the auth surface). This is **Effort 2** — the actual RDS
re-key, unblocked now that Effort 1 (dedicated DB user) and #807 (KMS key policy) are done. Grounded by
`active/spike/auth-001-rds-key-migration/SPIKE.md`.

> **MECHANISM CHANGED 2026-07-23 — read the HANDOFF STATE section first.** This plan originally used a logical
> `pg_dump`/`pg_restore` freeze (Option A). After a failed freeze attempt and a fragile rehearsal, the engineer
> **decided to switch to the AWS-native snapshot / copy-with-re-key / restore mechanism**, accepting a longer
> (~15 min) but bulletproof downtime. The dump/restore scripts (`prestage.sh`, `freeze.sh`, `rehearse.sh`) in
> this folder are **SUPERSEDED** — do not run them. The new mechanism is in "Ordered cutover sequence" below.

---

## HANDOFF STATE — 2026-07-23 (written before auto-compaction; this is the pick-up point)

### What is DONE

- **Effort 1 (app off the master `postgres` onto dedicated least-privilege DB users) — COMPLETE and CUT OVER to
  production with ZERO downtime.** Keycloak prod authenticates as the dedicated role `EVKcRQtsJsyxzQDaNaphGu`
  (owns the 91 `public` tables in `keycloak`); staging authenticates as `iDdssfbZVDcejjYwjpkuhBuF` (owns
  `keycloak_staging`). `PUBLIC` CONNECT revoked, explicit CONNECT granted per database. Cutover was a rolling ECS
  deploy; Infinispan/JGroups preserved sessions (no logged-in user dropped). The dedicated-user secrets are
  populated and verified. **Effort 1 residual (Phase 3, still PENDING):** after a stabilization window,
  `REVOKE EVKcRQtsJsyxzQDaNaphGu FROM postgres` and `REVOKE iDdssfbZVDcejjYwjpkuhBuF FROM postgres` — tracked in
  `../auth-001-app-user-migration/PLAN.md`.
- **#807 (KMS key policy for `alias/auth-001`) — APPLIED + MERGED + cleaned up.** Added the
  `rds.sa-east-1.amazonaws.com` ViaService grant (alongside the existing `secretsmanager` one) and tightened the
  admin/crypto statements. So `alias/auth-001` (`key/5a64fa33`) already accepts RDS-side encryption — the key is
  ready to receive the re-keyed instance.
- **A CLI instance `auth-001-rekey` was created under the correct key `alias/auth-001`** during the (now
  abandoned) dump/restore path. It is **SUPERSEDED by the snapshot decision** → it should be **DELETED** as the
  first step after compaction (it holds no production data; it was only the dump/restore target).

### The ABORTED FREEZE incident (no data loss)

A first freeze attempt scaled production `auth-001` to `desired_count 0` and then handed the engineer a pile of
MANUAL SQL to run DURING the outage — wrong shape (a short window cannot contain manual copy-paste). The service
was scaled straight back to `2` on the ORIGINAL instance, which was never renamed and never written to, so
**production recovered with ZERO data loss** — only a short outage was spent. Production is currently UP
(`auth-001` running 2). Lesson carried into the new mechanism: the freeze must be ONE fully-automated,
rehearsed motion with no manual steps.

### The DECISION — AWS snapshot / copy-with-re-key / restore (engineer, 2026-07-23)

The engineer chose the AWS-native mechanism over logical dump/restore, accepting a longer downtime for
guaranteed correctness. Verbatim: *"Beleza, é um downtime de 15 minutos, mas é um downtime muito mais seguro e
garantido... A gente vai fazer o esquema de backup da própria AWS e de restauração da própria AWS. Ela garante
que isso funciona."*

Why it is bulletproof vs. dump/restore:

- **Block-level copy** — a snapshot restore reproduces the instance EXACTLY: all data, all cluster-global roles
  (`EVKcRQtsJsyxzQDaNaphGu`, `iDdssfbZVDcejjYwjpkuhBuF`) with their ownership and ACLs, the master password, and
  the instance config. **Zero manual SQL** — none of the role-recreation / ownership / ACL steps the dump/restore
  path needed, and none of the logical-dump version pitfalls (the `transaction_timeout` GUC error that PG17
  client-vs-PG15 server hit during the rehearsal).
- **Correct key by construction** — `copy-db-snapshot --kms-key-id alias/auth-001` re-encrypts the snapshot under
  the target key; the instance restored from that copy inherits `alias/auth-001`. The KMS key of an instance is
  immutable (SPIKE Finding 1), so re-keying is always "new instance under the target key" — the snapshot copy is
  the AWS-blessed way to change the key of the data.
- **Correct name by construction** — restore straight into the identifier `auth-001` (after freeing it by renaming
  the old instance), so the canonical name and endpoint are right the first time.

**The cost the engineer accepted:** ~15 min of downtime (dominated by the restore, plus snapshot + copy time),
because snapshot → copy → restore run serially inside the freeze. Safety over window length.

### CUTOVER DONE — 2026-07-23

The freeze ran and the re-key is mechanically complete. `auth-001` is restored under the correct key
`key/5a64fa33` (alias/auth-001), Multi-AZ, on the canonical endpoint `auth-001.c8jdkpg7fpd1.sa-east-1.rds`
(unchanged → no task-def change was needed). Keycloak is back at `desiredCount 2` / `runningCount 2` and the ECS
service reached `services-stable` (proves the tasks connected to the restored DB and booted). The old instance
was renamed `auth-001-old` (wrong key `6f7b8e40`) and is RETAINED as the rollback anchor. `auth-001-rekey` was
deleted before the freeze.

**Downtime note (lesson):** the snapshot was taken AFTER the freeze started, so the snapshot-creation time was
spent down. The lower-downtime shape is a LIVE baseline snapshot first, then a fast incremental snapshot inside
the freeze (the restore itself is the unavoidable floor either way). Recorded for the next re-key.

### What is NEXT

- **Login validated** (2026-07-23) — the engineer logged into the Keycloak admin console on the restored
  instance. Full end-to-end proof (data + roles + app connection).
- **Terraform state reconciled + applied** (2026-07-23) — `state rm` of the old instance + `import` of the
  restored one into `module.this.aws_db_instance.auth001`; `rds.tf` `kms_key_id → key/5a64fa33`; `terraform
  apply` of the saved plan (`0 add, 1 change, 0 destroy` — re-enabled `deletion_protection` + `copy_tags_to_snapshot`
  that the restore had defaulted off); a re-plan then confirmed **No changes**. PR **[#811]** is OPEN on
  `4shark/terraform`, awaiting the engineer's merge (agent does not merge).

Remaining (burn-in / cleanup — nothing time-critical):

1. **Engineer merges PR #811.**
2. Cleanup checklist below, after an agreed burn-in: Phase 3 REVOKE on the restored instance; delete
   `auth-001-old` and the two snapshots (`auth-001-prerekey-20260723`, `auth-001-rekeyed-20260723`); remove local
   dump/script/`/tmp` artifacts (incl. the `/tmp` password file).

---

## The goal

Move the productive Keycloak RDS `auth-001` off the WRONG key (`alias/auth002` = `key/6f7b8e40`) onto its
dedicated key (`alias/auth-001` = `key/5a64fa33`), keeping the canonical `auth-001` identifier and endpoint.
The KMS re-key is the ONLY hard requirement of Effort 2. The originally-bundled extras (managed master password,
Performance Insights, Enhanced Monitoring) are now **optional follow-ups, not gating** — Effort 1 already made
the managed-master-password adoption moot (the app no longer authenticates as the master), and PI / Enhanced
Monitoring can be enabled on the restored instance at restore time or via a follow-up `modify` with no extra
downtime. Resolve whether to include them at execution; they do not block the re-key.

## Current instance (confirmed 2026-07-23, `describe-db-instances`)

- `auth-001`: PostgreSQL 15.17, db.t3.small, 20 GB gp3, Multi-AZ, sa-east-1, subnet group `auth-001`, SG
  `sg-02d86dfe41cef47cb`, master `postgres`, databases `keycloak` (+ `keycloak_staging`), backup 7 d / 02:00,
  param/option group `default.postgres15`.
- Encrypted under `key/6f7b8e40` (`alias/auth002`) — the wrong key; target `key/5a64fa33` (`alias/auth-001`).
- 20 GB allocated is the ceiling; the actual Keycloak dataset is small (~102 MB `keycloak` + ~15 MB
  `keycloak_staging` measured), so the snapshot + copy + restore is fast.
- Endpoint host hash `c8jdkpg7fpd1` is shared across this account's sa-east-1 instances, so a restored/renamed
  `auth-001` very likely reuses `auth-001.c8jdkpg7fpd1.sa-east-1.rds.amazonaws.com` (= current `KC_DB_URL`) →
  possibly NO task-def change needed. Confirm the restored endpoint before deciding.

## Discovery points — status

- **DP2 (KC_DB_USERNAME identity) — RESOLVED, and no longer a migration concern.** Keycloak authenticates as
  `EVKcRQtsJsyxzQDaNaphGu` (Effort 1). Under the SNAPSHOT mechanism this needs no special handling: the snapshot
  carries the role, its ownership of the 91 tables, and its password verbatim. (This was the hard part of
  dump/restore — the snapshot removes it entirely.)
- **DP3 (KMS key policy for RDS) — RESOLVED.** #807 added the `rds.sa-east-1` ViaService grant to
  `alias/auth-001`, so `copy-db-snapshot --kms-key-id alias/auth-001` and the restore both succeed. The rehearsal
  (below) is the live proof of this.
- **DP1 (DB size) — RESOLVED.** ~102 MB + ~15 MB; the freeze is short on data movement, dominated by AWS
  snapshot/copy/restore orchestration time, not bytes.
- **DP4 (Infinispan session clustering) — accepted.** The freeze scales Keycloak to 0, losing only the in-memory
  Infinispan cache; persisted offline sessions live in the DB and are carried by the snapshot, so they survive. A
  possible re-login for active users during the freeze is the same class of blip already accepted.
- **DP5 (table inventory) — RESOLVED for prod (91 `public` tables owned by `EVKcRQtsJsyxzQDaNaphGu`).** Under the
  snapshot mechanism this is a post-restore SANITY check, not a reconstruction step.

## The Terraform-state tension (unchanged by the mechanism switch)

`auth-001` is declared directly as `aws_db_instance.auth001` in `modules/auth/rds.tf` (not the shared
`modules/rds_instance`, so no `prevent_destroy`). A Terraform-driven KMS-key change forces a **replace**, which
destroys the data — out of the question. So the new instance is created **out of band** (here: by snapshot
restore) under the target key, and Terraform state is then reconciled to adopt it:

- **Approach (DECIDED): `state rm` old + `import` new into the SAME address `aws_db_instance.auth001`, no second
  rename.** After the restored instance holds the canonical `auth-001` identifier,
  `terraform state rm module.this.aws_db_instance.auth001` + `terraform import` the restored instance into
  `aws_db_instance.auth001`, then update `rds.tf` (`kms_key_id` → `alias/auth-001`, plus any of managed
  pw / PI / monitoring that were actually enabled) so a subsequent plan is clean (0 changes). The Terraform
  address stays stable.
- **This is a PR on `modules/auth/rds.tf` + the state operations, apply-before-merge, per the terraform rules.**
  The snapshot/copy/restore/rename are operational steps run alongside the PR, not Terraform.

## Rehearsal (ZERO downtime — do this BEFORE the freeze)

Prove the mechanism and time it against a live snapshot, with production fully UP:

1. `create-db-snapshot` of the live `auth-001` (non-blocking; a snapshot of a running Multi-AZ instance is fine).
2. `copy-db-snapshot --kms-key-id alias/auth-001` — this is the live proof that #807's key policy accepts the
   RDS re-encryption.
3. `restore-db-instance-from-db-snapshot` into a THROWAWAY identifier (e.g. `auth-001-rehearsal`), same subnet
   group + SG.
4. Verify: it reaches `available`; its `KmsKeyId` is `key/5a64fa33`; a connection as `EVKcRQtsJsyxzQDaNaphGu`
   sees the 91 `public` tables; a Keycloak-style login query works.
5. **Record the wall-clock of steps 1–3** — that is the real freeze estimate.
6. Delete the throwaway instance and the copied snapshot.

If the rehearsal is clean, the freeze is known-good and its duration is known.

## Ordered cutover sequence (the real freeze — snapshot mechanism)

Everything is AWS-native and automatable; no manual SQL anywhere.

1. **Freeze** — scale Keycloak ECS `auth-001` service to `desired_count 0`; wait for `runningCount 0`. Writes stop.
2. **Snapshot the old instance** — `create-db-snapshot` of `auth-001` (captures the final, post-freeze state).
3. **Re-key the snapshot** — `copy-db-snapshot --kms-key-id alias/auth-001` (re-encrypts under the target key).
4. **Free the name** — `modify-db-instance --new-db-instance-identifier auth-001-old --apply-immediately` on the
   old instance; wait until it settles (it is now off the canonical name and endpoint, but still holds every
   write up to the freeze → the rollback anchor).
5. **Restore under the canonical name + key** — `restore-db-instance-from-db-snapshot --db-instance-identifier
   auth-001` from the re-keyed copy, with subnet group `auth-001`, SG `sg-02d86dfe41cef47cb`, and (optionally)
   `--enable-performance-insights --performance-insights-kms-key-id alias/auth-001 --monitoring-interval 60
   --monitoring-role-arn <rds-monitoring-role>`. The restored instance inherits `alias/auth-001`.
6. **Verify** — wait `available`; confirm `KmsKeyId == key/5a64fa33`, the endpoint host, and (as
   `EVKcRQtsJsyxzQDaNaphGu`) the 91 `public` tables + `DATABASECHANGELOG`/`...LOCK`.
7. **Repoint + up** — if the restored endpoint host differs from the current `KC_DB_URL`, register a new ECS
   task-def revision with the new host; if it is unchanged (likely — shared hash), no task-def change. Scale
   Keycloak to `desired_count 2`. Wait `runningCount 2`.
8. **Verify a real login end-to-end** + a clean Liquibase boot. Freeze ends here.

Then, outside the freeze: reconcile Terraform state (the `state rm` + `import` above), burn-in, and after an
agreed window take a final snapshot of `auth-001-old` and delete it.

## Rollback

Until the burn-in window closes and `auth-001-old` is deleted, the OLD instance (renamed `auth-001-old`, still
under `alias/auth002`) exists and holds every write up to the freeze. If the restored instance misbehaves before
real production writes have landed: scale Keycloak to 0, rename `auth-001-old` back to `auth-001` (and drop the
restored one), register a task-def revision if the endpoint changed, scale to 2. Because no writes landed on the
restored instance in a same-window rollback, the old instance is still authoritative. After real production
writes have landed on the restored instance, rollback also means restoring those writes — so the burn-in window
is where "safe to delete `auth-001-old`" is declared, not before.

## Risks

| Risk | Mitigation |
|---|---|
| Freeze longer than the accepted ~15 min | Rehearse first (zero downtime) to get the real snapshot+copy+restore wall-clock; the dataset is tiny so orchestration time dominates, not bytes |
| `copy-db-snapshot --kms-key-id alias/auth-001` rejected by the key policy | Proven live in the rehearsal before the freeze; #807 already added the `rds.sa-east-1` ViaService grant |
| Restored endpoint host differs from `KC_DB_URL` | Verify the endpoint in the rehearsal AND at step 6; register a new task-def revision only if it changed (shared hash makes an unchanged host likely) |
| Terraform state surgery corrupts the address or double-manages the instance | `state rm` + `import` into the SAME address on a captured plan; verify a 0-change plan before merging (apply-before-merge) |
| Restore does not carry managed master password | Not a blocker — Effort 1 made the master-password path moot; adopt (or drop) managed pw / PI / monitoring as an optional follow-up modify, no extra downtime |
| Active sessions dropped by the scale-to-0 freeze | Accepted (DP4); persisted offline sessions survive in the DB and are carried by the snapshot |

## Cleanup checklist (run ONLY after the cutover is verified — engineer request 2026-07-23)

**Progress (2026-07-23):** items 2, 3, 4 DONE — the credential file `/tmp/auth001_new_master_password.txt`, the
obsolete scripts (`prestage.sh` / `freeze.sh` / `rehearse.sh`), and the session `/tmp` logs were removed; no CLI
dump files persisted (the script traps had cleaned their mktemp dirs). Item 6 (Terraform) DONE and merged
(#811). Item 1 (DB REVOKE) DONE — the engineer revoked both `postgres` memberships in psql on the restored
instance (2026-07-23). Item 5 DONE (2026-07-23) — the engineer authorized decommission: `deletion_protection`
disabled on `auth-001-old`, the instance deleted, and both snapshots (`auth-001-prerekey-20260723`,
`auth-001-rekeyed-20260723`) deleted. **Effort 2 is fully complete — nothing remains.**

1. **DB — drop the `postgres` rollback membership on the RESTORED instance (Effort 1 Phase 3).** During Effort 1
   `postgres` was made a member of each dedicated role as the rollback path; the snapshot carried those
   memberships forward, so they now exist on the NEW `auth-001` too and must be removed there. As the master on
   the restored `auth-001`: `REVOKE "EVKcRQtsJsyxzQDaNaphGu" FROM postgres;` and
   `REVOKE "iDdssfbZVDcejjYwjpkuhBuF" FROM postgres;` (quoted — the role names are case-preserving). Claude has
   no production DB access → the engineer runs this at a psql terminal. This is the same Phase 3 tracked in
   `../auth-001-app-user-migration/PLAN.md`, now anchored to the restored instance.
2. **Local dump files from the manual CLI path** — remove any `pg_dump` output directories/files produced during
   the abandoned logical-dump attempts (mktemp dirs, any dump under the plans folder).
3. **SH-script artifacts** — the outputs generated by `prestage.sh` / `rehearse.sh`, and the now-obsolete scripts
   themselves (`prestage.sh`, `freeze.sh`, `rehearse.sh`) — the mechanism changed to snapshots, so they are dead.
4. **Session `/tmp` artifacts** — `/tmp/freeze_*.log`, `/tmp/auth001_*`, and critically
   `/tmp/auth001_new_master_password.txt` (holds the master password of the now-deleted `auth-001-rekey`
   instance — purge it, it is a credential on disk).
5. **AWS, after the burn-in window** — delete the old instance `auth-001-old` (wrong key `6f7b8e40`); delete the
   two snapshots `auth-001-prerekey-20260723` (old key) and `auth-001-rekeyed-20260723` (the re-keyed copy) once
   the restored instance is proven.
6. **Terraform** — reconcile state (`state rm` old + `import` restored into `aws_db_instance.auth001`) and set
   `kms_key_id → alias/auth-001` in `modules/auth/rds.tf` to a 0-change plan, apply-before-merge.

## Superseded material (kept for context)

- **`prestage.sh`, `freeze.sh`, `rehearse.sh`** in this folder implement the ABANDONED logical `pg_dump`/
  `pg_restore` path (dedicated-user dump, `--no-owner` restore, serial RDS renames). They were the right shape
  for dump/restore but are moot under the snapshot mechanism — **do not run them.** `prestage.sh` did run once
  (printed `PRESTAGE OK`, creating roles/DBs/ACL on `auth-001-rekey`); `rehearse.sh` surfaced the benign
  `transaction_timeout` GUC error (PG17 client vs PG15 server) that reinforced abandoning logical dump/restore.
  Both are historical now.
- **`auth-001-rekey` instance** — the dump/restore target under `alias/auth-001`; superseded, to be deleted.
- The original dump/restore cutover sequence, its in-freeze parallel-rename decision, and the ~5-min downtime
  estimate are replaced by the snapshot sequence above; they remain in git/session history if needed.
