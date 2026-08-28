# SPIKE — AWS Identity, Credential, and Profile Model Redesign

## Investigation question

4Shark's current AWS identity/credential/profile naming grew operationally — `ivo`, `ivo-elevated`, `4shark-mfa`, `4shark-elevated`, `default`, `AWS_MFA_SERIAL`, `AWS_BREAK_GLASS_MFA_SERIAL` — and a rename-only pass on these strings was stopped mid-flight by the engineer with the instruction to stop being operational and rethink the model from first principles instead: which identities, profiles, and env-vars this system should actually *have* (not just how they are spelled), each grounded in 4Shark's own naming grammar (`THIRD-PARTY-KEY-STANDARD.md`, `CODE-STYLE-RULES.md`) and in current AWS community practice, with the constraint that the literal IAM account identifier (`ivo@4shark.com.br`) is not renamed — only the role/profile/variable layer around it is open to redesign.

The five strategic questions this spike answers (verbatim from the brief):

1. Is the current profile set the right shape at all — does every profile that exists need to, and is anything missing?
2. What does the AWS community recommend for this exact shape (low-privilege baseline → MFA-elevated session, plus a separate high-privilege break-glass identity)?
3. Is there an established community convention for *naming* AWS CLI profiles?
4. How does the redesign reconcile `ivo`'s two roles — AWS policy-arbiter vs. cross-service (GCP/MongoDB Atlas) break-glass owner?
5. Do the two MFA-serial env-vars (`AWS_MFA_SERIAL`, `AWS_BREAK_GLASS_MFA_SERIAL`) survive the redesign under 4Shark's naming grammar?

## Sources consulted

**4Shark code and docs (ground truth for the current model):**

- `~/Projects/4Shark/terraform/identity/README.md` — the model's own documentation (identity model, engineer identity, workflow, platforms managed)
- `~/Projects/4Shark/terraform/docs/adr/ADR-004-identity-model.md` — original decision record
- `~/Projects/4Shark/terraform/docs/adr/ADR-013-break-glass-usage-model.md` — the most recent, most precise statement of the break-glass identity's intended scope
- `~/Projects/4Shark/terraform/identity/break_glass.tf`, `guard.tf`, `.envrc`, `policy_break_glass.tf`, `policy_break_glass_portal.tf` — the actual IAM resources
- `~/Projects/4Shark/terraform/audit/.envrc`, `~/Projects/4Shark/terraform/analytics-access/main.tf`, `~/Projects/4Shark/terraform/workspace-access/main.tf`, `~/Projects/4Shark/terraform/workspace-access/README.md`, `~/Projects/4Shark/terraform/shared-resources/README.md` — where `ivo` appears outside the `identity/` stack
- `~/Projects/4Shark/terraform/CHANGELOG.md` — history of the `4shark-elevated` profile
- `~/.claude/docs/AWS-MFA.md`, `~/.claude/docs/runbooks/engineer-access/AWS-ENGINEER-SETUP.md`, `~/.claude/docs/IDENTITY-STACK.md` — dot-claude's own documentation of the model
- `~/.claude/skills/elevate-aws-access/scripts/elevate-aws-access.sh`, `~/.claude/skills/elevate-break-glass-access/scripts/elevate-break-glass-access.sh` — the two elevation mechanisms, as code
- `~/.claude/docs/THIRD-PARTY-KEY-STANDARD.md` — 4Shark's own credential-naming grammar and ownership rule
- `~/.claude/docs/CODE-STYLE-RULES.md` § Variable Naming — the no-abbreviation / accurate-description rule

**External (AWS documentation, fetched and verified):**

- AWS Well-Architected SEC03-BP03 — Establish emergency access process
- AWS Well-Architected SEC02-BP02 — Use temporary credentials
- AWS STS `GetSessionToken` API reference
- AWS IAM Guide — Secure API access with MFA (choosing between `GetSessionToken` and `AssumeRole`)

**External (WebSearch summaries only — not independently fetched; used only to support the "no single naming convention" conclusion, never to sustain a specific technical claim):** aws-vault issue tracker, Granted/Common Fate docs, various AWS CLI profile-naming blog posts.

## Findings

### Q1 — Is the current profile set the right shape?

#### Finding 1: `4shark-elevated` is very likely dead documentation, not a live parallel mechanism

**Evidence:**

`~/.claude/docs/AWS-MFA.md:15-24` currently describes it as a live, parallel profile:

