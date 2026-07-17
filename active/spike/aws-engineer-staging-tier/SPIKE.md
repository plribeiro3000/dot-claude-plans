# SPIKE — A Third AWS Permission Tier Scoped to Non-Productive Environments

## Investigation question

4Shark's AWS permission model has two tiers today (baseline, MFA-elevated), both gating on
`platform_engineers` (requires `email` + `given_name`). The engineer wants a third tier,
`engineer-staging`, for identities with far less access than baseline, scoped only to
non-productive environments — driven by a frontend engineer who needs to read exactly one SSM
parameter in the beta environment (a read-only MongoDB connection string) and holds no AWS
identity today. How should this be modelled, per AWS vendor guidance and observable community
practice? Options and trade-offs only — no recommendation.

## Sources consulted

- `~/Projects/4Shark/terraform/identity/engineers.tf:1-24` — `platform_engineers`/`atlas_engineers`/`console_engineers` locals; the Atlas-decoupling precedent
- `~/Projects/4Shark/terraform/identity/group_baseline.tf`, `policies_baseline.tf` — baseline (no-MFA) group and its policy statements
- `~/Projects/4Shark/terraform/identity/policy_engineer_terraform_*.tf`, `policy_engineer_write.tf` — MFA-elevated layer
- `~/Projects/4Shark/terraform/identity/sso.tf` — IAM Identity Center permission sets, identity-store users/groups, account assignments
- `~/Projects/4Shark/terraform/identity/guard.tf`, `terraform.tfvars` — break-glass guard; the `leandro` entry (no `given_name`)
- `~/.claude/docs/IDENTITY-STACK.md`, `identity/README.md`, `docs/adr/ADR-004-identity-model.md` — governing policy + engineer identity model
- `~/Projects/4Shark/terraform/app-beta-001/ssm.tf`, `mongodb.tf` — the concrete SSM/KMS shape for the beta environment
- `aws-engineer-staging-tier_diff_1.patch` — diff of **open PR #732** (`feature/beta-mongo-readonly-user`), which already adds a `beta-001/MONGO_READONLY_URL` SecureString parameter but no AWS IAM path to read it
- `aws-engineer-staging-tier_data_1.json` — `aws sts get-caller-identity` + `aws organizations describe-organization` output confirming this account is the Organization's **management account**
- `aws-engineer-staging-tier_doc_1.txt` through `_doc_5.txt` — fetched AWS docs (IAM identities, ABAC, SSM Parameter Store access, permissions boundaries, SCPs)
- https://www.trk7.com/blog/aws-ssm-parameter-store-iam-tag-support/ — practitioner report on SSM tag-condition limitations (non-AWS-official)

## Findings

### Finding 1: This account is the Organization's management account — SCPs cannot scope anything here

**Evidence:**
```
"MasterAccountId": "405749097490"   ← matches the account sts get-caller-identity resolves to
"FeatureSet": "ALL", "AvailablePolicyTypes":[{"Type":"SERVICE_CONTROL_POLICY","Status":"ENABLED"}]
```
AWS Organizations docs, verbatim: *"SCPs don't affect users or roles in the management account. They affect only the member accounts in your organization."* and *"You can't use SCPs to restrict the following tasks: Any action performed by the management account."*

**Source:** `aws-engineer-staging-tier_data_1.json`; https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html (`aws-engineer-staging-tier_doc_5.txt`)

**Significance:** SCPs are a candidate mechanism for environment scoping in general, but not for 4Shark's `identity/` stack or any `app-*` stack — all of it runs in the management account, and SCPs have zero effect there. Whatever mechanism is chosen must work at the identity/resource-policy layer, not the Organization-policy layer.

### Finding 2: Permission boundaries scope the ceiling, not the environment

**Evidence:** *"A permissions boundary is an advanced feature for using a managed policy to set the maximum permissions that an identity-based policy can grant to an IAM entity... it limits the user's permissions but does not provide permissions on its own."* And: *"The effective permissions are the intersection of both policy types."*

