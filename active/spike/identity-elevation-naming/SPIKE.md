# SPIKE — Identity & Elevation Naming Grammar

## Investigation question

4Shark's AWS account has a layered privilege model with four identity tiers (root, engineer/baseline, engineer/MFA-elevated, break-glass/baseline, break-glass/MFA-elevated). The two engineer-facing AWS profiles are named after the company (`4shark`, `4shark-mfa`); the permission-administrator identity is named after the person currently holding it (`ivo`, `ivo-elevated`). The engineer wants to rename all of it — AWS profiles/IAM users, the Terraform `identity/` stack, repo.cloud, the IAM roles, and the dot-claude config — using names grounded in an established industry concept and named by function rather than by person. This spike surfaces the established concept names for each tier and lays out naming-grammar options; it does not choose one.

## Current model (ground truth, as implemented)

Four tiers, established by reading the terraform `identity/` stack and its governing ADRs before any web research:

1. **Root** — the AWS root user. Full account power, the only identity with it. Every login requires a hardware MFA key (YubiKey), never a software TOTP.
2. **Engineer, baseline** — read-only by default on AWS (and Cloudflare/MongoDB Atlas). AWS profile `default` (called `4shark` informally in the docs — see `~/.claude/docs/AWS-MFA.md:7`, *"Default profile — read-only access for day-to-day operations"*).
3. **Engineer, MFA-elevated** — a 1-hour AWS STS session (`aws sts get-session-token`), profile `4shark-mfa`, gated by the `EngineerWriteAccess` policy checking `aws:MultiFactorAuthPresent` (`~/Projects/4Shark/terraform/identity/README.md:15`, *"Write operations on AWS require MFA — the `EngineerWriteAccess` policy checks `aws:MultiFactorAuthPresent` on every sensitive action"*).
4. **Break-glass, baseline (the "permission-administrator")** — AWS IAM user `ivo@4shark.com.br` (`~/Projects/4Shark/terraform/identity/break_glass.tf:21-22`), holding a long-term access key that exists *only* to be exchanged via `GetSessionToken` (`~/.claude/docs/IDENTITY-STACK.md:10`, *"The `ivo` profile carries the long-term key, and `GetSessionToken` is why it exists — AWS requires a long-term credential to mint a session"*). It carries no baseline IAM policy at all — `GetSessionToken` needs no authorization to call (`~/Projects/4Shark/terraform/identity/break_glass.tf:14-19`, *"The only thing this identity does without MFA is mint a session, and that action is not authorizable"*).
5. **Break-glass, MFA-elevated (the "judge")** — a 15-minute `GetSessionToken` session (the AWS floor for that API), profile `ivo-elevated`, scoped to identity work only: creating/removing IAM users, groups, policies inside the `identity/` Terraform stack. It grants nothing else — no security groups, no compute, no data (`~/Projects/4Shark/terraform/identity/README.md:29`, *"Its elevated session is scoped to identity work — IAM users, groups, policies — never security groups, compute or data"*). `guard.tf` mechanically restricts `plan`/`apply` on the `identity/` stack to this one identity by IAM unique ID (`~/Projects/4Shark/terraform/identity/guard.tf:6-7`).

Two orthogonal axes, both already present in the local docs before any web research began:

- **Elevation axis** — baseline (little/no standing privilege) → time-boxed MFA session (1h for engineer, 15min for break-glass). 4Shark's own terminology for this split is already "baseline vs MFA-elevated" (`~/.claude/docs/IDENTITY-STACK.md:12-15`).
- **Role axis** — engineer (operates infrastructure) vs. break-glass/permission-administrator (grants/revokes IAM permissions, operates nothing else) vs. root (emergency full power).

The trigger for reaching the break-glass identity is *not* an outage — it is a missing engineer permission, closed permanently via a reactive-grant rule each time it is used (`~/Projects/4Shark/terraform/docs/adr/ADR-013-break-glass-usage-model.md:13-15`, *"the identity is in fact reached for a different and more frequent reason: engineer permissions start at nothing and are granted reactively, one confirmed `AccessDenied` at a time, so the ordinary trigger is a permission the engineer account does not yet hold"*). ADR-013 itself already flags that this diverges from the AWS Well-Architected emergency-access pattern (see Finding 9 below) — that divergence is why the local docs currently call it "break glass" even though the trigger does not match AWS's own break-glass trigger.

