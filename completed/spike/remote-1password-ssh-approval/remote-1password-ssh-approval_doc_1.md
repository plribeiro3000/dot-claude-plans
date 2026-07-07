# Auxiliary source — 1Password official developer documentation

Consolidated verbatim excerpts extracted via WebFetch from 1Password's official developer
documentation. Each excerpt below was independently re-fetched at least once and the quoted
substring was confirmed present both times (citation self-check).

## Source: SSH agent security
- Canonical URL: https://developer.1password.com/docs/ssh/agent/security
- Resolved URL (301 redirect target): https://www.1password.dev/ssh/agent/security
- Fetched: 2026-07-06

> The authorization prompt indicates which process is requesting permission to use which SSH key.

> a session is established between the key and the process the SSH command was run from (a process can be a terminal window or tab, an IDE, or a GUI application, like a Git or SFTP client).

> [approval methods] will vary depending on your device, operating system version, 1Password settings, and other factors.

> If the SSH key you're approving belongs to an account that uses 1Password Unlock with SSO, you may be redirected to the sign-in page for your identity provider.

> Your private keys never leave 1Password, are never stored locally, and are never used without your consent.

## Source: SSH agent forwarding
- Canonical URL: https://developer.1password.com/docs/ssh/agent/forwarding/
- Resolved URL (301 redirect target): https://www.1password.dev/ssh/agent/forwarding/
- Fetched: 2026-07-06

> Instead of storing your private keys on the remote host, you can use SSH agent forwarding to forward your requests to your local 1Password SSH Agent.

> authorize the request with biometrics without your private keys ever leaving the local 1Password process.

> The 1Password app on your local machine should prompt you to authorize the request.

> If someone else were to gain access to the remote environment as the same OS user, they'd be able to use the SSH key to authenticate connections from the remote host for the duration of the session.

> Only use agent forwarding when you need it and in environments that you trust are secure.

> always scope the `ForwardAgent yes` directive down to a specific host or domain.

## Source: Service Accounts overview
- Canonical URL: https://developer.1password.com/docs/service-accounts/
- Resolved URL (301 redirect target): https://www.1password.dev/service-accounts/
- Fetched: 2026-07-06

> 1Password Service Accounts help automate secrets management in your applications and infrastructure without the need to deploy additional services.

> an authentication method for 1Password CLI that isn't associated with an individual

> You control which vaults and Environments are accessible and which actions the service account can perform.

> You can see what items a service account accesses by creating a usage report

> Using a service account helps you implement the principal of least privilege and avoid the limitations of personal accounts (for example, SSO and MFA requirements).

Note: "principal of least privilege" appears exactly this way (not "principle") in the extracted
text returned by the fetch tool; preserved verbatim rather than silently corrected.
