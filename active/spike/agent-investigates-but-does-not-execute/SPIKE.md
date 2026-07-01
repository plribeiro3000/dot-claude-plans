# SPIKE — Agent Investigates But Does Not Execute

**Date:** 2026-06-30
**Status:** Research complete — two-axis restructure (second restructure on engineer direction)

---

## Investigation question

**Original (three questions, answered in Findings 1-3):**
1. Is the "agent investigates but stops to ask" behavior named in the community?
2. Is it affecting other teams/Claude Code users, or isolated to 4Shark?
3. Does the 4Shark configuration contribute to it?

**Root-cause reframe (engineer's direction after initial findings):**
The agent applies Ask-Don't-Decide identically to two structurally different types of gap:
- **(a) Genuine/irresolvable gap** — information that Claude genuinely cannot access: production DB without direct access, SSH, data only the client holds. Asking is structurally correct here — no other path exists.
- **(b) Non-searching gap** — information that IS accessible via code, docs, schema, or AWS read-only, but the agent did not look before asking. Asking here is avoidable.

Is there a missing decidability pre-check upstream of Ask-Don't-Decide that would let the agent distinguish these two types and exhaust accessible sources before treating a gap as genuine?

**Concrete failing instance (Axis 1):** Engineer said "Cara, sobe aí o MongoDB do Integrator Maqnelson e faz a conexão." Agent found 3 EC2 MongoDB nodes stopped, prepared the mongosh + Mongoid query, then stopped to ask for MFA confirmation. Agent reply: "Não, ainda não subi. Parei pra confirmar com você antes de ligar 3 instâncias de banco." The EC2 state was readable via `aws ec2 describe-instances` (read-only, no MFA needed). The task was an unambiguous direct imperative. This is a type-(b) gap — access-by-not-searching — treated as type-(a).

**Second axis (engineer's direction after Findings 1-7):**
Before the "exhaust accessible sources" gate fires, there is a parallel gap on the option-surfacing path: when the agent is about to invoke AskUserQuestion with technical options (library choice, API pattern, security practice, version), those options are generated from parametric knowledge — training data that is static, cutoff-bound, and potentially stale. The agent does not currently WebSearch before formulating these options. Is there a missing gate requiring external research before option surfacing?

---

## Two axes

Both axes share the same root: the agent generates content (facts OR options) from parametric knowledge without first exhausting appropriate accessible sources. The accessible sources and trigger events differ:

| Axis | Gap type | When it fires | Accessible sources to exhaust | Missing gate |
|------|----------|---------------|-------------------------------|--------------|
| **Axis 1** (in PR #326) | Fact/state gap — the agent doesn't know an internal fact | Agent perceives a fact/system-state it doesn't know → about to ask | Internal: code, docs, schema, AWS read-only | "Exhaust internal sources BEFORE asking about a fact" |
| **Axis 2** (new) | Option/decision gap — the agent is about to surface technical alternatives | Agent is about to invoke AskUserQuestion with options | External: web search, current docs, community best practices, current library versions | "Ground options in external evidence BEFORE surfacing them" |

The document that owns both gaps is ASK-DONT-DECIDE.md. Whether the fix is one unified rule with two sub-cases, or two separate rules side by side, is an engineer design decision. Findings 8-10 lay the evidence for that decision.

---

## Sources consulted

- See auxiliary: `agent-investigates-but-does-not-execute_doc_1.txt` — GitHub #42796 verified content: statistics (permission-seeking: 40, premature stopping: 18), thinking redaction timeline, Read:Edit ratio degradation, "cheapest action available" verbatim quote
- See auxiliary: `agent-investigates-but-does-not-execute_doc_2.txt` — Anthropic trustworthy-agents article verified quotes; UNVERIFIED Anthropic Constitution quotes documented
- See auxiliary: `agent-investigates-but-does-not-execute_excerpt_1.md` — verbatim excerpts from CLAUDE.md (Work Through to PR, AWS Policy, Questions Are Just Questions, Scope Discipline, Workflow Philosophy) and ASK-DONT-DECIDE.md (lines 25-31, 107-109, 117-126); stop-gate inventory (12 gates, 2 counter-rules)
- See auxiliary: `agent-investigates-but-does-not-execute_doc_3.txt` — new research: Uncertainty Decomposition paper (Action Confidence vs Request Uncertainty terminology), Vienna 2025 paper (76.92% resolve rate on resolvable-gap no-ask tasks), Shane Chang verified quote ("truly needs to"), UNVERIFIED NN/g Group attribution, ASK-DONT-DECIDE.md and CLAUDE.md key excerpts with passive-conditions analysis
- See auxiliary: `agent-investigates-but-does-not-execute_doc_4.txt` — Axis 2 research: parametric knowledge terminology (arxiv 2606.20245, askdewey.com), grounding as named pattern (AWS Prescriptive Guidance), concept drift (getmaxim.ai), ReAct (arxiv 2210.03629), Research-First Policy Axis 2 asymmetry analysis, ASK-DONT-DECIDE.md Axis 2 gap (lines 38-48, 107-109, 117-126), community naming gap for "research before surfacing options"
- `/Users/plribeiro3000/.claude/docs/ASK-DONT-DECIDE.md` — 135 lines, fully read; `file:25-31`, `file:32`, `file:38-48`, `file:65-67`, `file:99-109`, `file:107-109`, `file:117-126`
- `/Users/plribeiro3000/.claude/CLAUDE.md` — 1465 lines, fully read; `file:225-228`, `file:483-493`
- https://github.com/anthropics/claude-code/issues/42796 — permission-seeking and premature-stopping statistics, thinking redaction correlation, Read:Edit degradation
- https://arxiv.org/html/2603.26233v1 — Vienna 2025: UA-Multi scaffold; 76.92% resolve rate on no-ask tasks (resolvable-gap data); 69.40% vs 61.20% baseline
- https://arxiv.org/html/2606.19559v1 — Uncertainty Decomposition paper: Action Confidence (c_t) vs Request Uncertainty (u_t)
- https://arxiv.org/html/2606.20245 — "Navigating Unreliable Parametric and Contextual Knowledge": "parametric knowledge" and "contextual knowledge" terms; staleness risk verbatim quote
- https://www.askdewey.com/insights/parametric-knowledge-explained — "parametric knowledge" defined as "statistical patterns embedded in an LLM's trained weights"; "cognitive homogenization" and 26% expert-divergence data
- https://docs.aws.amazon.com/prescriptive-guidance/latest/agentic-ai-serverless/pattern-grounded-agent-ai.html — "grounded agent AI workflow" named pattern; "remain grounded in fact" and "grounded in enterprise truth" quotes
- https://www.getmaxim.ai/articles/a-comprehensive-guide-to-preventing-ai-agent-drift-over-time/ — "concept drift" and "context drift" terms; "outdated information learned during pre-training"
- https://arxiv.org/abs/2210.03629 — ReAct: "generating both reasoning traces and task-specific actions in an interleaved manner"; "interface with external sources"
- https://shanechang.com/p/training-llms-smarter-clarifying-ambiguity-assumptions/ — "a model should only ask a question if it truly needs to" (verified)
- https://www.anthropic.com/research/building-effective-agents — "reinforce Claude's choice to pause, rather than to assume" (verified)

---

## Findings

### Finding 1: Community names — "permission-seeking" and "premature stopping" (Axis 1 context)

**Evidence:**
GitHub #42796 telemetry across 6,852 sessions (March 8–25, 2026):

| Category           | Count |
|--------------------|-------|
| Permission-seeking | 40    |
| Premature stopping | 18    |
| Ownership dodging  | 73    |
| Known-limitation labeling | 14 |
| Session-length excuses | 4  |
| **Total violations** | **173** |
| Total before March 8 | 0  |

Verbatim from the issue: "permission-seeking — agent asks 'should I continue?' during active execution"; "premature stopping — agents stop at 'good stopping points' when they should continue."

**Source:** `agent-investigates-but-does-not-execute_doc_1.txt` — verified from https://github.com/anthropics/claude-code/issues/42796

**Significance:** The behavior has community names, a measured onset date (March 8, 2026), and a zero pre-regression baseline. It is not 4Shark-isolated.

**Verification block:** URL fetched 2026-06-30 / Verbatim quote checked: "Permission-seeking: 40" / Statistics table confirmed in WebFetch return

---

### Finding 2: Model-level root — thinking regression makes "ask" the cheapest action (Axis 1 context)

**Evidence:**
Verbatim from GitHub #42796 (verified):
> "The rollout of thinking content redaction (`redact-thinking-2026-02-12`) correlates precisely with a measured quality regression."

Thinking depth: Baseline ~2,200 chars → March 12+: ~600 chars (−73%). Read:Edit ratio: 6.6 (Jan–Feb) → 2.0 (Mar 8–23), −70%.

Verbatim from the issue:
> "When thinking is shallow, the model defaults to the cheapest action available: edit without reading, stop without finishing, dodge responsibility for failures, take the simplest fix rather than the correct one."

**Source:** `agent-investigates-but-does-not-execute_doc_1.txt` — verified from https://github.com/anthropics/claude-code/issues/42796

**Significance:** The regression makes "ask" cheap AND makes natural research (which would have revealed the gap is resolvable) expensive. Asking before searching is now the model's lowest-cost path — for both facts (Axis 1) and options (Axis 2).

**Verification block:** URL fetched 2026-06-30 / Verbatim quotes: "redact-thinking-2026-02-12 correlates precisely" and "cheapest action available" / Both confirmed in WebFetch return

---

### Finding 3: Anthropic training explicitly reinforces pausing over assuming (Axis 1 context)

**Evidence:**
Verbatim from Anthropic trustworthy-agents article (verified):
> "First, we construct training scenarios that place Claude in ambiguous situations, and then reinforce Claude's choice to pause, rather than to assume."

**Source:** `agent-investigates-but-does-not-execute_doc_2.txt` — verified from https://www.anthropic.com/research/building-effective-agents

**Significance:** Confirmation-seeking is a trained safety behavior, not a trainable-out bug. The fix cannot come at the model layer. It must come at the configuration layer — what counts as a resolvable gap vs a genuine gap — so that the ask-reflex is not triggered by gaps the agent could have resolved itself.

**Verification block:** URL fetched 2026-06-30 / Verbatim quote confirmed in WebFetch return

---

### Finding 4 (CENTRAL, Axis 1): ASK-DONT-DECIDE.md lacks a decidability pre-check — "the safe direction is ask" has no upstream gate

**Evidence:**

ASK-DONT-DECIDE.md `file:25-31` (verbatim, fully read):

```
What is NOT a decision (you may proceed without asking):
- Mechanical execution of an explicit instruction ("rename X to Y everywhere")
- Following a pattern that is unambiguous in the surrounding code
- Following a written rule in ~/.claude/docs/ that covers the situation
- Trivial choices the engineer has explicitly delegated ("just pick a name")
```

ASK-DONT-DECIDE.md `file:32` (verbatim):
> "The boundary is judgment, but the safe direction is *ask*. The engineer can always say 'use your judgment for this category' — but Claude does not get to grant that permission to itself."

ASK-DONT-DECIDE.md `file:107-108` (verbatim):
> "Ask when the decision is non-trivial AND the answer is not in any documented rule AND the surrounding code does not unambiguously show the answer. Do not ask when the answer is in a rule, in the surrounding code, or in an explicit instruction the engineer just gave."

**The structural gap:** The "do not ask" conditions at `file:25-31` and `file:107-108` are **passive** (descriptive): if these conditions happen to be true, you should not ask. They do NOT impose an **active** mandatory pre-check: before invoking AskUserQuestion about a fact or system state, you MUST have consulted [specific accessible sources] and confirmed the gap is not resolvable there.

"The safe direction is ask" (`file:32`) is the terminal fallback with no upstream gate. The agent can reach it without having searched accessible sources at all.

**Community terminology for the missing distinction:**
Uncertainty Decomposition paper (https://arxiv.org/html/2606.19559v1, verified from `agent-investigates-but-does-not-execute_doc_3.txt`):
> "An agent may report low confidence because the action is difficult (e.g., many similar products to choose from) or because the user request is ambiguous (e.g., 'find me a shirt' without specifying color or size). These two situations call for different responses: the former suggests the agent should proceed cautiously, while the latter suggests it should ask the user for clarification."

Paper terminology: **Action Confidence (c_t)** — how likely the chosen action makes progress; low when the action is hard. **Request Uncertainty (u_t)** — how underspecified the user's goal is; high when the intent is ambiguous. Prescription: ask when u_t is high. Do NOT ask when c_t is low — proceed cautiously instead.

ASK-DONT-DECIDE.md conflates these two dimensions. Any perceived uncertainty triggers "the safe direction is ask" — regardless of whether the uncertainty is about the user's intent (u_t, irresolvable) or about a fact the agent could look up (c_t, resolvable).

**Source:** `/Users/plribeiro3000/.claude/docs/ASK-DONT-DECIDE.md` lines 25-32, 107-108; `agent-investigates-but-does-not-execute_doc_3.txt`

**Significance:** This is the Axis 1 structural root. The model already has a trained ask-bias (Finding 3) and regressed to the cheapest action (Finding 2). The config gap removes the only structural check that would have blocked the ask: a mandatory requirement to exhaust accessible sources before treating a gap as genuine. Without that gate, asking is simultaneously the cheapest action AND the most legitimate action.

**Verification block:** File read `/Users/plribeiro3000/.claude/docs/ASK-DONT-DECIDE.md` 135 lines in full / Verbatim quotes at lines 25-32, 107-108 confirmed in file read / Uncertainty Decomposition quote confirmed in `agent-investigates-but-does-not-execute_doc_3.txt` (URL fetched 2026-06-30)

---

### Finding 5: Research-First Policy creates a mandatory gate before RESPONDING — no symmetric gate before ASKING (Axis 1 context)

**Evidence:**

CLAUDE.md `file:483-487` (verbatim):
> "### Research-First Policy
> - NEVER answer questions from training data alone — always verify with a real source first
> - Questions about the codebase (behavior, structure, configuration): use Grep/Read/Glob BEFORE responding
> - Questions about external tools, libraries, APIs, error messages: use WebSearch BEFORE responding"

The gate condition is "BEFORE responding." No equivalent rule was found in CLAUDE.md for "BEFORE asking (invoking AskUserQuestion)." A complete search of all 1465 lines found no sentence of the form "exhaust accessible sources before invoking AskUserQuestion."

This is a structural asymmetry: the rule system requires research before answering the engineer; it does not require research before asking the engineer.

Complementary evidence from Vienna 2025 paper (https://arxiv.org/html/2603.26233v1, verified from `agent-investigates-but-does-not-execute_doc_3.txt`):
> "For the 156 tasks where UA-Multi refrained from asking, it still achieved a 76.92% resolve rate, indicating it correctly identified tasks that already contained sufficient information to proceed."

The 76.92% figure is the empirical operationalization of the resolvable-gap concept. ASK-DONT-DECIDE.md cites this same paper at `file:65-67` for the 69.40% improvement from asking — but does not incorporate the complementary finding. The paper is used selectively to support asking; the equal finding that not asking (when info is accessible) also improves outcomes is absent.

**Source:** `/Users/plribeiro3000/.claude/CLAUDE.md` lines 483-487; `/Users/plribeiro3000/.claude/docs/ASK-DONT-DECIDE.md` lines 65-67; `agent-investigates-but-does-not-execute_doc_3.txt`

**Significance:** The Research-First Policy already establishes the pattern "exhaust accessible sources BEFORE [action]." The pattern is not extended to the ask boundary. This is the missing mirror: "exhaust accessible sources BEFORE asking." (Note: Finding 9 documents the parallel Axis 2 gap on the option-surfacing path.)

**Verification block:** File read `/Users/plribeiro3000/.claude/CLAUDE.md` at lines 480-495 / Verbatim quote confirmed at lines 483-487 / Vienna 2025 quote confirmed in `agent-investigates-but-does-not-execute_doc_3.txt` (URL fetched 2026-06-30)

---

### Finding 6: CLAUDE.md distinguishes capability access vs non-searching access — but does not connect the distinction to ASK-DONT-DECIDE.md (Axis 1 context)

**Evidence:**

CLAUDE.md `file:225-228` (verbatim):
> "### Production Access
> - Claude HAS read-only access to AWS — the default profile is read-only by design, use it freely for logs, service status, instance listing, and any describe/list/get operation
> - Claude does NOT have direct access to production databases or SSH — when production data is needed, ask the user to provide it"

This text names two distinct access categories:

**(a) Capability gap** — Claude genuinely cannot access. Prod DB without direct access, SSH, data the client holds. The rule says "ask the user to provide it." Asking is structurally correct.

**(b) Non-searching gap** — info IS accessible (EC2 state, ECS status, CloudWatch logs, codebase, docs, schema) but the agent did not look. The rule says "use it freely." Not asking is structurally correct — the gap would dissolve on lookup.

In the Maqnelson MongoDB instance: the 3 stopped EC2 nodes were discoverable via `aws ec2 describe-instances` (read-only, default profile, no MFA). This is a type-(b) gap. The agent treated it as type-(a) and asked before checking.

ASK-DONT-DECIDE.md makes no reference to Production Access or the capability/non-searching distinction. The doc's ask conditions (`file:107-108`: "the answer is not in any documented rule AND the surrounding code does not unambiguously show the answer") cover code/doc source availability but not AWS/system-state accessibility. The bridge between "can I look this up?" and "should I ask?" does not exist in the rule system.

**Source:** `/Users/plribeiro3000/.claude/CLAUDE.md` lines 225-228; `/Users/plribeiro3000/.claude/docs/ASK-DONT-DECIDE.md` lines 107-108; `agent-investigates-but-does-not-execute_doc_3.txt`

**Significance:** The distinction the engineer identifies as missing IS already articulated in CLAUDE.md — but in a different section, for a different purpose (choosing which AWS profile to use). The two documents exist independently with no bridge: "Production Access" does not say "check this before asking"; "ASK-DONT-DECIDE.md" does not say "check your access inventory first."

**Verification block:** File read `/Users/plribeiro3000/.claude/CLAUDE.md` at lines 220-232 / Verbatim quote confirmed at lines 225-228 / Cross-reference to ASK-DONT-DECIDE.md confirmed: no mention of "Production Access" or AWS lookup in the 135-line doc

---

### Finding 7: The model regression aggravates the config gap — it does not create a new gap, it reveals the existing one (Axis 1 context)

**Evidence (synthesis of Findings 1-6):**

Before the regression (Jan–Feb 2026): the model's natural extended thinking (~2,200 chars) meant it examined accessible sources as part of reasoning. In the MongoDB instance, fuller thinking would likely have caused the model to run `aws ec2 describe-instances`, confirm the instances were stopped, consult AWS Policy ("use wrapper scripts"), and proceed. The passive conditions in ASK-DONT-DECIDE.md (`file:25-31`, `file:107-108`) were satisfied by the research the model naturally did — so the ask was blocked in practice even without an active gate.

After the regression (March 2026+): examining accessible sources is the "expensive" path that gets skipped. The perceived gap rises because the model didn't look. The model reaches "the safe direction is ask" (`file:32`) without having to demonstrate that it checked first. The config gap (passive conditions, no active pre-check) was always present; the regression removes the natural behavior that compensated for it.

Shane Chang (verified from `agent-investigates-but-does-not-execute_doc_3.txt`):
> "it's essential to balance *when* to ask versus *when to confidently answer*. Ideally, a model should only ask a question if it truly needs to."

The 4Shark config currently has no mechanism for the agent to determine whether it "truly needs to" — because determining that requires checking accessible sources first, and there is no mandatory gate for that check.

**Source:** Synthesis of Findings 1-6; Shane Chang quote from `agent-investigates-but-does-not-execute_doc_3.txt`

**Significance:** The regression made the config gap visible and frequent. The fix is not "improve the model" (trained behavior, Finding 3) nor "add domain counter-rules" (symptom treatment). The fix is to add an upstream pre-check to ASK-DONT-DECIDE.md that operationalizes the gap-type distinction — so that the ask only fires when the gap is genuinely irresolvable, not when the gap exists because the agent didn't look.

**Verification block:** Synthesis derived from Findings 1-6 (all verified above) / Shane Chang quote confirmed in `agent-investigates-but-does-not-execute_doc_3.txt` (URL fetched 2026-06-30)

---

### Finding 8: Axis 2 — community vocabulary for "stale parametric options"; community does NOT name "research before surfacing options" as a distinct practice

**Evidence:**

**Established terms (all verified):**

"Parametric knowledge" — from https://www.askdewey.com/insights/parametric-knowledge-explained (verified):
> "Parametric knowledge refers to the statistical patterns embedded in an LLM's trained weights."
> "the statistical center of mass – the internet average, weighted by volume and repetition."
> "The more differentiated your knowledge, the more it gets averaged away"

The third quote is load-bearing for Axis 2: an agent generating options from parametric knowledge generates the "internet average" of options — not necessarily the current best practice, not the expert minority view, and not the version the library actually ships today.

"LLMs are trained on static corpora, they may provide outdated information with unwarranted confidence" — from https://arxiv.org/html/2606.20245 (verified).

"Grounding" / "grounded agent AI workflow" — from https://docs.aws.amazon.com/prescriptive-guidance/latest/agentic-ai-serverless/pattern-grounded-agent-ai.html (verified):
> "Responses lack grounding in domain-specific facts, policies, or real-time state"
> "businesses want agents that reason intelligently, act autonomously, and remain grounded in fact."
> "Search or query knowledge bases to stay grounded in enterprise truth."

AWS names this an established architectural pattern for agents. It is framed around answering user queries, not specifically the AskUserQuestion option-generation step — but the concept maps: an agent surfacing options from training data without grounding them in current sources is generating "ungrounded options."

"Concept drift" — from https://www.getmaxim.ai/articles/a-comprehensive-guide-to-preventing-ai-agent-drift-over-time/ (verified):
> "Concept drift occurs when relationships between input data and target variables change over time. The underlying patterns that models learned during training become invalid as environmental conditions evolve."

This is the failure mode for Axis 2 at the option level: if the agent's training has drifted from current library APIs or community best practices, the options it surfaces from parametric knowledge are "drifted options."

ReAct pattern — from https://arxiv.org/abs/2210.03629 (verified):
> "generating both reasoning traces and task-specific actions in an interleaved manner"
> "reasoning traces help the model induce, track, and update action plans as well as handle exceptions, while actions allow it to interface with external sources"

ReAct is the community name for interleaving reasoning with external tool use. It implies research at reasoning time — including before generating option content — but does not name the specific sub-case of external research before option-surfacing to a user.

**Not found:** A specific named practice for "ground your options in external evidence before surfacing them via AskUserQuestion." The community names "grounding" (of outputs in general), "parametric knowledge" (the risk source), and ReAct (the interleaving pattern), but does NOT name the specific agent sub-behavior: "run WebSearch before formulating the options list you are about to surface to the engineer."

**Concrete Axis 2 instance:**
- Engineer asks "Como devemos autenticar as chamadas do webhook?"
- This is a decision → agent invokes AskUserQuestion
- Current: agent generates "Option A: HMAC signature, Option B: Bearer token, Option C: API key" from parametric knowledge (training cutoff: Aug 2025)
- Missing: agent has not searched "webhook authentication best practices 2026" or verified what the project's current webhook library supports
- The options may be: outdated (HMAC-SHA1 recommended instead of HMAC-SHA256 + signing secret), missing community consensus that emerged post-cutoff, or failing to surface what the library installed in the project actually supports now
- Nothing in CLAUDE.md or ASK-DONT-DECIDE.md requires the search before formulating the options

**Source:** All four URLs above; `agent-investigates-but-does-not-execute_doc_4.txt`

**Significance:** The community vocabulary ("parametric knowledge," "grounding," "concept drift") confirms the risk is named and understood. The absence of a named practice for "ground options before surfacing" means 4Shark would be adding a novel gate, not implementing an existing standard. The closest established precedent is the AWS "grounded agent AI workflow" pattern applied at the option-generation step rather than the answer-generation step.

**Verification block:** All four URLs fetched 2026-06-30 / Verbatim quotes confirmed in `agent-investigates-but-does-not-execute_doc_4.txt` (auxiliary file, written same session with quote-or-drop discipline) / "research before surfacing options" as a distinct named practice: NOT FOUND in any source fetched

---

### Finding 9: Research-First Policy Axis 2 asymmetry — "BEFORE responding" does not cover "BEFORE surfacing options via AskUserQuestion"

**Evidence:**

CLAUDE.md `file:483-493` (verbatim, confirmed read):
```
### Research-First Policy

- NEVER answer questions from training data alone — always verify with a real source first
- Questions about the codebase (behavior, structure, configuration): use Grep/Read/Glob BEFORE responding
- Questions about external tools, libraries, APIs, error messages: use WebSearch BEFORE responding
- If you cannot find evidence: say "I did not find this" — NEVER fill the gap with a guess
- When the engineer asks "what could this be?" or "why is this happening?": investigate the code and/or search the web — do not theorize from training data
```

Every trigger in this policy is the engineer asking a question: "When the engineer asks," "Questions about the codebase," "questions from training data alone." Every gate condition is "BEFORE responding" — responding to an engineer-initiated query.

The AskUserQuestion invocation is the inverse flow: the **agent** is initiating, generating options to surface to the engineer. The engineer has not asked anything that would trigger the Research-First Policy. The policy has no clause of the form "before invoking AskUserQuestion with technical options, use WebSearch to verify those options are current."

ASK-DONT-DECIDE.md `file:38-48` (verbatim, confirmed read):
> "Use the `AskUserQuestion` tool. Frame the question in terms of **alternatives the engineer can choose between**, not in terms of code: [...] The question carries the **evidence** for each option — what file demonstrates each approach, what the trade-off is."

The "evidence for each option" mandated at `file:38-48` is **internal** evidence only: `file:line` references in the codebase, sibling patterns. There is no requirement to externally verify whether those options represent current best practices. A well-formed AskUserQuestion per the current rules can read: "Option A matches `processor.rb:45`, Option B matches `service_object.rb:12`" — entirely internal, no WebSearch performed.

ASK-DONT-DECIDE.md `file:117-126` (hook enforcement table, verbatim confirmed): No hook exists for "verify options externally before AskUserQuestion." The mechanical enforcement layer has no gate for Axis 2.

**The precise asymmetry:** The Research-First Policy requires `WebSearch BEFORE responding` to an engineer question about external tools/APIs/libraries. The agent can generate options about those same external tools/APIs/libraries (which library to use, which API pattern, which auth approach) — surfacing them via AskUserQuestion — without any WebSearch. The same subject matter (external tools, libraries, APIs) is gated when the agent responds but ungated when the agent generates options.

**Source:** `/Users/plribeiro3000/.claude/CLAUDE.md` lines 483-493; `/Users/plribeiro3000/.claude/docs/ASK-DONT-DECIDE.md` lines 38-48, 117-126; `agent-investigates-but-does-not-execute_doc_4.txt`

**Significance:** The asymmetry is narrow and precise. Extending it requires one of two doc changes: (a) add a clause to Research-First Policy ("before generating AskUserQuestion options involving external tools/libraries/APIs/patterns, use WebSearch"), or (b) add a clause to ASK-DONT-DECIDE.md's "How to Ask" section ("for options that involve external knowledge, ground them in a WebSearch first before presenting"). Option (a) is in CLAUDE.md (requires a PR to dot-claude); option (b) is in ASK-DONT-DECIDE.md (shares the same document as the Axis 1 fix in PR #326).

**Verification block:** File read `/Users/plribeiro3000/.claude/CLAUDE.md` at lines 479-496 / Verbatim quotes confirmed / File read `/Users/plribeiro3000/.claude/docs/ASK-DONT-DECIDE.md` 135 lines in full / Lines 38-48 verbatim confirmed / Lines 117-126 hook table confirmed: no AskUserQuestion pre-research entry / Asymmetry analysis is author's own observation, not a claim from any external source

---

### Finding 10: Two-axis relationship — same root, distinct triggers, potentially unified fix

**Evidence (synthesis of Findings 4, 5, 8, 9):**

**Common root:** Both axes share the same mechanistic failure: the agent generates content from parametric knowledge (training data) without first exhausting accessible sources. The two faces:

- Axis 1 (fact/state): agent generates a gap signal ("I don't know X") from shallow reasoning rather than from actually checking accessible sources
- Axis 2 (option/decision): agent generates option content ("consider A, B, or C") from training-data defaults rather than from verified current sources

The Research-First Policy pattern already names this root for the answering case: "NEVER answer questions from training data alone — always verify with a real source first" (`file:485`). Axis 1 extends this to asking; Axis 2 extends this to option generation.

**Distinct triggers and sources:**

| | Axis 1 | Axis 2 |
|---|---|---|
| Trigger | Agent perceives a fact/state it doesn't know (about to ask about a system fact) | Agent is about to surface technical alternatives to the engineer via AskUserQuestion |
| What to exhaust | Internal: code, docs, schema, AWS read-only (no auth required) | External: web search, current official docs, community resources |
| What counts as "not needing to fire" | The fact IS in accessible internal sources — check and proceed | The decision is purely internal/codebase-pattern — no external knowledge has cutoff risk |
| Where the gap lives in the rule system | ASK-DONT-DECIDE.md `file:32` ("safe direction is ask") has no upstream gate | ASK-DONT-DECIDE.md `file:38-48` requires internal evidence only; Research-First Policy is "before responding" not "before generating options" |

**One unified rule or two distinct rules?**

One unified frame: "Before generating content that goes to the engineer — whether as an answer (existing Research-First Policy) or as a gap signal (Axis 1 fix) or as technical options (Axis 2 fix) — exhaust appropriate accessible sources first. Internal sources for facts; external sources for technical recommendations."

Two distinct rules: Axis 1 addresses a specific moment (the AskUserQuestion invocation when the agent lacks a fact); Axis 2 addresses a different moment (the AskUserQuestion invocation when the agent is about to surface technical alternatives). They have different trigger conditions and different "sources to exhaust." Separating them may be more actionable — the engineer can apply each rule to the right moment without ambiguity.

Both shapes are documentable. The "one unified rule" is philosophically cleaner but may reduce actionability. The "two rules" is more precise per trigger but may add documentation load. This is a design decision for the engineer.

**Fix document options:**

Both fixes touch ASK-DONT-DECIDE.md. Axis 1 (currently in PR #326): adds a pre-check to the AskUserQuestion decision boundary. Axis 2: adds either a clause to the "How to Ask" section of ASK-DONT-DECIDE.md or a clause to the Research-First Policy in CLAUDE.md. Whether to unify or separate depends on where the engineer wants the rules to live and how the progressive-hardening loop applies.

**Source:** Synthesis of Findings 4, 5, 8, 9 (all individually verified above)

**Significance:** The two-axis framing is the engineer's own conceptual contribution — not found in the community literature. The community names the individual components (parametric knowledge risk, grounding, decidability, Research-First), but the specific pairing as "two faces of the same agent-generates-without-grounding failure" is a 4Shark-original synthesis. The fix scope is genuinely a design question: one unified principle or two distinct operational rules.

**Verification block:** This finding is a synthesis — no new external claims; all component quotes verified in Findings 4, 5, 8, 9 / "Two-axis framing as 4Shark-original synthesis": no community source found that uses this exact pairing

---

## Trade-offs surfaced

### Axis 1 options (Exhaust-Before-Ask gate — decidability pre-check)

Options A-E address the Axis 1 decidability pre-check gap (Finding 4) and the Research-First asymmetry on the ask boundary (Finding 5). Domain-specific counter-rules (e.g., "ops imperative means proceed") address the consequence instance by instance, not the root cause — documented only as contrast.

| Option | Approach | Pros | Cons | Sustained by |
|--------|----------|------|------|-------------|
| **A: Exhaust-Before-Ask gate** | Add an active pre-condition to ASK-DONT-DECIDE.md: before invoking AskUserQuestion about a fact or system state, the agent must have exhausted accessible sources (code, docs, AWS read-only, schema) and confirmed the gap persists. Mirror of Research-First Policy on the ask boundary | Closes the root gap directly; symmetric with an existing Tier 1 pattern; applies universally across ops, code, infra | Text-only rule (passive enforcement); a shallow-thinking model may skip the pre-check; requires self-declaration of sources consulted | Findings 4, 5, 7 |
| **B: Explicit gap-type classification** | Add a mandatory classification step: before invoking AskUserQuestion, the agent must classify the gap as (a) capability gap (genuinely inaccessible — ask is correct) or (b) non-searching gap (accessible but not searched — research first). Wire the Production Access distinction from CLAUDE.md `file:225-228` into the decidability logic | Operationalizes the distinction CLAUDE.md already makes; two-class checklist is simpler than multi-source research; explicitly names both types | Correct classification requires knowing the access inventory; shallow reasoning may misclassify (b) as (a); adds decision overhead | Findings 4, 5, 6, 7 |
| **C: Symmetric Research-First clause** | Add one sentence to the Research-First Policy (CLAUDE.md `file:483`): "Before invoking AskUserQuestion about a fact or system state, use Grep/Read/Glob/AWS read-only BEFORE asking" — exactly mirroring the existing "BEFORE responding" clause | Minimal change; reuses a pattern the agent already follows; Tier 1 injection fires at every prompt | Lowest structural weight — if "BEFORE responding" hasn't prevented all premature stops, "BEFORE asking" text may not either; no gap-type classification logic | Findings 4, 5 |
| **D: Investigate AskUserQuestion hook** | Research whether PreToolUse on `AskUserQuestion` is possible in the current hooks system. If feasible: require a structured "sources consulted" field before the question routes to the engineer — structural enforcement at invocation time | Structural enforcement survives model regression; cannot be bypassed by shallow thinking | Feasibility not confirmed (settings.json review found no AskUserQuestion hook entry); feasibility requires a separate investigation | Finding 4 |
| **E: Status quo** | No config change. Watch Anthropic for restoration of thinking depth | Zero config change; reversible | Config gap predates the regression and will persist independently; provides no protection if degradation continues | Findings 2, 7 |

**Domain counter-rules (NOT root-level options, for contrast only):** "Ops Direct Imperative means proceed," "AWS action-tier classification," "per-skill authorization language" — these were rejected by the engineer (prior session) as symptom-level fixes per domain, not root-level fixes.

---

### Axis 2 options (Ground-Before-Surface gate — external research before option surfacing)

Options F-I address the Axis 2 gap (Finding 8) and the Research-First Policy asymmetry on the option-generation path (Finding 9).

| Option | Approach | Pros | Cons | Sustained by |
|--------|----------|------|------|-------------|
| **F: Extend Research-First to option generation** | Add a clause to Research-First Policy (CLAUDE.md `file:483`): "Before invoking AskUserQuestion with options involving external knowledge (libraries, APIs, patterns, versions, security practices), use WebSearch to ground those options in current evidence BEFORE surfacing them" | Minimal change; closes the precise gap identified at `file:483-493`; symmetric with existing "BEFORE responding" clause; Tier 1 injection ensures it fires at every prompt | CLAUDE.md change requires a PR to dot-claude; text-only (same enforcement risk as Option C for Axis 1); calibration criteria ("involving external knowledge") require judgment | Findings 8, 9 |
| **G: Add "Ground-Before-Ask" clause to ASK-DONT-DECIDE.md** | In the "How to Ask" section (near `file:38-48`): add a requirement that for options involving external knowledge, the agent must run WebSearch and include the search result as the evidence backing each option. Currently `file:38-48` mandates internal evidence (file:line); extend it to include external evidence when appropriate | Keeps the rule in ASK-DONT-DECIDE.md alongside the Axis 1 fix (same document); the "evidence for each option" requirement at `file:43` becomes "internal evidence for codebase options, external evidence for external-knowledge options" | Requires expanding the "How to Ask" section significantly; calibration logic (when to search externally) must be specified; adjacent to the Axis 1 fix, which may make the section hard to read | Findings 8, 9, 10 |
| **H: Include Axis 2 in PR #326** | Expand PR #326's scope to cover both axes — add the Axis 1 gate AND the Axis 2 external-research clause in one PR | One PR, coherent pair of rules; reviewer sees both faces of the same root; single merge event | PR scope grows; CLAUDE.md (Research-First) and ASK-DONT-DECIDE.md are both touched by one PR; if Axis 2 needs iteration, it blocks Axis 1 shipping | Finding 10 |
| **I: Separate PR for Axis 2** | Ship PR #326 with Axis 1 only; open a new feature branch for Axis 2 after PR #326 merges | Smaller PRs, independent review, independent merge; Axis 1 fix ships faster | Engineer has to context-switch twice; ASK-DONT-DECIDE.md touched twice; PR #326 ships an incomplete solution from the two-axis perspective | Finding 10 |

**Calibration — when Axis 2 should NOT fire (trade-off in all Axis 2 options):**

Axis 2 external research adds latency and potentially buries the engineering question under a research report. It should NOT fire for:
- Pure codebase-pattern decisions (inline vs extracted, naming conventions, file placement) — the codebase IS the source of truth; external research adds noise
- Options already constrained by a documented rule (the rule answers the question; WebSearch is redundant)
- Options where the engineer has already framed the alternatives (engineer typed "escolhe entre A e B" — they've done the scoping)
- Decisions where the library or API version is pinned in the project and not subject to upgrade (e.g., Ruby version in `.ruby-version` is the constraint, not community best practice)

It SHOULD fire for:
- Library/gem/npm package selection (version, alternative libs available today)
- Security practice selection (auth patterns, encryption choices, token formats)
- API design patterns (REST vs GraphQL vs webhook vs polling — community consensus evolves)
- Infrastructure pattern choices (event queue type, storage backend, cache strategy)
- Any option where "current best practice as of [training cutoff]" is the knowledge source

The calibration criterion for all Axis 2 options: **does the option involve knowledge with training-cutoff risk?** If yes, WebSearch before surfacing. If no, internal evidence is sufficient.

---

### PR scoping question (engineer decision)

This is not an option with a trade-off table — it is a binary engineer decision that determines sequencing:

**Context:** PR #326 is currently open. It adds the Axis 1 "Exhaust-Before-Ask gate" to ASK-DONT-DECIDE.md. The Axis 2 fix touches either ASK-DONT-DECIDE.md (Option G) or CLAUDE.md Research-First Policy (Option F), or both.

**Option H (same PR):**
- ASK-DONT-DECIDE.md is touched once for both axes → clean doc history
- Reviewer sees the complete two-axis picture → informed review
- Risk: if Axis 2 design needs iteration (calibration criteria, exact language), it blocks Axis 1 from merging

**Option I (separate PR):**
- PR #326 ships Axis 1 now, independently reviewable
- Axis 2 ships in a follow-up PR after validation of Axis 1 in practice
- Risk: ASK-DONT-DECIDE.md is edited twice (two PRs targeting the same file); interim state of the doc is incomplete

Neither option is technically superior — the choice depends on whether the engineer wants to iterate on Axis 2 language before shipping, or whether both axes are ready to ship together.

---

## What remains uncertain

- Whether `AskUserQuestion` is hookable via PreToolUse in the current Claude Code hooks system — feasibility investigation is the prerequisite for Option D (Axis 1 structural enforcement)
- Whether Anthropic's `redact-thinking-2026-02-12` has been reverted or improved since the March 2026 regression data in GitHub #42796
- Whether adding an Exhaust-Before-Ask gate (Options A or B) or a Ground-Before-Surface gate (Options F or G) would survive a degraded-thinking model — the regression makes research the expensive skipped step, so a text rule requiring research may face the same skip
- The NN/g Group citation at ASK-DONT-DECIDE.md `file:101` is UNVERIFIED — fetching the Shane Chang article cited as the source did NOT surface "NN/g" or "NN/g Group" in the fetched content (see `agent-investigates-but-does-not-execute_doc_3.txt`)
- The exact calibration criteria for Axis 2: the "training-cutoff risk" heuristic (does this option involve external knowledge?) is the research finding, but the operational definition of what counts as "external knowledge" for this purpose needs engineer validation before writing the rule
- The correct risk classification of the failing instance itself: Was stopping to confirm 3 production EC2 instances a correct Blocker-class caution (high blast radius), or was it over-caution given the unambiguous direct imperative? This is a design decision that depends on 4Shark's production ops risk tolerance

---

## Suggested options for main and the engineer

Findings converge on two parallel gaps — one in the fact/state asking path (Axis 1, structural root in ASK-DONT-DECIDE.md `file:32`), one in the technical option surfacing path (Axis 2, structural root in Research-First Policy `file:483-493` and ASK-DONT-DECIDE.md `file:38-48`). The engineer and main session decide independently on each axis:

**For Axis 1:**
- **Option A (Exhaust-Before-Ask gate)**: most structurally direct fix; mirrors the existing Research-First pattern; applies universally across ops, code, and infra domains without per-domain exceptions
- **Option B (gap-type classification)**: more explicit checklist; operationalizes the distinction CLAUDE.md already makes; better if the access inventory can be documented concisely
- **Option C (symmetric Research-First)**: lowest-friction change; text-only extension of an existing Tier 1 rule; may be sufficient or may need to combine with A or B
- **Option D (hook investigation)**: should run in parallel with whichever text option is chosen; structural enforcement is the only mechanism that survives model regression reliably
- **Option E (monitor)**: valid as a parallel safety check but not a substitute for a config fix given the gap predates the regression

**For Axis 2:**
- **Option F (extend Research-First)**: closes the precise gap at `file:483-493`; minimal change; requires calibration language for "external knowledge options"
- **Option G (add clause to ASK-DONT-DECIDE.md How to Ask)**: keeps both axes in the same document; rewrites the evidence requirement to be source-sensitive; more visible to the agent at the AskUserQuestion invocation moment
- F and G are not mutually exclusive — F injects at session start (Tier 1), G fires at the invocation point; combining both gives the strongest coverage

**PR scoping:**
- **Option H (include Axis 2 in PR #326)**: one coherent two-axis PR; complete picture for reviewer; risk is scope and iteration lock
- **Option I (separate PR after PR #326)**: Axis 1 ships independently; Axis 2 iterated separately; risk is double doc touch and incomplete interim state

No recommendation is made — the engineer decides on axis options and PR scoping independently.
