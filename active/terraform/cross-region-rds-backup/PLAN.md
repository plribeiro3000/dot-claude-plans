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
