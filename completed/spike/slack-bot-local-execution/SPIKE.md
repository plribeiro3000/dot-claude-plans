# SPIKE — Slack Bot Triggering Local Claude Code Execution

## Investigation question

A 4Shark engineer (macOS, Claude Code) wants a bot in the company Slack. Someone mentions the bot in a specific channel with a natural-language command (e.g. "@bot roda o integrador da Atento MX"). The command must execute ON the engineer's own local machine — because only there do the VPN, AWS profiles, 1Password, and the team's custom skills (`~/.claude/skills/integrators` already implements the "roda o integrador" flow) exist. The response returns to the channel. When the machine is offline, the bot should answer something like "server inactive" instead of staying silent.

**Question to answer**: what are the viable architectures, with what trade-offs, and what is the risk surface? This spike does not choose an architecture — it surfaces options and trade-offs for the engineer to decide.

**Addendum (second research round)**: the engineer decided Axis 1 (transport/reachability — see "Decisions and open options" below) and brought a second, related question that the first round did not cover: how does the team lock down *what the bot will do* — which channel it lives in, whether it answers DMs, whether anyone can invite it elsewhere, what command surface (structured vs. free natural language) is safest, and — new to this round — that every invocation spends the engineer's own Claude token/budget, making "who can trigger it and how often" a cost question as much as a security one.

**STATUS: CLOSED — decision: do not build.** The engineer reviewed this spike's Axis 4 material and decided not to build the bot at all — see "Outcome" at the end of this document for the decision in his own words, the reasoning, and which findings survive as reusable material for whatever comes next. The axes below (2 through 6) are preserved for historical/reference value; Axis 1 stays recorded as a decision, and Axes 2–4 are now marked **Moot**, Axes 5–6 are marked **Survives**. Nothing below represents open, pending work.

## Revision note

This document has been revised four times.

**First revision** — after `output-verifier` returned REJECT for citation-integrity failures on the original draft. Two defects were found and fixed: (1) Finding 2 attributed a fabricated quote to GitHub issue #53049 and its verification block falsely claimed the quote had been checked; (2) Finding 9 presented a paraphrase (three separate source bullets merged into one invented sentence) as a verbatim quote. A full self-check of every other finding (per Citation Discipline rule 5) found the same defect at smaller scale in Findings 3, 4, 5, 6, 7, 11, and 12 — an ellipsis (`...`) bridging two non-adjacent sentences into what read as a single contiguous quotation — corrected to either two separate quotes or a single genuinely contiguous one.

**Second revision** — two additions: (1) recorded the engineer's decision on Axis 1, which was previously an open option; (2) a new research round (Findings 18–25) answering the engineer's follow-up question about locking down what the bot can do — DM handling, slash-command scope, channel-invite control, cost/token control, and industry ChatOps authorization practice. While re-verifying sources for this round, a residual citation defect was found in **Finding 16** from the first draft: its quoted sentence fused a confirmed clause ("Always validate an incoming slash command request...") with an unconfirmed one ("...and always work with user IDs and channel IDs") that does not appear verbatim on the cited page. Finding 16 was corrected — the confirmed clause kept as a verbatim quote, the unconfirmed clause dropped per quote-or-drop, status upgraded from fully UNVERIFIED to partially verified.

**Third revision** — the same ellipsis-across-sentence-boundary defect from the first revision reappeared in **Finding 25**, the second revision's own most consequential finding (the one narrowing Finding 15's risk and feeding directly into the engineer's Axis 4 decision). Finding 25's quote strung together three non-adjacent sentences from the `dontAsk` section — skipping, without marking the skip, a status-bar sentence and a v2.1.199 MCP-tools footnote in between — and its verification block asserted "each as its own contiguous span," which was false for that quote. A table-cell fusion was also present: the quote combined the "Best for" column header with its cell content as if they were running prose, and — caught during the same correction pass — added a trailing period inside the quotation marks for that cell's text that is not present in the actual table cell (a table cell is not a sentence). Finding 25 was rewritten so every quoted span is either a genuinely contiguous sentence/cell or presented as a separate, individually-quoted item, with no ellipsis crossing a sentence boundary anywhere in the Finding. Findings 18–24 were swept with the same check and found clean. One unrelated wording fix was made in the Axis 1 decision text: "exactly as Finding 10 recommends" was reworded to avoid verdict-shaped language.

**Fourth revision (this one)** — the engineer closed the spike: he decided not to build the bot at all. See the "Outcome" section for his reasoning, quoted directly in Portuguese with an English gloss (Category 4 embedded content per the Language Policy). Axes 2, 3, and 4 are now marked **Moot** — the premise they depended on (a local AI with full local access, contained only by a surface-level command/tool restriction) was rejected outright by the engineer, not resolved by choosing among the axis's options. Axis 1, Axis 5, and Axis 6, along with Findings 8, 9, 10, 11, 18, 19, 20, and 21, are marked **Survives** — they describe the Slack-side boundary (transport reliability, channel/DM enforcement, per-invocation cost caps) independent of which AI eventually sits behind the bot, and are expected to carry over directly to the indicated future work. Findings 22 and 23 (StackStorm's decoupled service identity, OWASP least privilege) shift role: they were an unresolved tension to name in the prior revisions and are now the starting premise of whatever design comes next. No new research was conducted for this revision and no new citation was added — this is a closure record, not a research update.

## Sources consulted

- https://docs.slack.dev/apis/events-api/using-socket-mode/ — Socket Mode disconnect/reconnect behavior; silent on what happens to an event with no client connected
- https://docs.slack.dev/apis/events-api/ — 3-second ack window, 3-retry schedule, auto-disable threshold
- https://docs.slack.dev/apis/events-api/comparing-http-socket-mode/ — Slack's own production-vs-local recommendation
- https://docs.slack.dev/interactivity/handling-user-interaction/ — `response_url` validity window
- https://docs.slack.dev/authentication/verifying-requests-from-slack/ — signing-secret verification, replay-attack window
- https://docs.slack.dev/interactivity/implementing-slash-commands/ — slash-command invocation scope (global by default), request-validation guidance (re-fetched twice this round — see Finding 16 and Finding 19)
- https://docs.slack.dev/surfaces/app-home/ — Messages tab, disabling DMs, `message.im` event, `im.history` scope
- https://claude.com/docs/claude-tag/overview.md — Claude Tag sandbox execution model
- https://github.com/anthropics/claude-code/issues/53049 — Remote Control external-injection feature request (re-fetched twice — see Finding 2 revision note)
- https://code.claude.com/docs/en/agent-sdk/overview.md — Agent SDK filesystem config loading, auth model
- https://code.claude.com/docs/en/channels.md — Channels research-preview mechanics
- https://code.claude.com/docs/en/slack — "Claude Code in Slack" (legacy), routing model, deprecation notice
- https://platform.claude.com/docs/en/api/claude-code/routines-fire — Routines API execution location
- https://code.claude.com/docs/en/headless — `claude -p` headless CLI, `--bare`, config loading
- https://code.claude.com/docs/en/cli-reference — `--max-turns` and `--max-budget-usd` cost/turn-limiting flags
- https://code.claude.com/docs/en/permission-modes — `bypassPermissions` / `dontAsk` / `auto` mode guidance for unattended execution (re-fetched a third time this round for Finding 25's full raw section)
- https://github.com/mpociot/claude-code-slack-bot (README + CLAUDE.md) — community bot #1 architecture
- https://github.com/AnandChowdhary/claude-code-slack-bot — community bot #2 architecture (cloud, not local)
- https://github.com/takafu/slack-claude-bot — community bot #3 architecture
- https://genai.owasp.org/llmrisk/llm01-prompt-injection/ — official OWASP LLM01 definition
- https://owasp.org/www-community/controls/Least_Privilege_Principle — official OWASP Least Privilege definition
- https://crontap.com/blog/dead-man-switch-explained-for-developers — heartbeat / dead man's switch pattern (considered and superseded — see Decisions)
- https://docs.stackstorm.com/rbac.html — StackStorm ChatOps RBAC, decoupled bot service identity
- https://onspring.com/resources/blog/what-is-an-audit-trail/ — audit trail as detection/accountability, not prevention (re-fetched this round to confirm heading/sentence contiguity for Finding 24)
- `~/.claude/skills/integrators/SKILL.md` — 4Shark's existing local-execution gate pattern for "roda o integrador"
- See auxiliary: `slack-bot-local-execution_community-bots_1.md` — full comparison table of the three community Slack+Claude Code bots

## Findings

### Finding 1: Claude Tag runs in an Anthropic-hosted sandbox, never on the engineer's machine

**Evidence:** *"When Claude works on a task, it runs in an ephemeral sandbox hosted by Anthropic, not on your computer or inside your network. The sandbox is created when a conversation starts, holds any code or files Claude is working with, and is discarded when the conversation goes idle."*

**Source:** https://claude.com/docs/claude-tag/overview.md

