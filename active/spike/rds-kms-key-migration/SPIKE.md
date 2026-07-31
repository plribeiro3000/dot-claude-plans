# SPIKE — Moving the app Aurora clusters onto each environment's own KMS key

## Question

The KMS key-per-environment migration has one surface left: 14 references to the shared master key across the four `app-*` stacks' `rds.tf`. Three distinct mechanics are involved. For each one: can the key be changed in place, and if not, what does AWS document as the way to change it, and what does that cost in downtime?

A specific hypothesis was raised and is tested first, because if it holds it is by far the cheapest path:

> "uma coisa que pensei foi de usar o modo cluster que temos em todos os apps para fazer uma terceira em modo leitura ja encriptada, depois derrubamos a master e automaticamente a aws coloca o novo como primario"

Add a third instance to the existing cluster, already encrypted under the new key, then drop the writer and let Aurora promote the new instance.

## Answer up front

The hypothesis cannot work, and the reason is structural rather than a limitation that might be lifted: in Aurora, encryption is a property of the **cluster's shared storage volume**, not of an instance. There is no such thing as an instance encrypted differently from its cluster. Adding a third instance adds compute against the same encrypted volume.

Two of the three mechanics are immutable after creation. The third is the only one that changes cleanly — and it is about to be renamed by AWS in two days, which changes what we should do with it.

## The current shape

Measured from `develop` at `fd2f5a1`. **The four stacks are not the same kind of database, and an earlier revision of this spike got that wrong by calling all four Aurora.** Three are Aurora PostgreSQL 16.13 clusters via `modules/rds_aurora_cluster`; the fourth (`app-beta-001`) is a single plain RDS PostgreSQL 18.4 instance via `modules/rds_instance` — `instance_class = "db.t3.micro"`, `allocated_storage = 20`, `multi_az = false`, no cluster and no reader. That difference decides its migration path (Finding 7) and it is the reason the correction matters rather than being a detail.

All four share `manage_master_user_password = true`, `storage_encrypted = true`, and `deletion_protection = true`.

| Stack | Storage key | Master secret key | PI keys | Total |
|---|---|---|---|---|
| `app-beta-001` | 1 | 1 | 1 | 3 |
| `app-demo-001` | 1 | 1 | 1 | 3 |
| `app-shared-001` | 1 | 1 | 2 | 4 |
| `app-atento-001` | 1 | 1 | 2 | 4 |
| | 4 | 4 | 6 | **14** |

`app-shared-001` and `app-atento-001` carry four because each runs two instances with Performance Insights enabled.

---

## Finding 1 — Aurora encryption is cluster-level; all instances share one key

> "Each DB instance in the DB cluster shares the same storage encrypted with the same KMS key."

This is the sentence that settles the hypothesis. The cluster has one storage volume; the instances are compute attached to it. An instance has no storage encryption property of its own — consistent with our own module, where `kms_key_id` sits on `aws_rds_cluster` and the per-instance object exposes only `performance_insights_kms_key_id`.

The same page states the read-replica case in the same direction, which is the closest analogue to "a third instance already encrypted":

> "If you have an existing unencrypted cluster, any Amazon Aurora replica (read instance) created from that cluster will also be unencrypted."

A replica inherits the cluster's encryption state. It cannot diverge from it.

**Verification**
- URL fetched: `https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Overview.Encryption.html`
- Verbatim quotes checked: both above
- Quote substrings confirmed in § "Overview of encryption in Amazon Aurora resources" and § "Limitations of Amazon Aurora encrypted DB clusters"

---

## Finding 2 — The cluster's storage key cannot be changed, and the documented path is snapshot-and-restore

> "Once you have created an encrypted DB cluster, you can't change the KMS key used by that DB cluster. Therefore, be sure to determine your KMS key requirements before you create your encrypted DB cluster."

AWS documents the replacement procedure explicitly:

> "If you need to change the encryption key for your DB cluster, follow these steps:
> - Create a manual snapshot of your cluster.
> - Restore the snapshot and enable encryption with your desired KMS key during the restore operation."

This is the same immutability shape the OpenSearch domains had: the key is fixed at creation, so moving it is a replacement, not an edit. The difference from OpenSearch is what a replacement costs. An OpenSearch index is rebuilt per commission; an Aurora cluster holds the production database.

**Verification**
- URL fetched: `https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Overview.Encryption.html`
- Verbatim quotes checked: both above
- Quote substrings confirmed in § "Encrypting an Amazon Aurora DB cluster" and the KMS considerations list

---

## Finding 3 — Blue/Green Deployments are blocked for our clusters, twice over

Blue/green is the obvious candidate for a low-downtime cutover, and it is unavailable to us.

The first blocker is categorical and applies to all four clusters as they stand:

> "Blue/green deployments don't support managing master user passwords with AWS Secrets Manager."

