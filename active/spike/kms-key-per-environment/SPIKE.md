# SPIKE — One KMS Key Per Environment

## Investigation question

4Shark wants one KMS key per environment so a leak in one environment cannot decrypt another's
data (engineer, verbatim: *"é uma chave por ambiente, cara, porque se algum ambiente vazar,
qualquer coisa não afeta o outro"*). Question: what do AWS and the community actually recommend
on KMS key segregation vs consolidation — does key separation deliver the isolation claimed, what
does it cost, and what does migration require per service?

**Revision scope**: new research surfaced that "production vs dev/test" (AWS's data-classification
guidance) and "one key per tenant" (AWS's SaaS tenancy guidance) are TWO DIFFERENT AXES, not
competing answers to the same question. This revision reconciles them explicitly rather than
picking a number, per the engineer's own instruction that the spike must not just swing to
whatever he said most recently.

## Sources consulted

- `app-beta-001/ssm.tf:67-68`, `app-demo-001/ssm.tf:67-68`, `app-shared-001/ssm.tf:54-55`,
  `app-atento-001/ssm.tf:58-59` — confirmed myself: all four grant `kms:Decrypt` on the same key
- `app-beta-001/ssm.tf:53`, `app-demo-001/ssm.tf:53`, `app-shared-001/ssm.tf:39`,
  `app-atento-001/ssm.tf:43`, `setup/ssm.tf:45`, `onboarding/ssm.tf:49` — confirmed myself: every
  stack's SSM policy attaches to the same role name
- `modules/cross_region_backup/main.tf` — read in full; the in-house per-stack key precedent
- `~/.claude/skills/apps/environments.json` — classification/tenancy metadata per app environment
- `~/.claude/docs/PROJECTS-CATALOG.md:51-52` — classification for `setup`/`onboarding`
- Live AWS state (read-only, this session): `kms list-aliases` (us-east-1), `kms describe-key` +
  `get-key-policy` + `get-key-rotation-status` for `4shark-ecs-beta-key` and `4shark-master`
- `~/Projects/4Shark/dot-claude-plans/active/terraform/kms-migration/PLAN.md` — read in full (56
  lines); the existing plan this spike's direction may supersede
- `~/Projects/4Shark/dot-claude-plans/active/spike/aws-engineer-staging-tier/SPIKE.md` — sibling
  spike, Finding 4 (the leak this investigation is triggered by)
- See auxiliary: `kms-key-per-environment_doc_1.txt` — AWS Well-Architected SEC08-BP02 (classification axis)
- See auxiliary: `kms-key-per-environment_doc_2.txt` — AWS KMS key-policies.html
- See auxiliary: `kms-key-per-environment_doc_3.txt` — SSM Parameter Store KMS encryption context
- See auxiliary: `kms-key-per-environment_doc_4.txt` — RDS/Secrets Manager/SSM rekey mechanics
- See auxiliary: `kms-key-per-environment_doc_5.txt` — AWS silo-model guidance (tenancy axis)
- See auxiliary: `kms-key-per-environment_doc_6.txt` — AWS pool-isolation guidance (tenancy axis, historical-reference banner)
- See auxiliary: `kms-key-per-environment_doc_7.txt` — AWS KMS default key policy (the pivotal finding)
- See auxiliary: `kms-key-per-environment_doc_8.txt` — AWS S3 multi-tenant blog, key layering
- See auxiliary: `kms-key-per-environment_doc_9.txt` — AWS KMS resource quotas
- See auxiliary: `kms-key-per-environment_doc_10.txt` — AWS cost-conscious KMS strategy blog (both halves)
- See auxiliary: `kms-key-per-environment_doc_11.txt` — AWS decentralized-vs-centralized guidance, corrected scope
- See auxiliary: `kms-key-per-environment_doc_12.txt` — OpenSearch/EBS/pricing, directly re-fetched
- See auxiliary: `kms-key-per-environment_data_1_aliases_useast1.json` — live KMS alias listing
- See auxiliary: `kms-key-per-environment_data_2_key_details.json` — describe-key/policy/rotation
  for `4shark-ecs-beta-key` and `4shark-master`
- See auxiliary: `kms-key-per-environment_data_3_ssm_role_grep.txt` — the shared-role grep

## Findings

### Finding 1: The shared-key state is confirmed, and the key's own description says it is deliberate

**Evidence:** `app-beta-001/ssm.tf:68`, `app-demo-001/ssm.tf:68`, `app-shared-001/ssm.tf:55`,
`app-atento-001/ssm.tf:59` all grant `kms:Decrypt` on
`arn:aws:kms:us-east-1:405749097490:key/mrk-fa0cda243274491784fc7b39bead5a03` — one key across
all four app environments, productive included. `kms describe-key` on that key ID returns
`"Description": "4Shark master encryption key - all environments and services"`.

**Source:** the four `ssm.tf` files above; `kms-key-per-environment_data_2_key_details.json` →
`master_key_describe.KeyMetadata.Description`.

**Significance:** the single-key design is not an oversight — its own description states the
scope as "all environments and services."

### Finding 2: The estate sits on TWO independent axes — classification and tenancy — and neither alone yields a key count

**Evidence:** mapping each environment against both axes, verified per-cell:

| Environment | Classification | Tenancy | Source |
|---|---|---|---|
| `beta-001` | no real data — `"notes": "... Data is fabricated."` | n/a | `environments.json` |
| `demo-001` | REAL client data despite `"productive": false` — `"it carries REAL data (beta has only fabricated data)"` | pooled | `environments.json` |
| `shared-001` | production (`"productive": true`) | **pool** — `"kind": "multi-tenant"`, `"most white-label clients live here"` | `environments.json` |
| `atento-001` | production (`"productive": true`) | **silo** — `"kind": "dedicated"`, `"Dedicated backend for the largest client (Atento) — contracted for 9 countries"` | `environments.json` |
| `setup` | production — `"Mandatory for the mobile client"` | pooled config (one service configures every client's mobile app) | `PROJECTS-CATALOG.md:51` |
| `onboarding` | not wired to runtime — `"nothing is wired into the runtime yet"` | n/a | `PROJECTS-CATALOG.md:52` |

**Source:** table above.

**Significance:** classification (what the data IS — production, real-but-non-prod, fabricated)
and tenancy (who else's data shares the boundary — silo vs pool) are orthogonal. `shared-001` and
`atento-001` are BOTH production, so a classification-only split (Finding 3) puts them on the same
key despite being opposite tenancy shapes. `beta-001` and `demo-001` are BOTH non-productive, so
they would also share a key under classification-only, despite one holding zero real data and the
other holding real client data. A design must state EXPLICITLY which axis (or both) it honours —
neither axis by itself produces 4Shark's "six environments" nor the engineer's "two" in one
coherent scheme.

### Finding 3: The classification axis — AWS's worked example is a two-way split, not a six-way one

**Evidence:** *"Using the same encryption key for all data regardless of data usage, types, and
classification"* is a named anti-pattern. The implementation step: *"create one AWS KMS key for
encrypting production data and a different key for encrypting development or test data."*

**Source:** AWS Well-Architected Framework, SEC08-BP02 (`kms-key-per-environment_doc_1.txt`).

**Significance:** this is real AWS guidance, and it backs moving off ONE shared key — but its own
example draws the line at production vs dev/test, a coarser split than "one key per environment."
It says nothing about tenancy (Finding 4) — `shared-001` and `atento-001` are indistinguishable
under this axis alone, both being "production."

### Finding 4: The tenancy axis — a separate key per TENANT, and atento-001 matches the trigger language literally

**Evidence:** *"Each tenant will also have a separate AWS Key Management Service (AWS KMS) key for
encryption."* The trigger for this model: *"In some cases, large customers require dedicated
clusters to reduce noisy neighbor impact. In those situations, you can apply the silo model."*
Counterweight, same page: *"The [...] team generally advises against a silo model because of the
higher cost incurred by idle resources and the additional operational complexities. However, for
highly regulated or sensitive workloads require this additional isolation, customers might be
willing to pay the additional cost."*

Separately, on the pooled side (`shared-001`): *"you cannot use this as a rationale to relax the
isolation requirements of your environment. If anything, these shared model increases the chance
for cross-tenant access"* — carries a "historical reference only" banner.

**Source:** AWS Prescriptive Guidance, silo-model multi-tenancy
(`kms-key-per-environment_doc_5.txt`); AWS Whitepaper, SaaS Tenant Isolation Strategies, pool
isolation (`kms-key-per-environment_doc_6.txt`).

**Significance:** `atento-001` — dedicated infra, largest client, 9 countries contracted (Finding
2) — is the literal case this guidance describes ("large customers require dedicated clusters").
`shared-001`'s pooled model is explicitly the HARDER case to isolate, per this source, not a
reason to isolate less. This is a different axis from Finding 3 and argues for a DIFFERENT split
than the classification axis does: `atento-001` separate from `shared-001` regardless of both
being "production."

### Finding 5: The condition under which ANY of the options is real rather than theatre — a restrictive key policy, not the key's mere existence

**Evidence:** *"Unless the key policy explicitly allows it, you cannot use IAM policies to allow
access to a KMS key. Without permission from the key policy, IAM policies that allow permissions
have no effect. [...] The default key policy enables IAM policies."* And, on the default
programmatic policy specifically: *"Unlike other AWS resource policies, an AWS KMS key policy does
not automatically give permission to the account or any of its identities. [...] This default key
policy statement allows the account to use IAM policies to delegate permission for all actions
(kms:*) on the KMS key."*

**Source:** AWS KMS key-policies.html (`kms-key-per-environment_doc_2.txt`); AWS KMS default key
policy (`kms-key-per-environment_doc_7.txt`).

**Consequence, checked against 4Shark's own code:** a per-stack key created with Terraform's
DEFAULT policy shape — account-root, `kms:*` — delegates ALL authorization back to IAM. A
principal holding `kms:Decrypt` on `"*"` in an IAM policy then has access to every key with that
shape, defeating the isolation the separate key was created for. 4Shark's OWN in-house per-stack
precedent has exactly this shape today: `modules/cross_region_backup/main.tf:14-24` builds
`local.kms_policy` as a single statement —

```hcl
locals {
  kms_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "EnableAccountAdmin"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "kms:*"
      Resource  = "*"
    }]
  })
}
```

— applied to both `aws_kms_key.local` and `aws_kms_key.dr` (`main.tf:29-50`), i.e. every
`backup-<stack>-local`/`-dr` key in the account-root shape Finding 5 flags as delegating, not
restricting.

**Significance:** this is the finding that most changes the decision. A per-environment (or
per-tenant) key is a real second wall ONLY if its key policy scopes `kms:Decrypt` to the specific
principals that should hold it — otherwise a broad IAM grant (`kms:Decrypt` on `"*"`, or on that
key's specific ARN if an identity is over-scoped) reopens every key with that policy shape, and
the separate keys buy nothing over one shared key. This condition applies uniformly across
Findings 2, 3, and 4 — whichever axis (or axes) the design honours, the isolation is real only if
this condition is also met. And it names a live weakness: the backup-key precedent (Finding 8)
already has the permissive shape.

### Finding 6: For SSM SecureString specifically, the classification/tenancy isolation is achievable on the EXISTING shared key too, via IAM condition on encryption context

**Evidence:** Parameter Store's encryption context is `PARAMETER_ARN`, and for a hierarchical path
it already includes the full path — 4Shark's own parameters already follow `/beta-001/*`,
`/demo-001/*`, etc. AWS documents: *"You can also include the encryption context in an IAM
policy. For example, you can permit a user to decrypt only one particular parameter value or set
of parameter values."* with a worked `kms:EncryptionContext:PARAMETER_ARN` condition example.

**Source:** SSM Parameter Store KMS encryption doc (`kms-key-per-environment_doc_3.txt`).

**Significance:** for SSM, a correctly-scoped IAM policy condition on the CURRENT shared key would
already prevent an identity that leaked in `beta-001` from decrypting a `shared-001` parameter —
no new key required for that specific claim, PROVIDED Finding 5's condition (restrictive scoping)
is met — a condition on a policy is exactly the kind of restriction Finding 5 says the key alone
does not provide. This is NOT investigated for RDS/EBS/OpenSearch in this spike (see "What remains
uncertain").

### Finding 7: Layering — encrypt AND control key access — is AWS's own framing, not a practitioner theory

**Evidence:** *"When using encryption keys, it is important to use different keys for data that
belongs to different entities to keep access to the data isolated."* And: *"Another option that
provides you with two layers of protection is to encrypt the data and make sure that access to
the keys used to encrypt the data is also strictly controlled."*

**Source:** AWS Storage Blog, prefix-level encryption keys in Amazon S3
(`kms-key-per-environment_doc_8.txt`).

**Significance:** corroborates Finding 5 from an independent AWS source — the recommended shape is
always TWO layers (a key boundary AND a restricted-access boundary), never one alone.

### Finding 8: 4Shark already has an in-house per-stack key precedent — regional, not multi-region — with the Finding 5 weakness

**Evidence:** `modules/cross_region_backup/main.tf:29-57` creates `aws_kms_key.local` (source
region) and `aws_kms_key.dr` (destination region) — two ordinary regional keys per invocation,
aliased `backup-<identifier>-local` / `backup-<identifier>-dr`, NOT one multi-region key. Confirmed
live as 6 aliases in us-east-1 (`kms-key-per-environment_data_1_aliases_useast1.json`):
`app-atento-001`, `app-beta-001`, `app-demo-001`, `app-shared-001`, `onboarding`, `setup`.
`auth-001/backup.tf` also invokes the module; no `backup-auth-001-*` alias appears in the
us-east-1 listing — not verified where it lives.

**Source:** `modules/cross_region_backup/main.tf:14-57` (read in full).

**Significance:** demonstrates the estate does NOT need multi-region keys to satisfy cross-region
backup — two regional keys suffice. But per Finding 5, this precedent's key POLICY is the
delegating account-root shape, not a restrictive one — so as a MODEL for a new per-environment
key, it demonstrates the naming/regional shape but NOT yet the restrictive-policy half that would
make the isolation real.

### Finding 9: RETRACTED/corrected — the "decentralized approach" guidance does not apply to this decision

**Evidence:** *"There are two broad approaches to managing AWS KMS keys in multi-account
environments."* The decentralized approach means *"you create keys in each account that uses
those keys"*; centralized means keys live in *"one or a few designated AWS accounts"* accessed
cross-account. *"In general, we recommend that you start with a decentralized approach unless you
can articulate a need for a centralized KMS key model."*

**Source:** AWS Prescriptive Guidance, key-management.html
(`kms-key-per-environment_doc_11.txt`).

**Significance:** this quote was cited in the prior draft of this spike as arguing for
"fewer/more keys within one account." That is wrong — its axis is explicitly MULTI-ACCOUNT key
placement (which AWS account holds the key), not per-account key count. 4Shark runs a single AWS
account, so this guidance's literal question does not arise here. Retracted as support for either
side of the environment-count question; corrected rather than silently deleted, per the citation
rule that a source cited once must not be re-cited with a changed meaning.

### Finding 10: Migration cost varies sharply by service — some in-place, some require full replacement

**Evidence:**
- RDS — *"Amazon RDS doesn't currently support in-place conversion of unencrypted instances to
  encrypted instances"*; snapshot+copy+restore, *"a downtime period of at least 30 minutes."*
- EBS — *"You cannot change the KMS key that is associated with an existing snapshot or volume.
  However, you can associate a different KMS key during a snapshot copy operation"* — a full,
  non-incremental copy.
- OpenSearch — *"After you configure a domain to encrypt data at rest, you can't disable the
  setting. Instead, you can take a manual snapshot of the existing domain, create another domain,
  migrate your data, and delete the old domain."* Manual key rotation is explicitly unsupported.
- Secrets Manager — `UpdateSecret --kms-key-id` re-encrypts `AWSCURRENT`/`AWSPENDING`/`AWSPREVIOUS`
  in place, no resource recreation.
- S3 — changing the bucket's default encryption key is instant but does NOT retroactively
  re-encrypt existing objects; needs Batch Operations or `UpdateObjectEncryption`.
- SSM SecureString — `put-parameter --overwrite --key-id <new>` re-triggers the standard
  `Encrypt` workflow under the new key, same parameter name, no resource recreation — mechanically
  cheap, though the AWS CLI reference page does not explicitly document this as a supported
  "rekey" operation (inferred from documented mechanics, not an AWS-stated guarantee).

**Source:** AWS Database Blog + Secrets Manager doc (`kms-key-per-environment_doc_4.txt`);
OpenSearch + EBS docs, directly re-fetched (`kms-key-per-environment_doc_12.txt`).

**Significance:** RDS, EBS, and OpenSearch require a full replacement (instance/volume/domain) to
change key — the expensive tier, whichever axis is chosen. SSM, Secrets Manager, S3-new-objects
are cheap or free of downtime. The migration cost is a property of the SERVICE, not of how many
keys the final design has — the same cost applies whether moving to 2 keys or 6.

### Finding 11: Cost and quota are both non-factors

**Evidence:** *"Each AWS KMS key that you create in AWS KMS costs $1/month (prorated hourly)."*
Confirmed directly: *"The $1/month charge is the same for [...] multi-Region keys (each primary
and each replica multi-Region key)"* — each replica bills separately. API requests: *"$0.03 /
10,000 requests"* beyond a 20,000/month free tier, account-wide. Quota: *"You can have up to
100,000 customer managed keys in each Region of your AWS account"* and *"All AWS KMS resource
quotas are adjustable."*

Confirmed live customer-managed keys in us-east-1 today: `4shark-master` (+1 more for its
`sa-east-1` replica), `4shark-ecs-beta-key`, `KMS-BackupAMIs-virginia`, and 6
`backup-<stack>-local` keys — 9 confirmed in this region alone, ≈$9/month baseline.

**Source:** AWS KMS pricing, directly re-fetched (`kms-key-per-environment_doc_12.txt`); AWS KMS
resource quotas (`kms-key-per-environment_doc_9.txt`); live alias listing.

**Significance:** a 2-key classification split adds ~$2-4/month; a 6-key per-environment split
adds ~$6-12/month; honouring BOTH axes across the full matrix in Finding 2 (up to 6+ cells) is
still comparably trivial. 100,000 keys per region means the quota is never a constraint at 4Shark's
scale. Neither cost nor quota discriminates between any of the options.

### Finding 12: `alias/4shark-ecs-beta-key` is live, billed, and unreferenced by any Terraform or repo

**Evidence:** created 2025-10-17, `KeyRotationEnabled: false`, key policy is the bare console
default template — only account-root + two IAM key-admin principals, no service-principal
statement, no resource-scoped grant. `grep -rn` for the alias name and its raw key ID across
`~/Projects/4Shark/terraform/` and every other 4Shark repo: zero hits. `app-beta-001`'s RDS,
connection pooler, and SSM all reference `4shark-master` instead.

**Source:** `kms-key-per-environment_data_2_key_details.json`; grep of the terraform repo.

**Significance:** appears orphaned — billed for ~9 months, unreferenced. Not investigated: who
created it or why (would need a CloudTrail dig into 2025-10-17, out of scope here).

### Finding 13: The workload identity is a real audience too — one role holds the union of every environment's grant

**Evidence:** every stack's SSM policy attaches to the identical role name:
```
app-atento-001/ssm.tf:43:  role = "ecsTaskExecutionRole"
app-demo-001/ssm.tf:53:    role = "ecsTaskExecutionRole"
app-beta-001/ssm.tf:53:    role = "ecsTaskExecutionRole"
app-shared-001/ssm.tf:39:  role = "ecsTaskExecutionRole"
setup/ssm.tf:45:           role = "ecsTaskExecutionRole"
onboarding/ssm.tf:49:      role = "ecsTaskExecutionRole"
```

**Source:** `kms-key-per-environment_data_3_ssm_role_grep.txt`.

**Significance:** IAM policies attached to a role accumulate. This role — not a human — is the
principal that actually holds `ssm:GetParameters` across every environment's path prefix plus
`kms:Decrypt` on the shared key, and has held it since these stacks were created. The identity
boundary has demonstrably failed here for YEARS, independent of any key decision — which is both
the argument for treating a key as an independent second control (a role misconfiguration alone
cannot then cross a key boundary) AND the reason Finding 5's "restrictive policy" condition
matters so much: a new key inherits nothing protective if this same role is simply granted
decrypt on it too.

### Finding 14: No published defender found for "IAM scoping alone is sufficient, extra keys are theatre"

**Evidence:** none of the sources fetched in this spike — AWS Well-Architected, AWS Prescriptive
Guidance (silo model, key management), the AWS SaaS tenant isolation whitepaper, the AWS KMS
developer guide, or the two AWS blog posts — argue that a correctly-scoped IAM policy on a single
shared key is a complete substitute for key-level separation. Every source that discusses the
trade-off treats "how many keys" and "how tight is the policy" as separate, additive questions,
never as alternatives.

**Source:** absence across all fetched sources in this spike (Findings 2–11).

**Significance:** recorded as a negative finding, not a gap — its absence is itself evidence
against the position that IAM scoping alone (Finding 6's mechanism) is sufficient and a separate
key is unnecessary theatre. The engineer's instinct that a key is a meaningful control is not
contradicted by any source found; what the sources contradict is only the specific claim that
"one key per environment" (as opposed to per-classification or per-tenant) is what AWS
prescribes.

### Finding 15: The existing `kms-migration/PLAN.md` conflicts with a per-environment/per-tenant direction on exactly one task

**Evidence:** Task 1 (import the CLI-created `4shark-master` into Terraform state) is independent
of the axis decision — prerequisite housekeeping regardless of the final key count. Task 2
(*"Migrate old RDS instances to `4shark-master` KMS key"*, via snapshot+copy+restore) is NOT
independent — moving legacy RDS instances onto the single shared key, only to move them again onto
a new key shortly after, is duplicate maintenance-window work (Finding 10 confirms RDS rekey needs
≥30 min downtime each time) in the wrong direction if segregation is adopted on either axis.

**Source:** `~/Projects/4Shark/dot-claude-plans/active/terraform/kms-migration/PLAN.md:25-56`
(read in full).

**Significance:** whether Task 2 proceeds as written, is deferred, or is redirected straight at a
new key is a scope decision this spike surfaces but does not make.

### Finding 16: The intra-stack prod-vs-staging case (added 2026-07-20) — the two axes point opposite ways, and the keys' PURPOSE breaks the tie toward one key per stack

**New question from the engineer:** an integrator stack often carries two ECS clusters in the SAME
stack, same network — production and staging (e.g. `integrator-commcenter` + `integrator-commcenter-staging`).
One key for the stack, or one per cluster? Staging here is 4Shark-internal homologation, not the
client's data; a staging leak is internal-only, and the only thing a shared key costs is that a
staging compromise could reach production's integration data.

**The two axes established above disagree on this exact cell:**
- **Classification (Finding 3, SEC08-BP02)** — *"create one AWS KMS key for encrypting production
  data and a different key for encrypting development or test data"* → prod cluster and staging
  cluster are literally "production" vs "test", so this axis says TWO keys.
- **Tenancy (Finding 4 / Finding 7)** — *"use different keys for data that belongs to different
  entities"* → prod and staging of one integrator are the SAME entity (same client, same 4Shark-internal
  ownership), so this axis says ONE key.

**What breaks the tie: the keys' purpose at 4Shark is per-integrator ACCESS DELEGATION** (decided
2026-07-20; the whole reason the integrator keys exist — grant an engineer who owns a client the
ability to reach only that client's integrator). The delegation boundary is the integrator, i.e. the
STACK, not the cluster: whoever owns Commcenter owns its prod AND its staging. A per-stack key already
delivers the isolation that goal needs — Commcenter's key names only Commcenter's role, so no other
integrator's role can decrypt it (the integrator-to-integrator wall). Splitting prod/staging WITHIN
one integrator advances the delegation goal by nothing, because delegation is whole-integrator.

**The engineer's risk instinct is correct but aimed at the wrong threat.** KMS-key theft is near-zero
(it needs a principal the key policy already restricts). The threat that ACTUALLY materialized at
4Shark is Finding 13 — an over-broad IAM/role grant, held for years. A per-STACK key already contains
that at the integrator boundary; a second staging key would only narrow it to the intra-integrator
"a staging-role misconfiguration reaching Commcenter-prod" case — a real but far smaller blast radius,
and one that Finding 6 can address WITHOUT a second key: SSM encryption-context conditioning on
`PARAMETER_ARN` (`/commcenter/*` vs `/commcenter-staging/*`) gives path-level prod/staging isolation on
a single key. Only CRYPTOGRAPHIC prod/staging separation — a staging compromise that cannot decrypt
prod even under a broad IAM grant — requires the second key.

**Recommendation: one key per STACK.** It matches the delegation boundary the keys exist to serve,
honours the tenancy axis (same entity → same key), and keeps prod/staging isolation available via IAM
encryption-context (Finding 6) if ever wanted, without a second key to maintain. The SEC08-BP02
prod/test pull is real but weaker here because staging is same-entity internal homologation, not a
distinct client-sensitivity class.

**The one condition that flips it to per-cluster keys — name it so the next session doesn't re-derive
it:** the day 4Shark wants **staging-only (or prod-only) delegation** — a less-trusted principal who
may touch an integrator's staging but must NOT touch its production — prod and staging need separate
keys, because only a key boundary makes "staging yes, prod no" enforceable against an IAM
misconfiguration. Until that is a stated need, it is speculative and one key per stack is correct.

**Source:** Findings 3, 4, 6, 7, 13 of this spike (no new external fetch — this cell is fully decided
by the axes already established); engineer's framing of the Commcenter prod/staging case, 2026-07-20.

## Trade-offs surfaced

| Axis honoured | Requires | Buys | Costs / leaves open | Source |
|---|---|---|---|---|
| Neither (status quo) | — | — | full account-wide blast radius on `4shark-master`; the same role holds decrypt across every environment (Finding 13) | Findings 1, 13 |
| Classification only (e.g. production vs non-productive) | keys mapped to data-sensitivity tier | matches AWS's literal SEC08-BP02 example; cheapest new-key footprint | `shared-001` and `atento-001` share a key despite opposite tenancy shapes (pool vs silo); `beta-001` (no real data) and `demo-001` (real data) share a key despite different classification-worthy risk | Finding 3 |
| Tenancy only (e.g. atento-001 silo vs everything else pooled) | a key per tenant-isolation boundary | matches AWS's silo-model guidance almost literally for `atento-001`; addresses the "largest client" concentration risk directly | says nothing about `beta-001` (fabricated) vs `demo-001` (real data) sharing a key, since both are "non-tenant-specific" internal environments | Finding 4 |
| Both axes, mapped per the Finding 2 table | a key per distinct classification×tenancy cell the estate actually has | closest to the engineer's stated goal, verified against BOTH concerns AWS documents separately | most keys/policies to keep restrictive; still cheap (Finding 11) | Findings 2, 11 |
| Any of the above, with a default/account-root key policy (as `cross_region_backup` uses today) | — | — | delivers NO isolation over the current shared key regardless of axis chosen — the separation is theatre unless the key policy is also restrictive | Finding 5, 8 |

## What remains uncertain

- Whether SSM's `kms:EncryptionContext` conditioning strategy (Finding 6) has an equivalent for
  RDS, EBS, or Secrets Manager on a shared key — not investigated in this time-boxed spike.
- Who created `4shark-ecs-beta-key` and why (Finding 12) — would need a CloudTrail lookup for
  2025-10-17, not done here.
- Whether `auth-001`'s `cross_region_backup` invocation (Finding 8) is live in a different region
  or not yet applied — not verified.
- Which axis (or axes) the engineer actually wants honoured — classification, tenancy, or the full
  matrix (Finding 2) — is the open scope question this revision was built to surface rather than
  resolve.
- What happens to `kms-migration/PLAN.md` Task 2 (Finding 15) — proceed, defer, or redirect.
- **SSM in-place rekey via `put-parameter --overwrite --key-id`** was reported to the author of
  this spike as empirically settled by a live probe outside this document (key changed, tier
  preserved, version incremented 1→2, value decrypted intact) — this is a WRITE operation and this
  spike's AWS access is read-only, so it was NOT independently re-run or re-verified here; recorded
  as relayed, not as a citation this spike can stand behind on its own.
- **Settled, no longer open** (previously flagged uncertain, now directly re-fetched in this
  revision): AWS KMS pricing (Finding 11), the EBS in-place-change limitation (Finding 10), and
  OpenSearch forcing domain replacement to change key (Finding 10) all now carry direct,
  verbatim-quoted AWS-documentation citations rather than WebSearch-only synthesis.

## Suggested options for main and the engineer

- Option A: honour the classification axis only — closest to AWS's literal SEC08-BP02 example
  (Finding 3), cheapest, leaves the pool/silo distinction unaddressed
- Option B: honour the tenancy axis only — closest to AWS's silo-model guidance for `atento-001`
  (Finding 4), leaves the classification distinction (fabricated vs real non-prod data) unaddressed
- Option C: honour both axes, one key per distinct cell in the Finding 2 table — closest to the
  engineer's stated goal, most keys/policies to maintain
- Option D: keep the single shared key, add `kms:EncryptionContext` IAM conditions scoped per
  environment path (Finding 6) — fixes the SSM leak with zero new keys; leaves
  RDS/EBS/OpenSearch/Secrets Manager on the shared key unless separately addressed
- **Regardless of A/B/C/D**: the key policy on whatever is chosen must be restrictive, not the
  account-root default shape `cross_region_backup` uses today (Finding 5, 8) — without this, the
  option chosen delivers no isolation over the status quo
- Regardless of A/B/C/D: `kms-migration/PLAN.md` Task 1 (import `4shark-master`) stays needed;
  Task 2 (migrate legacy RDS onto `4shark-master`) needs an explicit engineer call given Finding 15
- Regardless of A/B/C/D: `4shark-ecs-beta-key` (Finding 12) and the same-role-across-stacks shape
  (Finding 13) are separate cleanup/hardening decisions surfaced by this spike, not resolved by it
