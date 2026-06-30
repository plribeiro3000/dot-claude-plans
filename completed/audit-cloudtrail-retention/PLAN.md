# PLAN — CloudTrail import into Terraform + retain-forever + docs

**Status**: Draft — awaiting engineer confirmation on the two open decisions below
**Date**: 2026-05-31
**Type**: Cross-repo (terraform + dot-claude), production audit infrastructure
**Workflow**: Standard (PLAN.md)

---

## Goal

Bring the existing (pre-IaC) account CloudTrail under Terraform, change its S3 retention
from "expire after 3 years" to "keep forever (with Glacier tiering)", and document for the
team how/where to search account events. Two PRs.

---

## Settled decisions

| Topic | Decision |
|---|---|
| Stack | New `audit/` stack (AWS Control Tower default name for the governance account) |
| Apply gating | Same as `identity/` — `.envrc` `export AWS_PROFILE=ivo` + `guard.tf` postcondition on the break-glass `user_id`. Apply runs under break-glass, by the engineer — **not Claude** |
| Retention | Forever in **S3 Standard, no storage-class transition** (Glacier dropped — see note). No expiration of current or noncurrent versions |
| Region | `sa-east-1` (where the trail home, bucket, and KMS key live) |
| ADR | New `ADR-008` in the terraform repo, same PR as the import (explains 3y → forever) |
| Docs | dot-claude: new Tier 2 doc on searching account events (Athena, not `lookup-events`) + Tier 1 pointer entry in CLAUDE.md. Separate PR |

---

## Current-state facts (read-only discovery, 2026-05-31)

| Attribute | Value |
|---|---|
| Trail | `main` · multi-region · home `sa-east-1` · logging since 2022-04-18 · `IsOrganizationTrail: false` |
| Event selectors | Advanced — Management events only |
| Log file validation | Enabled |
| Bucket | `4shark-cloudtrail` · `sa-east-1` · ~12.3 GB · ~2.46M objects |
| Versioning | Enabled (MFADelete Disabled) |
| Encryption | SSE-KMS, customer-managed CMK `64eb0fa9-7e7a-419c-97bc-8817d99b1b4d` (created by CloudTrail in 2022, dedicated to the trail) |
| Current lifecycle | `Expire after 36 months` (1095d) + NoncurrentVersionExpiration 1095d + AbortIncompleteMultipartUpload 1095d |
| Ingestion | ~1.3 GB/month (us-east-1 ~1.1 GiB + sa-east-1 ~143 MiB + minor others) |
| Already deleted | 2022 + early 2023 (expired by the 1095d rule). Survives jun/2023 onward |

---

## Pattern findings (Pattern Priming — read `identity/` + `modules/s3_bucket`)

- **`guard.tf`**: `data "aws_caller_identity" "guard"` + `lifecycle.postcondition` on `self.user_id == "AIDAV46EH4QJBIBQ7ATEM"`. Copy verbatim into `audit/`.
- **`providers.tf`**: `terraform` block, `required_providers` aws `6.46.0` pinned, `backend "s3"` key `<stack>/terraform.tfstate`. For `audit/`: provider region `sa-east-1`, backend key `audit/terraform.tfstate`.
- **`stack.tm.hcl`**: carries a real UUID `id` → must be generated via `terramate create`, never hand-written.
- **`modules/s3_bucket`**: generic (AES256, no KMS, no bucket policy, **no lifecycle**). Does NOT fit a CloudTrail bucket → write **explicit resources** in the `audit/` stack, not the module.

---

## RESOLVED DECISIONS

### D1 — KMS key → **Import & manage**
`aws_kms_key` + `aws_kms_alias` imported into the `audit/` state for full IaC control
(rotation, key policy). **Execution risk to control**: capture the live key policy EXACTLY
on import — a wrong policy on apply can lock CloudTrail out of its own key. Capture verbatim
JSON at execution and diff before apply.

### D2 — Retention shape → **Forever in S3 Standard, no transition**
Both current and noncurrent versions stay in S3 Standard with **no expiration and no
storage-class transition**. Lifecycle keeps only `AbortIncompleteMultipartUpload` (hygiene).
Versioning is Enabled — noncurrent versions (only created by tamper/manual overwrite, since
CloudTrail writes unique keys) are also kept forever, which audit integrity wants.

### D3 — Policy expression style → **Hybrid**
Bucket policy via `data "aws_iam_policy_document"` (simple, 2 statements, matches the local
`shared-resources/mongo-cwagent.tf` convention). KMS key policy as **literal JSON verbatim**
(CloudTrail-generated, carries a legacy bare-principal-ID `AIDAIBZMFXLNMOFR6ADPQ`; copying
exactly avoids transcription error and KMS key-policy lockout risk on import).

### NOTE — why Glacier was dropped (was earlier proposed, then reversed)
An earlier draft proposed transitioning old logs to Glacier Instant Retrieval for cost. That
is **wrong for CloudTrail's object profile** and was removed:
- CloudTrail log files are tiny (~16–24 KB; all < 128 KB). Per AWS, objects < 128 KB **do not
  transition by default** (since Sep 2024) — the rule would be a no-op.
- Forcing the transition costs **more**: one transition request per object (~2.46M requests)
  + 40 KB overhead per object for Glacier Flexible/Deep (8 KB Standard + 32 KB Glacier), which
  triples billed bytes for a ~20 KB object; Glacier IR bills a 128 KB minimum per object.
- The data is only ~12 GB (~1.3 GB/month) — Standard cost is ~$0.50/month now, ~$7/month in
  10 years. The Glacier optimization saves nothing here and adds retrieval friction.
- Real cost archival, if ever needed, requires **aggregating** small logs into large objects
  (CloudTrail Lake or a compaction job) — out of scope.
