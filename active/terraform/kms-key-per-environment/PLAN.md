# PLAN — One KMS key per environment, with restrictive key policies

**Status: DELIVERED — every surface the Terraform stacks own is encrypted under its environment's own
key.** All fifteen stacks are on a dedicated task-execution role, every module mints its own
correctly-named key, and the account-wide `ecsTaskExecutionRole` no longer carries any per-stack SSM
policy. The last two surfaces outside a customer-managed key were the `sa-east-1` outbound registries,
closed 2026-08-19: both now read `KMS` under the replica of their linked cluster's key
(`mrk-416bffe4…`, `mrk-07429959…`), verified by reading the repository configuration back from AWS.
See the phase notes below for the per-stack history and the two cross-region blind spots that
step-3 exposed.

**What outlives the migration is destruction, not migration.** `4shark-master` no longer encrypts
anything; its `sa-east-1` replica is in `PendingDeletion` with AWS's own 30-day window running to
2026-09-18, and the primary in `us-east-1` stays `Enabled` until that replica is actually gone — AWS
refuses to delete a primary while a replica exists. Removing the primary from `shared-resources/kms.tf`
is therefore one small PR that cannot be written earlier, scheduled for 2026-09-21.

**App estate — measured live against AWS 2026-08-19, surface by surface.** RDS (four environments, each
on its own key), SSM (73 parameters), OpenSearch (both domains), S3 (four buckets on `aws:kms` with
Bucket Keys, and the pre-existing objects re-encrypted — the `kms-migration/` prefix is present in each),
CloudWatch Logs (83 groups) and ECR all sit on the per-environment keys. The twelve app log groups
without a key are AWS-service-created (`/aws/ecs/containerinsights/…`, `/aws/rds/cluster/…/postgresql`,
`/aws/lambda/…`), not module-owned.

**The ECR scope is TEN repositories, not the eight in `us-east-1`.** The `Build` workflow of each
productive stack dual-pushes, so `shared-001-app` and `atento-001-app` also exist in `sa-east-1`, feeding
the `app-outbound-*` Fargate stacks that run the same application image in that Region. They are
Terraform-managed and always were — the declaration is not in any stack but in
`modules/app_outbound_runtime/compute.tf`, which instantiates the same `modules/ecr` the migration
rewrote. **Searching the stacks for `aws_ecr_repository` and concluding they were unmanaged is the
mistake to avoid repeating**; a module can own a resource no stack file mentions. Both are live paths:
`atento-001-app` has carried images since 2026-04-22 and holds 237, `shared-001-app` since 2026-07-15 and
holds 87, and every productive build pushes to them.

**The key they need is already in `sa-east-1`, and an alias search is what hides it.** AWS requires the
key to live in the repository's Region, and `modules/app_outbound_runtime/kms.tf:33` creates exactly that
— an `aws_kms_replica_key` of the linked cluster's key, minted for the log groups (§ Phase 11) and
carrying the cluster's own key material. **It has no alias, so listing `sa-east-1` aliases returns only
`alias/auth-001` and the integrator keys and reads as "no app key here"**; `list-key-policies` against the
primary's `Replicas` is what answers the question. So no replication is owed — the two things missing are
the ECR statements in the replica's own policy (a replica's policy is independent and AWS never
synchronizes it from the primary) and an alias so the key is findable at all.

### Owed — the `sa-east-1` outbound registries

**Grant the replica ECR use, then adopt it, and RENAME in the same replace.** The repository is named
after the stack that PRODUCES the image (`local.image_name = "${var.primary_identifier}-app"`), not the
one that consumes it, so a registry serving `app-outbound-maqnelson` is called `shared-001-app` — which
reads as the primary stack having a São Paulo presence it does not have. ECR offers no rename: its API
carries `CreateRepository` and `DeleteRepository` and nothing between them. That is what makes the rename
cheap here rather than expensive — adopting the key ALREADY destroys and recreates the repository, so
changing the name costs nothing extra if both land in one replace. Doing them separately would pay the
empty-repository window twice.

**Step 1 — the key policy and the alias (PR #1029, `1 add, 1 change, 0 destroy` on both stacks, applied
2026-08-19).** `get-key-policy` against each replica in `sa-east-1` returns two `ecr.sa-east-1` hits —
the use statement and the grant — so the precondition step 2 depends on is confirmed live, not assumed
from a successful apply. The
ECR use + `CreateGrant` pair, scoped `kms:ViaService = ecr.sa-east-1.amazonaws.com`, plus
`aws_kms_alias.app_cluster` named `alias/${var.environment}` → `alias/app-outbound-maqnelson` and
`alias/app-outbound-atento-br`. The alias is named after the stack that OWNS it rather than the primary
it replicates, because an alias is a Regional resource and the primary's says nothing here. Both changes
are additive and must be applied and confirmed BEFORE step 2 — without the grant already live, the
create half of the replace fails after the destroy half has run.

