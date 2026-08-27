# SPIKE — Break-Glass Account MFA Enforcement Gaps

## How the community actually does this

Six practitioner-grounded patterns, each backed by an independently-verified source (evidence and verification blocks below — Findings 1.6, 1.7, 2.8, 2.9, 2.10, 2.11, 3.4, 4.5, P.1–P.6).

**1. The break-glass identity is kept OUTSIDE SSO/federation, on purpose, so an IdP outage cannot strand it.** Microsoft's Entra guidance ("These accounts should be cloud-only accounts... that aren't federated"); a widely-used AWS reference architecture, the Secure Environment Accelerator ("The use and creation of IAM users is highly discouraged, with one exception, break glass users", each requiring "a dedicated Yubikey"); an AWS-maintained reference implementation on GitHub ("a dedicated break glass IAM user provides emergency access when SSO systems are unavailable"); and HashiCorp's own HCP Terraform documentation ("we recommend creating and designating two accounts with owner permissions, sometimes referred to as break glass accounts... use these accounts to access the organization for troubleshooting using their username and password"). 4Shark already applies this to AWS root and GitHub (`ivonoide`, outside `@4shark.com.br` domain SSO) — but not to AWS's `ivo` IAM user's own MFA path, nor to Cloudflare and MongoDB Atlas, all three of which are reached through the same Google-federated session.

**2. Routine infrastructure-as-code is NOT run as the break-glass or most-privileged identity.** Charles Sieg: "Running Terraform against the management account is a security concern... The management account should be a locked vault, not a daily driver." AWS's own DevOps Guidance frames a break-glass role as something reached for to "troubleshoot issues with automation tooling" — the tool for when automation breaks, not the automation itself.

**3. Operating discipline is "sign in only when the sky is falling," monitored on every touch, tested rarely.** A named practitioner newsletter: "You never touch it unless the sky is falling"; monitoring is turned up so "any login screams red alerts everywhere," and functional validation happens only "once a year during the day."

**4. No practitioner account of forcing Cloudflare or MongoDB Atlas to re-authenticate against an existing Google session was found**, despite a genuine search — several of the most relevant Cloudflare Community and AWS re:Post threads on exactly this session topic returned HTTP 403 and could not be read.

**5. 4Shark's IAM Identity Center instance is externally federated to Google Workspace, and AWS's own documentation states its MFA settings are then unavailable, full stop — not merely weaker.** A session-less request to the AWS access portal start URL redirects straight to Google's sign-in page — the same redirect-based test general SSO troubleshooting guidance documents for identifying a configured IdP. AWS's own IAM Identity Center documentation is explicit about the consequence: "If you're using an external IdP, the Multi-factor authentication section will not be available. Your external IdP manages MFA settings, rather than IAM Identity Center managing them." Moving a privileged Terraform apply onto Identity Center in this configuration puts it behind Google's own MFA and session policy — the same 14-day-default session already implicated in Cloudflare and MongoDB Atlas — not behind anything AWS controls.

**6. The practitioner-documented way to keep privileged AWS access independent of any IdP is a hardware key's own OATH-TOTP applet, enrolled as a plain IAM "virtual MFA device."** AWS's enrollment path for a virtual MFA device accepts any RFC 6238 TOTP generator via a QR code or secret key — it is not restricted to a phone app, and it is a different AWS product category from the vendor-preshared "hardware TOTP token." Practitioners document the concrete workflow on a YubiKey: `ykman oath accounts add --oath-type TOTP --touch ...` to enroll, then `aws sts get-session-token --serial-number ... --token-code $(ykman oath accounts code ...)` to authenticate — touch required, so a code cannot be produced without the physical key present. This is the same mechanism 4Shark's break-glass YubiKeys already carry for GitHub.

## Investigation question

4Shark's documented break-glass model (`~/.claude/docs/runbooks/engineer-access/BREAK-GLASS.md`) assumes hardware-FIDO2-only access to the break-glass identity across AWS, Cloudflare, MongoDB Atlas, and GitHub. An audit found two contradictions of that guarantee:

1. An IAM user `ivo@4shark.com.br` (distinct from AWS root) holds one active static access key (created 2026-03-10) with zero MFA devices, and the `identity/` Terraform stack — which defines every engineer's IAM permissions — is pinned by `guard.tf` to that user's `user_id`, so the stack governing all permissions is applied with a long-lived key and no second factor.
2. The engineer reports that `admin.google.com` prompts for the YubiKey while Gmail for the same account does not, and that from a persistent Gmail session, SSO into privileged surfaces reportedly proceeds without a fresh hardware-key prompt.