**Source:** https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html (`aws-engineer-staging-tier_doc_4.txt`)

**Significance:** A permission boundary does not itself express "beta only" — that scoping still has to come from the identity policy's own `Resource` ARNs (or tag conditions). A boundary's role here would be capping what a narrow-tier identity's policy is *allowed to ever grant*, as a second guardrail on top of a correctly-scoped identity policy — not a substitute for one. Unlike SCPs, boundaries are a pure IAM feature and DO apply in the management account (nothing in the fetched doc or the SCP doc restricts boundaries to member accounts).

### Finding 3: SSM path-prefix scoping is documented and matches 4Shark's existing parameter layout

**Evidence:**
```
"Resource": "arn:aws:ssm:{{us-east-1}}:{{111122223333}}:parameter/prod-*"
```
*"If a user has access to a path, then the user can access all levels of that path. For example, if a user has permission to access path /a, then the user can also access /a/b."*

**Source:** https://docs.aws.amazon.com/systems-manager/latest/userguide/sysman-paramstore-access.html (`aws-engineer-staging-tier_doc_3.txt`)

Codebase: `app-beta-001/ssm.tf:38` names every secret `/beta-001/${each.key}`; `app-demo-001/ssm.tf:38` uses `/demo-001/${each.key}` — every 4Shark app environment already uses this exact `/‹environment›/` prefix convention, so `arn:...:parameter/beta-001/*` is a direct fit for path-prefix scoping.

**Significance:** The path-prefix mechanism AWS documents lines up with 4Shark's existing naming scheme with no restructuring needed. The hierarchical-access caveat (`/a` access implies `/a/b` access) does not create a cross-environment leak here, since each environment already has its own top-level path segment (`/beta-001/`, `/demo-001/`, ...).

### Finding 4: KMS decrypt is NOT environment-scoped today — it is one shared key across all four app environments, productive included

**Evidence:**
```
app-demo-001/ssm.tf:68:   Resource = ["arn:aws:kms:us-east-1:405749097490:key/mrk-fa0cda243274491784fc7b39bead5a03"]
app-beta-001/ssm.tf:68:   Resource = ["arn:aws:kms:us-east-1:405749097490:key/mrk-fa0cda243274491784fc7b39bead5a03"]
```
The identical key ARN also appears in `app-shared-001/ssm.tf`, `app-atento-001/ssm.tf`, `setup/ssm.tf`, `onboarding/ssm.tf` (confirmed by `grep -rl` for that key ID across the repo) — `shared-001` and `atento-001` are the two **productive** environments.

AWS doc, verbatim: *"If you require fine-grained access control over the SecureString parameters in your account, you should use a customer managed key to protect and restrict access to these parameters."* — and separately, on the account's default key: *"The default AWS Key Management Service (AWS KMS) key has Decrypt permission for all IAM principals within the AWS account."*

**Source:** `~/Projects/4Shark/terraform/app-demo-001/ssm.tf:68`, `~/Projects/4Shark/terraform/app-beta-001/ssm.tf:68`; https://docs.aws.amazon.com/systems-manager/latest/userguide/sysman-paramstore-access.html (`aws-engineer-staging-tier_doc_3.txt`)

**Significance:** Scoping `ssm:GetParameter` to `/beta-001/*` bounds *which parameter names* an identity can ask SSM for, but the `kms:Decrypt` grant needed to read a `SecureString` value is written against a KMS key ARN shared by every environment, not a per-environment key. AWS's own guidance is that fine-grained SecureString access needs a customer-managed key *per access boundary* — the current single shared key is a structural mismatch with "beta only," independent of whatever IAM policy shape is chosen for the new tier. This is a fact about the current key architecture, not a flaw in any one candidate design.

