# Privileged Access Surface — the Ivo Break-Glass Identity

Record of an audit of every privileged entry point tied to the `ivo` break-glass identity, and of
the remediation carried out against it. Written so the work can be understood, finished, or
audited by someone who was not in the session that ran it.

**Subject**: the break-glass identity `ivo@4shark.com.br` — an AWS IAM user, an AWS Identity Center
user, and a Google Workspace account federating into Cloudflare and MongoDB Atlas. AWS account
`405749097490`.

**State**: eight of the fourteen entries are closed, including the design's load-bearing half — the
restriction on the `ivo` key, described in § The design change and its missing half. Two things
remain: seven SSH keys on disk, and the absence of a break-glass identity for Cloudflare and Atlas
outside the domain. Both are in § What remains, alongside the one constraint that has no fix at the
current Workspace edition.

Research behind the elevation mechanism lives in `active/spike/break-glass-mfa-enforcement/SPIKE.md`.

---

## The premise the audit corrected

The audit started from a worry that a stolen machine would hand an attacker AWS through a Google
sign-in. **That path is real.** The Identity Center instance's identity source is an external
provider over SAML 2.0, read from the console's *Identity source* tab, and the only SAML provider in
the account is `AWSSSO_ddde7fecc0d50ba5_DO_NOT_DELETE`, which Identity Center creates for itself. A
live Google session therefore reaches the AWS access portal.

Two traps make this easy to get wrong from the API alone, and both were fallen into. The
identity-store user records carry no `ExternalIds`, which looks like an internal directory and is
not: Identity Center supports an external provider whose users are created manually rather than
provisioned by SCIM. And no role trusts a *Google* SAML provider, which is true and irrelevant —
the trust runs through Identity Center's own provider, not a direct one. **The identity source is
console-only and exposes no read API**, so no session can settle it and the engineer has to look.

What the key protecting that path is worth knowing: Google Workspace requires a FIDO2 security key
for that account, and three are registered, so the portal sits behind hardware in both directions —
the console and `aws sso login`, which opens the same browser flow.

The lost-machine scenario is worse by a different path, and that is the finding worth carrying:
the machine holds a **static AWS access key** for an IAM user that can write IAM, with no MFA in
front of it. AWS is explicit that the MFA condition key cannot help there —
`aws:MultiFactorAuthPresent` *"is only present when the user authenticates with short-term
credentials. Long-term credentials, such as access keys, do not include this key."* A policy that
demands MFA is simply not evaluated against a static key.

---

## The design change and its missing half

The audit's recommendation for the static key was to delete it and move the `identity/` apply onto
Identity Center. **That is not what was built.** The chosen design keeps the key but reduces it to
a token that can only be exchanged: a two-profile pair where `ivo` holds the long-term credential
and `ivo-elevated` receives a short STS session minted with a hardware TOTP.

Two properties of that design are already in place. The session is **15 minutes**, which is the
shortest AWS will issue — `GetSessionToken`'s `DurationSeconds` has a documented minimum of 900 —
and the `identity/` and `audit/` stacks pin `AWS_PROFILE=ivo-elevated` in their own `.envrc`, so
the elevated session is what those stacks run under.

**The restriction on the `ivo` key is in place**, which is what makes the design whole rather than a
safe path built alongside an unsafe one. Three MFA-conditioned policies replaced
`AdministratorAccess` on that user, so the key on disk grants nothing on its own and is good for
exactly one thing: minting the session.

Two facts about the account shape decide how that restriction has to be written, and both are easy
to get wrong from the outside.

**The restriction is not a policy that permits only `GetSessionToken`.** A session minted by
`GetSessionToken` carries the *same* permissions as the user who called it — the only thing that
distinguishes it from the raw key is that the session was authenticated with MFA and therefore
satisfies `aws:MultiFactorAuthPresent`. So the shape that makes the key worthless while leaving the
session capable is to condition **every** permission the identity holds on that key, which is
already the house pattern: eight policy files under `identity/` gate the engineers' write access
exactly that way, and `policy_encryption_environment.tf:36` carries an explicit
`DO NOT ADD aws:MultiFactorAuthPresent HERE` for the one policy that must not.

**The `ivo` IAM user is not managed by Terraform.** It does not appear in the `engineers` map in
`terraform.tfvars`, and `identity/` references the identity only through `guard.tf`, which pins its
UserId (`AIDAV46EH4QJBIBQ7ATEM`) in a postcondition so no other principal can apply the stack. That
absence is coherent rather than an oversight — this is the identity that *applies* the stack, so
declaring it there would have the stack manage the credential it depends on, the same circularity
that `THIRD-PARTY-KEY-STANDARD.md` carves out for a provider's own bootstrap credential. Whether to
adopt the user into the stack anyway or to attach the conditioned policy out of band is the
decision this item opens with, and it should be taken deliberately.