Four questions, refined on verified ground truth from the `identity/` Terraform stack (AWS access is IAM Identity Center; Google Workspace is confirmed as the external IdP for that Identity Center instance and for Cloudflare and MongoDB Atlas's SAML federation):

- **Q1** — Should a break-glass/emergency identity hold programmatic credentials (a static access key) at all?
- **Q2** — Can AWS require MFA, specifically a hardware key, for *programmatic* access, given that Identity Center's own MFA settings do not apply here?
- **Q3** — How does Google Workspace's session-length architecture explain the Admin-console-prompts / Gmail-doesn't-prompt vector, and what does the community say about a break-glass identity having a routinely used mailbox at all?
- **Q4** (re-scoped) — For the two service providers that actually federate from Google in 4Shark (Cloudflare Super Administrator, MongoDB Atlas Organization Owner), can the SP side force fresh IdP authentication independent of an existing Google session, and can either cap federated session lifetime on its own?
- **Secondary** — What does the community say about three orphaned SAML providers in the AWS account (`JumpCloud`, `JumpCloudDeveloper`, `ArchBit` — none currently trusted by any IAM role)?

**4Shark's IAM Identity Center instance is externally federated to Google Workspace** — a session-less request to the AWS access portal start URL redirects to Google's sign-in page (Finding P.1). This rules out routing the `identity/` stack's apply through `aws sso login`: doing so would inherit Google's own session and MFA policy (Finding P.3), not strengthen AWS's. "Item 1 — Concrete remediation" below designs the fix on that basis, keeping the applying identity independent of Identity Center and Google entirely.

## Sources consulted

- [AWS Well-Architected — SEC01-BP02](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_securely_operate_aws_account.html) — root-user access-key and MFA guidance; cites CIS 1.4/1.5/1.6
- [AWS IAM — Secure API access with MFA](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_mfa_configure-api-require.html) — `GetSessionToken`/`AssumeRole` MFA mechanics
- [AWS IAM — Global condition context keys (`aws:MultiFactorAuthPresent`)](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_condition-keys.html)
- [AWS IAM — Multi-factor authentication in IAM](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_mfa.html) — MFA types, FIDO2/passkey console-only limitation, `aws login`
- [AWS CLI — Login for AWS local development using console credentials](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html) — `aws login` mechanics (CLI ≥ 2.32.0)
- [AWS IAM — Troubleshoot Passkeys and FIDO Security Keys](https://docs.aws.amazon.com/IAM/latest/UserGuide/troubleshoot_mfa-fido.html)
- [AWS IAM — Security best practices in IAM](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html) — unused-credential review guidance
- [AWS IAM — Assign a virtual MFA device in the AWS Management Console](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_mfa_enable_virtual.html) — any RFC 6238 TOTP app qualifies, enrollment via QR code / secret key
- [AWS IAM Identity Center — Prompt users for MFA](https://docs.aws.amazon.com/singlesignon/latest/userguide/mfa-getting-started.html) — always-on vs context-aware modes; the "external IdP: Multi-factor authentication section will not be available" note
- [AWS IAM Identity Center — Configure MFA device enforcement](https://docs.aws.amazon.com/singlesignon/latest/userguide/how-to-configure-mfa-device-enforcement.html)
- [AWS IAM Identity Center — Choose MFA types for user authentication](https://docs.aws.amazon.com/singlesignon/latest/userguide/how-to-configure-mfa-types.html) — the FIDO2-only vs authenticator-app selector (native directory only)
- [AWS IAM Identity Center — Available MFA types](https://docs.aws.amazon.com/singlesignon/latest/userguide/mfa-types.html) — confirms FIDO2 works for both console and CLI v2 (native directory only)
- [AWS CLI — Configuring IAM Identity Center authentication with the AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html) — `aws sso login` browser flow
- [csf.tools — NIST SP 800-53 r5 AC-2(2)](https://csf.tools/reference/nist-sp-800-53/r5/ac/ac-2/ac-2-2/) — control text and scope limitation
- [AWS Well-Architected — [AG.SAD.5] Implement break-glass procedures](https://docs.aws.amazon.com/wellarchitected/latest/devops-guidance/ag.sad.5-implement-break-glass-procedures.md) — break-glass roles for troubleshooting automation tooling
- [Microsoft — Manage emergency access admin accounts](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/security-emergency-access) — Entra ID break-glass guidance, cloud-only/non-federated requirement
- [Yubico — Simplifying break-glass account security with YubiKeys](https://www.yubico.com/blog/simplifying-break-glass-account-security-with-yubikeys/) — hardware-key redundancy guidance (already cited in the 4Shark runbook)
- [AWS Samples (GitHub) — aws-cross-account-break-glass-example](https://github.com/aws-samples/aws-cross-account-break-glass-example) — reference implementation: local IAM user, not federated
- [AWS Secure Environment Accelerator — Authentication & Authorization architecture](https://aws-samples.github.io/aws-secure-environment-accelerator/latest/architectures/sensitive/auth/) — "highly discouraged... one exception, break glass users", dedicated YubiKey per user
- [Charles Sieg — Terraform + CloudFormation StackSets: Deploying IAM Roles Across Every Account in Your Organization](https://charlessieg.com/articles/terraform-cloudformation-stackset-iam-role-organization.html) — "management account should be a locked vault, not a daily driver"
- [HashiCorp Developer — Configure and manage single sign-on in HCP Terraform](https://developer.hashicorp.com/terraform/cloud-docs/users-teams-organizations/single-sign-on) — break-glass accounts recommended before enabling SSO, username+password fallback
- [HashiCorp Developer — Manage API tokens for HCP Terraform](https://developer.hashicorp.com/terraform/cloud-docs/users-teams-organizations/api-tokens) — team/org tokens (not individual accounts) for routine automation
- [Intranet From The Trenches (Substack) — Break-Glass Accounts Explained](https://intranetfromthetrenches.substack.com/p/break-glass-accounts-explained-your-secret-superhero-when-everything-goes-wrong) — operating discipline: bury in a vault, monitor every sign-in, test once a year
- [Google Workspace — Set session length for Google Cloud services](https://knowledge.workspace.google.com/admin/security/set-session-length-for-google-cloud-services) — Cloud console/gcloud/OAuth-scope session control, reauthentication method options
- [Google Workspace — Set session length for Google services](https://knowledge.workspace.google.com/admin/security/set-session-length-for-google-services) — the general 14-day web-session default, Admin console's fixed 1-hour exception
- [Cloudflare One — Session management](https://developers.cloudflare.com/cloudflare-one/access-controls/access-settings/session-management/) — Zero Trust Access global session duration
- [Cloudflare One — Independent MFA](https://developers.cloudflare.com/cloudflare-one/access-controls/access-settings/independent-mfa/) — scope limited to Access applications, not dashboard/Super Administrator
- [MongoDB Atlas — Advanced Options for Federated Authentication](https://www.mongodb.com/docs/atlas/security/federation-advanced-options/) — confirms absence of session/re-auth controls in the documented feature set
- [Obsidian Security — SSO Bypass: How Attackers Circumvent Single Sign-On](https://www.obsidiansecurity.com/blog/sso-bypass-attack-techniques) — general SSO-session/MFA-bypass risk class; sustains the "break-glass fallback becomes a permanent backdoor" framing
- [detection.fyi — AWS IAM SAML Provider Created (persistence detection rule)](https://detection.fyi/elastic/detection-rules/integrations/aws/persistence_iam_saml_provider_created/) — SAML provider as a persistence vector
- [GitHub — boto/botocore Discussion #3581](https://github.com/boto/botocore/discussions/3581) — no direct API to describe an Identity Center instance's identity provider
- [AWS IAM Identity Center — External identity providers](https://docs.aws.amazon.com/singlesignon/latest/userguide/manage-your-identity-source-idp.html) — redirect behavior under federation
- [dev.to (AWS Builders) — Using YubiKey TOTP for AWS CLI Multi-factor Authentication](https://dev.to/aws-builders/using-yubikey-totp-for-aws-cli-multi-factor-authentication-4224) — the `ykman oath accounts add --touch` / `aws sts get-session-token` workflow
- [Erlend Ekern — Hardware security keys for AWS IAM users](https://blog.ekern.me/2023/10/01/hardware-security-keys-for-aws-iam-users.html) — confirms FIDO2 console-only, OATH-TOTP as the CLI-reachable alternative
- `~/.claude/docs/runbooks/engineer-access/BREAK-GLASS.md` — the current documented 4Shark model (read in full)
- `~/Projects/4Shark/terraform/identity/sso.tf:10-19,116-123` — AWS Identity Center setup, `session_duration = "PT1H"` on the `AdministratorAccess` permission set, the standing account assignment
- `~/Projects/4Shark/terraform/identity/cloudflare_sso.tf:1-12` — Google SAML IdP registration in Cloudflare (`idpid=C00op2v5t`)
- `~/Projects/4Shark/terraform/identity/mongodb_federation.tf:1-24` — Google SAML IdP registration in MongoDB Atlas (same `idpid`)
- `~/Projects/4Shark/terraform/identity/guard.tf:1-21` — the postcondition pinning `identity/` stack applies to `user_id == "AIDAV46EH4QJBIBQ7ATEM"`
- `~/Projects/4Shark/terraform/identity/.envrc:1-13` — `export AWS_PROFILE=ivo` plus the provider credential exports for Cloudflare/GitHub/MongoDB Atlas/Rollbar

## Findings

### Preliminary — 4Shark's Identity Center is federated to Google Workspace, and that closes off the Identity Center path

#### Finding P.1 — Empirical determination: the AWS access portal start URL redirects to Google

**Evidence:** A session-less request to `https://d-906791aeb2.awsapps.com/start` (carrying no engineer session) redirects to `https://accounts.google.com`, presenting "Sign in — Use your Google Account."

**Source:** direct browser observation (coordinator-run), corroborated by AWS's own documented behavior for this configuration — quote: "Regardless of how you provision users, IAM Identity Center redirects the AWS Management Console, command line interface, and application authentication to your external IdP." (Source: [AWS IAM Identity Center — External identity providers](https://docs.aws.amazon.com/singlesignon/latest/userguide/manage-your-identity-source-idp.html).)

**Significance:** this resolves the conflict between two pieces of local evidence — an inconclusive `ExternalIds`-absence check and a design document's claim — in favor of the design document: 4Shark's IAM Identity Center instance is externally federated to Google Workspace, matching what `terraform/identity/README.md:192-196` states. The `ExternalIds`-absence check was consistent with either interpretation because manual (non-SCIM) provisioning under an external IdP is itself an ordinary, documented pattern — quote: "The SAML protocol does not provide a way to query the IdP to learn about users and groups. Therefore, you must make IAM Identity Center aware of those users and groups by provisioning them into IAM Identity Center. ... you can configure Provision users and groups from an external identity provider using SCIM ..., or use Manual provisioning." (Source: same page as above.)

**Verification:** the redirect observation is coordinator-supplied ground truth from a direct browser test, not a fetched URL. The corroborating AWS quotes were fetched (`manage-your-identity-source-idp.html`) / quote checked / substrings "IAM Identity Center redirects the AWS Management Console, command line interface, and application authentication to your external IdP" and "The SAML protocol does not provide a way to query the IdP to learn about users and groups" both confirmed present.

#### Finding P.2 — This redirect-based determination technique is a documented pattern in general SSO troubleshooting

**Evidence:** general SSO-testing guidance recommends validating a federated login by requesting the protected resource from a session-less (incognito/private) browser state and observing that the request "should automatically redirect you to the configured SSO provider... This redirect behavior reveals the configured identity provider."

**Source:** search-aggregated general SSO-troubleshooting guidance; the specific vendor help-center page originally surfaced for this claim (Keepit) could not be independently fetched and quote-verified (its content had moved to a different URL at fetch time), so this finding is marked **UNVERIFIED** per the citation discipline and does not sustain a standalone claim on its own.

**Significance:** the technique behind Finding P.1 (a session-less request to the access-portal URL, observing the redirect target) matches a general pattern the SSO-administration community documents for exactly this purpose — identifying which IdP a service is configured against, without needing API/console access to the service's own configuration. This is offered as corroborating context for why the technique is reliable, not as the basis for any conclusion; Finding P.1's conclusion rests on the direct observation plus AWS's own documented redirect behavior, both independently verified.

**Verification:** UNVERIFIED — the specific source page could not be fetched with its content intact; reported as a search-aggregated pattern, not an attributed quote.

#### Finding P.3 — AWS states plainly that Identity Center's own MFA settings do not apply under external federation — not merely that they are weaker

**Evidence:**

> "If you're using an external IdP, the **Multi-factor authentication** section will not be available. Your external IdP manages MFA settings, rather than IAM Identity Center managing them."

**Source:** [AWS IAM Identity Center — Prompt users for MFA](https://docs.aws.amazon.com/singlesignon/latest/userguide/mfa-getting-started.html).

**Significance:** this is the direct answer to whether Identity Center's always-on/FIDO2-only settings are a live control point for 4Shark: they are not. The console section that configures them "will not be available" at all under Finding P.1's confirmed configuration — AWS hands the entire MFA decision to Google. This means `aws sso login` (the CLI path that would reuse Identity Center's console MFA) authenticates through whatever Google itself requires at that moment, which is governed by the 14-day-default "Google services" session (Finding 3.2), not by any AWS-side setting. Moving the `identity/` stack's apply onto Identity Center would therefore not close the gap the runbook's threat model targets — it would relocate the gap from "a static access key with zero MFA" to "a session inherited from Gmail," which is arguably the same class of problem the engineer's original report described.

**Verification:** URL fetched (`mfa-getting-started.html`) / quote checked / substring "If you're using an external IdP, the Multi-factor authentication section will not be available. Your external IdP manages MFA settings, rather than IAM Identity Center managing them." confirmed present.

#### Finding P.4 — Two AWS re:Post threads asking this exact question (enforcing MFA under Identity Center + external IdP) were found but could not be read

**Evidence:** two threads, "How to Enforce 2FA for AWS IAM Identity Center with Google Workspace as an External IdP" and "Require MFA when using SSO + External idP," were located by search as directly on-topic community discussions; both returned HTTP 403 on fetch.

**Source:** `repost.aws` (URLs named in the search results; neither independently fetched).

**Significance:** this is the same pattern as Finding 4.5 (Cloudflare Community threads inaccessible) — the exact practitioner discussion exists and is on-topic, but this spike's tooling could not read it. An authenticated read of these two threads is a concrete, not-yet-exhausted next step, alongside the Cloudflare threads already named in Finding 4.5.

**Verification:** both URLs attempted, both returned HTTP 403; no content quoted because none was retrieved.

#### Finding P.5 — AWS's virtual MFA device accepts any RFC 6238 TOTP generator — a category distinct from AWS's vendor-preshared "hardware TOTP token" product

**Evidence:**

> "To do this, install a mobile app that is compliant with RFC 6238, a standards-based TOTP (time-based one-time password) algorithm. These apps generate a six-digit authentication code." ... "AWS requires a virtual MFA app that produces a six-digit OTP." ... enrollment: "IAM generates and displays configuration information for the virtual MFA device, including a QR code graphic... use the app to scan the QR code" or "type the secret key into your MFA app."

**Source:** [AWS IAM — Assign a virtual MFA device in the AWS Management Console](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_mfa_enable_virtual.html).

**Significance:** nothing in this enrollment path restricts the "app" to a phone or to a vendor-approved product — any device that implements RFC 6238 and can either scan the displayed QR code or accept the displayed secret key qualifies. This is a materially different AWS product category from the "hardware TOTP token" product ("You can only use tokens that have their unique token seeds shared securely with AWS... Tokens purchased from other sources will not function with IAM"), which requires a specific vendor-preshared device. A YubiKey's own OATH-TOTP applet (via Yubico Authenticator or `ykman`) is exactly this kind of RFC 6238 generator, and enrolling it means scanning AWS's own-generated QR code into the key — not purchasing a pre-provisioned device from AWS's approved list.

**Verification:** URL fetched (`id_credentials_mfa_enable_virtual.html`) / quote checked / substrings "install a mobile app that is compliant with RFC 6238", "AWS requires a virtual MFA app that produces a six-digit OTP", and the QR-code/secret-key enrollment description all confirmed present.

#### Finding P.6 — Practitioners document the concrete YubiKey-OATH-TOTP-as-IAM-MFA workflow, including the touch requirement and its use with `GetSessionToken`

**Evidence:**

> Enrollment: `ykman oath accounts add --issuer AWS --oath-type TOTP --digits 6 --algorithm SHA1 --touch example-user`, followed by `aws iam enable-mfa-device --user-name example-user --serial-number ${MFA_ARN} --authentication-code1 ${CODE1} --authentication-code2 ${CODE2}`.
>
> "If you added `--touch` option, you need to be present."
>
> Authenticating: `aws sts get-session-token --serial-number ${MFA_ARN} --token-code $(ykman oath accounts code example-user-cli | grep -oE '[0-9]{6}$')`

**Source:** [dev.to (AWS Builders) — Using YubiKey TOTP for AWS CLI Multi-factor Authentication](https://dev.to/aws-builders/using-yubikey-totp-for-aws-cli-multi-factor-authentication-4224).

Corroborated on FIDO2's console-only limitation, from an independent practitioner blog:

> "AWS supports using FIDO certified security keys only in the AWS Management Console. Using FIDO Certified security keys for MFA is not supported in the AWS CLI and AWS API."

**Source:** [Erlend Ekern — Hardware security keys for AWS IAM users](https://blog.ekern.me/2023/10/01/hardware-security-keys-for-aws-iam-users.html).

**Significance:** this is a fully practitioner-verified, concrete path to requiring physical possession of the hardware key for `terraform apply` against `identity/`, without touching Identity Center or Google at all. The `--touch` flag means a code can only be generated with the physical key present (not merely "known," the way a copied TOTP secret would be) — the same possession guarantee 4Shark's runbook already relies on for GitHub's TOTP-on-YubiKey path (`BREAK-GLASS.md:52-53`). `aws sts get-session-token` is the correct API for this, and it is IAM-user-native, requiring no CLI version newer than what 4Shark already runs and no browser step.

**Verification:** First URL fetched (`dev.to/aws-builders/...`) / quote checked / substrings "ykman oath accounts add --issuer AWS --oath-type TOTP", "you need to be present", and the `get-session-token`/`ykman oath accounts code` command line all confirmed present. Second URL fetched (`blog.ekern.me/...`) / quote checked / substring "AWS supports using FIDO certified security keys only in the AWS Management Console. Using FIDO Certified security keys for MFA is not supported in the AWS CLI and AWS API." confirmed present.

---

### Q1 — Should a break-glass account have programmatic credentials at all?

#### Finding 1.1 — AWS Well-Architected: root-user access keys are a documented anti-pattern, unconditionally

**Evidence:**

> "Do not create access keys for the root user. If access keys exist, remove them (CIS 1.4).
> 1. Eliminate any long-lived programmatic credentials (access and secret keys) for the root user.
> 2. If root user access keys already exist, you should transition processes using those keys to use temporary access keys from an AWS Identity and Access Management (IAM) role, then delete the root user access keys."

**Source:** [AWS Well-Architected — SEC01-BP02](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_securely_operate_aws_account.html), implementation step 2.

**Significance:** This is written for the AWS *root* user specifically, not for an IAM user acting as a break-glass identity — 4Shark's `ivo@4shark.com.br` IAM user is a different principal type from root. The applicability to 4Shark's case is by analogy (an emergency-only, maximally-privileged, rarely-used identity), not a direct statement about IAM-user break-glass accounts. The stated remediation path — "transition processes using those keys to use temporary access keys from an IAM role" — describes the general shape of the fix; Finding P.6 supplies the concrete IAM-user-native equivalent (temporary keys from `GetSessionToken` rather than a role, since a role would mean Identity Center, which Finding P.3 rules out).

**Verification:** URL fetched (`sec_securely_operate_aws_account.html`) / quote checked / substring "Do not create access keys for the root user. If access keys exist, remove them (CIS 1.4)." confirmed present in the fetched implementation-guidance section.

#### Finding 1.2 — Microsoft Entra: emergency accounts are interactive-login-only by design; the guidance never contemplates an API credential

**Evidence:**

> "Choose one of these passwordless authentication methods for your emergency access accounts. These methods satisfy the mandatory multifactor authentication requirements.
> - Passkey (FIDO2) (Recommended)
> - Certificate-based authentication..."
>
> "The device or credential must not expire or be in scope of automated cleanup due to lack of use."
>
> "Use strong authentication for your emergency access accounts and make sure it doesn't use the same authentication methods as your other administrative accounts."

**Source:** [Microsoft — Manage emergency access admin accounts](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/security-emergency-access).

**Significance:** Every configuration requirement Microsoft lists is scoped to an *interactive sign-in* identity. Microsoft's model has no notion of the emergency account authenticating a script or an infrastructure-as-code tool — the document is silent on programmatic/API access because the account is not designed to have any.

**Verification:** URL fetched / quote checked / substrings "Choose one of these passwordless authentication methods", "must not expire or be in scope of automated cleanup", and "doesn't use the same authentication methods as your other administrative accounts" all confirmed present in the fetched page.

#### Finding 1.3 — NIST AC-2(2) governs automated account *lifecycle*, not credential *type*, and explicitly does not apply where automation cannot reach the account

**Evidence:**

> Control statement: "Automatically [remove, disable] temporary and emergency accounts after [organization-defined time period]."
>
> "When the OT (e.g., field devices) cannot support temporary or emergency accounts, this enhancement does not apply."

**Source:** [csf.tools — NIST SP 800-53 r5 AC-2(2)](https://csf.tools/reference/nist-sp-800-53/r5/ac/ac-2/ac-2-2/).

**Significance:** AC-2(2) is the control 4Shark's runbook cites as grounding the break-glass model, but its actual content is about *automatically disabling* temporary/emergency accounts after a time period — the opposite of what 4Shark's break-glass account needs (it must persist indefinitely, which the runbook's own "Policy Exclusions" section already carves out). AC-2(2) says nothing about whether the account may hold programmatic credentials.

**Verification:** URL fetched / quote checked / substrings "Automatically [remove, disable] temporary and emergency accounts" and "this enhancement does not apply" confirmed present.

#### Finding 1.4 — Yubico's own break-glass guidance is silent on programmatic access; it addresses key redundancy only

**Evidence:** The Yubico blog post cited in 4Shark's own runbook (`BREAK-GLASS.md:80-81`, the "two-token minimum" reference) covers hardware-key redundancy and storage — it does not state a position on whether a break-glass identity should hold API keys or long-lived programmatic credentials.

**Source:** [Yubico — Simplifying break-glass account security with YubiKeys](https://www.yubico.com/blog/simplifying-break-glass-account-security-with-yubikeys/).

**Significance:** This is a "not found" result stated plainly: none of the four cited authoritative sources for 4Shark's break-glass model (NIST AC-2(2), CIS, AWS Well-Architected, Yubico) directly addresses "should a break-glass IAM user have a static access key" as its own question.

**Verification:** URL fetched. No verbatim quote is claimed for the "silent on X" observation — this is a negative finding, not an attributed quote.

#### Finding 1.5 — 4Shark's own `guard.tf` already encodes the principle Finding 1.1 argues for, but the underlying identity does not meet it

**Evidence:**

```hcl
# ~/Projects/4Shark/terraform/identity/guard.tf:4-8
data "aws_caller_identity" "guard" {
  lifecycle {
    postcondition {
      condition     = self.user_id == "AIDAV46EH4QJBIBQ7ATEM"
```

**Source:** `terraform/identity/guard.tf:4-8`, read directly.

**Significance:** The stack that defines every engineer's IAM permissions is deliberately restricted to being applied only by the break-glass identity — a sound design. But the mechanism enforcing this is a `user_id` match on an IAM user whose only credential (per the audit) is a static access key with zero MFA devices. Per Finding P.3, this postcondition never needs to change to reference an Identity Center principal instead — the fix in "Item 1" upgrades the SAME `user_id`'s credential, not the identity the guard checks.

**Verification:** File read directly at the cited path and line range; content quoted verbatim above.

#### Finding 1.6 — Independent practitioner and vendor-reference sources converge: the break-glass identity is deliberately kept OUTSIDE SSO/federation

**Evidence:**

> "Native IAM users. The use and creation of IAM users is highly discouraged, with one exception, break glass users." ... "each IAM break glass user requires a dedicated Yubikey" ... "Use cases for break glass access include failure of the organizations IdP, an incident involving the organizations IdP, a failure of AWS SSO, or a disaster involving the loss of an organization's entire cloud or IdP teams."

**Source:** [AWS Secure Environment Accelerator — Authentication & Authorization architecture](https://aws-samples.github.io/aws-secure-environment-accelerator/latest/architectures/sensitive/auth/).

Corroborated independently by an AWS-maintained reference implementation:

> "For organizations using IAM Identity Center with external Identity Providers, a dedicated break glass IAM user provides emergency access when SSO systems are unavailable."

**Source:** [AWS Samples (GitHub) — aws-cross-account-break-glass-example](https://github.com/aws-samples/aws-cross-account-break-glass-example), README.

Corroborated a third time, on a different platform, by HashiCorp's own documentation for HCP Terraform:

> "Before you configure SSO for your organization, we recommend creating and designating two accounts with owner permissions, sometimes referred to as break glass accounts." ... "If you encounter problems with your SSO provider that prevent you from logging in with SSO credentials, use these accounts to access the organization for troubleshooting using their username and password."

**Source:** [HashiCorp Developer — Configure and manage single sign-on in HCP Terraform](https://developer.hashicorp.com/terraform/cloud-docs/users-teams-organizations/single-sign-on).

**Significance:** On the evidence from three independent, differently-governed sources, a break-glass identity is deliberately kept outside SSO/federation, precisely because federating it through the IdP would make it fail in exactly the scenario it exists for. This is the SAME architectural gap on the AWS side that already exists for Cloudflare and MongoDB Atlas (Finding P.1/P.3): 4Shark's `ivo` IAM user is itself outside Identity Center's federation for its own credential (it authenticates with an access key, not through Google), but that credential currently carries no MFA — the fix in "Item 1" is to strengthen that already-separate IAM-user path, not to move it onto the federated one. AWS root and GitHub already fully match this pattern; Cloudflare and MongoDB Atlas do not.

**Verification:** First URL fetched (`aws-secure-environment-accelerator/.../auth/`) / re-fetched for self-check / quote checked / substrings "The use and creation of IAM users is highly discouraged, with one exception, break glass users.", "each IAM break glass user requires a dedicated Yubikey", and "Use cases for break glass access include failure of the organizations IdP" all confirmed present on both fetches. Second URL fetched (`github.com/aws-samples/aws-cross-account-break-glass-example`) / re-fetched for self-check / quote checked / substring "a dedicated break glass IAM user provides emergency access when SSO systems are unavailable" confirmed present on both fetches. Third URL fetched (`developer.hashicorp.com/.../single-sign-on`) / quote checked / substrings "creating and designating two accounts with owner permissions, sometimes referred to as break glass accounts" and "use these accounts to access the organization for troubleshooting using their username and password" both confirmed present.

#### Finding 1.7 — AWS's own DevOps Guidance frames a break-glass role as the tool you reach for when automation tooling breaks, not as the identity that runs automation

**Evidence:**

> "Create break-glass roles and users you can assume control of during emergencies that are able to bypass established controls, update guardrails, **troubleshoot issues with automation tooling**, or remediate security and operational issues that may occur."

**Source:** [AWS Well-Architected — [AG.SAD.5] Implement break-glass procedures](https://docs.aws.amazon.com/wellarchitected/latest/devops-guidance/ag.sad.5-implement-break-glass-procedures.md).

**Significance:** The phrase "troubleshoot issues with automation tooling" only makes sense if the normal case is that automation tooling runs under something *other than* the break-glass identity. This is corroborating context for Finding 2.8/2.9 (routine IaC should not run as the break-glass identity), independent of Finding P.3.

**Verification:** URL fetched (`ag.sad.5-implement-break-glass-procedures.md`) / quote checked / substring "troubleshoot issues with automation tooling" confirmed present.

---

### Q2 — Can AWS require MFA, specifically a hardware key, for programmatic access?

Findings 2.1–2.3 concern the legacy IAM-user `GetSessionToken` path and hold regardless of federation. Findings 2.4–2.7 describe IAM Identity Center's own MFA mechanics — kept here for reference and because Finding 2.7's FIDO2-and-CLI mechanism is real in general, but **none of Findings 2.4–2.7 is reachable for 4Shark's `identity/` stack**, because Finding P.3 establishes that Identity Center's MFA settings are unavailable once Google is the external IdP (Finding P.1). Findings 2.10–2.11 supply the path that actually applies. Findings 2.8–2.9 address a separate, federation-independent question: whether the break-glass identity should be the one applying `identity/` at all.

#### Finding 2.1 — `aws:MultiFactorAuthPresent` does not exist at all for long-term credentials, and does not propagate through `AssumeRole`

**Evidence:**

> "Existence—To simply verify that the user did authenticate with MFA, check that the `aws:MultiFactorAuthPresent` key is True in a Bool condition. **The key is only present when the user authenticates with short-term credentials. Long-term credentials, such as access keys, do not include this key.**"

**Source:** [AWS IAM — Secure API access with MFA](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_mfa_configure-api-require.html).

Corroborated by the global condition-keys reference:

> "This condition key is not present for federated identities or requests made using access keys to sign AWS CLI, AWS API, or AWS SDK requests."

**Source:** [AWS IAM — Global condition context keys](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_condition-keys.html).

**Significance:** A policy condition on `aws:MultiFactorAuthPresent` cannot gate the IAM user `ivo@4shark.com.br`'s static access key at all — the condition key is structurally absent from that credential type. The key would first have to stop being a long-term access key, which is exactly what "Item 1" does.

**Verification:** URL fetched (`id_credentials_mfa_configure-api-require.html`) / quote checked / substring "The key is only present when the user authenticates with short-term credentials. Long-term credentials, such as access keys, do not include this key." confirmed present. Second URL fetched (`reference_policies_condition-keys.html`) / quote checked / substring "This condition key is not present for federated identities or requests made using access keys" confirmed present.

#### Finding 2.2 — Under the IAM-user path, `GetSessionToken` MFA explicitly excludes FIDO2/passkey/security-key devices, leaving TOTP as the only device type it accepts

**Evidence:**

> "You cannot use MFA-protected API access with U2F security keys." ... "You cannot pass the MFA information for a security key or passkey to AWS STS API operations to request temporary credentials." ... "You can enable a passkey or security key from the AWS Management Console only, not from the AWS CLI or AWS API."

**Source:** [AWS IAM — Secure API access with MFA](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_mfa_configure-api-require.html) and [AWS IAM — Multi-factor authentication in IAM](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_mfa.html).

**Significance:** For an IAM user, `aws sts get-session-token` cannot accept a FIDO2 hardware key's assertion — only a TOTP code (virtual or hardware) can be passed. This is a hard product limitation. Combined with Finding P.5/P.6, this establishes the CEILING and the PATH at once: TOTP is the only device type this API accepts, and a YubiKey's own OATH-TOTP applet is a fully valid TOTP device for it.

**Verification:** First URL fetched / quote checked / substring "You cannot use MFA-protected API access with U2F security keys." confirmed present. Second URL fetched / quote checked / substrings "You cannot pass the MFA information for a security key or passkey to AWS STS API operations" and "You can enable a passkey or security key from the AWS Management Console only, not from the AWS CLI or AWS API." both confirmed present.

#### Finding 2.3 — `aws login` (CLI ≥ 2.32.0) reuses console FIDO2 for CLI credentials, but for 4Shark's `ivo` user this means reusing Google's federated console sign-in, not AWS's own

**Evidence:**

> "You can use your existing AWS Management Console sign-in credentials for programmatic access to AWS services. After a browser-based authentication flow, AWS generates temporary credentials..." ... "You can authenticate using root credentials created during initial account set up, an IAM user, or a federated identity from your identity provider."

**Source:** [AWS CLI — Login for AWS local development using console credentials](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html).

**Significance:** This mechanism is real and does support FIDO2. For `ivo` specifically, which platform this reuses depends on how `ivo` signs into the AWS console today: if `ivo` has its OWN IAM-user console credentials (username+password, independent of Google), `aws login` would reuse THAT sign-in and could carry FIDO2 registered directly on the IAM user. If `ivo`'s only console access is via Identity Center/Google (as `terraform/identity/README.md:192-196` describes for ordinary engineers), `aws login` would reuse the Google-federated session instead, inheriting Finding P.3's limitation. This spike did not verify which applies to `ivo` specifically — see "what remains uncertain." Finding 2.10/2.11's `GetSessionToken` path does not carry this ambiguity, which is why it is offered as the primary concrete option in "Item 1."

**Verification:** URL fetched (`cli-configure-sign-in.html`) / quote checked / substring "You can authenticate using root credentials created during initial account set up, an IAM user, or a federated identity from your identity provider" confirmed present.

#### Finding 2.4 — 4Shark's actual AWS access is IAM Identity Center, with the `AdministratorAccess` permission set capped at a 1-hour session — reference only, not a remediation path

**Evidence:**

```hcl
# ~/Projects/4Shark/terraform/identity/sso.tf:10-14
resource "aws_ssoadmin_permission_set" "admin" {
  name             = "AdministratorAccess"
  session_duration = "PT1H"
```

**Source:** `terraform/identity/sso.tf:10-14`, read directly.

**Significance:** This 1-hour cap governs the ordinary engineer's Identity Center session, not `identity/`'s apply gate — and per Finding P.3, even for engineers this session's MFA strength is whatever Google enforces at the moment of re-authentication, not an AWS-side setting. Kept here for completeness; it does not bear on Item 1's fix.

**Verification:** File read directly at the cited path and line range; content quoted verbatim above.

#### Finding 2.5 — IAM Identity Center's "always-on"/"context-aware" MFA prompting modes exist, but are configured by the IdP, not AWS, once federated — reference only

**Evidence:** (See Finding P.3 for the operative quote: the entire "Multi-factor authentication" configuration section, including this always-on/context-aware choice, "will not be available" under an external IdP.)

**Source:** [AWS IAM Identity Center — Prompt users for MFA](https://docs.aws.amazon.com/singlesignon/latest/userguide/mfa-getting-started.html).

**Significance:** Identity Center's documented always-on/context-aware choice does not apply to 4Shark's configuration; the operative question for 4Shark is Google's own reauthentication policy (Findings 3.1–3.3), not this AWS setting.

**Verification:** see Finding P.3.

#### Finding 2.6 — Identity Center's FIDO2-only device-type restriction exists, but is not configurable by AWS once federated — reference only

**Evidence:** (See Finding P.3.) The MFA-type selector ("Security keys and built-in authenticators" vs "Authenticator apps") lives inside the same "Multi-factor authentication" section Finding P.3 establishes is unavailable under external federation.

**Source:** [AWS IAM Identity Center — Choose MFA types for user authentication](https://docs.aws.amazon.com/singlesignon/latest/userguide/how-to-configure-mfa-types.html).

**Significance:** kept for reference; not reachable for 4Shark's configuration.

**Verification:** see Finding P.3 for the operative quote establishing unavailability.

#### Finding 2.7 — `aws sso login`'s FIDO2 support is real, but for 4Shark it means authenticating through Google, not through AWS — reference only

**Evidence:**

> "All MFA types are supported for both browser-based console access as well as using the AWS CLI v2 with IAM Identity Center."

**Source:** [AWS IAM Identity Center — Available MFA types](https://docs.aws.amazon.com/singlesignon/latest/userguide/mfa-types.html).

**Significance:** true as a general statement about Identity Center, but for a Google-federated instance the "browser-based console access" this quote refers to IS the Google sign-in flow — so `aws sso login` for `identity/` would authenticate against Google's own MFA/session policy (14-day default, Finding 3.2), not against an AWS-configured always-on/FIDO2-only policy that Finding P.3 establishes does not exist here. This is why Finding P.3's conclusion — do not move `identity/`'s apply onto Identity Center — stands regardless of this finding's technical accuracy about Identity Center in general.

**Verification:** URL fetched (`mfa-types.html`) / quote checked / substring "All MFA types are supported for both browser-based console access as well as using the AWS CLI v2 with IAM Identity Center." confirmed present.

#### Finding 2.8 — A named practitioner source states plainly that running Terraform against the most-privileged account is itself a security concern, and recommends a delegated identity instead

**Evidence:**

> "Running Terraform against the management account is a security concern. The management account has god-mode permissions over the entire organization... The management account should be a locked vault, not a daily driver."

**Source:** [Charles Sieg — Terraform + CloudFormation StackSets: Deploying IAM Roles Across Every Account in Your Organization](https://charlessieg.com/articles/terraform-cloudformation-stackset-iam-role-organization.html).

**Significance:** This holds independently of Finding P.3 — `guard.tf`'s pin to the break-glass `user_id` makes that identity the daily driver for every IAM-permission change, which this finding argues against, regardless of how strongly that identity is itself authenticated.

**Verification:** URL fetched / re-fetched for self-check / quote checked / substrings "Running Terraform against the management account is a security concern. The management account has god-mode permissions over the entire organization." and "The management account should be a locked vault, not a daily driver." both confirmed present in the same paragraph on both fetches.

#### Finding 2.9 — HashiCorp's own token model separates routine automation identities from individual/privileged accounts, corroborating the same principle on a second platform

**Evidence:**

> "Organization API tokens are designed for creating and configuring workspaces and teams. We don't recommend using them as an all-purpose interface to HCP Terraform... For more routine interactions with workspaces, use team API tokens."

**Source:** [HashiCorp Developer — Manage API tokens for HCP Terraform](https://developer.hashicorp.com/terraform/cloud-docs/users-teams-organizations/api-tokens).

**Significance:** corroborates Finding 2.8's principle on a different platform.

**Verification:** URL fetched / quote checked / substrings "For more routine interactions with workspaces, use team API tokens" confirmed present.

#### Finding 2.10 — A YubiKey's OATH-TOTP applet is a valid, AWS-documented "virtual MFA device," distinct from AWS's vendor-preshared hardware TOTP token product

(Restated from Finding P.5/P.6 for Q2's own numbering — see those findings for the full evidence, source, and verification blocks.) **Significance for Q2 specifically:** this closes Finding 2.2's ceiling — the ONE device type `GetSessionToken` accepts (TOTP) can be hosted on the SAME physical hardware key 4Shark already issues for break-glass, via a documented, standard AWS enrollment path.

#### Finding 2.11 — `aws sts get-session-token` with a hardware-TOTP `ivo` device requires no CLI upgrade, no browser, and no dependency on Identity Center or Google

(Restated from Finding P.6 for Q2's own numbering.) **Significance for Q2 specifically:** among every path this spike examined, this is the ONLY one that (a) requires physical possession of the hardware key, (b) never touches Identity Center or Google Workspace at any point, and (c) works with the CLI version and API 4Shark already uses today (`GetSessionToken`, 4Shark's classic IAM-user CLI path). Finding 2.3's `aws login` may also achieve (a) and (b) — contingent on the unresolved question of which console credential `ivo` actually uses today — but only Finding 2.11's path is confirmed independent of that ambiguity.

---

### Q3 — Google Workspace session control and the routine-mailbox question

#### Finding 3.1 — The Admin console's 1-hour session is fixed and cannot be changed; it is a *different* session mechanism from the one governing Gmail

**Evidence:**

> "The session length for admins using the Google Admin console is set to one hour and can't be modified. After an hour, admins must sign in again."

**Source:** [Google Workspace — Set session length for Google services](https://knowledge.workspace.google.com/admin/security/set-session-length-for-google-services?hl=en).

**Significance:** `admin.google.com` forces a fresh sign-in (and therefore a fresh MFA/YubiKey challenge) every hour, unconditionally, by product design.

**Verification:** URL fetched / quote checked / substring confirmed present.

#### Finding 3.2 — The general "Google services" web session (which governs Gmail, and — per Finding P.3 — the session AWS `AdministratorAccess` re-federates against) defaults to 14 days, not 1 hour

**Evidence:**

> "The session-length control settings documented below affect sessions with all Google web properties that a user accesses while signed in." ... "By default, the web session length for Google services is 14 days."

**Source:** [Google Workspace — Set session length for Google services](https://knowledge.workspace.google.com/admin/security/set-session-length-for-google-services?hl=en).

**Significance:** Gmail, and every other "Google web property" the signed-in user visits, is governed by this 14-day session by default. This includes AWS `AdministratorAccess` re-authentication whenever the 1-hour Identity Center session expires (Finding 2.4) and Identity Center re-federates against Google (Finding P.3) — so the `PT1H` cap on the permission set buys far less than it appears to: the hour expires, but re-authentication is silently satisfied by whatever Google session is already open, for up to 14 days. This is configurable per organizational unit, so 4Shark could shorten it for the break-glass identity's own Google account specifically, without touching the AWS side at all.

**Verification:** URL fetched / quote checked / substrings confirmed present.

#### Finding 3.3 — "Google Cloud session control" (the 1–24 hour, security-key-capable reauthentication policy) is a *separate, narrower* setting that does not govern Gmail

**Evidence:**

> Google Cloud session control applies to: "The Google Cloud console," "The gcloud command-line tool (Cloud SDK)," and "Any applications... that require user authorization for Google Cloud scopes." ... "The minimum frequency allowed is 1 hour, and the maximum is 24 hours." Reauthentication method options: "Password" or "Security key."

**Source:** [Google Workspace — Set session length for Google Cloud services](https://knowledge.workspace.google.com/admin/security/set-session-length-for-google-cloud-services).

**Significance:** its documented scope is Google *Cloud* console/gcloud/OAuth-scoped applications — not Gmail, and not confirmed to include SAML-based federation into AWS Identity Center, Cloudflare, or MongoDB Atlas (SAML federation is a different mechanism from OAuth "Google Cloud scopes"). Tightening this setting would not, on the evidence gathered, close the session-reuse vector described in Finding 3.2.

**Verification:** URL fetched / quote checked / substrings confirmed present.

#### Finding 3.4 — A named practitioner source states the accepted operating discipline for a break-glass account directly: bury it, monitor every touch, test rarely

**Evidence:**

> "It's one (or usually two) super-powered cloud-only admin accounts you create once, give global admin rights, strip all the normal MFA and Conditional Access stuff off on purpose, and then basically bury in a vault." ... "You never touch it unless the sky is falling." ... "turn on crazy monitoring so any login screams red alerts everywhere" ... "treat any sign-in as a potential incident—even if it's you testing" ... tested "once a year during the day so you know it still works."

**Source:** [Intranet From The Trenches (Substack) — Break-Glass Accounts Explained](https://intranetfromthetrenches.substack.com/p/break-glass-accounts-explained-your-secret-superhero-when-everything-goes-wrong).

**Significance:** this directly answers whether the fix is "cap the session at 10 minutes" or "don't sign in routinely at all," in favor of the stronger claim. Given Finding 3.2's reach into AWS access, this discipline is not only about Gmail hygiene — an unattended, long-lived Google session on this account is a live path to AWS `AdministratorAccess`, not merely to Cloudflare/Atlas.

**Verification:** URL fetched / re-fetched for self-check / quote checked / substrings confirmed present on both fetches.

---

### Q4 (re-scoped) — Can Cloudflare or MongoDB Atlas force fresh Google authentication independent of the existing session?

#### Finding 4.1 — Neither Cloudflare's Dashboard SSO nor MongoDB Atlas's federated-authentication documentation states a mechanism for the service provider to force fresh IdP authentication independent of an existing Google session

**Evidence:** MongoDB Atlas's "Advanced Options for Federated Authentication" page documents only role assignment, domain restriction, "Bypass SAML Mode," and membership restriction — no session/ForceAuthn control. Cloudflare's Dashboard SSO documentation is scoped to SSO *setup*, not session *behavior*.

**Source:** [MongoDB Atlas — Advanced Options for Federated Authentication](https://www.mongodb.com/docs/atlas/security/federation-advanced-options/).

**Significance:** on the evidence from each vendor's own current documentation, neither Cloudflare nor MongoDB Atlas documents a customer-facing control to force a fresh Google authentication challenge independent of whatever session Google itself considers valid.

**Verification:** MongoDB Atlas URL fetched / confirmed the documented feature list contains no session/ForceAuthn language.

#### Finding 4.2 — Cloudflare's "Independent MFA" is explicitly scoped to Zero Trust Access applications, not the dashboard or Super Administrator login

**Evidence:**

> "Independent multi-factor authentication (MFA) allows you to enforce MFA requirements directly in Access without relying on your identity provider (IdP)."

**Source:** [Cloudflare One — Independent MFA](https://developers.cloudflare.com/cloudflare-one/access-controls/access-settings/independent-mfa/).

**Significance:** exists, and does exactly what the runbook's threat model needs, but only for Zero Trust Access-protected applications — not the Cloudflare account dashboard the break-glass Super Administrator signs into.

**Verification:** URL fetched / quote checked / substring confirmed present.

#### Finding 4.3 — Cloudflare's own Access (Zero Trust) session-duration setting does force IdP reauthentication when it expires, illustrating the mechanism exists in Cloudflare's product family generally — just not on the surface 4Shark uses

**Evidence:**

> The global session duration "determines how often Cloudflare Access prompts the user to log in to their identity provider." ... "the user will be required to re-authenticate with the IdP after this period of time."

**Source:** [Cloudflare One — Session management](https://developers.cloudflare.com/cloudflare-one/access-controls/access-settings/session-management/).

**Significance:** confirms Cloudflare's platform is technically capable of this; not confirmed for the dashboard SSO surface.

**Verification:** URL fetched / quote checked / substrings confirmed present.

#### Finding 4.4 — General SAML `ForceAuthn` is a real protocol feature, establishing that the mechanism 4Shark would need is not exotic

**Evidence:** search results describe `ForceAuthn=true` as a standard SAML AuthnRequest attribute; vendor implementations (Salesforce, Oracle, GitLab) were not individually fetched and quote-verified.

**Source:** Aggregated WebSearch results — marked **UNVERIFIED** per the citation discipline.

**Significance:** establishes the mechanism is a solved SAML-ecosystem problem generally; whether Cloudflare or MongoDB Atlas implement it without documenting a customer toggle remains open.

**Verification:** UNVERIFIED.

#### Finding 4.5 — A genuine search for a practitioner account of forcing Cloudflare or MongoDB Atlas to re-authenticate against an existing Google session found none, and names why the search was constrained

**Evidence:** two Cloudflare Community threads on exactly this session topic returned HTTP 403. A security-vendor blog (Obsidian Security) discusses SSO-bypass generally but not this specific reauthentication-forcing question.

**Source:** search conducted across `community.cloudflare.com` and [Obsidian Security — SSO Bypass: How Attackers Circumvent Single Sign-On](https://www.obsidiansecurity.com/blog/sso-bypass-attack-techniques) (fetched, confirmed not to address the specific claim). The same access-wall pattern recurs with two AWS re:Post threads (Finding P.4).

**Significance:** the community-writeup layer was searched, not skipped, across two separate platforms (Cloudflare Community, AWS re:Post) — both times the on-topic discussion exists but is behind an access wall this spike's tooling cannot cross.

**Verification:** URLs named in Evidence; no quote offered for the reauthentication-forcing question because none was found.

---

### Secondary — Orphaned SAML identity providers (`JumpCloud`, `JumpCloudDeveloper`, `ArchBit`)

#### Finding 5.1 — The security community treats an unused-but-present SAML identity provider as a persistence vector worth removing, though this spike found no CIS-benchmark control naming SAML providers specifically

**Evidence:**

> "Adversaries who have gained administrative access may create rogue SAML providers to establish persistent, federated access to AWS accounts that survives credential rotation." ... Recommended remediation: "delete the SAML provider using `DeleteSAMLProvider`" and "review and remove any IAM roles that trust the rogue provider."

**Source:** [detection.fyi — AWS IAM SAML Provider Created (persistence detection rule)](https://detection.fyi/elastic/detection-rules/integrations/aws/persistence_iam_saml_provider_created/).

**Significance:** 4Shark's three orphaned providers are not currently trusted by any of the account's 110 IAM roles, so today they are inert — a pre-staged trust anchor an attacker could reference without needing `iam:CreateSAMLProvider`, rather than an active exposure. No CIS/NIST control found names SAML identity providers specifically as an unused-resource category to prune.

**Verification:** URL fetched / quote checked / substrings confirmed present.

## Item 1 — Concrete remediation

The `identity/` stack's apply gate must not depend on Identity Center or Google (Finding P.3), so the fix strengthens the SAME `ivo` IAM user's credential — `guard.tf`'s `user_id` check does not need to change. Two options; no recommendation between them.

### Option 1 — Hardware TOTP on `ivo`, via `GetSessionToken` (Findings 2.10, 2.11, P.5, P.6)

**Changes:**
- Enroll the break-glass YubiKey's OATH applet as `ivo`'s IAM virtual MFA device (console, one-time): `ykman oath accounts add --issuer AWS --oath-type TOTP --touch ivo`, then `aws iam enable-mfa-device --user-name ivo --serial-number <arn> --authentication-code1 <code1> --authentication-code2 <code2>`.
- Delete `ivo`'s static access key once the new flow is confirmed working.
- `guard.tf`: **no change.**
- `identity/.envrc` line 4: **no change** (`export AWS_PROFILE=ivo` stays; the profile's credentials are minted per-session instead of static).

**Daily command, before `terraform apply`:**
```
aws sts get-session-token --serial-number <arn> --token-code $(ykman oath accounts code ivo | grep -oE '[0-9]{6}$')
```
then export the three returned values as `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN` (or a credential-process wrapper) before running `bash ~/.claude/scripts/terraform.sh ~/Projects/4Shark/terraform/identity <subcommand>`. No browser. 1-hour session (`GetSessionToken` default).

**Rollback:** the static access key is not deleted until this flow is confirmed working — reverting is "use the old key" with no state change.

### Option 2 — `aws login` against `ivo`'s own IAM-user console credentials (Findings 2.3, P.5)

**Only valid if `ivo` has its OWN console username+password, independent of Google** — unconfirmed (Finding 2.3). If `ivo`'s only console path is Identity Center/Google, this option inherits Finding P.3's limitation and does not close the gap.

**Changes:** register a FIDO2 security key directly on `ivo`'s IAM console MFA (not via Google). `guard.tf`: no change. `.envrc`: no change.

**Daily command:** `aws login --profile ivo` (browser, FIDO2 challenge, 12-hour cached session) before `terraform.sh`.

**Rollback:** same as Option 1 — old key stays valid until the new flow is confirmed.

### The lockout question

Because neither option changes WHICH `user_id` `guard.tf` checks — only how that same user authenticates — **there is no lockout risk and no transitional guard is needed for either option.** A transitional (expand/contract) guard would only be required if a NEW IAM user were introduced instead of upgrading `ivo` in place; neither option above does that. 4Shark's own Deployment Strategy names the applicable pattern for that different case ("Phase the change (expand/contract — Parallel Change)... ONLY when the in-flight contract breaks backward-incompatibly," `CLAUDE.md` § Deployment Strategy) — restated here in case a future decision (e.g. splitting break-glass from a routine-automation identity, Finding 2.8) does introduce a new principal.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Option 1 — hardware TOTP on `ivo` via `GetSessionToken` | No browser needed; confirmed independent of Identity Center/Google; no CLI-version dependency; no `guard.tf` change; same mechanism 4Shark already uses for GitHub | TOTP is weaker than FIDO2 in general (real-time relay phishing is theoretically possible, though the `--touch` requirement still demands physical possession per code) | Findings 2.2, 2.10, 2.11, P.5, P.6 |
| Option 2 — `aws login` against `ivo`'s own console credentials | Full FIDO2 strength if `ivo` has its own console login | Contingent on an unconfirmed fact (does `ivo` sign into the AWS console independently of Google?); if not, this option silently inherits Finding P.3's limitation | Findings 2.3, P.5 |
| Move `identity/` stack applies OFF the break-glass identity entirely, onto a dedicated non-emergency automation identity | Follows Findings 1.6/2.8/2.9; break-glass blast radius shrinks to genuine emergencies | Requires deciding what that identity is and how it authenticates; introduces the lockout question the two options above avoid | Findings 1.6, 1.7, 2.8, 2.9 |
| Shorten the Google Workspace "session length for Google services" org-unit setting for the break-glass identity | Bounds both the Gmail/Cloudflare/Atlas exposure and the AWS `AdministratorAccess` re-federation window (Finding 3.2) | Not confirmed to be enforceable down to a window shorter than the Admin console's 1-hour floor; treats a symptom the community more often treats structurally (Finding 3.4) | Finding 3.2 |
| Stop the break-glass Google identity from being used for routine mailbox access at all | Addresses the root pattern in Finding 3.4, which also gates AWS access, raising the stakes of leaving it as-is | Operational change, not a technical one | Finding 3.4 |
| Move Cloudflare and MongoDB Atlas break-glass access off Google Workspace SSO onto a local/native account per platform | Removes the Google-session vector structurally for those two platforms | Both platforms enforce domain-wide SSO with "no per-user bypass" documented; a platform-level exception was not researched | Finding 1.6 |
| Remove the three orphaned SAML providers | Eliminates a pre-staged trust anchor (Finding 5.1) | Routine hygiene, not a response to an active exposure | Finding 5.1 |

## What remains uncertain

- Whether `ivo` has its own IAM-user console credentials independent of Google, or whether its only console path is through Identity Center/Google — this decides whether Item 1's Option 2 is viable at all (Finding 2.3).
- Whether Cloudflare's Dashboard SSO or MongoDB Atlas's federated Organization Owner sign-in has any documented session-duration or ForceAuthn-equivalent control (Finding 4.1); the relevant community threads (two on Cloudflare, two on AWS re:Post) were found but returned HTTP 403 (Findings 4.5, P.4) — an authenticated read of all four is a concrete, not-yet-exhausted next step.
- Whether general SAML `ForceAuthn` is technically supported by Cloudflare's or MongoDB Atlas's SAML implementations but simply undocumented as a customer-configurable option (Finding 4.4).
- Whether Cloudflare and MongoDB Atlas's domain-wide SSO enforcement has any documented exception mechanism for a single break-glass account (relevant only if the "move off Google SSO" trade-off is pursued for those two platforms).
- Whether Google's per-organizational-unit "session length for Google services" setting can be configured low enough, specifically for the break-glass identity's own OU, to meaningfully bound the AWS re-federation window identified in Finding 3.2 — not tested.

## Suggested options for main and the engineer

- **Option 1 — Hardware TOTP on `ivo` via `GetSessionToken`** (Item 1, Option 1). No `guard.tf` or `.envrc` structural change; no lockout risk; confirmed independent of Google.
- **Option 2 — `aws login` against `ivo`'s own console credentials** (Item 1, Option 2), contingent on confirming `ivo` has independent console access (open question above).
- **Option 3 — Move `identity/` stack applies off the break-glass identity entirely**, onto a dedicated non-emergency automation identity (Findings 1.6, 1.7, 2.8, 2.9) — orthogonal to Options 1/2, and introduces the lockout/expand-contract question if adopted.
- **Option 4 — Shorten the break-glass identity's own "session length for Google services" OU setting**, known to bound AWS re-federation as well as Cloudflare/Atlas exposure (Finding 3.2).
- **Option 5 — Stop the break-glass Google identity from being used for routine mailbox access at all** (Finding 3.4), independent of any session-length setting chosen.
- **Option 6 — Move Cloudflare and MongoDB Atlas break-glass access off Google Workspace SSO onto a local/native account per platform** (Finding 1.6), subject to the domain-wide-SSO-exception open question.
- **Option 7 — Remove the three orphaned SAML providers** (Finding 5.1), independent of any other option.
- **Option 8 — Pursue an authenticated read of the four inaccessible community threads** (two Cloudflare, two AWS re:Post) to close the open questions in Findings 4.1, 4.4, 4.5, and P.4.

These options are not mutually exclusive and are not ranked. Options 1 and 2 are alternatives for the SAME fix (item 1); Options 3 through 8 address independent axes and can be adopted alongside whichever of 1/2 is chosen.