Every one of our four clusters sets `manage_master_user_password = true`. A second, independent AWS page states the same constraint from the other side, listing "Amazon RDS Blue/Green Deployments" among the features for which Secrets Manager master-password management is not supported.

The second blocker is why blue/green would not solve the key problem even if the first were removed:

> "Amazon Aurora creates the green environment by *cloning* the underlying Aurora storage volume in the blue environment."

A clone is copy-on-write against the source volume's pages, so the green cluster is not an independently-encrypted copy. Consistent with that, the list of what may differ between blue and green is engine version and parameter groups — the KMS key is not among them.

For reference, had it been available, its cutover cost is documented as:

> "The switchover results in downtime. The downtime is usually under one minute, but it can be longer depending on your workload."

**Verification**
- URLs fetched: `https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/blue-green-deployments-considerations.html`, `https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/blue-green-deployments-overview.html`, `https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/rds-secrets-manager.html`
- Verbatim quotes checked: all four above
- Quote substrings confirmed in § "General limitations for blue/green deployments", § "Considerations for blue/green deployments", § "Workflow of a blue/green deployment", and § "Limitations for Secrets Manager integration with Amazon Aurora"
- NOT verified verbatim: that a clone inherits the source's KMS key. No AWS sentence states this directly. It is inferred from the copy-on-write mechanism plus the absence of a key parameter in the cloning API. Treat as strong inference, not a quote.

---

## Finding 4 — The master user secret's key is also immutable, but has a documented off/on path

> "After Aurora is managing the database credentials for a DB cluster, you can't change the KMS key that is used to encrypt the secret."

The same page repeats this sentence three times — in the console, CLI and API sections — which is unusually emphatic and suggests it is a common expectation to correct.

There is an escape hatch, documented for a different purpose (recovering an `impaired` secret) but mechanically applicable:

> "you can modify the DB cluster to turn off automatic management of database credentials, and then modify the DB cluster again to turn on automatic management of database credentials"

Turning management off and on again creates a new secret, and the key is specifiable at that moment. The cost is that the master password changes in the process, and there is a window where management is off.

Whether that window matters depends on who uses the master user. Our applications connect with their own roles; the master is used for migrations and administration. That needs confirming against the code before this path is chosen — it is listed as an open question below rather than assumed.

**Verification**
- URL fetched: `https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/rds-secrets-manager.html`
- Verbatim quotes checked: both above
- Quote substrings confirmed in § "Managing the master user password for a DB cluster with Secrets Manager" (three occurrences) and § "Viewing the details about a secret for a DB cluster"

---

## Finding 5 — Performance Insights is the one clean mechanic, and it is being renamed in two days

Toggling it is explicitly non-disruptive:

> "Turning Performance Insights on and off doesn't cause downtime, a reboot, or a failover."

But the page opens with a dated end-of-life that lands two days from this spike:

> "AWS has announced the end-of-life date for Performance Insights: July 31, 2026. After this date, Amazon RDS will no longer support the Performance Insights console experience."

And, importantly for us, the transition is automatic and preserves our configuration:

> "If you take no action, DB clusters using Performance Insights will default to using the Standard mode of Database Insights with your existing retention period configured. Your CloudFormation templates, Terraform configurations, and deployment scripts will continue to work exactly as they do today – all Performance Insights API parameters, including retention period settings, are fully preserved."

So the six PI key references do not break, and nothing must be done before the date. What it means for sequencing is that these six should not be touched this week: doing so would change a resource while the service behind it is being renamed, and any surprise would be ambiguous between our change and the transition.

**Verification**
- URL fetched: `https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/USER_PerfInsights.Enabling.html`
- Verbatim quotes checked: all three above
- Quote substrings confirmed in the page's opening Important block and § "Turning Performance Insights on and off for Aurora"
- NOT verified: whether changing the PI key requires a disable/re-enable cycle, and whether historical PI data encrypted under the old key survives it. The page documents the key as a create-time and enable-time option and is silent on changing it in place.

---

## Finding 6 — The cluster identifier is invisible to the application, so no round-trip is needed

The question was whether a replacement database must end up carrying the original identifier, which for the OpenSearch domains forced a two-hop round trip through a temporary name. Here it does not, and the reason is the pooler.

The application resolves a stable internal CNAME — `connection-pooler-<environment>.4shark.internal` — which contains no database identifier. The pooler, in turn, receives its backend host as a Terraform reference, not a literal:

```
app-shared-001/main.tf:102-118

  databases = [
    {
      name          = "shared001_master"
      host          = module.rds_aurora_cluster.cluster_endpoint
      ...
    },
    {
      name          = "shared001_follower"
      host          = module.rds_aurora_cluster.cluster_reader_endpoint
      ...
    },
  ]
```

So a new database with a new identifier produces a new endpoint, Terraform rewires the pooler to it by reference, and the application never sees the change. The cutover point is the pooler's configuration, not the application's — and the pooler is precisely the component whose job is to absorb a backend change.

