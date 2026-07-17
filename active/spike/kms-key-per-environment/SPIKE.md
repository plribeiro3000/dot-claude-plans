# SPIKE — One KMS Key Per Environment

## Investigation question

4Shark wants one KMS key per environment so a leak in one environment cannot decrypt another's
data (engineer, verbatim: *"é uma chave por ambiente, cara, porque se algum ambiente vazar,
qualquer coisa não afeta o outro"*). Question: what do AWS and the community actually recommend
on KMS key segregation vs consolidation — does key separation deliver the isolation claimed, what
does it cost, and what does migration require per service? Report honestly even where it
contradicts the engineer's framing.

## Sources consulted

- `app-beta-001/ssm.tf:67-68`, `app-demo-001/ssm.tf:67-68`, `app-shared-001/ssm.tf:54-55`,
  `app-atento-001/ssm.tf:58-59` — confirmed myself: all four grant `kms:Decrypt` on the same key
- `modules/cross_region_backup/main.tf` — read in full; the in-house per-stack key precedent
- Live AWS state (read-only, this session): `kms list-aliases` (us-east-1), `kms describe-key` +
  `get-key-policy` + `get-key-rotation-status` for `4shark-ecs-beta-key` and `4shark-master`
- `~/Projects/4Shark/dot-claude-plans/active/terraform/kms-migration/PLAN.md` — read in full (56
  lines); the existing plan this spike's direction may supersede
- `~/Projects/4Shark/dot-claude-plans/active/spike/aws-engineer-staging-tier/SPIKE.md` — sibling
  spike, Finding 4 (the leak this investigation is triggered by)
- See auxiliary: `kms-key-per-environment_doc_1.txt` — AWS Well-Architected SEC08-BP02, the direct
  guidance on key-per-classification
- See auxiliary: `kms-key-per-environment_doc_2.txt` — AWS KMS key-policies.html, what actually
  gates key usage
- See auxiliary: `kms-key-per-environment_doc_3.txt` — SSM Parameter Store KMS encryption context,
  the per-parameter IAM condition mechanism
- See auxiliary: `kms-key-per-environment_doc_4.txt` — RDS rekey options, Secrets Manager rekey,
  SSM CLI rekey mechanics
- See auxiliary: `kms-key-per-environment_data_1_aliases_useast1.json` — live KMS alias listing
- See auxiliary: `kms-key-per-environment_data_2_key_details.json` — describe-key/policy/rotation
  for `4shark-ecs-beta-key` and `4shark-master`

## Findings

### Finding 1: The shared-key state is confirmed, and the key's own description says it is deliberate

**Evidence:** `app-beta-001/ssm.tf:68`, `app-demo-001/ssm.tf:68`, `app-shared-001/ssm.tf:55`,
`app-atento-001/ssm.tf:59` all grant `kms:Decrypt` on
`arn:aws:kms:us-east-1:405749097490:key/mrk-fa0cda243274491784fc7b39bead5a03` — one key across
all four app environments, productive included. `kms describe-key` on that key ID returns
`"Description": "4Shark master encryption key - all environments and services"`.

**Source:** the four `ssm.tf` files above; `kms-key-per-environment_data_2_key_details.json` →
`master_key_describe.KeyMetadata.Description`.

**Significance:** confirms the sibling spike's Finding 4 directly against live AWS state, not just
Terraform. The single-key design is not an oversight — the key's own description states the scope
as "all environments and services," meaning it was named and described with that intent.

### Finding 2: AWS's actual position is coarse segregation by classification, not per-environment

**Evidence:** *"Using the same encryption key for all data regardless of data usage, types, and
classification"* is listed as a named anti-pattern. The implementation step: *"create one AWS
KMS key for encrypting production data and a different key for encrypting development or test
data."*

**Source:** AWS Well-Architected Framework, SEC08-BP02 —
https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_protect_data_rest_encrypt.html
(`kms-key-per-environment_doc_1.txt`).

**Significance:** AWS does recommend moving off a single shared key — the engineer's instinct is
directionally backed. But the AWS-documented example is a **two-way** split (production vs
dev/test), not a six-way per-environment split. This directly surfaces the ambiguity in the
engineer's own phrasing (see Finding 9).

### Finding 3: AWS frames the isolation as "key + policy," not "key" alone

**Evidence:** *"Create and configure AWS KMS keys with policies that limit access to the
appropriate principals for each classification of data."* Separately: *"No AWS principal ...
has any permissions to a KMS key unless they are explicitly allowed ... in a key policy, IAM
policy, or grant."*

**Source:** SEC08-BP02 (`kms-key-per-environment_doc_1.txt`); AWS KMS key-policies.html
(`kms-key-per-environment_doc_2.txt`).

**Significance:** the recommendation is never "a separate key, by itself, isolates." It is "a
separate key WITH a policy scoped to the right principals." A new key with an unscoped or
overly-broad policy delivers nothing over the current state.

### Finding 4: For SSM SecureString specifically, the same isolation is achievable on the EXISTING shared key, via IAM condition on encryption context

**Evidence:** Parameter Store's encryption context is `PARAMETER_ARN`, and for a hierarchical
path it already includes the full path — 4Shark's own parameters already follow
`/beta-001/*`, `/demo-001/*`, etc. AWS documents: *"You can also include the encryption context
in an IAM policy. For example, you can permit a user to decrypt only one particular parameter
value or set of parameter values."* with a worked `kms:EncryptionContext:PARAMETER_ARN`
condition example.

**Source:** SSM Parameter Store KMS encryption doc
(`kms-key-per-environment_doc_3.txt`).

**Significance:** this is the rigorous answer to "where does the isolation actually come from."
For SSM, a correctly-scoped IAM policy condition on the CURRENT shared key would already prevent
an identity that leaked in `beta-001` from decrypting a `shared-001` parameter — no new key
required for that specific claim. This was NOT investigated for RDS/EBS in this spike (time-boxed;
see "What remains uncertain") — RDS/EBS also carry an encryption context in some AWS SDKs, but
whether it is similarly conditionable on the shared key was not verified here.

### Finding 5: 4Shark already has an in-house per-stack key precedent — regional, not multi-region

**Evidence:** `modules/cross_region_backup/main.tf:29-57` creates `aws_kms_key.local` (source
region) and `aws_kms_key.dr` (destination region, `provider = aws.destination`) — two ordinary
regional keys per invocation, aliased `backup-<identifier>-local` / `backup-<identifier>-dr`, NOT
one multi-region key. The key policy in that module grants only `kms:*` to the account root
(`local.kms_policy`), relying on IAM policies for the rest — matching AWS's decentralized model
(Finding 6).

**Source:** `modules/cross_region_backup/main.tf:14-57` (read in full).

**Significance:** 4Shark already runs one-key-per-stack in production, today, for backups —
confirmed live as 6 `backup-<stack>-local` aliases in us-east-1
(`kms-key-per-environment_data_1_aliases_useast1.json`): `app-atento-001`, `app-beta-001`,
`app-demo-001`, `app-shared-001`, `onboarding`, `setup`. `auth-001/backup.tf` also invokes the
module, but no `backup-auth-001-*` alias appears in the us-east-1 listing — `auth-001` likely
lives in a different region (per `/authenticators` skill docs), not verified in this spike. The
precedent also shows the estate does NOT need multi-region keys to satisfy cross-region backup —
it uses two regional keys instead.

### Finding 6: AWS's stated default is decentralized (per-account/per-workload) key ownership, absent an articulated reason for centralizing

**Evidence:** *"In general, we recommend that you start with a decentralized approach unless you
can articulate a need for a centralized KMS key model."* Also: *"When deploying workloads using a
multi-account strategy, you should keep AWS KMS keys in the same account as the workload that
uses them."*

**Source:** AWS Prescriptive Guidance, Key management best practices for AWS KMS —
https://docs.aws.amazon.com/prescriptive-guidance/latest/aws-kms-best-practices/key-management.html;
AWS Well-Architected SEC08-BP01 —
https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_protect_data_rest_key_mgmt.html.

**Significance:** 4Shark runs a single AWS account (not multi-account per environment), so this
guidance's literal multi-account framing does not map 1:1 — but the underlying rationale (local
administrators manage keys scoped to what they understand, least-broad blast radius by default)
still argues in the same direction as Finding 2: a single account-wide key for everything is the
consolidated extreme AWS explicitly frames as the exception to justify, not the default.

