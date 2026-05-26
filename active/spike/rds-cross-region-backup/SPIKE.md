# SPIKE — RDS Cross-Region Backup for 4Shark

**Conducted by:** Paulo Ribeiro
**Date:** 2026-05-20
**Status:** Research complete — pending decisions

---

## Goal

Answer two questions:

1. Where are the automated backups for 4Shark RDS instances currently stored? Are they protected against a full regional outage?
2. What is the most cost-effective, operationally viable option to achieve cross-region DR for RDS?

**Motivation:** All 4Shark RDS automated backups reside in the same AWS region as the DB instances themselves. A full region failure would destroy both the primary data and all backups simultaneously. The engineer asked: *"Se a região pegar fogo, perdemos os backups junto?"* — investigation confirmed: yes.

---

## Method

- Audited all `rds.tf` files in the Terraform monorepo (`~/Projects/4Shark/terraform`)
- Read the two RDS modules (`modules/rds_instance/main.tf`, `modules/rds_aurora_cluster/main.tf`)
- Ran `grep` across the full repository for any cross-region backup, replication, or AWS Backup resource references
- Consulted AWS documentation for available DR mechanisms (automated backups replication, AWS Backup, Aurora Global Database)
- Analyzed pricing from official AWS Backup pricing page and the AWS Database Blog cost breakdown post
- Evaluated trade-offs with the engineer and recorded decisions inline

---

## Evidence

### Current State — RDS Inventory

Seven RDS databases exist across two regions. None have cross-region backup configured.

| Stack | Region | Type | Engine | Retention | Multi-AZ | Cross-region backup |
|-------|--------|------|--------|-----------|----------|---------------------|
| `app-shared-001` | us-east-1 | Aurora cluster (2 nodes) | PostgreSQL 15.15 | 7 days | yes (cluster) | none |
| `app-atento-001` | us-east-1 | Aurora cluster (2 nodes) | PostgreSQL 15.15 | 7 days | yes (cluster) | none |
| `app-demo-001` | us-east-1 | Aurora cluster (1 node) | PostgreSQL 16.11 | 7 days | no | none |
| `app-beta-001` | us-east-1 | RDS instance | PostgreSQL 17.6 | 7 days | no | none |
| `auth-001` | sa-east-1 | RDS instance | PostgreSQL 15.12 | 7 days | yes | none |
| `setup` | us-east-1 | RDS instance | PostgreSQL 16.9 | 7 days | no | none |
| `onboarding` | us-east-1 | RDS instance | PostgreSQL 16.9 | 7 days | no | none |

**Sources:** `app-demo-001/rds.tf`, `app-shared-001/rds.tf`, `app-beta-001/rds.tf`, `app-atento-001/rds.tf`, `auth-001/rds.tf`, `setup/rds.tf`, `onboarding/rds.tf`

### Current State — What the Modules Configure

`modules/rds_instance/main.tf` (51 lines) configures `aws_db_instance` with `backup_retention_period` and `copy_tags_to_snapshot = true`. No cross-region replication resources are present.

`modules/rds_aurora_cluster/main.tf` configures `aws_rds_cluster` + `aws_rds_cluster_instance` with the same pattern.

**`copy_tags_to_snapshot = true` only copies metadata tags to the snapshot — it does not copy the snapshot to another region.**

A repository-wide grep for cross-region backup resources returned a single irrelevant hit (a comment in `app-outbound-atento-br/compute.tf:13`). Resources searched: `automated_backups_replication`, `backup_replication`, `aws_db_snapshot_copy`, `aws_backup`, `cross.region`, `replicate.*backup`.

### Option 1 — `aws_db_instance_automated_backups_replication` (rejected)

Native RDS resource that replicates automated backups to another region.

**Fatal limitation:** only supports `aws_db_instance`. Does not support Aurora (`aws_rds_cluster`). Three of the seven databases are Aurora (`app-shared-001`, `app-atento-001`, `app-demo-001`), making this option a partial solution at best.

**Source:** [Replicating automated backups to another AWS Region](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_ReplicateBackups.html)

### Option 2 — AWS Backup (chosen)

AWS Backup is an orchestration service that uses native RDS/Aurora snapshot and PITR APIs. It supports both `aws_db_instance` and Aurora clusters uniformly.

