# SPIKE — Why the Agent Over-Elicits Decisions It Should Make Itself, and What Enforces the Fix Beyond Prose

## Investigation question

Two composing failures, observed together in one incident (a PR-review triage where the agent offered 5 options for a decision the engineer had no basis to make, because he does not look at code during planning — only at PR review):

- **Failure 1 (the pre-filter)** — the agent asks the engineer to decide when the decision is tactical, reversible, low blast-radius, and has an obvious recommended path. It should decide and let the PR review catch it.
- **Failure 2 (the delivery)** — even when a decision genuinely is strategic and belongs with the engineer, the agent surfaces it as abstract prose describing options, with no code excerpt attached. The engineer cannot decide from text alone; the rule already says to attach ~10-15 lines of code + file:line + flow narrative (`CLAUDE.md` § Output Policy Layer 5; `DECISION-SURFACING.md` Layer B), and that rule did not fire either.

Both rules already exist in prose, injected by hook on every turn (`SessionStart`, `UserPromptSubmit`, `SubagentStart` per `inject-code-pattern-rule.sh`, `inject-output-policy-reminder.sh`). Both failed on the same incident. The question: **why does prose-plus-hook not enforce a judgmental rule, and what mechanism — not more prose — closes the gap for each failure?**

Five sub-questions guided the research: (1) does the literature name this over-elicitation failure mode; (2) is there a formal asymmetry argument for "deciding is better than asking someone who cannot answer"; (3) has anyone solved mechanical enforcement of a judgmental (non-deterministic) rule in an agent; (4) what do frontier coding agents actually do to contain themselves from asking; (5) does a cheap downstream review gate (the PR) change the ask-vs-decide calculus.

## Sources consulted