### Finding 7: RDS and EBS require snapshot + recreate to change key; Secrets Manager and S3 do not

**Evidence:** RDS — *"Amazon RDS doesn't currently support in-place conversion ... A downside is
that it requires a downtime period of at least 30 minutes, depending on the size of your
database."* EBS — cannot change the key of an existing volume/snapshot in place; a new,
non-incremental encrypted copy must be created under the new key (additional storage cost).
Secrets Manager — `UpdateSecret --kms-key-id` re-encrypts `AWSCURRENT`/`AWSPENDING`/`AWSPREVIOUS`
in place, no resource recreation. S3 — changing the bucket's default encryption key is instant
but does NOT retroactively re-encrypt existing objects; those need S3 Batch Operations or
`UpdateObjectEncryption` if migration is required.

**Source:** AWS Database Blog, RDS KMS key options; AWS Secrets Manager, change encryption key doc
(both in `kms-key-per-environment_doc_4.txt`); WebSearch summary corroborated for EBS (not
independently re-fetched — see uncertainty note below).

**Significance:** this directly confirms and extends the prior `PLAN.md`'s premise for RDS
(snapshot+copy+restore, maintenance window per instance) and shows the migration cost is
NOT uniform across services — RDS/EBS are the expensive ones; SSM, Secrets Manager, S3 are cheap
or free of downtime.

