# SPIKE — MongoDB Atlas Permissioning Redesign (Least Privilege + Elevation)

## Investigation question

4Shark wants to redesign MongoDB Atlas permissioning to mirror the least-privilege +
elevation model already used on AWS. Specifically: how do MongoDB itself and the wider
community recommend structuring Atlas access control — org/project roles, least privilege
for a small team, elevation for privileged actions, database-user modelling, and
self-service network access? This SPIKE distinguishes what MongoDB recommends from what is
merely a community workaround, and grounds every claim in a fetched source or a cited
`file:line`.

## Sources consulted

- `~/Projects/4Shark/terraform/identity/mongodb_federation.tf`, `mongodb_org.tf`,
  `mongodb_teams.tf`, `engineers.tf`, `terraform.tfvars`, `guard.tf` — current-state grounding
  (read in full this session)
- `~/Projects/4Shark/terraform/app-beta-001/mongodb.tf` — shared database credential pattern
- `~/Projects/4Shark/terraform/modules/mongodb_atlas/database_users.tf`,
  `network.tf` — module-level database-user and IP-access-list implementation
- https://www.mongodb.com/docs/atlas/reference/user-roles/ — full fixed org/project role
  enumeration, exact role privilege descriptions. See auxiliary
  `mongodb-atlas-permissioning_doc_1.md`
- https://www.mongodb.com/docs/atlas/security/ip-access-list/ and
  https://www.mongodb.com/docs/atlas/security/add-ip-address-to-list/ — the documented
  contradiction on which role can manage IP access list entries. See auxiliary
  `mongodb-atlas-permissioning_doc_2.md`
- https://www.mongodb.com/docs/atlas/architecture/current/network-security/ — private
  endpoint vs IP access list guidance. See auxiliary `mongodb-atlas-permissioning_doc_2.md`
- https://www.mongodb.com/docs/atlas/security/federated-authentication/,
  https://www.mongodb.com/docs/atlas/security/manage-role-mapping/,
  https://www.mongodb.com/docs/atlas/architecture/current/auth/authorization/,
  https://www.mongodb.com/docs/atlas/security/manage-org-mapping/,
  https://www.mongodb.com/docs/atlas/security/federation-advanced-options/ — federated auth,
  JIT role mapping, MFA/SSO bypass, domain restriction. See auxiliary
  `mongodb-atlas-permissioning_doc_3.md`
- https://www.mongodb.com/docs/atlas/workforce-oidc/,
  https://www.mongodb.com/community/forums/t/workforce-identity-federation-with-oidc-to-support-google/295993,
  https://www.mongodb.com/docs/database-tools/authentication/,
  https://www.mongodb.com/docs/atlas/security-add-mongodb-roles/,
  https://www.mongodb.com/docs/atlas/security-add-mongodb-users/,
  https://www.mongodb.com/docs/atlas/database-auditing/,
  https://www.mongodb.com/docs/atlas/tutorial/activity-feed/ — Workforce/Workload OIDC,
  custom database roles, temporary database users, auditing, attribution. See auxiliary
  `mongodb-atlas-permissioning_doc_4.md`
- https://www.mongodb.com/docs/atlas/architecture/current/auth/authentication/,
  https://www.cisecurity.org/benchmark/mongodb,
  https://www.mongodb.com/community/forums/t/does-mongodb-atlas-meet-the-cis-center-of-internet-security-benchmark/189214,
  https://howtoharden.com/guides/mongodb-atlas/,
  https://oneuptime.com/blog/post/2026-03-31-mongodb-atlas-access-roles-permissions/view —
  service accounts vs API keys, CIS benchmark applicability, independent practitioner
  corroboration. See auxiliary `mongodb-atlas-permissioning_doc_5.md`

## Findings

### Finding 1: Org/project roles are a fixed, predefined set — no custom control-plane roles

**Evidence:**

