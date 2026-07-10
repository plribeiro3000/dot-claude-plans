# SPIKE — Integrator run: automated request detection + auto-primed numbers preview, plus zero-numbers advisory

## Investigation question

This spike investigates, without implementing anything, two things that build on the in-progress `manual-integrator-run-skill` feature (see `~/.claude/plans/active/spike/manual-integrator-run-skill/SPIKE.md` and `~/.claude/plans/active/manual-integrator-run-skill/PLAN.md`):

1. **Part 1 — automation layer.** Is it feasible to build a listener (email inbox — read-only — and optionally a Slack channel) that detects an "please run the integrator for client X" request, automatically spawns a new Claude Code session on the engineer's machine, and drives that session through the existing/planned `/integrators` run action's READ-ONLY numbers-preview steps (raise client, trigger preview, present NUMBERS), then STOPS at the human-approval gate? What are the available building blocks in this environment, what are the real mechanisms and constraints (grounded in official Claude Code documentation and local skill files, not assumed), what architecture options exist, and what decisions remain for the engineer? The hard safety boundary — the spawned/listener process must NEVER auto-run the accept step — is treated as inviolable throughout.
2. **Part 2 — small scoped addition.** Where in the already-planned `/integrators` run action's control flow (the manual-integrator-run-skill's step 6/7, "trigger preview" → "present NUMBERS, stop for approval") does an advisory "all counts are zero, confirm with the client before proceeding" check slot in, and how is "all zero" detected from the NUMBERS output?

## Sources consulted