- Source: AWS — "Transitioning objects using S3 Lifecycle" (`lifecycle-transition-general-considerations`):
  *"We don't recommend transitioning objects less than 128 KB because you are charged a
  transition request for each object… the transition costs can outweigh the storage savings."*

---

## Execution — PR 1 (terraform repo): `feature/audit-stack-cloudtrail-import`

> Apply-before-merge, `import {}` blocks (declarative, plan-reviewable), apply via `AWS_PROFILE=ivo` run by the engineer. Import = treated as apply (PR open first).

1. `terramate create audit --name audit --description "Account audit & governance (CloudTrail, future Config/GuardDuty/Security Hub)"` — generates `stack.tm.hcl` with a real UUID.
2. `audit/providers.tf` — aws provider region `sa-east-1`, aws `6.46.0`, backend key `audit/terraform.tfstate`.
3. `audit/.envrc` — `source_up` + `export AWS_PROFILE=ivo` (copy identity/).
4. `audit/guard.tf` — copy identity/ guard verbatim.
5. `audit/cloudtrail.tf` — explicit resources matching current state:
   - `aws_cloudtrail.main` (multi-region, management events, log file validation, KMS key, S3 bucket)
   - `aws_s3_bucket.cloudtrail` (+ `prevent_destroy`)
   - `aws_s3_bucket_versioning` (Enabled)
   - `aws_s3_bucket_server_side_encryption_configuration` (SSE-KMS, existing key)
   - `aws_s3_bucket_public_access_block`
   - `aws_s3_bucket_policy` (CloudTrail service principal — capture exact current policy)
   - `aws_s3_bucket_lifecycle_configuration` — **the change**: drop `Expiration` + `NoncurrentVersionExpiration` (retain forever); **no storage-class transition** (see Glacier note); keep `AbortIncompleteMultipartUpload` (hygiene)
   - KMS per D1
6. `import {}` blocks for every existing resource (trail, bucket, versioning, sse, pab, policy[, kms]).
7. `ADR-008-cloudtrail-retention.md` in `docs/adr/` — why 3y → forever (AWS default is indefinite; compliance defines minimums; tiering for cost), why `audit/` stack, why ivo-gated.
8. Open PR → `terraform plan` (read-only, default profile may fail on guard if not ivo — note) → engineer applies with `AWS_PROFILE=ivo` → verify lifecycle changed + import clean → merge.
9. CHANGELOG entry (terraform repo).

## Execution — PR 2 (dot-claude repo): `feature/account-events-search-doc`

1. New Tier 2 doc `docs/SEARCHING-ACCOUNT-EVENTS.md` — CloudTrail console Event History = 90d only; `lookup-events` API = 90d only; the S3 trail bucket holds the full history; how to retrieve events >90d by date prefix from S3 (Athena noted as **not configured**, no how-to); retention is **forever in S3 Standard** (no Glacier).
2. CLAUDE.md — Tier 1 pointer entry referencing the new doc.
3. `scripts/read-context.sh` — register the doc in the Tier 2 list (so it surfaces).
4. CHANGELOG entry (dot-claude). Per Configuration Changes Policy: edit in the dot-claude working copy, PR, never `~/.claude/` directly.

---

## Risks / notes

- **Apply is break-glass** — Claude prepares code + plan + import blocks; the engineer runs `plan`/`apply` under `AWS_PROFILE=ivo`. Claude cannot apply this stack.
- **`prevent_destroy`** on the bucket guards against accidental deletion via Terraform.
- **Import accuracy** — bucket policy + KMS (if D1=import) must mirror live exactly or apply will show spurious diffs / risk lockout. Capture exact JSON at execution.
- **No object migration** — import touches state only; the 2.46M objects are untouched. No new bucket created.
- **2022/early-2023 data is already gone** — this change protects from jun/2023 forward.

---

## Status

**Complete.** Both PRs merged and the import applied:
- terraform `#460` — CloudTrail imported into the `audit/` stack + retain-forever lifecycle + ADR-008 (merged, applied via `ivo`).
- terraform `#461` — follow-up cleanup: `object_lock_enabled = true` declared + one-shot `imports.tf` removed (merged, plan was a no-op).
- dot-claude `#210` — Tier 2 `SEARCHING-ACCOUNT-EVENTS.md` + Tier 1 CLAUDE.md section + read-context.sh pointer (merged; `~/.claude` pulled).

## Out of scope — decided against (engineer decision, 2026-05-31)

Two follow-ups surfaced during the work and were **explicitly declined** — not deferred. Do not
re-open them as pending tasks:

- **S3 Object Lock / WORM activation.** The bucket already has `object_lock_enabled = true` but no
  retention rule. Activating WORM (a default retention) was considered and **will not be done**.
  No current compliance mandate requires it; Compliance mode is irreversible and not worth the
  commitment for defense-in-depth alone. The break-glass gate + `prevent_destroy` are the
  accepted protection level.
- **Athena (scale querying over the logs).** Not being set up. For >90-day lookups the S3-by-date
  path documented in `SEARCHING-ACCOUNT-EVENTS.md` is sufficient; standing up Athena is not
  justified by current need.

---

## Sources

- AWS — Security best practices in CloudTrail (store indefinitely by default; lifecycle to Glacier; dedicated bucket; MFA-delete × lifecycle incompatibility)
- AWS Control Tower — shared accounts (`Audit` / `Log archive` naming)
- AWS Prescriptive Guidance — Security Tooling account (what a security/audit stack holds)
- Repo: `terraform/identity/{guard,providers,.envrc}.tf`, `terraform/modules/s3_bucket`, `terraform/docs/adr/ADR-007`, `dot-claude/docs/TERRAFORM-CONVENTIONS.md`
