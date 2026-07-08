# Auxiliary source — Claude Code on the web (official docs)

**URL**: https://code.claude.com/docs/en/claude-code-on-the-web
**Fetched**: 2026-07-07
**Why kept**: primary source for where files/execution live in the cloud-sandbox mode, session lifecycle, security/isolation architecture, and the "Environment expired" / deletion behavior.

---

## Full fetched content (relevant excerpts, verbatim)

> Claude Code on the web runs tasks on Anthropic-managed cloud infrastructure at [claude.ai/code](https://claude.ai/code). Sessions persist even if you close your browser, and you can monitor them from the Claude mobile app.

> Organizations with [Zero Data Retention](/en/zero-data-retention) enabled can't use `/web-setup` or other cloud session features.

### The cloud environment

> Each session runs in a fresh Anthropic-managed VM with your repository cloned. This section covers what's available when a session starts and how to customize it.

> Cloud sessions start from a fresh clone of your repository. Anything committed to the repo is available. Anything you've installed or configured only on your own machine isn't available in the session.

Table (partial) — "Available in cloud sessions":
- Your repo's `CLAUDE.md`, `.claude/settings.json` hooks, `.mcp.json` MCP servers, `.claude/rules/`, `.claude/skills/`/`agents/`/`commands/` — Yes (part of the clone)
- Your organization's server-managed settings — Yes (fetched from Anthropic's servers when the session starts)
- Static API tokens and credentials — No ("No dedicated secrets store exists yet")
- Interactive auth like AWS SSO — No ("Not supported. SSO requires browser-based login that can't run in a cloud session")

> A dedicated secrets store is not yet available. Both environment variables and setup scripts are stored in the environment configuration, visible to anyone who can edit that environment. If you need secrets in a cloud session, add them as environment variables with that visibility in mind.

### Environment caching

> The setup script runs the first time you start a session in an environment. After it completes, Anthropic snapshots the filesystem and reuses that snapshot as the starting point for later sessions.

> The setup script runs again to rebuild the cache when you change the environment's setup script or allowed network hosts, and when the cache reaches its expiry after roughly seven days.

### Resource limits

> Cloud sessions run with approximate resource ceilings that may change over time: 4 vCPUs, 16 GB of RAM, 30 GB of disk.

### Work with sessions

> Sessions appear in the sidebar at claude.ai/code. From there you can review changes, share with teammates, archive finished work, or delete sessions permanently.

### Share sessions

> Check your session for sensitive content before sharing. Sessions may contain code and credentials from private GitHub repositories. Repository access verification is not enabled by default. [Max/Pro accounts default]

### Delete sessions

> Deleting a session permanently removes the session and its data. This action can't be undone.

### Security and isolation

> Each cloud session is separated from your machine and from other sessions through several layers:
>
> * **Isolated virtual machines**: each session runs in an isolated, Anthropic-managed VM
> * **Network access controls**: network access is limited by default, and can be disabled. When running with network access disabled, Claude Code can still communicate with the Anthropic API, which may allow data to exit the VM.
> * **Credential protection**: sensitive credentials such as git credentials or signing keys are never inside the sandbox with Claude Code. Authentication is handled through a secure proxy using scoped credentials.
> * **Secure analysis**: code is analyzed and modified within isolated VMs before creating PRs

### Troubleshooting — Environment expired

> Cloud sessions stop after a period of inactivity and the underlying environment is reclaimed. From a local terminal, this surfaces as `Could not resume session ... its environment has expired. Creating a fresh session instead.` On the web, the session is marked expired in the session list.
>
> Reopen the session from claude.ai/code to provision a fresh environment with your conversation history restored.

### Limitations

> **Organization IP allowlist**: cloud sessions call the Anthropic API from Anthropic-managed infrastructure, not your network. If your organization has IP allowlisting enabled, every cloud session fails with an authentication error.

### Related resources

> * [Data usage](/en/data-usage): what Anthropic retains from cloud sessions

---

## Note on "environment expired" vs data deletion

The doc distinguishes two different things: the **VM/environment** is reclaimed after inactivity (this is compute reclamation, not necessarily data deletion — "your conversation history restored" implies the underlying session data survives environment reclamation), and the **session data** (transcript, diffs) persists under the account's standard data-retention policy until the engineer explicitly deletes the session ("Deleting a session permanently removes the session and its data"). There is no documented fixed number of days after which cloud-session file/code data is wiped automatically outside of the standard commercial 30-day retention window described in `api-and-data-retention` / `data-usage` (see `anthropic_doc_2_data-usage-retention.md`).
