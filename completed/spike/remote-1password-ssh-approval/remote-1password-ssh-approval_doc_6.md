# Auxiliary source — Non-interactive git+SSH extraction pattern, agent coexistence, WSL

## Source: `op read` command reference
- Canonical URL: https://developer.1password.com/docs/cli/reference/commands/read/
- Resolved URL (301 redirect): https://www.1password.dev/cli/reference/commands/read
- Fetched: 2026-07-06

> Write the secret to a file instead of stdout. [describing `--out-file`]

`--file-mode` sets the file permission mode for the output file (default `0600`); the flag has no
effect without `--out-file`.

> op read --out-file ./key.pem op://app-prod/server/ssh/key.pem

> op read "op://app-prod/ssh key/private key?ssh-format=openssh"

No explicit security warning about writing a private key to disk appears on this reference page —
it documents the mechanism, not its risk profile.

## Source: 1Password GitHub Action — load-secrets-action
- Canonical URL: https://github.com/1Password/load-secrets-action
- Fetched: 2026-07-06

> When loading SSH keys, you can specify the format using the `ssh-format` query parameter. This is useful when you need the private key in a specific format like OpenSSH.

Example given:

```
SSH_PRIVATE_KEY: op://vault/item/private key?ssh-format=openssh
```

The action extracts the raw key material as an output/environment value; the `ssh-format`
parameter only controls the output encoding of that extracted key, it does not interface with the
1Password SSH agent.

## Source: 1Password SSH agent — Advanced use cases (agent coexistence, per-host routing)
- Canonical URL: https://developer.1password.com/docs/ssh/agent/advanced/
- Resolved URL (301 redirect): https://www.1password.dev/ssh/agent/advanced/
- Fetched: 2026-07-06

> The 1Password SSH agent can run alongside another SSH agent, like the OpenSSH agent.

Example SSH client config, selective 1Password usage:

```
Host raspberry-pi
  IdentityAgent ~/.1password/agent.sock
Host ec2-server
  IdentityFile ~/.ssh/ssh-key-not-on-1password.pem
```

Example SSH client config, 1Password as default with a named exception:

```
Host *
  IdentityAgent ~/.1password/agent.sock
Host ec2-server
  IdentityAgent none
  IdentityFile ~/.ssh/ssh-key-not-on-1password.pem
```

Windows limitation, stated explicitly:

> Windows doesn't have the same flexibility with the `~/.ssh/config` file as macOS and Linux, because Microsoft OpenSSH listens to a fixed pipe.

Consequence stated: on Windows, the 1Password SSH agent authenticates for all hosts, without the
per-host selective configuration available on macOS/Linux.

## Source: 1Password WSL (Windows Subsystem for Linux) integration — official
- Canonical URL: https://developer.1password.com/docs/ssh/integrations/wsl/
- Resolved URL (301 redirect): https://www.1password.dev/ssh/integrations/wsl/
- Fetched: 2026-07-06

> The 1Password Windows Subsystem for Linux (WSL) integration allows you to authenticate SSH and Git commands and sign your Git commits within WSL using the 1Password SSH agent running on your Windows host.

> The 1Password integration supports both WSL 1 and WSL 2.

Prerequisite listed: "Install and sign in to 1Password for Windows." The integration relays
requests to "the Windows OpenSSH client (`ssh.exe`)," which then talks to the Windows-hosted
1Password SSH agent — so the Windows desktop app (and whatever unlock method it is configured
with, Windows Hello included) is the authentication gateway for this specific integration. No
mention of Service Accounts or a native Linux `op` binary appears on this page as an alternative
non-interactive path.

## 4Shark's existing WSL wiring (internal source, not external)

- File: `~/.claude/commands/op-signin.md` (4Shark repository, read directly — not a web fetch)

> `/usr/local/bin/op` is a wrapper script that forwards all `op` commands to `op.exe` (the Windows binary) via WSL interop. Because execution happens on the Windows side, the 1Password desktop app authenticates via Windows Hello — no master password or session token required.

This confirms 4Shark's current WSL setup (relevant to Emerson's machine) already follows the
official pattern above: the interactive/biometric path in WSL goes through `op.exe` on the
Windows side, gated by Windows Hello. A Service-Account-token path does not need this wrapper at
all — a Service Account only needs the `OP_SERVICE_ACCOUNT_TOKEN` environment variable plus any
`op` CLI binary (Windows or Linux) — but installing it under the SAME path (`/usr/local/bin/op`)
that the existing skill already reserves for the `op.exe` wrapper would need to be avoided or
deliberately re-architected, since the two are mutually exclusive within one process environment
per `remote-1password-ssh-approval_doc_5.md`'s coexistence finding.

## Source: Installing a native 1Password CLI binary in WSL (community, not official 4Shark or 1Password doc)
- URL: https://gist.github.com/WillianTomaz/a972f544cc201d3fbc8cd1f6aeccef51
- Fetch status: content extracted via WebFetch; this is a community gist, not a 1Password-official
  or 4Shark-official source — treated as illustrative only, not authoritative

Describes bridging the SSH agent socket between WSL and Windows using `npiperelay.exe` and
`socat`, forwarding `SSH_AUTH_SOCK` inside WSL to the Windows-hosted agent. Does not discuss
Service Accounts. A commenter on the same gist notes the official 1Password WSL doc (cited above,
`developer.1password.com/docs/ssh/integrations/wsl/`) as the current supported path, which this
SPIKE treats as authoritative over the gist for anything the two disagree on.