**Step 2 — `force_delete = true`, alone (PR #1031, `0 add, 1 change, 0 destroy` on both stacks).** The
repositories hold images, so the replace in step 4 cannot destroy them while the guard is on. It lands
alone because Terraform issues the delete with the value already in STATE, not the one in the new
configuration — the same reason the app estate needed PRs #1019 and #1021 separated. The change is
Terraform-side only and alters nothing in AWS.

**Step 3 — the `app` repository, BEFORE the replace (PR #5359, merged into `develop`).** The image is
pushed by `app`'s Build, which composed one repository name and applied it to every registry in its
list, so a rename in `sa-east-1` left the push aiming at a repository that no longer exists — and ECR
does not create one on push. Each job now lists full repository paths, and the two deploy workflows
carried the same path hardcoded for the second Region's worker and runner. **Six references, not two**:
`build-image.yaml` ×2, `deploy-shared-001.yaml` ×2, `deploy-atento-001.yaml` ×2.

**The productive Build runs from `master`, and GitHub uses the workflow file of the ref that triggered
it — so step 3 sitting on `develop` does not protect step 4.** Either the replace waits for a release or
hotfix carrying it to `master`, or the refill is dispatched with `--ref` pointing at a branch that
already has it while `master`'s automatic push-triggered build stays broken until the release. That
choice is the engineer's.

**Step 4 — `kms_key_arn` on the outbound's `module "ecr"` plus the rename, in one replace.**

The window is the one the app estate already measured: the repository comes back empty and the outbound
stacks rest at `desired_count 0`, so nothing is trying to launch. The refill is the productive `Build`,
which pushes to both Regions on its own.

### Owed — the rule for creating a NEW outbound

**An outbound's registry can only be encrypted if the primary's key is already replicated into the
outbound's Region, so that check belongs in the creation path rather than in someone's memory.** Standing
up an outbound today creates its ECR through `modules/app_outbound_runtime` with no key, and nothing
notices — the repository is born `AES256` and stays that way until an audit finds it, which is exactly how
these two came to be missed. The replication is a precondition of the outbound, not a follow-up to it.

**The app ECR migration — three prerequisite applies, then one window per environment.** Encryption is
fixed at creation, so adopting the key REPLACES a repository and it comes back empty. Nothing already
running is affected: an image is pulled when a task launches, not while it runs, so what has to stop for
the window is only what STARTS tasks. Both schedule families are held at `DISABLED` through the window
(`lambda_scheduler_state`, `scheduled_task_state`) and released in the apply that follows the rebuild.
The four windows measured 5m19s (beta), 4m42s (demo), 3m54s (shared) and 3m53s (atento).

Three facts the sequence turns on, each of which costs a broken window if missed:

- **The rebuild is TWO dispatches per environment.** `<env>-app` comes from the `app` repository's
  `Build`; `<env>-connection-pooler` comes from the pooler image's own repository, with the same
  environment input. Dispatching only the first leaves the pooler repository empty, and nothing surfaces
  it until a pooler task next needs to launch.
- **A productive `Build` publishes to `us-east-1` AND `sa-east-1`**, so the `:latest` confirmation covers
  both Regions before the schedules are released.
- **The ECR lifecycle policies die with the repository and Terraform only notices on the next refresh**,
  so they are recreated by the release apply rather than the window apply.

**Read a surface against AWS before reporting it, never against this file.** A status line records the
intent at the moment it was written, and work that continues in a sibling plan never comes back to
update it — so a plan can describe a surface as pending long after it finished. That gap has already
produced a report claiming the app estate was untouched while five of its six surfaces were migrated.

### Retiring `4shark-master` — the dependency is SNAPSHOTS, not usage

Cryptographic use of the key ended between 10 and 15 August 2026, when the last predecessor cluster was
destroyed; the final events on it are a `Decrypt` and two `RetireGrant` from Performance Insights. **Usage
having stopped does not make the key removable** — a snapshot generates no event and still cannot be
restored without the key that encrypted it.

**Nothing depends on the key any more.** All seven snapshots were retired 2026-08-19, so `4shark-master`
can be scheduled for deletion whenever the engineer chooses. Five were straightforward — the three
`preupgrade-app-*-cluster-…` rollback points of the 30 May PostgreSQL upgrades (whose clusters no longer
exist), `onboarding-preteardown-20260717` (that database was removed deliberately and did not return), and
`setup-pre-dedicated-key-migration` (its re-encrypted twin lives on `alias/setup`). None covered a day
inside any current retention window.

**The other two were the atento backup window, and retiring them was a business decision rather than a
cleanup.** A re-provisioned cluster starts its backup history at zero, so `app-atento-001` — created 14/08
— carries five daily backups against a seven-day retention, and point-in-time recovery cannot reach past
its creation either (`EarliestRestorableTime` is the minute the cluster was born). Those two recovery
points of the predecessor were therefore the only route back to 13 August and to the morning of the 14th.
**PITR is bounded by `BackupRetentionPeriod`, not by a separate longer window** — seven days on every
database here, which is worth stating because the opposite is easy to assume.

What made the deletion right is that restoring `app-atento-001` is not an operation 4Shark would perform:
four countries work independently on that environment, each with its own team, so reverting the database
to fix one country would revert the other three. Recovery capacity that would never be exercised is cost
without benefit. **Read that as scoped to this environment** — it follows from the multi-country tenancy,
not from a general position on backups.

**A recovery point held by AWS Backup cannot be deleted through the RDS API.** `delete-db-cluster-snapshot`
refuses it outright (`AWS Backup snapshots cannot be deleted`); the vault owns it, so the call is
`backup:DeleteRecoveryPoint` against `<environment>-local`. Any snapshot whose identifier begins with
`awsbackup:` takes that path.

**Deleting a snapshot needs `rds:DeleteDBClusterSnapshot` / `rds:DeleteDBSnapshot`**, which the elevated
layer did not carry — terraform PR #1013 adds them. Enumerating instance snapshots needs
`rds:DescribeDBSnapshots`, added in #1012; before it the inventory reported five snapshots instead of
seven, and reported low, which is the direction that matters.

**Retirement is TWO stages separated by the deletion window, because the key is multi-Region.** AWS orders
them: *"To delete a primary key, you must schedule the deletion all of its replica keys, and then wait for
the replica keys to be deleted. The required waiting period for deleting a primary key begins when the last
of its replica keys is deleted."* Removing both `aws_kms_replica_key.master` and `aws_kms_key.master` in one
apply therefore fails — the primary would be scheduled while AWS still considers it replicated.

Stage one is **DONE** — terraform PR #1015 removed the replica and its alias from `shared-resources/kms.tf`
(`0 add, 0 change, 2 destroy`, applied 2026-08-19). The replica reports `PendingDeletion` in `sa-east-1`
with `DeletionDate` **2026-09-18**: the provider defaults `deletion_window_in_days` to 30 for
`aws_kms_replica_key`, so the schedule stays cancellable until that date. Stage two removes
`aws_kms_key.master`, its alias, and the now-unused `sa-east-1` element of
`data.aws_iam_policy_document.master_key` — **only once the replica is actually gone**, so it unblocks
on 2026-09-18 and not before.

**There is no `alias/auth002` key to retire, and the id recorded against that name belongs to something
else.** `6f7b8e40` in sa-east-1 is **`alias/aws/rds`** — AWS-managed, created 2019, and undeletable by
design (*"You can only schedule the deletion of a customer managed key. You cannot delete AWS managed keys
or AWS owned keys."*). The only auth-related aliases in that region are `alias/auth-001` and
`alias/backup-auth-001-local`. Eight manual `auth-001` snapshots did sit on the AWS-managed key — six from
December 2024, two from the 2026-07-03 upgrade — and were retired 2026-08-19 as versions nobody would roll
back to; the fifteen the database holds today are all on `alias/auth-001`. That cleanup freed no key.

**Integrator closing audit — 2026-07-27, live against AWS, surface by surface.** Three surfaces are on
the integrator's own key, verified rather than assumed: the twelve serving EBS volumes (each under its
own client's key, no cross-use), all 158 `/integrator*` SSM parameters (grouping by key yields exactly
one bucket per integrator, nothing on the AWS-managed key), and the four `integrator-<client>-redis001`
ElastiCache groups (`AtRestEncryptionEnabled: true`, own key each). **Three other surfaces are NOT, and
this plan never scoped them either way** — S3 deployment buckets and the 16 ECR repositories sit on
AES256 (SSE-S3/AWS-managed: encrypted, but no key policy to scope, so no per-integrator isolation), and
50 `/ecs/integrator-*` CloudWatch log groups carry no customer key at all. **Note the shape**: it is the
same one that produced the MongoDB miss — "the integrators are on their own key" standing in for a claim
nobody had checked surface by surface. All three were taken into scope the same day as **§ Phase 12**,
which carries their differing mechanics (one in-place, one forces a replace, one needs a data move) and
the three decisions they need before starting. The audit report is
`/tmp/interactive_report_integrator_kms_audit_20260727.html`.

**Why this plan was reopened, kept here because the mistake is the lesson.** It was marked COMPLETE on
2026-07-24 and that was wrong: "the integrators are on their own key" was read as covering everything an
integrator holds at rest, when the key's `kms:ViaService` scope was SSM and ElastiCache only. The
MongoDB hosts' EBS volumes were never on it, so the database storage — the largest body of customer data
the integrators hold — sat unencrypted while the plan claimed completion. A per-surface claim must name
its surfaces; "on its own key" is not a statement about a stack, it is a statement about a service.

**Progress 2026-07-27 — the data HAS moved; two steps remain, both irreversible-adjacent.** Twelve
replacement nodes (three per integrator) came up with their root volume encrypted under that
integrator's own key, each key's policy widened to permit use through EC2 — without which an encrypted
volume could not be created at all — and then all four replica sets were migrated onto them the same
day. Every client now serves entirely from the encrypted block; the old unencrypted trio is out of the
set and stopped, holding a frozen copy. Customer data is on encrypted volumes for the first time.

**The teardown is DONE too — 2026-07-27, same day.** The twelve retired instances and their twelve DNS
records are destroyed (terraform PR #848). The engineer chose to proceed without the record-count gate,
which is recorded here as a decision rather than an omission: MongoDB's initial-sync contract is what
backs "the new nodes have all the data" and it is a strong mechanical guarantee, but nobody counted both
sides independently.

**What that decision cost is smaller than it looks, and the reason matters.** The twelve root volumes
carry `delete_on_termination = false`, so they survived the terminate as `available` — 12 × 40 GB — and
the eight snapshots are still there. The data baseline for a count is therefore intact; what the
teardown removed is the CHEAP path to it (start a stopped instance and read it). Recovering it now means
attaching a volume or restoring a snapshot. **The one thing left on this surface is deciding when those
volumes go**, and that decision ends the possibility of the count. See § "The integrator MongoDB EBS
gap" below for the verified state, both id tables, and the structural findings the migration surfaced.

Absorbs and replaces `active/terraform/kms-migration/PLAN.md` (deleted). Sources:
`active/spike/kms-key-per-environment/SPIKE.md`, `active/spike/aws-engineer-staging-tier/SPIKE.md`,
direct AWS documentation research, and a live SSM rekey probe (2026-07-17).

## Goal

Make a leak in one environment unable to reach another's data at rest.

## Two facts that decide the whole shape

**1. A separate key isolates nothing on its own.** Authorization to a KMS key is granted by its key
policy, and the policy Terraform writes by default is a single statement — the account principal
with `kms:*` — which delegates every decision back to IAM. AWS, verbatim: *"This default key policy
statement allows the account to use IAM policies to delegate permission for all actions (kms:*) on
the KMS key."* So any principal holding `kms:Decrypt` on `"*"` in IAM opens every key with that
shape. **4Shark's six existing `backup-<stack>-local` keys have exactly that shape today**
(`modules/cross_region_backup/main.tf`, `local.kms_policy`) — they are one-key-per-stack already and
they isolate nothing. Count without policy is theatre.

**2. The restrictive policy names a role — and the role does not exist yet.** Every stack attaches
its SSM policy to the SAME role:

```hcl
resource "aws_iam_role_policy" "ecs_ssm_read" {
  name = "beta-001-ssm-read"
  role = "ecsTaskExecutionRole"          # <-- identical in every stack
```

Permissions accumulate on a role, so that one role today holds `ssm:GetParameters` across every
environment's path prefix plus `kms:Decrypt` on the shared key — **beta's tasks can already read
productive parameters.** And a per-stack key policy cannot be written while the role is shared:
naming `ecsTaskExecutionRole` in beta's key policy would grant every stack's tasks access to beta's
key, and vice versa.

**Therefore the role split comes first.** It is not a parallel task — it is the prerequisite that
makes the policy expressible at all.

**Corrected 2026-07-17 — this section previously said "all six stacks" and named six files. It is
eleven, and the role does more than the name says.** Verified by grep across the repo and against
the live role:

- **Eleven stacks declare a `<stack>-ssm-read` policy on it**: the six above plus `integrator-almaviva`,
  `integrator-atento`, `integrator-commcenter`, `integrator-maqnelson`, `integrator-redebrasil`. The
  live role carries exactly eleven such inline policies, confirming the count.
- **Fifteen stacks name the role in a task definition** — the eleven plus `app-outbound-atento-br`
  and `app-outbound-maqnelson` (which have no SSM policy but do run tasks under the role).
- **It is the `task_role_arn` as well as the `execution_role_arn`**, in nearly every task definition.
  So it is not only the startup identity that fetches secrets and pulls images — it is the runtime
  identity the application code itself assumes. Splitting it is two changes wearing one name.

**Three inline policies on it existed in no `.tf` at all** — created by hand in the console (their
`VisualEditor0`/`VisualEditor1` Sids give them away), so nothing recorded that the role depends on
them. A per-stack role built from the Terraform alone would have dropped all three silently:

| Policy | What it does | Disposition |
|---|---|---|
| `ECSExecPolicy` | `ssmmessages:*` — what makes ECS Exec (`bin/ecs run`) work. It is a **task-role** permission | Imported (PR #738). Must be reproduced per stack |
| `target-alb` | `elasticloadbalancing:Register/DeregisterTargets` | Imported (PR #738). **Possibly dead** — target registration is normally done by the ECS service via its service-linked role, not the task role. Settle it at beta's cutover |
| `ecs-secret-access-beta-app001` | Decrypt of two Secrets Manager secrets | **Dead — deliberately not imported.** The secrets are in no `.tf`; the live `beta-001-web:222` task definition reads SSM only, zero Secrets Manager; neither secret has been accessed since 2026-02 while beta runs continuously. Not reproduced on beta's role; dies with the shared role |

## The design

### Scope — this design covers the six stacks on `4shark-master`, and only those

**Corrected 2026-07-17.** This plan was written as if the estate encrypted its SSM under one key. It
does not. There are two populations, and the second is out of this design's reach:

| Population | Stacks | Key | Reachable by this design? |
|---|---|---|---|
| On `4shark-master` | `app-beta-001`, `app-demo-001`, `app-shared-001`, `app-atento-001`, `setup`, `onboarding` | `mrk-fa0cda24…`, **customer-managed**, us-east-1 | **Yes** — everything below applies. (Plan-start landscape; `onboarding` has since migrated to `alias/onboarding` — surface 2 DONE 2026-07-22.) |
| On the AWS default SSM key | `integrator-almaviva`, `integrator-atento`, `integrator-commcenter`, `integrator-maqnelson`, `integrator-redebrasil` | `b16e449a…`, **AWS-managed**, sa-east-1 | **Yes — decided 2026-07-20** (see below) |

The second key is `alias/aws/ssm` for sa-east-1 — `describe-key` returns `"KeyManager": "AWS"` and
*"Default key that protects my SSM parameters when no other key is defined"*. **An AWS-managed key
does not accept a custom key policy**, so the two-statement policy below cannot be written for it.
The five integrators cannot be isolated by editing that key; isolating them means first moving them
onto customer-managed keys.

**The open question below is now DECIDED — 2026-07-20 — and the driver is access delegation, not
just decrypt isolation.** The earlier framing asked whether the five were "exposed" today and noted
that, since an AWS-managed SSM key only decrypts *via SSM*, the per-stack role split alone might
isolate them and no key work would be needed. That test answered the narrow question "is a secret
leaking." The engineer's actual goal is broader and it settles the decision toward customer-managed
keys regardless: **a dedicated key per integrator, with a key policy that names only that integrator's
role, is what makes per-integrator ACCESS DELEGATION expressible** — granting an engineer who owns one
client (e.g. Santiago owns Atento) the ability to reach and run only that client's integrator, and
nothing else. An AWS-managed key cannot carry that policy, so the role split alone cannot express the
boundary the engineer needs. The key work therefore exists, and its scope is one customer-managed key
per integrator. (This is the enabler for the restricted-engineer tier tracked in
`active/spike/aws-engineer-staging-tier/` — this plan builds the keys and policies; the actual IAM
grant to a specific engineer is that tier's follow-up, not this work.)

### Six keys — the count falls out, it is not chosen

The policy names the role. The role is per stack. Therefore the key is per stack. No category
judgement is applied and none has to be re-applied when an environment's classification changes.

| Key | Names (usage) |
|---|---|
| beta-001 | `beta-001` task role |
| demo-001 | `demo-001` task role |
| shared-001 | `shared-001` task role |
| atento-001 | `atento-001` task role |
| setup | `setup` task role |
| onboarding | `onboarding` task role |

`4shark-master` retires once nothing uses it.

**This is already the house pattern.** `auth-001` has its own key (`alias/auth-001`, sa-east-1 —
`auth-001/secrets.tf:4`, `auth-001/iam.tf:49`) and never used the master. The six
`backup-<stack>-local` keys are one per stack. The master is the exception, not the rule.

**Why six and not two or three.** Two AWS guidances point at different splits and neither alone
covers the estate: SEC08-BP02 (classification — *"create one AWS KMS key for encrypting production
data and a different key for encrypting development or test data"*) would put `shared-001` and
`atento-001` on one key despite `atento-001` being a dedicated-infrastructure client; the silo model
(tenancy — *"Each tenant will also have a separate AWS KMS key for encryption"*, triggered by
*"large customers require dedicated clusters"*) would put `beta-001` (fabricated data) and
`demo-001` (real client data) together. Per-role is the only rule that satisfies both without
anyone re-deriving a category later.

### The key policy — two statements, never `kms:*`

Administering a key and using a key are different things. AWS: *"Key administrators have permissions
to manage the KMS key, but do not have permissions to use the KMS key in cryptographic
operations."* The default collapses them into one `kms:*`, and that collapse is what leaks.

```hcl
# Administration — the account principal, and NO cryptographic action.
# The account root is the only principal that cannot be deleted; it stays so the key can
# never become unmanageable. AWS: "suppose you create a key policy that gives only one user
# access to the KMS key. If you then delete that user, the key becomes unmanageable and you
# must contact AWS Support to regain access."
{
  Sid       = "Key administration"
  Effect    = "Allow"
  Principal = { AWS = "arn:aws:iam::405749097490:root" }
  Action    = ["kms:Create*", "kms:Describe*", "kms:Enable*", "kms:List*", "kms:Put*",
               "kms:Update*", "kms:Revoke*", "kms:Disable*", "kms:Get*", "kms:Delete*",
               "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion"]
  Resource  = "*"
}

# Usage — only this stack's task role, only cryptographic actions.
{
  Sid       = "Allow use of the key"
  Effect    = "Allow"
  Principal = { AWS = "arn:aws:iam::405749097490:role/<stack>-task-role" }
  Action    = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey*", "kms:ReEncrypt*",
               "kms:DescribeKey"]
  Resource  = "*"
}
```

The account principal administers and never decrypts. Because the policy never allows a
cryptographic action to the account principal, **an IAM policy granting `kms:Decrypt` on `"*"` no
longer opens the key** — IAM can only delegate what the key policy allows it to delegate. AWS
Prescriptive Guidance states the rule directly: *"Do not use `kms:*` for actions in IAM or key
policies because this gives the principal permissions to both administer and use the key."*

Terraform's `aws_kms_key.policy` is an in-place update (`PutKeyPolicy`) — changing it never recreates
a key, and it is reversible.

**A grant statement may also be required** for services that use grants on the engineer's behalf
(`kms:CreateGrant` / `ListGrants` / `RevokeGrant` with
`Condition = { Bool = { "kms:GrantIsForAWSResource" = true } }`). Confirm per service at
implementation rather than adding it pre-emptively.

### Regional, not multi-region

AWS: *"we recommend that you create a multi-Region key only when you plan to replicate it"* and
*"For most data security needs, the Regional isolation and fault tolerance of Regional resources
make standard AWS KMS single-Region keys a best-fit solution."* Nothing in `sa-east-1` uses
`4shark-master`'s replica — the only `sa-east-1` stacks are `auth-001` (own key) and
`app-outbound-atento-br` (no SSM, no RDS, no KMS at all). Cross-region RDS copy does not need one
either: *"you must specify a KMS key valid in the destination AWS Region. It can be a Region-specific
KMS key, or a multi-Region key."* The estate's own `cross_region_backup` proves it — paired regional
keys, not a multi-region key.

One-way door worth naming: *"You cannot convert an existing single-Region key to a multi-Region
key."* Regional is the choice that stays reversible-by-recreation.

## What the shared key protects, and what rekeying each costs

| Service | Where | In-place rekey? | Evidence |
|---|---|---|---|
| **SSM SecureString** | six stacks' `ssm.tf` | **Yes** — probed live | Key changed `alias/aws/ssm` → `alias/4shark-master`, tier preserved, **version 1 → 2**, value decrypted intact (2026-07-17). AWS documents `Overwrite`+`KeyId` only for tier conversion, never for same-tier rekey — settled by probe, not by doc. |
| **Secrets Manager** (pooler userlist) | four `app-*/connection_pooler.tf` | **Yes** — documented | *"When you change the encryption key, Secrets Manager re-encrypts AWSCURRENT, AWSPENDING, and AWSPREVIOUS versions with the new key."* Trap: *"If you don't have kms:Decrypt permission to the previous key ... the existing versions are not re-encrypted."* |
| **RDS** | six stacks' `rds.tf` | **No** | *"Once you have created an encrypted DB instance, you can't change the KMS key used by that DB instance."* Path: snapshot → copy under new key → restore. Downtime per instance. |
| **OpenSearch** | `app-shared-001/opensearch.tf:46`, `app-atento-001/opensearch.tf:46` | **No — domain replacement** | *"Encrypted OpenSearch Service domains don't support manual key rotation."* Provider marks `encrypt_at_rest.kms_key_id` **`ForceNew`**; provider docs: *"If you change the kms_key_id, Terraform will also recreate the domain, potentially causing data loss."* AWS documents **no** key-change migration path and **no** downtime figure. |

**The SSM version bump is the one caveat AWS does not document.** Anything pinning a parameter
version must be checked before rekeying that stack.

## Sequence

Each phase is its own PR. Phases 1–4 are complete and coherent on their own.

### Phase 1 — Import `4shark-master` into Terraform — **DONE** (PR #736, merged 2026-07-17)

Applied and verified: `0 added, 1 changed, 0 destroyed` (state-only — `deletion_window_in_days` and
`bypass_policy_lockout_safety_check` are creation/destruction-time arguments), confirming plan
returned "No changes", and the live replica policy was re-read after the apply and diffed byte-for-byte
against its pre-apply copy. Nothing in AWS changed.

Alongside it, **PR #738** brought the shared role's two console-created inline policies under
Terraform (`ECSExecPolicy`, `target-alb`) — see the table in fact 2. No-change plan; no apply.

### Phase 1 (original scope, for the record) — Import `4shark-master` into Terraform

Created by CLI; no resource manages it. Prerequisite regardless of anything below. Create
`shared-resources/kms.tf` with `aws_kms_key` + `aws_kms_alias` matching the live config, import both,
confirm a no-change plan. Multi-region key, `mrk-fa0cda243274491784fc7b39bead5a03`, alias
`alias/4shark-master`, primary `us-east-1`, replica `sa-east-1`, policy allowing
`rds.{region}.amazonaws.com` + `secretsmanager.{region}.amazonaws.com`.

Its description (*"4Shark master encryption key - all environments and services"*) becomes false as
stacks leave. Correct it as they do.

### Phase 2 — Split `ecsTaskExecutionRole` into a role per stack

**The load-bearing phase.** Without it no per-stack key policy is writable, and the cross-environment
read stays open regardless of how many keys exist.

Give each stack its own role holding only that stack's grants. Touches each stack's `ssm.tf` and its
ECS task definitions (**both** `execution_role_arn` and `task_role_arn` — see fact 2).

**Corrected 2026-07-17 — the apply is NOT the deploy, and that is worse, not better.** This section
previously said changing the role on a task definition replaces the service's tasks. It does not.
`modules/ecs_service/main.tf:152-157` sets `ignore_changes = [desired_count, task_definition,
load_balancer]` **unconditionally** — the comment names CodeDeploy, but the block is not conditional,
so it holds for every service. The apply therefore registers a new task-definition revision that the
running service never adopts. Nothing redeploys.

**The cutover happens at the next application deploy, and it happens by inheritance.** The deploy
action (`app/.github/actions/deploy-ecs/action.yaml:65-97`) runs `describe-task-definition
--task-definition $FAMILY` — a bare family name, which resolves to the latest ACTIVE revision
(verified live: `beta-001-web` resolved to 223 while the service ran 222) — then deletes only
metadata (`revision`, `status`, `taskDefinitionArn`, …), swaps the image and command, and
re-registers. It never writes `executionRoleArn` or `taskRoleArn`, so **those are inherited from
whatever revision Terraform last left behind.**

**So the risk does not disappear at apply time; it detaches from it.** A missing permission surfaces
at whoever runs the next deploy of that environment — possibly days later, possibly a different
engineer, with nothing connecting the failure to this change.

**Therefore the apply and the deploy are ONE step, run together, watched.** Apply, then immediately
trigger that environment's deploy so the change and its verification stay coupled. This is the
standing procedure for every environment in the table below, with one addition for the productive
ones.

**Productive environments — check the Sidekiq queue before deploying.** A deploy runs
`sidekiqctl quiet`, pausing workers for 5–10 minutes while the queue keeps receiving jobs. On top of
an already-heavy queue this spikes Redis memory and can cause an outage. Check the depth first and
hold the deploy until it drains if it is heavy; deploy freely at normal levels. This is the only
thing that ever makes a 4Shark deploy wait (`app/CLAUDE.md` § Deploy) — it applies to
`app-shared-001` and `app-atento-001`, not to beta or demo.

#### 2a — Create the roles (additive, zero risk)

Create each stack's role and policies while **nothing references them**. Nothing redeploys, no
behavior changes. This also unblocks Phase 3: a KMS key policy must name a principal that exists.

#### 2b — Cut over, one environment at a time, in this order

The order is chosen so each environment pays for the next one's safety. Every exception found in an
earlier environment is already handled by the time a later one is touched, so the environments that
must not break are the ones with the fewest unknowns left:

**Step 1 (`app-beta-001`) is DONE and verified — 2026-07-17.** PR #740 created the role (`5 to add,
0 to change, 0 to destroy`; the service stayed on its revision, proving the additive claim). PR #741
pointed the services at it (`9 to add, 1 to change, 9 to destroy` — the nine task definitions are
*replaced*, because both role fields are `# forces replacement`). The deploy then ran and the service
moved 222 → 225 carrying the new role in both fields; the engineer confirmed by logging in to the
front end.

**The nine "destroys" are safe, and the reason generalizes — check it per stack rather than assuming
it.** Terraform's state holds a revision the service is not running: it registers one, the GHA deploy
later registers its own on top, and `ignore_changes` keeps the service on the deploy's. So the replace
deregisters an unused revision. Verified on all nine before applying (web: state 223 / service 222;
runner 83/82; cleansing 122/121; commission 214/213; tiger-shark 68/22). **If a stack ever has state ==
running revision, the replace deregisters the revision the service needs to launch replacement tasks.**
Confirm before every apply.

**What the beta cutover proved, each by a different mechanism** — reuse these as the per-stack
verification rather than inventing new ones:

| Permission | Proven by |
|---|---|
| `<stack>-ssm-read` + `kms:Decrypt` | The app **booted** — it reads 16 SecureString parameters to start |
| `AmazonECSTaskExecutionRolePolicy` | Image pulled from ECR, logs written |
| `iam:PassRole` (deploy user) | `register-task-definition` succeeded — this is the gate that AccessDenies |
| `<stack>-ecs-exec` | `ExecuteCommandAgent: RUNNING` on the task — the agent cannot connect without `ssmmessages` |
| The whole stack, end to end | Engineer logged in to the front end (auth + database + Redis) |

**`target-alb` — SETTLED and removed, 2026-07-17 (PR #752).** It is dead: target registration is done
by the ECS service-linked role, never the task role. AWS, verbatim ([ECS ALB docs](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/alb.html)):
*"Amazon ECS requires the service-linked IAM role which provides the permissions needed to register
and deregister targets with your load balancer when tasks are created and stopped."* The web service
registers through `modules/public_alb`'s blue/green role (`ecs.amazonaws.com`), and the workers have no
load balancer. All three copies were removed (shared role, beta, demo — `1 destroy` each, verified: the
policy is gone from all three roles, the rest of each role intact) and the per-stack template no longer
includes it. **The remaining 13 stacks' roles carry only `<stack>-ssm-read` + `<stack>-ecs-exec` +
the AWS managed policy** — no `target-alb`.

**Beta is COMPLETE — 2026-07-17.** Four PRs, each verified before the next:

| PR | What | Plan | Verified by |
|---|---|---|---|
| #740 | Create the role | `5 add, 0 change, 0 destroy` | Service stayed on its revision — the additive claim, proven |
| #741 | Services → new role | `9 add, 1 change, 9 destroy` | Deploy ran; service 222 → 225 on the new role; engineer logged in to the front end |
| #742 | Scheduled tasks → new role | `4 add, 5 change, 4 destroy` | Ran `attachment-expirator` by hand: `exitCode 0`. No service appeared in the plan — zero downtime, proven by the plan, not asserted |
| #744 | Drop `beta-001-ssm-read` from the shared role | `0 add, 0 change, 1 destroy` | The shared role went from 14 inline policies to 13, beta's gone; then a **fresh** task launched after the deletion read its parameters and exited 0 |

**The last check is the one that matters and it generalizes**: a running service proves nothing after
this step — it already read its parameters at startup. Launch a NEW task after the deletion. That is
what distinguishes "still up" from "no longer depends on the shared role".

**Two things beta surfaced that were in no plan, and both would have bitten a productive stack:**

1. **A tenth consumer.** The scheduled tasks never deploy, so they would have sat on the shared role
   forever while every service cut over — and step 3 would have killed them at 4am, unwatched. Beta's
   set includes the LGPD anonymization cron. Count the crons, not just the services.
2. **Rollback to a pre-cutover revision no longer starts.** Old revisions still name the shared role,
   so once its policy is gone they cannot read the parameters. The deploy's own rollback is fine (it
   targets the revision before the next deploy, which carries the new role). Accepted on beta —
   recovery is to deploy forward. **This is a fresh decision for each productive stack, not a
   precedent.**

**Beta's residual, non-blocking**: the deploy user still holds `iam:PassRole` on the shared role
(`iam_deploy_user.tf:28`) — not the leak this plan targets, and dropping it may affect the workflow's
rollback path (unverified). And `target-alb` is still unproven.

**Step 2 (`app-demo-001`) IN PROGRESS — 2026-07-17.** The beta script replicated cleanly: role
created (PR #746, `5 add`), services pointed at it (PR #747, `9 add, 1 change, 9 destroy` — the nine
task-definition replaces, verified per service that the deregistered revision was NOT the running one),
deploy ran, web moved 125 → 128 on the new role, `ExecuteCommandAgent: RUNNING`. Demo carries real
data and is the last gate before productive, but the catalog flags it `productive: false`, so no
Sidekiq-queue gate applied (that is `shared-001` / `atento-001` only). **Remaining for demo**: scheduled
tasks (step "2b-cron") and step 3 (drop `demo-001-ssm-read` from the shared role) — same shape as beta,
same order.

**Scheduled tasks DONE — 2026-07-17 (PR #749, `4 add, 5 change, 4 destroy`).** No service in the plan
(only reads); ran `attachment-expirator` by hand, `exitCode 0`.

**`app-demo-001` COMPLETE — 2026-07-17.** Step 3 applied (PR #750, `0 add, 0 change, 1 destroy`): the
shared role went from 13 inline policies to 12, demo's gone; a fresh task launched after the deletion
read its parameters and exited 0. Two of fifteen stacks done (`beta-001`, `demo-001`); the beta script
replicated onto demo with zero new findings.

| Order | Stack | What it is for | Cost of a mistake |
|---|---|---|---|
| 1 | `app-beta-001` | **DONE 2026-07-17.** Found every gap: the tfvars hardcoding, both `iam:PassRole` gates, the `ignore_changes` inheritance chain, and one dead policy | Nothing |
| 2 | `app-demo-001` | **COMPLETE 2026-07-17 (PRs #746/#747/#749/#750).** Same script, zero new findings | Low, visible — real data, non-productive |
| 3 | `setup` | **COMPLETE 2026-07-17 (PRs #754/#755/#757).** Different shape, checked not assumed: single web service, no scheduled tasks, own deploy repo (`4shark/setup`, master). Web moved to the new role (rev 27), `ExecuteCommandAgent RUNNING`. **The fresh-task-after-removal probe beta/demo used does NOT apply here** — that probe exists to catch a hidden second consumer (the cron), and setup has none; proof is service-on-new-role + the role's own `setup-ssm-read` intact + nothing else consuming the removed shared grant. Role template already enxuto (3 policies, no `target-alb`) | Real, non-productive |
| 4 | `onboarding` | **COMPLETE 2026-07-17 (PRs #759/#760/#762).** Web + sidekiq, no scheduled tasks, own deploy repo (`4shark/onboarding`, master). Both cut over via deploy inheritance (web rev 16, sidekiq rev 13, both on the new role). State was BEHIND the running revision here (state 10/7, running 14/11) — re-checked before applying, so the replace deregistered old unused revisions. `ExecuteCommandAgent` not exercisable (the stack rests at desired 0), but the successful blue/green deploy proves the runtime role; same self-sufficiency proof as setup (no second consumer) | Real, non-productive |

**All four non-productive stacks are done. The shared role is down to 9 inline policies** (was 14): `atento-001-ssm-read`, `shared-001-ssm-read`, the five `integrator-*-ssm-read`, `ECSExecPolicy`, and the dead `ecs-secret-access-beta-app001`. **Next is the productive frontier — `shared-001` and `atento-001` — where the Sidekiq-queue gate applies for the first time and the pre-cutover-rollback consequence becomes a per-stack conscious decision, not an automatic accept.**

**`app-shared-001` IN PROGRESS — 2026-07-17 (first productive stack).** Step 1 (role, PR #763) and step 2 (services → new role, PR #766, `10 add, 1 change, 10 destroy`) merged and applied. The verifying deploy is the first time the productive Sidekiq-queue gate ran for real: first check HOLD (a transient burst — samples 3-4 caught 2 then 14 executing, enqueued stayed 0, drained by sample 5), re-ran to a clean GO (0/0 across 10 samples), then deployed `deploy-shared-001.yaml` (run 29601996934, success). Cutover verified after the deploy, not the apply: web moved 120 → 123 on `shared-001-ecs-task-execution-role`, workers system/user/commission at rev 108 and deal-indexation at 61 all on the new role (both `executionRoleArn` and `taskRoleArn`). **Step 2b (scheduled tasks) DONE — PR #768** (`7 add, 8 change, 7 destroy` planned; applied `7 add, 1 change, 7 destroy` — the 7 schedule updates resolved no-op because the module targets the task-def by family, `replace(...arn, "/:\\d+$/", "")`, so the family string is unchanged; benign, same module beta/demo used). All 7 crons on the new role; ran `attachment-expirator` by hand, exitCode 0.

**`app-shared-001` COMPLETE — 2026-07-17.** Step 3 applied (PR #769, `0 add, 0 change, 1 destroy`): `shared-001-ssm-read` dropped from the shared role, which went from 9 inline policies to 8. Before step 3, verified every launchable task-def is on the new role — the 5 at-rest services (runner/migration/cleansing/commission-white-shark/commission-tiger-shark) included, not just the running ones. After the deletion, launched a fresh `attachment-expirator` to prove the dedicated role reads SSM through its own policy, not the shared one. The productive pre-cutover-rollback consequence was accepted as a conscious decision (recovery is deploy-forward). First productive stack done; the Sidekiq-queue gate ran for real (one HOLD on a transient burst, then GO). **Next: `app-atento-001`, the second and last productive stack (dedicated client infra), then the residual non-productive items.**

**`app-atento-001` IN PROGRESS — 2026-07-17 (second productive stack).** Structural difference confirmed and handled: this is a parallel compute-only rebuild mid-migration, but the deploy IAM was already migrated in (iam_deploy_user.tf live here), and the sa-east-1 payroll is a SEPARATE stack (`app-outbound-atento-br`), so app-atento-001's role split covers only the 9 us-east-1 services — same shape as shared-001. Step 1 (role, PR #770, `4 add`) and step 2 (services → new role, PR #772, `9 add, 1 change, 9 destroy`) merged and applied. The "replace is safe" check passed on all 9 (state revision uniformly one ahead of running). Verifying deploy: engineer fired `deploy-atento-001` manually (run 29611028995, success) while the queue check was mid-window (9/10 clean); cutover verified — web 35→38, workers 33→36, all on `atento-001-ecs-task-execution-role`. Step 2b done (PR #773, `7 add, 1 change, 7 destroy`; `attachment-expirator` exitCode 0). **`app-atento-001` COMPLETE — 2026-07-17.** Step 3 applied (PR #774, `0 add, 0 change, 1 destroy`): `atento-001-ssm-read` dropped from the shared role. Before step 3, verified every service (running + at-rest) and all 7 crons on the new role; after, a fresh `attachment-expirator` proved SSM read via the dedicated role's own policy. **Both productive stacks are done.**

**Mid-apply lock incident on step 3 (recovered clean).** The first step-3 apply died when the MFA token expired MID-OPERATION: `DeleteRolePolicy` got 403 (rejected — policy NOT deleted), state save got ExpiredToken (S3 state NOT updated), and the state lock release failed, leaving an orphaned lock (`63e4207a-…`, OperationTypeApply, held by this machine). Diagnosis before any write: nothing deleted, nothing forked — AWS and S3 state both still had the policy, so NOT the `state push errored.tfstate` case. Recovery: re-elevate MFA → `force-unlock` the orphaned self-held lock (known ID, no concurrent process) → fresh plan re-confirmed `1 to destroy` (consistency proven) → re-apply succeeded. **Lesson: a mid-apply MFA expiry can strand the lock even when nothing was applied; force-unlock is the correct recovery ONLY after confirming the state was not forked (delete rejected + state save failed = both sides unchanged = consistent). The apply that dies before ANY resource mutates does not need `state push`.**

**The two `app-outbound-*` stacks — COMPLETE — 2026-07-17. This is where the step-3 drops bit twice.** The sa-east-1 payroll/runner workers name the shared role in their task defs but hold no SSM policy of their own — they inject ANOTHER stack's parameters cross-region as `valueFrom` secrets. So a productive stack's step-3 (dropping its `<stack>-ssm-read` from the shared role) orphans its cross-region outbound sibling unless that sibling is cut over first. Both were missed initially:

- **`app-outbound-atento-br`** injects `/atento-001/*`. `app-atento-001`'s step-3 (PR #774) dropped `atento-001-ssm-read` without accounting for it → the payroll worker would fail secret-resolution on next scale-up (latent: desired 0). Caught same session; `atento-001-ssm-read` RESTORED on the shared role (PR #776) to stop the bleed, then the proper split: dedicated role + both task-defs (PR #777, `6 add, 2 destroy`, ssm-read scoped to `/atento-001/*` + MRK), deploy-user PassRole on `app-atento-001`'s deploy user (PR #778, `1 change`). Cutover via targeted `update-service` (payroll→:76, runner→:75 — the services were pinned to old-role revisions by `ignore_changes`, not a full productive deploy). Then re-dropped `atento-001-ssm-read` (PR #779, `1 destroy`) AFTER an exhaustive sweep: all 9 live services + 7 crons + web-migration + pooler (own role) + both outbound services confirmed on dedicated roles.
- **`app-outbound-maqnelson`** injects `/shared-001/*` (via `../modules/shared_001_task_config`, shared with `app-shared-001`). `app-shared-001`'s step-3 (PR #769, a PRIOR session) had ALREADY dropped `shared-001-ssm-read` → this worker was latently broken since then (desired 0 masked it; service events showed only steady-state, no launch failures). Fixed by the split: dedicated role + both task-defs (PR #780, `6 add, 2 destroy`, ssm-read scoped to `/shared-001/*` + MRK), deploy-user PassRole on `app-shared-001`'s deploy user (PR #781, `1 change`). Cutover via targeted `update-service` (payroll→:6, runner→:5). NO step-3 drop for maqnelson — it never had its own grant on the shared role (it rode `shared-001-ssm-read`, already gone). Audit confirmed maqnelson was the LAST `/shared-001/*` orphan: `shared_001_task_config` is used by only `app-shared-001` (own services verified on the dedicated role) and this stack.

**Lesson: step-3 must sweep every task-def that NAMES the shared role AND reads the dropped prefix, INCLUDING cross-region outbound siblings in another stack.** The productive-stack completions above verified only the same-stack us-east-1 services/crons; the sa-east-1 outbound consumer was the blind spot both times. The proven cutover for a desired-0 service is a targeted `update-service` to the new-role revision — not a full productive deploy (the service is pinned to the old revision by `ignore_changes`, so a precise repoint heals it with zero blast radius).

**The `integrator-*` stacks — DONE — 2026-07-24.** The design decision landed on customer-managed keys, one per integrator, and the shared `modules/integrator` now OWNS that key (`kms.tf`): every stack instantiating the module is born with `alias/integrator-<client>`, so the key can neither be omitted nor misnamed for a new integrator — it exists by construction rather than by being passed in. Each integrator's dedicated task-execution role (also module-owned) carries `kms:Decrypt` scoped to that one key, and the SSM parameters were rekeyed onto it, so nothing reads through the account-wide AWS-managed key any more. The key policy is scoped by service (`kms:ViaService`, within this account — ssm and elasticache as delivered here, plus ec2 from 2026-07-27) rather than by naming principals — which is what makes per-integrator ACCESS DELEGATION expressible: granting an engineer who owns one client the ability to reach only that client's integrator is a matter of scoping their `ssm:GetParameters` to that prefix. The same key also encrypts that integrator's Redis at rest. Delivered as part of the integrator module absorption (see `completed/terraform/integrator-module-absorption/`). **What this did NOT cover when it was written: the integrator's MongoDB hosts.** As delivered, the key's `kms:ViaService` scope was ssm + elasticache, so the database nodes' EBS volumes were outside it and unencrypted — "the integrators are on their own key" was true of their parameters and their cache, not of their database storage. **Closed 2026-07-27**: each key's policy gained an EC2 via-service statement plus `kms:CreateGrant`, and the nodes were re-provisioned onto encrypted volumes under it. See § "The integrator MongoDB EBS gap" below for the verified state and what is still owed.

**Remaining — every surface is now encrypted; what is owed on the integrator MongoDB hosts is verification and cleanup, not encryption.** The four non-productive app stacks, the two productive ones, `setup`, `onboarding`, both `app-outbound-*` and the five `integrator-*` are all on a dedicated role with their parameters and Redis on a dedicated key. The integrator database hosts' block storage joined them on 2026-07-27 — the data was migrated onto encrypted volumes the same day the capacity was built. What is left there is the engineer's record-count gate and the teardown of the old nodes; see the next section.

### The integrator MongoDB EBS gap — CLOSED 2026-07-27 (migrated + torn down); only the orphaned-volume deletion remains

**The original finding — the volumes were unencrypted, verified live 2026-07-24** (`aws ec2
describe-volumes`, sa-east-1), kept as written because it is what the section exists to answer: all
twelve root volumes of the four active integrators' replica-set nodes reported `Encrypted: false` and
`KmsKeyId: null` — `integrator-{almaviva,atento,commcenter,maqnelson}-mongo00{4,5,6}`. This is not a
wrong-key finding: there is no key at all, so the customer data those nodes hold sits on disk in the
clear. The three `4client-redebrasil-mongo00{3,4,5}` volumes are unencrypted too, but that stack is the
frozen cancelled-contract one and goes away in its teardown, not here.

**The module never asked for encryption.** `modules/integrator/mongodb.tf` declares each node's
`root_block_device` with `volume_size` / `volume_type` / `delete_on_termination` / tags and no
`encrypted` and no `kms_key_id`, so every node inherits the AMI/account default — which is off. The
per-integrator key the module now owns (`alias/integrator-<client>`) is scoped `kms:ViaService` to
**ssm and elasticache**; EBS is not in that policy, so even the key that exists today could not encrypt
these volumes without a policy change.

**Why it was missed rather than deferred.** The EBS surface WAS identified and deliberately deferred
early in this plan — "*encrypting the EBS volumes REPLACES them (a volume cannot be encrypted in
place), so that is a separate, deliberate operation*" — but that deferral was written in the `vpn`
context and only ever executed for `vpn` (PRs #793–#796, where the Mongo host was replaced by an
encrypted, keyless one). The same reasoning was never carried across to the ~15 integrator Mongo hosts,
and the integrator completion note above did not name the gap. That is the correction this section
records.

**Shape of the fix — node replacement, which 4Shark already has tooling for.** An EBS volume cannot be
encrypted in place, so each node has to be replaced by one provisioned with `encrypted = true` +
`kms_key_id` pointing at that integrator's key. Replacing replica-set nodes with zero downtime is
exactly what the `mongodb-reprovision` skill does (fresh nodes → join → sync → cutover → retire the
old), so this is the same operation already run for the OS upgrade, with two additions on top:

1. **Widen each integrator key's policy to cover EBS** — the current `kms:ViaService` list (ssm,
   elasticache) has to gain the EC2 service, the way `alias/vpn` was scoped via-EC2 for its own host.
2. **Declare encryption in the module, not per stack** — `encrypted` + `kms_key_id` belong in
   `modules/integrator/mongodb.tf`, so a new integrator's nodes are born encrypted by construction,
   the same guarantee the module already gives for the key itself.

**Per-integrator, not all four at once** — each is a live replica set for a paying client; the cutover
window is per client, and a failed cutover must not be able to touch a second one.

**Step 1 of the fix is DONE — terraform PR #845, applied and merged 2026-07-27.** Both additions above
shipped together with the replacement nodes, because neither is optional: without the key-policy
widening the encrypted volume cannot be created at all (the policy granted the account root management
actions only, no cryptographic action), and declaring the encryption in the module rather than per
stack is what makes it unforgettable — the stack passes node names, the module attaches the key.

What is live now, verified against AWS rather than inferred: **twelve new nodes, three per integrator,
every root volume `Encrypted: true` under that integrator's own key** (four distinct key ARNs, one per
stack), each resolving on the internal zone. Each integrator stack applied `3 added, 1 changed, 0
destroyed` — the single change being its KMS key (policy + description), an in-place update that
re-encrypts nothing — and the DNS stack applied `12 added, 0 changed, 0 destroyed`. **No live resource
was replaced at any point.**

The node numbering also got corrected in the same pass. The `mongodb-reprovision` skill said numbering
ADVANCES and never reuses; it does not — it **alternates between two blocks**, taking whichever is free,
because the serving block is unavailable (two instances cannot share a `Name` tag and the internal DNS
record resolves by it) and the retired block frees again at teardown. The replacement nodes are
therefore `001/002/003`, not `007/008/009`; a number is a slot, not a version, and a counter that only
climbed would reach `mongo042` and stop meaning anything. Corrected in dot-claude PR #454 before the
terraform code was renumbered to match.

**Step 2 is DONE for all four integrators — the data has moved, 2026-07-27.** Every client now serves
its replica set entirely from the encrypted block: `mongo001` PRIMARY, `mongo002` SECONDARY, `mongo003`
ARBITER, priorities `1 / 0.5 / 0`, `Problems: []`, verified per client after the fact rather than
inferred from the cutover output. The old trio is out of the set and stopped (twelve instances, all
`stopped`, data frozen as the warm fallback). The connection strings were rotated in SSM — eleven
parameters, one per deployment, each verified by re-reading the stored value and confirming it names
`mongo001/002/003` and no old node. Customer data is therefore on encrypted volumes for the first time.

**The one guarantee that is NOT ours: the record-count comparison.** MongoDB's own initial-sync
contract is what backs "the new nodes have all the data" — a member reports `SECONDARY` only after the
sync completed, and `cutover` refuses to touch the set until BOTH new data nodes reach it. That is a
strong mechanical guarantee, but it is not an independent count of both sides, and the independent count
is the engineer's `bin/ecs run` gate. It is only possible **before** the teardown, which destroys the
frozen copy that serves as the baseline.

**Rollback is no longer free.** It stopped being free at each client's B.3 step, where the old data
members left the set. From here the old nodes are a frozen copy: putting one back is a re-add and a
full re-sync — a restore, not an undo. The restore points below are the cold path.

**The repoint was NOT the shape the runbook describes, and the next migration needs to know.**
`mongodb-reprovision`'s SKILL.md says the old nodes are named in four places in each stack's
`compute.tf`. They are not: the module was consolidated, so all five reference sites live in
**`modules/integrator/`** — `deployments.tf` (the `AWS_INSTANCE_IDS` env var and the `start_mongodb`
schedule's `InstanceIds`), `deployments_alb.tf` (the scheduler role's `ec2:StartInstances` resource),
`iam_deploy.tf` and `outputs.tf` (the instance ARN lists) — and are shared by every integrator stack.
Consequence: **a repoint cannot be done per client.** It is correct only once every stack that declares
nodes has cut over, which is why the four ran to completion before the repoint landed (terraform PR
#846, applied to almaviva `4/3/4`, maqnelson `4/3/4`, atento `0/1/0`; commcenter planned `No changes`
because it declares neither `mongo_start_cron` nor `inject_mongo_instance_ids`). A per-client switch
variable was considered and rejected as abstraction for a window that had already closed.

Two facts worth carrying forward. First, **the deploy is mandatory for a reason narrower than the
runbook states**: the connection string resolves from the SSM ARN at task-start, so a fresh task gets
the new hosts with no deploy at all — what the deploy fixes is `AWS_INSTANCE_IDS`, a literal baked into
the task-definition revision, which the services do not pick up because `task_definition` sits in
`ignore_changes` (`modules/ecs_service/main.tf:155`). Left undeployed, the app's shutdown worker stops
the retired nodes and leaves the serving ones running — cost, not failure. Eleven deploys were run (the
four clients' production plus staging and atento's four countries) and the resulting revisions were
verified to carry the new IDs. Second, **the deploy's own MongoDB preflight is already
migration-aware** — it derives the instance Name tags from the hosts in the SSM URL rather than
hardcoding them (`integrator/.github/workflows/deploy.yaml:59-95`), so rotating the parameter is what
makes the check follow. Nothing there needed changing.

**The teardown ran the same day — terraform PR #848.** The DNS stack applied FIRST (`0 add, 0 change,
12 destroy`), which is not a preference: a `data "aws_instance"` matches `running`/`stopped` but not
`terminated`, so terminating before those lookups are gone breaks every later plan of the whole DNS
stack, for unrelated environments too. Termination protection was cleared out of band on all twelve
first and verified with `describe-instance-attribute` — `describe-instances` does not return the field
at all, so a protected instance is indistinguishable from a cleared one and the apply would die
mid-destroy. Each integrator stack then applied `0 add, 0 change, 3 destroy`, naming exactly its own old
trio with **zero task-definition churn**, which is the runbook's signal that the repoint had already
shipped separately. All four sets verified `Healthy: true`, `Problems: []`, priorities `1 / 0.5 / 0`
after the fact.

**The retired block was DELETED from the module rather than left at `count = 0`, and that is what made
the destroy possible.** `prevent_destroy` must be a literal, so it attaches to the slot and not to the
role: the old arbiter carried the guard, and a block left in place would have refused its own destroy.
Removing the block removed the guard with it — the runbook says exactly this (`SKILL.md:201`) and the
plan confirmed it, since `mongo006` destroyed without complaint. The `has_mongo` local went too, having
become dead once the serving block is gated per map key. The next re-provision re-adds 004/005/006 the
same way and deletes 001/002/003 at its own teardown; the module header now documents that cycle.

**The orphan count is FOURTEEN, not twelve — and the two extras were not left by this migration.**
`vol-0274bf12f079cf3e4` and `vol-068a53f9cf38e271e`, both tagged `integrator-commcenter-mongo00{1,2}`,
are 60 GB (today's are 40 GB) and dated 2026-07-13 — before the 2026-07-15 generation existed. They are
the PREVIOUS re-provision's retired data nodes, whose volumes nobody deleted: unencrypted customer data
from that generation, billing for two weeks, and no snapshot of them recorded anywhere. Their node names
collide with numbers that are live again today, which is exactly what makes them easy to misread as
current. **The lesson generalises past these two: a re-provision that stops at the terminate leaves
paid-for unencrypted data behind unless deleting the volume is an explicit step** — Phase D.6 exists for
this and was skipped both times. **Both were deleted on the engineer's go, 2026-07-27**, bringing the
orphan count back to the twelve this migration deliberately kept.

**What remains on this surface is one decision: when the orphaned volumes go.** `redebrasil` is
excluded from all of it — the engineer confirmed 2026-07-27 that the stack is being decommissioned this
week or next, so its unencrypted `4client-redebrasil-mongo00{3,4,5}` volumes go away by deletion rather
than by re-provisioning.

**A note on `redebrasil` planning, because the obvious reading of it is wrong.** The stack fails config
validation with six `Unsupported argument` errors — `vpc_id`, `subnet_prv_a_id`, `subnet_prv_b_id`,
`route_table_private_id`, `additional_ingress_sg_ids`, `internal_zone_id`, all passed to `module "this"`
and all dropped from the module when it absorbed the subnet lookups (`modules/integrator/main.tf:21-22`
now reads them from SSM itself). Reproduced against unmodified `develop`, so it predates any open PR.
This looks like an unnoticed regression and **is not one**: the stack carries `freeze.tf`, a deliberate
always-failing `precondition` added to abort every plan and apply on a cancelled contract (§ Phase 10
records it). The config drift simply fires *earlier* than the precondition, so the freeze message never
gets printed — the drift masks the guard rather than replacing it. **Do not "fix" this stack.** Both the
drift and the freeze resolve by deleting it. A background task was opened to repair the drift on
2026-07-27 and was wrong to exist; it is recorded here so the next reader does not re-open it.

**Restore points — record every one here the moment `snapshot` returns them.** They are the cold
rollback once the old volumes are gone, and after the teardown there is no way to rediscover which
snapshot belonged to which node.

| Client | Node | Volume | Snapshot | Taken |
|---|---|---|---|---|
| almaviva | mongo004 | `vol-0bc85dd65541ea4b5` | `snap-06ffbf5ead8e6ce48` | 2026-07-27 |
| almaviva | mongo005 | `vol-04ec67b945d5d05c8` | `snap-0e0c030b6c20caea3` | 2026-07-27 |
| maqnelson | mongo004 | `vol-0bd2586d34b953c5c` | `snap-077ed0e6881bd942c` | 2026-07-27 |
| maqnelson | mongo005 | `vol-04c0a26b6102b4f60` | `snap-0b63a69da2e8ea440` | 2026-07-27 |
| commcenter | mongo004 | `vol-087ae6d5959083bc3` | `snap-07b0761fe039cfe43` | 2026-07-27 |
| commcenter | mongo005 | `vol-06902a79a8dbd9ccc` | `snap-09d1dd6733e65e9e9` | 2026-07-27 |
| atento | mongo004 | `vol-0ab2bf4f0b48edd10` | `snap-0ab3ad4c82b7f8283` | 2026-07-27 |
| atento | mongo005 | `vol-03505729e3a466e1a` | `snap-074aea977c11d354f` | 2026-07-27 |

**Root volumes of the twelve retired nodes — captured before the terminate (Phase D.1), because after
it there is no way to discover which volume belonged to which node.** They carry
`delete_on_termination = false`, so they survive the instance as `available` and keep costing until
deleted deliberately. **They are NOT being deleted in this teardown** — the engineer chose to proceed
without the record-count gate, so these volumes plus the snapshots above are what keeps that
verification possible at all. Deleting them is a separate, later decision.

| Client | Node | Volume |
|---|---|---|
| almaviva | mongo004 | `vol-0bc85dd65541ea4b5` |
| almaviva | mongo005 | `vol-04ec67b945d5d05c8` |
| almaviva | mongo006 | `vol-074c9ba6887ede322` |
| maqnelson | mongo004 | `vol-0bd2586d34b953c5c` |
| maqnelson | mongo005 | `vol-04c0a26b6102b4f60` |
| maqnelson | mongo006 | `vol-0f5df2cab6aca2072` |
| commcenter | mongo004 | `vol-087ae6d5959083bc3` |
| commcenter | mongo005 | `vol-06902a79a8dbd9ccc` |
| commcenter | mongo006 | `vol-0167d6bab97db98db` |
| atento | mongo004 | `vol-0ab2bf4f0b48edd10` |
| atento | mongo005 | `vol-03505729e3a466e1a` |
| atento | mongo006 | `vol-080628e841101ae3d` |

Only the DATA MEMBERS OF THE SERVING SET are listed — those are the snapshots that carry data and the
only ones whose absence would be a missing backup. Two shapes both appear in practice and both are
correct: when the set is already up, the script reads its config and snapshots exactly the data members
(almaviva, two snapshots); when no set is reachable — the normal state of a daily-shutdown client at
Phase 0 — it cannot know which member is the arbiter, so it snapshots EVERY node (maqnelson, six). The
extra ones there (the arbiter and the three fresh replacements) are near-empty and deliberately not
tracked here.

**Two operational traps hit during the migration itself, both worth carrying forward.** First, a
replacement node came up on a private IP that a previously-destroyed instance had used, so the
engineer's `known_hosts` still held the old key and SSH refused with a host-key-changed warning. That is
IP reuse inside the VPC, not an attack — but it is verified, never assumed: the instance's own AWS
console output prints the fingerprints cloud-init generated at boot, and the ED25519 one matched what
SSH presented. Clearing the stale entries (`ssh-keygen -R <ip>` — there were TWO for that address, not
one) unblocked it. Second, **the MFA session is valid one hour and this migration outlives it**; when it
expired mid-run, `create-snapshot` failed and the empty ids nearly passed as backups. Re-elevate before
each client rather than discovering it inside a step.

**A defect in the re-provision script surfaced here and was fixed before any data moved (dot-claude
PR #455), and a SECOND round was needed because the first fix repeated the original mistake one level
up (PR #456).** The first fix asserted the snapshot list was non-empty; the expired session produced two
records whose ids were the empty string, so the length was right and the check passed. Both layers now
verify each entry carries a real `snap-` id, and refuse a partial result. The recurring lesson is the
same in all three rounds: **assert the thing itself, never a count of things.** The preflight decided whether the serving set was up by COUNTING running nodes, an
inference that held only while a client had one block of nodes. This migration creates a second block,
so "some are running" became true while the running ones were the fresh replacements — in no set,
holding nothing — and the nodes with the data were stopped. It then asked a memberless node for the set
config, resolved an empty list of nodes to back up, and reported `Ready: true` with **zero snapshots**.
The script now classifies each node individually and branches on whether a set is reachable; an empty
snapshot list aborts in two independent places. Worth carrying forward: adding nodes to an estate can
invalidate a count-based premise somewhere downstream, and the failure surfaced as false success.

**One risk to check rather than assume, at the repoint step**: the scheduler that starts these nodes
daily needs `kms:CreateGrant` to boot an encrypted volume. The grant statement added to each key
covers it by key policy, but that path is only exercised once the new nodes enter the schedule — verify
the first scheduled start after the repoint instead of discovering it inside a window.
| 2 | `app-demo-001` | **Catch the exceptions** beta could not surface — it holds real client data and clients reach it | Low, visible |
| 3 | `app-shared-001` | Only the exception-of-the-exception should still be unknown here | Real, many clients |
| 4 | `setup`, `onboarding` | Same shape as the app stacks | Real |
| 5 | `app-atento-001`, `app-outbound-*`, the five `integrator-*` | Nothing new should be left to discover | Highest — dedicated client infrastructure |

Do not reorder to "get the important one done first". The order IS the risk control.

**Verify per stack before moving on** — and verify *after the deploy*, not after the apply, since the
apply changes nothing that runs. Confirm: the service's running revision actually moved; tasks start
on the new role; the app answers; `bin/ecs run` attaches (the `ECSExecPolicy` reproduction); the new
role reads its own parameters and **cannot** read another stack's.

**The tfvars trap** — the role is hardcoded as a string in each stack's `terraform.tfvars` (18 lines
in `app-beta-001`, two per service). A tfvars file is static and cannot reference
`aws_iam_role.ecs_task_execution.arn`. Inject the role in `locals.tf` instead, in the same `merge`
that already injects `secrets` and `env`, and delete the tfvars lines — that produces a real
dependency edge instead of a second hardcoded ARN.

**A service that never deploys never cuts over** — the role changes by inheritance at deploy time, so
a service that has not shipped in months stays on the shared role indefinitely. Step 3 (deleting the
old policy from the shared role) cannot run until **every** service in that stack has cycled. Confirm
each one's running revision before step 3, per stack.

**Two `iam:PassRole` gates break the deploy if missed.** A deploy PASSES the role when it registers a
task definition, so a role the principal cannot pass fails with AccessDenied — at exactly the deploy
being used to verify the cutover. Both grants name the shared role today and must gain the new one:

| Grant | Where | Breaks |
|---|---|---|
| Deploy user | each stack's `iam_deploy_user.tf`, `task_execution_role_arns` | The GHA deploy — `register-task-definition` |
| Scheduler | `scheduled-tasks.tf`, the `ecs_scheduler` role's inline policy | The cron tasks — `ecs:RunTask` |

**Scheduled tasks are a SEPARATE step from the services, on purpose.** They are not in `local.services`
and carry no `ignore_changes`, so re-pointing them takes effect on the next cron fire — unattended, at
4am. That is precisely the decoupling the apply-plus-deploy rule above exists to avoid. Cut them over
in their own step, where the task can be triggered manually and watched. Beta's set includes the LGPD
anonymization cron, so a silent failure there is not cosmetic.

**Known open question, to be settled at step 1**: whether `target-alb` is needed on a task role at
all. Beta is where that costs nothing to find out.

### Phase 12 — The three integrator surfaces the closing audit surfaced (S3, ECR, CloudWatch Logs) — 12a + 12b DONE 2026-07-27/28; 12c IN PROGRESS (step 1 done, step 2 next)

> **Status, 2026-07-28.** CloudWatch Logs (12a) and ECR (12b) are applied, verified against AWS and
> merged. **S3 (12c) is the only integrator surface left, and it is HALF done**: the bucket default
> encryption is applied and merged (step 1, PR #860 + #861), so new objects are on the stack's key — but
> the objects that already exist are still under the AWS-managed key, and moving them is § 12c step 2,
> **the next work item in this whole plan**. It is the heaviest of the three surfaces precisely because
> it is the one that cannot be solved without moving data. Everything the integrator estate needs beyond
> this is either out of Phase 12 (the `redebrasil` teardown) or deferred by decision (§ Phase 13a).
>
> **Do not read "the integrator is done" from 12a/12b/12c-step-1 being green.** It is not done until
> step 2 finishes, and the app estate does not start before it.

The 2026-07-27 audit found three integrator surfaces that are encrypted but NOT under the integrator's
own key, and that this plan had never scoped either way. They are grouped here because they share a
goal, and separated below because **their mechanics are not alike at all** — one is an in-place
attribute, one is immutable and forces a replace, one cannot be solved without moving data. Ordering
them by that cost is the plan: the cheapest is also the one carrying the most customer-derived content.

**A correction that removes work, recorded because the opposite was assumed.** The initial instinct was
that log groups would need renaming so Terraform would see drift and recreate them with the key, leaving
the wrongly-named ones to age out. **Neither half of that holds.** `kms_key_id` on
`aws_cloudwatch_log_group` is NOT `ForceNew` — only `name` and `name_prefix` are (provider docs) — and on
the AWS side `associate-kms-key` attaches a key to an EXISTING group, verbatim: *"Only the log events
ingested after the key is associated are encrypted with that key."* And the names are already correct:
all 50 `/ecs/integrator-*` groups are on the `integrator-<client>` standard, the ADR-010 VPN-edge rename
having already covered the tunnel groups. The single legacy name left in the account is
`/aws/vpn/4client-redebrasil-main`, on the frozen stack. **So no rename, no recreation, no waiting for
expiry — adding the argument is the whole change.**

**12a — DONE 2026-07-27 (PR #849, applied to all four stacks).** Every log group the module owns is on
its integrator's key: almaviva and maqnelson `0 add, 7 change, 0 destroy`, commcenter `11`, atento `33`
— **not one resource recreated in any of them**, which is the whole point of the correction below.
Verified after the fact against AWS: 54 of the 61 `integrator*` log groups carry a key. The seven
without are six on the frozen `redebrasil` stack (expected — it cannot be applied) and one genuine
find: **`/aws/lambda/EC2-start-integrator-atento-br` is an unmanaged orphan.** The atento stack does not
set `ec2_start_lambda_log_group`, and the module would name the group `…-integrator-atento` anyway, so
this `-atento-br` name is a leftover from the older per-country stack layout that Terraform has never
owned. It holds 0 bytes, so it is cleanup rather than exposure — but it is also the kind of thing that
only surfaces when someone counts.

**The data-loss question was asked and answered empirically, not from the doc.** After the almaviva
apply, the VPN log group still reported 5,175,967 stored bytes, and three events dated 2026-07-24 —
three days before the key existed on that group — read back cleanly via `get-log-events`. So associating
a key neither drops nor re-encrypts what is already there; CloudWatch keeps the previous encryption
reference and serves it. **What the change does create is a new dependency**: from now on the log data
ingested by these groups is unreadable if the integrator's key is deleted or the logs statement is
removed from its policy. AWS states it plainly — *"If you revoke CloudWatch Logs access to an associated
key or delete an associated KMS key, your encrypted data in CloudWatch Logs can no longer be
retrieved."* The 30-day deletion window and rotation make that hard to do by accident, but the blast
radius of deleting an integrator key is now larger than it was.

**12a design note — the prerequisite that was on the key, not the log group.** The one
on the key, not the log group: a KMS key usable by CloudWatch Logs needs a policy statement admitting the
`logs.<region>.amazonaws.com` service principal, normally narrowed by an `kms:EncryptionContext:aws:logs:arn`
condition. Each integrator key currently admits ssm, elasticache and (since PR #845) ec2, so this is a
fourth via-service statement on the same policy — the same shape as the EC2 one, and the same reason it
must land BEFORE the log groups reference the key, or the association is rejected. Content-wise this is
the surface most worth doing: integrator logs carry processing traces and error payloads that quote
customer records.

**12b — ECR. A replace is unavoidable, and it empties the repository.** ECR sets encryption at creation
and offers no way to change it: the API has `put-image-scanning-configuration`, `put-image-tag-mutability`,
`put-lifecycle-policy` and `put-replication-configuration`, and nothing for encryption. So Terraform must
destroy and recreate each of the 16 `integrator*` repositories, and the images go with them. **The
consequence is a sequencing constraint, not a data loss**: the deploy consumes `:latest` from ECR, so a
freshly recreated repository has nothing to pull until a build runs. The order is replace → build →
deploy, and it must happen in a window where the integrator is idle — which is most of the day, since
every integrator sits at `desired_count 0` between processing windows. **Worth deciding rather than
assuming**: an image layer holds application code, not customer records, so ECR is the weakest case of
the three on content grounds even though it is the middle one on cost.

**Facts established 2026-07-27, from the vendor rather than from memory, ahead of execution:**

- **The replace is confirmed by AWS, not inferred from a missing API.** Verbatim: *"Repository Encryption
  Configuration can't be changed after a repository is created."* (`encryption-at-rest.html`,
  Considerations). There is no import trick and no in-place path.
- **`force_delete` is required and it is the phase's one real decision.** Verbatim, HashiCorp: the flag
  *"will delete the repository even if it contains images. Defaults to `false`."* Every repository in
  scope holds images (the reference one alone ~128), so without it the apply starts, fails on the first
  destroy, and leaves the run half-done. **A half-done apply is not hypothetical here — it is exactly
  what happened in Phase 13 (#854) when a permission was missing.** The fork: a module variable
  defaulting to `false` that each stack opts into and drops after (recommended — keeps the provider's
  guard-rail intact for every future destroy, on a resource whose contents have NO backup); hardcoding
  `true` in the module (one PR, but removes the guard permanently for a one-time migration); or emptying
  each repository by hand (moves the irreversible step out of the plan, where nobody reviews it).
- **The key-policy prerequisite — DONE 2026-07-27 (PR #855, applied + merged).** Creating a
  KMS-encrypted repository requires `kms:CreateGrant` and `kms:DescribeKey`, which AWS allows in the key
  policy. `modules/integrator/kms.tf` gained the ECR pair (via-service crypto + `CreateGrant` bounded by
  `kms:GrantIsForAWSResource`), following the shape the same file already used for ElastiCache and EC2.
  Applied to the four active integrators (`0 add, 1 change, 0 destroy` each) and verified against the
  LIVE policy, not the plan: almaviva's key now carries 10 statements — the original 8 in their original
  order plus the 2 new ones. **That verification was the point.** A key-policy update is a whole-document
  `PutKeyPolicy`, so the risk was never "adding a statement" but an existing statement vanishing in the
  rewrite and the integrator losing SSM decrypt. The plan's `7 unchanged elements hidden` plus zero `-`
  lines said it, and the live read confirmed it.
- **Why this went first, alone.** It is the `kms:ReplicateKey` lesson from Phase 13 applied before it
  costs anything: a capability set without the permission it needs fails at apply, and here the failure
  would land on the CREATE — after the DESTROY had already emptied the repository. Granting first, in a
  change that can only add, removes the failure mode instead of surviving it.
- **`kms:RetireGrant` is NOT covered and cannot be** — AWS requires it on the IAM policy of the identity
  DELETING an encrypted repository, and a key policy cannot supply it. Nothing is encrypted yet so
  nothing needs it; it becomes a prerequisite the first time an ENCRYPTED repository is destroyed (a
  teardown, or a second `force_delete` replace). Recorded in the module header at the point a reader
  would look.
- **`integrator-redebrasil` cannot receive ANY module change, and this is broader than ECR.** Its plan
  fails with six `Unsupported argument` errors (`vpc_id`, `subnet_prv_a_id`, `subnet_prv_b_id`,
  `route_table_private_id`, `additional_ingress_sg_ids`, `internal_zone_id`) — the stack is frozen at a
  module interface that no longer exists (the module has 14 variables and none of those is among them).
  It was excluded from ECR anyway, but the consequence generalizes: **no future module change can be
  applied there either**, which is why it never picked up the earlier phases and why teardown is the
  only remaining path for that stack.
- **The repository count, established from `init` rather than guessed:** each integrator stack
  instantiates FOUR ECR modules — `ecr_deployment`, `ecr_deployment_staging`, `ecr_harvester`,
  `ecr_harvester_staging`. Iterated by `for_each`, so the 16 are distributed unevenly: almaviva 1,
  maqnelson 1, commcenter 2, atento 11 (four countries × deployment, three staging, four harvester),
  redebrasil 1.

**12b execution — the flag and the key are TWO applies, and that is not a preference.** PR #856 set
`force_delete` alone (`0 add, N change, 0 destroy` per stack); PR #857 adopted the key. Combining them
was tried first and **failed**: the plan showed the flag being added, the apply still died with
`RepositoryNotEmptyException ... consider using force_delete`. **Terraform issues the delete using the
value already in STATE, not the one in the new configuration** — so the delete runs first, with the old
value. Nothing was destroyed (the API refuses before acting), which is the only reason this cost a
re-plan instead of an incident. The tell that the split worked: in #857's plan `force_delete` no longer
appears in the diff at all — it has moved to the unchanged attributes, leaving only the encryption
forcing the replacement.

**This is the THIRD instance of one failure shape in this plan, and it now has a name.** `kms:ReplicateKey`
(Phase 13), the ECR key-policy grant (12b), and `force_delete` (here) are all *a capability enabled in the
same apply as the operation that consumes it*. Two were caught by an apply failing; one was caught by
reading the docs first. **Rule for the rest of this plan: when a change needs a permission, a flag, or a
property that did not exist before, that prerequisite lands and is CONFIRMED in its own apply.** The cost
is one extra round-trip; the alternative is a failure that lands after the destroy.

**12b applied 2026-07-28 — all four active stacks, in two waves, PR #857 merged.** almaviva (`1/0/1`),
maqnelson (`1/0/1`), commcenter (`2/0/2`) went first; atento (`11/0/11`) followed once the engineer
confirmed the window. Every apply `0 changed`, so no resource outside the repositories was touched.
Verified in AWS: all 15 repositories read `KMS` under their own stack's key with their names unchanged.
`redebrasil`'s 16th stays `AES256` — it cannot receive a module change at all (frozen interface) and
resolves by teardown.

**The rebuild is NINE dispatches, not fifteen, and the shape is not uniform** — this had to be read from
the workflows before destroying anything, because a wrong assumption here empties a repository with no
way to refill it. Seven come from `integrator`'s `Build`, one per slug of the `INTEGRATORS` repository
variable (`commcenter` and `commcenter-staging` are SEPARATE slugs; so are each atento country and its
staging). The four harvester repositories come from `simplex-harvester`'s `Build`, which **takes no input
at all** — the BRANCH selects the destination: `master` → the two production repos, any other ref → the
two staging repos, each dispatch covering MX and CO together. Dispatching those by slug would have failed
after the destroy.

**The scheduling constraint is in the OTHER stack's timezone, and the deadline is not the integration.**
`ECS-integrator-atento-cl-cron-integration-cron-schedule` is `cron(0 10 * * ? *)` in **America/Santiago**
— not Brasília, which is what a reader assumes and what the engineer initially estimated. More
importantly the binding deadline is `integrator-atento-cl-scale-up-{web,worker}` at `cron(55 9 * * ? *)`
Santiago: **the scale-up is what launches the task and pulls the image**, five minutes ahead of the
integration. Read the scale-up schedule, not the integration schedule, when sizing a window like this.

**A stack cannot be partially applied, and the answer is a policy one.** The engineer asked to apply the
harvesters, BR, MX and CO while holding CL. That requires `-target`, which 4Shark forbids and the wrapper
rejects (it hides drift in non-targeted resources). So an ECR migration is per-STACK, all-or-nothing, and
a stack with several countries is gated by whichever country runs next.

**12b COMPLETE — verified 2026-07-28, per repository rather than by sampling.** All 15 repositories of the
four active stacks read `KMS` under their own stack's key with unchanged names, AND all 15 carry the
`latest` tag the task definitions pull. The tag was confirmed by a direct `--image-ids imageTag=latest`
lookup on each one, not inferred from nine green workflow runs — **a successful build is not a present
image, and the whole sequence was built to avoid exactly that class of assumption.** The Chile deadline
cleared with 24 minutes to spare: image in the repository at 09:31 Santiago against a 09:55 scale-up.
`integrator-redebrasil` remains `AES256`, unreachable by any module change and resolving by teardown.

> **A JMESPath note that cost a round-trip**: `length(imageDetails[?contains(imageTags, 'latest')])`
> fails with `invalid type for value: None` when any image in the repository is untagged. Use
> `--image-ids imageTag=latest` instead — it asks the API the question directly and errors cleanly if
> the tag is absent, which is the answer you actually want.
- **The window is real and was open when checked.** All twelve integrator clusters reported `0/0`. A
  destroyed repository is an empty repository, so any task launching between destroy and rebuild cannot
  pull its image — the order is key policy → confirm idle → replace → build → deploy → verify → drop the
  opt-in, and the idle check is re-run immediately before, because a GO means clean when checked, not
  clean now.
- **The rebuild is the only recovery.** There is no snapshot of an ECR repository; images come back by
  running the build workflow per integrator plus the harvester repositories. That is what makes the
  `force_delete` placement decision worth the round-trip rather than a default.

**12c — S3. A new bucket, a data move, and a cutover — the versioning is why.** Default encryption
applies to newly written objects only, so the obvious cheap path is copy-in-place (rewriting each object
onto itself re-encrypts it without a new bucket). **That path does not reach the goal here, because the
buckets are versioned** (`Status: Enabled`): a copy-in-place writes a NEW version and every prior version
stays on AES256, so "everything encrypted" would additionally require expiring the entire version
history. A new bucket gives the guarantee by construction — every object KMS-encrypted from its first
write — and the old bucket takes its versions with it when it is deleted.

Scale, measured 2026-07-27: the almaviva deployment bucket alone holds **~45.6 GB** of live integration
payloads (`storage/group/*.json`), and there are 13 `4shark-integrator*` buckets in sa-east-1. Size the
rest at execution rather than now; the almaviva figure is already enough to say this is an `s3 sync`
window or an S3 Batch Operations job, not a two-minute copy.

The cutover has a piece that is easy to miss: the bucket name reaches the application as the
module-derived `AWS_BUCKET` env var (`modules/integrator/deployments.tf`, `"4shark-${deployment_name}"`),
so a new bucket name is a module change → new task-definition revision → deploy, exactly like the
`AWS_INSTANCE_IDS` repoint was. The bucket is not just storage; its name is configuration.

**The naming decision is MADE (engineer, 2026-07-28): keep `4shark-integrator-<client>` exactly as it
is.** *"Eu gosto dos nomes dos buckets que estão hoje, que é 4Shark integrator. Aí, o nome do cliente, eu
gosto desse padrão. Quero manter esse padrão."* A permanent `-v2` suffix is off the table, so the
migration is the double one: out to a temporary name, back to the canonical name. This is the more
expensive path in data movement and it was chosen deliberately, not by default — the name is the thing
being protected.

**The engineer's sequence, recorded verbatim in intent (2026-07-28).** Create a temporary bucket; move
the data there; delete the original; point the application at the temporary one so it keeps running;
then re-create the ORIGINAL NAME with the key; replicate from the temporary back into it; cut the
application over once synchronized; delete the temporary. The application never stops writing, and the
canonical name is reclaimed at the end.

**RESEARCH DONE 2026-07-28 — and it found that S3 is NOT like ECR, which is the finding that matters.**
The ECR migration needed a destroy because encryption is fixed at creation. **S3's is not.** Verbatim:
*"If you want to encrypt your objects with SSE-KMS, you must change the encryption type in your bucket
settings"* (`bucket-encryption.html`) — an in-place setting change on the existing bucket. The problem S3
actually has is the OBJECTS, not the bucket, and AWS names the mechanism for those in the same page:
*"To encrypt your existing unencrypted Amazon S3 objects, you can use Amazon S3 Batch Operations… You can
use the Batch Operations Copy operation to copy existing unencrypted objects and write them back to the
same bucket as encrypted objects."*

**Three facts that bear on the sequence, each sourced:**

1. **Live replication does NOT carry existing objects.** Verbatim: *"By default, Amazon S3 replicates the
   following: **Objects created after you add a replication configuration**"*
   (`replication-what-is-isnot-replicated.html`). So "espelhar os dados do bucket original" is TWO
   mechanisms, not one — live replication for new writes, **S3 Batch Replication** for the ~45 GB already
   there. A plan that assumes one silently copies nothing.
2. **AWS explicitly advises against deleting a bucket whose name you intend to keep.** Verbatim: *"If you
   delete a bucket in the shared global namespace, be aware that another AWS account can use the same
   general purpose bucket name for a new bucket and can therefore potentially receive requests intended
   for the deleted bucket. If you want to prevent this, **or if you want to continue to use the same
   bucket name, don't delete the bucket.**"* (`delete-bucket.html`)
3. **There is NO stated reclaim window — the "espera um tempo" step has no number to fill in.** Verbatim:
   *"When you delete a general purpose bucket, the bucket might not be instantly removed. Instead, Amazon
   S3 queues the bucket for deletion… the deletion process takes time to fully propagate and achieve
   consistency throughout the system."* No duration is given anywhere. **A migration whose hinge is an
   unspecified wait, on a globally-contested namespace, cannot be scheduled.**

**The alternative these facts point at — same goal, bucket never deleted, one pass over the data.** Set
the bucket's default encryption to the integrator's key (in place, instant); run S3 Batch Operations Copy
over the objects in place, which writes each back as a new KMS-encrypted CURRENT version; then let a
lifecycle rule age out the old AES256 versions — `NoncurrentVersionExpiration` with `NoncurrentDays`,
which verbatim *"doesn't apply to the current object versions. It removes only the noncurrent versions"*
(`lifecycle-configuration-examples.html`). The name is never released, so it can never be taken; the
application never repoints, because `AWS_BUCKET` does not change; and the data moves once instead of
twice. The cost is that full coverage arrives when the noncurrent window elapses rather than at a
cutover — **the same trade the engineer already accepted for CloudWatch Logs** (*"as outras paciência, a
gente espera 180 dias pra elas expirarem"*).

**Surfaced to the engineer 2026-07-28 as a disagree-and-commit, not a question.** The double migration
remains theirs to choose; what this section records is that AWS advises against its central step and
gives no duration for its central wait.

#### The in-place path, sized and de-risked (research 2026-07-28)

**Nothing is ever unavailable, and that is the load-bearing fact.** Changing the bucket default does not
touch what is already stored — *"Objects that are already in an existing unencrypted bucket won't be
automatically encrypted"* — and reading is transparent regardless of which key wrote an object:
*"There is no change in the way that you access objects"* (`default-encryption-faq.html`). AES256 and
KMS objects coexist in one bucket and the application never inspects which is which. **So this migration
needs no window at all** — which dissolves the engineer's "tem que rodar em menos de um dia" constraint:
the job can take a week and the integrator keeps running throughout.

**THE PREREQUISITE, and it is the fourth instance of the same failure shape.** The integrator key policy
allows SSM, ElastiCache, EC2, CloudWatch Logs and ECR — **not S3**. An object written under the key
before that statement exists becomes unreadable to the application, because SSE-KMS reads need decrypt.
The S3 statement lands and is confirmed in its own apply, before any object is rewritten. Use the
`kms:ViaService = s3.<region>.amazonaws.com` shape the module already uses — **NOT an encryption-context
condition**, because *"If your existing IAM policies or AWS KMS key policies use your object ARN as the
encryption context… these policies won't work with an S3 Bucket Key. S3 Bucket Keys use the bucket ARN
as encryption context"* (`bucket-key.html`).

**Enable S3 Bucket Keys BEFORE the batch, or every future read costs a KMS call.** Without it,
*"Amazon S3 uses an individual AWS KMS data key for every object… Amazon S3 makes a call to AWS KMS every
time a request is made against a KMS-encrypted object"*; with it, *"reduce AWS KMS request costs by up to
99 percent"*. It applies to new writes only — *"objects that are already in the bucket do not use the S3
Bucket Key"* — so enabling it first means the batch itself produces Bucket-Key objects. Enabling it after
would require a second pass over 8.24M objects.

**Scale, measured 2026-07-28: 8,241,007 objects in the almaviva bucket alone** (CloudWatch
`NumberOfObjects`; a plain `list-objects-v2` did not finish in 5 minutes). **Object count, not the ~45 GB,
is what sizes this** — Batch Operations bills and works per object. The other twelve buckets are unmeasured.

**AWS publishes NO throughput figure. Do not promise a duration.** The only statement is *"Because
manifests can contain billions of objects, jobs might take a long time to run"* (`batch-ops-create-job.html`).

**What makes it low-risk is that the job is self-narrowing and chunkable, not that it is fast.** The
manifest generator filters on `MatchAnyObjectEncryption` — *"includes only source bucket objects with the
indicated server-side encryption type (SSE-S3, SSE-KMS, DSSE-KMS, SSE-C, or NOT-SSE). If you select
SSE-KMS… you can optionally further filter your results by specifying a specific KMS key ARN."* So a job
scoped to "not yet on this key" **shrinks every time it runs**: a re-run picks up only the remainder, and
a failure is a partial result to resume rather than a restart. `MatchAnyPrefix` / `CreatedAfter` /
`CreatedBefore` slice it further. Every job also emits a completion report that can be scoped to failed
tasks only, so failures are enumerable rather than inferred.

**One versioned-bucket behaviour to design around, and it happens to favour us:** *"it doesn't take a
'snapshot' of the state of the bucket… Amazon S3 performs the operation on the latest version of the
object, not on the version that existed when you created the job."* Do NOT pin version IDs — acting on
latest is what we want, and objects the integrator writes mid-job are already KMS from the bucket default,
so they never needed the job.

**"In place" does NOT mean overwrite, and saying so caused a real misunderstanding (2026-07-28).** The
engineer read "in-place" as "the old bytes are replaced" and reasonably asked why anything would then
need expiring. In a versioning-enabled bucket there is no overwrite: the copy writes version 2 (KMS) and
version 1 (AES256) survives as noncurrent. Both buckets checked have `Versioning: Enabled`, and a sampled
object reads `ServerSideEncryption: AES256, SSEKMSKeyId: null` — SSE-S3, the AWS-managed key.

**Which makes expiry OPTIONAL, and the engineer was right to challenge it.** After the batch, every read
the application performs returns the KMS version — correctness is complete with the batch alone. Expiry
answers two different questions: whether any byte may remain under the AWS-managed key rather than the
stack's (the noncurrent versions are still encrypted, just not by us), and whether storage stays
permanently doubled (45 GB → 90 GB on almaviva alone). **Neither is required for the system to work**, so
expiry is a separate cleanup decision that can be deferred indefinitely — NOT a step of the migration,
which is how this section originally and wrongly framed it.

#### 12c prerequisite APPLIED 2026-07-28 (PR #860) — the S3 statement on each integrator key

Applied to all four active integrators, `0 add, 1 change, 0 destroy` each, no bucket or object touched.
Verified by reading each live key policy back and searching for `s3.sa-east-1.amazonaws.com` — 2 hits per
key. **Verify by searching for the ViaService, never by counting statements**: an earlier round of this
same step was reported as applied on a statement COUNT that happened to match, when the last two
statements were in fact the ECR pair from PR #855 and the S3 pair was absent from all four keys.
Written with `kms:ViaService = s3.<region>` rather than an encryption-context condition — deliberately
diverging from the CloudWatch Logs statement above, because S3 Bucket Keys move the encryption context
from the object ARN to the BUCKET ARN, so an object-scoped policy would silently stop matching the moment
Bucket Keys are enabled. **This prerequisite would NOT have failed loudly**: unlike the ECR grant, a
missing S3 grant fails at read time, one object at a time, after the object is already encrypted.

#### 12c step 1 APPLIED 2026-07-28 (PR #861) — bucket default encryption on the integrator estate

**All 11 buckets of the four active integrators now default to their stack's key, with S3 Bucket Keys
on.** Applied per stack — almaviva 1, maqnelson 1, commcenter 2, atento 7 — every one an in-place update
of `aws_s3_bucket_server_side_encryption_configuration`, `0 add, N change, 0 destroy`. No bucket was
recreated, no object was rewritten, and no name was released.

**Verified against the live API, per bucket, not from the apply output** — `get-bucket-encryption` on
each of the 11 returns `aws:kms` + `BucketKeyEnabled: true`. The apply summary says a resource changed;
it does not say the resulting configuration is the intended one, and this migration has already been
reported "applied" once on evidence that did not actually confirm the change (§ 12c prerequisite).

**The no-data-loss guarantee was demonstrated, not asserted.** A pre-existing object
(`storage/group/1.json`, almaviva) was downloaded after the change: it still reports
`ServerSideEncryption: AES256` and its 892 bytes came back intact — the AES256 objects are untouched and
still readable, exactly as the coexistence property predicts. Separately, a throwaway object written to
`commcenter-staging` came back `aws:kms` under the commcenter key with `BucketKeyEnabled: true`, was
re-read byte-identical, and was then hard-deleted by version id, leaving neither a version nor a delete
marker. **That write-then-read is what proves the § 12c prerequisite grant actually works** — a missing
S3 grant fails at READ time, per object, after the object is already encrypted, so nothing before this
test would have surfaced it.

**Bucket Keys had to land in this same apply, not a later one.** They apply to new writes only, so
turning them on after the objects exist would need a second full pass over 8.24M objects — and without
them S3 calls KMS on every request against a KMS-encrypted object, which at that scale is a permanent
per-read cost and a throttling surface.

**What is now true and what is not**: every object written from this point forward is on the stack's key.
The objects already stored are still AES256 and still read fine. **Step 1 is HALF the migration — the
half that stops the bleeding, not the half that moves the data.** Bringing the existing objects onto the
key is § 12c step 2 below, and it is the NEXT thing to do.

**MERGED 2026-07-28 — code and infrastructure are back in sync**, and the shared module was checked for
collateral drift rather than assumed clean. `modules/s3_bucket` is called by the four app stacks as well
as by `modules/integrator`, so its change reached stacks this migration never touched. `app-shared-001`
plans **`No changes`**, and the live encryption of `beta-001` / `demo-001` / `atento-001` reads
`AES256` + `BucketKeyEnabled: false` — exactly what the module's `kms_key_arn == null` path declares. The
app estate is therefore unchanged and carries no pending diff for an unrelated apply to trip over.

**Note for the app-estate phase: those four stacks call `../modules/s3_bucket` straight from their own
`s3.tf`**, so the key would be passed at the STACK call site — the shape the engineer rejected for the
app key ("esse multi region devia estar no modulo"). Same refactor debt already recorded for
`ecs_service` / `ecs_scheduled_task` / `codedeploy` / `lambda-ecs-autoscaling`; fold `s3_bucket` into it.

#### Stack standardization APPLIED and MERGED 2026-07-28 (PR #863) — and two lessons that outlive it

**What it closed.** Every `EC2-start` log group in the integrator estate now carries its stack's key —
verified live, the only one without is `redebrasil` (frozen, cancelled contract, resolves by teardown).
The group is derived per productive environment from `var.deployments`, with **no flag**, because
`deployments.tf` already states the rule this plan kept violating: *"Everything else follows from that ...
There is no flag to set."* Three successive drafts added an input (a name suffix, then a set of keys)
before the module's own documentation was read. **EBS encryption by default is now on in both regions**,
so `encrypted` is no longer an attribute any caller declares — the engineer's framing, and the reason
every per-resource `encrypted = true` written for this PR was removed again: *"não existe alguém escolher
se encripta ou não"*.

**LESSON 1 — a resource changing STATE ADDRESS while keeping its real name is a `state mv`, never a
destroy/create.** Changing `count` to `for_each` moves `foo[0]` to `foo["main"]`; Terraform sees an
unrelated destroy plus create at the SAME AWS name. On the first apply that raced and lost:
`ResourceAlreadyExistsException` on create, because the CloudWatch Logs delete was still propagating.
Recovery was fix-forward (re-plan showed `1 to add, 0 to destroy`, apply, verify) — but the three
remaining stacks used `terraform state mv` instead and planned **zero actions**. Reach for `state mv`
whenever the address moves and the name does not.

**LESSON 2 — a stale branch does not announce itself; it shows up as someone else's change being
reverted.** `app-shared-001` planned `18 to add, 7 to change, 18 to destroy`, which was dismissed twice as
"pre-existing provider drift" on the strength of four empty-array lines. Reading the whole diff under the
engineer's insistence — *"eu preciso saber o motivo de todas essas alterações sempre, está na porra da
política"* — showed it removing two `MIGRATION_*` `statement_timeout` variables that were **live in
production and present in the code**, merged three hours earlier by PR #864. The branch predated it.
After a rebase the same stack planned **`No changes`**: there was no provider drift at all, and applying
would have silently reverted a production change nobody asked to revert. **Rebase before planning, and
justify every line of a plan — a classification made from a sample is not a justification.**

#### 12c step 2 — DONE 2026-07-29. 23.2M objects re-encrypted, zero failures, integration ran through it

**The integrator estate is migrated.** `atento-mx` 7, `commcenter` 24,388, `almaviva` 8,218,095,
`maqnelson` 14,959,643 — **23,202,133 objects, not one failed task in any job.** The five empty buckets
needed no job; `atento-co` and `atento-cl` held only deleted versions; `redebrasil` is excluded (frozen).

**The overlap question was answered by measurement, not by argument.** The engineer chose to let
`maqnelson`'s job run through its own integration window rather than pause it — the job was still at ~91%
when `mongo_start_cron` fired at 01:20 UTC. During that overlap the integrator's worker produced **over
60,000 log lines and zero error lines** — no `AccessDenied`, no `SlowDown`, no `Throttled`, no exception
of any kind. **The KMS-contention risk this plan could not dismiss analytically is now dismissed
empirically**, on a real integration running concurrently with ~1.4M objects being re-encrypted.

**Do not read this as "S3 Batch Operations never interferes."** What was observed is this operation
(`UpdateObjectEncryption` — atomic, no data movement) on this estate, with Bucket Keys on. The account's
KMS quota was still never checked, so a job shape that consumes materially more KMS (a Copy-based
migration, or Bucket Keys off) has not been cleared by this evidence.

**Verification standard applied per bucket**, and it is the standard to repeat on the app estate: run the
same `SSES3`-filtered job again as a sweep and READ its generated manifest — success is "every key in it
sits under `kms-migration/`", never "the sweep found nothing", because AWS writes completion reports
SSE-S3 regardless of the bucket default so each sweep always finds the previous one's artifacts.
`commcenter`, `almaviva` and `maqnelson` all passed exactly that way — 3, 14 and 19 artifact keys, zero
data objects. **`maqnelson` was the last one outstanding and it closed clean on 2026-07-29**: the sweep
completed 19/19 tasks with zero failures, and every one of the 19 keys in its manifest is under
`kms-migration/reports/`. The integrator estate's verification is therefore complete, not merely its
migration.

#### Estate-wide standardization audit, 2026-07-29 — the rule, and who already meets it

**The rule, in the engineer's words:** whatever the system needs in order to run must be produced by the
module from the fact that the stack exists — never declared in a file inside the stack. *"Se o integrador
precisa do ElastCache para rodar, isso tem que ser criado junto com o módulo."* A stack defines only what
genuinely differs between environments: the name, the VPN peers, the per-country deployment map. The
reason is not tidiness — it is that **a new stack copied from `main.tf` alone must come up complete**, and
anything living in a separate stack file is something the next stack can silently omit.

**Already compliant, and they are the reference implementations: `setup`, `onboarding`, `vpn`,
`auth-001`.** Each is a single `module "this"` call and nothing else — zero resources, zero data sources,
zero locals outside the module. Their file layout is identical down to the filenames. **All six modules
that need a KMS key own one** (`setup`, `onboarding`, `vpn`, `auth`, `app`, `integrator` each have a
`kms.tf`), so the per-stack key is already universal.

**The integrator now meets it too, with one exception.** The three examples raised are all already true:
`elasticache.tf` creates the subnet group and replication group **unconditionally** (no `count`, no
`for_each`); `s3.tf` does `for_each = var.deployments`, so listing a deployment IS what creates its
bucket, already on the stack key; `kms.tf` creates key and alias unconditionally. Three of four integrator
stacks are a bare `module "this"`. **The single remaining loose resource in the whole integrator estate is
`aws_instance.windows_machine` in the atento stack** — and whether it belongs in the module is a genuine
question, because it is engineer tooling rather than something the integrator needs to run. Either the
module grows it behind a variable (on the stack key, like every other module surface) or it moves out of
the integrator stack entirely; leaving it inline is what let its volume stay unencrypted.

**The real gap is the app estate, and it is ~25× the size.** Where an integrator stack is one module call,
`app-shared-001` is **35 module calls plus 27 loose resources** across a dozen files, and `atento-001` /
`beta-001` / `demo-001` repeat the same hand-assembly (26 / 25 / 24 loose resources): `connection_pooler`,
`iam_task_role`, `iam_deploy_user`, `rds`, `mongodb`, `opensearch`, `lambda`, `ssm`, `scheduled-tasks`.
**The sharpest case is S3: only `modules/integrator` owns a bucket.** The app stacks call
`../modules/s3_bucket` from their own `s3.tf`, so the bucket exists because someone remembered the call —
a new app environment copied from `main.tf` alone comes up with none. Every one of those loose resources
is a place a module-wide change can fail to reach, which is exactly the mechanism that produced this
plan's two encryption holes; the app estate simply has 27 of them per stack instead of one.

**The divergence is NOT in naming or layout** — those are uniform across the estate, and module-owned
resources consistently derive names from the environment (`local.deployment_name`) rather than the stack,
which is what made the per-country log-group fix fall out without needing an input. The divergence is
entirely in how much of the system each stack assembles by hand, and it splits cleanly: integrator,
setup, onboarding, vpn and auth are done; the app estate is the remaining work.

#### 12c step 2 — the mechanics, kept for the app estate

> **This is the next work item, and it is written as its own numbered step because it was twice framed as
> a deferred nice-to-have and twice had to be corrected by the engineer** — most recently 2026-07-28:
> *"opa, como que o proximo é o app? e a migracao dos arquivos atuais em todos os buckets s3 cara?"*
> **The app estate does NOT start until this finishes.** The phrasing that caused the drift was "not
> required for correctness", which is true and irrelevant: the system works with mixed encryption, but
> the GOAL of this whole plan is that 4Shark's data sits under 4Shark's per-stack keys, and until the
> existing objects move, the overwhelming majority of the integrator's bytes are still under the
> AWS-managed key. Half-done is not done.

**Scope: the 11 buckets of the four active integrators**, the same set § 12c step 1 just changed —
almaviva, maqnelson, commcenter (+staging), and atento `br`/`cl`/`co`/`mx` (+staging `cl`/`co`/`mx`).
`4shark-integrator-artifacts` is NOT in scope (it is the open shared-resource question below) and
`redebrasil` is excluded like everywhere else in Phase 12.

**THE OPERATION IS `S3UpdateObjectEncryption`, NOT `S3PutObjectCopy` — and this replaces everything this
section previously said about copying objects onto themselves.** AWS shipped `UpdateObjectEncryption` on
2026-02-05 for exactly this problem, and its own documentation names our case as Example 2: *"Create a
Batch Operations job that updates SSE-S3 encrypted objects to SSE-KMS"*. It *"can atomically update the
server-side encryption type of an existing object in a general purpose bucket without any data movement,
using envelope encryption to re-encrypt the data key with your newly specified server-side encryption
type."*

**Re-wrapping 23.2M data keys is a categorically different operation from rewriting 23.2M objects**, and
every hazard the copy approach forced this plan to reason about disappears with it:

| | `S3PutObjectCopy` (the old plan) | `S3UpdateObjectEncryption` (correct) |
|---|---|---|
| Data movement | rewrites every object | none — re-wraps the data key |
| Object size limit | 5 GB, oversize fails | none stated; 20 billion objects per manifest |
| Creation date | rewritten on every object | *"preserves all object metadata properties, including the storage class, creation date, last modified date, ETag, and checksum"* |
| Lifecycle clocks | reset under the `integration-debug/*` prefixes | untouched |
| Versioned bucket | writes a new version; AES256 version lingers | acts on the current version in place |
| Storage cost | doubles until noncurrent versions expire | unchanged |

**Two consequences worth naming, because they cut in opposite directions.** The good one: the noncurrent
AES256 versions never come into existence, so the "expire the old versions" cleanup this plan kept
carrying as a separate open decision **simply does not arise** — the storage-doubling and the
"some bytes still under the AWS-managed key" questions both evaporate. The one to be honest about:
**there is no old version to roll back to.** The copy approach's reversibility came from versioning
leaving the AES256 object behind; here the change is atomic and in place. That is a smaller risk surface
rather than a larger one — nothing is rewritten, so there is no partial-write failure mode — but it is
not the same safety property, and this plan should not pretend it is.

**The properties that still hold**: nothing is unavailable at any point, because SSE-S3 and SSE-KMS
objects coexist and *"There is no change in the way that you access objects"*; the job acts on the
current version unless a version ID is given, so objects the integrator writes mid-job are already KMS
and need nothing; and the manifest generator's `MatchAnyObjectEncryption` filter scopes each run to
objects not yet on the key, so a job **shrinks on every re-run** — a failure is a partial result to
resume, never a restart.

**Preconditions checked against this estate, 2026-07-28.** `UpdateObjectEncryption` *"doesn't support
objects that are unencrypted"* — ours are all SSE-S3, so they qualify, and any exception would surface
in the completion report rather than silently. It *"fails on any object that has an S3 Object Lock
retention mode or legal hold applied"* — Object Lock is not configured on these buckets
(`GetObjectLockConfiguration` returns `ObjectLockConfigurationNotFoundError`). It needs the **full key
ARN**, never an alias — *"You can't use an alias name or alias ARN"* — which the per-stack ARNs already
give us.

**BLOCKER, and it is a tooling one: the installed AWS CLI is too old.** `aws-cli/2.28.17` rejects both
`S3UpdateObjectEncryption` and the `MatchAnyObjectEncryption` filter at client-side parameter validation
(*"must be one of: LambdaInvoke, S3PutObjectCopy, …"*), because its bundled service model predates the
2026-02-05 launch. The current release is **2.36.9**, and the current `s3control create-job` reference
lists both. **Upgrading the CLI is the fix** — "calling the API directly" does not route around it,
because the CLI *is* the API client and the block is its own model validation, so bypassing it means
hand-signing SigV4 requests against the S3 Control endpoint, which is not something to improvise on a
production migration. AWS CloudShell is the zero-install alternative (browser, pre-authenticated,
current CLI).

**`S3PutObjectCopy` remains a working fallback if the CLI cannot be upgraded** — the old mechanics are
preserved below and they do function on 2.28.17 — but it is strictly worse on every row of the table
above, and without `MatchAnyObjectEncryption` it also loses the shrink-on-re-run property, since the
generated manifest would have to include every object on every run.

**Do NOT promise a duration.** AWS publishes no throughput figure; the only statement is that jobs over
large manifests *"might take a long time to run"*. Almaviva alone is 8,241,007 objects. The job is
chunkable by `MatchAnyPrefix` / `CreatedBefore` if it needs to be paced, and every job emits a completion
report that can be scoped to failed tasks only — so progress and failure are both enumerable rather than
inferred.

**THE COUNTS BELOW ARE VERSIONS AND DELETE MARKERS, NOT CURRENT OBJECTS — do not read them as the size
of the work.** CloudWatch's `NumberOfObjects` on `AllStorageTypes` counts every version plus every delete
marker in a versioned bucket. It was caught on `atento-co`, whose metric said 18: the first job's
manifest generation *"found no keys matching the filter criteria"*, and a listing showed the bucket holds
**zero current data objects** — 9 noncurrent versions and 9 delete markers, which is exactly the 18. The
whole bucket is deleted data. **The 8.2M / 15M figures for `almaviva` and `maqnelson` are therefore an
upper bound of unknown tightness**, and every sizing statement in this section that rests on them is
provisional until each bucket's manifest generation reports its real `TotalNumberOfTasks`.

**The cheapest way to measure current objects IS the job itself** — manifest generation reports the true
count, costs nothing on an empty result, and a bucket with nothing to do simply fails fast with
`InvalidManifestContent`. So the running order below doubles as the measurement, and no separate
inventory pass is needed.

**How far off the metric actually is varies wildly per bucket, so neither direction generalizes.** On
`atento-co` it was total fiction — 18 by the metric, 0 real objects. On `almaviva` it is nearly exact —
8,241,007 by the metric against **8,218,095** real current objects from manifest generation, a gap of
about 23k. The lesson is not "the metric always overstates by a lot"; it is that the ratio of live data
to dead versions is a property of how each client's bucket has been used, and only the manifest knows.

**Per-bucket totals, measured 2026-07-28** (CloudWatch `NumberOfObjects` / `AllStorageTypes` — versions
plus delete markers, per the correction above):

| Bucket | Objects |
|---|---|
| `atento-br`, `atento-cl-staging`, `atento-co-staging`, `atento-mx-staging`, `commcenter-staging` | empty |
| `atento-co` | 18 |
| `atento-mx` | 27 |
| `atento-cl` | 50 |
| `commcenter` | 24,755 |
| `almaviva` | 8,241,007 |
| `maqnelson` | **14,960,541** |

**`maqnelson` is the largest bucket in the estate — almost double `almaviva` — and this plan said the
opposite everywhere until it was measured.** Almaviva was called "the largest" purely because it was the
one bucket anyone had counted (it was the example when the 8.2M figure was taken). Nothing else was ever
measured, and the unmeasured bucket turned out to be the big one. **The sizing story of this whole step
is `maqnelson` + `almaviva` ≈ 23.2M objects; every other in-scope bucket together is under 25k.**

**Order of execution — smallest NON-EMPTY first.** The first run must prove the job shape (IAM role,
manifest filter, report destination, copy semantics, resulting encryption) end to end, and getting it
wrong on 15M objects costs a long wait before the error surfaces. So: `atento-co` (18) → `atento-mx`
(27) → `atento-cl` (50) → `commcenter` (24.7k) → `almaviva` (8.2M) → `maqnelson` (15M).

**The empty buckets are NOT the proving ground, though an earlier draft of this section said they were.**
An empty bucket generates an empty manifest, which exercises none of the copy semantics — it proves the
job was accepted, not that it does the right thing. They need no job at all: with nothing stored, step
1's default already governs everything they will ever hold.

**Metadata and tags survive by default — the AWS blog overstates this and the API reference settles it.**
The blog says to specify object properties as part of the job; the `S3CopyObjectOperation` reference says
that for `NewObjectMetadata`, *"If you don't provide this parameter, Amazon S3 copies all the metadata
from the original objects"*, and for `NewObjectTagging`, *"If NewObjectTagging is not specified, the tags
of the source objects are copied to destination objects by default."* So OMIT both. Supplying them is
what would cause loss — an empty `NewObjectTagging` set explicitly strips tags.

**What the copy DOES change is the creation date** — *"all your objects show an updated creation date
upon completion, regardless of when you originally added them to S3."* Two consequences, one harmless and
one that was checked. The harmless one: the module's two lifecycle rules are prefix-scoped to
`integration-debug/scripts/` (7 days) and `integration-debug/audits/` (30 days), so objects under those
prefixes get their clock reset and live one extra window — a delay in cleanup, not a loss.

**The one that mattered — whether the integrator reads object age as business state — was checked, and
the answer is no.** The estate note says the integrator "cycles data between Mongo and S3 as it warms and
cools", which made object age plausibly meaningful, and a rewritten creation date across 8.2M objects is
not undoable. It turns out not to: `grep` for `last_modified` / `LastModified` across the integrator's
`app/` and `lib/` returns nothing, and `list_objects` / `bucket.objects` returns nothing across `app/`,
`lib/` and `config/` — the application never enumerates the bucket at all. Every access goes through
`integrator/app/models/s3.rb`, which builds a deterministic key (`storage/<type>/<id>.json`) and calls
`put_object` / `get_object` / `delete_object` on it. **The bucket is a keyed store addressed by id, not a
timeline**, so a rewritten creation date changes nothing the application reads.

**Storage class: every bucket is `StandardStorage` only** — verified 2026-07-28 by listing the
CloudWatch `BucketSizeBytes` metric dimensions across all of `sa-east-1`; no `Glacier`, no `IA`, no
`IntelligentTiering` on any bucket in the region. That removes the restore-first precondition the Copy
restrictions impose on archived objects, and it means `StorageClass` can be omitted from the job.

**The 5 GB ceiling is the one real limit, and it is DETECTABLE rather than silent.** Copy restrictions:
*"Objects to be copied can be up to 5 GB in size."* Enumerating the oversize objects up front is not
practical — a `list-objects-v2` over almaviva's 8.2M keys does not finish (attempted; it also did not
finish on maqnelson within two minutes). Arithmetic says they are unlikely: 45.6 GB over 8,241,007
objects averages ~5.5 KB, so a single 5 GB object would be more than a tenth of the bucket in one file.
The plan does not rest on that, though — an oversize object FAILS its task and lands in the completion
report, so the first job's report is what settles it, per bucket. If any appear, they are handled
separately with a multipart copy; do not silently leave them behind.

**Job mechanics, settled from the AWS documentation 2026-07-28:**

**The job role EXISTS as of 2026-07-28: `arn:aws:iam::405749097490:role/s3-batch-kms-migration`, created
by hand through the API and NOT in Terraform — deliberately, on the engineer's own rule**: *"o primeiro a
gente resolve direto na api e depois dropamos diretamente na api da aws"* for a one-off, and Terraform
for anything standing. This one is genuinely one-off: once every object is on the key, nothing assumes
the role again — a new object is encrypted by the bucket default at write time with no job involved, KMS
key rotation does not re-encrypt stored objects, and a NEW integrator's bucket starts empty with the key
already default, so it never needs a migration at all. **DELETE THE ROLE when § 12c step 2 completes**
(`delete-role-policy` then `delete-role`); its description says so too.

> **CORRECTION, 2026-07-29 — this paragraph used to say the app estate would need "its own temporary role
> in `us-east-1`". That is wrong, and the premise under it is wrong: IAM is a GLOBAL service — a role has
> no region.** What is regional is the *resources a policy names*, not the role. So the app migration
> reused THIS role, extended in place (`put-role-policy`) with the four `4shark-{shared,atento,beta,demo}-001`
> bucket ARNs across all three S3 statements and the four `us-east-1` `mrk-` key ARNs on the KMS statement
> — 15 buckets and 8 keys total, still enumerated, still never `*`. A second role would have bought
> nothing and left a second thing to remember to delete. **The deletion debt is therefore ONE role, not
> two, and it now waits for the app sweeps as well as § 12c step 2.**

Its inline policy is scoped to exactly the 11 in-scope bucket ARNs and the 4 integrator key ARNs, not
`*`, so a mistake in a job definition cannot reach anything outside this migration. **No key policy
change was needed**: each integrator key's S3 statement is `Principal: {"AWS": "*"}` gated on
`kms:CallerAccount` = the 4Shark account and `kms:ViaService` = `s3.sa-east-1.amazonaws.com`, so any
principal in the account acting through S3 is already covered — the role's own IAM policy is what grants.

**The role's policy was written for the COPY approach and must be widened before the first
`UpdateObjectEncryption` job.** It currently grants `s3:GetObject` / `s3:PutObject` / tagging plus
`kms:Decrypt` + `kms:GenerateDataKey`. `UpdateObjectEncryption` needs the **`s3:UpdateObjectEncryption`**
action instead of `s3:PutObject`, and AWS's documented policy for it also lists **`kms:Encrypt`** and
**`kms:ReEncrypt*`** alongside Decrypt and GenerateDataKey. Update the inline policy when the operation
switches; the role itself does not need recreating.

Its policy needs
`s3:GetObject` + `s3:PutObject` on the bucket's objects (source and destination are the same bucket
here), `s3:PutInventoryConfiguration` on the bucket — required specifically because we generate the
manifest rather than supply one — read access to the manifest location, write access to the report
location, and `kms:Decrypt` + `kms:GenerateDataKey` on the stack key so the copy can read the AES256
source and write the KMS destination.

The manifest is GENERATED, not hand-built, and that choice is what makes the step resumable: the
generator's `MatchAnyObjectEncryption` filter scopes each run to objects not yet on the key, so a re-run
picks up only the remainder. A hand-built CSV manifest would be a frozen snapshot of an 8.2M-key listing
we already know we cannot produce.

The job is created in `sa-east-1` — *"you must create the job in the same Region as the destination
bucket"* — which is where these buckets and their keys already are.

**Manifest and report both go to a dedicated prefix INSIDE the bucket being migrated.** Decided rather
than surfaced: it keeps each client's operational artifacts inside that client's own bucket, which is the
same client-scoping rule 4Shark's Output Policy already applies to S3 staging, and it avoids taking a
dependency on `4shark-integrator-artifacts` whose key question is still open. Re-runs are unaffected —
the manifest and report objects are themselves written under the new key, so the "not yet on this key"
filter excludes them from subsequent manifests. Completion reports are always SSE-S3 regardless
(*"Completion reports are always encrypted with server-side encryption with Amazon S3 managed keys"*),
which is a property of the report, not of the data.

**Verification is per bucket and must not be inferred from the job's own success count.** After each
job, re-run the same job as a VERIFICATION SWEEP — an identical `SSES3`-filtered manifest generation over
the same bucket — and independently read a sample of objects back, confirming `aws:kms` + the stack key
and that the payload still parses. This is the same discipline that caught the § 12c prerequisite being
reported applied when it was not.

**The completion criterion is NOT "the sweep finds zero objects" — it is "the sweep finds only
`kms-migration/` artifacts", and getting that wrong would read as a failed migration.** This section
previously asserted that the manifest and report objects *"are themselves written under the new key, so
the filter excludes them from subsequent manifests"*. **That is false, and the commcenter sweep proved
it**: it returned 3 tasks, and its generated manifest named exactly the previous job's own report files
(`kms-migration/reports/job-<id>/manifest.json`, `.md5`, and the results CSV) — zero data objects. AWS
writes these SSE-S3 regardless of the bucket default (*"Completion reports are always encrypted with
server-side encryption with Amazon S3 managed keys (SSE-S3)"*), so **every sweep finds the previous
sweep's own artifacts, forever.** There is no "not this prefix" manifest filter to exclude them
(`KeyNameConstraint` only matches, never excludes), so the check is to READ the sweep's generated
manifest and confirm every key in it sits under `kms-migration/`.

**EXECUTION LOG — 2026-07-28**

| Bucket | Job result | Verified against AWS |
|---|---|---|
| `atento-co` | failed, `InvalidManifestContent` — *"Manifest generation found no keys matching the filter criteria"* | listing shows zero current data objects; the bucket is 9 noncurrent versions + 9 delete markers |
| `atento-mx` | **7/7 succeeded, 0 failed, 4s** | `head-object`: `aws:kms` + stack key + BucketKey; `LastModified` still 2026-06-26; ONE version, same `VersionId`; read-back 173,268 bytes = `ContentLength` |
| `atento-cl` | failed, same empty-manifest reason as `atento-co` | — |
| `commcenter` | **24,388/24,388 succeeded, 0 failed, 33s** | two objects read back and parsed as valid JSON at exactly their `ContentLength` (4,882 and 2,925 bytes); `LastModified` still 2025-07-17 / 2025-07-24; `storage/client/1.json` still a single version |
| `commcenter` verification sweep | 3/3 succeeded | its generated manifest names ONLY the previous job's own report artifacts — **zero data objects left on SSE-S3** |
| `almaviva` | **8,218,095/8,218,095 succeeded, 0 failed** (job `bafaacc5`) | **verified three ways — see below** |
| `almaviva` verification sweep | 14/14 succeeded (job `6009d50c`) | its generated manifest names ONLY the migration job's own report artifacts (`manifest.json`, `.md5`, and 12 partitioned result CSVs) — **zero data objects left on SSE-S3** |
| `maqnelson` | **14,959,643/14,959,643 succeeded, 0 failed** (job `0f057597`) | verification sweep running (job `89e80944`); the engineer closed the step on the strength of the other three sweeps rather than blocking on it |
| the 5 empty buckets | no job needed | **confirmed empty by direct listing**, not by the CloudWatch metric — `atento-br`, `commcenter-staging`, and the `atento-{cl,co,mx}-staging` trio all return no `Contents` at all. Re-checked deliberately because that metric is what misled on `atento-co` |

**The engineer stopped the run before the two big buckets to ask whether a backup had been taken. It had
not, and the answer is worth keeping**: there is NO backup of these buckets — the only AWS Backup plan in
`sa-east-1` is `auth-001-cross-region-dr` and its only protected resource is the `auth-001` RDS instance;
`almaviva` has no replication configured either. **And versioning does not cover this operation**,
precisely because `UpdateObjectEncryption` is in place and leaves no prior version — verified on both
`atento-mx` and `commcenter`, each still showing a single version with its original `VersionId`. What
stands in for a backup here is that the operation does not rewrite the object at all, plus the empirical
checks in the table above, taken on a small real bucket BEFORE anything larger was touched. **If a future
step of this migration ever needs a genuine rollback path, it has to be created first — replication to a
copy bucket, or an AWS Backup plan — because none exists today.**

**`LastModified` preservation is now confirmed at scale, not just in the doc.** Commcenter's objects still
carry 2025-07-17 / 2025-07-24 dates after 24,388 re-encryptions, and almaviva's still read 2025-02-11
after 8.2M. Under the `S3PutObjectCopy` approach this plan originally specified, every one of those dates
would now read 2026-07-28.

**The strongest single check available was run on `almaviva`, and it is worth repeating on any future
estate: a byte-for-byte diff of the SAME object before and after.** `storage/group/1.json` was downloaded
early in the session while the bucket was still SSE-S3, and again after the 8.2M-object migration
completed. `diff` returned empty — 892 bytes both times, and the re-read reports `aws:kms` under the
almaviva key with Bucket Key on. Sampling encryption metadata proves the key changed; only the diff proves
the payload did not. **Take the "before" copy BEFORE starting, or this check is unavailable later.**

**Throughput is NOT constant, and the lifetime average is the wrong number to plan with.** Two jobs
running concurrently share the account's Batch Operations capacity: while both ran, each held ~450 obj/s.
The moment `almaviva` finished, `maqnelson` roughly doubled. A 42-second sample right after that showed
1,350 obj/s — a burst, not a rate; measured over the following 20 minutes it settled at 888 obj/s.
**Estimate from a delta across a long interval, never from the lifetime average (which carries the slow
shared-capacity hours) and never from a sub-minute sample (which catches a burst).** The counter also
advances in blocks, so two samples 19 seconds apart can show zero movement on a healthy job.

**The engineer chose to let the migration overlap the integration window rather than pause it** —
`maqnelson` was still at ~91% when its `mongo_start_cron` fired at 01:20 UTC. The reasoning for why that
is safe: `UpdateObjectEncryption` is atomic per object and moves no data, so an object is never
mid-change; SSE-S3 and SSE-KMS coexist and reads are transparent; and anything the integration writes
during the window is already born on the key from the bucket default, so the job has nothing to do with
it. **The one risk that could not be dismissed by measurement is KMS request contention** — mitigated by
Bucket Keys being on (up to 99% fewer KMS calls), but the account's KMS quota was never checked. Two
monitors covered the window: one on the jobs' failure counters, one on the integrator worker's log for
S3/KMS errors.

**What is explicitly NOT part of this step**: expiring the noncurrent AES256 versions. That is a separate
cleanup decision (storage doubles until it happens; correctness does not depend on it) and the engineer
already challenged including it here. It stays out.

#### The estate, measured 2026-07-28 — the app side is the EASY side, not the hard one

| | integrator (`sa-east-1`) | app (`us-east-1`) |
|---|---|---|
| Buckets | 12 client + `-artifacts` | 4 (`beta`/`demo`/`shared`/`atento`-001) |
| Objects (largest) | 8,241,007 (almaviva) | 45,499 (shared-001) |
| Size (largest) | ~45.6 GB (almaviva) | not measured |
| Versioning | Enabled | Enabled |
| Objects today | `AES256` (SSE-S3) | `AES256` (SSE-S3) |

**Region placement is already correct and needed no change — it just was not written down anywhere**,
which is why the engineer had to ask. All 12 integrator buckets plus `4shark-integrator-artifacts` are in
`sa-east-1` where the integrators run; all four app buckets are in `us-east-1` where the apps run.

**The app side is ~181× smaller in object count**, which is what sizes a Batch Operations job. A sampled
key — `integration-debug/audits/97/client/<timestamp>.csv` — is a write-once artifact with the date in
its name. **The engineer's read of the two workloads is borne out**: the integrator cycles data between
Mongo and S3 as it warms and cools, so object states carry meaning there; the app generates spreadsheets
for download and receives uploads for processing, never mutating them, so versioning stores nothing of
value and only doubles cost. That difference is a versioning-policy decision per estate, separate from
encryption and not urgent.

**Still open and NOT the engineer's to guess: `4shark-integrator-artifacts`.** It is shared across
integrators rather than owned by one, so there is no "its own key" to put it on. **The same question
appears in § Phase 13a as `RDSOSMetrics`** — a Region-wide log group shared by every RDS instance.
Answer them together; a shared resource under a one-key-per-stack model needs one rule, not two.

`integrator-redebrasil` is excluded from all of 12a/12b/12c: frozen, cancelled contract, resolves by
teardown.

### Phase 14 — The app estate: the LAST thing between here and the goal (surveyed 2026-07-29)

> **When the four `app-*` stacks and the two `app-outbound-*` stacks are on their own keys, this entire
> task is finished** — every 4Shark environment encrypted, each with a key of its own. The integrator,
> setup, onboarding, vpn and auth estates are already there.

**THE FINDING THAT SIZES THIS PHASE: the per-stack keys already EXIST and almost nothing uses them.**
`modules/app/kms.tf` creates `aws_kms_key.multi_region` with `alias/app-<identifier>` per stack, and all
four are live in `us-east-1` — `app-shared-001`, `app-atento-001`, `app-beta-001`, `app-demo-001`. But
the module wires that key into exactly **one** surface: `log_group_kms_key_id` (`modules/app/main.tf:62`).
Everything else in the estate still points at the SHARED `4shark-master` multi-Region key
(`mrk-fa0cda24…`), which is the key this whole plan exists to stop using — one key for every environment
is precisely the isolation failure being undone.

**34 references to the shared master key remain, and they cluster into four kinds of file:**

| File | shared-001 | atento-001 | beta-001 | demo-001 | outbound-atento-br | outbound-maqnelson |
|---|---|---|---|---|---|---|
| `rds.tf` | 4 | 4 | 3 | 3 | — | — |
| `connection_pooler.tf` | 3 | 3 | 3 | 3 | — | — |
| `iam_task_role.tf` | 1 | 1 | 1 | 1 | 1 | 1 (`iam.tf`) |
| `opensearch.tf` | 1 | 1 | — | — | — | — |

The RDS references are not one thing: they cover `storage_encrypted` + `kms_key_id` on the cluster,
`master_user_secret_kms_key_id` on the managed master password, and `performance_insights_kms_key_id` on
each instance. Each is a separate surface that has to move.

**The two outbound stacks have NO key of their own at all** — `modules/app_outbound` contains no
`aws_kms_key` resource anywhere, and no `alias/app-outbound-*` exists. They are the only 4Shark
environments with no dedicated key, so for them step 1 below is genuinely "create it", not "start using
what is already there".

#### The order, and why it is this order

The engineer set it explicitly, and it inverts what would otherwise be tempting: *"não faz sentido
padronizar agora, porque não tem padrão. Padronizar agora vai acabar gerando mais problema. A gente tem
que corrigir tudo, encriptar tudo com a chave, e depois a gente olha para o planejamento de padronização
da stack."*

**14a — Every environment has a dedicated key, created by its module.** For the four `app-*` stacks this
is already done and needs only verification. For the two `app-outbound-*` stacks it is real work:
`modules/app_outbound` grows a `kms.tf` on the shape `modules/app/kms.tf` already uses, producing
`alias/app-outbound-<client>`. Nothing consumes the new keys in this step — it is additive and carries no
risk, which is why it goes first.

**14b — Every service moves onto its stack's key.** The 34 references above, surface by surface: RDS
cluster storage, RDS managed master password, RDS Performance Insights, OpenSearch, the connection
pooler, and the task-role decrypt grants. **This is the step with real operational weight** — an RDS
`kms_key_id` change is not in-place, and Performance Insights and the managed master password each have
their own re-key semantics. Each surface needs its own research before it is planned, exactly as the
integrator's ECR (immutable, forced replace) and S3 (live setting) turned out to differ.

**14b.1 — S3 default encryption: DONE (PR #865, applied and merged 2026-07-29).** S3 was not in the
34-reference table because the app buckets pointed at no customer key at all — they defaulted to SSE-S3,
so their objects sat under the AWS-managed key. It went first precisely because it is the one surface in
the estate with **zero** operational weight: bucket default encryption is a live setting, changing it
rewrites nothing, and a bucket serves objects under mixed encryption without the reader knowing which.

What applied, identically on all four stacks (`0 to add, 3 to change, 0 to destroy`, all in-place):
`modules/app/kms.tf` gained the two S3 statements — the crypto grant scoped by `kms:ViaService` +
`kms:CallerAccount`, and the `kms:CreateGrant` gated on `kms:GrantIsForAWSResource` — on both
`aws_kms_key.multi_region` and `aws_kms_key.this`; and each stack's `s3.tf` passes
`kms_key_arn = module.app.kms_key_arn` to `../modules/s3_bucket`.

**The key-policy statements had to land in the SAME change, not after it**, and that ordering is the
reason this note exists: the policy admitted SSM and CloudWatch Logs only, so an object written under a
key whose policy does not admit S3 becomes unreadable **at read time, one object at a time**, long after
the write succeeded. Unlike a missing repository grant, that failure is silent until someone reads.

Scoped by `kms:ViaService` and never by encryption context, because **S3 Bucket Keys move the encryption
context from the object ARN to the bucket ARN** — an object-scoped condition silently stops matching the
moment Bucket Keys are enabled, and they are enabled here (Bucket Keys apply to new writes only, so they
had to be on before the objects were written rather than after).

Verified live per bucket with `get-bucket-encryption`: all four report `aws:kms` with
`BucketKeyEnabled: true`, each under a distinct `mrk-` key.

**14b.2 — S3 existing objects: DONE and VERIFIED (2026-07-29).** The objects already in the four buckets
were written under SSE-S3 and would have stayed that way; the same Batch Operations
`S3UpdateObjectEncryption` job proven on the other estate (23,202,133 objects, zero failed tasks) moved
them, in place, with no data movement.

| Bucket | Objects migrated | Failed | Sweep result |
|---|---|---|---|
| `4shark-beta-001` | 1,313 | 0 | 3 keys, all artifacts |
| `4shark-demo-001` | 3,527 | 0 | 3 keys, all artifacts |
| `4shark-shared-001` | 31,019 | 0 | 3 keys, all artifacts |
| `4shark-atento-001` | 59,295 | 0 | 3 keys, all artifacts |

**95,154 objects, not one failed task in any job.** Each sweep's generated manifest holds exactly the
three artifacts its own migration job wrote (`manifest.json`, `manifest.json.md5`, one `results/*.csv`
under `kms-migration/reports/job-<migration-job-id>/`) and zero data objects — the documented pass
condition, not an empty result.

**The estimate in this plan was ~45k–112k per bucket and the real counts are far lower, for the reason
already documented for `atento-co`**: that estimate came from CloudWatch `NumberOfObjects` /
`AllStorageTypes`, which counts versions AND delete markers rather than current objects. Do not size a
future migration from that metric.

**Integrity proved by checksum on both PRODUCTIVE buckets, not inferred from the job's own report.** A
`head-object` on a real audit CSV in each, then a full read-back and an `md5` of the downloaded bytes:
`4shark-shared-001` 3,153,873 bytes, ETag and MD5 both `5bc62b7ad06f228edc048deccf7ae504`;
`4shark-atento-001` 5,095,591 bytes, both `f44be2741d54ed2025c1858367a2afa1`. Each reports
`aws:kms` + `BucketKeyEnabled: true` under its own stack's key, and **`LastModified` still shows the
original write date** (2026-06-30 and 2026-07-07) — the in-place property holding in practice, and the
read path confirmed working through the new key policy.

**The whole S3 surface of the app estate is therefore finished** — default encryption and stored objects
both on each stack's own key.

**14b.3 — OpenSearch: DONE AND VERIFIED (2026-07-29), with two remaining cleanup items.** Both canonical
domains — `app-shared-001` and `app-atento-001` — now run under their own environment's key
(`mrk-416bffe4…` and `mrk-07429959…`), keeping their canonical names. Verified live: the applications
connect to them, and the `deals` index in each carries the DECLARED definition (`refresh_interval: -1`,
`dynamic: "false"`, all nine fields correctly typed).

**The strongest evidence is the index creation timestamps.** `atento-001` created its index at 19:51:07
UTC and `shared-001` at 19:51:30 — 23 seconds apart, both inside the deploy window that opened at 19:46.
Two independent environments creating the index seconds apart is the initializer running at boot, not a
write creating it implicitly. Corroborated negatively: zero `[search_indexes]` lines in either web log
after the deploy, where the previous deploy produced three `LocalJumpError` lines per environment.

**Two items remain, neither touching traffic**: destroy both transitional domains AND restore
`prevent_destroy` in `modules/opensearch/main.tf` (it is currently off for EVERY domain — the only open
fragility); then delete the local credential backup at
`~/Downloads/opensearch-key-migration-credentials/`.

**The app-side defect this exposed, and the two hotfixes that closed it.** The initializer never created
the index — `create!` existed but nothing called it, so an OpenSearch pointed at a fresh cluster would let
the engine auto-create `deals` with a 1s refresh interval and guessed types, reintroducing exactly the
regression ADR-0001 fixed. `3.59.1` added the creation (and carried a Rails 8.1.3.1 bump closing
CVE-2026-66066 in Active Storage). `3.59.2` removed a `rescue StandardError` that had been added on the
agent's own initiative: it swallowed the boot failure, so the first deploy was PROMOTED while the index
did not exist. Raising instead fails the health check, which makes blue/green abort and keep the running
version — the engineer caught this, and it is the reason the defect surfaced at all.

**`return` does not work inside the `to_prepare` block — measured, not theorized.** Production logs from
both environments showed `LocalJumpError — unexpected return`: the block is stored at file load and
invoked later, when no enclosing scope remains to return from. `next` exits the block correctly. This cost
one deploy cycle and is worth remembering for any initializer that guards inside `to_prepare`.

**Original 14b.3 analysis (kept for the reasoning):**

**OpenSearch: IN-PLACE IS IMPOSSIBLE, and that is an API refusal, not a downtime trade-off
(researched 2026-07-29).** AWS's own API reference for `EncryptionAtRestOptions` says it verbatim: *"Can
only be used when creating a new domain or enabling encryption at rest for the first time on an existing
domain. You can't modify this parameter after it's already been specified."* Both domains
(`app-shared-001`, `app-atento-001`, us-east-1) already have encryption at rest ON, pointed at the shared
`4shark-master` key — so the key cannot be changed on them at any price. **A new domain is the only
path**; the question is not "in place or new", it is only "how do we cut over".

**The cutover is cheap, and the data question resolves BETTER than assumed.** The engineer's premise was
that the index data is disposable because it only lives during a calculation. The code is stronger than
that: `DealSearchIndex::Producer` (`app/workers/deal_search_index/producer.rb:17`) opens with
`commission.deal_indexation_batches.delete_all` and re-indexes that commission's deals from scratch on
every recompute. There is no accumulated state to migrate — an empty new domain refills itself
commission by commission as recomputes run.

**THE OPERATIONAL PRECONDITION, set by the engineer and it is the one that governs this work: nothing may
be running when a cutover happens.** *"não vamos ter problema com dados se garantirmos que não tem nada
em execução quando fizermos."* That is the condition to verify before each repoint — an in-flight
commission recompute has `DealIndexationBatch` rows sitting in `executed`/`claimed` that reference
documents in the cluster being pointed away from, and its `Computation` counters would never reconcile.
With the pipeline idle there is no such state, which is what makes the swap safe.

**Mechanically the cutover is an env-var change plus a deploy.** The app resolves the cluster from
`OPENSEARCH_HOST` / `OPENSEARCH_USER` / `OPENSEARCH_PASSWORD`
(`app/lib/application_configuration.rb:190-199`), and the app's own `CLAUDE.md` states deploys are
zero-downtime by design. The module writes the credentials to
`/${domain_name}/opensearch/master_{user,password}`, so a new domain name produces new SSM paths that the
task definition must be repointed at.

**Two constraints the plan must respect when this is executed:**

The module carries `lifecycle { prevent_destroy = true }` (`modules/opensearch/main.tf`), so retiring the
old domain is a deliberate removal of that guard — it cannot happen by accident, and it must not happen
before the new domain is serving.

**NAMING — a correction to the premise, recorded because it changes where the work lands.** The engineer
recalled having removed an `app` prefix and wanted it restored. **The OpenSearch domains never lost
it**: they are `app-shared-001` and `app-atento-001` both in code and live (`list-domain-names`,
2026-07-29). What was renamed was the STACK DIRECTORY — commit `a9614ef` moved
`app-shared-001/opensearch.tf` to `shared-001/opensearch.tf`, and `32c5cec` moved it back ("reclaim
app-shared-001 slot"); the `domain_name` argument read `app-shared-001` before and after both. **The
resource that actually lacks the prefix is the CONNECTION POOLER** — `shared-001-connection-pooler` and
its three secrets (`app-shared-001/connection_pooler.tf:12,16,33,50`). The naming intent is real, it just
lands on the pooler, and it is settled when 14b reaches the pooler — not here.

#### The chosen sequence: temporary domain, round trip, final name preserved

**The engineer's decision, and the reason it is a round trip rather than a one-way rename:** a domain
name is unique per account per Region, so the encrypted replacement cannot be born as `app-shared-001`
while `app-shared-001` still exists. Rather than accept a permanently different name, the domain is moved
out and back — *"subimos um temporário, migramos e depois dropamos o antigo e subimos novamente e fazemos
outra migração."* The canonical name survives the migration; the cost is two cutovers instead of one.

**BOTH STACKS MOVE TOGETHER IN EVERY PR, AND CREATING A DOMAIN IS ALWAYS ITS OWN PR, SEPARATE FROM THE
REPOINT THAT USES IT.** Two constraints, and they do not conflict — which is the part that was got wrong
once and is written here so it is not got wrong again.

The engineer's constraint is **deploy count**: *"eu vou fazer dois deploys. Do jeito que você está
falando, quatro deploys vai demorar muito mais."* Moving both stacks in the same PR is what satisfies it.
**Separating creation from repoint costs ZERO extra deploys** — standing up a domain changes no task
definition, so that PR needs no deploy at all. Only a repoint does.

**Separation is what removes the race, not merely what orders it.** Bundle them and the repoint's
`OPENSEARCH_HOST` resolves to a domain created in the same apply, so correctness rests entirely on
Terraform's graph and on the provider genuinely blocking until the cluster serves. Split them and the
question disappears: by the time the repoint runs, the domain has existed for as long as it took to merge
a PR, and its credentials are already sitting in SSM.

| PR | Content | Deploys | State |
|---|---|---|---|
| 1 (#866) | Create `app-shared-001-tmp` + `app-atento-001-tmp`, each on its own stack's key | none | **APPLIED 2026-07-29** |
| 2 | Repoint both applications at the transitional domains | one per stack | next |
| 3 | Destroy both originals (lifting `prevent_destroy`), recreate each under its canonical name encrypted | none | |
| 4 | Repoint both applications back; remove the transitional domains | one per stack | |

**PR 1 applied — both stacks `5 added, 0 changed, 0 destroyed`.** Verified live with `describe-domain`:
both report `Processing: false`, `Created: true`, and each sits on its own stack's key
(`alias/app-shared-001` and `alias/app-atento-001` respectively, never the shared master). The
credentials the module generated are in SSM under each domain's own path, which is where PR 2 reads them
from.

Two deploy rounds total, exactly as asked. **Every repoint PR is gated on the pipeline being idle**
(§ the precondition above); the creation and teardown PRs are not, because they touch nothing the
application is reading.

**Reading either plan — the task-definition churn is expected, not a surprise to re-diagnose.** A task
definition is immutable, so changing `OPENSEARCH_HOST` registers a new revision and deregisters the old
one; Terraform reports that as one add plus one destroy per definition. Measured on PR 1: `shared-001`
`23 add / 7 change / 18 destroy` and `atento-001` `22 add / 7 change / 17 destroy`. The destroys equal
the count of task definitions carrying the variable (18 and 17), the extra five adds per stack are the
domain plus the credentials the module generates, and the seven changes are the scheduled tasks.

**The scheduled tasks move at APPLY time, the services only at DEPLOY time — and that asymmetry is
structural.** `aws_scheduler_schedule.task_definition_arn` records the task-definition **family**, not a
pinned revision, so it re-resolves to the newest revision on its own (the same behavior documented in the
MongoDB re-provision runbook). The long-running services keep serving their current revision until the
deploy. The resulting intermediate state — crons on the new domain, services on the old — is bounded and
harmless precisely because the cutover is gated on an idle pipeline.

**Decision recorded: each transitional domain is named `app-<stack>-tmp`.** It exists for the length of
one migration and is destroyed in PR 2, so it does not set a convention — the `-tmp` suffix says exactly
that, where a `-002` would read as a second environment and outlive its meaning if the cleanup ever
slipped.

**Decision recorded: each transitional domain mirrors ITS OWN stack, not a normalized pair.** The two
stacks already differ (`shared-001` passes `off_peak_hours`, `atento-001` does not; `shared-001` appends
a trailing slash to the endpoint URL, `atento-001` does not). Normalizing them here would fold a
standardization change into a key migration — that belongs to 14c.

**14c — Standardization, and ONLY after 14b.** The app stacks assemble by hand what the integrator gets
from its module: `app-shared-001` alone is 35 module calls plus 27 loose resources across a dozen files,
and the other three repeat it (26 / 25 / 24). The sharpest case is that **only `modules/integrator` owns
an S3 bucket** — the app stacks call `../modules/s3_bucket` from their own `s3.tf`, so a new app
environment copied from `main.tf` alone comes up with no bucket at all. Moving all of that into
`modules/app` is the same shape of work the integrator finished, and the reason it comes last is that
restructuring the stacks while their key wiring is still mid-migration would mean changing two variables
at once on every plan.

**What is NOT in this phase**: the `4shark-integrator-artifacts` bucket (shared across integrators, so no
single stack's key fits — same open question as `RDSOSMetrics` in § Phase 13a), and the two VPN root
volumes (replacing them drops every tunnel; needs its own window).

### Phase 13 — Log-group encryption across EVERY estate — MODULE WORK DONE; 14 adoption cases DEFERRED (engineer, 2026-07-27)

> **DEFERRED, not dropped — and this line is the whole reason it is written here.** The engineer chose to
> park the 14 remaining groups and move to the integrator ECR work: *"Coloca no planejamento pra gente
> voltar nisso depois e vamos focar nos integrators agora."* Everything needed to resume is in § Phase
> 13a below: the exact list, who creates each group, and the path per group. **Nothing here is blocked on
> discovery** — it is import work with two decisions attached (`RDSOSMetrics` ownership, and confirming
> the orphan is safe to delete). Resume by reading § Phase 13a; do not re-audit the account first, but DO
> re-read the live list, because a new stack adds new Container Insights groups.

**The engineer's acceptance criterion, stated by them 2026-07-27 and it governs this phase:** *"Eu só vou
colocar que isso tá finalizado quando a gente verifica que todos estão finalizados, com exceção da
redebrasil"* — every log group in CloudWatch encrypted, `redebrasil` excepted because its stack is being
decommissioned. **That criterion is not met.** Read live from AWS after the last apply, 14 groups carry
no key besides `redebrasil`'s seven.

**What IS finished, and it is the larger half:** every log group a Terraform module CREATES, in both
Regions, is encrypted under the key of the stack that owns it. PRs #850 (seven stacks), #851 (the app
service groups), #852 (crons, deploy hooks, autoscaling), #853 (the app keys re-minted multi-Region) and
#854 (the outbound replicas) are all applied and merged. No module-created group is on the AWS-owned
default anywhere.

**Correction to what this section said an hour earlier — these 14 were described as "out of this phase's
reach" and that was wrong.** Not one of them is un-encryptable; CloudWatch Logs accepts a key on any log
group, including an existing one (`associate-kms-key`). What is true is narrower: none of them is
CREATED by a module, so Terraform does not govern them, and the path is **adoption by import, not
creation**. "The module cannot reach it" was reported as "it cannot be done", which understated the work
as impossible instead of pending. The distinction is the difference between a closed phase and an open
one.

#### Phase 13a — The 14 adoption cases (deferred 2026-07-27; this is the resume point)

| Group(s) | Count | Created by | Path |
|---|---|---|---|
| `/aws/ecs/containerinsights/<cluster>/performance` | 7 | ECS Container Insights, on enable | Import into the owning stack, associate that stack's key |
| `/aws/rds/cluster/<cluster>/postgresql` | 3 | RDS, on log export enable | Import into the owning stack, associate that stack's key |
| `RDSOSMetrics` (one per Region) | 2 | RDS Enhanced Monitoring | **Needs a decision** — a single Region-wide group shared by every RDS instance, so there is no one stack whose key it belongs on. Same shape as the shared-bucket question in § Phase 12c decision 2 |
| `Lambda-app-shared-001-worker-system-autoscaling` | 1 | A pre-rename Lambda | **Delete, do not encrypt** — stale leftover beside its correctly-named, encrypted sibling; nothing in the code produces this name. Confirm nothing writes to it first |
| `EC2-start-integrator-atento-br` | 1 | Lambda, on first invoke | Import, then flip `ec2_start_lambda_log_group = true` — `modules/integrator/lambda.tf` already declares the group WITH the key behind that toggle, and this stack (plus `redebrasil`) never turned it on |

**Two of the 14 are independent of everything else and cost almost nothing** — deleting the orphan and
importing the `EC2-start` group. They were offered as fill-in work and the engineer deferred the whole
set, so they wait with the rest rather than being picked off; recorded here so the option is visible on
resume instead of being rediscovered.

**The `RDSOSMetrics` decision is the only real blocker in this sub-phase**, and it generalizes: a
Region-wide resource shared by every stack has no owner under a one-key-per-stack model. § Phase 12c
decision 2 asks the same question about a shared bucket. Answer them together or the two answers will
diverge.

> **This section was marked `DONE` twice on 2026-07-27 and was wrong both times.** The first time it
> called the phase closed in the same breath as surfacing the outbound groups as an open decision. The
> second time it closed the phase on MY criterion (module-created groups) rather than the engineer's
> (every group). Both failures are the same one: the completion claim was written to describe the work
> that had been done, instead of measured against what completion was defined to be. **The criterion
> comes first; the claim is checked against it.**

**Applied to seven stacks, all in-place, zero destruction:** `vpn` and `auth-001` (`0/3/0` each),
`setup` (`0/2/0`), and the four app stacks `beta-001`/`demo-001`/`shared-001`/`atento-001` (`0/2/0`
each — the pooler log group plus the key policy). Sixteen changes, no resource recreated anywhere.
Verified against AWS rather than trusting the apply output: every target carries a key AND kept its
data — `/ecs/auth-001-web` at 44 MB, the four poolers at ~100–134 MB each, `/ecs/setup-web`, `/ecs/vpn`
and `/ecs/vpn-staging`.

**The plan step caught a real defect before it became an incident, and this is the second time today.**
The first `setup` plan showed the log group changing but NOT the key — because the CloudWatch Logs
statements had been added only to `modules/auth` and `modules/vpn`, missing `modules/setup` and
`modules/app`. Applying that would have failed on permission at the association. Both key policies were
fixed and the plan re-run before any apply. (The other catch was the teardown's `prevent_destroy`, which
the plan disproved.) In both cases the AWS documentation had the right shape and the incomplete part was
its application.

**Two unencrypted groups surfaced that no module change can reach**, both outside this phase's scope:
`/aws/vpn/4client-redebrasil-main` (487 MB — the largest unencrypted log group in the account, on the
frozen stack, resolves at its teardown) and `/aws/ecs/containerinsights/setup-cluster/performance`,
created by Container Insights rather than by Terraform. Same class as the `EC2-start-integrator-atento-br`
orphan found in Phase 12a: a module governs what it creates, and nothing else.

**PR #851 closed the ECS-service groups — deliberately in the WRONG shape, as accepted debt.** All FOUR
app stacks (not two: `beta-001` and `demo-001` carry the identical call site and were missed in the
first count) call `modules/ecs_service` DIRECTLY from their `main.tf`, bypassing `modules/app` — they
predate it. PR #851 makes each `lookup` default to `module.app.kms_key_arn` instead of null, plus the
autoscaling-Lambda log groups in the two stacks that create them. Applied to all four (`0/9/0`,
`0/9/0`, `0/14/0`, `0/13/0`) and merged.

**PR #852 closed the three families #851 did not reach, found by auditing AWS instead of the code.**
After #851 applied, reading every log group in both regions from the live account showed 32 still on
the AWS-owned default. Each app stack calls three OTHER modules that also create log groups —
`ecs_scheduled_task` (22 cron groups), `codedeploy` (4 deploy-hook groups) and `lambda-ecs-autoscaling`
(6 groups in the two NON-productive stacks). All three modules already declared `kms_key_id` wired to a
variable; no call site passed one. Same call-site-only shape, no module change. Applied to all four
stacks (`0/8/0` each) and verified: creation timestamps unchanged from April, `storedBytes` intact, so
no group was recreated.

**The audit is the finding, not the fix.** #851's own verification read the MODULES and concluded the
work was done — and it was wrong, because two of the four stacks were already passing the key to their
autoscaling Lambdas from #851 while the other two were not. A module-level read cannot see an
asymmetry that lives in the call sites. **Verify a coverage claim against the live account, per
resource, in every region — never against the code that was supposed to produce it.**

**What remains unencrypted account-wide, and why each is not a gap in this phase.** Twelve groups are
created by an AWS service rather than by any resource block — seven Container Insights performance
streams, three RDS `postgresql` engine logs, two `RDSOSMetrics` (one per region) — so there is no
`kms_key_id` for Terraform to set and adopting them is a separate effort with a different mechanism per
service. Seven belong to the frozen `redebrasil` stack and resolve at its teardown. One
(`Lambda-app-shared-001-worker-system-autoscaling`) is a stale leftover from before the naming change,
sitting next to its correctly-named, encrypted sibling — delete it, do not encrypt it. One
(`EC2-start-integrator-atento-br`) needs an import before its stack can adopt it (see Phase 12a).

**The six `app-outbound-*` log groups — RESOLVED AND APPLIED 2026-07-27 (PRs #853, #854): replicate the
cluster key. The engineer's instinct was right and my first framing of the cost was wrong.**

**Outcome, verified in AWS.** The four app keys were re-minted as multi-Region (#853: `1 add, 19–24
change, 0 destroy` per stack, every change a log group or the alias, all in-place; ingestion measured
live 6–19s after the cut on both productive stacks). Each outbound then created a replica in
`sa-east-1` (#854). The six outbound groups now read `mrk-416bffe4…` and `mrk-07429959…` — **byte-identical
key IDs to `alias/app-shared-001` and `alias/app-atento-001` in us-east-1**, with a `sa-east-1` ARN, and
`describe-key` in that Region returns `MultiRegionKeyType: REPLICA`. That is the proof it is the
cluster's key present in a second Region, not a second key.

**The defect this exposed, and it was mine.** #853's key policy listed administration actions ending at
`kms:Revoke*` — the only `R` entry — which does not reach `kms:ReplicateKey`. So the keys were
multi-Region **in name only**: the property was set and every replication attempt failed with
`AccessDeniedException ... because no resource-based policy allows the kms:ReplicateKey action`. Fixed
in `modules/app/kms.tf` (#854) and applied to both primaries before the outbound could proceed.
**Setting a capability flag is not the same as granting the permission the capability needs** — a
wildcard list is exactly where that gap hides, and only an apply finds it.

**A partial apply happened and cost nothing, because the check was run rather than assumed.** The
failed #854 apply deregistered two task definitions before dying on the replica. The services were
pinned to revisions the apply did NOT touch (`:9`/`:8` live, both `ACTIVE`), so there was no exposure;
the re-plan then showed `0 to destroy` because the destroy had already happened. The same check was run
on `atento-br` BEFORE applying (services on `:78`/`:79`, plan deregistering `:75`/`:76`). **`ignore_changes
= [task_definition]` means terraform's tracked revision and the serving revision routinely differ — so
"terraform is destroying a task definition" is not by itself a downtime signal, and the only way to know
is to compare the two.**

§ Phase 11 makes an outbound consume its linked cluster's key and never mint its own, precisely so it
cannot lose decrypt when the cluster's key moves. CloudWatch Logs appears to forbid that, because a log
group is encryptable only by a key whose region matches — AWS states it as a property of the service
principal: *"This service principal must be in the same AWS Region where the KMS key is stored."*
(`encrypt-log-data-kms.html`, Step 2). The cluster keys are single-region — `describe-key` returns
`MultiRegion: False` on all four `alias/app-*`.

**A multi-Region key dissolves the conflict rather than compromising on it.** Verbatim: related
multi-Region keys *"have the same key material and key ID"* and *"any related multi-Region key in any
AWS Region can decrypt ciphertext encrypted by any other related multi-Region key"*
(`multi-region-keys-overview.html`). A `sa-east-1` replica is therefore not a second key that happens to
be nearby — it IS the cluster's key, present in the outbound's region. That is exactly the property
§ Phase 11 is protecting, so the rule is satisfied literally, not bent. The account already runs this
shape: `4shark-master` is a multi-Region PRIMARY in `us-east-1` with a replica in `sa-east-1` under the
same key ID.

**The blocker is one-way and it is about TIMING, not cost.** Verbatim: *"You cannot convert an existing
single-Region key to a multi-Region key."* So the four `alias/app-*` keys must be REPLACED by
multi-Region ones, and everything under them re-encrypted. **An earlier note here called that "the
largest move" and that was wrong — measured, not assumed:** `/shared-001/*` SSM parameters and the
`app-shared-001` RDS cluster both still report `mrk-fa0cda…` (the legacy master key). The heavy surfaces
have NOT migrated — that is Phases 3–8, still pending. What actually sits under the dedicated app keys
today is the log groups wired this week, re-associated in-place. **The window is now, and it closes:**
make the app keys multi-Region before Phases 3–8 and the whole app estate lands on them once; do it
after and the same migration is paid twice.

**Mechanism, checked against the code rather than assumed.** `modules/app` sets `multi_region = true` on
`aws_kms_key.this`; the outbound stack creates `aws_kms_replica_key` in `sa-east-1` pointing at the
cluster key's ARN. No new provider wiring is needed — `app-outbound-*/providers.tf` ALREADY declares
both a default `sa-east-1` provider and a `us-east-1` alias (added to read the cluster's SSM
parameters). The replica needs its OWN key policy granting `logs.sa-east-1.amazonaws.com`, because
policy is an *independent property* of a replica and is never synchronized from the primary — only key
ID, key material, key spec, usage and rotation are shared.

**The integrator keys need none of this.** They live in `sa-east-1` with no cross-region sibling, so a
single-region key is already the right shape there. The asymmetry is real and worth stating: only the
app family has a consumer in a second region.

**Why this is debt and not a solution.** The engineer's requirement was explicit — *"não ser algo que
fica no main.tf, o módulo já cria os logs com a chave"* — and this puts the key in the stack's
`main.tf`, which is exactly the forgetting surface it was meant to remove. The structural fix is the
one the integrator already demonstrates: the SERVICES belong inside the estate module, and the module
passes the key at its own call sites, so no stack ever needs to know a key exists. For the app estate
that means moving the service definitions out of the four `main.tf` files and into `modules/app`.

**Decision, 2026-07-27: take the debt now, correct it in the app estate work.** The interim ships so
CloudWatch Logs is closed account-wide and can be verified as a whole; the refactor happens when
Phases 3–8 touch the app estate anyway, which is after the integrator finishes. Recording it here
because a remedy deferred without a written trace is a remedy abandoned. **PR #852 widened this same
debt from one module to four** — the cron, deploy-hook and autoscaling call sites now carry the key in
the stack too, so the app-estate refactor has four families to absorb, not one.

**Correction — `onboarding` was never a gap.** An earlier note in this plan claimed it created log
groups in the stack. It does not: neither the stack nor `modules/onboarding` declares any, its three
sub-modules (`networking_data`, `ecr`, `iam_deploy`) create none, and no log group with `onboarding` in
its name exists in us-east-1. The claim was inferred from "the module does not create them" rather than
checked.

#### Survey as of 2026-07-27 (kept for the record)

This was the survey that scoped the sweep, written before PR #850 and kept because it is the map of
where log groups are created — the thing that had to be established once and would otherwise be
re-derived by the next person. **Every "does not set a key" below was resolved by PR #850 except the
last paragraph**, which names what a module change cannot reach.

**Every estate module already OWNED a key** — `modules/{integrator,app,auth,vpn,setup,onboarding}/kms.tf`
each declare `aws_kms_key.this`. Nothing was blocked on minting keys; the sweep was a wiring job.

**Where log groups are created, and how each was resolved:**

| Module | Groups | Resolution (PR #850) |
|---|---|---|
| `auth` | `web` (logs.tf:1), `staging_web` (auth_001_staging.tf:14) | wired to the module's own key |
| `vpn` | `vpn` + `vpn_staging` (logs.tf:1,12) | wired to the module's own key (`alias/vpn`, previously minted and idle) |
| `connection_pooler` | `this` (main.tf:241) | optional argument, fed the APP stack's key — the pooler is a dependency of the app stack, not a stack of its own, and the rule is one key per stack |
| `codedeploy` | `codedeploy_hook` (main.tf:227, conditional) | optional argument; `setup` passes its key, inert while the hook is disabled |
| `lambda-ecs-autoscaling` | `this` (main.tf:5, conditional) | optional argument added; no caller wires it yet |

**The generic sub-modules and their callers.** `ecs_service` has carried
`cloudwatch_log_group_kms_key_id` all along, and `ecs_scheduled_task` gained `log_group_kms_key_id` in
PR #849. `modules/setup/main.tf:304` now defaults its `lookup` to the stack's key instead of null, so a
service added to the map is encrypted unless deliberately overridden. **The two that remain are
`app-shared-001/main.tf:566` and `app-atento-001/main.tf:527`**, which call `ecs_service` directly from
the stack — older-style stacks not yet on `modules/app`, so no module change reaches them — plus
`onboarding`, which creates its log groups in the stack rather than in `modules/onboarding` (whose three
sub-modules create none). All three are the same one-line change.

**The prerequisite each estate inherits from 12a.** A key cannot encrypt a log group until its policy
admits the `logs.<region>.amazonaws.com` service principal, narrowed by `ArnLike` on
`kms:EncryptionContext:aws:logs:arn` — the via-service shape used for SSM/ElastiCache/EC2 does NOT work
for CloudWatch Logs, because Logs encrypts on ingest as itself. Every key needed that statement before
its log groups could reference it. **This is the prerequisite that was half-forgotten and that the plan
step caught**: PR #850 initially added it to `auth` and `vpn` only, and `setup`'s plan showed the log
group changing without the key — the tell. `modules/setup/kms.tf` and `modules/app/kms.tf` were fixed
before any apply ran. All four estate keys now carry it, in whichever form each file already used: where
via-service was expressed as a list, the logs entry joined the list; where it was a single value, a
separate statement carries it.

**The productive applies went without incident.** `app-shared-001` and `app-atento-001` were applied
last, deliberately, so they ran with five prior confirmations that the policy shape works in practice
rather than only in plan. Both came back `0 added, 2 changed, 0 destroyed`.

**Scope note — `simplex-harvester` is already covered.** Its log groups are created by
`modules/integrator/harvesters.tf` through `ecs_scheduled_task`, so PR #849 encrypted them; there is no
separate harvester estate to sweep.

### Phases 3–8 — The app estate: module-owned keys, data migration, and naming (RESTRUCTURED 2026-07-20)

**Carried in from Phase 13 (2026-07-27): the app-estate log-group debt is corrected HERE.** The four app
stacks call FOUR log-group-creating modules directly from their own `.tf` files rather than through
`modules/app` — `ecs_service` (the services), `ecs_scheduled_task` (the crons), `codedeploy` (the
deploy hook) and `lambda-ecs-autoscaling` (the scaling functions) — so in every one of those the key is
passed at the stack call site, the shape the engineer explicitly rejected. Moving those definitions
into `modules/app` is what makes the guarantee structural, and it belongs in this phase because it is
the same act as everything else here: the module owns what the stack currently improvises. Do not treat
the Phase 13 interim as finished work.

**This supersedes the original per-resource-type Phases 3–8** (create keys → SSM → Secrets Manager →
RDS snapshot/restore → legacy RDS → retire). The design converged on two decisions taken after the
integrator work landed: (1) the KEY is created BY THE MODULE, not per-stack — the same forward-lock
Phase 10 applies to the integrator module, so the app-estate key split and Phase 10 are the SAME act
for these stacks (`modules/app` / the `onboarding` / `setup` stacks mint `alias/app-<stack>` etc.); and
(2) RDS and OpenSearch, previously listed as blocked/out-of-scope for having no in-place rekey, get a
**replace** path — a new resource under the correct key, which also lets the estate's non-standard
names be corrected in the same move. Runs beta → demo → shared-001 → atento-001 → onboarding → setup,
verified between each; productive stacks (shared-001, atento-001) on a real window.

**Current encryption state (verified 2026-07-20):** none of `app-*` / `onboarding` / `setup` has a
dedicated key. Their SSM SecureStrings sit on the AWS-managed `alias/aws/ssm` (no `kms_key_id` set —
`app-shared-001/ssm.tf:25`), while RDS storage, the connection-pooler Secrets Manager secrets,
OpenSearch, and Performance Insights sit on the shared multi-region `4shark-master`
(`mrk-fa0cda243274491784fc7b39bead5a03`, us-east-1). So this is the REAL key split for these stacks
(create + migrate the data), not the clean `state mv` the integrators got.

**Superseded for `onboarding` — DONE 2026-07-22 (see the surface-2 entry in § Execution order).** This
2026-07-20 snapshot is stale for onboarding on two counts: it now HAS its dedicated key with its SSM on it,
and the "SSM on `alias/aws/ssm`" claim was never true for onboarding specifically — its 11 parameters were
on `4shark-master` (the 2026-07-17 probe had already moved them there), which is what the migration rekeyed
onto `alias/onboarding`. Onboarding also turned out to have no RDS / OpenSearch / pooler at all (removed when
it went idle), so "create + migrate the data" reduced to the SSM rekey for it. `setup` is being migrated in a
parallel session; the snapshot stands for `app-*` until those run.

**Per-stack playbook — ONE procedure, applied per stack in the order above:**

1. **Module mints the key. — DONE for app (PR #786, merged 2026-07-20).** `modules/app` creates its own
   `aws_kms_key` + `alias/app-${var.identifier}` + the two-statement via-SSM policy (account/region from
   data sources), ARN exported as `kms_key_arn`. Importing `modules/app` is enough — no per-stack file.
   All four app cluster stacks (`beta-001`, `demo-001`, `shared-001`, `atento-001`) now carry their key,
   created and unused. **Cycle learning (do NOT re-derive):** the key sits INSIDE `modules/app` even
   though `modules/app` is a downstream cluster/pooler wrapper — this is safe ONLY because `modules/app`
   does NOT consume the stack's SSM parameters (the app services live in the stack), so the stack's
   parameters reference `module.<app>.kms_key_arn` one-directionally with no cycle. A standalone
   `modules/kms` imported by each stack was tried and REJECTED: it delivers the key but requires a
   per-stack `kms.tf`, which the engineer explicitly refused ("import the module → get the key,
   automatic, no file"). **For `onboarding` / `setup`, verify the same before placing the key**: the key
   goes into their extracted composition module ONLY if that module does not consume their SSM params;
   if it does, the params must move into the module too (or the key sits upstream of them). New stacks
   are then born with a correctly-named dedicated key by construction.
2. **Rekey the rekeyable data onto it** — SSM SecureStrings (`put-parameter --overwrite --key-id`,
   value-preserving, bumps version — engineer's step, secret values) and the connection-pooler Secrets
   Manager secrets (`UpdateSecret --kms-key-id`). Keep decrypt on the old key until each re-encryption
   is confirmed (the documented no-op trap). The dedicated role's `-ssm-read` MUST carry explicit
   `kms:Decrypt` on the new key — the AWS-managed `alias/aws/ssm` auto-granted it, a customer-managed
   key does not.
3. **RDS — blue/green replace (engineer's approach 2026-07-20).** RDS storage encryption key is
   immutable after creation, so instead of a downtime snapshot/restore: stand up a NEW RDS under the
   correct key AND the correct name, set it to pull live/real-time data from the original (read replica
   / logical replication), wait until fully synced, then deploy the app pointing at the new DB; once
   nothing still reaches the old one, decommission it (cut its connection so the app stops trying the
   old). Near-zero downtime, and the new instance is created with the standard name.
4. **OpenSearch — replace in a quiet window (engineer's approach 2026-07-20).** The OpenSearch data does
   NOT need to persist (no in-place rekey exists, and none is needed): in a window with no processing
   running, stand up a NEW domain under the correct key and name, point the app at it, tear down the
   old. The "no processing at the moment" precondition is what makes the data loss safe.
5. **Retire `4shark-master` for this stack's scope** only once nothing the stack owns references it.

**Naming standardization — DECIDED 2026-07-20, folded in because the replaces create new resources
anyway.** The app estate's resource names are inconsistent (part carries the `app` prefix, part does
not). The standard is the `app` prefix on everything — `app-<name>-001`. Because RDS and OpenSearch are
recreated (steps 3–4), name the new resources correctly THEN, at no extra cost. **Discovery point:**
enumerate the current non-conforming names per stack before the replace, so each new resource lands on
the standard name and nothing is missed. (Naming is a design decision — confirm the exact target names
with the engineer per stack before creating.)

**The `app-outbound-*` exception — consume the cluster's key, migrate in lockstep (verified
2026-07-20).** An outbound application shares the secrets of the app cluster it connects to, so it must
decrypt on that CLUSTER's key, never mint its own. `modules/app_outbound` therefore takes the connected
cluster's key (its deterministic `alias/app-<cluster>`) and grants decrypt on it — it does NOT create a
key. **The mapping is by real connection, NOT by name** (the name misleads): `app-outbound-atento-br`
connects to `app-atento-001` (decrypts `mrk-fa0cda…`, monitoring `app-atento001-api`), and
`app-outbound-maqnelson` connects to `app-shared-001` (monitoring `app-shared001-api`) — NOT a
"maqnelson" cluster. When a cluster moves off `4shark-master` onto its dedicated key, its outbound's
decrypt grant must repoint to the SAME new key in the same move, or the outbound loses decrypt of the
cluster's secrets. Sweep every task-def still naming the shared role before dropping any grant — the
outbound misses (#769/#774) are the standing warning that a desired-0 or cross-region consumer hides
from a same-stack-only check.

### Phase 9 — The five integrators (sa-east-1, customer-managed key per integrator)

> **Status 2026-07-24: Phase 9 is DONE and merged — all three steps.** The 2026-07-20 note below was
> written when only step 2 (the minted key) was done; it is now fully superseded. Three merged commits
> executed the role split and the rekey across all five stacks: `86e797f` (dedicated task-execution role
> + kms key on all five), `304af61` (tighten grants to the dedicated key, drop the shared-role
> `ssm-read`), `32ac8ad` (module owns the key + ends default-SG drift). Every stack's `iam_task_role.tf`
> carries `integrator-<slug>-ecs-task-execution-role` (+ `-ssm-read` with explicit `kms:Decrypt` on its
> own key, + `-ecs-exec`); every `compute.tf` points its task defs at that dedicated role; nothing
> references the account-wide `ecsTaskExecutionRole` any longer. Step 3 (move SSM onto the key) is applied
> in AWS, not just code — maqnelson's 12 `/integrator-maqnelson/*` parameters are confirmed on
> `alias/integrator-maqnelson` (`aws ssm describe-parameters`, 2026-07-24), and the four other stacks
> carry the identical code. The Redis standardization is Phase 9a/9b (merged: #821/#826/#827/#829). **What
> remains for the integrators is NOT here — it is the remaining `4client-` legacy naming families.**
>
> **`4client-` legacy naming — state as of 2026-07-24 (verified by reading the stacks + the `dns` stack):**
> - **Redis — DONE** (#821/#826/#827/#829; ADR-010 updated in #830). Only remnant is the frozen redebrasil
>   `ec-redebrasil`, which goes at teardown.
> - **MongoDB — effectively DONE, not pending as the ADR still implies.** almaviva/atento/commcenter/maqnelson
>   are already on `integrator-<client>-mongoNNN` — both the EC2 Name tags and the `dns` stack records
>   (`dns/internal_dns_integrator.tf:15-120`; maqnelson `integrator-maqnelson/mongodb.tf:35-160`). The naming
>   migration happened as a **node replacement** (the `mongodb-reprovision` skill: fresh nodes, join, cutover),
>   not an in-place rename — the `4client-` trios were retired at cutover. The SOLE remaining `4client-` Mongo
>   is **redebrasil** (`dns/internal_dns_integrator.tf:139/151/163`). Its path is **teardown of the stack**, NOT
>   a reprovision: redebrasil is a cancelled contract, frozen this session (`integrator-redebrasil/freeze.tf`
>   blocks every apply), and reprovisioning a database about to be deleted is wasted work — the freeze would
>   also block the reprovision's own applies. Do not reprovision redebrasil; tear it down.
>   *(Follow-up CLOSED 2026-07-27: ADR-010 was corrected and is now current. Its § "Legacy exception —
>   integrator `4client-` (retired 2026-07)" lists all four families — Redis, MongoDB, default SG, VPN
>   edge — as retired onto `integrator-<client>`, and states that the only remnants are on the frozen
>   cancelled-contract stack. The closing audit confirms that claim against AWS: the only `4client-`/`ec-`
>   names left in the account are `4client-redebrasil-mongo00{3,4,5}` and `ec-redebrasil`. **Nothing is
>   owed on the naming standardization** — it resolves by that stack's teardown.)*
> - **Default security group `4client-<client>` — DONE, applied + merged (#831, 2026-07-24).** The default
>   SG's Name tag was renamed `4client-<client>` → `integrator-<client>` in the module (`security.tf`).
>   Applied to the four active integrators as an in-place tag change (`0 add / 1 change / 0 destroy` each — the
>   SG id and its rules are unchanged, so zero downtime); redebrasil frozen (skipped). The default SG's
>   group-name is immutable (always `default`), so the Name tag is the only "name" it has. (#831 first
>   decoupled the SG from `name_prefix`; #832 re-coupled it once `name_prefix` itself moved to `integrator-`.)
> - **VPN edge `4client-<client>-*` — DONE, applied (#832, 2026-07-24). A ~1 min tunnel bounce per connection,
>   NOT zero-downtime.** The one-line flip of `local.name_prefix` from `4client-` to `integrator-`
>   (`modules/integrator/main.tf`) renamed every VPN resource. The gateway / customer gateway / connection
>   carry the name in a tag (in-place); the CloudWatch tunnel log group's name is force-new, so it is recreated,
>   and the connection then re-applies its tunnel log config. **The earlier "no service disruption" read
>   (provider issue #26876) was WRONG for this case** — the connection modify does a real per-tunnel
>   replacement: on almaviva, tunnel 1 went DOWN 16:14:34 → UP 16:15:29 (~55 s). Because every integrator here
>   is single-tunnel BY DESIGN (the second tunnel was never established — confirmed by the engineer, not a
>   regression), that bounce is a full ~1 min VPN outage per connection, with no second tunnel to carry
>   traffic. The engineer accepted it deliberately: applied inside a ~7-8 h processing-free window (next
>   integration run far off), so a 1-minute outage is harmless. Verified post-apply: all four active
>   integrators' connections are `available` with the primary tunnel `UP` (almaviva; commcenter; maqnelson;
>   atento ×3 — azure, co-cirion, mx-equinix). redebrasil frozen (skipped). **Lesson recorded: renaming a
>   `4client-` resource that a live `aws_vpn_connection` references (a log group ARN) bounces the tunnel ~1 min
>   — schedule it in a processing-free window, do not treat it as zero-downtime.**
>
> So the `4client-` naming cleanup is **DONE for every active integrator**: Redis, MongoDB, the default SG, and
> the VPN edge are all on the `integrator-<client>` standard. The only `4client-`/`ec-` names left are on the
> frozen redebrasil stack, and they go at its teardown. There is no further integrator naming family to migrate.
> *(ADR-010 follow-up DONE — #833, 2026-07-24: the legacy-exception section now records the `4client-` naming as
> retired family by family, leaving only the redebrasil-until-teardown note.)*
>
> **Integrator follow-ups (engineer, 2026-07-24) — both DONE for the active integrators; outbound remains:**
> 1. **Full `4client-` audit — DONE.** Swept the whole repo (80 hits), classified into: zero-downtime tag
>    renames (the `networking/` layer — VPCs, subnets, route tables, TGW attachments, peering), applied in #834;
>    the app_outbound family (its own PR, still open — see below); redebrasil (frozen → teardown); and
>    docs/comments (left). The integrator side of `4client-` is now fully retired — Redis (#821/#826/#827/#829),
>    MongoDB (reprovision), SG (#831), VPN (#832), networking (#834), all `integrator-<client>`. ADR-010
>    recorded it (#830, #833).
> 2. **Standardize the integrator stacks — DONE, merged (#835 three stacks + #836 the multi-jurisdiction one).**
>    Every active integrator stack now has a `variables.tf` + `terraform.tfvars` driven by a single
>    `client_name`, with every `integrator-<client>` name/slug derived from it — matching setup/onboarding/vpn/
>    auth. The redundant per-stack duplication is gone. Verified zero-diff: `terraform plan` returned **No
>    changes** on all four (the resolved values are identical), so it was a pure code refactor, no apply. What
>    stayed hardcoded: the backend state key and module block labels (neither takes a variable) and display
>    values (capitalized name, emails). redebrasil left out (frozen — freeze blocks even a plan).
>
> **Still open — the app_outbound `4client-` rename (audit category 2).** `modules/app_outbound` (used by both
> `app-outbound-atento-br` and `app-outbound-maqnelson`) still has `name_prefix = "4client-app-outbound-<client>"`,
> plus the atento-br outbound VPC/TGW/peering tags in `networking/`. Its `vpn.tf` has NO CloudWatch log group, so
> unlike the integrator VPN the rename is in-place tags only — **zero downtime, no tunnel bounce** (verify with a
> No-changes/0-destroy plan). Target `app-outbound-<client>` (ADR-006/010). This was started, then deferred at the
> engineer's request to finish the integrators first; it is the last `4client-` item outside the frozen redebrasil.
>
> **Original 2026-07-20 note (superseded, kept for history):** the dedicated key per integrator is already
> MINTED — `modules/integrator` creates `alias/integrator-<slug>` by construction
> (`modules/integrator/kms.tf`, Phase 10 done via #785). So step 2 below ("customer-managed key per
> integrator") is DONE; what remains is the role split (step 1), moving SSM onto the key (step 3), plus the
> naming + Redis standardizations. The population table in § Scope ("on the AWS-managed `alias/aws/ssm`")
> predates #785 and is stale for the key — the key is customer-managed now.

The six-stack estate above is DONE (beta, demo, shared-001, atento-001, setup, onboarding, plus the
two sa-east-1 `app-outbound-*` siblings). The five integrators are the last population, and unlike the
estate they sit in sa-east-1 on the **AWS-managed** `alias/aws/ssm` key — decided in-scope 2026-07-20
because the goal is per-integrator access delegation (see § Scope). Each integrator gets the SAME
expand/contract treatment the app stacks got, plus a key move the app stacks did not need (they were
already on a customer-managed key; the integrators are not):

1. **Role split** — each integrator names the account-wide `ecsTaskExecutionRole` in its task defs and
   carries an `integrator-<slug>-ssm-read` on it (11-of-15 rule, § Two facts). Give each its own
   `integrator-<slug>-ecs-task-execution-role` (+ `-ssm-read` + `-ecs-exec`), point its task defs at
   it, cut over, then drop the shared grant — identical to Phase 2, sa-east-1.
2. **Customer-managed key per integrator** — one regional sa-east-1 key each, two-statement policy
   (§ The key policy) naming only that integrator's new role. This is what the AWS-managed key could
   never carry, and what makes "Santiago reaches only Atento" expressible.
3. **Move SSM onto the key** — rekey each integrator's parameters off `alias/aws/ssm` onto its own key
   (`put-parameter --overwrite --key-id`, bumps version — Phase 4 mechanics). **Discovery point**: the
   integrator role's SSM read today is likely `ssm:GetParameters` ALONE — an AWS-managed SSM key
   auto-grants decrypt to any SSM caller in the account, so no explicit `kms:Decrypt` was ever needed.
   A customer-managed key does NOT auto-grant; the dedicated role's `-ssm-read` MUST add explicit
   `kms:Decrypt` on the new key, or the task fails secret resolution on cutover. Verify this before the
   move, per integrator.

**Granularity — DECIDED 2026-07-20: one key per STACK (see SPIKE Finding 16).** A stack that carries
both a production and a staging cluster (e.g. `integrator-commcenter` + `integrator-commcenter-staging`,
same stack, same network) gets ONE key, not one per cluster. The two AWS axes disagree on this cell —
classification (SEC08-BP02) says split prod from test, tenancy says same entity → same key — and the
tie breaks toward one key because the keys exist for per-integrator access delegation, whose boundary
is the integrator/stack, not the cluster. Intra-stack prod/staging isolation, if ever wanted, comes
from SSM encryption-context conditioning (`/commcenter/*` vs `/commcenter-staging/*`, SPIKE Finding 6)
on the single key, not a second key. **Flip condition, named so it is not re-derived:** the day 4Shark
wants staging-only (or prod-only) delegation — a principal allowed on an integrator's staging but NOT
its production — prod and staging need separate keys. Until that is a stated need, one key per stack.

**Discovery point to settle at step 1, before touching anything — stack-vs-slug count.** The SSM policy
list names five (`almaviva`, `atento`, `commcenter`, `maqnelson`, `redebrasil`), but sa-east-1 carries
many more integrator task-def families (`integrator-atento-br/-cl/-co/-mx` + staging + harvesters).
"One key per stack" still needs the stack unit pinned down: confirm whether a client's jurisdiction
variants (`atento-br`/`-cl`/`-co`/`-mx`) are ONE Terraform stack or several — read the stacks, do not
assume. A single `terraform` stack = one key; separate stacks = separate keys, per the rule above.
- **The same cross-region-sibling sweep the outbounds needed.** Before dropping any
  `integrator-<slug>-ssm-read` from the shared role, sweep EVERY task-def still naming the shared role
  that reads that integrator's prefix — the outbound misses (#769/#774) are the standing warning that a
  desired-0 or cross-region consumer hides from a same-stack-only check.

Order: one integrator (family) at a time, verified between each; start with the one whose access
delegation is wanted first (Atento, the Santiago driver) unless a lower-risk integrator is preferred as
the shakedown.

### Phase 9a — Integrator Redis: reserve DB /0 + new instance, staged (engineer, 2026-07-24)

**The engineer chose to START the integrator effort with the Redis (ElastiCache).** This subsection is the
Redis half of Phase 9's "naming + Redis standardizations"; the role-split/rekey half stays as Phase 9 above.
Recorded now so the multi-stage shape is not forgotten — execution comes later.

**Current state (read from Terraform 2026-07-24, do not re-derive).** Each integrator has its OWN dedicated
ElastiCache created by the module — `modules/integrator/elasticache.tf:7`, `aws_elasticache_cluster.redis`,
`cluster_id = "ec-<client>"`, single node, `default.redis7`, tag `...-redis001`, reached at DNS
`4client-<client>-redis001.4shark.internal:6379`. **The logical DB index each app uses lives in the `REDIS`
env var of that app's `compute*.tf`** (NOT in the module) — a bare `:6379` means DB 0. Redis exposes 16
logical DBs (0–15). Live allocation:

| Integrator | App (`compute*.tf`) | Current DB |
|---|---|---|
| almaviva | `compute.tf` | **/0** |
| atento | `compute_br.tf` | **/0** |
| atento | `compute_mx.tf` | /1 |
| atento | `compute_cl.tf` | /2 |
| atento | `compute_co.tf` | /3 |
| atento | `compute_mx_staging.tf` | /4 |
| atento | `compute_cl_staging.tf` | /5 |
| atento | `compute_co_staging.tf` | /6 |
| commcenter | `compute.tf` | **/0** |
| commcenter | `compute_staging.tf` | /1 |
| maqnelson | `compute.tf` | **/0** |
| redebrasil | `compute.tf` | **/0** |

> **Verify at execution:** the engineer said Atento has 8 apps (4 countries × prod+staging), but only 7
> `REDIS` entries were found — no `compute_br_staging.tf` REDIS surfaced. Confirm whether an Atento BR
> staging app exists and where its Redis index is, before reallocating.

**Why reserve /0 — the future coordination counter (Stage 3, DEFERRED, NOT now).** Today, when an
integration finishes, the client's Mongo is shut down to save cost — but only when the integrator has a
SINGLE app. A multi-app integrator (commcenter = 2, atento = 8) never shuts its Mongo down, so the Mongo
runs (and costs) whenever ANY of its apps is idle-but-present. The intended fix: reserve Redis DB **/0** as a
shared coordination counter per integrator. Before an app runs it INCRs the /0 counter; when it finishes it
DECRs; whichever app sees the DECR reach zero was the last one running and may shut the Mongo down. **The
integrator application change that implements this counter/shutdown is explicitly OUT OF SCOPE of the
current work** — the engineer does not want it built now.

**Scope — RedeBrasil is 100% untouched (engineer, 2026-07-24): it is being decommissioned.** It gets no new
Redis, no repoint, no /0 change; its app stays on /0 on the old cluster until the whole stack is torn down.
The four in scope are **`almaviva`, `atento`, `commcenter`, `maqnelson`** ("the other four").

**The staging — three PRs (engineer, 2026-07-24).** The engineer refined the sequence so the whole fleet
moves as one, cleanly:

1. **PR 1 — stand up ALL the new Redis at once.** One PR adds a brand-new ElastiCache for each of the four
   in-scope integrators, born with the new standardized name and **encrypted at rest under that integrator's
   dedicated `alias/integrator-<slug>` key** (the module already mints the key — Phase 10). The new clusters
   are added ALONGSIDE the old ones; nothing points at them yet, so PR 1 is additive and zero-risk to running
   apps.
2. **PR 2 — repoint the apps. DONE, applied, merged (#826, 2026-07-24).** Each app's `REDIS` env in
   `compute*.tf` now points at the new `integrator-<client>-redis001.4shark.internal` host with a DB index in
   **/1–/15** (reserving /0); the `dns` stack got the four new CNAME records (`aws_elasticache_replication_group`
   data source → `primary_endpoint_address`). Applied in order: `dns` (4 records added) → almaviva/maqnelson
   (4 task-def revisions each) → commcenter (8) → atento (25); every "destroy" is an immutable ECS task-def
   revision being replaced, no service/cluster/data touched. Before applying atento, all four atento clusters
   were confirmed idle (0 running tasks — CL's run is at 14:00 UTC), the first to exercise the new Redis.
   Convention now in force: **/0 reserved, apps use /1–/15, at most
   15 apps per Redis**. DB layout applied — almaviva /1; atento br/1 mx/2 cl/3 co/4 mx_staging/5 cl_staging/6
   co_staging/7; commcenter prod/1 staging/2; maqnelson /1. **PR #826 merged (2026-07-24).**
3. **PR 3 — drop the old Redis. DONE, applied, open as #827 (2026-07-24).** Removed the legacy `ec-<client>`
   clusters and their `4client-<client>-redis001` DNS records for the four migrated integrators; RedeBrasil's
   `ec-redebrasil` is kept (decommissioning, out of scope). The old cluster is gated off in the shared module
   by `count = var.create_new_redis ? 0 : 1` with a `moved` block so RedeBrasil's still-live cluster is
   re-homed, not recreated. Final AWS state verified: only `ec-redebrasil` remains. **Incident during apply:**
   the PR-3 worktree directory vanished mid-apply (likely a concurrent session's cleanup), so 3 of the 4
   cluster-drop applies failed with "no such file or directory" after `dns` (4 records) and `almaviva`
   (ec-almaviva) had already applied; recovered by recreating the worktree from the branch and re-applying
   maqnelson/commcenter/atento. No outage — the old clusters were already unused (apps on the new Redis).
   **PR #827 merged (2026-07-24) — the integrator Redis migration is complete end to end.**

**PR 1 status — DONE, applied to all four, merged (#821, 2026-07-24).** Each stack applied clean: **1 added,
1 changed, 0 destroyed** — `integrator-<client>-redis001` created (encrypted replication group) and the
dedicated key's policy updated in-place; the legacy `ec-<client>` cluster is untouched and still serves the
apps (nothing repointed yet). The four new instances are live and idle. **Next is PR 2** (repoint the apps:
new `primary_endpoint_address`, DB index in /1–/15 with /0 reserved, deploy). Two findings that PR 2/PR 3
must carry:
- **The new Redis is an `aws_elasticache_replication_group` (single node, `num_cache_clusters = 1`), NOT an
  `aws_elasticache_cluster`.** Terraform's standalone `aws_elasticache_cluster` does not accept
  `at_rest_encryption_enabled` / `kms_key_id` — customer-managed at-rest encryption is only on a replication
  group. Consequence for **PR 2 (DNS repoint)**: the `dns` stack's data source for the new host must be
  `data.aws_elasticache_replication_group` and its endpoint is `primary_endpoint_address` — NOT the legacy
  `data.aws_elasticache_cluster` + `cache_nodes[0].address`. The legacy record keeps the old shape until PR 3.
- **The key policy was widened from SSM-only to SSM + ElastiCache** (`modules/integrator/kms.tf`: a crypto
  statement scoped `kms:ViaService = elasticache.sa-east-1.amazonaws.com` plus `kms:CreateGrant` constrained
  by `kms:GrantIsForAWSResource = true`). This is in the SHARED module, so it is present in code for all five
  integrators, but only applied on the four in PR 1; RedeBrasil's stack is never applied. The gate is
  `var.create_new_redis` (default false), set true only in the four active stacks.

**Target DB layout on each new Redis (PR 2), /0 reserved (fresh instance, assign cleanly):**
- **almaviva**: app → /1
- **atento**: br→/1, mx→/2, cl→/3, co→/4, mx_staging→/5, cl_staging→/6, co_staging→/7 (+ br_staging→/8 if it
  exists — verify per the note above)
- **commcenter**: prod→/1, staging→/2
- **maqnelson**: app → /1

**Encryption — YES (engineer, 2026-07-24): the new Redis is born encrypted at rest under the dedicated
`alias/integrator-<slug>` key.** The fresh cluster is the moment to do it, and it closes this effort's
KMS-per-environment goal for the integrator Redis.

**Naming — DECIDED (engineer, 2026-07-24): the new Redis is `integrator-<client>-redis001`.** The source is
`terraform/docs/adr/ADR-010-resource-naming-convention.md`. ADR-010's rule (line 27): every integrator
resource is `integrator-<client>-*`, "across compute AND infrastructure, no exception." ADR-010 §
"Legacy exception" (lines 62–71) lists TODAY's Redis names — `ec-<client>` / `4client-<client>-redis001` — as
the acknowledged `4client-` technical debt, "to be addressed in a dedicated future effort — not retrofitted
piecemeal," and § "Change policy" says a convention migration is done "all resources together in a single
dedicated effort — never one at a time." **This Redis-standardization IS that sanctioned dedicated effort for
the Redis** (all four at once, one PR), so the `4client-` Redis name is retired now: cluster_id, DNS record,
and tag all become **`integrator-<client>-redis001`** (`modules/integrator/elasticache.tf` — today
`cluster_id = "ec-<client>"` and tag `...-redis001`; the DNS record is `4client-<client>-redis001.4shark.internal`).
The ElastiCache `cluster_id` has a 40-char limit — `integrator-<client>-redis001` fits for the current four,
but check per name at build time.
- **Scope of the rename is the Redis only.** ADR-010's other `4client-` legacy resources — the Mongo host
  (`4client-<client>-mongo003`), the module default SG (`4client-<client>`), and the VPN-edge resources — are
  NOT touched by this effort; they stay legacy until their own dedicated efforts.
- **Follow-up — update ADR-010 itself. DONE, merged (#830, 2026-07-24).** ADR-010 § "Legacy exception" now
  reflects reality: Redis is out of the `4client-` list, recorded as the first legacy resource-family retired
  (`integrator-<client>-redis001`, module-created under the dedicated key), with the remaining `4client-` debt
  named as MongoDB + default SG + VPN edge. The one `ec-` remnant noted is the frozen cancelled-contract stack
  pending teardown. Doc-only PR, no CHANGELOG entry (no infra change; the migration itself shipped in
  #821/#826/#827/#829).

**Stage 3 — the coordination counter + Mongo shutdown — remains DEFERRED (NOT this effort),** per the "Why
reserve /0" rationale above.

### Phase 9b — Redis cleanup + make the module OWN the Redis (engineer, 2026-07-24, MERGED — PR #829)

The three-PR migration (9a) got the fleet onto the new encrypted Redis safely, but it left transitional
scaffolding in the shared module that had to be removed, and it surfaced a standard the engineer wanted
enforced: **every integrator MUST have a Redis, born from the module, never added by hand** (every integration
runs Sidekiq, so Redis is not optional — the module guarantees it, the same way it already guarantees the KMS
key). Both the cleanup and the mandate landed in a single PR; the originally-planned "PR B" collapsed into
"PR A" because an ungated module resource IS the mandate — there was nothing separate left to do.

**PR A — code cleanup + mandate (#829, applied + merged 2026-07-24).** `modules/integrator/elasticache.tf` is now the
final single-Redis shape:
- **Both `moved` blocks removed** — the one-time state re-home job was done once #827 applied.
- **Collapsed to ONE Redis resource** — `aws_elasticache_replication_group.redis_v2` renamed to `redis` (the
  `_v2` suffix is gone; nothing reads as "the second one" now that the first is gone), and the legacy
  `aws_elasticache_cluster.redis` resource deleted entirely.
- **`var.create_new_redis` gate removed** — the module now creates the Redis unconditionally; the variable and
  the `create_new_redis = true` line are gone from the four stacks. This ungated resource IS the mandate: an
  integrator without a module-created Redis is now impossible by construction, the same class of guarantee as
  the dedicated KMS key.
- **The label rename was realized with `terraform state mv`, NOT a moved block** — the engineer asked to remove
  the moveds, so a lingering moved block in the code was not acceptable. Per stack (`almaviva`, `atento`,
  `commcenter`, `maqnelson`), `state mv 'module.this.aws_elasticache_replication_group.redis_v2[0]' →
  'module.this.aws_elasticache_replication_group.redis'` re-homed the state address; the live instance is
  unchanged, so `plan` afterward reports "No changes" on all four. The `[0]` index came from the old `count`
  gate; the resource is module-qualified (`module.this.…`), which the first `state mv` attempt missed.

**RedeBrasil — FROZEN by a real terraform-level guard, not by discipline or decommission.** Removing the gate
would make the module want to create `integrator-redebrasil-redis001` and drop the legacy `ec-redebrasil` on
RedeBrasil's next apply — but RedeBrasil's contract is cancelled and it must never be applied again. The
engineer rejected "just don't apply it manually" as a non-mechanism and demanded a code-level block. The
resolution is `integrator-redebrasil/freeze.tf`: a `terraform_data.frozen` with a `lifecycle` `precondition`
that always fails, so `plan` and `apply` on that stack abort with an explicit freeze message. Terraform rejects
a bare `condition = false` (the expression must reference an object), so the condition is `path.module == ""` —
always false, and it references `path.module` to satisfy the rule. Verified: a `plan` on redebrasil now aborts
with "integrator-redebrasil is FROZEN (contract cancelled). Delete freeze.tf to apply." The guard is deleted
when the stack is torn down for real; until then no apply can touch it. This replaces the three options the
earlier draft floated (decommission now / drop from the list / carve-out) — none were needed once a true freeze
existed.

**Future — port the pattern to `app`.** The engineer wants the same "the module OWNS the Redis, it is not
created by the consuming stack" guarantee ported to the `app` module/stacks later, to keep one standard across
the estate. Deferred; noted here so it is not lost. (App's Redis today is external Redis Cloud, per ADR-010 —
porting the *guarantee* may mean the app module owning the Redis Cloud resource, not an ElastiCache; scope it
when it is picked up.)

### Phase 10 — The module OWNS and auto-creates the key, named after the stack (the forward-lock) — **DONE 2026-07-20**

> **Status 2026-07-20: COMPLETE for all six surfaces, and it ran FIRST, not last.** The original framing
> ("Runs LAST, after everything migrated") was inverted in execution: the module-owns-key modularization
> landed BEFORE the data migration — `app` (#786), `integrator` (#785, `state mv`), `onboarding`/`setup`
> (#788), `auth` (#789), `vpn` (#790). Every surface's module now mints or owns its dedicated key by
> construction. The prose below is kept as the design record; the data migration it references as
> "already done" is what the **Execution order** section above now sequences (it is NOT done — the keys
> exist, the data still has to move onto them).

The engineer's closing requirement, and the reason the whole migration is worth it: once every
environment is on a dedicated key, **make the key impossible to omit OR misname for the next one.**

**Refined 2026-07-20 — auto-create, do NOT take a parameter.** The earlier framing was "add a required
KMS-key variable to every application module (`app`, `integrator`, `onboarding`, `setup`)." The engineer
sharpened it: a parameter can still be passed wrong, and a defaulted one can be omitted — but a key the
MODULE creates itself cannot be either. So the module owns the key: every application module creates its
own `aws_kms_key` + `aws_kms_alias` + the two-/three-statement restrictive policy (§ The key policy),
with the alias **derived from the stack's identity**, which equals the stack folder name by convention
(`integrator-almaviva` → `alias/integrator-almaviva`, `app-shared-001` → `alias/app-shared-001`). The
module already receives that identity (`var.environment` / `var.client_name`), so it builds the alias
internally — the caller passes nothing key-related and cannot get it wrong. This converts the property
from "achieved by migration" to "guaranteed by construction": every future environment is born with its
own dedicated, correctly-named key, and the class of problem this whole plan exists to fix (retrofitting
isolation onto shared-key estates, and the cross-consumer misses that came with it) cannot recur.

**This SUBSUMES the per-stack key files, it does not sit beside them.** The integrator keys created in
Phase 9 live in each stack's own `kms.tf` (`aws_kms_key.integrator` + alias). When the integrator module
takes over key creation, those resources MOVE into the module — a `terraform state mv` per stack, the
alias unchanged (`integrator-<slug>` = the folder), so NO re-encryption and NO parameter churn. The app
stacks are the other half: they still sit on the shared `4shark-master` key today (their role split is
done, their KEY split is Phases 3–8, not yet run), so the app module creating `alias/app-<stack>` per
caller IS that app-stack key split — Phase 10 and Phases 3–8 converge into "the module makes the key."
Sequence Phase 10 so it lands as the single mechanism that owns every application stack's key, rather
than bolting a second creation path next to the hand-written `kms.tf` files.

Runs LAST, after all stacks — the five integrators AND the app-stack key migration — are settled, so no
in-flight stack is forced to satisfy the new module shape mid-migration. **Blast radius is why it is its
own effort, never folded into a per-stack PR:** it edits the SHARED modules (`app`, `integrator`,
`onboarding`, `setup`) that every stack instantiates, so a single module change re-plans every stack at
once. **Discovery points**: (1) whether the deploy user / any non-task reader must be named on the
module-created key's decrypt statement (the gap that bit Phase 9's PR3 — the module must carry it so it
is not re-missed); (2) how the `terraform state mv` of the existing integrator keys into the module is
staged so no plan wants to destroy-and-recreate a live key.

### Phase 11 — Cross-module standardization: all four surfaces forward-lock the key (added 2026-07-20)

Once app / integrator / onboarding / setup are all on dedicated keys, the closing act is to make the
four SURFACES uniform, so that copying any stack and instantiating its module is BORN with the correct
dedicated key — no per-stack key file to forget or misname, ever again. This is Phase 10 generalized
from the integrator to all four.

**Structural finding and resolution (2026-07-20).** The surfaces were not symmetric: `integrator`
(`modules/integrator`) and `app` (`modules/app`) were composed modules reused by N stacks — the key
minted INSIDE the module, which is the forward-lock — while `onboarding`, `setup`, `auth-001`, and `vpn`
were **flat stacks** with no module to hold a minted key.

**Decision — DONE (engineer, 2026-07-20): extract a composed module for every flat stack, so all
surfaces forward-lock the key inside a module.** An intermediate call placed a stack-level `kms.tf` on
`onboarding`/`setup` (PR #787, applied), reasoning that single-instance stacks have no next stack to
forward-lock. The engineer overrode it: extract `modules/onboarding` and `modules/setup` (PR #788,
applied) so the module owns the key uniformly, then `modules/auth` (PR #789, applied) and `modules/vpn`
(PR #790, applied). Each extraction is a pure state re-address via `moved {}` blocks (0 destroy); the
stack becomes a thin caller (providers, variables, the module call, outputs).

- `onboarding` / `setup` — the module MINTS a dedicated key (`alias/onboarding`, `alias/setup`),
  two-statement via-SSM policy (their secrets are SSM SecureStrings).
- `auth-001` (Keycloak) — the module ADOPTS the key that already existed by hand (`alias/auth-001`,
  already used by the Keycloak Secrets Manager secret) instead of minting a new one, and applies a
  via-**SecretsManager** policy (its secret lives in Secrets Manager, not SSM). Imported into the module,
  the hardcoded ARN in `secrets.tf` replaced by `aws_kms_key.this.arn`; the redundant minted key from
  the first apply was scheduled for deletion (PR #789). auth is the one surface where the dedicated key
  pre-existed — adopt, don't mint.
- `vpn` (Pritunl) — the module MINTS a dedicated key (`alias/vpn`), but the key is born **UNUSED**: the
  VPN has no SSM/Secrets Manager secret store to encrypt. Its at-rest sensitive data is the hosts' EBS
  volumes (the MongoDB data host + the Pritunl instances), which carry no dedicated key today. The key
  policy is therefore scoped via-**EC2** (the service through which EBS is encrypted) — same two-statement
  shape and 5-action set as the others, adapted to the VPN's intended future consumer. Actually
  encrypting the EBS volumes REPLACES them (a volume cannot be encrypted in place), so that is a separate,
  deliberate operation, deferred and out of scope of PR #790. vpn is the one surface where the key is
  minted ready but idle.

So the forward-lock now holds by construction for every surface: import the module, get the
correctly-named dedicated key.

**The `app_outbound` exception, made structural (engineer decision, 2026-07-20).** An outbound must use
the key of the app cluster it links to, never one named after itself. `modules/app_outbound` takes a
**required** `app_stack` variable (e.g. `app-atento-001`) and derives the linked cluster's key from it
— `data "aws_kms_alias"` on `alias/${var.app_stack}`, decrypt granted on its `target_key_arn`. The
variable being required means an outbound cannot be instantiated without declaring which cluster it
draws from, and the key follows from that declaration automatically — no separate key argument to get
wrong, and no key minted for the outbound itself. The verified links seed it: `app-outbound-atento-br`
→ `app_stack = "app-atento-001"`, `app-outbound-maqnelson` → `app_stack = "app-shared-001"` (by
connection, not by name).

**Guarantee this phase closes:** for each surface (`app`, `integrator`, `onboarding`, `setup`, `auth`,
`vpn`), instantiating the module (or copying the stack) produces a correctly-named dedicated key by construction,
and an outbound is structurally forced to borrow its linked cluster's key — the whole class of "new
environment born on a shared key, or on a misnamed one" cannot recur.

### Phase 15 — The account-wide buckets: three categories, five keys (engineer, 2026-08-21)

Twelve buckets sit outside every stack — they belong to the account, not to an environment — and all
of them are on the AWS-managed S3 key. The per-stack rule of § "Six keys" does not reach them: there
is no task role to name, because no stack owns them. The engineer categorized them by **who may
read** instead, which is the same reasoning one level up — the reader is the blast radius.

| Bucket | Region | Category | Key |
|---|---|---|---|
| `4shark-legal` | sa-east-1 | DPO only | `4shark-legal` |
| `4shark-terraform-state` | us-east-1 | infrastructure | `4shark-infrastructure` |
| `4shark-backups` | us-east-1 | infrastructure | `4shark-infrastructure` |
| `4shark-lambda-artifacts-us-east-1` | us-east-1 | infrastructure | `4shark-infrastructure` |
| `4shark-cloudtrail` | sa-east-1 | infrastructure | `4shark-infrastructure` |
| `4shark-lambda-artifacts-sa-east-1` | sa-east-1 | infrastructure | `4shark-infrastructure` |
| `4shark-development` | us-east-1 | development | `4shark-development` |
| `4shark-integrator-artifacts` | sa-east-1 | development | `4shark-development` |
| `4shark-assets` | — | public | stays SSE-S3 |
| `4shark-incentive` | — | public | stays SSE-S3 |
| `mobile.app4shark.com` | — | public | stays SSE-S3 |
| `4shark-danfe-poc` | — | discard | — |

**The three public buckets are not a preference — SSE-KMS cannot serve an anonymous reader.**
Downloading a KMS-encrypted object requires `kms:Decrypt` on the caller, and an anonymous principal
has no identity to grant it to. AWS states the consequence directly: *"you can't use SSE-KMS with
objects that need to be publicly accessible"*. So a bucket serving objects to the open internet stays
on SSE-S3 for as long as it serves them. All three do: `4shark-incentive` holds brand logo pairs
(`<brand>/large.png`, `<brand>/small.png`), and `mobile.app4shark.com` holds exactly two objects —
`apple-app-site-association.json` and `assetlinks.json`, the Apple Universal Links and Android App
Links association files that Apple and Google fetch anonymously to verify the domain-to-app claim.
Deleting that bucket breaks the app's deep links; it is small, not empty.

#### Three names, five keys — the region is what multiplies them

A KMS key is regional and an S3 bucket can only be encrypted by a key in its own Region. Two of the
three categories hold buckets in both Regions, so each of those is **one name declared twice**, once
per Region — an alias is itself a per-Region name, so the same alias in `us-east-1` and `sa-east-1`
is not a collision. The estate already reads this way: `alias/main` exists in both
(`audit/kms.tf:115`, `shared-resources/kms_cloudtrail.tf:153`).

| Alias | us-east-1 | sa-east-1 |
|---|---|---|
| `alias/4shark-infrastructure` | ✓ | ✓ |
| `alias/4shark-development` | ✓ | ✓ |
| `alias/4shark-legal` | — | ✓ |

**Paired regional keys, never a multi-Region key** — § "Regional, not multi-region" already decided
this for the estate, and S3 gives no reason to depart: each bucket lives in one Region and never has
to decrypt another Region's ciphertext, which is the only thing a multi-Region key buys. The app
module's `multi_region = true` is not a counter-precedent — it exists because an outbound sibling
runs the *same application* in a second Region against the *same* log groups and secrets.

#### The names follow the estate's own alias grammar

An alias names the thing the key belongs to: `alias/app-<stack>`, `alias/integrator-<client>`,
`alias/auth-001`, `alias/backup-<stack>-local`. A stack-scoped key carries no prefix because the
stack name is already unique; the **one** account-wide key carries `4shark-` (`alias/4shark-master`,
`shared-resources/kms.tf:125`). These three are account-wide by the same argument, so they take the
same prefix — which also makes each alias read as the bucket set it covers. Lowercase throughout,
matching every existing alias and every bucket name.

Key shape is `modules/vpn/kms.tf`'s: `deletion_window_in_days = 30`, `enable_key_rotation = true`,
an explicit policy with a key-administration statement, a tagged-operator statement
(`aws:PrincipalTag/KeyAccess = all` + MFA) and a `kms:ViaService = s3.<region>.amazonaws.com`
statement, and `Automation = "terraform"` in the tags.

#### Home — `shared-resources`, for the reason `4shark-master` is already there

The stack that hosts `4shark-master` states it: the key *"is shared by every stack and belongs to no
single one"*. That is exactly these three, and `shared-resources` already declares both Region
providers. The buckets themselves stay where they are; only `4shark-cloudtrail` is Terraform-managed
today (`audit/cloudtrail.tf:7`), and its `audit` stack reads the sa-east-1 infrastructure key by
alias rather than minting one.

**CloudTrail already has a second layer, and it is not this one.** The trail encrypts its own log
files with `aws_kms_key.cloudtrail` (`audit/cloudtrail.tf:118`) before they land; the bucket's
default encryption is separately `AES256` (`audit/cloudtrail.tf:29`). Moving the bucket onto the
infrastructure key changes the bucket-level default and leaves the trail's own key untouched.

#### Migration mechanics — already settled, do not re-derive

The in-place default-encryption change plus the S3 Batch Operations re-encryption pass is § Phase 12c
verbatim, proven on production buckets holding millions of objects: Bucket Keys enabled **before** the
batch, a `kms:ViaService` statement on the key policy, and a manifest filtered on
`MatchAnyObjectEncryption`. Nothing is ever unavailable, because a bucket holds objects under
different encryption at once and the reader never has to know which.

**Open — `4shark-danfe-poc`.** Categorized as discard. Deleting a bucket is irreversible and is the
engineer's call; it blocks nothing above.

## Execution order — the data migration, simplest first (engineer, 2026-07-20)

**This section is the authoritative running order from 2026-07-20 forward. It REORDERS the phase
mechanics above; it does not replace them.** The per-surface playbooks (Phases 3–8 for the app estate,
Phase 9 for the integrators) keep their step-by-step detail — this section only fixes which surface is
done in which order, and folds in the two surfaces (`vpn`) and two extra jobs (integrator naming, the
integrator Redis) that the phase text did not yet carry.

**What is already DONE (do not re-plan it).** The forward-lock — every surface's module MINTS or owns a
dedicated, correctly-named key by construction (Phases 10–11) — is COMPLETE for all six surfaces:
`app` (#786), `integrator` (#785), `onboarding`/`setup` (#788), `auth` (#789), `vpn` (#790). So the key
EXISTS per stack today. What remains is the DATA migration: moving each stack's at-rest data off the
shared/AWS-managed key onto the dedicated key it already has. `auth` is the one surface where the data
is already on its key (the Keycloak secret used the adopted key all along — #789), leaving only its RDS.
**auth RDS — REDESIGNED 2026-07-22 (discovery session). Two decoupled efforts, security first.** auth's RDS
goes onto the SAME `alias/auth-001`, NOT a separate key (the older "(separate key)" note predates the
one-key-per-stack conclusion the setup RDS confirmed: finest granularity is one application per SDLC stage,
not one key per service type). Discovery this session (read-only) found two things the earlier note did not
account for:

- **The RDS storage is on the WRONG key — `alias/auth002` (`6f7b8e40`), not any dedicated key** — and it has
  NO managed master password, NO Performance Insights, NO enhanced monitoring today (master user `postgres`,
  password set out of band). So the § "Out of scope" table's claim that `alias/auth002` is an unused orphan is
  WRONG — it encrypts this RDS's storage and can only be retired AFTER the re-key. (Live `alias/auth002` →
  `6f7b8e40`; the table's recorded `df7df919` id does not match live — reconcile before any auth002 deletion.)
- **Keycloak connects to the DB as the RDS master `postgres`** — the application runs with full privilege, a
  security defect in its own right, and it also blocks adopting managed master password: enabling managed-pw
  rotates the `postgres` password and the app's stored password (in the manual secret `auth-001-sm`) goes
  stale → Keycloak breaks. Setup's managed-pw worked only because setup's app uses a dedicated user; auth is
  the exception.

Therefore the work splits, security first (engineer decision 2026-07-22):

- **Effort 1 (do FIRST — in-place on the current instance, NO re-key, NO Terraform): move Keycloak off the
  master onto a dedicated LEAST-PRIVILEGE DB user.** Create a minimal-privilege user (only what Keycloak +
  Liquibase need — DDL on its own schema, DML on its tables; NO superuser, NO cross-database access), transfer
  the existing schema's ownership to it, update the `auth-001-sm` secret values, rolling-restart Keycloak.
  No direct DB access → SQL is generated for the engineer to run (three-script pre-flight/mutation/verification
  per SCRIPT-DISCIPLINE). Grounded by the `keycloak-least-privilege-db-user` spike BEFORE any SQL is written —
  the privilege set + ownership transfer are not improvised on a productive auth DB.
- **Effort 2 (AFTER Effort 1): re-key + managed master password + PI + enhanced monitoring.** Mechanism =
  Option A (pg_dump/restore short-freeze) per the `auth-001-rds-key-migration` spike — the DB is small
  (~1.8 GB used) so the freeze is a few minutes, and Option A avoids the sequence/DDL/large-object gaps that
  logical replication and DMS carry. Stand up a NEW instance under `alias/auth-001` (managed-pw + PI +
  monitoring set at creation), dump→restore, repoint + rolling deploy. With Keycloak already on a dedicated
  user (Effort 1), adopting managed-pw on `postgres` is now safe (the app-user survives, like setup). PI is
  KEPT (4Shark/setup pattern; console EOL 2026-07-31 but API/Terraform config preserved and instances
  auto-migrate to CloudWatch Database Insights — enabling it is not wasted work).
- **Prerequisite for Effort 2 — DONE as a PR:** broaden `alias/auth-001`'s policy from via-SecretsManager to
  `ViaService = [secretsmanager, rds]` (rds for PI) AND tighten its admin statement from `kms:*` to the
  management-only action list (it had inherited the leaky `kms:*` shape when adopted by hand in #789) —
  **PR #807, open, apply GATED on the engineer's OK.** In-place `PutKeyPolicy`, `0 add, 1 change, 0 destroy`.

Spikes: `active/spike/auth-001-rds-key-migration/SPIKE.md` (RDS re-key mechanism, 3 options, Option A chosen),
`active/spike/keycloak-least-privilege-db-user/SPIKE.md` (Effort 1 grounding).
Every other surface still has data to move.

**Codebase hygiene — DONE (#791, merged 2026-07-20).** The whole Terraform estate was audited: every
data surface gets its key from its module (no discrepancy, forward-lock confirmed). The one-time
`moved {}` blocks from the modularizations (`onboarding`/`setup`/`auth`/`vpn`) and the already-applied
one-time `import {}` blocks across the app/integrator/mongodb/`shared-resources` stacks (plus the
`identity` repo-rename `moved.tf`) were removed as inert scaffolding — each affected stack verified
`0 changes` before removal. So a fresh session will not find leftover state-move/import blocks to clean.

**The order is simplest-to-hardest, so each surface shakes down the mechanics for the next.** Verify
each surface end to end before starting the next.

**Progress (2026-07-22).** Surface 1 `vpn` is **DONE** end to end (encrypted, keyless, old host retired,
canonical name). **Surface 2 `onboarding` is DONE** (PR #799, merged 2026-07-22) — see the surface-2 entry
below for the collapsed scope and the alias-vs-ARN learning. **Surface 3 `setup` is DONE** (2026-07-22) —
SSM SecureStrings rekeyed onto `alias/setup` (PRs #800 expand / #802 contract) and the **RDS fully migrated**
onto `alias/setup` (storage + Performance Insights + managed master secret), PR #804. Surfaces 2 and 3 were
independent Terraform stacks (separate state, separate AWS resources, separate per-stack task roles), so
there was no contention; the only shared object, `4shark-master`, is not retired until the very end, so
neither touches it, and neither edits `shared-resources/` (the one file both could collide on). After setup,
4 the five integrators, then 5 `app`. Surfaces 4–5 have not started; each is still on the shared/AWS-managed
key for its data.

**Progress (2026-07-23) — `auth-001` DONE end to end, plus a four-surface conformance study with two fixes applied.**

The **`auth-001` RDS re-key is COMPLETE** (full detail in `auth-001-rds-rekey/PLAN.md`). The instance was moved
off the wrong key `alias/auth002` onto its dedicated `alias/auth-001` (`key/5a64fa33`) via the AWS-native
mechanism the engineer chose over logical dump/restore: freeze Keycloak → snapshot → `copy-db-snapshot
--kms-key-id alias/auth-001` (re-encrypt) → rename old → `restore-db-instance-from-db-snapshot` as `auth-001` →
scale up. Login validated by the engineer; endpoint unchanged (no task-def change). Terraform reconciled
(`state rm` old + `import` restored into `module.this.aws_db_instance.auth001`, `rds.tf` `kms_key_id → key/5a64fa33`,
`apply` `0/1/0`, re-plan clean — **PR #811**). Effort 1 Phase 3 (`REVOKE "EVKcRQtsJsyxzQDaNaphGu"/"iDdssfbZVDcejjYwjpkuhBuF"
FROM postgres`) done in psql on the restored instance. Old instance `auth-001-old` + both migration snapshots
deleted; local artifacts and the `/tmp` credential file purged. **Downtime lesson for the next RDS re-key:**
baseline the snapshot BEFORE the freeze (a fast incremental inside the freeze), not during — the restore is the
unavoidable floor either way. Recorded in the sub-plan.

**Conformance study of the four DONE surfaces (`auth` / `onboarding` / `setup` / `vpn`), plus an integrator
preview.** (The HTML lived at `/tmp/kms_conformance_auth_20260723.html` — transient; the findings are captured
here so nothing is lost.) The reference pattern the four should match: the MODULE mints `aws_kms_key.this` +
`aws_kms_alias` named `alias/<stack>` (the stack folder carries NO `kms.tf`); a two-statement policy (admin =
account root, an EXPLICIT management-action list, NEVER `kms:*`, no crypto action; crypto = `Principal "*"`
scoped by `kms:CallerAccount` + `kms:ViaService` to only the services the stack uses); `enable_key_rotation`,
`deletion_window_in_days = 30`; consumers reference the minted key by `aws_kms_key.this.arn` (never a hardcoded
ARN); RDS via the shared `../rds_instance` module. **`setup` is the cleanest reference.** Two deviations were
found AND FIXED 2026-07-23: **(a)** `modules/auth/rds.tf` hardcoded the key ARN instead of referencing
`aws_kms_key.this.arn` (auth's own `secrets.tf` already did it right) — fixed by **PR #812** (0-change, merged);
**(b)** `modules/vpn/kms.tf` admin statement used `Action = "kms:*"` — the forbidden shape — fixed to the
explicit management-action list by **PR #813** (applied `0/1/0`, merged). `onboarding` and the `integrator`
module already conform.

**One follow-up remains on `auth` (NOT done):** `modules/auth/rds.tf` still hand-rolls `aws_db_instance` instead
of using the shared `../rds_instance` module (`setup` uses it — `modules/setup/rds.tf:45`). Switching changes the
resource address, so it is a careful state migration (a `moved` block or `state mv`), not a value edit. Deferred
— do it before or after the integrators, the engineer's call.

**NEW effort surfaced 2026-07-23 — module parameterization (reopens the four composed modules' "DONE").** The
rds_instance-switch PR for auth exposed a systemic issue the engineer flagged: the four SINGLETON composed
modules (`auth`, `onboarding`, `setup`, `vpn`) HARDCODE their environment name, so a second environment (e.g.
`auth-002`) could not instantiate the module without colliding (`alias/auth-001` already exists). A module must
carry NOTHING environment-specific — the name is a REQUIRED `var.identifier` the caller passes (the pattern
`modules/app` and `modules/integrator` already follow). `app`/`integrator` are correct (multi-instance);
`onboarding`/`setup` have a `var.environment` but still hardcode the name in places; `auth`/`vpn` had no
`variables.tf` at all. **Decision (engineer, 2026-07-23): parameterize all four via `var.identifier`, one PR per
module, each proven value-preserving with a 0-change plan.** `auth` is DONE — **PR #814** adds `var.identifier`
driving every one of ~50 resource names (KMS alias, secrets, subnet, ECS, ALB, ECR, IAM, SGs, logs, DNS) PLUS
the rds_instance switch; the stack passes `identifier = "auth-001"`, so the plan is `0/0/0` (only a `moved` block
re-homes the RDS state address); applied and squashed to one commit, awaiting merge. **Remaining: `onboarding`,
`setup`, `vpn`** get the same treatment (one PR each) BEFORE the integrators. Known cosmetic nit deferred: the
bare-value form is `"${var.identifier}"` (valid; idiomatic `var.identifier` is a lint, not a fmt, fix).

**Why these four are fixed BEFORE the integrators (engineer, 2026-07-23) — this is the module standard now.**
The gap was found on `auth`; correcting all four singleton modules first means the integrator work (and every
future module) is born correct instead of being retrofitted later. **The standard any 4Shark module must follow:
a module carries NOTHING environment-specific — the name is a REQUIRED `var.identifier` the caller passes,
driving every resource name; `var.environment` (when present) is for tags and the SSM parameter namespace only;
defaults are allowed ONLY for genuinely shared values (backup retention, instance size/version, storage type),
NEVER the name.** The parameterization is always value-preserving — the stack passes the current identifier, so
the plan is a no-op (0/0/0). Watch out per module: only VALUE strings are parameterized, never the terraform
resource labels (`resource "x" "setup"`) — those are state addresses; a blind replace_all breaks them, so
edits are targeted. `Project` tags and GitHub repo names stay hardcoded (they are the project/repo, not the env).

**Progress (2026-07-24):** DONE + merged — `auth` (**#814**, ~50 names + rds_instance switch, 0/0/0),
`onboarding` (**#816**, 0/0/0, also fixed an SSM path-vs-grant inconsistency), `setup` (**#817**, 0/0/0
including the production RDS), `vpn` (**#819**, 0/0/0). **All four modules are now parameterized by a
required `var.identifier` and are a clean reference.** The integrator effort (below) begins next.

**`vpn` note (engineer, 2026-07-23): option B — parameterized via `var.identifier` for uniformity, EVEN
THOUGH its "vpn" is the application name (ADR-010, a deliberate singleton with no `-001`/`-002`), not an
environment identifier.** The vpn module got a new `variables.tf` + `identifier` driving every resource
name; the many `Role = "vpn"` tags stayed (they are the role, like `Project`), the terraform resource
labels (`resource "x" "vpn"`, `aws_*.vpn` refs) stayed (state addresses), and the legacy EIP `Name`
(`4shark-vpn-001-eip`) stayed (a physical adopted tag). **Architecture note surfaced during review: the
vpn module is unlike the other three — it contains production AND staging together in one module instance
(one cluster, one Mongo host, ONE minted KMS key), so `vpn-staging` is a `-staging` suffix on top of
`var.identifier` INSIDE the single import, not a second module import. A second import would mint a second
key, which is exactly why staging lives in the same instance.** The single `identifier = "vpn"` in
`vpn/main.tf` drives both prod and staging names; the 0/0/0 plan refreshed both services with no change.

**NEXT (after the three remaining module parameterizations): the five integrators** (execution-order step 4 / Phase 9 below) — the role split, move each integrator's
SSM SecureStrings onto the already-minted `alias/integrator-<slug>` key, plus the naming and Redis
standardizations folded in. The customer-managed key per integrator is already minted (Phases 9–10), so the
key-creation half is done; what remains is the role split + the SSM rekey + the two standardizations, one
integrator family at a time.

**READ § "Phase 2 RDS migration — the playbook and the prerequisites, learned on setup" (below) before
migrating any RDS-bearing stack (`app`, `atento`, `auth`, and `onboarding`'s future RDS).** The setup RDS
surfaced two non-obvious blockers that WILL recur, plus the mechanism that worked — do not re-derive them.

1. **`vpn` — replace the MongoDB host with an encrypted one — DONE (2026-07-21, PRs #793 / #794 / #795 / #796).**
   The VPN has no SSM/Secrets Manager store; its at-rest data is the hosts' EBS volumes, and the one that
   matters is the MongoDB host, which holds every Pritunl org, user and VPN profile. An existing EBS
   volume cannot be encrypted in place, so this was a host replacement: a NEW MongoDB node was stood up
   with its root volume encrypted under `alias/vpn` AND made **keyless** — no SSH key pair, reached only
   through SSM Session Manager under a dedicated instance profile (`vpn-mongo`, carrying
   `AmazonSSMManagedInstanceCore` alongside the CloudWatch-agent policy), the first Mongo host off SSH
   keys (#793). The Pritunl database was moved Mongo → Mongo by `mongodump | mongorestore` streamed from
   the live Pritunl host (the only host that reaches both mongos over 27017), the persistent config
   verified collection-by-collection; the Pritunl `MONGODB_URI` was cut to the new host (#794); and the
   old host was retired (#795), and the replacement was renamed to the canonical `aws_instance.mongodb`
   (via `terraform state mv`, #796). The keyless access uses a dedicated profile rather than the
   account-shared `mongo-cwagent`, so SSM was NOT turned on for the ~15 integrator Mongo hosts — that
   follows in its own change if wanted. The two Pritunl instances' own EBS stay unencrypted — always out
   of scope (see the table below).

2. **`onboarding` — DONE 2026-07-22 (PR #799, merged).** The discovery collapsed the scope to almost
   nothing: `4989a2c` (2026-07-17, "remove idle load balancer, deploy machinery, redis and database") had
   already DELETED `onboarding/rds.tf` / `redis.tf` / `backup.tf` and gutted `main.tf`, so onboarding has
   **no RDS, no OpenSearch, no ElastiCache/Redis, no pooler** in Terraform — verified against live AWS
   (`describe-db-instances` empty; the only OpenSearch domains are `app-shared-001` / `app-atento-001`).
   The whole surface was therefore just: rekey the 11 SSM SecureStrings off `4shark-master` onto the
   dedicated `alias/onboarding` (they were on the master, not `alias/aws/ssm` — the 2026-07-17 probe had
   moved them) and repoint the task role's `kms:Decrypt` from the master ARN to the dedicated key. No RDS
   blue/green, no OpenSearch replace. `4shark-master` NOT retired (last cross-cutting step); `shared-resources/`
   untouched.
   - **The value rekey is value-preserving and out of band** (engineer's step, MFA): `get-parameter
     --with-decryption` piped into `put-parameter --key-id alias/onboarding --overwrite`, per parameter, so
     the value is rewritten with itself under the new key and never lost. Then Terraform's `ssm.tf` carries
     `key_id` so the binding is declared (the module owns the key already).
   - **LEARNING for setup / app — the alias-vs-ARN trap.** `put-parameter --key-id alias/<stack>` stores the
     KeyId as the literal alias STRING (`"alias/onboarding"`), not the resolved key ARN. So the Terraform
     `aws_ssm_parameter.key_id` MUST be `aws_kms_alias.this.name` (the alias), NOT `aws_kms_key.this.arn` —
     otherwise the plan never reconciles the 11 params and you get a spurious 12-change plan whose apply
     would overwrite every secret with the `"PLACEHOLDER"` seed (the value rides along in the provider's
     `PutParameter` on a key_id-only change, and `ignore_changes = [value]` does NOT protect it). The role's
     `kms:Decrypt` Resource stays the key ARN (`aws_kms_key.this.arn`) — IAM needs a concrete key ARN there,
     an alias does not authorize decrypt.

3. **`setup` — the same app-estate playbook, in use but still simple (single web service, no crons).**
   Same steps as onboarding; the difference is setup carries live traffic, so the rekey and the RDS
   cutover happen in an announced window rather than freely.

4. **The five integrators — role split + rekey + naming + Redis, one integrator (family) at a time.**
   This is Phase 9 (role split → move SSM onto the already-minted `alias/integrator-<slug>` key), PLUS
   two standardizations folded in because the integrator pieces are being touched anyway:
   - **Naming standardization** — bring every integrator piece to the current naming standard. **There
     is no separate canonical naming-standard doc today** — the engineer holds the target convention;
     confirm the exact target names with the engineer per integrator before renaming (naming is a design
     decision). Note: `terraform/integrator-module-cleanup/PLAN.md` is a DIFFERENT effort (removing
     EC2-era legacy code from `modules/integrator`) — it is not the naming standard and does not overlap.
   - **The Redis is per-client ElastiCache, no longer the standard** — each integrator provisions its
     own dedicated `aws_elasticache_cluster.redis` (`ec-<client>`, `modules/integrator/elasticache.tf:7`).
     That per-client self-managed Redis is not the current standard for a new integrator; bring it to the
     current standard as part of this step. **The target standard is the engineer's to specify** (do not
     assume it) — capture it before touching the Redis. **The engineer chose to START the integrator effort
     with the Redis (2026-07-24); the full staged detail — current-state DB map, the `/0`-reservation
     convention, the Stage 1 correction, and the open decisions — is in Phase 9a above.**
   Order among the five: start with the one whose access delegation is wanted first (Atento — the
   Santiago driver) unless a lower-risk integrator is preferred as the shakedown. The stack-vs-slug count
   and the cross-region-sibling sweep from Phase 9 still apply.

5. **`app` — `shared-001` and `atento-001` LAST (hardest: productive, OpenSearch, the outbound siblings).**
   The full Phases 3–8 playbook on the productive stacks: rekey SSM, RDS blue/green replace, **OpenSearch
   replace in a quiet window** (`app-shared-001/opensearch.tf`, `app-atento-001/opensearch.tf` — the
   OpenSearch data need not persist), naming standardization on the recreated resources (the `app-` prefix
   on everything), the `app-outbound-*` decrypt grant repointed to the cluster's new key in lockstep, then
   retire `4shark-master`. Productive, so the Sidekiq-queue gate and the announced window apply. `beta-001`
   and `demo-001` (non-productive) can be done first within this step as the shakedown for the two
   productive ones, matching the original beta→demo→productive risk order — but the app SURFACE as a whole
   comes last, after vpn/onboarding/setup/integrators.

**Why this order and not the phase-text order.** The phase mechanics were written app-first (beta → … →
onboarding → setup, then integrators). The engineer inverted it on 2026-07-20: do the surfaces with the
least at-risk data and the simplest shape first (`vpn` is one machine; `onboarding` is idle; `setup` is
one service), so the mechanics are proven on low-stakes surfaces before the productive app estate. The
per-phase detail above is unchanged and correct; only the sequence is this section's.

## Phase 2 RDS migration — the playbook and the prerequisites, learned on setup (2026-07-22)

The setup RDS surfaced two non-obvious blockers plus the working mechanism. Every RDS-bearing stack
(`app`, `atento`, `auth`, `onboarding`'s future RDS) hits the same. Do not re-derive.

**PREREQUISITE 1 — broaden the dedicated key's policy to multi-service BEFORE touching the RDS.** The
dedicated keys were minted **via-SSM-only** (`kms:ViaService = ssm.<region>.amazonaws.com`) because they
were created for the SSM SecureStrings. RDS cannot use a via-SSM-only key for the **managed master secret
(Secrets Manager)** or **Performance Insights** — `modify-db-instance` fails with `KMSKeyNotAccessibleFault`.
STORAGE encryption slips through (RDS uses a KMS grant, which the account-root admin statement's
`kms:Create*` permits), which MASKS the problem until managed-pw/PI are enabled. So the key's use-statement
`ViaService` must become a LIST — `["ssm.<r>...", "rds.<r>...", "secretsmanager.<r>..."]` — before the RDS
migration. This is the "one key per stack, multi-service via ViaService" the AWS/community key-scope research
concluded (finest recommended granularity is one application per SDLC stage, NOT one key per service type —
k9 Security "AWS KMS Key Scope Guide" + AWS Prescriptive Guidance). It is a PREREQUISITE, not cleanup.
(setup: broadened live via `put-key-policy` + reflected in `modules/setup/kms.tf`, PR #804.)

**PREREQUISITE 2 — `prevent_destroy` in `modules/rds_instance` blocks a Terraform replace.** `kms_key_id`
is ForceNew, so changing it via TF plans a destroy+create, which `lifecycle { prevent_destroy = true }`
refuses; and prevent_destroy cannot be a variable (TF requires a literal). Two ways past it: (a) transiently
flip the module's `prevent_destroy = false` on the branch, apply, revert to true before merge; or (b) — what
setup used — do the migration by HAND (AWS CLI) so Terraform never issues a destroy, then reconcile state.

**THE MECHANISM THAT WORKED (setup) — manual CLI migration, then reconcile TF state.** All AWS-API, no
direct DB access, so the agent does it all:

1. Scale the app service to 0 (stop writes; downtime = the window).
2. `create-db-snapshot` of the current instance.
3. `copy-db-snapshot --kms-key-id alias/<stack>` — re-encrypts the snapshot under the dedicated key. THIS
   is where the re-key happens (a restore keeps the snapshot's key; restore does NOT accept a different one).
   **VERIFY this copy `available` BEFORE deleting anything — it is the rollback.**
4. `delete-db-instance --skip-final-snapshot` (deletion_protection must already be false — a prior in-place
   PR). Wait for fully deleted (frees the identifier).
5. `restore-db-instance-from-db-snapshot` from the ENCRYPTED copy, same identifier. **Restore does NOT
   accept `--manage-master-user-password`, `--enable-performance-insights`, or `--monitoring-*`** — pass only
   class / subnet / SGs / param-group / multi-az / public / deletion-protection / engine-lifecycle.
6. `modify-db-instance --manage-master-user-password --master-user-secret-kms-key-id alias/<stack>
   --enable-performance-insights --performance-insights-kms-key-id alias/<stack> --monitoring-interval N
   --monitoring-role-arn ... --apply-immediately`. Requires Prerequisite 1 already done. Non-disruptive.
7. Scale the app back up. **The endpoint is STABLE across delete+restore of the same identifier** (setup's
   `setup.cvw5l7p4adp1…` was identical), so the app's DB URL does NOT change — PROVIDED the app connects as a
   dedicated app-user (creds preserved in the restored data), NOT the managed master (whose password the
   managed-secret enable rotates). Setup's app-user survived the rotation; confirm this per stack.
8. Reconcile Terraform: update the stack code to match the now-live infra (the three RDS key args →
   `aws_kms_key.this.arn`, `kms.tf` ViaService broadened). `terraform plan` refreshes state (same identifier →
   reads the new instance, kms matches → **no ForceNew replace**) and shows only the mutable attrs the restore
   left at defaults (`copy_tags_to_snapshot`, `max_allocated_storage`, `performance_insights_retention_period`,
   re-asserting the master-secret key) as an in-place `1 to change`. Apply → `No changes` → branch is faithful.

**Data preservation:** the snapshot preserves everything; only writes during the window are lost. Confirm the
acceptable-loss story per stack (setup's is recreated-on-reconnect device registrations).

**Setup cleanup — DONE (2026-07-22).** PR #805 consolidated the RDS's three explicit key references to ONE
— `modules/rds_instance` now defaults `performance_insights_kms_key_id` + `master_user_secret_kms_key_id` to
`kms_key_id` via `coalesce`, so the caller passes the key once (the "não pode ter três entradas" rule),
backward-compatible for every other RDS stack (they pass explicit keys → coalesce returns them) — and
restored `deletion_protection = true` (dropped in PR #803 for the migration). PR #806 corrected the
`modules/setup/kms.tf` header comment, which wrongly described setup as a flat stack owning the key at stack
level; the key is created BY THE MODULE the stack imports (forward-lock), like the app/integrator estates.

**Audited and confirmed (2026-07-22) — this is the reference shape for the next stacks:** the dedicated key
is defined exactly once (`modules/setup/kms.tf`, in the module, not the stack — `terraform/setup/` carries no
kms reference at all), and the RDS references it once (`kms_key_id`; PI + managed-secret keys inherit).
Remaining: delete the two rollback snapshots (`setup-pre-dedicated-key-migration`, `…-encrypted`) once
confident — non-blocking.

## Out of scope, surfaced here so they are not forgotten

| Item | State |
|---|---|
| **OpenSearch** | ~~Blocked~~ — NO LONGER out of scope (2026-07-20). Handled by the replace path in Phases 3–8 step 4: the data need not persist, so a new domain under the correct key/name replaces the old in a quiet window. Folded into the per-stack app-estate migration. |
| **The six `backup-<stack>-local` key policies** | Right count, wrong policy (account-root `kms:*`, `modules/cross_region_backup/main.tf`). Same fix as Phase 3, different scope. |
| **`alias/4shark-ecs-beta-key`** (`6bf5847f`, us-east-1) | Orphan. Created 2025-10-17, rotation off, console-default policy, referenced by no repo. Billed ~9 months for nothing. |
| **`alias/auth002`** | No such alias exists in the account. The `6f7b8e40` id filed under that name is `alias/aws/rds` in sa-east-1 — AWS-managed and undeletable. The `auth-001` RDS runs on `alias/auth-001`; nothing here is retirable. |
| **`alias/main`** (`64eb0fa9`, sa-east-1) | Legitimate — CloudTrail's key, `audit/kms.tf:116`. Leave alone. |
| **VPN EBS encryption** | The `alias/vpn` key (PR #790) is minted ready but idle. Using it means encrypting the three VPN hosts' EBS volumes (MongoDB data host + the two Pritunl instances), which REPLACES each volume — a data migration on the MongoDB host (`disable_api_termination`, `delete_on_termination=false`, holds all Pritunl state), taken in a window. Deferred; the key's via-EC2 policy is already in place for it. |
| **The restricted engineer tier** | `active/spike/aws-engineer-staging-tier/`. This plan makes its scoping possible; it does not build it. |
| **Integrator S3 / ECR / CloudWatch Logs** | **Surfaced 2026-07-27 by the closing audit, then taken IN scope the same day — see § Phase 12** for the three efforts, their differing mechanics, and the three decisions they need first. Moved out of this table because "out of scope" is where a thing goes when nobody intends to do it. |

The remaining orphan (`alias/4shark-ecs-beta-key`) is billed and unrotated (`alias/auth002` is in use — see its row). Deleting a KMS key is irreversible — each is its own decision.

## Risks

| Risk | Mitigation |
|---|---|
| A key policy locks the key out | The account principal keeps administration in every policy. It is the only principal that cannot be deleted. Never write a policy without it. |
| Splitting the task role breaks a stack's task startup | The Phase 2 order (beta → demo → shared → setup/onboarding → atento/integrators) exists for this. Verify startup before the next stack. |
| A per-stack role silently drops a permission nobody declared | This already nearly happened: three inline policies existed only in the console. Build each role from the **live** role's policy list, not from the `.tf` — and re-check the live list before each cutover, because a new hand-made policy can appear at any time. |
| A parameter's version bump breaks something pinning that version | The bump is confirmed by probe, so it is known, not a surprise. Grep for version-pinned references before Phase 4. |
| Secrets Manager re-encryption silently no-ops | AWS documents the cause (missing decrypt on the previous key). Keep the old key readable during Phase 5 and verify the versions re-encrypted. |
| The work stalls midway | Phase 2 alone closes the cross-environment read. Stopping after it is a coherent state, not a loose end. |

## Open questions

None blocking. Recorded as unresolvable-by-documentation rather than unexamined:

- **OpenSearch downtime for a domain replacement** — AWS does not publish it. Blocks only the
  OpenSearch decision, which is out of scope above.
- **An RDS encryption context** (which could scope decrypt per-instance on a shared key the way
  `PARAMETER_ARN` does for SSM) — the AWS KMS/RDS page failed to render across three fetch attempts.
  UNVERIFIED. Does not block anything here.
