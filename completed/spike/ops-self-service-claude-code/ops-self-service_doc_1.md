# Auxiliary — External documentation excerpts consulted

Curated quotes from fetched Anthropic / GitHub / Slack / AWS documentation, preserved verbatim so
SPIKE.md claims can be re-verified without re-fetching. One block per source, in the order first
used in SPIKE.md.

---

## 1. Claude Code headless mode (`-p` / `--print`)

**URL**: https://code.claude.com/docs/en/headless
**Fetched**: 2026-07-01

> "Add the `-p` (or `--print`) flag to any `claude` command to run it non-interactively. All CLI options work with `-p`, including: `--continue` for continuing conversations, `--allowedTools` for auto-approving tools, `--output-format` for structured output."

> "Add `--bare` to reduce startup time by skipping auto-discovery of hooks, skills, plugins, MCP servers, auto memory, and CLAUDE.md. Without it, `claude -p` loads the same context an interactive session would, including anything configured in the working directory or `~/.claude`."

> "`--bare` is the recommended mode for scripted and SDK calls, and will become the default for `-p` in a future release."

> "Bare mode skips OAuth and keychain reads. Anthropic authentication must come from `ANTHROPIC_API_KEY` or an `apiKeyHelper` in the JSON passed to `--settings`."

> "Use `--allowedTools` to let Claude use certain tools without prompting... To set a baseline for the whole session instead of listing individual tools, pass a permission mode. `dontAsk` denies anything not in your `permissions.allow` rules or the read-only command set, which is useful for locked-down CI runs. `acceptEdits` lets Claude write files without prompting and also auto-approves common filesystem commands such as `mkdir`, `touch`, `mv`, and `cp`."

> "User-invoked skills and custom commands work in `-p` mode: include `/skill-name` in the prompt string and Claude Code expands it before running."

> "With `--output-format json`, the response payload includes `total_cost_usd` and a per-model cost breakdown, so scripted callers can track spend per invocation without consulting the usage dashboard."

Verification: URL fetched directly via WebFetch. Quotes copied verbatim from the returned markdown. Confirmed present at fetch time.

---

## 2. Claude Agent SDK overview

**URL**: https://code.claude.com/docs/en/agent-sdk/overview
**Fetched**: 2026-07-01

> "Build AI agents that autonomously read files, run commands, search the web, edit code, and more. The Agent SDK gives you the same tools, agent loop, and context management that power Claude Code, programmable in Python and TypeScript."

> "The SDK also supports Claude Code's filesystem-based configuration. With default options the SDK loads these from `.claude/` in your working directory and `~/.claude/`."

> Comparison table quote — Agent SDK vs Managed Agents: "**Runs in**: Your process, your infrastructure" (Agent SDK) vs "Anthropic-managed infrastructure" (Managed Agents, one per session sandbox).

> "A common path is to prototype with the Agent SDK locally, then move to Managed Agents for production."

> Branding guidelines: "Not permitted: 'Claude Code' or 'Claude Code Agent' ... Your product should maintain its own branding and not appear to be Claude Code or any Anthropic product."

Verification: URL fetched directly via WebFetch. Quotes copied verbatim. Confirmed present at fetch time.

---

## 3. Claude Code GitHub Actions

**URL**: https://code.claude.com/docs/en/github-actions
**Fetched**: 2026-07-01

> "With a simple `@claude` mention in any PR or issue, Claude can analyze your code, create pull requests, implement features, and fix bugs - all while following your project's standards."

> "Claude Code GitHub Actions is built on top of the Claude Agent SDK, which enables programmatic integration of Claude Code into your applications. You can use the SDK to build custom automation workflows beyond GitHub Actions."

> Quick setup permissions: "The GitHub app will request read & write permissions for Contents, Issues, and Pull requests."

> Custom GitHub App (recommended for branded identity / 3rd-party providers): "For best control and security when using 3P providers like Vertex AI or Bedrock, we recommend creating your own GitHub App... Note your App ID from the app settings page... This app will be used with the actions/create-github-app-token action to generate authentication tokens in your workflows."

