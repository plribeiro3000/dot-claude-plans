# Auxiliary source — Federated auth, role mapping (JIT), and MFA bypass

Preserved fetched content supporting SPIKE.md Finding 4 (elevation) and Finding 7 (MFA/SSO).

## Source: https://www.mongodb.com/docs/atlas/security/federated-authentication/

> "Atlas bypasses 2FA for users who authenticate with federated authentication through your
> IdP. If a user authenticates through your IdP and has 2FA for their Atlas account enabled,
> Atlas doesn't prompt the user for 2FA."

> "Instead, you can configure your trusted IdP to prompt users for 2FA."

## Source: https://www.mongodb.com/docs/atlas/security/manage-role-mapping/

> "Atlas applies the role mappings when you log in."

> "If a federated user logs in but doesn't belong to an IdP group mapped to a desired
> organization, Atlas removes the mapped role from the user in that organization and its
> projects."

> "Consider a scenario where a user belongs to the admin IdP group. You have configured a
> role mapping of admin to the Organization Owner in Organization A. If you remove that user
> from the admin IdP group, Atlas deletes that users' Organization Owner role when the user
> next logs in."

> "Every organization must have at least one user that has the Organization Owner role. If
> removing a role removes the last owner from an organization, the removal fails."

> "Created an IdP application. This application must have a SAML attribute named to
> memberOf. Map this attribute to the IdP source attributes for groups. This attribute links
> the IdP groups with your Atlas roles."

**Significance**: role-mapping changes (grant AND revoke) apply only at the user's next
login — there is no server-side push, no immediate revocation. This is the load-bearing
latency caveat for using IdP-group-to-Atlas-role mapping as an elevation lever: a member
moved into (or out of) an elevated Google group does not gain (or lose) the mapped Atlas
role until their next Atlas login.

## Source: https://www.mongodb.com/docs/atlas/architecture/current/auth/authorization/

> "You should always restrict access by assigning the lowest-needed RBAC roles. You should
> also use domain restrictions."

> "Because a Project Owner can create and delete clusters, you should assign this role to a
> programmatic service account unless you are working in a sandbox environment."

> "By integrating Atlas with a federated identity provider, you can use just-in-time
> provisioning by mapping identity provider groups to Atlas roles. This streamlines access
> management and ensures secure and organized role assignments throughout the platform."

> "Atlas also supports creating temporary database users that automatically expire after the
> predefined times. A user can be created for 6 hours, 1 day, or 1 week."

> "The Organization Owner role should be heavily restricted and not assigned to a human, as
> it has the ability to change organization-wide settings and delete configurations. This
> role should be assigned to a service account which you use only to initially set up and
> configure the organization. Minimize configuration changes after the initial creation. To
> avoid account lockouts, you can create the following items:
> - SAML Organization Owner group with Just-in-Time Access.
> - Service account with the Organization Owner role. Keep it in a secure place with strong
>   access management for break-glass emergency scenarios."

**Significance**: this is MongoDB's own documented pattern that maps directly onto 4Shark's
AWS break-glass model — a SAML/IdP group mapped to `Organization Owner` used as the
just-in-time elevation lever, paired with a standing, vaulted service-account owner for
emergencies. It is presented specifically for `Organization Owner`, not for project-level
roles generally, and MongoDB does not, anywhere found in this research, describe an
analogous native mechanism for temporary elevation of *project*-level roles (e.g.
`GROUP_CLUSTER_MANAGER`) — the same IdP-group-mapping technique would have to be
generalized by the customer, it is not itself documented at the project-role level.

## Source: https://www.mongodb.com/docs/atlas/security/manage-org-mapping/ and https://www.mongodb.com/docs/atlas/security/federation-advanced-options/

> "You can restrict access to your organization to an approved list of domains. This allows
> you to set the domains from which organization users can login without needing to directly
> map those domains to your IdP."

> "Once you enable the Restrict Access by Domain option:
> - You can only invite new users to join your organization whose email addresses are in the
>   approved list of domains.
> - Users who are already in your organization whose usernames do not contain a domain in
>   the approved list are not restricted access to your organization.
> - Any domains which are mapped to your IdP are automatically added to the approved list."

**Significance**: the documented effect of "Restrict Access by Domain" is scoped to
**invitation eligibility** — it gates who can be *invited*, and explicitly does not
retroactively restrict existing members. Nothing in the fetched text describes this
setting as an authentication/SSO-bypass gate. This bears on the current-state fact that
`identity/mongodb_federation.tf:21` sets `domain_restriction_enabled = false` with
`domain_allow_list = ["4shark.com.br"]` still populated — per the documented behavior above,
the populated allow list has no restrictive effect while the flag is `false` (no fetched
MongoDB source states what happens to the allow list's enforcement when the flag is
disabled beyond the "once you enable" framing, so this is reported as the literal,
documented scope of the enabled state; MongoDB does not describe the disabled state's
implications explicitly in the fetched pages — flagged as unresolved in the SPIKE's open
questions).
