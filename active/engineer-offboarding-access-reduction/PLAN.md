# Engineer Offboarding — Access Revocation

Record of a full engineer offboarding across every system 4Shark uses, from the interim
containment through the Terraform apply that removed the identity. Written so the work can be
understood, finished, or audited by someone who was not in the session that ran it.

**Subject**: `emerson.silva@4shark.com.br` / GitHub `eoliveiramg`, AWS account `405749097490`.
**State**: identity revoked everywhere it was found. Residual cleanup and one security decision
remain — see `TASKS.md`.

This case is the source material for the offboarding runbook 4Shark does not yet have. The
lessons that runbook must inherit are in § What this case taught, and they matter more than the
per-system record.

---

## Why the interim step existed

The engineer was terminated and paid for the notice period, so he was not expected to work, but
remained reachable on Slack and GitHub until the formal cut. The goal for that window was to
remove destructive capability without producing a signal he would read as distrust.

Two findings shaped it. First, **the baseline was not read-only**: `ECSRemoteAccess` was attached
to the `engineers` group with no MFA condition and granted `ecs:ExecuteCommand` on
`task/*` and `cluster/*` — a Rails console on any production task, meaning read, write and delete
across the whole production database — plus `ecs:UpdateService` on `Resource = "*"`, enough to
scale every production service to zero. Removing MFA, the intuitive move, would have left both
untouched. Second, **MFA deactivation is not durable on its own**: `IAMSelfService` grants
`iam:EnableMFADevice` and `iam:CreateVirtualMFADevice` unconditionally, so the engineer could
re-enrol in seconds.

The interim control was therefore a permissions boundary of `ReadOnlyAccess` on the IAM user,
which caps effective permissions to the intersection and so removes `ecs:ExecuteCommand`,
`ecs:UpdateService`, `ssm:StartSession`, the whole MFA tier and the re-enrolment path at once —
followed by deactivating the MFA device, which closes the two sensitive reads the boundary alone
leaves reachable (`s3:GetObject` and `ssm:GetParameter`, both present in `ReadOnlyAccess` and
granted by the engineer's own policies only under MFA). A narrower Deny policy,
`DestructiveActionGuardrail`, was attached first and kept afterwards as a second layer.

---

## What the apply removed

PR [#893](https://github.com/4shark/terraform/pull/893) removed the engineer from
`identity/terraform.tfvars`, and the apply destroyed fourteen resources: the AWS IAM user and its
login profile, the SSO Identity Store user and its group membership, the GitHub organization
membership and five team memberships, the Cloudflare account member, the MongoDB Atlas
organization and team assignments, and the Rollbar user. An in-place update removed him from the
`engineers` IAM group.

**The PR carried a fix the offboarding process did not know it needed.** GitHub organization
membership derives from the `engineers` map, but team membership comes from
`github_team_memberships`, a separate hand-written map in `identity/github.tf`. Editing only
`terraform.tfvars` would have left five team-membership resources referencing a username with no
organization membership, which GitHub rejects — the apply would have failed. Both files must be
edited together on every offboarding.

**The apply failed on its last resource and needed a second pass.** `DeleteUser` returned
`DeleteConflict: Cannot delete entity, must detach all policies first`, because the interim
`DestructiveActionGuardrail` was attached out of band and Terraform had no knowledge of it.
Detaching the policy, deleting the access key and removing the boundary cleared it; a second plan
showed one resource to destroy and completed. **Any out-of-band artifact attached to an identity
blocks its Terraform deletion** — an interim control bought via CLI has to be unwound before the
stack can finish.

---

## What this case taught

**The inventory's blind spot is the finding with the longest shelf life.** The system list was
built from the providers declared in the terraform repository, so everything that is not
infrastructure was invisible. Four systems surfaced only because the engineer named them
after the inventory was published: a personal Claude Code account, the engineer's user account
inside 4Shark's own `app` product across four environments, Clockify, and Figma. Clockify and
Figma both sit in category 3 below (time tracking and design), which the category-based runbook
catches by construction where the provider-derived list did not.

Codemagic — the service that builds and publishes the mobile app to the App Store and the Play
Store — is one more the provider-derived list could never have shown: it sits in the
individual-tooling category, on the mobile developer's own workflow, and proves the same point that
the question is which categories the person held accounts in, not whether a system is on a list.

**So the runbook must be organized by CATEGORY, not by a list of systems.** A named list is
always incomplete, and the three misses prove it. The categories this case revealed:

1. **Infrastructure and technical SaaS** — what Terraform can see.
2. **User accounts inside the products 4Shark builds** — the `app` across every environment.
3. **Administrative SaaS** — time tracking, and whatever else the company subscribes to with
   per-person login (accounting, e-signature, design, task management).
4. **Individual engineer tooling** — which may sit on the person's own account rather than the
   company's, and therefore has no company-side record to consult.

The question the runbook asks is not "is system X on the list?" but "in which categories did this
person hold an account?".

**Revoking access is not the same as containing exposure.** Deleting the 1Password account and
cancelling the Claude Code account remove future access; neither undoes what the person already
read or copied. Session transcripts under `~/.claude/projects/` and local clones of `dot-claude`
and `dot-claude-plans` persist on their machine. Everything reachable in the 1Password vaults —
notably the shared `Terraform ENV` item holding the org-wide third-party credentials, plus
database passwords and VPN/MongoDB keys — should be treated as known to them. `THIRD-PARTY-KEY-STANDARD.md`
carries the rotation path per category.

---

## Per-system record

Revoked by the `identity/` apply: AWS IAM user, AWS SSO identity and group membership, GitHub
organization and team membership, Cloudflare account member, MongoDB Atlas organization and team
assignment, Rollbar user.

Revoked by hand, outside Terraform: Pritunl VPN, Redis Cloud, Datadog, Netlify, 1Password, Slack,
Clockify, Figma, Codemagic, Apple Store, Google Play, the `app` user account in all four
environments (beta-001, demo-001, shared-001, atento-001), and the engineer's own Claude Code
account, which he cancelled himself.

Two adjacent questions were settled from `PROJECTS-CATALOG.md` rather than assumed. Keycloak is
*"For clients only; 4Shark does not use it for internal application auth"*, so deactivating the
four `app` accounts ends the login with no Keycloak user behind it. `onboarding` is
*"Conceptual for now: the repo holds the idea; nothing is wired into the runtime yet"*, so it
holds no accounts. **Unverified**: whether the engineer held a person account in `integrator`
(a Rails application with its own internal web interface) or in `setup`.

---

## Open — unrelated to access

A GitHub billing anomaly surfaced while reducing seats and is **not** the documented
"takes effect next cycle" behaviour. The organization is on the Team plan showing 9 purchased
seats against 5 used, with a banner scheduling a downgrade to 5 seats effective 2026-09-04. The
engineer reports having requested reductions repeatedly, including one to 7 seats roughly three
months earlier, none of which took effect across at least two billing cycles. No public bug
report matching this symptom was found; the closest community thread
([#40334](https://github.com/orgs/community/discussions/40334)) was closed by a moderator
redirecting to support, with users reporting the same across years and no documented resolution.

A check is scheduled for 2026-09-04 — both a Claude Code scheduled task
(`github-seat-downgrade-check`) and a calendar event on `paulo@4shark.com.br`. If the count is
still 9, support is the only route.