> "The `prompt` input accepts a skill invocation as well as plain text: For a skill in your repository's `.claude/skills/` directory, run `actions/checkout` before the action step and pass `/skill-name`."

> Custom automation example (non-`@claude`-triggered, scheduled):
> ```yaml
> on:
>   schedule:
>     - cron: "0 9 * * *"
> jobs:
>   report:
>     steps:
>       - uses: anthropics/claude-code-action@v1
>         with:
>           prompt: "Generate a summary of yesterday's commits and open issues"
> ```

> Amazon Bedrock auth path (OIDC, no static keys): "OIDC is more secure than using static AWS access keys because credentials are temporary and automatically rotated." Required GitHub secret: `AWS_ROLE_TO_ASSUME` (ARN of an IAM role trusted via GitHub's OIDC provider `token.actions.githubusercontent.com`).

> Cost: "Claude Code runs on GitHub-hosted runners, which consume your GitHub Actions minutes... Each Claude interaction consumes API tokens based on the length of prompts and responses."

Verification: URL fetched directly via WebFetch. Quotes copied verbatim. Confirmed present at fetch time.

---

## 4. Claude Code in Slack (per-user, being retired)

**URL**: https://code.claude.com/docs/en/slack
**Fetched**: 2026-07-01

> "Claude Code in Slack is being replaced by Claude Tag for Team and Enterprise workspaces. Claude Tag runs @Claude as your organization's shared identity with admin-configured access."

> "Each session runs under your own Claude account, using your connected repositories and your plan limits."

> "Claude Code in Slack only works in channels (public or private). It does not work in direct messages (DMs)."

> Warning on trust boundary: "When @Claude is invoked in Slack, Claude is given access to the conversation context to better understand your request. Claude may follow directions from other messages in the context, so users should make sure to only use Claude in trusted Slack conversations."

> Access table: "Claude Code Sessions — Each user runs sessions under their own Claude account. Usage & Rate Limits — Sessions count against the individual user's plan limits. Repository Access — Users can only access repositories they've personally connected."

> "Claude in Slack will be switched over to the new Claude Tag experience on August 3, 2026." (from search snippet corroborating the retirement note above; same fact as the in-page `<Note>`.)

Verification: URL fetched directly via WebFetch. Quotes copied verbatim. Confirmed present at fetch time.

---

## 5. Claude Tag (organization shared identity)

**URL**: https://claude.com/docs/claude-tag/overview
**Fetched**: 2026-07-01

> "Anyone in a channel can tag Claude into a problem and hand it work."

> "You extend what Claude can reach, like your repositories, ticketing systems, data warehouses, and custom tools, through connections, plugins, and skills."

> "An Owner configures these per scope (a channel, a workspace, or the whole organization), separately from any connectors an individual user has set up."

> "What it can reach depends on the channel you're in, not on who you are."

> "You configure this once, at claude.ai/admin-settings/claude-tag, and everyone in those places can use Claude Tag immediately, with no per-user setup."

Verification: URL fetched via WebFetch. Quotes copied verbatim from the returned summary. Confirmed present at fetch time. Note: this fetch returned a synthesized digest rather than the raw page markdown; treat quotes as accurately extracted by the fetch tool but slightly less directly verifiable than the other entries (no raw markdown to re-diff against).

---

## 6. Claude Code on the web (cloud sandbox)

**URL**: https://code.claude.com/docs/en/claude-code-on-the-web
**Source**: WebSearch result snippet (page not separately WebFetched in this spike — see note below)

> "Claude Code on the web executes each Claude Code session in an isolated sandbox where it has full access to its server in a safe and secure way." (from WebSearch synthesized summary, sourced to code.claude.com/docs/en/claude-code-on-the-web)

> "Each cloud session is separated from your machine and from other sessions through several layers: Isolated virtual machines... and network access controls that limit network access by default." (same source)

**UNVERIFIED caveat**: these two quotes come from the WebSearch tool's own summarization of the page, not a direct WebFetch of the page's raw content by this spike. They are corroborated independently by the companion Anthropic engineering post `anthropic.com/engineering/claude-code-sandboxing` (same search result set) describing the same sandboxing architecture, but that post was not fetched directly either. Treat the "isolated VM, network access limited by default" claim as directionally reliable (consistent across two independent listed sources) but flag it UNVERIFIED per Citation Discipline until directly re-fetched.

---

## 7. Claude Managed Agents

**URL**: https://platform.claude.com/docs/en/managed-agents/overview
**Fetched**: 2026-07-01

> "Claude Managed Agents provides the harness and infrastructure for running Claude as an autonomous agent. Instead of building your own agent loop, tool execution, and runtime, you get a fully managed environment where Claude can read files, run commands, browse the web, and execute code securely."

> "**Environment**: Configuration for where sessions run: an Anthropic-managed cloud sandbox, or a self-hosted sandbox on your own infrastructure."

> "**Self-hosted execution**: Sandboxes on infrastructure you control for compliance or data-residency requirements."

> "Claude Managed Agents is currently in beta. All Managed Agents endpoints require the `managed-agents-2026-04-01` beta header."

> "Claude Managed Agents is stateful by design: sessions are long-running, resume cleanly after pauses, and store conversation history, sandbox state, and outputs server-side. Because of this, Managed Agents is not currently eligible for Zero Data Retention (ZDR) or HIPAA Business Associate Agreement (BAA) coverage."

Verification: URL fetched directly via WebFetch. Quotes copied verbatim. Confirmed present at fetch time.

---

## 8. GitHub Actions environments — required reviewers (manual approval gate)

**URL**: https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment
**Fetched**: 2026-07-01 (via WebFetch summarization)

> "specify people or teams that must approve workflow jobs that use this environment" — and "only one of the required reviewers needs to approve the job for it to proceed."

> "a job that references an environment must follow any protection rules for the environment before running" — i.e. the workflow run pauses at that job until an approval is recorded.

> Self-review prevention option: "prevent users from approving workflows runs that they triggered."

**Note**: the WebFetch summarization did not surface GitHub's own audit-log documentation for approvals; the existence of the audit trail is inferred from GitHub's general Deployments API / webhook events, not independently re-verified in this spike. Treat "creates an audit trail" as a reasonable inference from GitHub's documented Deployments API, not a directly quoted claim.

---

## 9. AWS Chatbot / ChatOps (non-Claude baseline for comparison)

**URL**: https://aws.amazon.com/chatbot/ (and companion AWS blog posts, same WebSearch result set)
**Source**: WebSearch synthesized summary

> "AWS Chatbot is an interactive agent that makes it easy to monitor and interact with AWS resources from team chat channels in Microsoft Teams and Slack. Using AWS Chatbot, teams can receive alerts, run commands to return diagnostic information, invoke AWS Lambda functions, and create AWS Support cases."

> "approvers can initiate approval using the Approve button in Slack ... a DevOps engineer can kick off the deployment using Slack in a ChatOps collaboration model with a single click."

**UNVERIFIED caveat**: these are WebSearch-tool summaries of AWS's own marketing/blog pages, not a direct WebFetch of a single canonical page. Included as directional grounding for the "Slack approval-button" pattern already proven at industry scale outside of Claude — not as a load-bearing citation for any Claude-specific claim.

---

## 10. Slack Workflow Builder — incoming webhook trigger

**URL**: https://slack.com/help/articles/360041352714-Create-more-advanced-workflows-using-webhooks
**Fetched**: 2026-07-01 (via WebFetch summarization)

> "When you choose to start a workflow with a webhook, you'll configure the webhook to kick off your workflow when a third-party app or service sends a web request to your URL."

**Note on outgoing webhooks**: a follow-up WebSearch (query: `Slack Workflow Builder "send a web request" step outgoing webhook action documentation`) found no native Slack Workflow Builder step for sending an outgoing HTTP request — that capability is provided only by third-party connector apps (e.g. "Workflow Buddy") or by building a first-party custom Slack App with a slash command / interactive button, which does have a well-documented outgoing webhook payload (Slack's `interactivity` API). This distinction matters for Option comparisons in SPIKE.md — "Slack triggers an external system" is not a zero-code native feature; it requires either a small custom Slack App or a third-party connector.
