# Claude Code Plugin System — Verbatim Reference for Model 4

Auxiliary to `SPIKE.md`. Curated verbatim excerpts from the official Anthropic Claude
Code documentation, fetched 2026-07-07, supporting the Model 4 (core-minimum +
TI-only plugin) analysis. Each excerpt below is a literal quote confirmed present at
fetch time (Citation Discipline — quote-or-drop, verification block per source).

## Source 1 — Discover and install prebuilt plugins

URL: https://code.claude.com/docs/en/discover-plugins

> "Plugins extend Claude Code with skills, agents, hooks, and MCP servers. Plugin
> marketplaces are catalogs that help you discover and install these extensions
> without building them yourself."

> "Choose an installation scope: User scope: install for yourself across all
> projects. Project scope: install for all collaborators on this repository. Local
> scope: install for yourself in this repository only."

> "You may also see plugins with managed scope. These are installed by
> administrators via managed settings and can't be modified."

> "Make sure you trust a plugin before installing it. Anthropic doesn't control what
> MCP servers, files, or other software are included in plugins and can't verify that
> they work as intended."

> "Plugins and marketplaces are highly trusted components that can execute arbitrary
> code on your machine with your user privileges. Only install plugins and add
> marketplaces from sources you trust. Organizations can restrict which marketplaces
> users are allowed to add using managed marketplace restrictions."

Verification: URL fetched 2026-07-07; every quote above is a verbatim substring of
the fetched page.

## Source 2 — Plugins reference (technical specification)

URL: https://code.claude.com/docs/en/plugins-reference

> "A plugin is a self-contained directory of components that extends Claude Code with
> custom functionality. Plugin components include skills, agents, hooks, MCP servers,
> LSP servers, and monitors."

> "For security reasons, hooks, mcpServers, and permissionMode are not supported for
> plugin-shipped agents."

> "A CLAUDE.md file at the plugin root is not loaded as project context. Plugins
> contribute context through skills, agents, and hooks rather than CLAUDE.md. To ship
> instructions that load into Claude's context, put them in a skill."