```
Organization Roles: Organization Owner, Organization Project Creator,
Organization Billing Admin, Organization Stream Processing Admin,
Organization Billing Viewer, Organization Read Only, Organization Member

Project Roles (26 total, incl.): Project Owner, Project Network Access Manager,
Project Cluster Manager, Project Data Access Read/Write, Project Read Only,
Project Data Access Admin, Project Database Access Admin, Project Access Manager, ...
```

Direct re-query of the same page confirmed: *"there is no mention of custom roles anywhere
in the content ... The page only discusses pre-defined Atlas user roles at the organization
and project levels."*

**Source:** https://www.mongodb.com/docs/atlas/reference/user-roles/ (full list in auxiliary
`mongodb-atlas-permissioning_doc_1.md`)

**Significance:** any least-privilege redesign for org/project (control-plane) access must
compose from this fixed catalog — there is no equivalent to an AWS IAM custom policy at the
Atlas control-plane layer. Fine-grained, project-scoped customization is only available at
the **database (data-plane) role** layer (Finding 5), a structurally different mechanism.

**Verification**: URL fetched twice (initial enumeration, then re-query for the
custom-roles-absence statement) / Verbatim quote checked / Quote substring confirmed present
in both fetches.

---

### Finding 2: MongoDB's own docs contradict each other on which role manages IP access list entries

**Evidence:**

`https://www.mongodb.com/docs/atlas/security/ip-access-list/`:
> "To manage IP Access List entries, you must have `Project Owner` or `Project Network
> Access Manager` access to the project."

`https://www.mongodb.com/docs/atlas/security/add-ip-address-to-list/`:
> "To add your IP address to an IP access list, you must have `Project Owner` access to the
> project."

Both statements were independently fetched, then each independently re-fetched to
self-check; both quotes are confirmed verbatim and present on each respective page as of this
session.

**Source:** both URLs above. Full context in auxiliary `mongodb-atlas-permissioning_doc_2.md`.

**Significance:** the narrower `Project Network Access Manager` role — which would let 4Shark
delegate self-service network-access changes without granting full `Project Owner` — is
documented on one canonical reference page but silently omitted from the task-oriented
how-to page. An engineer reading only the how-to page would conclude `Project Owner` is the
only path and never discover the narrower role exists. This is exactly the omission the
engineer's brief anticipated.

**Verification:** URL fetched (both) / Verbatim quote checked (both) / Quote substring
confirmed at "Required Access" section on each page, re-confirmed on second fetch.

---

### Finding 3: `Project Network Access Manager` is broader than "IP access list only" — it also covers VPC peering and PrivateLink

**Evidence:**

> "`Project Network Access Manager`
> `GROUP_NETWORK_ACCESS_MANAGER`
> Grants privileges to update project network settings for the following:
> - Access lists
> - VPC peering
> - Private Link"

**Source:** https://www.mongodb.com/docs/atlas/reference/user-roles/ (auxiliary
`mongodb-atlas-permissioning_doc_1.md`)

**Significance:** delegating this role to a non-admin engineer for "just IP access list
self-service" also hands them the ability to modify VPC peering and PrivateLink
configuration for the project — a materially larger blast radius than the IP-allow-list-only
framing in the investigation brief assumed. This role is per-project, matching the scoping
already used by 4Shark's `mongodbatlas_team_project_assignment` resources
(`identity/mongodb_teams.tf:42-49`).

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed at the
`Project Network Access Manager` entry of the role list.

---

### Finding 4: Atlas has no native temporary/elevated role assignment for project roles — the one documented JIT pattern is scoped specifically to `Organization Owner`, via IdP group → role mapping, and it is next-login-only

**Evidence:**

> "By integrating Atlas with a federated identity provider, you can use just-in-time
> provisioning by mapping identity provider groups to Atlas roles."