### Finding 5: SSM tag-based (ABAC) conditions have a documented practitioner-reported gap, and 4Shark's SSM parameters carry no tags today

**Evidence:** A practitioner attempted the condition `"ssm:resourceTag/Application1": "One"` on `GetParameter`/`GetParametersByPath` and reported: *"I was expecting a policy like this"* [to work], then had to fall back to a `describe-parameters` + per-parameter `get-parameter` workaround, citing *"a known issue with AWS...prevents us from doing that"* for `get-parameters-by-path` tag filtering.

**Source:** https://www.trk7.com/blog/aws-ssm-parameter-store-iam-tag-support/ (fetched twice, consistent both times) — practitioner blog, not an AWS-official source.

Codebase: `grep -n "tags" app-beta-001/mongodb.tf app-beta-001/ssm.tf` returns nothing — neither `aws_ssm_parameter.secrets` nor `aws_ssm_parameter.mongo_url` (nor the not-yet-merged `mongo_readonly_url` in PR #732) declares a `tags` block.

**Significance:** Two independent obstacles to an ABAC/tag-based design for this specific case: (1) a credible but non-authoritative report that the relevant condition key doesn't reliably gate the exact actions needed, and (2) 4Shark's SSM parameters aren't tagged at all today, so ABAC here would require adding tagging as a prerequisite, not just an IAM policy change. AWS's own ABAC-vs-RBAC guidance frames ABAC as valuable when resource sets grow and change often (*"ABAC permissions scale with innovation"*) — the beta-only, single-parameter case in view here does not obviously have that shape.

### Finding 6: IAM Identity Center is AWS's stated best practice for human access; 4Shark's own baseline/elevated tiers currently use the discouraged path for programmatic access

**Evidence:** *"As a best practice, AWS recommends that you require human users to assume an IAM role to access AWS so that they're using temporary credentials. If you are managing identities in the IAM Identity Center directory or using federation with an identity provider you are following best practices."* And, on the alternative: *"IAM users and their access keys have long-term credentials to your AWS resources."* The programmatic-access table marks "Use long-term credentials to sign programmatic requests" for IAM users explicitly **"(Not recommended)."**

**Source:** https://docs.aws.amazon.com/IAM/latest/UserGuide/introduction_identity-management.html (`aws-engineer-staging-tier_doc_1.txt`)

Codebase: `identity/engineers.tf:26-35` creates `aws_iam_user.engineer` for every `platform_engineer`; `identity/README.md:198-209` documents that this IAM user is "Used for CLI and API access (access key + secret key)" with a TOTP MFA device — i.e., today's baseline/elevated tiers use long-lived IAM-user access keys for the exact programmatic use case (an `aws ssm get-parameter` call) the frontend engineer needs, which is the path AWS marks "Not recommended." `sso.tf` separately provisions an Identity Center identity per engineer, but per `README.md:192-196` that path is reserved for **console** login via Google SSO, not CLI.

**Significance:** 4Shark's existing two tiers already diverge from AWS's stated best practice for the *programmatic* half of access (IAM user + long-lived access key), while using Identity Center correctly for the *console* half. A third tier inherits this same fork: it could extend the existing IAM-user pattern (consistent with current tiers, inherits the long-lived-key trade-off) or route through Identity Center exclusively (matches AWS's stated best practice, but is a new pattern relative to what `platform_engineers` do today, and Identity Center's `aws sso login` flow is a different day-to-day experience than an access key in `~/.aws/credentials`).

### Finding 7: A read-only credential for beta already exists in an open, unmerged PR — the gap is the AWS IAM path to it, not the MongoDB credential itself

**Evidence:** PR #732 (`feature/beta-mongo-readonly-user`, OPEN as of 2026-07-16) adds:
```hcl
resource "aws_ssm_parameter" "mongo_readonly_url" {
  name  = "/beta-001/MONGO_READONLY_URL"
  type  = "SecureString"
  value = local.mongo_readonly_url
}
```
alongside a new MongoDB Atlas `readAnyDatabase` credential, with the CHANGELOG entry *"Read-only MongoDB credential for the beta environment."* `terraform.tfvars:32-38` shows `leandro` already has `atlas_teams = ["beta-readonly"]` (MongoDB Atlas side) but no `given_name` — so he is excluded from `platform_engineers` and has **no AWS identity of any kind today**, matching the investigation's premise exactly.

**Source:** `aws-engineer-staging-tier_diff_1.patch`; `~/Projects/4Shark/terraform/identity/terraform.tfvars:32-38`

**Significance:** This is not a hypothetical case to design against — it is a concrete, in-flight resource (`/beta-001/MONGO_READONLY_URL`) that the new tier would need to grant `ssm:GetParameter` (+ scoped `kms:Decrypt`) on. Any option chosen should be validated against this exact parameter name once PR #732 merges.

### Finding 8: The tier name "engineer-staging" does not match any name in the actual estate

**Evidence:** 4Shark's non-productive environments are named `beta-001` and `demo-001` (confirmed: `app-beta-001/`, `app-demo-001/` stack directories, `/beta-001/*` and `/demo-001/*` SSM prefixes); productive are `shared-001` and `atento-001`. None is named or aliased "staging" anywhere in the `app-*` stacks. The one place "staging" appears in the repo is `integrator-atento`'s harvester/ECR resources (`Environment = "staging"` tags, e.g. `integrator-atento/ssm_harvester_staging.tf:19`) — an unrelated, pre-existing use of that word for a different system (the Atento integrator/harvester, not the app environments). By contrast, 4Shark's own naming for exactly this kind of access already exists: MongoDB Atlas team `beta-readonly` (`terraform.tfvars:36`) and the CHANGELOG's own phrase, *"Read-only MongoDB team for the beta environment."*

**Source:** `~/Projects/4Shark/terraform/identity/terraform.tfvars:36-37`; `~/Projects/4Shark/terraform/integrator-atento/ssm_harvester_staging.tf:19`; CHANGELOG entry captured in `aws-engineer-staging-tier_diff_1.patch:9`

**Significance:** "Staging" is not an environment name anywhere in the app estate — it would be a fourth vocabulary alongside `beta-001`/`demo-001` (non-productive) and `shared-001`/`atento-001` (productive), and it already denotes something else (an Atento harvester environment) elsewhere in the same repo. The codebase's own precedent for this exact access shape names it by environment (`beta-readonly`), not by a generic "staging" label.

### Finding 9: AWS does not publish a named reference pattern for a "read-only-in-non-productive" persona

**Evidence:** The IAM "Different methods to provide user access" table documents *how* to grant access (Identity Center SSO, federation, IAM users) but does not name or describe a persona/pattern for "narrow read access limited to non-production resources." The AWS docs fetched for this spike (`aws-engineer-staging-tier_doc_1.txt` through `_doc_5.txt`) describe general mechanisms (path-prefix ARNs, ABAC tags, permission boundaries, SCPs) with no worked example combining them into a "staging-only read-only engineer" reference architecture.

**Source:** Absence across all five fetched AWS docs (`aws-engineer-staging-tier_doc_1.txt`–`_doc_5.txt`).

**Significance:** Not found: an AWS-published or vendor-endorsed named pattern for this exact persona. The mechanisms exist individually (path-prefix ARN, ABAC, permission boundary) but combining them for "third tier, non-productive only" is a 4Shark-specific composition, not something to point at a single AWS reference for.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Extend `platform_engineers` pattern: new IAM group/policy, ARN-scoped to `/beta-001/*` + `/demo-001/*`, attached to a new IAM user (mirrors `engineers.tf`) | Reuses the existing code shape (`aws_iam_user`, group, policy attachment); path-prefix ARN scoping is AWS-documented and matches existing `/‹env›/` naming (Finding 3) | Long-lived IAM user access key — the path AWS marks "Not recommended" for programmatic access (Finding 6); still needs the KMS-decrypt scoping question resolved (Finding 4) since the key is shared across ALL environments including productive | Findings 3, 4, 6 |
| New IAM Identity Center permission set (custom policy, same ARN-scoping), assigned only to this engineer | Matches AWS's stated best practice for human access — temporary credentials via `aws sso login` (Finding 6); centralizes with the existing `sso.tf` machinery (admin/engineer permission sets already exist) | Different day-to-day flow than today's `platform_engineers` (who use IAM-user keys for CLI per `README.md:198-209`); still inherits the shared-KMS-key gap (Finding 4) | Findings 4, 6 |
| ABAC: tag environments/resources, condition IAM policies on `aws:ResourceTag`/`ssm:ResourceTag` | AWS's stated model for a growing/changing resource set (Finding 5); fewer policies to maintain long-term | 4Shark's SSM parameters carry no tags today — tagging work is a prerequisite, not just a policy change; a practitioner reports the specific `ssm:ResourceTag` condition on `GetParameter`/`GetParametersByPath` did not work as expected (Finding 5, non-authoritative) | Finding 5 |
| Permission boundary as an added guardrail on any of the above | Pure IAM feature, works in the management account unlike SCPs (Finding 1, 2); caps what the new tier's policy could ever be widened to | Does not itself express "beta only" — the boundary constrains a ceiling, it does not replace the ARN/tag scoping that does the actual environment-limiting (Finding 2) | Findings 1, 2 |
| SCP-based environment isolation | N/A | Not viable at all — this account is the Organization's management account, and SCPs explicitly do not apply there (Finding 1) | Finding 1 |

## What remains uncertain

- Whether `ssm:ResourceTag`/`aws:ResourceTag` conditions work reliably against `GetParameter` in current AWS behavior — the only evidence found is a non-AWS-official practitioner report of a failure (Finding 5); no AWS-official confirmation or denial was found either way.
- Whether a per-environment (or per-non-productive-group) customer-managed KMS key is something the engineer wants to introduce as part of this change, given the current shared-key architecture spans all four app environments (Finding 4) — this is a design question, not something this spike answers.
- The exact final name and shape of `/beta-001/MONGO_READONLY_URL` is still subject to PR #732 merging as currently drafted; if that PR's shape changes, the concrete resource ARN to scope against would change too.
- Whether "non-productive" for this tier means {beta-001, demo-001} only, or should also reach the `integrator-atento` `staging`-tagged resources (a different, pre-existing use of "staging" in the repo, Finding 8) — not investigated, since the engineer's driver is specifically the beta app environment.

## Suggested options for main and the engineer

- Option A: New IAM user + IAM group (mirrors `platform_engineers`/`engineers.tf` shape today), policy scoped to `arn:...:parameter/beta-001/*` (+ `demo-001/*` if both non-productive environments are in scope) plus `kms:Decrypt` on the shared key (accepting Finding 4's cross-environment KMS exposure as-is, or introducing a narrower key as a separate decision)
- Option B: New IAM Identity Center permission set with the same ARN-scoped custom policy, assigned only to this engineer — no new `aws_iam_user`, no long-lived access key, consistent with AWS's stated best practice (Finding 6)
- Option C: ABAC — tag `/beta-001/*` (and other non-productive) SSM parameters with an `Environment` (or similar) tag, write a tag-conditioned policy — contingent on resolving the uncertainty in Finding 5 first
- Option D: Any of A/B/C combined with a permission boundary as an added ceiling (Finding 2), independent of which scoping mechanism is chosen
- Naming: keep `beta-001`/`demo-001` (or a name like `engineer-non-productive`) rather than `engineer-staging`, given Finding 8 — or engineer confirms "staging" is intentional as a new, generic vocabulary term distinct from the Atento integrator's unrelated use of the word