**Significance:** Confirms the previously-established finding. Claude Tag cannot reach the engineer's VPN, AWS profiles, 1Password, or `~/.claude/skills/`, because it never runs on the engineer's machine at all — it runs in a sandbox Anthropic hosts and discards per conversation. Claude Tag is out of scope for this requirement regardless of configuration.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed at the document's "Where Claude Tag runs" section.

### Finding 2: Remote Control has no public external-injection API — and the tracking issue is closed as a duplicate, not open

**Evidence:** GitHub issue #53049, filed by a user building a WhatsApp-to-Claude-Code bridge, requests exactly this capability. The issue's summary line states: *"Add a mechanism to send a prompt to an already-running Claude Code session from an external process and receive the response — without requiring the user to type in the UI."* The issue's current status is **"Closed as duplicate"** — not open, as an earlier internal note had stated.

**Source:** https://github.com/anthropics/claude-code/issues/53049

**Significance:** Corrects the previously-established finding, in two ways. First, the attributed quote itself was wrong: an earlier draft of this spike attributed a different sentence to this issue in quotation marks — that sentence does not appear in the issue body; the quote above is the actual summary line, re-fetched and confirmed correct. Second, the status correction stands: this issue is closed as a duplicate, not open. This does not mean the capability shipped — "closed as duplicate" points to another, presumably canonical, tracking issue rather than to a resolution — but the specific URL given should not be cited as "an open feature request". The underlying gap it documents is real: `claude --print` (the CLI's non-interactive form) *creates a new session* rather than injecting into an already-open interactive one. The issue's own problem description states: *"Today I can run `claude --print "task" --cwd /project/dir` which correctly picks up CLAUDE.md and project files. But this creates a **new** session, losing the in-memory conversation history of the session currently open in the UI."* This is corroborated independently by Finding 7 below (the headless docs describe `-p` as always starting a fresh non-interactive run).

**Verification:** URL re-fetched a second time specifically to correct this Finding / Verbatim quote checked against the raw issue body / Both quoted substrings confirmed present verbatim in the issue body as re-fetched.

### Finding 3: The Agent SDK runs in the caller's own process/infrastructure and loads `~/.claude/` filesystem config by default

**Evidence:**
```
The SDK also supports Claude Code's filesystem-based configuration. With
default options the SDK loads these from `.claude/` in your working
directory and `~/.claude/`. To restrict which sources load, set
`setting_sources` (Python) or `settingSources` (TypeScript) in your options.
```
And on execution location, from the SDK-vs-Managed-Agents comparison table: *"Runs in: Your process, your infrastructure"* (Agent SDK) vs *"Anthropic-managed infrastructure"* (Managed Agents). On authentication, the setup step reads: *"Get an API key from the Console, then set it as an environment variable."*, followed immediately by the code sample `export ANTHROPIC_API_KEY=sk-ant-xxxxx`. Bedrock/Vertex/Foundry are documented as alternate credential providers — no subscription-seat auth path is documented for this SDK.

**Source:** https://code.claude.com/docs/en/agent-sdk/overview.md

**Significance:** The Agent SDK is a viable local-execution surface: it runs where the caller's process runs (the engineer's Mac, if that's where the daemon is started) and by default picks up `~/.claude/skills/`, `~/.claude/commands/`, `CLAUDE.md`, and hooks — meaning `/integrators`-style skills would be available without extra wiring. The identified cost is authentication: it requires an `ANTHROPIC_API_KEY` (Console/metered billing), not the Claude subscription the engineer already holds for interactive Claude Code — a separate billing/quota surface to provision and monitor.

**Verification:** URL re-fetched with an explicit verbatim-reproduction request / Verbatim quote checked / Both quoted substrings confirmed present exactly as quoted, each within its own contiguous span (no cross-section merging).

### Finding 4: Channels push events into an already-open local session — they cannot start one, and delivery stops the moment the session closes

**Evidence:** *"A channel is an MCP server that pushes events into your running Claude Code session, so Claude can react to things that happen while you're not at the terminal."* Separately, later in the same paragraph: *"Events only arrive while the session is open, so for an always-on setup you run Claude in a background process or persistent terminal."* On supported platforms: *"Telegram, Discord, and iMessage are included in the research preview."* Slack is not in that list. From the "How channels compare" table, the Standard MCP server row reads: *"Claude queries it during a task; nothing is pushed to the session."*

**Source:** https://code.claude.com/docs/en/channels.md

**Significance:** Confirms and sharpens the previously-established finding. Two separate gaps for the 4Shark use case: (1) Channels does not currently ship a Slack plugin — Telegram, Discord, and iMessage are the three officially supported channels in the research preview; a custom Slack channel would have to be built against the Channels reference protocol; (2) even with a custom Slack channel, Channels only *delivers events into a session that is already running* — it does not spin up a new session on demand, so the underlying "is the machine/session alive" problem is not solved by Channels itself; a separate mechanism would still be needed to keep a Claude Code process alive as a background/persistent-terminal session, and to answer "offline" when that background process is not running.

**Verification:** URL re-fetched with an explicit verbatim-reproduction request / Verbatim quote checked / All four quoted substrings confirmed present exactly as quoted, each as its own contiguous span.

### Finding 5: "Claude Code in Slack" is being replaced by Claude Tag and, even before replacement, always routed to a cloud web session — never local

**Evidence:** *"Claude Code in Slack is being replaced by Claude Tag for Team and Enterprise workspaces."* On execution: *"When you mention `@Claude` with a coding task, Claude automatically detects the intent and creates a Claude Code session on the web, allowing you to delegate development work without leaving your team conversations."* Separately, in the following paragraph: *"Each session runs under your own Claude account, using your connected repositories and your plan limits."* Session flow step 3: *"Session creation: A new Claude Code session is created on claude.ai/code."*

**Source:** https://code.claude.com/docs/en/slack

**Significance:** Even setting aside the announced deprecation, this integration was never a local-execution path — it always created a `claude.ai/code` cloud session tied to a connected GitHub repository, with no access to the engineer's VPN, AWS profiles, 1Password, or `~/.claude/`. Not viable for this requirement, deprecation aside.

**Verification:** URL re-fetched with an explicit verbatim-reproduction request / Verbatim quote checked / All quoted substrings confirmed present exactly as quoted, each as its own contiguous span (the "creates a Claude Code session on the web" sentence and the "Each session runs under your own Claude account" sentence are in different paragraphs and are quoted separately rather than merged).

### Finding 6: The Routines API fires a cloud-hosted session with no path to local execution

**Evidence:** *"Claude Code on the web runs Claude Code sessions on Anthropic-managed cloud infrastructure at claude.ai/code, and a routine is a saved configuration there: a prompt, one or more repositories, and connectors, packaged so it can run unattended on a schedule, in response to GitHub events, or when called over HTTP."* Separately, in the following paragraph: *"This endpoint is the HTTP entry point. POSTing to it starts a new run of an existing routine and returns the resulting session ID and URL."*

**Source:** https://platform.claude.com/docs/en/api/claude-code/routines-fire

**Significance:** Confirms the previously-established finding. The Routines API is a clean, well-documented HTTP trigger (bearer token, `POST /v1/claude_code/routines/{routine_id}/fire`), but it is architecturally bound to Anthropic's cloud infrastructure and has no local-execution mode. Rejected as a path for this requirement on the same grounds as Claude Tag.

**Verification:** URL re-fetched with an explicit verbatim-reproduction request / Verbatim quote checked / Both quoted substrings confirmed present exactly as quoted, each as its own contiguous span.

### Finding 7: The headless CLI (`claude -p`) is the practical local-invocation surface, and it loads the full `~/.claude/` filesystem config by default

**Evidence:** *"Add the `-p` (or `--print`) flag to any `claude` command to run it non-interactively."* Separately, in the "Start faster with bare mode" section: *"Without it, `claude -p` loads the same context an interactive session would, including anything configured in the working directory or `~/.claude`."* (the "it" here refers to the `--bare` flag being discussed in that section — not inserted into the quote). And on skills specifically: *"User-invoked skills and custom commands work in `-p` mode: include `/skill-name` in the prompt string and Claude Code expands it before running."* `--bare` is the opposite case: *"Add `--bare` to reduce startup time by skipping auto-discovery of hooks, skills, plugins, MCP servers, auto memory, and CLAUDE.md."*

**Source:** https://code.claude.com/docs/en/headless

**Significance:** This is the concrete mechanism a local daemon would use: spawn `claude -p "roda o integrador da Atento MX" --allowedTools "..."` as a subprocess. Without `--bare`, this loads `~/.claude/skills/integrators/SKILL.md` and the rest of the team's config automatically — the same config the engineer's interactive session uses. This directly matches how the `takafu/slack-claude-bot` community project is built (Finding 13 / auxiliary file). Authentication for `claude -p` is not detailed on this page, but the Agent SDK page (Finding 3) documents `ANTHROPIC_API_KEY` or provider credentials as the auth path for programmatic/headless invocation, distinct from the interactive subscription login — this needs confirming for a bare `claude -p` invocation running under the engineer's already-authenticated CLI session, which the fetched pages do not explicitly state either way. **Not found**: whether `claude -p` run from the same user account that is already logged into interactive Claude Code reuses that OAuth session, or requires a separate `ANTHROPIC_API_KEY`.

**Verification:** URL re-fetched with an explicit verbatim-reproduction request / Verbatim quote checked / All four quoted substrings confirmed present exactly as quoted, each as its own contiguous span (the "Add the -p flag" sentence and the "Without it, claude -p loads the same context" sentence are in different sections of the page and are quoted separately rather than merged).

### Finding 8: Slack's own Socket Mode documentation does not state what happens to an event when no client is connected — and Slack's own comparison page recommends against Socket Mode for production

**Evidence:** The dedicated Socket Mode guide states only: *"If your app is actively receiving events when you toggle Socket Mode on, you may lose events until you establish a connection to your WebSocket URL"* and *"Expect disconnects to your WebSocket connection. These may happen when you toggle off Socket Mode in the app settings, or for other reasons."* Neither statement, nor anything else on that page, describes queuing, buffering, or redelivery behavior for an event sent while zero clients are connected. Separately, Slack's own HTTP-vs-Socket-Mode comparison page states: *"short-lived connections—like stateless HTTP connections—are inherently more reliable than long-lived connections"*; *"the socket server backend recycles containers serving connections every now and then, leading to occasional reliability issues"*; and, as a direct recommendation: *"To have the highest possible reliability for application connectivity, we recommend using HTTP for production applications"* — with Socket Mode's own recommended use case stated as: *"we recommend using Socket Mode when developing your app and using it locally"* and, for production, *"Once deployed and published for use in a team setting, we recommend using HTTP request URLs."*

**Source:** https://docs.slack.dev/apis/events-api/using-socket-mode/ ; https://docs.slack.dev/apis/events-api/comparing-http-socket-mode/

**Significance:** This directly answers the critical sub-question the brief raised. Slack's documentation is silent on redelivery/buffering for a disconnected Socket Mode client — there is no documented safety net. Combined with Slack's own explicit guidance that Socket Mode is a **local-development** transport and HTTP is the **production** transport, this means: (a) if the engineer's Socket-Mode-connected local process is offline when a teammate mentions the bot, the practical behavior — per the absence of any documented recovery mechanism — is that the event is not delivered and no retry is documented, so the mention simply produces no response unless a separate component intervenes; (b) Socket Mode is, by Slack's own words, not the transport Slack recommends for exactly the kind of always-should-be-reachable production bot this requirement describes. This is the crux of the offline-detection problem: Socket Mode by itself provides no "the bot is down" signal at all, only silence.

**Verification:** Both URLs re-fetched with explicit verbatim-reproduction requests / Verbatim quotes checked / All seven quoted substrings confirmed present exactly as quoted, each as its own separate contiguous span (no ellipsis-bridging used in this Finding).

### Finding 9: The HTTP Events API has a documented, bounded retry schedule and a documented reliability floor — properties Socket Mode does not share

**Evidence:** *"Your app should respond to the event request with an HTTP 2xx within three seconds."* Retry schedule, quoted verbatim as the source presents it: *"We'll knock knock knock on your server's door, retrying a failed request up to 3 times in a gradually increasing timetable: 1. The first retry will be sent nearly immediately. 2. The second retry will be attempted after 1 minute. 3. The third and final retry will be sent after 5 minutes."* Retries carry `x-slack-retry-num` and `x-slack-retry-reason` headers. Persistent-failure handling, quoted verbatim: *"Respond with success conditions to at least 5% of the events delivered to your app or your app will risk being temporarily disabled. However, apps receiving less than 1,000 events per hour will not be automatically disabled."* Separately: *"We'll also send you, the Slack app's creator and owner, an email alerting you to the situation."*

**Source:** https://docs.slack.dev/apis/events-api/

**Significance:** An HTTP-endpoint-fronted architecture gets three delivery attempts spread over roughly 6 minutes (immediate, +1 min, +5 min) before Slack gives up on that specific event — a bounded but real window in which a briefly-offline machine could come back and still receive the mention, if the endpoint that's retried is something other than the engineer's own laptop (since a laptop with no public HTTPS endpoint cannot be the direct target of Slack's HTTP retries at all — this is exactly why Socket Mode exists for non-publicly-reachable machines). This retry behavior is only available to an architecture that puts a public HTTP endpoint in front — meaning an always-on component (see the Decisions section below) — not to a bare Socket-Mode-only local bot.

**Verification:** URL re-fetched by this revision with an explicit verbatim-reproduction request, and the returned text matches the corrected ground-truth quotes the coordinator supplied when flagging this Finding / Verbatim quotes checked against the raw fetched text / All four quoted substrings (3-second ack, retry schedule, 5% threshold, email notification) confirmed present exactly as quoted, each in its own contiguous span, in the "Notes on retries" and rate-limit sections of the page. This corrects the prior version of this Finding, which had merged three separate retry-schedule bullets into one invented sentence and paraphrased the 5% threshold wording instead of quoting it verbatim.

### Finding 10: The 3-second acknowledgement constraint is handled by ack-then-respond-later, via `response_url` (bounded to 30 minutes / 5 sends) or `chat.postMessage`

**Evidence:** *"These responses can be sent up to 5 times within 30 minutes of receiving the payload."* (on `response_url`). Separately, from search-summarized guidance corroborated by the same interactivity model: a slash command or interaction handler must acknowledge within 3 seconds, after which further updates go through `response_url` or the standard `chat.postMessage` Web API call, which has no such time bound.

**Source:** https://docs.slack.dev/interactivity/handling-user-interaction/

**Significance:** "Roda o integrador" is a multi-minute operation (per `~/.claude/skills/integrators/SKILL.md`, it starts MongoDB, waits for it to be running, scales ECS services, launches a preview task, and explicitly **stops for the engineer's go** before the real run — see Finding 17). This is far outside both the 3-second Slack ack window and the 30-minute `response_url` window in the worst case (if the engineer doesn't confirm the preview quickly). The pattern this Finding documents: ack the Slack event immediately (empty 200 OK or an ephemeral "on it"), then post progress/results asynchronously via `chat.postMessage` in the thread — not via `response_url`, which is time- and count-bounded and could expire mid-flow for a long-running or human-gated operation like this one.

**Verification:** URL re-fetched with an explicit verbatim-reproduction request / Verbatim quote checked / Quote substring confirmed present exactly as quoted in the response_url section of the page.

### Finding 11: Slack request signature verification is a documented, mandatory control for any HTTP-fronted architecture

**Evidence:** *"Slack adds an `X-Slack-Signature` HTTP header"* to each request. Separately: *"The signature is created by hashing the request body with the SHA-256 function, and combining it with an HMAC signing secret."* The docs illustrate replay-attack rejection with this exact code comment: *"The request timestamp is more than five minutes from local time. It could be a replay attack, so let's ignore it."*

**Source:** https://docs.slack.dev/authentication/verifying-requests-from-slack/

**Significance:** Any architecture element that receives Slack webhooks directly over HTTP (an always-on component, if built as a webhook receiver rather than a Socket Mode client) must verify this signature and reject requests older than 5 minutes — otherwise anyone who can reach that HTTP endpoint could forge a Slack event and trigger the command flow. Socket Mode sidesteps this specific verification because the connection is already pre-authenticated — the Socket Mode guide states: *"there's no need to verify or validate inbound events, because you're receiving the events over a pre-authenticated WebSocket"* — but this trade-off only matters for the always-on-component design, not for a pure local Socket Mode client.

**Verification:** URL re-fetched twice with explicit verbatim-reproduction requests, once for this section and once separately confirming the Socket Mode quote against its own source page / Verbatim quotes checked / All quoted substrings confirmed present exactly as quoted, each as its own contiguous span. This corrects the prior version of this Finding, which had bridged the header-name sentence and the SHA-256 sentence with an ellipsis and included an unverified third clause ("unique to each request and doesn't contain any secret information") that has been dropped per the quote-or-drop rule.

### Finding 12: A generic heartbeat / dead man's switch pattern is the standard shape for "who answers when the primary is down" — considered and superseded this round (see Decisions)

**Evidence:** *"A dead man's switch is the developer pattern for 'alert me when the silence is the problem.'"* And: *"In software, the same idea shows up as a heartbeat or dead-man check: something that should happen on a schedule pings a monitor URL."*

**Source:** https://crontap.com/blog/dead-man-switch-explained-for-developers

**Significance:** This is a generic, widely-used pattern (not specific to Slack or Claude) that maps onto the "server inactive" requirement via a machine-pings-a-watcher model. The specific role split (a scheduler owning the clock, a job pinging on success, a watcher holding the tolerance window and firing on a late/missing ping) is described in the source but is not quoted here verbatim — the source presents it as a diagram-style list rather than flowing prose, and this spike restates it as an observation rather than risk a fused quotation. **This round, the engineer reviewed this pattern and chose a simpler mechanism instead — see "Decisions and open options" below for the reasoning.** The finding itself remains factually accurate and its citation remains verified; only its role in the architecture changed, from "the pattern this spike proposes" to "the pattern the engineer considered and rejected in favor of something with fewer moving parts."

**Verification:** URL re-fetched with an explicit verbatim-reproduction request / Verbatim quotes checked / Both quoted substrings confirmed present exactly as quoted, each as its own contiguous span. This corrects the prior version of this Finding, which presented a paraphrased restructuring of the source's scheduler/job/watcher bullet list as if it were a single verbatim quote; that material is now described in indirect prose (no quotation marks) per the quote-or-drop rule.

### Finding 13: Community Slack+Claude Code bots demonstrate the local-invocation pattern but do not solve offline detection, and default to no per-user access control

**Evidence:** See auxiliary file `slack-bot-local-execution_community-bots_1.md` for the full comparison with per-project quotes. Summary: `mpociot/claude-code-slack-bot` and `takafu/slack-claude-bot` both run locally via Socket Mode; `takafu`'s README states the bot **"spawns Claude Code CLI with the message"** as a subprocess and that Claude then **"uses Bash tool to call Slack API directly"**; `mpociot`'s `CLAUDE.md` documents **"All MCP tools are allowed by default"**. Neither project documents an allowlist of Slack users/channels permitted to trigger it, and neither documents an offline/"server down" response.

**Source:** README/CLAUDE.md of https://github.com/mpociot/claude-code-slack-bot and https://github.com/takafu/slack-claude-bot (full quotes in the auxiliary file)

**Significance:** These are the closest existing precedents to what the engineer is asking for, and they confirm both halves of the investigation: (1) the local-Socket-Mode-plus-CLI-subprocess architecture works and is exactly what a 4Shark implementation would look like at the invocation layer; (2) neither solves the offline-detection requirement, and neither restricts who can trigger command execution — both gaps the 4Shark implementation would need to close itself, not adopt from precedent. This round's cost-control question (Finding 21) sharpens this further: neither community bot documents any per-user rate limit or spend cap either.

**Verification:** URLs re-fetched with explicit verbatim-reproduction requests / Verbatim quotes checked / All three quoted substrings confirmed present exactly as quoted (each is an exact substring of a longer sentence in the source — e.g. "uses Bash tool to call Slack API directly" is a substring of the fuller README sentence "Claude uses Bash tool to call Slack API directly (via curl) for...").

### Finding 14: OWASP ranks Prompt Injection as the #1 risk for LLM applications, defined broadly enough to cover this exact shape

**Evidence:** *"A Prompt Injection Vulnerability occurs when user prompts alter the LLM's behavior or output in unintended ways."*

**Source:** https://genai.owasp.org/llmrisk/llm01-prompt-injection/

**Significance:** A bot that accepts free-form natural language from a Slack channel and feeds it to an agent holding AWS credentials, VPN reachability, 1Password, and 4Shark's operational skills is, structurally, exactly the risk category OWASP names #1. Anyone who can post in the channel — or whose earlier message is quoted/pasted into the channel by someone else — is a potential source of an instruction the agent might treat as a command. This is a defining property of the requested feature, not a peripheral concern. See the Command Surface Format discussion under Axis 4 below for how the engineer's structured-vs-free-language question connects to this Finding.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed in the page's opening definition.

### Finding 15: Claude Code's own documentation explicitly warns against exactly the unattended-execution posture this bot requires — with one caveat sharpened this round (see Finding 25)

**Evidence:** On `bypassPermissions` (the mode that would be needed for an unattended Slack-triggered process to run without stalling on an approval prompt nobody is present to answer): *"Only use this mode in isolated environments like containers, VMs, or dev containers without internet access, where Claude Code cannot damage your host system."* And separately: *"`bypassPermissions` offers no protection against prompt injection or unintended actions."* On the softer `auto` mode as an alternative: *"Auto mode reduces permission prompts but does not guarantee safety. Use it for tasks where you trust the general direction, not as a replacement for review on sensitive operations."*

**Source:** https://code.claude.com/docs/en/permission-modes

**Significance:** This is a direct, first-party warning against the specific shape this feature needs: a Slack-triggered daemon has, by construction, nobody watching the terminal to answer a permission prompt, so it needs some mode that does not block on approval — yet Anthropic's own guidance says `bypassPermissions` is intended only for "isolated environments... where Claude Code cannot damage your host system" and explicitly does NOT protect against prompt injection. The engineer's actual machine — with live AWS credentials, VPN, and 1Password access — is the opposite of "isolated... cannot damage your host system". `auto` mode is a softer alternative (a classifier reviews actions and blocks escalation, production deploys, and infra changes by default) but is explicitly not "a replacement for review on sensitive operations," and it still requires either an admin-enabled Team/Enterprise setting or specific plan/model support (per the same page) — its blocked-by-default list does include items directly relevant here, such as "production deploys and migrations" and "modifying shared infrastructure," which overlaps with what `/integrators` "roda o integrador" does. **This round's research (Finding 25) identifies a third mode, `dontAsk`, that may remove the need to choose between `bypassPermissions` and `auto` at all when the command surface is closed** — see Finding 25 and Axis 4 below.

**Verification:** URL fetched / Verbatim quote checked / All three quoted substrings confirmed present exactly as quoted, each as its own contiguous span, in the "Skip all checks with bypassPermissions mode" and "Eliminate permission prompts with auto mode" sections.

### Finding 16: Slack requires validating an incoming slash-command request — the specific channel_id/user_id-allowlisting guidance is not documented as an explicit sentence on the primary page (corrected this round)

**Evidence:** *"Always validate an incoming slash command request that has been issued to you by Slack."* The same page's error-response example uses an ephemeral response type: `{"response_type": "ephemeral", "text": "Sorry, slash commando, that didn't work. Please try again."}` — showing ephemeral responses (visible only to the requesting user) are a documented response shape, useful for silent-fail authorization errors. On `channel_id`/`user_id` specifically: the page's slash-command payload reference documents these fields exist in every request, but this spike did not find an explicit sentence on the page instructing the reader to validate them as an authorization allowlist — that specific guidance, present in the first draft of this Finding, was a fabricated fusion and has been removed.

**Source:** https://docs.slack.dev/interactivity/implementing-slash-commands/

**Significance:** The validation requirement (verify the request came from Slack — i.e. the signature check in Finding 11) is documented and confirmed. What is **not** documented on this specific page is a "check channel_id/user_id against an allowlist" recommendation as prose guidance — that pattern is a reasonable engineering inference from the payload fields existing, not a quoted best practice from this source. This distinction matters for Axis 5 below: channel/user restriction is something 4Shark's own code would implement, not something Slack's documentation instructs as a named practice on this page.

**Verification:** URL re-fetched twice this round with explicit verbatim-reproduction requests (once for the invocation-scope question in Finding 19, once specifically re-checking this Finding's original quote) / The confirmed clause is verbatim / The "user IDs and channel IDs" clause from the original draft was searched for specifically on the raw page content and not found as an exact sentence — dropped per quote-or-drop. Status upgraded from fully UNVERIFIED (first draft, WebSearch-aggregated only) to partially verified (this draft, direct re-fetch).

### Finding 17: 4Shark's own `/integrators` skill already has an explicit human-gate for exactly the operation named in the example ("roda o integrador")

**Evidence:**
```
4. **Preview the numbers via an ephemeral ECS task, then STOP for the
   engineer's go.** ...
   Surface the `NUMBERS` to the engineer and **wait** — do NOT start the
   integration until the engineer explicitly says "ok, pode rodar" (or
   equivalent).

5. **On the engineer's go, run the integration** — launch the same
   ephemeral task with `AUTO_ACCEPT=true`.
```

**Source:** `~/.claude/skills/integrators/SKILL.md:102-127` (steps 4–5 of "If the engineer asked to 'run the integrator'")

**Significance:** This is the concrete tension the brief asked to be named explicitly. The skill's documented flow is: scale up → preview the pending-record numbers via an `AUTO_ACCEPT=false` dry run → **stop and wait for the engineer's explicit go** → only then run with `AUTO_ACCEPT=true`. A Slack-triggered bot has two options, both with consequences: (a) preserve the two-step gate — the bot posts the preview numbers to the Slack thread and waits for a second message ("ok, pode rodar") before proceeding, which keeps the gate intact but means the *initial* trigger already required nobody to be at a terminal, and the second "go" is now also a Slack message, moving the authorization surface from "engineer's own terminal, engineer's own hands" to "whoever can post a convincing-enough reply in that Slack thread"; or (b) skip the gate for Slack-triggered runs and go straight to `AUTO_ACCEPT=true`, which is a stated divergence from the documented flow and removes the safety check entirely for this trigger path. Neither option is cost-free, and this spike does not choose between them — it names the tension per the brief's explicit request.

**Verification:** `file:line` reference confirmed by direct `Read` of `/Users/plribeiro3000/.claude/skills/integrators/SKILL.md`, lines 102–127.

### Finding 18: The Slack "Messages tab" is a config-level, no-code switch that can block DMs to the bot outright — distinct from simply not subscribing to the `message.im` event

**Evidence:** *"The Messages tab in an App Home provides a space for the app and user to converse."* On the scope needed to read DM history: *"Add im.history (Optional)."* On the event needed to respond to DMs: *"Your app must also subscribe to the message.im event so it can respond to messages."* On disabling it: *"This page is also where you can choose to disable the Messages tab, if you wish."*

**Source:** https://docs.slack.dev/surfaces/app-home/

**Significance:** This resolves the engineer's question with a real distinction between two different mechanisms, only one of which is pure config. **Disabling the Messages tab** (App Home settings, no code) is the closest thing to "the bot simply does not receive DMs" — it is a workspace/app-configuration action, not a runtime check. Separately, **not subscribing to the `message.im` event** means the app's code never receives a webhook for a DM sent to it — but this page does not state whether the DM composer UI itself still lets a user attempt to type and send a message when the event subscription is merely absent (as opposed to the Messages tab being explicitly disabled). **Not found**: an explicit statement on this page (or any page re-fetched this round) of what a user sees when they try to DM a bot that has the Messages tab enabled but no `message.im` subscription. What the page does establish clearly is that disabling the Messages tab is a genuine "does not receive" config option, while a bot that receives a DM and replies with a redirect message ("fale comigo no canal X") is necessarily a code-level "receives and refuses" behavior — the two are architecturally different, and the config-only path (disable the tab) is available.

**Verification:** URL fetched with an explicit verbatim-reproduction request / Verbatim quotes checked / All four quoted substrings confirmed present exactly as quoted, each as its own contiguous span.

### Finding 19: Slash commands are global across the workspace by default — invokable from any conversation, not scoped to the channel the app was added to

**Evidence:** *"By enabling slash commands, your app can be summoned by users from any conversation in Slack."* With one documented exception: *"Slash commands created by developers cannot, however, be invoked in message threads."* The page does not explicitly confirm or deny whether "any conversation" includes direct messages with the app specifically — re-fetched twice this round to check, and neither fetch found a sentence naming DMs one way or the other.

**Source:** https://docs.slack.dev/interactivity/implementing-slash-commands/

**Significance:** This confirms the engineer's hypothesis: a registered slash command is not channel-scoped by Slack itself — it can be typed in any channel, not just the one the bot "lives in." This directly changes the framing of the format question in Axis 4 below: choosing structured slash commands over free natural language does **not**, by itself, get channel-locking for free. Both formats need the same code-level `channel_id` check (Finding 16) if the requirement is "only usable from this one channel" — the format choice and the channel-lock mechanism are independent decisions, not two sides of the same coin.

**Verification:** URL re-fetched twice this round with explicit verbatim-reproduction requests, both returning identical text / Verbatim quotes checked / Both quoted substrings confirmed present exactly as quoted, each as its own contiguous span.

### Finding 20: Not found — no native Slack admin control was located that restricts a bot app to specific channels; the closest documented controls are workspace/org-wide (all-or-nothing) app approval and human-member channel-invite permissions (not app additions)

**Evidence:** No single quotable sentence — this is a "not found" conclusion after three separate searches. What was found instead, as context: Slack documents channel-level restriction of *human members'* ability to invite other *humans* (channel invitation permissions, an unrelated control surface), and workspace/organization-level app approval that is binary — an app is approved or restricted for the whole workspace/org, not per-channel. Neither matches "prevent this specific bot from being added to a specific channel."

**Source:** Multiple `WebSearch` queries against slack.com/help and docs.slack.dev; no primary page located describing a per-channel app-restriction control.

**Significance:** Per the engineer's question about someone inviting the bot to another channel: nothing found in Slack's own admin surface stops that from happening at the platform level. The only enforcement point identified is code-level — the bot's own event handler checking `channel_id` on every incoming event/command and refusing to act (or refusing to even respond) outside its designated channel. This is consistent with Finding 19: both "which channel can trigger commands" and "which channels the bot will act in" resolve to the same answer — a code-level check, not a Slack configuration switch.

**Verification:** No quote to verify — this Finding documents an absence, reached after three independent `WebSearch` queries covering channel invitations, app approval, and app-channel restriction specifically. Per the Research-First Policy, "I did not find this" is stated directly rather than filled with a guess.

### Finding 21: `claude -p` has documented native flags for capping turns and dollar spend per invocation — but no documented mechanism for a rolling multi-invocation budget across many Slack-triggered runs

**Evidence:** *"Limit the number of agentic turns (print mode only). Exits with an error when the limit is reached. No limit by default."* (`--max-turns`). *"Maximum dollar amount to spend on API calls before stopping (print mode only)"* (`--max-budget-usd`).

**Source:** https://code.claude.com/docs/en/cli-reference

**Significance:** These flags directly address a runaway *single* invocation — a channel message that sends the agent into a long, expensive loop can be capped with `--max-turns` and/or `--max-budget-usd` on every spawned `claude -p` call. This is a real, native, low-effort cost control the daemon can apply unconditionally. What these flags do **not** provide is an *aggregate* limit — e.g. "this channel may trigger at most N paid invocations per day" or "user X has spent $Y this week." **Not found**: any Claude Code-native mechanism for cross-invocation, multi-user budget tracking; that would need to be built into the daemon itself (e.g. a simple per-user/per-channel counter with a reset window), since each `claude -p` call is independent and the flags only bound that single call.

**Verification:** URL fetched with an explicit verbatim-reproduction request / Verbatim quotes checked / Both quoted substrings confirmed present exactly as quoted in the CLI reference's flag table — the `--max-turns` quote is three sentences that are directly adjacent in the source with nothing skipped between them (confirmed against the raw fetched text), not an ellipsis-bridged fusion.

### Finding 22: StackStorm's ChatOps model names a documented industry pattern — a decoupled bot service identity, distinct from whichever human typed the chat command — which is the inverse of what this bot's local-execution requirement implies

**Evidence:** *"Effective user for executions which are triggered via ChatOps (POST to /aliasexecutions/) using hubot is the StackStorm user that is configured in hubot (ST2_AUTH_USERNAME - by default that is chatops_bot)."*

**Source:** https://docs.stackstorm.com/rbac.html

**Significance:** This names a real, documented ChatOps authorization pattern: the executing identity is a fixed, configured service account (`chatops_bot`), never the Slack/chat user who typed the command. That decoupling is exactly what limits blast radius in StackStorm's model — the bot has its own bounded permission set, independent of any individual operator's broader access. It is also the inverse of the constraint that makes this 4Shark bot need to run locally at all: Findings 1, 5, and 6 established that the reason this cannot be a cloud/service-identity bot is that the value is precisely the engineer's own environment — VPN reachability, the engineer's AWS profiles, 1Password, and `~/.claude/skills/`. A StackStorm-style decoupled service identity solves the "the bot's permissions are scoped and separate from the operator" problem but would forfeit the local-environment access that is the entire premise of the request (per the engineer's own token/cost framing in this round's brief, the token being spent is explicitly *his own*, i.e. explicitly not decoupled). This is a real tension to name, not a solved problem: the industry pattern that best addresses "bot shouldn't have the operator's full permissions" is structurally at odds with "the bot must run as/with the operator's own local access." **Closure update**: the engineer resolved this exact tension — see "Outcome" below. This Finding, and Finding 23, now describe the starting premise of whatever design comes next, rather than an open trade-off this spike leaves unweighed.

**Verification:** URL fetched with an explicit verbatim-reproduction request / Verbatim quote checked / Quote substring confirmed present exactly as quoted in the RBAC page's ChatOps section.

### Finding 23: OWASP's Least Privilege Principle is the general security grounding for "the bot's permission set should not equal the operator's"

**Evidence:** *"a user, process, or program should be given only the minimum level of access or permissions necessary to perform its intended function, and nothing more."*

**Source:** https://owasp.org/www-community/controls/Least_Privilege_Principle

**Significance:** This is the general principle behind narrowing `--allowedTools` and choosing a closed command surface (Axis 4) rather than handing the daemon unrestricted tool access. It is a generic security principle, not specific to ChatOps or LLM agents — cited here as the named grounding for "the bot should have less than the operator," a claim this spike would otherwise be making without a citable source. **Closure update**: see Finding 22's closure note — this principle is now the starting premise of future work, not a trade-off this spike leaves open.

**Verification:** URL fetched with an explicit verbatim-reproduction request / Verbatim quote checked / Quote substring confirmed present exactly as quoted in the page's opening definition.

### Finding 24: Audit trails are documented as a detection/accountability mechanism, not a prevention control — no source was found specifically naming "open Slack channel visibility" as a named ChatOps security control

**Evidence:** *"Threat Detection: Audit trails capture user logins, access attempts to sensitive information, modifications to system configurations and other security-related system activities down to the microsecond."*

**Source:** https://onspring.com/resources/blog/what-is-an-audit-trail/

**Significance:** This confirms the general security-industry framing the engineer's own observation implicitly relies on: visibility (an audit trail) is a *detection* mechanism — it lets someone notice, after the fact, that a command ran or that a duplicate request was about to be made — not a *prevention* mechanism that stops an unauthorized or malicious command before it executes. The engineer's specific observation ("channel aberto = transparência... se alguém já pediu, outro não pede de novo") is a real, valid operational benefit (duplicate-request avoidance via social visibility), but it is a courtesy/coordination effect, not a security control in the sense of blocking prompt injection or an unauthorized trigger. **Not found**: any source, in this round's searches, that specifically discusses an open Slack channel's visibility as a named ChatOps security/access control (as distinct from the generic audit-trail concept quoted above, which is about logging, not about channel membership visibility specifically). This is a case where the general security concept (detection vs. prevention) is well-documented, but the specific ChatOps-channel-visibility framing is not named in the literature found — stated directly rather than filled with a guess.

**Verification:** URL re-fetched this round with a dedicated request to confirm whether "Threat Detection" and the sentence that follows it are genuinely contiguous in the source (as opposed to a heading elsewhere in the page fused with body text from a different location) / Verbatim quote checked / Quote substring confirmed present exactly as quoted — "Threat Detection:" is the bolded label that opens this specific bullet and the sentence follows it immediately in the same bullet, so the combined quote is a genuinely contiguous span, not a fusion across unrelated page locations.

### Finding 25: Claude Code's `dontAsk` permission mode — not `bypassPermissions` — is the documented fit for "a pre-defined, closed set of allowed actions, running fully non-interactively"

**Evidence:** From the mode-comparison table, the `dontAsk` row: the "What runs without asking" cell reads *"Only pre-approved tools"*; the "Best for" cell, separately, reads *"Locked-down CI and scripts"* (these are two distinct table cells in the same row, quoted separately here rather than run together as if the column label "Best for" were part of the quoted cell text — and neither quote adds punctuation the cell itself does not contain). From the mode's own section — three sentences, each quoted individually because the source separates them with a status-bar sentence and a v2.1.199 MCP-tools footnote that this Finding does not need and will not silently skip over inside a single quotation: *"`dontAsk` mode auto-denies every tool call that would otherwise prompt."* Separately: *"Only actions matching your `permissions.allow` rules and read-only Bash commands can execute; explicit `ask` rules are denied rather than prompting."* Separately: *"This makes the mode fully non-interactive for CI pipelines or restricted environments where you pre-define exactly what Claude may do."*

**Source:** https://code.claude.com/docs/en/permission-modes

**Significance:** This directly answers the coordinator's question of whether a closed command set + narrow `--allowedTools` still needs `bypassPermissions`. It does not. `bypassPermissions` disables permission *checking* itself (per Finding 15, carrying the "isolated environment... cannot damage your host system" warning and "offers no protection against prompt injection"). `dontAsk` does the opposite of disabling checking: it keeps every permission rule in force and simply auto-denies (instead of prompting for) anything not already on the `permissions.allow` list — the mode's own description frames this as "restricted environments where you pre-define exactly what Claude may do," which is precisely the closed-command-surface shape the engineer is asking about. If Axis 4 is resolved toward a genuinely closed set of allowlisted commands with a correspondingly narrow `--allowedTools`, the daemon can run under `dontAsk` and never needs `bypassPermissions` or `auto` mode at all — removing Finding 15's warning from the architecture entirely for that branch. The trade-off: `dontAsk`'s rigidity cuts both ways — a legitimate action that was not anticipated and pre-allowlisted is silently denied rather than escalated for approval, since nobody is at the terminal to answer a prompt in this unattended context anyway. This works cleanly for a closed command surface (Axis 4 options where the intent is classified/validated before any tool runs) but does not resolve anything for a fully free-natural-language surface, where the exact tool calls needed cannot be fully pre-enumerated. **Closure note**: this Finding is precisely the one the engineer's closing objection targets — see "Outcome" below. `dontAsk` narrows *how* a capability is contained; the engineer's objection is that the capability being contained is the wrong target to begin with. This Finding's facts stand; it dies with Axis 4 as a design lever, not because it was wrong.

**Verification:** URL re-fetched a third time this round with an explicit request to reproduce the full raw `dontAsk` section and the mode-comparison table row character for character / Verbatim quotes checked individually, one at a time / All five quoted substrings (two table cells, three prose sentences) confirmed present exactly as quoted, each as its own genuinely contiguous span — none spans a sentence boundary, none merges a table's column-header label with a different cell's content, and none adds a character (e.g. punctuation) not present in the source. This corrects the prior version of this Finding, which fused three non-adjacent sentences from the same section into what read as one contiguous quotation — silently skipping, with no ellipsis or other mark of the gap, a status-bar sentence and the v2.1.199 MCP-tools footnote that sit between them in the source — combined the "Best for" column header with its cell content as running prose, and added a trailing period inside the quotation marks for that cell that the actual table cell does not contain. That version's verification block asserted "each as its own contiguous span," which was false for that quote. The underlying fact (the mode exists, its table entry, its "pre-define exactly what Claude may do" framing) was accurate throughout — only the citation form was wrong.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Agent SDK-based local daemon | Full programmatic control (hooks, structured output, custom tool permissions); loads `~/.claude/` config by default (Finding 3) | Requires provisioning and monitoring a separate `ANTHROPIC_API_KEY`/billing surface, distinct from the interactive subscription (Finding 3); more integration work than shelling out to `claude -p` | Finding 3 |
| `claude -p` (headless CLI) spawned as a subprocess by a local listener | Matches documented behavior directly (Finding 7); loads skills/CLAUDE.md/hooks automatically without `--bare`; matches the `takafu` community precedent exactly; has native `--max-turns`/`--max-budget-usd` cost caps (Finding 21) | Auth model for a bare `-p` invocation under an already-logged-in interactive session is not confirmed by the fetched docs (Finding 7, marked "Not found"); still needs a permission-mode decision (Finding 15 vs. Finding 25) | Findings 7, 15, 21, 25 |
| Preserve the `/integrators` two-step human gate (preview → wait for "pode rodar" → run) inside the Slack flow | Keeps the documented safety check formally intact; matches existing skill behavior | Moves the authorization surface from "engineer's terminal, engineer's hands" to "whoever posts a convincing reply in the Slack thread" — a channel is a wider trust boundary than a terminal session (Finding 17) | Finding 17 |
| Skip the gate for Slack-triggered runs (go straight to `AUTO_ACCEPT=true`) | Faster, matches the "one Slack message and it's done" expectation implied by the original ask | Explicit, stated divergence from the documented `/integrators` flow; removes the one safety check the skill currently has for this exact operation (Finding 17) | Finding 17 |
| (a) Structured slash commands, closed parameter set | No LLM interpreting intent at the trigger gate — the command name and parameters ARE the intent; pairs naturally with `dontAsk` + narrow `--allowedTools` (Finding 25), avoiding `bypassPermissions` entirely | NOT channel-scoped by Slack itself (Finding 19) — still needs a code-level `channel_id` check; NOT DM-scoped either without the same check; lowest usability/flexibility ceiling; the LLM still interprets the *parameter values* even if the *action* is fixed | Findings 19, 20, 25 |
| (b) `@mention` with free natural language | Matches the original request's example phrasing exactly; highest usability | Squarely the OWASP LLM01 risk category (Finding 14); the LLM interprets the entire message as potential intent, with no closed-set gate; restricting WHO can trigger it does not restrict WHAT their message says (Finding 14/16 connection); does not cleanly fit `dontAsk`'s pre-defined-allowlist model (Finding 25) — the exact tools needed can't be fully pre-enumerated | Findings 14, 16, 25 |
| (c) Hybrid — free natural language, classified/validated against a known intent set before any write-capable tool runs | Keeps conversational usability while adding a gate the LLM itself cannot talk its way past as easily as a single-pass free-form agent (a classification step is a second, narrower judgment, not the same unconstrained interpretation) | The classifier is itself an LLM judgment call, not a hard boundary — a sufficiently crafted message could still mis-classify; adds a component (the classifier) that itself needs testing/maintenance; still an LLM in the interpretation path | Findings 14, 16 |
| (d) Free natural language + narrow `--allowedTools`/permission-mode as the real gate (trust the tool boundary, not the intent classification) | The enforcement point moves from "did we correctly guess intent" to "can this specific tool even run" — arguably more robust than trusting classification; composable with `dontAsk` if the tool set is narrow enough (Finding 25) | Only as safe as the `--allowedTools` list is narrow; a broad or loosely-scoped tool (e.g. an unrestricted `Bash`) reopens the same risk free-form parsing carries; still needs the channel/user boundary from Axis 5 since Slack itself provides none (Finding 19, 20) | Findings 14, 15, 25 |
| Cost control: native `--max-turns`/`--max-budget-usd` per invocation only | Zero-effort, native, applies to every spawned `claude -p` call (Finding 21) | No aggregate/rolling multi-user budget — "not found" as a native mechanism; a custom per-user/per-channel counter would need to be built into the daemon (Finding 21) | Finding 21 |
| Channel lock via code-level `channel_id` check on every event | The only mechanism found that actually restricts where the bot acts — no Slack admin config does this (Finding 19, 20) | Must be implemented and maintained by 4Shark; there is no config fallback if the code has a bug | Findings 19, 20 |
| DM handling: disable the Messages tab entirely (config, no code) | Cleanest "does not receive DMs at all" — App Home setting, no runtime logic (Finding 18) | All-or-nothing: also removes any legitimate future DM use case; does not, by itself, redirect the user anywhere — they just cannot compose the message | Finding 18 |
| DM handling: subscribe to `message.im`, receive the DM, code replies with a redirect ("fale comigo no canal X") | Gives the user active guidance instead of a dead end; matches the engineer's stated preference ("recusar e redirecionar") | Requires code (not config); the exact platform behavior when subscribed-but-Messages-tab-enabled was not fully confirmed in the docs re-fetched this round (Finding 18, "Not found") | Finding 18 |
| Decoupled service-identity bot (StackStorm ChatOps pattern) | Scopes the bot's permissions independently of any operator, a documented industry practice (Finding 22) for "bot shouldn't equal the operator" | Directly conflicts with why this bot must be local at all (Findings 1, 5, 6) — the value IS the engineer's own environment and, per this round's cost framing, explicitly his own token; a decoupled identity would need its own environment access, defeating the premise | Finding 22 |

*(This table is preserved as historical record. Per the closure recorded in "Outcome" below, the rows about command-surface format (a)–(d) and the `/integrators` human-gate died with the discarded local-AI premise; the rows about cost control, channel lock, and DM handling survive as reusable Slack-boundary facts for future work regardless of which AI answers.)*

## What remains uncertain

- Whether a bare `claude -p` invocation, run as a subprocess of a daemon under the engineer's own already-authenticated user account, reuses the interactive Claude Code OAuth/subscription session, or requires a distinct `ANTHROPIC_API_KEY`. Not found in the fetched headless-mode or Agent SDK documentation — both describe `ANTHROPIC_API_KEY` as the SDK/scripted-call auth path without stating whether an existing interactive login is also usable for `-p`. *(Moot with the closure — no local daemon will be built.)*
- What Slack's Socket Mode client library (e.g. `@slack/socket-mode`, `bolt-js`, `bolt-python`) does internally when a `disconnect` event fires and the process itself has exited or is unreachable — the official docs describe disconnect/reconnect handling for the *client's own* lifecycle, not the scenario where the host machine is off and nothing is running to reconnect at all.
- Whether Slack Enterprise Grid / workspace admin policy at 4Shark would need to approve a Socket-Mode app differently from an HTTP-Events-API app — not investigated in this spike; a workspace-admin-side question, not a purely technical one.
- The precise cost/operational overhead of standing up the always-on AWS component (Lambda+API Gateway or small ECS service) the engineer decided on for Axis 1 — not estimated in this spike; would need its own sizing pass.
- Whether a user attempting to DM a bot that has the Messages tab enabled but is not subscribed to `message.im` sees any UI difference from DMing a bot that is fully responsive — not found in the docs re-fetched this round (Finding 18).
- Whether Slack's "any conversation in Slack" scope for slash commands explicitly includes direct messages with the app — the primary doc was re-fetched twice and neither fetch confirmed or denied this specifically (Finding 19).
- Whether any native Slack admin control restricts a bot app to specific channels — searched three times this round with no primary source located (Finding 20); this should be treated as "not found," not "confirmed absent."
- Any native Claude Code mechanism for a rolling, multi-invocation, multi-user budget (as opposed to the per-invocation `--max-turns`/`--max-budget-usd` caps that were found) — not found (Finding 21); would need custom daemon-side tracking if the engineer wants this.
- Whether the specific "open channel visibility as a ChatOps security control" framing is named anywhere in the literature — searched this round, general audit-trail detection-vs-prevention framing was found and cited (Finding 24), but the channel-visibility-specific angle was not found in a named source.

## Decisions and open options

**All axes below are historical record.** Axis 1 was the engineer's decision. Axes 2–4 are now Moot — the project was discarded before they could be resolved. Axes 5–6 survive as reusable Slack-boundary material, independent of which AI eventually sits behind a future bot. See "Outcome" for the closure.

### Decided — Axis 1: Transport/reachability

**The engineer chose Option B: an always-on component**, reasoning: *"não dá pra colocar um timeout no código do bot? Se minha máquina não responder, ele fala 'máquina não acessível'"* ("can't we just put a timeout in the bot's code? if my machine doesn't respond, it says 'machine not accessible'").

**This closes the question, and the reasoning is worth recording because it resolves an ambiguity the first round left open**: a "timeout that answers on the bot's behalf" is not a third option distinct from Option A/Option B — it structurally IS Option B. Code that "tries to connect to the machine, times the attempt, and gives up with a message" necessarily runs somewhere other than the machine it is timing out on — there is no way to run a timeout against yourself and have it fire when you are the thing that is down; the clock and the thing being measured cannot be the same process that disappears together. With pure Socket Mode (Option A), there is nowhere to hang that timeout, because the timer dies in the exact same outage that was supposed to trigger it (this is the same point Finding 8 makes: Socket Mode alone provides no signal at all when the client is down, only silence).

**Mechanics chosen: timeout (try-and-wait), not heartbeat/dead-man's-switch.** The engineer reviewed the heartbeat pattern from Finding 12 and pointed out — correctly — that it carries more moving parts than the requirement needs: a heartbeat requires the local machine to actively ping a watcher on a schedule AND a tolerance window to be calibrated (how long since the last ping counts as "down"?). A try-and-wait timeout is simpler: the always-on component only acts when a Slack event actually arrives — it attempts to reach the local machine (or waits for the local machine to pick up a queued job), times that single attempt, and answers "inactive" if nothing happens within the window — no separate polling schedule, no calibrated tolerance window, no state to maintain between events. Finding 12's citation is unchanged and remains factually accurate; the heartbeat pattern is simply not the mechanism chosen here.

**Two structural details this decision implies, checked against already-established findings:**

(a) **The connection direction inverts because the engineer's machine has no public IP (NAT).** "The component connects to the machine" is the mental model the engineer's phrasing suggests, but Finding 8 already establishes the machine has no public HTTPS endpoint — that is precisely why Socket Mode (a machine-initiated outbound connection) exists as an option at all. In practice, this means the *machine* is the one that must hold the connection open toward the always-on component (a long-poll, a WebSocket, or consuming a queue) — not the reverse. Concretely, the timeout becomes "nobody picked up the job within N seconds" rather than "we tried to dial the machine and it didn't answer." This is an architectural inference from Finding 8's already-cited facts, not a new external citation — no source is quoted for this point because none was fetched to establish it; it follows directly from the machine having no public endpoint.

(b) **The timeout window will very likely exceed Slack's 3-second acknowledgement budget**, which Finding 9 already establishes verbatim (*"Your app should respond to the event request with an HTTP 2xx within three seconds"*). A timeout long enough to distinguish "machine is briefly busy" from "machine is truly offline" cannot fit inside 3 seconds. The practical shape is the same ack-then-respond-later pattern Finding 10 already documents for the long-running "roda o integrador" case: the always-on component acknowledges the Slack event immediately (2xx within the 3-second window), then — once its timeout for the local machine expires — posts "máquina não acessível" to the thread asynchronously via `chat.postMessage`, the same shape Finding 10 describes for a response that cannot complete inside the ack window.

**Survives closure**: this axis describes the Slack-side transport regardless of which AI answers, and is expected to carry over directly to the indicated future direction (see Outcome).

### Moot — Axis 2: Local invocation mechanism (project discarded — see Outcome)

- Option A: `claude -p` (headless CLI) spawned as a subprocess — matches documented behavior and community precedent (Findings 7, 13) directly, but the OAuth-vs-API-key question (see "What remains uncertain") needs resolving first.
- Option B: Agent SDK — more programmatic control, confirmed local execution and config loading (Finding 3), but a separate `ANTHROPIC_API_KEY`/billing surface to provision.

Both options were about invoking a local daemon under the engineer's own environment. With no local daemon being built, this axis has no remaining decision to make.

### Moot — Axis 3: Human-gate preservation for state-changing operations (project discarded — see Outcome)

- Option A: Preserve the two-step preview-then-confirm gate inside the Slack thread — safer, but moves "who can say go" from a terminal to a Slack channel's trust boundary.
- Option B: Collapse to single-step for Slack-triggered runs — faster, but a documented, explicit divergence from the existing skill's safety behavior that the engineer would need to consciously accept.

This axis was specific to a Slack-triggered process running with the engineer's own local `/integrators` skill. Finding 17's tension is preserved as historical record; it does not carry over to a future service-identity AI in the same shape, since that AI would not be invoking `/integrators` with the engineer's own local access to begin with.

### Moot — Axis 4: Command surface format (project discarded — see Outcome)

Four real options were identified, not two — see the Trade-offs table above for the full (a)–(d) comparison with sources. Summary of the axis:

- Option (a): Structured slash commands, closed parameter set.
- Option (b): Free natural language via `@mention`.
- Option (c): Hybrid — free language classified against a known intent set before any write-capable tool runs.
- Option (d): Free language, with `--allowedTools`/permission-mode as the real enforcement boundary rather than intent classification.

The engineer's framing ("closed menu vs. open language, filtered some other way") maps onto (a) vs. (b)/(c)/(d) — but Finding 19 changes what "closed menu" actually buys: it does **not** provide channel-scoping for free (that is a separate, always code-level control — Axis 5). What (a) does provide over (b)/(c)/(d) is removing the LLM from the *action-selection* step entirely, which is what lets it pair cleanly with `dontAsk` mode (Finding 25) and avoid `bypassPermissions` altogether. Options (c) and (d) each keep conversational usability but push the real gate to a different place — a classifier (c) or the tool permission boundary itself (d) — and neither is risk-free per Finding 14/16's core point: restricting who can trigger the bot never restricts what a trusted trigger's message actually says.

**This is the axis the engineer's closing objection is about directly.** All four options here contain a capability that remains total underneath a filter; the engineer's decision (see Outcome) was that the filter is aimed at the wrong object entirely, not that one of these four options is the right filter. This axis dies as a design lever for the local-AI premise; the underlying analysis (that restricting the trigger never restricts the content) survives as a general fact for any future command-surface decision, wherever that decision is made next.

### Survives — Axis 5: Channel/DM boundary enforcement

- The bot living in one specific channel, refusing to act elsewhere, and refusing/redirecting DMs is **entirely code-level** — Findings 19 and 20 establish that Slack provides no admin control for either restriction (slash commands are global by default; no per-channel app restriction was found). The only lever is the bot's own `channel_id` check on every incoming event or command.
- DM handling specifically has one config-only sub-option (Finding 18): disabling the Messages tab blocks DMs outright with no code, at the cost of losing any future legitimate DM use case and giving the user no redirect message. The engineer's stated preference ("recusar e redirecionar") requires code — subscribe to `message.im`, receive the DM, reply with a pointer to the correct channel.

These are facts about Slack's own platform, independent of which AI answers behind the bot — expected to carry over directly to the indicated future direction.

### Survives — Axis 6: Cost/token control

- Native per-invocation caps exist and are essentially free to apply: `--max-turns` and `--max-budget-usd` on every spawned `claude -p` call (Finding 21).
- No native mechanism was found for an aggregate, multi-invocation, multi-user budget (Finding 21) — if the engineer wants "no more than N invocations per day" or "user X is rate-limited after Y triggers," that tracking has to be built into the daemon itself.
- This axis interacted with Axis 4: a closed command surface (option (a)) was also easier to cost-bound, because the set of possible operations — and therefore a rough cost-per-operation estimate — is known in advance; free natural language (options (b)/(c)/(d)) made per-invocation cost harder to predict even with `--max-turns`/`--max-budget-usd` in place. That specific interaction is now moot along with Axis 4, but the underlying facts about what `claude -p` natively caps and does not cap remain true regardless of which AI runs behind a future bot.

## Outcome

**The engineer closed this spike. Decision: do not build the bot.**

### The decision, in his own words

Working back through Axis 4 (command surface format) one more time, the engineer arrived at a structural objection to the whole axis, not a choice among its options:

*"como é que eu travo para eles não fazerem tudo? Não é preocupação depois que acessaram. É garantir que eles nem vão acessar. Essa é a forma segura de garantir isso."* ("how do I lock it down so they can't do everything? It's not a worry about after they've gained access. It's about making sure they never gain access in the first place. That's the safe way to guarantee it.")

He then named why none of Axis 4's four options actually gets there:

*"não importa o que a gente fizer, o meu bot, a minha IA, tem acesso total porque eu sou o dono da empresa e sou o CTO. Não tem ninguém acima de mim em tecnologia. Eu tenho que ter acesso a porra toda."* ("no matter what we do, my bot, my AI, has full access because I'm the owner of the company and the CTO. There's no one above me in technology. I have to have access to everything.")

*"Não faz sentido criar um monte de trava em cima da minha IA para a minha IA não poder fazer coisas se vier de lá."* ("It doesn't make sense to pile a bunch of locks on top of my AI so that my AI can't do things if the request comes from there.")

And closed it: *"esse bot morre"* ("this bot dies").

### The reasoning, spelled out

Axis 4's four options (structured commands, free `@mention`, a hybrid classifier, or `--allowedTools` as the real gate) were never four different answers — they were the same answer wearing different clothes: a filter layered on top of a capability that remains total underneath. The engineer's point is that the lock was aimed at the wrong object. The local AI needs full access because the engineer needs full access — he is the CTO and owner, and there is no technical authority above him to scope that access down to. Constraining the tool to satisfy a requirement that is not the tool's own requirement (it is the Slack channel's requirement) degrades an instrument built for one purpose to serve a different, narrower one.

This closure does not overturn anything this spike found — it resolves the tension the spike had explicitly left open across two revisions. Findings 22 and 23 already established that the documented industry practice for "the bot shouldn't have the operator's full permissions" (StackStorm's decoupled service identity, Finding 22; the general Least Privilege Principle, Finding 23) is structurally incompatible with "the bot runs with the engineer's own environment and token" — the premise every local-execution option in this spike depended on. The spike named that as an unresolved tension. The engineer resolved it by discarding the premise that created the tension, not by discarding the practice: an AI with full local access to the engineer's own machine cannot simultaneously be scoped down to less than that access, so scoping it down means it can no longer be that AI.

### Indicated future direction (not researched, not opened as options)

The engineer indicated where this goes next, explicitly marking it as a later effort, not something to investigate now: a 4Shark-owned AI, possibly running on Bedrock, with its own limited identity and access — made available to the team — rather than exposing the engineer's own local AI to Slack. Per his own framing this is "depois" (later). This spike does not research, evaluate, or open options on that direction — it is recorded here only as the stated next step, for whoever picks this up.

### What survives this closure

Half of this spike is about the Slack-side boundary — how a bot in a channel behaves, what Slack does and doesn't enforce, how acknowledgement and retries work — and that half does not depend on which AI answers on the other side. It is expected to be directly reusable for the indicated future direction (a 4Shark-owned AI exposed to the team via Slack).

**Survives — reusable regardless of which AI is behind the bot:**
- Axis 1 in full (the always-on component, the try-and-wait timeout instead of heartbeat, the NAT-driven connection-direction inversion, the 3-second-ack framing) — Findings 8, 9, 10, 12
- Finding 11 (Slack request signature verification for any HTTP-fronted architecture)
- Findings 18, 19, 20 and Axis 5 (channel and DM boundaries are always Slack-side code, never Slack configuration — this is a fact about Slack, not about the AI behind the bot)
- Finding 21 and Axis 6 (native per-invocation cost/turn caps exist; native aggregate multi-user budget tracking does not — though the specific "it's the engineer's own token" framing that motivated this axis no longer applies to a service-identity AI, the underlying finding about what Claude Code natively caps and doesn't cap remains a fact worth carrying forward)

**Dies with the discarded premise — depended on the local AI having the engineer's full local access:**
- Axis 2 (local invocation mechanism — `claude -p` vs. Agent SDK; there is no local daemon to invoke)
- Axis 3 (the `/integrators` human-gate-via-Slack tension — specific to a Slack-triggered process running with the engineer's own local skills)
- Axis 4 (command surface format as a containment mechanism — the engineer's own objection: containment was never the right lever against a tool that must retain full access for its actual owner)
- Finding 25 (`dontAsk` as an alternative to `bypassPermissions` — a non-question once the AI behind the bot does not carry full local access by construction)
- Finding 17 (the `/integrators` gate tension named for the same reason as Axis 3)

**Becomes the starting premise of the next design, rather than a tension to name:**
- Finding 22 (StackStorm's decoupled ChatOps service identity)
- Finding 23 (OWASP Least Privilege) — both were surfaced in this spike as an industry practice in tension with the local-AI premise; with that premise now discarded, they describe the shape the next design starts from, not a trade-off it has to weigh.

No option in this document is chosen or recommended by this closure beyond what the engineer himself decided. This spike's work is complete; it is preserved as historical record and as a source of reusable Slack-boundary findings for whatever comes next.