> "The Organization Owner role should be heavily restricted and not assigned to a human...
> To avoid account lockouts, you can create the following items:
> - SAML Organization Owner group with Just-in-Time Access.
> - Service account with the Organization Owner role. Keep it in a secure place with strong
>   access management for break-glass emergency scenarios."

> "Atlas applies the role mappings when you log in."

> "If you remove that user from the admin IdP group, Atlas deletes that users' Organization
> Owner role when the user next logs in."

**Source:** https://www.mongodb.com/docs/atlas/architecture/current/auth/authorization/ and
https://www.mongodb.com/docs/atlas/security/manage-role-mapping/ (auxiliary
`mongodb-atlas-permissioning_doc_3.md`)

**Significance:** this confirms the engineer's hypothesis — Atlas has no STS-analog (no
short-lived, on-demand elevated session/credential for control-plane roles). The one
MongoDB-documented elevation pattern (IdP group mapped to a role, applied at login) is
presented specifically for `Organization Owner` as a break-glass/JIT pattern, paired with a
vaulted standing service account. **No MongoDB source found in this research generalizes the
same technique to project-level roles** (e.g. mapping a Google group to
`GROUP_CLUSTER_MANAGER` for just-in-time elevation) — 4Shark would be extending a documented
org-level pattern to the project level on its own, not following an explicit MongoDB
recommendation for that layer.