## Sources consulted

- `~/.claude/docs/IDENTITY-STACK.md` — 4Shark's own baseline/MFA-elevated terminology and the procedural (not technical) bound on the break-glass identity
- `~/.claude/docs/AWS-MFA.md` — the `4shark`/`4shark-mfa` naming and the separate `4shark-elevated` CLI-native profile
- `~/Projects/4Shark/terraform/identity/README.md` — the security model table, the break-glass account description, engineer identity model
- `~/Projects/4Shark/terraform/docs/adr/ADR-004-identity-model.md` — the original decision to adopt the unified identity model with a break-glass account
- `~/Projects/4Shark/terraform/docs/adr/ADR-013-break-glass-usage-model.md` — the correction of ADR-004's framing, its own citation of AWS SEC03-BP03, and the explicit statement that scoping the session "bounds intent and audit legibility, never capability"
- `~/Projects/4Shark/terraform/identity/break_glass.tf` and `guard.tf` — the break-glass IAM user resource and the stack-apply guard
- [AWS Well-Architected SEC03-BP03](https://docs.aws.amazon.com/wellarchitected/latest/framework/sec_permissions_emergency_process.html) — official AWS emergency/break-glass access guidance (Findings 8, 9, 12, 13)
- [AWS Organizations — Terminology and concepts](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_getting-started_concepts.html) — official definition of "delegated administrator" (Finding 7)
- [AWS CloudTrail — Organization delegated administrator](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-delegated-administrator.html) — a worked example of delegated administrator scope (Finding 7b)
- [AWS Security Blog — How to Create a Limited IAM Administrator by Using Managed Policies](https://aws.amazon.com/blogs/security/how-to-create-a-limited-iam-administrator-by-using-managed-policies/) — AWS's own use of "IAM administrator" as a role title (Finding 6)
- [AWS CAF Security Perspective whitepaper — Identity and access management](https://docs.aws.amazon.com/whitepapers/latest/aws-caf-security-perspective/identity-and-access-management.html) — separation of duties, root user dual control, temporary-credentials-by-default (Findings 4, 5, 11)
- [AWS IAM — Temporary security credentials](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_temp.html) — the AWS-native term for time-boxed elevation (Finding 3)
- [NIST SP 800-53 Rev 5 AC-6, via csf.tools](https://csf.tools/reference/nist-sp-800-53/r5/ac/ac-6/) — the least-privilege control text (Finding 2)
- [Palo Alto Networks — What Is Just-In-Time Access?](https://www.paloaltonetworks.com/cyberpedia/what-is-just-in-time-access-jit) — JIT definition and its relation to zero standing privileges (Finding 1)
- [Teleport — What is Zero Standing Privilege?](https://goteleport.com/blog/zero-standing-privileges/) — ZSP definition, Gartner-coinage claim, relation to JIT (Finding 1b)
- [Google Cloud IAM — Best practices for using service accounts securely](https://docs.cloud.google.com/iam/docs/best-practices-service-accounts) — function-named vs. person-tied identity lifecycle (Finding 10)

## Findings

### Research point 1 — the whole model (default-deny baseline, time-boxed elevation)

**Finding 1 — Just-in-Time (JIT) access**
**Evidence:** *"Just-in-time (JIT) access is an access control approach that grants time-limited, task-specific privileged permissions to a human or non-human identity only when needed, and revokes those privileges immediately after the work is done."*
**Source:** Palo Alto Networks, "What Is Just-In-Time Access (JIT)?"
**Significance:** This is the closest established name for the elevation axis as a whole — a baseline identity that exchanges standing privilege for a short, task-scoped session, which is exactly the `4shark`→`4shark-mfa` and `ivo`→`ivo-elevated` shape.
**Verification:** URL fetched: https://www.paloaltonetworks.com/cyberpedia/what-is-just-in-time-access-jit — Verbatim quote checked — Quote substring confirmed in the fetched page body (definition section).

**Finding 1b — Zero Standing Privileges (ZSP), and its relation to JIT**
**Evidence:** *"Zero standing privilege (ZSP) is an applied zero trust security strategy for privileged access management (PAM)"*, and *"no users should be pre-assigned with administrative account privileges"* — with JIT named as *"the process used precisely for this purpose"* of realizing ZSP. The article also states the term *"was coined by an analyst at Gartner"* without naming the specific report.
**Source:** Teleport, "What is Zero Standing Privilege (ZSP)?"
**Significance:** ZSP names the *end state* 4Shark's model already approximates (both engineer and break-glass identities hold near-zero standing privilege); JIT/elevation is the *mechanism* that gets there. The Gartner-coinage claim is a secondary source's attribution, not independently confirmed against a Gartner-published page (Gartner's own report pages are not open-access) — treat "coined by Gartner" as reported by a third party, not verified against the primary source.
**Verification:** URL fetched: https://goteleport.com/blog/zero-standing-privileges/ — Verbatim quote checked — Quote substrings confirmed in the fetched page body.

**Finding 2 — NIST SP 800-53 least privilege (AC-6)**
**Evidence:** *"Employ the principle of least privilege, allowing only authorized accesses for users (or processes acting on behalf of users) that are necessary to accomplish assigned organizational tasks."*
**Source:** NIST SP 800-53 Rev 5, control AC-6, as reproduced by csf.tools
**Significance:** This is the umbrella principle both the engineer and break-glass tiers already implement (read-only/near-zero by default, elevate only for the task). It grounds "least privilege" as the governing framework term, distinct from — and superordinate to — JIT/ZSP, which are implementation mechanisms of it.
**Verification:** URL fetched: https://csf.tools/reference/nist-sp-800-53/r5/ac/ac-6/ — Verbatim quote checked — Quote substring confirmed at the "Main Control Statement" section of the fetched page.

**Finding 3 — AWS's own term: "temporary security credentials"**
**Evidence:** *"Temporary security credentials are short-term, as the name implies. They can be configured to last for anywhere from a few minutes to several hours. After the credentials expire, AWS no longer recognizes them or allows any kind of access from API requests made with them."*
**Source:** AWS IAM User Guide, "Temporary security credentials in IAM"
**Significance:** This is AWS's own vocabulary for exactly the mechanism `4shark-mfa` and `ivo-elevated` use (`sts get-session-token`). A naming scheme that wants to stay AWS-idiomatic rather than borrow PAM-industry vocabulary (JIT/ZSP) has this as its anchor term.
**Verification:** URL fetched: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_temp.html — Verbatim quote checked — Quote substring confirmed at the top of the "Temporary security credentials in IAM" section.

### Research point 2 — Tier 2 (engineer): baseline vs. elevated naming

**Finding 4 — "temporary credentials by default" as an AWS CAF tenet**
**Evidence:** *"Use temporary credentials like AWS IAM roles by default — Static users, passwords, and access keys are a last resort, issued by exception only."*
**Source:** AWS Cloud Adoption Framework (CAF) Security Perspective whitepaper, "Identity and access management"
**Significance:** AWS's own recommended tenet names the baseline/elevated split as "temporary credentials by default" vs. static/long-term as the exception — matching 4Shark's `4shark` (default profile, no elevation) / `4shark-mfa` (temporary STS session) shape precisely.
**Verification:** URL fetched: https://docs.aws.amazon.com/whitepapers/latest/aws-caf-security-perspective/identity-and-access-management.html — Verbatim quote checked — Quote substring confirmed under "Sample tenets".

**Finding 5 — "treat static credentials as toxic"**
**Evidence:** *"Treat static AWS IAM credentials as toxic and prohibit them by default. People access AWS through federated authorization."*
**Source:** Same AWS CAF whitepaper as Finding 4
**Significance:** Reinforces the baseline-identity concept: the *standing* credential is the thing to avoid, not the identity itself. Relevant to naming because it argues against any scheme that would make the "baseline" name read as a permanent, always-privileged account.
**Verification:** URL fetched: https://docs.aws.amazon.com/whitepapers/latest/aws-caf-security-perspective/identity-and-access-management.html — Verbatim quote checked — Quote substring confirmed under "Credential management".

**Not found:** No established, AWS- or NIST-sourced term was found that names the baseline↔elevated *pair* as a single noun (e.g., no verified "step-up account" or equivalent). "Step-up authentication" appears in vendor glossaries (e.g., an nhimg.org glossary entry) describing conditional re-verification at moments of rising risk, but that source was not independently re-fetched and confirmed here, so it is not used to sustain any naming candidate below.

### Research point 3 — Tier 3 (the permission-granting identity): does "delegated administrator" or "break-glass" match?

**Finding 6 — AWS's own term: "IAM administrator"**
**Evidence:** A limited IAM administrator *"should be able to create users and generate access keys, and be able to grant permissions by using a well-defined set of managed policies."* And: *"By specifying the exact set of managed policies that the limited IAM administrator may attach, you prevent the limited IAM administrator from elevating her own privilege and gaining unauthorized access to your account."*
**Source:** AWS Security Blog, "How to Create a Limited IAM Administrator by Using Managed Policies"
**Significance:** This is the closest AWS-native title for 4Shark's Tier 3 identity — a role whose job is creating/granting IAM permissions to *other* identities, with an explicit self-escalation concern that mirrors ADR-013's own rationale (`~/Projects/4Shark/terraform/docs/adr/ADR-013-break-glass-usage-model.md:45-46`, *"A principal that can write IAM can always write itself an administrator policy... a permissions boundary does not close that for a principal able to edit its own boundary"*). Unlike AWS's blog post (which proposes a *technical* bound via managed-policy allow-lists), 4Shark's ADR-013 already concluded the bound here is procedural, not technical — the concept name transfers; the enforcement mechanism does not.
**Verification:** URL fetched: https://aws.amazon.com/blogs/security/how-to-create-a-limited-iam-administrator-by-using-managed-policies/ — Verbatim quote checked — Quote substrings confirmed in the fetched page body.

**Finding 7 — "Delegated administrator" (AWS Organizations) does NOT match**
**Evidence:** *"Delegated administrator for an AWS service: From these accounts, you can manage AWS services that integrate with Organizations... These accounts have administrative permissions for a specific service, as well as permissions for Organizations read-only actions."*
**Source:** AWS Organizations User Guide, "Terminology and concepts for AWS Organizations"
**Significance:** "Delegated administrator" in AWS's own usage names an account that administers ONE AWS *service* (e.g., GuardDuty, Config, CloudTrail) across an entire multi-account organization — not an identity whose job is granting/revoking IAM *permissions* to other identities within a single account. This is a genuine terminology mismatch with 4Shark's Tier 3, confirming the caution flagged in the investigation brief.
**Verification:** URL fetched: https://docs.aws.amazon.com/organizations/latest/userguide/orgs_getting-started_concepts.html — Verbatim quote checked — Quote substring confirmed under "Delegated administrator" in the "Organization structure" section.

**Finding 7b — worked example of the mismatch**
**Evidence:** *"When you use CloudTrail with an AWS Organizations organization, you can assign any account within the organization to act as a CloudTrail delegated administrator to manage the organization's trails and event data stores on behalf of the organization."*
**Source:** AWS CloudTrail User Guide, "Organization delegated administrator"
**Significance:** Confirms Finding 7 with a concrete example — the delegated-administrator pattern is per-service, per-organization, not per-permission, per-account. 4Shark's account is (as far as the engineer profile can determine) not confirmed to belong to an AWS Organization at all (`~/Projects/4Shark/terraform/docs/adr/ADR-013-break-glass-usage-model.md:52`, *"Whether this account belongs to an organization is unconfirmed: `organizations:DescribeOrganization` is denied to the engineer profile"*), which independently weakens "delegated administrator" as a fit — the concept presupposes an AWS Organization the local model does not confirm having.
**Verification:** URL fetched: https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-delegated-administrator.html — Verbatim quote checked — Quote substring confirmed at the top of the "Organization delegated administrator" page.

**Finding 8 — AWS's own use of "break-glass"**
**Evidence:** *"The emergency access account should only be accessed during emergencies, as break-glass procedures can be considered a backdoor."* Also: *"During normal operations, no one should access the emergency access account and you must monitor and alert on the misuse of this account."*
**Source:** AWS Well-Architected Framework, SEC03-BP03 "Establish emergency access process"
**Significance:** AWS's own documentation does use "break-glass" (linking it to a dedicated whitepaper page titled "Break glass access"), so 4Shark's existing "break glass" terminology is not invented — it is AWS's own vocabulary for an emergency-access account. The second quote is the exact sentence ADR-013 already cites (`~/Projects/4Shark/terraform/docs/adr/ADR-013-break-glass-usage-model.md:19-20`).
**Verification:** URL fetched: https://docs.aws.amazon.com/wellarchitected/latest/framework/sec_permissions_emergency_process.html — Verbatim quote checked — Both quote substrings confirmed in the fetched page body (Common guidance section, and "During normal operations..." sentence under Failure Mode 1).

**Finding 9 — but AWS's "break-glass" trigger does not match 4Shark's actual trigger**
**Evidence:** AWS's break-glass/emergency-access process is designed for *"the unlikely event of an issue with your centralized identity provider"* — specifically federation failure (identity provider down, its AWS-side configuration broken or expired, or an IAM Identity Center regional disruption) — never for a routine missing permission. 4Shark's own ADR-013 draws this exact distinction: *"That phrasing describes an outage, and the identity is in fact reached for a different and more frequent reason: engineer permissions start at nothing and are granted reactively, one confirmed `AccessDenied` at a time, so the ordinary trigger is a permission the engineer account does not yet hold."*
**Source:** AWS Well-Architected SEC03-BP03 (URL above) for the AWS-side framing; `~/Projects/4Shark/terraform/docs/adr/ADR-013-break-glass-usage-model.md:13-15` for 4Shark's own correction
**Significance:** 4Shark's Tier 3 identity is doing two jobs the AWS "break-glass" concept keeps separate: (a) the emergency/outage-recovery identity AWS describes, and (b) a routine, frequently-used permission-granting identity, which is closer to Finding 6's "IAM administrator" than to Finding 8's "break-glass." A naming scheme has to decide whether to keep one name for both jobs (as today) or split the vocabulary.
**Verification:** URL fetched (AWS side): https://docs.aws.amazon.com/wellarchitected/latest/framework/sec_permissions_emergency_process.html — Verbatim quote confirmed in the "Desired outcome" section. Local file read directly: `~/Projects/4Shark/terraform/docs/adr/ADR-013-break-glass-usage-model.md`, lines 13-15 quoted verbatim above.

### Research point 4 — Tier 1 (root) and hardware MFA

**Finding 11 — root user dual control (AWS CAF)**
**Evidence:** *"All AWS account root users, especially the management account root user, need a strong password in addition to multi-factor authentication (MFA). AWS account root users must be protected with due care and should be controlled by two people. For example, the individual or team that controls the root password of an AWS account should not also control its MFA token."*
**Source:** AWS CAF Security Perspective whitepaper (same as Finding 4/5)
**Significance:** AWS's own guidance for root protection goes further than 4Shark's current single-owner-with-hardware-key model (dual control: one person holds the password, another holds the MFA device). This is a fact for the engineer to weigh, not a naming point — flagged here because Tier 1's *name* in any new scheme should not imply a control 4Shark does not actually run (e.g., naming it "root-dual-control" would overstate the current setup).
**Verification:** URL fetched: https://docs.aws.amazon.com/whitepapers/latest/aws-caf-security-perspective/identity-and-access-management.html — Verbatim quote checked — Quote substring confirmed under "Credential management".

**Finding 12 — AWS's own root emergency-access guidance repeats hardware MFA**
**Evidence:** *"We recommend setting a strong password and multiple MFA tokens for the root user. We also recommend storing the password and the MFA tokens in a secure enterprise credential vault that enforces strong authentication and authorization."*
**Source:** AWS Well-Architected SEC03-BP03 (URL above), "Failure Mode 1" section, root-user approach
**Significance:** Confirms hardware-MFA-on-root as AWS's own recommendation, independent of a CIS Benchmark citation (see Not-found note below).
**Verification:** URL fetched: https://docs.aws.amazon.com/wellarchitected/latest/framework/sec_permissions_emergency_process.html — Verbatim quote checked — Quote substring confirmed in "Failure Mode 1: Identity provider used to federate to AWS is unavailable".

**Not found:** The CIS AWS Foundations Benchmark's exact control text requiring hardware MFA on the root account (commonly cited as CIS control 1.5/1.6/1.14 depending on version) sits behind CIS's own paywalled PDF; secondary pages (e.g., Plerion's knowledge base) reference the control number and give a paraphrase but do not reproduce CIS's verbatim wording, and the fetch of one such page explicitly declined to quote text it did not have. This spike does not attribute a CIS quote — Finding 12 (AWS's own SEC03-BP03 guidance) is used instead, since it was independently fetched and verified.

### Research point 5 — function-not-person naming principle

**Finding 10 — Google Cloud IAM: naming by function, and lifecycle divergence from person-tied accounts**
**Evidence:** On naming: *"Add a prefix to the service account email address that identifies how the account is used. For example: `vm-` for service accounts attached to a VM instance."* On the person/function divergence: *"When an employee joins, a new user account is created for them...And when they leave the company, their user account is suspended or deleted."* — contrasted with service accounts, which the same guidance ties to applications or systems rather than to a person, and recommends disabling (not deleting) when the *resource* they serve is decommissioned, "preserving IAM bindings for potential future re-enablement."
**Source:** Google Cloud IAM documentation, "Best practices for using service accounts securely"
**Significance:** This is the clearest available statement of exactly the principle the engineer named in the brief — an identity named after a *function* has a lifecycle independent of who currently occupies that function, unlike a person-tied account whose lifecycle is bound to that person's employment. It is not AWS-specific, but the principle transfers directly: 4Shark's Tier 3 identity ("ivo" today) is functionally a service/role account (a programmatic-only IAM user with no console login — `~/Projects/4Shark/terraform/identity/break_glass.tf:9-10`, *"a console login profile, which does not exist at all — this identity is programmatic only"*), even though it is currently named after the person who owns it.
**Verification:** URL fetched: https://docs.cloud.google.com/iam/docs/best-practices-service-accounts — Verbatim quote checked — Both quote substrings confirmed in the fetched page body.

**Not found / dropped:** A BeyondTrust article specifically titled "Functional Accounts: Do's and Don'ts" was located by search and looked directly on-point (role-based vs. name-based account naming, transition smoothness when someone leaves), but the URL returned HTTP 403 on fetch and could not be independently verified. Per the quote-or-drop rule, no quote from it is used, and it does not sustain any Finding or naming candidate below. Finding 10 (Google Cloud) stands on its own for this research point.

## Trade-offs surfaced

| Concern | For borrowing PAM/industry vocabulary (JIT, ZSP) | For staying AWS-native (temporary credentials, IAM administrator) |
|---|---|---|
| Recognizability to a new engineer reading `~/.aws/credentials` | High — JIT/ZSP is common PAM vocabulary across vendors (BeyondTrust, CyberArk, Teleport, StrongDM all use it) | Lower outside AWS specifically, but exactly matches what the AWS console and CLI already call these mechanisms |
| Precision for Tier 3 | ZSP/JIT describe the *elevation shape* but say nothing about *what the identity is for* (granting permissions) | "IAM administrator" (Finding 6) names the *function* directly, at the cost of being AWS-IAM-specific vocabulary that would not obviously extend to Cloudflare/MongoDB Atlas, which the break-glass identity also administers (`~/Projects/4Shark/terraform/identity/README.md:23-30`) |
| Fit with 4Shark's own prior terminology | 4Shark already writes "baseline vs MFA-elevated" (`IDENTITY-STACK.md:12-15`) — closer to the AWS-native camp than to JIT/ZSP wording | Same — the existing docs already lean AWS-native |
| Splitting the "outage" vs "permission-grant" trigger (Finding 9) | Neither vocabulary decides this; it is orthogonal to which words are used | Same |

## Naming grammar candidate options

Four candidate grammars, each grounded in a cited concept, each mapping the current `4shark`/`4shark-mfa` and `ivo`/`ivo-elevated` pairs onto new names. Presented as options — no candidate is recommended over another.

| # | Grammar | Grounded in | Tier 2 (engineer) mapping | Tier 3 (break-glass) mapping | Tier 1 (root) | Trade-offs |
|---|---|---|---|---|---|---|
| A | `<role>` / `<role>-elevated` | 4Shark's own existing "baseline vs MFA-elevated" wording (`IDENTITY-STACK.md:12-15`); Finding 3 (AWS "temporary security credentials") | `engineer` / `engineer-elevated` | `identity-admin` / `identity-admin-elevated` (Finding 6, "IAM administrator") | `root` (unchanged — already the AWS-mandated term) | Smallest departure from current docs; keeps the elevation suffix uniform across every tier, but "identity-admin" is IAM-specific even though the identity also touches Cloudflare/Atlas |
| B | `<role>-baseline` / `<role>-jit` | Finding 1 (JIT access) + Finding 1b (ZSP) as the vocabulary | `engineer-baseline` / `engineer-jit` | `access-admin-baseline` / `access-admin-jit` | `root` | Signals the PAM-industry concept explicitly (useful if 4Shark ever adopts a PAM tool), but "jit" as a suffix is unfamiliar to an engineer reading `~/.aws/credentials` cold, and diverges furthest from 4Shark's existing "baseline/elevated" wording |
| C | `<function>` / `<function>-mfa` | Preserves the CURRENT literal suffix style (`4shark-mfa`), only replacing the person/company segment with a function word; Finding 3 (temporary credentials are the mechanism, "mfa" names the specific gate 4Shark actually uses) | `engineer` / `engineer-mfa` | `permissions-admin` / `permissions-admin-mfa` | `root` | Cheapest migration (only the base word changes, suffix pattern is untouched everywhere it already appears — scripts, `.envrc`, `settings.local.json`); "permissions-admin" is closer to Finding 6's framing than "identity-admin" is, since granting/revoking IS the permission action, not merely "identity" work broadly |
| D | `break-glass` retained for Tier 3, split by function | Finding 8 (AWS itself uses "break-glass") for the *outage* half; Finding 6 ("IAM administrator") for the *permission-grant* half; Finding 9 names the mismatch this candidate resolves by NOT collapsing the two | `engineer` / `engineer-elevated` (as in A) | Two separate identities: `break-glass` (kept, for a genuine SSO/federation outage) + `permissions-admin` / `permissions-admin-elevated` (Finding 6, for the routine reactive-grant work ADR-013 describes) | `root` | Only candidate that acts on Finding 9 rather than leaving it unresolved; costs the most to implement (a literal second identity, not just a rename) and reopens a question ADR-013 explicitly declined to reopen (`ADR-013:60-65`, "Split the two roles" was considered and rejected on cost grounds) |

All four candidates leave `root` unchanged, because Finding 12 and the CIS-adjacent hardware-MFA requirement (Not-found note under Research point 4) both describe root as AWS's own fixed vocabulary — there is no found alternative name to consider for that tier.

## Surfaces carrying the current names (for scoping a future rename — not researched in depth)

Flagged from what was read locally during this spike; not exhaustive:

- AWS: the IAM user `ivo@4shark.com.br` itself (`identity/break_glass.tf:22`), and whatever AWS profile names exist in each engineer's `~/.aws/credentials` (`4shark`, `4shark-mfa`, `4shark-elevated`, `ivo`, `ivo-elevated`)
- Terraform `identity/` stack: `break_glass.tf` (resource name + username), `guard.tf` (comments reference "break-glass account" prose, though the postcondition itself keys on IAM unique ID, not name), `README.md` (extensive prose usage), `terraform.tfvars`/`engineers` map is unaffected (it is per-engineer, not the break-glass identity)
- Terraform `identity/.envrc` and `audit/.envrc`, both pinning `AWS_PROFILE=ivo-elevated` (`~/.claude/docs/IDENTITY-STACK.md:5`)
- ADR-004 and ADR-013 (both use "break glass account"/"break-glass identity" throughout)
- `~/.claude/docs/runbooks/engineer-access/BREAK-GLASS.md` (not read in this spike, but named as the activation runbook in `identity/README.md:38`)
- `~/.claude/docs/runbooks/engineer-access/AWS-ENGINEER-SETUP.md` (documents the `4shark-elevated` CLI-native profile, per `AWS-MFA.md:15-16`)
- `~/.claude/docs/AWS-MFA.md` and `~/.claude/docs/IDENTITY-STACK.md` (both Tier-2/Tier-3 docs throughout)
- `~/.claude/CLAUDE.md` — § AWS Policy, § Terraform Command Execution, § "Identity Stack and Engineer Permissions" all reference `4shark-mfa`/`ivo-elevated` by name
- `~/.claude/skills/elevate-aws-access/` and `~/.claude/skills/elevate-break-glass-access/` — skill names themselves encode "break-glass" as a concept, and their scripts write to the `4shark-mfa`/`ivo-elevated` profiles
- `~/.claude/scripts/terraform.sh` and `ruby.sh` (indirectly — `terraform.sh` exports `AWS_PROFILE=4shark-mfa` internally per `~/.claude/CLAUDE.md` § AWS Policy)
- repo.cloud — not inspected in this spike (outside the terraform/dot-claude repos read); the engineer's brief names it explicitly as a surface, so it needs its own check before any rename lands

## What remains uncertain

- Whether 4Shark's AWS account belongs to an AWS Organization at all is unconfirmed (Finding 7b cites ADR-013's own admission that `organizations:DescribeOrganization` is denied to the engineer profile). This affects whether "delegated administrator" could ever legitimately apply to a *different, future* identity (e.g., if 4Shark later adopts AWS Organizations for multi-account separation) — it does not apply to the current single-account Tier 3 identity regardless.
- The exact CIS AWS Foundations Benchmark control number and wording for root hardware MFA was not independently verified (paywalled); only AWS's own SEC03-BP03 root guidance (Finding 12) is verified and cited.
- "Step-up authentication" as a term for Tier 2's baseline→elevated transition was found in vendor glossaries but not independently re-fetched and confirmed — it does not sustain any candidate above.
- The BeyondTrust "Functional Accounts" source could not be fetched (403) — the function-not-person naming principle rests on Finding 10 (Google Cloud) alone, which is sufficient but not corroborated by a second independent source.
- Whether Gartner is genuinely the originating source for "Zero Standing Privileges" is reported by a secondary source (Teleport) rather than confirmed against a Gartner-published page.

## Suggested options for main and the engineer

- Option A: `<role>` / `<role>-elevated` grammar (smallest change, keeps 4Shark's existing "baseline/elevated" language)
- Option B: `<role>-baseline` / `<role>-jit` grammar (adopts PAM-industry JIT/ZSP vocabulary explicitly)
- Option C: `<function>` / `<function>-mfa` grammar (cheapest migration — preserves the literal `-mfa` suffix pattern already hardcoded across scripts, `.envrc` files, and docs)
- Option D: retain `break-glass` for genuine outage/federation-failure use, introduce a separate `permissions-admin`/`permissions-admin-elevated` identity for the routine reactive-grant work — the only option that acts on the AWS break-glass/trigger mismatch (Finding 9) rather than leaving it as-is

(No recommendation — surface the candidates and their grounding; main and the engineer choose.)
