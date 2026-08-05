# SPIKE — Automating the PR review pipeline (pr-review → pr-triage → report)

## Question

Every open PR should automatically get the 4Shark `pr-review` agent (which carries the team's
policies and reads sibling files, unlike Copilot which only sees the diff), running in the
background; then `pr-triage` to close false positives; then a single report to the engineer with
the surviving findings. A new push restarts the cycle.

What mechanism can deliver that, and what part of it is mechanically enforceable?

## Findings

### Finding 1 — No hook can spawn a subagent

Claude Code's hook system exposes 31 events. Hook handler types are `command`, `http`,
`mcp_tool`, `prompt`, and `agent`; the `agent` type is for agent-based hooks, not for spawning a
subagent into the main conversation. Subagents are spawned through the model's own tool call.

Consequence: the trigger cannot be a mechanical guarantee. It is a **context injection** — the
same tier as `inject-remote-execution-context.sh` and `inject-availability-context.sh`. The hook
detects the moment and injects the pipeline; the model spawns the agents.

- URL fetched: https://code.claude.com/docs/en/hooks
- Verbatim quote checked: *"PostToolUse: next to the tool result. The conversation continues so Claude can act on the feedback."*
- Quote substring confirmed in the decision-control section of the hooks reference.

### Finding 2 — Subagents already run in the background by default on this version

The engineer's installed version is `2.1.221` (`claude --version`).

- URL fetched: https://code.claude.com/docs/en/sub-agents
- Verbatim quote checked: *"As of v2.1.198, subagents run in the background by default. Claude runs a subagent in the foreground when it needs the result before continuing."*
- Quote substring confirmed at § "Run subagents in foreground or background".

Consequence: the "runs in background" requirement needs no new machinery. It is already the
default and can be pinned with the `background` frontmatter field.

- Verbatim quote checked: *"Set to `true` to always run this subagent as a [background task](#run-subagents-in-foreground-or-background), even when Claude needs its result right away."*
- Quote substring confirmed at the frontmatter field table, `background` row.

### Finding 3 — `pr-review`'s tool set survives the background filter

A background subagent runs with a reduced built-in tool set.

- URL fetched: https://code.claude.com/docs/en/sub-agents
- Verbatim quote checked: *"a background subagent keeps every MCP tool but only these built-in tools: `Read`, `Grep`, `Glob`, `Bash`, `PowerShell`, `Edit`, `Write`, `NotebookEdit`, `WebFetch`, `WebSearch`, `TodoWrite`, `Skill`, `ToolSearch`, `EnterWorktree`, `ExitWorktree`, `Monitor`, `TaskStop`, `SendMessage`, and `Artifact`."*
- Quote substring confirmed at § "Available tools".

`agents/pr-review.md:6` declares `tools: Read, Grep, Glob, Bash` — all four are in the allowed
list, so `pr-review` loses nothing when backgrounded. This is not true of every agent, so it is a
fact worth recording: an agent whose tool list falls outside that set silently degrades in the
background.

### Finding 4 — A background result arrives as a later-turn notification, which is what makes chaining work

- URL fetched: https://code.claude.com/docs/en/sub-agents
- Verbatim quote checked: *"A background subagent's results reach Claude as a completion notification in a later turn. Claude waits for that notification before reporting the subagent's results, and if you ask about progress first, it reports that the subagent is still running."*
- Quote substring confirmed at § "Run subagents in foreground or background".

Consequence: the chain `pr-review` → main posts to GitHub → `pr-triage` → main resolves threads →
report is a legitimate sequence. Main is re-invoked when the background agent finishes and can
carry on without the engineer typing anything.

### Finding 5 — `PostToolUse` carries the tool result, and there is local precedent for reading it

`scripts/inject-full-read-reminder.sh:48` already reads `(.tool_response // .tool_result // "")`
from the `PostToolUse` payload. So detecting *"a `gh pr create` just succeeded and returned a PR
URL"* is an established shape in this repository, not a new capability.

### Finding 6 — `TaskCompleted` / `TaskCreated` cannot carry the chain

Both events support only blocking (`exit 2` / `{"continue": false}`), not `additionalContext`.
They are therefore useless for injecting "now run pr-triage".

- URL fetched: https://code.claude.com/docs/en/hooks
- Verbatim quote checked: *"TeammateIdle, TaskCreated, TaskCompleted | Exit code or `continue: false`"*
- Quote substring confirmed in the decision-control table.

`SubagentStop` *does* accept `additionalContext`, but the docs do not state where that context
lands for a background subagent. Since Finding 4 already gives main the completion notification,
`SubagentStop` is not needed and is deliberately not used — an undocumented delivery path is not
worth depending on.

## Design decisions

### The trigger is the diff's file types, not a repo allowlist