- `~/.claude/plans/active/spike/manual-integrator-run-skill/SPIKE.md` — background on the manual-integrator-run-skill feature this spike builds on: rake surface (RD4), NUMBERS composition (Finding 4), Fallback A execution model.
- `~/.claude/plans/active/manual-integrator-run-skill/PLAN.md` — the locked control-flow steps 1–9 for the new `/integrators` action, in particular steps 6 and 7.
- `~/.claude/skills/spawn-session/SKILL.md` and `~/.claude/skills/spawn-session/scripts/spawn-session.sh` — the local session-spawning primitive.
- `~/.claude/skills/integrators/SKILL.md` — the existing skill Part 1 would extend and Part 2 would slightly modify.
- `~/.claude.json` — searched for locally-configured MCP servers (none found beyond `granola`; the Gmail/Slack/session-management/scheduled-tasks MCP servers named in the task briefing are account-level connectors, not present in this repo's local config — see Finding 9 for the resulting citation limitation).
- https://code.claude.com/docs/en/remote-control — Remote Control mechanics, connection model, local-process requirement, mobile push notifications.
- https://code.claude.com/docs/en/scheduled-tasks.md — `/loop` and `CronCreate`/`CronList`/`CronDelete`, session-scoped semantics, 7-day expiry.
- https://code.claude.com/docs/en/desktop-scheduled-tasks.md — Desktop scheduled tasks, machine-must-be-awake constraint, connector availability.
- https://code.claude.com/docs/en/routines.md — Cloud Routines, connectors, and where the routine actually executes.
- https://code.claude.com/docs/en/channels.md — Channels (push-based event delivery into a running session), officially supported connectors.
- https://code.claude.com/docs/en/desktop.md — Dispatch (phone-message-triggered Desktop session spawn).
- https://github.com/anthropics/claude-code/issues/43397 — reported/reproduced gap where MCP connector tools are unavailable on an autonomous/scheduled session fire until a user message arrives.
- See auxiliary: `integrator-run-auto-trigger_scheduling-doc_1.md` — verbatim excerpts of the six official-doc fetches above and the GitHub issue summary, kept so a revision of this spike does not need to re-fetch.

## Findings

### Finding 1: `spawn-session.sh` boots a plain session and activates Remote Control — it does NOT currently inject an initial task/prompt

**Evidence:**
```bash
# ~/.claude/skills/spawn-session/scripts/spawn-session.sh:74-84
tmux new-session -d -s "$session" -c "$WORK_DIR" "caffeinate -s claude"

if ! wait_until_ready "$session"; then
  echo "FAILED: $session — Claude did not reach its prompt in time." >&2
  exit 1
fi

tmux send-keys -t "$session" '/remote-control'
sleep 1
tmux send-keys -t "$session" Enter
sleep 2
```

**Significance:** the script boots a detached `claude` process in tmux at `$WORK_DIR` (defaults to `~/Projects/4Shark`), waits for the prompt, then types exactly one thing into it: `/remote-control`. There is no second `tmux send-keys` call carrying a task prompt. As written today, a spawned session is empty/idle once Remote Control activates — it does not "pre-run the numbers preview" on its own. Extending it to also type a task prompt (e.g. `tmux send-keys -t "$session" "run the /integrators preview for client X, stop before accept" ` followed by `Enter`) is mechanically the same technique the script already uses for `/remote-control` — technically straightforward — but this is a proposed extension, not something already implemented; SKILL.md's own text confirms the current scope is "Spawn, verify, report — that is the whole job" (`~/.claude/skills/spawn-session/SKILL.md:29`).

### Finding 2: Remote Control requires a live local process; the mobile app is a window into that process, not a place work spawns from

**Evidence:** "Remote Control connects claude.ai/code or the Claude app for iOS and Android to a Claude Code session running on your machine... Claude keeps running locally the entire time, so nothing moves to the cloud." and "Local process must keep running: Remote Control runs as a local process. If you close the terminal, quit VS Code, or otherwise stop the `claude` process, the session ends." (https://code.claude.com/docs/en/remote-control, quoted in full in the auxiliary file § 5)

**Significance:** for the engineer's vision ("when he arrives via the mobile app, the session is already primed") to work, the spawned session's underlying `claude` process must already be running and connected before the engineer opens the app — which is exactly what `spawn-session.sh` already achieves for a manually-triggered spawn. Automating the trigger (Part 1) does not change this requirement: whatever detects the request must itself be able to invoke the same local spawn mechanism, on the same machine, or the resulting session will not exist for Remote Control to expose.

### Finding 3: the three native scheduling surfaces differ sharply in whether they run on the local machine and whether MCP connectors are available — this is the central constraint for Part 1

**Evidence:** the comparison table published identically on both the `/loop` and Desktop-scheduled-tasks doc pages (https://code.claude.com/docs/en/scheduled-tasks.md, https://code.claude.com/docs/en/desktop-scheduled-tasks.md; full table in auxiliary § 1):

> "MCP servers | Connectors configured per task [Cloud] | Config files and connectors [Desktop] | Inherits from session [`/loop`]"
> "Runs on | Anthropic cloud [Cloud] | Your machine [Desktop] | Your machine [`/loop`]"
> "Requires open session | No [Cloud] | No [Desktop] | Yes [`/loop`]"

**Significance:** this is the load-bearing fact for every architecture option below.
- **Cloud Routines** run on Anthropic-managed infrastructure, not the engineer's machine (confirmed again in Finding 5) — so a cloud routine cannot itself invoke `spawn-session.sh` (a local tmux/bash script). It could only detect the request; spawning the local session would need a separate bridge.
- **Desktop scheduled tasks** run on the engineer's machine without needing an already-open interactive session, but only while the Desktop app is running and the computer is awake (Finding 4) — a real, not theoretical, constraint for a listener meant to run "continuously".
- **`/loop`** runs on the machine too, but is session-scoped: it requires an already-open interactive Claude Code session and stops when that session ends, with tasks auto-expiring after 7 days (auxiliary § 2) — meaning a `/loop`-based listener needs a dedicated, long-lived terminal/session the engineer keeps open (or re-arms weekly), similar in spirit to how `spawn-session.sh` itself uses `caffeinate` to keep the machine from sleeping.

### Finding 4: Desktop scheduled tasks are gated on "app running and computer awake" — not a true always-on daemon without extra care

**Evidence:** "Tasks only run while the desktop app is running and your computer is awake. If your computer sleeps through a scheduled time, the run is skipped. To prevent idle-sleep, enable **Keep computer awake** in Settings under **Desktop app → General**." (https://code.claude.com/docs/en/desktop-scheduled-tasks.md, auxiliary § 3)

**Significance:** a Desktop-scheduled-task listener needs both the Desktop app open and the "Keep computer awake" setting enabled (or an equivalent like the `caffeinate` wrapper `spawn-session.sh` already uses) to poll reliably. It also supports a "missed runs" catch-up (fires once for the most recent missed slot after the machine wakes) — acceptable for a polling listener, since a slightly-delayed detection of "please run the integrator" is not correctness-critical, only UX-critical.

### Finding 5: Cloud Routines execute in an Anthropic-managed sandbox, cloned from GitHub — they cannot reach the engineer's local machine, tmux, or `spawn-session.sh`

**Evidence:** "A routine is a saved Claude Code configuration: a prompt, one or more repositories, and a set of connectors, packaged once and run automatically. Routines execute on Anthropic-managed cloud infrastructure, so they keep working when your laptop is closed." and "Each repository you add is cloned at the start of a run, starting from the default branch." (https://code.claude.com/docs/en/routines.md, auxiliary § 4)

**Significance:** a cloud Routine is the only scheduling surface here that can run reliably with the machine off, and it is the only one whose connectors are described as "configured per task" (implying Gmail/Slack could be attached to it as claude.ai account connectors, same as any other MCP connector on that account) — but it fundamentally cannot execute `spawn-session.sh`, since there is no local filesystem, no tmux, and no access to the 4Shark AWS profile/credentials configured on the engineer's laptop. A cloud-routine-based listener could therefore only ever DETECT the request (read Gmail/Slack) — it could not itself spawn the local Remote-Control-ready session the engineer's vision depends on, unless the routine's job is redefined as "do the whole preview run itself, in the cloud" (a materially different architecture — see Option B' below) rather than "spawn a local session".

### Finding 6: documented, reproduced gap — MCP connector tools can be unavailable to a session on its first autonomous/scheduled fire, becoming available only after a user message arrives

**Evidence:** GitHub issue #43397 (fetched summary, treated as UNVERIFIED-exact-wording per the auxiliary file's own caveat — the tool that fetched it returned a synthesized summary, not the raw issue body): reports that on a cloud-scheduled-task's autonomous fire, `ToolSearch` for each connector (Zoho Cliq, Zoho CRM, Microsoft 365/Outlook in the reported case) returns "No matching deferred tools found", and that sending any message into the same session immediately makes the connectors available with no configuration change. The issue is linked to two related tickets (#35899, #36327) describing the same symptom on Desktop scheduled tasks with different connectors (Datadog/Jira, Slack), and Anthropic's tracker marks the standalone issue duplicate/not-planned rather than shipping a fix.

**Significance:** this directly grounds the constraint the engineer asked to have called out explicitly. Even on a scheduling surface whose comparison-table entry says MCP connectors are available ("Connectors configured per task" for Cloud, "Config files and connectors" for Desktop), the documented behavior is that an interactively-authenticated connector (the shape the Gmail/Slack MCP servers described in this environment are) can silently fail to load on the autonomous fire itself, and only starts working after a live user turn — which defeats the purpose of an unattended listener. This is reported for both Cloud and Desktop scheduled tasks; there is no equivalent report found (nor would one be expected, given `/loop`'s "inherits from session" model) for `/loop` running inside an already-open, already-authenticated interactive session, since that session's MCP connectors were already loaded by the ordinary interactive-session bootstrap before the loop's first fire.

### Finding 7: Channels are push-based and reactive but do not officially support Gmail or Slack as a connector type in the current research preview

**Evidence:** "A channel is an MCP server that pushes events into your running Claude Code session, so Claude can react to things that happen while you're not at the terminal." and "You install a channel as a plugin and configure it with your own credentials. Telegram, Discord, and iMessage are included in the research preview." (https://code.claude.com/docs/en/channels.md, auxiliary § 6)

**Significance:** Channels are architecturally the closest fit to "listen continuously and push the event into a running session" — closer than polling — but the officially shipped, ready-to-use plugin set is Telegram/Discord/iMessage, not Gmail/Slack. The doc says a custom channel can be built ("To build your own channel, see the Channels reference") but that reference page was not fetched in this spike (flagged under "What remains uncertain" below) — building a custom Gmail/Slack channel plugin is real, unscoped engineering effort (a Bun-based MCP server the engineer would author and maintain), not a configuration step.

### Finding 8: Dispatch is an adjacent, but different, mechanism — phone-message-triggered, not automatic-detection-triggered

**Evidence:** "Dispatch is a persistent conversation with Claude that lives in the Cowork tab. You message Dispatch a task, and it decides how to handle it." and "A task can end up as a Code session in two ways: you ask for one directly... or Dispatch decides the task is development work and spawns one on its own." and "Dispatch requires a Pro or Max plan and is not available on Team or Enterprise plans." (https://code.claude.com/docs/en/desktop.md § "Sessions from Dispatch", auxiliary § 7)

**Significance:** Dispatch already does "message from phone → spawn a Desktop session on the engineer's machine" — but the trigger is the engineer explicitly messaging Dispatch, not an automatic detection of an inbound client email/Slack message. It does not solve Part 1's "listen and detect automatically" requirement on its own. It is also gated to Pro/Max plans, not Team/Enterprise — whether 4Shark's plan tier supports it is unconfirmed (not found locally; flagged under "What remains uncertain").

### Finding 9: the Gmail/Slack/session-management/scheduled-tasks MCP tool surface named in the task briefing could not be independently verified by this research agent

**Evidence:** searching `~/.claude.json` for `mcpServers` across every registered project and the global scope found only one server, `granola` (a meeting-notes tool), at the global scope:
```
/mcpServers -> ['granola']
```
No `mcp__80b82206-...` (Gmail), `mcp__49a4f51b-...` (Slack), `mcp__ccd_session_mgmt__*`, or a `scheduled-tasks` MCP server appears in this file, nor in `~/.claude/settings.json` (only a generic `"matcher": "mcp__.*"` hook pattern, not a server registration).

**Significance:** this research agent's own tool list (per its subagent contract) does not include those Gmail/Slack/session-management MCP tools, so their exact tool names, parameters, and behavior as described in the task briefing are taken on the engineer's/environment's word, not independently confirmed by invoking them. This is a citation-discipline gap this spike surfaces rather than papers over: any claim in this document about what those specific tools return or accept is second-hand from the task briefing, not a verified Finding. The mechanism-level claims above (what `/loop`, Desktop tasks, Routines, Channels, and Remote Control do) are independently sourced from official Anthropic documentation and are not affected by this gap.

### Finding 10 (Part 2): the NUMBERS block is exactly 14 named collection counts — "all zero" means every one of the 14 is 0

**Evidence:**
```ruby
# integrator/app/services/throughput_calculator.rb:10-26 (quoted in the manual-integrator-run-skill SPIKE.md:142-158)
COLLECTIONS =
  {
    clients: :updated_at,
    deals: :updated_at,
    deal_extra_fields: :updated_at,
    goals: :updated_at,
    groups: :updated_at,
    groupifications: :created_at,
    hierarchy: :created_at,
    modifiers: :updated_at,
    products: :updated_at,
    subsidiaries: :updated_at,
    users: :updated_at,
    user_activity: :created_at,
    user_fields: :created_at,
    user_identifiers: :updated_at
  }.freeze
```
`~/.claude/plans/active/spike/manual-integrator-run-skill/SPIKE.md:137` — "Finding 4: `ThroughputCalculator::COLLECTIONS` is the exact NUMBERS content — 14 named collections, each counted since the job's `fetch_since` watermark" — and `:160` — "the rake task's own preview... iterates the same constant directly (`integration.rake` lines 66-70 and 143-147) ... re-implements the per-collection count inline against `Job.ne(ends_at: nil).order_by(starts_at: :asc).last.ends_at` as the watermark".

**Significance:** the already-planned control flow slots this in precisely at the boundary between manual-integrator-run-skill's steps 6 and 7:

```
# ~/.claude/plans/active/manual-integrator-run-skill/PLAN.md:187-188
6. **Trigger preview (numbers pass)** — raw `aws ecs run-task` with a container command
   override to `bundle exec rake integration:start` (Phase 2, Fallback A); poll `aws ecs
   describe-tasks` until `STOPPED`; read NUMBERS from CloudWatch Logs. *New command, new
   mechanism.*
7. **Present NUMBERS, STOP for engineer approval** — no execution continues until the
   engineer replies. *New, but structurally matches the skill's existing "confirm before
   bulk scale-down" pause pattern (`SKILL.md:108-111`).*
```

Step 6 already reads the NUMBERS block (14 labeled counts) from CloudWatch Logs before step 7 presents it. Detecting "all zero" is a pure parse of that already-captured text — check whether every one of the 14 named collection counts in the block equals 0 — with no new AWS call, no new CloudWatch read, and no change to steps 6 or 8/9. The addition is presentational, inside step 7's existing "present NUMBERS" moment: when all 14 are zero, the presentation adds one advisory line (e.g., "all counts are zero — nothing appears to have changed since the last integration; recommended to confirm with the client before proceeding") alongside the NUMBERS. Per the PLAN's own step 7 framing ("STOP for engineer approval"), the engineer already has to explicitly approve before step 8 runs — the zero-numbers line does not need a second, separate gate; it rides the same stop. It is explicitly advisory: the engineer may still approve and proceed (PLAN.md:188 already makes step 7 a hard stop regardless of the NUMBERS' content — the zero-numbers line does not add a new block, only new information at an existing block).

## Architecture options for Part 1 — listener → spawn → pre-run pipeline

None of these is recommended over another; each trades differently against the constraints in Findings 3–8.

| Option | Where the listener runs | How it spawns the local session | MCP connector risk (Finding 6) | Always-on without engineer attention? | Engineering effort |
|---|---|---|---|---|---|
| **A — Local `/loop` inside a dedicated, kept-open interactive session** | Locally, inside one interactive `claude` process the engineer starts once (mirrors `spawn-session.sh`'s own `caffeinate`-wrapped tmux pattern) | The loop session itself runs `bash ~/.claude/skills/spawn-session/scripts/spawn-session.sh`, then (per Finding 1's proposed extension) injects the pre-run task prompt via the same `tmux send-keys` technique | Lowest — Gmail/Slack MCP connectors are already loaded via ordinary interactive-session bootstrap before the loop's first fire; "inherits from session" per Finding 3 | No — needs a dedicated terminal/session the engineer keeps running (or a `launchd`/similar wrapper that restarts it), and the loop itself expires after 7 days (Finding 3), so needs periodic re-arming | Low — extends existing local scripts, no new infra |
| **B — Desktop scheduled task (local) polling Gmail/Slack** | Locally, via the Desktop app's scheduled-task runner | Same as A — the scheduled task's prompt would `bash` the spawn script + prompt injection | Documented risk from Finding 6 (Desktop scheduled tasks are explicitly named in the linked issues as affected) — connector tools may not be loaded on the autonomous fire | Closer — no open interactive session required, but still needs the Desktop app open and the machine awake (Finding 4); the app's "Keep computer awake" setting substitutes for `caffeinate` | Low-medium — configured via the Desktop app UI, same underlying local scripts |
| **B' — Cloud Routine does the entire preview run itself, no local spawn** | Anthropic cloud sandbox (Finding 5) | N/A — does not spawn a local session at all; the routine's own cloud session runs the numbers-preview steps directly, then the engineer picks up that SAME cloud session (not a local one) via claude.ai/code or the mobile app | Documented risk from Finding 6 (Cloud scheduled/autonomous fires are the primary case in the linked issue) | Yes — cloud infra runs with the laptop off (Finding 5) | High — needs AWS credentials as routine-environment variables in the cloud sandbox, materially diverging from the local-AWS-profile model the rest of `/integrators` and 4Shark's AWS Policy assume; does not use `spawn-session.sh` or Remote Control at all |
| **D — Custom Channel plugin for Gmail/Slack (push-based)** | Locally, as a long-running Bun-based channel server (Finding 7) | The channel event arrives inside an already-open local session, which then runs the spawn+prompt steps (same mechanism as A) | Lowest, same reasoning as A — events land inside an already-open, already-authenticated session | Requires the local channel server process to stay running (same category of constraint as A) | High — no ready-made Gmail/Slack channel plugin exists today (Finding 7); building one is unscoped extra engineering |

Options A and D both route the detection into an already-open local session, which is what keeps the Gmail/Slack MCP connectors reliably available (Finding 6); the difference is polling (A) vs push (D, closer to the engineer's "listens continuously" framing but not yet built for Gmail/Slack). Options B and B' move the listener off the engineer's attention but reintroduce the connector-availability risk documented in Finding 6, and B' additionally changes where the actual AWS-touching work happens.

## The hard safety boundary (restated, per the engineer's explicit instruction)

Every option above must preserve, unmodified: the auto-spawned/auto-triggered session performs ONLY the read-only numbers-preview portion of the already-planned control flow — manual-integrator-run-skill PLAN.md steps 1 through 6 (resolve client, raise Mongo if any, read Terraform counts, scale up, wait for readiness, trigger the preview and read NUMBERS) — and then STOPS at step 7 exactly as already planned ("no execution continues until the engineer replies", PLAN.md:188). No option researched here proposes, implies, or requires giving the automated/scheduled trigger the ability to run step 8 (the `AUTO_ACCEPT=1 SKIP_THROUGHPUT=1` accept). The engineer's explicit approval remains the only path to step 8 in every option. This is unchanged by which scheduling/spawn mechanism is chosen.

## What remains uncertain

- The exact tool names/parameters of the Gmail MCP (`mcp__80b82206-...`), Slack MCP (`mcp__49a4f51b-...`), session-management MCP (`mcp__ccd_session_mgmt__*`), and any `scheduled-tasks` MCP as described in the task briefing were not independently verified by this research agent (Finding 9) — confirming their actual behavior needs a session that has those tools loaded.
- Whether 4Shark's Claude Code plan tier is Team/Enterprise or Pro/Max was not found locally — this determines whether Dispatch (Finding 8, Pro/Max only) and Remote Control's Team/Enterprise admin-toggle gating (auxiliary § 5, "off by default until an Owner enables the Remote Control toggle") apply, and it is already in active use per `spawn-session`'s existence, so it is presumably already enabled — but the plan tier itself is not confirmed.
- The Channels Reference page (for building a custom Gmail/Slack channel, Option D) was not fetched in this spike — the actual engineering shape (webhook-vs-polling, credential storage, Bun runtime requirements) is unresearched beyond what the Channels overview page states.
- Whether the classification step (deciding "this email/Slack message is an integrator-run request" and extracting the client name) should be LLM-based (inside the loop's own prompt, using whichever model the loop session runs) or a cheaper rule/keyword pre-filter before invoking a full Claude Code turn — not researched here; either is technically compatible with any of the four options above.
- De-duplication/idempotency mechanism (a Gmail label marking "already processed", a session-management MCP query for "is there already a primed session for this client", or something else) — the tools that would implement this (Gmail MCP's `label_message`, the session-management MCP) are exactly the ones flagged as unverified in Finding 9.
- Audit trail and kill-switch design for an autonomous process that reads email and spawns sessions touching production infrastructure — not researched; this is a design decision, not a fact-finding question, and belongs with the engineer's review of the options above.
- Whether `spawn-session.sh`'s proposed prompt-injection extension (Finding 1) should live in `spawn-session.sh` itself (a new optional argument) or in a new script specific to this feature — not decided here; either is mechanically the same `tmux send-keys` technique.

## Suggested options for main and the engineer

- **Option A** — dedicated local `/loop` session, extending `spawn-session.sh` to accept an injected task prompt. Lowest connector risk (Finding 6), lowest engineering effort, but needs the engineer (or a `launchd`-style wrapper) to keep one terminal alive and re-arm the loop every 7 days.
- **Option B** — Desktop scheduled task running the same spawn+prompt logic. Removes the "keep a terminal open" requirement but inherits the documented MCP-connector-on-autonomous-fire risk (Finding 6) and still needs the Desktop app open + machine awake.
- **Option B'** — cloud Routine that does the entire numbers-preview run itself, no local spawn, engineer approves from the SAME cloud session via web/mobile. True always-on (works with the laptop off) but is architecturally the most divergent from the rest of `/integrators`' local-AWS-profile model, and still inherits the Finding 6 risk.
- **Option D** — custom Channel plugin for Gmail/Slack, push-based instead of polling. Closest to the "listens continuously" framing and shares Option A's low connector risk, but requires building a channel plugin that does not exist today (Finding 7).
- **Part 2** — the zero-numbers advisory line is a small, self-contained addition to manual-integrator-run-skill's step 7 presentation (Finding 10); it does not depend on any Part 1 decision and can be scoped into the existing PLAN.md independently, whenever the engineer wants it folded in.
