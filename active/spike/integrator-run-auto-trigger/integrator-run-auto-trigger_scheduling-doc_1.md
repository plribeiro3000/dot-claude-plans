# Auxiliary — Claude Code scheduling/automation surfaces, verbatim excerpts

Fetched 2026-07-09 while researching `~/.claude/plans/active/spike/integrator-run-auto-trigger/SPIKE.md`. Kept as source material so a revision of the spike does not need to re-fetch these pages.

## 1. Scheduling comparison table (identical table appears on both pages)

Source: https://code.claude.com/docs/en/scheduled-tasks.md and https://code.claude.com/docs/en/desktop-scheduled-tasks.md

Quote:

> |                            | Cloud                          | Desktop                                | `/loop`                             |
> | :------------------------- | :------------------------------ | :-------------------------------------- | :------------------------------------ |
> | Runs on                    | Anthropic cloud                | Your machine                           | Your machine                        |
> | Requires machine on        | No                             | Yes                                     | Yes                                  |
> | Requires open session      | No                             | No                                      | Yes                                  |
> | Persistent across restarts | Yes                            | Yes                                      | Restored on `--resume` if unexpired |
> | Access to local files      | No (fresh clone)               | Yes                                      | Yes                                  |
> | MCP servers                | Connectors configured per task | Config files and connectors            | Inherits from session                |
> | Permission prompts         | No (runs autonomously)         | Configurable per task                  | Inherits from session                |
> | Customizable schedule      | Via `/schedule` in the CLI     | Yes                                      | Yes                                   |
> | Minimum interval           | 1 hour                         | 1 minute                                | 1 minute                              |

## 2. `/loop` mechanics and expiry

Source: https://code.claude.com/docs/en/scheduled-tasks.md

Quote (session-scoped nature):

> "Tasks are session-scoped: they live in the current conversation and stop when you start a new one."

Quote (seven-day expiry):

> "Recurring tasks automatically expire 7 days after creation. The task fires one final time, then deletes itself."

Quote (underlying tools):

> "Under the hood, Claude uses these tools: `CronCreate` — Schedule a new task... `CronList` — List all scheduled tasks... `CronDelete` — Cancel a task by ID."

Quote (fires only while idle):

> "Tasks only fire while Claude Code is running and idle. Closing the terminal or letting the session exit stops them firing."

## 3. Desktop scheduled tasks — machine-must-be-awake constraint

Source: https://code.claude.com/docs/en/desktop-scheduled-tasks.md

Quote:

> "Tasks only run while the desktop app is running and your computer is awake. If your computer sleeps through a scheduled time, the run is skipped. To prevent idle-sleep, enable **Keep computer awake** in Settings under **Desktop app → General**."

Quote (permission stalls):

> "If a task runs in Ask mode and needs to run a tool it doesn't have permission for, the run stalls until you approve it. The session stays open in the sidebar so you can answer later."

## 4. Cloud Routines — where the session actually executes, and connector scope

Source: https://code.claude.com/docs/en/routines.md

Quote (execution location):

> "A routine is a saved Claude Code configuration: a prompt, one or more repositories, and a set of connectors, packaged once and run automatically. Routines execute on Anthropic-managed cloud infrastructure, so they keep working when your laptop is closed."

Quote (connectors are account-level, added per routine):

> "Connectors are the claude.ai integrations on your account. MCP servers you added locally in the CLI with `claude mcp add` are stored on your machine rather than your claude.ai account, so they do not appear in the connectors list."

Quote (no local filesystem, fresh clone):

> "Each repository you add is cloned at the start of a run, starting from the default branch."

## 5. Remote Control — connection model and local-process requirement

Source: https://code.claude.com/docs/en/remote-control

Quote (local execution, outbound-only):

> "Your local Claude Code session makes outbound HTTPS requests only and never opens inbound ports on your machine. When you start Remote Control, it registers with the Anthropic API and polls for work."

Quote (local process must keep running):

> "Local process must keep running: Remote Control runs as a local process. If you close the terminal, quit VS Code, or otherwise stop the `claude` process, the session ends."

Quote (mobile push notification trigger):

> "Claude decides when to push. It typically sends one when a long-running task finishes or when it needs a decision from you to continue."

## 6. Channels — supported connectors and reactive model

Source: https://code.claude.com/docs/en/channels.md

Quote (what a channel is):

> "A channel is an MCP server that pushes events into your running Claude Code session, so Claude can react to things that happen while you're not at the terminal."

Quote (officially supported set, research preview):

> "You install a channel as a plugin and configure it with your own credentials. Telegram, Discord, and iMessage are included in the research preview."

Quote (comparison table, "How channels compare"):

> | Feature | What it does | Good for |
> |---|---|---|
> | Claude Code on the web | Runs tasks in a fresh cloud sandbox, cloned from GitHub | Delegating self-contained async work you check on later |
> | Claude in Slack | Spawns a web session from an `@Claude` mention in a channel or thread | Starting tasks directly from team conversation context |
> | Standard MCP server | Claude queries it during a task; nothing is pushed to the session | Giving Claude on-demand access to read or query a system |
> | Remote Control | You drive your local session from claude.ai or the Claude mobile app | Steering an in-progress session while away from your desk |

Note: Gmail is not in the officially-supported channel plugin list (Telegram/Discord/iMessage); a custom channel would need to be built per the Channels reference (not fetched in this spike — flagged as further research if this path is chosen).

## 7. Dispatch — phone-message-triggered Desktop session spawn

Source: https://code.claude.com/docs/en/desktop.md (section "Sessions from Dispatch")

Quote:

> "Dispatch is a persistent conversation with Claude that lives in the Cowork tab. You message Dispatch a task, and it decides how to handle it."

Quote (routing to a Code session):

> "A task can end up as a Code session in two ways: you ask for one directly, such as 'open a Claude Code session and fix the login bug', or Dispatch decides the task is development work and spawns one on its own."

Quote (plan restriction):

> "Dispatch requires a Pro or Max plan and is not available on Team or Enterprise plans."

## 8. GitHub issue #43397 — MCP connectors unavailable on autonomous/scheduled fire

Source: https://github.com/anthropics/claude-code/issues/43397

Summary of the reported and reproduced behavior (paraphrased from the fetched issue, since the tool call returned a synthesized summary rather than raw issue body text — treat this entry as UNVERIFIED-quote, verified-existence; re-fetch the raw issue before relying on exact wording):

- Connectors affected in the report: Zoho Cliq, Zoho CRM, Microsoft 365 (Outlook email search); the reporter states "Any" connector is affected generally.
- Symptom: on autonomous/scheduled fire, `ToolSearch` for each connector returns "No matching deferred tools found"; the agent concludes the tools are not available.
- Reproducible pattern reported: sending any user message into the same session immediately makes the connectors available with no configuration change — i.e., tools appear to load into the session only after a user message, not during autonomous initialization.
- Status: referenced as related to issues #35899 and #36327 (Desktop scheduled tasks with Datadog/Jira and Slack connectors), suggesting the gap is not cloud-only.
- Anthropic's issue tracker marks it duplicate/not-planned as a standalone ticket, pointing to the related platform-infrastructure issues instead of shipping a standalone fix.

This finding is the primary external grounding for the constraint the engineer asked to be called out explicitly: an interactively-authenticated MCP connector (Gmail, Slack) may be absent or unreliable in a headless/autonomous/cron-fired session.
