# SPIKE — How an Agent Should Surface Complex Plans and Decisions to a Context-less Human

- **Status**: Complete — findings + recommendation ready for engineer decision
- **Date**: 2026-07-10
- **Author**: main session (synthesis of 5 parallel research agents)
- **Trigger**: Engineer frustration — on complex work the agent dumps a 2000-line plan nobody reads, then jumps to over-technical decisions ("Decision A: simple or complex?") with no context. The human cannot review the plan and cannot decide on the question.
- **Question**: Does the community discuss this? Is it converging on a solution? What is that solution?

---

## BLUF (the answer, first)

**Yes. The problem has established names, an agreed root cause, and a convergent solution — across communication theory, HCI research, cognitive science, and the actual behavior of shipping AI coding tools (Cursor 2.1, Kiro, GitHub Spec Kit, Devin, Claude Code).**

The engineer's two proposed options are exactly the two the literature endorses:

1. **"Decide alone based on the community recommendation"** → validated by the *decide-vs-ask-as-expected-value* rule (Horvitz mixed-initiative; Anthropic's own autonomy research). Ask only when the value of resolving the human's true intent outweighs the interruption cost. Tactical, convention-settled decisions should be **decided, not asked**.

2. **"Give better context — but not a wall of text"** → validated by BLUF / Minto / inverted-pyramid (conclusion-first), consequence-based framing (frame by outcome, not mechanism), and the ADR decision-record structure (Context → Options → Decision → Consequences).

And the specific failure the engineer named — **"Decision A: simple or complex?"** — is wrong on every axis the research identifies: it is *mechanism-based* (implementation internals), delivered to a *non-expert in that mechanism*, with *no consequences stated* and *no recommended default*. The confirmed evidence predicts the human literally cannot calibrate on it.

**The core insight**: the wall-of-text and the context-free-question are **the same failure**, not two — both are the *curse of knowledge*: the agent substitutes its own mental state for a model of the human's. The fix is one discipline, applied in two directions.

---

## Root cause — why this happens (cognitive science)

### Curse of knowledge / expert blind spot — the single root cause of BOTH symptoms

Once you know something, you cannot reconstruct not knowing it. Coined by Camerer, Loewenstein & Weber (1989, *Journal of Political Economy*).

- Definition: *"A cognitive bias that occurs when a person who has specialized knowledge assumes that others share in that knowledge."* — [Wikipedia: Curse of knowledge](https://en.wikipedia.org/wiki/Curse_of_knowledge) (CONFIRMED)
- Pinker names it the chief cause of opaque writing: *"It simply doesn't occur to the writer that readers haven't learned their jargon, don't seem to know the intermediate steps that seem to them to be too obvious to mention, and can't visualize a scene currently in the writer's mind's eye."* — [Psychological Science / Pinker](https://www.psychologicalscience.org/observer/the-curse-of-knowledge-pinker-describes-a-key-cause-of-bad-writing) (CONFIRMED)
- Teaching form — expert blind spot: *"the inability to perceive the difficulties that novices will experience as they approach a new domain of knowledge"* (Nathan, Koedinger & Alibali 2001). — [IU CITL](https://blogs.iu.edu/citl/2023/04/10/reflecting-on-expert-blind-spots-to-improve-skills-based-teaching/) (CONFIRMED)

**Both symptoms are this one bias:**
- **Under-explain** (bare technical question) = the agent omits the "too obvious to mention" steps.
- **Over-explain** (wall of text) = the agent knows it knows a lot and dumps all of it, rather than modeling which subset the human needs.

### Why the wall of text specifically damages the decision

- **Cognitive Load Theory** (Sweller): working memory is limited; *extraneous* load — *"unnecessary mental effort that does not contribute directly to learning"* — competes with the load the human needs to actually decide. (PLAUSIBLE — multiple CLT sources, not single-fetch-verified)
- **Coherence principle** (Mayer): *"people learn more deeply from a multimedia message when extraneous material is excluded rather than included"* — supported in 23/23 experimental tests, median effect size 0.86. (PLAUSIBLE — Mayer's commonly-cited figures)
- **Information foraging / scent** (Pirolli & Card): readers do not read walls of text, they *forage* and abandon low-yield text. Scent = *"How promising a potential source of information appears to the user."* Readers *"stop when the rate-of-gain ratio would decrease."* — [NN/g: Information Foraging](https://www.nngroup.com/articles/information-foraging/) (CONFIRMED). **A complete plan still fails if it has poor scent.**

### Why there is no safe default explanation level

- **Expertise reversal effect** (Kalyuga 2007): *"information beneficial to novice learners becomes redundant to those more knowledgeable"* — the level that helps a novice actively *harms* an expert. The agent that defaults to *its own* level guarantees a mismatch. **Fix: calibrate to the recipient, not to yourself.** (PLAUSIBLE)

---

## The solution — what the community converges on

### 1. Lead with the conclusion (BLUF / Minto / inverted pyramid)

Four independent frameworks all put the point at the top:

- **BLUF** (US Army, AR 25-50): *"place the main point of a message at the beginning and then follow it up with the context."* — [Wikipedia: BLUF](https://en.wikipedia.org/wiki/BLUF_(communication)) (CONFIRMED)
- **Minto Pyramid Principle** (McKinsey): answer first, then grouped support, to *"maximise and effectively use the limited time of the audience."* — [Toolshero](https://www.toolshero.com/communication-methods/minto-pyramid-principle/) (CONFIRMED)
- **Inverted pyramid** (journalism): *"Readers can stop reading at any point on the page and still come away with the main point."* — [NN/g](https://www.nngroup.com/articles/inverted-pyramid/) (CONFIRMED)
- **Progressive disclosure** (NN/g): *"Initially, show users only a few of the most important options,"* disclose detail *"only if a user asks for them."* — [NN/g](https://www.nngroup.com/articles/progressive-disclosure/) (CONFIRMED)

**Implication**: decision first, context second and bounded, full plan available on demand (on disk) — not front-loaded.

### 2. Frame the decision by CONSEQUENCE, not MECHANISM (the killer finding)

- Consequence-based explanations *"emphasize the individual impact of consuming a recommended item on the user, which makes the effect of following recommendations clearer,"* and are explicitly aimed at users who *"lack expertise in a specific item domain."* — [Lubos et al., arXiv:2308.16708](https://arxiv.org/abs/2308.16708) (CONFIRMED)

This is the direct fix for "Decision A: simple or complex?" — restate it as *what each option gives and costs*, in domain terms, not implementation terms.

### 3. More explanation ≠ better decisions — explanation raises reliance, not calibration

The strongest confirmed counter-intuitive result in the set. The naive fix ("just explain more") backfires:

- *"Adding explanations to the AI decisions does not appear to reduce the overreliance and some studies suggest that it might even increase it."*
- *"cognitive forcing significantly reduced overreliance compared to the simple explainable AI approaches"* — but users *disliked* the designs that helped most (accuracy/satisfaction trade-off). — [Buçinca, Malaya & Gajos, CSCW 2021](https://www.eecs.harvard.edu/~kgajos/papers/2021/bucinca2021trust.shtml) (CONFIRMED)

**Implication**: dumping mechanism at the human manufactures unearned confidence. The fix is the *right thing at the right altitude*, not *more*.

### 4. Recommend a default + name the cost of deviating (recommendation + escape hatch)

This is precisely the shape the engineer proposed ("community recommends X, my path breaks Y, want mine or the community's?"). Defaults labeled *"recommended"* are powerful and accepted readily; legitimacy requires a **low-cost, transparent escape** so the recommendation informs rather than coerces. (PLAUSIBLE — default-nudge literature, *Behavioural Public Policy*)

### 5. Decide vs ask = expected value under uncertainty (validates "decide alone")

- Horvitz's mixed-initiative principles frame acting-vs-asking as a cost/benefit/uncertainty comparison; dialogue is reserved *"to resolve key uncertainties."* — [Horvitz 1999](https://www.microsoft.com/en-us/research/publication/principles-mixed-initiative-user-interfaces/) (abstract CONFIRMED; principle list PLAUSIBLE)
- Anthropic's own autonomy research: *"On the most complex tasks, Claude Code asks for clarification more than twice as often as on minimal-complexity tasks"* and *"Claude increasingly limits its own autonomy by stopping to consult the human."* — [Anthropic: Measuring agent autonomy](https://www.anthropic.com/research/measuring-agent-autonomy) (CONFIRMED)

**Implication**: question frequency should *scale with uncertainty and stakes*, not be constant. A tactical, convention-settled point is a **decide**, not an **ask**.

### 6. The structured decision artifact — ADR (Context → Options → Decision → Consequences)

The canonical format for handing ONE decision to a reader without context. Michael Nygard's template separates the WHY from the WHAT:

- **Context**: *"What is the issue that we're seeing that is motivating this decision or change?"*
- **Decision**: *"What is the change that we're proposing and/or doing?"*
- **Consequences**: *"What becomes easier or more difficult to do because of this change?"* — [Nygard template](https://github.com/joelparkerhenderson/architecture-decision-record/blob/main/locales/en/templates/decision-record-template-by-michael-nygard/index.md) (CONFIRMED)
- Reader-first ordering: *"put the most important material at the start, and push details to later in the record."* — [Fowler](https://martinfowler.com/bliki/ArchitectureDecisionRecord.html) (CONFIRMED)
- Anti-advocacy: the consequences section must include *"all downstream effects... positive, negative, and neutral... to discourage advocacy writing that hides trade-offs."* (PLAUSIBLE)

This is the exact skeleton of a good decision card: **problem (context) → options with trade-offs → recommendation → what deviating costs**.

### 7. Convergence in the actual tools (this is not theory — it is shipping)

- **GitHub Spec Kit**: gated phases (Specify → Plan → Tasks → Implement); *"Instead of reviewing thousand-line code dumps, you, the developer, review focused changes that solve specific problems."* — [GitHub blog](https://github.blog/ai-and-ml/generative-ai/spec-driven-development-with-ai-get-started-with-a-new-open-source-toolkit/) (CONFIRMED)
- **AWS Kiro**: three artifacts (requirements.md / design.md / tasks.md) with **approval gates as the default** (skipping them is the opt-out "Quick Plan"). — [Kiro docs](https://kiro.dev/docs/specs/) (CONFIRMED)
- **Cursor 2.1**: *"pauses before plan generation and presents 3-5 targeted questions"* with *"concrete options with brief explanations of tradeoffs,"* multiple-choice + skip. Plans are searchable so you can *"instantly jump to any file."* — [digitalapplied](https://www.digitalapplied.com/blog/cursor-2-1-clarifying-questions-plans) (CONFIRMED)
- **Devin 2.0** (Cognition): interactive planning gate — *"You can modify the plan... before letting Devin work autonomously."* — [Cognition](https://cognition.com/blog/devin-2) (CONFIRMED)
- **Claude Code plan mode**: writes plan to a markdown file; community complaint that *"the approval prompt appears before they have had a chance to read the plan."* — [claude-code#28288](https://github.com/anthropics/claude-code/issues/28288) (CONFIRMED)
- **Practitioner "wall of text" complaint, named**: *"you are not carefully reviewing a plan anymore. You are scanning a wall of text and trying to decide whether it is safe to continue."* Diagnosis: *"you and the agent do not yet have shared understanding."* — [Harsh Patel, Medium](https://harshppatel2880.medium.com/ai-coding-works-better-when-you-and-the-agent-have-shared-understanding-4cb1c1293ebb) (CONFIRMED)
- **Practitioner best practice**: *"Ask the questions one at a time"*; *"For each question, provide your recommended answer with reasoning"*; *"If a question can be answered by exploring the codebase, explore the codebase instead."* — [BSWEN](https://docs.bswen.com/blog/2026-04-01-ai-clarifying-questions-codex/) (CONFIRMED)

**Convergent points across independent tools/writers:**
1. Plan = an editable markdown/checklist artifact; review-before-execute gate.
2. Clarifying questions moved *before* the plan.
3. Questions carry *recommended answers / trade-off options*, not open-ended prompts.
4. "One question at a time"; explore the codebase instead of asking when you can.
5. The named failure is *shared understanding*, not plan correctness.

**Open disagreements** (honest): how *much* to ask (Cursor caps at 3-5; BSWEN says "interview relentlessly"); ask-first vs plan-first for large tasks; where the plan is approved (inline vs on-disk). No source quantifies a target plan length beyond "scannable."

---

## Recommendation for 4Shark — a Decision-Surfacing discipline

This is a **refinement of the existing `ASK-DONT-DECIDE` rule**, not a replacement. The research shows that "ask, don't decide" *without a framing discipline* produces exactly this failure: over-technical asks and unreviewable plans. The community answer adds two layers on top of ASK-DONT-DECIDE:

### Layer A — Filter: is this even an ask? (decide-vs-ask)

Classify every decision point:

- **Tactical** — implementation detail, convention/community has a clear answer, low blast radius, resolvable by reading the codebase → **DECIDE. Do not ask.** Note it in one line ("using X per convention Y"). This is `Ground-Before-Surface` + `Exhaust-Before-Ask` already in the rules, plus the decide-vs-ask expected-value rule.
- **Strategic** — materially changes outcome/cost, breaks something, genuine uncertainty, no settled rule → **SURFACE it** (Layer B).

The engineer's option (a) "decide alone based on the community recommendation" *is* the tactical branch. Legitimate and evidence-backed.

### Layer B — Frame: the Decision Card (never a wall of text, never a bare toggle)

When surfacing a strategic decision, use a fixed, small structure (ADR compressed to a live ask):

1. **The problem — 1-2 sentences, in consequence/domain terms, zero jargon.** "Where in the system are we, what breaks, why does this choice exist." (Assume no prior context. Curse-of-knowledge guard.)
2. **The recommended path** — what the community/convention says + one-line why.
3. **The cost of the alternative** — what deviating buys and what it breaks.
4. **The ask** — recommended default vs alternative. One decision. Framed by consequence.

Full plan/detail stays on disk (progressive disclosure) — linked, not pasted.

### Delivery

- Strategic decision → `AskUserQuestion` with **consequence-framed options** (recommended first, labeled), or an **HTML decision card** in `/tmp` when there are trade-off tables/diagrams. Never the 2000-line plan inline; never the bare technical toggle.
- The full plan is the detail-on-demand layer, not the surface.

### Where it would live

- Amend `~/.claude/docs/ASK-DONT-DECIDE.md` (add the decide-vs-ask filter + the consequence-framing requirement), or
- New Tier 1 doc `DECISION-SURFACING.md` referenced from `ASK-DONT-DECIDE.md` and `GROUND-BEFORE-SURFACE.md`.

**This is a design decision for the engineer** — whether to adopt, and as an amendment vs a new doc. That change goes through the normal dot-claude PR workflow (§ Configuration Changes Policy), not a direct `~/.claude/` edit.

---

## Evidence quality note

- **CONFIRMED** (fetched + verbatim-verified): curse of knowledge (Pinker), information foraging (NN/g), all four communication frameworks (BLUF/Minto/inverted-pyramid/progressive-disclosure), consequence-based explanations (arXiv), over-reliance-from-explanation (Buçinca/Gajos), Anthropic autonomy research, ADR (Nygard + Fowler), Spec Kit, Kiro, Cursor 2.1, Devin 2.0, claude-code#28288, the "wall of text" practitioner quote (Harsh Patel), the one-question-at-a-time best practice (BSWEN).
- **PLAUSIBLE** (search-summary, multiply-corroborated, not single-fetch-verified): Cognitive Load Theory, expertise reversal, Mayer's coherence figures (23/23, d=0.86), Horvitz's 12-principle list, default-nudge escape-hatch, Windsurf/Aider/Copilot-Workspace behavior.
- **Genuine gap**: no single canonical named source for "asking someone to decide without giving them the model to decide with" — supported only indirectly (Pinker + information scent). Not load-bearing for the recommendation.

## Auxiliary
Raw per-angle research findings (5 agents) are captured in the conversation transcript; key sources are cited inline above with their verification level.
