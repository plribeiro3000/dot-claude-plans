# SPIKE — Agent Governance Architecture: Community Taxonomy Beyond Hooks/Docs/Wrappers, and a Wrapper Deep-Dive

**Conducted by:** spike agent (Task-spawned)
**Date:** 2026-07-01
**Status:** Research complete — pending decisions

---

## Investigation question

4Shark governs its Claude Code harness with three mechanisms: (1) deterministic
**hooks** (PreToolUse/PostToolUse/UserPromptSubmit/SessionStart/SubagentStart
scripts under `~/.claude/scripts/`), (2) **documentation** (`CLAUDE.md` +
`~/.claude/docs/*.md`, tiered and injected by `read-context.sh`), and (3)
**wrappers with alias** (tool-shaping scripts placed in front of a raw tool,
canonically `~/.claude/scripts/ruby.sh`).

1. Is there a recognized **community taxonomy** of mechanisms for governing a
   coding agent's behavior, and does it contain a category **beyond**
   4Shark's three?
2. Is 4Shark's "hooks + docs + wrappers" combination aligned with what the
   community/vendor recommends as the sound center of gravity, or is a
   different primary strategy recommended?
3. **Wrapper deep-dive**: what tools does the community most commonly wrap
   around coding agents, and why? Is a **git** wrapper a recognized pattern,
   and how does wrapper-for-git relate to 4Shark already handling git safety
   via a hook (`validate-bash-command.sh`)? What other high-value wrappers
   might 4Shark be missing?
4. Is there a **community-recognized principle for when to reach for a
   wrapper vs. a hook**?

This spike builds on, and does not re-derive, three prior spikes: the
industry survey of permission/sandbox/classifier approaches
(`ai-agent-permission-control/SPIKE.md`), the hook-vs-prose-rule enforcement
distinction (`agent-command-approval-visibility/SPIKE.md`), and the
PreToolUse/doc-injection mechanics
(`pretooluse-command-triggers/SPIKE.md`, `agent-pipe-chaining/SPIKE.md`,
`llm-agent-command-chaining/SPIKE.md`). Its contribution is the taxonomy
question (is there a 4th+ category) and the wrapper deep-dive, neither of
which those spikes addressed as a primary question.

---

## Sources consulted

**Internal (4Shark repo, read directly, cited by file:line):**

- `~/.claude/settings.json` (704 lines, read in full) — the complete hook
  wiring and `permissions.allow`/`ask`/`deny` arrays
- `~/.claude/scripts/ruby.sh` (110 lines, read in full) — the canonical
  wrapper
- `~/.claude/docs/RUBY-COMMAND-EXECUTION.md` (92 lines, read in full)
- `~/.claude/scripts/read-context.sh` (232 lines, read in full) — the Tier
  1/2 doc-injection mechanism
- `~/.claude/docs/adr/ADR-001-rules-loading-mechanism.md` (124 lines, read
  in full)
- `~/.claude/scripts/validate-bash-command.sh` (first 80 of 588 lines read)
  — the canonical hook
- `~/.claude/scripts/start-instance.sh`, `~/.claude/scripts/ecs-scale.sh`
  (read in full/partial) — secondary wrapper examples
- `~/.claude/scripts/` directory listing (49 entries) — hook/wrapper script
  census
- Direct `grep` of `settings.json` for `mcp`/`sandbox` keys (zero matches)
  and of `~/.claude/scripts/*.sh` for `eval`/`regression` (zero matches)
- `python3 -c "import json; ..."` against `settings.json` to count
  `permissions.allow`/`ask`/`deny` entries exactly (210 / 36 / 64)

**Prior spikes (read in full, referenced not duplicated):**

- `~/.claude/plans/active/spike/ai-agent-permission-control/SPIKE.md` (288
  lines)
- `~/.claude/plans/active/spike/agent-command-approval-visibility/SPIKE.md`
  (206 lines)

**External (fetched, quotes verified, auxiliary files hold full detail):**

- `https://github.com/ai-boost/awesome-harness-engineering` +
  raw README — see `governance_taxonomy_harness_1.txt`
- `https://code.claude.com/docs/en/agent-sdk/secure-deployment` (full doc)
  — see `governance_anthropic_secure_deploy_2.txt`
- `https://code.claude.com/docs/en/permissions` (full doc) — see
  `governance_anthropic_permissions_3.txt`
- `https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents`
  — see `governance_anthropic_evals_4.txt`
- `https://github.com/ai-ecoverse/ai-aligned-git` + raw README — see
  `governance_wrapper_git_ai_aligned_5.txt`
- `https://github.com/Dicklesworthstone/destructive_command_guard` — see
  `governance_wrapper_dcg_6.txt`