The mechanism the engineer named — `mongodbatlas_federated_settings_org_role_mapping` — is
the correct Terraform resource type in the `mongodbatlas` provider for implementing this
MongoDB-documented pattern (IdP group → role mapping). It does **not currently exist
anywhere in 4Shark's Terraform**: `grep -rn "mongodbatlas_federated_settings_org_role_mapping"
~/Projects/4Shark/terraform/` returns no matches. Today's org-role assignment resource,
`mongodbatlas_cloud_user_org_assignment` (`identity/mongodb_org.tf:1-9`), is a direct
per-user role grant keyed on `each.value.email` — a structurally different mechanism from
IdP-group-to-role mapping. Adopting the JIT pattern means introducing a new resource type
and wiring a Google Workspace group into it, not extending something already in place.
Whether the equivalent resource exists for project-role mapping via Terraform was not
confirmed or refuted in this research (open question, below).

Comparing this to 4Shark's own AWS elevation mechanisms requires naming which one, since the
two are not interchangeable: the vaulted-service-account-with-`Organization Owner` half of
the MongoDB pattern resembles 4Shark's **break-glass** account (`identity/guard.tf` — rare,
emergency, a standing vaulted credential, not a routine flow). It does **not** resemble
4Shark's **routine** elevation flow, `/elevate-aws-access` → the `4shark-mfa` profile, which
is on-demand, self-service, MFA-token-based, and effective immediately. The SAML-Org-Owner-
group JIT half is closer in spirit to `/elevate-aws-access` (an engineer-initiated, routine
elevation rather than an emergency one) but differs from it in a material way: it is
group-membership-based rather than token-based, and — per the latency point below — it only
takes effect at the user's next login, in both directions. `/elevate-aws-access` has no such
delay; the elevated session is available as soon as the engineer runs it.

The **latency/caveat** the engineer asked about is confirmed: role mapping is evaluated only
at the point of login — moving a person into an elevated Google group does not elevate an
already-active Atlas session, and moving them back out does not revoke access until their
next login. There is no push-based, immediate revocation.

**Verification:** URLs fetched (both) / Verbatim quotes checked / Quote substrings confirmed
present at each cited passage.

---

### Finding 5: Data-plane least privilege is a genuinely different, more granular mechanism than the org/project roles — custom database roles exist, scoped per-project, database-only

**Evidence:**

> "You can create custom roles in Atlas when the built-in roles don't include your desired
> set of privileges."

> "You can create up to 100 custom roles per project by default."

> "A database user's access is determined by the roles assigned to the user. When you create
> a database user, any of the built-in roles add the user to all clusters in your Atlas
> project. To specify which resources a database user can access in your project, you can
> select the option Restrict Access to Specific Clusters in the Atlas UI or set specific
> privileges and custom roles."

**Source:** https://www.mongodb.com/docs/atlas/security-add-mongodb-roles/ and
https://www.mongodb.com/docs/atlas/security-add-mongodb-users/ (auxiliary
`mongodb-atlas-permissioning_doc_4.md`)

**Significance:** this directly answers investigation point 5. 4Shark's current
`app-beta-001/mongodb.tf:20` grants the shared credential `readWriteAnyDatabase` on the
`admin` database — a broad built-in role. MongoDB's own docs frame the alternative
explicitly as scoping via "Restrict Access to Specific Clusters" and/or custom
database roles, rather than an AnyDatabase built-in role, when finer-grained access is
wanted. This is presented as an option, not a MongoDB mandate to change the current setup.

**Verification:** URLs fetched (both) / Verbatim quotes checked / Quote substrings confirmed
in each page's body.

---

### Finding 6: Workforce Identity Federation (OIDC) exists for human database login — but it is a SEPARATE IdP registration from the SAML federation 4Shark already has, requires M10+/MongoDB 7.0.11+, officially lists only three IdPs (none of them Google), and only MongoDB Shell/Compass are named as supporting clients — not `mongodump`

**Evidence:**

> "Workforce Identity Federation is supported by Atlas dedicated clusters (M10 and above)
> running MongoDB version 7.0.11 and above."

> "register your OIDC application with an IdP that supports OIDC standard, such as Microsoft
> Entra ID, Okta, or Ping Identity."

> "You need to use MongoDB Shell or Compass to access Atlas with Workforce Identity
> Federation."

Community (non-official) report:

> "Today I tried to set up OIDC for Workforce and grant access to the database using my IdP
> (Google), but the current implementation doesn't support ClientID + Client Secret and when
> using Google as IdP we must use both, otherwise the flow won't work properly." — forum user
> rmart001

**Source:** https://www.mongodb.com/docs/atlas/workforce-oidc/ (official) and the linked
MongoDB community forum thread (unofficial, community report — auxiliary
`mongodb-atlas-permissioning_doc_4.md`)

**Significance:** this is a substantial finding against the "engineers authenticate to the
database with their Google identity" idea the engineer raised. MongoDB's own supported-IdP
list for Workforce OIDC does not name Google Workspace — only Microsoft Entra ID, Okta, and
Ping Identity are named — and a community thread (unresolved, no MongoDB staff confirmation
found) reports a concrete technical blocker specific to Google as the OIDC provider. All
four of 4Shark's clusters (`app-atento-001`, `app-beta-001`, `app-demo-001`,
`app-shared-001`) are on `cluster_tier = "M10"` (verified: `grep cluster_tier
app-*/mongodb.tf`), so the tier prerequisite is already met — the IdP-support gap is the
blocker, not the cluster tier. Separately, even where Workforce OIDC IS configured, MongoDB
names only MongoDB Shell and Compass as supporting clients — `mongodump` and the other
Database Tools are documented as supporting **Workload** (machine) OIDC, not Workforce
(human) OIDC (`https://www.mongodb.com/docs/database-tools/authentication/`: *"Starting in
100.11.0, database tools support Atlas Workload Identity Federation"* — Workload, not
Workforce). So even setting the Google-IdP gap aside, an engineer authenticated via Workforce
OIDC would still need a separate credential path to run `mongodump`.

**Verification:** URLs fetched (official docs + forum) / Verbatim quotes checked / Quote
substrings confirmed at each cited passage.

---

### Finding 7: Federated (SAML) login bypasses Atlas's own 2FA by design — MFA must be enforced at the IdP

**Evidence:**

> "Atlas bypasses 2FA for users who authenticate with federated authentication through your
> IdP. If a user authenticates through your IdP and has 2FA for their Atlas account enabled,
> Atlas doesn't prompt the user for 2FA."

