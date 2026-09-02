# SPIKE — Hermes Agent v0.21.0 vs. Claude Code

## Investigation question

The engineer runs Claude Code heavily and reviews every step; they want to reach a "Kanban" model of working — pull a task card, an agent goes off with its own disk/OS, comes back with a PR, no step-by-step babysitting, several agents running in parallel. Hermes Agent v0.21.0 ("Pantheon Release," 2026-08-31) surfaced as a candidate. Five questions:

1. What is Hermes Agent, concretely?
2. What does it do that Claude Code genuinely cannot?
3. How much of the target "pull card → agent → PR" model does Claude Code already deliver?
4. Can Hermes and Claude Code interoperate, coexist, or would adopting Hermes mean migrating away from the existing Claude Code investment?
5. What does each path actually cost per month — including whether the existing $200/mo Claude Max plan can be reused, or whether Hermes means a second, uncapped metered inference bill?

## Sources consulted

- [github.com/NousResearch/hermes-agent/releases/tag/v2026.8.31](https://github.com/NousResearch/hermes-agent/releases/tag/v2026.8.31) — v0.21.0 release notes (Bot Mode, agent-to-agent messaging, cron memory, MCP command center)
- [github.com/NousResearch/hermes-agent/releases](https://github.com/NousResearch/hermes-agent/releases) — release history, v0.21.0 "Pantheon" and v0.20.0 "Herald" framing
- [hermes-agent.nousresearch.com/docs/user-guide/features/kanban](https://hermes-agent.nousresearch.com/docs/user-guide/features/kanban) — Kanban board full spec (re-fetched for self-check)
- [hermes-agent.org](https://hermes-agent.org/) — project positioning, self-hosted model, license
- [github.com/NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) — README, architecture
- [hermes-agent.nousresearch.com/docs/user-guide/features/mcp](https://hermes-agent.nousresearch.com/docs/user-guide/features/mcp) — MCP client/server roles (re-fetched for self-check)
- [github.com/NousResearch/hermes-agent/issues/47199](https://github.com/NousResearch/hermes-agent/issues/47199) — open feature request, Claude Code as a local backend
- [github.com/NousResearch/hermes-agent/issues/40014](https://github.com/NousResearch/hermes-agent/issues/40014) — open bug, Claude Max/Pro OAuth token hits metered endpoint
- [github.com/NousResearch/hermes-agent/issues/25267](https://github.com/NousResearch/hermes-agent/issues/25267) — open feature request, Agent-SDK subscription auth ("Codex-style")
- [code.claude.com/docs/en/remote-control](https://code.claude.com/docs/en/remote-control) — Remote Control
- [code.claude.com/docs/en/agent-teams](https://code.claude.com/docs/en/agent-teams) — Agent Teams
- [code.claude.com/docs/en/workflows](https://code.claude.com/docs/en/workflows) — Dynamic Workflows
- [code.claude.com/docs/en/worktrees](https://code.claude.com/docs/en/worktrees) — git worktrees
- [code.claude.com/docs/en/sub-agents](https://code.claude.com/docs/en/sub-agents) — background subagents
- [code.claude.com/docs/en/memory](https://code.claude.com/docs/en/memory) — CLAUDE.md + auto memory
- [code.claude.com/docs/en/mcp](https://code.claude.com/docs/en/mcp) — Claude Code as MCP server (`claude mcp serve`)
- [claude.com/blog/introducing-routines-in-claude-code](https://claude.com/blog/introducing-routines-in-claude-code) — Routines announcement
- [claude.com/blog/claude-code-on-the-web](https://claude.com/blog/claude-code-on-the-web) — cloud sessions announcement
- [claude.com/blog/run-claude-code-sessions-on-your-own-compute](https://claude.com/blog/run-claude-code-sessions-on-your-own-compute) — self-hosted runners beta (referenced via search aggregation, not independently re-fetched — see Finding 9)
- [support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan](https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan) — official policy on Agent SDK + subscription quota
- [instances.vantage.sh/aws/ec2/t3.medium](https://instances.vantage.sh/aws/ec2/t3.medium) — EC2 pricing
- [openrouter.ai/anthropic/claude-sonnet-4.5](https://openrouter.ai/anthropic/claude-sonnet-4.5) — metered API pricing
- See auxiliary: `hermes-agent_costdata_1.md` — the cost arithmetic, the raw infra-spec quotes, and the real-world usage-cost data points, with confidence levels marked per source

## Findings

### Part 1 — What Hermes Agent is

#### Finding 1: Hermes Agent is a self-hosted, always-on, multi-platform personal agent — not a terminal coding tool

**Evidence:**
> "The self-improving AI agent built by Nous Research. It's the only agent with a built-in learning loop — it creates skills from experience, improves them during use, nudges itself to persist knowledge, searches its own past conversations, and builds a deepening model of who you are across sessions."
> "Run it on a $5 VPS, a GPU cluster, or serverless infrastructure that costs nearly nothing when idle. It's not tied to your laptop."
> "connects to Telegram, Discord, Slack, WhatsApp, Signal, and CLI — all from a single gateway process"

**Source:** [hermes-agent.org](https://hermes-agent.org/), fetched directly. Architecture (Agent Core, Gateway Process, Memory Store, seven terminal backends including Docker/SSH/Modal) confirmed via [github.com/NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) README, fetched directly.

**Significance:** Hermes is architecturally a persistent server process reachable from many chat surfaces, not a CLI tool a person opens per task. That is a different category from Claude Code's default session-per-invocation model, though Claude Code has moved toward always-reachable sessions too (Findings 8-9, 15).

**Verification:** Both URLs fetched directly on 2026-09-01; quotes confirmed present in the fetched content.

#### Finding 2: v0.21.0 "Pantheon Release" adds Bot Mode — a persistent society of named agents that talk to each other and to the user

**Evidence:**
> "Bot Mode is now a bundled, default-on part of the desktop app" with named agents, deterministic avatars, and "Discord-style group chats where multiple bots and you talk in one room."
> "`hermes peer` — bot-to-bot DMs between your agents"
> "Cron agents now load and update persistent memory" with `continuity=true` carrying output between runs

**Source:** [github.com/NousResearch/hermes-agent/releases/tag/v2026.8.31](https://github.com/NousResearch/hermes-agent/releases/tag/v2026.8.31), fetched directly, 2026-08-31 release, ~5,800 commits / ~2,475 merged PRs / 760+ contributors since the prior baseline per the same release page.

**Significance:** This is the specific release that prompted the engineer's question. Its headline features are a standing multi-agent society (not spun up per task and torn down) and cron jobs that carry memory forward across scheduled runs — both distinct from a one-shot task.

**Verification:** URL fetched directly; quotes confirmed present in the fetched release notes.

#### Finding 3: Hermes Kanban is a durable, cross-agent task board — the feature that matches the engineer's mental model most directly

**Evidence:**
> "Hermes Kanban is a durable task board, shared across all your Hermes profiles, that lets multiple named agents collaborate on work without fragile in-process subagent swarms."
> Task states: `triage | todo | ready | running | blocked | review | done | archived` — `blocked` and `review` are parallel branch states reachable from `running`, not sequential steps in a single linear chain.
> Worker tools: `kanban_show`, `kanban_list`, `kanban_complete`, `kanban_request_review`, `kanban_request_changes`, `kanban_block`, `kanban_heartbeat`, `kanban_comment`, `kanban_create`, `kanban_link`, `kanban_unblock`, plus attachment tools.
> Workspace types: `scratch` (ephemeral), `dir:<path>` (preserved shared directory), `worktree` (git worktree, "preserved post-completion").

**Source:** [hermes-agent.nousresearch.com/docs/user-guide/features/kanban](https://hermes-agent.nousresearch.com/docs/user-guide/features/kanban), fetched directly and re-fetched for self-check.

**Significance:** This is the single feature that most literally matches "pull a card, an agent works it in its own worktree, it comes back with a review request." It is a first-class, persistent, human-and-agent-shared board — not a to-do list one agent keeps in its own head for one run. Whether Claude Code has an equivalent is addressed in Findings 12-13.

**Verification:** URL fetched directly on 2026-09-01, re-fetched for self-check same day; both quotes confirmed present, and the state machine branching shape (not a strict sequence) is confirmed by the re-fetch.

### Part 2 — What Hermes does that Claude Code genuinely cannot (skeptical pass)

#### Finding 4: Multi-platform reach (Telegram/Discord/Slack/WhatsApp/Signal) via one gateway is a real, distinct capability

**Evidence:** "connects to Telegram, Discord, Slack, WhatsApp, Signal, and CLI — all from a single gateway process" (Finding 1 source).

**Significance:** Claude Code's nearest equivalent is Remote Control (Finding 15) and the official Claude iOS/Android apps — both are Anthropic-first-party surfaces. Nothing found in this research gives Claude Code a native bridge into Telegram, Discord, Slack, WhatsApp, or Signal as messaging channels for the agent itself. If the engineer's workflow genuinely needs the agent reachable inside those specific chat apps (not just claude.ai/code or the Claude app), this is a real gap Claude Code does not close. **This is the strongest "Hermes does something Claude Code cannot" candidate found in this research.**

**Verification:** Same as Finding 1.

#### Finding 5: "Always-on for near-zero idle cost" is Hermes's own framing, but the true cost driver is inference, not the host — see the Cost section (Part 5)

**Evidence:** "Run it on a $5 VPS ... that costs nearly nothing when idle" (Finding 1 source).

**Significance:** Literally true for the compute host (confirmed independently in Part 5 — an EC2 instance sized to Hermes's own documented minimums costs roughly $30-33/month, not $5, but still small). It is misleading as a total-cost claim, because "idle" describes the host, not the inference bill, which is unrelated to whether the box is busy. This finding is deliberately narrow to avoid the trap of reading "near-zero idle cost" as "near-zero total cost" — Part 5 is where the real number lives.

**Verification:** Same as Finding 1; the EC2 cross-check is Finding 19.

#### Finding 6: Persistent cross-platform user modeling ("digital twin") is a broader memory model than Claude Code's, but Claude Code has a genuine native equivalent, not a gap

**Evidence:** Hermes: "builds a deepening model of who you are across sessions" (Finding 1). Claude Code: "Two mechanisms carry knowledge across sessions: CLAUDE.md files... Auto memory: notes Claude writes itself based on your corrections and preferences... Both are loaded at the start of every conversation."

**Source:** Hermes — Finding 1 source. Claude Code — [code.claude.com/docs/en/memory](https://code.claude.com/docs/en/memory), fetched directly.

**Significance:** This is a difference in SCOPE, not in kind. Hermes's memory model is explicitly cross-platform and person-modeling ("who you are"), reachable from every chat surface it bridges to. Claude Code's auto memory is explicitly scoped: "Each project gets its own memory directory... Auto memory is machine-local... Files are not shared across machines or cloud environments." Claude Code already does the "accumulate learnings without being told" part Hermes markets; what it does not do is unify that across machines or non-coding chat platforms.

**Verification:** Both URLs fetched directly on 2026-09-01; quotes confirmed present.

#### Finding 7: Kanban as the primary interface is Hermes's genuine differentiator over Claude Code's session-centric model, but Claude Code's Dynamic Workflows cover the parallel-orchestration mechanics without the persistent-board UX

**Evidence:** See Finding 3 (Hermes) and Finding 13 (Claude Code Dynamic Workflows) below.

**Significance:** Held for the "how much does Claude Code already deliver" section (Part 3) so the comparison is made once, directly, rather than twice.

### Part 3 — How much of the target model Claude Code already delivers

#### Finding 8: Claude Code on the web (claude.ai/code) already matches "assign a task, walk away, get a PR"

**Evidence:**
> "Claude Code on the web' is a new feature allowing developers to 'assign multiple coding tasks to Claude that run on Anthropic-managed cloud infrastructure.'"
> "Each session runs in its own isolated environment with real-time progress tracking." / "an isolated sandbox environment with network and filesystem restrictions."
> "run multiple tasks in parallel across different repositories from a single interface and ship faster with automatic PR creation and clear change summaries."
> "kick off coding sessions without opening your terminal"

**Source:** [claude.com/blog/claude-code-on-the-web](https://claude.com/blog/claude-code-on-the-web), fetched directly.

**Significance:** This is the closest native Claude Code equivalent to "pull a card, agent works it in isolation, comes back with a PR." It runs on Anthropic's own cloud infrastructure (no EC2 box for the engineer to manage), supports multiple parallel tasks across repos, and produces a PR as the deliverable — the same output shape the engineer wants. It is session-based rather than card-based (no shared persistent board across tasks the way Hermes Kanban is), which is the real structural gap versus Hermes — see Finding 7/13.

**Verification:** URL fetched directly; quotes confirmed present.

#### Finding 9: Self-hosted Claude Code environments (Aug 2026 public beta) let an organization run cloud-style sessions on its own infrastructure — UNVERIFIED at primary-source level, sourced via search aggregation only

**Evidence (via aggregation, not independently re-fetched):** "self-hosted environments for Claude Code entered public beta [on August 6, 2026], allowing you to run Claude Code sessions on your own infrastructure... Repository checkouts, build artifacts, secrets, and any files a session creates or modifies stay on machines the organization provisions. However, the conversation itself... is sent to Anthropic for inference..."

**Source:** WebSearch aggregation citing [claude.com/blog/run-claude-code-sessions-on-your-own-compute](https://claude.com/blog/run-claude-code-sessions-on-your-own-compute) and secondary press coverage (unite.ai, edtechinnovationhub.com). This blog URL was NOT independently fetched with WebFetch in this spike — mark **UNVERIFIED** at the primary-source level per Citation Discipline, though the claim is corroborated by multiple independent secondary sources describing the same August 6, 2026 date and mechanism (fixed vs. on-demand runners).

**Significance:** If accurate, this closes most of the remaining gap with Hermes's "run it on your own box" positioning — but it requires Team or Enterprise plan, and inference still routes through Anthropic (this is infrastructure self-hosting, not inference self-hosting — unlike Hermes, which can point at any model provider including local weights, per Finding 20).

#### Finding 10: git worktrees give Claude Code native, isolated, parallel-disk sessions — the mechanical prerequisite for "each agent has its own disk"

**Evidence:**
> "Running each Claude Code session in its own worktree means edits in one session never touch files in another, so one session can build a feature while a second fixes a bug."
> "In the desktop app, every new session gets its own worktree automatically."
> Enforcement is not advisory: "Claude Code blocks an Edit, Write, or NotebookEdit that targets a path in the main checkout" and three more mechanical checks (command working directory, git redirects, command shape) that "you can't turn ... off."

**Source:** [code.claude.com/docs/en/worktrees](https://code.claude.com/docs/en/worktrees), fetched directly.

**Significance:** This is not a manual convention the engineer has to remember — Claude Code mechanically blocks a tool call that would escape the worktree. Combined with the desktop app auto-creating one worktree per session, "each parallel agent has its own isolated disk" is already true today, without Hermes.

**Verification:** URL fetched directly; quotes confirmed present.

#### Finding 11: Background subagents are the interactive-session default — parallel work without a visible step-by-step conversation

**Evidence:**
> "Where fork mode is on, as it is by default in an interactive session, Claude Code runs the subagent in the background, forks and non-fork subagents alike, and Claude can't ask for the foreground."
> Concurrency: "By default, when 20 subagents are running in a session, spawning another with the Agent tool fails with `Concurrent subagent limit reached`" — and this limit "isn't enforced" when `ultracode` effort is active.
> Isolation: "Each subagent starts with a fresh, isolated context window. It doesn't see your conversation history..." Disk isolation is opt-in: "A subagent with `isolation: worktree` runs its Bash and PowerShell commands inside its worktree."

**Source:** [code.claude.com/docs/en/sub-agents](https://code.claude.com/docs/en/sub-agents), fetched directly.

**Significance:** Directly answers "no step-by-step conversation" — background is already the default, not an opt-in, for a normal interactive session. The 20-subagent default cap (removable) and the worktree-isolation opt-in are the two operational details that would need tuning to match the engineer's "many parallel agents" target.

**Verification:** URL fetched directly; quotes confirmed present, including the version-specific caveat ("Before v2.1.186, background subagents auto-denied any tool call that would have prompted") which the source did not resolve to an exact version where background became the *default* — treat "background is default" as confirmed, the exact version it became default as **UNVERIFIED**.

#### Finding 12: Agent Teams is Claude Code's closest analog to a persistent multi-agent society, but it is explicitly session-scoped, not durable across sessions like Hermes's board — and it is still experimental

**Evidence:**
> "Agent teams are experimental and disabled by default." "One session acts as the team lead... Teammates work independently, each in its own context window, and communicate directly with each other."
> Comparison table (verbatim column headers): Subagents "Own context window; results return to the caller" vs. Agent teams "Own context window; fully independent"; "Main agent manages all work" vs. "Self-coordination through messages, plus a shared task list."
> Limitations, quoted directly: "No session resumption with in-process teammates" / "One team per session: a session has exactly one team, scoped to that session. You can't create additional named teams or share a team across sessions." / "No nested teams: teammates cannot spawn their own teammates."

**Source:** [code.claude.com/docs/en/agent-teams](https://code.claude.com/docs/en/agent-teams), fetched directly.

**Significance:** This is the direct comparison point against Hermes's Kanban/Bot Mode (Findings 2-3). Agent Teams gives peer agents (not a hierarchy) with direct messaging and a shared task list — structurally close to Hermes's board. But it is (a) opt-in via an experimental environment variable, (b) scoped to one session with no cross-session persistence, and (c) capped at "no nested teams" and roughly 3-5 recommended teammates for practical use. Hermes's Kanban board is explicitly durable and cross-profile by design. This is the clearest concrete gap between the two systems found in this research.

**Verification:** URL fetched directly; quotes confirmed present.

#### Finding 13: Dynamic Workflows give Claude Code scripted, large-scale, resumable multi-agent orchestration — closer to Hermes's dispatcher than Agent Teams is, but the unit of work is a script run, not a durable card

**Evidence:**
> "A dynamic workflow is a JavaScript script that orchestrates many subagents at once. Claude writes the script for the task you describe, and a runtime executes it in the background while your session stays responsive."
> Scale: "Up to 16 concurrent agents, fewer when Claude Code has fewer CPUs available" and "1,000 agents total per run."
> Resumability: "The runtime tracks each agent's result as the run progresses, which is what makes a run resumable within the same session." A completed agent "returns its saved result" on relaunch; only agents downstream of a changed or failed one rerun.
> Explicit comparison table column, verbatim: "What's repeatable" → Workflows: "The orchestration itself," vs. Agent teams: "The team definition."

**Source:** [code.claude.com/docs/en/workflows](https://code.claude.com/docs/en/workflows), fetched directly.

**Significance:** Workflows are the mechanical answer to "many parallel agents, coordinated, without a step-by-step conversation" — a script holds the plan, agents run in the background, results are cached and resumable, and the built-in `/deep-research` workflow demonstrates the exact "kick off, walk away, get one report" shape the engineer wants. What Workflows do NOT provide is Hermes's durable, human-and-agent-shared BOARD as the entry point — a workflow is invoked per task (or saved as a reusable command), not a place where cards accumulate and get triaged/pulled over days or weeks the way Hermes's `triage → todo → ready` states imply.

**Verification:** URL fetched directly; quotes confirmed present.

#### Finding 14: Routines give Claude Code scheduled, triggered, PR-producing automation on cloud infrastructure — the nearest match to Hermes's "cron with memory," with one confirmed gap on cross-run memory

**Evidence:**
> "A routine is a Claude Code automation you configure once — including a prompt, repo, and connectors — and then run on a schedule, from an API call, or in response to an event."
> "Claude opens one session per PR and will continue to feed updates from that PR to the session, so it can address follow-ups like comments and CI failures."
> Triggers: scheduled ("hourly, nightly, or weekly"), API-based (its "own endpoint and auth token. POST a message, get back a session URL"), webhook-based (GitHub events).

**Source:** [claude.com/blog/introducing-routines-in-claude-code](https://claude.com/blog/introducing-routines-in-claude-code), fetched directly (announcement dated April 14, 2026 per the same source).

**Significance:** Routines match Hermes's "scheduled ops — recurring daily briefs that build a journal over weeks" use case (quoted in Finding 3's source as one of Hermes Kanban's target workloads) on the trigger and delivery side. The gap is memory continuity: the fetched announcement text describes session continuity WITHIN one PR's follow-up thread, not memory carried FROM one scheduled run TO the next the way Hermes's v0.21.0 "cron agents now load and update persistent memory" (Finding 2) explicitly does. **This is a genuine, source-confirmed gap** — Hermes's release notes make an explicit cross-run memory claim that the Claude Code Routines announcement text does not make for its own scheduled runs.

**Verification:** URL fetched directly; quotes confirmed present. The absence of a cross-run-memory claim in the Routines announcement is an absence, not a positive claim that Routines lack it — flagged as **uncertain**, not as a confirmed negative (see "What remains uncertain").

#### Finding 15: Remote Control gives phone/browser control of a Claude Code session already running on the engineer's own machine

**Evidence:**
> "Remote Control connects claude.ai/code or the Claude app for iOS and Android to a Claude Code session running on your machine."
> "Claude keeps running locally the entire time, so your code execution and filesystem access stay on your machine." / "the conversation and the progress of subagents and dynamic workflows stay in sync across all connected devices."

**Source:** [code.claude.com/docs/en/remote-control](https://code.claude.com/docs/en/remote-control), fetched directly.

**Significance:** This answers the "control from the phone" half of the target model, but with a structural caveat Hermes does not share: Remote Control is a window into a session that must already be running on a machine the engineer controls (their laptop, or per Finding 9 a self-hosted runner) — it is not itself the compute. Hermes's server process runs independently of any device. Claude Code on the web (Finding 8) is the piece that removes this dependency, at the cost of being a separate mode from Remote Control rather than the same session.

**Verification:** URL fetched directly; quotes confirmed present.

### Part 4 — Integration, coexistence, migration

#### Finding 16: Bidirectional MCP interoperability between Hermes and Claude Code is real and officially documented on both sides — but each side's server mode is scoped narrowly, and neither exposes its own orchestration primitive (Kanban, or Workflows/Agent Teams) to the other over MCP

**Evidence — Hermes as MCP server (self-checked via re-fetch):**
> "In addition to connecting to MCP servers, Hermes can also be an MCP server. This lets other MCP-capable agents (Claude Code, Cursor, Codex, or any MCP client) use Hermes's messaging capabilities — list conversations, read message history, and send messages across all your connected platforms."
> "The MCP server exposes 10 tools, matching OpenClaw's channel bridge surface plus a Hermes-specific channel browser" — confirmed by re-fetch to be messaging-only tools (`conversations_list`, `messages_read`, `messages_send`, `channels_list`, etc.); the re-fetch explicitly confirmed "No kanban tools mentioned... The capabilities are explicitly limited to messaging operations."

**Evidence — Claude Code as MCP server:**
> "You can use Claude Code itself as an MCP server that other applications can connect to: `claude mcp serve`... A stdio MCP server communicates over stdin and stdout." Configurable directly in `claude_desktop_config.json`.

**Source:** Hermes — [hermes-agent.nousresearch.com/docs/user-guide/features/mcp](https://hermes-agent.nousresearch.com/docs/user-guide/features/mcp), fetched and re-fetched for self-check. Claude Code — [code.claude.com/docs/en/mcp](https://code.claude.com/docs/en/mcp), fetched directly.

**Significance:** Both tools officially, natively support being called as an MCP server by the other — this is not a hack. But the practical interoperability is narrower than "Hermes orchestrates Claude Code as a worker via MCP" or vice versa: Hermes's MCP-server surface is messaging only (no way to hand it a coding task or read its Kanban board over MCP), and Claude Code's MCP-server surface exposes its general tool set (file edit, bash, etc.) rather than a task-queue interface. A community article (generativeai.pub, NOT an official source, third-party) describes wiring the two together with Claude Code as the "focused coding specialist called from the terminal by Hermes" — but this pattern relies on Hermes shelling out to the `claude` CLI (headless `-p` mode) rather than MCP, and is a community integration pattern, not a documented first-party feature of either project. Flagged **UNVERIFIED as an official capability** — treat as a plausible DIY integration, not a supported one.

**Verification:** Both official URLs fetched directly and, for Hermes, re-fetched for self-check on 2026-09-01; all quotes confirmed present in the fetched content.

#### Finding 17: A related, still-open Hermes feature request confirms Claude Code is already being reached for as a coding backend from inside Hermes — via `claude -p` headless mode, not the subscription

**Evidence:**
> Issue title: "Integration: MCP provider for Claude Code subscription — local backend without API keys #47199." Status: open, P3 priority. "Hermes agents can't access Claude Max/Pro subscription directly (as of April 4, 2026). Current paths force a choice: [1] Separate API billing...costs money separately from Max plan, [2] Alternative models..."

**Source:** [github.com/NousResearch/hermes-agent/issues/47199](https://github.com/NousResearch/hermes-agent/issues/47199), fetched directly.

**Significance:** This is the Hermes community itself independently confirming, as of the issue's own dated text (April 4, 2026), that there is no clean way for a Hermes agent to consume a Claude Max/Pro subscription — it is either a separate API bill or a non-Claude model. This directly foreshadows the cost findings in Part 5, from a source inside the Hermes project rather than from Anthropic.

**Verification:** URL fetched directly; quote confirmed present.

#### Finding 18: The engineer's existing Claude-Code-specific governance investment (hooks, skills, subagent contract, policy corpus) has no documented Hermes equivalent found in this research, and would not transfer

**Evidence:** This is drawn from 4Shark's own internal `CLAUDE.md` (the document governing this session), not an external source — cited as a fact about the engineer's own environment, not an external claim. The corpus includes: dozens of `PreToolUse`/`PostToolUse`/`Stop`/`SubagentStart` hooks enforcing specific code, git, and infrastructure policies; a nine-agent subagent contract with designated-file write exceptions and two independent read-only verifiers; a curated `coding-policies`/`terraform-policies` document-loading model; and per-repo conventions accumulated over the life of the tooling.

**Significance:** Nothing in the Hermes documentation fetched during this research (skills, MCP, cron, Kanban, Bot Mode) describes an equivalent to Claude Code's `PreToolUse`/`Stop` hook system with mechanical, non-bypassable blocks (e.g., the worktree-escape blocks in Finding 10, or the destructive-git-command blocks referenced in the governing CLAUDE.md). Hermes does have "Protected instruction files requiring write approval" (Finding 2's release notes) and a "Comprehensive security redaction sweep," which are conceptually adjacent but not confirmed to be the same mechanism (a mechanical, per-tool-call, non-model-editable gate). Migrating would mean rebuilding this governance layer from scratch on an unverified foundation, or running without it.

**Verification:** Internal-document citation; no external URL to verify. Flagged explicitly as internal-source-only.

### Part 5 — Cost and infrastructure economics

#### Finding 19: The compute host itself is small and cheap either way — not the deciding cost factor

See auxiliary `hermes-agent_costdata_1.md` §1-2. Hermes's own documented minimum for cloud-API mode ("2 CPU cores, 2-4 GB RAM, 20-30 GB SSD storage," per third-party VPS-advisory aggregation, not Nous Research's own docs — treat as directional) maps to an AWS `t3.medium` (2 vCPU, 4 GiB RAM), confirmed at **$0.0416/hour** directly from [instances.vantage.sh/aws/ec2/t3.medium](https://instances.vantage.sh/aws/ec2/t3.medium) — roughly **$30-33/month** including storage (own calculation). The engineer's "an EC2 running" framing is directionally correct and the cost is genuinely small, but it is not the number that matters — see Finding 20 onward.

**Verification:** EC2 pricing URL fetched directly; quote confirmed present. Hermes spec figures sourced only via aggregation of third-party advisory sites, not Nous Research's own docs — flagged **lower-confidence** in the auxiliary file.

#### Finding 20: Hermes bundles no model — it is BYO-inference, with OpenRouter as its documented default fallback aggregator

**Evidence:** Provider list confirmed via WebSearch aggregation of [github.com/NousResearch/hermes-agent/blob/main/website/docs/integrations/providers.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/integrations/providers.md) (not independently re-fetched with WebFetch — treat the exhaustive list as **UNVERIFIED at the individual-entry level**, though the general shape — many providers including `anthropic`, `openrouter`, `bedrock`, `ollama-cloud` — is corroborated by multiple independent search results): "OpenRouter is Hermes Agent's default fallback aggregator — one API key that routes to Claude, GPT, Gemini, DeepSeek, Grok, Kimi, GLM, and dozens more."

**Significance:** Unlike Claude Code, which is Anthropic's own product and defaults to the engineer's existing Claude subscription with no separate configuration, Hermes requires the engineer to explicitly point it at a model provider and pay that provider's rate. This is the root of the cost question — Hermes is provider-agnostic by design, which is a strength for avoiding lock-in, but means there is no flat-rate option built in the way Claude Code's Pro/Max plans are.

**Verification:** Not independently re-fetched; sourced via search aggregation of the official providers.md file plus multiple third-party corroborating sources. Confidence: **moderate** — the existence of many providers and OpenRouter-as-default is corroborated across independent sources; the exact enumerated list is not independently confirmed.

#### Finding 21: Anthropic's Consumer Terms of Service explicitly forbid using a Claude Free/Pro/Max subscription's OAuth token in any third-party tool — confirmed via the official Agent SDK support page, current as of the date fetched

**Evidence:**
> "For now, we're pausing the changes to Claude Agent SDK usage described below. For now, nothing has changed: Claude Agent SDK, `claude -p`, and third-party app usage still draw from your subscription's usage limits." — the page confirms that, as currently in effect, **third-party apps that authenticate through the official Agent SDK** are permitted to draw from subscription quota, with no separate credit pool (that separate-credit-pool change was announced for June 15, 2026 and then paused).
> Separately, via search aggregation of Anthropic's legal/compliance page (not independently re-fetched — **UNVERIFIED at primary-source level**, but corroborated by four independent news sources with consistent wording): "Using OAuth tokens obtained through Claude Free, Pro, or Max accounts in any other product, tool, or service — including the Agent SDK — is not permitted and constitutes a violation of the Consumer Terms of Service."

**Source:** [support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan](https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan), fetched directly. The second quote is via aggregation only.

**Significance — reconciling an apparent contradiction:** These two statements look contradictory (OAuth-in-Agent-SDK is "not permitted" vs. "third-party app usage still draw[s] from your subscription's usage limits") until read together with Finding 22: the sanctioned path is a third-party app authenticating **through the official Claude Agent SDK library**, which handles the subscription auth correctly on the app's behalf. What is banned is a third-party tool taking the raw OAuth token and hitting Anthropic's API endpoints directly, bypassing the Agent SDK. That distinction is exactly what Finding 22 shows Hermes currently gets wrong.

**Verification:** The support.claude.com URL was fetched directly, and the pause/current-state quote is confirmed present. The legal-terms exact wording quote is sourced via aggregation only and is flagged **UNVERIFIED at primary-source level** in this document, though structurally consistent with the confirmed page.

#### Finding 22: Hermes's own bug tracker confirms its Anthropic integration hits the raw metered API endpoint, not the sanctioned Agent SDK path — so a Claude Max/Pro subscription cannot cleanly be reused with Hermes today

**Evidence:**
> Issue title: "Claude Code OAuth (Max/Pro plan) still hits pay-per-token API endpoint — drains 'extra usage' credits instead of using subscription quota."
> "`agent/anthropic_adapter.py` builds an Anthropic SDK client using OAuth tokens but directs requests to `https://api.anthropic.com/v1/messages` — the pay-per-token endpoint — regardless of subscription status." Users report: "You're out of extra usage. Add more at claude.ai/settings/usage." Status at time of research: **open, P2 priority ("degraded with workaround"), no maintainer response recorded.**

**Source:** [github.com/NousResearch/hermes-agent/issues/40014](https://github.com/NousResearch/hermes-agent/issues/40014), fetched directly.

**Significance:** This is the single most decision-relevant finding in this spike. It confirms, from Hermes's own bug tracker (a primary source, not a third-party blog), that today, pointing Hermes at a Claude Max/Pro subscription OAuth token does NOT cleanly consume the flat-rate subscription — it either burns metered "extra usage" credits (itself a paid add-on, separate from the base $200/month) or, per Finding 21, may not be a sanctioned use of the OAuth token in the first place, since Hermes's own adapter bypasses the official Agent SDK. Either way: **there is no confirmed, working, ToS-compliant path today for the $200/month Claude Max plan to cover Hermes's Anthropic inference.**

**Verification:** URL fetched directly; quotes confirmed present, including the exact file path (`agent/anthropic_adapter.py`) and endpoint (`api.anthropic.com/v1/messages`) named in the issue.

#### Finding 23: The fix — Agent-SDK-based subscription authentication, modeled on how OpenAI's Codex CLI already does this for ChatGPT subscribers — is an open, unimplemented Hermes feature request

**Evidence:**
> Issue title: "[Feature]: Claude Agent SDK model provider with subscription OAuth (Codex-style) #25267." "This is asking Hermes to support Claude subscription authentication via the Agent SDK, mirroring how the existing Codex OAuth credential pool works for OpenAI subscribers." Status: **open, "needs-decision" label, no maintainer response, not implemented; the requester volunteered to implement it but no associated pull request shows completion.**

**Source:** [github.com/NousResearch/hermes-agent/issues/25267](https://github.com/NousResearch/hermes-agent/issues/25267), fetched directly.

**Significance:** Confirms Finding 22 is a known, named gap with a proposed fix, not a permanent architectural limitation — but it is unimplemented as of this research, with no committed timeline. Anyone adopting Hermes today to reuse a Claude subscription would be relying on a fix that does not yet exist, per Hermes's own tracker.

**Verification:** URL fetched directly; quotes confirmed present.

#### Finding 24: Metered inference for heavy agentic usage is real money, per-person, uncapped — a flat subscription (Claude Max) caps cost, metered API does not

**Evidence:** See auxiliary `hermes-agent_costdata_1.md` §3-5 for the full figures and confidence levels. Directly fetched: Claude Sonnet 4.5 on OpenRouter costs **"$3.00/M input tokens and $15.00/M output tokens"** (confirmed at [openrouter.ai/anthropic/claude-sonnet-4.5](https://openrouter.ai/anthropic/claude-sonnet-5.5)). Via lower-confidence aggregation of third-party analysis (not independently re-fetched, treat as **UNVERIFIED-but-plausible**): heavy/parallel-agent usage is reported in the range of "$500 to $2,000 per month" per person, with one reported case ("Microsoft's Experiences + Devices division") at "~$2,000 per engineer per month."

**Significance:** This is the structural point the coordinator flagged as pivotal. A Claude Max plan is a **flat, capped** monthly cost ($100 or $200) regardless of how hard the engineer drives it within the plan's usage limits. Metered API billing (which is what Hermes's Anthropic path currently falls back to, per Finding 22, or what a deliberate OpenRouter/API-key setup would use) is **uncapped by construction** — the more agents run, the more it costs, with no ceiling. For a 3-engineer team routing real, heavy, always-on multi-agent coding work through metered billing, the documented range (per person, per month) points to roughly **$450-$6,000/month for the team** at the high end of documented real-world reports, before accounting for Hermes's own multi-agent fan-out (Kanban board with several concurrent workers) potentially multiplying that further. The engineer's own "tens of thousands per month" fear was **not found independently confirmed** at that magnitude in this research — see auxiliary file §5 for the explicit reasoning — but the STRUCTURAL claim behind the fear (uncapped metered billing can run arbitrarily high, unlike the flat plan) is correct and source-grounded.

**Verification:** OpenRouter pricing URL fetched directly; quote confirmed present. The heavy-usage dollar figures are aggregation-sourced and flagged accordingly in the auxiliary file.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Hermes Kanban board as primary interface | Durable, cross-profile, human-and-agent-shared; matches the engineer's mental model closely; explicit `triage→...→done` states designed for pull-based work | No first-party bridge from an external orchestrator to drive it (MCP server exposes messaging only, not `kanban_*`); requires abandoning Claude Code's session model | Findings 3, 16 |
| Claude Code Agent Teams | Native, first-party, peer agents with direct messaging + shared task list; zero extra infra | Experimental/opt-in; session-scoped only, no cross-session persistence; "no nested teams"; practical cap ~3-5 teammates | Finding 12 |
| Claude Code Dynamic Workflows | Scripted, resumable, up to 1,000 agents/run, 16 concurrent; built-in `/deep-research` shows the exact "kick off, walk away, one report" shape | Not a durable shared board — invoked per task/saved command, not a place cards accumulate over weeks | Finding 13 |
| Claude Code on the web / self-hosted runners | Matches "assign task, walk away, get PR" almost exactly; Anthropic-managed compute (no server to run) unless self-hosted | Session-based, not card-based; self-hosted option needs Team/Enterprise plan and engineering staff to maintain (Finding 9, UNVERIFIED at primary-source level) | Findings 8, 9 |
| Reusing the $200/mo Claude Max plan with Hermes | Would be free if it worked | Confirmed NOT to work cleanly today — Hermes's own Anthropic adapter hits the metered endpoint (Finding 22); the fix is an open, unimplemented feature request (Finding 23) | Findings 21-23 |
| Metered API/OpenRouter billing (required for Hermes today) | Uncapped ceiling means unlimited scale if budget allows; provider-agnostic, can mix cheaper models | Uncapped is a two-way door — cost has no ceiling and scales directly with parallel/always-on agent count; documented heavy-use reports range $150-2,000+/month per person | Findings 20, 24 |

## What remains uncertain

- Whether Claude Code's self-hosted runner beta (Finding 9) is accurately described — the announcement blog itself was not independently fetched with WebFetch in this spike, only corroborated via search aggregation of multiple secondary sources.
- The exact version of Claude Code where background subagents became the *default* (Finding 11) — the fetched doc confirms it IS the default today and references pre-v2.1.186 behavior, but does not state the version where the default flipped.
- Whether Claude Code Routines genuinely lack cross-run memory the way Hermes's cron+memory explicitly claims to have it (Finding 14) — this is an absence in the fetched announcement text, not a confirmed negative from a source that directly addresses the question.
- The full, exact list of model providers Hermes supports (Finding 20) — corroborated in shape via aggregation, not independently verified entry-by-entry against the primary `providers.md` file.
- The exact Anthropic Consumer Terms of Service wording forbidding OAuth-token reuse in third-party tools (Finding 21, second quote) — corroborated by multiple independent news sources with consistent wording, but the legal page itself was not independently fetched.
- Whether the community-documented "wire Claude Code into Hermes via MCP" pattern (mentioned in Finding 16) is stable/maintained — it is a third-party blog pattern, not a supported feature of either project, and was not independently verified as functioning.
- The precise monthly dollar figure a 3-engineer 4Shark-style team would actually incur running Hermes for real, heavy, always-on multi-agent coding work — bounded above and below by the ranges in Finding 24, but no source in this research measured a team of this specific shape and workload.

## Suggested options for main and the engineer

- **Option A — Stay on Claude Code, deliberately adopt the underused native features.** Combine git worktrees (Finding 10, already mechanically enforced per 4Shark's own worktree policy) + Claude Code on the web (Finding 8) for the "assign and walk away" flow + Dynamic Workflows (Finding 13) for large parallel fan-outs + Routines (Finding 14) for scheduled/triggered automation + Remote Control (Finding 15) for phone check-ins. **Cost: $0 incremental** — covered by the existing $200/mo Max plan, as long as usage stays within the plan's included limits (Finding 21 confirms first-party Claude Code usage is the sanctioned, subscription-covered path). The remaining gap versus Hermes is the durable cross-session Kanban-style board (Agent Teams, Finding 12, is session-scoped only) — this is a genuine, not-yet-closed structural difference.

- **Option B — Coexist: run Hermes narrowly for the capability it's genuinely ahead on (Finding 4 — multi-platform reach into Telegram/Discord/Slack/WhatsApp/Signal as an always-on assistant), keep Claude Code for coding work.** **Cost: ~$30-33/month EC2 (Finding 19) + a genuinely separate metered inference bill**, because the $200 Max plan cannot cleanly cover Hermes today (Finding 22). If usage stays light/bursty (the "always-on assistant" niche, not heavy coding fan-out), the metered bill could stay in the tens-to-low-hundreds of dollars per month; if coding workload gets routed through it, expect the $150-2,000+/month per-person range in Finding 24, on top of the $200 already being paid for Claude Code.

- **Option C — Migrate fully to Hermes for the multi-agent coding workflow.** **Cost: the same metered inference bill as Option B, but for the team's full coding workload** (documented range implies roughly $450-6,000+/month for a 3-person team at the high end of what's documented, uncapped) **+ the EC2 host + the one-time cost of rebuilding 4Shark's entire Claude-Code-specific governance layer** (Finding 18 — hooks, skills, subagent contract, policy corpus) on an unverified foundation, since no Hermes equivalent to the mechanical `PreToolUse`/`Stop` hook system was found in this research. This also means giving up the $200/mo plan's flat, capped cost structure entirely.

- **Option D — Wait.** Issue #25267 (Finding 23) is the one that would remove the double-billing problem if implemented (Agent-SDK-based subscription auth for Hermes, "Codex-style"). It is open and unimplemented with no committed timeline. Revisiting Options B/C becomes materially cheaper if and when that lands.

(No recommendation given between these — the trade-off is the engineer's and main's to weigh: how much genuine weight the multi-platform reach (Finding 4) and durable Kanban board (Finding 3) carry for this specific workflow, against a confirmed, uncapped, currently-unavoidable second inference bill (Findings 21-24) and an unquantified governance-rebuild cost (Finding 18).)