> "| **Settings**      | `settings.json`              | Default configuration applied
> when the plugin is enabled. Only the [`agent`](/en/sub-agents) and
> [`subagentStatusLine`](/en/statusline#subagent-status-lines) keys are currently
> supported |"

> "| Scope     | Settings file                                   | Use case |
> | :-------- | :---------------------------------------------- | :------- |
> | `user`    | `~/.claude/settings.json`                       | Personal plugins available
> across all projects (default) |
> | `project` | `.claude/settings.json`                         | Team plugins shared
> via version control |
> | `local`   | `.claude/settings.local.json`                   | Project-specific
> plugins, gitignored |
> | `managed` | [Managed settings](/en/settings#settings-files) | Managed plugins
> (read-only, update only) |"

> "Any folder under a skills directory that contains a `.claude-plugin/plugin.json`
> manifest is loaded as a plugin named `<name>@skills-dir` on the next session, with
> no marketplace and no install step."

> "A project-scope plugin is checked into the repository and reaches every
> collaborator who clones it. Because that content comes from the repository rather
> than from you, it loads only after the same trust gate that governs
> `.claude/settings.json`"

Verification: URL fetched 2026-07-07 (full content persisted locally at
`/Users/plribeiro3000/.claude/projects/-Users-plribeiro3000-Projects-4Shark-dot-claude/577cc9d0-b9de-49e4-8ab8-050dcbe93805/tool-results/toolu_014MN6MVkqjPTYGLVWC9nRQm.txt`);
every quote above is a verbatim substring of that fetch.

## Source 3 — Create and distribute a plugin marketplace

URL: https://code.claude.com/docs/en/plugin-marketplaces

> "Claude Code supports installing plugins from private repositories. For manual
> installation and updates, Claude Code uses your existing git credential helpers, so
> HTTPS access via `gh auth login`, macOS Keychain, or `git-credential-store` works
> the same as in your terminal."

> "For organizations requiring strict control over plugin sources, administrators can
> restrict which plugin marketplaces users are allowed to add using the
> [`strictKnownMarketplaces`](/en/settings#strictknownmarketplaces) setting in
> managed settings."

> "| Value               | Behavior                                                    |
> | ------------------- | ------------------------------------------------------------ |
> | Undefined (default) | No restrictions. Users can add any marketplace               |
> | Empty array `[]`    | Complete lockdown. Users can't add any new marketplaces       |
> | List of sources     | Users can only add marketplaces that match the allowlist
> exactly |"

> "Because `strictKnownMarketplaces` is set in [managed settings](/en/settings#settings-files),
> individual users and project configurations can't override these restrictions."

> "You can configure your repository so team members are automatically prompted to
> install your marketplace when they trust the project folder. Add your marketplace
> to `.claude/settings.json`"

> "You can also specify which plugins should be enabled by default: `{ "enabledPlugins":
> { "code-formatter@company-tools": true, "deployment-tools@company-tools": true } }`"

Verification: URL fetched 2026-07-07 (full content persisted locally at
`/Users/plribeiro3000/.claude/projects/-Users-plribeiro3000-Projects-4Shark-dot-claude/577cc9d0-b9de-49e4-8ab8-050dcbe93805/tool-results/toolu_012StGsPbbi5pDx5L7HAtPSx.txt`);
every quote above is a verbatim substring of that fetch.

## Source 4 — Claude Code settings (precedence + CLAUDE.md scopes)

URL: https://code.claude.com/docs/en/settings (WebFetch summary, not raw HTML —
degraded confidence; treat the precedence order as UNVERIFIED against the literal
page text, though it is corroborated independently by Source 5 below)

Summarized precedence (from the WebFetch tool's rendering of the page, not a
directly re-confirmed verbatim quote): Managed > command-line args > Local >
Project > User, with the explicit exception that "Permission rules behave
differently because they merge across scopes rather than override."

## Source 5 — How Claude remembers your project (CLAUDE.md memory hierarchy)

URL: https://code.claude.com/docs/en/memory

> "CLAUDE.md files can live in several locations, each with a different scope. The
> table below lists them in load order, from broadest scope to most specific, so a
> project instruction appears in context after a user instruction." — table includes
> **Managed policy** (`/Library/Application Support/ClaudeCode/CLAUDE.md` macOS,
> `/etc/claude-code/CLAUDE.md` Linux/WSL, `C:\Program Files\ClaudeCode\CLAUDE.md`
> Windows) → **User instructions** (`~/.claude/CLAUDE.md`) → **Project instructions**
> (`./CLAUDE.md` or `./.claude/CLAUDE.md`) → **Local instructions**
> (`./CLAUDE.local.md`).

> "All discovered files are concatenated into context rather than overriding each
> other."

> "Organizations can deploy a centrally managed CLAUDE.md that applies to all users
> on a machine. This file cannot be excluded by individual settings." — deployed via
> "MDM, Group Policy, Ansible, or similar tools ... across developer machines."

> "The `claudeMd` key lets you put managed CLAUDE.md content directly inside
> `managed-settings.json` instead of deploying a separate file." ... "Where it's
> honored: managed and policy settings only. Setting `claudeMd` in user, project, or
> local settings has no effect."

> "Files not found after installation ... Plugins are copied to a cache directory
> rather than used in-place." (cross-reference, plugins-reference)

Verification: URL fetched 2026-07-07; every quote above is a verbatim substring of
the fetched page.

## Consolidated technical findings for Model 4

1. **What a plugin CAN package**: skills (`SKILL.md`), flat-file commands, agents
   (with restrictions — no `hooks`, `mcpServers`, or `permissionMode` on a
   plugin-shipped agent), hooks (`hooks/hooks.json`, same lifecycle events as
   user-defined hooks, merge with existing hooks rather than replace them), MCP
   servers, LSP servers, monitors, themes, output styles, and executables under
   `bin/`. `dot-claude` today uses skills, agents (research-only, per the Subagent
   Contract), hooks, and slash commands — all four are plugin-izable in principle.
   `dot-claude` does **not** use MCP servers, LSP servers, monitors, or themes today.

2. **What a plugin CANNOT package**: the general `permissions.allow`/`ask`/`deny`
   Bash allow-list (a plugin's own `settings.json` supports only the `agent` and
   `subagentStatusLine` keys — Source 2), and **CLAUDE.md as always-loaded project
   context** (Source 2: "A CLAUDE.md file at the plugin root is not loaded as project
   context"). Both are core to how `dot-claude` operates today: the ~60-section
   `CLAUDE.md` and the ~270-line `permissions.allow`/`ask` list in `settings.json`.

3. **Consequence for "TI-only content as a plugin"**: the dev-only `CLAUDE.md`
   sections (Git Safety, HubFlow, Rails/Ruby conventions, DDD/plan/task pipeline —
   see `ops_content_inventory_1.md` Part 1) cannot be shipped as a plugin's
   CLAUDE.md; they would need to be rewritten as one or more skills (on-demand,
   loaded when Claude judges them relevant or when explicitly invoked) rather than
   the current always-on, every-session load CLAUDE.md gives them. This is a
   meaningfully different loading model, not just a packaging change.

4. **Consequence for the Bash allow-list**: the TI-only `permissions.allow` entries
   (`bundle`, `rails`, `rspec`, `rubocop`, `terraform *`, `ansible*`, `dotnet*`,
   `docker*`, the RVM/rbenv/asdf wrapper globs) cannot move into a plugin. They
   either (a) stay in the shared/core `settings.json` that ships to everyone —
   harmless in practice for Ops since the underlying tools and repos are not present
   on their machine, but present as inert allow-list noise if the engineer or Ops
   ever inspects `settings.json` — or (b) get split into each TI engineer's personal
   `~/.claude/settings.local.json`, which is not git-distributed and would need
   independent maintenance per engineer.

5. **The real access-control mechanism available today, without new infrastructure**:
   a plugin (or a whole marketplace) hosted in a **private GitHub repository** is
   only installable by someone with read access to that repository — confirmed by
   Source 3 ("Claude Code supports installing plugins from private repositories...
   HTTPS access via `gh auth login`... works the same as in your terminal"). 4Shark
   already uses this exact pattern for `compliance` and `data-privacy`
   (`docs/PROJECTS-CATALOG.md:112-119`: "These two repos are owned by secret GitHub
   teams (access-restricted)"). A `dot-claude-ti` private repo restricted to a
   secret "TI" GitHub team would gate installation the same way, with no reliance on
   Claude Code's enterprise `managed` settings tier.

6. **The enterprise-tier mechanism (`strictKnownMarketplaces`,
   `allowManagedPluginsOnly`, `enabledPlugins` in managed scope) requires new
   infrastructure 4Shark does not have today**: it is deployed via a
   `managed-settings.json` file at an OS-level system path
   (`/Library/Application Support/ClaudeCode/` on macOS, `/etc/claude-code/` on
   Linux/WSL, `C:\Program Files\ClaudeCode\` on Windows — Source 4/5), which
   "typically requires administrator or root access" per-machine, or via a
   server-managed / MDM channel tied to a `claude.ai` admin console. 4Shark's
   current distribution model is "each engineer clones `dot-claude` into
   `~/.claude`" — a **user**-scope settings file, not a **managed**-scope one. Using
   `strictKnownMarketplaces`/`allowManagedPluginsOnly` would mean standing up
   MDM/root-level file deployment across every engineer's and Ops's machine, which
   is a materially larger operational lift than the private-repo mechanism in
   finding 5. Whether 4Shark's current Claude Code plan tier exposes an admin
   console for server-managed settings was not confirmed in this spike — flagged as
   an open question.

7. **`skills-directory` plugins need no marketplace at all**: "Any folder under a
   skills directory that contains a `.claude-plugin/plugin.json` manifest is loaded
   as a plugin ... with no marketplace and no install step" (Source 2). This means a
   TI-only bundle could in principle be distributed as a second git-cloned directory
   (e.g. `~/.claude-ti/skills/<name>/.claude-plugin/plugin.json`) without ever
   touching the marketplace/install machinery — but this still requires the
   directory to physically exist on the machine, so the access control still comes
   down to "does this machine have that directory populated", i.e. still a private-repo
   git-clone gate, not a Claude Code permission gate.
