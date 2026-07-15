# Auxiliary source — Workforce/Workload OIDC, custom database roles, auditing, attribution

Preserved fetched content supporting SPIKE.md Findings 5, 6, and 9.

## Source: https://www.mongodb.com/docs/atlas/workforce-oidc/

> "Workforce Identity Federation is supported by Atlas dedicated clusters (M10 and above)
> running MongoDB version 7.0.11 and above."

> "register your OIDC application with an IdP that supports OIDC standard, such as Microsoft
> Entra ID, Okta, or Ping Identity."

Google Workspace is not named anywhere in this page as a supported OIDC IdP for Workforce
Identity Federation — only Microsoft Entra ID, Okta, and Ping Identity are named.

> "You need to use MongoDB Shell or Compass to access Atlas with Workforce Identity
> Federation."

## Source: https://www.mongodb.com/community/forums/t/workforce-identity-federation-with-oidc-to-support-google/295993

Community forum thread, NOT MongoDB official documentation — treated as a corroborating
community report, not vendor guidance. User "rmart001" (Rafael) states:

> "Today I tried to set up OIDC for Workforce and grant access to the database using my IdP
> (Google), but the current implementation doesn't support ClientID + Client Secret and when
> using Google as IdP we must use both, otherwise the flow won't work properly."

No official MongoDB staff response confirming or denying this limitation was present in the
fetched thread content. Two other users in the same thread report analogous integration
friction with other IdPs. This is reported as an unresolved, unofficial, community-observed
gap — not a MongoDB-documented limitation.

## Source: https://www.mongodb.com/docs/database-tools/authentication/

> "Starting in 100.11.0, database tools support Atlas Workload Identity Federation. Use
> Workload Identity Federation to authenticate connections to MongoDB on Microsoft Azure and
> Google Cloud Platform."

Only Workload (machine) OIDC is named as supported by the Database Tools (which include
`mongodump`); the fetched page names no support for Workforce (human) OIDC in the Database
Tools, and the documented Workforce OIDC client list above (MongoDB Shell, Compass) does not
include `mongodump`.

## Source: https://www.mongodb.com/docs/atlas/security-add-mongodb-roles/

> "You can create custom roles in Atlas when the built-in roles don't include your desired
> set of privileges."

> "You can create up to 100 custom roles per project by default."

> "The privilege actions available for custom roles and the custom roles API represent a
> subset of the privilege actions available for built-in roles."

Required permissions to configure custom database roles: `Organization Owner`, `Project
Owner`, or `Project Database Access Admin` (per the same page).

## Source: https://www.mongodb.com/docs/atlas/security-add-mongodb-users/

> "A database user's access is determined by the roles assigned to the user. When you create
> a database user, any of the built-in roles add the user to all clusters in your Atlas
> project. To specify which resources a database user can access in your project, you can
> select the option Restrict Access to Specific Clusters in the Atlas UI or set specific
> privileges and custom roles."

> "Atlas supports creating temporary database users that automatically expire within a
> user-configurable 7-day period."

> "Atlas audits the creation, deletion, and updates of both temporary and non-temporary
> database users in the project's Activity Feed."

Note the wording discrepancy across MongoDB's own pages: the Architecture Center
(`architecture/current/auth/authorization/`) describes fixed options of "6 hours, 1 day, or
1 week"; this page describes "a user-configurable 7-day period." Both are quoted as found;
this SPIKE does not attempt to reconcile the wording difference — it is reported as an open
question.

## Source: https://www.mongodb.com/docs/atlas/database-auditing/

> "Toggle the button next to Database Auditing to On." (confirms auditing is off by default,
> not an automatically-active feature)

> "Database auditing lets administrators track system activity for deployments with multiple
> users."

Database auditing is unavailable on Free and Flex tier clusters (a paid, dedicated tier is
required — the fetched page did not state an exact minimum tier number in the excerpt
retrieved, only that Free/Flex are excluded). A separate community search result (not
independently re-fetched against the primary doc page in this session) stated auditing is
supported for M10 and larger; this is reported with lower confidence and marked
accordingly in the SPIKE.

## Source: https://www.mongodb.com/docs/atlas/tutorial/activity-feed/

> "In the updated Data Explorer interface, the Project Activity Feed no longer logs the
> usernames of Atlas users when they read or modify data. Although the Project Activity Feed
> no longer logs usernames, it continues to log user connections from the Atlas UI to a
> cluster."

The Activity Feed records project/organization-level control-plane events (billing, access,
auto-scaling, connections) — the fetched content does not describe it as recording
document-level data access/query content; it explicitly disclaims username-level attribution
for Data Explorer read/modify actions in the updated interface. To track actual data-plane
access, the page points to database audit logs with custom filters targeting
`atlasDataAccessReadWrite` / `atlasDataAccessReadOnly` / `atlasDataAccessAdmin` roles.

**Significance for the shared-credential problem**: even with database auditing turned on,
an audit log attributes an action to the **database username** used for the connection —
not to the individual engineer — when multiple engineers connect through one shared
database user (as in `app-beta-001/mongodb.tf:60-84`, `/beta-001/MONGO_USERNAME` +
`/beta-001/MONGO_PASSWORD`). No fetched MongoDB source describes a mechanism by which a
shared database credential can be disambiguated into per-person attribution after the fact.