- `https://codenote.net/en/posts/aws-cli-ai-agent-secure-access-defense-in-depth/`
  — see `governance_wrapper_aws_cli_7.txt`
- `https://www.aikido.dev/blog/introducing-safe-chain` — see
  `governance_wrapper_npm_aikido_8.txt`
- `https://dev.to/supertrained/tool-level-permission-scoping-in-mcp-why-server-authentication-isnt-enough-58ni`
  — see `governance_mcp_scoping_9.txt`

**Searched but not usable as a citation (per Citation Discipline — quote
could not be independently confirmed against the specific URL, so dropped
rather than attributed):** `https://tolearn.blog/blog/2026-04-02-hooks-plugins-sessions-ai-agents`
(a WebSearch synthesis attributed a "reserve hooks for the critical few"
quote to this article; a direct re-fetch of the article itself could not
locate that passage — treated as UNVERIFIED and not used).
`https://ranjankumar.in/hooks-policy-as-code-agent-enforcement` and
`https://danicat.dev/posts/20260610-mastering-hooks/` were fetched
specifically to find a wrapper-vs-hook comparison; both were confirmed, on
direct fetch, to **not** contain one — this negative result is itself a
finding (see Finding 10).

---

## Findings

### Group A — 4Shark's current mechanisms, grounded

#### Finding 1: 4Shark's hook surface is large and hook-dominant; wrappers are a small minority of the script inventory

**Evidence:** `~/.claude/scripts/` holds 49 entries. Counting by prefix:
`auto-approve-*` (4), `check-*` (8), `inject-*` (16), `validate-*` (5) — 33
hook-shaped scripts wired into `settings.json`'s `hooks` block (`PreToolUse`,
`PostToolUse`, `UserPromptSubmit`, `SessionStart`, `SubagentStart`,
`Notification` — `settings.json:9-353`). By contrast, the scripts matching
the brief's "wrapper" definition (`ruby.sh`, `start-instance.sh`,
`stop-instance.sh`, `ecs-scale.sh`) number 4. `settings.json`'s
`permissions.allow` array (`settings.json:357-578`, 210 entries — counted
via `python3 -c "import json; print(len(json.load(open('settings.json'))['permissions']['allow']))"`)
separately lists specific auto-approved command shapes, including dedicated
entries for each wrapper script (e.g.
`"Bash(bash $HOME/.claude/scripts/ruby.sh:*)"` at `settings.json:461-462`).

**Source:** `~/.claude/scripts/` directory listing; `~/.claude/settings.json:9-353,357-578`.

**Significance:** by raw script count, 4Shark's governance investment is
roughly 8:1 in favor of hooks over wrappers. This is a factual baseline for
Finding 2's taxonomy comparison, not itself a judgment about whether that
ratio is right.

---

#### Finding 2: 4Shark's own "hooks" bucket actually contains two architecturally distinct Claude Code mechanisms — hook scripts and permission allow/ask/deny rules — that the vendor's own docs treat as separately evaluated layers

**Evidence:** `settings.json:355-620` defines `permissions.allow` (210
entries), `permissions.ask` (36 entries), and `permissions.deny` (64
entries, a fixed credential/secrets denylist) — counts confirmed by parsing
the file as JSON rather than counting lines. These are glob-pattern rules
evaluated by Claude Code's own permission engine — they are not hook
scripts and are not listed in the `hooks` block. Anthropic's permissions
doc states directly: *"Hook decisions don't bypass permission rules. Deny
and ask rules are evaluated regardless of what a PreToolUse hook returns...
A blocking hook also takes precedence over allow rules. A hook that exits
with code 2 stops the tool call before permission rules are evaluated."*
The independent `awesome-harness-engineering` list describes the same
architecture from the outside: *"Five-layer evaluation order (hooks → deny
rules → permission mode → allow rules → canUseTool)."*

**Source:** `~/.claude/settings.json:355-620`; `governance_anthropic_permissions_3.txt`
(full doc, "Hooks vs permission rules" section); `governance_taxonomy_harness_1.txt`
("Permissions & Authorization" section).

**Significance:** the engineer's framing of "three mechanisms" (hooks, docs,
wrappers) folds the permission allow/ask/deny system into "hooks" — but
Claude Code's own architecture treats it as a separate, earlier-or-later
evaluated layer with different semantics (a static glob match vs. an
arbitrary script's exit code). 4Shark already uses this layer heavily (210
allow entries, 36 ask entries), so this is not a missing mechanism — it is
a mechanism 4Shark uses extensively but does not name as its own category
internally. Whether that internal-naming gap matters in practice (vs.
purely descriptive) is presented as an open question, not resolved here.

---

#### Finding 3: 4Shark's config uses zero MCP servers, zero sandbox settings, zero native `Agent(...)` subagent permission rules, and no output-styles directory