```
This is separate from the native AWS CLI elevated profile (`4shark-elevated`) documented in the AWS Engineer Setup runbook
(`~/.claude/docs/runbooks/engineer-access/AWS-ENGINEER-SETUP.md`). Both use MFA, but:

| Aspect | `4shark-elevated` (CLI native) | `4shark-mfa` (Claude Code) |
|--------|-------------------------------|---------------------------|
| Profile | `~/.aws/config` role chaining | `~/.aws/credentials` direct keys |
```

But the runbook it points to, `~/.claude/docs/runbooks/engineer-access/AWS-ENGINEER-SETUP.md:10-35`, never defines `4shark-elevated` at all. It describes a *different, two-profile* model (`4shark` / `4shark-mfa`) elevated by a script at `~/.claude/scripts/aws-elevate.sh` — a path that does not exist in the current repository layout (the real script is `~/.claude/skills/elevate-aws-access/scripts/elevate-aws-access.sh`, per `~/.claude/docs/AWS-MFA.md:246`). The runbook is self-consistent internally but is not the document AWS-MFA.md claims it is.

`~/Projects/4Shark/terraform/CHANGELOG.md:365` records `4shark-elevated`'s origin: *"Engineers can now assume the elevated role with a single `AWS_PROFILE=4shark-elevated` flag — MFA prompt and credential caching are handled automatically by AWS CLI, replacing the previous manual credential export workflow."* Seven lines later, the same CHANGELOG section (`CHANGELOG.md:372`) records the model changing again: *"MFA-gated write access for engineers via GetSessionToken (no role assumption required)"* — this is a description of the current `4shark-mfa` mechanism, and "no role assumption required" is a direct statement that the *role-chaining* mechanism `4shark-elevated` used was replaced.

