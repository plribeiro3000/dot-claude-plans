# GitHub issues investigated — anthropics/claude-code

All states below were fetched directly via `gh api repos/anthropics/claude-code/issues/<n>`
on 2026-07-29 (not inferred from web-search summaries, which in one case — #57346 —
returned a title/description that did NOT match the actual GitHub issue; see note at the
bottom). Each row: number, title, state, state_reason, created_at, closed_at.

## Directly relevant to Q1 (syntax contract) — currently OPEN, filed within days of this spike

| # | Title | State | Created | URL |
|---|---|---|---|---|
| 81170 | [BUG] Contradictory guidance on Write() vs Edit() permission rule matching in settings.json | OPEN | 2026-07-25 | https://github.com/anthropics/claude-code/issues/81170 |
| 75315 | [BUG] Path-scoped Write(...) allow rules never match (silently ignored) — only Edit(...) rules gate the Write tool | OPEN | 2026-07-07 | https://github.com/anthropics/claude-code/issues/75315 |
| 80893 | deny and ask rules in settings.json have no effect on Write/Edit/Read tools | OPEN | 2026-07-24 | https://github.com/anthropics/claude-code/issues/80893 |

**#81170 body (verbatim, key excerpt):**
> On session startup, Claude Code prints this warning: "Permission deny rule
> (.claude/settings.json): Write(functions/.env) is not matched by file permission checks
> — only Edit(path) rules are. Use Edit(functions/.env) instead (Edit rules cover all
> file-editing tools)." This says Write(path) rules are never evaluated, and to use
> Edit(path) only. Running /doctor recommends the opposite — that I add
> Write(functions/.env) back alongside Edit(functions/.env). I've now had this flagged
> both ways across separate sessions, with no way to verify which claim about the
> permission engine is actually true.

**#75315 body (verbatim, key excerpt):**
> Path-scoped `Write(...)` allow rules are accepted without any warning but never match,
> so every `Write` tool call they were meant to allow is denied. [...] Last Working
> Version: n/a — reproduced identically on 2.1.186, 2.1.187, 2.1.198, 2.1.202; the form
> appears to have never matched.

**#80893 body (verbatim, key excerpt):**
> deny and ask permission rules in ~/.claude/settings.json have no effect on the Write,
> Edit, and Read tools. File write operations are neither blocked nor prompted regardless
> of what deny/ask rules are configured. Only Bash(...) rules are respected by the
> permission system. [...] Tested `deny: ["Edit(/home/john/*)"]` as a workaround based on
> #75315 — no effect. File writes still complete silently.

## Directly relevant to Q4 (cleanup tooling) — currently OPEN feature requests, no official tool exists yet

| # | Title | State | Created | URL |
|---|---|---|---|---|
| 78817 | [Feature Request] Auto-migrate deprecated Write() permission rules to Edit() in settings.json | OPEN | 2026-07-18 | https://github.com/anthropics/claude-code/issues/78817 |
| 74705 | Feature: interactive context hygiene audit command | OPEN | 2026-07-06 | https://github.com/anthropics/claude-code/issues/74705 |
| 81956 | Feature request: /permissions should support a global scope | OPEN | 2026-07-28 | https://github.com/anthropics/claude-code/issues/81956 |

**#78817 body (verbatim):**
> Deprecated Write(<path>) permission rules written into settings.json by older Claude
> Code versions are not auto-migrated on update. They silently stop matching (only
> Edit(path) rules cover file-writing tools now), so the user gets a per-session "Fix:"
> notice but has to edit settings.json by hand. Please auto-migrate Write(path) ->
> Edit(path) (with dedup) during settings migration, instead of only showing a warning.

**#74705 body (verbatim, key excerpt):**
> A built-in /hygiene (or /audit) slash command that interactively audits context window
> usage and proposes removals — covering memory, MCP servers, plugins/skills, permissions,
> and settings — in one pass. [...] Permission allowlist entries referencing removed
> servers [...] Today, each of these requires manual investigation across different
> commands [...] There's no single command that audits everything and recommends cleanup.
> [...] I've built this as a personal skill (.claude/skills/session-hygiene/SKILL.md)
> which works well, but it would benefit all users as a built-in since context bloat is
> universal for long-term users.

**#81956 body (verbatim, key excerpt):**
> `/permissions` currently only reads all scopes but writes exclusively to the current
> repo's `.claude/settings.local.json` — there's no way to target the global
> `~/.claude/settings.json` through the UI. [...] Right now the only way to add or edit a
> global permission rule is to hand-edit `~/.claude/settings.json` directly —
> `/permissions` can't help at all in that case, since it structurally only ever writes to
> the project-local file.