The consequence for planning is that a **one-way move to a new permanent identifier is available**, and the round trip through a temporary name is unnecessary. What remains to be measured is the pooler's own cutover: repointing it changes its task definition, so its tasks are replaced, and whether the application's connections survive that replacement transparently is not established here.

## Finding 7 — For a plain RDS instance, the original hypothesis IS the documented path

Finding 1 closed the hypothesis for Aurora, where encryption belongs to the shared cluster volume. A plain RDS instance has its own storage, and there the same idea is documented on both halves.

The replica can be created encrypted under a chosen key. The console flow for creating a read replica states it directly:

> "To create an encrypted read replica, expand **Additional configuration** and specify the following settings: 1. Choose **Enable encryption**. 2. For **AWS KMS key**, choose the AWS KMS key identifier of the KMS key."

with the precondition we already satisfy:

> "The source DB instance must be encrypted."

And the promotion half — the engineer's "derrubamos a master e automaticamente a aws coloca o novo como primario" — is documented as literal behaviour:

> "If you delete a source DB instance without deleting its read replicas in the same AWS Region, each replica is promoted to a standalone DB instance."

Deleting the source to trigger promotion is not the shape to use, because it couples the promotion to a destroy. `promote-read-replica` is the deliberate operation and should be preferred; the quote matters because it establishes that promotion of a same-region replica to a standalone instance is a first-class, supported transition rather than an improvisation.

**Verification**
- URLs fetched: `https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_ReadRepl.Create.html`, `https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_ReadRepl.html`
- Verbatim quotes checked: all three above
- Quote substrings confirmed in § "Console" (create read replica, step 10) and § "Considerations when deleting replicas"
- NOT verified: that the KMS-key choice applies to a SAME-region replica specifically. The console flow documents the setting without restricting it by Region, and the page covers same-Region and cross-Region together, but no sentence scopes it explicitly. This is the one point to confirm on `beta` before relying on it — and `beta` is non-productive, which is what makes it the right place to confirm it.

## The three mechanics, summarised

| Mechanic | Refs | In-place? | Documented path | Cost |
|---|---|---|---|---|
| Cluster storage `kms_key_id` | 4 | No — fixed at creation | Snapshot → restore specifying the new key | A cutover; the whole question below |
| `master_user_secret_kms_key_id` | 4 | No — fixed while management is on | Toggle managed password off, then on with the new key | Master password rotates; brief unmanaged window |
| `performance_insights_kms_key_id` | 6 | Undetermined | Likely disable → re-enable | No downtime, reboot or failover; but hold until the EOL transition passes |

---

## What remains open, and it is the expensive part

The snapshot-and-restore path is documented and reliable, and it is a **cutover with real downtime** — the restore produces a new cluster with a new endpoint, and every write between the snapshot and the switch is lost unless something carries it across. That is acceptable for `beta` and `demo`. It is the whole problem for `shared-001` and `atento-001`.

The zero-downtime shape for those two would be to stand up the new encrypted cluster, replicate into it continuously, and cut over when it is caught up — which is exactly the shape of the hypothesis, just at the cluster level instead of the instance level. For Aurora PostgreSQL the candidate mechanisms are native logical replication and AWS DMS. AWS itself points at both as the alternative when blue/green does not fit, naming "AWS Database Migration Service (AWS DMS)" and "self-managed logical replication" for high-write-volume major-version upgrades.

**That is a lead, not a verified path, and it should be the next round of this spike.** What has to be answered before anything is planned:

1. Does Aurora PostgreSQL 16 logical replication carry everything this database contains — sequences, large objects, DDL, materialized views? The blue/green limitations page documents each of these as a logical-replication gap, and those gaps are properties of PostgreSQL logical replication itself, not of blue/green. If they apply, the replica is not a faithful copy and the cutover is unsafe.
2. What is the actual cutover window with replication in place — the application's reconnect through the pooler, plus sequence synchronisation?
3. Does anything connect as the master user at runtime, or only for migrations and administration? This decides whether Finding 4's off/on toggle is invisible or user-visible.
4. Can the PI key be changed without a disable/re-enable, and does historical data survive? To be re-asked after the July 31 transition, against whatever the Database Insights documentation then says.
5. `deletion_protection = true` on every cluster — confirm the intended teardown order for the old cluster, since the flag has to come off deliberately and that is the irreversible step.

## What is safe to conclude now

The hypothesis is closed: instance-level encryption does not exist in Aurora, so the third-reader plan cannot be built. The shape of the idea survives — stand up the new thing, replicate, cut over, drop the old — but it has to operate on clusters.

The 14 references are not one piece of work. They are three, with different costs and different orders, and only one of them is cheap. Nothing here should be bundled into a single PR.

The two non-productive stacks (`beta`, `demo`) can take the documented snapshot-and-restore whenever wanted, and doing one of them first is the cheapest way to learn the real mechanics before touching a productive cluster.
