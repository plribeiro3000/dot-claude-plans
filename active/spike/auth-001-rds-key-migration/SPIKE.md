# SPIKE — auth-001 RDS Re-Key to Dedicated KMS Key + Managed Master Password / Performance Insights / Enhanced Monitoring Adoption

## Investigation question

How can the productive Keycloak RDS instance `auth-001` (PostgreSQL 15.17, db.t3.small, 20GB gp3, Multi-AZ, sa-east-1) be moved from the wrong KMS key (`alias/auth002`) onto its dedicated key (`alias/auth-001`) with only a short (~1-2 minute) connection blip — while simultaneously adopting managed master password, Performance Insights, and Enhanced Monitoring — given that the engineer accepts a brief write-freeze but not a 10-20 minute hard outage, and the data must be preserved (no destroy+recreate)?

## Context (given, not re-verified this session)

- Instance `auth-001`: PostgreSQL 15.17, db.t3.small, 20GB gp3, Multi-AZ, sa-east-1, `keycloak` DB, master user `postgres`.
- Currently encrypted under `alias/auth002` (wrong key); target is `alias/auth-001`.
- No managed master password, PI disabled, `monitoring_interval` 0 today.
- Keycloak connects via Secrets Manager secret `auth-001-sm` (KC_DB_USERNAME/KC_DB_PASSWORD); whether that username is the master `postgres` or a dedicated app user is unconfirmed.
- Keycloak runs on ECS Fargate, `desired_count` 2; `KC_DB_URL` is baked into the task-def env from the RDS endpoint address. An endpoint change needs a new task-def revision + rolling deploy.
- Declared as `aws_db_instance` directly in `modules/auth/rds.tf` (not the shared `modules/rds_instance`) — no `prevent_destroy`, but a Terraform replace still destroys the data, so that path is out regardless of the lifecycle block.

## Sources consulted