> "Instead, you can configure your trusted IdP to prompt users for 2FA."

**Source:** https://www.mongodb.com/docs/atlas/security/federated-authentication/ (auxiliary
`mongodb-atlas-permissioning_doc_3.md`)

**Significance:** 4Shark's Atlas org is federated to Google Workspace via SAML
(`identity/mongodb_federation.tf:5-16`). Per this documented behavior, whatever Atlas-native
2FA setting exists on an individual's Atlas account is not enforced at Atlas login for a
federated user — MFA policy for Atlas access, given the current setup, lives entirely in
Google Workspace's own sign-in policy, not in any Atlas-side control.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed at the
2FA/federated-authentication section of the page.

---

### Finding 8: Domain restriction on the federation config controls invitation eligibility, not authentication bypass — its documented effect does not touch the disabled state 4Shark currently has

**Evidence:**

> "You can restrict access to your organization to an approved list of domains. This allows
> you to set the domains from which organization users can login without needing to directly
> map those domains to your IdP."

> "Once you enable the Restrict Access by Domain option:
> - You can only invite new users to join your organization whose email addresses are in the
>   approved list of domains.
> - Users who are already in your organization whose usernames do not contain a domain in
>   the approved list are not restricted access to your organization.
> - Any domains which are mapped to your IdP are automatically added to the approved list."

**Source:** https://www.mongodb.com/docs/atlas/security/manage-org-mapping/ and
https://www.mongodb.com/docs/atlas/security/federation-advanced-options/ (auxiliary
`mongodb-atlas-permissioning_doc_3.md`)

**Significance:** `identity/mongodb_federation.tf:21` sets `domain_restriction_enabled =
false` while `domain_allow_list = ["4shark.com.br"]` is still populated. The documented
behavior above describes only the *enabled* state's effect (gates new invitations; does not
retroactively restrict existing members). No fetched MongoDB source in this research
describes the *disabled* state's effect on a populated allow list — this is reported as an
open question, not a confirmed gap. What IS confirmed is that domain restriction, even when
enabled, is an invitation-eligibility gate, not an SSO/authentication bypass control — it is
a different control from the federation config's own IdP routing (which is what actually
determines whether a `4shark.com.br` email is directed to the Google SAML login).

**Verification:** URLs fetched (both) / Verbatim quotes checked / Quote substrings confirmed
in the "Considerations" section of the domain-restriction page.

---

### Finding 9: Auditing and attribution have a hard limit — the Activity Feed does not attribute individual data reads/writes, and database audit logs (opt-in) attribute to the connecting database username, not the person, when a credential is shared

**Evidence:**

> "In the updated Data Explorer interface, the Project Activity Feed no longer logs the
> usernames of Atlas users when they read or modify data. Although the Project Activity Feed
> no longer logs usernames, it continues to log user connections from the Atlas UI to a
> cluster."

> "Toggle the button next to Database Auditing to On." (auditing is opt-in, not default)

> "Database auditing lets administrators track system activity for deployments with multiple
> users."

**Source:** https://www.mongodb.com/docs/atlas/tutorial/activity-feed/ and
https://www.mongodb.com/docs/atlas/database-auditing/ (auxiliary
`mongodb-atlas-permissioning_doc_4.md`)

**Significance:** this bears directly on the shared-credential gap identified in
`app-beta-001/mongodb.tf:60-84` (`/beta-001/MONGO_USERNAME` + `/beta-001/MONGO_PASSWORD`, one
credential for the whole application/team). Two independent limits compound: (a) the Atlas
UI's own Activity Feed no longer attributes individual data reads/writes to a named user at
all (per the fetched page, this applies to the "updated Data Explorer interface" — the scope
of "updated" was not further qualified in the fetched content); (b) even with database
auditing turned on (a separate, opt-in, paid-tier feature), an audit event attributes the
action to whatever database username performed it — if that username is the one shared
credential, auditing cannot disambiguate which individual engineer ran the query. No fetched
MongoDB source describes a mechanism to recover per-person attribution after the fact from a
shared credential.

