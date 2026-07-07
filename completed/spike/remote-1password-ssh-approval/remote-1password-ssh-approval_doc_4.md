# Auxiliary source — Claude Code official docs: Claude Code on the web, Security, Desktop/Dispatch

## Source: Claude Code on the web
- URL: https://code.claude.com/docs/en/claude-code-on-the-web
- Fetched: 2026-07-06 (full page persisted at fetch time)

> Claude Code on the web runs tasks on Anthropic-managed cloud infrastructure at claude.ai/code. Sessions persist even if you close your browser, and you can monitor them from the Claude mobile app.

> Each session runs in a fresh Anthropic-managed VM with your repository cloned.

GitHub authentication table (reproduced):

| Method | How it works | Best for |
|---|---|---|
| GitHub App | Authorize the Claude GitHub App during web onboarding. | Browser onboarding; teams that want Auto-fix |
| `/web-setup` | Run `/web-setup` in your terminal to sync your local `gh` CLI token to your Claude account. | Individual developers who already use `gh` |

"What's available in cloud sessions" table, relevant rows (reproduced):

> Static API tokens and credentials | No | No dedicated secrets store exists yet.

> Interactive auth like AWS SSO | No | Not supported. SSO requires browser-based login that can't run in a cloud session

> A dedicated secrets store is not yet available. Both environment variables and setup scripts are stored in the environment configuration, visible to anyone who can edit that environment. If you need secrets in a cloud session, add them as environment variables with that visibility in mind.

### GitHub proxy

> For security, all GitHub operations go through a dedicated proxy service that transparently handles all git interactions. Inside the sandbox, the git client authenticates using a custom-built scoped credential. This proxy:
> - Manages GitHub authentication securely: the git client uses a scoped credential inside the sandbox, which the proxy verifies and translates to your actual GitHub authentication token
> - Restricts git push operations to the current working branch for safety
> - Enables cloning, fetching, and PR operations while maintaining security boundaries

### Security and isolation

> Isolated virtual machines: each cloud session runs in an isolated, Anthropic-managed VM

> Credential protection: sensitive credentials such as git credentials or signing keys are never inside the sandbox with Claude Code. Authentication is handled through a secure proxy using scoped credentials.

## Source: Security (code.claude.com/docs/en/security)
- URL: https://code.claude.com/docs/en/security
- Fetched: 2026-07-06

> Remote Control sessions work differently: the web interface connects to a Claude Code process running on your local machine. All code execution and file access stays local, and the same data that flows during any local Claude Code session travels through the Anthropic API over TLS. No cloud VMs or sandboxing are involved. The connection uses multiple short-lived, narrowly scoped credentials, each limited to a specific purpose and expiring independently, to limit the blast radius of any single compromised credential.

> When using Claude Code on the web, additional security controls are in place:
> - Isolated virtual machines: Each cloud session runs in an isolated, Anthropic-managed VM
> - Credential protection: Authentication is handled through a secure proxy that uses a scoped credential inside the sandbox, which is then translated to your actual GitHub authentication token
> - Branch restrictions: Git push operations are restricted to the current working branch

## Source: Desktop application docs — Dispatch
- URL: https://code.claude.com/docs/en/desktop
- Fetched: 2026-07-06 (full page persisted at fetch time; excerpt below)

> Environment: choose where Claude runs. Select Local for your machine, Remote for Anthropic-hosted cloud sessions, or an SSH connection for a remote machine you manage.

> Dispatch is a persistent conversation with Claude that lives in the Cowork tab. You message Dispatch a task, and it decides how to handle it.

> A task can end up as a Code session in two ways: you ask for one directly, such as "open a Claude Code session and fix the login bug", or Dispatch decides the task is development work and spawns one on its own.

> Either way, the Code session appears in the Code tab's sidebar with a Dispatch badge. You get a push notification on your phone when it finishes or needs your approval.

Analysis note (not a quote): the summary table in `remote-1password-ssh-approval_doc_3.md` states
Dispatch's "Claude runs on" column as "Your machine (Desktop)" — i.e., by default Dispatch, like
Remote Control, executes on the physical machine, not in the cloud. The "Environment" selector
quoted above shows Dispatch/Desktop sessions can alternatively be pointed at "Remote" (Anthropic
cloud) or an "SSH connection" (a remote machine the engineer manages) instead of "Local" — those
alternate targets move the execution host, which is the same category of trade-off as switching
to Claude Code on the web, just self-hosted instead of Anthropic-managed.
