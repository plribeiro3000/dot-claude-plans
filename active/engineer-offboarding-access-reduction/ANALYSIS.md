# System Inventory — Where an Engineer Holds Access

Which systems revoke an engineer's access automatically and which need someone to open an
interface, with the evidence behind each classification. This is the seed of the offboarding
runbook; the narrative and the lessons are in `PLAN.md`.

## Revoked by the `identity/` apply

One apply, run from the break-glass account (`identity/guard.tf` admits no other caller), covers
all six. Each row was read off the resource, not assumed.

| System | Resource destroyed | Declared in |
|---|---|---|
| AWS — IAM user | `aws_iam_user.engineer` + membership of the `engineers` group | `engineers.tf:26`, `group_baseline.tf:6` |
| AWS — SSO / console | `aws_identitystore_user.engineer` + group membership | `sso.tf:64`, `sso.tf:106` |
| GitHub | `github_membership.member` + `github_team_membership.member` | `github.tf:77`, `github.tf:91` |
| Cloudflare | `cloudflare_account_member.engineer` | `cloudflare_account_member.tf:30` |
| MongoDB Atlas | `mongodbatlas_cloud_user_org_assignment.engineer` + team assignments | `mongodb_org.tf:1`, `mongodb_teams.tf:31` |
| Rollbar | `rollbar_user.engineer` | `rollbar.tf:18` |

**GitHub needs two files edited, not one.** Organization membership derives from the `engineers`
map in `terraform.tfvars`, but team membership comes from `github_team_memberships`, a hand-written
map in `identity/github.tf`. Editing only the tfvars leaves team-membership resources pointing at
a username with no organization membership, and the apply fails.

## Manual — no Terraform, no SSO

| System | Why manual | Evidence |
|---|---|---|
| Pritunl (VPN) | The `vpn/` stack declares infrastructure, never users | no user resource in `vpn/*.tf` |
| Redis Cloud | The `rediscloud` provider manages databases; no user resource anywhere | providers of the database stacks |
| Google Workspace | It is the identity provider itself; `hashicorp/google` is used only for service accounts | `workspace-access/main.tf:55`, `analytics-access/main.tf:49` |
| Datadog | The `DataDog/datadog` provider manages monitors and keys, not people | `monitoring/providers.tf` |
| Netlify | No Netlify provider in any stack — sites are created through the API | no occurrence in the repository |
| 1Password | Outside Terraform by nature; holds the credentials and SSH keys | no coverage in the repository |
| Slack | Outside Terraform | no coverage in the repository |
| Clockify | Administrative SaaS — neither infrastructure nor product | surfaced only when named by the engineer |
| `app` user account | A person account inside 4Shark's own product, one per environment | surfaced only when named by the engineer |
| Claude Code / Anthropic | Personal account on the engineer's own email — no company seat to reclaim | surfaced only when named by the engineer |

The last three carry no repository evidence because none exists to find. They are the reason
`PLAN.md` § What this case taught argues for a category-driven runbook rather than a system list.

## Settled by reading, not assumed

Keycloak holds no internal account: `PROJECTS-CATALOG.md` records it as *"For clients only;
4Shark does not use it for internal application auth"*, so deactivating the `app` accounts ends
the login. `onboarding` holds no accounts at all: *"Conceptual for now: the repo holds the idea;
nothing is wired into the runtime yet"*.

**Open**: whether a person account exists in `integrator` (Rails with its own internal web) or in
`setup`.

## Ordering that avoids an open window

1. **Suspend Google Workspace first.** It is the SAML identity provider for MongoDB Atlas
   (`mongodb_federation.tf`) and the SSO for Cloudflare (ADR-004), so suspending it drops both
   logins immediately, without waiting for any apply. It removes the *login*; the apply removes
   the *authorization*, and an account restored in Google would meet its permissions again if the
   apply had not run.
2. **Apply the `identity/` stack** from the break-glass account.
3. **Clear anything attached to the identity out of band** — an attached policy blocks
   `DeleteUser` and will fail the apply; see `PLAN.md`.
4. **Walk the manual list**, confirming each in its own interface rather than assuming the apply
   reached it.
5. **Decide on credential rotation** — revoking access does not undo what was already read.