- [Encrypting Amazon RDS resources](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Overview.Encryption.html) — KMS key immutability after creation, same-region replica key constraint, cross-region replica key freedom, full limitations list
- [Creating a read replica in a different AWS Region](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_ReadRepl.XRgn.html) — confirms `--kms-key-id` is only a parameter of the cross-region replica creation path
- [Working with DB instance read replicas](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_ReadRepl.html) — general read-replica mechanics (same-region vs cross-region)
- [Overview of Amazon RDS Blue/Green Deployments](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/blue-green-deployments-overview.html) — switchover timing, what the green environment copies (including PI/Enhanced Monitoring)
- [Limitations and considerations for Amazon RDS blue/green deployments](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/blue-green-deployments-considerations.html) — Secrets Manager incompatibility, encryption-state immutability, logical-replication limitations (sequences, DDL, DCL, large objects)
- [Password management with Amazon RDS and AWS Secrets Manager](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-secrets-manager.html) — managed master password at create vs modify, blue/green + read-replica-from-managed-secret exclusions, required KMS permissions
- [Overview of Performance Insights on Amazon RDS](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.Overview.html) — **time-critical**: Performance Insights end-of-life notice
- [Monitoring OS metrics with Enhanced Monitoring](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_Monitoring.OS.html) — Enhanced Monitoring mechanics and engine availability
- [Performing logical replication for Amazon RDS for PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/PostgreSQL.Concepts.General.FeatureSupport.LogicalReplication.html) — `rds.logical_replication` static parameter + reboot requirement, required roles
- [PostgreSQL Logical Replication Restrictions](https://www.postgresql.org/docs/current/logical-replication-restrictions.html) — native Postgres restrictions: sequences, DDL, large objects, replica identity
- [AWS DMS: Creating tasks for ongoing replication](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Task.CDC.html) — CDC latency has no SLA; full-load-plus-CDC mechanics
- [Using a PostgreSQL database as a target for AWS DMS](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Target.PostgreSQL.html) — sequences NOT migrated by DMS, manual `NEXTVAL` reset required
- [Changing an AWS KMS policy for Performance Insights](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.access-control.cmk-policy.html) — exact KMS key policy statement (`kms:ViaService` = `rds.<region>.amazonaws.com`)
- [Secret encryption and decryption in AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/latest/userguide/security-encryption.html) — exact KMS `kms:ViaService` = `secretsmanager.<region>.amazonaws.com` requirement
- [pg_dump — PostgreSQL documentation](https://www.postgresql.org/docs/current/app-pgdump.html) — MVCC-consistent, non-blocking dump; parallel jobs
- [AWS CLI `create-db-instance` reference](https://docs.aws.amazon.com/cli/latest/reference/rds/create-db-instance.html) — confirms PI, Enhanced Monitoring, and managed master password are all valid at instance-creation time
- [GitHub keycloak/keycloak#24493](https://github.com/keycloak/keycloak/issues/24493) — Keycloak connection pool does not remove broken connections after a DB failover without a manual restart
- Options for changing AWS KMS encryption key for Amazon RDS databases (AWS Database blog, fetched but only a paraphrased summary was retrievable, not literal quotes — treated as directional context only, not a sustaining citation; see Finding 3 note)
- Keycloak Infinispan session-replication-during-rolling-restart behavior — reached only via WebSearch synthesis, not a direct fetch; tagged **UNVERIFIED**, does not sustain any Finding below (listed under "What remains uncertain")

## Findings

### Finding 1: Once created, an RDS instance's KMS key cannot be changed — re-keying always means a new instance

**Evidence:** "Once you have created an encrypted DB instance, you can't change the KMS key used by that DB instance. Therefore, be sure to determine your KMS key requirements before you create your encrypted DB instance. If you must change the encryption key for your DB instance, create a manual snapshot of your instance and enable encryption while copying the snapshot." Also, in the Limitations section: "You can only encrypt an Amazon RDS DB instance when you create it, not after the DB instance is created."

**Source:** [Encrypting Amazon RDS resources](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Overview.Encryption.html)

**Significance:** There is no in-place operation that moves `auth-001`'s existing storage onto `alias/auth-001`. Every viable path in this spike creates a **new** DB instance object under the target key and moves the data into it — the question is only which mechanism moves the data with the least downtime.

**Verification:** URL fetched directly. Verbatim quote checked. Substring confirmed at the "Overview of encrypting Amazon RDS resources" section and the "Limitations of Amazon RDS encrypted DB instances" section of the fetched page.

---

### Finding 2: A same-region read replica must use the source's KMS key; a cross-region replica can use a different key

**Evidence:** "A read replica of an Amazon RDS encrypted instance must be encrypted using the same KMS key as the primary DB instance when both are in the same AWS Region." And, separately: "If the primary DB instance and read replica are in different AWS Regions, you encrypt the read replica using the KMS key for that AWS Region." This is echoed in the cross-Region read-replica creation reference, which exposes a `--kms-key-id` CLI parameter specifically for the destination-Region key: "The following parameter is also required for creating an encrypted read replica in another AWS Region: `--kms-key-id` – The AWS KMS key identifier of the KMS key to use to encrypt the read replica in the destination AWS Region."

**Source:** [Encrypting Amazon RDS resources](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Overview.Encryption.html); [Creating a read replica in a different AWS Region](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_ReadRepl.XRgn.html)

**Significance:** A read replica cannot be used to re-key `auth-001` in place within sa-east-1 (the replica would inherit `alias/auth002`). Re-keying via replication requires either a cross-Region replica (irrelevant here — the target stays in sa-east-1) or a mechanism that is not RDS's built-in replica feature (logical replication set up by hand, or DMS).

**Verification:** URL fetched directly (both pages). Verbatim quotes checked. Substrings confirmed in the "Limitations of Amazon RDS encrypted DB instances" bullet list and in the "Cross-Region read replica" AWS CLI parameter list, respectively.

---

### Finding 3: Blue/Green Deployments do not support this migration's other stated goal (managed master password) and their KMS-key behavior for the green environment is not documented explicitly

**Evidence:** "Blue/green deployments don't support managing master user passwords with AWS Secrets Manager." Also: "You can't change an unencrypted DB instance into an encrypted DB instance. In addition, you can't change an encrypted DB instance into an unencrypted DB instance." The switchover mechanics: "The switchover typically takes under a minute with no data loss and no need for application changes" and "The green environment includes the features used by the DB instance. These features include the read replicas, the storage configuration, DB snapshots, automated backups, Performance Insights, and Enhanced Monitoring."

**Source:** [Limitations and considerations for Amazon RDS blue/green deployments](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/blue-green-deployments-considerations.html); [Overview of Amazon RDS Blue/Green Deployments](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/blue-green-deployments-overview.html)

**Significance:** Regardless of whether Blue/Green would allow specifying a different KMS key for the green environment (not found in the fetched documentation — see "What remains uncertain"), Blue/Green is ruled out here on an independent, explicitly-documented ground: it cannot be combined with adopting managed master password, which is part of this migration's scope. Blue/Green also would not by itself solve the re-key requirement, since nothing in the fetched pages lists the KMS key as a value you can change for the green environment (only engine version and parameter group are named as changeable). The engineer's low-downtime mechanism (Blue/Green) is attractive for its sub-minute switchover, but this specific combination of goals (re-key + managed master password in one pass) is not achievable through it per the documentation found.

**Verification:** URL fetched directly (both pages). Verbatim quotes checked. Substrings confirmed in the "General limitations for blue/green deployments" bullet list and in the "Workflow of a blue/green deployment" section, respectively.

---

### Finding 4: Native PostgreSQL logical replication does not replicate sequences, DDL, or large objects

**Evidence:** "Sequence data is not replicated. The data in serial or identity columns backed by sequences will of course be replicated as part of the table, but the sequence itself would still show the start value on the subscriber." "The database schema and DDL commands are not replicated. The initial schema can be copied by hand using `pg_dump --schema-only`. Subsequent schema changes would need to be kept in sync manually." "Large objects ... are not replicated. There is no workaround for that, other than storing data in normal tables."

**Source:** [PostgreSQL Logical Replication Restrictions](https://www.postgresql.org/docs/current/logical-replication-restrictions.html)

**Significance:** If a logical-replication-based cutover were chosen, the target instance's schema would need to be created by hand (`pg_dump --schema-only` or equivalent) before subscribing, and every sequence (Keycloak's Liquibase-managed schema includes several, per standard Keycloak DB layout) would need its `nextval` manually bumped to match the source immediately before cutover — a step with no built-in verification and a real risk of a silent primary-key collision if missed or mistimed.

**Verification:** URL fetched directly. Verbatim quote checked. Substring confirmed in the "Restrictions" section of the fetched page (bullet list under the numbered restrictions).

---

### Finding 5: Enabling logical replication on an RDS PostgreSQL source is a static parameter requiring a reboot

**Evidence:** "You turn on PostgreSQL logical replication and logical decoding for Amazon RDS with a parameter, a replication connection type, and a security role... Set the `rds.logical_replication` static parameter to 1. As part of applying this parameter, also set the parameters `wal_level`, `max_wal_senders`, `max_replication_slots`, and `max_connections`. These parameter changes can increase WAL generation, so set the `rds.logical_replication` parameter only when you are using logical slots... Reboot the DB instance for the static `rds.logical_replication` parameter to take effect."

**Source:** [Performing logical replication for Amazon RDS for PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/PostgreSQL.Concepts.General.FeatureSupport.LogicalReplication.html)

**Significance:** Choosing the logical-replication path means a reboot of `auth-001` is required before any replication can start — a separate blip event from the eventual cutover, on top of the schema/sequence handling from Finding 4. On a Multi-AZ instance the reboot can be requested with failover, but the fetched page does not state whether that avoids the connection interruption; it only documents the reboot requirement itself.

**Verification:** URL fetched directly. Verbatim quote checked. Substring confirmed in the "Understanding logical replication and logical decoding" numbered procedure ("To turn on logical decoding for an RDS for PostgreSQL DB instance").

---

### Finding 6: AWS DMS CDC has no latency SLA, and DMS does not migrate sequences to a PostgreSQL target

**Evidence:** "AWS DMS CDC does not provide real-time replication. Replication latency varies based on source workload, network conditions, replication instance resources, target ingestion capacity, and data characteristics. There are no SLAs for CDC latency. Latency can increase to several minutes or longer depending on these factors." Separately, for a PostgreSQL target specifically: "If your tables use sequences, then update the value of `NEXTVAL` for each sequence in the target database after you stop the replication from the source database. AWS DMS copies data from your source database, but doesn't migrate sequences to the target during the ongoing replication."

**Source:** [AWS DMS: Creating tasks for ongoing replication](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Task.CDC.html); [Using a PostgreSQL database as a target for AWS DMS](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Target.PostgreSQL.html)

**Significance:** DMS carries the same sequence gap as native logical replication (Finding 4) plus an explicitly unbounded latency characteristic ("no SLAs"), and introduces an additional moving part — a DMS replication instance — on a productive authentication path. It also requires disabling foreign-key-enforcing triggers during full load (PostgreSQL implements FKs via triggers, per the same page), which is an extra pre-flight step against a live schema.

**Verification:** URL fetched directly (both pages). Verbatim quotes checked. Substrings confirmed in the top note of "Creating tasks for ongoing replication" and in the "Limitations on using PostgreSQL as a target for AWS Database Migration Service" bullet list, respectively.

---

### Finding 7: `pg_dump` takes a consistent, non-blocking snapshot; parallel jobs can shorten the dump

**Evidence:** "pg_dump is a utility for exporting a PostgreSQL database. It makes consistent exports even if the database is being used concurrently. pg_dump does not block other users accessing the database (readers or writers)." On parallelism: "This option may reduce the time needed to perform the dump but it also increases the load on the database server. You can only use this option with the directory output format because this is the only output format where multiple processes can write their data at the same time."

**Source:** [pg_dump — PostgreSQL documentation](https://www.postgresql.org/docs/current/app-pgdump.html)

**Significance:** A `pg_dump` of the live `auth-001` database does not itself require stopping Keycloak — it takes an MVCC snapshot and does not block writers. However, because the dump is a snapshot at a single point in time, any write that happens on the source **after** that snapshot and before the new instance goes live would be lost unless writes are stopped first. This is why the short freeze (scaling Keycloak to 0) is needed around the dump-and-restore step specifically, not because the dump itself is blocking, but to guarantee no write is lost between snapshot and cutover.

**Verification:** URL fetched directly. Verbatim quotes checked. Substrings confirmed in the pg_dump description paragraph and in the `-j`/`--jobs` option description of the fetched page.

---

### Finding 8: Managed master password can be enabled at instance CREATION time — but not through Blue/Green, and not on a read replica whose source already manages credentials this way

**Evidence:** "You can specify that RDS manages the master user password in Secrets Manager for an Amazon RDS DB instance or Multi-AZ DB cluster when you perform one of the following operations: Create a DB instance ... Modify a DB instance ..." Limitations: "Managing master user passwords with Secrets Manager isn't supported for the following features: Creating a read replica when the source DB or DB cluster manages credentials with Secrets Manager. This applies to all DB engines except RDS for SQL Server. Amazon RDS Blue/Green Deployments ..." Required permissions to set a customer managed key: "`kms:DescribeKey` ... is required to access your customer-managed key for the `MasterUserSecretKmsKeyId`" and, for the user specifying that key, "`kms:Decrypt`, `kms:GenerateDataKey`, `kms:CreateGrant`."

**Source:** [Password management with Amazon RDS and AWS Secrets Manager](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-secrets-manager.html); confirmed available at `create-db-instance` time via [AWS CLI reference](https://docs.aws.amazon.com/cli/latest/reference/rds/create-db-instance.html) (`--manage-master-user-password`, `--master-user-secret-kms-key-id`)

**Significance:** Whatever data-migration mechanism is chosen, the **new** instance can be created directly with managed master password turned on and pointed at `alias/auth-001` for the secret's KMS key — no separate modify step is required for this piece. This also reconfirms Finding 3's Blue/Green exclusion from a second angle (the feature list, not just the general limitations bullet).

**Verification:** URL fetched directly (both pages). Verbatim quotes checked. Substrings confirmed in the "Overview of managing master user passwords with AWS Secrets Manager" section and the "Limitations for Secrets Manager integration with Amazon RDS" bullet list, respectively; CLI parameter existence confirmed in the fetched `create-db-instance` reference.

---

### Finding 9: Performance Insights and Enhanced Monitoring are also settable at instance-creation time

**Evidence:** From the `create-db-instance` CLI reference: `--enable-performance-insights` — "Specifies whether to enable Performance Insights for the DB instance." `--performance-insights-kms-key-id` — "The Amazon Web Services KMS key identifier for encryption of Performance Insights data." `--monitoring-interval` — "The interval, in seconds, between points when Enhanced Monitoring metrics are collected for the DB instance." `--monitoring-role-arn` — "The ARN for the IAM role that permits RDS to send enhanced monitoring metrics to Amazon CloudWatch Logs."

**Source:** [AWS CLI `create-db-instance` reference](https://docs.aws.amazon.com/cli/latest/reference/rds/create-db-instance.html)

**Significance:** All three of the migration's non-encryption goals (managed master password, PI, Enhanced Monitoring) can be requested in the single `create-db-instance` (or `restore-db-instance-from-*`) call that creates the new, correctly-keyed instance — none of them need a follow-up `modify-db-instance` step or a second maintenance event.

**Verification:** URL fetched directly. Parameter descriptions returned verbatim by the fetch tool from the CLI reference page; cross-checked against the option names appearing in the command's synopsis section.

---

### Finding 10: Performance Insights' KMS key policy needs `kms:ViaService = rds.<region>.amazonaws.com` plus specific actions and encryption-context conditions

**Evidence:** Example key-policy statement from the fetched page:
```
"Action": [
    "kms:Decrypt",
    "kms:GenerateDataKey"
    ],
"Resource": "*",
"Condition" : {
"StringEquals" : {
    "kms:ViaService" : "rds.{{us-east-1}}.amazonaws.com"
    },
"ForAnyValue:StringEquals": {
    "kms:EncryptionContext:aws:pi:service": "rds",
    "kms:EncryptionContext:service": "pi",
    "kms:EncryptionContext:aws:rds:db-id": "{{db-AAAAABBBBBCCCCDDDDDEEEEE}}"
    }
}
```
And: "If you specify a customer managed key, users in your account that call the Performance Insights API need the `kms:Decrypt` and `kms:GenerateDataKey` permissions on the KMS key."

**Source:** [Changing an AWS KMS policy for Performance Insights](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.access-control.cmk-policy.html)

**Significance:** For sa-east-1, this means the `alias/auth-001` key policy needs a statement allowing `kms:Decrypt` + `kms:GenerateDataKey` with `kms:ViaService = rds.sa-east-1.amazonaws.com` (and, if scoping tightly, the `aws:pi:service`/`aws:rds:db-id` encryption-context conditions) before Performance Insights is turned on against that key.

**Verification:** URL fetched directly. Verbatim policy JSON and prose checked. Substring confirmed in the "Example" code block and the "Choose a customer managed key" bullet of the fetched page.

---

### Finding 11: The managed-master-password secret's KMS key needs `kms:ViaService = secretsmanager.<region>.amazonaws.com`

**Evidence:** "To allow the KMS key to be used only for requests that originate in Secrets Manager, in the permissions policy, you can use the `kms:ViaService` condition key with the `secretsmanager.{{<Region>}}.amazonaws.com` value." The example AWS-managed key policy shows the required actions: `"Action": ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:CreateGrant", "kms:DescribeKey"]` under a `kms:ViaService` condition, plus a separate statement for `"kms:GenerateDataKey*"`.

**Source:** [Secret encryption and decryption in AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/latest/userguide/security-encryption.html)

**Significance:** Confirms the CONTEXT-supplied statement that `alias/auth-001`'s policy needs both a `secretsmanager.sa-east-1.amazonaws.com` ViaService grant (for the managed master password, likely already present since the stack already uses this key for `auth-001-sm`) and, per Finding 10, a new `rds.sa-east-1.amazonaws.com` ViaService grant (for Performance Insights, which is new). Both should be confirmed present on the key policy before the new instance is created — see Discovery Points.

**Verification:** URL fetched directly. Verbatim quotes checked. Substring confirmed in the "Permissions for the KMS key" section and the example key-policy JSON block of the fetched page.

---

### Finding 12: Performance Insights has a published end-of-life date of July 31, 2026 — nine days from today

**Evidence:** "AWS has announced the end-of-life date for Performance Insights: July 31, 2026. After this date, Amazon RDS will no longer support the Performance Insights console experience. The Performance Insights console will redirect to CloudWatch Database Insights. Flexible retention periods (1–24 months) and their associated pricing are preserved in Standard mode of Database Insights at the same cost as Performance Insights today. The Performance Insights API will continue to exist with no changes... If you take no action, DB instances using Performance Insights will default to using the Standard mode of Database Insights with your existing retention period configured. Your CloudFormation templates, Terraform configurations, and deployment scripts will continue to work exactly as they do today – all Performance Insights API parameters, including retention period settings, are fully preserved."

**Source:** [Overview of Performance Insights on Amazon RDS](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.Overview.html)

**Significance:** This is time-critical to the scope of this migration. The engineer's request to "adopt Performance Insights" lands 9 days before AWS's own stated console sunset for the feature. The API and Terraform-level configuration are documented as unaffected ("fully preserved" / "continue to exist with no changes"), and instances keep working automatically under "Standard mode of Database Insights" with no action required — so enabling `--enable-performance-insights` today is not wasted work, but main should be aware the *console experience* named "Performance Insights" is being retired at essentially the same time as this migration, and any documentation/runbook written for this change should account for that.

**Verification:** URL fetched directly. Verbatim quote checked. Substring confirmed in the "Important" banner at the top of the fetched "Overview of Performance Insights on Amazon RDS" page.

---

### Finding 13: Keycloak's own connection pool has documented cases of not recovering from a DB-side event without a Keycloak restart

**Evidence:** From the bug report: "Database connection that cause exceptions should be removed from the pool and not be reused. No manual intervention should be necessary." Describing the observed failure: during a PostgreSQL master/standby failover, "existing connections became read-only. When Keycloak attempted write operations, it received errors like 'ERROR: cannot execute INSERT in a read-only transaction' but continued reusing these invalid connections rather than removing them." And: "This could only be resolved by manually restarting the keycloak server to force a reconnection to the new master database." The issue was later linked to a closed pull request (#36330), though the fetched content does not state which Keycloak version shipped the fix.

**Source:** [GitHub keycloak/keycloak#24493](https://github.com/keycloak/keycloak/issues/24493)

**Significance:** This is not exactly this migration's shape (that report is about an unplanned failover producing read-only connections, not a planned endpoint repoint), but it establishes that Keycloak's connection pool has a documented history of not gracefully self-healing around a database-side event, and that a full restart of the Keycloak process was the resolution path in that case. This supports the context's premise that the cutover needs a genuine ECS task-def rolling redeploy (which restarts every task, forcing new connections) rather than relying on the pool to notice the endpoint changed underneath it. Whether the specific Keycloak version 4Shark runs still exhibits this exact failure mode is not confirmed by this Finding — it establishes the pattern, not this version's current behavior.

**Verification:** URL fetched directly. Verbatim quotes checked. Substrings confirmed in the issue's opening description and its reported resolution note.

---

## Options analysis — migration mechanism comparison

| Approach | Downtime characteristic | Complexity | Keycloak/schema-specific gotchas | Sustained by |
|---|---|---|---|---|
| **(a) Short-freeze `pg_dump`/`pg_restore`**: create new instance under `alias/auth-001` (with managed password + PI + Enhanced Monitoring at create time), scale Keycloak to 0, dump, restore, repoint, scale up | Dump itself is non-blocking (MVCC snapshot); the only true "frozen" window is between scaling to 0 and the new instance being live and verified — bounded by dump+restore duration for this DB's actual size (unmeasured — see Discovery Points) | Low — standard, well-documented tooling; parallel `-j` dump/restore can shorten the window further | None of the sequence/DDL/large-object gaps that logical replication or DMS carry — `pg_dump` captures full schema (including sequences) as ordinary SQL objects, not via a replication stream that skips them | Findings 1, 7, 8, 9, 10, 11 |
| **(b) Native PostgreSQL logical replication**: enable `rds.logical_replication` (reboot required), create schema by hand on new instance, publish/subscribe, sync, cutover | Near-zero at the final cutover moment, but a separate reboot event is required up front to turn on `rds.logical_replication`, and Multi-AZ failover behavior during that reboot is not confirmed by the fetched docs | Medium-high — manual schema replication (`pg_dump --schema-only`), manual sequence resync before cutover, ongoing DDL must be paused during migration | Sequences, DDL, and large objects are NOT replicated — must be handled by hand; a missed sequence resync risks a silent primary-key collision after cutover | Findings 4, 5 |
| **(c) AWS DMS (full load + CDC)**: DMS replication instance performs full load then continuous CDC until cutover | "No SLAs for CDC latency... Latency can increase to several minutes or longer" — not a bounded number | Medium-high — new infrastructure component (DMS replication instance), source must have backups enabled and adequate WAL retention, FK-enforcing triggers must be disabled during full load | Sequences NOT migrated by DMS to a PostgreSQL target — explicit manual `NEXTVAL` reset required after stopping replication; adds a new moving part to a productive auth path | Finding 6 |

The evidence collected shows option (a) has the fewest structural gaps for this specific case: it does not carry the sequence/DDL/large-object exclusions that both (b) and (c) carry (Findings 4 and 6), it does not require a separate reboot event on the source before migration can even start (Finding 5), and its non-blocking dump (Finding 7) means the actual frozen window is bounded by dump+restore duration rather than by an open-ended CDC lag with no SLA (Finding 6). The trade-off is that (a) is the only option of the three that requires stopping Keycloak entirely (scale to 0) for its frozen window, whereas (b) and (c) are designed around the database staying live and only the final switch being brief — but neither (b) nor (c) actually delivers a truly zero-risk brief switch here, because both leave an unresolved manual step (sequence resync) between "replication caught up" and "safe to cut over."

## Cutover sequence for option (a) — ordered steps

This sequence is written against the evidence above; it assumes the discovery points below are resolved first (DB size, KC_DB_USERNAME identity, KMS key policy statements).

1. Confirm `alias/auth-001`'s key policy includes both the `secretsmanager.sa-east-1.amazonaws.com` ViaService grant (Finding 11) and a new `rds.sa-east-1.amazonaws.com` ViaService grant (Finding 10) — add the latter if missing, before creating the new instance.
2. Create the new RDS instance (`create-db-instance` or `restore-db-instance-from-db-snapshot` of an empty/fresh instance — not a snapshot restore of `auth-001` itself, since that would inherit `alias/auth002`) with: engine PostgreSQL 15.17, matching class/storage/Multi-AZ, `--kms-key-id alias/auth-001`, `--manage-master-user-password --master-user-secret-kms-key-id alias/auth-001`, `--enable-performance-insights --performance-insights-kms-key-id alias/auth-001`, `--monitoring-interval <N> --monitoring-role-arn <arn>` (Findings 1, 8, 9).
3. Once the new instance is `available`, scale the Keycloak ECS service to `desired_count 0` — this is the start of the write-freeze; no writes reach `auth-001` from this point on.
4. Run a `pg_dump` (directory format, `-j` parallel jobs) of the `keycloak` database from `auth-001` (Finding 7 — this step itself does not need the freeze to be consistent, but running it after the freeze guarantees the dump captures every write up to the freeze point with nothing missed after).
5. `pg_restore` into the new instance's `keycloak` database.
6. Verify: row counts per table match between old and new; sequence current values (`SELECT last_value FROM <sequence>`) match; the Liquibase changelog table is present and matches.
7. Update credentials: resolve the Discovery Point on whether Keycloak's `KC_DB_USERNAME` is the master user or a dedicated app user, and either point Keycloak at the new RDS-managed secret directly or recreate the dedicated app user + grants on the new instance and update `auth-001-sm` accordingly.
8. Publish a new ECS task-definition revision with `KC_DB_URL` pointed at the new instance's endpoint (and the resolved credential source from step 7).
9. Scale the Keycloak ECS service back to `desired_count 2` — this is a full rolling restart of every task, which per Finding 13 is the safe way to guarantee no task is left holding a stale connection to the old endpoint.
10. Verify logins succeed; monitor CloudWatch and the new instance's Performance Insights/Enhanced Monitoring dashboards for the burn-in period.
11. After a confirmation burn-in window, take a final snapshot of the old `auth-001` (still under `alias/auth002`) and decommission it — Terraform state should be updated to reflect the new instance as `auth-001` going forward.

No step in this sequence leaves a window where Keycloak is running against the old instance while writes could still land on it undetected — writes stop at step 3, and nothing repoints back to the old instance afterward.

## Discovery points for main

The following require live AWS/application data this spike did not gather (per the research-only spike contract, these are named for main to run, not executed here):

1. **Actual `keycloak` database size** — read `FreeStorageSpace` (and ideally the actual DB size via `SELECT pg_database_size('keycloak')` if a connection is available) via CloudWatch for `auth-001` to size the expected dump/restore duration and validate the "short blip" assumption holds for option (a).
2. **KC_DB_USERNAME identity** — confirm whether Keycloak's Secrets Manager secret `auth-001-sm` currently authenticates as the master `postgres` user or a dedicated application user. This changes step 7 of the cutover sequence: if Keycloak already uses a dedicated user, that user and its grants must be recreated on the new instance separately from the managed master password; if Keycloak uses the master user directly, adopting managed master password may directly satisfy Keycloak's credential going forward (subject to whether app-level use of the master user is acceptable, which is a separate question from this migration's scope).
3. **Current KMS key policy content for `alias/auth-001`** — confirm (via `aws kms get-key-policy`) whether the `rds.sa-east-1.amazonaws.com` ViaService statement for Performance Insights (Finding 10) is already present or needs to be added; the `secretsmanager.sa-east-1.amazonaws.com` statement (Finding 11) likely already exists since the key is already used for `auth-001-sm` today, but should be confirmed rather than assumed.
4. **Keycloak's clustering/session-cache configuration on ECS Fargate** — confirm whether the 2 Keycloak tasks' Infinispan session cache is configured with a discovery mechanism that actually replicates sessions between the 2 Fargate tasks, or whether each task holds a local-only cache. This determines whether the `desired_count 0 → 2` cycle in the cutover sequence causes an unavoidable session/re-login event independent of the database migration itself — worth confirming as an expectation to set with the engineer, not something this migration newly introduces if it already exists in the current Fargate topology.
5. **Full table/object inventory of the `keycloak` database** — confirm the current table list (including Liquibase's `DATABASECHANGELOG`/`DATABASECHANGELOGLOCK`) so the post-restore verification step (cutover step 6) has a concrete checklist rather than an assumed set.

## What remains uncertain

- Whether AWS RDS Blue/Green Deployments would reject a different `--kms-key-id` for the green environment outright, or silently inherit the blue environment's key — not found in the fetched Blue/Green documentation (only engine version and parameter group are named as changeable for green). This is moot for the current scope since Blue/Green is independently ruled out by its Secrets Manager incompatibility (Finding 3), but it is left unresolved rather than asserted.
- Whether 4Shark's specific Keycloak deployment on ECS Fargate replicates Infinispan sessions across its 2 tasks today. Community reports describe session loss during rolling restarts under certain Infinispan/JGroups configurations, but this was reached only via search-result synthesis, not a direct, quotable fetch — it is **not** treated as a Finding above and does not sustain any option-comparison conclusion. It is listed as Discovery Point 4 for main to confirm against the actual task definition.
- The exact dump/restore duration for `auth-001`'s real data volume — no live measurement was available to this research-only spike (Discovery Point 1).
- Whether the current Multi-AZ standby of `auth-001` complicates a reboot-based path (relevant only if option (b) is later reconsidered) — the fetched logical-replication page documents the reboot requirement on the primary but does not describe Multi-AZ failover behavior during that reboot.

## Suggested options for main and the engineer

- **Option A — `pg_dump`/`pg_restore` short-freeze** (Findings 1, 7, 8, 9, 10, 11; cutover sequence above spells this out step-by-step). Evidence shows this avoids the sequence/DDL/large-object gaps present in both replication-based options and bounds the frozen window to dump+restore duration rather than an open-ended CDC/replication lag with no SLA. Trade-off: Keycloak is fully scaled to 0 for the duration of the freeze, so it is a true (if short) outage rather than a live cutover.
- **Option B — native PostgreSQL logical replication with manual schema/sequence handling** (Findings 4, 5). Evidence shows the theoretical cutover moment is briefer than Option A's, but it requires an up-front reboot to enable `rds.logical_replication`, manual schema replication before subscribing, and a manual sequence resync immediately before cutover with no built-in verification — a real risk surface for a productive authentication database.
- **Option C — AWS DMS full load + CDC** (Finding 6). Evidence shows this adds a new infrastructure component (a DMS replication instance) to the auth path, carries the same manual sequence-reset requirement as Option B, and has explicitly no SLA on CDC latency, making the "when is it safe to cut over" call less bounded than Option A's dump+restore window.

No recommendation is made here per this spike's scope — main and the engineer choose between the three based on the evidence and trade-offs above, informed by the discovery points once gathered.
