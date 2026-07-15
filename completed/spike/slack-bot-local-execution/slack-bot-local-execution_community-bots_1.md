# Auxiliary — Community Slack + Claude Code bot precedent

Referenced from `SPIKE.md` Finding 13. Raw comparison of three open-source community projects that connect Slack to a locally-running Claude Code, gathered via `WebFetch` on each project's README/CLAUDE.md on 2026-07-15. None of these are Anthropic-official; all are third-party.

## mpociot/claude-code-slack-bot

- URL: https://github.com/mpociot/claude-code-slack-bot
- Runs locally via `npm run dev` / `npm run prod`.
- Transport: Socket Mode ("Socket Mode is enabled" — README).
- Invokes Claude via the **Claude Code SDK** (not a CLI subprocess), with alternative backends for AWS Bedrock and Google Vertex AI.
- Access control: no user allowlist documented in the README. Authentication relies only on Slack bot/app tokens.
- Tool access: per `CLAUDE.md` in the repo — **"All MCP tools are allowed by default with `mcp__serverName__toolName` pattern"** — no per-user restriction on which tools a Slack message can invoke.
- Long-running tasks: handled via streaming/real-time message updates in the Slack thread rather than an explicit ack-then-respond pattern.
- Offline handling: not documented.

## AnandChowdhary/claude-code-slack-bot

- URL: https://github.com/AnandChowdhary/claude-code-slack-bot
- **Not local** — runs on Cloudflare Workers, built "on top of Claude Code Action" (the GitHub Action integration). It creates GitHub issues that a separate Claude Code Action process picks up.
- Transport: HTTP Events API (`https://your-worker.workers.dev/slack/events`), not Socket Mode.
- Long-running tasks: Cloudflare Queues poll for progress every 10 seconds, auto-stop after 30 minutes.
- Access control: GitHub PAT with `repo` scope + Slack OAuth scopes; no Slack-side user allowlist documented.
- Relevance to the 4Shark question: this architecture does NOT reach a specific engineer's local machine — it is cloud-to-cloud, so it does not solve the "must run where the VPN/AWS profiles/1Password/skills are" requirement at all. Included for completeness, not as a viable candidate.

## takafu/slack-claude-bot

- URL: https://github.com/takafu/slack-claude-bot
- Runs **locally**. Transport: Socket Mode — README states **"Socket Mode: No public server required - connects via WebSocket"**.
- Invocation: spawns the **Claude Code CLI as a subprocess** — README: *"the bot spawns Claude Code CLI with the message"* — and passes Slack context (including `SLACK_BOT_TOKEN`) as environment variables.
- Security-relevant: the README states Claude **"uses Bash tool to call Slack API directly"** — i.e. the spawned Claude process holds the bot token and can call the Slack API itself, not just reply through a controlled channel.
- Access control: no user allowlist documented — any workspace member who can message the bot can trigger it.
- Mitigation offered: a workspace-specific security-hook file, `.claude/settings.slack.json`, that lets a team define custom permission policies limiting Claude's actions specifically in the Slack-triggered context (separate from the operator's own interactive `.claude/settings.json`).
- Session model: thread-based — each Slack thread maintains its own Claude session/context, with mention-triggered start and automatic continuation for follow-ups in the same thread.

## Summary table

| Project | Where it runs | Transport | Invocation | User allowlist | Long-running handling |
|---|---|---|---|---|---|
| mpociot/claude-code-slack-bot | Local | Socket Mode | Claude Code SDK | None documented | Streaming thread updates |
| AnandChowdhary/claude-code-slack-bot | Cloud (Cloudflare Workers + GitHub Action) | HTTP Events API | Claude Code Action → GitHub issue | GitHub/Slack OAuth scopes only | Cloudflare Queues polling, 30 min cap |
| takafu/slack-claude-bot | Local | Socket Mode | Claude Code CLI subprocess | None documented (mitigated via `.claude/settings.slack.json` hook file) | Thread-based session continuation |

None of the three local-capable projects (mpociot, takafu) documents an offline/"server down" response mechanism — the gap the 4Shark question specifically raises is not solved by existing community precedent.