### Finding 8: SSM SecureString rekey is mechanically cheap but not an AWS-documented guarantee

**Evidence:** `put-parameter --overwrite --key-id <new>` re-triggers the standard SecureString
`Encrypt` workflow under the new key, same parameter name, no resource recreation. The AWS CLI
reference page documents `--overwrite` and `--key-id` individually but does NOT explicitly state
that this sequence is the supported way to change an existing parameter's key.

**Source:** `kms-key-per-environment_doc_4.txt` (put-parameter CLI reference, verbatim quotes +
the explicit "not stated" note).

**Significance:** flagged honestly per citation discipline — this is inferred from documented
mechanics, not an AWS-stated guarantee, unlike Finding 7's RDS/Secrets-Manager claims which ARE
explicit AWS statements.

### Finding 9: The engineer's own phrasing carries two different granularities

**Evidence:** the investigation brief itself notes the engineer said "uma chave pra produção e
outra pra staging" (2 keys: prod / non-prod) in one breath and "um por ambiente" (6+ keys: one per
`beta-001`/`demo-001`/`shared-001`/`atento-001`/`onboarding`/`setup`) in the next.

**Source:** engineer's own words, as relayed in the investigation brief.

**Significance:** these are not the same design. AWS's own worked example (Finding 2) matches the
2-key granularity, not the 6-key one. This is a real open scope question — not resolved here.

### Finding 10: Cost is not a discriminating factor between the options

**Evidence:** each KMS key costs $1/month flat (prorated hourly), *"the same for symmetric keys
... multi-Region keys (each primary and each replica multi-Region key)"* — so a multi-region key
bills per replica, not once. API requests: $0.03 per 10,000 symmetric requests beyond a 20,000/month
free tier, account-wide. Confirmed live customer-managed keys in us-east-1 today: `4shark-master`
(1 unit here; +1 more for its `sa-east-1` replica, not queried in this listing),
`4shark-ecs-beta-key`, `KMS-BackupAMIs-virginia`, and 6 `backup-<stack>-local` keys — 9 confirmed
in this region alone, ≈$9/month baseline before the `-dr` replicas in the destination region
(not queried).

**Source:** https://aws.amazon.com/kms/pricing/ (WebSearch synthesis, not independently
re-fetched — see uncertainty note); `kms-key-per-environment_data_1_aliases_useast1.json`.

**Significance:** a 2-key split adds ~$2/month (or ~$4 if each is multi-region like
`4shark-master`); a 6-key split adds ~$6/month (or ~$12 multi-region). Both are trivial against
current AWS spend. Cost does not decide between the options; it only rules out "cost" as a reason
to prefer one over the other.

### Finding 11: `alias/4shark-ecs-beta-key` is live, billed, and unreferenced by any Terraform or repo

**Evidence:** created 2025-10-17, `KeyRotationEnabled: false`, key policy is the bare console
default template (`"Id": "key-consolepolicy-3"`, only account-root + two IAM key-admin principals
— no service-principal statement, no resource-scoped grant). `grep -rn` for the alias name, and
for its raw key ID, across `~/Projects/4Shark/terraform/` and every other 4Shark repo: zero hits.
`app-beta-001`'s RDS, connection pooler, and SSM all reference `4shark-master` instead
(`app-beta-001/rds.tf:58,70,74`; `connection_pooler.tf:18,35,52`; `ssm.tf:68`).

**Source:** `kms-key-per-environment_data_2_key_details.json`; grep of the terraform repo and
`app-beta-001/*.tf`.

