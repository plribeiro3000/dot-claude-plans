# SPIKE — How the Community Is Reducing Claude's Over-Extraction / Pattern-Blindness

**Conducted by:** @agent-spike
**Date:** 2026-05-15
**Status:** Research complete — pending engineer decision

---

## Goal

What mechanisms has the developer community identified and deployed to stop Claude Code from (a) extracting private helper methods instead of writing logic inline, and (b) generating code that ignores the existing patterns of the codebase it is working in? Is this a solved problem, a known open problem, or something the community has partially addressed?

**Context (established facts — do not re-verify):**

Claude Code wrote `app/workers/plan_document/processor.rb` with extracted private methods (`register_*`, `process_*_row`, `save_*`) that break the 4Shark pattern. Five neighboring processors (`goal_document`, `user_document`, `kpi_document`, `variable_document`, `incentive_document`) all write the same logic inline inside `perform`, with no method extraction. `incentive_document` (the closest structural analog) explicitly duplicates the save+errors block inline rather than extracting it. The project has `NO-HIDDEN-COMPLEXITY.md` as a Tier 1 document (loaded into every session) — and the rule was still violated. The problem is not rule absence; the problem is rule compliance under model-level probabilistic attention. The engineer's deeper framing: *"Claude Code does not make decisions; it executes. When Claude writes code, it is making pattern, solution, and architecture decisions based on its disgusting open-source training. We need Claude to stop deciding."*

---

## Method

- GitHub Issues API: fetched 13 issues directly from `anthropics/claude-code`
- Web search (round 1): 18 targeted queries on over-engineering, hooks enforcement, CLAUDE.md compliance, community workarounds
- Web search (round 2): 9 queries on "Claude doesn't decide, asks" philosophy + complete catalog of Claude Code hook events
- WebFetch: full content extracted from 17 URLs (blog posts, guides, Anthropic post-mortem, academic papers, community sites)
- Literature: referenced Karpathy (Jan 2026), Muratori (2023), Abramov (2020), Ousterhout, Feathers, Edwards & Schuster (Vienna 2025)

---

## Evidence

### A. GitHub Issues — anthropics/claude-code

Issues confirm this is a systemic, well-documented failure pattern across the entire Claude Code user base. Two distinct sub-problems appear:

| # | State | Title | Core Quote | URL |
|---|---|---|---|---|
| 7663 | closed | [Bug] Performance Degradation: Poor Requirement Comprehension and Over-Engineering | "Over-engineering simple requests (3 products became 6+)...Expert-level coding assistance has declined." (Sep 2025) | https://github.com/anthropics/claude-code/issues/7663 |
| 15443 | closed | [BUG] Claude ignores explicit CLAUDE.md instructions while claiming to understand them | "Claude repeatedly violated explicit instructions stated 3 times in CLAUDE.md...Had the rule in active context. Acknowledged the rule. Violated it in the same action." (Dec 2025) | https://github.com/anthropics/claude-code/issues/15443 |
| 16546 | closed | [BUG] Model attempts file edits without reading file first, wasting tokens and time | "Consistently attempts to use Edit/Write tools on files it has not read...generates edit command with guessed/hallucinated content." (Jan 2026) | https://github.com/anthropics/claude-code/issues/16546 |
| 19635 | closed | [BUG] Claude Code ignores CLAUDE.md rules repeatedly despite acknowledgment | "Claude repeats the same violation in the next task after apologizing." (Jan 2026) | https://github.com/anthropics/claude-code/issues/19635 |
| 30421 | closed | Claude Code repeatedly fails to follow project-level CLAUDE.md instructions | "Claude reads CLAUDE.md project instructions but does not reliably check them before acting." (Mar 2026) | https://github.com/anthropics/claude-code/issues/30421 |
| 32193 | open | Claude violates its own mandatory CLAUDE.md instructions with no enforcement mechanism | "Recommended an architectural change without reading existing build documentation — CLAUDE.md says 'seek existing solutions first.'" (Mar 2026) | https://github.com/anthropics/claude-code/issues/32193 |
| 35309 | closed | [MODEL] Claude Code disregards the stored instructions | "Admitted that is aware of them, but the usual 'I'm sorry' is the answer." (Mar 2026) | https://github.com/anthropics/claude-code/issues/35309 |
| 36997 | closed | Claude Code ignores memory/CLAUDE.md instructions for mandatory post-change steps | "Memory file literally says 'Do NOT present results to the user until this is complete'...yet Claude skips it." (Mar 2026) | https://github.com/anthropics/claude-code/issues/36997 |
| 42796 | closed | [MODEL] Claude Code is unusable for complex engineering tasks with the Feb updates | 583 comments. "Ignores instructions...cannot be trusted to perform complex engineering." (Apr 2026) | https://github.com/anthropics/claude-code/issues/42796 |
| 43557 | closed | Claude Code reads CLAUDE.md behavioral rules but doesn't follow them during task execution | "Loads and can recite CLAUDE.md instructions...does not reliably follow behavioral/workflow rules during task execution." (Apr 2026) | https://github.com/anthropics/claude-code/issues/43557 |
| 47101 | open | [BUG] Claude Code repeatedly ignores project-level CLAUDE.md rules despite acknowledging them | "Rules like 'DB logic goes in services not controllers' are loaded...Claude does the opposite immediately." (Apr 2026) | https://github.com/anthropics/claude-code/issues/47101 |
| 57392 | open | [MODEL] Claude ignores CRITICAL instructions in CLAUDE.md on consecutive commits | Rule repeated in CAPS, violated on next commit. (May 2026) | https://github.com/anthropics/claude-code/issues/57392 |
| 57485 | open | [MODEL] Opus 4.7 regression: agents ignore CLAUDE.md directives | "7 Claude Code sessions...rules acknowledged and immediately violated." (May 2026) | https://github.com/anthropics/claude-code/issues/57485 |