**Evidence:** direct `grep -ri "mcp\|sandbox" ~/.claude/settings.json`
returned no matches; the only MCP-named file on disk is
`~/.claude/mcp-needs-auth-cache.json` (a cache artifact, not a server
configuration). No `sandbox` key exists anywhere in `settings.json`. The
`permissions.allow`/`ask`/`deny` arrays contain zero `Agent(...)`-shaped
entries (Anthropic's own primitive for scoping which subagents may run, or
scoping a subagent call's `model`/`isolation` parameters — confirmed to
exist as a native mechanism in `governance_anthropic_permissions_3.txt`). No
`~/.claude/output-styles/` directory exists.

**Source:** direct `grep` run against `~/.claude/settings.json`;
`find ~/.claude -maxdepth 1 -iname "*output-style*"` (zero results);
`governance_anthropic_permissions_3.txt` ("Agent (subagents)" and "Output
styles" sections, and the "CROSS-CHECK" paragraph at the end of that file).

**Significance:** 4Shark's subagent governance (the Subagent Contract) is
implemented entirely as a documentation/prose convention injected via
`read-context.sh` at `SubagentStart`, plus after-the-fact verification by
main (per `CLAUDE.md` § Subagent Contract, "Verification after every Task
invocation"). It is not backed by the native `Agent(...)` permission-rule
primitive that would deny/scope a subagent call mechanically, the same way
a `Bash(...)` deny rule mechanically blocks a shell command. This is a
factual gap, not a recommendation to close it — see Options, below.

---

#### Finding 4: 4Shark has no eval/regression-testing mechanism for its own hook/wrapper/doc scripts

**Evidence:** `grep -rl "eval\|regression" ~/.claude/scripts/*.sh` (and a
directory scan for BATS/shellcheck/shunit artifacts) returned no matches.
`~/.claude/` contains no test suite that exercises `validate-bash-command.sh`,
`ruby.sh`, or any other governance script against a corpus of known-good/
known-bad inputs.

**Source:** direct `grep`/`find` against `~/.claude/scripts/` and
`~/.claude/`.

**Significance:** this is the factual predicate for Finding 9 below (is
this a real community-recommended gap, or not).

---

### Group B — the community taxonomy question

#### Finding 5: an independent community taxonomy of "AI agent harness engineering" lists twelve categories, several of which have no 4Shark equivalent

**Evidence:** `awesome-harness-engineering` (a curated, actively maintained
list, fetched both via its rendered page and its raw README as a
self-check) organizes governance/steering mechanisms into: Agent Loop,
Planning & Task Decomposition, Context Delivery & Compaction, Tool Design,
Skills & MCP, Permissions & Authorization, Memory & State, Task Runners &
Orchestration, Verification & CI Integration, Observability & Tracing,
Debugging & Developer Experience, Human-in-the-Loop, plus a distinct
"Security, Sandbox & Permissions" grouping. Quoted verbatim for the
categories most relevant to this spike: *"Permissions & Authorization —
Structured authorization patterns for agents: how to give agents the right
permissions without relying on prompt-level trust"*; *"Skills & MCP —
Anthropic's open protocol for connecting agents to external tools, data
sources, and services in a standardized way"*; *"Verification & CI
Integration — primary governance through automated testing, policy
enforcement gates, and observability checkpoints that prevent agent
regressions before deployment"*; *"Observability & Tracing —
instrumentation and logging that expose agent decision-making, tool
invocations, and error modes in production."*

**Source:** `governance_taxonomy_harness_1.txt` (both fetches, full quotes).

**Significance:** mapped against 4Shark's three named mechanisms (hooks,
docs, wrappers), four of these twelve categories have **no direct 4Shark
equivalent today**: Skills & MCP (Finding 3 — zero MCP servers configured),
Verification & CI Integration (Finding 4 — no eval/regression harness for
the governance scripts themselves), Observability & Tracing (no audit-log/
trajectory-replay mechanism found for hook decisions — 4Shark's hooks
`exit 2`/print to stderr but nothing persists a structured decision log),
and Memory & State in the cross-session-learning sense (4Shark explicitly
disables Claude Code's native adaptive memory — `settings.json:4`,
`"autoMemoryEnabled": false` — and replaces it with a manual, engineer-
triggered save-to-file workflow per `CLAUDE.md` § Memory Save Workflow,
which is a deliberate substitution, not an oversight, but is architecturally
a different mechanism than the "harness learns and adapts" category this
taxonomy describes). Two other categories (Human-in-the-Loop, Tool Design)
are substantially covered by 4Shark's existing hooks+docs+wrappers
combination and are not treated as gaps.

---

#### Finding 6: Anthropic's own vendor guidance names sandboxing/OS-level isolation as a first-class, distinct security layer that 4Shark does not use

**Evidence:** Anthropic's secure-deployment guide states the "same
principles that apply to running any semi-trusted code apply here:
isolation, least privilege, and defense in depth," and separately lists,
as one of four "built-in security features," *"Sandbox mode: Bash commands
can run in a sandboxed environment that restricts filesystem and network
access."* It further states: *"Permissions and sandboxing are complementary
security layers: Permissions control which tools Claude Code can use...
Sandboxing provides OS-level enforcement that restricts the Bash tool's
filesystem and network access... even if a prompt injection bypasses
Claude's decision-making."* An isolation-technology comparison table lists
sandbox-runtime, Docker containers, gVisor, and Firecracker/QEMU VMs with
their isolation strength, performance overhead, and complexity trade-offs.

**Source:** `governance_anthropic_secure_deploy_2.txt` (full doc, "Built-in
security features" and "How permissions interact with sandboxing"
sections); confirmed absent from 4Shark's config in Finding 3.

**Significance:** this finding does not re-derive the prior spike
(`ai-agent-permission-control/SPIKE.md` Approach B, "Sandbox / Isolated
Environment") — that spike already covered sandboxing as one of three
industry approaches and concluded it "requires infrastructure investment
that doesn't match 4Shark's current pain point" as of its April 2026
writing. This finding adds one new fact: as of this spike's fetch (2026-07-01),
Anthropic ships sandboxing as a **built-in, zero-infrastructure-required**
mode (`sandbox-runtime`, described as needing no Docker configuration,
container images, or networking setup — "You provide a settings file
specifying allowed domains and paths") — a materially lower-cost on-ramp
than the container/VM options the prior spike weighed. Whether this changes
the prior spike's cost-benefit conclusion is a decision for main/the
engineer, not resolved here.

---

#### Finding 7: MCP tool-level scoping is treated by the community as architecturally distinct from both server authentication and generic command allow/deny rules — and is a native Claude Code primitive 4Shark does not use

**Evidence:** *"MCP server authentication and tool-level authorization are
different layers. Conflating them creates lateral movement risk."*
*"Agent authenticates → access granted → all tools available"* (server-auth
model) versus *"Agent authenticates → role/scope attached → tools filtered
by role"* (tool-scoping model). *"Per-tool permission scoping is not a
feature you add after deployment. It's an architecture decision that shapes
how the server is built."* Anthropic's own permissions doc independently
confirms a native primitive for this: `mcp__<server>__<tool>` permission
rules, including whole-server or whole-tool-surface denial (`"deny":
["mcp__*"]`), and confirms that a bare-tool-name deny rule **removes the
tool from Claude's context entirely** — a visibility-level control, not
merely an execution-level block.

**Source:** `governance_mcp_scoping_9.txt`; `governance_anthropic_permissions_3.txt`
("MCP" and "Tool name wildcards" sections).

**Significance:** this is a genuine capability gap relative to the platform
(4Shark uses zero MCP servers, confirmed Finding 3) — not necessarily a
gap relative to need, since 4Shark's current toolset (Bash + Read/Write/Edit
+ WebSearch/WebFetch) does not route through MCP servers at all. Whether
MCP tool-scoping is relevant depends on whether 4Shark ever adopts MCP
servers (e.g., a database or ticketing integration) — presented as an open
question, not a current deficiency.

---

#### Finding 8: subagent-scoped permissions are a native Claude Code primitive; 4Shark's Subagent Contract achieves a similar goal entirely through prose + after-the-fact verification

**Evidence:** Anthropic's permissions doc: *"Use Agent(AgentName) rules to
control which subagents Claude can use... Add these rules to the deny array
in your settings or use the --disallowedTools CLI flag to disable specific
agents"* — plus parameter-level rules such as `Agent(model:opus)` and
`Agent(isolation:worktree)`, which scope a subagent call's resource
envelope directly. 4Shark's actual subagent-governance mechanism is
`SUBAGENT-CONTRACT.md` (injected in full at `SubagentStart` via
`read-context.sh` — confirmed at `read-context.sh:41-44,74-80`) plus a
main-session obligation, stated in `CLAUDE.md` § Subagent Contract, to
manually check `git status`/`~/.claude/plans/active/`/`/tmp/` after every
`Task` return and roll back + respawn if the subagent wrote outside its
designated file.

**Source:** `governance_anthropic_permissions_3.txt` ("Agent (subagents)"
section); `~/.claude/scripts/read-context.sh:41-44,74-80` (Tier 2 full-expansion
logic on `SubagentStart`); `CLAUDE.md` § Subagent Contract (in-session
context, "Verification after every Task invocation").

**Significance:** 4Shark's subagent boundary is currently entirely
advisory/detective (a prose rule the subagent is expected to follow, plus a
manual post-hoc check by main) rather than preventive/mechanical (a
permission rule that would make an out-of-scope tool call impossible for
the subagent to even attempt). This is the same "advisory vs. mechanical"
distinction the sibling spike `agent-command-approval-visibility/SPIKE.md`
Finding 7 already established for `CLAUDE.md` rules generally — applied
here specifically to the subagent-scoping case, and grounded in a concrete
native alternative (`Agent(...)` rules) that spike did not examine.

---

#### Finding 9: evals/CI regression-testing of the harness itself is a genuinely disputed category — one credible source treats it as governance, the vendor's own engineering blog treats it as QA

**Evidence:** the `awesome-harness-engineering` list's "Verification & CI
Integration" category explicitly frames automated evals as governance:
*"primary governance through automated testing, policy enforcement gates,
and observability checkpoints that prevent agent regressions before
deployment"* — including *"Deployment gates blocking releases on eval
failures."* Anthropic's own `demystifying-evals-for-ai-agents` engineering
post, by contrast, frames evals as measuring whether *"the agent still
handle[s] all the tasks it used to"* — a task-performance QA practice, with
no passage in the fetched document framing evals as controlling or gating
what the agent is *permitted* to do at runtime.

**Source:** `governance_taxonomy_harness_1.txt` ("Verification & CI
Integration" section); `governance_anthropic_evals_4.txt` (full quotes and
analysis).

**Significance:** this is presented as a genuine disagreement in the
sources, not resolved by this spike. What is not disputed: 4Shark has zero
of either flavor (Finding 4) — no regression suite exercising its own
hook/wrapper scripts against known-good/known-bad command corpora, and no
task-performance eval suite for the agent's output quality. Whether this
gap matters more as a "governance" concern (would a bad hook edit silently
regress a safety guarantee) or a "QA" concern (would a CLAUDE.md rewrite
silently degrade output quality) determines which framing — and therefore
which team practice — would close it.

---

#### Finding 10: no source found in this spike states a general, explicit "wrapper vs. hook" decision principle — but two independently-built git-safety tools converged on different mechanisms for different sub-concerns within the same domain, which is itself informative

**Evidence:** two dedicated searches for an explicit wrapper-vs-hook
decision framework were run; both leads that appeared promising on
WebSearch synthesis failed to confirm on direct fetch:
`ranjankumar.in/hooks-policy-as-code-agent-enforcement` was fetched and
found to not discuss wrapper scripts as an alternative to hooks at all;
`danicat.dev/posts/20260610-mastering-hooks/` was fetched and found to
"focus exclusively on hooks... [without] compar[ing] these to wrapper-based
alternatives." **Not found**: an explicit, named community principle for
choosing a wrapper over a hook (or vice versa).

What WAS found, however, is a natural experiment: `destructive_command_guard`
(`dcg`) and `ai-aligned-git` both target "git safety for AI agents," and
chose different mechanisms for different sub-concerns. `dcg`'s README
states plainly: *"Your AI agent invokes dcg as a PreToolUse hook before
executing each shell command. The hook receives the command as JSON on
stdin"* — pure hook, no PATH shimming, used for the concern "block
destructive operations already expressed as a formed command" (force-push,
`reset --hard`, etc. — the same concern class 4Shark's own
`validate-bash-command.sh` handles for git, per `CLAUDE.md` § Git Safety).
`ai-aligned-git`, by contrast, installs via *"install the wrapper, configure
your PATH"* — pure PATH shim — used for the concern "force a specific
invocation shape and inject metadata the bare command would not otherwise
carry" (individual `git add <file>` instead of bulk `git add .`, mandatory
`--vibe-level`/`--prompt` flags).