**Significance:** three independent pieces of evidence (a stale runbook that documents something else and references a non-existent script path, a CHANGELOG entry recording the role-chaining model's replacement, and no live reference to `4shark-elevated` anywhere in the terraform repository outside that one CHANGELOG line) converge on the same conclusion: `4shark-elevated` is very likely a documentation artifact from a superseded design, not a currently-needed second profile. This spike could not verify against the actual `~/.aws/config` on the engineer's machine (local, non-versioned state, out of scope for a codebase read) — see Open Questions.

#### Finding 2: `AWS_BREAK_GLASS_MFA_SERIAL` is a shared constant currently modeled as per-engineer data, asymmetrically with its own sibling constant in the same script

**Evidence:**

`~/.claude/skills/elevate-break-glass-access/scripts/elevate-break-glass-access.sh:34-37` hardcodes the 1Password secret reference directly in the script:

```
# The field is named rather than left to `--otp`, which returns whichever one-time-password
# field it finds first, and the item is addressed by ID because a secret reference rejects
# the brackets in its title.
OP_SECRET_REFERENCE="op://Employee/53yllsd37op6bjmf57ie2y4faq/one-time password?attribute=totp"
```

But the MFA device *serial* for that same, single, shared break-glass identity is read from each engineer's own `~/.claude/settings.local.json`, per `elevate-break-glass-access.sh:78-86`:

```
if [ -z "${AWS_BREAK_GLASS_MFA_SERIAL:-}" ]; then
  AWS_BREAK_GLASS_MFA_SERIAL=$(jq -r '.env.AWS_BREAK_GLASS_MFA_SERIAL // empty' ~/.claude/settings.local.json 2>/dev/null)
fi

if [ -z "${AWS_BREAK_GLASS_MFA_SERIAL:-}" ]; then
  echo "Error: AWS_BREAK_GLASS_MFA_SERIAL is not set." >&2
  echo "Persist it in ~/.claude/settings.local.json under \"env\"." >&2
  exit 1
fi
```

There is exactly one break-glass identity (`identity/README.md:24-30`: *"A dedicated owner account — not tied to any individual engineer — holds administrative privileges across all platforms"*), so its MFA device ARN is the same value for every engineer, not a personal fact. `~/.claude/CLAUDE.md`'s own § AWS Policy states the intended, opposite shape for this exact class of value: *"An ENGINEER's item is the opposite: per-person, so it is configured as `AWS_MFA_ITEM` in the engineer's own `settings.local.json`, never in the shared `settings.json`"* — that sentence exists specifically to say the break-glass item is NOT per-engineer, while the current `AWS_BREAK_GLASS_MFA_SERIAL` plumbing treats it exactly like a per-engineer fact.

**Significance:** within the same script, one fact about the single shared break-glass identity (the 1Password reference) is pinned in code, and a second fact about the *same* identity (the MFA serial) is left to per-engineer local configuration. The MFA serial ARN is not secret material — it identifies a device, not a credential value — so there is no confidentiality reason for the asymmetry. This is a direct answer to "does this variable need to exist": as a personal, per-engineer env-var, no.

#### Finding 3: the engineer/break-glass split into two profiles per identity is forced by `GetSessionToken`'s own API contract, not a design choice 4Shark could collapse

**Evidence:**

`~/.claude/skills/elevate-break-glass-access/scripts/elevate-break-glass-access.sh:17-21`:

```
# Two profiles, mirroring the engineer pair (default -> 4shark-mfa): `ivo` holds the
# long-term key and is permitted almost nothing, `ivo-elevated` receives the 15-minute
# session that carries the real access. They cannot be one profile — writing the session
# over the key that mints it would destroy the only credential able to call
# GetSessionToken, which AWS requires to be a long-term one.
```

The AWS STS `GetSessionToken` API reference (fetched, https://docs.aws.amazon.com/STS/latest/APIReference/API_GetSessionToken.html) confirms the constraint independently of 4Shark's own comment: *"The `GetSessionToken` operation must be called by using the long-term AWS security credentials of an IAM user."*

**Significance:** the two-profile-per-identity shape (a long-term-key profile that can do almost nothing except mint a session, and a short-lived MFA-session profile that carries the real access) is not an arbitrary 4Shark convention — it is the only shape `GetSessionToken` supports, for both the engineer identity and the break-glass identity. A redesign that tried to collapse `default`+`4shark-mfa` into one profile, or `ivo`+`ivo-elevated` into one profile, would not be a naming simplification; it would require abandoning `GetSessionToken` for a different STS API (see Finding 8).

#### Finding 4: no missing profile/variable was found for an account or environment axis — today's model has exactly one AWS account, and its Organization membership is itself unconfirmed

**Evidence:**

`~/Projects/4Shark/terraform/docs/adr/ADR-013-break-glass-usage-model.md:51-53`: *"Whether this account belongs to an organization is unconfirmed: `organizations:DescribeOrganization` is denied to the engineer profile."*

**Significance:** a profile-naming scheme that reserved a segment for "which AWS account" (as `aws-vault`/`Granted` conventions do, see Finding 9) would be premature — 4Shark's model has one account, and there is no confirmed evidence of a second one to distinguish from. This is listed under Open Questions below rather than folded into the redesign, because "no evidence found" is not the same as "confirmed absent."

### Q2 — What does the AWS community recommend for this shape?

#### Finding 5: AWS's own emergency-access guidance (SEC03-BP03) names the exact anti-pattern ADR-013 already engaged with, and adds one operational recommendation 4Shark's model does not currently implement

**Evidence:**

AWS Well-Architected SEC03-BP03 (fetched, https://docs.aws.amazon.com/wellarchitected/latest/framework/sec_permissions_emergency_process.html), under "Common anti-patterns": *"Your emergency access processes are used in non-emergency situations. For example, your users frequently misuse emergency access processes as they find it easier to make changes directly than submit changes through a pipeline."* This is the exact sentence ADR-013 quotes and engages with directly (`ADR-013:19-21`).

The same page, under "Implementation guidance," states a step 4Shark's model does not currently perform: *"Upon returning to normal operations, automatically rotate the emergency access credentials, and notify the relevant teams."*

**Significance:** ADR-013 already made a considered decision *not* to follow SEC03-BP03's stricter posture (a dedicated emergency AWS account, near-zero use, detective alerting) because 4Shark's actual trigger is "a missing engineer permission," not an outage, and the reactive-grant model converges the permission set over time (`ADR-013:32-37`). This spike found nothing that reopens that decision. What is new here is the credential-rotation recommendation specifically: `ivo`'s long-term access key and MFA device are explicitly kept out of Terraform (`break_glass.tf:6-10`: *"its long-term access key and its MFA device, because both would land in state and because Terraform managing them means an apply can destroy the credential that runs the apply"*), so "automatic" rotation is not mechanically available the way it is for a Terraform-managed key — this is a genuine gap between the SEC03-BP03 recommendation and 4Shark's design, inherited from the same constraint that keeps `ivo`'s credentials outside Terraform in the first place.

#### Finding 6: AWS's temporary-credentials guidance (SEC02-BP02) lists the exact shape of 4Shark's engineer profile as an anti-pattern, and 4Shark's own docs already state the reason it is not followed

**Evidence:**

AWS Well-Architected SEC02-BP02 (fetched, https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_identities_unique.html), under "Common anti-patterns": *"Developers using long-term access keys from IAM users rather than obtaining temporary credentials from the CLI using federation."* And in the implementation guidance: *"Avoiding the use of long-term credentials in favor of temporary credentials should go hand in hand with a strategy of reducing the usage of IAM users in favor of federation and IAM roles. While IAM users have been used for both human and machine identities in the past, we now recommend not using them to avoid the risks in using long-term access keys."*

4Shark's own `identity/README.md:214-225` already documents the deliberate split this collides with: *"AWS IAM user (programmatic access) — Used for CLI and API access (access key + secret key). This user is independent of SSO and requires a TOTP MFA device registered in the AWS console for write operations."* — separate from the SSO-federated Identity Center user used for console login (`identity/README.md:208-212`).

**Significance:** 4Shark's engineer CLI identity (`default` / `4shark-mfa`, and the break-glass `ivo` / `ivo-elevated`) is precisely the pattern AWS's own guidance recommends against for human access. This is a genuine fork rather than a settled question — see the Trade-offs table (Fork 4).

#### Finding 7: `GetSessionToken` is the AWS-documented, correct choice for exactly the access-control shape 4Shark built — not a legacy accident

**Evidence:**

AWS IAM Guide "Secure API access with MFA" (fetched, https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_mfa_configure-api-require.html), § "Choosing between GetSessionToken and AssumeRole":

*"Use `GetSessionToken` for the following scenarios: Call API operations that access resources in the same AWS account as the IAM user who makes the request. Note that temporary credentials from a `GetSessionToken` request can access IAM and AWS STS API operations only if you include MFA information in the request for credentials. Because temporary credentials returned by `GetSessionToken` include MFA information, you can check for MFA in individual API operations made by the credentials."*

*"Use `AssumeRole` for the following scenarios: ... The temporary credentials returned by `AssumeRole` do not include MFA information in the context, so you cannot check individual API operations for MFA. This is why you must use `GetSessionToken` to restrict access to resources protected by resource-based policies."*

This matches how 4Shark actually uses the MFA claim: `identity/README.md:20`: *"Write operations on AWS require MFA — the `EngineerWriteAccess` policy checks `aws:MultiFactorAuthPresent` on every sensitive action"*, and every statement in `identity/policy_break_glass.tf:38-42, 62-67, 96-99, 111-114, 138-142, 159-163, 188-192, 201-205` carries the same `Condition: { Bool: { "aws:MultiFactorAuthPresent": "true" } }` shape.

**Significance:** the choice of `GetSessionToken` over `AssumeRole` is not an implementation detail to reconsider — it is the AWS-documented correct API for an identity-policy `aws:MultiFactorAuthPresent` condition checked against operations in the *same* account, which is exactly 4Shark's shape (single account, per Finding 4). Any redesign should preserve this mechanism; the open question is only whether IAM users are the right *identity* to carry it (Finding 6, Fork 4), not whether `GetSessionToken` is the right *API*.

#### Finding 8: AWS's own recommended alternative — IAM Identity Center CLI federation — does not offer a currently-verified equivalent to 4Shark's frictionless, Touch-ID-driven elevation

**Evidence:**

Finding 6 already establishes that AWS recommends federation via IAM Identity Center over IAM-user access keys for human CLI access. Independently, a WebSearch on headless/non-interactive `aws sso login` returned, among the results, an open `aws/aws-cli` GitHub issue titled *"Browserless AWS CLI login to AWS SSO"* and a blog post describing the native workaround: *"the `--use-device-code` flag provides a solution where the CLI prints a URL and a one-time code, which you can open on any other device, enter the code to authenticate, and the CLI polls in the background to pick up the token automatically."* (WebSearch summary only — not independently fetched; per this spike's citation discipline this supports only the general shape of the trade-off, not a specific verbatim AWS claim.)

**Significance:** 4Shark's current elevation flow is designed around silent, Touch-ID-gated automation (`~/.claude/docs/AWS-MFA.md:10-11`: *"the engineer never types a TOTP code manually"*). `aws sso login`'s standard flow opens a browser for interactive consent; the device-code flow still requires the engineer to open a URL and type a code on another device, not a background Touch ID prompt. This is real, but this spike did not verify whether a headless SSO client (e.g., third-party tools such as `headless-sso`, found in search results but not independently vetted) could reproduce 4Shark's current UX — flagged as an open question, not asserted either way.

#### Finding 9: AWS CLI profile-naming tooling (`aws-vault`, `Granted`) supports flexible, templated naming rather than prescribing a fixed convention

**Evidence:**

Granted/Common Fate documentation (WebSearch summary): profile names can be customized with a template such as `"{{ .AccountID }}-{{ .AccountName }}-{{ .RoleName }}"`. (WebSearch summary only — not independently fetched.)

**Significance:** this corroborates, from the tooling side, that there is no single external convention 4Shark's redesign must conform to — it supports Finding 10 below rather than adding a new claim.

### Q3 — Is there an established community convention for naming AWS profiles?

#### Finding 10: no single naming convention was found; multiple independent sources state organizations define their own scheme

**Evidence:** WebSearch results (not independently fetched — this Finding is explicitly about the absence of a single convention, which a search summary is adequate evidence for): *"there's no official AWS-recommended naming convention specifying the exact suffixes '-mfa', '-elevated', or '-admin'. Organizations typically define their own naming schemes based on their needs."* The same search surfaced a generic recommendation with no fixed vocabulary: *"Use descriptive names with account name and environment."*

**Significance:** "the community does not name a single convention for AWS profile suffixes" is itself a valid, useful conclusion per this spike's citation discipline — it means the redesign is free to draw its naming from 4Shark's OWN grammar (Q5 below) rather than reconciling against an external standard that does not exist.

### Q4 — Reconciling `ivo`'s two roles: AWS scope vs. cross-service ownership

#### Finding 11: `ivo`'s elevated AWS session carries IAM+Identity Center+CloudTrail(+state) permissions — broader than "identity only," narrower than infrastructure administration

**Evidence:**

`~/Projects/4Shark/terraform/identity/policy_break_glass.tf` attaches three separate IAM policies to the break-glass user (`:210-223`), not one:

- `BreakGlassIdentity` (`:21-46`): `iam:*`, `identitystore:*`, `sso-directory:*`, `sso:*` — MFA-gated
- `BreakGlassAudit` (`:48-118`): `cloudtrail:*` plus scoped S3 actions on `arn:aws:s3:::4shark-cloudtrail` — MFA-gated
- `BreakGlassTerraformState` (`:120-208`): S3 read/write scoped to `identity/*` and `audit/*` state paths, plus KMS actions scoped by alias to `alias/4shark-infrastructure` / `alias/main` — MFA-gated

The file's own header comment (`:6-13`) states the design directly: *"THE SERVICES ARE GRANTED WHOLE, THE STORAGE IS NOT, and that asymmetry is the design rather than an inconsistency. IAM, Identity Center and CloudTrail are the domain this identity exists for..."*

**Significance:** the brief's candidate name "policy-arbiter" (IAM/permission-granting only) is narrower than what the break-glass identity's AWS session actually does — it also administers CloudTrail (the `audit/` stack) and the state/KMS access those two stacks specifically need. A name for the AWS-side role should cover "identity and audit administration," not "policy granting" alone, or it will mislead about the `audit/` half.

#### Finding 12: 4Shark's own vocabulary for this role, everywhere it appears in code, is already "break-glass" — not "policy-arbiter" or any other term

**Evidence:**

The IAM policy *resource names themselves* — `BreakGlassIdentity`, `BreakGlassAudit`, `BreakGlassTerraformState`, `BreakGlassIdentityPortal` (`policy_break_glass.tf:21,48,120`; `policy_break_glass_portal.tf:21`) — use "BreakGlass" as the prefix. `identity/README.md`'s section header is literally "### Break Glass Account" (`:23`). `ADR-004` and `ADR-013` are both titled around "break glass" / "Break-Glass". The operational runbook is `~/.claude/docs/runbooks/engineer-access/BREAK-GLASS.md` (referenced at `identity/README.md:38`).

**Significance:** "break-glass" is not a candidate term to introduce — it is already the term the codebase uses consistently, in Terraform resource names, ADR titles, README section headers, and the runbook filename. A redesign that renamed the AWS *profile* to something else (e.g. "policy-arbiter") while every surrounding artifact still says "break-glass" would introduce a second competing vocabulary for the same concept — this is presented as Fork 1 in the Trade-offs section, not resolved unilaterally here.

#### Finding 13: `ivo@4shark.com.br` is also a live identity outside AWS, confirming the account genuinely spans more than one platform's break-glass role

**Evidence:**

`~/Projects/4Shark/terraform/analytics-access/main.tf:52` and `~/Projects/4Shark/terraform/workspace-access/main.tf:58` both grant `member = "user:ivo@4shark.com.br"` on a GCP `serviceAccountTokenCreator` role. `~/Projects/4Shark/terraform/workspace-access/README.md:45`: *"The project is owned by `ivo@4shark.com.br`, so generate the key as that account."* `~/Projects/4Shark/terraform/identity/README.md:17`: *"MongoDB Atlas | Org Member | Via break glass account."*

**Significance:** this corroborates the brief's premise directly from code — `ivo` genuinely is 4Shark's single cross-service owner identity (AWS, GCP, MongoDB Atlas, and per the CLAUDE.md context, Redis Cloud), not an AWS-specific concept. The redesign's naming choice for the *AWS profile* does not need to (and per Finding 12, should not) invent a second name for the underlying identity — the account is one thing wearing narrower or broader scope per platform, and that scoping is already handled by policy attachment (Finding 11), not by name.

### Q5 — Do the two MFA-serial env-vars survive the redesign?

#### Finding 14: 4Shark's own bootstrap-credential exception (`THIRD-PARTY-KEY-STANDARD.md`) is structurally the closest internal precedent for what `ivo`'s long-term AWS key already is

**Evidence:**

`~/.claude/docs/THIRD-PARTY-KEY-STANDARD.md:99-105`: *"The credential Terraform authenticates with is the one key this standard cannot govern in full. It is the chicken-and-egg the rest of the document depends on and never names: Terraform creates keys by authenticating to the vendor, so the credential that authenticates it cannot itself be created by Terraform... Naming — no `<ENTITY>` segment... it is org-wide by definition."* And `:115`: *"Lifecycle — created out of band, rotated by hand."*

`identity/break_glass.tf:6-10` describes `ivo`'s long-term key in the same terms, independently: *"its long-term access key and its MFA device, because both would land in state and because Terraform managing them means an apply can destroy the credential that runs the apply."*

**Significance:** `ivo`'s AWS long-term key is 4Shark's own AWS-native instance of the exact pattern `THIRD-PARTY-KEY-STANDARD.md` already names and grants an exception for elsewhere (Datadog's `DATADOG_API_KEY`/`DATADOG_APP_KEY`, Rollbar's `ROLLBAR_API_KEY`): a bootstrap credential, org-wide (no `<ENTITY>` segment), created and rotated out of band. Applying the doc's own naming shape (`<SERVICE>_<TYPE>`, dropping the entity segment) to the AWS case suggests the credential-identifying facts about it — an MFA serial ARN, a 1Password reference — belong pinned as constants the same way `OP_SECRET_REFERENCE` already is (Finding 2), not as a personal engineer variable.

#### Finding 15: the personal engineer env-vars (`AWS_MFA_SERIAL`, `AWS_MFA_ITEM`) already satisfy `CODE-STYLE-RULES.md`'s variable-naming rule as written

**Evidence:**

`~/.claude/docs/CODE-STYLE-RULES.md:183-184`: *"No abbreviations... The name must accurately describe what the variable actually holds."* `AWS_MFA_SERIAL` holds an MFA device serial/ARN; `AWS_MFA_ITEM` holds a 1Password item title. Neither is abbreviated (MFA is an acronym in wide use throughout 4Shark's own docs, not an abbreviation of a longer phrase chosen for brevity), and both names describe their content accurately.

**Significance:** these two personal, per-engineer env-vars are not implicated by the redesign on naming grounds — the redesign's work on env-vars is concentrated on `AWS_BREAK_GLASS_MFA_SERIAL` (Finding 2), which is the one that does not fit its own category.

## Redesigned model

The table states what should exist, what changes, and why — grounded in the numbered Findings above. "Account identifier" (`ivo@4shark.com.br`) is out of scope per the brief and is not listed as changing.

| Item | Current | Disposition | New shape | Why (Findings) |
|---|---|---|---|---|
| Engineer baseline profile | `default` (per `AWS-MFA.md`) / `4shark` (per the stale `AWS-ENGINEER-SETUP.md`) | **RENAME** | A role-based name replacing the redundant/stale `4shark` segment — e.g. `engineer` | Findings 1, 10, 12 (no external convention to defer to; 4Shark's own vocabulary is the input) |
| Engineer MFA-elevated profile | `4shark-mfa` | **RENAME** | Paired with the baseline name above, using 4Shark's own existing "MFA-elevated" vocabulary (`IDENTITY-STACK.md:12-15`) — e.g. `engineer-mfa` or `engineer-elevated` | Findings 3, 10, 12 |
| CLI-native role-chaining profile | `4shark-elevated` | **DROP** (pending verification — see Open Questions) | — | Finding 1 |
| Break-glass long-term-key profile | `ivo` | **RENAME** | Role-based name matching the account's own established vocabulary — e.g. `break-glass` | Findings 3, 12, 13, 14 |
| Break-glass MFA-elevated profile | `ivo-elevated` | **RENAME** | Paired with the above — e.g. `break-glass-elevated` | Findings 3, 11, 12 |
| `identity/`/`audit/` stack `.envrc` pin | `export AWS_PROFILE=ivo-elevated` | **UPDATE** (mechanical follow-on of the rename above) | `export AWS_PROFILE=<new-elevated-profile-name>` | Follows from the row above |
| `guard.tf` postcondition | Compares `user_id` to a hardcoded IAM unique ID, with a comment explaining the opacity is deliberate (`guard.tf:1-21`; `identity/README.md:60-66`) | **KEEP** | Unchanged — this already does not reference `ivo` by name, so profile renaming does not touch it | Not implicated by any Finding |
| Engineer personal MFA serial | `AWS_MFA_SERIAL` | **KEEP** | Unchanged | Finding 15 |
| Engineer personal 1Password item | `AWS_MFA_ITEM` | **KEEP** | Unchanged | Finding 15 |
| Break-glass MFA serial | `AWS_BREAK_GLASS_MFA_SERIAL` (per-engineer `settings.local.json` entry) | **DROP** | Hardcode the ARN as a script constant in `elevate-break-glass-access.sh`, mirroring `OP_SECRET_REFERENCE` already there | Findings 2, 14 |
| Break-glass 1Password OTP reference | `OP_SECRET_REFERENCE` (already hardcoded) | **KEEP** | Unchanged — this is the pattern the row above should follow | Finding 2 |
| Account/environment segment in profile names | None | **NOT ADDED** | — | Finding 4 (single account, unconfirmed Organization — no evidence a segment is needed yet) |
| A profile distinguishing "Claude Code" elevation from "terminal" elevation | Implied by `AWS-MFA.md`'s comparison table, but the underlying scripts show one mechanism | **NOT ADDED** | — | Finding 1 (the distinction the table describes appears to already be collapsed into one script/profile in current code) |

## Trade-offs surfaced

### Fork 1 — AWS-side name for the break-glass identity's elevated session

| Option | Pros | Cons | Source |
|---|---|---|---|
| A. Keep unified "break-glass" vocabulary (`break-glass`, `break-glass-elevated`) | Consistent with every other artifact already using this term (IAM policy resource names, ADR titles, README section header, runbook filename — Finding 12); no translation cost for a reader moving between the profile and the surrounding docs | Does not narrow the name to reflect that the AWS session specifically covers identity+audit+state, not literally "everything" | Findings 11, 12 |
| B. A narrower, AWS-scoped name (e.g. reflecting "identity and audit administration") | More precisely describes what the *AWS profile specifically* may do, per the three attached policies (Finding 11) | Introduces a second term for the same underlying account/identity that "break-glass" already names everywhere else in the codebase — a reader has to learn that this name and "break-glass" refer to the same thing | Finding 11 vs. Finding 12 |

### Fork 2 — Engineer CLI identity: keep IAM-user + `GetSessionToken`, or migrate to IAM Identity Center federation

| Option | Pros | Cons | Source |
|---|---|---|---|
| A. Keep IAM users + `GetSessionToken` (current shape, renamed only) | `GetSessionToken` is the AWS-documented correct API for this exact access-control shape — same-account, identity-policy `aws:MultiFactorAuthPresent` conditions (Finding 7); preserves the current frictionless, Touch-ID-automated elevation UX (`AWS-MFA.md:10-11`) | This is precisely the anti-pattern AWS's own SEC02-BP02 guidance lists: *"Developers using long-term access keys from IAM users rather than obtaining temporary credentials from the CLI using federation"* (Finding 6) | Findings 6, 7 |
| B. Migrate engineer CLI access to IAM Identity Center federation (`aws sso login` / `aws configure sso`) | Matches AWS's stated recommendation directly (Finding 6); eliminates long-term IAM user access keys for engineers entirely | No verified equivalent to today's silent Touch-ID automation exists in the standard flow — the native non-interactive path (`--use-device-code`) still requires the engineer to open a URL and enter a code manually, not a background MFA prompt (Finding 8, WebSearch-sourced, not independently verified); would be a bigger change than a naming redesign, touching the elevation scripts and the console-vs-CLI identity split described in `identity/README.md:204-225` | Findings 6, 8 |

### Fork 3 — What to do with `4shark-elevated`

| Option | Pros | Cons | Source |
|---|---|---|---|
| A. Remove every reference (treat as confirmed dead) | Cleans up `AWS-MFA.md`'s comparison table, which currently describes a mechanism that appears to no longer exist in code | This spike could not read the engineer's local `~/.aws/config` (a Bash `grep` against that path was denied by the sandbox) — removing based on documentation-only evidence risks deleting a genuinely still-configured profile on someone's machine | Finding 1 |
| B. Keep the reference, but mark it explicitly unverified/legacy pending a one-line confirmation from each engineer (`grep '^\[' ~/.aws/config`) | No risk of deleting a live mechanism sight unseen | Leaves stale, actively misleading documentation (a runbook that points to a non-existent script) in place a while longer | Finding 1 |

## What remains uncertain

- **Whether `4shark-elevated` (role-chaining) is genuinely still configured on any engineer's machine.** All documentary evidence points to it being superseded (Finding 1), but this spike had no read access to `~/.aws/config` to confirm directly.
- **Whether 4Shark's AWS account belongs to an AWS Organization.** `organizations:DescribeOrganization` is denied to the engineer profile (Finding 4/ADR-013); this bears on whether an account-segment is ever needed in profile naming, and on whether an SCP-based preventive bound on the break-glass identity (an alternative ADR-013 left open) becomes available.
- **Whether a headless/Touch-ID-equivalent automation exists for IAM Identity Center CLI federation** that would make Fork 2 Option B practically comparable in UX to the current `GetSessionToken` flow. Finding 8 is WebSearch-sourced only and not independently verified against a working implementation.
- **Whether Redis Cloud's ownership of `ivo` (referenced in `~/.claude/CLAUDE.md` § Deployment Strategy in the context of the Sidekiq queue check, and in the mission brief) follows the same "org-wide owner, not an entry in `var.engineers`" shape confirmed for GCP and MongoDB Atlas** (Finding 13). No Redis Cloud-specific Terraform or credential file was located in the terraform repository search performed for this spike.

## Suggested options for main and the engineer

- The redesign in the table above (renaming `default`→`engineer`-family and `ivo`→`break-glass`-family, dropping `4shark-elevated` and `AWS_BREAK_GLASS_MFA_SERIAL`, keeping everything else) is directly grounded in Findings 1–4, 10, 12, 14, 15 and does not depend on resolving either open fork.
- Fork 1 (naming the AWS-scoped session narrowly vs. keeping unified "break-glass" vocabulary) and Fork 2 (IAM-user+MFA vs. Identity Center federation) are genuinely open — this spike surfaces both sides with their grounding but does not resolve them; per the Subagent Contract, that choice belongs to the engineer.
- Fork 3 (delete vs. mark-and-verify `4shark-elevated`) is a scoping decision on how much confidence is required before touching a currently-live-looking (but likely dead) mechanism.

## Surfaces this redesign would touch

- **dot-claude**: `~/.claude/docs/AWS-MFA.md` (profile table, comparison table, all profile-name references), `~/.claude/docs/IDENTITY-STACK.md`, `~/.claude/docs/runbooks/engineer-access/AWS-ENGINEER-SETUP.md` (needs a full rewrite regardless of this redesign — it is already stale independent of any naming decision, per Finding 1), `~/.claude/CLAUDE.md` § AWS Policy and § "Identity Stack and Engineer Permissions", `~/.claude/skills/elevate-aws-access/scripts/elevate-aws-access.sh` (the `AWS_PROFILE_NAME` constant), `~/.claude/skills/elevate-break-glass-access/scripts/elevate-break-glass-access.sh` (`AWS_SOURCE_PROFILE`, `AWS_PROFILE_NAME`, and the `AWS_BREAK_GLASS_MFA_SERIAL` removal per Finding 2), `~/.claude/scripts/terraform.sh` (the `AWS_PROFILE=4shark-mfa` default), `~/.claude/docs/runbooks/engineer-access/BREAK-GLASS.md` (not read in this spike — should be checked for further `ivo`/`ivo-elevated` references before executing any rename)
- **terraform repository**: `identity/.envrc`, `audit/.envrc` (the `AWS_PROFILE=ivo-elevated` pin), `identity/README.md`, `docs/adr/ADR-004-identity-model.md` and `ADR-013-break-glass-usage-model.md` (both narrate the current profile names in prose)
- **Local, non-versioned state**: each engineer's `~/.aws/credentials` and `~/.aws/config` (profile section headers), each engineer's `~/.claude/settings.local.json` (`AWS_MFA_SERIAL`, `AWS_MFA_ITEM`, and the `AWS_BREAK_GLASS_MFA_SERIAL` entry this redesign proposes removing)
