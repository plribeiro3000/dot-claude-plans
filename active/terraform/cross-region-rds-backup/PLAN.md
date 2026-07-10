# PLAN — Cross-Region RDS Backup (AWS Backup → us-west-2)

**Date:** 2026-06-29 · **Owner:** Paulo Ribeiro
**Reference research:** `~/.claude/plans/active/spike/rds-cross-region-backup/SPIKE.md` (approach, options, cost) + its community/destination-region section.
**Why this exists:** prerequisite for the BCP/DRP document (P6 in `legal-compliance-documents/ANALYSIS.md`). Today all RDS backups are co-located in their DB's region — a full-region outage destroys data + backups together. This closes that gap so the BCP can honestly claim regional DR.

## Objective

Add AWS Backup cross-region DR copies (destination **us-west-2**) for the 3 critical production databases, additively — no change to the RDS instances themselves. Closes the regional-outage exposure and underpins the annual DR-test commitment in the BCP.

## Locked decisions

| Decision | Choice | Source |
|---|---|---|
| Mechanism | AWS Backup (covers both RDS instances and Aurora clusters) | spike |
| First wave | `app-shared-001` (Aurora), `app-atento-001` (Aurora), `auth-001` (RDS instance) | spike |
| Destination region | **us-west-2** (max geographic separation; cost premium over us-east-2 ≈ $3–6/mo, trivial) | engineer 2026-06-29 |
| Local retention | 7 days | spike |
| DR-copy retention | 7 days | spike |
| Resource selection | tag-based (`Backup=cross-region-dr`) | spike |
| Failure monitoring | CloudWatch alarm on `NumberOfBackupJobsFailed` (required) | spike |
| `EnableContinuousBackup` (PITR via AWS Backup) | OFF initially — keep native RDS PITR independent | spike |
| Vault Lock (WORM) | OFF initially — revisit if compliance demands | spike |
| Validation sequence | **Direct to the 3 critical DBs** (engineer's call) — acceptable because the change is ADDITIVE (adds a backup plan; does not touch the RDS instances). `terraform plan` review is the safety gate | engineer 2026-06-29 |

## Real volumes (measured via CloudWatch `VolumeBytesUsed`, 2026-06-29)

| DB | Region | Type | Real volume | (spike estimate) |
|---|---|---|---|---|
| `app-shared-001-cluster` | us-east-1 | Aurora | **~339 GB** | ~300 GB |
| `app-atento-001-cluster` | us-east-1 | Aurora | **~34 GB** | ~300 GB (was 10× off) |
| `auth-001` | sa-east-1 | RDS instance | ~5 GB (not re-measured; small) | ~5 GB |

**Revised cost ≈ ~$45–55/month** (destination warm storage ~$0.095/GB-mo on 7-day incremental snapshots dominates; cross-region transfer is the minor component). Far below the spike's ~$110 estimate, because `atento` is ~34 GB, not ~300 GB. (Storage measured; transfer/churn estimated.)

## Proposed architecture

A new dedicated Terraform stack **`backup/`** with provider aliases for the three regions involved (`us-east-1`, `sa-east-1`, `us-west-2`), plus a new reusable module **`modules/backup_plan/`** following the existing module conventions.

Per database, the module creates:
- a **local backup vault** in the DB's source region (us-east-1 for shared/atento; sa-east-1 for auth-001), with its own KMS key;
- a **DR backup vault** in **us-west-2** with its own KMS key (the copy is re-encrypted at the destination);
- a **backup plan** — daily rule, schedule on a window **distinct from each RDS `preferred_backup_window`** (overlap bills duplicate snapshots — spike Finding 5), `delete_after = 7` local, with a `copy_action` to the us-west-2 DR vault (`delete_after = 7`);
- a **backup selection** picking the DB by tag (`Backup=cross-region-dr`);
- a **CloudWatch alarm** on `NumberOfBackupJobsFailed` (pattern at `modules/cloudwatch_app_monitoring/alarms_rds.tf`) — without it, `copy_action` failures are silent.

The 3 source DBs get tagged `Backup=cross-region-dr` (in their existing stacks or via the selection's explicit ARN — confirm at implementation).

**Structural choice — RESOLVED (engineer 2026-06-29):** a **separate `modules/backup_plan/` module, called per-stack** with a `var.destination_region` (community-standard, per cloudposse/lgallard/thoughtbot/opszero — backup is never embedded in the resource module). Each stack passes its own destination (`us-west-2` here; a future India stack would pass `ap-south-1`), so per-resource region flexibility is preserved. NOT extending the RDS module (rejected: couples concerns, doesn't generalize to EBS/EFS/S3, bloats the RDS module). NOT a single central tag-based stack (rejected: that is the AWS multi-account/Organizations pattern, overkill for a single account and loses per-resource destination flexibility). Analysis: `/tmp/backup_module_architecture_analysis_20260629.html`.

## Execution phases

1. **Module** — write `modules/backup_plan/` (vault local + DR, KMS keys, plan with copy_action, selection, alarm). Pattern-prime against existing modules first.
2. **Stack** — `backup/` with the three provider aliases; instantiate the module for the 3 DBs; tag the DBs.
3. **Plan** — `terraform plan -out`; present the structured summary (resources to add; sensitive resources; cost); **STOP for engineer approval**.
4. **Apply (after approval, MFA)** — apply; open PR (apply-before-merge).
5. **Validate** — confirm first backup + cross-region copy jobs succeed in us-west-2; confirm the failure alarm exists. **Restore-test fidelity is resolved by spike `dr-restore-test-fidelity` (2026-07-07):** the test must hit real RDS/Aurora on a non-prod stack (beta/demo), never production; a local-Postgres restore is not valid BCP evidence. It must be the **cross-region restore — the us-west-2 DR recovery point restored into a new us-west-2 RDS** (restoring the same-region local copy only tests same-region recovery, which native RDS backups already cover; the cross-region restore is what validates the regional-DR claim this stack exists for). Chosen approach (engineer, 2026-07-07) = **AWS Backup Restore Testing automated (dated Audit-Manager evidence) + an annual game-day** doing the real cutover (restore → repoint app → measured end-to-end RTO, since restore-job duration alone excludes the cutover); both run **in us-west-2 against the DR vaults** (the RestoreTestingPlan is regional). This closes P7's first cycle and feeds the BCP's measured RTO.
6. **Hand back to P6/BCP** — with cross-region DR live, write the BCP/DRP document claiming the now-real regional DR + the annual test cadence.

## Risks

| Risk | Mitigation |
|---|---|
| Backup window overlaps RDS `preferred_backup_window` → duplicate billed snapshots | Schedule the AWS Backup rule on a distinct window; verify each DB's window first |
| Cross-region KMS mis-config blocks the copy | DR vault gets its own us-west-2 KMS key; the copy re-encrypts at destination; validate the first copy job |
| `copy_action` silent failure | CloudWatch alarm on `NumberOfBackupJobsFailed` is part of the module, not optional |
| Restore procedure changes (now `aws backup start-restore-job`, not RDS console) | Document in the BCP + note to the team; covered by the restore-test in phase 5 |
| Cost drift if volumes grow | Storage measured now; revisit if `VolumeBytesUsed` grows materially |

## Out of scope (second wave / deferred)

- Non-critical DBs (`setup`, `onboarding`, `app-beta-001`, `app-demo-001`) — second wave.
- `EnableContinuousBackup` (PITR via AWS Backup) and Vault Lock — deliberate separate decisions later.
- Aurora Global Database — rejected on cost (spike); backup-restore DR meets the RTO/RPO need.

## Restore-test drills — results (P7)

### Results at a glance (all drills, 2026-07-10)

| Drill | DB | Scenario (source vault) | Size | Restore RTO (→ DB queryable) | Content check |
|---|---|---|---|---|---|
| 1 | `app-beta-001` | cross-region (DR vault, us-west-2) | 214 MB | **~3 min** | exact match (beta idle) |
| 2 | `app-shared-001` | cross-region (DR vault, us-west-2) | 339 GB | **~1 h** | partial match, coherent (busy prod) |
| 3 | `app-shared-001` | local (local vault, us-east-1) | 339 GB | **~27 min** | RTO only (fidelity already proven in Drill 2) |

**BCP numbers (production `app-shared-001`, 339 GB):** local restore **~27 min**, cross-region restore **~1 h** — measured, ~2x+ apart (all in the cluster-restore step: 16 vs 50 min). Restore is always to a NEW cluster/instance (no in-place); a full incident RTO adds app cutover on top, and compute rebuild via IaC for full-region-loss.

### Drill 1 — beta (`app-beta-001`), 2026-07-10 — PASSED

First manual cross-region restore drill, run on the non-prod beta stack as the fastest way to prove the end-to-end path before the production-representative run. Manual `start-restore-job` (not yet the automated RestoreTestingPlan).

**What was done:** restored the us-west-2 DR recovery point of `app-beta-001` (recovery point 2026-07-09) into a new throwaway us-west-2 RDS instance (`app-beta-001-restore-test`) in the default VPC over a throwaway DB subnet group, validated the content against the live beta base, then tore everything down (instance, SG rule, subnet group).

**Results:**
- Restore duration (the RTO component this measures): **~3 min 9 s** — T0 `start-restore-job` 12:52:07 UTC → instance restored 12:55:16 UTC. Restored instance: postgres 18.4, db.t3.micro, 20 GB, encrypted, `available` in us-west-2a.
- Content present and internally consistent: **163 tables, 214 MB**, database `app_beta_001`.
- Point-in-time fidelity: newest `updated_at` = 2026-07-08 19:29:40 UTC, which is ≤ the recovery point — the restore reflects the correct instant.
- **Matches the live base exactly:** restored vs live beta both = **16,282 users / 54 companies / last update 2026-07-08 19:29:40 UTC**. Beta had no writes between the recovery point and the drill, so live == restored.
- Scope note: this is restore-job duration only — it does NOT include the application cutover, which a full incident RTO would add.

**Technical gotchas (carry into Drill 2 and the RestoreTestingPlan):**
- `DBSnapshotIdentifier` must NOT be passed in the `start-restore-job` metadata — AWS expects the recovery point via `--recovery-point-arn` (its `serviceBackupArn`); leaving the key in fails the job in ~15 s. Strip it and all `InformationalOnly:*` keys from what `get-recovery-point-restore-metadata` returns.
- Override the region-specific metadata: `DBSubnetGroupName` (the source-region one does not exist in us-west-2), `VpcSecurityGroupIds`, drop `AvailabilityZone`, set `Port=5432`, `DeletionProtection=false`, and use `default.postgres18` for the parameter group (the source custom PG group does not exist in us-west-2).
- **us-west-2 has no 4Shark networking of its own** — only the default VPC. A DB subnet group had to be created there for the restore. The eventual RestoreTestingPlan / annual game-day needs a subnet group + SG present in us-west-2 (throwaway for a drill; durable if automated).
- The restore IAM role `backup-app-<db>` already carries `AWSBackupServiceRolePolicyForRestores`, so it works for `start-restore-job` as-is.
- Pulling live counts to compare: the beta ECS cluster is `beta-001-cluster` (env arg `beta-001`, NOT `app-beta-001`); `bin/ecs run` needs a runner service the beta stack lacks, so use `bin/ecs connect beta-001 web '<command>'` against the running web task.

### Restore scenarios to measure — two paths (decision 2026-07-10)

The BCP must state an RTO for **each** recovery path, not one. Two scenarios, each validated by its own restore test:

1. **Same-region restore (local vault)** — the common case: DB corruption while the region is healthy. Restore from the LOCAL AWS Backup vault (`app-<db>-local`) into the same region. Faster RTO. This plan originally deprioritized it as "covered by native RDS backups" — that holds for *capability* (native RDS PITR/snapshot recovers same-region) but NOT for *stating the everyday-recovery RTO*, and the local AWS Backup vault is a distinct copy from native RDS backups. So it is now an explicit measured scenario (engineer decision 2026-07-10).
2. **Cross-region restore (DR vault)** — the disaster case: local backup also lost / region lost. Restore from the us-west-2 DR vault (`app-<db>-dr`). Larger RTO; for full region loss, add the compute rebuild via IaC (ANALYSIS scenario (b)).

Grounding (2026-07-10 research): AWS restore test plans are meant to "simulate different recovery scenarios," and best practice is to "run game days that exercise the real failover, measure actual RTO and RPO each time." Same-region restores are faster (no WAN copy); cross-region exists for the region-loss case. **Nuance — MEASURED, and it refuted the earlier assumption (Drills 2 + 3, 2026-07-10):** I originally assumed the raw DB-restore duration would be similar for both (both restore an in-region-resident snapshot). The measurements disprove it: for the same 339 GB shared cluster, the local restore took ~16 min to cluster-available vs ~50 min cross-region (~27 min vs ~1 h total). Restoring an Aurora cluster from a cross-region-copied snapshot in the DR region is materially slower than from a native local backup snapshot — the DB-restore step itself differs, on top of any cutover/compute-rebuild difference. Sources: [AWS — Validate recovery readiness with AWS Backup restore testing](https://aws.amazon.com/blogs/storage/validate-recovery-readiness-with-aws-backup-restore-testing/); [AWS — Disaster recovery options in the cloud](https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-options-in-the-cloud.html); [AWS Builder Center — Automate RTO and Data Recovery Validations](https://builder.aws.com/content/2mZmBTIhCMvZRk2YOjFS4VFJSba/automate-rto-and-data-recovery-validations-for-aws-backup-with-restore-automation).

### Drill 2 — shared (`app-shared-001`), cross-region (DR vault) — PASSED (2026-07-10)

Scenario 2 (cross-region) against the largest productive DB — the production-representative RTO the BCP must cite. Restored the us-west-2 DR recovery point of the `app-shared-001` Aurora cluster (recovery point 2026-07-10 05:00 UTC) into a new throwaway us-west-2 Aurora cluster + one `db.t4g.large` writer instance, over a throwaway subnet group in the default VPC, validated against the live shared base, then tore everything down.

**RTO — restore duration (the key BCP number):**
- T0 `start-restore-job`: 13:36:26 UTC.
- Cluster `available` (event "DB cluster created from snapshot"): 14:27:00 UTC → **cluster restore ≈ 50 min**.
- Writer instance (`db.t4g.large`) added + `available`: ~14:37 UTC → **instance add ≈ 10 min**.
- **Total restore RTO ≈ 1 hour** (T0 → DB queryable). Contrast: beta was ~3 min for 214 MB — a productive 339 GB cluster restores roughly 20× slower, which is exactly why a homologation-base number is not usable for the BCP.
- Scope note: still restore-duration only; a full incident RTO adds the app cutover (and, for full-region loss, the compute rebuild via IaC — ANALYSIS scenario (b)).

**Content validation (partial, as expected — shared is productive and drifts past the recovery point):**
- Restored `app_shared_001`: **161,375 users / 78 companies / 315 GB**, newest `updated_at` = 2026-07-10 04:02:28 UTC (≤ the 05:00 UTC recovery point → point-in-time fidelity confirmed).
- Live shared at ~14:20 UTC: **161,376 users / 78 companies**, newest `updated_at` = 2026-07-10 14:20:04 UTC.
- Delta explained and coherent: companies identical; users +1 on live; live's newest update ~10 h ahead — all consistent with ~9-10 h of production writes after the recovery point. Restored ≤ live, no corruption. This is the honest partial-match a busy base gives (unlike beta, which was idle and matched exactly).

**Aurora-specific gotchas (vs the RDS-instance path in Drill 1):**
- `ResourceType Aurora`: the restore creates the CLUSTER only (0 members) — a writer instance must be added separately (`create-db-instance --db-cluster-identifier`), and that add-time counts toward RTO.
- Metadata overrides: new `DBClusterIdentifier`, `DBSubnetGroupName`, `VpcSecurityGroupIds` (us-west-2 default SG), drop `AvailabilityZones` (us-east-1 AZs), `default.aurora-postgresql16` cluster param group, drop `KmsKeyId` (inherit the DR snapshot's us-west-2 key) and `EnableCloudwatchLogsExports`.
- `aws rds wait db-cluster-available` caps at 40×30 s = 20 min, so it times out on a large restore — just re-launch it; the cluster is still legitimately `creating`, not stuck.
- Connect to the CLUSTER endpoint (`...cluster-...`), not an instance endpoint. Live-count via `bin/ecs connect shared-001 web` prompts to pick a task (shared runs 4 web tasks) — answer it non-interactively (`printf '1\n' | ...`), unlike beta's single-task connect.

**Rationale:** beta is 214 MB; a homologation-base restore time does not reflect a productive-base RTO. `app-shared-001` is the largest DB (~339 GB, Aurora cluster) and productive — its cross-region restore time is the RTO figure the BCP must actually cite. Run the same cross-region drill against `app-shared-001`'s us-west-2 DR recovery point to obtain a production-representative RTO.

**Differences from Drill 1 to plan for:**
- shared is **Aurora** (cluster), not an RDS instance — the restore creates a new Aurora cluster + instance, so the metadata shape and the `ResourceType` differ from the RDS-instance path used for beta.
- ~339 GB vs 214 MB — the restore duration and cost are materially higher; measure, do not extrapolate from beta.
- Same throwaway-network approach in us-west-2; same content-match validation against the live shared base (shared is productive and busy, so live will have drifted past the recovery point — compare with that in mind, unlike beta which was idle).

### Drill 3 — shared same-region local restore (scenario 1) — PASSED (2026-07-10)

Measures the everyday-recovery RTO: restored the shared Aurora cluster from the LOCAL vault (`app-shared-001-local`, us-east-1, recovery point 2026-07-10 05:00 UTC, recovery-point id prefix `job-` = a native backup job, NOT a `copyjob-` cross-region copy) into a new throwaway us-east-1 Aurora cluster + `db.t4g.large` instance (beta VPC subnet group, not publicly accessible — this drill measured RTO only; content-restore fidelity was already proven in Drill 2). Then tore it down. New isolated cluster — live shared never touched (RDS/Aurora restore is always to new, never in-place).

**RTO — local restore:**
- T0 `start-restore-job`: 14:59:04 UTC.
- Cluster `available` (event "DB cluster created from snapshot"): 15:15:21 UTC → **cluster restore ≈ 16 min**.
- Writer instance `available`: ~15:26 UTC → **instance add ≈ 10 min**.
- **Total local RTO ≈ 27 min.**

**Key finding — the two scenarios have materially different RTOs (same 339 GB shared cluster):**

| Scenario | Cluster restore | Total RTO (restore → DB queryable) |
|---|---|---|
| **Local** (local vault → same region, us-east-1) | ~16 min | **~27 min** |
| **Cross-region** (DR vault us-west-2) | ~50 min | **~1 h** |

The local restore is ~2x+ faster; the whole gap is in the cluster-restore step (16 vs 50 min), not the instance add. This refutes the earlier assumption that in-region snapshot restores would be similar. **BCP must state both RTOs separately:** ~27 min for the common local-corruption recovery (region healthy — native RDS PITR would be faster still, per its finer granularity), ~1 h for the cross-region DR recovery (region lost) — plus the app cutover on top of each, and the compute rebuild via IaC for the full-region-loss case.

## Learnings — reusable procedure (from Drills 1–3)

The exact mechanics to fold into the runbook and any automation:

- **`start-restore-job` metadata:** strip `DBSnapshotIdentifier` (AWS wants the recovery point as `--recovery-point-arn`; leaving it fails the job in ~15 s) and every `InformationalOnly:*` / `aws:backup:request-id` key from what `get-recovery-point-restore-metadata` returns. Override the region-specific fields: new identifier, `DBSubnetGroupName`, `VpcSecurityGroupIds`, drop `AvailabilityZone(s)`, `Port=5432`, `DeletionProtection=false`, parameter group → the region default (`default.postgres18` / `default.aurora-postgresql16`), drop `KmsKeyId` (inherit the snapshot's key), drop `EnableCloudwatchLogsExports`.
- **Aurora vs RDS instance:** RDS-instance restore (`ResourceType RDS`) produces a ready instance. Aurora restore (`ResourceType Aurora`) produces the CLUSTER only (0 members) — a writer instance must be `create-db-instance --db-cluster-identifier`'d separately, and that ~10 min counts toward RTO. Connect to the CLUSTER endpoint (`...cluster-...`).
- **Networking for the throwaway target:** us-west-2 has only a default VPC (no 4Shark networking) → make a throwaway subnet group over its default subnets. us-east-1 has NO default VPC → use a non-prod VPC's subnets (the beta VPC) for the throwaway subnet group. The restore role `backup-app-<db>` already carries `AWSBackupServiceRolePolicyForRestores`.
- **Waiters:** `aws rds wait db-cluster-available` / `db-instance-available` cap at 40×30 s = 20 min → they time out on a large restore; just relaunch (the cluster is still legitimately `creating`).
- **Recovery-point origin tell:** id prefix `job-` = a native local backup (local vault); `copyjob-` = the cross-region copy (DR vault). Use this to pick the right scenario.
- **Live-count for the content check:** `bin/ecs connect <env> web '<rails runner>'` — env is the cluster short name (`beta-001`, `shared-001`, NOT `app-beta-001`); `bin/ecs run` needs a runner-service the app stacks lack. A busy stack (shared) runs multiple web tasks and prompts to pick one → answer non-interactively (`printf '1\n' | ...`).
- **Credential handling:** the DB password lives inside the env's `/<env>/DATABASE_URL` SSM param — fetch to a local file (never printed to chat), connect via a file-sourced conn string; the `DATABASE_URL` dbname is stale (`<env>_master`) — the real app DB is `app_<env>`. Purge the file after.

## Status — end of session 2026-07-10 (roadmap fully closed)

The restore capability is proven and measured (3 drills PASSED), the automation is live and validated, the documentation is written and merged, and the calendar block is created. Nothing pending.

1. **Automation — DONE (terraform PR #675 merged + applied; validated 2026-07-10).** 17 resources live: reusable `modules/restore_testing_plan` (dedicated minimal VPC + subnet group + SG + `aws_backup_restore_testing_plan` + `aws_backup_restore_testing_selection` + `NumberOfRestoreJobsFailed` alarm), wired into `app-shared-001` for both scenarios (DR us-west-2 + local us-east-1). Cadence MONTHLY (`cron(0 6 1 * ? *)`); the annual game-day stays manual. Cost ~$24/yr. Apply gotcha (fixed): AWS SG descriptions reject non-ASCII (em-dash) → use plain hyphens.
   - **Overrides validated — the antecipado (2026-07-10).** The run-time caveat (`restore_metadata_overrides` are only exercised when a test runs; Terraform does not validate them at plan/apply) is CLOSED. The local plan's schedule was bumped to fire 2026-07-10 17:00 UTC; it launched a restore job (`CreatedBy.RestoreTestingPlanArn = ...app_shared_001_local`, Status RUNNING) — a job was CREATED, not rejected at metadata, so the overrides ARE accepted by the restore-testing engine. The bump was drift (live one-time cron ≠ committed monthly) and was **reverted to monthly via `terraform apply` on `app-shared-001`** (0 add, 1 change, 0 destroy) — live now equals code. The DR-scenario plan was NOT separately bumped (still monthly); its overrides are the same shape, and the Slack alarm (below) now covers any first-monthly-run failure.
   - **Slack alerting — DONE via terraform (PR #678 merged + applied), no manual step remains.** The previously-manual Chatbot subscription was replaced: the central Chatbot Slack channel config (`4shark-cloudwatch-alerts` → #dev_operations) was imported into `monitoring/chatbot.tf` and the us-west-2 DR topic (`restore-test-app-shared-001-dr-alerts`) added to its `sns_topic_arns` — verified both topics subscribed. Gotcha: Chatbot is global (region-less ARN); do NOT set a per-resource `region` override — it forces replacement of the central integration (caught in the plan before apply, removed).
   - Deferred: the Audit-Manager "restore time meets target" control (dated RTO evidence) — add if an auditor asks.
2. **Documentation — DONE.**
   - **Restore runbook** — `dot-claude` PR #381 merged: `docs/runbooks/disaster-recovery/BACKUP-RESTORE-TESTING.md` (both scenarios, cadence, procedure, learnings; registered in INDEX + `/runbook`).
   - **BCP/DRP (P6)** — `compliance` PR #9 merged: `internal/plano-de-continuidade-de-negocios-e-recuperacao-de-desastres.md` (Termo de Ciência format, applicability-matrix row #16). States committed **RPO ≤ 1h / RTO 4h** (the targets given to Barigui — the measured margin ~27 min/~1 h is kept internal), the two scenarios, cross-region separation, and the test cadence. Closes Barigui R92 + R93. `legal-compliance-documents/ANALYSIS.md` P6/P7 and `PLAN.md` marked DONE.
3. **Google Drive — Compliance register — DONE.** The test-execution spreadsheet register (a register of runs, NOT a prose doc) holds the 2026-07-10 runs (both scenarios, RTOs, data validation). The process/how-to lives in the dot-claude runbook, not the Drive.
4. **Calendar block — DONE (2026-07-10).** A recurring monthly block was created on the engineer's primary calendar for the first business day of each month, 09:00–12:00 America/Sao_Paulo (`RRULE:FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1`, BUSY; first occurrence 2026-08-03), to review the monthly automated restore test. Engineer chose a MONTHLY cadence (not annual-only); the annual end-to-end game-day (~July) is noted in the event description.

### Incidental this session (context, not backup-scope)
- **Terraform plan-output guard — dot-claude PR #382 merged + live.** A `tf.plan` got committed into the terraform repo because a relative `-out=tf.plan` resolves against `-chdir=<stack>` → lands in the stack directory. Fix: `terraform.sh` now forces any `plan -out` to `/tmp/<basename>`, `validate-bash-command.sh` blocks a raw project-tree `-out`, and the misleading doc examples (including the CLAUDE.md wrapper example, which was the root cause) were corrected. The stray `tf.plan` was removed (terraform PR #677 merged).
- **Compliance document versioning — merged.** All 20 compliance documents now carry a `**Versão:** 1.0` header (6 were missing it); ready for the "v1.0 of all" signature batch.