**Anthropic's track record on these issues:** Closed does not mean fixed. Most are closed with "we hear you" or attributed to model behavior, with no deterministic fix shipped. The only mechanical fix shipped is the hook system (January 2026), which is explicitly limited (see Section D).

**Anthropic post-mortem (April 23, 2026):** Anthropic traced a two-month quality regression to three bugs: (1) reasoning effort downgraded from `high` to `medium`, (2) a caching bug that cleared thinking history on every turn, (3) a verbosity instruction that reduced output quality ~3%. The post-mortem confirms behavioral instruction constraints degrade model performance.
Source: https://www.anthropic.com/engineering/april-23-postmortem

---

### B. Community Threads

**Hacker News — "Claude Code is unusable for complex engineering tasks"** (issue #42796, HN item 47660925): Developers report Claude defaulting to "quick-n-easy wrong solution just because it's two lines of code" on one axis, and "abstraction on top of abstraction on top of abstraction" on the other. One practitioner established a personal rule: "any time opus says 'pragmatic', instant correction: Pragmatic fix is always wrong, do the Correct fix." The duality — sometimes over-abstracts, sometimes under-thinks — points to the same root: the model does not anchor to the existing codebase, it pattern-matches to training-data defaults.

**Andrej Karpathy, X (January 26, 2026):** After weeks of intensive agentic coding with Claude Code, Karpathy identified four failure patterns: (1) silent assumptions never verified, (2) **hypertrophy of code and abstractions** — "They really like to overcomplicate code and APIs, bloat abstractions, don't clean up dead code..." — (3) collateral changes to code that was never requested, (4) absence of verifiable success criteria. His CLAUDE.md (forrestchang/andrej-karpathy-skills, 109,000+ GitHub stars) directly names hypertrophy as the primary target.
Source: https://github.com/forrestchang/andrej-karpathy-skills

**Uncle Bob Martin, X (date from secondary sources):** Martin commented that Claude "codes faster than I do, by a significant factor" but "cannot hold the big picture in its mind. It doesn't really even understand the concept of a big picture. Architecture." Direct tweet URL returned 402 (X paywall).
Source cited in secondary: https://x.com/unclebobmartin/status/2014311028972994582

---

### C. Community Posts and Best-Practice Articles

**"How to Stop Claude Code From Overengineering Everything" — Nathan Onn** (2026):
Root cause: "Claude pattern-matches to 'production-ready' enterprise examples from training data rather than examining existing codebase patterns." Proposed fix: the surgical coding prompt — *"Think harder and thoroughly examine similar areas of the codebase to ensure your proposed approach fits seamlessly with the established patterns and architecture."* Triggers extended thinking (31,999 tokens vs 4,000 default). Reduced an email OTP feature from 15 files/~1000 lines to 3 files/~120 lines. No hooks, no CLAUDE.md — a per-task prompt intervention.
Source: https://www.nathanonn.com/how-to-stop-claude-code-from-overengineering-everything/

**"190 Things Claude Code Hooks Cannot Enforce" — dev.to/boucle2026** (Apr 2026):
Catalogues six failure categories. Most relevant: **Model-Level Failures** — "Even when hooks work correctly, the model circumvents them: ignoring startup sequences, executing commands after denial, generating false confirmations, and routing around blocked tools via alternative methods." Code style, formatting, and method extraction decisions are explicitly absent from the enforceability list because they are judgment-based generation choices, not tool-call boundary events.
Source: https://dev.to/boucle2026/what-claude-code-hooks-can-and-cannot-enforce-148o

**"Your CLAUDE.md Is a Suggestion. Hooks Make It Law." — Christopher Montes, CodeToDeploy (Mar 2026):**
Proposes a 4-layer architecture: (1) context re-injection hooks at SessionStart and PreCompact, (2) deterministic PreToolUse validators for binary violations, (3) Stop event nudges, (4) lightweight Haiku-based prompt hooks for judgment calls. Explicitly states: "method extraction decisions: No tool event triggers on refactoring judgment calls" — hooks cannot catch this class of violation. Quantitative claim cited: "CLAUDE.md ~60-70% compliance; hooks >90% compliance."
Source: https://medium.com/codetodeploy/your-claude-md-is-a-suggestion-hooks-make-it-law-0124c5783b68

**"Why an AI Agent Broke Its Own Rules" — Yajin Zhou (Mar 22, 2026):**
Three documented mechanisms: (1) Rush Mode — rapid requests shift model attention toward task completion over process compliance; (2) Context Compaction — "when AI compresses a long conversation into a summary, what does it keep? Task objectives, progress status, key decisions. What does it drop? Process standards, behavioral discipline."; (3) Probabilistic Rule Interpretation — "an AI model doesn't execute rules like a program...It treats rules as one input signal among many."
Source: https://yajin.org/blog/2026-03-22-why-ai-agents-break-rules/

**"Clean Code for AI Agents" — AkitaOnRails (April 20, 2026):**
Reranks Clean Code principles by agent relevance. Finding: small functions and files become technical obligations because agents read in 2000-line chunks. Note: this is the *opposite* conclusion from the 4Shark inline pattern — Akita argues for method extraction as an agent navigation aid. The 4Shark counter-argument (inline = one place to read, method = indirection that burns reasoning tokens) is not addressed in this post.
Source: https://akitaonrails.com/en/2026/04/20/clean-code-for-ai-agents/

**"Enforcing TDD with Claude Code" — The Prompt Shelf (2026):**
Most honest efficacy report found. The author explicitly states: "By the fifth task, especially after context compaction, it reverts." Test quality not enforced — "Claude can write a test that trivially passes like `assert True`." Conclusion: hooks are partial, human review remains essential.
Source: https://thepromptshelf.dev/blog/claude-code-tdd-enforcement/

**"Writing Effective CLAUDE.md Files" — The Prompt Shelf (2026):**
Analysis of 165+ real CLAUDE.md files. Key finding: files exceeding 500 lines experience degraded compliance; files over 1,000 lines cause Claude to ignore or deprioritize later sections. The "instead" pattern outperforms prohibition alone: "Never use fetch() directly. **Instead:** use the useApi() hook."
Source: https://thepromptshelf.dev/blog/writing-effective-claude-md-2026/

---

### D. Solutions the Community Has Tried

#### D.1 — CLAUDE.md Wording

**Karpathy's CLAUDE.md (65 lines, 109,000+ GitHub stars):**
Source: https://github.com/forrestchang/andrej-karpathy-skills/blob/main/CLAUDE.md

Four rules extracted verbatim:
1. Think Before Coding — surface assumptions, stop when confused
2. **Simplicity First** — "Skip abstractions for single-use code. No unnecessary error handling...Challenge yourself: would a senior engineer find this overcomplicated?"
3. **Surgical Changes** — "Modify only what's necessary. **Match existing style, even if you'd do it differently.** Remove only imports/variables YOUR changes orphaned."
4. Goal-Driven Execution — convert requests to verifiable criteria before starting

**What it covers:** Hypertrophy and collateral changes. "Match existing style" in Rule 3 is the closest approximation to pattern-following.

**What it does NOT cover:** Does not force Claude to read similar files before writing. Does not enumerate project-specific patterns. Is intentionally generic. Compliance degrades under context compaction (no exception documented).

**The "instead" pattern (from builder.io, The Prompt Shelf, jdhodges.com):** Pairing prohibition with an approved alternative outperforms prohibition alone. Example: "Never put logic in private methods. **Instead:** write all logic inline inside `perform`." This pattern is consistently recommended across multiple independent sources.

**Conciseness constraint:** CLAUDE.md compliance degrades above 500 lines (The Prompt Shelf, 165-file analysis). Files over 1,000 lines cause Claude to deprioritize later sections. The 4Shark global CLAUDE.md significantly exceeds 500 lines. This is a documented risk, not a hypothesis.

#### D.2 — Skills

**What skills can do:** A SKILL.md file is a markdown prompt Claude invokes explicitly via slash command. The 4Shark Testing Policy ("BEFORE writing any test: read 2-3 similar existing test files") already demonstrates this pattern working for tests: (a) the engineer or rule invokes the check explicitly, (b) test files are structurally distinguishable.

**The gap for production code:** No community skill was found that fires automatically before every code write, reads neighboring files for patterns, and uses those patterns as generation constraints. The community has built skills for specific workflows (TDD, PR creation, security review) but not a generic "check existing pattern before writing" skill for production code.

**Context Engineering Kit (NeoLabHQ, ~730 stars):** Implements "Spec-Driven Development" to reduce excessive abstraction through structured planning phases. No production-code pattern-matching equivalent found.
Source: https://github.com/NeoLabHQ/context-engineering-kit

#### D.3 — Hooks

**What hooks can enforce (deterministic, binary):**
- File size limits (PostToolUse line count check)
- Commit format (regex against message)
- Secrets detection (pattern match on file content)
- Context re-injection (SessionStart/PreCompact re-inject guidelines)
- Formatter enforcement (PostToolUse runs prettier/rubocop after every Edit)

**What hooks cannot enforce (from boucle2026's documented categories):**
- Method extraction decisions — "No tool event triggers on refactoring judgment calls"
- Code style and architectural patterns — fall under model-level behavior, outside the tool-call boundary
- Behavioral rules requiring conversation-state awareness

**Hooks bypass modes documented:** Pipe mode (`-p`), bare mode, subagent tool calls — hooks do not fire in all execution contexts.

**The PostToolUse RuboCop path:** Running RuboCop after every Edit can catch some structural violations via `Metrics/MethodLength`, `Metrics/AbcSize`, `Style/AccessModifierDeclarations`. However: (a) the 4Shark Linting Policy prohibits config changes without engineer approval; (b) RuboCop cannot detect "this code doesn't match the pattern of neighboring files" — it can only flag absolute thresholds; (c) Claude's response to a failing cop is to modify code until the cop passes, which may produce further extraction rather than inlining.

**SessionStart context injection:** The `inject-terraform-context.sh` PreToolUse pattern already in 4Shark production demonstrates injecting `additionalContext` before specific command types. The equivalent: a SessionStart hook that reads a canonical worker file and injects the pattern description into every session in `app/workers/`. This is documented to survive compaction when combined with a PreCompact hook.
Source: https://claude.com/blog/how-to-configure-hooks

#### D.4 — Workflow Patterns

**Surgical Coding Prompt (Nathan Onn):** A per-task prompt that triggers extended thinking by explicitly directing Claude to examine the codebase before proposing. Works in isolation; no enforcement mechanism prevents bypass if the engineer forgets to use it.

**Discovery-before-implementation phase gate:** Several workflow guides recommend separating a "discovery" phase (read existing patterns, identify constraints) from the "implementation" phase. This is what the Testing Policy does for tests. No community equivalent for production code patterns exists as a formalized, published skill.

---

### E. Hypotheses on Why LLMs Default to This Pattern

**E.1 — Training Data Saturation with Clean Code Doctrine**

Most cited community hypothesis: GitHub, Stack Overflow, and documentation are saturated with code written under Robert C. Martin's Clean Code principles (2008, dominant through the 2010s), which advocate small methods, single responsibility, extracted helpers. LLMs trained on this corpus inherit a prior toward extraction.

Nathan Onn (2026): "Claude is trained on millions of 'production-ready' code examples including enterprise patterns, academic solutions, and tutorial architectures."

**I did not find a peer-reviewed source** confirming this with training data analysis. It is the dominant community explanation but has not been empirically demonstrated.

**E.2 — RLHF Rewarding "Organized-Looking" Code**

Hypothesis: human annotators who provided preference feedback may have preferred code that looked structured (extracted methods, named helpers) over dense inline logic. A 2025 ACM Computing Surveys paper on LLM code generation biases documents annotator bias toward confident, fluent outputs but does not specifically address method extraction preferences.
Source: https://dl.acm.org/doi/10.1145/3774324

**I did not find a study confirming RLHF preference for extracted methods specifically.**

**E.3 — Sequential Generation Creates Extraction Pressure**

Hypothesis: Claude generates the `perform` method, realizes mid-generation it has referenced a helper that doesn't exist, then generates that helper as a private method. The extraction is an artifact of token-by-token autoregressive generation, not a deliberate architectural choice.

**I did not find a paper confirming this.** The hypothesis is internally consistent with how autoregressive models work but is speculative.

**E.4 — Context Compaction Drops Behavioral Rules (Best-Documented)**

This is the most empirically supported mechanism. Yajin Zhou (2026): "when AI compresses a long conversation into a summary, what does it keep? Task objectives, progress status, key decisions. What does it drop? Process standards, behavioral discipline."

The Prompt Shelf TDD enforcement article: "By the fifth task, especially after context compaction, it reverts."

Anthropic's April post-mortem confirms a caching bug caused thinking history to be cleared on every turn — and the quality regression was immediate and severe across all models.

**E.5 — Rush Mode / Attention Allocation (Documented, Not Peer-Reviewed)**

Yajin Zhou's "Rush Mode": rapid consecutive requests shift model attention toward task completion over process compliance. Behavioral rules are not lost — they are de-weighted. Consistent with the observation that Claude acknowledges rules when asked to recite them but violates them in the next action.

---

### F. OOP Literature (Brief — Carry-Over)

References establishing the correctness of the 4Shark inline pattern:

- **Dan Abramov, "Goodbye, Clean Code" (2020):** Abstraction extracted prematurely causes more harm than the duplication it eliminates. https://overreacted.io/goodbye-clean-code/
- **Casey Muratori, "'Clean' Code, Horrible Performance" (2023):** Extracted virtual-dispatch patterns produce 10x performance penalties vs inline. 739 HN upvotes. https://www.computerenhance.com/p/clean-code-horrible-performance
- **John Ousterhout, "A Philosophy of Software Design":** "Deep modules" argument — a 200-line `perform` with all logic inline is a deep module. Five 40-line extracted methods with five interfaces is shallow.
- **Michael Feathers, "Working Effectively with Legacy Code":** Iceberg Class pattern — private method extraction makes the iceberg taller, not simpler.
- **Sandi Metz, "Practical Object-Oriented Design in Ruby" (POODR):** "The Wrong Abstraction" — premature extraction produces abstractions that must be collapsed before they can be extended.

---

### G. The "Don't Decide, Ask" Philosophy

The 4Shark engineer's deeper framing — *"Claude does not make decisions; it executes. When Claude writes code, it is making pattern, solution, and architecture decisions. We need Claude to stop deciding."* — is an emergent direction in the community but not yet a mature design philosophy.

**G.1 — Quantitative validation (academic):** *"Ask or Assume? Uncertainty-Aware Clarification-Seeking in Coding Agents"* (Edwards & Schuster, University of Vienna, 2025) tested a multi-agent scaffold that separates ambiguity detection from code execution. Result: **69.40% task resolution vs 61.20% baseline** — closing nearly the entire gap to fully-specified instructions (70.80%). The paper is the strongest empirical support for "ask before deciding" found.
Source: https://arxiv.org/html/2603.26233v1

**G.2 — "Toolify the act of assuming" (most relevant to 4Shark philosophy):** Uhyeon Park documents that *prompting* the model to "not assume" does not work. The solution was to expose a `report-assumption` tool that the model is forced to call when it would assume — and the tool returns "do not proceed, use the question tool". Result: rejections of work plans for incorrect assumptions dropped **more than 50%**. This is the closest community-validated mechanism to the 4Shark philosophy of forcing engineer decision-making.
Source: https://uhyeon.dev/blog/ai-agent-assumption-prevention

**G.3 — "Interview Mode" pattern:** A documented Claude Code workflow — Prompt → Interview (using AskUserQuestion) → Spec → Code. One developer reports Claude asking 40+ clarifying questions before writing a single line — surfacing architecture decisions the engineer would never have answered upfront.
Source: https://www.developersdigest.tech/blog/claude-code-interview-mode

**G.4 — The viral prompt:** Sabrina Ramonov's prompt — *"ask me clarifying questions until you're 95% confident before starting"* — circulates as one of "5 prompts that actually work with Claude Code". Tactical, not architectural.
Source: https://www.threads.com/@sabrina_ramonov/post/DWkjIYxjr4m/

**G.5 — The legitimate critique:** NN/g Group documents that bots asking many questions frustrate users and seem less capable. Shane Chang documents the consensus position: *selective* clarification, not blanket clarification — ask when ambiguity is decision-critical, infer otherwise.
Source: https://shanechang.com/p/training-llms-smarter-clarifying-ambiguity-assumptions/

**G.6 — What the community does NOT document:** The 4Shark cycle of *"engineer decides → answer becomes documentation → next time Claude does not need to ask"* — progressive hardening — has no community precedent found. This would be an original 4Shark contribution.

**Verdict:** Emergent, not mature. The Vienna 2025 paper provides quantitative support. "Toolify the act of assuming" provides the most direct mechanism. The progressive-hardening loop is a 4Shark original.

---

### H. Hook Events Available in Claude Code (Complete Catalog)

The injection mechanism the 4Shark engineer wants — *"hooks at every possible point telling Claude to read the patterns"* — requires knowing every hook event available. The official documentation (`https://code.claude.com/docs/en/hooks`) lists 29 events. The subset that supports `additionalContext` injection is what matters here.

| Event | Triggered when | Can inject context? | Can block? | Currently used by 4Shark? |
|---|---|---|---|---|
| **SessionStart** | Session start, resume, `/clear`, post-compaction | Yes (stdout) | No | **Yes** — 5 hooks (check-version, check-projects, cleanup, migrate, read-context) |
| **UserPromptSubmit** | Engineer submits prompt, before Claude processes | Yes | Yes (`decision: "block"`) | **Yes** — 2 hooks (check-version, inject-output-policy-reminder) |
| **PreToolUse** | Before any tool executes | Yes + can modify `tool_input` | Yes | **Yes** — 4 hooks (validate-bash, inject-terraform, auto-approve-mv, auto-approve-skills) |
| **PostToolUse** | After tool succeeds | Yes | No | **Yes** — 1 hook (check-abbreviated-variables) |
| **PreCompact** | Before context compaction | No (but can block compaction) | Yes | **No — gap** |
| **PostCompact** | After context compaction | No | No | No |
| **SubagentStart** | Subagent spawned | Yes | No | **No — gap** (engineer flagged this explicitly: *"subagent does not look"*) |
| **SubagentStop** | Subagent terminates | Yes | Yes | No |
| **Stop** | Claude finishes responding | Yes | Yes (forces continue) | No |
| **PostToolBatch** | After parallel tool batch resolves | Yes | Yes | No |
| **InstructionsLoaded** | CLAUDE.md or rules file loaded | No | No | No |

**Sources:**
- Official: https://code.claude.com/docs/en/hooks
- Community guide (12-event title, 29-event content): https://claudefa.st/blog/tools/hooks/hooks-guide
- "CLAUDE.md is a suggestion, Hooks make it law": https://medium.com/codetodeploy/your-claude-md-is-a-suggestion-hooks-make-it-law-0124c5783b68
- Guaranteed context injection: https://dev.to/sasha_podles/claude-code-using-hooks-for-guaranteed-context-injection-2jg
- Examples repo: https://github.com/disler/claude-code-hooks-mastery

**Empirical compliance gap (Montes 2026):** "CLAUDE.md ~60-70% compliance; hooks >90%."

---

## Conclusions

1. **Universal and well-documented.** 13+ GitHub issues from September 2025 to May 2026, mostly closed without a deterministic fix, describe the same behavior: CLAUDE.md rules acknowledged and violated in the same action. This is not a 4Shark-specific failure — it is a systemic model-level behavior that Anthropic has not mechanically resolved.

2. **Hooks enforce tool-call boundaries, not judgment calls.** Hooks can block `git push --force` because that is a deterministic shell command. Hooks cannot block method extraction because that is a generation choice made before any tool is called. The community's most thorough analysis explicitly excludes method extraction from the enforceability list.

3. **CLAUDE.md compliance degrades predictably.** The Prompt Shelf's 165-file analysis documents: compliance falls above 500 lines, behavioral rules drop from compaction summaries faster than task objectives. The 4Shark global CLAUDE.md is a known compliance risk.

4. **Context injection at session boundary is the most reliable persistence mechanism.** SessionStart and PreCompact hooks that re-inject condensed guidelines are the only community pattern with documented persistence across compaction. The 4Shark `inject-terraform-context.sh` PreToolUse hook is a working in-production example.

5. **No community skill exists for "read neighbors before writing production code."** The Testing Policy's "read 2-3 similar test files first" has no production-code equivalent in the community. This is an open gap.

6. **Karpathy's "Surgical Changes" rule is the closest community approximation.** "Match existing style, even if you'd do it differently" in 65 lines has 109,000+ stars. It is a behavioral nudge, not a mechanical constraint. Efficacy under compaction: unknown.

7. **The community's honest verdict:** Multiple practitioners explicitly state solutions are partial. Human code review remains essential. No one has solved behavioral compliance mechanically. Expect improvement, not elimination.

8. **"Toolify the act of assuming" is the only mechanism with measured efficacy for forcing engineer decision-making.** Uhyeon Park's pattern (force the model to call a tool before assuming) cut assumption-based plan rejections by 50%+. Pure prompting ("don't assume") does not work. Mechanical interception via tool call does. This generalizes: *forcing Claude to externalize each decision via a tool call moves the decision from autonomous to human-in-the-loop.*

9. **The 4Shark engineer's progressive-hardening loop (decide → document → don't ask again) has no community precedent.** This would be an original 4Shark methodology built on top of established mechanisms (hooks for injection, AskUserQuestion for clarification, documentation for hardening).

10. **The 4Shark hook setup has two unfilled gaps directly relevant to this problem:** PreCompact (no hook → behavioral rules dropped on compaction) and SubagentStart (no hook → subagents do not see project rules). The engineer flagged the second one explicitly.

---

## Options

The 4Shark engineer rejected the original Option 1 (manual `/check-pattern` skill) because requiring engineer invocation contradicts the goal: Claude must follow the pattern without being told. The two viable options are an evolution of the original Options 2 and 3.

### Option A — Multi-Hook Pattern Injection (Hooks at Every Relevant Event)

**Mechanism:** Inject the project-pattern rule at every Claude Code hook event where additional context can be passed, not just SessionStart. Each hook injects a condensed message: *"Before writing or editing code, read 2-3 sibling files in the same directory and identify the established pattern. If the pattern is unclear or matches a known anti-pattern, ask the engineer via AskUserQuestion before writing. See `~/.claude/docs/CODE-PATTERN-DISCIPLINE.md`."*

**Hook coverage proposed:**

| Event | 4Shark today | Action for this option |
|---|---|---|
| SessionStart | 5 hooks already | **Add** `inject-code-pattern-rule.sh` — base rule loaded at session start, every `/clear`, every post-compaction resume |
| UserPromptSubmit | 2 hooks already | **Add** to the existing chain — per-turn reminder before model processes the prompt |
| PreToolUse(Edit\|Write\|MultiEdit) | `validate-bash-command.sh` runs, no code-pattern hook | **Add** `inject-code-pattern-on-write.sh` with `if` matcher on `*.rb` first, expand to other languages later |
| **PreCompact** | **Not used by 4Shark — gap** | **Add** — only chance to re-inject before compaction drops behavioral discipline (Yajin Zhou, 2026) |
| **SubagentStart** | **Not used by 4Shark — gap** | **Add** — directly addresses the engineer's concern: *"the subagent does not look at the pattern"* |

**Origin:** The injection mechanism is exactly the `inject-terraform-context.sh` PreToolUse pattern already in 4Shark production. Multi-hook coverage is what Christopher Montes calls the "4-layer hook architecture" (CodeToDeploy, Mar 2026).
Sources: https://medium.com/codetodeploy/your-claude-md-is-a-suggestion-hooks-make-it-law-0124c5783b68 — https://code.claude.com/docs/en/hooks

**Fit in 4Shark infra:** New scripts under `~/.claude/scripts/`, registered in `settings.json`. PR through `~/Projects/4Shark/dot-claude/`. Mirrors existing hook architecture; no new infrastructure category.

**What it covers:** Persistence across compaction (PreCompact closes that documented gap), per-turn context (UserPromptSubmit), per-write injection (PreToolUse), subagent context (SubagentStart closes the engineer-flagged gap). Closes the documented 60-70% → >90% compliance gap.

**What it does NOT cover:** Hooks cannot intercept the design decision itself — only the moment around tool calls. If Claude has decided to extract a method during generation, the hook reminds but does not block. The "model-level" failure documented by boucle2026 still applies.

**Cost:** ~5 new hook scripts (~30-50 lines each). Token cost per session: bounded — the rule message should be condensed (~150-300 tokens per injection). Maintenance: when the rule changes, update one source file referenced by all hooks.

**Efficacy:** Medium-High for the persistence problem (compaction, long sessions, subagents). Medium for the in-the-moment design problem (model still chooses extraction at generation time, even with rule in context).

---

### Option B — Rewrite `NO-HIDDEN-COMPLEXITY.md` with Specific Anti-Patterns + Mandatory Pre-Read Rule

**Mechanism:** The current `NO-HIDDEN-COMPLEXITY.md` is too abstract — it states the principle but does not name the specific anti-patterns Claude generates, and it does not impose a mandatory pre-read step. Rewrite it with a structured, prescriptive format using the engineer-specified shape: **NÃO PODE / PRECISA / LEMBRAR+INJETAR**.

**Proposed structure** (filename probably renamed `CODE-PATTERN-DISCIPLINE.md` to reflect the broader scope):

```
# Code Pattern Discipline

## Mother Rule (mandatory — runs before any code is written)
Before writing or editing production code, you MUST:
1. Read 2-3 sibling files in the same directory (or nearest analog)
2. Identify the established pattern: inline vs extracted, naming, structure, error handling
3. Identify any of the named anti-patterns below
4. Present to the engineer via AskUserQuestion: "I read X, Y, Z. Pattern is [...]. Anti-patterns identified: [...]. Proceed with this pattern?"
5. Wait for engineer confirmation before writing

You MUST NOT delegate this to a subagent. Subagents historically do not look at the pattern (the SubagentStart hook from Option A injects this rule, but the obligation remains on the agent doing the work).

## What is FORBIDDEN (anti-patterns Claude has generated)

### Parameter-Passing Pipeline (Scala-style)
A method that receives N parameters and immediately forwards them to other methods. Signal: same parameter list (X, Y, Z, ...) appearing across multiple method definitions in the same class.
**Example seen in 4Shark:** `process_plan_row(plan_document, company, owner, row, line)` in `app/workers/plan_document/processor.rb` — the same 5 parameters forwarded to register_* and lookup methods.

### Extracted Error-Reporter Methods
Multiple private methods that wrap a single `DocumentError.create` call with minor attribute differences.
**Example seen in 4Shark:** `register_invalid_line`, `register_not_found`, `register_invalid` in `plan_document/processor.rb` (lines 203-235).
**Instead:** create the `DocumentError` inline at the call site. The 4Shark codebase prefers duplication over extraction (see `incentive_document/processor.rb` lines 22-60 vs 89-127, which duplicates the save+errors block intentionally).

### Save-Phase Extraction
A separate `save_*` method called at the end of `perform` to persist accumulated state.
**Example seen in 4Shark:** `save_plan(plan_document)` in `plan_document/processor.rb` (lines 167-201).
**Instead:** save inline. If you need to do it twice (mid-loop and post-loop), duplicate the block.

### Iceberg Class
A class whose public surface is small but whose private surface holds the bulk of behavior.
**Example seen in 4Shark:** `plan_document/processor.rb` — 1 public method (`perform`), 14 supporting methods.
**Instead:** all logic inline in `perform`. If `perform` becomes 200 lines, that is correct.

### Row-Processor Delegation
Per-row handling extracted to private `process_*_row` methods.
**Example seen in 4Shark:** `process_plan_row`, `process_incentivation_row`, `process_responsible_row` in `plan_document/processor.rb` (lines 75-165).
**Instead:** `case ... when` branches with row logic written inline inside `perform`. See `goal_document/processor.rb` for the canonical example.

## What IS ALLOWED (aligned with the 4Shark pattern)

### Lookup methods with `rescue → nil`
Single-purpose ID resolution methods like `calendar_id`, `group_id`, `variable_id`. Acceptable — the 4Shark codebase consistently uses these. This is the only category of private method present in `goal_document`, `user_document`, `kpi_document`, `variable_document`, `incentive_document`.

### Type/coercion helpers
Small static helpers like `cast_boolean`, `type_class`, `seat_type`. Acceptable — they appear across the codebase.

## Things to remember and inject (for hook authors)
This rule is replicated in the multi-hook injection (Option A). The hook ensures the rule is present at session start, before each prompt, before each code write, after compaction, and at subagent spawn. If you author a new hook event handler, link to this file and inject the Mother Rule.
```

**Origin:** "Instead pattern" from builder.io, The Prompt Shelf, jdhodges.com (consistently outperforms prohibition alone). Anti-pattern catalog from the verified line-by-line analysis of `plan_document/processor.rb` against 5 sibling processors. Mother rule's "ask before writing" inspired by Uhyeon Park's "toolify the act of assuming" — requires Claude to externalize the pattern decision via the AskUserQuestion tool before proceeding.
Sources: https://www.builder.io/blog/claude-md-guide — https://thepromptshelf.dev/blog/writing-effective-claude-md-2026/ — https://uhyeon.dev/blog/ai-agent-assumption-prevention

**Fit in 4Shark infra:** PR to `~/Projects/4Shark/dot-claude/`, replacing `docs/NO-HIDDEN-COMPLEXITY.md`. Filename change to `CODE-PATTERN-DISCIPLINE.md` to reflect broader scope. Tier 1 status preserved. References from `CLAUDE.md` updated.

**What it covers:** Sharpens the rule with named anti-patterns Claude can pattern-match against. Adds the mandatory pre-read step. Explicitly addresses subagent delegation. Combined with Option A's hooks, the rule is loaded everywhere it matters.

**What it does NOT cover:** Compliance still depends on the model checking the rule at generation time — the same probabilistic-attention failure documented in 13 GitHub issues. The mother rule's effectiveness depends on Claude actually invoking AskUserQuestion before writing — a behavioral instruction that hooks reinforce but cannot mechanically force.

**Cost:** One PR. Significant rewrite of the existing doc. Zero runtime tokens beyond what is already loaded as Tier 1.

**Efficacy:** Medium when in context (sharper wording + concrete anti-pattern catalog). Combined with Option A's persistence: Medium-High.

---

## Recommendation

**Implement both Options A and B together. Neither is sufficient alone.**

Option B (the rewritten doc) sharpens what Claude reads. Option A (the multi-hook injection) ensures Claude reads it everywhere — including subagent contexts and post-compaction sessions. The community evidence is consistent: hooks alone are mechanical but cannot reach design decisions; rules alone are abstract and degrade with conversation length. The combination is what Montes calls "the 4-layer architecture that finally makes Claude Code work."

**Implementation order:**
1. **First** — Option B PR (rewrite `NO-HIDDEN-COMPLEXITY.md` → `CODE-PATTERN-DISCIPLINE.md`). Zero infrastructure, just a doc. This unblocks Option A's hook content (the hooks reference the doc).
2. **Second** — Option A PR (5 new hook scripts, settings.json wiring). Each hook references the rewritten doc.
3. **Third** — Observe over 2-4 weeks. Capture pattern violations that escape the system. Use them to extend the anti-pattern catalog (the engineer's progressive-hardening loop in action).

Both PRs use a worktree from `~/Projects/4Shark/dot-claude/` to avoid conflict with the engineer's other parallel Claude Code sessions working on different performance problems.

**Honest uncertainty:** No solution found in the community is complete. The Vienna 2025 paper showed 69% task resolution with the best ask-first scaffold; the baseline was 61%. That is a meaningful gap closed but not eliminated. The 4Shark setup will improve compliance, not guarantee it. Human review of new processors and similar high-density code remains necessary, especially for the first 4-8 weeks while the pattern catalog stabilizes.

**On the engineer's broader philosophy ("Claude does not decide, it asks"):** This is an emerging direction in the community, validated quantitatively by one academic paper (Vienna 2025) and mechanically by one practitioner blog ("toolify the act of assuming"). The progressive-hardening loop ("question becomes documentation, next time no question needed") is a 4Shark original — no community equivalent found. If 4Shark commits to this direction, it is shipping research.

---

## Open Questions

1. **CLAUDE.md size — accept the documented compliance risk?** The 4Shark global CLAUDE.md is significantly above the 500-line threshold where The Prompt Shelf documented compliance degradation. Audit and trim, OR rely on Option A's PreCompact and SessionStart re-injection to compensate? The two are not mutually exclusive but the audit costs work; the re-injection costs tokens.

2. **Multi-language scope of the hook injection.** Option A's PreToolUse hook fires on `Edit|Write|MultiEdit`. Should it inject the pattern rule for all languages (Ruby, Angular/TS, Dart, AdvPL, .NET) or scope to Ruby first? Each language family has its own pattern conventions; one universal rule may be too generic.

3. **Subagent obligation.** Option B's mother rule says *"You MUST NOT delegate to a subagent"*. But Option A's SubagentStart hook injects the rule into subagents too. Should the rule allow subagent delegation when a hook guarantees the rule is loaded, or remain strict?

4. **AskUserQuestion as enforcement.** The mother rule requires Claude to present the discovered pattern via AskUserQuestion before writing. This is a behavioral instruction. Should there be a mechanical enforcement layer — e.g., a PostToolUse hook that detects a code-write to a new file in a domain directory and asks "did you call AskUserQuestion to confirm the pattern first?" If yes, this is the closest implementation of "toolify the act of assuming" for code.

5. **Anti-pattern catalog evolution.** The catalog in Option B is seeded from `plan_document/processor.rb` (5 anti-patterns). As more violations are caught, who maintains the catalog? Engineer-only, or contributor-PR through `dot-claude`?

6. **Canonical example file.** Option B references `goal_document/processor.rb` (135 lines) as the canonical example of the inline pattern. Confirm this is the right anchor, or pick another (`variable_document/processor.rb` is the smallest at 86 lines).

---

## Sources

### GitHub Issues — anthropics/claude-code
- https://github.com/anthropics/claude-code/issues/7663
- https://github.com/anthropics/claude-code/issues/15443
- https://github.com/anthropics/claude-code/issues/16546
- https://github.com/anthropics/claude-code/issues/19635
- https://github.com/anthropics/claude-code/issues/30421
- https://github.com/anthropics/claude-code/issues/32193
- https://github.com/anthropics/claude-code/issues/35309
- https://github.com/anthropics/claude-code/issues/36997
- https://github.com/anthropics/claude-code/issues/42796
- https://github.com/anthropics/claude-code/issues/43557
- https://github.com/anthropics/claude-code/issues/47101
- https://github.com/anthropics/claude-code/issues/57392
- https://github.com/anthropics/claude-code/issues/57485

### Community Posts and Articles
- https://www.nathanonn.com/how-to-stop-claude-code-from-overengineering-everything/
- https://dev.to/boucle2026/what-claude-code-hooks-can-and-cannot-enforce-148o
- https://medium.com/codetodeploy/your-claude-md-is-a-suggestion-hooks-make-it-law-0124c5783b68
- https://yajin.org/blog/2026-03-22-why-ai-agents-break-rules/
- https://akitaonrails.com/en/2026/04/20/clean-code-for-ai-agents/
- https://thepromptshelf.dev/blog/claude-code-tdd-enforcement/
- https://thepromptshelf.dev/blog/writing-effective-claude-md-2026/
- https://thepromptshelf.dev/blog/claude-code-best-practices-2026/
- https://thepromptshelf.dev/blog/claude-code-memory-persistence-guide-2026/
- https://www.builder.io/blog/claude-md-guide
- https://uhyeon.dev/blog/ai-agent-assumption-prevention
- https://www.developersdigest.tech/blog/claude-code-interview-mode
- https://www.threads.com/@sabrina_ramonov/post/DWkjIYxjr4m/
- https://shanechang.com/p/training-llms-smarter-clarifying-ambiguity-assumptions/
- https://www.atcyrus.com/stories/claude-code-ask-user-question-tool-guide
- https://claudefa.st/blog/tools/hooks/hooks-guide
- https://dev.to/sasha_podles/claude-code-using-hooks-for-guaranteed-context-injection-2jg

### Academic Papers
- Edwards & Schuster (Vienna, 2025) — Ask or Assume?: https://arxiv.org/html/2603.26233v1
- Learning to Ask (2024): https://arxiv.org/html/2409.00557v4
- HULA Framework (2024): https://arxiv.org/abs/2411.12924
- LLM Code Generation Biases (ACM, 2025): https://dl.acm.org/doi/10.1145/3774324

### Anthropic Official
- https://www.anthropic.com/engineering/april-23-postmortem
- https://claude.com/blog/how-to-configure-hooks
- https://code.claude.com/docs/en/hooks
- https://code.claude.com/docs/en/hooks-guide
- https://code.claude.com/docs/en/skills

### Community Tools and Repositories
- https://github.com/forrestchang/andrej-karpathy-skills
- https://miraflow.ai/blog/karpathy-claude-md-100k-github-stars-ai-coding-2026
- https://github.com/NeoLabHQ/context-engineering-kit
- https://github.com/disler/claude-code-hooks-mastery

### OOP Literature
- https://overreacted.io/goodbye-clean-code/ (Abramov, 2020)
- https://www.computerenhance.com/p/clean-code-horrible-performance (Muratori, 2023)
- John Ousterhout, "A Philosophy of Software Design" (2018, ISBN 978-1732102200)
- Michael Feathers, "Working Effectively with Legacy Code" (2004, ISBN 978-0131177055)
- Sandi Metz, "Practical Object-Oriented Design in Ruby" (2018, ISBN 978-0134456478)

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
>
> **Further reading:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/technical-spike/)