**The prerequisite is an inventory nobody has taken**: which policies are attached to `ivo` today.
That listing needs a break-glass session, because `iam:ListSAMLProviders` and its neighbours are
denied to both the engineer's baseline and MFA-elevated profiles.

---

## What the community does, and where 4Shark's shape diverges

**Break-glass identities belong in infrastructure as code.** Keeping them out because the stack
would manage its own operator is not the industry position. AWS Well-Architected SEC03-BP03 says to
*"Pre-create resources needed by the emergency access process ... pre-create the emergency access
AWS account with IAM users and roles"*, and names the mechanism in its implementation steps: *"You
can use CloudFormation StackSets with AWS Organizations to create such resources in the member
accounts in your organization."* AWS Labs' own reference implementation, `aws-break-glass-role`,
provisions the role with CDK.

**The circularity is broken one level ABOVE the identity, not by keeping it out of code.** The same
best practice: *"Create AWS Organizations service control policies (SCPs) to deny the deletion and
modification of the cross-account IAM roles in the member AWS accounts."* An SCP is enforced from
the organization's management account, so a member-account identity — however privileged — cannot
lift it. That is the answer to "who controls the break-glass identity": an authority it cannot
reach, plus logs it cannot alter (*"ship logs to an immutable store or an account that cannot be
altered by the break glass credentials"*).

**Whether that answer is even available here is unresolved.** `organizations:DescribeOrganization`
is denied to the engineer's profile, so this account's membership in an AWS Organization was not
confirmed. If there is no organization, there is no SCP layer to write, and the guardrail above the
identity does not exist to be built — which would make the honest control a detective one
(CloudTrail to a store the identity cannot rewrite) rather than a preventive one.

**The sharpest divergence is that `ivo` is not used as a break-glass identity at all.** It is the
routine operator of the `identity/` stack: `guard.tf` pins its UserId so that *only* it can apply,
which means every ordinary identity change runs through the emergency credential. SEC03-BP03 names
that as an anti-pattern in its own words — *"Your emergency access processes are used in
non-emergency situations. For example, your users frequently misuse emergency access processes as
they find it easier to make changes directly than submit changes through a pipeline"* — and states
the intended posture plainly: *"During normal operations, no one should access the emergency access
account and you must monitor and alert on the misuse of this account."*

The consequence is concrete rather than theoretical. The whole detective model the community relies
on — alert whenever the break-glass identity is used — **cannot be built here**, because using it is
normal. Every alert would be a false positive, so the alert is never written, and a genuine misuse
looks exactly like Tuesday.

## The model 4Shark operates

`ivo` **is** 4Shark's break-glass identity, and the shape below is the settled design rather than a
step toward another one.

**Its trigger is a missing permission, not an outage.** Day-to-day work runs on the engineer account
(`default` for reads, `4shark-mfa` for writes). The break-glass identity is reached only when the
engineer account lacks a permission the work needs. Engineer permissions start at nothing and are
granted reactively, one confirmed `AccessDenied` at a time — the rule `IDENTITY-STACK.md` already
carries — so the identity's job is to close a gap in that permission set, and the gap closes for
good each time.

**Its elevated session is scoped to identity work**: IAM users, groups, policies. Not security
groups, not compute, not data. A permission an engineer needs for ordinary infrastructure work is an
engineer permission, granted through the stack — never a reason to reach for this identity.

**Today's usage volume is bootstrapping, not the steady state.** The engineer permission set is
still being built out, so gaps are frequent; they get rarer as the set converges. Read any measure
of how often the identity is used against that, not against a finished system.

**The control against IAM self-escalation is procedural, deliberate, and accepted.** An identity that
can write IAM can always write itself an administrator policy — `iam:PutUserPolicy` and
`iam:AttachUserPolicy` are catalogued escalation paths, and no permissions boundary closes them for
a principal that can edit its own boundary. What bounds this identity is therefore not a policy but
a person: one owner holds it, `AdministratorAccess` is never granted, and no third party's code runs
under it. A preventive technical bound would require an authority the identity cannot reach — an SCP
from an organization management account — and that is not what this account is built on.

**What follows from the decision**: no separate pipeline identity applying `identity/`, no second AWS
account, and no split of the identity's two roles. The `guard.tf` postcondition stays exactly as it
is, because it is what keeps an engineer from applying the stack that defines their own permissions.

The two profiles cannot be collapsed into one. Writing the session over the key that mints it
destroys the only credential able to call `GetSessionToken`, which AWS requires to be a long-term
one.

---

## What was closed, and what authorized each closure

**The `identity/tfplan` artifact was deleted.** A binary Terraform plan of the IAM stack sat in the
working directory carrying every resolved value in clear. It was confirmed git-ignored before
removal, and its contents were deliberately not read — a plan of the IAM stack is exactly the file
whose contents must not pass through a session transcript. A fresh `terraform plan` regenerates it
when needed.

**Three orphaned SAML providers were deleted** — `JumpCloud` and `JumpCloudDeveloper` (October
2021) and `ArchBit` (May 2023), each a live federation path into the account for a vendor 4Shark no
longer uses. Two verifications authorized the deletion: all **110 roles** in the account were
scanned and no trust policy references any of the three, and no `aws_iam_saml_provider` resource
exists anywhere in the terraform repository, so nothing drifted.

**A fourth provider exists and must never be deleted.** `AWSSSO_ddde7fecc0d50ba5_DO_NOT_DELETE`
belongs to Identity Center itself. The original audit counted three providers because it had never
managed to list them — `iam:ListSAMLProviders` is denied both to the engineer's baseline profile
and to the MFA-elevated one, so only the break-glass session can enumerate them. Anyone repeating
this check will hit the same wall and should not read the denial as an empty account.

**The elevation tooling was unblocked.** Two environment variables were missing from the engineer's
own `~/.claude/settings.local.json`, and their absence stopped both elevation paths from running at
all. `AWS_BREAK_GLASS_MFA_SERIAL` is `arn:aws:iam::405749097490:mfa/YubiKey1`, read from
`aws iam list-virtual-mfa-devices` and confirmed attached to `ivo@4shark.com.br`.
`AWS_MFA_ITEM` is `Amazon AWS - Paulo (4Shark)`.

The second variable is worth explaining, because it looks redundant and is not. `elevate-aws-access.sh`
resolves the 1Password item on its own whenever exactly one item's title starts with `Amazon AWS`.
The vault holds two — one per engineer — so the fallback cannot choose and the script stops. The
variable is per-person, which is why it belongs in the engineer's local settings and never in the
shared `settings.json`. The agent cannot write either file: `validate-installed-config-edit.sh`
blocks it, deliberately, after an incident where the agent edited its own permissions.

**The credentials file was tightened.** `chmod 600 ~/.aws/credentials` was applied after the AWS CLI
warned three times that the file holding both static keys was world-readable. The verification is
indirect — `~/.aws` is permission-blocked to the agent, which is the policy working — so what
confirms it is the CLI falling silent, not a reading of the file mode.

**The `ivo` IAM user's `AdministratorAccess` was replaced** (terraform PR #1092). Three
MFA-conditioned policies took its place — `BreakGlassIdentity` (IAM, Identity Center, Identity
Store), `BreakGlassAudit` (CloudTrail and its log bucket) and `BreakGlassTerraformState` (the two
stacks' state objects and the keys that encrypt them). What proves the scope sufficient is not the
apply but the plan that followed it: run under the new policies, it refreshed every resource across
IAM, Identity Center, the state bucket and KMS, and reported no drift.

**The Identity Center admin permission set was scoped** (terraform PR #1100). It granted the AWS
managed `AdministratorAccess` — `"Action": "*"` on `"Resource": "*"` — to the group whose only
member is `ivo`, so whoever passed the portal login held the account entire. It now carries
`BreakGlassIdentityPortal` and is named `BreakGlassAccess`, the rename forcing a replacement because
a permission set's name is immutable. The policy is separate from the three above because those
condition on `aws:MultiFactorAuthPresent`, which AWS documents as *"not present for federated
identities"* — attached to a permission set they would grant nothing.

That apply failed midway and was recovered fix-forward on the same PR. Terraform ran the two
destroys concurrently; removing the account assignment de-provisioned the permission set, and the
concurrent managed-policy detach then tried to re-provision it and received a 404. The recovery was
a re-plan to read the real state rather than assume it, followed by an apply of what remained.

**The break-glass Google session was terminated.** Sign-in cookies were reset for
`ivo@4shark.com.br`, ending a session that had been live for three months. The reset is what kills
an open session: a change to the session-length policy applies only once the current session ends,
so shortening the duration would have left that one running.

**The break-glass Google account is restricted to a security key.** Google Admin's 2-Step
Verification, scoped to the `break-glass` organizational unit that holds only `ivo`, enforces
*Somente chave de segurança ou chave de acesso* with no enrollment grace period. Two settings there
carry more weight than the method restriction itself: *Permitir que o usuário confie no dispositivo*
is unchecked, so no device can be marked trusted and skip the challenge, and *Não permitir que os
usuários gerem códigos de segurança* removes the user's own fallback. The only bypass left is an
administrator generating verification codes, which opens a one-day window.

Three security keys are registered on the account, all as second factor rather than passkey, so the
lockout this configuration can cause is covered.

---

## What remains

**Identity Center manages no MFA of its own here**, so there is nothing to configure on the AWS
side. The instance's identity source is an external provider over SAML 2.0, which is why its
Authentication tab shows session duration and trusted token issuers but no MFA section at all.
Authentication happens at Google Workspace, and `aws sso login` reaches the same provider through
the browser — so both portal paths, console and CLI, sit behind whatever Google requires.

The absence of `ExternalIds` on the identity-store user records is not evidence against this:
Identity Center supports an external provider whose users are created manually rather than
provisioned by SCIM, which is the shape this account runs.

**Every virtual MFA device in the account is attached to a user** — `YubiKey1` to `ivo` and
`1Password` to `paulo`, and nothing else exists.

**AWS does not delete a virtual MFA device when it deletes the user it belonged to**, which is what
produced most of those orphans. An offboarding leaves the device object behind, detached, and
nothing surfaces it afterwards — so removing the device belongs in the offboarding procedure
alongside removing the user.

An unattached device authenticates nobody — both `GetSessionToken` and console sign-in require the
device to belong to the calling user — so what survives a detachment is only the seed in whoever's
authenticator app, live again only if someone with IAM write reattaches it. AWS exposes no
last-used timestamp for MFA the way it does for access keys, and an unattached record carries
neither `EnableDate` nor a creation date, so CloudTrail is the only source and it reaches 90 days.

**Seven SSH private keys sit in `~/.ssh`** beyond the sanctioned GitHub key. The `migrate-ssh-keys`
skill moves them into 1Password one at a time and removes each from disk only after the service is
proven to authenticate through the agent.

**Cloudflare and MongoDB Atlas have no break-glass identity outside the domain.** Both federate
through the Google account, so a live Gmail session hands over Cloudflare Super Administrator and
Atlas Organization Owner with no fresh challenge, and a Google outage removes emergency access to
both. The GitHub account `ivonoide` is the model to copy — an identity outside `@4shark.com.br`
with its own FIDO2 and TOTP. This is the largest remaining item and the only one needing vendor
coordination.

**The break-glass Google session cannot be expired by policy on this Workspace edition.** The
session-length control requires *"Frontline Standard and Frontline Plus; Business Plus; Enterprise
Standard and Enterprise Plus; Education Fundamentals, Education Standard, and Education Plus;
Enterprise Essentials Plus; G Suite Business; Cloud Identity Premium"*, and the console's *Access
and data control* menu offers only API controls, data protection, Google Cloud session control and
external sharing — so the tenant sits below that list. A web session renews with use, which is how
one lived three months.

Three ways out, none free. Moving the Identity Center identity source to its own directory takes
Google out of the AWS path and unlocks AWS-side controls that reach a 15-minute interactive session
and security-key-only MFA — at the cost of a window in which, per AWS, *"all users and groups,
including the administrative user in IAM Identity Center, will lose single sign-on access"*, and it
leaves Cloudflare and Atlas untouched. Upgrading the Workspace edition is the only option that
covers the whole chain, and stops at a one-hour floor. Scheduling `users.signOut` against that
account automates the cookie reset, and expires nothing — the session dies on the job's clock rather
than on inactivity.

The Google Cloud session control, which this edition does have, is set for that organizational unit
to require reauthentication every hour with a security key. It governs only what carries the Cloud
Platform scope, and its *trusted apps exempt* checkbox means anything marked Trusted skips it.

Three entries were found already correct and are not to be touched: the AWS root account (FIDO2,
outside any federation, three YubiKeys), the GitHub `ivonoide` account, and a third party's
Identity Center access correctly scoped to `beta-001` with a read-only Atlas role.

---

## Open questions

Whether either vendor implements `ForceAuthn` without exposing a customer-facing control is unknown,
and it decides whether Cloudflare and Atlas can be made to re-challenge without replacing their
identity provider. It needs an empirical test or a vendor conversation; it cannot be settled from
documentation.

Whether the Workspace edition upgrade is worth its recurring per-seat cost is a business question,
not a technical one. What it buys that nothing else does is coverage of the whole chain — every
service that authenticates through Google, rather than AWS alone.

---

## Artifacts

The status report rendering all fourteen entries with their current state is regenerated per
session under `/tmp/security_audit_ivo_status_<timestamp>.html` and is not durable — this document
is the durable record. No credential value was read or written into any session transcript during
the audit.

`SPIKE.md` holds the permission research, and `break-glass-permissions_cloudtrail_1.txt` beside it
holds the CloudTrail aggregate the research rests on. That file matters because the query behind it
reaches back only 90 days: the window it captured has since moved, so re-running the command
produces a different set. The full history lives in `s3://4shark-cloudtrail` from 2023 onward for
anything the window no longer reaches.
