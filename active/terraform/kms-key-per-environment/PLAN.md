# PLAN — One KMS key per environment, with restrictive key policies

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

**Remaining (all non-productive):** only the five `integrator-*` stacks (the AWS-managed `alias/aws/ssm` key design decision — the role split alone vs customer-managed keys). Both `app-outbound-*` stacks are DONE.
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

### Phases 3–8 — The app estate: module-owned keys, data migration, and naming (RESTRUCTURED 2026-07-20)

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

> **Status 2026-07-20:** the dedicated key per integrator is already MINTED — `modules/integrator`
> creates `alias/integrator-<slug>` by construction (`modules/integrator/kms.tf`, Phase 10 done via
> #785). So step 2 below ("customer-managed key per integrator") is DONE; what remains is the role
> split (step 1), moving SSM onto the key (step 3), plus the naming + Redis standardizations. Sequenced
> 4th in the authoritative **Execution order** section above. The population table in § Scope ("on the
> AWS-managed `alias/aws/ssm`") predates #785 and is stale for the key — the key is customer-managed now.

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

**Progress (2026-07-23):** DONE + merged — `auth` (**#814**, ~50 names + rds_instance switch, 0/0/0),
`onboarding` (**#816**, 0/0/0, also fixed an SSM path-vs-grant inconsistency), `setup` (**#817**, 0/0/0
including the production RDS). IN PROGRESS — `vpn`. **`vpn` decision (engineer, 2026-07-23): option B —
parameterize it via `var.identifier` for uniformity, EVEN THOUGH its "vpn" is the application name (ADR-010, a
deliberate singleton with no `-001`/`-002`), not an environment identifier.** So vpn gets a new `variables.tf`
+ `identifier` driving the resource names; the many `Role = "vpn"` tags stay (they are the role, like `Project`),
the terraform resource labels (`resource "x" "vpn"`, `aws_*.vpn` refs) stay (state addresses), targeted edits
only (~50), 0/0/0 gate. Only after `vpn` are all four a clean reference and the integrator effort (below) begins.

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
     assume it) — capture it before touching the Redis.
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
| **`alias/auth002`** (live `6f7b8e40`, sa-east-1) | **NOT an orphan — corrected 2026-07-22.** It encrypts the `auth-001` RDS storage today (`modules/auth/rds.tf` hardcodes its key). Retire only AFTER the auth RDS is re-keyed onto `alias/auth-001` (Effort 2 in § "What is already DONE"). The `df7df919` id recorded earlier does not match live (`6f7b8e40`) — reconcile before any deletion. |
| **`alias/main`** (`64eb0fa9`, sa-east-1) | Legitimate — CloudTrail's key, `audit/kms.tf:116`. Leave alone. |
| **VPN EBS encryption** | The `alias/vpn` key (PR #790) is minted ready but idle. Using it means encrypting the three VPN hosts' EBS volumes (MongoDB data host + the two Pritunl instances), which REPLACES each volume — a data migration on the MongoDB host (`disable_api_termination`, `delete_on_termination=false`, holds all Pritunl state), taken in a window. Deferred; the key's via-EC2 policy is already in place for it. |
| **The restricted engineer tier** | `active/spike/aws-engineer-staging-tier/`. This plan makes its scoping possible; it does not build it. |

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
