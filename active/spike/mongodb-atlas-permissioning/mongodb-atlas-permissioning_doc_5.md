# Auxiliary source — Programmatic API keys / service accounts, CIS benchmark, practitioner corroboration

Preserved fetched content supporting SPIKE.md Finding 10 and the trade-offs table.

## Source: https://www.mongodb.com/docs/atlas/architecture/current/auth/authentication/

> "Service accounts use industry-standard OAuth2.0 to securely authenticate with Atlas
> through the Atlas Administration API. We recommend that you use service accounts instead
> of API keys when possible because they provide added security through short-lived access
> tokens and required credential rotations."

> "Assign the least privileged Atlas role required for the service account's intended
> purpose to adhere to the principle of least privilege."

> "Use an IP access list for your service accounts."

> "Follow best practices for rotating API keys regularly. To learn how to rotate these keys
> with HashiCorp Vault, for example, see the Hashicorp documentation."

> "You can manage programmatic access for service accounts by using the Atlas UI, Atlas CLI,
> Atlas Administration API, and Terraform."

> "For development and test environments, you can also use SCRAM. Consider creating
> temporary database users with just-in-time database access."

**Significance**: MongoDB's own current guidance names **service accounts (OAuth2.0,
short-lived tokens)** as the recommended mechanism over classic Programmatic API Keys
(long-lived key pairs) for automation — 4Shark's Terraform provider currently authenticates
via the classic Programmatic API Key model (`identity/providers.tf:5`,
`provider "mongodbatlas" {}` reading credentials from environment, per the provider's
standard auth resolution — the provider block itself carries no visible key material). This
is presented as an option for the engineer's consideration, not a finding that the current
setup is wrong — Terraform provider support for the newer service-account OAuth flow was
not independently verified in this research.

## Source: https://www.cisecurity.org/benchmark/mongodb and https://www.mongodb.com/community/forums/t/does-mongodb-atlas-meet-the-cis-center-of-internet-security-benchmark/189214

CIS publishes a **MongoDB Benchmark** — for self-managed MongoDB Server deployments — not an
Atlas-specific benchmark. From the MongoDB community forum (Raoul Becke, non-staff post):

> "Unfortunately there exists no dedicated MongoDB Atlas Benchmark"

MongoDB staff member Stennie_X responded (same thread):

> "MongoDB Atlas meets higher standards of security than the CIS benchmark, including regular
> independent third party verification for compliance with multiple international security
> and privacy standards."

> "most of those are at a lower level than end users have access to. Atlas is a fully managed
> data service so end users do not have direct access to make changes to the MongoDB server
> configuration file or the backing instances for an Atlas cluster."

**Significance**: there is no CIS-style benchmark specific to Atlas RBAC/permissioning that
this research could locate. The CIS MongoDB Benchmark targets the self-managed server
configuration surface (auth mechanisms, file permissions, network binding) that Atlas
customers do not control directly — it is not a fit substitute for an Atlas
control-plane/data-plane permissioning benchmark.

## Practitioner corroboration (independent, non-MongoDB — treated as community opinion, not vendor guidance)

### https://howtoharden.com/guides/mongodb-atlas/

> "Limiting Organization Owner assignments prevents broad, unchecked control over billing,
> clusters, and security settings"

Recommends restricting `Organization Owner` to "2-3 people" and distributing project-level
roles by function (Data Access Admin, Cluster Manager, Read Only).

> "IP allowlisting limits exposure to known addresses" (positions IP allow-listing as a
> weaker "L1" control)

> "Private endpoints eliminate public internet exposure. Traffic stays within cloud provider
> network" (positions private endpoints as the stronger "L2", "more secure than IP
> allowlisting alone" for production, M10+ tier required)

> "Create dedicated users for each application. Avoid shared credentials"

This source recommends per-application (not necessarily per-engineer) database users and
does not address API key/service-account lifecycle hardening specifics.

### https://oneuptime.com/blog/post/2026-03-31-mongodb-atlas-access-roles-permissions/view

Independent practitioner walkthrough of org/project roles via CLI and Terraform examples.
Cites no MongoDB documentation and offers no small-team-specific or elevation-specific
recommendation — confirmed by direct re-query of the fetched content. Included here only to
document that it was checked and found not to add material beyond what MongoDB's own docs
already establish.
