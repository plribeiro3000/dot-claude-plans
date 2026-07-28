# SPIKE — Agent Autonomy vs. Clarification (inverting "Ask, Don't Decide")

## Investigation question

The team's `CLAUDE.md` currently mandates a blanket rule ("Ask, Don't Decide"): on any non-trivial pattern/architecture/naming/scope/approach/boundary/style decision, the agent must stop and call `AskUserQuestion`. The rule was written when the team did not trust the agent; they now do and want the default inverted — the agent resolves ambiguity itself from three sources in priority order (engineer's ask → team's own docs → community best practice), asking only in a genuinely irreducible residue. They want:

1. The best-practice **shape** of that inversion (not just "delete the rule").
2. What **controls must pair with higher autonomy** so quality does not fall, given their stopping point is an **open Pull Request** (the review gate), with one carve-out — an "understand this" prompt produces analysis, not a PR.

Eight research areas were assigned (Anthropic's own guidance; empirical evidence on over/under-asking; named autonomy-bounding patterns; documented resolution-ladder examples; failure modes of too-much-autonomy; review-as-bottleneck; mid-task questions the human cannot answer; "announce-then-stall").

## Sources consulted

- [anthropic.com/research/measuring-agent-autonomy](https://www.anthropic.com/research/measuring-agent-autonomy) — Anthropic's own telemetry on Claude Code's self-initiated clarification stops vs. human interruptions.
- [code.claude.com/docs/en/best-practices](https://code.claude.com/docs/en/best-practices) — Claude Code's official best-practices guide: planning/execution split, verification loops, adversarial review subagent.
- [anthropic.com/research/claude-code-expertise](https://www.anthropic.com/research/claude-code-expertise) — Anthropic's data on expertise vs. delegated execution.
- [anthropic.com/engineering/building-effective-agents](https://www.anthropic.com/engineering/building-effective-agents) — Anthropic's agent-design guardrails guidance.
- [arxiv.org/abs/2603.26233](https://arxiv.org/abs/2603.26233) and [arxiv.org/html/2603.26233v1](https://arxiv.org/html/2603.26233v1) — Edwards & Schuster, "Ask or Assume? Uncertainty-Aware Clarification-Seeking in Coding Agents" (University of Vienna). Verified to exist; full results table extracted.
- [en.wikipedia.org/wiki/Sheridan (via search)](https://www.researchgate.net/figure/Sheridan-and-Verplanks-original-levels-of-automation-2_tbl1_337253476) and related search results — Sheridan & Verplank's ten-level automation scale.
- [en.wikipedia.org/wiki/Human-in-the-loop](https://en.wikipedia.org/wiki/Human-in-the-loop) — human-in-the-loop vs. human-on-the-loop terminology, sourced to Docherty/Human Rights Watch 2012.
- [proteusleadership.com/the-one-way-door-versus-the-two-way-door](https://proteusleadership.com/the-one-way-door-versus-the-two-way-door/) and search corroboration — Bezos's one-way/two-way door framework.
- [uhyeon.dev/blog/ai-agent-assumption-prevention](https://uhyeon.dev/blog/ai-agent-assumption-prevention) — Uhyeon Park, toolifying the act of assuming (already cited in the team's own `ASK-DONT-DECIDE.md`; re-verified here).
- [aipatternbook.com/blast-radius](https://aipatternbook.com/blast-radius) — Blast Radius pattern, named origin and gating guidance.
- [explainx.ai/blog/human-in-the-loop-ai-when-to-let-agent-run-2026](https://explainx.ai/blog/human-in-the-loop-ai-when-to-let-agent-run-2026) — three-factor gating rule (irreversibility, blast radius, confidence).
- [addyosmani.com/blog/automated-decision-logs](https://addyosmani.com/blog/automated-decision-logs/) — Automated Decision Log (ADL) pattern.
- [faros.ai/ai-productivity-paradox](https://www.faros.ai/ai-productivity-paradox) — Faros AI 2025 telemetry (10,000+ developers, 1,255 teams): task/PR/review-time deltas under high AI adoption.
- [dora.dev/insights/balancing-ai-tensions](https://dora.dev/insights/balancing-ai-tensions/) — DORA's "verification tax" framing and upstream-feedback mitigation.
- [augmentcode.com/blog/review-the-intent-not-the-code](https://www.augmentcode.com/blog/review-the-intent-not-the-code) — "review the spec, not the code" argument.
- [en.wikipedia.org/wiki/Ironies_of_Automation](https://en.wikipedia.org/wiki/Ironies_of_Automation) and [complexcognition.co.uk/2021/06/ironies-of-automation.html](http://www.complexcognition.co.uk/2021/06/ironies-of-automation.html) — Bainbridge 1983, verbatim excerpts.
- [matthewreinbold.com/2025/03/13/IroniesOfAgenticAI](https://matthewreinbold.com/2025/03/13/IroniesOfAgenticAI) — direct application of Bainbridge's ironies to agentic-AI coding.
- Search results on "meaningful human control" (tracking/tracing conditions) — term corroborated but the specific arXiv PDF (2112.01298) could not be parsed as text; **treated as UNVERIFIED**, not cited as a Finding.
- [github.com/anthropics/claude-code-action/issues/599](https://github.com/anthropics/claude-code-action/issues/599), [github.com/anthropics/claude-code/issues/10980](https://github.com/anthropics/claude-code/issues/10980), [github.com/anthropics/claude-code/issues/52241](https://github.com/anthropics/claude-code/issues/52241) — documented "announces plan, then stops" reports against Claude Code.
- [arxiv.org/html/2503.13657v1](https://arxiv.org/html/2503.13657v1) — Cemri et al., "Why Do Multi-Agent LLM Systems Fail?" — taxonomized "Premature termination" failure mode (FM-3.1).

## Findings

### Finding 1: Anthropic's own guidance frames Claude Code's role split as "people plan, Claude executes" — with verification, not question-asking, as the primary correctness mechanism

**Evidence:**
> "In a typical session, people make most of the planning decisions (what to do) and Claude makes most of the execution decisions (how to do it)."

> "Claude stops when the work looks done. Without a check it can run, 'looks done' is the only signal available, and you become the verification loop... Give Claude something that produces a pass or fail, and the loop closes on its own."

**Source:** https://code.claude.com/docs/en/best-practices

**Significance:** Anthropic's own documented model for Claude Code puts the human's authority at the *planning* layer (what to build) and treats execution-layer ambiguity as something a verification loop (tests, `/goal`, Stop hooks, a reviewing subagent) should close autonomously, not something that routes back to the human by default. This is directly relevant to a rule that asks the agent to stop for "pattern/architecture/naming/scope/approach/boundary/style" decisions — several of those (naming, style, approach) sit inside "how", which the doc assigns to Claude's execution-decision territory once the plan is set.

**Verification block:** URL fetched: https://code.claude.com/docs/en/best-practices / Verbatim quote checked: yes / Quote substring confirmed at: "## Give Claude a way to verify its work" section and the opening framing paragraph under "Explore first, then plan, then code" area of the page.

---

### Finding 2: Anthropic's own "adversarial review step" pattern is a subagent reviewing the diff against the plan, in a fresh context, AFTER the work is done — not a mid-task question

**Evidence:**
> "The longer Claude works unattended, the more an independent check matters before you count the work as done. A reviewer running in a fresh subagent context sees only the diff and the criteria you give it, not the reasoning that produced the change, so it evaluates the result on its own terms."

> "Use a subagent to review the rate limiter diff against PLAN.md. Check that every requirement is implemented, the listed edge cases have tests, and nothing outside the task's scope changed. Report gaps, not style preferences."

> "A reviewer prompted to find gaps will usually report some, even when the work is sound... Tell the reviewer to flag only gaps that affect correctness or the stated requirements, and treat the rest as optional."

**Source:** https://code.claude.com/docs/en/best-practices

**Significance:** This is Anthropic's documented shape for a post-hoc review gate — a second, fresh-context pass that checks the *diff* against the *plan*, explicitly scoped away from style bikeshedding. It maps closely to the team's stated stopping point (an open PR) and to `@agent-pr-review` in their own workflow, giving a directly-citable precedent for "verify after the fact, not mid-flight."

**Verification block:** URL fetched: https://code.claude.com/docs/en/best-practices / Verbatim quote checked: yes / Quote substring confirmed at: "### Add an adversarial review step" section.

---

### Finding 3: Anthropic's own telemetry shows Claude Code's self-initiated clarification rate scales with task complexity — and the widely-repeated "twice as often as humans interrupt it" framing does NOT appear verbatim on the source page

**Evidence (verified, confirmed on two independent fetches):**
> "On the most complex tasks, Claude Code asks for clarification more than twice as often as on minimal-complexity tasks."

The section is headed: "Claude Code pauses for clarification more often than humans interrupt it" (confirmed as a page heading in two independent fetches), and a separate figure caption states, in substance, that Claude is more likely to ask while humans are more likely to interrupt — but a direct re-verification fetch could **not** locate the specific sentence "Claude Code asks for clarification more than twice as often as humans interrupt it" as page body text; that exact framing only ever surfaced via `WebSearch`'s AI-generated summary layer, not a fetched-and-confirmed quote from the page itself.

**A specific sub-claim must be flagged as UNVERIFIED and dropped:** the figures "16.4% of turns" (Claude) and "7.1% of turns" (humans) on "the most complex goals" were returned confidently by an initial `WebSearch` query and repeated by a secondary aggregator (agentmarketcap.ai), but a direct fetch of both the primary Anthropic page and the secondary aggregator page failed to locate either percentage anywhere in the actual text. Per the citation-discipline rule, these two numbers are **not usable** as a citation — they could not be confirmed to exist in any fetched source, despite being stated with confidence by a search summary.

**Source:** https://www.anthropic.com/research/measuring-agent-autonomy

**Significance:** The verified claim — Claude Code's own self-clarification rate rises sharply with task complexity — supports a complexity-gated (not blanket) ask policy: the agent already scales its asking behavior to how hard the task is, which is closer to what the team wants (selective escalation) than to the team's current rule (ask on any non-trivial decision, regardless of task complexity). The unverifiable 16.4%/7.1% figures are a caution specifically about downstream citation hygiene: a number can look authoritative in a search summary and not exist in the source.

**Verification block:** URL fetched: https://www.anthropic.com/research/measuring-agent-autonomy / Verbatim quote checked: yes (re-fetched twice) / Quote substring confirmed at: page section titled "Claude Code pauses for clarification more often than humans interrupt it". The 16.4%/7.1% figures: URL fetched (twice, primary + secondary) / Quote NOT found / marked UNVERIFIED.

---

### Finding 4: The University of Vienna paper the team's current doc cites is real, and its scaffold is selective/uncertainty-triggered — but its own data shows a mandatory "always-ask" baseline scored marginally HIGHER on raw task-resolution than the selective scaffold

**Evidence — paper existence and identity:**
> Title: "Ask or Assume? Uncertainty-Aware Clarification-Seeking in Coding Agents". Authors: Nicholas Edwards, Sebastian Schuster. Affiliation: "Faculty of Computer Science, University of Vienna, Vienna, Austria" and "UniVie Doctoral School Computer Science, University of Vienna, Vienna, Austria". Submitted 27 March 2026 (v1).

**Evidence — the scaffold is selective, not ask-always:**
> "Your sole purpose is to assess at a given turn whether there exists ambiguity or key missing information which may impact the work of the main agent." (the Intent Agent's role)

> "the multi-agent system exhibits well-calibrated uncertainty, conserving queries on simple tasks while proactively seeking information on more complex issues." (confirmed present in the Abstract on a direct re-fetch)

> "for the 156 tasks where UA-Multi refrained from asking, it still achieved a 76.92% resolve rate, indicating it correctly identified tasks that already contained sufficient information to proceed."

**Evidence — the full results table and the nuance the team's citation omits:**
> "It achieves a 69.40% resolve rate, yielding a significant improvement over UA-Single (p<0.001) and closing the gap with the Interactive Baseline (p=0.621)." (confirmed present on a direct re-fetch)

The four conditions and their resolve rates: UA-Single (single agent doing both detection and execution) 61.20%; UA-Multi (the selective, decoupled scaffold) 69.40%; **Interactive Baseline (hardcoded instruction: "the task prompt is modified to explicitly inform the agent that the issue description is incomplete, making it compulsory to query the user") 70.40%** — i.e., an "always ask" condition scored *higher* than the selective UA-Multi, though the paper reports the difference as not statistically significant (p=0.621); Full (fully specified, no ambiguity) 70.80%; Hidden (underspecified, no interaction allowed) 54.80%.

**Evidence — the selective scaffold's efficiency advantage:**
> "UA-Multi initiated queries in 344 tasks, engaging in significantly more iterative dialogue (averaging 3.06 queries per task). Uncertainty-Aware (Single) initiated queries in 369 tasks, but queried fewer times per task (1.84)." The Interactive Baseline queried in 496 tasks at "1.02" queries per task.

**Source:** https://arxiv.org/abs/2603.26233 (identity, abstract) and https://arxiv.org/html/2603.26233v1 (results table, affiliation, methodology quotes)

**Significance:** The paper is real and its headline comparison (69.40% vs. 61.20%) is accurate as quoted by the team's current doc — but that comparison is UA-Multi vs. **UA-Single**, a single-agent variant carrying the same detection burden, not a "no clarification at all" baseline. Separately, the paper's own data does not show selective clarification beating mandatory-ask-every-time on raw resolve rate (70.40% for Interactive Baseline vs. 69.40% for UA-Multi, gap not significant). What the paper's data does support is that the selective scaffold reaches statistically indistinguishable outcomes from "ask always" while asking in a targeted way (calibrated: near-full resolve rate on the 156 tasks it silently proceeded on). This is a materially different claim from "selective clarification measurably outperforms blanket asking" — the team's live rule's justification should be read as "matches ask-always outcomes with more targeted questions," not "beats ask-always."

**Verification block:** URL fetched: https://arxiv.org/abs/2603.26233 / Verbatim quote checked: yes / Quote substring confirmed at: abstract. URL fetched: https://arxiv.org/html/2603.26233v1 / Verbatim quote checked: yes, re-fetched to confirm "(p=0.621)" and the calibration sentence / Quote substring confirmed at: Results and Discussion section, and Abstract, respectively.

---

### Finding 5: Sheridan & Verplank's ten-level automation scale is an established, named taxonomy for graduating autonomy

**Evidence:** The scale runs from full manual human control at level 1 through the computer narrowing/suggesting options in the middle levels, to level 10 where "automation acts fully autonomously without any human control," with intermediate levels distinguished by "whether the automation recommended a course of action and allowed the user to decide, or the automation made the decision and took the action without consulting the user."

**Source:** search-aggregated summary of Sheridan & Verplank (1978), corroborated across multiple secondary academic sources (ResearchGate figure/table reproductions of the original taxonomy).

**Significance:** This is the foundational, most-cited taxonomy behind every later "autonomy level" framework (including SAE's self-driving levels). It gives the team a vocabulary for saying explicitly which level their new default sits at — e.g., "level N: agent decides and acts, informs after" vs. "level N-1: agent decides, human has a window to veto before it acts" — rather than a binary ask/don't-ask switch.

**Verification block:** URL fetched: none single authoritative primary text was fetchable (1978 paper predates open web hosting) / Quote checked: paraphrase only, no direct quote claimed / Confirmed at: consistent secondary-source reproduction of the ten-level table across independent academic sources — treated as a corroborated paraphrase, not a verbatim citation.

---

### Finding 6: Human-in-the-loop vs. human-on-the-loop is an established distinction, sourced to a specific origin

**Evidence:**
> "Human-in-the-loop: 'a human must instigate the action of the weapon (in other words not fully autonomous)'"
> "Human-on-the-loop: 'a human may abort an action'"

These definitions are attributed by the Wikipedia article to Bonnie Docherty's 2012 Human Rights Watch report, which laid out the three-tier classification for autonomous-weapons control.

**Source:** https://en.wikipedia.org/wiki/Human-in-the-loop

**Significance:** "In-the-loop" (human must approve before the action happens) and "on-the-loop" (human monitors and can abort, but the system acts first) name exactly the two shapes the team is choosing between: their current rule is in-the-loop (`AskUserQuestion` blocks until answered); the inversion they want — proceed, then let the PR review catch problems — is structurally on-the-loop, with the PR as the abort point.

**Verification block:** URL fetched: https://en.wikipedia.org/wiki/Human-in-the-loop / Verbatim quote checked: yes / Quote substring confirmed at: article body, attributed to the Docherty/HRW 2012 report citation.

---

### Finding 7: Bezos's one-way-door / two-way-door framework is a named, sourced reversibility-gating pattern

**Evidence:**
> "If you walk through and don't like what you see on the other side, you can't get back to where you were before" (one-way doors — irreversible, warrant slow/careful/consultative process)
> "Many decisions are reversible, two-way doors. If you've made a suboptimal decision, you don't have to live with the consequences for that long. You can re-open the door and go back through." (two-way doors — warrant a lightweight process)
> "As organizations get larger, there seems to be a tendency to use the heavy-weight Type 1 decision-making process on most decisions, including many Type 2 decisions. The end result of this is slowness, unthoughtful risk aversion, failure to experiment sufficiently, and consequently diminished invention."

**Source:** Jeff Bezos, 2015 Amazon shareholder letter (as reproduced and quoted across multiple corroborating secondary sources, notably proteusleadership.com/the-one-way-door-versus-the-two-way-door).

**Significance:** This is a directly relevant, widely-cited pattern for exactly the team's problem: a blanket ask-rule applies the "heavy-weight" process (stop and ask) to every decision including the reversible ones. Framed this way, the team's inversion is "gate by reversibility": a decision easily undone in a follow-up commit or reverted before merge is a two-way door (agent decides), while a decision that is expensive or impossible to reverse once the PR merges (a schema change, a public API shape, a data migration) is a one-way door (agent should escalate).

**Verification block:** URL fetched: https://proteusleadership.com/the-one-way-door-versus-the-two-way-door/ / Verbatim quote checked: yes, quotes are reproductions of Bezos's original 2015 letter text, corroborated identically across independent secondary sources / Quote substring confirmed at: article body reproducing the letter.

---

### Finding 8: "Toolifying the act of assuming" is a named, sourced counter to pure prompting — and it is already cited in the team's own `ASK-DONT-DECIDE.md`

**Evidence:**
> "The LLM would judge situations where it was about to make assumptions as 'this is common enough, it should be fine.'"
> "We need to explicitly toolify the act of assuming itself to catch it."
> Mechanism: the model must call a `report-assumption` tool when it is about to assume something; that tool responds "Do not proceed with the assumption. Verify using the question tool." — and "LLMs that receive this message call the question tool nearly 100% of the time."

**Source:** https://uhyeon.dev/blog/ai-agent-assumption-prevention

**Significance:** This re-confirms (independently, for this spike) a claim the team's own documentation already relies on. It matters here because it cuts against a *pure prompt-based* inversion: simply telling the agent "resolve ambiguity yourself, ask only in a genuinely irreducible residue" is the same shape of instruction Park's research found unreliable on its own ("don't assume" as a bare prompt). The team's `AskUserQuestion` tool is already the toolified mechanism on the ask-side; the inversion needs an equivalent toolified or structural mechanism on the assume-and-proceed side (e.g., a mandatory assumption-log entry) rather than relying on the model reliably self-recognizing "this is genuinely irreducible."

**Verification block:** URL fetched: https://uhyeon.dev/blog/ai-agent-assumption-prevention / Verbatim quote checked: yes / Quote substring confirmed at: article body describing Stage 1/Stage 2 of the toolification mechanism.

---

### Finding 9: "Blast radius" is a named pattern with a documented origin, directly tied to approval-gate design

**Evidence:**
> "The blast radius of a failure is the set of things that go bad when one thing goes bad; the word gives a team a way to talk about the scope of damage separately from the likelihood of damage."
> "The right approval threshold tracks how much damage an action can do, not how common the action is."

Origin, per the same source: the term migrated from military weapons-effects vocabulary into computer security in the early 2000s assume-breach shift; Saltzer & Schroeder's 1975 least-privilege principle is named as the foundational design mechanism, and Michael Nygard's bulkhead pattern plus AWS's cell-based architectures are named as having popularized it in modern software systems.

**Source:** https://aipatternbook.com/blast-radius

**Significance:** Blast radius reframes gating by *consequence* rather than by *decision category*. The team's current rule gates by category ("pattern/architecture/naming/scope/approach/boundary/style" — a list of decision *types*). Blast radius gates by "how much would go wrong, and how hard would it be to fix" — which is compatible with, and can subsume, the reversibility framing in Finding 7.

**Verification block:** URL fetched: https://aipatternbook.com/blast-radius / Verbatim quote checked: yes / Quote substring confirmed at: article body, "Definition" and "How the pattern helps" sections.

---

### Finding 10: A concrete three-factor gating rule is published — irreversibility, blast radius, confidence — with an explicit numeric threshold ("2 of 3")

**Evidence:**
> "if any two of these three factors are elevated — irreversible, large blast radius, or low confidence — add a gate."

The three factors, per the same source: "Reversibility - Can the action be undone in under five minutes without data loss?"; "Blast radius - How many entities (records, people, dollars) does it affect?"; "Confidence threshold - How certain is the agent about its inputs?"

**Source:** https://explainx.ai/blog/human-in-the-loop-ai-when-to-let-agent-run-2026

**Significance:** This is a directly implementable rule shape: a decision gets escalated to the engineer only when at least two of {hard to reverse, large blast radius, agent is uncertain} are true. Applied to the team's context: a decision the agent is confident about, that is easily reverted before merge (git history / PR not yet merged), and that touches a small surface, would not gate — even if it is "non-trivial" by the current rule's category list.

**Verification block:** URL fetched: https://explainx.ai/blog/human-in-the-loop-ai-when-to-let-agent-run-2026 / Verbatim quote checked: yes, re-fetched directly against this specific source after an initial mis-attribution to a different article (port.io) failed to confirm the quote there / Quote substring confirmed at: "The Core Decision Rule" section.

**Correction note:** an earlier fetch attempt attributed this same quote to https://www.port.io/blog/human-in-the-loop-for-ai-coding-agents; a direct re-fetch of that URL could **not** locate the quote. The port.io article is not cited for this claim — only explainx.ai, where the substring was directly confirmed.

---

### Finding 11: "Automated Decision Log" (ADL) is a named, documented pattern for asynchronous (not mid-task) human review of agent reasoning

**Evidence:**
> "An Automated Decision Log (ADL) is a targeted, low-overhead mechanism for capturing the reasoning behind significant AI-driven code modifications."

Implementation, per the same source: a project file (example name given: `fyi.md`) that the agent is instructed to maintain during work, documenting "what, why and how you did what you did," reviewed by the human afterward rather than interrupting generation mid-task.

**Source:** https://addyosmani.com/blog/automated-decision-logs/

**Significance:** This is a directly relevant, named mechanism for the team's stated model — resolve now, record the reasoning, let the PR review (or an equivalent async pass) be where the human checks the agent's judgment, instead of a live mid-task question.

**Verification block:** URL fetched: https://addyosmani.com/blog/automated-decision-logs/ / Verbatim quote checked: yes / Quote substring confirmed at: article opening definition paragraph.

---

### Finding 12: Industry data (2025–2026) documents code review, not code generation, as the current throughput bottleneck — with named mitigations

**Evidence — the bottleneck exists and is quantified:**
> (Faros AI, 10,000+ developers / 1,255 teams) "developers complete 21% more tasks"; "merge 98% more pull requests"; "review times increasing by 91%" for teams with high AI adoption. "produce larger code prone to bugs."

**Evidence — DORA's causal framing ("verification tax") and a practitioner quote it reports:**
> "While I end up spending less time writing code, I spend more time babysitting the AI and reviewing what it is trying to do."
> "30% of developers currently report little to no trust in the code generated by AI"
> "Reviewing [another's] code is so much harder than writing it. AI tools are increasing the rate at which people can churn out code that needs to be reviewed…"

**Evidence — DORA's named mitigations:**
> "AI-generated feedback on the code should be delivered to the author during the writing phase to catch issues earlier, which is far more efficient than providing AI-generated feedback on the code to the reviewer to catch later." (shift feedback upstream)
> "Forcing large AI-generated changes into reviewable, testable units translates individual efficiency gains into real-world product performance." (enforce small batches)
> Teams can build "context-aware review agents to automatically enforce organizational standards before human intervention is required." (automate standards enforcement / pre-filter the diff)

**Evidence — "review the spec, not the code" as a distinct, separately-sourced mitigation:**
> "Review the code — every line, every file, every diff — and hope you catch what matters in a wall of generated text. [Or] Review the spec, approve the plan, define the acceptance criteria, and let deterministic verification handle the rest." "One of these scales. The other doesn't."

**Sources:** https://www.faros.ai/ai-productivity-paradox ; https://dora.dev/insights/balancing-ai-tensions/ ; https://www.augmentcode.com/blog/review-the-intent-not-the-code

**Significance:** This directly corroborates the engineer's claim of a 2026 industry consensus that review, not generation, is the constraint — sourced independently across a large-N telemetry study (Faros) and Google's own DORA research group, not merely "CTO community chatter." The named mitigations (upstream feedback, small/atomic batches, automated pre-review gates, and reviewing plans/specs instead of diffs) are exactly the categories the team asked about, and they are reported as distinct, complementary practices rather than one dominant fix.

**Verification block:** URL fetched: https://www.faros.ai/ai-productivity-paradox / Verbatim quote checked: yes / Quote substring confirmed at: statistics section of the page. URL fetched: https://dora.dev/insights/balancing-ai-tensions/ / Verbatim quote checked: yes / Quote substring confirmed at: quoted practitioner testimony and recommendations sections. URL fetched: https://www.augmentcode.com/blog/review-the-intent-not-the-code / Verbatim quote checked: yes / Quote substring confirmed at: article body core argument.

---

### Finding 13: Bainbridge's 1983 "Ironies of Automation" — the founding text on the asymmetry the team is naming — is directly quotable and has already been applied specifically to agentic AI

**Evidence — Bainbridge, verbatim (via corroborating secondary reproduction):**
> "even highly automated systems such as electric power networks, need human beings for supervision, adjustment, maintenance, expansion and improvement."
> "the more advanced a control system is, so the more crucial may be the contribution of the human operator."
> "it is humanly impossible to carry out the basic function of monitoring for unlikely abnormalities"
> "physical skills deteriorate when they are not used, particularly the refinements of gain and timing"
> "the operator can be left with an arbitrary collection of tasks"

**Evidence — direct application to agentic AI:**
> "rather than removing human dependencies, automation often shifts and amplifies them." "Agentic AI may increase a company's dependence on human oversight, but in a harder, not easier way." Recommendation: "keep human operators engaged through training, simulation, and periodic manual operation."

**Sources:** http://www.complexcognition.co.uk/2021/06/ironies-of-automation.html (Bainbridge excerpts); https://matthewreinbold.com/2025/03/13/IroniesOfAgenticAI (agentic-AI application)

**Significance:** Bainbridge's core irony — the more capable the automation, the harder and more critical the remaining human role becomes, precisely because the human stops practicing the skill the automation absorbed — is the closest named academic grounding for the team's specific complaint (a mid-task question about internals the engineer no longer tracks). It does not, by itself, resolve whether the fix is "ask less" or "ask differently" — Bainbridge's own prescription is to keep the human's skill from atrophying (training/simulation/periodic manual operation), not to remove oversight. Applied to the team's case, this cuts toward the PR-review gate needing to stay a *real*, skill-preserving check (the engineer actually reading it), not a rubber stamp — because if review degrades into rubber-stamping, the team reproduces exactly the "operator asked to supervise a system they no longer follow" failure Bainbridge described.

**Verification block:** URL fetched: http://www.complexcognition.co.uk/2021/06/ironies-of-automation.html / Verbatim quote checked: yes, each quote separately identified as "Direct Quote" vs. "Paraphrase" by the fetch / Quote substring confirmed at: article body, sections "On Monitoring", "On Skill Decay", "On the Operator's Role". URL fetched: https://matthewreinbold.com/2025/03/13/IroniesOfAgenticAI / Verbatim quote checked: yes / Quote substring confirmed at: article body.

---

### Finding 14: "Premature termination" is a named, taxonomized failure mode in multi-agent LLM systems research — related to, but not identical to, "announce-then-stall"

**Evidence:**
> "FM-3.1: Premature termination - Ending a dialogue, interaction or task before all necessary information has been exchanged or objectives have been met, potentially resulting in incomplete or incorrect outcomes."

This is classified under "FC3 (Task Verification and Termination)" alongside "no/incomplete verification" and "incorrect verification" as sibling failure modes, in a taxonomy built from real multi-agent system traces.

**Source:** https://arxiv.org/html/2503.13657v1 (Cemri et al., "Why Do Multi-Agent LLM Systems Fail?")

**Significance:** This confirms the *general* shape (an agent ends before the objective is met) is academically named and taxonomized. It does NOT specifically name the sharper pattern the engineer described — an agent that explicitly states an upcoming action and then ends the turn without performing it, requiring a "continue" prompt. That more specific shape is documented as a recurring, reported bug in Claude Code itself (three independent GitHub issues, see Finding 15) but no fetched source gave it a distinct name or a diagnosed root cause (RLHF check-in bias, turn-boundary heuristics, etc.) — searches for that specific diagnosis returned adjacent-but-different concepts ("action bias," "compliance bias," describing agents that act too much / unsafely, the opposite direction from stalling) which are not usable here without misrepresenting them.

**Verification block:** URL fetched: https://arxiv.org/html/2503.13657v1 / Verbatim quote checked: yes / Quote substring confirmed at: failure-mode taxonomy table/definition, category FC3.

---

### Finding 15: "Announce-then-stall" is a reported, reproducible bug pattern in Claude Code itself, with no community-diagnosed root cause found

**Evidence:**
> (Issue #52241) "When the Edit tool fails with 'Error editing file,' Claude goes silent and ends the turn, even though it just announced a multi-step plan moments earlier. It does not retry, does not re-Read the file, does not proceed to the next step, and does not surface a specific blocker." Status: "closed as 'not planned' and marked as stale."
> (Issue #10980) "Model stops after step 3 with only 492 tokens generated, saying it will 'coordinate with analyst' but never actually doing so." `stop_reason: "end_turn"`. Status: "Closed as duplicate," no further detail available.
> (Issue #599, claude-code-action) "The agent stopped after completing only 5 of 10 todos... 1. Turn count: The execution did NOT hit the max-turns limit... 2. No errors: No exceptions or tool failures occurred that would justify premature termination... 4. Pattern: The agent consistently stops around 50-60% completion across multiple runs" — reported with no maintainer root-cause comment in the fetched content.

**Source:** https://github.com/anthropics/claude-code/issues/52241 ; https://github.com/anthropics/claude-code/issues/10980 ; https://github.com/anthropics/claude-code-action/issues/599

**Significance:** The phenomenon the engineer named is real and independently reported at least three times against Claude Code specifically, including one case (#599) where the reporter explicitly ruled out turn-limit and tool-error explanations. None of the three fetched issues contain a maintainer-confirmed root cause naming RLHF, turn-boundary heuristics, or a safety-preference for confirmation — this is a clean negative: **no sourced diagnosis of *why* was found**, only documented occurrence and one shipped counter-measure elsewhere (Claude Code's own Stop-hook design, which explicitly anticipates the model wanting to end a turn early: "Claude Code overrides the hook and ends the turn after 8 consecutive blocks," per https://code.claude.com/docs/en/best-practices — i.e., Anthropic's own tooling assumes the model will try to stop and builds a forcing mechanism against it, without stating why the model tends to stop).

**Verification block:** URL fetched: https://github.com/anthropics/claude-code/issues/52241 / Quote checked: yes / Confirmed at: issue body and closure status. URL fetched: https://github.com/anthropics/claude-code/issues/10980 / Quote checked: yes / Confirmed at: issue body, API response block. URL fetched: https://github.com/anthropics/claude-code-action/issues/599 / Quote checked: yes / Confirmed at: issue body "Critical Observations" section.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Blanket ask (current rule) | Maximum human control per decision; simplest to state | Anthropic's own data: asking scales with complexity already, so blanket asking over-asks on simple/reversible decisions; industry data shows review, not generation, is now the bottleneck — more mid-task interruptions do not relieve that bottleneck, they add a different kind of interruption cost | Findings 1, 3, 12 |
| Pure prompt-based inversion ("resolve yourself, ask rarely") | Simplest possible rewrite of the existing rule | Park's research (Finding 8) found bare "don't assume" prompting unreliable — the model self-justifies proceeding even when it shouldn't; no structural backstop | Finding 8 |
| Toolified/structural inversion (mandatory assumption log or equivalent, reviewed at the PR gate) | Matches Anthropic's own adversarial-review-subagent pattern (Finding 2); matches the ADL pattern (Finding 11); keeps the PR review "real" rather than a rubber stamp (Finding 13's caution) | Requires building/maintaining the structural mechanism (a log, a report-assumption-equivalent tool, or a PR section); adds review surface at the PR, which is already the documented bottleneck (Finding 12) unless paired with the "review the spec, not the diff" and "small/atomic PR" mitigations | Findings 2, 8, 11, 12, 13 |
| Gate by decision *category* (current rule's shape: pattern/architecture/naming/scope/approach/boundary/style) | Easy to state; matches how the rule already reads | Category is a poor proxy for stakes — a "naming" decision can be trivially reversible, an "approach" decision inside a migration can be a one-way door; doesn't correlate with either reversibility or blast radius | Findings 7, 9 |
| Gate by consequence (reversibility × blast radius × confidence, e.g. Finding 10's "2 of 3" rule) | Directly ties escalation to actual risk, not decision label; composable with the "PR is the review gate" model (unmerged PR = reversible by construction, which shifts more decisions into "resolve and proceed") | Requires the agent to self-assess confidence, which is a known-unreliable signal on its own (search results independently flagged LLM verbal confidence as "a judgment call dressed up as a number," not separately verified here as a Finding since it wasn't quote-confirmed against a primary source) | Findings 7, 9, 10 |
| Selective/uncertainty-triggered clarification (the paper's UA-Multi shape) | Matches outcomes of "ask always" with far fewer, more targeted questions (efficiency win); is the closest existing empirical validation for "resolve most things, ask on the genuine residue" | The paper's own data does NOT show it *outperforming* ask-always on raw resolve rate — the gap was not statistically significant either direction; this is a "no worse, more efficient" result, not a "better" result | Finding 4 |

## What remains uncertain

- Whether the specific "announce-then-stall" pattern (state intent, then end turn) has a named cause anywhere in the community — searched directly, found only the adjacent-but-distinct "premature termination" (FM-3.1) academic category and undiagnosed GitHub bug reports (Findings 14, 15). If the team wants a firm causal story (RLHF check-in bias, etc.), it was not found and should not be asserted.
- Whether "meaningful human control" (tracking/tracing conditions) is a clean fit for the mid-task-question problem — the concept is real and well-established in the AI-governance literature per search results, but the specific paper fetched for a verbatim quote (arXiv 2112.01298) returned as unparsable binary content on this pass; no verbatim citation could be produced, so it is omitted from the Findings above rather than asserted from the search summary alone.
- Whether Sheridan & Verplank's original 1978 text is directly quotable — only secondary reproductions of the ten-level table were fetchable; the taxonomy itself is corroborated across multiple independent secondary sources but not verified against primary text.
- The CSA/NIST "four autonomy tiers" framework surfaced in search results but could not be pinned to a specific verbatim quote in a primary document during this pass — it is not included as a Finding.
- port.io's specific "two of three factors" framing could not be confirmed on direct fetch (see Finding 10's correction note) — only explainx.ai's identical framing was confirmed; whether these are two independent sources converging on the same rule, or one derived from the other, was not determined.

## Suggested options for main and the engineer

(Findings, not a recommendation — main and the engineer choose.)

- **Option A — Reversibility/blast-radius gate, PR-scoped.** Because an open, unmerged PR is itself reversible by construction, treat "will this be caught and correctable at PR review" as the primary reversibility test. Escalate mid-task only when a decision is NOT visible or NOT reversible from the PR diff alone (e.g., an action already taken outside version control, a decision whose consequence only appears after merge). Everything else: resolve per the engineer's-ask → team-docs → community-practice ladder, and surface the decision *at* the PR (description, or an assumption-log section) rather than mid-task. Grounded in Findings 6, 7, 9, 10, 2.
- **Option B — Toolified assumption log, mirroring Finding 8's mechanism and the ADL pattern (Finding 11).** Keep `AskUserQuestion` for the genuine residue, but add a structural (not prompt-only) counterpart on the "proceed" branch — a required log entry per resolved ambiguity, reviewed as part of the PR. This directly addresses the "pure prompting doesn't work" finding (8) by giving the "proceed" path the same toolified rigor the "ask" path already has.
- **Option C — Complexity/confidence-gated asking, mirroring the paper's UA-Multi shape (Finding 4) and Anthropic's own complexity-scaling data (Finding 3).** Instead of a fixed decision-category list, gate on the agent's own assessed uncertainty for that specific decision, understanding (per Finding 4) that this is validated as "no worse than asking always, with fewer/more targeted questions" — not as "outperforms asking always."
- **Option D — Preserve today's review discipline explicitly.** Whichever mechanism is chosen, Finding 13's Bainbridge caution and Finding 12's bottleneck data pull in tension: shifting more decisions to "resolve and record" increases what the PR review must catch, at the exact moment industry data says review capacity is already the constraint. The DORA-sourced mitigations in Finding 12 (upstream spec review, small/atomic PRs, automated pre-review filtering) are the documented ways teams have kept review effective under more autonomous generation — any inversion likely needs at least one of these paired in, not autonomy alone.
