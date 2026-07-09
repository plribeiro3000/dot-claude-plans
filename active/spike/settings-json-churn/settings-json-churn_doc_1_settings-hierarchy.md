# Auxiliary — Claude Code official settings hierarchy (fetched)

Source: https://code.claude.com/docs/en/settings
Fetched: 2026-07-07/08 (spike research session)

This file preserves the WebFetch extraction used to ground Finding 2 and Finding 3 of SPIKE.md. Quoted spans below are as returned by the fetch tool; treat this as a research artifact, not the raw HTML.

## Precedence order (verbatim quote)

> 1. **Managed** (highest): can't be overridden by anything
> 2. **Command line arguments**: temporary session overrides
> 3. **Local**: overrides project and user settings
> 4. **Project**: overrides user settings
> 5. **User** (lowest): applies when nothing else specifies the setting

## Settings files and scope (extraction table)

| File | Location | Scope | Git Status | Auto-Written By Claude Code | Purpose |
|------|----------|-------|-----------|---------------------------|---------|
| **managed-settings.json** | System directories (macOS: `/Library/Application Support/ClaudeCode/`, Linux/WSL: `/etc/claude-code/`, Windows: `C:\Program Files\ClaudeCode\`) | Managed (enforced) | N/A | No (admin-deployed) | Organization-wide policies that cannot be overridden |
| **.claude/settings.json** | Project root | Project | Committed to git | Yes (via `/config`, UI) | Team-shared settings for all collaborators |
| **.claude/settings.local.json** | Project root | Local | Gitignored | Yes (via `/config`, UI) | Personal overrides for specific project only |
| **~/.claude/settings.json** | User home | User | N/A (doc treats this as inherently personal) | Yes (via `/config`, UI) | Personal preferences across all projects |
| **~/.claude.json** | User home | User | N/A | Yes (auto-managed) | OAuth sessions, MCP configs, per-project state, caches |

Note: the doc's "Git Status: N/A" for `~/.claude/settings.json` reflects that the tool's own model does not assume this file is git-tracked at all — 4Shark's practice of tracking it in the shared `dot-claude` repo is a usage the doc does not anticipate.

## Managed settings delivery mechanisms (verbatim quotes)

Server-managed:
> delivered remotely at sign-in, either from Anthropic's servers via the claude.ai admin console or from a self-hosted Claude apps gateway.

MDM/OS-level:
- macOS: `com.anthropic.claudecode` plist managed preferences domain (via Jamf, Kandji, etc.)
- Windows Admin: `HKLM\SOFTWARE\Policies\ClaudeCode` registry key (via Group Policy or Intune)
- Windows User-Level: `HKCU\SOFTWARE\Policies\ClaudeCode` (lowest policy priority)

File-based:
> `managed-settings.json` and `managed-mcp.json` deployed to system directories... File-based managed settings also support a drop-in directory at `managed-settings.d/` in the same system directory alongside `managed-settings.json`.

## Read-only managed-only lockdown keys (verbatim quote)

> `allowManagedPermissionRulesOnly`: (Managed settings only) Prevent user and project settings from defining `allow`, `ask`, or `deny` permission rules. Only rules in managed settings apply.

Similar enforcements exist for:
- `allowManagedMcpServersOnly`
- `allowManagedHooksOnly` (implies hooks ARE a supported managed-settings key)

## Permission merge behavior (verbatim quote)

> Permission rules behave differently because they merge across scopes rather than override. See [Settings precedence](#settings-precedence).

## Local settings trust behavior (verbatim quote)

> Because this file is yours rather than the repository's, its permission `allow` rules take effect without the workspace trust step that `.claude/settings.json` allow rules require. If the repository supplies the file, for example by committing it, workspace trust still applies.

## Reload/write behavior (verbatim quote)

> When Claude Code watches your settings files and reloads them when they change, so edits to most keys apply to the running session without a restart. This includes `permissions`, `hooks`, and credential helpers like `apiKeyHelper`. The reload covers user, project, local, and managed settings

Restart-only exceptions (verbatim quote):
> * `model`: use `/model` to switch mid-session
> * `outputStyle`: part of the system prompt, which is rebuilt on `/clear` or restart

## Backup behavior (verbatim quote)

> Claude Code automatically creates timestamped backups of configuration files and retains the five most recent backups to prevent data loss.

## Auto-written triggers (extraction, not a single verbatim block)

Claude Code automatically modifies settings files when the engineer:
- Uses `/config` command to change settings
- Toggles preferences in the Settings UI (theme, editor mode, notifications, etc.)
- Runs commands like `/effort`, `/model`, `/advisor` which write their values
- Adds MCP servers or plugins
- Configures hooks or permissions

## No "extends"/import mechanism found in official docs

The fetched settings doc does not document an `extends`, `import`, or multi-file-merge-by-arbitrary-filename mechanism. The only scopes it recognizes are the four/five rows in the table above. See `settings-json-churn_doc_4_community-and-feature-requests.md` for the open (unshipped) feature request proposing this.