**How it works:**

- **Backup vault** — a logical container with its own KMS key, access policy, and optional Vault Lock (immutable WORM)
- **Backup plan** — one or more rules: cron schedule, retention, and `copy_action` entries pointing at vaults in other regions
- **Resource assignment** — by tag (e.g., `Backup=daily-cross-region`) or by explicit ARN

**Execution flow:** the backup plan triggers `create-db-snapshot` (or `copy-db-snapshot` from the most recent automated backup if one already exists, making the first managed snapshot incremental). `copy_action` copies the resulting snapshot to the destination vault in the target region. PITR can optionally be enabled via `EnableContinuousBackup`, which transfers management of the 5-minute transaction log stream from RDS native to AWS Backup.

**Known pitfall — duplicate snapshot charges:** if the AWS Backup schedule window overlaps with the RDS `preferred_backup_window`, both the RDS native backup and the AWS Backup run within the same window, producing separate snapshots that are both retained and billed. Windows must be kept distinct.

**Migration behavior (no data migration required):** when AWS Backup first runs against an RDS instance that already has native automated backups, it detects the existing backups and takes an incremental snapshot from the most recent one via `copy-db-snapshot`. Native automated backups continue to exist and expire on their own retention schedule. Coexistence is the normal path — no cutover needed.

**Sources:**
- [Amazon RDS backups — AWS Backup developer guide](https://docs.aws.amazon.com/aws-backup/latest/devguide/rds-backup.html)
- [Continuous backups and PITR — AWS Backup developer guide](https://docs.aws.amazon.com/aws-backup/latest/devguide/point-in-time-recovery.html)
- [PITR and continuous backup for RDS with AWS Backup — AWS Storage Blog](https://aws.amazon.com/blogs/storage/point-in-time-recovery-and-continuous-backup-for-amazon-rds-with-aws-backup/)
- [re:Post — Impact of enabling AWS Backup PITR on RDS native automated backups](https://repost.aws/questions/QUy4ZcF-ErRuaVanWCQo0aSA/impact-of-enabling-aws-backup-pitr-on-rds-native-automated-backups)

### Option 3 — Aurora Global Database (rejected)

Cross-region read replica with RPO ~1s and full region failover capability.

**Rejected:** requires a permanently active second instance in the DR region, which represents a substantial cost increase. The RTO/RPO offered exceeds 4Shark's stated DR need (backup recovery is acceptable; sub-second failover is not required). Cost does not justify the capability.

### Cost Model

**Reference prices (us-east-1, May 2026):**
- AWS Backup warm storage (RDS/Aurora): **$0.095/GB-month**
- Cross-region data transfer: **$0.02/GB**
- Cold storage: **not supported for RDS/Aurora** (confirmed in AWS Backup pricing page)
- Free tier (in-region): 100% of `allocated_storage` is free for backup storage in the same region

**Snapshot increment model:** snapshots are incremental at the block level — both in-region and across cross-region copies (after the first copy, subsequent copies to the same destination are incremental). Example for a 300 GB DB with ~20 GB daily churn: 7 daily backups ≈ 300 GB (base) + 6 × 20 GB (deltas) ≈ 420 GB total.

**Cost scenarios for a 300 GB production database, 7-day retention:**

| Configuration | Local storage | Local cost | Destination storage | Destination + transfer cost | Total/month |
|---|---|---|---|---|---|
| Current (7d local only) | 420 GB | ~$11 (overage) | 0 | $0 | **~$11** |
| 7d local + 7d destination | 420 GB | ~$11 | 420 GB | $42 storage + $12 transfer | **~$65** |
| 1d local + 7d destination | 300 GB | $0 (free tier) | 420 GB | $42 + $12 | **~$54** |

**Decision:** keep 7 days local + 7 days at destination. Cutting local to 1 day saves ~$11/month per database but eliminates the safety net: if a `copy_action` fails (KMS error, throttling, transient API failure), the local snapshot expires before the next attempt and the day's backup is permanently lost. Fast local restores also become unavailable. The premium is worth the safety margin.

**Estimated storage for the 7 RDS instances:**

Aurora uses dynamic storage — the numbers below are estimates. Actual sizing requires measuring `VolumeBytesUsed` via CloudWatch before quoting.

| RDS | Estimated storage | Estimated DR cost/month |
|-----|-------------------|-------------------------|
| `app-shared-001` (4Shark prod) | ~300 GB | ~$54 |
| `app-atento-001` (Atento prod) | ~300 GB | ~$54 |
| `auth-001` (Keycloak) | ~5 GB | ~$2 |
| `setup`, `onboarding`, `beta`, `demo` | ~20 GB each | optional |

**Estimated minimum (3 critical DBs only): ~$110/month**

**Sources:**
- [AWS Backup pricing](https://aws.amazon.com/backup/pricing/)
- [Demystifying Amazon RDS backup storage costs — AWS Database Blog](https://aws.amazon.com/blogs/database/demystifying-amazon-rds-backup-storage-costs/)

### Target Architecture (reference design — not implemented)

Terraform pseudo-code showing the intended backup plan shape:

```hcl
rule {
  rule_name         = "daily-${var.identifier}"
  schedule          = "cron(0 5 * * ? *)"   # distinct from RDS preferred_backup_window
  target_vault_name = aws_backup_vault.local.name
  lifecycle { delete_after = 7 }             # local: 7-day safety net

  copy_action {
    destination_vault_arn = aws_backup_vault.dr.arn
    lifecycle { delete_after = 7 }           # destination: 7-day DR copy
  }
}
```

Expected new Terraform resources: `aws_backup_vault` (local + DR region), `aws_backup_plan`, `aws_backup_selection` (likely tag-based), KMS keys (multi-region or one per region), `aws_cloudwatch_metric_alarm` on `NumberOfBackupJobsFailed`. A new module `modules/backup_plan/` is expected, following the pattern of existing modules.

### Operational Impact After Implementation

- **RDS instances themselves:** no change (engine, instance class, security groups, parameter groups, application connections).
- **Native PITR:** unchanged unless `EnableContinuousBackup` is enabled in the backup rule — if it is, the RDS console blocks native PITR edits and all PITR passes through AWS Backup.
- **Restore procedure change:** restores come from `aws backup start-restore-job` instead of "Restore from DB Snapshot" in the RDS console. Engineers need to be aware of this change before it happens.
- **Monitoring:** a CloudWatch alarm on `NumberOfBackupJobsFailed` is required. Without it, `copy_action` failures are silent until someone manually opens the vault. Pattern exists at `modules/cloudwatch_app_monitoring/alarms_rds.tf`.

---

## Conclusions

**Finding 1 — current exposure:** all 7 RDS databases store automated backups in the same AWS region as the DB. A full regional outage destroys primary data and all backups simultaneously. No cross-region protection exists.

**Finding 2 — option selection:** AWS Backup is the only option that covers both RDS instances and Aurora clusters uniformly. `aws_db_instance_automated_backups_replication` covers only RDS instances (not Aurora) and was rejected. Aurora Global Database was rejected on cost grounds.

**Finding 3 — cost:** adding 7-day cross-region backup for the 3 critical databases costs approximately $110/month. Cutting local retention to 1 day saves ~$11/month per DB but removes the safety net for failed copy actions and eliminates fast local restores — the engineer decided the saving does not justify the risk.

**Finding 4 — migration:** no data migration is required. AWS Backup coexists with native RDS automated backups and takes the first snapshot incrementally from the existing automated backup history.

**Finding 5 — known pitfall:** AWS Backup schedule windows must not overlap with the RDS `preferred_backup_window` — overlapping windows produce duplicate snapshots that are billed separately.

**Finding 6 — monitoring gap:** without a CloudWatch alarm on `NumberOfBackupJobsFailed`, backup copy failures are invisible. This alarm is required alongside the backup plan.

---

## Decisions Recorded

These decisions were made with the engineer during the investigation and are recorded here to avoid re-litigating them when implementation resumes.

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Which option | AWS Backup | Only option covering both RDS instances and Aurora clusters |
| Scope — first wave | `app-shared-001`, `app-atento-001`, `auth-001` only | The 4 non-production DBs are deferred to a second wave |
| Local retention | Keep 7 days | Safety net for failed copy actions; fast local restore |
| Destination retention | 7 days | Matches local retention; engineer decision |
| Monitoring | CloudWatch alarm on `NumberOfBackupJobsFailed` | Silent failures are unacceptable for DR |
| `EnableContinuousBackup` | Pending — do not enable initially | Keep native RDS PITR independent; revisit separately |
| Vault Lock | Pending — default off | Irreversible; revisit if compliance requirement surfaces |
| Validation sequence | Non-prod first (`setup` or `onboarding`) | Reduce risk before touching critical databases |

---

## Open Questions

1. **Destination region:** us-west-2 (same US sovereignty, further distance) or another? `auth-001` is in sa-east-1 — its destination region may differ from the us-east-1 databases. Engineer decides.

2. **Aurora actual storage:** `VolumeBytesUsed` must be measured in CloudWatch before committing to cost estimates — the 300 GB figure is an approximation.

3. **Non-critical databases:** `setup`, `onboarding`, `app-beta-001`, `app-demo-001` — include in first wave, second wave, or exclude?

4. **`EnableContinuousBackup` (PITR via AWS Backup):** enabling it transfers PITR management from RDS native to AWS Backup and blocks native PITR edits in the console. Default decision: do not enable initially. Requires a separate deliberate decision.

5. **Vault Lock:** adds WORM immutability to the destination vault. Irreversible once enabled. Default decision: off. Revisit if LGPD or Atento contract requirements are confirmed.

6. **Validation sequence:** confirmed implicitly — run against a non-production database (`setup` or `onboarding`) before touching critical databases. Explicit confirmation needed at implementation start.

---

## Next Steps

When resuming, call `@agent-plan-researcher` with the following scope:

- Measure actual `VolumeBytesUsed` for all 7 RDS via CloudWatch (cost model input)
- Define destination region(s) — one for us-east-1 databases, possibly another for `auth-001` (sa-east-1)
- Define the Terraform module structure for `modules/backup_plan/` following existing module patterns
- Define implementation sequence: non-production validation first, then critical databases
- Resolve open questions above before composing `PLAN.md`

**Do not create a plan now.** The engineer explicitly stated: *"não vou fazer agora, salve um spike."*

---

## Sources

| Source | Contribution |
|--------|-------------|
| [Amazon RDS backups — AWS Backup developer guide](https://docs.aws.amazon.com/aws-backup/latest/devguide/rds-backup.html) | Confirmed Aurora + RDS instance support; backup plan mechanics |
| [Continuous backups and PITR — AWS Backup developer guide](https://docs.aws.amazon.com/aws-backup/latest/devguide/point-in-time-recovery.html) | `EnableContinuousBackup` behavior; impact on native PITR |
| [Demystifying Amazon RDS backup storage costs — AWS Database Blog](https://aws.amazon.com/blogs/database/demystifying-amazon-rds-backup-storage-costs/) | Incremental block-level snapshot model; free tier mechanics |
| [AWS Backup pricing](https://aws.amazon.com/backup/pricing/) | Warm storage rate ($0.095/GB-month); cold storage unsupported for RDS/Aurora |
| [Replicating automated backups to another AWS Region — RDS docs](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_ReplicateBackups.html) | Confirmed `aws_db_instance_automated_backups_replication` does not support Aurora |
| [PITR and continuous backup for RDS with AWS Backup — AWS Storage Blog](https://aws.amazon.com/blogs/storage/point-in-time-recovery-and-continuous-backup-for-amazon-rds-with-aws-backup/) | Migration coexistence behavior; incremental first-run snapshot |
| [re:Post — Impact of AWS Backup PITR on RDS native automated backups](https://repost.aws/questions/QUy4ZcF-ErRuaVanWCQo0aSA/impact-of-enabling-aws-backup-pitr-on-rds-native-automated-backups) | Community confirmation of coexistence behavior and PITR management transfer |
| `modules/rds_instance/main.tf` | Module configures `backup_retention_period` and `copy_tags_to_snapshot` only — no cross-region resources |
| `modules/rds_aurora_cluster/main.tf` | Same as above for Aurora clusters |
| `app-shared-001/rds.tf`, `app-atento-001/rds.tf`, `app-demo-001/rds.tf`, `app-beta-001/rds.tf`, `auth-001/rds.tf`, `setup/rds.tf`, `onboarding/rds.tf` | Per-stack RDS configuration audit — confirmed no cross-region backup in any stack |

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
>
> **Further reading:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/technical-spike/)