**Verification:** URLs fetched (both) / Verbatim quotes checked / Quote substrings confirmed
in each page.

---

### Finding 10: MongoDB's current guidance favors service accounts (OAuth2.0) over classic Programmatic API Keys for automation; no Atlas-specific CIS benchmark exists

**Evidence:**

> "Service accounts use industry-standard OAuth2.0 to securely authenticate with Atlas
> through the Atlas Administration API. We recommend that you use service accounts instead
> of API keys when possible because they provide added security through short-lived access
> tokens and required credential rotations."

> "Assign the least privileged Atlas role required for the service account's intended
> purpose to adhere to the principle of least privilege."

> "Use an IP access list for your service accounts."

CIS benchmark status (community forum, non-staff post, confirmed by MongoDB staff reply in
the same thread):

> "Unfortunately there exists no dedicated MongoDB Atlas Benchmark" — and MongoDB staff
> (Stennie_X) confirming Atlas's underlying server config is not directly inspectable by
> customers: *"Atlas is a fully managed data service so end users do not have direct access
> to make changes to the MongoDB server configuration file or the backing instances for an
> Atlas cluster."*

**Source:** https://www.mongodb.com/docs/atlas/architecture/current/auth/authentication/ and
https://www.mongodb.com/community/forums/t/does-mongodb-atlas-meet-the-cis-center-of-internet-security-benchmark/189214
(auxiliary `mongodb-atlas-permissioning_doc_5.md`)

**Significance:** 4Shark's Terraform authenticates to the `mongodbatlas` provider via
`provider "mongodbatlas" {}` (`identity/providers.tf:5`) — the provider's standard credential
resolution, presumed to be the classic Programmatic API Key pair based on how the block is
written (no explicit `client_id`/`client_secret` OAuth argument visible in this file).
Whether the current setup is the classic API key or the newer OAuth service-account flow was
NOT independently confirmed by reading provider credential injection (out of scope for a
Terraform config file read — the actual credential source is environment/1Password-managed).
This is reported as an open question. On the benchmark side: no CIS benchmark specific to
Atlas exists; the published CIS "MongoDB Benchmark" targets self-managed server
configuration, a surface Atlas customers do not have direct access to.

**Verification:** URLs fetched (both) / Verbatim quotes checked / Quote substrings confirmed
in each source.

---

### Finding 11: MongoDB recommends private endpoints over IP access lists for every project, not only as an option

**Evidence:**

> "We recommend that you set up private endpoints for all new staging and production
> projects to limit the extension of your network trust boundary."

> "In general, we recommend using private endpoints for every Atlas project, because this
> approach provides the most granular security and eases the administrative burden that can
> come from managing IP access lists and large blocks of IP addresses as your cloud network
> scales."

**Source:** https://www.mongodb.com/docs/atlas/architecture/current/network-security/
(auxiliary `mongodb-atlas-permissioning_doc_2.md`)