## Directly relevant to Q6 (session-only scope)

| # | Title | State | Created | URL |
|---|---|---|---|---|
| 48479 | [FEATURE] Add "Allow for Session" permission option to Claude Code Desktop | OPEN (per WebSearch summary; not re-verified via gh api — see caveat) | 2026-04-15 | https://github.com/anthropics/claude-code/issues/48479 |
| 22292 | Feature: Persistent permission preferences across sessions | not re-verified via gh api | — | https://github.com/anthropics/claude-code/issues/22292 |

CAVEAT: #48479 and #22292 state/body were obtained through WebSearch's summarization, not
a direct `gh api` fetch (the two `gh api` calls issued for them returned no output in this
session — not re-attempted due to time-boxing). Treat their state as UNVERIFIED pending a
direct API check; do not treat the "OPEN" label above as confirmed the way the other
issues in this table are. The one confirmed, sourced-in-full fact from #48479 is captured
in SPIKE.md Finding 6 with this same caveat attached.

## Investigated and found NOT directly relevant (accumulation / bloat reports, but about
## `.claude.json` session-history bloat, not about the permissions allow-list specifically)

| # | Title | State | State reason | Created | Closed |
|---|---|---|---|---|---|
| 34923 | [BUG] defaultMode: bypassPermissions in settings.json has no effect — permission prompts still appear | CLOSED | not_planned | 2026-03-16 | 2026-06-01 |
| 57346 | VS Code and Claude Code Refuse to send any Requests on Large Projects | CLOSED | duplicate | 2026-05-08 | 2026-05-12 |
| 6850 | [BUG] settings.local.json allow not working - keeps asking and wanting to add existing items again | OPEN | — | 2025-08-30 | — |
| 41259 | Permissions in settings.local.json not respected after Edit tool modifies the file | CLOSED | not_planned | 2026-03-31 | 2026-06-01 |
| 14532 | Claude Code Settings Bloat Bug - Twitter/Issue Report | CLOSED | duplicate | 2025-12-18 | 2025-12-22 |
| 6394 | Critical: .claude.json bloat severely impacting user experience | CLOSED | not_planned | 2025-08-23 | 2026-01-11 |
| 7243 | [Bug] The .claude.json elephant in the room | CLOSED | not_planned | 2025-09-06 | 2026-02-05 |
| 24207 | [BUG] No disk space management: ~/.claude grows unbounded | CLOSED | not_planned | 2026-02-08 | 2026-06-04 |
| 19109 | Claude Code permission settings | CLOSED | duplicate | 2026-01-19 | 2026-01-22 |

**#34923 body (verbatim, key excerpt — the one useful data point in this group for Q5/Q6):**
> Setting "defaultMode": "bypassPermissions" in both ~/.claude/settings.json and the
> project-level .claude/settings.local.json does not suppress permission prompts. [...]
> Prompts appear on every tool call. Each approval writes the specific command to
> settings.local.json under permissions.allow, growing the allowlist indefinitely.

**IMPORTANT LESSON on citation discipline, from this batch:** a WebSearch summary claimed
issue #57346 was "The Claude Code native binary silently exits when a workspace's
.claude/settings.local.json accumulates too many entries in permissions.allow +
permissions.additionalDirectories combined." The actual `gh api` fetch showed the real
title is "VS Code and Claude Code Refuse to send any Requests on Large Projects," closed
as a duplicate. The search-tool paraphrase did not match the source. This is why every
issue cited as a Finding in SPIKE.md was re-verified via a direct `gh api` call in this
session, not taken from a WebSearch summary.

## Not found

A targeted search (`gh api search/issues` for "printed twice", "duplicate" + "startup
warning" + "permission") did not turn up any filed issue describing the exact behavior
the engineer reported — the same block of allow/deny warnings appearing twice in one
`claude --resume` startup. A general "output printed twice" bug PATTERN does recur in
Claude Code's history (issues #29069 Bash timeout message printed twice, #20760 and
#20488 `/context` output printed twice, #1858 task-planning tool output duplicated) — all
four CLOSED, none about permission warnings specifically. This establishes the bug CLASS
exists and has precedent, but does not confirm the specific permission-warning-duplication
case. Marked "Not found" in SPIKE.md Finding 3 rather than inferred.