- `~/.claude/docs/DECISION-SURFACING.md` — read in full; already defines the decide-vs-ask filter (Layer A) and the Decision Card (Layer B), cites Buçinca & Gajos, Pinker, Mayer, NN/g, and tool convergence (Spec Kit, Kiro, Cursor 2.1, ADR)
- `~/.claude/docs/ASK-DONT-DECIDE.md` — read in full; defines the Exhaust-Before-Ask gate, the Vienna 2025 empirical backing, and the progressive-hardening loop
- `~/Projects/4Shark/dot-claude-plans/active/spike/agent-decision-surfacing/SPIKE.md` — read in full; the prior research record. Explicitly logs a genuine gap it did not close: *"no single canonical named source for 'asking someone to decide without giving them the model to decide with'"*
- [arXiv:2604.14624 — Asking What Matters](https://arxiv.org/abs/2604.14624) (Vijayvargiya, Viswanathan, Neubig) — names *task relevance* and *user answerability* as the two properties of effective clarification; ships a trained module (CLARITI) that cuts questions 41% with equal resolution
- [arXiv:2605.07937 — Ask Early, Ask Late, Ask Right](https://arxiv.org/abs/2605.07937) (Gulati, Gupta, Lumer, Sen, Subbiah) — quantifies over-asking (52% of sessions) as a distinct, measured frontier-model failure mode, separate from under-asking
- [arXiv:2606.03135 — Uncertainty-Aware Clarification in LLM Agents with Information Gain](https://arxiv.org/abs/2606.03135) (Deng et al.) — Information Gain Reward: a computed criterion for when NOT to ask (zero/negative expected information gain)
- [arXiv:1805.04655 — Learning to Ask Good Questions (EVPI)](https://arxiv.org/abs/1805.04655) (Rao & Daumé III) — the foundational EVPI framing: *"a good question is one whose expected answer will be useful"*
- [Antigravity Lab — Delegate the Undoable, Guard the Irreversible](https://antigravitylab.net/en/articles/agents/antigravity-agent-reversibility-tiered-autonomy-architecture) — reversibility (one-way vs two-way door) as an autonomy-tiering criterion, orthogonal to who-holds-the-information
- [Swarmia — Five levels of AI coding agent autonomy](https://www.swarmia.com/blog/five-levels-ai-agent-autonomy/) — autonomy matched to task ambiguity, not a fixed level
- [arXiv:2605.11495 — Dynamic Autonomy for Coding Agents Under Local Oversight](https://arxiv.org/html/2605.11495) — a governance-context cost-asymmetry finding that cuts the other way from the engineer's PR-gate argument (see Finding 11)
- [Jannik Zeiser, "Owning Decisions: AI Decision-Support and the Attributability-Gap", *Science and Engineering Ethics* 30(4):27, 2024](https://pmc.ncbi.nlm.nih.gov/articles/PMC11189344/) — names the failure of delegating a decision to a human who cannot meaningfully evaluate it ("rubber-stamping")
- [Snorkel AI — The Self-Critique Paradox](https://snorkel.ai/blog/the-self-critique-paradox-why-ai-verification-fails-where-its-needed-most/) — why a model cannot reliably police its own output when generator and judge share the same blind spots
- [Claude Agent SDK docs — Handle approvals and user input](https://code.claude.com/docs/en/agent-sdk/user-input) — the literal `AskUserQuestion` schema (fetched in full) and the documented custom-tool escape valve
- `~/.claude/settings.json` — grepped for `AskUserQuestion`; zero matches, confirming no hook currently gates this tool

## Findings

### Part I — Failure 1: the pre-filter (deciding when it should ask)

#### Finding 1: Over-asking is a named, measured, current (2026) failure mode — this is not a 4Shark-only complaint

**Evidence:** *"no current frontier model asks within the empirically optimal window, with strategies ranging from over-asking (52% of sessions) to never asking at all"* — [arXiv:2605.07937 abstract](https://arxiv.org/abs/2605.07937).

**Significance:** This directly answers sub-question 1 for the pre-filter side: the community measures and names over-asking as a distinct failure mode, symmetric to (and as damaging as) under-asking, in frontier agents as of 2026. It is not a vague intuition — the paper quantifies it (52% of observed sessions) and shows it produces materially worse outcomes than a well-timed ask. This closes the gap the prior spike (`agent-decision-surfacing/SPIKE.md`) flagged as unresolved.

#### Finding 2: "User answerability" is the literature-named version of the asymmetry the engineer described

**Evidence:** *"effective clarification remains challenging in software engineering tasks as not all missing information is equally valuable, and questions must target information users can realistically provide"* and the paper operationalizes this as one of two reward properties: *"task relevance (which information predicts success) and user answerability (what users can realistically provide)"* — [arXiv:2604.14624 abstract](https://arxiv.org/abs/2604.14624).

**Significance:** This is the closest literature match to the engineer's framing — "he has no basis to decide, he never looked at the code." The paper's second axis, user answerability, is exactly this: a question can be perfectly legitimate in content and still be the wrong question to ask *this* user, because the user cannot realistically supply a useful answer. The 4Shark case is a structural version of this: the engineer's whole working model is "I review at PR, not during planning" — so mid-execution code-shaped questions are, by construction, low-answerability for him, independent of the question's technical merit.

#### Finding 3: Expected Value of Perfect Information (EVPI) gives a formal criterion for "when NOT to ask" — not just a heuristic

**Evidence:** *"a good question is one whose expected answer will be useful"* — [arXiv:1805.04655 abstract](https://arxiv.org/abs/1805.04655), the original EVPI-for-clarification framing (Rao & Daumé III, ACL 2018). The 2026 operationalization: *"when the prior belief over user intent is already highly concentrated... additional clarification often introduces weakly informative or irrelevant context"*, and when the model chooses not to intervene, *"the posterior belief remains identical to the prior, naturally yielding a reward of zero"* — [arXiv:2606.03135, fetched in full](https://arxiv.org/abs/2606.03135).

**Significance:** This gives sub-question 2 a formal backbone beyond intuition: a question's value is the expected reduction in uncertainty about the right action, weighted by whether the answer is actually obtainable. If the human's answer would not change (because they have no informed preference — the 4Shark case) or cannot be obtained usefully, EVPI is at or near zero, and asking is dominated by deciding. This generalizes Finding 2 from a description into a formal decision-theoretic argument the engineer's spike prompt explicitly asked for.

#### Finding 4: Reversibility is a real autonomy criterion but is explicitly a *different* axis than "who holds the information"

**Evidence:** *"the thing that bites first in agent operations is not intelligence — it is whether you can undo the operation afterward"* and *"Two-way-door operations are file edits, branch commits, draft generation, local builds. If they go wrong you revert with git"* — [Antigravity Lab, fetched in full](https://antigravitylab.net/en/articles/agents/antigravity-agent-reversibility-tiered-autonomy-architecture). The same source, checked directly for an information-holder framing, has none: *"The article does not contain explicit statements about delegating decisions based on who holds relevant information or context. It focuses exclusively on reversibility."*

**Significance:** The incident that triggered this spike (a `country.rb` fix decision) is a textbook two-way door — a code change caught by `git revert` and by the PR review the engineer already does. Reversibility alone would already say "decide" here. But reversibility is not the whole story: even a one-way-door decision should not be surfaced as a bare question to someone who structurally cannot answer it (Finding 2) — it should be surfaced with the code/evidence the Decision Card format requires (Part II). The two criteria — reversibility (does this need to go to the human at all) and answerability/evidence (if it does, can this human actually judge it) — are independent and both must hold for a "surface it" decision to be correctly executed.

#### Finding 5 (Part I/II bridge): Delegating a decision the human cannot meaningfully evaluate is a documented failure, not a safeguard

**Evidence:** *"the challenge is to ensure that human contribution is meaningful, and not merely a 'rubber-stamping' of quasi-automated decisions"*, and: *"A human decision-maker may lack crucial information to provide a satisfying explanation and justification of a decision because she relied on a black-box AI system (i.e. she falls short in terms of answerability)"* — [Zeiser, *Science and Engineering Ethics* 30(4):27 (2024)](https://pmc.ncbi.nlm.nih.gov/articles/PMC11189344/), fetched in full.

**Significance:** This is the direct, formal answer to sub-question 2's core claim — that pushing a decision to a human who cannot meaningfully own it is *worse*, not safer, than deciding and recording. The paper's target domain is human oversight of AI decision-support broadly (hiring algorithms, clinical decision support), and the mechanism it names — "attributability-gap" — applies unchanged to the 4Shark incident: the 5-option `AskUserQuestion` prompt asked the engineer to "own" a decision (which `country.rb` fixes to bundle) without giving him the information (the code) that would let his answer reflect his actual judgment rather than a coin flip framed as a choice.

---

### Part II — Failure 2: the delivery (surfacing strategic decisions as abstract text)

#### Finding 6: The `AskUserQuestion` tool schema has literally zero field for evidence, code, or citation

**Evidence:** the full documented schema (fetched from Anthropic's own docs) is: `questions` (array of 1-4), each with `question` (text), `header` (label, max 12 characters), `options` (2-4, each `label` + `description`, optionally `preview` — a markdown/HTML mockup for *visual* comparisons like layout or color scheme), and `multiSelect` (boolean). Quoting the doc directly: *"Each question has a `question` (the text to display), `options` (the choices), and `multiSelect` (whether multiple selections are allowed)"* — [Claude Agent SDK docs, fetched in full](https://code.claude.com/docs/en/agent-sdk/user-input).

**Significance:** This is the concrete, verified root cause of Failure 2. `CLAUDE.md` § Output Policy Layer 5 requires every item for decision to carry a code excerpt + file:line + flow narrative; `DECISION-SURFACING.md` Layer B requires the same in Decision Card form. Neither requirement has a home in the tool the agent actually calls. The `preview` field exists but is scoped by the docs to *visual* mockups (layout/color), not code snippets or citations, and is TypeScript-only, off by default (`previewFormat` unset ⇒ *"Field is absent. Claude does not generate previews"*). Nothing in the schema *requires* — or even offers a natural slot for — the evidence Layer 5 mandates. The prose rule has no structural home to land in.

#### Finding 7: Custom tools are Anthropic's own documented answer to "beyond `AskUserQuestion`'s shape"

**Evidence:** *"Use custom tools when you need to: Collect structured input: build forms, wizards, or multi-step workflows that go beyond `AskUserQuestion`'s multiple-choice format... Implement domain-specific interactions: create tools tailored to your application's needs, like code review interfaces or deployment checklists"* — [Claude Agent SDK docs, fetched in full](https://code.claude.com/docs/en/agent-sdk/user-input). The docs also confirm the general write-gating mechanism: *"a `PreToolUse` hook, which executes before the rest of the flow and can allow, deny, or modify requests"* and, for the specific tool-approval path, `canUseTool` callbacks can `deny` or `suggest alternative` (block-with-guidance) for *any* tool, `AskUserQuestion` included, since the docs explicitly instruct routing on `tool_name == "AskUserQuestion"`.

**Significance:** This is a real, Anthropic-endorsed escape hatch: a schema can be built (or an existing tool call intercepted) that makes a `code_excerpt`/`file_line` field structurally mandatory, so a question without it is rejected before the engineer ever sees it — the same "toolify the constraint" move `ASK-DONT-DECIDE.md` already cites for a different problem (Uhyeon Park's "toolify the act of assuming"). This confirms sub-question 3 has at least one concrete, vendor-documented mechanism candidate: this is not speculative engineering, it is a documented SDK pattern, though one important caveat applies — see "What remains uncertain" on whether the custom-tool path is available inside the Claude Code CLI/app (vs. only inside a bespoke Agent-SDK harness).

#### Finding 8: `~/.claude/settings.json` has zero hooks gating `AskUserQuestion` today

**Evidence:** `grep -n "AskUserQuestion" ~/.claude/settings.json` returned no output.

**Significance:** Confirms the gap is not "the hook exists but is misconfigured" — no PreToolUse/PostToolUse matcher for `AskUserQuestion` exists in the current configuration at all. Every other judgmental-adjacent rule in `CLAUDE.md` that 4Shark considered high-value has, over time, migrated from prose-only to a mechanical hook (`validate-bash-command.sh`, `validate-commit-message.sh`, `inject-commit-policy-reminder.sh`, etc.) — the ask/surfacing pipeline is the one major decision point in the whole contract that has never received this treatment.

---

### Part III — Cross-cutting: why prose-plus-hook does not close either gap

#### Finding 9: The self-critique paradox — the generator and the would-be judge are the same model with the same blind spots

**Evidence:** *"If your reward model (Judge) has the same blind spots as your policy model, self-correction isn't just useless—it's an adversarial attack on your own training data"* and *"when models perform well initially... Critique here is actively harmful"* because *"the model is right, but the critic will hallucinate flaws to justify its existence"* — [Snorkel AI, fetched in full](https://snorkel.ai/blog/the-self-critique-paradox-why-ai-verification-fails-where-its-needed-most/).

**Significance:** 4Shark's current mechanism for both failures is "inject the rule text into context, trust the same generative process to self-apply it before acting." This finding gives a documented reason that specific shape is structurally weak, independent of how well the rule is worded: the same forward pass that decides "should I ask" is asked to also police "should I ask" against the rule, with the identical blind spot in both roles. This is the general version of the well-known 4Shark observation (`CLAUDE.md` § Work Through to the Pull Request) that a hook can inject context but "cannot edit the model's own response text" — Finding 9 explains *why* injected prose specifically fails for judgmental (not deterministic) rules: there is no independent check, only a second pass of the same reasoning that produced the first-pass mistake.

#### Finding 10: 4Shark's own two hard-enforced rules (Bash Single-Line, Git Safety) are exactly the deterministic-shape cases where a hook *does* work — decide-vs-ask is not that shape

**Evidence:** (internal, not external) — `scripts/validate-bash-command.sh` and `scripts/validate-commit-message.sh`, per `CLAUDE.md`, work because the violating shape is a regex-matchable string (`git push --force` against `develop`, a commit subject missing `<type>(<scope>)`). No external source was needed to confirm this — it follows directly from comparing the mechanically-enforced 4Shark rules against the decide-vs-ask rule: "is this decision tactical or strategic" is not a string pattern, it requires judgment about blast radius, reversibility, and precedent that a regex cannot approximate.

**Significance:** This bounds what mechanism can realistically close Failure 1: not a `validate-*.sh`-style deterministic hook (the classify step is genuinely judgmental), but either (a) a structural constraint on the *output* of that judgment (Finding 6-7's schema-enforced evidence field, which IS mechanically checkable — "is there a file:line pattern in this text?" is a regex, even though "was asking the right call?" is not), or (b) a second, independently-prompted pass (a verifier-style check, mirroring `output-verifier`/`policy-verifier`, run at ask-time rather than write-time).

---

### Part IV — Frontier practice and one open tension

#### Finding 11: One directly-relevant counter-finding — a governance-context paper found the opposite cost asymmetry from the one the 4Shark PR-gate argument assumes

**Evidence:** *"In a governance context a missed check-in (un-reviewed API change ships) is costlier than an extra one (two seconds of developer time)"* — [arXiv:2605.11495, fetched in full](https://arxiv.org/html/2605.11495).

**Significance:** This is presented as a genuine tension, not resolved in either direction. The paper's claim is about *governance/safety-critical* actions (an unreviewed API change shipping), where a missed check-in is catastrophic and an extra one is nearly free — the opposite asymmetry from the 4Shark tactical-code-decision case, where the "extra check-in" (a synchronous `AskUserQuestion` the engineer cannot answer) is the costly one (it blocks the flow and produces no signal), and the "missed check-in" (deciding silently) is cheap because the PR review is a real, already-budgeted catch net. Both papers agree the asymmetry should drive the decision; they disagree on which asymmetry applies, because they are describing different action classes (irreversible governance actions vs. reversible code edits with a downstream review gate). The 4Shark case needs to be argued from its own facts (Finding 4's two-way-door analysis + the engineer's stated review-at-PR practice), not imported wholesale from either paper.

#### Finding 12: Frontier autonomy-tiering research ties ask-frequency to task ambiguity/depth, converging with — but not extending — 4Shark's existing filter

**Evidence:** *"It's not a ranking, and higher is not always better... [Level 3+] you can describe 'done' in a sentence or two with no ambiguity, and you trust CI (or human review) to catch mistakes"*, versus lower autonomy when *"the task is ambiguous, requires deep context"* — [Swarmia, fetched in full](https://www.swarmia.com/blog/five-levels-ai-agent-autonomy/).

**Significance:** This corroborates `DECISION-SURFACING.md`'s existing Layer A filter (tactical → decide, strategic → ask) from an independent, current (2026) industry source, and explicitly names "you trust... human review to catch mistakes" as the condition that licenses higher autonomy — the same review-catches-it logic 4Shark already uses for `CLAUDE.md` § Work Through to the Pull Request. It does not, however, add anything on *enforcement*: like `DECISION-SURFACING.md` itself, it is a design principle communicated in prose, with no mechanism cited for making an agent actually comply.

#### Finding 13: Question-budget mechanisms exist as a research pattern, distinct from schema-enforced evidence

**Evidence:** research-prototype descriptions (search-summary level, not independently fetched/verified against a primary source — flagged as such) describe a bounded question count computed from an ambiguity score, with the budget adapting to expected task difficulty.

**Significance:** UNVERIFIED at the citation-discipline standard applied to the rest of this spike (summary-only, no primary quote confirmed) — included only as a named alternative mechanism shape for the options section below, not as a load-bearing finding. Do not treat this as confirmed community practice without a follow-up fetch.

## What is already covered vs the gap

| Layer | Already documented in 4Shark? | Where | The actual gap |
|---|---|---|---|
| Concept: tactical vs strategic filter (Failure 1) | Yes, in full | `DECISION-SURFACING.md` Layer A, `ASK-DONT-DECIDE.md` Exhaust-Before-Ask | No enforcement — it is prose injected by hook, self-applied by the same generative pass that makes the tactical/strategic call (Finding 9) |
| Concept: evidence/code-excerpt required when surfacing (Failure 2) | Yes, in full | `CLAUDE.md` § Output Policy Layer 5 ("Every item for decision must carry: 1. code excerpt... 2. flow narrative... 3. verdict"), `DECISION-SURFACING.md` Layer B (Decision Card) | No structural home — the `AskUserQuestion` schema has no field for it (Finding 6), so there is nothing for a hook to check even if one existed (Finding 8) |
| Asymmetry argument: asking someone who cannot answer is worse than deciding | Was an explicit **open gap** in the prior spike (`agent-decision-surfacing/SPIKE.md`: *"no single canonical named source"*) | — | **Closed by this spike** — "user answerability" (Finding 2), EVPI (Finding 3), and the attributability-gap/rubber-stamping literature (Finding 5) all independently name this |
| Why prose+hook fails specifically for judgmental rules | Not previously documented as a distinct mechanism-level claim | (adjacent: `CLAUDE.md` § Work Through to the Pull Request already names Constitutional-AI safety-bias + RLHF sycophancy as the root cause of the *reflexive pause* bias) | The self-critique paradox (Finding 9) adds the *mechanistic* reason (same model, same blind spots, no independent check) — a different angle from the *motivational* bias 4Shark already cites, and applies to both failures symmetrically |
| A concrete mechanism to enforce either rule | No — zero hooks reference `AskUserQuestion` (Finding 8) | — | This is the real, still-open gap this spike surfaces options for, below |

**The engineer's diagnosis is confirmed by the evidence, not just restated**: the concept layer is fully covered in existing 4Shark docs for both failures. The base-rate bias (asking/abstracting is the cheap, low-effort action; deciding/attaching-evidence is the effortful one) is not neutralized by prose injected into the same context the biased generation happens in — this is what Finding 9 formalizes. Nothing found in this research suggests 4Shark needs a new *concept* doc; everything found points at the *enforcement* layer as the gap.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Custom tool replacing/wrapping `AskUserQuestion` with a mandatory `code_excerpt`/`file_line` field | Schema-enforced — a call missing the field is malformed input, not a policy violation to detect after the fact; directly closes Finding 6-7's gap | Requires building and maintaining a custom tool; documented for the Agent SDK, unconfirmed whether the Claude Code CLI/app (4Shark's actual runtime) exposes an equivalent extension point (see "What remains uncertain") | [Claude Agent SDK docs](https://code.claude.com/docs/en/agent-sdk/user-input) |
| `PreToolUse` hook on `AskUserQuestion` that heuristically checks the question/options text for an evidence marker (file:line pattern, fenced code) and denies otherwise | Fits 4Shark's existing hook pattern exactly (`validate-bash-command.sh` style); no new tool to build; works today inside Claude Code | Heuristic, not schema-level — a determined bad-faith call could fabricate a fake file:line string that passes the regex without being a real citation; mirrors the general limits of every `validate-*.sh` pattern-match hook already in use | Internal reasoning from Finding 8 + 4Shark's existing hook architecture |
| Verifier-style second pass at ask-time (mirrors `output-verifier`/`policy-verifier`, but gating an `AskUserQuestion` call instead of a file write) | Gives an *independent* pass, addressing Finding 9's self-critique-paradox concern more directly than a same-model self-check | Cost: a second model call before every clarifying question; latency; the Subagent Contract's verifiers currently run only after exception-tier file writes, never at ask-time — this would be new scope for that pattern | Finding 9 (Snorkel AI); 4Shark's own Subagent Contract verifier design |
| Question-budget (cap N tactical-shaped asks, computed from an ambiguity signal) | Bounds the failure mode numerically rather than case-by-case; research precedent (Finding 13, UNVERIFIED) | Does not address Failure 2 (evidence) at all; a budget can be gamed by asking N "big" bundled questions instead of fewer good ones; the underlying research citation is unverified at this spike's standard | Finding 13 (unverified — flagged) |
| Harden `CLAUDE.md` § Work Through to the Pull Request to explicitly name code-shaped tactical decisions as in-scope for "decide, let the PR catch it" | No new mechanism to build; extends a rule 4Shark already enforces successfully for the commit/PR reflexive-pause case | Still prose — Finding 9 says prose alone does not survive the self-critique paradox; would need to pair with one of the above, not replace it | Extension of existing `CLAUDE.md` section; Finding 12 (Swarmia autonomy-tiering, converges but does not enforce) |

## What remains uncertain

- **No single term unifies both failures.** "Over-clarification" / "over-asking" (Finding 1) names Failure 1; "rubber-stamping" / attributability-gap (Finding 5) names the delegation problem behind Failure 2. No source found treats "asks when it should decide" and "surfaces without evidence when it does ask" as the same named phenomenon — they are documented as two adjacent problems, not one.
- **The custom-tool mechanism (Finding 7) is documented for the Agent SDK; it is not confirmed whether the Claude Code CLI/native-app runtime (4Shark's actual environment) exposes the same `canUseTool`/custom-tool extension surface, or whether that layer is only reachable by teams building their own harness on the SDK.** This was not resolved by the sources fetched — worth a direct, narrow follow-up (reading Claude Code's own hook/tool-extension docs, not the Agent SDK docs) before committing to Option A below.
- **Whether a schema-enforced evidence field would be populated with genuine content or boilerplate filler was not tested by any source found.** The broader "reward hacking of structured-output requirements" concern is plausible by analogy but was not independently researched or verified for this specific case — flagged, not claimed.
- **The review-at-PR-lowers-the-value-of-synchronous-clarification argument (sub-question 5) has no direct external confirmation.** Search for "asynchronous review vs synchronous clarification" surfaced trunk-based-development literature that, if anything, argues for *faster* synchronous review — a different claim than "downstream review absorbs upstream tactical decisions cheaply." The closest existing support is 4Shark's own `CLAUDE.md` § Work Through to the Pull Request (Constitutional AI safety-bias + RLHF sycophancy as the root cause of reflexive pausing), which the engineer's argument extends by analogy from the commit/PR boundary to the mid-execution tactical-question boundary — this is a plausible generalization, not an independently-sourced external finding.
- **Finding 13 (question budgets) is UNVERIFIED** at the citation standard used for the rest of this document — included for completeness in the options section, should not be treated as confirmed practice without a direct follow-up fetch.

## Suggested options for main and the engineer

- **Option A — Custom decision-surfacing tool with a mandatory evidence field.** Replace (or wrap) `AskUserQuestion` for code-shaped decisions with a tool whose schema requires `code_excerpt` + `file_line` before the call is well-formed. Directly targets Failure 2 at the schema level (Finding 6-7). Needs a preliminary check of whether Claude Code (not just the Agent SDK) supports this extension point.
- **Option B — `PreToolUse` hook on `AskUserQuestion`** that pattern-matches for an evidence marker in the question/options text and denies the call (with a corrective message, mirroring `validate-bash-command.sh`) when absent. Lower engineering cost than Option A, heuristic rather than schema-enforced, buildable today.
- **Option C — Ask-time verifier pass**, extending the Subagent Contract's verifier pattern (`output-verifier`/`policy-verifier`) to run before an `AskUserQuestion` call is allowed through, checking both the tactical-vs-strategic classification (Failure 1) and the evidence requirement (Failure 2) as a genuinely independent second pass — directly answering Finding 9's self-critique-paradox concern, at the cost of added latency and new scope for the verifier pattern.
- **Option D — Question budget**, capping tactical-shaped asks per task/session, forced by a computed ambiguity signal (Finding 13, unverified) — addresses Failure 1's frequency but not Failure 2's evidence gap, and would need to be paired with A, B, or C.
- **Option E — Extend `CLAUDE.md` § Work Through to the Pull Request** to name code-shaped tactical decisions explicitly in scope, reinforcing (not replacing) whichever mechanical option above is chosen — the prose layer that gives the mechanism its "why," per 4Shark's existing pattern of pairing every mechanical hook with a documented rationale.

These are not mutually exclusive — Options A/B/C address the enforcement gap for *how* a decision reaches the engineer (Failure 2 mechanism) and can combine with a classification check for *whether* it should reach the engineer at all (Failure 1, Options C/D). No option is recommended here; the choice of mechanism, and whether to pursue more than one, is the engineer's design decision per `ASK-DONT-DECIDE.md`.