**Significance:** 4Shark's current network control for `app-beta-001` is entirely IP-access-
list-based, built from VPC NAT Gateway EIPs (`app-beta-001/mongodb.tf:29-35`,
`modules/mongodb_atlas/network.tf:1-7` — a per-entry `mongodbatlas_project_ip_access_list`
resource, not an authoritative/exclusive list resource). MongoDB's own architecture guidance
frames private endpoints as the general recommendation for every project, not a
production-only upgrade — a permissioning redesign that touches network access would be
extending, not replacing, IP-access-list management (self-service network access, as the
engineer's brief frames it) against a control MongoDB itself frames as secondary to private
endpoints.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed in the
"Network Security" architecture guidance page.

---

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| IdP-group → Org-role JIT mapping (`mongodbatlas_federated_settings_org_role_mapping`), MongoDB's own documented pattern | MongoDB-endorsed for `Organization Owner` specifically; the vaulted-service-account half of the pattern resembles 4Shark's existing break-glass account (`identity/guard.tf`) | Documented ONLY for `Organization Owner`, not project roles; the resource does not currently exist anywhere in 4Shark's Terraform — today's org role assignment uses `mongodbatlas_cloud_user_org_assignment` (`identity/mongodb_org.tf:1-9`), a direct per-user grant, so adopting this means introducing a new resource type, not extending one already in place; the group-JIT half is unlike `/elevate-aws-access` (group-membership-based, not token-based) and its effect is next-login-only in both directions (no immediate grant or revoke); generalizing to project-level roles is an extrapolation 4Shark would be making, not a documented MongoDB pattern | `mongodb-atlas-permissioning_doc_3.md` |
| Keep static `engineers-elevated` team + `GROUP_CLUSTER_MANAGER` assignment, add members manually when elevation is needed | Simple, already-scaffolded in Terraform (`mongodb_teams.tf:17-19,42-49`); no reliance on undocumented project-level JIT mapping | Manual add/remove step (a person, e.g. break-glass account owner, must run Terraform each time) — not self-service; still static once granted, no automatic timeout | Current-state read, `mongodb_teams.tf` |
| Per-engineer database users (data-plane) instead of one shared credential | Restores per-person attribution even without database auditing turned on (Activity Feed and audit logs both key off the database username, so distinct usernames = distinct attribution); matches practitioner guidance ("Create dedicated users for each application. Avoid shared credentials") | Practitioner source recommends per-application, not explicitly per-engineer, credentials — 4Shark would be extending the practice, not following a literal precedent; still a password-based credential unless combined with Workforce OIDC | `mongodb-atlas-permissioning_doc_5.md` (howtoharden.com), `mongodb-atlas-permissioning_doc_4.md` (attribution mechanics) |
| Workforce Identity Federation (OIDC) for human database login via Google | Would eliminate the shared password entirely if it worked, tying database login to the same Google identity already used for Atlas SSO | Google Workspace is not in MongoDB's officially named OIDC IdP list (only Entra ID, Okta, Ping Identity); unresolved community report of a concrete Google-specific blocker; even where it works, only MongoDB Shell/Compass are named as supporting clients — not `mongodump` | `mongodb-atlas-permissioning_doc_4.md` |
| `Project Network Access Manager` delegated to a non-admin engineer for self-service IP-list changes | Narrower than `Project Owner`; matches the "self-service network access" framing in the brief; documented on the canonical IP Access List reference page | Also grants VPC peering and PrivateLink changes — broader blast radius than "just IP list" suggests; a second, contradicting MongoDB how-to page tells readers only `Project Owner` can add an IP, so the narrower role is easy to miss designing against | `mongodb-atlas-permissioning_doc_1.md`, `mongodb-atlas-permissioning_doc_2.md` |
| Private endpoints instead of IP access lists | MongoDB's general recommendation for every project, not just production; removes public internet exposure entirely | Requires re-architecting current NAT-Gateway-EIP-based network control (`app-beta-001/mongodb.tf:29-35`); M10+ tier requirement already met but implementation effort not scoped in this research | `mongodb-atlas-permissioning_doc_2.md` |
| Service accounts (OAuth2.0) instead of classic Programmatic API Keys for Terraform | MongoDB's current recommendation for automation; short-lived tokens, required rotation | Whether the `mongodbatlas` Terraform provider version 4Shark uses supports the service-account auth flow was not confirmed in this research | `mongodb-atlas-permissioning_doc_5.md` |

## What remains uncertain

- Whether the `mongodbatlas_federated_settings_org_role_mapping` pattern (or an equivalent)
  can be applied at the **project** level via Terraform, not just the organization level —
  no MongoDB source found in this research documents project-level IdP-group role mapping;
  only the org-level resource and org-level JIT pattern were confirmed.
- What the **disabled** state of `domain_restriction_enabled` does to a populated
  `domain_allow_list` (`identity/mongodb_federation.tf:21-22`) — MongoDB's docs describe only
  the enabled state's effect (gates invitations). Not found: an explicit statement of the
  disabled state's behavior.
- Whether 4Shark's current `mongodbatlas` Terraform provider authentication
  (`identity/providers.tf:5`) uses the classic Programmatic API Key or the newer OAuth
  service-account flow — not verified from the Terraform files alone (credential source is
  environment/1Password-managed, outside this research's file-read scope).
- The exact minimum cluster tier for Database Auditing — the primary MongoDB doc page
  fetched confirmed Free/Flex tiers are excluded but did not state a specific minimum tier
  number in the retrieved excerpt; a secondary (community) source stated "M10 and larger,"
  which is consistent with but not independently confirmed against the primary doc.
- Why the two MongoDB docs on IP Access List management (Finding 2) contradict each other —
  not found: any MongoDB changelog, errata, or explanation reconciling the two pages.
- Whether MongoDB has published guidance more specific than "assign the lowest-needed RBAC
  roles" for a team the size of 4Shark's (2-3 platform engineers) — not found in official
  MongoDB sources; the only size-specific number found ("Organization Owner ... 2-3 people")
  came from an independent, non-MongoDB practitioner guide (`howtoharden.com`), not from
  MongoDB itself.

## Suggested options for main and the engineer

- **Option A — Adopt the MongoDB-documented org-level JIT pattern as-is (Org Owner only), keep project elevation manual.** Introduce `mongodbatlas_federated_settings_org_role_mapping` — a new resource type, not currently used anywhere in 4Shark's Terraform (today's org role assignment uses the structurally different `mongodbatlas_cloud_user_org_assignment`, `identity/mongodb_org.tf:1-9`) — for a break-glass/JIT `Organization Owner` group, matching MongoDB's own documented pattern exactly (Finding 4). This means wiring a new Google Workspace group into Atlas federation, not extending an existing mechanism. Leave `engineers-elevated` project-level elevation as a manual Terraform-applied step (add/remove team membership), since no MongoDB source documents project-level JIT mapping.
- **Option B — Extend IdP-group role mapping to project roles as an unofficial pattern.** Apply the same Google-group → role-mapping mechanism to project roles (e.g. `GROUP_CLUSTER_MANAGER`), accepting this is an extrapolation beyond MongoDB's documented scope, with the same next-login-only latency characteristic confirmed in Finding 4.
- **Option C — Fix the baseline/elevated split at the data-access-grant level.** Since `GROUP_DATA_ACCESS_READ_WRITE` is Atlas-UI-Data-Explorer-only (Finding 1 auxiliary), decide separately whether UI-based data read-write on productive projects should sit in baseline at all, independent of what happens with `GROUP_CLUSTER_MANAGER`/elevated.
- **Option D — Address the shared database credential independent of the control-plane redesign.** Options include per-engineer database users (practitioner-corroborated, Finding 5/trade-offs), or Workforce OIDC (blocked/unconfirmed for Google per Finding 6) — these are data-plane changes orthogonal to the org/project role redesign.
- **Option E — Delegate `Project Network Access Manager` for self-service network access**, accepting the broader-than-IP-list scope (VPC peering, PrivateLink) documented in Finding 3, or evaluate migrating to private endpoints per MongoDB's general recommendation (Finding 11) as a longer-effort alternative.
- **Option F — Move Terraform's `mongodbatlas` provider auth to the OAuth service-account model** MongoDB currently recommends over classic Programmatic API Keys (Finding 10), pending confirmation of provider version support.

(No recommendation among these — surfaced as options per the engineer's brief; main and the
engineer choose.)
