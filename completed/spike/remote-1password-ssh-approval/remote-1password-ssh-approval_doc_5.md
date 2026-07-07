# Auxiliary source — 1Password Service Accounts: mechanics, limitations, coexistence

## Source: Service Accounts overview
- Canonical URL: https://developer.1password.com/docs/service-accounts/
- Resolved URL (301 redirect): https://www.1password.dev/service-accounts/
- Fetched: 2026-07-06

> 1Password Service Accounts help automate secrets management in your applications and infrastructure without the need to deploy additional services.

> You control which vaults and Environments are accessible and which actions the service account can perform.

> You can see what items a service account accesses by creating a usage report.

Six use cases listed on the page: provisioning web services with secrets, creating test
environments, loading secrets into CI/CD pipelines, securing infrastructure secrets, automating
secrets management scripts, and streamlining development workflows. No SSH agent use case is
listed among them.

## Source: Use service accounts with 1Password CLI
- Canonical URL: https://developer.1password.com/docs/service-accounts/use-with-1password-cli
- Resolved URL (301 redirect): https://www.1password.dev/service-accounts/use-with-1password-cli
- Fetched: 2026-07-06

> export OP_SERVICE_ACCOUNT_TOKEN=<your-service-account-token>

Commands confirmed to work with a Service Account token: `op read`, `op inject`, `op run`,
`op vault create`, plus `op item` and `op document` management (requiring `--vault` when the
account can access multiple vaults). Commands confirmed NOT supported: `op connect`, `op group`,
user-provisioning commands, `op events-api`, `op vault edit`. No `op` subcommand related to the
SSH agent (there is no `op ssh-agent` management command in the product at all — the SSH agent is
started and controlled by the 1Password desktop app, not the CLI) appears in either the supported
or unsupported list on this page.

## Source: Get started with 1Password Service Accounts
- Canonical URL: https://developer.1password.com/docs/service-accounts/get-started
- Resolved URL (301 redirect): https://www.1password.dev/service-accounts/get-started
- Fetched: 2026-07-06

> op service-account create <serviceAccountName> --expires-in <duration> --vault <vault-name:<permission>,<permission>

> The service account creation wizard only shows the service account token once. Save the token in 1Password immediately to avoid losing it.

> Service account permissions, vault access, and Environment access are immutable. If you want to grant a service account access to additional vaults or Environments, change the permissions ... you'll need to create a new service account with the appropriate permissions and access.

Permissions available at creation: `read_items`, `write_items` (requires `read_items`),
`share_items` (requires `read_items`).

## Source: 1Password Service Account security
- Canonical URL: https://developer.1password.com/docs/service-accounts/security
- Resolved URL (301 redirect): https://www.1password.dev/service-accounts/security
- Fetched: 2026-07-06

> It's up to you to save and protect the service account token.

> You can rotate or revoke service account tokens.

> You might want to revoke or rotate a service account token if a service account token became compromised or you need to comply with a security policy that requires regular token rotation.

> A service account token associated with a deleted service account can't authenticate.

No page in the Service Accounts documentation tree fetched for this spike recommends a specific
OS-level secure-storage mechanism (Keychain, Secret Service, Credential Manager) for the token on
a developer workstation. The stated position is that protecting the token is the operator's
responsibility, full stop.

## Source: 1Password SSH agent — Get started (prerequisites)
- Canonical URL: https://developer.1password.com/docs/ssh/get-started/
- Resolved URL (301 redirect): https://www.1password.dev/ssh/get-started/
- Fetched: 2026-07-06

Prerequisites listed for Mac, Windows, and Linux each read, in the same shape: "Sign up for
1Password" and "Install and sign in to 1Password for [platform]." No Service Account token
appears anywhere in the prerequisites for any platform.

## Source: 1Password Community — "How to use service accounts and regular accounts in the same environment?"
- URL: https://www.1password.community/discussions/developers/how-to-use-service-accounts-and-regular-accounts-in-the-same-environment/97657
- Fetched: 2026-07-06

Question: can a Service Account and a personal (signed-in) account be used simultaneously in the
same environment with the 1Password CLI?

Official reply, attributed to 1Password staff member Horia Culea:

> Indeed it is not possible to use a user account with a service account token in the environment. This is by design, as we intend the service accounts credentials to only exist within the scope of their usage.

Suggested workaround from the same reply:

> you could use an envvar with a different name (e.g. having the token exported as `OP_SERVICE_ACCOUNT_TOKEN_GLOBAL`) and move its value to `OP_SERVICE_ACCOUNT_TOKEN` at the beginning of the scripts

This exchange is specifically about the `op` CLI's own environment-variable resolution (the CLI
picks `OP_SERVICE_ACCOUNT_TOKEN` over a signed-in personal session whenever the variable is set in
that process's environment). It does not state, and this research found no separate statement
either way, on whether setting this variable in a shell also affects the independently-running
1Password SSH agent background process (which authenticates via the desktop app's own session,
not via `op` CLI environment variables read per-invocation).
