<!-- Fetched excerpt — https://code.claude.com/docs/en/permissions — retrieved 2026-07-16 -->
<!-- Full raw fetch also persisted by the harness at:
     ~/.claude/projects/-/ce4bf5cd-6e1c-4f99-8815-dd3b88cd0e12/tool-results/toolu_01W2rLPHCUdZzWc3hg2aPBhm.txt
     This file extracts only the sections load-bearing for the spike. -->

# Configure permissions (excerpt)

## Manage permissions

You can view and manage Claude Code's tool permissions with `/permissions`. This UI lists all permission rules and the `settings.json` file each rule comes from.

* **Allow** rules let Claude Code use the specified tool without manual approval.
* **Ask** rules prompt for confirmation whenever Claude Code tries to use the specified tool.
* **Deny** rules prevent Claude Code from using the specified tool.

Rules are evaluated in order: deny, then ask, then allow. The first match in that order determines the outcome, and rule specificity doesn't change the order.

A broad deny rule like `Bash(aws *)` blocks every matching call, including calls that also match a narrower allow rule like `Bash(aws s3 ls)`, so a deny rule can't carry allowlist exceptions. The same precedence applies between ask and allow: a matching ask rule prompts even when a more specific allow rule also matches the same call.

Deny rules behave differently depending on whether they name a tool or scope a pattern within one. A bare tool name like `Bash` removes the tool from Claude's context entirely, so Claude never sees it. A scoped rule like `Bash(rm *)` leaves the tool available and blocks matching calls when Claude attempts them.

> Permission rules are enforced by Claude Code, not by the model. Instructions in your prompt or `CLAUDE.md` shape what Claude tries to do, but they don't change what Claude Code allows. To grant or revoke access, use `/permissions`, the rules described here, a permission mode, or a PreToolUse hook.

## Bash — compound commands

Claude Code is aware of shell operators, so a rule like `Bash(safe-cmd *)` won't give it permission to run the command `safe-cmd && other-cmd`. The recognized command separators are `&&`, `||`, `;`, `|`, `|&`, `&`, and newlines. A rule must match each subcommand independently.

When you approve a compound command with "Yes, don't ask again", Claude Code saves a separate rule for each subcommand that requires approval, rather than a single rule for the full compound string.

## Bash — process wrappers

Before matching Bash rules, Claude Code strips a fixed set of process wrappers so a rule like `Bash(npm test *)` also matches `timeout 30 npm test`. The recognized wrappers are `timeout`, `time`, `nice`, `nohup`, and `stdbuf`.

Bare `xargs` is also stripped, so `Bash(grep *)` matches `xargs grep pattern`. [...] Development environment runners such as `direnv exec`, `devbox run`, `mise exec`, `npx`, and `docker exec` are not in the list. Because these tools execute their arguments as a command, a rule like `Bash(devbox run *)` matches whatever comes after `run`, including `devbox run rm -rf .`. To approve work inside an environment runner, write a specific rule that includes both the runner and the inner command.

## Bash — fragile argument-constraining patterns

> Bash permission patterns that try to constrain command arguments are fragile. For example, `Bash(curl http://github.com/ *)` intends to restrict curl to GitHub URLs, but won't match variations like:
> - Options before URL: `curl -X GET http://github.com/...`
> - Different protocol: `curl https://github.com/...`
> - Redirects: `curl -L http://bit.ly/xyz`, which redirects to GitHub
> - Variables: `URL=http://github.com && curl $URL`
> - Extra spaces: `curl  http://github.com`
>
> For more reliable URL filtering, consider:
> - **Restrict Bash network tools**: use deny rules to block `curl`, `wget`, and similar commands, then use the WebFetch tool with `WebFetch(domain:github.com)` permission for allowed domains
> - **Use PreToolUse hooks**: implement a hook that validates URLs in Bash commands and blocks disallowed domains
> - **Add CLAUDE.md guidance**: describe your allowed curl patterns in `CLAUDE.md`. This shapes what Claude tries but doesn't enforce a boundary, so pair it with one of the options above

## Extend permissions with hooks

Claude Code hooks provide a way to register custom shell commands to perform permission evaluation at runtime. When Claude Code makes a tool call, PreToolUse hooks run before the permission prompt. The hook output can deny the tool call, force a prompt, or skip the prompt to let the call proceed.

Hook decisions don't bypass permission rules. Claude Code evaluates deny and ask rules regardless of what a PreToolUse hook returns: a matching deny rule blocks the call, and a matching ask rule still prompts even when the hook returned `"allow"` or `"ask"`. This preserves the deny-first precedence described in Manage permissions, including deny rules set in managed settings.

Connector tools your organization set to `ask` and MCP tools marked `requiresUserInteraction` also still prompt when a hook returns `"allow"`.

A blocking hook also takes precedence over allow rules. A hook that exits with code 2 stops the tool call before permission rules are evaluated, so the block applies even when an allow rule would otherwise let the call proceed. To run all Bash commands without prompts except for a few you want blocked, add `"Bash"` to your allow list and register a PreToolUse hook that rejects those specific commands.

## Working directories — additional configuration loaded from --add-dir

The following configuration types are loaded from `--add-dir` directories: Skills (with live reload), Subagents, Settings (`enabledPlugins`/`extraKnownMarketplaces` keys only), CLAUDE.md/rules/CLAUDE.local.md (only with an env-var override).

Hooks and other `.claude/settings.json` keys load from the current working directory's `.claude/` folder with no parent-directory fallback, alongside the user `~/.claude/settings.json` and managed settings.

## Settings precedence

1. Managed settings — can't be overridden by any other level
2. Command line arguments — temporary session overrides
3. Local project settings (`.claude/settings.local.json`)
4. Shared project settings (`.claude/settings.json`)
5. User settings (`~/.claude/settings.json`)

If a tool is denied at any level, no other level can allow it. [...] a user-level deny blocks a project-level allow, because deny rules from any scope are evaluated before allow rules.