**Significance:** this key is not the answer to "off-standard" by design — it appears orphaned.
Not investigated: who created it or why (would require a CloudTrail dig into 2025-10-17, out of
this spike's scope). It has been billed for ~9 months unreferenced as of this spike.

### Finding 12: The existing `kms-migration/PLAN.md` conflicts with a per-environment direction on exactly one task

**Evidence:** Task 1 (import the CLI-created `4shark-master` into Terraform state) is independent
of the key-count decision — it is prerequisite housekeeping regardless of how many keys the
estate ends up with. Task 2 (*"Migrate old RDS instances to `4shark-master` KMS key"*, via
snapshot+copy+restore) is NOT independent — moving legacy RDS instances onto the single shared
key, only to move them again onto a new per-environment key shortly after, is duplicate
maintenance-window work in the wrong direction if segregation is adopted.

**Source:** `~/Projects/4Shark/dot-claude-plans/active/terraform/kms-migration/PLAN.md:25-56`
(read in full).

**Significance:** whether Task 2 proceeds as written, is deferred, or is redirected straight at
new per-environment keys is a scope decision this spike surfaces but does not make.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Keep single shared key + add `kms:EncryptionContext` IAM conditions | Zero new keys/cost; matches 4Shark's existing SSM path-prefix naming; fixes the exact SSM leak in the sibling spike | Documented only for SSM in this spike; RDS/EBS/Secrets Manager still share one key and one blast radius; every IAM policy touching this key must get the condition added and kept correct | Findings 3, 4 |
| Two keys: production vs non-productive | Matches AWS's literal worked example (Finding 2); smallest new-key footprint (~$2-4/mo); simplest to reason about and audit | Coarser than "per ambiente" as literally said elsewhere; a leak in `beta-001` still can decrypt `demo-001` (both non-productive, same key) | Finding 2 |
| One key per environment (6: beta-001, demo-001, shared-001, atento-001, onboarding, setup) | Matches 4Shark's own existing `backup-<stack>-*` precedent (Finding 5); matches "um por ambiente" literally; finest-grained blast-radius containment | ~$6-12/mo (still trivial); more keys to rotate/audit/monitor; RDS/EBS migration cost (Finding 7) applies once per environment migrated | Findings 2, 5, 10 |
| Any of the above, multi-region like `4shark-master` | Consistent with the one key that already exists | Not required by the estate's own precedent — `cross_region_backup` achieves cross-region DR with two regional keys, not one multi-region key (Finding 5); doubles the per-key cost | Finding 5 |

## What remains uncertain

- Whether SSM's `kms:EncryptionContext` conditioning strategy (Finding 4) has an equivalent for
  RDS, EBS, or Secrets Manager on a shared key — not investigated in this time-boxed spike.
- Who created `4shark-ecs-beta-key` and why (Finding 11) — would need a CloudTrail lookup for
  2025-10-17, not done here.
- Whether `auth-001`'s `cross_region_backup` invocation (Finding 5) is live in a different region
  or not yet applied — not verified.
- The exact AWS KMS pricing figures (Finding 10) and the EBS in-place-change claim (Finding 7)
  came back from WebSearch's synthesis rather than a directly re-fetched, verbatim-quoted AWS
  page in this session — treat as corroborated-by-search, not independently re-verified per the
  full citation-discipline self-check.
- Which granularity the engineer actually means — 2 keys (prod/non-prod) or 6 (one per
  environment) — Finding 9 surfaces the contradiction; it is not resolved here.
- What happens to `kms-migration/PLAN.md` Task 2 (Finding 12) — proceed, defer, or redirect.

## Suggested options for main and the engineer

- Option A: two keys, production vs non-productive — closest to AWS's literal documented example
  (Finding 2), cheapest, coarsest isolation
- Option B: one key per environment (6, matching the existing `backup-<stack>-*` precedent,
  Finding 5) — finest isolation, still cheap, most keys to manage
- Option C: keep the single shared key, add `kms:EncryptionContext:PARAMETER_ARN` IAM conditions
  scoped per environment path (Finding 4) — fixes the SSM leak with zero new keys; leaves
  RDS/EBS/Secrets Manager on the shared key unless separately addressed
- Option D: combine B (new keys for SSM/RDS/EBS/Secrets Manager, one per environment) with the
  already-built backup-key pattern (Finding 5) as the shared convention going forward
- Regardless of A/B/C/D: `kms-migration/PLAN.md` Task 1 (import `4shark-master`) stays needed;
  Task 2 (migrate legacy RDS onto `4shark-master`) needs an explicit engineer call given Finding 12
- Regardless of A/B/C/D: `4shark-ecs-beta-key` (Finding 11) is a separate cleanup decision — keep,
  investigate further, or schedule for deletion
