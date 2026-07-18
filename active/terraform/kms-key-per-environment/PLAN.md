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
| On `4shark-master` | `app-beta-001`, `app-demo-001`, `app-shared-001`, `app-atento-001`, `setup`, `onboarding` | `mrk-fa0cda24…`, **customer-managed**, us-east-1 | **Yes** — everything below applies |
| On the AWS default SSM key | `integrator-almaviva`, `integrator-atento`, `integrator-commcenter`, `integrator-maqnelson`, `integrator-redebrasil` | `b16e449a…`, **AWS-managed**, sa-east-1 | **No** |

The second key is `alias/aws/ssm` for sa-east-1 — `describe-key` returns `"KeyManager": "AWS"` and
*"Default key that protects my SSM parameters when no other key is defined"*. **An AWS-managed key
does not accept a custom key policy**, so the two-statement policy below cannot be written for it.
The five integrators cannot be isolated by editing that key; isolating them means first moving them
onto customer-managed keys, which is a separate decision with its own migration.

**What is NOT yet established** (do not assume either way without checking): whether those five are
actually exposed today. Decrypt through an AWS-managed SSM key only happens *via SSM*, so the SSM
parameter permission may already be the real boundary — in which case the per-stack role split alone
isolates them and no key work is needed. Answer this before scoping any integrator key work; it
decides whether that work exists at all.

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

**Remaining (all non-productive):** the two `app-outbound-*` stacks (the sa-east-1 payroll/outbound workers — name the shared role in task defs, no SSM policy of their own), and the five `integrator-*` stacks (the AWS-managed `alias/aws/ssm` key design decision — the role split alone vs customer-managed keys).
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

### Phase 3 — Create the six keys with restrictive policies

Regional keys, two-statement policy as above, each naming its own stack's role from Phase 2. Nothing
consumes them yet, so this phase carries no migration risk.

### Phase 4 — Move SSM onto the per-stack keys

Point each `ssm.tf` at its key, rekey the existing parameters
(`put-parameter --overwrite --key-id` — probed, bumps version), confirm the application still reads
them. **Beta first** — this is also the phase that unblocks the restricted engineer tier
(`active/spike/aws-engineer-staging-tier/`). Then one productive stack at a time, verified between
each.

### Phase 5 — Secrets Manager (pooler userlist)

`UpdateSecret --kms-key-id`, four stacks, beta first. Keep decrypt on the old key until the
re-encryption is confirmed (the documented trap above).

### Phase 6 — RDS

Snapshot + copy under the new key + restore. One maintenance window per instance. Beta first
(free), then the productive stacks one at a time on a real window.

**Separable and deferrable indefinitely.** Phases 2–5 close the cross-environment read on their own;
no engineer tier holds raw RDS storage decrypt (the database is reached by credential, not by KMS).
If deferred, record it as a decision rather than a loose end.

### Phase 7 — Migrate legacy RDS instances off the old key (was `kms-migration` Task 2)

Some RDS instances still use a pre-migration key (`64b7af79-...`). Identify them:

```bash
aws rds describe-db-instances --query 'DBInstances[*].[DBInstanceIdentifier,KmsKeyId]' --output table --region us-east-1
aws rds describe-db-clusters --query 'DBClusters[*].[DBClusterIdentifier,KmsKeyId]' --output table --region us-east-1
```

Per instance: manual snapshot → `copy-db-snapshot --kms-key-id <its stack's key>` → restore → point
Terraform at the new instance → delete the old.

**Changed from the original plan**: the old plan sent these to `4shark-master`. Under this design
they go straight to their own stack's key — one window instead of two, and no intermediate wrong
state. Fold into Phase 6, same windows.

### Phase 8 — Retire `4shark-master`

Only once nothing references it. Deleting a KMS key is irreversible — its own decision, its own PR.

## Out of scope, surfaced here so they are not forgotten

| Item | State |
|---|---|
| **OpenSearch** | Cannot rekey in place; AWS documents no migration path and no downtime figure for a key change. Both domains stay on `4shark-master`, which blocks Phase 8 until decided separately. |
| **The six `backup-<stack>-local` key policies** | Right count, wrong policy (account-root `kms:*`, `modules/cross_region_backup/main.tf`). Same fix as Phase 3, different scope. |
| **`alias/4shark-ecs-beta-key`** (`6bf5847f`, us-east-1) | Orphan. Created 2025-10-17, rotation off, console-default policy, referenced by no repo. Billed ~9 months for nothing. |
| **`alias/auth002`** (`df7df919`, sa-east-1) | Orphan. Created 2024-12-12, no description, no `auth-002` stack exists. |
| **`alias/main`** (`64eb0fa9`, sa-east-1) | Legitimate — CloudTrail's key, `audit/kms.tf:116`. Leave alone. |
| **The restricted engineer tier** | `active/spike/aws-engineer-staging-tier/`. This plan makes its scoping possible; it does not build it. |

Both orphans are billed and unrotated. Deleting a KMS key is irreversible — each is its own decision.

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