**Source:** `governance_wrapper_dcg_6.txt`; `governance_wrapper_git_ai_aligned_5.txt`
(both, full quotes and the direct side-by-side comparison already drafted
in each aux file's "Significance" section).

**Significance:** this spike's own synthesis (not a quoted community
principle — explicitly flagged as inference, per Citation Discipline) is
that the pattern across all four wrapper examples found (`ruby.sh`,
`ai-aligned-git`, the AWS CLI allowlist wrapper, Aikido Safe Chain for
npm/npx/yarn) is consistent: **every wrapper example found in this spike
exists to change what the invocation IS before it is ever formed as a
string a hook or permission matcher would see** — injecting a secret
(`ruby.sh`'s `RAILS_MASTER_KEY`), forcing individual file adds
(`ai-aligned-git`), removing shell-metacharacter surface via `shell=False`
+ an argument array (the AWS wrapper), or intercepting at the package-install
boundary before code executes (Aikido). Every hook example found (`dcg`,
4Shark's own `validate-bash-command.sh`) exists to make an allow/deny
**decision on an already-fully-formed command**. This is offered as a
descriptive pattern across the evidence gathered, not as a community-cited
rule — see "What remains uncertain" below for the honest boundary of this
claim.

---

## Taxonomy table

| Community-recognized category | Does 4Shark do this today? | Does the community/vendor actively recommend it? | Evidence |
|---|---|---|---|
| Permissions & Authorization (glob allow/ask/deny rules) | **Yes, extensively** (210 allow + 36 ask entries) but internally folded into "hooks" rather than named as its own layer | Yes — vendor's own architecture (5-layer evaluation order) | Findings 1, 2 |
| Deterministic hooks (PreToolUse/PostToolUse/etc.) | **Yes, extensively** (33 scripts) | Yes — "the model cannot reason its way around it. The model cannot forget it. The hook runs" (per prior sibling spike, not re-derived) | Finding 1; sibling spike `agent-command-approval-visibility` |
| Documentation / rules files (CLAUDE.md, Tier 1/2 docs) | **Yes, extensively** (ADR-001-justified custom SessionStart hook over native `rules/`) | Yes, with a documented caveat — vendor's own docs: *"Instructions in your prompt or CLAUDE.md shape what Claude tries to do, but they don't change what Claude Code allows"* (advisory, not enforced) | ADR-001; sibling spike Finding 7 |
| Tool-shaping wrappers (rewrite the invocation before it forms) | **Yes, narrowly** (4 scripts: ruby, ecs-scale, start/stop-instance) | Yes, as one of several patterns — no single canonical "wrapper" category name found in vendor docs; closest vendor analogue is the external credential-proxy pattern | Findings 1, 6 (aux), Group C below |
| Sandboxing / OS-level isolation | **No** — no `sandbox` key in `settings.json` | **Yes, strongly** — vendor's own built-in feature, explicitly framed as complementary to (not a replacement for) permissions | Finding 6 |
| MCP tool-scoping / least-privilege tool exposure | **No** — zero MCP servers configured | Yes, where MCP is used at all — treated as a distinct visibility-layer control | Finding 7 |
| Subagent decomposition as a permission-scoped control (native `Agent(...)` rules) | **Partially** — subagent decomposition exists (9 exception-tier agents) but scoping is prose+manual-verification, not the native `Agent(...)` permission primitive | Yes — native platform primitive exists for this purpose | Finding 8 |
| Model-based classifier ("auto mode") | **No** | Documented trade-off, not unqualified — 17% false-negative rate per prior sibling spike; not re-derived here | Prior spike `ai-agent-permission-control` Approach C |
| Evals / regression testing of the harness itself | **No** — no eval/regression suite for hook/wrapper scripts | **Disputed** — one community list frames it as governance ("deployment gates"); Anthropic's own blog frames it as QA, not access control | Findings 4, 9 |
| Observability / audit logging of governance decisions | **No** — hooks `exit 2`/stderr only, no persisted decision log | Named as its own category by the independent taxonomy | Finding 5 |
| Output styles (full system-prompt replacement) | **No** — no `~/.claude/output-styles/` directory | Exists as a native, documented mechanism; no strong community "you should use this" signal found | Finding 3; `governance_anthropic_permissions_3.txt` |
| Spec-driven / plan-driven workflows (PLAN.md/TASKS.md pipeline) | **Yes, extensively** — the entire `plan-researcher → plan-composer`, `task-researcher → task-composer` pipeline | Yes — already the basis for ADR-001's own citations (José Parreño García, Joshua McDonald, GitHub Spec Kit) | ADR-001 references (not re-fetched in this spike) |
| Prompt-injection-specific defenses (web-summarization, egress allowlisting) | **Partially** — WebFetch/WebSearch are Claude-Code-native tools, so the vendor's own "summarized search results" mitigation applies by default; no additional 4Shark-specific defense found | Named by the vendor as a built-in feature, not a separate mechanism to add | Finding 6 (aux) |
| Memory (dynamic, agent-written, cross-session) | **Explicitly disabled** (`autoMemoryEnabled: false`) and replaced with a manual save-to-file workflow | Native platform feature exists; 4Shark's substitution is a deliberate, documented choice (per `CLAUDE.md` § Memory Save Workflow), not an oversight | Finding 5; `settings.json:4` |

---

## Wrapper deep-dive

### Most commonly wrapped tools found in this research, and why

Four concrete wrapper examples were found and verified in this spike, spanning
three different tool families:

1. **Ruby/Bundler** (`ruby.sh`, 4Shark's own) — wraps the version-manager
   resolution (RVM/rbenv/asdf) and injects `RAILS_MASTER_KEY` internally, so
   the invocation contains neither `$(...)` command substitution nor a
   leading `VAR=value` prefix — both of which independently defeat Claude
   Code's string-prefix permission matcher (`RUBY-COMMAND-EXECUTION.md:20-33`).
   No external community example of this exact combination (Ruby version
   manager + secret injection, purpose-built for an AI coding agent) was
   found — this appears to be a 4Shark-specific synthesis rather than an
   adopted community pattern. **Not found**: any other project wrapping
   RVM/rbenv/asdf specifically for agent-permission reasons.

2. **git** (`ai-aligned-git`) — wraps `git` via a PATH shim to block bulk
   `git add .`, block `--no-verify`, and require AI-attribution metadata.
   A recognized, purpose-built pattern (governance_wrapper_git_ai_aligned_5.txt).

3. **AWS CLI** (the codenote.net pattern) — wraps `aws` as a non-shell
   argument-array allowlist, citing OWASP's "first line of defense against
   OS command injection" principle. A recognized pattern
   (governance_wrapper_aws_cli_7.txt).

4. **npm/npx/yarn** (Aikido Safe Chain) — wraps the package managers via
   shell aliases to scan every install against a malware-intelligence feed
   before code executes. A general supply-chain-security pattern that
   explicitly extends to AI coding tools, not purpose-built for them
   (governance_wrapper_npm_aikido_8.txt).

**Not found in this research** (searched, no confirmed wrapper pattern):
Docker, kubectl, or Terraform wrapped specifically as an invocation-rewriting
script for AI-agent safety. The Terraform ecosystem's AI-agent safety
material found in this spike's searches converges instead on
plan-then-approve workflows and policy-as-code (OPA/Sentinel/conftest)
evaluated against a **JSON-exported plan**, not on an invocation-rewriting
wrapper around the `terraform` binary itself — structurally closer to
4Shark's own hook-based approach (`inject-terraform-context.sh` +
`permissions.ask` gating `terraform apply`/`destroy`) than to a wrapper.
kubectl-for-agents material found emphasizes RBAC scoping and command
allowlists enforced "outside the model" — consistent with either a wrapper
or a hook, but no specific wrapper implementation was fetched and verified.

### Is a git wrapper a recognized pattern, and how does it relate to 4Shark's existing hook-based git safety?

Yes — `ai-aligned-git` is a real, purpose-built git wrapper for AI agents
(Finding 10; `governance_wrapper_git_ai_aligned_5.txt`). But its concern set
is **not** the same as 4Shark's current git-safety concern. 4Shark's
`validate-bash-command.sh` (hook) blocks destructive operations on an
already-formed command: force-push to `develop`/`master`, `reset --hard`,
`clean -f`, `branch -D`, `checkout .`, branch creation outside HubFlow
conventions, `gh pr merge` (per `CLAUDE.md` § Git Safety). This is the same
concern class `destructive_command_guard` addresses — and `dcg` is itself a
**hook**, not a wrapper (Finding 10). `ai-aligned-git`'s concern is
different: forcing individual `git add <file>` over bulk `git add .`, and
demanding attribution metadata a bare `git commit` does not otherwise carry.
4Shark has no equivalent rule today for either of `ai-aligned-git`'s two
concerns (bulk-add is not currently blocked; attribution is handled
differently — 4Shark's own convention is "no AI co-authorship" in commit
messages, the functional opposite of `ai-aligned-git`'s mandatory
disclosure — see `CLAUDE.md` § Git Commit Policy). So: a git wrapper is a
recognized pattern, but the specific concern it addresses in the wild
(bulk-add safety, attribution disclosure) is different from the concern
4Shark already solved via a hook (destructive-operation blocking). Building
a 4Shark git wrapper would not replace `validate-bash-command.sh`'s git
block — it would need its own, different rationale.

### The wrapper-vs-hook axis

**Not found**: an explicit, named community principle stating when to
reach for a wrapper versus a hook (Finding 10 — two targeted fetches for
this exact comparison both came back empty). This spike's own descriptive
synthesis, grounded in the four wrapper and two hook examples gathered
(explicitly flagged as inference rather than a cited rule): every wrapper
example found reshapes or reconstructs the invocation **before** it exists
as a command string (injecting a secret, forcing an argument array instead
of a shell string, forcing specific flags/individual arguments) — it acts
at construction time. Every hook example found evaluates an **already-
formed** command string and returns allow/deny/redirect — it acts at
decision time. 4Shark's own split is consistent with this pattern without
having stated it explicitly: `ruby.sh` exists specifically because the
`$(...)`/`VAR=` shapes defeat the permission matcher **no matter how the
hook or allow-list is written** (`RUBY-COMMAND-EXECUTION.md:29-33`,
*"No number of allow-list entries fixes this; the fix is to remove the
substitution and the prefix from the invocation entirely"*) — i.e., 4Shark
reached for a wrapper precisely in the one case where a hook/permission-rule
fix was structurally impossible (the unsafe shape had to never be
constructed, because no amount of post-hoc string matching could reliably
recognize it). This matches the AWS-CLI wrapper's OWASP-cited rationale
("not invoking OS commands directly at all" as the *first* line of
defense, before any allowlist/hook layer). Whether this "construction-time
vs. decision-time" framing generalizes beyond the six examples gathered
here is explicitly not established — see below.

---

## What remains uncertain

- **Whether "construction-time vs. decision-time" is a real community
  principle or this spike's own post-hoc pattern-matching across six
  examples.** No source states it in this form. It is offered as a
  synthesis grounded in verified evidence (Finding 10), not a citation.
- **Whether the `awesome-harness-engineering` list's "governance" framing
  of evals (deployment gates) or Anthropic's own "QA" framing is the more
  authoritative read for 4Shark's specific situation** (Finding 9) — the
  two sources disagree and this spike does not adjudicate between them.
- **Whether 4Shark's zero-MCP-server state is a gap or simply "not yet
  needed."** No 4Shark workflow currently routes through MCP (confirmed by
  the settings.json grep), so Finding 7's capability gap has no known
  concrete trigger today.
- **Whether Docker, kubectl, or Terraform have documented AI-agent-specific
  wrapper implementations that this spike's searches simply did not
  surface** — the searches run were not exhaustive (no GitHub topic-tag
  crawl, no Reddit/Discord search), and the "not found" conclusions for
  these three tools should be read as "not found in this spike's searches,"
  not as "does not exist anywhere."
- **Whether Anthropic's `sandbox-runtime` (Finding 6) is viable on 4Shark's
  actual engineer machines (macOS via `sandbox-exec`) without breaking the
  RVM/`ruby.sh`, Terraform `direnv`, or `bin/ecs run` workflows** — this
  spike did not test the tool; it only confirms the vendor's claim that
  setup is lower-friction than containers/VMs.

---

## Suggested options for main and the engineer

- **Option A — No change.** 4Shark's current hooks+docs+wrappers combination
  already covers the categories with the strongest, least-disputed community
  backing (permissions, hooks, docs-as-advisory-with-hook-backup). The
  categories it does not cover (sandboxing, MCP scoping, native subagent
  permission rules, eval/regression harness for the governance scripts
  themselves) each have a documented reason they may not yet be needed at
  4Shark's current scale (no MCP servers in use; subagent contract violations
  are caught by main's manual post-hoc check; no history of a hook script
  itself regressing silently).

- **Option B — Pilot Anthropic's built-in `sandbox-runtime`** for one
  narrow, high-risk case (e.g., Bash commands during `/execute`) given
  Finding 6's observation that it is now a lower-friction, built-in mode
  rather than requiring container/VM infrastructure — re-evaluating the
  prior spike's "infrastructure investment doesn't match the pain point"
  conclusion against this new fact.

- **Option C — Formalize the wrapper-vs-hook axis as an explicit, named
  4Shark convention** (a new doc, e.g. `WRAPPER-VS-HOOK.md`), using this
  spike's construction-time/decision-time synthesis (Finding 10) as a
  starting draft, so future tool-shaping decisions (the engineer's original
  "should we build a git wrapper?" question) have a documented decision
  rule rather than being decided ad hoc each time.

- **Option D — Investigate a 4Shark git wrapper for the specific concerns
  `ai-aligned-git` addresses that 4Shark's hook does not** (bulk `git add .`
  safety, or some other invocation-shape concern specific to 4Shark's own
  workflow) — explicitly scoped as a **different** concern from the
  destructive-operation blocking `validate-bash-command.sh` already handles,
  per the Wrapper deep-dive section above. This would require the engineer
  to first identify which specific problem a wrapper (vs. extending the
  existing hook) would solve, since the evidence gathered here does not show
  4Shark currently has the same problem `ai-aligned-git` solves.

- **Option E — Add a lightweight regression/eval harness for 4Shark's own
  governance scripts** (Finding 4/9) — e.g., a fixture corpus of known-good
  and known-bad Bash commands run against `validate-bash-command.sh` in CI,
  closing the one taxonomy gap (Verification & CI Integration /
  Observability & Tracing) that is unambiguously absent regardless of which
  source's "is this governance or QA" framing is preferred.

- **Option F — Investigate native `Agent(...)` permission rules as a second,
  mechanical layer under the existing prose-based Subagent Contract**
  (Finding 8) — e.g., `deny` rules scoping which subagents may invoke
  state-changing tools, complementing (not replacing) the existing
  `SUBAGENT-CONTRACT.md` + main's manual verification.

(No recommendation — options presented with trade-offs and their grounding
finding; the engineer and main decide.)