The engineer's framing was per-repo ("Ruby yes, Terraform no"). A repo allowlist gets this wrong
in both directions: a Ruby change inside the `terraform` repo would be skipped, and a
docs-only PR in `app` would be reviewed for nothing.

The rule is therefore: **classify by the extensions the PR actually changes.** Code the review
can reason about (`.rb`, `.ts`, `.tsx`, `.js`, `.dart`, `.cs`, `.py`, `.prw`, `.sh`) → run the
review. A PR whose diff is only `.tf`/`.tfvars`/`.md`/`.yaml`/`.json`/lockfiles → skip. This is
repo-agnostic and matches the engineer's intent (Terraform PRs are declarative and simple) without
hardcoding a list that goes stale.

### The wait for the other reviewers runs in the background, not in the session's flow

`skills/pr-triage/SKILL.md:10` states its own purpose: *"The 4Shark workflow runs multiple AI/human
reviewers over the same PR. Threads accumulate. The most common low-value thread is a false
positive."* Its value comes from closing **other** reviewers' bad comments — above all Copilot's,
which sees only the diff. Copilot reports asynchronously, so the triage needs those threads to
exist before it can do its job.

The wait therefore belongs to a background command, not to main's flow. Right after posting the
findings, main starts `scripts/await-pr-reviewers.sh` through `Bash` with `run_in_background: true`,
tells the engineer the triage is armed, and ends the turn. When the script exits, that completion
notification re-invokes main, which runs `/pr-triage` and delivers the report. Nothing polls in the
foreground and the engineer waits on nothing.

**The mechanism is a background `Bash` command, not a `Monitor` — the `Monitor` documentation is
explicit about which shape fits.** For *"tell me when the server is ready / the build finishes"* it
prescribes *"**Bash with `run_in_background`** and a command that exits when the condition is true"*,
and it warns: *"**Don't use an unbounded command for a single notification.** `tail -f`,
`inotifywait -m`, and `while true` never exit on their own, so the monitor stays armed until timeout
even after the event has fired."* Waiting for a reviewer is exactly one notification.

- URL fetched: https://code.claude.com/docs/en/hooks (Monitor tool description, same doc set)
- Verbatim quote checked: *"Don't use an unbounded command for a single notification."*
- Quote substring confirmed in the Monitor tool description delivered by ToolSearch.

The watched reviewer's login is `copilot-pull-request-reviewer`, confirmed against a real PR
(`gh -R 4shark/app pr view 5284 --json reviews` returns
`[{"author":"copilot-pull-request-reviewer","state":"COMMENTED"}]`) rather than taken from the
example block in `SKILL.md`.

Both endings of the wait are normal. `reported:` means the thread set is complete; `timeout:` means
nobody reported inside the bound, so the triage runs on what exists and the report says so. A
repository with no automated reviewer configured takes the timeout path every time — `dot-claude`
PR #488 returned `{"latestReviews":[],"reviews":[]}`, which is why the timeout is an outcome rather
than an error.

### The re-push trigger is keyed on the head SHA

A new push restarts the cycle, but a rebase or a fixup can push several times in a minute. The
hook writes a marker keyed on the pushed head SHA, so the same commit never re-triggers while a
genuinely new one always does.

## What is enforceable and what is not

| Piece | Mechanism | Tier |
|---|---|---|
| Detecting a PR was opened | `PostToolUse(Bash)` reading `tool_response` for the PR URL | Mechanical |
| Detecting a new push to an open PR | `PostToolUse(Bash)` + `gh pr view`, SHA-keyed marker | Mechanical |
| Running `pr-review` in the background | Default since v2.1.198, pinned with `background: true` | Mechanical |
| Waiting for the other reviewers | `await-pr-reviewers.sh` polling GitHub | Mechanical |
| Actually spawning the agents | Injected instruction; the model obeys | Advisory |
| Deciding the diff is worth reviewing | Injected classification rule; the model judges | Advisory |

The advisory rows are advisory because no hook can spawn an agent (Finding 1). This is the honest
ceiling of the mechanism, and it is the same ceiling every other injector in this repository has.

## Why there is no GitHub Actions path

A cloud action (`claude-code-action` on `pull_request`) would reach PRs opened by hand with no
session running, and it is deliberately not adopted. The action checks out the repository and
therefore loads the repo's own `CLAUDE.md` — not `~/.claude/CLAUDE.md`, which is the policy corpus
that makes `pr-review` worth more than a diff-only reviewer. Closing that gap would mean syncing
the whole policy set into every repository.

The gap does not need closing. A PR opened outside a session enters the pipeline the moment the
engineer mentions it ("abri o PR, link tal") — the third trigger, which costs nothing and carries
the full policy corpus because it runs in a real session. No `claude-code-action` workflow exists
in `app/.github/workflows/`, and none is planned.
